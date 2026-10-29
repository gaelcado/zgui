//! An editor showing its text otherwise than as written (`set_projector`,
//! `set_chip_look`), and making its own edits (`set_line_edits`,
//! `set_paste_filter`): what shows, and carets, hits and keys following.
use std::{ops::Range, rc::Rc};
use zgx::{
    compose::prelude::*,
    editor_projection::{ChipShown, Face, LineEdits, Projection, Projector, Replacement},
    input::{InputEvent, Key, Modifiers, PointerButton},
    scene::{Color, NodeId, NodeKind},
    widgets::{EditorHandle, Ui},
};

fn descendants(ui: &Ui, root: NodeId) -> Vec<NodeId> {
    let scene = ui.scene.borrow();
    let mut result = vec![root];
    let mut cursor = 0;
    while cursor < result.len() {
        result.extend_from_slice(scene.children(result[cursor]));
        cursor += 1;
    }
    result
}

/// `**word**` in bold, its markers hidden off the active lines.
fn stars() -> Projector {
    Rc::new(|text: &str, active: Range<usize>| {
        let mut p = Projection::default();
        let mut at = 0;
        while let Some(open) = text[at..].find("**").map(|i| at + i) {
            let Some(close) = text[open + 2..].find("**").map(|i| open + 2 + i) else {
                break;
            };
            p.faces.push((
                open..close + 2,
                Face {
                    weight: Some(700),
                    ..Default::default()
                },
            ));
            if !(open <= active.end && close + 2 > active.start) {
                p.replacements.push(Replacement::hidden(open..open + 2));
                p.replacements.push(Replacement::hidden(close..close + 2));
            }
            at = close + 2;
        }
        p
    })
}

fn fixture(text: &str, configure: impl FnOnce(View) -> View) -> (Ui, EditorHandle, NodeId) {
    let mut ui = Ui::new(400., 300.);
    let view = ui.mount(configure(
        text_area("Draft", ui.signal(text.to_owned()))
            .size(300., 160.)
            .p(10.)
            .text_size(10.)
            .line_height(20.),
    ));
    ui.prepare_frame();
    ui.input.focus(&ui.scene, Some(view.node()));
    let editor = ui.focused_editor().unwrap();
    editor.editor.borrow_mut().set_selection(0, 0);
    editor.refresh();
    ui.prepare_frame();
    (ui, editor, view.node())
}

/// The rich text the editor shows, if it shows one.
fn shown(ui: &Ui, root: NodeId) -> Option<zgx::rich_text::RichText> {
    let scene = ui.scene.borrow();
    descendants(ui, root)
        .into_iter()
        .find_map(|n| match scene.kind(n) {
            NodeKind::RichText { text } => Some((**text).clone()),
            _ => None,
        })
}

fn key(ui: &mut Ui, key: Key, shift: bool) {
    let modifiers = Modifiers {
        shift,
        ..Default::default()
    };
    ui.dispatch_with_modifiers(
        InputEvent::KeyDown {
            key,
            modifiers,
            repeat: false,
        },
        modifiers,
    );
    ui.prepare_frame();
}

fn click(ui: &mut Ui, x: f32, y: f32) {
    for event in [
        InputEvent::PointerDown {
            x,
            y,
            button: PointerButton::Primary,
        },
        InputEvent::PointerUp {
            x,
            y,
            button: PointerButton::Primary,
        },
    ] {
        ui.dispatch(event);
    }
    ui.prepare_frame();
}

#[test]
fn markers_hide_off_the_carets_line_and_faces_set_its_runs() {
    let (mut ui, editor, root) = fixture("a **b** c\nnext", |v| v.projector(|| Some(stars())));
    // The caret on the first line: its markers show, "**b**" in bold.
    let rich = shown(&ui, root).expect("a projected text shows its runs");
    assert_eq!(rich.text(), "a **b** c\nnext");
    let bold: Vec<_> = rich
        .runs()
        .iter()
        .filter(|r| r.font.weight == 700)
        .map(|r| r.range.clone())
        .collect();
    assert_eq!(bold, vec![2..7]);
    // On the second line, the first's markers go.
    editor.editor.borrow_mut().set_selection(12, 12);
    editor.refresh();
    ui.prepare_frame();
    let rich = shown(&ui, root).unwrap();
    assert_eq!(rich.text(), "a b c\nnext");
    // A click just after "b" (6 a glyph, from 10 in) lands after its
    // hidden closing markers; and the line shows them again.
    click(&mut ui, 10. + 3. * 6. + 1., 20.);
    assert_eq!(editor.editor.borrow().selection().focus, 7);
    assert_eq!(shown(&ui, root).unwrap().text(), "a **b** c\nnext");
    // The text is as written all along.
    assert_eq!(editor.value().get(), "a **b** c\nnext");
}

#[test]
fn a_chip_shows_its_label_after_its_well_and_steps_whole() {
    let icon = std::sync::Arc::new(
        zgx::svg::SvgData::new(
            &b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1 1'><rect width='1' height='1'/></svg>"[..],
        )
        .unwrap(),
    );
    let fill = Color(10, 132, 255, 40);
    let look_icon = icon.clone();
    let (mut ui, editor, root) = fixture("see @crates/zgx/lib.rs now", move |v| {
        v.chips("@", move || fill).chip_look(move |token| {
            Some(ChipShown {
                label: token.rsplit('/').next().map(str::to_owned),
                icon: Some(look_icon.clone()),
                ..Default::default()
            })
        })
    });
    let rich = shown(&ui, root).unwrap();
    assert!(rich.text().contains("lib.rs") && !rich.text().contains("crates"));
    // Its fill spans the well and the label: wider than "lib.rs" alone.
    let scene = ui.scene.borrow();
    let nodes = descendants(&ui, root);
    let quad = nodes
        .iter()
        .find(|n| matches!(scene.kind(**n), NodeKind::Quad(q) if q.fill == fill))
        .map(|n| scene.bounds(*n))
        .expect("the chip's fill");
    assert!(quad.width >= 20. + 6. * 6., "{quad:?}");
    assert!(
        nodes
            .iter()
            .any(|n| matches!(scene.kind(*n), NodeKind::Svg(_))),
        "its icon in the well"
    );
    drop(scene);
    // A caret steps over it whole, either way.
    editor.editor.borrow_mut().set_selection(4, 4);
    key(&mut ui, Key::ArrowRight, false);
    assert_eq!(editor.editor.borrow().selection().focus, 22);
    key(&mut ui, Key::ArrowLeft, false);
    assert_eq!(editor.editor.borrow().selection().focus, 4);
    // Shift extends over it whole.
    key(&mut ui, Key::ArrowRight, true);
    assert_eq!(editor.copy(), "@crates/zgx/lib.rs");
    // Its end's backspace still takes it whole; the text keeps the path.
    editor.editor.borrow_mut().set_selection(22, 22);
    key(&mut ui, Key::Backspace, false);
    assert_eq!(editor.value().get(), "see  now");
}

#[test]
fn a_word_its_look_calls_plain_is_no_chip() {
    let fill = Color(10, 132, 255, 40);
    let (mut ui, editor, root) = fixture("pay $5 to $pdf now", move |v| {
        v.chips("$", move || fill).chip_look(|token| {
            Some(ChipShown {
                plain: token.as_bytes().get(1).is_some_and(u8::is_ascii_digit),
                ..Default::default()
            })
        })
    });
    // One fill: the skill's, not the amount's.
    let fills = |ui: &Ui| {
        let scene = ui.scene.borrow();
        descendants(ui, root)
            .into_iter()
            .filter(|n| matches!(scene.kind(*n), NodeKind::Quad(q) if q.fill == fill))
            .count()
    };
    assert_eq!(fills(&ui), 1);
    // A backspace after the amount takes one character, not the word.
    editor.editor.borrow_mut().set_selection(6, 6);
    key(&mut ui, Key::Backspace, false);
    assert_eq!(editor.value().get(), "pay $ to $pdf now");
    // After the skill, it takes it whole.
    editor.editor.borrow_mut().set_selection(13, 13);
    key(&mut ui, Key::Backspace, false);
    assert_eq!(editor.value().get(), "pay $ to  now");
}

/// Lines starting "- " go on as a list; Tab indents them by two.
struct Dashes;
impl LineEdits for Dashes {
    fn newline(&self, text: &str, at: usize) -> Option<(Range<usize>, String)> {
        let start = text[..at].rfind('\n').map_or(0, |i| i + 1);
        text[start..]
            .trim_start()
            .starts_with("- ")
            .then(|| (at..at, "\n- ".to_owned()))
    }
    fn indent(
        &self,
        text: &str,
        selection: Range<usize>,
        outdent: bool,
    ) -> Option<(Range<usize>, String, Range<usize>)> {
        let start = text[..selection.start].rfind('\n').map_or(0, |i| i + 1);
        if !text[start..].trim_start().starts_with("- ") {
            return None;
        }
        if outdent {
            text[start..].starts_with("  ").then(|| {
                (
                    start..start + 2,
                    String::new(),
                    selection.start - 2..selection.end - 2,
                )
            })
        } else {
            Some((
                start..start,
                "  ".into(),
                selection.start + 2..selection.end + 2,
            ))
        }
    }
}

#[test]
fn line_edits_continue_and_indent_a_list_in_one_undo_step() {
    let (mut ui, editor, _) = fixture("- a", |v| v.line_edits(Dashes));
    editor.editor.borrow_mut().set_selection(3, 3);
    key(&mut ui, Key::Enter, false);
    assert_eq!(editor.value().get(), "- a\n- ");
    assert_eq!(editor.editor.borrow().selection().focus, 6);
    key(&mut ui, Key::Tab, false);
    assert_eq!(editor.value().get(), "- a\n  - ");
    assert_eq!(editor.editor.borrow().selection().focus, 8);
    key(&mut ui, Key::Tab, true);
    assert_eq!(editor.value().get(), "- a\n- ");
    assert!(editor.editor.borrow_mut().undo());
    assert_eq!(editor.editor.borrow().text(), "- a\n  - ");
    // Off a list, a break is a break.
    editor.editor.borrow_mut().set_text("plain");
    editor.editor.borrow_mut().set_selection(5, 5);
    key(&mut ui, Key::Enter, false);
    assert_eq!(editor.editor.borrow().text(), "plain\n");
}

#[test]
fn a_paste_goes_through_its_filter_as_one_undo_step() {
    let (ui, editor, _) = fixture("ask ", |v| {
        v.paste_filter(|text| (text == "lib.rs").then(|| "@crates/zgx/lib.rs ".to_owned()))
    });
    editor.editor.borrow_mut().set_selection(4, 4);
    editor.paste("lib.rs");
    ui.prepare_frame();
    assert_eq!(editor.value().get(), "ask @crates/zgx/lib.rs ");
    editor.paste("x");
    assert_eq!(editor.value().get(), "ask @crates/zgx/lib.rs x");
    assert!(editor.editor.borrow_mut().undo());
    assert!(editor.editor.borrow_mut().undo());
    assert_eq!(editor.editor.borrow().text(), "ask ");
}

#[test]
fn a_projected_text_says_it_fits_by_what_shows() {
    let mut ui = Ui::new(500., 300.);
    let fits = ui.signal(false);
    ui.mount(
        text_area(
            "Draft",
            ui.signal("@a/very/long/path/to/a/file.rs ".to_owned()),
        )
        .size(400., 160.)
        .p(10.)
        .text_size(10.)
        .text_wrap(false)
        .chips("@", || Color(0, 0, 0, 40))
        .chip_look(|token| {
            Some(ChipShown {
                label: token.rsplit('/').next().map(str::to_owned),
                icon: None,
                ..Default::default()
            })
        })
        .fits(fits.clone(), || 380. - 210.),
    );
    ui.prepare_frame();
    ui.prepare_frame();
    // The path is 31 glyphs (186), more than the 210 of room less the
    // hysteresis takes; its label is far less.
    assert!(fits.get());
}

/// Whether text `label` shows (laid out, on screen, not faded out).
fn showing(ui: &Ui, label: &str) -> bool {
    let scene = ui.scene.borrow();
    scene.paint_items().any(|item| {
        matches!(scene.kind(item.id), NodeKind::Text { text, .. } if &**text == label)
            && item.effects.opacity > 0.
            && scene.visible_bounds(item.id).is_some_and(|b| b.width > 0.)
    })
}

/// A chip's card (`chip_tooltip`): made for the chip under the pointer as
/// it shows, over the chip; gone as the pointer leaves the chip or a key is
/// pressed; moving over the rest of the text makes none.
#[test]
fn a_chips_card_shows_over_it_while_the_pointer_rests_there() {
    let fill = Color(10, 132, 255, 40);
    let asked: Rc<std::cell::RefCell<Vec<String>>> = Rc::default();
    let made = asked.clone();
    let (mut ui, _editor, root) = fixture("see @card now", move |v| {
        v.chips("@", move || fill).chip_tooltip(move |token| {
            made.borrow_mut().push(token.to_owned());
            Some(text(format!("card for {token}")))
        })
    });
    let chip = {
        let scene = ui.scene.borrow();
        descendants(&ui, root)
            .into_iter()
            .find(|n| matches!(scene.kind(*n), NodeKind::Quad(q) if q.fill == fill))
            .map(|n| scene.transformed_bounds(n))
            .expect("the chip's fill")
    };
    let at = |ui: &mut Ui, x: f32| {
        ui.dispatch(InputEvent::PointerMove {
            x,
            y: chip.y + chip.height / 2.,
        });
        ui.prepare_frame();
    };
    // Over the text before it: nothing.
    at(&mut ui, chip.x - 12.);
    assert!(!showing(&ui, "card for @card"));
    assert!(asked.borrow().is_empty(), "nothing made off a chip");
    // Over the chip: its card, made for it, at it.
    at(&mut ui, chip.x + chip.width / 2.);
    assert!(showing(&ui, "card for @card"), "over the chip");
    assert_eq!(*asked.borrow(), ["@card"]);
    let card = {
        let scene = ui.scene.borrow();
        scene
            .paint_items()
            .find(|item| matches!(scene.kind(item.id), NodeKind::Text { text, .. } if text.starts_with("card for")))
            .and_then(|item| scene.visible_bounds(item.id))
            .unwrap()
    };
    // Over it where there is room; at the window's top, under it, 6 off.
    assert!(
        (card.y - (chip.y + chip.height) - 6.).abs() < 1. && (card.x - chip.x).abs() < 1.,
        "{card:?} by {chip:?}"
    );
    // Moving within it makes no other.
    at(&mut ui, chip.x + 2.);
    assert_eq!(asked.borrow().len(), 1);
    // Off it, the card goes; back, it comes; a key sends it away.
    at(&mut ui, chip.x + chip.width + 30.);
    assert!(!showing(&ui, "card for @card"), "gone off the chip");
    at(&mut ui, chip.x + chip.width / 2.);
    assert!(showing(&ui, "card for @card"));
    key(&mut ui, Key::ArrowLeft, false);
    assert!(!showing(&ui, "card for @card"), "a key closes it");
}
