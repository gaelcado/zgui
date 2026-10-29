//! The tree view: the keyboard (moving, opening, closing, typeahead,
//! activating), what assistive technology hears, children loaded as an
//! item opens, thousands of rows, right to left, and the pointer.
use std::{cell::RefCell, rc::Rc};
use zgx::{
    compose::{ViewHandle, prelude::*},
    input::{InputEvent, Key, Modifiers, PointerButton},
    reactive::Signal,
    scene::{Direction, NodeId},
    semantics::Role,
    widgets::Ui,
};
use zgx_components::*;

struct Fixture {
    ui: Ui,
    view: ViewHandle,
    open: Signal<Vec<String>>,
    selected: Signal<Option<String>>,
    activated: Rc<RefCell<Vec<String>>>,
    /// The lazily loaded children of `b`, once loaded.
    loaded: Signal<Option<Vec<TreeItem>>>,
}

fn fixture(big: usize) -> Fixture {
    let mut ui = Ui::new(400., 400.);
    let open = ui.signal(Vec::<String>::new());
    let selected = ui.signal(None::<String>);
    let activated = Rc::new(RefCell::new(Vec::new()));
    let loaded = ui.signal(None::<Vec<TreeItem>>);
    let (log, lazy) = (activated.clone(), loaded.clone());
    let children = move |parent: Option<&str>| match parent {
        None => TreeChildren::Ready(vec![
            TreeItem::parent("a", "Alpha"),
            TreeItem::parent("b", "Beta"),
            TreeItem::leaf("c", "Charlie"),
        ]),
        Some("a") => TreeChildren::Ready(vec![
            TreeItem::leaf("a1", "Apple"),
            TreeItem::parent("a2", "Avocado"),
        ]),
        Some("a2") => TreeChildren::Ready(
            (0..big)
                .map(|i| TreeItem::leaf(format!("x{i}"), format!("Item {i}")))
                .collect(),
        ),
        Some("b") => match lazy.get() {
            Some(items) => TreeChildren::Ready(items),
            None => TreeChildren::Loading,
        },
        Some(_) => TreeChildren::Ready(Vec::new()),
    };
    let view = ui.mount(column().id("root").w(300.).h(400.).child(tree(
        "Files",
        children,
        open.clone(),
        selected.clone(),
        move |id| log.borrow_mut().push(id.to_owned()),
    )));
    ui.prepare_frame();
    ui.prepare_frame();
    Fixture {
        ui,
        view,
        open,
        selected,
        activated,
        loaded,
    }
}
fn key(ui: &mut Ui, key: Key) {
    ui.dispatch(InputEvent::KeyDown {
        key,
        modifiers: Modifiers::default(),
        repeat: false,
    });
    ui.prepare_frame();
}
fn with_role(ui: &Ui, role: Role) -> Vec<NodeId> {
    let scene = ui.scene.borrow();
    let semantics = ui.semantics.borrow();
    let mut out = Vec::new();
    let mut pending = vec![scene.root()];
    while let Some(n) = pending.pop() {
        if semantics.get(n).is_some_and(|s| s.role == role) {
            out.push(n);
        }
        pending.extend(scene.children(n).iter().rev().copied());
    }
    out
}
fn labels(ui: &Ui) -> Vec<String> {
    with_role(ui, Role::TreeItem)
        .iter()
        .map(|n| ui.semantics.borrow().get(*n).unwrap().label.clone())
        .collect()
}
fn focus_tree(f: &mut Fixture) -> NodeId {
    let tree = with_role(&f.ui, Role::Tree)[0];
    f.ui.input.focus(&f.ui.scene, Some(tree));
    f.ui.prepare_frame();
    tree
}

#[test]
fn the_keyboard_moves_opens_closes_and_activates() {
    let mut f = fixture(3);
    assert_eq!(labels(&f.ui), ["Alpha", "Beta", "Charlie"]);
    let tree = focus_tree(&mut f);
    assert_eq!(
        f.selected.get().as_deref(),
        Some("a"),
        "focused: the first is current"
    );
    key(&mut f.ui, Key::ArrowRight);
    assert_eq!(f.open.get(), ["a"], "Right opens it");
    assert_eq!(
        labels(&f.ui),
        ["Alpha", "Apple", "Avocado", "Beta", "Charlie"]
    );
    key(&mut f.ui, Key::ArrowRight);
    assert_eq!(f.selected.get().as_deref(), Some("a1"), "then enters it");
    key(&mut f.ui, Key::ArrowLeft);
    assert_eq!(
        f.selected.get().as_deref(),
        Some("a"),
        "Left goes to the parent"
    );
    key(&mut f.ui, Key::ArrowLeft);
    assert!(f.open.get().is_empty(), "then closes it");
    key(&mut f.ui, Key::End);
    assert_eq!(f.selected.get().as_deref(), Some("c"));
    key(&mut f.ui, Key::Home);
    key(&mut f.ui, Key::Character("c".into()));
    assert_eq!(f.selected.get().as_deref(), Some("c"), "typeahead");
    key(&mut f.ui, Key::Enter);
    assert_eq!(*f.activated.borrow(), ["c"]);
    // Focus stays on the tree; the current row is its active descendant.
    assert_eq!(f.ui.input.focused(), Some(tree));
    let charlie = with_role(&f.ui, Role::TreeItem)[2];
    let semantics = f.ui.semantics.borrow();
    assert_eq!(
        semantics.get(tree).unwrap().active_descendant,
        Some(charlie)
    );
    let node = semantics.get(charlie).unwrap();
    assert_eq!(
        (
            node.level,
            node.position_in_set,
            node.size_of_set,
            node.selected
        ),
        (Some(1), Some(3), Some(3), Some(true))
    );
}

#[test]
fn children_load_as_an_item_opens_and_thousands_stay_virtual() {
    let mut f = fixture(2000);
    focus_tree(&mut f);
    key(&mut f.ui, Key::ArrowDown);
    key(&mut f.ui, Key::ArrowRight);
    assert_eq!(f.open.get(), ["b"]);
    assert!(labels(&f.ui).contains(&"Loading…".to_owned()));
    f.loaded.set(Some(vec![TreeItem::leaf("b1", "Banana")]));
    f.ui.prepare_frame();
    assert_eq!(labels(&f.ui), ["Alpha", "Beta", "Banana", "Charlie"]);
    let banana = with_role(&f.ui, Role::TreeItem)[2];
    assert_eq!(f.ui.semantics.borrow().get(banana).unwrap().level, Some(2));
    // Two thousand under Avocado: only what shows is built.
    f.open.set(vec!["a".into(), "a2".into()]);
    f.ui.prepare_frame();
    f.ui.prepare_frame();
    let built = with_role(&f.ui, Role::TreeItem).len();
    assert!(built < 40, "{built} rows built");
    key(&mut f.ui, Key::End);
    f.ui.prepare_frame();
    assert_eq!(f.selected.get().as_deref(), Some("c"));
    assert!(
        labels(&f.ui).contains(&"Charlie".to_owned()),
        "scrolled to it"
    );
}

#[test]
fn right_to_left_left_opens() {
    let mut f = fixture(3);
    let root = f.view.find("root").unwrap();
    f.ui.scene
        .borrow_mut()
        .set_direction(root, Some(Direction::Rtl));
    f.ui.prepare_frame();
    focus_tree(&mut f);
    key(&mut f.ui, Key::ArrowRight);
    assert!(f.open.get().is_empty(), "Right goes back, right to left");
    key(&mut f.ui, Key::ArrowLeft);
    assert_eq!(f.open.get(), ["a"]);
}

#[test]
fn the_chevron_opens_a_click_chooses_and_a_double_click_activates() {
    let mut f = fixture(3);
    let rows = with_role(&f.ui, Role::TreeItem);
    let b = f.ui.scene.borrow().bounds(rows[0]);
    let button = PointerButton::Primary;
    // The chevron, at the row's start.
    let (x, y) = (b.x + 6., b.y + b.height / 2.);
    f.ui.dispatch(InputEvent::PointerDown { x, y, button });
    f.ui.dispatch(InputEvent::PointerUp { x, y, button });
    f.ui.prepare_frame();
    assert_eq!(f.open.get(), ["a"]);
    assert_eq!(f.selected.get(), None, "the chevron chooses nothing");
    let charlie = *with_role(&f.ui, Role::TreeItem).last().unwrap();
    let c = f.ui.scene.borrow().bounds(charlie);
    let (x, y) = (c.x + 60., c.y + c.height / 2.);
    f.ui.dispatch_with_modifiers(
        InputEvent::PointerDown { x, y, button },
        Modifiers::default(),
    );
    f.ui.dispatch_with_modifiers(InputEvent::PointerUp { x, y, button }, Modifiers::default());
    assert_eq!(f.selected.get().as_deref(), Some("c"));
    f.ui.dispatch_with_modifiers(
        InputEvent::PointerDown { x, y, button },
        Modifiers::default(),
    );
    f.ui.dispatch_with_modifiers(InputEvent::PointerUp { x, y, button }, Modifiers::default());
    assert_eq!(*f.activated.borrow(), ["c"]);
}

#[test]
fn rows_the_app_draws_keep_the_tree_and_parents_open_as_pressed() {
    let mut ui = Ui::new(400., 400.);
    let open = ui.signal(Vec::<String>::new());
    let selected = ui.signal(None::<String>);
    let children = |parent: Option<&str>| match parent {
        None => TreeChildren::Ready(vec![
            TreeItem::parent("a", "Alpha"),
            TreeItem::leaf("c", "Charlie"),
        ]),
        Some("a") => TreeChildren::Ready(vec![TreeItem::leaf("a1", "Apple")]),
        Some(_) => TreeChildren::Ready(Vec::new()),
    };
    let dress: DressRow = Rc::new(
        |item: &TreeItem, level: usize, bare: View, _: &mut Context| {
            bare.id(item.id.clone())
                .pl(level as f32 * 14.)
                .child(text(format!("{} at {level}", item.label)))
        },
    );
    let options = TreeOptions {
        row: Some(dress),
        row_height: Some(30.),
        open_on_click: true,
        ..Default::default()
    };
    let view = ui.mount(column().w(300.).h(400.).child(tree_with(
        "Files",
        children,
        open.clone(),
        selected.clone(),
        |_| {},
        options,
    )));
    ui.prepare_frame();
    ui.prepare_frame();
    let alpha = view.find("a").expect("the app's row");
    assert_eq!(
        with_role(&ui, Role::TreeItem)[0],
        alpha,
        "the drawn row is the item"
    );
    assert_eq!(ui.scene.borrow().bounds(alpha).height, 30.);
    // A press on a parent chooses it and opens it; its child is a level in.
    let b = ui.scene.borrow().bounds(alpha);
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = PointerButton::Primary;
    ui.dispatch(InputEvent::PointerDown { x, y, button });
    ui.dispatch(InputEvent::PointerUp { x, y, button });
    ui.prepare_frame();
    assert_eq!(selected.get().as_deref(), Some("a"));
    assert_eq!(open.get(), ["a"]);
    let apple = view.find("a1").expect("opened");
    let semantics = ui.semantics.borrow();
    let node = semantics.get(apple).unwrap();
    assert_eq!((node.level, node.label.as_str()), (Some(2), "Apple"));
    drop(semantics);
    assert_eq!(ui.scene.borrow().bounds(apple).y, b.y + 30.);
}

/// A row that drags (into a chat, onto a folder) is still the tree's to
/// choose as it is pressed and to open as the press comes up: a drag
/// source's capture only watches for a drag, unlike a field's, which keeps
/// the press. Dragged, a parent stays as it was.
#[test]
fn rows_that_drag_still_choose_and_open_as_pressed() {
    let mut ui = Ui::new(400., 400.);
    let open = ui.signal(Vec::<String>::new());
    let selected = ui.signal(None::<String>);
    let children = |parent: Option<&str>| match parent {
        None => TreeChildren::Ready(vec![
            TreeItem::parent("a", "Alpha"),
            TreeItem::leaf("c", "Charlie"),
        ]),
        Some("a") => TreeChildren::Ready(vec![TreeItem::leaf("a1", "Apple")]),
        Some(_) => TreeChildren::Ready(Vec::new()),
    };
    let dress: DressRow = Rc::new(|item: &TreeItem, _: usize, bare: View, _: &mut Context| {
        let id = item.id.clone();
        bare.id(item.id.clone())
            .on_drag(move || id.clone())
            .child(text(item.label.clone()))
    });
    let options = TreeOptions {
        row: Some(dress),
        row_height: Some(30.),
        open_on_click: true,
        ..Default::default()
    };
    let view = ui.mount(column().w(300.).h(400.).child(tree_with(
        "Files",
        children,
        open.clone(),
        selected.clone(),
        |_| {},
        options,
    )));
    ui.prepare_frame();
    let b = ui.scene.borrow().bounds(view.find("a").expect("the row"));
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = PointerButton::Primary;
    ui.dispatch(InputEvent::PointerDown { x, y, button });
    ui.dispatch(InputEvent::PointerUp { x, y, button });
    ui.prepare_frame();
    assert_eq!(selected.get().as_deref(), Some("a"), "chosen");
    assert_eq!(open.get(), ["a"], "and opened");
    // Pressed and moved past the threshold, it drags instead, still open.
    assert!(!ui.input.is_dragging());
    ui.dispatch(InputEvent::PointerDown { x, y, button });
    ui.dispatch(InputEvent::PointerMove {
        x: x + 40.,
        y: y + 40.,
    });
    assert!(ui.input.is_dragging(), "a drag under way");
    ui.dispatch(InputEvent::PointerUp {
        x: x + 40.,
        y: y + 40.,
        button,
    });
    ui.prepare_frame();
    assert_eq!(open.get(), ["a"], "a drag neither opens nor closes it");
}

/// A tree choosing several, its rows dragging, Alpha open: Alpha, Apple,
/// Avocado, Beta, Charlie.
struct Many {
    ui: Ui,
    view: ViewHandle,
    selected: Signal<Option<String>>,
    selection: Signal<Vec<String>>,
}
fn many() -> Many {
    let mut ui = Ui::new(400., 400.);
    let open = ui.signal(vec!["a".to_owned()]);
    let selected = ui.signal(None::<String>);
    let selection = ui.signal(Vec::<String>::new());
    let children = |parent: Option<&str>| match parent {
        None => TreeChildren::Ready(vec![
            TreeItem::parent("a", "Alpha"),
            TreeItem::parent("b", "Beta"),
            TreeItem::leaf("c", "Charlie"),
        ]),
        Some("a") => TreeChildren::Ready(vec![
            TreeItem::leaf("a1", "Apple"),
            TreeItem::leaf("a2", "Avocado"),
        ]),
        Some(_) => TreeChildren::Ready(Vec::new()),
    };
    let dress: DressRow = Rc::new(|item: &TreeItem, _: usize, bare: View, _: &mut Context| {
        let id = item.id.clone();
        bare.id(item.id.clone())
            .on_drag(move || id.clone())
            .child(text(item.label.clone()))
    });
    let options = TreeOptions {
        row: Some(dress),
        row_height: Some(30.),
        selection: Some(selection.clone()),
        ..Default::default()
    };
    let view = ui.mount(column().w(300.).h(400.).child(tree_with(
        "Files",
        children,
        open,
        selected.clone(),
        |_| {},
        options,
    )));
    ui.prepare_frame();
    ui.prepare_frame();
    Many {
        ui,
        view,
        selected,
        selection,
    }
}
impl Many {
    fn press(&mut self, id: &str, modifiers: Modifiers) {
        let b = self.ui.scene.borrow().bounds(self.view.find(id).expect(id));
        let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
        let button = PointerButton::Primary;
        self.ui
            .dispatch_with_modifiers(InputEvent::PointerDown { x, y, button }, modifiers);
        self.ui
            .dispatch_with_modifiers(InputEvent::PointerUp { x, y, button }, modifiers);
        self.ui.prepare_frame();
    }
    fn key(&mut self, key: Key, shift: bool) -> bool {
        let done = self.ui.dispatch(InputEvent::KeyDown {
            key,
            modifiers: Modifiers {
                shift,
                ..Modifiers::default()
            },
            repeat: false,
        });
        self.ui.prepare_frame();
        done.default_prevented
    }
    fn chosen(&self) -> Vec<String> {
        let mut s = self.selection.get();
        s.sort();
        s
    }
}
/// ⌘ on macOS, Ctrl elsewhere.
fn command(shift: bool) -> Modifiers {
    Modifiers {
        shift,
        meta: cfg!(target_os = "macos"),
        control: !cfg!(target_os = "macos"),
        ..Modifiers::default()
    }
}
fn shift() -> Modifiers {
    Modifiers {
        shift: true,
        ..Modifiers::default()
    }
}

/// Several chosen, as a file explorer: ⌘ adds or takes away, Shift chooses
/// the rows from the anchor (⌘⇧ adds them), Shift and an arrow extends, a
/// plain move or click chooses one, Escape keeps the current item alone,
/// and a press below the rows chooses none. The rows' choice follows.
#[test]
fn a_tree_chooses_several_with_command_and_shift() {
    let mut m = many();
    m.press("a1", Modifiers::default());
    assert_eq!(m.chosen(), ["a1"]);
    m.press("c", command(false));
    assert_eq!(m.chosen(), ["a1", "c"], "⌘ adds");
    assert_eq!(m.selected.get().as_deref(), Some("c"), "and it is current");
    m.press("a2", shift());
    assert_eq!(m.chosen(), ["a2", "b", "c"], "from the anchor, Charlie");
    m.press("a1", command(true));
    assert_eq!(m.chosen(), ["a1", "a2", "b", "c"], "⌘⇧ adds the range");
    let semantics = |m: &Many, id: &str| {
        let node = m.view.find(id).unwrap();
        m.ui.semantics.borrow().get(node).unwrap().selected
    };
    assert_eq!(semantics(&m, "b"), Some(true));
    assert_eq!(semantics(&m, "a"), Some(false));
    m.press("b", command(false));
    assert_eq!(m.chosen(), ["a1", "a2", "c"], "⌘ takes one away");
    assert_eq!(semantics(&m, "b"), Some(false));
    // Escape keeps the current item alone, then is not the tree's.
    let tree = with_role(&m.ui, Role::Tree)[0];
    m.ui.input.focus(&m.ui.scene, Some(tree));
    assert!(m.key(Key::Escape, false));
    assert_eq!(m.chosen(), ["b"]);
    assert!(!m.key(Key::Escape, false), "nothing more to drop");
    // Shift and the arrows extend from the anchor; a plain move, one.
    m.key(Key::ArrowDown, true);
    assert_eq!(m.chosen(), ["b", "c"]);
    m.key(Key::ArrowUp, true);
    m.key(Key::ArrowUp, true);
    assert_eq!(m.chosen(), ["a2", "b"]);
    assert_eq!(m.selected.get().as_deref(), Some("a2"));
    m.key(Key::ArrowUp, false);
    assert_eq!(m.chosen(), ["a1"]);
    // The app's own choice of the current item chooses it alone.
    m.selected.set(Some("c".into()));
    m.ui.prepare_frame();
    assert_eq!(m.chosen(), ["c"]);
    // Below the rows: none.
    let (x, y) = (100., 380.);
    let button = PointerButton::Primary;
    m.ui.dispatch(InputEvent::PointerDown { x, y, button });
    m.ui.dispatch(InputEvent::PointerUp { x, y, button });
    m.ui.prepare_frame();
    assert!(m.chosen().is_empty());
    assert_eq!(m.selected.get(), None);
}

/// A press on one of several chosen keeps them while it drags them all,
/// and chooses it alone only as a press that didn't drag comes up.
#[test]
fn a_drag_from_several_chosen_keeps_them() {
    let mut m = many();
    m.press("a1", Modifiers::default());
    m.press("a2", shift());
    assert_eq!(m.chosen(), ["a1", "a2"]);
    let b = m.ui.scene.borrow().bounds(m.view.find("a1").unwrap());
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = PointerButton::Primary;
    m.ui.dispatch(InputEvent::PointerDown { x, y, button });
    assert_eq!(m.chosen(), ["a1", "a2"], "pressed, still both");
    m.ui.dispatch(InputEvent::PointerMove {
        x: x + 40.,
        y: y + 40.,
    });
    assert!(m.ui.input.is_dragging());
    m.ui.dispatch(InputEvent::PointerUp {
        x: x + 40.,
        y: y + 40.,
        button,
    });
    m.ui.prepare_frame();
    assert_eq!(m.chosen(), ["a1", "a2"], "dragged, both");
    m.press("a2", Modifiers::default());
    assert_eq!(m.chosen(), ["a2"], "a plain click, one");
}
