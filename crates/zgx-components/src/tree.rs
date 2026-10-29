//! A tree view: items in a hierarchy, opened and closed, as WAI-ARIA's tree
//! and Finder's sidebar. The tree is one Tab stop and keeps focus, its
//! current item the active descendant: Up and Down move, Right opens an
//! item and then enters it, Left closes it and then goes to its parent
//! (mirrored right to left), Home and End go to the ends, typing goes to
//! the next item starting with it, Enter activates; the choice follows the
//! current item. Children come from the app as each item opens (loaded
//! then, if it likes: "loading" until they come); the rows are virtual, so
//! a tree of thousands builds only what shows. An app may draw the rows
//! itself ([`TreeOptions::row`]): a file explorer's, with its guides and
//! icons, choosing several at once ([`TreeOptions::selection`]).
use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    rc::Rc,
    time::{Duration, Instant},
};
use zgx::{
    compose::{Context, NodeHandle, View, component, div, text, text_signal, virtual_list},
    input::{EventPhase, InputEvent, Key, PointerButton},
    reactive::Signal,
    scene::{Color, Direction, NodeId},
    semantics::Role,
    style::{Styled, Styles},
    theme::tok,
};

/// An item of a [`tree`]: its id (unique in the tree), what it shows, and
/// whether it has children (shown with a chevron, which opens it).
#[derive(Clone, Debug, PartialEq)]
pub struct TreeItem {
    /// Unique in the tree.
    pub id: String,
    /// What it shows.
    pub label: String,
    /// It opens: its children come from `children` as it does.
    pub parent: bool,
    /// What else its row is drawn from (an app's own item: a file's git
    /// status), as a stamp: its row is built again when this or its label
    /// changes, as when its id does.
    pub revision: u64,
}
impl TreeItem {
    /// A leaf showing `label`.
    pub fn leaf(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            parent: false,
            revision: 0,
        }
    }
    /// An item with children.
    pub fn parent(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            parent: true,
            revision: 0,
        }
    }
    /// Its row's key: a row is built again as it changes.
    fn key(&self) -> String {
        format!("{}\u{1f}{}\u{1f}{}", self.id, self.label, self.revision)
    }
}

/// What `children` answers for an item: its children, or not yet (they
/// are loading: the tree shows "Loading…" until it answers again).
pub enum TreeChildren {
    /// These, in order.
    Ready(Vec<TreeItem>),
    /// Still coming.
    Loading,
}

/// A row of the tree as it shows.
#[derive(Clone, Debug, PartialEq)]
struct Row {
    item: TreeItem,
    /// 1 at the roots.
    level: usize,
    open: bool,
    /// Its place among its siblings, from 1, and how many there are.
    position: usize,
    siblings: usize,
    parent: Option<String>,
    /// A "Loading…" row standing for children still coming.
    loading: bool,
}

/// The rows showing: the roots, and the children of each open item.
fn rows(children: &dyn Fn(Option<&str>) -> TreeChildren, open: &HashSet<String>) -> Vec<Row> {
    fn walk(
        children: &dyn Fn(Option<&str>) -> TreeChildren,
        open: &HashSet<String>,
        parent: Option<&str>,
        level: usize,
        out: &mut Vec<Row>,
    ) {
        match children(parent) {
            TreeChildren::Loading => out.push(Row {
                item: TreeItem::leaf(format!("{}\u{0}loading", parent.unwrap_or("")), "Loading…"),
                level,
                open: false,
                position: 1,
                siblings: 1,
                parent: parent.map(str::to_owned),
                loading: true,
            }),
            TreeChildren::Ready(items) => {
                let n = items.len();
                for (i, item) in items.into_iter().enumerate() {
                    let is_open = item.parent && open.contains(&item.id);
                    let id = item.id.clone();
                    out.push(Row {
                        item,
                        level,
                        open: is_open,
                        position: i + 1,
                        siblings: n,
                        parent: parent.map(str::to_owned),
                        loading: false,
                    });
                    if is_open {
                        walk(children, open, Some(&id), level + 1, out);
                    }
                }
            }
        }
    }
    let mut out = Vec::new();
    walk(children, open, None, 1, &mut out);
    out
}

/// A row's height, and how far each level indents.
const ROW: f32 = 26.;
const INDENT: f32 = 16.;

/// Gives a row, bare, its look and content, from its item and its level
/// (1 at the roots).
pub type DressRow = Rc<dyn Fn(&TreeItem, usize, View, &mut Context) -> View>;

/// How a [`tree_with`] looks and answers beyond a [`tree`]'s.
#[derive(Clone, Default)]
pub struct TreeOptions {
    /// Each row, bare (its role, level, choice and expanded state, the
    /// press that chooses it), as the app draws it: its indent, chevron,
    /// fill and content, none of the tree's own.
    pub row: Option<DressRow>,
    /// A row's height: 26 unless set.
    pub row_height: Option<f32>,
    /// A press on a parent opens or closes it as it chooses it, as a file
    /// explorer's folders do; otherwise its chevron does.
    pub open_on_click: bool,
    /// The chosen items' ids, both ways, as a file explorer chooses several:
    /// ⌘ (Ctrl elsewhere) and a click adds an item or takes it away, Shift
    /// and a click (or an arrow) chooses the rows from the anchor, ⌘⇧ adds
    /// them; a plain click or move chooses the current item alone, Escape
    /// keeps only it, and a press on the tree's empty space chooses none.
    /// Without it, the current item is the choice.
    pub selection: Option<Signal<Vec<String>>>,
}

/// A tree of what `children` gives for each item (`None`: the roots), its
/// open items' ids in `open` and the chosen one in `selected`, both
/// two-way. `activate` runs on Enter or a double click. `children` is read
/// as the tree shows, and followed (a signal it reads changing shows the
/// change); `label` names it.
pub fn tree(
    label: impl Into<String>,
    children: impl Fn(Option<&str>) -> TreeChildren + 'static,
    open: Signal<Vec<String>>,
    selected: Signal<Option<String>>,
    activate: impl Fn(&str) + 'static,
) -> View {
    tree_with(
        label,
        children,
        open,
        selected,
        activate,
        TreeOptions::default(),
    )
}

/// A [`tree`] whose rows the app draws, or that opens its parents as they
/// are pressed (`options`): it keeps what makes it a tree (the roles, the
/// levels and places assistive technology hears, the keys, the virtual
/// rows).
pub fn tree_with(
    label: impl Into<String>,
    children: impl Fn(Option<&str>) -> TreeChildren + 'static,
    open: Signal<Vec<String>>,
    selected: Signal<Option<String>>,
    activate: impl Fn(&str) + 'static,
    options: TreeOptions,
) -> View {
    let label = label.into();
    let row_h = options.row_height.unwrap_or(ROW).max(1.);
    let (children, activate) = (Rc::new(children), Rc::new(activate));
    component(move |cx| {
        // A label that changes (a translation, a state), where the caller
        // gave one (`FollowedLabel::around`).
        let followed = zgx::compose::FollowedLabel::take(cx);
        let runtime = cx.runtime();
        let shown = runtime.signal(Vec::<Row>::new());
        {
            let (children, open, shown) = (children.clone(), open.clone(), shown.clone());
            cx.retain(runtime.effect(move || {
                let open: HashSet<String> = open.get().into_iter().collect();
                shown.set(rows(&*children, &open));
            }));
        }
        let offset = runtime.signal(0_f32);
        let tree_node: Rc<RefCell<Option<NodeHandle>>> = Rc::default();
        let row_nodes: Rc<RefCell<HashMap<String, NodeHandle>>> = Rc::default();
        let mounted = runtime.signal(0u64);
        let search: Rc<RefCell<(String, Instant)>> =
            Rc::new(RefCell::new((String::new(), Instant::now())));

        let toggle = {
            let open = open.clone();
            Rc::new(move |id: &str, to: Option<bool>| {
                let mut list = open.with_untracked(Clone::clone);
                let is = list.iter().any(|o| o == id);
                let want = to.unwrap_or(!is);
                if want && !is {
                    list.push(id.to_owned());
                } else if !want && is {
                    list.retain(|o| o != id);
                } else {
                    return;
                }
                open.set(list);
            })
        };
        // Several chosen: the anchor a range starts from, and the current
        // item as the tree last set it (another's write chooses it alone).
        let selection = options.selection.clone();
        let anchor: Rc<RefCell<Option<String>>> = Rc::default();
        let ours: Rc<RefCell<Option<String>>> = Rc::default();
        // Chooses `id` alone (none for `None`), the anchor with it.
        let alone = {
            let (selection, anchor) = (selection.clone(), anchor.clone());
            Rc::new(move |id: Option<&str>| {
                *anchor.borrow_mut() = id.map(str::to_owned);
                if let Some(selection) = &selection {
                    selection.set(id.map(|id| vec![id.to_owned()]).unwrap_or_default());
                }
            })
        };
        // Chooses the visible rows from the anchor (the current item without
        // one) to `id`, added to the choice with `add`.
        let range = {
            let (selection, anchor, shown, selected) = (
                selection.clone(),
                anchor.clone(),
                shown.clone(),
                selected.clone(),
            );
            Rc::new(move |id: &str, add: bool| {
                let Some(selection) = &selection else {
                    return;
                };
                let visible: Vec<String> = shown.with_untracked(|rows| {
                    rows.iter()
                        .filter(|r| !r.loading)
                        .map(|r| r.item.id.clone())
                        .collect()
                });
                let Some(end) = visible.iter().position(|v| v == id) else {
                    return;
                };
                let from = anchor
                    .borrow()
                    .clone()
                    .or_else(|| selected.with_untracked(Clone::clone));
                let start = from
                    .and_then(|a| visible.iter().position(|v| *v == a))
                    .unwrap_or(end);
                *anchor.borrow_mut() = Some(visible[start].clone());
                let mut next = if add {
                    selection.with_untracked(Clone::clone)
                } else {
                    Vec::new()
                };
                for v in &visible[start.min(end)..=start.max(end)] {
                    if !next.contains(v) {
                        next.push(v.clone());
                    }
                }
                selection.set(next);
            })
        };
        // The current item as the tree sets it: the choice stays as it is.
        let current = {
            let (selected, ours) = (selected.clone(), ours.clone());
            Rc::new(move |id: Option<&str>| {
                *ours.borrow_mut() = id.map(str::to_owned);
                selected.set(id.map(str::to_owned));
            })
        };
        if let Some(selection) = &selection {
            // The current item written elsewhere (by the app) is chosen alone.
            let (selected, ours, anchor, selection) = (
                selected.clone(),
                ours.clone(),
                anchor.clone(),
                selection.clone(),
            );
            cx.retain(runtime.effect(move || {
                let now = selected.get();
                if *ours.borrow() == now && now.is_some() {
                    return;
                }
                *ours.borrow_mut() = now.clone();
                *anchor.borrow_mut() = now.clone();
                let next = now.map(|id| vec![id]).unwrap_or_default();
                if selection.with_untracked(|s| *s != next) {
                    selection.set(next);
                }
            }));
        }
        // The current item: in view, and the tree's active descendant.
        {
            let (selected, shown, offset, tree_node, row_nodes, mounted) = (
                selected.clone(),
                shown.clone(),
                offset.clone(),
                tree_node.clone(),
                row_nodes.clone(),
                mounted.clone(),
            );
            cx.retain(runtime.effect(move || {
                let id = selected.get();
                mounted.with(|_| ());
                let index = id
                    .as_ref()
                    .and_then(|id| shown.with(|rows| rows.iter().position(|r| r.item.id == *id)));
                let Some(handle) = tree_node.borrow().clone() else {
                    return;
                };
                // Not laid out yet (a mount reads it again once it is): no
                // view to bring the row into.
                if let Some(i) = index
                    && let Some(scene) = handle.scene()
                    && let height = scene.borrow().bounds(handle.node()).height
                    && height > 0.
                {
                    let height = height.max(row_h);
                    let top = i as f32 * row_h;
                    let now = offset.with_untracked(|o| *o);
                    if top < now {
                        offset.set(top);
                    } else if top + row_h > now + height {
                        offset.set(top + row_h - height);
                    }
                }
                let target = id.and_then(|id| row_nodes.borrow().get(&id).map(NodeHandle::node));
                handle.update_semantics(|node| node.active_descendant = target);
                // Each row's place: its level, and where among its siblings.
                let nodes = row_nodes.borrow();
                shown.with(|rows| {
                    for r in rows {
                        if let Some(n) = nodes.get(&r.item.id) {
                            n.update_semantics(|node| {
                                node.level = Some(r.level);
                                node.position_in_set = Some(r.position);
                                node.size_of_set = Some(r.siblings);
                            });
                        }
                    }
                });
            }));
        }

        let row_view = {
            let (shown, selected, toggle, activate, row_nodes, mounted) = (
                shown.clone(),
                selected.clone(),
                toggle.clone(),
                activate.clone(),
                row_nodes.clone(),
                mounted.clone(),
            );
            let (selection, alone, range, current, anchor) = (
                selection.clone(),
                alone.clone(),
                range.clone(),
                current.clone(),
                anchor.clone(),
            );
            let (dress, open_on_click) = (options.row.clone(), options.open_on_click);
            move |index: Signal<usize>, key: String, cx: &mut Context| {
                let row = {
                    let (shown, index) = (shown.clone(), index.clone());
                    move || shown.with(|rows| rows.get(index.get()).cloned())
                };
                let this = row().unwrap_or_else(|| Row {
                    item: TreeItem::leaf(key.split('\u{1f}').next().unwrap_or_default(), ""),
                    level: 1,
                    open: false,
                    position: 1,
                    siblings: 1,
                    parent: None,
                    loading: false,
                });
                let id = this.item.id.clone();
                let (chosen, styled) = (selected.clone(), selected.clone());
                let (id_chosen, id_styled) = (id.clone(), id.clone());
                let (label_row, chevron_row, expanded_row) =
                    (row.clone(), row.clone(), row.clone());
                let loading = this.loading;
                let many = selection.clone();
                let mut view = zgx::compose::row()
                    .role(Role::TreeItem)
                    .accessible_label(this.item.label.clone())
                    .selected_when(move || match &many {
                        Some(many) => many.with(|s| s.contains(&id_chosen)),
                        None => chosen.with(|s| s.as_deref() == Some(&*id_chosen)),
                    })
                    .h(row_h)
                    .on_mount({
                        let (row_nodes, mounted, id) =
                            (row_nodes.clone(), mounted.clone(), id.clone());
                        move |handle| {
                            row_nodes.borrow_mut().insert(id, handle);
                            mounted.set(mounted.with_untracked(|m| m + 1));
                        }
                    });
                if this.item.parent {
                    view = view.expanded_when(move || expanded_row().is_some_and(|r| r.open));
                }
                let (toggle_click, id_toggle) = (toggle.clone(), id.clone());
                let styled_many = selection.clone();
                let view = match &dress {
                    // The app's own row, a loading one excepted.
                    Some(dress) if !loading => dress(&this.item, this.level, view, cx),
                    _ => view
                        .pr(8.)
                        .gap(4.)
                        .items_center()
                        .rounded(5.)
                        .reactive_style(move || {
                            let on = match &styled_many {
                                Some(many) => many.with(|s| s.contains(&id_styled)),
                                None => styled.with(|s| s.as_deref() == Some(&*id_styled)),
                            };
                            if on {
                                Styles::new().bg(tok::SELECTION_ITEM)
                            } else {
                                Styles::new().bg(Color(0, 0, 0, 0))
                            }
                        })
                        .child(div().shrink_0().reactive_style(move || {
                            let level = label_row().map_or(1, |r| r.level);
                            Styles::new().w((level - 1) as f32 * INDENT)
                        }))
                        .child(
                            text_signal(move || match chevron_row() {
                                Some(r) if r.item.parent && r.open => "▾".into(),
                                Some(r) if r.item.parent => "▸".into(),
                                _ => String::new(),
                            })
                            .w(INDENT)
                            .shrink_0()
                            .text_size(10.)
                            .text_color(tok::TEXT_SECONDARY)
                            .accessible_hidden()
                            .on_event(move |cx| {
                                // The chevron opens and closes, not choosing.
                                if cx.phase != EventPhase::Capture
                                    && matches!(
                                        cx.event,
                                        InputEvent::PointerDown {
                                            button: PointerButton::Primary,
                                            ..
                                        }
                                    )
                                {
                                    toggle_click(&id_toggle, None);
                                    cx.prevent_default();
                                    cx.stop_propagation();
                                }
                            }),
                        )
                        .child(text(this.item.label.clone()).truncate().apply(|t| {
                            if loading {
                                t.text_color(tok::TEXT_TERTIARY)
                            } else {
                                t
                            }
                        })),
                };
                let id_select = id.clone();
                let (activate_click, id_activate) = (activate.clone(), id.clone());
                let (toggle_press, parent) = (toggle.clone(), this.item.parent);
                let (selection, alone, range, current, anchor) = (
                    selection.clone(),
                    alone.clone(),
                    range.clone(),
                    current.clone(),
                    anchor.clone(),
                );
                // A draggable parent's press: it opens or closes as the
                // press comes up without having dragged (where it went down).
                // So a press on one of several chosen chooses it alone only
                // then: a drag carries them all.
                let mut pending: Option<(f32, f32)> = None;
                let (mut toggle_up, mut alone_up) = (false, false);
                view.on_event(move |cx| {
                    // A press a field in the row keeps (renaming it) is the
                    // field's; a draggable row's is still the tree's.
                    if cx.phase == EventPhase::Capture
                        || loading
                        || cx.press_kept()
                        || cx.default_prevented()
                    {
                        return;
                    }
                    match cx.event {
                        InputEvent::PointerDown {
                            x,
                            y,
                            button: PointerButton::Primary,
                        } => {
                            pending = None;
                            (toggle_up, alone_up) = (false, false);
                            let modifiers = cx.pointer_modifiers();
                            let (shift, command) = (modifiers.shift, modifiers.primary_shortcut());
                            if cx.click_count() >= 2 {
                                activate_click(&id_activate);
                            } else if let Some(many) = &selection
                                && (shift || command)
                            {
                                if shift {
                                    // From the anchor, added to the choice with ⌘.
                                    range(&id_select, command);
                                } else {
                                    // Added, or taken away; the anchor either way.
                                    let mut next = many.with_untracked(Clone::clone);
                                    if let Some(at) = next.iter().position(|s| *s == id_select) {
                                        next.remove(at);
                                    } else {
                                        next.push(id_select.clone());
                                    }
                                    *anchor.borrow_mut() = Some(id_select.clone());
                                    many.set(next);
                                }
                                current(Some(&id_select));
                            } else {
                                current(Some(&id_select));
                                let among = selection.as_ref().is_some_and(|many| {
                                    many.with_untracked(|s| s.len() > 1 && s.contains(&id_select))
                                });
                                if among && cx.capture_requested() {
                                    alone_up = true;
                                } else {
                                    alone(Some(&id_select));
                                }
                                if open_on_click && parent {
                                    if cx.capture_requested() {
                                        toggle_up = true;
                                    } else {
                                        toggle_press(&id_select, None);
                                    }
                                }
                                if toggle_up || alone_up {
                                    pending = Some((x, y));
                                }
                            }
                        }
                        InputEvent::PointerMove { x, y } => {
                            let far = cx.drag_threshold();
                            if pending.is_some_and(|(px, py)| (x - px).hypot(y - py) > far) {
                                pending = None;
                            }
                        }
                        InputEvent::PointerUp {
                            button: PointerButton::Primary,
                            ..
                        } => {
                            if pending.take().is_some() {
                                if alone_up {
                                    alone(Some(&id_select));
                                }
                                if toggle_up {
                                    toggle_press(&id_select, None);
                                }
                            }
                        }
                        InputEvent::PointerCancel | InputEvent::Blur => pending = None,
                        _ => {}
                    }
                })
            }
        };

        let (count, keys) = (shown.clone(), shown.clone());
        let list = virtual_list(
            offset,
            row_h,
            6,
            move || count.with(Vec::len),
            move |i| keys.with(|rows| rows.get(i).map(|r| r.item.key()).unwrap_or_default()),
            row_view,
        );
        let (key_shown, key_selected, key_toggle, key_activate) = (
            shown.clone(),
            selected.clone(),
            toggle.clone(),
            activate.clone(),
        );
        let key_tree = tree_node.clone();
        div()
            .role(Role::Tree)
            .accessible_label_or(label.clone(), followed.as_ref())
            .focusable(true)
            .h_full()
            .on_mount(move |handle| *tree_node.borrow_mut() = Some(handle))
            .on_event(move |cx| {
                if cx.phase == EventPhase::Capture {
                    return;
                }
                // A plain press on the empty space below the rows chooses
                // none (a modified one keeps the choice).
                if selection.is_some()
                    && let InputEvent::PointerDown {
                        button: PointerButton::Primary,
                        ..
                    } = cx.event
                {
                    let modifiers = cx.pointer_modifiers();
                    let on_row = key_tree
                        .borrow()
                        .as_ref()
                        .and_then(NodeHandle::scene)
                        .is_none_or(|scene| {
                            let scene = scene.borrow();
                            let nodes = row_nodes.borrow();
                            let rows: HashSet<NodeId> =
                                nodes.values().map(NodeHandle::node).collect();
                            std::iter::once(cx.target)
                                .chain(scene.ancestors(cx.target))
                                .any(|n| rows.contains(&n))
                        });
                    if !on_row && !modifiers.shift && !modifiers.primary_shortcut() {
                        current(None);
                        alone(None);
                    }
                    return;
                }
                // Its own keys: a field in a row (renaming it) keeps its own.
                if cx.target != cx.current_target {
                    return;
                }
                let InputEvent::KeyDown { key, modifiers, .. } = &cx.event else {
                    // Focused with nothing chosen: the first item is current.
                    if matches!(cx.event, InputEvent::Focus)
                        && key_selected.with_untracked(Option::is_none)
                        && let Some(first) = key_shown.with_untracked(|r| r.first().cloned())
                    {
                        key_selected.set(Some(first.item.id));
                    }
                    return;
                };
                let rows = key_shown.with_untracked(Clone::clone);
                if rows.is_empty() {
                    return;
                }
                let at = key_selected
                    .with_untracked(Clone::clone)
                    .and_then(|id| rows.iter().position(|r| r.item.id == id));
                let rtl = key_tree
                    .borrow()
                    .as_ref()
                    .and_then(NodeHandle::scene)
                    .is_some_and(|scene| {
                        scene.borrow().direction(cx.current_target) == Direction::Rtl
                    });
                let (open_key, close_key) = if rtl {
                    (Key::ArrowLeft, Key::ArrowRight)
                } else {
                    (Key::ArrowRight, Key::ArrowLeft)
                };
                // A move chooses the item alone; with Shift (and several
                // chosen), the rows from the anchor to it.
                let extend = modifiers.shift && selection.is_some();
                let go = |i: usize| {
                    let id = &rows[i].item.id;
                    if extend {
                        range(id, false);
                    } else {
                        alone(Some(id));
                    }
                    current(Some(id));
                };
                let next = at.map_or(0, |i| (i + 1).min(rows.len() - 1));
                let previous = at.map_or(0, |i| i.saturating_sub(1));
                let at_row = at.map(|i| &rows[i]);
                match key {
                    Key::ArrowDown => go(next),
                    Key::ArrowUp => go(previous),
                    // Several chosen: only the current item stays.
                    Key::Escape => {
                        let Some(many) = &selection else {
                            return;
                        };
                        let id = key_selected.with_untracked(Clone::clone);
                        let only = id.clone().map(|id| vec![id]).unwrap_or_default();
                        if many.with_untracked(|s| *s == only || s.is_empty()) {
                            return;
                        }
                        alone(id.as_deref());
                    }
                    Key::Home => go(0),
                    Key::End => go(rows.len() - 1),
                    k if *k == open_key => match at_row {
                        Some(r) if r.item.parent && !r.open => key_toggle(&r.item.id, Some(true)),
                        Some(r) if r.item.parent => {
                            if let Some(i) = at.filter(|i| i + 1 < rows.len()) {
                                go(i + 1);
                            }
                        }
                        _ => {}
                    },
                    k if *k == close_key => match at_row {
                        Some(r) if r.item.parent && r.open => key_toggle(&r.item.id, Some(false)),
                        Some(r) => {
                            if let Some(p) = r
                                .parent
                                .as_ref()
                                .and_then(|p| rows.iter().position(|x| x.item.id == *p))
                            {
                                go(p);
                            }
                        }
                        None => {}
                    },
                    Key::Enter => {
                        if let Some(r) = at_row.filter(|r| !r.loading) {
                            key_activate(&r.item.id);
                        }
                    }
                    Key::Character(typed)
                        if !(modifiers.meta || modifiers.control || modifiers.alt) =>
                    {
                        let mut search = search.borrow_mut();
                        if search.1.elapsed() > Duration::from_millis(750) {
                            search.0.clear();
                        }
                        search.0.push_str(&typed.to_lowercase());
                        search.1 = Instant::now();
                        let start = at.map_or(0, |i| {
                            if search.0.chars().count() == 1 {
                                i + 1
                            } else {
                                i
                            }
                        });
                        let n = rows.len();
                        if let Some(i) = (0..n).map(|k| (start + k) % n).find(|&k| {
                            !rows[k].loading
                                && rows[k].item.label.to_lowercase().starts_with(&search.0)
                        }) {
                            // Alone, whatever Shift typed.
                            alone(Some(&rows[i].item.id));
                            current(Some(&rows[i].item.id));
                        }
                    }
                    _ => return,
                }
                cx.prevent_default();
                cx.stop_propagation();
            })
            .child(list.h_full())
    })
}
