//! What the styleguide's Zeron app costs, headless: instructions retired
//! (macOS) and script calls while idle, while the pointer moves down the
//! sidebar, while a transcript scrolls, and while the layouts cycle. Each
//! scenario runs on a fresh app, `RUNS` times (5 by default); the median and
//! the range are reported, so one noisy run does not decide.
//! Run: cargo run --release -p zgui-script --example zeron_bench
//! `LINT=1` instead mounts every workbench page and the app in each layout
//! with the design lint on, and counts what it reports by file
//! (`LINT=2` prints each finding).
use std::path::Path;
use zgui::input::{InputEvent, Key, Modifiers};
use zgui_script::{DesignLint, ScriptHost, testing::TestApp};

/// Instructions this process has retired (macOS; 0 elsewhere).
fn instructions() -> u64 {
    #[cfg(target_os = "macos")]
    {
        #[repr(C)]
        struct Usage {
            uuid: [u8; 16],
            fields: [u64; 40],
        }
        unsafe extern "C" {
            fn proc_pid_rusage(pid: i32, flavor: i32, buffer: *mut Usage) -> i32;
        }
        let mut usage = Usage {
            uuid: [0; 16],
            fields: [0; 40],
        };
        // RUSAGE_INFO_V4: `ri_instructions` is the 30th field after the uuid.
        unsafe { proc_pid_rusage(std::process::id() as i32, 4, &mut usage) };
        usage.fields[29]
    }
    #[cfg(not(target_os = "macos"))]
    0
}

const WIDTH: f32 = 1280.;
const HEIGHT: f32 = 800.;

fn app() -> TestApp {
    let h = TestApp::new(|runtime| {
        let host = ScriptHost::new(
            runtime,
            Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide/app_zeron.luau"),
        );
        host.action("inspect", |_| {});
        host.action("close_window", |_| {});
        host.action("open_app", |_| {});
        host
    });
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    h.ui.prepare_frame();
    h.settle();
    // Past the first frames' animations.
    h.frames(120);
    if let Some(e) = h.error() {
        panic!("script error: {e}");
    }
    h
}

struct Sample {
    instructions: u64,
    calls: u64,
    // Frames still asked for at the end (an idle window asks for none).
    wants_frame: bool,
}

fn measure(h: &mut TestApp, work: impl FnOnce(&mut TestApp)) -> Sample {
    let (i0, c0) = (instructions(), h.calls());
    work(h);
    Sample {
        instructions: instructions() - i0,
        calls: h.calls() - c0,
        wants_frame: h.clock.wants_frame(),
    }
}

fn idle(h: &mut TestApp) {
    // Two seconds of display frames with nothing happening.
    h.frames(120);
}

const ROWS: [&str; 12] = [
    "nav_prs",
    "agent_a1",
    "agent_a2",
    "agent_a4",
    "agent_a5",
    "agent_a6",
    "agent_a7",
    "agent_a8",
    "agent_a3",
    "thread_h1",
    "thread_h2",
    "thread_h3",
];
fn hover(h: &mut TestApp) {
    // The pointer down the sidebar's rows and back, a frame at each.
    for pass in 0..2 {
        let order: Vec<&str> = if pass == 0 {
            ROWS.to_vec()
        } else {
            ROWS.iter().rev().copied().collect()
        };
        for id in order {
            let Some(_) = h.find(id) else { continue };
            let b = h.bounds(id);
            for step in 0..4 {
                h.ui.dispatch(InputEvent::PointerMove {
                    x: b.x + 40. + step as f32 * 10.,
                    y: b.y + b.height / 2.,
                });
                h.frame();
            }
        }
    }
    h.frames(30);
}

fn scroll(h: &mut TestApp) {
    // Wheel notches over the transcript, up then down, a frame at each.
    let b = h.bounds("conversation");
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 3.);
    for delta in [-40., 40.] {
        for _ in 0..40 {
            h.ui.dispatch(InputEvent::Scroll {
                x,
                y,
                delta_x: 0.,
                delta_y: delta,
            });
            h.frame();
        }
    }
    h.frames(30);
}

fn layouts(h: &mut TestApp) {
    // ⌘⇧L through the four layouts and back to the first.
    for _ in 0..4 {
        h.key_with(
            Key::Character("l".into()),
            Modifiers {
                meta: true,
                shift: true,
                ..Default::default()
            },
        );
        h.frames(30);
    }
}

const PAGES: [&str; 23] = [
    "colour",
    "typography",
    "icons",
    "metrics",
    "motion",
    "patterns",
    "parity",
    "buttons",
    "inputs",
    "chips",
    "overlays",
    "lists",
    "apps",
    "shell",
    "transcript",
    "agent",
    "changes",
    "workspace",
    "panes",
    "panels",
    "settings",
    "composer",
    "pickers",
];

fn mount(script: &str, page: &str) -> TestApp {
    let page = page.to_string();
    let script = script.to_string();
    let h = TestApp::new(move |runtime| {
        let host = ScriptHost::new(
            runtime,
            Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("examples/styleguide/{script}")),
        );
        host.design_lint(DesignLint::Warn);
        host.action("inspect", |_| {});
        host.action("close_window", |_| {});
        host.action("open_app", |_| {});
        host.shared("start_page", page.as_str());
        host.shared("platform", "macos");
        host
    });
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    h.ui.prepare_frame();
    h.settle();
    h.frames(30);
    h
}

fn lint(verbose: bool) {
    let mut all: std::collections::BTreeSet<String> = Default::default();
    for page in PAGES {
        let h = mount("app.luau", page);
        all.extend(h.host.warnings());
    }
    let mut h = mount("app_zeron.luau", "");
    for _ in 0..4 {
        all.extend(h.host.warnings());
        h.key_with(
            Key::Character("l".into()),
            Modifiers {
                meta: true,
                shift: true,
                ..Default::default()
            },
        );
        h.frames(30);
    }
    all.extend(h.host.warnings());
    let mut by_file: std::collections::BTreeMap<String, usize> = Default::default();
    for w in &all {
        if verbose {
            println!("{w}");
        }
        let file = w.split(':').next().unwrap_or("?").to_string();
        *by_file.entry(file).or_default() += 1;
    }
    let mut files: Vec<_> = by_file.into_iter().collect();
    files.sort_by_key(|f| std::cmp::Reverse(f.1));
    for (file, n) in files {
        println!("{n:>5}  {file}");
    }
    println!("{:>5}  total", all.len());
}

fn main() {
    if let Ok(v) = std::env::var("LINT") {
        let verbose = v == "2";
        std::thread::Builder::new()
            .stack_size(32 << 20)
            .spawn(move || lint(verbose))
            .unwrap()
            .join()
            .unwrap();
        return;
    }
    let runs: usize = std::env::var("RUNS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5);
    type Scenario = (&'static str, fn(&mut TestApp));
    let scenarios: [Scenario; 4] = [
        ("idle", idle),
        ("hover", hover),
        ("scroll", scroll),
        ("layouts", layouts),
    ];
    println!(
        "scenario  instructions (M): median [min-max]  script calls: median  frames wanted after"
    );
    // A deep tree in a debug build wants a big stack; release does not, but
    // the same thread keeps the numbers comparable.
    let worker = std::thread::Builder::new()
        .stack_size(32 << 20)
        .spawn(move || {
            for (name, work) in scenarios {
                let mut samples: Vec<Sample> = (0..runs)
                    .map(|_| {
                        let mut h = app();
                        measure(&mut h, work)
                    })
                    .collect();
                samples.sort_by_key(|s| s.instructions);
                let m = |v: u64| v as f64 / 1e6;
                let median = &samples[samples.len() / 2];
                let mut calls: Vec<u64> = samples.iter().map(|s| s.calls).collect();
                calls.sort();
                println!(
                    "{name:<9} {:>9.1} [{:.1}-{:.1}]  {:>8}  {}",
                    m(median.instructions),
                    m(samples[0].instructions),
                    m(samples[samples.len() - 1].instructions),
                    calls[calls.len() / 2],
                    samples.iter().filter(|s| s.wants_frame).count(),
                );
            }
        })
        .unwrap();
    worker.join().unwrap();
}
