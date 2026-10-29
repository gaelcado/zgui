//! A card over an editor's chip (`View::chip_tooltip`), as a tooltip
//! behaves: shown over the chip 300 ms after the pointer comes to rest on
//! it, gone as the pointer leaves it or presses, the editor scrolls or a
//! key is pressed. Which chip is under the pointer is the editor's own hit
//! test, so moving over the draft runs nothing of the app's; the card is
//! made only as it shows.
use crate::{
    compose::{
        Environment, Placement, PlacementEdge, PlacementSide, TaskRunner, TaskToken, View, div,
        popover, switch,
    },
    input::{EventPhase, InputEvent},
    scene::NodeId,
    widgets::{EditorHandle, Ui},
};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
    time::Duration,
};

/// What a chip's card shows, from its reference (`None`: no card).
pub(crate) type ChipTip = Rc<dyn Fn(&str) -> Option<View>>;

/// How long the pointer rests on a chip before its card shows.
const DELAY: Duration = Duration::from_millis(300);
/// How long the pointer may be off the editor before the card goes.
const GRACE: Duration = Duration::from_millis(60);

pub(crate) fn mount(
    ui: &mut Ui,
    root: NodeId,
    editor: EditorHandle,
    make: ChipTip,
    environment: Environment,
) {
    let runtime = ui.runtime.clone();
    let open = runtime.signal(false);
    // The chip whose card shows, and the one under the pointer.
    let shown = runtime.signal(None::<String>);
    let over: Rc<RefCell<Option<String>>> = Rc::default();
    let waiting: Rc<RefCell<Option<TaskToken>>> = Rc::default();
    let anchor_node: Rc<Cell<Option<NodeId>>> = Rc::default();
    let runner = environment.services.get::<TaskRunner>();

    // The card's anchor: an empty box laid over the chip as it shows,
    // letting the pointer through to the editor.
    let anchor = {
        let anchor_node = anchor_node.clone();
        div()
            .pointer_events(false)
            .on_mount(move |handle| anchor_node.set(Some(handle.node())))
    };
    let card = {
        let shown = shown.clone();
        switch(
            move || shown.get(),
            move |token, _| token.and_then(|token| make(&token)).unwrap_or_else(div),
        )
    };
    let view = popover("Chip", open.clone(), anchor)
        .layer()
        .lazy()
        .autofocus(false)
        .placement(Placement {
            side: PlacementSide::Top,
            align: PlacementEdge::Start,
            offset: 6.,
        })
        .pointer_events(false)
        .panel_hidden()
        .child(card);
    crate::compose::mount(ui, root, view, environment);

    let weak = ui.downgrade();
    let leaving: Rc<RefCell<Option<TaskToken>>> = Rc::default();
    let hide = {
        let (open, waiting, over, leaving) =
            (open.clone(), waiting.clone(), over.clone(), leaving.clone());
        Rc::new(move || {
            waiting.borrow_mut().take();
            leaving.borrow_mut().take();
            over.borrow_mut().take();
            if open.with_untracked(|o| *o) {
                open.set(false);
            }
        })
    };
    ui.on_event(root, false, move |cx| {
        if cx.phase == EventPhase::Capture {
            return;
        }
        match cx.event {
            InputEvent::PointerMove { x, y } => {
                let hit = editor.chip_at(x, y);
                let token = hit.as_ref().map(|(token, _)| token.clone());
                if *over.borrow() == token {
                    return;
                }
                hide();
                let Some((token, at)) = hit else {
                    return;
                };
                *over.borrow_mut() = Some(token.clone());
                // The anchor covers the chip, from the editor's content box.
                if let Some(ui) = weak.upgrade()
                    && let Some(node) = anchor_node.get()
                {
                    let mut scene = ui.scene.borrow_mut();
                    if scene.contains(node) {
                        let host = scene.transformed_bounds(root);
                        let inset = scene.content_insets(root);
                        let mut style = scene.style(node);
                        style.absolute = true;
                        style.width = Some(at.width);
                        style.height = Some(at.height);
                        style.margin.left = at.x - host.x - inset.left;
                        style.margin.top = at.y - host.y - inset.top;
                        scene.set_style(node, style);
                    }
                }
                let (open, shown) = (open.clone(), shown.clone());
                let show = move || {
                    shown.set(Some(token));
                    open.set(true);
                };
                match &runner {
                    Some(runner) => {
                        *waiting.borrow_mut() = Some(runner.spawn(Box::pin(async move {
                            crate::timer::sleep(DELAY).await;
                            show();
                        })));
                    }
                    None => show(),
                }
            }
            // The pointer leaving: the card goes after a moment's grace, as
            // the editor is left and entered again when what is under the
            // pointer changes in it (the anchor laid over the chip).
            InputEvent::PointerLeave if cx.target == cx.current_target => match &runner {
                Some(runner) => {
                    let hide = hide.clone();
                    *leaving.borrow_mut() = Some(runner.spawn(Box::pin(async move {
                        crate::timer::sleep(GRACE).await;
                        hide();
                    })));
                }
                None => hide(),
            },
            InputEvent::PointerEnter if cx.target == cx.current_target => {
                leaving.borrow_mut().take();
            }
            InputEvent::PointerDown { .. }
            | InputEvent::PointerCancel
            | InputEvent::Scroll { .. }
            | InputEvent::KeyDown { .. }
            | InputEvent::Blur => hide(),
            _ => {}
        }
    });
}
