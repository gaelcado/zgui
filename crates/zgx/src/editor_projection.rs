//! What an editor shows of its text where it shows it otherwise than as it
//! is written (`EditorHandle::set_projector`): ranges hidden or shown as
//! other text (a Markdown draft's markers off the caret's line, a list's
//! bullet, a chip's label), faces over ranges (bold, italics, code), and
//! room before and after a range (a chip's icon well). The text stays as
//! written: its carets, hits and selections are of it, mapped through
//! what shows, as Zeron's composer maps its projection.
use crate::{
    rich_text::{Decoration, RichText, TextRun},
    scene::{Color, Rect},
    text_layout::{FontFamily, FontStyle, TextLayout, TextPosition},
};
use std::{ops::Range, rc::Rc};

/// How a range of an editor's text shows: what it sets over the editor's
/// own typography (later faces over earlier ones).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Face {
    /// Its weight (700 bold).
    pub weight: Option<u16>,
    /// Italic.
    pub italic: bool,
    /// Another family (inline code's monospace).
    pub family: Option<FontFamily>,
    /// Its text colour.
    pub color: Option<Color>,
    /// A line through it.
    pub strikethrough: bool,
    /// A wash behind it (inline code's), rounded by `radius`.
    pub background: Option<Color>,
    /// The wash's corner radius.
    pub radius: f32,
}
impl Face {
    fn apply(&self, run: &mut TextRun) {
        if let Some(weight) = self.weight {
            run.font.weight = weight;
        }
        if self.italic {
            run.font.italic = true;
        }
        if let Some(family) = &self.family {
            run.font.family = family.clone();
        }
        if let Some(color) = self.color {
            run.color = color;
        }
        if self.strikethrough {
            run.strikethrough = Some(Decoration::new(1.));
        }
        if let Some(background) = self.background {
            run.background = Some(background);
            run.radius = self.radius;
        }
    }
}

/// A range of the text shown as `text` instead (empty: hidden), with
/// `lead` points of room before what shows and `trail` after it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Replacement {
    /// Its bytes in the text.
    pub range: Range<usize>,
    /// What shows in their place.
    pub text: String,
    /// Room before it (a chip's icon well), in points.
    pub lead: f32,
    /// Room after it.
    pub trail: f32,
}
impl Replacement {
    /// `range` shown as `text`.
    pub fn new(range: Range<usize>, text: impl Into<String>) -> Self {
        Self {
            range,
            text: text.into(),
            lead: 0.,
            trail: 0.,
        }
    }
    /// `range` hidden.
    pub fn hidden(range: Range<usize>) -> Self {
        Self::new(range, "")
    }
}

/// What a projector gives for a text: its replacements (in order, apart)
/// and faces (over the text's bytes; they may overlap).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Projection {
    /// Ranges shown as other text, in order and apart.
    pub replacements: Vec<Replacement>,
    /// Faces over ranges of the text.
    pub faces: Vec<(Range<usize>, Face)>,
}

/// Asked for an editor's text and the lines the caret or selection is on
/// (their bytes, the active range): what shows of it. It is asked again only
/// when the text or the active lines change, so it must depend on nothing
/// but its arguments.
pub type Projector = Rc<dyn Fn(&str, Range<usize>) -> Projection>;

/// How a chip shows (`EditorHandle::set_chip_look`): the label in place of
/// its text (`None`: its text), and the icon painted in the well before
/// it (tinted as the editor's text).
#[derive(Clone, Debug, Default)]
pub struct ChipShown {
    /// What shows in place of its text.
    pub label: Option<String>,
    /// Painted in the well before the label.
    pub icon: Option<std::sync::Arc<crate::svg::SvgData>>,
    /// Not a chip after all (an amount, `$5`, or a path no one knows):
    /// it shows and deletes as plain text.
    pub plain: bool,
}
/// Asked for each chip's text (`@crates/zgx/src/lib.rs`), once for each
/// new one: how it shows (`None`: as its text, with no well).
pub type ChipLook = Rc<dyn Fn(&str) -> Option<ChipShown>>;
/// The well before a chip's label.
pub const CHIP_WELL: f32 = 20.;
/// The room after a chip's label.
pub const CHIP_TRAIL: f32 = 4.;
/// The icon in a chip's well.
pub const CHIP_ICON: f32 = 14.;

/// Edits an editor makes its own way for its text's structure (a Markdown
/// draft's lists, `EditorHandle::set_line_edits`). Either may decline,
/// leaving the key to the editor.
pub trait LineEdits {
    /// A line break typed at `at` (nothing selected): the range to replace
    /// and what with, instead of a bare break; the caret goes after it.
    fn newline(&self, text: &str, at: usize) -> Option<(Range<usize>, String)>;
    /// Tab, or Shift+Tab (`outdent`), with `selection`: the range to
    /// replace, its replacement, and the selection after.
    fn indent(
        &self,
        text: &str,
        selection: Range<usize>,
        outdent: bool,
    ) -> Option<(Range<usize>, String, Range<usize>)>;
}
/// Given pasted text before it goes in: what goes in instead (`None`: as
/// pasted). The paste stays one undo step.
pub type PasteFilter = Rc<dyn Fn(&str) -> Option<String>>;

/// Takes the room before and after a replacement: a character of no
/// width of its own, padded (`TextRun::padding`, both its sides).
const ROOM: &str = "\u{2060}";

/// A projection applied to a text: what shows, and the way between the
/// text's bytes and what shows.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Projected {
    /// The text it is of, and its active range.
    pub(crate) source: String,
    pub(crate) active: Range<usize>,
    /// What shows.
    pub(crate) display: String,
    /// Each replacement's bytes in the text and in what shows, in order.
    mappings: Vec<(Range<usize>, Range<usize>)>,
    /// Faces over what shows, and the padded room (its range, the pad a
    /// side).
    faces: Vec<(Range<usize>, Face)>,
    rooms: Vec<(Range<usize>, f32)>,
}
impl Projected {
    /// `projection` applied to `text` (`active`, the range it was asked
    /// for). Replacements out of order, overlapping one before them, or
    /// off character boundaries are left out.
    pub(crate) fn new(text: &str, active: Range<usize>, projection: Projection) -> Self {
        let mut out = Self {
            source: text.to_owned(),
            active,
            ..Default::default()
        };
        let mut at = 0;
        for r in projection.replacements {
            let range = r.range.start..r.range.end.min(text.len());
            if range.start < at
                || range.start > range.end
                || !text.is_char_boundary(range.start)
                || !text.is_char_boundary(range.end)
                || (range.is_empty() && r.text.is_empty())
            {
                continue;
            }
            out.display.push_str(&text[at..range.start]);
            let start = out.display.len();
            let pad = |room: f32| (room.is_finite() && room > 0.).then_some(room / 2.);
            if let Some(pad) = pad(r.lead) {
                out.rooms
                    .push((out.display.len()..out.display.len() + ROOM.len(), pad));
                out.display.push_str(ROOM);
            }
            out.display.push_str(&r.text);
            if let Some(pad) = pad(r.trail) {
                out.rooms
                    .push((out.display.len()..out.display.len() + ROOM.len(), pad));
                out.display.push_str(ROOM);
            }
            out.mappings.push((range.clone(), start..out.display.len()));
            at = range.end;
        }
        out.display.push_str(&text[at..]);
        let mut faces: Vec<_> = projection
            .faces
            .into_iter()
            .filter_map(|(range, face)| {
                let range = out.to_display(range.start)..out.to_display(range.end.min(text.len()));
                (range.start < range.end).then_some((range, face))
            })
            .collect();
        // In order of where they start; overlapping ones keep their order.
        faces.sort_by_key(|(range, _)| range.start);
        out.faces = faces;
        out
    }
    /// Whether it shows the text as written, as it is (nothing to map).
    pub(crate) fn is_plain(&self) -> bool {
        self.mappings.is_empty() && self.faces.is_empty()
    }
    /// Where byte `raw` of the text shows: a byte inside a replaced range
    /// at the start of what shows for it.
    pub(crate) fn to_display(&self, raw: usize) -> usize {
        let ix = self.mappings.partition_point(|(range, _)| range.end <= raw);
        if let Some((range, display)) = self.mappings.get(ix)
            && raw > range.start
        {
            return display.start;
        }
        let (raw_at, display_at) = ix
            .checked_sub(1)
            .map_or((0, 0), |p| (self.mappings[p].0.end, self.mappings[p].1.end));
        display_at + raw.saturating_sub(raw_at)
    }
    /// The text's byte for byte `display` of what shows: inside a
    /// replacement, its nearer end; hidden ranges where it is are passed
    /// together (a click before a word's first letter lands after the
    /// markers hidden before it).
    pub(crate) fn to_source(&self, display: usize) -> usize {
        let ix = self
            .mappings
            .partition_point(|(_, shown)| shown.end <= display);
        if let Some((range, shown)) = self.mappings.get(ix)
            && display > shown.start
        {
            return if display - shown.start < shown.len() / 2 {
                range.start
            } else {
                range.end
            };
        }
        let (raw_at, display_at) = ix
            .checked_sub(1)
            .map_or((0, 0), |p| (self.mappings[p].0.end, self.mappings[p].1.end));
        (raw_at + display.saturating_sub(display_at)).min(self.source.len())
    }
    /// The replaced ranges a caret steps over whole: those of more than
    /// one character that show as something other than their text.
    pub(crate) fn atomic(&self) -> impl Iterator<Item = Range<usize>> + '_ {
        self.mappings.iter().filter_map(|(range, shown)| {
            let raw = &self.source[range.clone()];
            (raw.chars().nth(1).is_some() && *raw != self.display[shown.clone()])
                .then(|| range.clone())
        })
    }
    /// Where a caret at `at` goes (moving forward or back): out of a range
    /// it steps over whole, to the end it moves toward.
    pub(crate) fn step(&self, at: usize, forward: bool) -> usize {
        self.atomic()
            .find(|r| r.start < at && at < r.end)
            .map_or(at, |r| if forward { r.end } else { r.start })
    }
    /// What shows, in runs: the editor's `color`, `size` and `font`, under
    /// the faces and, last, `colors` (a highlighter's, over the text's
    /// bytes).
    pub(crate) fn rich(
        &self,
        color: Color,
        size: f32,
        font: &FontStyle,
        colors: &[(Range<usize>, Color)],
    ) -> Option<RichText> {
        if self.display.is_empty() {
            return None;
        }
        let colors: Vec<(Range<usize>, Color)> = colors
            .iter()
            .filter_map(|(range, c)| {
                let range = self.to_display(range.start)..self.to_display(range.end);
                (range.start < range.end).then_some((range, *c))
            })
            .collect();
        let mut bounds = vec![0, self.display.len()];
        for (range, _) in &self.faces {
            bounds.extend([range.start, range.end]);
        }
        for (range, _) in &self.rooms {
            bounds.extend([range.start, range.end]);
        }
        for (range, _) in &colors {
            bounds.extend([range.start, range.end]);
        }
        bounds.retain(|&b| b <= self.display.len() && self.display.is_char_boundary(b));
        bounds.sort_unstable();
        bounds.dedup();
        let runs: Vec<TextRun> = bounds
            .windows(2)
            .map(|w| {
                let mut run = TextRun {
                    range: w[0]..w[1],
                    font: font.clone(),
                    font_size: size,
                    color,
                    ..Default::default()
                };
                for (range, face) in &self.faces {
                    if range.start <= w[0] && w[1] <= range.end {
                        face.apply(&mut run);
                    }
                }
                for (range, c) in &colors {
                    if range.start <= w[0] && w[1] <= range.end {
                        run.color = *c;
                    }
                }
                if let Some((_, pad)) = self.rooms.iter().find(|(range, _)| range.start == w[0]) {
                    run.padding = [*pad, 0.];
                    run.background = None;
                    run.strikethrough = None;
                }
                run
            })
            .collect();
        RichText::new(self.display.as_str(), runs).ok()
    }
}

/// A layout of what shows, its geometry of the text's bytes.
pub(crate) struct ProjectedLayout {
    pub(crate) shown: Rc<dyn TextLayout>,
    pub(crate) map: Rc<Projected>,
}
impl ProjectedLayout {
    fn position_in(&self, p: TextPosition) -> TextPosition {
        TextPosition {
            byte_offset: self.map.to_display(p.byte_offset),
            affinity: p.affinity,
        }
    }
    fn position_out(&self, p: TextPosition) -> TextPosition {
        TextPosition {
            byte_offset: self.map.to_source(p.byte_offset),
            affinity: p.affinity,
        }
    }
}
impl TextLayout for ProjectedLayout {
    fn cache_weight(&self) -> Option<usize> {
        self.shown.cache_weight().map(|w| {
            w.saturating_add(self.map.source.len())
                .saturating_add(self.map.display.len())
        })
    }
    fn size(&self) -> (f32, f32) {
        self.shown.size()
    }
    fn hit_test(&self, x: f32, y: f32) -> usize {
        self.map.to_source(self.shown.hit_test(x, y))
    }
    fn hit_position(&self, x: f32, y: f32) -> TextPosition {
        self.position_out(self.shown.hit_position(x, y))
    }
    fn caret(&self, byte_offset: usize) -> Rect {
        self.shown.caret(self.map.to_display(byte_offset))
    }
    fn caret_position(&self, position: TextPosition) -> Rect {
        self.shown.caret_position(self.position_in(position))
    }
    fn selection(&self, range: Range<usize>) -> Vec<Rect> {
        self.shown
            .selection(self.map.to_display(range.start)..self.map.to_display(range.end))
    }
    fn selection_within(&self, range: Range<usize>, top: f32, bottom: f32) -> Vec<Rect> {
        self.shown.selection_within(
            self.map.to_display(range.start)..self.map.to_display(range.end),
            top,
            bottom,
        )
    }
    fn carets_x(&self, offsets: &[usize]) -> Vec<f32> {
        let shown: Vec<usize> = offsets.iter().map(|&o| self.map.to_display(o)).collect();
        self.shown.carets_x(&shown)
    }
    fn visual_line_range(&self, position: TextPosition) -> (TextPosition, TextPosition) {
        let (start, end) = self.shown.visual_line_range(self.position_in(position));
        (self.position_out(start), self.position_out(end))
    }
    fn visual_line_edge(&self, position: TextPosition, end: bool) -> TextPosition {
        self.position_out(self.shown.visual_line_edge(self.position_in(position), end))
    }
}

/// The bytes of the lines `range` is on in `text` (from the start of the
/// first to the end of the last, its break left out).
pub(crate) fn lines_of(text: &str, range: Range<usize>) -> Range<usize> {
    let start = range.start.min(text.len());
    let end = range.end.clamp(start, text.len());
    let first = text[..start].rfind('\n').map_or(0, |i| i + 1);
    let last = text[end..].find('\n').map_or(text.len(), |i| end + i);
    first..last
}

#[cfg(test)]
mod tests {
    use super::*;

    fn bold() -> Face {
        Face {
            weight: Some(700),
            ..Default::default()
        }
    }

    #[test]
    fn hidden_markers_map_both_ways() {
        // "a **b** c": the markers hidden, "b" bold.
        let text = "a **b** c";
        let p = Projected::new(
            text,
            0..0,
            Projection {
                replacements: vec![Replacement::hidden(2..4), Replacement::hidden(5..7)],
                faces: vec![(2..7, bold())],
            },
        );
        assert_eq!(p.display, "a b c");
        assert_eq!(p.to_display(2), 2);
        assert_eq!(p.to_display(3), 2, "inside a hidden marker: where it was");
        assert_eq!(p.to_display(4), 2);
        assert_eq!(p.to_display(5), 3);
        assert_eq!(p.to_display(7), 3);
        assert_eq!(p.to_display(9), 5);
        // Before "b": after the opening markers.
        assert_eq!(p.to_source(2), 4);
        assert_eq!(p.to_source(3), 7, "after it: after the closing markers");
        assert_eq!(p.to_source(5), 9);
        let rich = p
            .rich(Color(0, 0, 0, 255), 14., &FontStyle::default(), &[])
            .unwrap();
        let b = rich.runs().iter().find(|r| r.range == (2..3)).unwrap();
        assert_eq!(b.font.weight, 700);
        assert!(
            rich.runs()
                .iter()
                .filter(|r| r.range != (2..3))
                .all(|r| r.font.weight == 400)
        );
        // Stepped over whole (though the caret's own line shows them).
        assert_eq!(p.atomic().count(), 2);
    }

    #[test]
    fn a_label_steps_whole_and_its_room_pads() {
        let text = "see @crates/lib.rs now";
        let mut chip = Replacement::new(4..18, "lib.rs");
        chip.lead = 20.;
        chip.trail = 4.;
        let p = Projected::new(
            text,
            0..0,
            Projection {
                replacements: vec![chip],
                faces: vec![],
            },
        );
        assert_eq!(p.display, format!("see {ROOM}lib.rs{ROOM} now"));
        assert_eq!(p.step(9, true), 18);
        assert_eq!(p.step(9, false), 4);
        assert_eq!(p.step(18, true), 18);
        // A hit inside the label: its nearer end.
        assert_eq!(p.to_source(5), 4);
        assert_eq!(p.to_source(4 + ROOM.len() + 5), 18);
        let rich = p
            .rich(Color(0, 0, 0, 255), 14., &FontStyle::default(), &[])
            .unwrap();
        let pads: Vec<f32> = rich.runs().iter().map(|r| r.padding[0]).collect();
        assert!(pads.contains(&10.) && pads.contains(&2.), "{pads:?}");
        let layout = ProjectedLayout {
            shown: Rc::new(crate::text_layout::FallbackTextLayout::with_rich(
                &rich, None,
            )),
            map: Rc::new(p),
        };
        // The label stands 20 further right than its letters would, and 4
        // more before what follows it.
        let plain = 14. * 0.6;
        assert!((layout.caret(18).x - (4. * plain + 20. + 6. * plain + 4.)).abs() < 0.01);
        assert!((layout.caret(19).x - layout.caret(18).x - plain).abs() < 0.01);
        assert_eq!(layout.hit_test(layout.caret(18).x + plain * 0.6, 1.), 19);
    }

    #[test]
    fn a_bullet_stays_one_character_and_editable() {
        let text = "- one";
        let p = Projected::new(
            text,
            0..0,
            Projection {
                replacements: vec![Replacement::new(0..1, "•")],
                faces: vec![],
            },
        );
        assert_eq!(p.display, "• one");
        assert_eq!(p.to_display(1), "•".len());
        assert_eq!(p.to_source("•".len()), 1);
        assert_eq!(p.atomic().count(), 0);
    }

    #[test]
    fn highlight_colours_win_over_faces() {
        let code = Face {
            color: Some(Color(1, 1, 1, 255)),
            family: Some(FontFamily::Monospace),
            ..Default::default()
        };
        let p = Projected::new(
            "x `ab` y",
            0..0,
            Projection {
                replacements: vec![],
                faces: vec![(2..6, code)],
            },
        );
        let rich = p
            .rich(
                Color(0, 0, 0, 255),
                14.,
                &FontStyle::default(),
                &[(3..4, Color(9, 9, 9, 255))],
            )
            .unwrap();
        let a = rich.runs().iter().find(|r| r.range == (3..4)).unwrap();
        assert_eq!(a.color, Color(9, 9, 9, 255));
        assert_eq!(a.font.family, FontFamily::Monospace);
    }

    #[test]
    fn the_active_range_is_whole_lines() {
        assert_eq!(lines_of("ab\ncd\nef", 4..4), 3..5);
        assert_eq!(lines_of("ab\ncd\nef", 1..7), 0..8);
        assert_eq!(lines_of("", 0..0), 0..0);
    }
}
