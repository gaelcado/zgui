//! Hover has `mouseenter` / `mouseleave` semantics: a node is hovered while
//! the pointer is anywhere inside it, descendants included, and hears one
//! enter and one leave, at the target phase, however the pointer moves
//! between its children.
use std::{cell::RefCell, rc::Rc};
use zgui::{
    compose::prelude::*,
    input::{EventPhase, InputEvent},
    scene::NodeId,
    widgets::Ui,
};

type Log = Rc<RefCell<Vec<String>>>;

/// Logs `name+` and `name-` for the node's own enters and leaves.
fn logged(view: View, name: &'static str, log: &Log) -> View {
    let log = log.clone();
    view.on_event(move |cx| {
        let sign = match cx.event {
            InputEvent::PointerEnter => '+',
            InputEvent::PointerLeave => '-',
            _ => return,
        };
        assert_eq!(cx.phase, EventPhase::Target, "{name} hears its own");
        assert_eq!(cx.target, cx.current_target);
        log.borrow_mut().push(format!("{name}{sign}"));
    })
}

fn take(log: &Log) -> Vec<String> {
    std::mem::take(&mut *log.borrow_mut())
}

fn move_to(ui: &mut Ui, x: f32, y: f32) {
    ui.dispatch(InputEvent::PointerMove { x, y });
}

/// A 200×100 parent at the origin holding two 80×80 children side by side
/// (at x 0 and 100) and, over the right half of the first, a positioned
/// 40×80 sibling painted over it.
fn mount(log: &Log) -> Ui {
    let mut ui = Ui::new(400., 300.);
    ui.mount(logged(
        overlay()
            .size(200., 100.)
            .child(
                row()
                    .gap(20.)
                    .child(logged(div().size(80., 80.), "a", log))
                    .child(logged(div().size(80., 80.), "b", log)),
            )
            .child(logged(
                div().absolute().left(40.).top(0.).size(40., 80.),
                "over",
                log,
            )),
        "parent",
        log,
    ));
    ui.prepare_frame();
    ui
}

#[test]
fn moving_between_children_tells_the_parent_nothing() {
    let log = Log::default();
    let mut ui = mount(&log);
    move_to(&mut ui, 10., 10.);
    assert_eq!(take(&log), ["parent+", "a+"]);
    // Within `a`: nothing.
    move_to(&mut ui, 20., 20.);
    assert!(take(&log).is_empty());
    // Into the gap: still the parent.
    move_to(&mut ui, 90., 10.);
    assert_eq!(take(&log), ["a-"]);
    // Into `b`, then back to `a`: the parent hears neither.
    move_to(&mut ui, 110., 10.);
    assert_eq!(take(&log), ["b+"]);
    move_to(&mut ui, 10., 10.);
    assert_eq!(take(&log), ["b-", "a+"]);
    // Out of everything: deepest first.
    move_to(&mut ui, 300., 200.);
    assert_eq!(take(&log), ["a-", "parent-"]);
}

#[test]
fn overlapping_siblings_follow_hit_order() {
    let log = Log::default();
    let mut ui = mount(&log);
    move_to(&mut ui, 10., 10.);
    take(&log);
    // Where `over` covers `a`, the pointer is in `over`, not `a` (as the
    // DOM: a positioned sibling is no ancestor).
    move_to(&mut ui, 50., 10.);
    assert_eq!(take(&log), ["a-", "over+"]);
    move_to(&mut ui, 70., 70.);
    assert!(take(&log).is_empty());
    // Past `over`'s right edge (inside neither child).
    move_to(&mut ui, 85., 10.);
    assert_eq!(take(&log), ["over-"]);
}

#[test]
fn leaving_the_window_leaves_every_hovered_node() {
    let log = Log::default();
    let mut ui = mount(&log);
    move_to(&mut ui, 110., 10.);
    assert_eq!(take(&log), ["parent+", "b+"]);
    ui.dispatch(InputEvent::PointerLeave);
    assert_eq!(take(&log), ["b-", "parent-"]);
    assert_eq!(ui.input.hovered(), None);
    // Coming back enters again.
    move_to(&mut ui, 110., 10.);
    assert_eq!(take(&log), ["parent+", "b+"]);
}

#[test]
fn a_parent_hover_style_holds_across_its_children() {
    let mut ui = Ui::new(300., 100.);
    let hovered = Rc::new(RefCell::new(Vec::new()));
    let seen = hovered.clone();
    ui.mount(
        row()
            .size(200., 50.)
            .hover(|s| s.bg(rgb(0x202020)))
            .on_event(move |cx| match cx.event {
                InputEvent::PointerEnter => seen.borrow_mut().push(true),
                InputEvent::PointerLeave => seen.borrow_mut().push(false),
                _ => {}
            })
            .child(button().size(50., 50.).on_click(|| {}))
            .child(button().size(50., 50.).on_click(|| {})),
    );
    ui.prepare_frame();
    for x in [10., 70., 20., 75., 150.] {
        move_to(&mut ui, x, 10.);
    }
    // One enter across both buttons and the row between them.
    assert_eq!(*hovered.borrow(), [true]);
    ui.dispatch(InputEvent::PointerLeave);
    assert_eq!(*hovered.borrow(), [true, false]);
}

#[test]
fn removing_the_hovered_child_keeps_its_parent_hovered() {
    let log = Log::default();
    let mut ui = Ui::new(300., 100.);
    let shown = ui.signal(true);
    let child = shown.clone();
    let child_log = log.clone();
    ui.mount(logged(
        row().size(200., 50.).child(switch(
            move || child.get(),
            move |on, _| {
                if on {
                    logged(div().size(50., 50.).on_click(|| {}), "child", &child_log)
                } else {
                    div()
                }
            },
        )),
        "parent",
        &log,
    ));
    ui.prepare_frame();
    move_to(&mut ui, 10., 10.);
    assert_eq!(take(&log), ["parent+", "child+"]);
    shown.set(false);
    ui.prepare_frame();
    // The parent is still under the pointer: no leave, no second enter.
    move_to(&mut ui, 12., 10.);
    assert!(take(&log).is_empty(), "{:?}", log.borrow());
    move_to(&mut ui, 250., 10.);
    assert_eq!(take(&log), ["parent-"]);
}

/// A 200×50 hover group: a 50×50 handle at its left, and a close button at
/// its right, hidden until the group is hovered. A third child is styled on
/// the group's hover and on its own, over it.
fn group(ui: &mut Ui) -> (NodeId, NodeId) {
    let view = ui.mount(
        row()
            .size(200., 50.)
            .hover_group()
            .child(div().size(50., 50.).on_click(|| {}))
            .child(
                div()
                    .size(50., 50.)
                    .opacity(0.)
                    .group_hover(|s| s.opacity(1.)),
            )
            .child(
                div()
                    .size(50., 50.)
                    .opacity(0.2)
                    .group_hover(|s| s.opacity(0.6))
                    .hover(|s| s.opacity(1.)),
            ),
    );
    ui.prepare_frame();
    let children = ui.scene.borrow().children(view.node()).to_vec();
    (children[1], children[2])
}

fn opacity(ui: &Ui, node: NodeId) -> f32 {
    ui.scene.borrow().effects(node).opacity
}

#[test]
fn group_hover_styles_follow_the_group_not_the_node() {
    let mut ui = Ui::new(300., 100.);
    let (close, both) = group(&mut ui);
    assert_eq!((opacity(&ui, close), opacity(&ui, both)), (0., 0.2));
    // Over the handle: the group is hovered, so its close button shows.
    move_to(&mut ui, 10., 10.);
    ui.prepare_frame();
    assert_eq!((opacity(&ui, close), opacity(&ui, both)), (1., 0.6));
    // Over the third child: its own hover lies over the group's.
    move_to(&mut ui, 120., 10.);
    ui.prepare_frame();
    assert_eq!((opacity(&ui, close), opacity(&ui, both)), (1., 1.));
    // Out of the group: both rest again.
    move_to(&mut ui, 250., 10.);
    ui.prepare_frame();
    assert_eq!((opacity(&ui, close), opacity(&ui, both)), (0., 0.2));
}

#[test]
fn group_hover_outside_a_group_never_applies() {
    let mut ui = Ui::new(300., 100.);
    let view = ui.mount(
        row().size(200., 50.).hover(|s| s.bg(rgb(0x202020))).child(
            div()
                .size(50., 50.)
                .opacity(0.)
                .group_hover(|s| s.opacity(1.)),
        ),
    );
    ui.prepare_frame();
    let child = ui.scene.borrow().children(view.node())[0];
    move_to(&mut ui, 10., 10.);
    ui.prepare_frame();
    assert_eq!(opacity(&ui, child), 0.);
}

#[test]
fn a_group_hover_shows_what_the_base_hides() {
    let mut ui = Ui::new(300., 100.);
    let view = ui.mount(
        row()
            .size(200., 50.)
            .hover_group()
            .child(div().size(50., 50.).on_click(|| {}))
            .child(div().size(30., 30.).hidden().group_hover(|s| s.shown())),
    );
    ui.prepare_frame();
    let close = ui.scene.borrow().children(view.node())[1];
    assert_eq!(ui.scene.borrow().bounds(close).width, 0., "hidden at rest");
    move_to(&mut ui, 10., 10.);
    ui.prepare_frame();
    assert_eq!(
        ui.scene.borrow().bounds(close).width,
        30.,
        "laid out in the hovered group"
    );
    move_to(&mut ui, 250., 10.);
    ui.prepare_frame();
    assert_eq!(ui.scene.borrow().bounds(close).width, 0.);
}
