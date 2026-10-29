//! A select the app draws (`select_with`): its button, menu and items are
//! the app's, and it is still a select (roles, value, typing, the menu).
use zgx::{
    compose::{Placement, ViewHandle, prelude::*},
    input::{InputEvent, Key, Modifiers, PointerButton},
    scene::NodeId,
    semantics::Role,
    widgets::Ui,
};
use zgx_components::*;

fn key(ui: &mut Ui, key: Key) {
    ui.dispatch(InputEvent::KeyDown {
        key,
        modifiers: Modifiers::default(),
        repeat: false,
    });
    ui.prepare_frame();
}
fn click(ui: &mut Ui, node: NodeId) {
    let b = ui.scene.borrow().bounds(node);
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = PointerButton::Primary;
    ui.dispatch(InputEvent::PointerDown { x, y, button });
    ui.dispatch(InputEvent::PointerUp { x, y, button });
    ui.prepare_frame();
}
fn with_role(ui: &Ui, view: &ViewHandle, role: Role) -> Vec<NodeId> {
    let scene = ui.scene.borrow();
    let semantics = ui.semantics.borrow();
    let mut out = Vec::new();
    let mut pending = vec![view.node()];
    while let Some(id) = pending.pop() {
        if semantics.get(id).is_some_and(|n| n.role == role) {
            out.push(id);
        }
        pending.extend(scene.children(id).iter().rev().copied());
    }
    out
}

#[test]
fn a_select_the_app_draws_keeps_its_roles_keys_and_menu() {
    let mut ui = Ui::new(400., 300.);
    let value = ui.signal("turn".to_owned());
    let options = vec![
        SelectOption::new("turn", "Last turn").id("scope_turn"),
        SelectOption::new("branch", "Branch").id("scope_branch"),
    ];
    let names = ["Last turn", "Branch"];
    let shown = value.clone();
    let parts = SelectParts {
        button: Some(Box::new(move |b, _| {
            b.id("scope").h(26.).px(8.).child(text_signal(move || {
                if shown.get() == "turn" {
                    "Last turn"
                } else {
                    "Branch"
                }
                .to_owned()
            }))
        })),
        bare_button: true,
        menu: Some(Box::new(|m, _| m.id("scopes").w(200.).p(4.))),
        item: Some(Box::new(move |i, item, _| {
            item.h(30.).child(text(format!("{} ✓", names[i])))
        })),
        placement: Some(Placement::default()),
    };
    let view =
        ui.mount(
            column()
                .p(20.)
                .child(select_with("Scope", value.clone(), options, "", parts)),
        );
    ui.prepare_frame();
    let trigger = with_role(&ui, &view, Role::ComboBox)[0];
    assert_eq!(trigger, view.find("scope").unwrap(), "the app's button");
    {
        let semantics = ui.semantics.borrow();
        let node = semantics.get(trigger).unwrap();
        assert_eq!(node.label, "Scope");
        assert_eq!(node.value.as_deref(), Some("Last turn"));
    }
    assert_eq!(ui.scene.borrow().bounds(trigger).height, 26.);
    click(&mut ui, trigger);
    let below = ui.scene.borrow().bounds(trigger);
    let menu = view.find("scopes").expect("the app's menu");
    let panel = ui.scene.borrow().bounds(menu);
    assert_eq!(panel.width, 200.);
    assert!(panel.y >= below.y + below.height, "placed under the button");
    let branch = view.find("scope_branch").expect("the item, by its id");
    assert_eq!(ui.scene.borrow().bounds(branch).height, 30.);
    assert_eq!(
        ui.semantics.borrow().get(branch).unwrap().checked,
        Some(false)
    );
    click(&mut ui, branch);
    assert_eq!(value.get(), "branch");
    assert_eq!(
        ui.semantics.borrow().get(trigger).unwrap().value.as_deref(),
        Some("Branch")
    );
    // Closed and focused, typing still chooses.
    ui.input.focus(&ui.scene, Some(trigger));
    key(&mut ui, Key::Character("l".into()));
    assert_eq!(value.get(), "turn");
}
