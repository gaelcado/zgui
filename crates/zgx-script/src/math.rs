//! `ui.math(tex, { display, face })`: a TeX formula laid out as Zeron sets
//! one (zatex, over a bundled OpenType math face), as SVG in ems: a script
//! sizes it to its text (`w`, `h` times the size) and shows it inline as a
//! span's icon on the baseline (`descent`), or as a block. Layout is one
//! pass, so it answers at once; a formula laid out before answers from the
//! cache, so a reply streaming in lays out only its new formulas.
use mlua::{Lua, Table};
use std::{cell::RefCell, collections::HashMap, rc::Rc};
use zatex::bundled::Face;

/// Formulas kept laid out, by face, style and source: enough for every
/// formula in a long conversation.
const KEPT: usize = 2048;
/// Units per em in the SVG: a tenth of a unit is a thousandth of an em.
const UNITS: f32 = 100.;

/// A laid-out formula, in ems: its SVG and box.
pub(crate) struct Formula {
    pub svg: Rc<str>,
    pub width: f32,
    pub height: f32,
    pub ascent: f32,
    pub descent: f32,
}

type Laid = Result<Rc<Formula>, Rc<str>>;
thread_local! {
    static LAID: RefCell<HashMap<(Face, bool, String), Laid>> = RefCell::new(HashMap::new());
}

/// The bundled face by the name Zeron's settings give it.
fn face(name: &str) -> Option<Face> {
    Some(match name {
        "fira" => Face::Fira,
        "stix" => Face::StixTwo,
        "computer_modern" => Face::ComputerModern,
        "libertinus" => Face::Libertinus,
        "pagella" => Face::Pagella,
        "euler" => Face::Euler,
        _ => return None,
    })
}

/// SVG path data, a tenth of a unit at most off.
struct Path(String);
impl Path {
    fn point(&mut self, x: f32, y: f32) {
        use std::fmt::Write;
        let _ = write!(self.0, "{:.1} {:.1}", x * UNITS, y * UNITS);
    }
}
impl zatex::PathSink for Path {
    fn move_to(&mut self, x: f32, y: f32) {
        self.0.push('M');
        self.point(x, y);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.0.push('L');
        self.point(x, y);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        self.0.push('Q');
        self.point(x1, y1);
        self.0.push(' ');
        self.point(x, y);
    }
    fn cubic_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        self.0.push('C');
        self.point(x1, y1);
        self.0.push(' ');
        self.point(x2, y2);
        self.0.push(' ');
        self.point(x, y);
    }
    fn close(&mut self) {
        self.0.push('Z');
    }
}

/// `tex` laid out in `face`, in ems, or why it can't be (a command zatex
/// doesn't know, a formula past its bounds).
pub(crate) fn lay_out(tex: &str, display: bool, face: Face) -> Laid {
    let key = (face, display, tex.to_owned());
    if let Some(laid) = LAID.with(|laid| laid.borrow().get(&key).cloned()) {
        return laid;
    }
    let options = if display {
        zatex::Options::display(1.)
    } else {
        zatex::Options::inline(1.)
    };
    let laid = match zatex::bundled::layout(tex, face, &options) {
        Ok(formula) => {
            let mut path = Path(String::new());
            // Glyphs name their font in the bundled table, whichever face
            // set them (`font_at`).
            for item in &formula.items {
                match *item {
                    zatex::Item::Glyph {
                        font,
                        glyph,
                        x,
                        y,
                        size,
                    } => zatex::bundled::font_at(font).outline(glyph, size, x, y, &mut path),
                    zatex::Item::Rule {
                        x,
                        y,
                        width,
                        height,
                    } => {
                        use zatex::PathSink;
                        path.move_to(x, y);
                        path.line_to(x + width, y);
                        path.line_to(x + width, y + height);
                        path.line_to(x, y + height);
                        path.close();
                    }
                }
            }
            let (left, top) = (formula.left * UNITS, -formula.ascent * UNITS);
            let (w, h) = (formula.span() * UNITS, formula.height() * UNITS);
            Ok(Rc::new(Formula {
                svg: format!(
                    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"{left:.1} {top:.1} {w:.1} {h:.1}\"><path d=\"{}\"/></svg>",
                    path.0
                )
                .into(),
                width: formula.span(),
                height: formula.height(),
                ascent: formula.ascent,
                descent: formula.descent,
            }))
        }
        Err(error) => Err(error.to_string().into()),
    };
    LAID.with(|cache| {
        let mut cache = cache.borrow_mut();
        if cache.len() >= KEPT {
            cache.clear();
        }
        cache.insert(key, laid.clone());
    });
    laid
}

/// `ui.math(tex, { display?, face? })`: `{ svg, w, h, ascent, descent }`
/// in ems, or nil and why it can't be set.
pub(crate) fn script(
    lua: &Lua,
    (tex, opts): (String, Option<Table>),
) -> mlua::Result<(Option<Table>, Option<String>)> {
    let (display, face) = match &opts {
        Some(t) => (
            t.get::<Option<bool>>("display")?.unwrap_or(false),
            match t.get::<Option<String>>("face")? {
                Some(name) => self::face(&name).ok_or_else(|| {
                    mlua::Error::runtime(format!(
                        "ui.math: no face {name:?} (fira, stix, computer_modern, libertinus, pagella, euler)"
                    ))
                })?,
                None => Face::Fira,
            },
        ),
        None => (false, Face::Fira),
    };
    match lay_out(&tex, display, face) {
        Ok(formula) => {
            let t = lua.create_table()?;
            t.raw_set("svg", &*formula.svg)?;
            t.raw_set("w", formula.width)?;
            t.raw_set("h", formula.height)?;
            t.raw_set("ascent", formula.ascent)?;
            t.raw_set("descent", formula.descent)?;
            Ok((Some(t), None))
        }
        Err(error) => Ok((None, Some(error.to_string()))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_formula_is_laid_out_once_in_ems() {
        let a = lay_out(r"\frac{a}{b} + x^2", false, Face::Fira).unwrap();
        let b = lay_out(r"\frac{a}{b} + x^2", false, Face::Fira).unwrap();
        assert!(Rc::ptr_eq(&a, &b), "cached");
        assert!(a.width > 1. && a.width < 6., "{}", a.width);
        assert!(a.ascent > 0.5 && a.descent > 0.1);
        assert!((a.height - a.ascent - a.descent).abs() < 1e-4);
        assert!(a.svg.starts_with("<svg") && a.svg.contains("<path d=\"M"));
        // Display style sets the fraction larger.
        let d = lay_out(r"\frac{a}{b} + x^2", true, Face::Fira).unwrap();
        assert!(d.height > a.height);
        // Each face its own.
        let e = lay_out(r"\frac{a}{b} + x^2", false, Face::Euler).unwrap();
        assert_ne!(a.svg, e.svg);
    }

    #[test]
    fn what_zatex_cannot_set_says_why() {
        let Err(error) = lay_out(r"\nosuchcommand{x}", false, Face::Fira) else {
            panic!("set");
        };
        assert!(!error.is_empty());
    }
}
