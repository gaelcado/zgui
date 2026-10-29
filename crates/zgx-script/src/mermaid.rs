//! `ui.mermaid(source, colours)`: a Mermaid diagram laid out and drawn as
//! Zeron draws one (mermaid-rs-renderer, Zeron's spacing and colours), as
//! SVG for `ui.svg`. It renders on a thread of its own, one diagram at a
//! time, so a script asks for it from a task (`ui.resource`) and shows the
//! fence's source until it comes; a diagram drawn before answers at once.
use crate::{
    calls::{PromiseUd, pending, settle_with},
    value::Value,
};
use mlua::{Lua, Table};
use std::{collections::HashMap, rc::Rc, sync::Mutex};

/// Past these a diagram stays source (Zeron's preview limits).
const MAX_SOURCE_BYTES: usize = 16 * 1024;
const MAX_LINES: usize = 256;
const MAX_TOKENS: usize = 2048;
const MAX_SVG_BYTES: usize = 2 * 1024 * 1024;
/// Diagrams kept drawn, by source and colours.
const KEPT: usize = 64;

/// The renderer has no cancellation: one diagram at a time.
static RENDER_LOCK: Mutex<()> = Mutex::new(());
type Drawn = Result<(String, f32, f32), String>;
static DRAWN: Mutex<Option<HashMap<(String, Palette), Drawn>>> = Mutex::new(None);

/// Zeron's diagram colours (mermaid.rs `Palette::from_theme`), each opaque.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct Palette {
    dark: bool,
    font: String,
    canvas: String,
    node: String,
    group: String,
    text: String,
    label: String,
    line: String,
    border: String,
    grid: String,
    accent_line: String,
    accent_wash: String,
}

type Rgba = [f32; 4];
fn parse(hex: &str) -> Option<Rgba> {
    let hex = hex.strip_prefix('#')?;
    let byte = |i: usize| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok();
    let a = match hex.len() {
        6 => 255,
        8 => byte(6)?,
        _ => return None,
    };
    Some([
        f32::from(byte(0)?) / 255.,
        f32::from(byte(2)?) / 255.,
        f32::from(byte(4)?) / 255.,
        f32::from(a) / 255.,
    ])
}
/// `color` at `alpha` (times its own) over the opaque `under`.
fn over(color: Rgba, alpha: f32, under: Rgba) -> Rgba {
    let a = color[3] * alpha;
    [
        color[0] * a + under[0] * (1. - a),
        color[1] * a + under[1] * (1. - a),
        color[2] * a + under[2] * (1. - a),
        1.,
    ]
}
fn hex(c: Rgba) -> String {
    let b = |v: f32| (v.clamp(0., 1.) * 255.).round() as u8;
    format!("#{:02x}{:02x}{:02x}", b(c[0]), b(c[1]), b(c[2]))
}

impl Palette {
    /// From the theme's roles as a script reads them (`ui.theme.get`):
    /// `bg`, `text`, `muted`, `faint`, `border`, `strong`, `accent`, `dark`
    /// and `font`.
    fn from_table(t: &Table) -> mlua::Result<Self> {
        let color = |name: &str, fallback: Rgba| -> mlua::Result<Rgba> {
            Ok(t.get::<Option<String>>(name)?
                .and_then(|h| parse(&h))
                .unwrap_or(fallback))
        };
        let dark = t.get::<Option<bool>>("dark")?.unwrap_or(true);
        let (white, black) = ([1., 1., 1., 1.], [0., 0., 0., 1.]);
        let bg = over(color("bg", if dark { black } else { white })?, 1., black);
        let ink = if dark { white } else { black };
        let text = color("text", if dark { white } else { black })?;
        let canvas = over(ink, 0.035, bg);
        let node = if dark { over(ink, 0.06, canvas) } else { bg };
        let accent = color("accent", text)?;
        Ok(Self {
            dark,
            font: t
                .get::<Option<String>>("font")?
                .unwrap_or_else(|| "sans-serif".into()),
            canvas: hex(canvas),
            node: hex(node),
            group: hex(over(ink, 0.03, canvas)),
            text: hex(over(text, 1., node)),
            label: hex(over(color("muted", text)?, 1., canvas)),
            line: hex(over(color("faint", text)?, 1., canvas)),
            border: hex(over(color("strong", text)?, 1., canvas)),
            grid: hex(over(color("border", text)?, 1., canvas)),
            accent_line: hex(over(accent, 0.6, canvas)),
            accent_wash: hex(over(accent, 0.12, node)),
        })
    }
}

/// Whether `source` is past what a preview draws.
fn too_complex(source: &str) -> bool {
    source.len() > MAX_SOURCE_BYTES
        || source.lines().count() > MAX_LINES
        || source
            .split(|c: char| c.is_whitespace() || matches!(c, ';' | '>' | '{' | '}'))
            .count()
            > MAX_TOKENS
}

/// The diagram's type: the first word after any front matter and comments.
fn diagram_keyword(source: &str) -> Option<&str> {
    let mut lines = source
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .peekable();
    if lines.next_if_eq(&"---").is_some() {
        lines.by_ref().find(|line| *line == "---");
    }
    lines
        .find(|line| !line.starts_with("%%"))
        .and_then(|line| line.split_whitespace().next())
}

/// `source` drawn in `palette`: its SVG and size.
fn render(source: &str, palette: &Palette) -> Drawn {
    if too_complex(source) {
        return Err("Diagram exceeds preview complexity limit".into());
    }
    let _guard = RENDER_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    std::panic::catch_unwind(|| {
        let mut options = mermaid_rs_renderer::RenderOptions {
            theme: if palette.dark {
                mermaid_rs_renderer::Theme::dark()
            } else {
                mermaid_rs_renderer::Theme::modern()
            },
            ..Default::default()
        };
        // Denser than the engine's default: diagrams are fitted to the
        // reading column, and slack spacing shrinks their labels.
        options.layout.node_spacing = 36.0;
        options.layout.rank_spacing = 40.0;
        options.layout.node_padding_x = 18.0;
        options.layout.node_padding_y = 10.0;
        let theme = &mut options.theme;
        theme.font_family = palette.font.clone();
        theme.font_size = 14.0;
        theme.background = palette.canvas.clone();
        theme.primary_color = palette.node.clone();
        theme.primary_text_color = palette.text.clone();
        theme.primary_border_color = palette.border.clone();
        theme.text_color = palette.label.clone();
        theme.line_color = palette.line.clone();
        theme.secondary_color = palette.node.clone();
        theme.tertiary_color = palette.group.clone();
        theme.edge_label_background = palette.canvas.clone();
        theme.cluster_background = palette.group.clone();
        theme.cluster_border = palette.border.clone();
        theme.sequence_actor_fill = palette.node.clone();
        theme.sequence_actor_border = palette.border.clone();
        theme.sequence_actor_line = palette.border.clone();
        theme.sequence_note_fill = palette.accent_wash.clone();
        theme.sequence_note_border = palette.accent_line.clone();
        theme.sequence_activation_fill = palette.accent_wash.clone();
        theme.sequence_activation_border = palette.accent_line.clone();
        if diagram_keyword(source) == Some("gantt") {
            // Gantt derives its bars' hues from this: a grey turns them red.
            theme.primary_border_color = palette.accent_line.clone();
        }
        let svg =
            mermaid_rs_renderer::render_with_options(source, options).map_err(|e| e.to_string())?;
        let svg = restyle(svg, palette);
        if svg.len() > MAX_SVG_BYTES {
            return Err("Diagram output exceeds preview size limit".to_string());
        }
        let (w, h) = size_of(&svg).ok_or("Diagram has no size")?;
        Ok((svg, w, h))
    })
    .unwrap_or_else(|_| Err("Diagram could not be rendered".into()))
}

/// The root's `width` and `height`.
fn size_of(svg: &str) -> Option<(f32, f32)> {
    let root = &svg[svg.find("<svg")?..];
    let root = &root[..root.find('>')?];
    let attr = |name: &str| -> Option<f32> {
        let at = root.find(&format!(" {name}=\""))? + name.len() + 3;
        root[at..].split('"').next()?.parse().ok()
    };
    Some((attr("width")?, attr("height")?))
}

/// Zeron's finishing touches (mermaid.rs `restyle`): a transparent canvas,
/// softer node corners, cards for boxes the engine fills with its
/// background, decisions in the accent and themed Gantt gridlines. Only
/// what still carries the palette's own colours changes, so a diagram's
/// own `style` and `classDef` colours stay.
fn restyle(svg: String, palette: &Palette) -> String {
    let canvas_fill = format!(" fill=\"{}\"", palette.canvas);
    let node_fill = format!(" fill=\"{}\"", palette.node);
    let border_stroke = format!(" stroke=\"{}\"", palette.border);
    let mut out = String::with_capacity(svg.len());
    let mut rest = svg.as_str();
    while let Some(start) = rest.find('<') {
        out.push_str(&rest[..start]);
        rest = &rest[start..];
        let Some(end) = rest.find('>') else { break };
        let tag = &rest[..=end];
        rest = &rest[end + 1..];
        if is_canvas(tag, palette) {
            continue;
        }
        if tag.starts_with("<polygon ") && is_default_diamond(tag, palette) {
            out.push_str(
                &tag.replacen(&node_fill, &format!(" fill=\"{}\"", palette.accent_wash), 1)
                    .replacen(
                        &border_stroke,
                        &format!(" stroke=\"{}\"", palette.accent_line),
                        1,
                    ),
            );
        } else if tag.starts_with("<rect ") {
            let mut tag = tag.replacen(" rx=\"3\" ry=\"3\" ", " rx=\"8\" ry=\"8\" ", 1);
            if tag.contains(&border_stroke) {
                tag = tag.replacen(&canvas_fill, &node_fill, 1);
            }
            out.push_str(&tag);
        } else if tag.starts_with("<line ") {
            out.push_str(&tag.replacen(
                " stroke=\"#E2E8F0\"",
                &format!(" stroke=\"{}\"", palette.grid),
                1,
            ));
        } else {
            out.push_str(tag);
        }
    }
    out.push_str(rest);
    out
}
/// The full-size backdrop the engine paints in the canvas colour.
fn is_canvas(tag: &str, palette: &Palette) -> bool {
    tag.starts_with("<rect ")
        && tag.contains(&format!(" fill=\"{}\"", palette.canvas))
        && !tag.contains(" stroke=")
        && (tag.starts_with("<rect x=\"0\" y=\"0\" ") || tag.contains(" x=\"-"))
}
/// A decision's diamond in the default node colours.
fn is_default_diamond(tag: &str, palette: &Palette) -> bool {
    tag.contains(&format!(" fill=\"{}\"", palette.node))
        && tag.contains(&format!(" stroke=\"{}\"", palette.border))
        && tag
            .split(" points=\"")
            .nth(1)
            .and_then(|p| p.split('"').next())
            .is_some_and(|points| points.split_whitespace().count() == 4)
}

/// `ui.mermaid(source, colours)`: a promise of `{ svg, w, h }`, or of the
/// reason the diagram can't be drawn.
pub(crate) fn script(
    lua: &Lua,
    (source, colours): (String, Option<Table>),
) -> mlua::Result<PromiseUd> {
    let palette = match &colours {
        Some(t) => Palette::from_table(t)?,
        None => Palette::from_table(&lua.create_table()?)?,
    };
    let promise = pending(lua, "ui.mermaid".into())?;
    let key = (source, palette);
    let known = DRAWN
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|drawn| drawn.get(&key).cloned());
    let answer = |drawn: Drawn| -> Result<Value, String> {
        let (svg, w, h) = drawn?;
        Ok(Value::Map(
            vec![
                (Rc::from("svg"), Value::Str(svg.into())),
                (Rc::from("w"), Value::Num(f64::from(w))),
                (Rc::from("h"), Value::Num(f64::from(h))),
            ]
            .into(),
        ))
    };
    if let Some(drawn) = known {
        settle_with(lua, &promise, async move { answer(drawn) })?;
        return Ok(PromiseUd(promise));
    }
    let (tell, mut heard) = zgx::task::latest::<Drawn>();
    std::thread::spawn(move || {
        let drawn = render(&key.0, &key.1);
        let mut kept = DRAWN.lock().unwrap_or_else(|e| e.into_inner());
        let kept = kept.get_or_insert_with(HashMap::new);
        if kept.len() >= KEPT {
            kept.clear();
        }
        kept.insert(key, drawn.clone());
        tell.send(drawn);
    });
    settle_with(lua, &promise, async move {
        match heard.recv().await {
            Some(drawn) => answer(drawn),
            None => Err("the diagram thread stopped".into()),
        }
    })?;
    Ok(PromiseUd(promise))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn palette() -> Palette {
        Palette {
            dark: true,
            font: "Geist".into(),
            canvas: "#0f0f0f".into(),
            node: "#1e1e1e".into(),
            group: "#151515".into(),
            text: "#e8e8ea".into(),
            label: "#a9a9ae".into(),
            line: "#85858a".into(),
            border: "#3a3a3a".into(),
            grid: "#262626".into(),
            accent_line: "#5f55a3".into(),
            accent_wash: "#2a2740".into(),
        }
    }

    #[test]
    fn a_flowchart_draws_in_zerons_colours_on_no_backdrop() {
        let (svg, w, h) = render(
            "graph TD\n  A[Start] --> B{Ready?}\n  B -->|Yes| C[Ship]\n",
            &palette(),
        )
        .unwrap();
        assert!(w > 50. && h > 50., "{w}×{h}");
        assert!(
            svg.contains(">Start<") && svg.contains(">Ship<"),
            "its labels"
        );
        assert!(
            !svg.contains("fill=\"#0f0f0f\""),
            "no backdrop: it sits on the fence"
        );
        assert!(svg.contains("rx=\"8\""), "softer corners");
        assert!(svg.contains("#2a2740"), "the decision in the accent");
    }

    #[test]
    fn what_cant_be_drawn_says_why() {
        assert!(
            render("graph TD\n  A -->", &palette()).is_err()
                || render("not a diagram", &palette()).is_err()
        );
        let big = "graph TD\n".to_string() + &"  A --> B\n".repeat(400);
        assert_eq!(
            render(&big, &palette()).unwrap_err(),
            "Diagram exceeds preview complexity limit"
        );
    }

    #[test]
    fn colours_compose_over_the_theme_background() {
        assert_eq!(
            hex(over(parse("#ffffff1a").unwrap(), 1., [0., 0., 0., 1.])),
            "#1a1a1a"
        );
        assert_eq!(
            parse("#8b7cf6"),
            Some([139. / 255., 124. / 255., 246. / 255., 1.])
        );
    }
}
