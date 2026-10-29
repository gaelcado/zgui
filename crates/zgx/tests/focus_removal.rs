//! When what has focus leaves the interface, focus moves on, as a native
//! toolkit's does: to its nearest focusable ancestor that stays, else to the
//! next Tab stop (a focus group's own), else the one before; never to the
//! window, which a screen reader would announce.
use zgx::{
    compose::{ViewHandle, prelude::*},
    semantics::Role,
    widgets::Ui,
};

fn named(id: &str) -> View {
    button().id(id).child(text(id))
}
/// `id`'s button while `shown` says so.
fn shown_named(shown: zgx::reactive::Signal<bool>, id: &'static str) -> View {
    switch(
        move || shown.get(),
        move |on, _| if on { named(id) } else { div() },
    )
}
fn focused(ui: &Ui, view: &ViewHandle, names: &[&str]) -> Option<String> {
    let id = ui.input.focused()?;
    names
        .iter()
        .find(|name| view.find(name) == Some(id))
        .map(|name| name.to_string())
}

#[test]
fn focus_moves_on_to_the_next_stop_or_back_to_the_one_before() {
    let mut ui = Ui::new(400., 300.);
    let shown = ui.signal(true);
    let after = ui.signal(true);
    let view = ui.mount(
        column()
            .child(named("before"))
            .child(shown_named(shown.clone(), "gone"))
            .child(shown_named(after.clone(), "after")),
    );
    ui.prepare_frame();
    let names = ["before", "gone", "after"];
    ui.input.focus(&ui.scene, view.find("gone"));
    shown.set(false);
    ui.prepare_frame();
    assert_eq!(focused(&ui, &view, &names).as_deref(), Some("after"));
    // Nothing after it: back to the one before.
    shown.set(true);
    ui.prepare_frame();
    ui.input.focus(&ui.scene, view.find("gone"));
    after.set(false);
    shown.set(false);
    ui.prepare_frame();
    assert_eq!(focused(&ui, &view, &names).as_deref(), Some("before"));
}

#[test]
fn a_focus_group_next_is_entered_at_its_own_stop() {
    let mut ui = Ui::new(400., 300.);
    let shown = ui.signal(true);
    let view = ui.mount(
        column().child(shown_named(shown.clone(), "gone")).child(
            row()
                .role(Role::Toolbar)
                .child(named("a"))
                .child(named("b")),
        ),
    );
    ui.prepare_frame();
    let names = ["gone", "a", "b"];
    // "b" was where focus last was in the toolbar.
    ui.input.focus(&ui.scene, view.find("b"));
    ui.input.focus(&ui.scene, view.find("gone"));
    shown.set(false);
    ui.prepare_frame();
    assert_eq!(focused(&ui, &view, &names).as_deref(), Some("b"));
}

#[test]
fn a_press_that_replaces_its_node_keeps_the_focus_its_handler_gave() {
    // A title pressed turns into its editor, which takes focus as it
    // mounts: the press doesn't then focus what it pressed (gone) and take
    // the focus away again.
    let mut ui = Ui::new(400., 300.);
    let editing = ui.signal(false);
    let flip = editing.clone();
    let view = ui.mount(column().child(switch(
        move || editing.get(),
        move |on, _| {
            if on {
                named("editor").on_mount(|handle| {
                    handle.focus();
                })
            } else {
                let flip = flip.clone();
                named("title").on_event(move |cx| {
                    if matches!(cx.event, zgx::input::InputEvent::PointerDown { .. })
                        && cx.phase == zgx::input::EventPhase::Target
                    {
                        flip.set(true);
                    }
                })
            }
        },
    )));
    ui.prepare_frame();
    let b = ui.scene.borrow().bounds(view.find("title").unwrap());
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = zgx::input::PointerButton::Primary;
    ui.dispatch(zgx::input::InputEvent::PointerDown { x, y, button });
    ui.dispatch(zgx::input::InputEvent::PointerUp { x, y, button });
    ui.prepare_frame();
    assert_eq!(focused(&ui, &view, &["editor"]).as_deref(), Some("editor"));
}
