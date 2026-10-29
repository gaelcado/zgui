//! The voice glyph as it paints: a canvas of dots, stepped on the frame
//! clock at 30 frames a second while it moves and resting once it does
//! not, held still when asked, its sample voices lighting it in their own
//! inks, the pointer lighting the dots under it.
use std::{
    cell::RefCell,
    rc::Rc,
    sync::Arc,
    time::{Duration, Instant},
};
use zgx::{
    canvas::{Brush, Draw},
    compose::{TaskRunner, prelude::*},
    frame::{Frame, FrameClock},
    input::InputEvent,
    reactive::Signal,
    scene::{Color, NodeKind, Rect},
    task::LocalExecutor,
    widgets::Ui,
};
use zgx_components::voice::{
    Beam, Field, Grid, Inks, Mode, Outline, Rings, Speaker, VoiceGlyph, voice_glyph,
};

const RED: [f32; 3] = [1., 0., 0.];
const BLUE: [f32; 3] = [0., 0., 1.];

struct Host {
    ui: Ui,
    executor: Rc<RefCell<LocalExecutor>>,
    clock: FrameClock,
    start: Instant,
    frame: u64,
}
impl Host {
    fn new(mut ui: Ui, view: View) -> Self {
        let executor = Rc::new(RefCell::new(LocalExecutor::new()));
        let clock = FrameClock::new();
        ui.mount(provide(
            TaskRunner::from_executor(executor.clone()),
            provide(clock.clone(), column().w_full().h_full().child(view)),
        ));
        let host = Self {
            ui,
            executor,
            clock,
            start: Instant::now(),
            frame: 0,
        };
        host.settle();
        host
    }
    fn settle(&self) {
        self.ui.prepare_frame();
        while self.executor.borrow_mut().tick() > 0 {}
        self.ui.prepare_frame();
    }
    /// One 60 Hz frame.
    fn frame(&mut self) {
        self.frame += 1;
        let interval = Duration::from_secs_f64(1. / 60.);
        self.clock.deliver(Frame {
            index: self.frame,
            time: self.start + interval * self.frame as u32,
            interval,
        });
        self.settle();
    }
    fn frames(&mut self, n: usize) {
        for _ in 0..n {
            self.frame();
        }
    }
    /// The glyph's canvas and where it sits.
    fn canvas(&self) -> (Arc<zgx::canvas::Canvas>, Rect) {
        let scene = self.ui.scene.borrow();
        let mut pending = vec![scene.root()];
        while let Some(n) = pending.pop() {
            if let NodeKind::Canvas(canvas) = scene.kind(n) {
                return (canvas.clone(), scene.bounds(n));
            }
            pending.extend(scene.children(n).iter().copied());
        }
        panic!("no canvas")
    }
    /// Its dots: each one's box and colour.
    fn dots(&self) -> Vec<(Rect, Color)> {
        let (canvas, _) = self.canvas();
        canvas
            .commands()
            .iter()
            .map(|draw| match draw {
                Draw::Fill {
                    path,
                    brush: Brush::Solid(color),
                    ..
                } => match path.shape() {
                    Some(zgx::canvas::Shape::Ellipse { rect }) => (rect, *color),
                    other => panic!("a dot is a circle, not {other:?}"),
                },
                other => panic!("a dot is filled, not {other:?}"),
            })
            .collect()
    }
}

fn inks() -> Inks {
    Inks {
        agent: [RED; 3],
        user: [BLUE; 3],
    }
}

const GRID: Grid = Grid { dot: 3., gap: 1. };

fn disc(mode: Signal<Mode>, speaker: Signal<Speaker>) -> View {
    voice_glyph(
        VoiceGlyph::field(Field::new(Rings::Round), 21, 21, GRID)
            .outline(Outline::Disc)
            .mode(move || mode.get())
            .speaker(move || speaker.get())
            .inks(inks)
            .touchable(),
    )
}

/// The dots within `reach` points of `at`.
fn near(dots: &[(Rect, Color)], at: (f32, f32), reach: f32) -> Vec<Color> {
    dots.iter()
        .filter(|(r, _)| (r.x + r.width / 2. - at.0).hypot(r.y + r.height / 2. - at.1) < reach)
        .map(|(_, c)| *c)
        .collect()
}

#[test]
fn a_field_paints_its_disc_and_steps_while_it_moves_then_rests() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let mode = runtime.signal(Mode::Listening);
    let speaker = runtime.signal(Speaker::Nobody);
    let mut host = Host::new(ui, disc(mode.clone(), speaker.clone()));
    let (_, at) = host.canvas();
    // 21 dots of 3 a point apart: 83 across, as large as its dots make it.
    assert_eq!((at.width, at.height), (83., 83.));
    let dots = host.dots();
    assert!(dots.len() > 250 && dots.len() <= 21 * 21, "{}", dots.len());
    for (r, _) in &dots {
        let (x, y) = (r.x + r.width / 2. - 41.5, r.y + r.height / 2. - 41.5);
        assert!(x.hypot(y) < 42., "a dot outside the disc: {r:?}");
    }
    // Listening breathes: every other 60 Hz frame paints anew (30 fps).
    assert!(host.clock.wants_frame());
    let mut painted = Vec::new();
    for _ in 0..20 {
        let before = host.canvas().0;
        host.frame();
        painted.push(!Arc::ptr_eq(&before, &host.canvas().0));
    }
    let shown = painted.iter().filter(|p| **p).count();
    assert!((9..=11).contains(&shown), "{shown} of 20 frames painted");
    // Muted and quiet, it settles over its passage and asks for no frame.
    mode.set(Mode::Muted);
    host.frames(90);
    assert!(
        !host.clock.wants_frame(),
        "a muted glyph at rest does no work"
    );
    let still = host.canvas().0;
    host.frames(10);
    assert!(Arc::ptr_eq(&still, &host.canvas().0));
    // A word wakes it.
    mode.set(Mode::Listening);
    host.settle();
    assert!(host.clock.wants_frame());
}

#[test]
fn each_voice_lights_the_heart_in_its_own_ink() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let mode = runtime.signal(Mode::Listening);
    let speaker = runtime.signal(Speaker::Agent);
    let mut host = Host::new(ui, disc(mode.clone(), speaker.clone()));
    host.frames(30);
    let red = |c: &Color| c.0 > 200 && c.2 < 50;
    let blue = |c: &Color| c.2 > 200 && c.0 < 50;
    let agent = near(&host.dots(), (41.5, 41.5), 8.);
    assert!(
        !agent.is_empty() && agent.iter().all(red),
        "Codex in its ink"
    );
    let lit = |dots: &[(Rect, Color)]| {
        near(dots, (41.5, 41.5), 8.)
            .iter()
            .map(|c| c.3 as u32)
            .sum::<u32>()
    };
    let speaking = lit(&host.dots());
    speaker.set(Speaker::User);
    host.frames(60);
    let user = near(&host.dots(), (41.5, 41.5), 8.);
    assert!(user.iter().all(blue), "the user in theirs");
    // Silent, the heart dims back to the breath.
    speaker.set(Speaker::Nobody);
    host.frames(120);
    assert!(lit(&host.dots()) < speaking, "quieter at rest");
    // Muted, the user is never shown.
    mode.set(Mode::Muted);
    speaker.set(Speaker::User);
    host.frames(60);
    assert!(
        near(&host.dots(), (41.5, 41.5), 8.)
            .iter()
            .all(|c| !blue(c))
    );
}

#[test]
fn held_still_it_paints_its_mode_and_asks_for_no_frame() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let mode = runtime.signal(Mode::Thinking);
    let still = runtime.signal(true);
    let shown = still.clone();
    let m = mode.clone();
    let host = Host::new(
        ui,
        voice_glyph(
            VoiceGlyph::field(Field::new(Rings::Round), 15, 15, GRID)
                .outline(Outline::Disc)
                .mode(move || m.get())
                .speaker(|| Speaker::Agent)
                .still(move || shown.get())
                .inks(inks),
        ),
    );
    assert!(!host.clock.wants_frame());
    let thinking = host.canvas().0;
    mode.set(Mode::Asking);
    host.settle();
    assert!(
        !Arc::ptr_eq(&thinking, &host.canvas().0),
        "the new mode shows"
    );
    assert!(!host.clock.wants_frame());
    still.set(false);
    host.settle();
    assert!(host.clock.wants_frame(), "let go, it moves");
}

/// Codex asking (the knock at the rim): every dot stays inside the box it
/// is given over the whole knock, none cut at its edge.
#[test]
fn an_asking_field_keeps_every_dot_inside_its_box() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let mode = runtime.signal(Mode::Asking);
    let speaker = runtime.signal(Speaker::Agent);
    let mut host = Host::new(ui, disc(mode, speaker));
    let (_, at) = host.canvas();
    for _ in 0..150 {
        host.frame();
        for (r, _) in host.dots() {
            assert!(
                r.x >= 0. && r.y >= 0. && r.x + r.width <= at.width && r.y + r.height <= at.height,
                "a dot cut at the edge: {r:?} in {at:?}"
            );
        }
    }
}

#[test]
fn a_beam_fills_its_box_and_rises_with_the_voice() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let speaker = runtime.signal(Speaker::Nobody);
    let who = speaker.clone();
    let mut host = Host::new(
        ui,
        voice_glyph(
            VoiceGlyph::beam(Beam::default(), Grid::dense(2.4))
                .outline(Outline::Stadium)
                .mode(|| Mode::Listening)
                .speaker(move || who.get())
                .inks(inks),
        )
        .w(200.)
        .h(22.),
    );
    let (_, at) = host.canvas();
    assert_eq!((at.width, at.height), (200., 22.));
    let reach = |dots: &[(Rect, Color)]| {
        let left = dots.iter().map(|(r, _)| r.x).fold(f32::MAX, f32::min);
        let right = dots.iter().map(|(r, _)| r.x + r.width).fold(0., f32::max);
        (left, right)
    };
    let (left, right) = reach(&host.dots());
    assert!(left < 12. && right > 188., "end to end: {left}..{right}");
    let top = |dots: &[(Rect, Color)]| {
        dots.iter()
            .filter(|(_, c)| c.3 > 160)
            .map(|(r, _)| r.y)
            .fold(f32::MAX, f32::min)
    };
    let resting = top(&host.dots());
    speaker.set(Speaker::User);
    host.frames(40);
    let mut risen = f32::MAX;
    for _ in 0..30 {
        host.frame();
        risen = risen.min(top(&host.dots()));
    }
    assert!(
        risen < resting && risen < 8.,
        "the voice lifts it: {risen} from {resting}"
    );
}

#[test]
fn the_pointer_lights_the_dots_under_it_and_lets_go() {
    let ui = Ui::new(400., 300.);
    let runtime = ui.runtime.clone();
    let mode = runtime.signal(Mode::Muted);
    let speaker = runtime.signal(Speaker::Nobody);
    let mut host = Host::new(ui, disc(mode, speaker));
    host.frames(90);
    assert!(!host.clock.wants_frame());
    let (_, at) = host.canvas();
    let quiet = near(&host.dots(), (20., 41.5), 6.);
    let alpha = |dots: &[Color]| dots.iter().map(|c| c.3 as u32).sum::<u32>();
    host.ui.dispatch(InputEvent::PointerMove {
        x: at.x + 20.,
        y: at.y + 41.5,
    });
    host.settle();
    assert!(host.clock.wants_frame(), "the touch wakes it");
    host.frame();
    host.frame();
    let lit = near(&host.dots(), (20., 41.5), 6.);
    assert!(
        alpha(&lit) > alpha(&quiet) * 2,
        "{} vs {}",
        alpha(&lit),
        alpha(&quiet)
    );
    // It holds, fades and lets the glyph rest again.
    host.frames(120);
    assert!(!host.clock.wants_frame());
    assert_eq!(alpha(&near(&host.dots(), (20., 41.5), 6.)), alpha(&quiet));
}
