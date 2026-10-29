//! The styleguide example: every page and component mounted headless,
//! driven as a person would, snapshotted, and held at rest.
mod common;
use common::Harness;
use std::path::Path;
use zgx::input::{InputEvent, Key, Modifiers, PointerButton};
use zgx_script::ScriptHost;

const WIDTH: f32 = 1280.;
const HEIGHT: f32 = 860.;

fn styleguide() -> Harness {
    let h = Harness::new(|runtime| {
        let host = ScriptHost::new(
            runtime,
            Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide/app.luau"),
        );
        host.action("inspect", |_| {});
        host.action("open_app", |_| {});
        host
    });
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    h.ui.prepare_frame();
    h.settle();
    h
}
fn healthy(h: &Harness) {
    if let Some(e) = h.error() {
        panic!("script error: {e}");
    }
}
fn key(h: &mut Harness, key: Key, meta: bool) {
    h.key_with(
        key,
        Modifiers {
            meta,
            ..Default::default()
        },
    );
}
/// Hover the middle of node `id`.
fn hover(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::PointerMove {
        x: b.x + b.width / 2.,
        y: b.y + b.height / 2.,
    });
    h.settle();
}
/// Scroll the sidebar until the page's row is within the window, then click
/// it (the tree is longer than the window now).
fn nav(h: &mut Harness, page: &str) {
    let id = format!("nav_{page}");
    for _ in 0..40 {
        let b = h.bounds(&id);
        if b.y >= 40. && b.y + b.height <= HEIGHT - 60. {
            break;
        }
        let delta_y = if b.y < 40. { -200. } else { 200. };
        h.ui.dispatch(InputEvent::Scroll {
            x: 100.,
            y: 400.,
            delta_x: 0.,
            delta_y,
        });
        h.settle();
        h.ui.prepare_frame();
    }
    h.click(&id);
}
/// Scroll the canvas until node `id` is within the window.
fn reveal(h: &mut Harness, id: &str) {
    for _ in 0..40 {
        let b = h.bounds(id);
        if b.y >= 60. && b.y + b.height <= HEIGHT - 20. {
            break;
        }
        let delta_y = if b.y < 60. { -300. } else { 300. };
        h.ui.dispatch(InputEvent::Scroll {
            x: 700.,
            y: 450.,
            delta_x: 0.,
            delta_y,
        });
        h.settle();
        h.ui.prepare_frame();
    }
}
/// Scroll the canvas until node `id` is within the window, then click it.
fn reveal_and_click(h: &mut Harness, id: &str) {
    for _ in 0..40 {
        let b = h.bounds(id);
        if b.y >= 60. && b.y + b.height <= HEIGHT - 20. {
            break;
        }
        let delta_y = if b.y < 60. { -300. } else { 300. };
        h.ui.dispatch(InputEvent::Scroll {
            x: 700.,
            y: 450.,
            delta_x: 0.,
            delta_y,
        });
        h.settle();
        h.ui.prepare_frame();
    }
    h.click(id);
}
/// Scroll the list `list` until node `id` inside it is within the list's
/// box.
fn reveal_in(h: &mut Harness, list: &str, id: &str) {
    for _ in 0..40 {
        let l = h.bounds(list);
        let b = h.bounds(id);
        if b.y >= l.y && b.y + b.height <= l.y + l.height {
            break;
        }
        let delta_y = if b.y < l.y { -60. } else { 60. };
        h.ui.dispatch(InputEvent::Scroll {
            x: l.x + l.width / 2.,
            y: l.y + l.height / 2.,
            delta_x: 0.,
            delta_y,
        });
        h.settle();
        h.ui.prepare_frame();
    }
}
/// Run a test's body on a thread with a deep stack: building the node tree
/// recurses once per level in `lower::build`, and a debug build's frames
/// exhaust the test threads' 2 MiB on the deepest pages (the Panels page's
/// window nests a titlebar, a pane strip and its chips inside the page,
/// inside the workbench's columns).
fn deep(body: impl FnOnce() + Send + 'static) {
    let worker = std::thread::Builder::new()
        .stack_size(32 << 20)
        .spawn(body)
        .unwrap();
    if let Err(panic) = worker.join() {
        std::panic::resume_unwind(panic);
    }
}
/// Settle, then check that nothing runs in the script and no frame is
/// wanted: the hot path at rest.
fn rests(h: &mut Harness, what: &str) {
    h.frames(90);
    let calls = h.calls();
    h.frames(60);
    assert_eq!(h.calls(), calls, "{what}: no script on the hot path");
    assert!(!h.clock.wants_frame(), "{what}: no frames wanted");
}

/// Writes a software capture when STYLEGUIDE_SNAPSHOT names a directory;
/// with `STYLEGUIDE_GPU=1`, through the GPU renderer offscreen, at
/// `STYLEGUIDE_SCALE` (the window's look: blur, layers, shadows).
fn snapshot(h: &Harness, name: &str) {
    let Some(dir) = std::env::var_os("STYLEGUIDE_SNAPSHOT") else {
        return;
    };
    let dir = Path::new(&dir);
    let _ = std::fs::create_dir_all(dir);
    h.ui.prepare_frame();
    if std::env::var_os("STYLEGUIDE_GPU").is_some() {
        let scale: f32 = std::env::var("STYLEGUIDE_SCALE")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(1.);
        let (w, hgt) = ((WIDTH * scale) as u32, (HEIGHT * scale) as u32);
        let mut gpu = zgx_gpu::GpuRenderer::new(w, hgt).expect("a GPU adapter");
        gpu.set_scale_factor(scale);
        for bytes in [
            &include_bytes!("../../zgx-desktop/examples/support/fonts/GeistVariable.ttf")[..],
            &include_bytes!("../../zgx-desktop/examples/support/fonts/GeistMonoVariable.ttf")[..],
        ] {
            gpu.text_system()
                .borrow_mut()
                .db_mut()
                .load_font_data(bytes.to_vec());
        }
        gpu.render(
            &h.ui.scene.borrow(),
            &[zgx::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
        )
        .expect("render");
        let pixels = gpu.readback().expect("readback");
        let mut out = format!("P6\n{w} {hgt}\n255\n").into_bytes();
        for rgba in pixels.chunks_exact(4) {
            out.extend_from_slice(&rgba[..3]);
        }
        std::fs::write(dir.join(format!("{name}.ppm")), out).unwrap();
        return;
    }
    let mut raster = zgx_desktop::raster::Raster::new(WIDTH as usize, HEIGHT as usize);
    for bytes in [
        &include_bytes!("../../zgx-desktop/examples/support/fonts/GeistVariable.ttf")[..],
        &include_bytes!("../../zgx-desktop/examples/support/fonts/GeistMonoVariable.ttf")[..],
    ] {
        raster.register_font(&zgx_gpu::text::FontData::new(bytes).unwrap());
    }
    raster.render(
        &h.ui.scene.borrow(),
        &[zgx::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
    );
    raster.write_ppm(&dir.join(format!("{name}.ppm"))).unwrap();
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

#[test]
fn walks_every_page_and_rests() {
    deep(|| {
        let mut h = styleguide();
        healthy(&h);
        h.frames(30);
        assert!(h.find("sidebar").is_some());
        assert_eq!(h.text("page_title"), "Colour");
        for page in PAGES {
            nav(&mut h, page);
            h.frames(40);
            healthy(&h);
            assert!(
                h.find(&format!("page_{page}")).is_some(),
                "the {page} page shows"
            );
            snapshot(&h, page);
        }
        // With snapshots on, every page again in the light theme.
        if std::env::var_os("STYLEGUIDE_SNAPSHOT").is_some() {
            h.click("appearance_toggle");
            h.frames(20);
            h.click("theme_light");
            h.click("appearance_toggle");
            h.frames(20);
            for page in PAGES {
                nav(&mut h, page);
                h.frames(30);
                healthy(&h);
                snapshot(&h, &format!("light_{page}"));
            }
            h.click("appearance_toggle");
            h.frames(20);
            h.click("theme_dark");
            h.click("appearance_toggle");
            h.frames(20);
        }
        // The shell page's jump pill sits inside its window.
        nav(&mut h, "shell");
        h.frames(40);
        let window = h.bounds("shell_window");
        let pill = h.bounds("shell_jump");
        assert!(
            pill.y + pill.height <= window.y + window.height,
            "the jump pill is inside the window: {pill:?} in {window:?}"
        );
        // ⌘K opens the jump palette; typing filters, ↩ opens the first match.
        key(&mut h, Key::Character("k".into()), true);
        h.frames(20);
        assert!(h.find("jump_palette").is_some(), "the palette opens");
        for c in ["c", "h", "a", "n"] {
            key(&mut h, Key::Character(c.into()), false);
        }
        h.frames(10);
        snapshot(&h, "jump");
        key(&mut h, Key::Enter, false);
        h.frames(30);
        assert!(h.find("jump_palette").is_none(), "the palette closes");
        assert_eq!(h.text("page_title"), "Changes");
        key(&mut h, Key::Character("k".into()), true);
        h.frames(10);
        key(&mut h, Key::Escape, false);
        h.frames(20);
        assert!(h.find("jump_palette").is_none(), "esc closes it");
        // ⌘1 goes back to the first page; ⌘0 to the last.
        key(&mut h, Key::Character("0".into()), true);
        h.frames(30);
        assert_eq!(h.text("page_title"), "Parity");
        key(&mut h, Key::Character("1".into()), true);
        h.frames(30);
        assert_eq!(h.text("page_title"), "Colour");
        rests(&mut h, "the colour page");
    });
}

#[test]
fn theme_density_zoom_and_inspector_restyle_in_place() {
    deep(|| {
        let mut h = styleguide();
        h.frames(10);
        // The titlebar spans the window and moves it; its buttons keep their
        // clicks.
        let bar = h.bounds("titlebar");
        assert!(
            bar.x <= 0.5 && bar.width >= WIDTH - 0.5,
            "the titlebar spans the window: {bar:?}"
        );
        assert_eq!(bar.height, 38.);
        // The appearance card holds the theme, its variant, the accent, the
        // material and the density.
        h.click("appearance_toggle");
        h.frames(20);
        snapshot(&h, "appearance");
        // The theme control switches the whole window's theme.
        h.click("theme_light");
        h.frames(30);
        healthy(&h);
        assert_eq!(&*h.ui.theme().current(), "zeron-light");
        h.click("theme_dark");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "zeron-dark");
        // The theme list holds Zeron's families; picking one restyles the
        // window, and the variant toggle moves to that family's sibling.
        assert!(h.find("theme_menu").is_some(), "the theme list shows");
        reveal_in(&mut h, "theme_menu", "theme_pick_catppuccin-mocha");
        h.click("theme_pick_catppuccin-mocha");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "catppuccin-mocha");
        h.click("theme_light");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "catppuccin-latte");
        snapshot(&h, "theme_catppuccin_latte");
        // An accent preset recolours the accent tokens across the window.
        h.click("accent_green");
        h.frames(30);
        snapshot(&h, "accent_green");
        reveal_in(&mut h, "theme_menu", "theme_pick_zeron-dark");
        h.click("theme_pick_zeron-dark");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "zeron-dark");
        h.click("accent_theme");
        h.frames(20);
        key(&mut h, Key::Escape, false);
        h.frames(20);
        // Density and zoom scope the page's tokens: a button shrinks and grows.
        nav(&mut h, "buttons");
        h.frames(40);
        let rest = h.bounds("button_primary");
        h.click("appearance_toggle");
        h.frames(20);
        h.click("density_compact");
        h.frames(30);
        key(&mut h, Key::Escape, false);
        h.frames(20);
        healthy(&h);
        let compact = h.bounds("button_primary");
        assert!(
            compact.height < rest.height,
            "compact: {compact:?} vs {rest:?}"
        );
        if std::env::var_os("STYLEGUIDE_SNAPSHOT").is_some() {
            for page in ["agent", "workspace", "transcript"] {
                nav(&mut h, page);
                h.frames(30);
                snapshot(&h, &format!("compact_{page}"));
            }
            nav(&mut h, "buttons");
            h.frames(30);
        }
        h.click("appearance_toggle");
        h.frames(20);
        h.click("density_comfortable");
        h.frames(20);
        key(&mut h, Key::Escape, false);
        h.frames(20);
        // The inspector is a tool in Files' place: it opens at its own width on
        // the panel curve, the canvas absorbing it, and closes to nothing.
        assert!(
            h.bounds("wb_files").width < 0.5,
            "the inspector starts closed"
        );
        let canvas = h.bounds("wb_conversation").width;
        h.click("inspector_toggle");
        h.frames(4);
        let mid = h.bounds("wb_files").width;
        assert!(mid > 0.5 && mid < 299.5, "it eases open: {mid}");
        h.frames(30);
        healthy(&h);
        assert!((h.bounds("wb_files").width - 300.).abs() < 0.5);
        assert!((h.bounds("wb_conversation").width - (canvas - 300.)).abs() < 0.5);
        snapshot(&h, "inspector");
        h.click("inspector_toggle");
        h.frames(30);
        assert!(h.bounds("wb_files").width < 0.5);
        // (The buttons page's loading spinners turn for as long as it shows.)
        nav(&mut h, "metrics");
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        rests(&mut h, "the metrics page");
    });
}

#[test]
fn controls_answer_the_pointer_and_keyboard() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "buttons");
        h.frames(30);
        h.click("button_primary");
        h.click("button_ghost");
        assert_eq!(h.text("button_clicks"), "clicks: 2");
        // The segmented control is one Tab stop (zgx's focus group): Right
        // moves the focus and the choice with it, and wraps around.
        h.click("seg_labels_week");
        // A click chooses but, as on macOS, gives a button no focus: the
        // keyboard reaches the group by Tab; here, straight.
        let week = h.find("seg_labels_week");
        let scene = h.ui.scene.clone();
        h.ui.input.focus(&scene, week);
        key(&mut h, Key::ArrowRight, false);
        let month = h.find("seg_labels_month");
        assert_eq!(h.ui.input.focused(), month, "the focus moved to Month");
        key(&mut h, Key::ArrowRight, false);
        h.frames(20);
        let day_node = h.find("seg_labels_day");
        assert_eq!(h.ui.input.focused(), day_node, "and wrapped to Day");
        let day = h.bounds("seg_labels_day");
        let week = h.bounds("seg_labels_week");
        assert!(day.x < week.x);
        // Inputs take text; the checkbox and toggle flip.
        nav(&mut h, "inputs");
        h.frames(30);
        h.type_text("field_name", "zgx");
        h.frames(5);
        // Heard as what they are, checked as they show.
        let heard = |h: &mut Harness, id: &str| {
            let node = h.find(id).unwrap();
            let tree = h.ui.semantics.borrow();
            let semantic = tree.get(node).unwrap();
            (semantic.role, semantic.checked)
        };
        use zgx::semantics::Role;
        assert_eq!(heard(&mut h, "check_off"), (Role::CheckBox, Some(false)));
        assert_eq!(heard(&mut h, "toggle_on"), (Role::Switch, Some(true)));
        reveal_and_click(&mut h, "check_off");
        reveal_and_click(&mut h, "toggle_off");
        h.frames(20);
        assert_eq!(heard(&mut h, "check_off"), (Role::CheckBox, Some(true)));
        assert_eq!(heard(&mut h, "toggle_off"), (Role::Switch, Some(true)));
        healthy(&h);
        // Chips: a filter toggles, a removable chip leaves.
        nav(&mut h, "chips");
        h.frames(30);
        h.click("filter_2");
        h.frames(20);
        h.click("tags_reset");
        h.frames(20);
        healthy(&h);
    });
}

/// The agent surfaces and the changes page: the mic steps through its
/// phases, the todo tray folds, a queued row leaves and comes back, the
/// roll takes a new value, a badge's card opens on hover, a diff folds.
#[test]
fn agent_surfaces_and_changes_answer() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "agent");
        h.frames(30);
        healthy(&h);
        // The mic: idle → requesting → listening → processing → idle; the
        // track comes with the first step and leaves on the last.
        assert!(h.find("dict_track").is_none());
        h.click("dict_mic");
        h.frames(30);
        assert!(h.find("dict_track").is_some(), "the track unrolls");
        h.click("dict_mic");
        h.frames(30);
        assert!(
            h.find("dict_mic_stop").is_some(),
            "listening shows the stop square"
        );
        h.click("dict_mic");
        h.click("dict_mic");
        h.frames(40);
        assert!(h.find("dict_track").is_none(), "idle again");
        healthy(&h);
        // The todo tray folds and opens.
        let open = h.bounds("todo").height;
        reveal_and_click(&mut h, "todo_header");
        h.frames(30);
        assert!(h.bounds("todo").height < open, "collapsed is shorter");
        reveal_and_click(&mut h, "todo_header");
        h.frames(30);
        // A queued row leaves; reset brings it back.
        assert!(h.find("queue_q2").is_some());
        reveal_and_click(&mut h, "queue_reset");
        h.frames(20);
        assert!(h.find("queue_q2").is_some());
        // Roll text takes the next value.
        reveal_and_click(&mut h, "roll_next");
        h.frames(50);
        snapshot(&h, "agent_roll");
        healthy(&h);
        // The badge's card after its delay.
        for _ in 0..40 {
            let b = h.bounds("badge");
            if b.y >= 60. && b.y + b.height <= HEIGHT - 20. {
                break;
            }
            h.ui.dispatch(InputEvent::Scroll {
                x: 700.,
                y: 450.,
                delta_x: 0.,
                delta_y: 300.,
            });
            h.settle();
            h.ui.prepare_frame();
        }
        hover(&mut h, "badge");
        assert!(h.find("badge_card").is_none(), "not before 280 ms");
        assert!(h.wait_until(|h| h.find("badge_card").is_some()));
        h.frames(30);
        healthy(&h);
        // Changes: the open file folds, a closed one opens.
        nav(&mut h, "changes");
        h.frames(30);
        let a = h.bounds("page_changes").height;
        h.click("file_a");
        h.frames(30);
        assert!(h.bounds("page_changes").height < a, "the diff folded away");
        h.click("file_b");
        h.frames(30);
        assert!(h.bounds("page_changes").height > a - 100., "another opened");
        healthy(&h);
        rests(&mut h, "the changes page");
        // Under reduced motion the agent page, full of loops, holds still.
        h.click("appearance_toggle");
        h.frames(20);
        h.click("reduced_motion");
        key(&mut h, Key::Escape, false);
        nav(&mut h, "agent");
        h.frames(40);
        rests(&mut h, "the agent page under reduced motion");
        h.click("appearance_toggle");
        h.frames(20);
        h.click("reduced_motion");
        key(&mut h, Key::Escape, false);
        h.frames(20);
        // Workspace: a commit row selects; the tree folds a folder.
        nav(&mut h, "workspace");
        h.frames(30);
        reveal_and_click(&mut h, "commits_3b87140c");
        h.frames(20);
        snapshot(&h, "workspace_history");
        reveal_and_click(&mut h, "tree_kit");
        h.frames(30);
        assert!(h.find("tree_f1").is_none(), "the kit folder folded");
        reveal_and_click(&mut h, "tree_kit");
        h.frames(30);
        assert!(h.find("tree_f1").is_some());
        // The PR detail's checks card folds.
        reveal_and_click(&mut h, "checks_header");
        h.frames(30);
        snapshot(&h, "workspace_detail");
        reveal_and_click(&mut h, "checks_header");
        h.frames(30);
        healthy(&h);
        // Panes: splits add cards, zoom shows one, close takes one away.
        nav(&mut h, "panes");
        h.frames(30);
        assert!(h.find("ws_ws_p0").is_some());
        h.click("ws_split_right");
        h.frames(40);
        h.click("ws_split_down");
        h.frames(40);
        h.click("ws_browser");
        h.frames(40);
        let p0 = h.bounds("ws_ws_p0");
        let p1 = h.bounds("ws_ws_p1");
        assert!(
            p1.x > p0.x + p0.width - 1.,
            "the second pane sits right of the first: {p0:?} {p1:?}"
        );
        snapshot(&h, "panes");
        // Wing's panes: an editor, Hacker News, notes and Claude Code open beside.
        h.click("ws_close");
        h.frames(30);
        h.click("ws_close");
        h.frames(30);
        h.click("ws_editor");
        h.frames(40);
        h.click("ws_hn");
        h.frames(40);
        assert!(
            h.find("wing_editor").is_some() && h.find("wing_hn").is_some(),
            "Wing's panes opened"
        );
        snapshot(&h, "panes_wing");
        h.click("ws_notes");
        h.frames(40);
        h.click("ws_claude");
        h.frames(40);
        snapshot(&h, "panes_wing_more");
        healthy(&h);
        h.click("ws_zoom");
        h.frames(40);
        assert!(
            h.find("ws_ws_p1").is_none(),
            "zoomed: only the focused pane shows"
        );
        h.click("ws_zoom");
        h.frames(40);
        h.click("ws_close");
        h.frames(40);
        healthy(&h);
        // Panels: the floating tabs move with the keys; a browser tab selects.
        nav(&mut h, "panels");
        h.frames(30);
        reveal_and_click(&mut h, "ftabs_code");
        key(&mut h, Key::ArrowRight, false);
        h.frames(30);
        reveal_and_click(&mut h, "btab_b2");
        h.frames(30);
        snapshot(&h, "panels_browser");
        healthy(&h);
        // Settings: a shortcut chip records.
        nav(&mut h, "settings");
        h.frames(30);
        reveal_and_click(&mut h, "sc_record_chip");
        h.frames(20);
        snapshot(&h, "settings_shortcuts");
        reveal_and_click(&mut h, "sc_record_chip");
        h.frames(20);
        healthy(&h);
    });
}

#[test]
fn overlays_open_close_and_rest() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "overlays");
        h.frames(30);
        // A tooltip (zgx's own, in the kit's bubble) after the pointer
        // rests, gone with the pointer. Closed, it stays mounted, unseen.
        let showing = |h: &mut zgx_script::testing::TestApp| {
            h.find("tooltip_search").is_some_and(|node| {
                let scene = h.ui.scene.borrow();
                scene.layout_visible(node) && scene.visible_bounds(node).is_some()
            })
        };
        hover(&mut h, "tip_search");
        h.frames(2);
        assert!(!showing(&mut h.0), "not at once");
        assert!(h.wait_until(|h| {
            h.frames(1);
            showing(h)
        }));
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        assert!(h.wait_until(|h| {
            h.frames(1);
            !showing(h)
        }));
        snapshot(&h, "overlays_tooltip");
        for stage in ["stage_menu", "stage_popover", "stage_toast"] {
            reveal(&mut h, stage);
            h.frames(10);
            snapshot(&h, &format!("overlays_{stage}"));
        }
        // The menu: opens from its trigger, Escape closes it, a choice runs.
        reveal_and_click(&mut h, "menu_trigger");
        h.frames(20);
        assert_eq!(h.text("menu_chose"), "chose: nothing yet · open");
        snapshot(&h, "menu");
        key(&mut h, Key::Escape, false);
        h.frames(20);
        assert_eq!(h.text("menu_chose"), "chose: nothing yet · closed");
        reveal_and_click(&mut h, "menu_trigger");
        h.frames(20);
        h.click("menu_rename");
        h.frames(20);
        assert_eq!(h.text("menu_chose"), "chose: Rename · closed");
        // The dialog: Enter approves, Escape closes.
        reveal_and_click(&mut h, "dialog_trigger");
        h.frames(20);
        assert_eq!(h.text("dialog_state"), "open");
        snapshot(&h, "dialog");
        key(&mut h, Key::Enter, false);
        h.frames(20);
        assert_eq!(h.text("dialog_state"), "closed", "Enter runs the primary");
        reveal_and_click(&mut h, "danger_trigger");
        h.frames(20);
        assert_eq!(h.text("dialog_state"), "danger");
        key(&mut h, Key::Escape, false);
        h.frames(20);
        assert_eq!(h.text("dialog_state"), "closed", "Escape closes the dialog");
        // A toast stacks, then leaves on its own. Its stack is on a layer
        // of its own (over dialogs), open while a toast shows.
        reveal_and_click(&mut h, "toast_push");
        h.frames(30);
        assert!(h.find("toast1").is_some());
        snapshot(&h, "toast");
        let spot = {
            let b = h.bounds("toast1");
            (b.x + b.width / 2., b.y + b.height / 2.)
        };
        let under = |h: &mut Harness| {
            let stack = h.find("toasts").unwrap();
            let scene = h.ui.scene.borrow();
            scene
                .hit_test(spot.0, spot.1)
                .is_some_and(|hit| scene.is_within(hit, stack))
        };
        assert!(under(&mut h), "the pointer over the toast reaches it");
        let stack = h.find("toasts").unwrap();
        assert!(
            !h.ui.scene.borrow().is_within(stack, h.handle.node()),
            "on a layer over the app, not in its tree"
        );
        // Swiped right less than 45 it springs back; past it, it goes.
        let swipe = |h: &mut Harness, by: f32| {
            let b = h.bounds("toast1");
            let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
            let button = zgx::input::PointerButton::Primary;
            h.ui.dispatch(InputEvent::PointerDown { x, y, button });
            h.ui.dispatch(InputEvent::PointerMove { x: x + by, y });
            h.ui.dispatch(InputEvent::PointerUp {
                x: x + by,
                y,
                button,
            });
            h.settle();
            h.frames(30);
        };
        swipe(&mut h, 30.);
        assert!(h.find("toast1").is_some(), "springs back");
        swipe(&mut h, 60.);
        assert!(h.find("toast1").is_none(), "dismissed");
        assert!(!under(&mut h), "its layer closed after the last one went");
        healthy(&h);

        // Three at once (toast.rs, sonner's): collapsed, the newest in
        // front, the two before it peeking 14 and 28 above it, each 5%
        // narrower, the stack as tall as it shows; under the pointer they
        // fan out 14 apart and whole, with no script while they rest; away,
        // they collapse again.
        for id in ["toast_push", "toast_push_action", "toast_push_error"] {
            reveal_and_click(&mut h, id);
            h.frames(5);
        }
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        h.frames(40);
        let shown = |h: &mut Harness, id: &str| {
            let node = h.find(&format!("{id}_slot")).expect(id);
            h.ui.scene.borrow().transformed_bounds(node)
        };
        let all = |h: &mut Harness| (shown(h, "toast2"), shown(h, "toast3"), shown(h, "toast4"));
        let (back, middle, front) = all(&mut h);
        snapshot(&h, "toasts_collapsed");
        assert!(
            (middle.y - (front.y - 14.)).abs() < 1.,
            "{middle:?} {front:?}"
        );
        assert!((back.y - (front.y - 28.)).abs() < 1., "{back:?} {front:?}");
        assert!((front.width - 356.).abs() < 0.5, "{front:?}");
        assert!(
            (middle.width - 356. * 0.95).abs() < 1. && (back.width - 356. * 0.9).abs() < 1.,
            "each 5% narrower: {back:?} {middle:?}"
        );
        assert!(
            middle.y + middle.height <= front.y + front.height + 0.5
                && back.y + back.height <= front.y + front.height + 0.5,
            "the ones behind clipped to the front's height"
        );
        let stack = h.bounds("toasts");
        assert!(
            (stack.height - (front.height + 28.)).abs() < 1.,
            "{stack:?}"
        );
        h.ui.dispatch(InputEvent::PointerMove {
            x: front.x + front.width / 2.,
            y: front.y + front.height / 2.,
        });
        h.frames(40);
        let (back, middle, front) = all(&mut h);
        snapshot(&h, "toasts_expanded");
        assert!(
            (middle.y + middle.height + 14. - front.y).abs() < 1.,
            "{middle:?} {front:?}"
        );
        assert!(
            (back.y + back.height + 14. - middle.y).abs() < 1.,
            "{back:?} {middle:?}"
        );
        assert!((back.width - 356.).abs() < 0.5, "whole again");
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls, "held, nothing runs");
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        h.frames(40);
        let (_, middle, front) = all(&mut h);
        assert!((middle.y - (front.y - 14.)).abs() < 1., "collapsed again");
        // Swiped away, the front each time, the next one coming forward.
        for id in ["toast4", "toast3", "toast2"] {
            let b = shown(&mut h, id);
            let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
            let button = zgx::input::PointerButton::Primary;
            h.ui.dispatch(InputEvent::PointerDown { x, y, button });
            h.ui.dispatch(InputEvent::PointerMove { x: x + 60., y });
            h.ui.dispatch(InputEvent::PointerUp {
                x: x + 60.,
                y,
                button,
            });
            h.settle();
            h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
            h.frames(30);
            assert!(h.find(id).is_none(), "{id} dismissed");
        }
        rests(&mut h, "the overlays page");
    });
}

#[test]
fn composer_shows_every_state() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "composer");
        h.frames(30);
        for (state, inside) in [
            ("typing", "composer_send"),
            ("attachments", "composer_box"),
            ("uploading", "composer_box"),
            ("sending", "composer_sending"),
            ("working", "composer_send"),
            ("steer", "composer_send"),
            ("compact", "composer_box"),
            ("docked", "composer_box"),
            ("queue", "queue_dock"),
            ("question", "question_dock_option_1"),
            ("error", "error_dock"),
            ("picker", "reference_picker"),
        ] {
            reveal_and_click(&mut h, &format!("composer_{state}"));
            h.frames(40);
            healthy(&h);
            assert!(h.find(inside).is_some(), "{state} shows {inside}");
            snapshot(&h, &format!("composer_{state}"));
        }
        // The docked footer's context chip opens its card above it.
        reveal_and_click(&mut h, "composer_docked");
        h.frames(30);
        reveal_and_click(&mut h, "composer_context");
        h.frames(30);
        assert!(
            h.texts().iter().any(|t| t.contains("tokens remaining")),
            "the context card opens"
        );
        h.key(Key::Escape);
        h.frames(30);
        // A question's choice selects.
        reveal_and_click(&mut h, "composer_question");
        h.frames(30);
        reveal_and_click(&mut h, "question_dock_option_2");
        h.frames(10);
        // Typing while a run works: send queues the draft and clears it.
        reveal_and_click(&mut h, "composer_steer");
        h.frames(40);
        assert!(
            h.find("composer_send").is_some(),
            "the click after choosing lands"
        );
        reveal_and_click(&mut h, "composer_send");
        h.frames(30);
        assert_eq!(h.text("composer_current"), "state: steer");
        healthy(&h);
        reveal_and_click(&mut h, "composer_empty");
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        rests(&mut h, "the composer page");
    });
}

/// Each mini app mounts on its own, answers its keys, and rests.
#[test]
fn mini_apps_mount_and_rest() {
    deep(|| {
        for (name, size, inside) in [
            ("zeron", (1180., 760.), "composer"),
            ("palette", (560., 440.), "picker"),
            ("settings", (760., 600.), "settings_app"),
        ] {
            let mut h = Harness::new(|runtime| {
                let host = ScriptHost::new(
                    runtime,
                    Path::new(env!("CARGO_MANIFEST_DIR"))
                        .join(format!("examples/styleguide/app_{name}.luau")),
                );
                host.action("inspect", |_| {});
                host.action("close_window", |_| {});
                host.action("open_app", |_| {});
                host
            });
            h.ui.scene.borrow_mut().resize(size.0, size.1);
            h.ui.prepare_frame();
            h.settle();
            h.frames(30);
            healthy(&h);
            assert!(h.find(inside).is_some(), "{name} shows {inside}");
            if name == "zeron" {
                key(&mut h, Key::Character("k".into()), true);
                h.frames(20);
                healthy(&h);
                assert!(h.find("palette").is_some(), "⌘K opens the palette");
                key(&mut h, Key::Escape, false);
                h.frames(20);
                assert!(h.find("palette").is_none(), "Escape closes it");
                // Zeron's titlebar names the session and spans the window.
                assert_eq!(h.text("ztitle_title"), "Write the release notes");
                assert!(h.bounds("ztitle").width >= size.0 - 0.5);
                // The pane opens beside the conversation, the two splitting what
                // the sidebar leaves; its surfaces' chips ride the titlebar.
                h.click("zeron_pane_toggle");
                h.frames(40);
                healthy(&h);
                let conversation = h.bounds("zcols_conversation").width;
                let pane = h.bounds("zcols_right").width;
                assert!(
                    (conversation - pane).abs() <= 1.,
                    "{conversation} vs {pane}"
                );
                assert!(
                    h.find("zchange_file_1").is_some(),
                    "the changes surface shows the diff"
                );
                assert!(
                    h.find("composer").is_some(),
                    "the conversation stays beside it"
                );
                snapshot(&h, "app_zeron_changes");
                h.click("zp_tab_zgx");
                h.frames(40);
                assert!(
                    h.find("zws_editor").is_some() && h.find("zws_hn").is_some(),
                    "Wing's editor and Hacker News"
                );
                snapshot(&h, "app_zeron_wing");
                // Files opens at its own width as far as the chat's 300 and the
                // pane's 360 allow beside the sidebar (here 264 of its 286); the
                // content columns re-split.
                h.click("zeron_files_toggle");
                h.frames(40);
                let files = h.bounds("zcols_files").width;
                let room = size.0 - 256. - 300. - 360.;
                assert!((files - room.min(286.)).abs() < 0.5, "Files: {files}");
                let conversation = h.bounds("zcols_conversation").width;
                let pane = h.bounds("zcols_right").width;
                // Halves of what the tools leave, unless that breaks the pane's
                // 360: then the pane keeps 360 and the chat the rest.
                let available = size.0 - 256. - files;
                let share = (available / 2.).max(360.).min((available - 300.).max(360.));
                assert!(
                    (pane - share).abs() <= 1.,
                    "re-split: {conversation} vs {pane}"
                );
                assert!((conversation + pane - available).abs() <= 1.);
                snapshot(&h, "app_zeron_files");
                h.click("zeron_files_toggle");
                h.frames(40);
                h.click("zeron_pane_toggle");
                h.frames(40);
                assert!(h.bounds("zcols_right").width < 0.5);
            }
            snapshot(&h, &format!("app_{name}"));
            // The Zeron app's working agent turns its arc, and the palette's caret
            // blinks, for as long as they show.
            if name == "settings" {
                rests(&mut h, name);
            } else {
                h.frames(60);
                let calls = h.calls();
                h.frames(60);
                assert_eq!(h.calls(), calls, "{name}: no script on the hot path");
            }
        }
    });
}

/// The reasoning slider answers a click and a drag; the compact picker's
/// panel answers the keys (effort, fast mode), swaps to its models page and
/// back on a pick, and the composer's chip opens the real card.
#[test]
fn compact_picker_and_slider_answer() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "pickers");
        h.frames(40);
        healthy(&h);
        // A click in the middle of five stops lands on the third.
        reveal_and_click(&mut h, "slider_plain");
        h.frames(30);
        assert_eq!(h.text("slider_plain_value"), "High");
        // A drag to the left end lands on the first, as the pointer goes.
        let b = h.bounds("slider_plain");
        let y = b.y + b.height / 2.;
        let (dragged, _) = h.host.haptics();
        h.ui.dispatch(InputEvent::PointerDown {
            x: b.x + b.width / 2.,
            y,
            button: PointerButton::Primary,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: b.x + 4., y });
        h.settle();
        h.ui.dispatch(InputEvent::PointerUp {
            x: b.x + 4.,
            y,
            button: PointerButton::Primary,
        });
        h.frames(30);
        assert_eq!(h.text("slider_plain_value"), "Low");
        assert_eq!(h.host.haptics().0, dragged + 1, "a tap for the new stop");
        snapshot(&h, "pickers_slider");
        // The panel: fast mode toggles from its bolt, and the card's keys set
        // the effort once something in it has focus.
        assert!(h.text("cp_state").contains("fast: off"));
        reveal_and_click(&mut h, "cp_fast");
        h.frames(30);
        assert!(
            h.text("cp_state").contains("fast: on"),
            "{}",
            h.text("cp_state")
        );
        reveal_and_click(&mut h, "cp_slider");
        h.frames(30);
        assert!(
            h.text("cp_state").contains("effort: High"),
            "{}",
            h.text("cp_state")
        );
        let (taps, _) = h.host.haptics();
        key(&mut h, Key::ArrowRight, false);
        h.frames(30);
        assert!(
            h.text("cp_state").contains("effort: X-High"),
            "{}",
            h.text("cp_state")
        );
        key(&mut h, Key::Home, false);
        h.frames(30);
        assert!(
            h.text("cp_state").contains("effort: Low"),
            "{}",
            h.text("cp_state")
        );
        // One haptic a step change (pickers.rs), none at an end it stays on.
        key(&mut h, Key::Home, false);
        key(&mut h, Key::ArrowLeft, false);
        h.frames(10);
        assert_eq!(
            h.host.haptics(),
            (taps + 2, Some(zgx::platform::Haptic::Level))
        );
        snapshot(&h, "pickers_panel");
        // The models page: a row picks its model and returns to the panel.
        reveal_and_click(&mut h, "cpm_m_gpt");
        h.frames(40);
        assert!(
            h.text("cp_state").contains("model: GPT-5.5 Codex"),
            "{}",
            h.text("cp_state")
        );
        assert!(
            h.find("cpm_panel").is_some(),
            "the pick returns to the panel"
        );
        // Its option rows open their choices.
        reveal_and_click(&mut h, "cpm_opt_1");
        h.frames(30);
        assert!(
            h.find("cpm_opt_verbosity_High").is_some(),
            "the choices open"
        );
        reveal_and_click(&mut h, "cpm_opt_verbosity_High");
        h.frames(30);
        // The title opens the models page; the star keeps a favourite.
        reveal_and_click(&mut h, "cp_title");
        h.frames(40);
        assert!(h.find("cp_models").is_some(), "the title opens the list");
        // The star shows under the pointer, then takes the click.
        hover(&mut h, "cp_m_haiku");
        h.frames(10);
        hover(&mut h, "cp_star_haiku");
        h.click("cp_star_haiku");
        h.frames(30);
        assert!(h.find("cp_models").is_some(), "a star keeps the list open");
        assert!(
            h.text("cp_state").contains("model: GPT-5.5 Codex"),
            "a star does not pick"
        );
        reveal_and_click(&mut h, "cp_back");
        h.frames(40);
        assert!(h.find("cp_panel").is_some(), "back returns to the panel");
        // The composer's chip opens the live card, which takes the keys.
        reveal_and_click(&mut h, "pcomp_model");
        h.frames(30);
        key(&mut h, Key::End, false);
        h.frames(30);
        assert!(
            h.text("cp_state").contains("effort: X-High"),
            "{}",
            h.text("cp_state")
        );
        snapshot(&h, "pickers_live");
        key(&mut h, Key::Escape, false);
        h.frames(30);
        healthy(&h);
        // With fast mode off on the lone slider (the chosen model has none),
        // nothing loops: the page rests.
        reveal_and_click(&mut h, "slider_fast_toggle");
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        h.frames(30);
        healthy(&h);
        rests(&mut h, "the pickers page");
    });
}

/// The sent-turn hold: sending reserves a runway and glides the prompt to
/// the top of the frame; the reply streams into the room below.
#[test]
fn sent_turn_glides_to_the_top() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "transcript");
        h.frames(40);
        reveal_and_click(&mut h, "hold_send");
        h.frames(60);
        healthy(&h);
        let frame = h.bounds("hold_scroll");
        let turn = h.bounds("hold_turn_1");
        assert!(
            (turn.y - (frame.y + 10.)).abs() <= 3.,
            "the prompt rests 10 under the top: {turn:?} in {frame:?}"
        );
        assert!(
            h.text("hold_state").contains("held: yes"),
            "{}",
            h.text("hold_state")
        );
        snapshot(&h, "transcript_hold");
        // The reply streams in (timers run in real time: the third paragraph
        // lands at 1.4 s); the prompt does not move while held, and the pin
        // takes over if the reply outgrows the runway.
        assert!(
            h.wait_until(|h| h.find("hold_reply_1_3").is_some()),
            "the reply streams in"
        );
        h.frames(30);
        healthy(&h);
        let after = h.bounds("hold_turn_1");
        assert!(
            after.y <= turn.y + 1.,
            "the prompt never drifts down: {after:?}"
        );
        snapshot(&h, "transcript_hold_reply");
        reveal_and_click(&mut h, "hold_reset");
        h.frames(30);
        assert!(h.text("hold_state").contains("held: no"));
        // The page's own working trailers keep spinning; the script stays off
        // the hot path.
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        h.frames(60);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(h.calls(), calls, "no script on the hot path after a send");
    });
}

/// The Panels page's window follows Zeron's panel policy.
#[test]
fn panels_follow_the_policy() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "panels");
        h.frames(40);
        healthy(&h);
        reveal_and_click(&mut h, "pd_window");
        let state = |h: &mut Harness| h.text("pd_state");
        let inner = h.bounds("pd").width;
        let half = (inner / 2.).floor();
        assert_eq!(
            state(&mut h),
            format!(
                "sidebar 256 · conversation {} · pane closed · files closed",
                inner - 256.
            )
        );
        // Closing the sidebar gives the conversation the window.
        h.click("pd_titlebar_sidebar");
        h.frames(30);
        assert!(state(&mut h).starts_with("sidebar closed"));
        // The pane opens on the panel curve and splits the room equally.
        h.click("pd_pane_toggle");
        h.frames(4);
        let mid = h.bounds("pd_right").width;
        assert!(mid > 0.5 && mid < half - 0.5, "the pane eases open: {mid}");
        h.frames(30);
        let s = state(&mut h);
        assert!(
            s.contains(&format!("pane {half}")) || s.contains(&format!("pane {}", half + 1.)),
            "{s}"
        );
        // A dragged divider holds until the next toggle.
        let seam = |h: &mut Harness| {
            let b = h.bounds("pd_seam_right");
            (b.x + b.width / 2., b.y + b.height / 2.)
        };
        let (x, y) = seam(&mut h);
        let primary = PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: primary,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: x - 60., y });
        h.settle();
        h.ui.dispatch(InputEvent::PointerUp {
            x: x - 60.,
            y,
            button: primary,
        });
        h.frames(2);
        let s = state(&mut h);
        assert!(s.ends_with("divider held"), "{s}");
        h.click("pd_pane_toggle");
        h.frames(30);
        h.click("pd_pane_toggle");
        h.frames(30);
        let s = state(&mut h);
        assert!(!s.contains("held"), "a toggle re-splits: {s}");
        // A double click on the seam resets the split.
        let (x, y) = seam(&mut h);
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: primary,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: x - 40., y });
        h.settle();
        h.ui.dispatch(InputEvent::PointerUp {
            x: x - 40.,
            y,
            button: primary,
        });
        h.frames(2);
        assert!(state(&mut h).ends_with("divider held"));
        h.frames(30);
        let (x, y) = seam(&mut h);
        for _ in 0..2 {
            h.ui.dispatch(InputEvent::PointerDown {
                x,
                y,
                button: primary,
            });
            h.settle();
            h.ui.dispatch(InputEvent::PointerUp {
                x,
                y,
                button: primary,
            });
            h.settle();
        }
        h.frames(30);
        let s = state(&mut h);
        assert!(!s.contains("held"), "a double click resets: {s}");
        let split = h.bounds("pd_conversation").width;
        // Expand covers the conversation, which keeps its layout beneath.
        h.click("pd_expand");
        h.frames(40);
        assert!(h.bounds("pd_conversation").width < 0.5);
        assert!((h.bounds("pd_conversation_content").width - split).abs() < 1.);
        assert!(state(&mut h).ends_with("expanded"));
        snapshot(&h, "panels_expanded");
        h.click("pd_collapse");
        h.frames(40);
        assert!((h.bounds("pd_conversation").width - split).abs() < 1.);
        // Narrowing the window applies at once: the pane no longer fits
        // beside the chat's 300, so it leaves; widening brings it back.
        let g = h.bounds("pd_grip");
        let (gx, gy) = (g.x + g.width / 2., g.y + g.height / 2.);
        h.ui.dispatch(InputEvent::PointerDown {
            x: gx,
            y: gy,
            button: primary,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove {
            x: gx - 320.,
            y: gy,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerUp {
            x: gx - 320.,
            y: gy,
            button: primary,
        });
        h.frames(1);
        let s = state(&mut h);
        assert!(s.contains("pane hidden"), "{s}");
        assert!(h.bounds("pd_right").width < 0.5, "applied at once");
        snapshot(&h, "panels_narrow");
        h.click("pd_full");
        h.frames(2);
        assert!(
            state(&mut h).contains(&format!("pane {half}"))
                || state(&mut h).contains(&format!("pane {}", half + 1.))
        );
        // Too narrow for the sidebar beside the pane: the least recently
        // opened leaves, and asking for it brings it back.
        h.click("pd_titlebar_sidebar");
        h.frames(30);
        let s = state(&mut h);
        assert!(
            s.starts_with("sidebar 256") && s.contains("pane hidden"),
            "{s}"
        );
        h.click("pd_pane_toggle");
        h.frames(30);
        let s = state(&mut h);
        assert!(
            s.starts_with("sidebar hidden") && !s.contains("pane hidden"),
            "{s}"
        );
        // Files keeps its width as far as the chat's 300 allows.
        h.click("pd_files_toggle");
        h.frames(30);
        snapshot(&h, "panels_files");
        healthy(&h);
        // The page's working agents turn their arcs; the script stays off
        // the hot path. (The seams' double-click windows are real-time
        // timers: let the last one lapse first.)
        std::thread::sleep(std::time::Duration::from_millis(400));
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        h.frames(60);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(
            h.calls(),
            calls,
            "the panels page: no script on the hot path"
        );
    });
}

/// Wing's panes under Zeron's panel policy.
#[test]
fn panes_follow_the_policy() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "panes");
        h.frames(30);
        let primary = PointerButton::Primary;
        let width = |h: &mut Harness, id: &str| h.bounds(&format!("ws_ws_{id}")).width;
        // Three panes in a row share it equally (not a half and two quarters).
        h.click("ws_split_right");
        h.frames(40);
        h.click("ws_split_right");
        h.frames(40);
        let (a, b, c) = (
            width(&mut h, "p0"),
            width(&mut h, "p1"),
            width(&mut h, "p3"),
        );
        assert!(
            (a - b).abs() <= 1. && (b - c).abs() <= 1.,
            "equal thirds: {a} {b} {c}"
        );
        // A dragged divider holds until the next change of structure.
        let d = h.bounds("ws_ws_s2");
        let (x, y) = (d.x + d.width / 2., d.y + d.height / 2.);
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: primary,
        });
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: x + 60., y });
        h.settle();
        h.ui.dispatch(InputEvent::PointerUp {
            x: x + 60.,
            y,
            button: primary,
        });
        h.frames(10);
        assert!(
            h.text("ws_state").ends_with("divider held"),
            "{}",
            h.text("ws_state")
        );
        assert!(width(&mut h, "p0") > width(&mut h, "p1") + 50.);
        // A double click on it shares equally again.
        std::thread::sleep(std::time::Duration::from_millis(400));
        let d = h.bounds("ws_ws_s2");
        let (x, y) = (d.x + d.width / 2., d.y + d.height / 2.);
        for _ in 0..2 {
            h.ui.dispatch(InputEvent::PointerDown {
                x,
                y,
                button: primary,
            });
            h.settle();
            h.ui.dispatch(InputEvent::PointerUp {
                x,
                y,
                button: primary,
            });
            h.settle();
        }
        h.frames(40);
        assert!(
            !h.text("ws_state").contains("held"),
            "{}",
            h.text("ws_state")
        );
        assert!((width(&mut h, "p0") - width(&mut h, "p1")).abs() <= 1.);
        // Too many for the area at 160 each: the least recently focused
        // leaves; bringing it back ranks it most recent, and another leaves.
        for _ in 0..3 {
            h.click("ws_split_right");
            h.frames(40);
        }
        healthy(&h);
        assert!(
            h.text("ws_state").contains("hidden"),
            "{}",
            h.text("ws_state")
        );
        assert!(
            h.find("ws_ws_p0").is_none(),
            "the least recently focused pane leaves"
        );
        snapshot(&h, "panes_hidden");
        // Two left (p0, then p1); bringing the latest back focuses it and
        // ranks it most recent, so the next least recent (p3) leaves.
        assert!(h.find("ws_ws_p1").is_none());
        reveal_and_click(&mut h, "ws_bring_back");
        h.frames(40);
        assert!(h.find("ws_ws_p1").is_some(), "it comes back");
        assert!(h.find("ws_ws_p3").is_none(), "the next least recent leaves");
        assert!(h.text("ws_state").contains("focus ws_p1"));
        healthy(&h);
        std::thread::sleep(std::time::Duration::from_millis(400));
        h.settle();
        h.ui.dispatch(InputEvent::PointerMove { x: 5., y: 500. });
        rests(&mut h, "the panes page");
    });
}

/// Every label the kit sets on a fill reads at 4.5:1 or more, in every
/// state, in every theme and with every accent preset.
#[test]
fn labels_read_on_their_fills_everywhere() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "colour");
        h.frames(20);
        healthy(&h);
        let floor = |h: &mut Harness| -> (f32, String) {
            let text = h.text("contrast_floor");
            let ratio = text
                .trim_start_matches("floor ")
                .split(':')
                .next()
                .and_then(|r| r.parse::<f32>().ok())
                .unwrap_or(0.);
            (ratio, text)
        };
        let names: Vec<String> =
            h.ui.theme()
                .names()
                .into_iter()
                .filter(|n| !n.starts_with("zgx"))
                .collect();
        assert!(names.len() >= 30, "every theme is loaded: {names:?}");
        let mut failures = Vec::new();
        for name in &names {
            h.ui.theme().set(name).unwrap();
            h.frames(3);
            let (ratio, text) = floor(&mut h);
            if ratio < 4.5 {
                failures.push(format!("{name}: {text}"));
            }
        }
        // The accent presets, in a dark and a light theme.
        h.ui.theme().set("zeron-dark").unwrap();
        h.frames(3);
        h.click("appearance_toggle");
        h.frames(20);
        for theme in ["zeron-dark", "zeron-light"] {
            h.ui.theme().set(theme).unwrap();
            h.frames(5);
            for accent in ["zeron", "orange", "amber", "green", "cyan", "blue", "pink"] {
                h.click(&format!("accent_{accent}"));
                h.frames(3);
                let (ratio, text) = floor(&mut h);
                if ratio < 4.5 {
                    failures.push(format!("{theme} + {accent}: {text}"));
                }
            }
        }
        assert!(
            failures.is_empty(),
            "labels under 4.5:1:\n{}",
            failures.join("\n")
        );
    });
}

/// Glide: a list's one wash travels to the row under the pointer.
#[test]
fn list_rows_wash_under_the_pointer_without_script() {
    deep(|| {
        let mut h = styleguide();
        // A row's wash is its first child: shown on the hovered row alone.
        let washed = |h: &mut Harness, row: &str| {
            let node = h.find(row).expect(row);
            let layer = h.ui.scene.borrow().children(node)[0];
            match h.ui.scene.borrow().kind(layer) {
                zgx::scene::NodeKind::Panel { quad, .. } => quad.fill.3 > 0,
                _ => false,
            }
        };
        nav(&mut h, "changes");
        h.frames(30);
        reveal(&mut h, "file_b");
        hover(&mut h, "file_a");
        h.frames(5);
        let calls = h.calls();
        hover(&mut h, "file_b");
        h.frames(5);
        assert!(washed(&mut h, "file_b") && !washed(&mut h, "file_a"));
        assert_eq!(h.calls(), calls, "the wash is the engine's: no script");
        healthy(&h);
    });
}

/// The Panels page's surfaces follow the look: the surface mode fills
/// them, and the double border's rim comes and goes with its switch.
#[test]
fn panels_surfaces_follow_the_look() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "panels");
        h.frames(20);
        reveal(&mut h, "surfaces_well");
        let quad = |h: &mut Harness, id: &str| {
            let node = h.find(id).unwrap();
            match h.ui.scene.borrow().kind(node) {
                zgx::scene::NodeKind::Panel { quad, .. } | zgx::scene::NodeKind::Quad(quad) => {
                    quad.clone()
                }
                _ => panic!("{id} paints no box"),
            }
        };
        let rim = |h: &mut Harness, id: &str| {
            quad(h, id)
                .decoration
                .as_ref()
                .and_then(|d| d.inset_shadows.as_ref())
                .map_or(0, |l| l.len())
        };
        assert_eq!(rim(&mut h, "surfaces_well"), 2, "a ring and a top band");
        assert_eq!(rim(&mut h, "surfaces_card"), 2);
        assert!(quad(&mut h, "surfaces_well").fill.3 < 255, "frosted");
        snapshot(&h, "surfaces");
        reveal_and_click(&mut h, "surfaces_rim");
        h.frames(10);
        assert_eq!(rim(&mut h, "surfaces_well"), 0, "the double border off");
        assert_eq!(rim(&mut h, "surfaces_card"), 0);
        reveal_and_click(&mut h, "surfaces_rim");
        reveal_and_click(&mut h, "surfaces_mode_opaque");
        h.frames(10);
        assert_eq!(quad(&mut h, "surfaces_well").fill.3, 255, "opaque");
        snapshot(&h, "surfaces_opaque");
        reveal_and_click(&mut h, "surfaces_mode_theme");
        h.frames(10);
        healthy(&h);
    });
}

#[test]
fn the_sidebar_specimen_keeps_an_empty_section_of_its_own() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "lists");
        h.frames(40);
        healthy(&h);
        // A section of the user's own with nothing in it yet says where
        // sessions go; its chevron points down, as an open section's does.
        assert!(h.find("sg_sidebar").is_some());
        assert!(h.texts().iter().any(|t| t == "Drop sessions here"));
        let node = h.find("side_later_chevron").expect("the section's chevron");
        let rotate = h.ui.scene.borrow().local_transform(node).rotate;
        assert_eq!(rotate.to_degrees().round(), 90.);
    });
}

/// Zeron's activity wave (proto/src/motion.rs gspin_opacity): full at the
/// cycle's start, to 10% by 45%, held to 92%, back to full.
fn gspin(t: f32) -> f32 {
    let t = t.rem_euclid(1.);
    if t < 0.45 {
        1. + (0.1 - 1.) * t / 0.45
    } else if t < 0.92 {
        0.1
    } else {
        0.1 + 0.9 * (t - 0.92) / 0.08
    }
}
/// A loader's cells: the children of each row of node `id`, in order.
fn loader_cells(h: &mut Harness, id: &str) -> Vec<zgx::scene::NodeId> {
    let node = h.find(id).unwrap_or_else(|| panic!("no {id}"));
    let scene = h.ui.scene.borrow();
    scene
        .children(node)
        .iter()
        .flat_map(|row| scene.children(*row).to_vec())
        .collect()
}
/// Whether `opacities` are the wave at one moment, cell `i` `phases[i]` of
/// a cycle ahead.
fn on_the_wave(opacities: &[f32], phases: &[f32]) -> bool {
    (0..1000).any(|step| {
        let t = step as f32 / 1000.;
        opacities
            .iter()
            .zip(phases)
            .all(|(o, p)| (o - gspin(t + p)).abs() < 0.04)
    })
}

/// The loaders are Zeron's: the gradient spinner's nine cells half a cell
/// apart in the sunrise rows, the mini spinner's six in a 2.5 by 4 cell
/// footprint, each cell on the activity wave at its own phase, all of it in
/// the engine (no script a frame); under reduced motion they hold still.
#[test]
fn loaders_run_zerons_wave_in_the_engine_and_hold_still_when_reduced() {
    deep(|| {
        let mut h = styleguide();
        nav(&mut h, "patterns");
        h.frames(30);
        reveal(&mut h, "patterns_gspin_grid");
        healthy(&h);
        let grid = h.bounds("patterns_gspin_grid");
        assert_eq!(
            (grid.width, grid.height),
            (10., 10.),
            "3 cells of 2.5, 1.25 apart"
        );
        let cells = loader_cells(&mut h, "patterns_gspin_grid");
        assert_eq!(cells.len(), 9);
        let top = match h.ui.scene.borrow().kind(cells[0]) {
            zgx::scene::NodeKind::Quad(q) | zgx::scene::NodeKind::Panel { quad: q, .. } => q.fill,
            other => panic!("a cell paints a box: {other:?}"),
        };
        assert_eq!((top.0, top.1, top.2), (0xb6, 0xd3, 0xef), "blue on top");
        // A cell's phase is its distance from the bottom centre, a quarter
        // of the cycle a step.
        let gspin_phases: Vec<f32> = (0..9usize)
            .map(|i| {
                let (r, c) = (i / 3, i % 3);
                (2 - r + c.abs_diff(1)) as f32 / 4.
            })
            .collect();
        let mini = h.bounds("patterns_mini");
        assert_eq!((mini.width, mini.height), (5., 8.));
        let mini_cells = loader_cells(&mut h, "patterns_mini");
        assert_eq!(mini_cells.len(), 6);
        // The ring, clockwise from the top left, a sixth apart.
        let mini_phases: Vec<f32> = [0., 1., 5., 2., 4., 3.].iter().map(|k| k / 6.).collect();
        let calls = h.calls();
        let mut low = 1f32;
        for _ in 0..60 {
            h.frame();
            let scene = h.ui.scene.borrow();
            let o: Vec<f32> = cells.iter().map(|c| scene.effects(*c).opacity).collect();
            assert!(
                on_the_wave(&o, &gspin_phases),
                "gradient spinner off the wave: {o:?}"
            );
            let m: Vec<f32> = mini_cells
                .iter()
                .map(|c| scene.effects(*c).opacity)
                .collect();
            assert!(
                on_the_wave(&m, &mini_phases),
                "mini spinner off the wave: {m:?}"
            );
            low = low.min(o.iter().cloned().fold(1., f32::min));
        }
        assert!(low < 0.12, "cells rest at 10%: {low}");
        assert_eq!(h.calls(), calls, "the loaders run in the engine");
        snapshot(&h, "loaders");
        // Skeleton rows breathe between 0.35 and 0.75.
        let rows = h.find("patterns_skeleton").unwrap();
        let first = h.ui.scene.borrow().children(rows)[0];
        let breath = h.ui.scene.borrow().effects(first).opacity;
        assert!((0.34..=0.76).contains(&breath), "{breath}");

        // Reduced motion: every cell still at 0.6, nothing wanted.
        h.click("appearance_toggle");
        h.frames(20);
        h.click("reduced_motion");
        key(&mut h, Key::Escape, false);
        h.frames(30);
        reveal(&mut h, "patterns_gspin_grid");
        for id in ["patterns_gspin_grid", "patterns_mini"] {
            for c in loader_cells(&mut h, id) {
                assert_eq!(
                    h.ui.scene.borrow().effects(c).opacity,
                    0.6,
                    "{id} holds still"
                );
            }
        }
        rests(&mut h, "the loaders under reduced motion");
        h.click("appearance_toggle");
        h.frames(20);
        h.click("reduced_motion");
        key(&mut h, Key::Escape, false);
        h.frames(20);
        healthy(&h);
    });
}
