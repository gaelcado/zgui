//! Streaming text fading in (`View::veil`): as a paragraph's text grows,
//! what was appended fades from clear to its colour, a chunk at a time, as
//! a chat's reply arrives. Each chunk fades over three times the gap
//! between chunks (an average: 120 to 400 ms), on an ease out, faster while
//! several overlap. Only colours change, so the paragraph keeps its layout
//! and its shaped glyphs (a recolour), and the frames stop once every
//! chunk has settled.
//!
//! A view keeps its veil while it lives; a veil with a key outlives it, so a
//! paragraph rebuilt as its text grows (a streamed block drawn again) fades
//! only what it gained. A key seen for the first time fades its whole text:
//! text that should show at once is given no veil.
use crate::rich_text::{RichText, TextRun};
use crate::scene::Color;
use std::{
    cell::RefCell,
    collections::{HashMap, VecDeque},
    ops::Range,
    rc::Rc,
    sync::Arc,
    time::Instant,
};

/// The first gap between chunks assumed, before two have arrived.
const SEED_MS: f32 = 160.;
const MIN_FADE_MS: f32 = 120.;
const MAX_FADE_MS: f32 = 400.;
/// The fade's ease out: `1 - (1 - t)^1.6`.
const CURVE: f32 = 1.6;
/// A gap longer than this counts as this (a pause is not the pace).
const GAP_CLAMP_MS: f32 = 1000.;
/// Keyed veils kept, the least recently used dropped first.
const KEPT: usize = 512;

#[derive(Clone, Debug)]
struct Chunk {
    range: Range<usize>,
    started: Instant,
    duration_ms: f32,
}

/// What a paragraph's text was, and the chunks of it still fading.
#[derive(Debug)]
pub(crate) struct Veil {
    prev: String,
    chunks: Vec<Chunk>,
    /// The average gap between chunks.
    ema_ms: f32,
    last_append: Option<Instant>,
}
impl Default for Veil {
    fn default() -> Self {
        Self {
            prev: String::new(),
            chunks: Vec::new(),
            ema_ms: SEED_MS,
            last_append: None,
        }
    }
}

/// A byte range and its opacity, from 0 to 1.
pub(crate) type Span = (Range<usize>, f32);

fn common_prefix(a: &str, b: &str) -> usize {
    let mut p = a.bytes().zip(b.bytes()).take_while(|(x, y)| x == y).count();
    while p > 0 && !b.is_char_boundary(p) {
        p -= 1;
    }
    p
}
/// Chunks fade faster while more than two overlap.
fn boost(active: usize) -> f32 {
    1. + 0.3 * active.saturating_sub(2) as f32
}
fn elapsed_ms(now: Instant, since: Instant) -> f32 {
    now.saturating_duration_since(since).as_secs_f32() * 1000.
}

impl Veil {
    /// The text is now `text`: what it gained past what it shares with the
    /// last text is a new chunk, started at `now`; a chunk past where they
    /// part is cut there.
    pub(crate) fn advance(&mut self, text: &str, now: Instant) {
        if text == self.prev {
            return;
        }
        let p = common_prefix(&self.prev, text);
        self.chunks.retain_mut(|c| {
            c.range.end = c.range.end.min(p);
            c.range.start < c.range.end
        });
        if text.len() > p {
            if let Some(last) = self.last_append {
                let gap = elapsed_ms(now, last).min(GAP_CLAMP_MS);
                self.ema_ms = self.ema_ms * 0.7 + gap * 0.3;
            }
            self.last_append = Some(now);
            self.chunks.push(Chunk {
                range: p..text.len(),
                started: now,
                duration_ms: (self.ema_ms * 3.).clamp(MIN_FADE_MS, MAX_FADE_MS),
            });
        }
        self.prev.clear();
        self.prev.push_str(text);
    }
    /// The opacity of each chunk still fading at `now`; settled ones go.
    pub(crate) fn spans(&mut self, now: Instant) -> Vec<Span> {
        let fast = boost(self.chunks.len());
        self.chunks
            .retain(|c| elapsed_ms(now, c.started) * fast < c.duration_ms);
        let fast = boost(self.chunks.len());
        self.chunks
            .iter()
            .map(|c| {
                let t = (elapsed_ms(now, c.started) * fast / c.duration_ms).clamp(0., 1.);
                (c.range.clone(), 1. - (1. - t).powf(CURVE))
            })
            .collect()
    }
    pub(crate) fn fading(&self) -> bool {
        !self.chunks.is_empty()
    }
}

fn faded(color: Color, alpha: f32) -> Color {
    Color(
        color.0,
        color.1,
        color.2,
        (f32::from(color.3) * alpha).round() as u8,
    )
}
fn fade_run(run: &mut TextRun, alpha: f32) {
    run.color = faded(run.color, alpha);
    run.background = run.background.map(|c| faded(c, alpha));
    for decoration in [&mut run.underline, &mut run.strikethrough]
        .into_iter()
        .flatten()
    {
        if let Some(c) = decoration.color {
            decoration.color = Some(faded(c, alpha));
        }
    }
}

/// `rich` with each span's opacity multiplied into the runs it covers, a
/// run split where a span starts or ends. A padded run (an inline code
/// chip) is not split, as its padding would then show inside it: it takes
/// the opacity of the span over its start.
pub(crate) fn apply(rich: &RichText, spans: &[Span]) -> Option<RichText> {
    if spans.iter().all(|(_, a)| *a >= 1.) {
        return None;
    }
    let text = rich.text();
    let alpha_at = |at: usize| {
        spans
            .iter()
            .find(|(r, _)| r.start <= at && at < r.end)
            .map_or(1., |(_, a)| *a)
    };
    let mut runs = Vec::with_capacity(rich.runs().len() + spans.len() * 2);
    for run in rich.runs() {
        if run.padding[0] > 0. {
            let alpha = alpha_at(run.range.start);
            let mut run = run.clone();
            fade_run(&mut run, alpha);
            runs.push(run);
            continue;
        }
        let mut cuts = vec![run.range.start, run.range.end];
        for (r, _) in spans {
            for at in [r.start, r.end] {
                if at > run.range.start && at < run.range.end && text.is_char_boundary(at) {
                    cuts.push(at);
                }
            }
        }
        cuts.sort_unstable();
        cuts.dedup();
        for w in cuts.windows(2) {
            let mut piece = run.clone();
            piece.range = w[0]..w[1];
            let alpha = alpha_at(w[0]);
            if alpha < 1. {
                fade_run(&mut piece, alpha);
            }
            runs.push(piece);
        }
    }
    RichText::new(rich.text_arc(), runs)
        .ok()
        .map(|veiled| veiled.with_options(rich.options()))
}

/// Keyed veils, and their keys from least to most recently used.
type Keyed = (HashMap<Arc<str>, Rc<RefCell<Veil>>>, VecDeque<Arc<str>>);
thread_local! {
    static KEYED: RefCell<Keyed> = RefCell::default();
}
/// The veil kept under `key`, made if it is new.
pub(crate) fn keyed(key: &Arc<str>) -> Rc<RefCell<Veil>> {
    KEYED.with(|keyed| {
        let (map, order) = &mut *keyed.borrow_mut();
        if let Some(veil) = map.get(key) {
            let veil = veil.clone();
            if order.back() != Some(key) {
                order.retain(|k| k != key);
                order.push_back(key.clone());
            }
            return veil;
        }
        let veil = Rc::new(RefCell::new(Veil::default()));
        map.insert(key.clone(), veil.clone());
        order.push_back(key.clone());
        while order.len() > KEPT {
            if let Some(old) = order.pop_front() {
                map.remove(&old);
            }
        }
        veil
    })
}

/// A rich text view's veil (`View::veil`): shows each text the view sets
/// with its fading chunks, and recolours it frame by frame until they
/// settle.
pub(crate) struct Fade {
    veil: Rc<RefCell<Veil>>,
    /// The text as set, unfaded.
    base: Rc<RefCell<Option<Arc<RichText>>>>,
    runner: Rc<crate::compose::TaskRunner>,
    frames: crate::frame::FrameClock,
    ui: crate::widgets::WeakUi,
    paragraph: crate::scene::NodeId,
    task: Rc<RefCell<Option<crate::compose::TaskToken>>>,
}
impl Fade {
    /// A veil for `paragraph`, under `key` if there is one; none where
    /// nothing runs tasks or delivers frames (it shows its text as set).
    pub(crate) fn new(
        ui: &mut crate::widgets::Ui,
        root: crate::scene::NodeId,
        paragraph: crate::scene::NodeId,
        key: Option<Arc<str>>,
        environment: &crate::compose::Environment,
    ) -> Option<Self> {
        let runner = environment.services.get::<crate::compose::TaskRunner>()?;
        let frames = (*environment.services.get::<crate::frame::FrameClock>()?).clone();
        let task: Rc<RefCell<Option<crate::compose::TaskToken>>> = Rc::default();
        // Its frames end with the view.
        ui.retain(root, task.clone());
        Some(Self {
            veil: match key {
                Some(key) => keyed(&key),
                None => Rc::default(),
            },
            base: Rc::default(),
            runner,
            frames,
            ui: ui.downgrade(),
            paragraph,
            task,
        })
    }
    /// `rich` as it shows now: what it gained since the last text fading.
    pub(crate) fn show(&mut self, rich: &Arc<RichText>) -> Arc<RichText> {
        let now = Instant::now();
        let mut veil = self.veil.borrow_mut();
        veil.advance(rich.text(), now);
        *self.base.borrow_mut() = Some(rich.clone());
        match apply(rich, &veil.spans(now)) {
            Some(veiled) => Arc::new(veiled),
            None => rich.clone(),
        }
    }
    /// Recolour every frame while a chunk fades (one task at a time).
    pub(crate) fn run(&mut self) {
        let running = self
            .task
            .borrow()
            .as_ref()
            .is_some_and(|token| !token.is_finished());
        if running || !self.veil.borrow().fading() {
            return;
        }
        let (veil, base, frames, ui, paragraph) = (
            self.veil.clone(),
            self.base.clone(),
            self.frames.clone(),
            self.ui.clone(),
            self.paragraph,
        );
        let token = self.runner.spawn(Box::pin(async move {
            loop {
                let frame = frames.next().await;
                let Some(ui) = ui.upgrade() else { return };
                let Some(rich) = base.borrow().clone() else {
                    return;
                };
                let mut veil = veil.borrow_mut();
                let spans = veil.spans(frame.time.max(Instant::now()));
                let shown = apply(&rich, &spans).map_or(rich, Arc::new);
                let mut scene = ui.scene.borrow_mut();
                if !scene.contains(paragraph) {
                    return;
                }
                scene.set_kind(paragraph, crate::scene::NodeKind::RichText { text: shown });
                if !veil.fading() {
                    return;
                }
            }
        }));
        *self.task.borrow_mut() = Some(token);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn rich(text: &str, runs: &[(Range<usize>, f32)]) -> RichText {
        let runs: Vec<TextRun> = runs
            .iter()
            .map(|(range, pad)| TextRun {
                range: range.clone(),
                padding: [*pad, 0.],
                ..Default::default()
            })
            .collect();
        RichText::new(text, runs).unwrap()
    }

    #[test]
    fn an_append_fades_in_and_settles() {
        let t0 = Instant::now();
        let mut veil = Veil::default();
        veil.advance("Hello", t0);
        veil.spans(t0);
        veil.advance("Hello world", t0 + Duration::from_millis(100));
        let spans = veil.spans(t0 + Duration::from_millis(100));
        assert_eq!(spans.last().map(|s| s.0.clone()), Some(5..11));
        assert_eq!(spans.last().map(|s| s.1), Some(0.));
        let mid = veil.spans(t0 + Duration::from_millis(150));
        let alpha = mid.last().unwrap().1;
        assert!(alpha > 0. && alpha < 1., "{alpha}");
        // Past its longest fade every chunk has settled.
        assert!(veil.spans(t0 + Duration::from_secs(2)).is_empty());
        assert!(!veil.fading());
    }

    #[test]
    fn a_rewrite_cuts_chunks_where_the_texts_part() {
        let t0 = Instant::now();
        let mut veil = Veil::default();
        veil.advance("abcdef", t0);
        veil.advance("abX", t0);
        let spans = veil.spans(t0);
        assert_eq!(
            spans.iter().map(|s| s.0.clone()).collect::<Vec<_>>(),
            [0..2, 2..3]
        );
    }

    #[test]
    fn opacity_splits_runs_but_not_padded_ones() {
        let text = rich("abcdefgh", &[(0..4, 0.), (4..8, 3.)]);
        let out = apply(&text, &[(2..6, 0.5)]).unwrap();
        let ranges: Vec<_> = out.runs().iter().map(|r| r.range.clone()).collect();
        assert_eq!(ranges, [0..2, 2..4, 4..8]);
        let alphas: Vec<u8> = out.runs().iter().map(|r| r.color.3).collect();
        assert_eq!(alphas, [255, 128, 128]);
        assert_eq!(out.text(), "abcdefgh");
        // Settled, the text is as it was.
        assert!(apply(&text, &[(2..6, 1.)]).is_none());
    }

    #[test]
    fn keyed_veils_outlive_their_views() {
        let key: Arc<str> = "veil-test-key".into();
        keyed(&key).borrow_mut().advance("kept", Instant::now());
        assert_eq!(keyed(&key).borrow().prev, "kept");
    }
}
