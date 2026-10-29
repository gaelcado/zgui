//! A numbered editor's gutter as review comments use it: marks in their
//! lines' numbers' place, following their lines through edits; a plate
//! under the pointer; presses on cells told without moving the caret; and
//! a card under a line, kept in view and following the scroll.
use std::{cell::RefCell, rc::Rc, sync::Arc};
use zgx::{
    compose::prelude::*,
    editor_gutter::{GutterLook, GutterMark},
    input::{EventPhase, InputEvent, Key, Modifiers, PointerButton},
    reactive::Signal,
    scene::{Color, NodeId, NodeKind, Rect},
    svg::SvgData,
    widgets::{EditorHandle, Ui},
};

const WELL: Color = Color(10, 20, 30, 255);
const PLATE: Color = Color(200, 10, 10, 255);
const GLYPH: &[u8] = b"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>\
    <rect x='2' y='2' width='12' height='12' fill='#000'/></svg>";

fn look(well: Color) -> GutterLook {
    let glyph = Arc::new(SvgData::new(GLYPH).unwrap());
    GutterLook {
        mark: Some(glyph.clone()),
        mark_color: Color(0, 0, 0, 255),
        mark_fill: well,
        add: Some(glyph),
        add_color: Color(255, 255, 255, 255),
        add_fill: PLATE,
    }
}
fn mark(id: &str, line: usize) -> GutterMark {
    GutterMark {
        id: id.into(),
        line,
    }
}
fn command() -> Modifiers {
    Modifiers {
        meta: cfg!(target_os = "macos"),
        control: !cfg!(target_os = "macos"),
        ..Modifiers::default()
    }
}

/// The presses told: each line, and its mark's id.
type Pressed = Rc<RefCell<Vec<(usize, Option<String>)>>>;
/// What a test drives: the window, its editor, the text, the marks given,
/// what presses and moves told, and the card's line.
struct Gutter {
    ui: Ui,
    editor: EditorHandle,
    value: Signal<String>,
    marks: Signal<Vec<GutterMark>>,
    pressed: Pressed,
    moved: Rc<RefCell<Vec<Vec<GutterMark>>>>,
    card: Signal<Option<usize>>,
    note: Signal<String>,
    escaped: Rc<RefCell<usize>>,
    /// The wells' colour (as a theme's would change).
    well: Signal<Color>,
}

fn gutter(lines: usize) -> Gutter {
    let mut ui = Ui::new(400., 300.);
    let text = (1..=lines)
        .map(|i| format!("line {i}"))
        .collect::<Vec<_>>()
        .join("\n");
    let value = ui.signal(text);
    let marks = ui.signal(vec![mark("c1", 3)]);
    let card = ui.signal(None::<usize>);
    let note = ui.signal(String::new());
    let pressed: Pressed = Rc::default();
    let moved: Rc<RefCell<Vec<Vec<GutterMark>>>> = Rc::default();
    let escaped: Rc<RefCell<usize>> = Rc::default();
    let well = ui.signal(WELL);
    let view = {
        let (marks, card, pressed, moved, escaped, well) = (
            marks.clone(),
            card.clone(),
            pressed.clone(),
            moved.clone(),
            escaped.clone(),
            well.clone(),
        );
        let card_view = div()
            .h(60.)
            .child(text_area("Note", note.clone()).w(200.).h(40.))
            .on_event(move |cx| {
                if cx.phase == EventPhase::Bubble
                    && matches!(
                        cx.event,
                        InputEvent::KeyDown {
                            key: Key::Escape,
                            ..
                        }
                    )
                {
                    *escaped.borrow_mut() += 1;
                }
            });
        text_area("Code", value.clone())
            .w(300.)
            .h(200.)
            .text_size(10.)
            .line_height(20.)
            .line_numbers(true)
            .gutter_marks(move || marks.get())
            .gutter_look(move || look(well.get()))
            .on_gutter_press(move |line, id| {
                pressed.borrow_mut().push((line, id.map(str::to_owned)));
            })
            .on_gutter_move(move |marks| moved.borrow_mut().push(marks.to_vec()))
            .gutter_card(card_view, move || card.get())
    };
    let mounted = ui.mount(view);
    ui.prepare_frame();
    let mut pending = vec![mounted.node()];
    let mut found = None;
    while let Some(id) = pending.pop() {
        if ui.editor(id).is_some() {
            found = Some(id);
            break;
        }
        pending.extend(ui.scene.borrow().children(id).iter().copied());
    }
    let editor = ui.editor(found.unwrap()).unwrap();
    ui.prepare_frame();
    Gutter {
        ui,
        editor,
        value,
        marks,
        pressed,
        moved,
        card,
        note,
        escaped,
        well,
    }
}

impl Gutter {
    /// Every node under the editor, with what it is.
    fn nodes(&self) -> Vec<(NodeId, NodeKind)> {
        let scene = self.ui.scene.borrow();
        let mut out = Vec::new();
        let mut pending = vec![self.editor.node];
        while let Some(id) = pending.pop() {
            out.push((id, scene.kind(id).clone()));
            pending.extend(scene.children(id).iter().copied());
        }
        out
    }
    /// The wells drawn, by their tops in the window.
    fn wells(&self) -> Vec<f32> {
        let scene = self.ui.scene.borrow();
        let mut tops: Vec<f32> = self
            .nodes()
            .into_iter()
            .filter(|(_, kind)| matches!(kind, NodeKind::Rect(c) if *c == WELL))
            .map(|(id, _)| scene.transformed_bounds(id).y)
            .collect();
        tops.sort_by(f32::total_cmp);
        tops
    }
    /// Whether line `n`'s number shows.
    fn number_shows(&self, n: usize) -> bool {
        let scene = self.ui.scene.borrow();
        let label = n.to_string();
        self.nodes().into_iter().any(|(id, kind)| {
            matches!(kind, NodeKind::Text { text, .. } if *text == *label)
                && scene.effects(id).opacity > 0.
        })
    }
    /// Where the plate is, while it shows.
    fn plate(&self) -> Option<Rect> {
        let scene = self.ui.scene.borrow();
        self.nodes()
            .into_iter()
            .find(|(_, kind)| matches!(kind, NodeKind::Quad(q) if q.fill == PLATE))
            .map(|(id, _)| id)
            .filter(|id| scene.effects(*id).opacity > 0.)
            .map(|id| scene.transformed_bounds(id))
    }
    fn cell(&self, line: usize) -> Rect {
        self.editor
            .gutter_cell(line)
            .unwrap_or_else(|| panic!("line {line}'s cell is not in view"))
    }
    fn move_to(&mut self, x: f32, y: f32) {
        self.ui.dispatch(InputEvent::PointerMove { x, y });
        self.ui.prepare_frame();
    }
    fn click(&mut self, x: f32, y: f32) {
        let button = PointerButton::Primary;
        self.ui.dispatch(InputEvent::PointerDown { x, y, button });
        self.ui.dispatch(InputEvent::PointerUp { x, y, button });
        self.ui.prepare_frame();
    }
    fn click_cell(&mut self, line: usize) {
        let at = self.cell(line);
        self.click(at.x + at.width / 2., at.y + at.height / 2.);
    }
    fn press(&mut self, key: Key, modifiers: Modifiers) {
        self.ui.dispatch(InputEvent::KeyDown {
            key: key.clone(),
            modifiers,
            repeat: false,
        });
        self.ui.dispatch(InputEvent::KeyUp { key, modifiers });
        self.ui.prepare_frame();
    }
    /// The card's box, while it shows.
    fn card(&self) -> Option<Rect> {
        let scene = self.ui.scene.borrow();
        let note = self.note_editor()?;
        let card = scene.parent(scene.parent(note)?)?;
        scene
            .layout_visible(card)
            .then(|| scene.transformed_bounds(card))
    }
    /// The card's text area.
    fn note_editor(&self) -> Option<NodeId> {
        self.nodes()
            .into_iter()
            .map(|(id, _)| id)
            .find(|id| *id != self.editor.node && self.ui.editor(*id).is_some())
    }
}

#[test]
fn marks_show_in_their_lines_numbers_place_and_presses_on_cells_are_told() {
    let mut g = gutter(30);
    // Line 3 shows its mark's well, not its number; the rest their numbers.
    assert_eq!(g.wells(), [g.cell(3).y]);
    assert!(!g.number_shows(3));
    assert!(g.number_shows(2) && g.number_shows(4));
    // Its colours follow what its look reads (a theme's tokens).
    g.well.set(Color(1, 2, 3, 255));
    g.ui.prepare_frame();
    assert!(g.wells().is_empty());
    g.well.set(WELL);
    g.ui.prepare_frame();
    assert_eq!(g.wells(), [g.cell(3).y]);
    // Assistive technology finds each cell a button.
    {
        let semantics = g.ui.semantics.borrow();
        let names: Vec<String> = g
            .nodes()
            .into_iter()
            .filter_map(|(id, _)| semantics.get(id).map(|n| n.label.clone()))
            .collect();
        assert!(
            names.contains(&"Open comment on line 3".to_string()),
            "{names:?}"
        );
        assert!(
            names.contains(&"Comment on line 4".to_string()),
            "{names:?}"
        );
    }

    // The plate shows on the hovered line's cell, in its number's place.
    let five = g.cell(5);
    g.move_to(five.x + 2., five.y + 3.);
    let plate = g.plate().expect("the plate on line 5");
    assert_eq!((plate.width, plate.height), (16., 16.));
    assert!(plate.y >= five.y && plate.y + 16. <= five.y + five.height);
    assert!(!g.number_shows(5));
    // Not on a marked line; gone over the text, and as the pointer leaves.
    let three = g.cell(3);
    g.move_to(three.x + 2., three.y + 3.);
    assert!(g.plate().is_none());
    assert!(!g.number_shows(3));
    g.move_to(five.x + 2., five.y + 3.);
    assert!(g.plate().is_some());
    g.move_to(five.x + 100., five.y + 3.);
    assert!(g.plate().is_none());
    assert!(g.number_shows(5));
    g.move_to(five.x + 2., five.y + 3.);
    g.move_to(390., 290.);
    assert!(g.plate().is_none());

    // A press on a cell tells its line, and its mark's: no caret placed,
    // no focus taken.
    let before = g.editor.selection();
    g.click_cell(5);
    g.click_cell(3);
    assert_eq!(
        *g.pressed.borrow(),
        [(5, None), (3, Some("c1".to_string()))]
    );
    assert_eq!(g.editor.selection(), before);
    assert_eq!(g.ui.focused_editor().map(|e| e.node), None);
    assert!(g.plate().is_none(), "a press takes the plate away");
    // A press on the text places the caret, as ever.
    let text = g.cell(2);
    g.click(text.x + text.width + 5., text.y + 5.);
    assert_eq!(g.pressed.borrow().len(), 2);
    assert_eq!(g.ui.focused_editor().map(|e| e.node), Some(g.editor.node));
    let line_two = "line 1\n".len().."line 1\nline 2".len();
    assert!(line_two.contains(&g.editor.selection().0));
}

#[test]
fn marks_follow_typing_undo_and_line_breaks_above_them_and_are_told() {
    let mut g = gutter(30);
    g.ui.input.focus(&g.ui.scene, Some(g.editor.node));
    g.editor.set_selection(0, 0);
    g.ui.prepare_frame();
    // A line typed above takes the mark down a line.
    g.ui.dispatch(InputEvent::Text("\n".into()));
    g.ui.prepare_frame();
    assert_eq!(*g.moved.borrow(), [vec![mark("c1", 4)]]);
    assert_eq!(g.wells(), [g.cell(4).y]);
    assert!(g.number_shows(3));
    // Undone, back.
    g.press(Key::Character("z".into()), command());
    assert_eq!(g.value.get().lines().next(), Some("line 1"));
    assert_eq!(g.moved.borrow().last().unwrap(), &vec![mark("c1", 3)]);
    assert_eq!(g.wells(), [g.cell(3).y]);
    // Typing within lines moves none.
    let at = "line 1\nline 2\nli".len();
    g.editor.set_selection(at, at);
    g.ui.dispatch(InputEvent::Text("x".into()));
    g.ui.prepare_frame();
    assert_eq!(g.moved.borrow().len(), 2);
    // A line break typed at the marked line's start takes it down.
    let at = "line 1\nline 2\n".len();
    g.editor.set_selection(at, at);
    g.ui.dispatch(InputEvent::Text("\n".into()));
    g.ui.prepare_frame();
    assert_eq!(g.moved.borrow().last().unwrap(), &vec![mark("c1", 4)]);
    // Given back as told, it stays where it is: nothing told again.
    g.marks.set(vec![mark("c1", 4)]);
    g.ui.prepare_frame();
    assert_eq!(g.moved.borrow().len(), 3);
    assert_eq!(g.editor.gutter_marks(), [mark("c1", 4)]);
    // A new value written to the text moves it too.
    g.value.set(format!("zero\n{}", g.value.get()));
    g.ui.prepare_frame();
    assert_eq!(g.editor.gutter_marks(), [mark("c1", 5)]);
    assert_eq!(g.moved.borrow().last().unwrap(), &vec![mark("c1", 5)]);
    // A line past the text's end is taken up as the text grows to it.
    g.marks.set(vec![mark("c1", 5), mark("late", 40)]);
    g.ui.prepare_frame();
    let more: Vec<String> = (32..=45).map(|i| format!("line {i}")).collect();
    g.value
        .set(format!("{}\n{}", g.value.get(), more.join("\n")));
    g.ui.prepare_frame();
    assert_eq!(g.editor.gutter_marks(), [mark("c1", 5), mark("late", 40)]);
    assert_eq!(g.moved.borrow().len(), 4);
}

#[test]
fn a_long_text_shows_its_marks_in_view_and_follows_them() {
    let mut g = gutter(5_000);
    g.marks.set(vec![mark("a", 2), mark("b", 4_000)]);
    g.ui.prepare_frame();
    assert_eq!(g.wells(), [g.cell(2).y]);
    // Scrolled to line 4,000: its mark there.
    let at = g.value.get().find("line 4000\n").unwrap();
    g.editor.set_selection(at, at);
    g.ui.prepare_frame();
    assert_eq!(g.wells(), [g.cell(4_000).y]);
    assert!(!g.number_shows(4_000));
    g.ui.input.focus(&g.ui.scene, Some(g.editor.node));
    g.editor.set_selection(0, 0);
    g.ui.dispatch(InputEvent::Text("\n\n".into()));
    g.ui.prepare_frame();
    assert_eq!(g.editor.gutter_marks(), [mark("a", 4), mark("b", 4_002)]);
}

#[test]
fn a_wrapped_lines_cell_is_its_first_row() {
    let g = gutter(30);
    g.editor.set_wrap(true);
    let rest = g.value.get().split_off("line 1\nline 2".len());
    g.value.set(format!("line 1\n{}{rest}", "word ".repeat(25)));
    g.ui.prepare_frame();
    let (two, three) = (g.cell(2), g.cell(3));
    assert_eq!(two.height, 20.);
    assert!(three.y - two.y > 40., "line 2 wraps onto rows of its own");
    assert_eq!(g.wells(), [three.y]);
    assert_eq!(g.editor.gutter_marks(), [mark("c1", 3)]);
}

#[test]
fn the_card_sits_under_its_line_in_view_and_follows_the_scroll() {
    let mut g = gutter(30);
    assert!(g.card().is_none(), "no card without a line");
    g.card.set(Some(3));
    g.ui.prepare_frame();
    let card = g.card().expect("the card under line 3");
    let three = g.cell(3);
    let view = g.ui.scene.borrow().transformed_bounds(g.editor.node);
    assert_eq!(card.y, three.y + three.height);
    // Beside the gutter, 8 in: as wide as the view leaves (320 at most).
    let gutter_width = three.width;
    assert_eq!(card.x, three.x + gutter_width - 8.);
    assert_eq!(
        card.width,
        (view.x + view.width - 8. - 8. - card.x).min(320.)
    );
    assert_eq!(card.height, 60.);
    // A view too narrow for it beside the gutter: the view's width, 8 in.
    use zgx::editor_gutter::card_span;
    assert_eq!(card_span(30., 400.), (22., 320.));
    assert_eq!(card_span(30., 200.), (8., 184.));

    // Scrolled: it goes with its line, until the line is out of view.
    let at = (three.x + 50., three.y);
    g.ui.dispatch(InputEvent::Scroll {
        x: at.0,
        y: at.1,
        delta_x: 0.,
        delta_y: 40.,
    });
    g.ui.prepare_frame();
    let one = g.cell(3);
    assert_eq!(one.y, three.y - 40.);
    assert_eq!(g.card().unwrap().y, one.y + one.height);
    g.ui.dispatch(InputEvent::Scroll {
        x: at.0,
        y: at.1,
        delta_x: 0.,
        delta_y: 200.,
    });
    g.ui.prepare_frame();
    assert!(g.editor.gutter_cell(3).is_none());
    assert!(g.card().is_none(), "hidden with its line out of view");

    // Under a line at the view's bottom, held inside the view.
    let last = (1..=30)
        .rev()
        .find(|line| g.editor.gutter_cell(*line).is_some())
        .unwrap();
    g.card.set(Some(last));
    g.ui.prepare_frame();
    let card = g.card().unwrap();
    let bottom = {
        let scene = g.ui.scene.borrow();
        let b = scene.transformed_bounds(g.editor.node);
        b.y + b.height - 6.
    };
    assert_eq!(card.y + card.height, bottom);
    assert!(card.y < g.cell(last).y + g.cell(last).height);

    // It takes its own presses, focus and keys: what is typed in its text
    // area goes there, Enter and Escape too.
    let before = g.value.get();
    let note = g.note_editor().unwrap();
    let at = g.ui.scene.borrow().transformed_bounds(note);
    g.click(at.x + 10., at.y + 10.);
    assert_eq!(g.ui.focused_editor().map(|e| e.node), Some(note));
    g.ui.dispatch(InputEvent::Text("hi".into()));
    g.press(Key::Enter, Modifiers::default());
    g.press(Key::Escape, Modifiers::default());
    assert_eq!(g.note.get(), "hi\n");
    assert_eq!(*g.escaped.borrow(), 1);
    assert_eq!(g.value.get(), before);
    // A press on the card's own space keeps focus off the editor.
    let card = g.card().unwrap();
    g.click(card.x + card.width - 4., card.y + card.height - 4.);
    assert_ne!(g.ui.focused_editor().map(|e| e.node), Some(g.editor.node));
}
