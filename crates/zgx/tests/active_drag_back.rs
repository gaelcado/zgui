use std::{cell::Cell, rc::Rc};
use zgx::{
    compose::prelude::*,
    input::{InputEvent, PointerButton},
    scene::{Color, NodeId, NodeKind},
    widgets::Ui,
};

fn fill(ui: &Ui, node: NodeId) -> Color {
    match ui.scene.borrow().kind(node) {
        NodeKind::Panel { quad, .. } => quad.fill,
        other => panic!("expected panel {other:?}"),
    }
}

fn at(ui: &mut Ui, event: impl Fn(f32, f32) -> InputEvent, (x, y): (f32, f32)) {
    ui.dispatch(event(x, y));
    ui.prepare_frame();
}

#[test]
fn a_press_dragged_off_a_button_and_back_looks_pressed_again_and_clicks() {
    let mut ui = Ui::new(300., 200.);
    let clicks = Rc::new(Cell::new(0));
    let counted = clicks.clone();
    let (base, active) = (rgb(0x112233), rgb(0xaabbcc));
    let view = ui.mount(
        column().size(300., 200.).child(
            button()
                .id("button")
                .size(100., 40.)
                .bg(base)
                .active(move |s| s.bg(active))
                .on_click(move || counted.set(counted.get() + 1)),
        ),
    );
    ui.prepare_frame();
    let node = view.find("button").unwrap();
    let primary = PointerButton::Primary;
    let (inside, outside) = ((50., 20.), (200., 150.));
    let move_to = |x, y| InputEvent::PointerMove { x, y };
    at(&mut ui, move_to, inside);
    at(
        &mut ui,
        |x, y| InputEvent::PointerDown {
            x,
            y,
            button: primary,
        },
        inside,
    );
    assert_eq!(fill(&ui, node), active, "pressed");
    at(&mut ui, move_to, outside);
    assert_eq!(fill(&ui, node), base, "off it, the press looks let go");
    at(&mut ui, move_to, inside);
    assert_eq!(fill(&ui, node), active, "back on it, pressed again");
    at(
        &mut ui,
        |x, y| InputEvent::PointerUp {
            x,
            y,
            button: primary,
        },
        inside,
    );
    assert_ne!(fill(&ui, node), active, "let go, it is only hovered");
    assert_eq!(clicks.get(), 1, "and letting go there clicks");

    // Let go off it: no click, and coming back later is only a hover.
    at(
        &mut ui,
        |x, y| InputEvent::PointerDown {
            x,
            y,
            button: primary,
        },
        inside,
    );
    at(&mut ui, move_to, outside);
    at(
        &mut ui,
        |x, y| InputEvent::PointerUp {
            x,
            y,
            button: primary,
        },
        outside,
    );
    at(&mut ui, move_to, inside);
    assert_ne!(fill(&ui, node), active, "a press let go elsewhere is over");
    assert_eq!(clicks.get(), 1);
}

#[test]
fn a_press_that_opens_a_menu_leaves_its_button_unpressed() {
    // A select's menu opens on press (as a native pop-up button's does):
    // the release lands in the menu, and the button must not stay pressed.
    let mut ui = Ui::new(300., 200.);
    let open = ui.signal(false);
    let (base, active) = (rgb(0x112233), rgb(0xaabbcc));
    let opener = open.clone();
    let view = ui.mount(
        column().size(300., 200.).child(
            popover(
                "Menu",
                open.clone(),
                button()
                    .id("button")
                    .size(100., 40.)
                    .bg(base)
                    .active(move |s| s.bg(active))
                    .child(text("Choose").id("label"))
                    .on_event(move |cx| {
                        if matches!(cx.event, InputEvent::PointerDown { .. }) {
                            opener.set(true);
                        }
                    }),
            )
            .child(button().id("item").size(80., 30.)),
        ),
    );
    ui.prepare_frame();
    let node = view.find("button").unwrap();
    let label = ui.scene.borrow().bounds(view.find("label").unwrap());
    let on_label = (label.x + 2., label.y + label.height / 2.);
    at(
        &mut ui,
        |x, y| InputEvent::PointerDown {
            x,
            y,
            button: PointerButton::Primary,
        },
        on_label,
    );
    assert!(open.get(), "the press opened the menu");
    assert_ne!(fill(&ui, node), active, "the menu took the press");
    let item = ui.scene.borrow().bounds(view.find("item").unwrap());
    at(
        &mut ui,
        |x, y| InputEvent::PointerUp {
            x,
            y,
            button: PointerButton::Primary,
        },
        (item.x + 5., item.y + 5.),
    );
    open.set(false);
    ui.prepare_frame();
    assert_eq!(fill(&ui, node), base, "closed, the button is at rest");
}
