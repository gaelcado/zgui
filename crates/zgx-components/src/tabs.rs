//! Tabs choosing a panel, as WAI-ARIA's tabs pattern and an editor's tab
//! strip: one Tab stop, the arrows moving among the tabs (the choice
//! following), Home and End to the ends; closable tabs close with their ×,
//! Delete, or a middle click; reorderable ones drag along the strip or move
//! with ⌘ (Ctrl) Shift and an arrow; a strip too long for its width scrolls,
//! and a menu at its end lists every tab. An app may draw the tabs itself
//! ([`TabsOptions::tab`]), and what follows the pointer as one drags
//! ([`TabsOptions::preview`]), and place their panels itself ([`tab_strip`]).
use std::{
    cell::{Cell, RefCell},
    collections::HashMap,
    rc::Rc,
};
use zgx::{
    compose::{
        Context, NodeHandle, View, button, column, component, div, keyed, menu, menu_item, row,
        scroll_x, switch, text, text_signal,
    },
    input::{DragPhase, EventPhase, FocusGroup, InputEvent, Key, PointerButton},
    reactive::Signal,
    scene::{Color, Direction},
    semantics::Role,
    style::{Styled, Styles},
    theme::tok,
};

/// A tab of [`tabs`]: its id (unique among them), what it shows, and
/// whether it closes.
#[derive(Clone, Debug, PartialEq)]
pub struct Tab {
    /// Unique among the tabs.
    pub id: String,
    /// What it shows.
    pub label: String,
    /// A × closes it (and Delete, and a middle click).
    pub closable: bool,
}
impl Tab {
    /// A tab that doesn't close.
    pub fn new(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            closable: false,
        }
    }
    /// One that closes.
    pub fn closable(mut self) -> Self {
        self.closable = true;
        self
    }
}

/// What a tab dragged along its strip carries (a drag of the engine's, so
/// a destination elsewhere may take it): its id.
#[derive(Clone, Debug, PartialEq)]
pub struct DraggedTab {
    /// The tab's id.
    pub id: String,
}

/// What a closed tab asks first: `true` closes it (an editor asking to save
/// first returns `false` and closes it itself later).
pub type CloseTab = Rc<dyn Fn(&str) -> bool>;
/// Told that a tab moved: its id, and its place now (from 0).
pub type MoveTab = Rc<dyn Fn(&str, usize)>;
/// Gives a tab, bare, its look and content, from the tab and what closes it
/// (asking `on_close` first, as the strip's own × does).
pub type DressTab = Rc<dyn Fn(&Tab, View, Rc<dyn Fn()>, &mut Context) -> View>;
/// What follows the pointer as a tab is dragged, from the tab.
pub type PreviewTab = Rc<dyn Fn(&Tab) -> View>;

/// How [`tabs`] behave beyond choosing.
#[derive(Clone, Default)]
pub struct TabsOptions {
    /// Tabs drag along the strip, and move with ⌘ (Ctrl) Shift and an arrow.
    pub reorderable: bool,
    /// Asked before a tab closes; without it, it closes.
    pub on_close: Option<CloseTab>,
    /// Told after a tab moves, dragged or by the keys (an app keeping the
    /// order, or tapping the trackpad as tabs swap places).
    pub on_move: Option<MoveTab>,
    /// Each tab, bare (its role, the focus, the choice, the keys and the
    /// drag set), as the app draws it: the app's look and content, and none
    /// of the strip's (no padding, fill or ×: the tab closes with what it is
    /// given). Its sizes are its own, so tabs can shrink to share the strip
    /// before it scrolls, or slide as they move (`layout = "position"` in a
    /// script).
    pub tab: Option<DressTab>,
    /// Styles over the row the tabs lie in (their `gap`, their alignment):
    /// two points apart unless set.
    pub list: Option<Styles>,
    /// What follows the pointer while a tab is dragged (the tab lifted, as
    /// a browser's), its top-left kept where the tab was grabbed; none
    /// unless given. The tab itself takes its place in the strip as the
    /// pointer passes its neighbours' middles.
    pub preview: Option<PreviewTab>,
    /// Written the id of the tab being dragged, and `""` once it is let go:
    /// for the tab to show where it was (dimmed, as under a preview).
    pub dragging: Option<Signal<String>>,
}

/// The ids in `items`, in order.
fn ids(items: &[Tab]) -> Vec<String> {
    items.iter().map(|t| t.id.clone()).collect()
}

/// A strip of `items` and the panel `panel` builds for the one `selected`
/// (its id). `items` is two-way: closing a tab removes it, reordering
/// moves it; closing the selected tab chooses its neighbour. The panel is
/// built as its tab is chosen; `label` names the strip.
pub fn tabs(
    label: impl Into<String>,
    items: Signal<Vec<Tab>>,
    selected: Signal<String>,
    options: TabsOptions,
    panel: impl FnMut(String, &mut Context) -> View + 'static,
) -> View {
    let strip = tab_strip(label, items, selected.clone(), options);
    let mut panel = panel;
    column()
        .child(strip)
        .child(
            div()
                .h(1.)
                .shrink_0()
                .bg(tok::BORDER_SUBTLE)
                .accessible_hidden(),
        )
        .child(
            div()
                .role(Role::TabPanel)
                .grow()
                .child(switch(move || selected.get(), move |id, cx| panel(id, cx))),
        )
}

/// The strip of [`tabs`] alone, its panels the app's to place (a title
/// bar's tabs, over panes kept elsewhere).
pub fn tab_strip(
    label: impl Into<String>,
    items: Signal<Vec<Tab>>,
    selected: Signal<String>,
    options: TabsOptions,
) -> View {
    let label = label.into();
    component(move |cx| {
        // A label that changes (a translation, a state), where the caller
        // gave one (`FollowedLabel::around`).
        let followed = zgx::compose::FollowedLabel::take(cx);
        let runtime = cx.runtime();
        // Each tab's node, for dragging, scrolling into view and focus.
        let nodes: Rc<RefCell<HashMap<String, NodeHandle>>> = Rc::default();
        let offset = runtime.signal(0_f32);
        let viewport: Rc<RefCell<Option<NodeHandle>>> = Rc::default();
        // The strip's and its tabs' widths, as layout gives them.
        let strip_bounds = runtime.signal(0_f32);
        let content_bounds = runtime.signal(0_f32);
        let overflow_open = runtime.signal(false);
        // What was chosen before the press that chose a tab: a close that
        // press ends in (a drawn tab's ×) chooses it again.
        let pressed_from: Rc<RefCell<Option<String>>> = Rc::default();

        // Close `id`: asked first, then gone, its neighbour chosen if it was.
        let close = {
            let (items, selected, on_close) =
                (items.clone(), selected.clone(), options.on_close.clone());
            Rc::new(move |id: &str| {
                if on_close.as_ref().is_some_and(|ask| !ask(id)) {
                    return;
                }
                let list = items.with_untracked(Clone::clone);
                let Some(at) = list.iter().position(|t| t.id == id) else {
                    return;
                };
                let mut next = list.clone();
                next.remove(at);
                if selected.with_untracked(|s| s == id)
                    && let Some(neighbour) = next.get(at).or_else(|| next.get(at.wrapping_sub(1)))
                {
                    selected.set(neighbour.id.clone());
                }
                items.set(next);
            })
        };
        // A close by the pointer leaves the choice where it was, though the
        // press on the × chose its tab (as an editor's background tab
        // closes); focus goes back there too, else it would fall to the
        // closed tab's neighbour, choosing that. Whoever removes the tab (the
        // strip, or the app from `on_close`), its effects settle first.
        let close_pressed = {
            let (close, items, selected, pressed_from, nodes) = (
                close.clone(),
                items.clone(),
                selected.clone(),
                pressed_from.clone(),
                nodes.clone(),
            );
            let runtime = runtime.clone();
            Rc::new(move |id: &str| {
                let before = pressed_from.borrow_mut().take();
                close(id);
                runtime.settle();
                if let Some(before) = before.filter(|b| b != id)
                    && items.with_untracked(|l| l.iter().any(|t| t.id == before))
                {
                    if selected.with_untracked(|s| *s != before) {
                        selected.set(before.clone());
                    }
                    if let Some(tab) = nodes.borrow().get(&before) {
                        tab.focus();
                    }
                }
            })
        };
        // Bring `id`'s tab into the strip's view.
        let reveal = {
            let (nodes, viewport, offset) = (nodes.clone(), viewport.clone(), offset.clone());
            Rc::new(move |id: &str| {
                let (Some(tab), Some(view)) =
                    (nodes.borrow().get(id).cloned(), viewport.borrow().clone())
                else {
                    return;
                };
                // Either may have gone since (a reload, the tab closed).
                if !tab.is_mounted() || !view.is_mounted() {
                    return;
                }
                let Some(scene) = tab.scene() else { return };
                let (b, v) = {
                    let scene = scene.borrow();
                    (scene.bounds(tab.node()), scene.bounds(view.node()))
                };
                let now = offset.with_untracked(|o| *o);
                if b.x < v.x {
                    offset.set((now - (v.x - b.x)).max(0.));
                } else if b.x + b.width > v.x + v.width {
                    offset.set(now + (b.x + b.width - v.x - v.width));
                }
            })
        };
        // The chosen tab in view however it was chosen (the app opening one,
        // the strip narrowing), once laid out.
        {
            let (selected, viewport, reveal, room) = (
                selected.clone(),
                viewport.clone(),
                reveal.clone(),
                strip_bounds.clone(),
            );
            // Only as the choice or the strip's width changes, not with
            // every layout that republishes its bounds.
            let last: Cell<Option<f32>> = Cell::new(None);
            let chosen: RefCell<String> = RefCell::default();
            cx.retain(runtime.effect(move || {
                let id = selected.get();
                let width = room.get();
                if last.replace(Some(width)) == Some(width) && *chosen.borrow() == id {
                    return;
                }
                *chosen.borrow_mut() = id.clone();
                if let Some(view) = viewport.borrow().clone() {
                    let reveal = reveal.clone();
                    view.after_layout(move || reveal(&id));
                }
            }));
        }
        // Move `id` to `to` among the tabs.
        let move_to = {
            let (items, on_move) = (items.clone(), options.on_move.clone());
            Rc::new(move |id: &str, to: usize| {
                let mut list = items.with_untracked(Clone::clone);
                let Some(from) = list.iter().position(|t| t.id == id) else {
                    return;
                };
                let to = to.min(list.len() - 1);
                if from != to {
                    let tab = list.remove(from);
                    list.insert(to, tab);
                    items.set(list);
                    if let Some(told) = &on_move {
                        told(id, to);
                    }
                }
            })
        };

        let tab_view = {
            let (items, selected, nodes) = (items.clone(), selected.clone(), nodes.clone());
            let (close, close_pressed, move_to, reveal) = (
                close.clone(),
                close_pressed.clone(),
                move_to.clone(),
                reveal.clone(),
            );
            let (dress, pressed_from) = (options.tab.clone(), pressed_from.clone());
            let (preview, dragging) = (options.preview.clone(), options.dragging.clone());
            let reorderable = options.reorderable;
            move |id: String, cx: &mut Context| {
                let lookup = {
                    let items = items.clone();
                    let id = id.clone();
                    move || items.with(|list| list.iter().find(|t| t.id == id).cloned())
                };
                let (chosen, styled, pressed, focused) = (
                    selected.clone(),
                    selected.clone(),
                    selected.clone(),
                    selected.clone(),
                );
                let (id_chosen, id_styled, id_pressed, id_focused) =
                    (id.clone(), id.clone(), id.clone(), id.clone());
                let current = lookup().unwrap_or_else(|| Tab::new(id.clone(), ""));
                let closable = current.closable;
                let named = lookup.clone();
                // A press that may become a drag along the strip: where it was.
                let drag: Rc<Cell<Option<(f32, f32)>>> = Rc::default();
                let tab = match &dress {
                    // The app's own: its look, a tab's behaviour.
                    Some(dress) => {
                        let closes: Rc<dyn Fn()> = {
                            let (close, id) = (close_pressed.clone(), id.clone());
                            Rc::new(move || close(&id))
                        };
                        let bare = button().focusable(true);
                        let bare = if current.label.is_empty() {
                            bare
                        } else {
                            bare.accessible_label_when(move || {
                                named().map(|t| t.label).unwrap_or_default()
                            })
                        };
                        dress(&current, bare, closes, cx)
                    }
                    None => {
                        let shown = lookup.clone();
                        let mut tab = button()
                            .accessible_label_when(move || {
                                named().map(|t| t.label).unwrap_or_default()
                            })
                            .px(12.)
                            .py(6.)
                            .gap(6.)
                            .rounded(6.)
                            .border(0.)
                            .shrink_0()
                            .reactive_style(move || {
                                if styled.with(|s| *s == id_styled) {
                                    Styles::new()
                                        .bg(tok::SURFACE_RAISED)
                                        .text_color(tok::TEXT_PRIMARY)
                                } else {
                                    Styles::new()
                                        .bg(Color(0, 0, 0, 0))
                                        .text_color(tok::TEXT_SECONDARY)
                                }
                            })
                            .hover(|s| s.text_color(tok::TEXT_PRIMARY))
                            .child(text_signal(move || {
                                shown().map(|t| t.label).unwrap_or_default()
                            }));
                        if closable {
                            let (close, id) = (close_pressed.clone(), id.clone());
                            tab = tab.child(
                                button()
                                    .focusable(false)
                                    .accessible_label(format!("Close {}", current.label))
                                    .w(16.)
                                    .h(16.)
                                    .p(0.)
                                    .rounded(4.)
                                    .border(0.)
                                    .bg(Color(0, 0, 0, 0))
                                    .hover(|s| s.bg(tok::HOVER))
                                    .items_center()
                                    .justify_center()
                                    .on_click(move || close(&id))
                                    .child(text("×").text_size(12.).text_color(tok::TEXT_TERTIARY)),
                            );
                        }
                        tab
                    }
                };
                let (close, move_to, reveal, nodes, items, pressed_from) = (
                    close.clone(),
                    move_to.clone(),
                    reveal.clone(),
                    nodes.clone(),
                    items.clone(),
                    pressed_from.clone(),
                );
                let dragging = dragging.clone();
                // Dragged with the pointer at `x`: past a neighbour's
                // middle, it takes its place.
                let reorder = {
                    let (items, nodes, move_to, id) =
                        (items.clone(), nodes.clone(), move_to.clone(), id.clone());
                    move |x: f32| {
                        let order = items.with_untracked(|l| ids(l));
                        let middles: Vec<(String, f32)> = {
                            let nodes = nodes.borrow();
                            order
                                .iter()
                                .filter_map(|tab| {
                                    let handle = nodes.get(tab).filter(|h| h.is_mounted())?;
                                    let scene = handle.scene()?;
                                    let b = scene.borrow().layout_bounds(handle.node());
                                    Some((tab.clone(), b.x + b.width / 2.))
                                })
                                .collect()
                        };
                        let Some(at) = order.iter().position(|t| *t == id) else {
                            return;
                        };
                        let rtl = middles.len() > 1 && middles[0].1 > middles[1].1;
                        let to = middles
                            .iter()
                            .filter(|(tab, mid)| {
                                *tab != id && if rtl { x < *mid } else { x > *mid }
                            })
                            .count();
                        if to != at {
                            move_to(&id, to);
                        }
                    }
                };
                let tab = match &preview {
                    Some(preview) => {
                        let (preview, lookup) = (preview.clone(), lookup.clone());
                        tab.drag_preview(move |_: &DraggedTab| {
                            let tab = lookup().unwrap_or_else(|| Tab::new("", ""));
                            preview(&tab)
                        })
                    }
                    None => tab,
                };
                tab.role(Role::Tab)
                    .selected_when(move || chosen.with(|s| *s == id_chosen))
                    .on_mount({
                        let (nodes, id) = (nodes.clone(), id.clone());
                        move |handle| {
                            nodes.borrow_mut().insert(id, handle);
                        }
                    })
                    .on_event(move |cx| {
                        if cx.phase == EventPhase::Capture {
                            return;
                        }
                        // Focus is the tab's own; a press may be on its text,
                        // or on a button in it.
                        let on_tab = cx.target == cx.current_target;
                        if matches!(cx.event, InputEvent::Focus | InputEvent::KeyDown { .. })
                            && !on_tab
                        {
                            return;
                        }
                        let index =
                            || items.with_untracked(|l| l.iter().position(|t| t.id == id_focused));
                        match &cx.event {
                            // Selection follows focus, as WAI-ARIA's automatic tabs.
                            InputEvent::Focus => {
                                if focused.with_untracked(|s| *s != id_focused) {
                                    focused.set(id_focused.clone());
                                }
                                reveal(&id_focused);
                            }
                            InputEvent::KeyDown { key, modifiers, .. } => {
                                let rtl = nodes
                                    .borrow()
                                    .get(&id_focused)
                                    .and_then(NodeHandle::scene)
                                    .is_some_and(|scene| {
                                        scene.borrow().direction(cx.target) == Direction::Rtl
                                    });
                                let command = modifiers.meta || modifiers.control;
                                match key {
                                    Key::Delete if closable => {
                                        close(&id_focused);
                                        cx.prevent_default();
                                        cx.stop_propagation();
                                    }
                                    Key::ArrowLeft | Key::ArrowRight
                                        if reorderable && command && modifiers.shift =>
                                    {
                                        let Some(at) = index() else { return };
                                        let toward_end = (*key == Key::ArrowRight) != rtl;
                                        let to = if toward_end {
                                            at + 1
                                        } else {
                                            at.saturating_sub(1)
                                        };
                                        move_to(&id_focused, to);
                                        cx.prevent_default();
                                        cx.stop_propagation();
                                    }
                                    _ => {}
                                }
                            }
                            InputEvent::PointerDown {
                                button: PointerButton::Middle,
                                ..
                            } if closable => {
                                close(&id_focused);
                                cx.stop_propagation();
                            }
                            // Chosen as it is pressed, as a browser's tabs are;
                            // a press a field in it keeps (renaming it) is the
                            // field's.
                            InputEvent::PointerDown {
                                x,
                                y,
                                button: PointerButton::Primary,
                            } => {
                                // What was chosen, for a close the press ends in;
                                // kept until the press is done.
                                let before = pressed.with_untracked(Clone::clone);
                                *pressed_from.borrow_mut() = Some(before.clone());
                                if cx.capture_requested() || cx.default_prevented() {
                                    return;
                                }
                                if before != id_pressed {
                                    pressed.set(id_pressed.clone());
                                }
                                // A drag once it moves: a press on a button in
                                // the tab stays that button's click.
                                if reorderable {
                                    drag.set(Some((*x, *y)));
                                }
                            }
                            // Moved past the slop, the press becomes a drag
                            // (the engine's: its preview follows the pointer,
                            // and the release is no click).
                            InputEvent::PointerMove { x, .. } => {
                                if let Some((start, y)) = drag.get()
                                    && (*x - start).abs() >= 4.
                                {
                                    drag.set(None);
                                    cx.start_drag_from(
                                        DraggedTab {
                                            id: id_focused.clone(),
                                        },
                                        start,
                                        y,
                                    );
                                }
                            }
                            InputEvent::Drag(event)
                                if cx.target == cx.current_target
                                    && event
                                        .payload
                                        .downcast_ref::<DraggedTab>()
                                        .is_some_and(|tab| tab.id == id_focused) =>
                            {
                                match event.phase {
                                    DragPhase::Start => {
                                        if let Some(dragging) = &dragging {
                                            dragging.set(id_focused.clone());
                                        }
                                    }
                                    DragPhase::Move if !event.visiting => reorder(event.x),
                                    DragPhase::End => {
                                        if let Some(dragging) = &dragging {
                                            dragging.set(String::new());
                                        }
                                    }
                                    _ => {}
                                }
                            }
                            InputEvent::PointerUp {
                                button: PointerButton::Primary,
                                ..
                            }
                            | InputEvent::PointerCancel => {
                                drag.set(None);
                                // The press is done once its click has run.
                                if let Some(tab) = nodes.borrow().get(&id_focused) {
                                    let pressed_from = pressed_from.clone();
                                    tab.after_layout(move || {
                                        pressed_from.borrow_mut().take();
                                    });
                                }
                            }
                            _ => {}
                        }
                    })
            }
        };

        let strip_items = items.clone();
        let mut region = keyed(move || strip_items.with(|l| ids(l)), tab_view)
            .flex_row()
            .gap(2.);
        if let Some(list) = &options.list {
            region.styles_mut().merge(list);
        }
        let list = row()
            .role(Role::TabList)
            .accessible_label_or(label.clone(), followed.as_ref())
            .focus_group(FocusGroup::Horizontal)
            .apply(|list| {
                // Room for the strip's own focus ring; drawn tabs draw theirs.
                if options.tab.is_some() {
                    list
                } else {
                    list.shrink_0().gap(2.).p(2.)
                }
            })
            .on_mount({
                let (content_bounds, runtime) = (content_bounds.clone(), runtime.clone());
                move |handle| follow(&runtime, &content_bounds, &handle)
            })
            // The tabs lie in a row in the keyed region.
            .child(region);
        // Drawn tabs that can shrink share the strip before it scrolls.
        let strip = scroll_x(offset)
            .apply(|strip| {
                if options.tab.is_some() {
                    strip.shrink_first()
                } else {
                    strip
                }
            })
            .grow()
            .min_w(0.)
            .on_mount({
                let (viewport, strip_bounds) = (viewport.clone(), strip_bounds.clone());
                let runtime = runtime.clone();
                move |handle| {
                    follow(&runtime, &strip_bounds, &handle);
                    *viewport.borrow_mut() = Some(handle);
                }
            })
            .child(list);
        // Too many to show: a menu of them all at the strip's end. Once it
        // shows, tabs that shrink may fill just the strip it leaves them:
        // it stays while they do, as many as they were, rather than going,
        // giving them back its room to spread past, and coming back, every
        // layout pass. Fewer tabs decide afresh, without it.
        let overflowing = {
            let (strip, content) = (strip_bounds.clone(), content_bounds.clone());
            let tabs = items.clone();
            let shown_for = Rc::new(Cell::new(None::<usize>));
            let last = Rc::new(Cell::new(0_usize));
            move || {
                let (content, strip) = (content.get(), strip.get());
                let count = tabs.with(|list| list.len());
                let fewer = count < last.replace(count);
                let over = if fewer {
                    false
                } else if shown_for.get() == Some(count) {
                    content > strip - 0.5
                } else {
                    content > strip + 0.5
                };
                shown_for.set(over.then_some(count));
                over
            }
        };
        let (menu_items, menu_selected, menu_reveal) =
            (items.clone(), selected.clone(), reveal.clone());
        let more = switch(overflowing, move |over, _| {
            if !over {
                return div();
            }
            let mut list = menu(
                "All tabs",
                overflow_open.clone(),
                button()
                    .accessible_label("All tabs")
                    .px(8.)
                    .py(4.)
                    .border(0.)
                    .bg(Color(0, 0, 0, 0))
                    .child(text("⌄").text_color(tok::TEXT_SECONDARY)),
            );
            for tab in menu_items.with(|l| l.clone()) {
                let (checked, chosen, reveal) = (
                    menu_selected.clone(),
                    menu_selected.clone(),
                    menu_reveal.clone(),
                );
                let (id, id2) = (tab.id.clone(), tab.id.clone());
                list = list.child(
                    menu_item(tab.label)
                        .menu_radio()
                        .menu_checked_when(move || checked.with(|s| *s == id))
                        .on_click(move || {
                            chosen.set(id2.clone());
                            reveal(&id2);
                        }),
                );
            }
            list
        });
        // One child: the strip's own spacing (`list`) is the tabs', none
        // between the strip and its menu.
        row().items_center().child(
            row()
                .items_center()
                .grow()
                .min_w(0.)
                .child(strip)
                .child(more),
        )
    })
}

/// Keep `into` equal to `handle`'s node's width, for as long as the node
/// is: its size, read only as layout runs (not its bounds, republished
/// every frame).
fn follow(runtime: &zgx::reactive::Runtime, into: &Signal<f32>, handle: &NodeHandle) {
    let Some(from) = handle.observe_size() else {
        return;
    };
    let into = into.clone();
    handle.retain(runtime.effect(move || {
        let width = from.get().0;
        if into.with_untracked(|w| *w != width) {
            into.set(width);
        }
    }));
}
