//! The voice glyph (Zeron's, PR #916): a dot-matrix that shows a call. A
//! [`Field`] is the call's disc, a voice pushed out ring by ring from its
//! heart; a [`Beam`] is a strip rising from its bottom as the voice does.
//! [`glyph`] decides every dot's level, ink and size from the two voices'
//! bands and the call's [`Mode`]; [`voice_glyph`] paints it as a canvas of
//! dots and steps it on the window's frame clock, at 30 frames a second
//! while anything in it moves and not at all once it rests, so a call
//! animates with no work outside the engine. Its voices are a sample's
//! ([`SampleSpeech`]): whoever [`Speaker`] says talks.
pub mod glyph;
mod speech;

pub use glyph::{Beam, Field, Grid, Inks, Mode, Outline, Rings, Touch, Voice};
pub use speech::{SampleSpeech, Speaker};

use std::{
    cell::{Cell, RefCell},
    rc::Rc,
    time::Instant,
};
use zgx::{
    canvas::{Canvas, Path},
    compose::{TaskRunner, View, prelude::*},
    frame::FrameClock,
    input::{EventPhase, InputEvent},
    reactive::{Effect, Signal},
    scene::{Color, Rect},
    semantics::Role,
};

/// The most frames a second a glyph is stepped and painted.
pub const FPS: f64 = 30.;

/// What a glyph is: a field of `cols` × `rows` dots, as large as they make
/// it, or a beam filling the box it is given.
enum Shape {
    Field {
        field: Field,
        cols: usize,
        rows: usize,
    },
    Beam(Beam),
}

/// A glyph to paint (see [`voice_glyph`]).
pub struct VoiceGlyph {
    shape: Shape,
    grid: Grid,
    outline: Outline,
    mode: Box<dyn FnMut() -> Mode>,
    speaker: Box<dyn FnMut() -> Speaker>,
    inks: Box<dyn FnMut() -> Inks>,
    still: Box<dyn FnMut() -> bool>,
    label: Option<Box<dyn FnMut() -> String>>,
    touch: bool,
}

impl VoiceGlyph {
    fn new(shape: Shape, grid: Grid) -> Self {
        Self {
            shape,
            grid,
            outline: Outline::Square,
            mode: Box::new(|| Mode::Listening),
            speaker: Box::new(|| Speaker::Nobody),
            inks: Box::new(|| Inks::new(glyph::SUNRISE)),
            still: Box::new(|| false),
            label: None,
            touch: false,
        }
    }
    /// `field`, `cols` × `rows` dots on `grid`: its box is theirs.
    pub fn field(field: Field, cols: usize, rows: usize, grid: Grid) -> Self {
        Self::new(
            Shape::Field {
                field,
                cols: cols.max(1),
                rows: rows.max(1),
            },
            grid,
        )
    }
    /// `beam` on `grid`, filling the box it is given: its dots counted as
    /// it paints, so it always reaches the box's edges.
    pub fn beam(beam: Beam, grid: Grid) -> Self {
        Self::new(Shape::Beam(beam), grid)
    }
    /// The outline it keeps (a beam's radii in points, a field's in dots).
    pub fn outline(mut self, outline: Outline) -> Self {
        self.outline = outline;
        self
    }
    /// What it shows between voices, following what `mode` reads.
    pub fn mode(mut self, mode: impl FnMut() -> Mode + 'static) -> Self {
        self.mode = Box::new(mode);
        self
    }
    /// Who speaks in the sample call it follows.
    pub fn speaker(mut self, speaker: impl FnMut() -> Speaker + 'static) -> Self {
        self.speaker = Box::new(speaker);
        self
    }
    /// Its inks, following what `inks` reads (the theme's tokens).
    pub fn inks(mut self, inks: impl FnMut() -> Inks + 'static) -> Self {
        self.inks = Box::new(inks);
        self
    }
    /// Held still while `still` holds (reduced motion): it shows its
    /// mode's pattern and nothing moves it.
    pub fn still(mut self, still: impl FnMut() -> bool + 'static) -> Self {
        self.still = Box::new(still);
        self
    }
    /// What it says to assistive technology, followed (its mode, worded).
    pub fn label(mut self, label: impl FnMut() -> String + 'static) -> Self {
        self.label = Some(Box::new(label));
        self
    }
    /// The pointer over it lights the dots under it, the light holding a
    /// moment where it left them.
    pub fn touchable(mut self) -> Self {
        self.touch = true;
        self
    }
}

/// A glyph's moving parts, shared by its frame loop and its painter.
struct Live {
    shape: Shape,
    speech: SampleSpeech,
    mode: Mode,
    still: bool,
    shown: bool,
    /// The last frame's time.
    now: Option<Instant>,
    /// Where the pointer last moved over it, from its first dot, and when.
    touch: Option<(f32, f32, Instant)>,
}

impl Live {
    /// The pointer's light as it stands now.
    fn touch(&self) -> Option<Touch> {
        let (x, y, at) = self.touch?;
        let held = self.now?.saturating_duration_since(at).as_secs_f32();
        let strength = Touch::strength_after(held);
        (strength > 0.).then_some(Touch { x, y, strength })
    }
    /// Hears the call at `now` and passes into its mode; whether anything
    /// still moves.
    fn step(&mut self, now: Instant) -> bool {
        self.now = Some(now);
        if self.still || !self.shown {
            return false;
        }
        let voice = self.speech.hear(now);
        let mode = self.mode;
        let moving = match &mut self.shape {
            Shape::Field { field, .. } => {
                field.hear(voice, now);
                field.shift(mode);
                field.moving(mode)
            }
            Shape::Beam(beam) => {
                beam.hear(voice, now);
                beam.shift(mode);
                beam.moving(mode)
            }
        };
        moving || self.speech.speaker() != Speaker::Nobody || self.touch().is_some()
    }
}

/// Each dot lands on whole device pixels at 2×, its centre and its size
/// alike: a dot straddling pixels otherwise than its neighbour reads as a
/// second, slower pattern over the grid (moiré), not as light.
fn snap(v: f32) -> f32 {
    (v * 2.).round() / 2.
}

/// `cells` laid out on `grid` from `origin`, one round dot each, its light
/// told by its colour, opacity and size alone.
fn paint(canvas: &mut Canvas, origin: (f32, f32), grid: Grid, cells: &[glyph::Cell]) {
    let pitch = grid.pitch();
    for cell in cells {
        let look = glyph::look(cell);
        if look.alpha < 0.01 {
            continue;
        }
        let across = snap(grid.dot * look.size).max(0.5);
        let centre = (
            origin.0 + cell.col * pitch + grid.dot / 2.,
            origin.1 + cell.row * pitch + grid.dot / 2.,
        );
        let rect = Rect::new(
            snap(centre.0 - across / 2.),
            snap(centre.1 - across / 2.),
            across,
            across,
        );
        let byte = |v: f32| (v.clamp(0., 1.) * 255.).round() as u8;
        let [r, g, b] = look.fill;
        if let Ok(dot) = Path::ellipse(rect) {
            canvas.fill(dot, Color(byte(r), byte(g), byte(b), byte(look.alpha)));
        }
    }
}

/// The glyph `options` describes, painted as a canvas and stepped on the
/// window's frame clock while it shows and anything in it moves: a voice,
/// its mode's own motion, a passage between modes, the pointer's light.
/// Without a frame clock, or held still, it paints its mode's pattern.
pub fn voice_glyph(options: VoiceGlyph) -> View {
    component(move |cx| {
        let VoiceGlyph {
            shape,
            grid,
            outline,
            mut mode,
            mut speaker,
            mut inks,
            mut still,
            label,
            touch,
        } = options;
        let runtime = cx.runtime();
        let size = match &shape {
            Shape::Field { cols, rows, .. } => Some(grid.extent(*cols, *rows)),
            Shape::Beam(_) => None,
        };
        let live = Rc::new(RefCell::new(Live {
            shape,
            speech: SampleSpeech::default(),
            mode: Mode::Listening,
            still: false,
            shown: true,
            now: None,
            touch: None,
        }));
        let tick: Signal<u64> = cx.state(0);
        let frames = cx.try_service::<FrameClock>().map(|f| (*f).clone());
        let tasks = frames
            .as_ref()
            .and(cx.try_service::<TaskRunner>())
            .map(|_| cx.tasks());
        let running = Rc::new(Cell::new(false));
        // Starts the frame loop unless it runs: it ends once nothing moves.
        let wake: Rc<dyn Fn()> = {
            let (live, running, tick) = (live.clone(), running.clone(), tick.clone());
            Rc::new(move || {
                let (Some(frames), Some(tasks)) = (frames.clone(), tasks.clone()) else {
                    return;
                };
                if running.get() || live.borrow().still || !live.borrow().shown {
                    return;
                }
                running.set(true);
                let (live, running, tick) = (live.clone(), running.clone(), tick.clone());
                tasks.spawn(async move {
                    loop {
                        let frame = frames.next().max_rate(FPS).await;
                        let moving = live.borrow_mut().step(frame.time);
                        tick.update(|t| *t = t.wrapping_add(1));
                        if !moving {
                            running.set(false);
                            return;
                        }
                    }
                });
            })
        };
        // Still or not first: a glyph held still never starts.
        {
            let (live, tick, wake) = (live.clone(), tick.clone(), wake.clone());
            cx.retain(runtime.effect_now(move || {
                let still = still();
                live.borrow_mut().still = still;
                tick.update(|t| *t = t.wrapping_add(1));
                wake();
            }));
        }
        {
            let (live, tick, wake) = (live.clone(), tick.clone(), wake.clone());
            cx.retain(runtime.effect_now(move || {
                let mode = mode();
                live.borrow_mut().mode = mode;
                tick.update(|t| *t = t.wrapping_add(1));
                wake();
            }));
        }
        {
            let (live, wake) = (live.clone(), wake.clone());
            cx.retain(runtime.effect(move || {
                let who = speaker();
                live.borrow_mut().speech.speak(who);
                wake();
            }));
        }
        let painter = live.clone();
        let mut view = canvas(move |(width, height)| {
            tick.get();
            let inks = inks();
            let live = painter.borrow();
            let mut out = Canvas::new();
            match &live.shape {
                Shape::Field { field, cols, rows } => {
                    let cells = field.cells_touched(
                        *cols,
                        *rows,
                        grid,
                        live.mode,
                        &inks,
                        outline,
                        &[],
                        live.touch(),
                    );
                    paint(&mut out, (0., 0.), grid, &cells);
                }
                Shape::Beam(beam) => {
                    // Its radii in dots; the matrix covers the box and runs
                    // past it, the box's own outline fading it out, so it
                    // fills the box to its curves.
                    let outline = match outline {
                        Outline::Rounded(radius) => Outline::Rounded(radius / grid.pitch()),
                        Outline::Under(radius) => Outline::Under(radius / grid.pitch()),
                        other => other,
                    };
                    let ((cols, rows), margin) = grid.cover(width, height);
                    let area = (width / grid.pitch(), height / grid.pitch());
                    let cells = beam.cells_over(cols, rows, area, live.mode, &inks, outline);
                    paint(&mut out, margin, grid, &cells);
                }
            }
            out
        })
        .role(Role::Image)
        .pointer_events(touch);
        if let Some(label) = label {
            view = view.accessible_label_when(label);
        }
        if let Some((width, height)) = size {
            view = view.w(width).h(height).shrink_0();
        }
        let bounds: Rc<RefCell<Option<Signal<Rect>>>> = Default::default();
        let visibility: Rc<RefCell<Option<Effect>>> = Default::default();
        cx.retain(visibility.clone());
        {
            let (bounds, live, wake) = (bounds.clone(), live.clone(), wake.clone());
            let runtime = runtime.clone();
            view = view.on_mount(move |handle| {
                *bounds.borrow_mut() = handle.observe_bounds();
                // Out of view it rests, and wakes as it shows again.
                if let Some(shown) = handle.observe_visibility() {
                    *visibility.borrow_mut() = Some(runtime.effect(move || {
                        let now = shown.get();
                        live.borrow_mut().shown = now;
                        wake();
                    }));
                }
            });
        }
        if touch {
            let clock = cx.try_service::<FrameClock>();
            view = view.on_event(move |ecx| {
                let InputEvent::PointerMove { x, y, .. } = ecx.event else {
                    return;
                };
                if ecx.phase == EventPhase::Capture {
                    return;
                }
                let Some(at) = bounds.borrow().as_ref().map(|b| b.with_untracked(|r| *r)) else {
                    return;
                };
                let (x, y) = (x - at.x, y - at.y);
                // Within the disc it keeps (a field's outline), not its box.
                let (w, h) = (at.width, at.height);
                if outline == Outline::Disc && (x - w / 2.).hypot(y - h / 2.) > w.min(h) / 2. {
                    return;
                }
                let mut state = live.borrow_mut();
                if state.still {
                    return;
                }
                // As of the frame last shown: a glyph at rest has stepped
                // none since it settled.
                let now = clock
                    .as_ref()
                    .and_then(|clock| clock.last())
                    .map_or_else(Instant::now, |frame| frame.time);
                state.touch = Some((x, y, now));
                drop(state);
                wake();
            });
        }
        view
    })
}
