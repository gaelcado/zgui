//! A numbered editor's gutter as review comments use it
//! (`View::gutter_marks`, `on_gutter_press`, `gutter_card`):
//! marked lines show a glyph on a well in their numbers' place, the line
//! under the pointer is offered a plate to press, a press on a cell is
//! told with its line (and its mark), and a card sits under a line. Marks
//! are held as anchors in the editing model (`TextEditor::set_anchors`),
//! so they follow their lines through edits. The plate follows the pointer
//! in the engine alone, and the card the scroll.
use crate::{
    compose::{Environment, View},
    input::{EventContext, EventPhase, InputEvent, PointerButton},
    scene::{Color, NodeId, NodeKind, QuadStyle, Rect, Scene, Transform},
    semantics::{Role, SemanticNode, Semantics},
    svg::SvgData,
    text_edit::TextEditor,
    widgets::{EditorHandle, Ui, fixed},
};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
    sync::Arc,
};

/// The plate offered under the pointer: its size, corners and glyph.
pub const PLATE: f32 = 16.;
const PLATE_RADIUS: f32 = 4.;
const PLATE_ICON: f32 = 11.;
/// A mark's glyph.
const MARK_ICON: f32 = 10.5;
/// The card under a line (Zeron's comment card): its widest.
pub const CARD_WIDTH: f32 = 320.;
/// The card's margin from the view's edges.
pub const CARD_MARGIN: f32 = 8.;
/// The narrowest the card is beside the gutter before it takes the view's
/// width instead.
pub const CARD_MIN_ANCHORED_WIDTH: f32 = 220.;

/// A marked line: what marks it, and the line, from 1.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GutterMark {
    /// What the app knows it by (a comment's id).
    pub id: String,
    /// Its line, from 1.
    pub line: usize,
}

/// How a gutter's marks and plate look: a mark's glyph in `mark_color` on
/// a well of `mark_fill` filling its cell; the plate `add_fill`, its glyph
/// `add_color`. Without `add`, no plate is offered.
#[derive(Clone, Debug)]
pub struct GutterLook {
    /// A marked line's glyph (an SVG, tinted).
    pub mark: Option<Arc<SvgData>>,
    /// The mark's glyph's colour.
    pub mark_color: Color,
    /// The well behind a mark's glyph, its cell's size.
    pub mark_fill: Color,
    /// The plate's glyph (an SVG, tinted).
    pub add: Option<Arc<SvgData>>,
    /// The plate's glyph's colour.
    pub add_color: Color,
    /// The plate.
    pub add_fill: Color,
}
impl PartialEq for GutterLook {
    fn eq(&self, other: &Self) -> bool {
        let same = |a: &Option<Arc<SvgData>>, b: &Option<Arc<SvgData>>| match (a, b) {
            (Some(a), Some(b)) => Arc::ptr_eq(a, b) || a == b,
            (None, None) => true,
            _ => false,
        };
        same(&self.mark, &other.mark)
            && same(&self.add, &other.add)
            && (
                self.mark_color,
                self.mark_fill,
                self.add_color,
                self.add_fill,
            ) == (
                other.mark_color,
                other.mark_fill,
                other.add_color,
                other.add_fill,
            )
    }
}
/// A look, with its glyphs tinted once.
struct Look {
    given: GutterLook,
    mark: Option<Arc<SvgData>>,
    add: Option<Arc<SvgData>>,
}
/// What a press on a cell tells: its line, and the mark's id on it.
type Press = Box<dyn FnMut(usize, Option<&str>)>;
/// What an edit moving marks tells: all of them, as they now are.
type Moved = Box<dyn FnMut(&[GutterMark])>;

/// Where the gutter was last drawn: its node, its cells' width and height,
/// where the view (gutter and text) starts in the editor's root and its
/// size.
#[derive(Clone, Copy, Default)]
struct Geometry {
    gutter: Option<NodeId>,
    width: f32,
    row: f32,
    origin: (f32, f32),
    view: (f32, f32),
}

/// What an editor's gutter adds (`EditorHandle::set_gutter_marks`, …),
/// made when first used.
#[derive(Default)]
pub(crate) struct Gutter {
    /// The marks' ids, each the editing model's anchor at its index.
    ids: RefCell<Vec<String>>,
    /// The lines of those given past the text's end, taken up as the text
    /// grows to them (a file arriving after its comments).
    wanted: RefCell<Vec<Option<usize>>>,
    pending: Cell<bool>,
    /// The marks' lines (from 1) for the text's revision, and those last
    /// told or given.
    lines: RefCell<Vec<usize>>,
    lines_for: Cell<Option<u64>>,
    told: RefCell<Vec<usize>>,
    look: RefCell<Option<Look>>,
    label: RefCell<String>,
    on_press: RefCell<Option<Press>>,
    pressed: Cell<bool>,
    on_move: RefCell<Option<Moved>>,
    /// The lines in view as last drawn, and where each cell's top is.
    cells: RefCell<Vec<(usize, f32)>>,
    geometry: Cell<Geometry>,
    /// A marked line's well and glyph in view, each.
    marks: RefCell<Vec<(NodeId, NodeId)>>,
    /// What presses and assistive technology reach: a cell's node, its
    /// line and whether it shows a mark with its card open; those of the
    /// draw before.
    targets: RefCell<Vec<(NodeId, usize, Option<bool>)>>,
    targets_was: RefCell<Vec<(NodeId, usize, Option<bool>)>>,
    /// The plate and its glyph, made as the pointer first comes; the line
    /// it is on, and the number hidden under it.
    plate: Cell<Option<(NodeId, NodeId)>>,
    hover: Cell<Option<usize>>,
    covered: Cell<Option<NodeId>>,
    /// The card under a line: its box, the line, and where it was placed
    /// (x, y, width, shown).
    card: Cell<Option<NodeId>>,
    card_line: Cell<Option<usize>>,
    card_placed: Cell<Option<(f32, f32, f32, bool)>>,
}

impl Gutter {
    /// The marks' lines (from 1), found again only when the text changed.
    pub(crate) fn lines(&self, e: &TextEditor) -> std::cell::Ref<'_, Vec<usize>> {
        if self.lines_for.get() != Some(e.revision()) {
            let mut lines = self.lines.borrow_mut();
            lines.clear();
            lines.extend(e.anchors().iter().map(|at| e.line_of(*at) + 1));
            self.lines_for.set(Some(e.revision()));
        }
        self.lines.borrow()
    }
    /// Mark `marks`' lines: a mark already on its line keeps its anchor
    /// (an app giving back what `on_move` told); the rest start at their
    /// line's start. False when they are as they were.
    pub(crate) fn set_marks(&self, e: &mut TextEditor, marks: &[GutterMark]) -> bool {
        let current = self.lines(e).clone();
        {
            let ids = self.ids.borrow();
            if ids.len() == marks.len()
                && marks
                    .iter()
                    .zip(ids.iter().zip(&current))
                    .all(|(mark, (id, line))| *id == mark.id && *line == mark.line)
            {
                return false;
            }
        }
        let count = e.line_of(e.len()) + 1;
        let anchors: Vec<usize> = {
            let ids = self.ids.borrow();
            marks
                .iter()
                .map(|mark| {
                    let kept = ids
                        .iter()
                        .position(|id| *id == mark.id)
                        .filter(|i| current.get(*i) == Some(&mark.line));
                    match kept {
                        Some(i) => e.anchors()[i],
                        None => e.line_start(mark.line.max(1) - 1),
                    }
                })
                .collect()
        };
        e.set_anchors(anchors);
        *self.ids.borrow_mut() = marks.iter().map(|m| m.id.clone()).collect();
        *self.wanted.borrow_mut() = marks
            .iter()
            .map(|m| (m.line > count).then_some(m.line))
            .collect();
        self.pending.set(marks.iter().any(|m| m.line > count));
        self.lines_for.set(None);
        let lines = self.lines(e).clone();
        *self.told.borrow_mut() = lines;
        true
    }
    /// Marks given past the text's end start at their lines once the text
    /// has them (its file arriving after its comments). Whether any did.
    pub(crate) fn settle(&self, editor: &RefCell<TextEditor>) -> bool {
        if !self.pending.get() {
            return false;
        }
        let Ok(mut e) = editor.try_borrow_mut() else {
            return false;
        };
        let count = e.line_of(e.len()) + 1;
        let mut wanted = self.wanted.borrow_mut();
        let mut anchors = e.anchors().to_vec();
        let mut moved = false;
        let mut pending = false;
        for (at, line) in anchors.iter_mut().zip(wanted.iter_mut()) {
            match *line {
                Some(want) if want > count => pending = true,
                Some(want) => {
                    *at = e.line_start(want - 1);
                    *line = None;
                    moved = true;
                }
                None => {}
            }
        }
        self.pending.set(pending);
        if moved {
            e.set_anchors(anchors);
            self.lines_for.set(None);
            let lines = self.lines(&e).clone();
            *self.told.borrow_mut() = lines;
        }
        moved
    }
    /// The marks, as they now are.
    pub(crate) fn marks_now(&self, e: &TextEditor) -> Vec<GutterMark> {
        let lines = self.lines(e);
        self.ids
            .borrow()
            .iter()
            .zip(lines.iter())
            .map(|(id, line)| GutterMark {
                id: id.clone(),
                line: *line,
            })
            .collect()
    }
    /// Tell `on_move` the marks if an edit moved any off its line since
    /// they were last told or given (nothing borrowed: it may do as it
    /// likes; out of its slot while it runs).
    pub(crate) fn tell(&self, editor: &RefCell<TextEditor>) {
        let marks = {
            let Ok(e) = editor.try_borrow() else {
                return;
            };
            let lines = self.lines(&e);
            if *lines == *self.told.borrow() {
                return;
            }
            *self.told.borrow_mut() = lines.clone();
            drop(lines);
            self.marks_now(&e)
        };
        let Some(mut told) = self.on_move.borrow_mut().take() else {
            return;
        };
        told(&marks);
        let mut slot = self.on_move.borrow_mut();
        if slot.is_none() {
            *slot = Some(told);
        }
    }
    pub(crate) fn set_look(&self, look: Option<GutterLook>) -> bool {
        let mut current = self.look.borrow_mut();
        if current.as_ref().map(|l| &l.given) == look.as_ref() {
            return false;
        }
        *current = look.map(|given| Look {
            mark: given
                .mark
                .as_ref()
                .map(|svg| Arc::new(svg.tinted(given.mark_color))),
            add: given
                .add
                .as_ref()
                .map(|svg| Arc::new(svg.tinted(given.add_color))),
            given,
        });
        true
    }
    pub(crate) fn set_label(&self, label: &str) -> bool {
        if *self.label.borrow() == label {
            return false;
        }
        *self.label.borrow_mut() = label.to_owned();
        // Named anew: every cell's name is set again.
        self.targets_was.borrow_mut().clear();
        true
    }
    pub(crate) fn on_press(&self, told: Press) {
        *self.on_press.borrow_mut() = Some(told);
        self.pressed.set(true);
        self.targets_was.borrow_mut().clear();
    }
    pub(crate) fn on_move(&self, told: Moved) {
        *self.on_move.borrow_mut() = Some(told);
    }
    pub(crate) fn set_card(&self, node: Option<NodeId>) {
        self.card.set(node);
        self.card_placed.set(None);
    }
    pub(crate) fn set_card_line(&self, line: Option<usize>) -> bool {
        self.card_line.replace(line) != line
    }
    /// Lay the gutter out for a draw: the lines in view (`shown`, each
    /// line from 1 and its top), its cells' size and where the view is.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn lay(
        &self,
        e: &TextEditor,
        gutter: NodeId,
        shown: &[(usize, f32)],
        width: f32,
        row: f32,
        origin: (f32, f32),
        view: (f32, f32),
    ) {
        drop(self.lines(e));
        let mut cells = self.cells.borrow_mut();
        cells.clear();
        cells.extend_from_slice(shown);
        self.geometry.set(Geometry {
            gutter: Some(gutter),
            width,
            row,
            origin,
            view,
        });
    }
    /// Whether `line` (from 1) is marked, as last found.
    pub(crate) fn marked(&self, line: usize) -> bool {
        self.lines.borrow().contains(&line)
    }
    /// The line numbers drawn (each node and its line): what a press on
    /// one tells, and what assistive technology finds there.
    pub(crate) fn numbered(&self, numbers: impl Iterator<Item = (NodeId, usize)>) {
        let mut targets = self.targets.borrow_mut();
        targets.clear();
        targets.extend(numbers.map(|(id, line)| (id, line, None)));
    }
    /// Draw the marks in view, the plate and the card, and name the cells
    /// (after `lay` and `numbered`).
    pub(crate) fn draw(&self, s: &mut Scene, semantics: &mut Semantics) {
        let geometry = self.geometry.get();
        let Some(gutter) = geometry.gutter.filter(|g| s.contains(*g)) else {
            return;
        };
        let look = self.look.borrow();
        let cells = self.cells.borrow();
        let lines = self.lines.borrow();
        let open = self.card_line.get();
        let mut drawn = self.marks.borrow_mut();
        let mut targets = self.targets.borrow_mut();
        let marked = cells.iter().filter(|(line, _)| lines.contains(line));
        let mut count = 0;
        for (line, y) in marked {
            if drawn.len() <= count {
                let well = s.append(gutter, NodeKind::Rect(Color(0, 0, 0, 0)), fixed(0., 0.));
                let glyph = s.append(gutter, NodeKind::Rect(Color(0, 0, 0, 0)), fixed(0., 0.));
                drawn.push((well, glyph));
            }
            let (well, glyph) = drawn[count];
            count += 1;
            let fill = look
                .as_ref()
                .map_or(Color(0, 0, 0, 0), |l| l.given.mark_fill);
            if !matches!(s.kind(well), NodeKind::Rect(c) if *c == fill) {
                s.set_kind(well, NodeKind::Rect(fill));
            }
            s.set_style(well, fixed(geometry.width, geometry.row));
            s.set_transform(well, Transform { x: 0., y: *y });
            match look.as_ref().and_then(|l| l.mark.clone()) {
                Some(icon) => {
                    if !matches!(s.kind(glyph), NodeKind::Svg(svg) if Arc::ptr_eq(svg, &icon)) {
                        s.set_kind(glyph, NodeKind::Svg(icon));
                    }
                    s.set_style(glyph, fixed(MARK_ICON, MARK_ICON));
                }
                None => s.set_style(glyph, fixed(0., 0.)),
            }
            s.set_transform(
                glyph,
                Transform {
                    x: (geometry.width - MARK_ICON) / 2.,
                    y: y + (geometry.row - MARK_ICON) / 2.,
                },
            );
            targets.push((well, *line, Some(open == Some(*line))));
        }
        while drawn.len() > count {
            let (well, glyph) = drawn.pop().unwrap();
            semantics.remove(well);
            s.remove(well);
            s.remove(glyph);
        }
        drop((drawn, lines, cells, look));
        // Each cell a button to assistive technology, named anew only when
        // its line or its card changed.
        let mut was = self.targets_was.borrow_mut();
        if self.pressed.get() {
            let label = self.label.borrow();
            for &(id, line, open) in targets.iter() {
                if was.contains(&(id, line, open)) && semantics.get(id).is_some() {
                    continue;
                }
                let mut node = SemanticNode::new(Role::Button, cell_name(&label, line, open));
                node.expanded = open;
                semantics.set(id, node);
            }
        }
        std::mem::swap(&mut *was, &mut *targets);
        drop((was, targets));
        self.place_plate(s);
        self.place_card(s);
    }
    /// Take the gutter away (its editor no longer numbered).
    pub(crate) fn clear(&self, s: &mut Scene, semantics: &mut Semantics) {
        self.cells.borrow_mut().clear();
        self.hover.set(None);
        for (well, glyph) in self.marks.borrow_mut().drain(..) {
            semantics.remove(well);
            s.remove(well);
            s.remove(glyph);
        }
        self.targets_was.borrow_mut().clear();
        self.place_plate(s);
        self.place_card(s);
    }
    /// The line (from 1) of the cell under window point `(x, y)`.
    fn line_at(&self, s: &Scene, x: f32, y: f32) -> Option<usize> {
        let geometry = self.geometry.get();
        let gutter = geometry.gutter.filter(|g| s.contains(*g))?;
        let at = s.bounds(gutter);
        let (x, y) = s.point_in(gutter, x, y).unwrap_or((x, y));
        let (x, y) = (x - at.x, y - at.y);
        if !(0. ..geometry.width).contains(&x) || !(0. ..at.height).contains(&y) {
            return None;
        }
        self.cells
            .borrow()
            .iter()
            .find(|(_, top)| (*top..top + geometry.row).contains(&y))
            .map(|(line, _)| *line)
    }
    /// Where line `line`'s cell is (from 1), in the window's points, while
    /// it is in view.
    pub(crate) fn cell(&self, s: &Scene, line: usize) -> Option<Rect> {
        let geometry = self.geometry.get();
        let gutter = geometry.gutter.filter(|g| s.contains(*g))?;
        let (_, y) = *self.cells.borrow().iter().find(|(l, _)| *l == line)?;
        let at = s.transformed_bounds(gutter);
        Some(Rect::new(at.x, at.y + y, geometry.width, geometry.row))
    }
    fn offers(&self) -> bool {
        self.look.borrow().as_ref().is_some_and(|l| l.add.is_some())
    }
    fn hover_to(&self, s: &mut Scene, line: Option<usize>) {
        if self.hover.get() != line {
            self.hover.set(line);
            self.place_plate(s);
        }
    }
    /// The plate on the hovered line's cell, over its number; hidden
    /// (transparent) while none is.
    fn place_plate(&self, s: &mut Scene) {
        if let Some(number) = self.covered.take()
            && s.contains(number)
        {
            set_opacity(s, number, 1.);
        }
        let geometry = self.geometry.get();
        let at = self.hover.get().and_then(|line| {
            let cells = self.cells.borrow();
            let (_, y) = cells.iter().find(|(l, _)| *l == line)?;
            Some((line, *y))
        });
        let look = self.look.borrow();
        let plate = self
            .plate
            .get()
            .filter(|(plate, glyph)| s.contains(*plate) && s.contains(*glyph));
        let (Some((line, y)), Some(look), Some(gutter)) = (
            at,
            look.as_ref().filter(|l| l.add.is_some()),
            geometry.gutter.filter(|g| s.contains(*g)),
        ) else {
            if let Some((plate, glyph)) = plate {
                set_opacity(s, plate, 0.);
                set_opacity(s, glyph, 0.);
            }
            return;
        };
        let (plate, glyph) = plate.unwrap_or_else(|| {
            let plate = s.append(
                gutter,
                NodeKind::Rect(Color(0, 0, 0, 0)),
                fixed(PLATE, PLATE),
            );
            let glyph = s.append(gutter, NodeKind::Rect(Color(0, 0, 0, 0)), fixed(0., 0.));
            self.plate.set(Some((plate, glyph)));
            (plate, glyph)
        });
        // Over what is drawn in the gutter since (a mark made after it).
        if s.children(gutter).last() != Some(&glyph) {
            let mut order = s.children(gutter).to_vec();
            order.retain(|id| *id != plate && *id != glyph);
            order.extend([plate, glyph]);
            s.reorder_children(gutter, &order);
        }
        let kind = NodeKind::Quad(QuadStyle {
            fill: look.given.add_fill,
            radius: PLATE_RADIUS,
            border_color: Color(0, 0, 0, 0),
            border_width: 0.,
            shadow: None,
            decoration: None,
            border_over: false,
            outline: None,
        });
        if *s.kind(plate) != kind {
            s.set_kind(plate, kind);
        }
        let icon = look.add.clone().unwrap();
        if !matches!(s.kind(glyph), NodeKind::Svg(svg) if Arc::ptr_eq(svg, &icon)) {
            s.set_kind(glyph, NodeKind::Svg(icon));
        }
        s.set_style(glyph, fixed(PLATE_ICON, PLATE_ICON));
        let (x, y) = (
            (geometry.width - PLATE) / 2.,
            y + (geometry.row - PLATE) / 2.,
        );
        s.set_transform(plate, Transform { x, y });
        s.set_transform(
            glyph,
            Transform {
                x: x + (PLATE - PLATE_ICON) / 2.,
                y: y + (PLATE - PLATE_ICON) / 2.,
            },
        );
        set_opacity(s, plate, 1.);
        set_opacity(s, glyph, 1.);
        // The line's number, under the plate, goes while it shows.
        let number = self
            .targets_was
            .borrow()
            .iter()
            .find(|(_, l, open)| *l == line && open.is_none())
            .map(|(id, ..)| *id);
        if let Some(number) = number {
            set_opacity(s, number, 0.);
            self.covered.set(Some(number));
        }
    }
    /// The card under its line, kept in the view (Zeron's comment card):
    /// beside the gutter `CARD_WIDTH` wide at most, or the view's width
    /// within its margins where that would be under
    /// `CARD_MIN_ANCHORED_WIDTH`; under its line's cell, held inside the
    /// view by its height as last laid out; hidden while its line is out
    /// of view.
    pub(crate) fn place_card(&self, s: &mut Scene) {
        let Some(card) = self.card.get().filter(|c| s.contains(*c)) else {
            return;
        };
        let geometry = self.geometry.get();
        let top = self.card_line.get().and_then(|line| {
            let cells = self.cells.borrow();
            cells
                .iter()
                .find(|(l, _)| *l == line)
                .map(|(_, y)| y + geometry.row)
        });
        let (left, width) = card_span(geometry.width, geometry.view.0);
        let placed = match top {
            Some(top) => {
                let height = s.bounds(card).height;
                let top = top.clamp(0., (geometry.view.1 - height).max(0.));
                (
                    geometry.origin.0 + left,
                    geometry.origin.1 + top,
                    width,
                    true,
                )
            }
            None => self
                .card_placed
                .get()
                .map_or((0., 0., width, false), |p| (p.0, p.1, p.2, false)),
        };
        if self.card_placed.replace(Some(placed)) == Some(placed) {
            return;
        }
        let (x, y, width, shown) = placed;
        let mut style = s.style(card);
        let visible = (!shown).then_some(false);
        if style.width != Some(width)
            || style.layout_options.as_ref().and_then(|o| o.visible) != visible
        {
            style.absolute = true;
            style.width = Some(width);
            let mut options = style.layout_options.as_deref().copied().unwrap_or_default();
            options.visible = visible;
            style.layout_options = Some(Arc::new(options));
            s.set_style(card, style);
        }
        s.set_transform(card, Transform { x, y });
    }
    /// A pointer event reaching the editor's root (any phase): the plate
    /// follows the pointer over the cells, and goes as it leaves, presses
    /// or scrolls; a primary press on a cell (or assistive technology
    /// pressing one) is told. `busy`: the pointer drags a selection.
    /// Whether it took the event.
    pub(crate) fn event(
        &self,
        cx: &mut EventContext,
        scene: &Rc<RefCell<Scene>>,
        root: NodeId,
        busy: bool,
    ) -> bool {
        match cx.event {
            InputEvent::PointerMove { x, y } => {
                if cx.phase == EventPhase::Capture {
                    return false;
                }
                let line = if cx.target == root && !busy && self.offers() {
                    self.line_at(&scene.borrow(), x, y)
                        .filter(|line| !self.marked(*line))
                } else {
                    None
                };
                if self.hover.get() != line {
                    self.hover_to(&mut scene.borrow_mut(), line);
                }
                false
            }
            InputEvent::PointerLeave | InputEvent::Scroll { .. } | InputEvent::PointerCancel
                if self.hover.get().is_some() =>
            {
                if !matches!(cx.event, InputEvent::PointerLeave) || cx.target == root {
                    self.hover_to(&mut scene.borrow_mut(), None);
                }
                false
            }
            InputEvent::PointerDown { x, y, button } => {
                if self.hover.get().is_some() {
                    self.hover_to(&mut scene.borrow_mut(), None);
                }
                if button != PointerButton::Primary
                    || cx.phase != EventPhase::Target
                    || cx.default_prevented()
                    || self.on_press.borrow().is_none()
                {
                    return false;
                }
                let Some(line) = self.line_at(&scene.borrow(), x, y) else {
                    return false;
                };
                cx.prevent_default();
                cx.stop_propagation();
                self.press(line);
                true
            }
            InputEvent::Activate if cx.target != root && cx.phase == EventPhase::Bubble => {
                let line = self
                    .targets_was
                    .borrow()
                    .iter()
                    .find(|(id, ..)| *id == cx.target)
                    .map(|(_, line, _)| *line);
                let Some(line) = line else {
                    return false;
                };
                cx.prevent_default();
                cx.stop_propagation();
                self.press(line);
                true
            }
            _ => false,
        }
    }
    /// Tell `on_press` of a press on `line`'s cell, with its mark's id.
    fn press(&self, line: usize) {
        let id = {
            let lines = self.lines.borrow();
            lines
                .iter()
                .position(|l| *l == line)
                .and_then(|i| self.ids.borrow().get(i).cloned())
        };
        let Some(mut told) = self.on_press.borrow_mut().take() else {
            return;
        };
        told(line, id.as_deref());
        let mut slot = self.on_press.borrow_mut();
        if slot.is_none() {
            *slot = Some(told);
        }
    }
}

fn set_opacity(s: &mut Scene, id: NodeId, opacity: f32) {
    let mut effects = s.effects(id);
    if effects.opacity != opacity {
        effects.opacity = opacity;
        s.set_effects(id, effects);
    }
}

/// Where the card goes across a view `view` wide beside a gutter `gutter`
/// wide: its left and width.
pub fn card_span(gutter: f32, view: f32) -> (f32, f32) {
    let left = (gutter - CARD_MARGIN).max(CARD_MARGIN);
    let width = (view - left - CARD_MARGIN).clamp(0., CARD_WIDTH);
    if width >= CARD_MIN_ANCHORED_WIDTH {
        (left, width)
    } else {
        (CARD_MARGIN, (view - CARD_MARGIN * 2.).max(0.))
    }
}

/// What assistive technology calls a cell (`label` the gutter's noun,
/// "Comment"): a mark "Open comment on line 12", any other cell "Comment
/// on line 12".
fn cell_name(label: &str, line: usize, mark: Option<bool>) -> String {
    let label = if label.is_empty() { "Mark" } else { label };
    if mark.is_none() {
        return format!("{label} on line {line}");
    }
    // A capitalised word goes on in lower case ("Comment"), an acronym or
    // a name as it is ("PR note").
    let mut chars = label.chars();
    let noun = match (chars.next(), chars.next()) {
        (Some(first), Some(second)) if first.is_uppercase() && second.is_lowercase() => first
            .to_lowercase()
            .chain(label[first.len_utf8()..].chars())
            .collect(),
        _ => label.to_owned(),
    };
    format!("Open {noun} on line {line}")
}

/// What `View::gutter_marks` and the rest give an editor.
#[derive(Default)]
pub(crate) struct GutterOptions {
    pub(crate) marks: Option<Box<dyn FnMut() -> Vec<GutterMark>>>,
    pub(crate) look: Option<Box<dyn FnMut() -> GutterLook>>,
    pub(crate) label: Option<String>,
    pub(crate) on_press: Option<Press>,
    pub(crate) on_move: Option<Moved>,
    pub(crate) card: Option<(View, CardLine)>,
}
/// The line a card goes under (`View::gutter_card`).
type CardLine = Box<dyn FnMut() -> Option<usize>>;

/// Give `editor` (mounted at `root`) its gutter's options: marks, look
/// and label kept current as what they read changes; the card mounted
/// into the editor's root once, under its line.
pub(crate) fn mount(
    ui: &mut Ui,
    root: NodeId,
    editor: EditorHandle,
    options: GutterOptions,
    environment: Environment,
) {
    let GutterOptions {
        marks,
        look,
        label,
        on_press,
        on_move,
        card,
    } = options;
    editor.set_gutter_label(label.as_deref().unwrap_or("Comment"));
    if let Some(told) = on_press {
        editor.on_gutter_press(told);
    }
    if let Some(told) = on_move {
        editor.on_gutter_move(told);
    }
    // The theme's colours unless given (a theme's change draws them anew).
    let mut look = look.unwrap_or_else(|| {
        let theme = environment.theme.clone();
        Box::new(move || GutterLook {
            mark: None,
            mark_color: theme.color(crate::theme::tok::TEXT_SECONDARY),
            mark_fill: theme.color(crate::theme::tok::SURFACE_RAISED),
            add: None,
            add_color: theme.color(crate::theme::tok::ACCENT_TEXT),
            add_fill: theme.color(crate::theme::tok::ACCENT),
        })
    });
    {
        let editor = editor.clone();
        ui.bind(root, move || editor.set_gutter_look(Some(look())));
    }
    if let Some(mut marks) = marks {
        let editor = editor.clone();
        ui.bind(root, move || editor.set_gutter_marks(&marks()));
    }
    let Some((view, mut line)) = card else {
        return;
    };
    // The card's box: out of the editor's flow, hidden until placed. A
    // press on it that nothing in it takes focuses it (out of Tab's way),
    // not the editor; the editor leaves alone what targets it.
    let mut style = fixed(CARD_WIDTH, 0.);
    style.height = None;
    style.absolute = true;
    style.layout_options = Some(Arc::new(crate::layout::LayoutOptions {
        visible: Some(false),
        ..Default::default()
    }));
    let card = ui.container(root, crate::scene::Layout::Column, style);
    ui.on_event(card, true, |_| {});
    let mut input = ui.input.options(card).unwrap_or_default();
    input.tab_index = -1;
    ui.input.set_options(card, input);
    crate::compose::mount(ui, card, view, environment);
    editor.set_gutter_card(Some(card));
    {
        let editor = editor.clone();
        ui.bind(root, move || editor.set_gutter_card_line(line()));
    }
    // Its height laid out anew (what it holds changed): placed again.
    let placed = editor.clone();
    let height = Cell::new(f32::NAN);
    ui.on_layout(
        card,
        Box::new(move || {
            let now = placed.scene_bounds(card).height;
            if height.replace(now) != now {
                placed.place_gutter_card();
            }
        }),
    );
}
