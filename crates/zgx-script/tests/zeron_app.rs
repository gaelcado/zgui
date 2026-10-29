//! The Zeron app (examples/styleguide/app_zeron.luau), headless: its two
//! layouts around the same columns, its two routes each under the panel
//! policy, the right pane's tabs and ⌘W, and back and forward. With
//! `STYLEGUIDE_SNAPSHOT=<dir>` it writes PPM snapshots there.
mod common;

use common::Harness;
use std::path::Path;
use zgx::input::{InputEvent, Key, Modifiers};
use zgx_script::{ScriptHost, Value};

const WIDTH: f32 = 1280.;
const HEIGHT: f32 = 800.;
/// The shell's inset (`zeron.well.gap`): from the window's edges to a card,
/// and between two cards.
const INSET: f32 = 6.;

fn host(runtime: &zgx::reactive::Runtime) -> ScriptHost {
    let host = ScriptHost::new(
        runtime,
        Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide/app_zeron.luau"),
    );
    host.action("inspect", |_| {});
    host.action("close_window", |_| {});
    host.action("open_app", |_| {});
    host
}

fn app() -> Harness {
    started(Harness::new(host))
}

/// The app with its sample session's replies played at `pace` (0.5: half
/// as fast), for tests that watch a turn as it streams.
fn paced_app(pace: f64) -> Harness {
    started(Harness::new(move |runtime| {
        let host = host(runtime);
        host.shared("stream_pace", pace);
        host
    }))
}

/// The app in a window that shows pages as its own, and with `terminals`
/// Ghostty's terminals, as the desktop host's does on macOS; the window's
/// native views, where its pages and terminals mount.
fn native_app(terminals: bool) -> (Harness, zgx::native_view::NativeViews) {
    let natives = zgx::native_view::NativeViews::new();
    natives.set_supported(true);
    natives.set_terminals(terminals);
    let window = natives.clone();
    let h = Harness::wrapped(host, move |view| zgx::compose::provide(window, view));
    (started(h), natives)
}

fn started(h: Harness) -> Harness {
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    h.ui.prepare_frame();
    h.settle();
    h.frames(30);
    healthy(&h);
    h
}

fn healthy(h: &Harness) {
    if let Some(e) = h.error() {
        panic!("script error: {e}");
    }
}

fn cmd(h: &mut Harness, key: &str, shift: bool) {
    h.key_with(
        Key::Character(key.into()),
        Modifiers {
            meta: true,
            shift,
            ..Default::default()
        },
    );
    h.frames(40);
    healthy(h);
}

fn snapshot(h: &Harness, name: &str) {
    let Some(dir) = std::env::var_os("STYLEGUIDE_SNAPSHOT") else {
        return;
    };
    let dir = Path::new(&dir);
    let _ = std::fs::create_dir_all(dir);
    h.ui.prepare_frame();
    // A window's frame measures what runs past `fade_overflow` edges as it
    // ends (`Scene::flush`); the harness's frames do not.
    h.ui.scene.borrow_mut().flush();
    h.ui.prepare_frame();
    // `STYLEGUIDE_GPU=1`: through the GPU renderer, offscreen, as the window
    // draws (blur, layers and shadows as they look there).
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
        // Text laid out with the fonts it draws in (the headless estimate
        // is wider or narrower), as a window lays it out.
        gpu.install_text(&mut h.ui.scene.borrow_mut());
        h.ui.refresh_text_geometry();
        h.ui.prepare_frame();
        gpu.render(
            &h.ui.scene.borrow(),
            &[zgx::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
        )
        .expect("render");
        let pixels = gpu.readback().expect("readback");
        let mut out = format!("P6\n{w} {hgt}\n255\n").into_bytes();
        // `STYLEGUIDE_WALLPAPER=1`: what the window lets through lands on a
        // colourful desktop (unblurred), so glass shows as glass.
        let wallpaper = std::env::var_os("STYLEGUIDE_WALLPAPER").is_some();
        for (i, rgba) in pixels.chunks_exact(4).enumerate() {
            if !wallpaper {
                out.extend_from_slice(&rgba[..3]);
                continue;
            }
            let (x, y) = (
                (i as u32 % w) as f32 / w as f32,
                (i as u32 / w) as f32 / hgt as f32,
            );
            let desk = [
                255. * (0.9 - 0.6 * x),
                255. * (0.3 + 0.5 * y),
                255. * (0.4 + 0.5 * x * (1. - y)),
            ];
            let a = rgba[3] as f32 / 255.;
            for c in 0..3 {
                out.push((rgba[c] as f32 + (1. - a) * desk[c]).min(255.) as u8);
            }
        }
        std::fs::write(dir.join(format!("zeron_{name}.ppm")), out).unwrap();
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
    raster
        .write_ppm(&dir.join(format!("zeron_{name}.ppm")))
        .unwrap();
}

/// Chooses `id` in the sidebar's view options, in `group`'s card if it
/// sits in one, then closes the menu (choosing leaves it up, as Zeron's).
fn view_option(h: &mut Harness, group: Option<&str>, id: &str) {
    h.click("side_view");
    h.frames(20);
    if let Some(group) = group {
        h.click(group);
        h.frames(20);
    }
    h.click(id);
    h.frames(20);
    // A press outside closes every level.
    let (x, y) = (WIDTH - 40., 40.);
    let button = zgx::input::PointerButton::Primary;
    h.ui.dispatch(InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(InputEvent::PointerUp { x, y, button });
    h.frames(20);
    healthy(h);
}

/// A secondary click near the left of node `id` (its context menu).
fn secondary(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    let (x, y) = (b.x + 20., b.y + b.height / 2.);
    let button = zgx::input::PointerButton::Secondary;
    h.ui.dispatch(zgx::input::InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(zgx::input::InputEvent::PointerUp { x, y, button });
    h.settle();
}

/// The stack the app's deep tree needs in a debug build.
fn deep(body: impl FnOnce() + Send + 'static) {
    let worker = std::thread::Builder::new()
        .stack_size(32 << 20)
        .spawn(body)
        .unwrap();
    if let Err(panic) = worker.join() {
        std::panic::resume_unwind(panic);
    }
}

#[test]
fn the_glass_layout_insets_wells_around_the_same_columns() {
    deep(|| {
        let mut h = app();
        // Zeron's layout: the unified titlebar spans the window.
        assert!(h.find("ztitle").is_some());
        assert!(h.find("well_conversation").is_none());
        h.click("zeron_pane_toggle");
        h.frames(40);
        let zeron_split = (
            h.bounds("zcols_conversation").width,
            h.bounds("zcols_right").width,
        );
        snapshot(&h, "zeron");

        cmd(&mut h, "k", false);
        snapshot(&h, "palette");
        h.key(Key::Escape);
        h.frames(30);
        // ⌘⇧L draws the same columns as glass: no band, a well per column.
        cmd(&mut h, "l", true);
        assert!(h.find("ztitle").is_none(), "the band leaves");
        let conversation = h.bounds("well_conversation");
        let right = h.bounds("well_right");
        assert_eq!(conversation.y, INSET, "the well is inset from the top");
        assert_eq!(conversation.y + conversation.height, HEIGHT - INSET);
        assert_eq!(right.x + right.width, WIDTH - INSET, "and from the right");
        assert!(
            (right.x - (conversation.x + conversation.width) - INSET).abs() < 0.5,
            "two wells a gap apart: {conversation:?} {right:?}"
        );
        // The policy is the same: the columns split as they did.
        assert_eq!(
            (
                h.bounds("zcols_conversation").width,
                h.bounds("zcols_right").width
            ),
            zeron_split
        );
        // The sidebar carries the window's controls beside the lights.
        assert!(h.find("side_head").is_some());
        assert!(h.bounds("side_sidebar").x >= 78.);
        snapshot(&h, "glass");

        // Shutting the sidebar: the conversation's header takes the
        // controls, and its well keeps the gap from the window's edge.
        cmd(&mut h, "b", false);
        assert!(h.bounds("zcols_sidebar").width < 0.5);
        assert!(h.find("well_sidebar").is_some());
        assert_eq!(h.bounds("well_conversation").x, INSET);
        snapshot(&h, "glass_shut");
        cmd(&mut h, "b", false);

        // ⌘⇧L cycles on through the tabs layouts back to Zeron's.
        for _ in 0..3 {
            cmd(&mut h, "l", true);
        }
        assert!(h.find("ztitle").is_some());
        assert!(h.find("well_conversation").is_none());
    });
}

#[test]
fn routes_keep_their_own_columns_and_history_goes_back() {
    deep(|| {
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        assert!(h.bounds("zcols_right").width > 300.);

        // The board: its own pane, closed until a pull request opens.
        h.click("nav_prs");
        h.frames(40);
        healthy(&h);
        assert!(h.find("prs_board").is_some());
        assert!(h.bounds("zprs_right").width < 0.5);
        assert_eq!(h.text("ztitle_title"), "Pull requests");
        board_lists(&mut h, "p2");
        h.click("pr_p2");
        h.frames(40);
        assert!(h.find("pr_detail").is_some());
        let (board, pane) = (
            h.bounds("zprs_conversation").width,
            h.bounds("zprs_right").width,
        );
        assert!((board - pane).abs() <= 1., "equal shares: {board} {pane}");
        snapshot(&h, "prs");

        // Shutting the sidebar on the board shuts it for the chat too; the
        // chat arrives at rest with its pane as it was. Back from the pull
        // request is the board alone, then the chat.
        cmd(&mut h, "b", false);
        cmd(&mut h, "[", false);
        assert!(h.find("prs_board").is_some());
        assert!(h.bounds("zprs_right").width < 0.5, "the board alone");
        cmd(&mut h, "[", false);
        assert!(h.find("composer").is_some(), "back to the chat");
        assert!(h.bounds("zcols_sidebar").width < 0.5);
        assert!(h.bounds("zcols_right").width > 300., "its pane kept");
        let (c, r) = (
            h.bounds("zcols_conversation").width,
            h.bounds("zcols_right").width,
        );
        assert!(
            (c + r - WIDTH).abs() <= 1.,
            "the two take the window: {c} {r}"
        );

        // Forward again: the board, then the pull request beside it.
        cmd(&mut h, "]", false);
        assert!(h.bounds("zprs_right").width < 0.5);
        cmd(&mut h, "]", false);
        assert!(h.bounds("zprs_right").width > 300.);
        // ⌘W closes the pull request's pane.
        cmd(&mut h, "w", false);
        assert!(h.bounds("zprs_right").width < 0.5);
    });
}

#[test]
fn the_panes_tabs_open_close_and_leave_the_picker() {
    deep(|| {
        let mut h = app();
        // ⌘W does nothing while the pane is shut.
        cmd(&mut h, "w", false);
        assert!(h.find("zp_tab_changes").is_none() || h.bounds("zcols_right").width < 0.5);
        h.click("zeron_pane_toggle");
        h.frames(40);
        assert!(h.find("zp_tab_changes").is_some());

        // A terminal from the palette opens as a tab, and takes the pane.
        cmd(&mut h, "k", false);
        h.click("palette_tab_commands");
        h.type_text("palette_input", "terminal");
        h.frames(10);
        h.click("palette_terminal");
        h.frames(40);
        healthy(&h);
        assert!(h.find("zp_tab_terminal_1").is_some(), "the new tab");
        assert!(h.find("term_terminal_1").is_some(), "its surface");

        // ⌘W closes the active tab; at the end, the one before it takes
        // over.
        cmd(&mut h, "w", false);
        assert!(h.find("zp_tab_terminal_1").is_none());
        assert!(h.find("preview_preview").is_some(), "the preview shows");
        // Close the rest: the picker is left.
        for _ in 0..3 {
            cmd(&mut h, "w", false);
        }
        assert!(h.find("zpane_picker").is_some());
        h.click("zpick_notes");
        h.frames(40);
        assert!(h.find("zp_tab_notes_2").is_some(), "the picker opens a tab");
    });
}

/// Opens `what` ("terminal", "browser") from ⌘K's commands.
fn open_from_palette(h: &mut Harness, what: &str) {
    cmd(h, "k", false);
    h.click("palette_tab_commands");
    // Typed, as the app's own commands follow Zeron's.
    h.type_text("palette_input", what);
    h.frames(10);
    h.click(&format!("palette_{what}"));
    h.frames(40);
    healthy(h);
}

/// What a mounted native node shows: the terminal or the page of node `id`.
fn native(
    h: &mut Harness,
    natives: &zgx::native_view::NativeViews,
    id: &str,
) -> zgx::native_view::NativeContent {
    h.ui.prepare_frame();
    let under = h.find(id).unwrap_or_else(|| panic!("no {id}"));
    let scene = h.ui.scene.borrow();
    natives
        .views()
        .into_iter()
        .find(|(node, _)| *node == under || scene.ancestors(*node).any(|a| a == under))
        .map(|(_, content)| content)
        .unwrap_or_else(|| panic!("nothing native under {id}"))
}

/// What a page's view was asked to do, once one attaches.
struct Recorder(std::rc::Rc<std::cell::RefCell<Vec<String>>>);
impl zgx::web_view::WebViewBackend for Recorder {
    fn run(&self, command: zgx::web_view::WebViewCommand) {
        self.0.borrow_mut().push(format!("{command:?}"));
    }
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

/// A terminal tab runs a session of its own, named by what its program
/// titles it ("Terminal N" until then), saying when its process ended; its
/// tab closing ends it. Where the host has no terminals, it says so.
#[test]
fn a_terminal_tab_runs_its_own_session() {
    deep(|| {
        let (mut h, natives) = native_app(true);
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "terminal");
        let zgx::native_view::NativeContent::Terminal(term) =
            native(&mut h, &natives, "term_terminal_1")
        else {
            panic!("not a terminal");
        };
        assert_eq!(term.options().font_size, Some(13.));
        // Zeron's colours and font (the theme's terminal palette,
        // Appearance's Terminal font), ⌘K left to the app; the light theme
        // restyles it.
        let config = term.config();
        for line in [
            "palette = 1=#f87171",
            "background = #090909",
            "font-family = Geist Mono",
            "font-size = 13",
            "keybind = super+k=unbind",
        ] {
            assert!(config.lines().any(|l| l == line), "{line}: {config}");
        }
        h.host.run_command("zeron_appearance_light");
        h.frames(10);
        assert!(
            term.config().lines().any(|l| l == "palette = 1=#dc2626"),
            "{}",
            term.config()
        );
        h.host.run_command("zeron_appearance_dark");
        h.frames(10);
        assert_eq!(h.text("zp_tab_terminal_1"), "Terminal 1");
        // Its program's title names the tab, as it changes.
        term.update_state(|s| s.title = "vim notes.md".into());
        h.frames(2);
        assert_eq!(h.text("zp_tab_terminal_1"), "vim notes.md");
        term.update_state(|s| s.exited = Some(0));
        h.frames(2);
        assert!(h.texts().iter().any(|t| t == "[process exited 0]"));
        // ⌘W closes the tab and ends its process.
        cmd(&mut h, "w", false);
        assert!(h.find("zp_tab_terminal_1").is_none());
        assert!(term.is_closed());

        // Without terminals, the tab says why it has none.
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "terminal");
        assert!(h.find("term_terminal_1").is_some());
        assert!(h.texts().iter().any(|t| t == "No terminal in this build"));
        snapshot(&h, "terminal_none");
    });
}

/// ⌘J opens the chat's terminals under it: their own tabs (a first one
/// opened with it, + for more, × on the chosen one), 280 high, the edge
/// dragging it between 160 and 55% of the column, a double press back to
/// 280; ⌘J or the chevron shut it, and so does closing its last tab.
#[test]
fn the_terminal_dock_opens_under_the_chat_with_tabs_of_its_own() {
    deep(|| {
        let mut h = app();
        assert!(h.find("zdock").is_none(), "nothing until it opens");
        cmd(&mut h, "j", false);
        h.frames(30);
        healthy(&h);
        let dock = h.bounds("zdock");
        let column = h.bounds("zcols_conversation");
        assert!((dock.height - 280.).abs() < 0.5, "{dock:?}");
        assert!((dock.y + dock.height - (column.y + column.height)).abs() < 0.5);
        assert_eq!(h.bounds("zdock_bar").height, 40.);
        let tab = h.bounds("zdock_tab_dock1");
        assert_eq!((tab.width, tab.height), (118., 28.));
        assert_eq!(h.text("zdock_tab_dock1"), "Terminal 1");
        assert!(h.find("zdock_term_dock1").is_some());
        // The composer sits over it.
        let composer = h.bounds("composer");
        assert!(
            composer.y + composer.height <= dock.y + 0.5,
            "{composer:?} {dock:?}"
        );

        // + opens another, chosen; its × closes it, the first chosen again.
        h.click("zdock_bar_add");
        h.frames(10);
        assert_eq!(h.text("zdock_tab_dock2"), "Terminal 2");
        assert!(h.find("zdock_term_dock2").is_some());
        h.click("zdock_tab_dock2_close");
        h.frames(10);
        assert!(h.find("zdock_tab_dock2").is_none());
        assert!(h.find("zdock_term_dock1").is_some());
        // A middle click closes a tab, chosen or not.
        h.click("zdock_bar_add");
        h.frames(10);
        let b = h.bounds("zdock_tab_dock1");
        let (x, y) = (b.x + 30., b.y + b.height / 2.);
        let middle = zgx::input::PointerButton::Middle;
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: middle,
        });
        h.ui.dispatch(InputEvent::PointerUp {
            x,
            y,
            button: middle,
        });
        h.frames(10);
        assert!(h.find("zdock_tab_dock1").is_none(), "middle-clicked away");
        assert!(h.find("zdock_term_dock3").is_some());

        // The edge drags it, within 55% of the column.
        let edge = h.bounds("zdock_edge");
        let (x, y) = (edge.x + 200., edge.y + 2.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerMove { x, y: y - 60. });
        h.frames(2);
        assert!((h.bounds("zdock").height - 340.).abs() < 0.5);
        h.ui.dispatch(InputEvent::PointerMove { x, y: 0. });
        h.ui.dispatch(InputEvent::PointerUp { x, y: 0., button });
        h.frames(2);
        let tallest = column.height * 0.55;
        assert!((h.bounds("zdock").height - tallest).abs() < 0.5);
        double_click(&mut h, "zdock_edge");
        h.frames(30);
        assert!((h.bounds("zdock").height - 280.).abs() < 0.5);

        // ⌘J shuts it, easing away, the draft taking the keyboard; again,
        // it comes back with its tab.
        cmd(&mut h, "j", false);
        h.frames(30);
        assert!(h.find("zdock").is_none());
        let field = h.find("composer_input");
        assert!(
            field.is_some() && h.ui.input.focused() == field,
            "the draft has the keyboard"
        );
        cmd(&mut h, "j", false);
        h.frames(30);
        assert!(h.find("zdock_tab_dock3").is_some());
        assert!(h.find("zdock_tab_dock4").is_none(), "no new tab");
        // Closing its last tab shuts it.
        h.click("zdock_tab_dock3_close");
        h.frames(30);
        assert!(h.find("zdock").is_none());
        snapshot(&h, "dock_closed");

        // Each session has its own.
        cmd(&mut h, "j", false);
        h.frames(30);
        assert_eq!(
            h.text("zdock_tab_dock4"),
            "Terminal 1",
            "numbered among its own"
        );
        snapshot(&h, "dock");
        h.click("agent_a3");
        h.frames(40);
        assert!(h.find("zdock").is_none(), "another session's is shut");
        healthy(&h);
    });
}

/// A browser tab offers the dev servers, loads what is typed as model.rs
/// takes it (or says why it is not an address), follows its page (the
/// tab named by its title or host, back while it has history), says when
/// a page fails with Try again, and ends its page as it closes. Without
/// pages of its own, an address opens in the system's browser.
#[test]
fn a_browser_tab_follows_its_page() {
    deep(|| {
        let (mut h, natives) = native_app(false);
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "browser");
        assert_eq!(h.text("zp_tab_preview_1"), "Browser");
        assert!(h.find("preview_1_previews_docs").is_some(), "a dev server");
        snapshot(&h, "browser_new");
        h.click("preview_1_previews_docs");
        h.frames(10);
        healthy(&h);
        let zgx::native_view::NativeContent::Web(web) = native(&mut h, &natives, "preview_1_page")
        else {
            panic!("not a page");
        };
        assert_eq!(web.url(), "http://localhost:5173/");
        let asked = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        web.attach(std::rc::Rc::new(Recorder(asked.clone())));
        assert!(
            asked
                .borrow()
                .iter()
                .any(|c| c.contains("http://localhost:5173/"))
        );
        assert_eq!(h.text("zp_tab_preview_1"), "localhost");
        web.update_state(|s| {
            s.title = "zgx docs".into();
            s.can_go_back = true;
        });
        h.frames(2);
        assert_eq!(h.text("zp_tab_preview_1"), "zgx docs");
        asked.borrow_mut().clear();
        h.click("preview_1_bar_back");
        assert_eq!(*asked.borrow(), ["GoBack"]);

        // What is typed, as an address.
        let cases = [
            (
                "javascript:alert(1)",
                Err("Only http and https addresses are supported."),
            ),
            (
                "https://me:pw@example.com",
                Err("Use an address without an embedded username or password."),
            ),
            (
                "two words",
                Err("Enter a valid website or localhost address."),
            ),
            ("localhost:3000", Ok("http://localhost:3000/")),
            ("127.0.0.1:5173/a?x=1", Ok("http://127.0.0.1:5173/a?x=1")),
            ("[::1]:8080", Ok("http://[::1]:8080/")),
            ("example.com/path", Ok("https://example.com/path")),
            ("https://localhost:3000", Ok("https://localhost:3000/")),
        ];
        for (typed, then) in cases {
            asked.borrow_mut().clear();
            h.click("preview_1_bar_address");
            h.keys("cmd+a");
            h.ui.dispatch(InputEvent::Text(typed.into()));
            h.key(Key::Enter);
            h.frames(2);
            match then {
                Err(why) => {
                    assert_eq!(h.text("preview_1_invalid"), why, "{typed}");
                    assert!(asked.borrow().is_empty(), "{typed}");
                }
                Ok(url) => {
                    assert!(h.find("preview_1_invalid").is_none(), "{typed}");
                    assert_eq!(asked.borrow()[0], format!("LoadUrl({url:?})"), "{typed}");
                }
            }
        }

        // A page that fails says so; Try again loads it again.
        web.update_state(|s| {
            s.error = Some("A server with the specified hostname could not be found.".into())
        });
        h.frames(10);
        assert!(h.find("preview_1_page").is_none());
        assert!(h.texts().iter().any(|t| t == "Couldn’t load this page"));
        asked.borrow_mut().clear();
        h.click("preview_1_action");
        assert!(
            asked.borrow()[0].starts_with("LoadUrl"),
            "{:?}",
            asked.borrow()
        );
        // ⌘W closes the tab and its page.
        cmd(&mut h, "w", false);
        assert!(web.is_closed());

        // Without pages of its own, the address opens outside.
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "browser");
        h.click("preview_1_previews_site");
        h.frames(10);
        assert!(h.texts().iter().any(|t| t == "Opened in your browser"));
        assert_eq!(h.text("zp_tab_preview_1"), "localhost");
        assert!(h.find("preview_1_bar_back").is_none());
        healthy(&h);
    });
}

/// A page answering what the app asks of it: its icon's address for the
/// favicon lookup; every command recorded.
struct Page {
    asked: std::rc::Rc<std::cell::RefCell<Vec<String>>>,
    icon: &'static str,
}
impl zgx::web_view::WebViewBackend for Page {
    fn run(&self, command: zgx::web_view::WebViewCommand) {
        self.asked.borrow_mut().push(format!("{command:?}"));
        if let zgx::web_view::WebViewCommand::Evaluate {
            script,
            reply: Some(reply),
        } = command
            && script.contains("rel~=icon")
        {
            reply(Ok(format!("{:?}", self.icon)));
        }
    }
    fn as_any(&self) -> &dyn std::any::Any {
        self
    }
}

/// A page goes only where Zeron's lets it (model.rs): web addresses in the
/// top frame, a frame's own documents too; the window's pages share one
/// store of website data (profile.rs), saying so where it cannot last; a
/// loaded page's tab shows its favicon, until the next page starts; ⌘[ and
/// ⌘] step its history while its address has the keyboard. On another device's session, a page on
/// localhost says it is this device's.
#[test]
fn a_browser_page_keeps_to_web_addresses_and_shows_its_favicon() {
    deep(|| {
        use zgx::web_view::{NavigationKind, NavigationRequest, WebProfile, WebViewEvent};
        let fetched = std::rc::Rc::new(std::cell::RefCell::new(Vec::<String>::new()));
        let log = fetched.clone();
        let natives = zgx::native_view::NativeViews::new();
        natives.set_supported(true);
        // macOS 13: no store of the app's own lasts.
        natives.set_temporary_stores(true);
        let window = natives.clone();
        let mut h = started(Harness::wrapped(
            move |runtime| {
                let host = host(runtime);
                host.fetcher(move |request: zgx_script::Request| {
                    log.borrow_mut().push(request.url.clone());
                    async move { Err::<zgx_script::Response, _>("offline".to_string()) }
                });
                host
            },
            move |view| zgx::compose::provide(window, view),
        ));
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "browser");
        h.click("preview_1_previews_docs");
        h.frames(10);
        let zgx::native_view::NativeContent::Web(web) = native(&mut h, &natives, "preview_1_page")
        else {
            panic!("not a page");
        };
        assert_eq!(
            web.options().profile,
            WebProfile::Named("zeron:synced:gael@zeron.dev".into())
        );
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("Logins are temporary")),
            "where named stores do not last"
        );
        let asked = |url: &str, main_frame: bool| NavigationRequest {
            url: url.into(),
            main_frame,
            kind: NavigationKind::Link,
            source_url: String::new(),
        };
        for url in ["https://example.com/a", "http://localhost:5173/"] {
            assert!(web.allows(&asked(url, true)), "{url}");
        }
        for url in [
            "file:///etc/passwd",
            "about:blank",
            "javascript:alert(1)",
            "https://me:pw@example.com/",
            "zeron://chat/1",
        ] {
            assert!(!web.allows(&asked(url, true)), "{url}");
        }
        for url in [
            "about:srcdoc",
            "data:text/html,hi",
            "blob:https://example.com/1",
        ] {
            assert!(web.allows(&asked(url, false)), "a frame's {url}");
        }
        assert!(!web.allows(&asked("file:///etc/passwd", false)));
        healthy(&h);

        // Loaded, it shows its icon; the next page starting takes it away.
        let commands = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        web.attach(std::rc::Rc::new(Page {
            asked: commands.clone(),
            icon: "http://localhost:5173/favicon.svg",
        }));
        assert!(h.find("zp_tab_preview_1_favicon").is_none());
        web.update_state(|s| s.url = "http://localhost:5173/".into());
        web.emit(WebViewEvent::NavigationFinished {
            url: "http://localhost:5173/".into(),
        });
        h.frames(5);
        assert!(h.find("zp_tab_preview_1_favicon").is_some(), "its icon");
        let came = h.wait_until(|h| {
            h.frames(1);
            !fetched.borrow().is_empty()
        });
        assert!(came);
        assert_eq!(fetched.borrow()[0], "http://localhost:5173/favicon.svg");
        web.emit(WebViewEvent::NavigationStarted {
            url: "http://localhost:5173/next".into(),
        });
        h.frames(5);
        assert!(h.find("zp_tab_preview_1_favicon").is_none(), "gone with it");

        // ⌘[ and ⌘] step the page's history while its address is focused.
        h.click("preview_1_bar_address");
        h.frames(5);
        commands.borrow_mut().clear();
        cmd(&mut h, "[", false);
        cmd(&mut h, "]", false);
        assert_eq!(*commands.borrow(), ["GoBack", "GoForward"]);
        h.key(Key::Escape);
        h.frames(10);

        // Another device's session: its localhost is not this page's.
        assert!(
            h.find("preview_1_remote_loopback").is_none(),
            "this device's"
        );
        h.click("agent_a7");
        h.frames(40);
        healthy(&h);
        assert!(
            h.find("preview_1_remote_loopback").is_some(),
            "{:?}",
            h.texts()
        );
        web.update_state(|s| s.url = "http://app.localhost:7331/".into());
        h.frames(5);
        assert!(
            h.find("preview_1_remote_loopback").is_none(),
            "a preview through the engine's proxy"
        );
    });
}

#[test]
fn the_tabs_layouts_split_panes_under_topbar_tabs() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        // Tabs: the topbar beside the lights, no sidebar, no right pane.
        assert!(h.find("ztopbar").is_some());
        assert!(h.find("ztitle").is_none());
        assert!(h.find("sidebar").is_none());
        for tab in ["ztab_t1", "ztab_t2", "ztab_t3"] {
            assert!(h.find(tab).is_some(), "{tab}");
        }
        // A space is heard by its name.
        assert_eq!(heard(&mut h, "ztab_t1"), "Release 0.2.117");
        // The first tab: the chat beside a terminal over the changes, cards
        // a gap apart and a gap in from the window.
        let (a, b, c) = (
            h.bounds("zt1_zt1_a"),
            h.bounds("zt1_zt1_b"),
            h.bounds("zt1_zt1_c"),
        );
        assert_eq!(a.x, INSET);
        assert_eq!(a.y, 44.);
        assert_eq!(a.y + a.height, HEIGHT - INSET);
        assert_eq!(b.x + b.width, WIDTH - INSET);
        assert!((b.x - (a.x + a.width) - INSET).abs() < 0.5, "{a:?} {b:?}");
        assert!((c.y - (b.y + b.height) - INSET).abs() < 0.5, "{b:?} {c:?}");
        assert!(h.find("zt1_a_composer").is_some(), "the chat's composer");
        // A card's header keeps its close; split and zoom are the topbar's.
        assert!(h.find("zt1_a_close").is_some());
        for control in ["split_right", "split_down", "zoom"] {
            assert!(h.find(&format!("zt1_a_{control}")).is_none(), "{control}");
            assert!(h.find(&format!("ztopbar_{control}")).is_some(), "{control}");
        }
        snapshot(&h, "tabs");

        // ⌘D splits the focused pane; the new one picks what it shows.
        cmd(&mut h, "d", false);
        assert!(h.find("zt1_p1_picker").is_some(), "the new pane's picker");
        h.click("zt1_p1_terminal");
        h.frames(40);
        healthy(&h);
        assert!(h.find("term_zt1_p1").is_some(), "a terminal");
        // ⌘W closes it.
        cmd(&mut h, "w", false);
        assert!(h.find("zt1_zt1_p1").is_none());

        // ⌘T: a new tab of one picker; ⌘W on it closes the tab.
        cmd(&mut h, "t", false);
        assert!(h.find("ztab_t4").is_some());
        cmd(&mut h, "w", false);
        assert!(h.find("ztab_t4").is_none());
        // ⌘2 selects the second tab.
        cmd(&mut h, "2", false);
        assert!(h.find("zt2_zt2_a").is_some());

        // Tabs and sidebar: the sessions beside the panes. A session shown
        // somewhere comes forward; another opens in a tab of its own.
        cmd(&mut h, "l", true);
        assert!(h.find("ztopbar_sidebar").is_some());
        assert!(h.bounds("ztabsh_sidebar").width > 200.);
        // The topbar on Zeron's titlebar metrics: its first control 88 in
        // (20 clear of the traffic lights), search and settings 4 apart
        // and 6 from the window's edge.
        assert_eq!(h.bounds("ztopbar_sidebar").x, 88.);
        let (search, settings) = (h.bounds("ztopbar_search"), h.bounds("ztopbar_settings"));
        assert!((settings.x - (search.x + search.width) - 4.).abs() < 0.01);
        assert!((WIDTH - (settings.x + settings.width) - 6.).abs() < 0.01);
        // The panes' shadows fall past the shell's edges, onto the sidebar
        // and under the topbar, rather than stopping in a line.
        {
            let shell = h.find("ztabsh_conversation").unwrap();
            let scene = h.ui.scene.borrow();
            assert!(!scene.style(shell).clip, "not clipped at its box");
            let inset = scene.clip_inset(shell).expect("a clip that reaches past");
            use zgx::layout::Length::Px;
            // A well's shadow: 24 of blur, 8 down.
            for side in [inset.left, inset.top, inset.bottom] {
                assert!(matches!(side, Px(v) if v <= -32.), "{inset:?}");
            }
        }
        h.click("agent_a1");
        h.frames(40);
        assert!(h.find("zt1_zt1_a").is_some(), "back to the first tab");
        h.click("agent_a3");
        h.frames(40);
        healthy(&h);
        assert!(h.find("ztab_t5").is_some(), "a tab for the third agent");
        snapshot(&h, "tabs_sidebar");
        cmd(&mut h, "b", false);
        assert!(h.bounds("ztabsh_sidebar").width < 0.5);
    });
}

#[test]
fn a_side_chat_forks_the_conversation_beside_it() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "fork chat");
        h.frames(10);
        h.click("palette_fork_chat");
        h.frames(40);
        healthy(&h);
        // A tab of the right pane: the conversation it forked, where it
        // forked, and a composer of its own.
        assert!(h.find("zp_tab_side_1").is_some(), "its tab");
        assert!(h.bounds("zcols_right").width > 300., "the pane opened");
        assert!(h.find("side_1_fork").is_some(), "the fork marker");
        assert!(
            joined(&mut h, "side_1_fork").contains("Write the release notes"),
            "{}",
            joined(&mut h, "side_1_fork")
        );
        assert!(h.find("side_1_composer").is_some(), "its own composer");
        assert!(h.find("composer").is_some(), "beside the conversation's");
        snapshot(&h, "side_chat");
    });
}

/// Drag pane `pane`'s grip (shown with the pointer near its top) to the
/// middle of node `to`, in steps; `at_end` runs before the release.
fn drag_pane(h: &mut Harness, pane: &str, to: &str, at_end: impl FnOnce(&mut Harness)) {
    let (tx, ty) = hold_pane_over(h, pane, to, at_end);
    h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: zgx::input::PointerButton::Primary,
    });
    h.frames(40);
    healthy(h);
}

/// `drag_pane` up to the release: where the pointer is held.
fn hold_pane_over(
    h: &mut Harness,
    pane: &str,
    to: &str,
    at_end: impl FnOnce(&mut Harness),
) -> (f32, f32) {
    use zgx::input::PointerButton::Primary;
    let card = h.bounds(pane);
    h.ui.dispatch(InputEvent::PointerMove {
        x: card.x + card.width / 2.,
        y: card.y + 12.,
    });
    h.frames(20);
    let grip = h.bounds(&format!("{pane}_grip"));
    let (fx, fy) = (grip.x + grip.width / 2., grip.y + grip.height / 2.);
    h.ui.dispatch(InputEvent::PointerMove { x: fx, y: fy });
    h.ui.dispatch(InputEvent::PointerDown {
        x: fx,
        y: fy,
        button: Primary,
    });
    let target = h.bounds(to);
    let (tx, ty) = (target.x + target.width / 2., target.y + target.height / 2.);
    for step in 1..=12 {
        let k = step as f32 / 12.;
        h.ui.dispatch(InputEvent::PointerMove {
            x: fx + (tx - fx) * k,
            y: fy + (ty - fy) * k,
        });
        h.frames(2);
    }
    at_end(h);
    (tx, ty)
}

#[test]
fn a_pane_dropped_on_anothers_middle_swaps_with_it_and_a_closed_one_fades() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        // The chat on the left, the terminal over the changes on the right.
        let (a, c) = (h.bounds("zt1_zt1_a"), h.bounds("zt1_zt1_c"));
        drag_pane(&mut h, "zt1_zt1_c", "zt1_zt1_a", |h| {
            h.frames(30);
            // Previewed live: the two already in each other's places.
            let shown = h.bounds("zt1_zt1_c");
            assert!(
                (shown.x - a.x).abs() < 1. && (shown.height - a.height).abs() < 1.,
                "{shown:?}"
            );
        });
        let (a2, c2) = (h.bounds("zt1_zt1_a"), h.bounds("zt1_zt1_c"));
        assert!(
            (c2.x - a.x).abs() < 1. && (c2.width - a.width).abs() < 1.,
            "{c2:?} {a:?}"
        );
        assert!(
            (a2.x - c.x).abs() < 1. && (a2.y - c.y).abs() < 1.,
            "{a2:?} {c:?}"
        );
        // Closed, a pane fades where it was as its neighbour takes its room,
        // then goes.
        let below = h.bounds("zt1_zt1_a");
        h.click("zt1_zt1_b");
        h.key_with(
            Key::Character("w".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(4);
        assert!(h.find("zt1_zt1_b").is_some(), "fading where it was");
        let fading = h.opacity("zt1_zt1_b");
        assert!(0. < fading && fading < 1., "{fading}");
        let growing = h.bounds("zt1_zt1_a");
        assert!(
            growing.y < below.y,
            "its neighbour already moving in: {growing:?}"
        );
        h.frames(40);
        healthy(&h);
        assert!(h.find("zt1_zt1_b").is_none(), "gone");
        let full = h.bounds("zt1_zt1_a");
        assert!(full.height > below.height * 1.8, "{full:?} {below:?}");
    });
}

#[test]
fn a_pane_drags_onto_a_space_or_into_one_of_its_own() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        // The grip: two rows of three dots, shown near the pane's top.
        drag_pane(&mut h, "zt1_zt1_b", "ztab_t2", |h| {
            // The space under the pane lights.
            snapshot(h, "pane_over_space");
        });
        assert!(
            h.find("zt2_zt1_b").is_some(),
            "it moved into the second space"
        );
        assert!(h.find("zt2_zt2_a").is_some(), "beside the space's pane");
        assert!(h.find("zt1_zt1_b").is_none());
        // A lone pane still has somewhere to go: onto the bar's end, past
        // the tabs, it opens a ghost tab and becomes a space of its own.
        let (x, y) = hold_pane_over(&mut h, "zt2_zt1_b", "ztopbar_end", |h| {
            assert!(h.find("ztopbar_slot").is_some(), "the ghost tab");
        });
        h.ui.dispatch(InputEvent::PointerUp {
            x,
            y,
            button: zgx::input::PointerButton::Primary,
        });
        h.frames(1);
        // It shows at once where the ghost was: no fade after the ghost.
        assert!(h.find("ztab_t4").is_some(), "a space of its own");
        assert_eq!(h.opacity("ztab_t4"), 1., "no fade in after the ghost");
        h.frames(40);
        healthy(&h);
        assert!(h.find("zt4_zt1_b").is_some(), "showing the pane");
        assert!(h.find("ztopbar_slot").is_none(), "the ghost goes");
        assert!(
            h.text("ztab_t4").starts_with("Terminal "),
            "named for what it shows: {}",
            h.text("ztab_t4")
        );
        snapshot(&h, "pane_own_space");
    });
}

#[test]
fn the_sidebar_sections_rows_and_view_options_follow_zerons() {
    deep(|| {
        let mut h = app();
        // The sections: Pinned, the user's own, Sessions, Archived (folded).
        for id in [
            "side_pinned",
            "side_cloud_onboarding",
            "side_cross_platform_zgx",
            "side_sessions",
            "side_archived",
        ] {
            assert!(h.find(id).is_some(), "{id}");
        }
        // Compact rows are 29 high, the pinned agent among them, 2 apart.
        assert_eq!(h.bounds("agent_a1").height, 29.);
        let (a1, a2) = (h.bounds("agent_a1"), h.bounds("agent_a2"));
        assert_eq!(a2.y - (a1.y + a1.height), 2.);
        assert!(
            h.find("thread_h4").is_some(),
            "the archived shelf starts open, as Zeron's"
        );
        // Open sections' chevrons point down.
        assert_eq!(turn(&mut h, "side_pinned_chevron"), 90.);
        assert_eq!(turn(&mut h, "side_archived_chevron"), 90.);
        snapshot(&h, "sidebar");

        // Hovering the rows runs no script: the wash and the corner's
        // Archive are the engine's.
        let calls = h.calls();
        for id in ["agent_a1", "agent_a4", "agent_a3", "thread_h1"] {
            hover_id(&mut h, id);
        }
        h.frames(20);
        assert_eq!(h.calls(), calls, "hover ran the script");

        // The shelf folds, its chevron turning right; opened again, it shows
        // what it holds and pages in the rest.
        h.click("side_archived_header");
        h.frames(4);
        let mid = turn(&mut h, "side_archived_chevron");
        assert!(mid > 0. && mid < 90., "turning: {mid}");
        h.frames(40);
        assert_eq!(turn(&mut h, "side_archived_chevron"), 0.);
        assert!(h.find("thread_h4").is_none(), "folded");
        h.click("side_archived_header");
        h.frames(40);
        healthy(&h);
        assert_eq!(turn(&mut h, "side_archived_chevron"), 90.);
        assert!(h.find("thread_h4").is_some(), "the shelf is open");
        assert!(h.text("side_archived_more").contains("Show 25 more"));
        h.click("side_archived_header");
        h.frames(40);

        // A section of the user's own deletes from its … menu: its sessions
        // go back to Sessions.
        hover_id(&mut h, "side_cloud_onboarding_header");
        h.click("side_cloud_onboarding_more");
        h.frames(20);
        h.click("side_cloud_onboarding_delete");
        h.frames(20);
        healthy(&h);
        assert!(h.find("side_cloud_onboarding").is_none());
        let (row, sessions) = (h.bounds("agent_a4"), h.bounds("side_sessions"));
        assert!(row.y > sessions.y, "under Sessions: {row:?} {sessions:?}");

        // The view menu: two-line rows (the project, then the title, then
        // the branch: 61), then the sessions by project.
        view_option(&mut h, None, "side_view_compact");
        assert_eq!(h.bounds("agent_a1").height, 61.);
        assert_eq!(h.bounds("thread_h1").height, 45.);
        assert_eq!(h.bounds("agent_a3").height, 63.);
        view_option(&mut h, Some("side_view_organize"), "side_view_project");
        assert!(h.find("side_sessions").is_none());
        assert!(h.find("side_project_comet").is_some());
        snapshot(&h, "sidebar_tall");
        // A project's + starts a session there.
        hover_id(&mut h, "side_project_comet_header");
        h.click("side_project_comet_new");
        h.frames(30);
        healthy(&h);
        assert!(h.find("new_composer").is_some(), "the new session's canvas");
        assert_eq!(h.text("new_project"), "comet", "in that project");

        // The filter keeps one project.
        h.click("side_filter");
        h.frames(20);
        h.click("side_filter_grid-website");
        h.frames(20);
        assert!(h.find("thread_h2").is_some());
        assert!(h.find("agent_a1").is_none());
        h.click("side_filter");
        h.frames(20);
        h.click("side_filter_all");
        h.frames(20);

        // Archive from the row's corner: it leaves for the shelf.
        let b = h.bounds("thread_h1");
        h.ui.dispatch(zgx::input::InputEvent::PointerMove {
            x: b.x + b.width - 10.,
            y: b.y + b.height / 2.,
        });
        h.frames(10);
        h.click("thread_h1_archive");
        h.frames(20);
        healthy(&h);
        assert!(h.find("thread_h1").is_none(), "archived");

        // Light, from the palette.
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "light");
        h.frames(10);
        h.click("palette_appearance_light");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "zeron-light");
        snapshot(&h, "light");
    });
}

#[test]
fn settings_is_a_page_and_a_new_session_starts_from_the_canvas() {
    deep(|| {
        let mut h = app();
        // ⌘, opens the settings over the window; a section, then light.
        cmd(&mut h, ",", false);
        assert!(h.find("settings").is_some());
        assert!(h.find("settings_page_general").is_some());
        h.click("settings_nav_appearance");
        h.frames(30);
        h.click("settings_mode_light");
        h.frames(30);
        assert_eq!(&*h.ui.theme().current(), "zeron-light");
        snapshot(&h, "settings");
        // The surface: Opaque makes the window's glass solid; Frosted lets
        // the blur through again.
        let glass = |h: &mut Harness| {
            let node = h.find("zeron").unwrap();
            match h.ui.scene.borrow().kind(node) {
                zgx::scene::NodeKind::Panel { quad, .. } => quad.fill.3,
                _ => 0,
            }
        };
        assert!(glass(&mut h) < 255, "frosted by default");
        h.click("settings_surface_opaque");
        h.frames(20);
        assert_eq!(glass(&mut h), 255, "opaque");
        h.click("settings_surface_frosted");
        h.frames(20);
        assert!(glass(&mut h) < 255);
        // An accent preset recolours the accent tokens, and what derives.
        h.click("settings_accent_green");
        h.frames(20);
        healthy(&h);
        h.click("settings_accent_theme");
        h.frames(20);
        h.key(Key::Escape);
        h.frames(30);
        assert!(h.find("settings").is_none(), "Esc returns to the app");

        // + opens the canvas: the composer between where it runs and its
        // checkout. Sending starts a session in the sidebar, which opens.
        h.click("ztitle_new");
        h.frames(30);
        assert!(h.find("canvas").is_some());
        assert!(h.find("new_project").is_some() && h.find("new_branch").is_some());
        snapshot(&h, "canvas");
        // The model chip's picker opens above it, its right edge on the
        // chip's (Zeron's composer pickers: up, end-aligned, 6 away).
        h.click("new_composer_model");
        h.frames(30);
        snapshot(&h, "canvas_picker");
        let (chip, card) = (h.bounds("new_composer_model"), h.bounds("new_picker"));
        assert!(
            card.y + card.height <= chip.y - 5.,
            "above: {card:?} {chip:?}"
        );
        assert!(
            (card.x + card.width - (chip.x + chip.width)).abs() < 1.,
            "end-aligned"
        );
        h.key(Key::Escape);
        h.frames(30);
        // The same in the dark theme: nothing but the card and its shadow.
        let theme = h.ui.theme().current();
        h.ui.theme().set("zeron-dark").unwrap();
        h.click("new_composer_model");
        h.frames(30);
        snapshot(&h, "canvas_picker_dark");
        h.key(Key::Escape);
        h.frames(30);
        h.ui.theme().set(&theme).unwrap();
        h.type_text("new_composer_input", "Tidy the sidebar's metrics");
        h.click("new_composer_send");
        h.frames(60);
        healthy(&h);
        assert!(h.find("agent_n1").is_some(), "the new session's row");
        assert_eq!(h.text("ztitle_title"), "Tidy the sidebar's metrics");
        assert!(h.find("sent_turn_1").is_some(), "its first message, sent");
    });
}

#[test]
fn the_composer_attaches_and_queues_while_the_agent_works() {
    deep(|| {
        let mut h = app();
        // + attaches; sending takes the attachments with the message.
        h.click("composer_add");
        h.frames(10);
        assert!(h.find("composer_att_a1").is_some(), "an attachment tile");
        h.type_text("composer_input", "First");
        h.click("composer_send");
        h.frames(10);
        assert!(h.find("composer_att_a1").is_none(), "sent with the message");
        assert!(h.find("sent_turn_1").is_some());
        // While the reply runs, sending queues; the queue shows over the
        // composer and goes when the run ends.
        h.type_text("composer_input", "Then this");
        h.click("composer_send");
        h.frames(10);
        assert!(h.find("composer_queue").is_some(), "the queue tray");
        assert!(h.find("sent_turn_2").is_none(), "not yet sent");
        let sent = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_turn_2").is_some()
        });
        assert!(sent, "the queued message goes when the run ends");
        h.frames(20);
        assert!(h.find("composer_queue").is_none() || h.bounds("composer_queue").height < 1.);
    });
}

/// A sent message says "Sending…" in the strip over the composer (the
/// gradient spinner beside it) until the session takes it up, when the
/// transcript's working line takes over, as Zeron's status strip and
/// trailer do.
#[test]
fn a_message_on_its_way_shows_the_sending_strip_then_the_working_line() {
    deep(|| {
        let mut h = app();
        assert!(h.find("composer_sending").is_none(), "nothing on its way");
        h.type_text("composer_input", "First");
        h.click("composer_send");
        h.frames(2);
        assert!(h.find("composer_sending").is_some(), "the sending strip");
        assert!(h.texts().iter().any(|t| t == "Sending…"));
        let working = |h: &mut Harness| usize::from(h.find("sent_working_1").is_some());
        let before = working(&mut h);
        let taken = h.wait_until(|h| {
            h.frames(1);
            h.find("composer_sending").is_none()
        });
        assert!(taken, "the session takes it up");
        assert!(working(&mut h) > before, "the working line");
        healthy(&h);
    });
}

/// A working session's row turns the mini spinner in the accent's three
/// tones, light over the accent over deep, as Zeron's sidebar does; only
/// the connection line keeps it one tone.
#[test]
fn a_working_rows_spinner_turns_in_the_accents_tones() {
    deep(|| {
        let mut h = app();
        h.frames(10);
        let spinner = h.find("agent_a1_spinner").expect("a working row's spinner");
        let scene = h.ui.scene.borrow();
        let fills: Vec<zgx::scene::Color> = scene
            .children(spinner)
            .iter()
            .map(|row| match scene.kind(scene.children(*row)[0]) {
                zgx::scene::NodeKind::Quad(q) | zgx::scene::NodeKind::Panel { quad: q, .. } => {
                    q.fill
                }
                other => panic!("a cell paints a box: {other:?}"),
            })
            .collect();
        assert_eq!(fills.len(), 3, "three rows");
        assert!(
            fills[0] != fills[1] && fills[1] != fills[2] && fills[0] != fills[2],
            "a tone a row: {fills:?}"
        );
    });
}

/// The composer is Zeron's material in every surface mode
/// (composer_surface_bg): dark frost's faint tint over the blur without a
/// shadow, light frost's input at 35%, opaque's solid input under the large
/// shadow; never a lit rim.
#[test]
fn the_composer_takes_the_composers_material_in_each_mode() {
    deep(|| {
        let mut h = app();
        let pill = quad(&mut h, "composer_box");
        assert!(pill.fill.3 < 64, "dark frost is faint: {pill:?}");
        assert!(!casts_shadow(&pill));
        assert_eq!(rim_lines(&pill), 0);
        in_appearance(&mut h, |h| h.click("settings_surface_opaque"));
        let pill = quad(&mut h, "composer_box");
        assert_eq!(pill.fill.3, 255, "opaque: {pill:?}");
        assert!(casts_shadow(&pill));
        in_appearance(&mut h, |h| {
            h.click("settings_surface_frosted");
            h.click("settings_mode_light");
        });
        let pill = quad(&mut h, "composer_box");
        assert!(
            (pill.fill.3 as i32 - 89).abs() <= 2,
            "light frost: {pill:?}"
        );
        assert!(!casts_shadow(&pill));
        snapshot(&h, "composer_light");
        in_appearance(&mut h, |h| {
            h.click("settings_surface_theme");
            h.click("settings_mode_dark");
        });
        healthy(&h);
    });
}

#[test]
fn command_return_on_an_empty_draft_sends_the_latest_queued_message() {
    deep(|| {
        let mut h = app();
        // The thread's composer shows how full its context is, and says it.
        assert!(h.find("composer_context").is_some(), "the context ring");
        let ring = heard_under(&mut h, "composer_context");
        assert!(
            ring.iter()
                .any(|l| l.starts_with("Context ") && l.ends_with("% used")),
            "{ring:?}"
        );
        h.type_text("composer_input", "First");
        h.click("composer_send");
        h.frames(10);
        h.type_text("composer_input", "Then this");
        h.key(Key::Enter);
        h.frames(10);
        assert!(
            h.find("sent_turn_2").is_none(),
            "queued while the run is on"
        );
        // ⌘⏎ with nothing typed: the latest queued goes now.
        h.key_with(
            Key::Enter,
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(10);
        healthy(&h);
        assert!(h.find("sent_turn_2").is_some(), "sent at once");
    });
}

#[test]
fn disclosure_chevrons_point_where_their_content_opens() {
    deep(|| {
        let mut h = app();
        // Shut, a chevron points right; the todo tray, docked over the
        // composer, rises as it opens: its chevron turns up.
        assert_eq!(turn(&mut h, "todo_tray_chevron"), 0.);
        h.click("todo_tray_header");
        h.frames(40);
        healthy(&h);
        assert_eq!(turn(&mut h, "todo_tray_chevron"), -90.);
        // A sidebar section opens below its header: down.
        assert_eq!(turn(&mut h, "side_sessions_chevron"), 90.);
        h.click("side_sessions_header");
        h.frames(40);
        assert_eq!(turn(&mut h, "side_sessions_chevron"), 0.);
        assert!(h.find("thread_h1").is_none(), "folded");
    });
}

#[test]
fn tool_calls_hang_off_the_trunk_and_arrive_drawn() {
    deep(|| {
        // Slower, so the turn is still working while its rows land.
        let mut h = paced_app(0.5);
        // The group's chevron is centred on the trunk (x 12.5 in the rows'
        // gutter) and on its header's line.
        let (chevron, header, row) = (
            h.bounds("turn_1_tools_chevron"),
            h.bounds("turn_1_tools_header"),
            h.bounds("turn_1_tools_t1_1"),
        );
        let trunk = row.x + 12.5;
        assert!(
            (chevron.x + chevron.width / 2. - trunk).abs() < 0.6,
            "on the trunk: {chevron:?} {row:?}"
        );
        assert!(
            (chevron.y + chevron.height / 2. - (header.y + header.height / 2.)).abs() < 0.6,
            "on the header's line: {chevron:?} {header:?}"
        );
        assert_eq!(row.height, 32.);
        assert_eq!(turn(&mut h, "turn_1_tools_chevron"), 90., "open: down");

        // A sent turn's calls arrive one by one, each running before it is
        // done; the summary counts them as they come.
        h.type_text("composer_input", "Go");
        h.click("composer_send");
        let arrived = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_1").is_some()
        });
        assert!(arrived, "the first call");
        // Opening, not open: under load it may be a frame into it.
        let first = h.bounds("sent_tools_1_live1_1").height;
        assert!(first < 32., "it opens from nothing: {first}");
        // Its height eases in real time: frames alone may outrun it.
        let landed = h.wait_until(|h| {
            h.frames(1);
            h.bounds("sent_tools_1_live1_1").height == 32.
        });
        healthy(&h);
        assert!(landed, "and lands at a row's");
        // Zeron's words (zeron_proto's tool_group_summary).
        assert!(
            joined(&mut h, "sent_tools_1_header").contains("Searched 1 time"),
            "{}",
            joined(&mut h, "sent_tools_1_header")
        );
        let more = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_3").is_some()
        });
        assert!(more, "the third call");
        h.frames(5);
        snapshot(&h, "tools_arriving");
        let last = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_4").is_some()
        });
        assert!(last, "the fourth call");
        h.frames(35);
        // By kind in Zeron's order, whatever the calls' (commands, edits,
        // reads, searches), only the first letter lifted.
        // (A thought arriving after them leads it: "Thought process · ran…".)
        let summary = joined(&mut h, "sent_tools_1_header").to_lowercase();
        assert!(
            summary.contains("ran 1 command")
                && summary.contains("edited 1 file")
                && summary.contains("read 1 file")
                && summary.contains("searched 1 time")
                && summary.find("ran 1") < summary.find("edited")
                && summary.find("edited") < summary.find("read"),
            "{summary}"
        );
        snapshot(&h, "tools_live");
        // With the reply done, the calls fold away under their summary.
        let folded = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_1").is_none()
        });
        assert!(folded, "the group folds when the turn is done");
        h.frames(40);
        assert_eq!(turn(&mut h, "sent_tools_1_chevron"), 0., "shut: right");
        // Nothing runs once it has settled.
        h.frames(60);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(h.calls(), calls, "a settled transcript runs no script");
    });
}

/// The connectors under node `id`: its SVG nodes 29 by 32 (a row's path),
/// laid out (a hidden one has no box), with their bounds and source.
fn connectors(
    h: &mut Harness,
    id: &str,
) -> Vec<(zgx::scene::Rect, String, Option<zgx::scene::Color>)> {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    let scene = h.ui.scene.borrow();
    let mut out = Vec::new();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let zgx::scene::NodeKind::Svg(svg) = scene.kind(n) {
            let b = scene.bounds(n);
            if b.width == 29. && b.height == 32. {
                let source = String::from_utf8_lossy(svg.bytes()).into_owned();
                out.push((b, source, svg.tint()));
            }
        }
        stack.extend(scene.children(n).iter().copied());
    }
    out
}

#[test]
fn the_tool_tree_is_one_smooth_path_a_row() {
    deep(|| {
        let mut h = app();
        to_top(&mut h);
        // Each row hangs off one path (activity_rail): the trunk at x 12.5
        // down to the fork at 10, a quadratic elbow (its control point on
        // the trunk at the row's middle) out to 18.5, the branch to 28, in
        // the line colour (white at 12% in the dark).
        let (first, last) = (h.bounds("turn_1_tools_t1_1"), h.bounds("turn_1_tools_t1_3"));
        let paths = connectors(&mut h, "turn_1_tools_t1_1");
        assert_eq!(paths.len(), 1, "one path for the row");
        let (b, source, tint) = &paths[0];
        assert_eq!((b.x, b.y), (first.x, first.y));
        assert!(
            source.contains(r#"d="M12.5 0V10Q12.5 16 18.5 16H28"#),
            "{source}"
        );
        assert_eq!(*tint, Some(zgx::scene::Color(255, 255, 255, 31)));
        // A row followed by another draws its trunk on down to 15 in the
        // same path (one coat where it forks), a plain line from there.
        assert!(source.contains("M12.5 10V15"), "{source}");
        let (_, last_source, _) = &connectors(&mut h, "turn_1_tools_t1_3")[0];
        assert!(
            !last_source.contains("V15"),
            "the last row stops at its tip"
        );

        // Drawn: the elbow is round, not a corner, and the trunk is one
        // coat all the way down through the fork.
        let Ok(mut gpu) = zgx_gpu::GpuRenderer::new((WIDTH * 2.) as u32, (HEIGHT * 2.) as u32)
        else {
            return;
        };
        gpu.set_scale_factor(2.);
        h.ui.prepare_frame();
        gpu.render(
            &h.ui.scene.borrow(),
            &[zgx::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
        )
        .expect("render");
        let pixels = gpu.readback().expect("readback");
        let at = |x: f32, y: f32| {
            let (px, py) = ((x * 2.) as usize, (y * 2.) as usize);
            let i = (py * (WIDTH * 2.) as usize + px) * 4;
            pixels[i] as i32
        };
        let ground = at(first.x + 6., first.y + 16.);
        let trunk = at(first.x + 12.5, first.y + 4.);
        assert!(trunk > ground + 8, "the trunk shows: {trunk} over {ground}");
        for y in [12.5, 14.5, 20., 31.] {
            let here = at(first.x + 12.5, first.y + y);
            assert!(
                (here - trunk).abs() <= 2,
                "one coat at {y}: {here}, the trunk {trunk}"
            );
        }
        // Where two straight lines would meet in a corner, the curve has
        // already turned: nothing there; on the curve, the line.
        let corner = at(last.x + 12.5, last.y + 15.75);
        assert!((corner - ground).abs() <= 2, "no corner: {corner}");
        let bend = at(last.x + 14., last.y + 14.5);
        assert!(bend > ground + 4, "the bend: {bend}");
        let branch = at(last.x + 24., last.y + 16.25);
        assert!((branch - trunk).abs() <= 3, "the branch: {branch}");
    });
}

#[test]
fn a_tool_row_opens_on_its_call_its_output_its_diff_and_its_images() {
    deep(|| {
        let mut h = app();
        to_top(&mut h);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t.contains(what));
        // Shut, a row is its line; a click on it opens the call in full and
        // what came back, the trunk running on down beside them.
        assert!(h.find("turn_1_tools_t1_2_body").is_none());
        assert!(!says(&mut h, "548985a Build"));
        h.click("turn_1_tools_t1_2_head");
        h.frames(3);
        let easing = h.bounds("turn_1_tools_t1_2").height;
        assert!(easing > 32. && easing < 166., "it eases open: {easing}");
        h.frames(30);
        healthy(&h);
        assert!(h.find("turn_1_tools_t1_2_body").is_some());
        assert!(says(&mut h, "548985a Build: dependencies keep line tables"));
        let open = h.bounds("turn_1_tools_t1_2");
        // The call (one line), the output (five), 6 above and below each,
        // a hairline's room before each.
        assert_eq!(open.height, 32. + 2. * (1. + 12.) + 6. * 18.);
        snapshot(&h, "tool_detail");
        h.click("turn_1_tools_t1_2_head");
        h.frames(30);
        assert!(h.find("turn_1_tools_t1_2_body").is_none(), "shut again");
        assert_eq!(h.bounds("turn_1_tools_t1_2").height, 32.);

        // A long output stops at 24 lines and counts the rest; a long call
        // wraps at 80 columns; an edit shows its hunks; images show in a
        // strip, and one opens in the viewer, Escape closing it.
        h.click("agent_a3");
        h.frames(30);
        // A markdown image alone in its paragraph shows as an image, at
        // most its own size and 480 high.
        let images: Vec<zgx::scene::Rect> = {
            let scene = h.ui.scene.borrow();
            let mut out = Vec::new();
            let mut stack = vec![scene.root()];
            while let Some(n) = stack.pop() {
                if let zgx::scene::NodeKind::Image(_) = scene.kind(n) {
                    out.push(scene.bounds(n));
                }
                stack.extend(scene.children(n).iter().copied());
            }
            out
        };
        assert_eq!(images.len(), 1, "the reply's image");
        assert!(images[0].width > 0. && images[0].width <= 720. && images[0].height <= 480.);
        // Up to the turn's calls.
        h.ui.dispatch(InputEvent::Scroll {
            x: 800.,
            y: 300.,
            delta_x: 0.,
            delta_y: -5000.,
        });
        h.frames(10);
        h.click("turn_1_tools_t1_1_head");
        h.frames(30);
        healthy(&h);
        assert!(says(&mut h, "… 8 more lines"));
        assert!(
            h.texts().iter().any(|t| t == "; done"),
            "the call wraps at 80 columns"
        );
        // Its whole output is kept apart (a sidecar): fetched in place on a
        // click, its first 400 lines in the summary's place.
        let blob = "turn_1_tools_t1_1_blob";
        for _ in 0..20 {
            if h.bounds(blob).y < HEIGHT - 200. {
                break;
            }
            h.ui.dispatch(InputEvent::Scroll {
                x: 800.,
                y: 300.,
                delta_x: 0.,
                delta_y: 100.,
            });
            h.frames(5);
        }
        let label = h.text(blob);
        assert!(
            label.starts_with("Show full output (") && label.ends_with(" KB)"),
            "{label}"
        );
        h.click(blob);
        h.frames(2);
        assert_eq!(h.text(blob), "Loading full output…");
        let fetched = h.wait_until(|h| {
            h.frames(1);
            h.find(blob).is_none()
        });
        assert!(fetched, "the full output replaces the affordance");
        h.frames(10);
        healthy(&h);
        assert!(says(&mut h, "run 12"), "every run's output");
        assert!(!says(&mut h, "… 8 more lines"), "not the summary's");
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("… ") && t.ends_with(" more lines")),
            "past its 400 lines"
        );
        h.ui.dispatch(InputEvent::Scroll {
            x: 800.,
            y: 300.,
            delta_x: 0.,
            delta_y: -5000.,
        });
        h.frames(10);
        h.click("turn_1_tools_t1_1_head");
        h.frames(10);
        h.click("turn_1_tools_t1_3_head");
        h.frames(30);
        assert!(says(&mut h, "@@ -404,7 +404,9 @@"));
        h.click("turn_1_tools_t1_3_head");
        // A diff too long to build whole stops at 600 lines and says so.
        h.click("turn_1_tools_t1_4_head");
        h.frames(30);
        assert!(says(
            &mut h,
            "Diff truncated — showing first 600 of 640 lines"
        ));
        h.click("turn_1_tools_t1_4_head");
        h.click("turn_1_tools_t1_2_head");
        h.frames(30);
        let frame = h.bounds("turn_1_tools_t1_2_image_1");
        assert_eq!(frame.height, 220.);
        assert_eq!(frame.width, 330., "220 high at its 3:2");
        assert_eq!(
            h.bounds("turn_1_tools_t1_2_image_2").width,
            220. * 480. / 720.
        );
        // A secondary click: its menu (transcript.rs image_context_menu).
        secondary(&mut h, "turn_1_tools_t1_2_image_1");
        h.frames(20);
        assert!(h.find("turn_1_tools_t1_2_image_1_menu_copy_path").is_some());
        assert!(says(&mut h, "Copy path") && says(&mut h, "Copy image"));
        h.key(Key::Escape);
        h.frames(20);
        h.click("turn_1_tools_t1_2_image_1");
        h.frames(30);
        healthy(&h);
        let shown = h.bounds("image_viewer_image");
        assert!(
            (shown.width - 720.).abs() < 0.5 && (shown.height - 480.).abs() < 0.5,
            "fitted at its own size: {shown:?}"
        );
        snapshot(&h, "image_viewer");
        // A pinch zooms it about the fingers: the point under them stays.
        let (cx, cy) = (shown.x + shown.width / 2., shown.y + shown.height / 2.);
        let image = h.find("image_viewer_image").unwrap();
        h.ui.dispatch(InputEvent::Pinch {
            x: cx + 100.,
            y: cy,
            delta: 2.,
        });
        h.frames(5);
        healthy(&h);
        let scale = h.ui.scene.borrow().local_transform(image).scale;
        assert!((scale.0 - 3.).abs() < 0.01, "three times: {scale:?}");
        let pan = h.ui.scene.borrow().transform(image);
        assert!((pan.x + 200.).abs() < 0.5, "about the fingers: {pan:?}");
        // A drag pans it, and is no click: it stays.
        use zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown {
            x: cx,
            y: cy,
            button: Primary,
        });
        for step in 1..=5 {
            h.ui.dispatch(InputEvent::PointerMove {
                x: cx + 10. * step as f32,
                y: cy,
            });
        }
        h.ui.dispatch(InputEvent::PointerUp {
            x: cx + 50.,
            y: cy,
            button: Primary,
        });
        h.frames(5);
        assert!(h.find("image_viewer_image").is_some(), "a drag keeps it");
        let pan = h.ui.scene.borrow().transform(image);
        assert!((pan.x + 150.).abs() < 0.5, "panned with the drag: {pan:?}");
        // A click closes it.
        h.click("image_viewer_image");
        h.frames(30);
        assert!(h.find("image_viewer_image").is_none(), "a click closes it");
        h.click("turn_1_tools_t1_2_image_1");
        h.frames(30);
        h.key(Key::Escape);
        h.frames(30);
        assert!(h.find("image_viewer_image").is_none(), "Escape closes it");
        // Nothing runs once it has settled.
        h.frames(30);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(h.calls(), calls);
    });
}

#[test]
fn a_running_groups_summary_shimmers_on_the_engines_clock() {
    deep(|| {
        let mut h = app();
        assert!(h.find("turn_1_tools_shimmer").is_none(), "settled: still");
        h.type_text("composer_input", "Go");
        h.click("composer_send");
        let running = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_shimmer").is_some()
        });
        assert!(running, "a light sweeps the summary while a call runs");
        let node = h.find("sent_tools_1_shimmer").unwrap();
        let offset = |h: &Harness| h.ui.scene.borrow().mask(node).map(|m| m.offset.0);
        let before = offset(&h).expect("masked");
        h.frames(6);
        let after = offset(&h).unwrap();
        assert!(after > before, "the band moves right: {before} → {after}");
        let done = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_shimmer").is_none()
        });
        assert!(done, "it stops once the calls are done");
    });
}

#[test]
fn a_session_row_pins_from_its_context_menu() {
    deep(|| {
        let mut h = app();
        secondary(&mut h, "thread_h1");
        h.frames(10);
        assert!(h.find("thread_h1_menu_pin").is_some(), "the menu shows");
        h.click("thread_h1_menu_pin");
        h.frames(20);
        healthy(&h);
        // Pinned's rows follow its header, before the next section's.
        let (row, pinned, next) = (
            h.bounds("thread_h1"),
            h.bounds("side_pinned"),
            h.bounds("side_cloud_onboarding"),
        );
        assert!(
            row.y >= pinned.y + pinned.height && row.y + row.height <= next.y,
            "now under Pinned: {row:?} {pinned:?} {next:?}"
        );
    });
}

#[test]
fn the_sidebars_popovers_are_zerons() {
    deep(|| {
        let mut h = app();
        // A press outside closes every level of a menu.
        let outside = |h: &mut Harness| {
            let (x, y) = (WIDTH - 40., 40.);
            let button = zgx::input::PointerButton::Primary;
            h.ui.dispatch(InputEvent::PointerDown { x, y, button });
            h.ui.dispatch(InputEvent::PointerUp { x, y, button });
            h.frames(30);
        };
        // The row's menu, on Zeron's card (216 less its hairline and 4 in):
        // rows 33, 2 apart; Copy's card 10 beside its row (its rows 4 in
        // past its hairline).
        secondary(&mut h, "thread_h1");
        h.frames(20);
        let (rename, pin) = (
            h.bounds("thread_h1_menu_rename"),
            h.bounds("thread_h1_menu_pin"),
        );
        assert_eq!((rename.width, rename.height), (216. - 2. - 8., 33.));
        assert_eq!(pin.y - (rename.y + rename.height), 2.);
        hover_id(&mut h, "thread_h1_menu_copy_trigger");
        h.frames(20);
        let (copy, link) = (
            h.bounds("thread_h1_menu_copy_trigger"),
            h.bounds("thread_h1_copy_link"),
        );
        assert_eq!(link.x - (copy.x + copy.width), 10. + 1. + 4.);
        assert_eq!(link.width, 232. - 2. - 8.);
        snapshot(&h, "sidebar_row_menu");
        outside(&mut h);

        // A section's …: shown while its menu is up, which opens from the
        // button's middle, 180 wide, its rows Zeron's.
        hover_id(&mut h, "side_cloud_onboarding_header");
        h.click("side_cloud_onboarding_more");
        h.frames(20);
        for line in h.tree().lines().filter(|l| l.contains("cloud_onboarding")) {
            eprintln!("TREE {line}");
        }
        let (more, edit) = (
            h.bounds("side_cloud_onboarding_more"),
            h.bounds("side_cloud_onboarding_edit"),
        );
        assert_eq!(edit.x, more.x + 10. + 1. + 4.);
        assert_eq!((edit.width, edit.height), (180. - 2. - 8., 33.));
        h.ui.dispatch(InputEvent::PointerMove { x: 700., y: 400. });
        h.frames(10);
        assert_eq!(h.opacity("side_cloud_onboarding_more"), 1., "kept while up");
        snapshot(&h, "sidebar_section_menu");
        outside(&mut h);
        assert_eq!(h.opacity("side_cloud_onboarding_more"), 0.);

        // The view options: beside the button, top-aligned, 6 past it;
        // Organize's card beside its row, the choice's check at its end.
        h.click("side_view");
        h.frames(20);
        let (view, organize) = (h.bounds("side_view"), h.bounds("side_view_organize"));
        assert_eq!(organize.x, view.x + view.width + 6. + 1. + 4.);
        assert_eq!(organize.y, view.y + 1. + 4.);
        assert_eq!(organize.height, 30.);
        h.click("side_view_organize");
        h.frames(20);
        assert!(h.find("side_view_device").is_some(), "its card");
        snapshot(&h, "sidebar_view_menu");
        // A choice closes its card and leaves the menu up.
        h.click("side_view_device");
        h.frames(20);
        assert!(h.find("side_device_macbook_pro").is_some(), "by device");
        assert_eq!(h.opacity("side_view_menu"), 1., "the menu stays up");
        h.click("side_view_show");
        h.frames(20);
        snapshot(&h, "sidebar_view_show");
        outside(&mut h);
        view_option(&mut h, Some("side_view_organize"), "side_view_list");

        // The project filter: rows 32, the list as tall as it holds.
        h.click("side_filter");
        h.frames(20);
        let (all, comet, new) = (
            h.bounds("side_filter_all"),
            h.bounds("side_filter_comet"),
            h.bounds("side_filter_new"),
        );
        assert_eq!(all.height, 32.);
        assert_eq!(comet.y - all.y, 34.);
        let last = h.bounds("side_filter_grid-website");
        // 2, the hairline with 2 over and under it, 2.
        assert_eq!(new.y - (last.y + last.height), 2. + 2. + 1. + 2. + 2.);
        snapshot(&h, "sidebar_filter_menu");
        outside(&mut h);

        // The hover card.
        hover_id(&mut h, "agent_a4");
        assert!(h.wait_until(|h| h.find("agent_a4_card").is_some()));
        h.frames(40);
        snapshot(&h, "sidebar_hover_card");
        healthy(&h);
    });
}

#[test]
fn the_topbar_tabs_are_named_spaces_renamed_in_place() {
    deep(|| {
        let mut h = app();
        for _ in 0..3 {
            cmd(&mut h, "l", true);
        }
        // A space is named for what it groups, not for a session (the
        // sidebar lists those).
        assert!(
            h.text("ztab_t1").contains("Release 0.2.117"),
            "{}",
            h.text("ztab_t1")
        );
        assert!(!h.text("ztab_t1").contains("Write the release notes"));
        // A double click renames it in place; Enter keeps the name.
        h.click("ztab_t1");
        h.click("ztab_t1");
        h.frames(10);
        assert!(h.find("ztab_t1_name").is_some(), "the name's field");
        // Focused with its name selected: typing replaces it.
        h.ui.dispatch(zgx::input::InputEvent::Text("Ship it".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("ztab_t1_name").is_none());
        assert!(
            h.text("ztab_t1").contains("Ship it"),
            "{}",
            h.text("ztab_t1")
        );
        assert!(
            !h.text("ztab_t1").contains("Release"),
            "{}",
            h.text("ztab_t1")
        );
        // A session opened in a new space names it.
        secondary(&mut h, "agent_a3");
        h.frames(10);
        h.click("agent_a3_menu_tab");
        h.frames(20);
        assert!(h.text("ztab_t4").contains("Fix flaky test"));
        snapshot(&h, "spaces");
        // Its × closes a space, the one under the pointer: it fades where it
        // was as the others close up over it, then goes.
        let third = h.bounds("ztab_t3").x;
        hover_id(&mut h, "ztab_t2");
        h.click("ztab_t2_close");
        h.frames(3);
        assert!(h.find("ztab_t2").is_some(), "fading first");
        let fading = h.opacity("ztab_t2");
        assert!(0. < fading && fading < 1., "fading: {fading}");
        assert!(
            h.bounds("ztab_t3").x < third,
            "the next one sliding over it"
        );
        h.frames(40);
        healthy(&h);
        assert!(h.find("ztab_t2").is_none(), "closed");
        assert!(h.bounds("ztab_t3").x < third, "the next one took its place");
        // Dragged onto another space, a space takes its place there.
        let (from, to) = (h.bounds("ztab_t4"), h.bounds("ztab_t1"));
        let (fx, fy) = (from.x + from.width / 2., from.y + from.height / 2.);
        h.ui.dispatch(InputEvent::PointerMove { x: fx, y: fy });
        h.ui.dispatch(InputEvent::PointerDown {
            x: fx,
            y: fy,
            button: zgx::input::PointerButton::Primary,
        });
        let (taps, _) = h.host.haptics();
        for step in 1..=10 {
            let x = fx + (to.x + 8. - fx) * step as f32 / 10.;
            h.ui.dispatch(InputEvent::PointerMove { x, y: fy });
            h.frames(2);
            if step == 1 {
                // Lifted: a frosted copy under the pointer, dim where it was.
                let preview = h.ui.input.drag_state().and_then(|d| d.preview);
                let preview = preview.expect("the space's copy follows the pointer");
                let shown = h.ui.scene.borrow().bounds(preview);
                assert!(
                    (shown.x - (from.x + x - fx)).abs() < 1. && (shown.y - from.y).abs() < 1.,
                    "grabbed where it was pressed: {shown:?} from {from:?}"
                );
                assert!(h.opacity("ztab_t4") < 0.5, "dim where it was");
            }
        }
        // Each swap taps the trackpad; hovering where it is taps nothing.
        let (swapped, last) = h.host.haptics();
        assert!(swapped > taps, "the tabs swapped without a tap");
        assert_eq!(last, Some(zgx::platform::Haptic::Alignment));
        for _ in 0..3 {
            h.ui.dispatch(InputEvent::PointerMove {
                x: to.x + 8.,
                y: fy + 1.,
            });
            h.frames(2);
        }
        assert_eq!(h.host.haptics().0, swapped, "no tap without a swap");
        h.ui.dispatch(InputEvent::PointerUp {
            x: to.x + 8.,
            y: fy,
            button: zgx::input::PointerButton::Primary,
        });
        h.frames(40);
        healthy(&h);
        assert!(h.ui.input.drag_state().is_none());
        assert_eq!(h.opacity("ztab_t4"), 1., "let go, it shows again");
        assert!(
            h.bounds("ztab_t4").x < h.bounds("ztab_t1").x,
            "dropped before the first: {:?} {:?}",
            h.bounds("ztab_t4"),
            h.bounds("ztab_t1")
        );
    });
}

/// Whether node `id` paints a fill (a tab's chosen wash).
fn washed(h: &mut Harness, id: &str) -> bool {
    quad(h, id).fill.3 > 0
}

/// Nothing in node `id` part way through a fade (shown or hidden, as a
/// tab's close at rest).
fn none_fading(h: &mut Harness, id: &str) -> bool {
    let node = h.find(id).unwrap_or_else(|| panic!("no {id}"));
    let scene = h.ui.scene.borrow();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        let o = scene.effects(n).opacity;
        if 0. < o && o < 1. {
            return false;
        }
        stack.extend(scene.children(n));
    }
    true
}

#[test]
fn a_space_is_chosen_at_once_and_only_moves_slide() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        h.ui.dispatch(InputEvent::PointerMove { x: 640., y: 400. });
        h.frames(30);
        let tabs = ["ztab_t1", "ztab_t2", "ztab_t3"];
        let at: Vec<_> = tabs.iter().map(|t| h.bounds(t)).collect();
        // The chosen space wears the chrome's wash, 24 high; the others none.
        assert!(washed(&mut h, "ztab_t1") && !washed(&mut h, "ztab_t2"));
        assert_eq!(at[0].height, 24.);
        // Chosen, the wash is on the next frame where it lands: no glass
        // sliding after it or fading in, and no tab moving.
        h.click("ztab_t2");
        h.ui.dispatch(InputEvent::PointerMove { x: 640., y: 400. });
        h.frames(1);
        assert!(washed(&mut h, "ztab_t2"), "chosen at once");
        assert!(!washed(&mut h, "ztab_t1"), "let go at once");
        for tab in tabs {
            assert!(none_fading(&mut h, tab), "{tab} fades");
        }
        assert!(h.find("zt2_zt2_a").is_some(), "its panes at once");
        assert!(h.find("zt1_zt1_a").is_none(), "the others' gone");
        for (tab, was) in tabs.iter().zip(&at) {
            assert_eq!(h.bounds(tab), *was, "{tab} moved");
        }
        // A new space fades in at the end; nothing else moves.
        h.key_with(
            Key::Character("t".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(2);
        let fading = h.opacity("ztab_t4");
        assert!(0. < fading && fading < 1., "fading in: {fading}");
        assert!(washed(&mut h, "ztab_t4") && !washed(&mut h, "ztab_t2"));
        for (tab, was) in tabs.iter().zip(&at) {
            assert_eq!(h.bounds(tab), *was, "{tab} moved");
        }
        h.frames(30);
        assert_eq!(h.opacity("ztab_t4"), 1.);
        healthy(&h);
    });
}

#[test]
fn the_focused_panes_split_and_zoom_sit_in_the_topbar() {
    deep(|| {
        let mut h = app();
        // Zeron's layout has no topbar, so none of its controls.
        assert!(h.find("ztopbar_split_right").is_none());
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        // Before search, titlebar buttons: 28 square, 4 apart, a group's 8
        // from search, on the traffic lights' line.
        let (right, down, zoom, search) = (
            h.bounds("ztopbar_split_right"),
            h.bounds("ztopbar_split_down"),
            h.bounds("ztopbar_zoom"),
            h.bounds("ztopbar_search"),
        );
        for b in [right, down, zoom] {
            assert_eq!((b.width, b.height), (28., 28.), "{b:?}");
            assert!((b.y + b.height / 2. - LIGHTS_LINE).abs() < 0.5, "{b:?}");
        }
        assert!((down.x - (right.x + right.width) - 4.).abs() < 0.01);
        assert!((zoom.x - (down.x + down.width) - 4.).abs() < 0.01);
        assert!((search.x - (zoom.x + zoom.width) - 8.).abs() < 0.01);
        assert_eq!(heard(&mut h, "ztopbar_split_right"), "Split right (⌘D)");
        // They act on the focused pane: the changes, split below, then the
        // new pane, split beside.
        h.click("zt1_zt1_c");
        h.frames(10);
        let c = h.bounds("zt1_zt1_c");
        h.click("ztopbar_split_down");
        h.frames(40);
        healthy(&h);
        let below = h.bounds("zt1_zt1_p1");
        assert!(
            below.y > c.y && (below.x - c.x).abs() < 0.5,
            "{below:?} {c:?}"
        );
        h.click("ztopbar_split_right");
        h.frames(40);
        healthy(&h);
        let (left, beside) = (h.bounds("zt1_zt1_p1"), h.bounds("zt1_zt1_p3"));
        assert!(
            beside.x > left.x && (beside.y - left.y).abs() < 0.5,
            "{beside:?}"
        );
        // Zoom: the focused pane takes the area, and the button stays lit
        // until it is pressed again.
        h.click("ztopbar_zoom");
        h.ui.dispatch(InputEvent::PointerMove { x: 640., y: 400. });
        h.frames(40);
        let zoomed = h.bounds("zt1_zt1_p3");
        assert_eq!(zoomed.x, INSET);
        assert_eq!(zoomed.x + zoomed.width, WIDTH - INSET);
        assert!(washed(&mut h, "ztopbar_zoom"), "lit while zoomed");
        h.click("ztopbar_zoom");
        h.ui.dispatch(InputEvent::PointerMove { x: 640., y: 400. });
        h.frames(40);
        assert!(h.bounds("zt1_zt1_p3").width < zoomed.width / 2.);
        assert!(!washed(&mut h, "ztopbar_zoom"));
        healthy(&h);
    });
}

/// What assistive technology hears node `id` called.
fn heard(h: &mut Harness, id: &str) -> String {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    h.ui.prepare_frame();
    let tree = h.ui.semantics.borrow();
    tree.get(node).map(|n| n.label.clone()).unwrap_or_default()
}

/// What assistive technology hears the nodes under `id` called.
fn heard_under(h: &mut Harness, id: &str) -> Vec<String> {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    h.ui.prepare_frame();
    let scene = h.ui.scene.borrow();
    let tree = h.ui.semantics.borrow();
    let mut out = Vec::new();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let Some(s) = tree.get(n).filter(|s| !s.label.is_empty()) {
            out.push(s.label.clone());
        }
        stack.extend(scene.children(n).iter().copied());
    }
    out
}

/// The colour of the text `what` under node `id`.
fn text_color(h: &mut zgx_script::testing::TestApp, id: &str, what: &str) -> zgx::scene::Color {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    let scene = h.ui.scene.borrow();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let zgx::scene::NodeKind::Text { text, color, .. } = scene.kind(n)
            && &**text == what
        {
            return *color;
        }
        stack.extend(scene.children(n).iter().rev());
    }
    panic!("no {what:?} under {id}")
}

/// Every text under node `id`, joined (a rolling label is a text a glyph).
fn joined(h: &mut zgx_script::testing::TestApp, id: &str) -> String {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    let scene = h.ui.scene.borrow();
    let mut out = String::new();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let zgx::scene::NodeKind::Text { text, .. } = scene.kind(n) {
            out.push_str(text);
        }
        stack.extend(scene.children(n).iter().rev());
    }
    out
}

/// The pointer over the middle of node `id`.
/// A node's rotation, in whole degrees.
fn turn(h: &mut Harness, id: &str) -> f32 {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    h.ui.scene
        .borrow()
        .local_transform(node)
        .rotate
        .to_degrees()
        .round()
}

fn hover_id(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::PointerMove {
        x: b.x + b.width / 2.,
        y: b.y + b.height / 2.,
    });
    h.frames(2);
}

#[test]
fn each_session_shows_its_own_transcript_in_markdown() {
    deep(|| {
        let mut h = app();
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t.contains(what));
        assert!(says(&mut h, "Can you draft the release notes for 0.2.117?"));
        // The layout refactor: a table, a code block, a quote.
        h.click("agent_a2");
        h.frames(30);
        healthy(&h);
        assert!(says(&mut h, "Refactor the layout engine so a column"));
        assert!(says(&mut h, "Approach"), "the table's head");
        assert!(
            says(&mut h, "should `invisible`") || says(&mut h, "should "),
            "the quote"
        );
        assert!(!says(&mut h, "Can you draft the release notes"));
        snapshot(&h, "markdown");
    });
}

/// Whether text `label` is painted, on screen and not faded out.
fn painted(h: &mut zgx_script::testing::TestApp, label: &str) -> bool {
    h.ui.prepare_frame();
    let scene = h.ui.scene.borrow();
    scene.paint_items().any(|item| {
        matches!(scene.kind(item.id), zgx::scene::NodeKind::Text { text, .. } if &**text == label)
            && item.effects.opacity > 0.
            && scene.visible_bounds(item.id).is_some_and(|b| b.width > 0.)
    })
}

/// The paragraph under rich text node `id`: its text and runs.
fn rich(h: &mut Harness, id: &str) -> std::sync::Arc<zgx::rich_text::RichText> {
    let node = h.find(id).unwrap_or_else(|| panic!("no `{id}`"));
    let scene = h.ui.scene.borrow();
    let paragraph = scene.children(node)[0];
    match scene.kind(paragraph) {
        zgx::scene::NodeKind::RichText { text } => text.clone(),
        other => panic!("`{id}` is no paragraph: {other:?}"),
    }
}

/// A reply's markdown as Zeron's: a code block's syntax coloured in Zeron's
/// palette, its Copy (and "Copied" for a moment), Fit content for every
/// fence; a Mermaid fence drawn, with Show source; a link naming a
/// workspace file opening it, a code span naming one a link too, under its
/// file's name; each link telling where it goes under the pointer (no
/// script) and its menu on a secondary click; a web link opening in a
/// browser tab until "Open links in Zeron" is off.
#[test]
fn a_replys_code_links_and_diagrams_are_zerons() {
    deep(|| {
        let mut h = started(Harness::with_desktop(host));
        h.click("agent_a2");
        h.frames(30);
        healthy(&h);
        into_view(&mut h, "reply_2_4_code_copy");
        // `let` in the keyword colour, `count` a function's, `1` a number's.
        let code = rich(&mut h, "reply_2_4_code_code");
        let shade = |word: &str| {
            let run = code
                .runs()
                .iter()
                .find(|r| &code.text()[r.range.clone()] == word)
                .unwrap_or_else(|| panic!("no run `{word}`"));
            (run.color.0, run.color.1, run.color.2)
        };
        assert_eq!(shade("let"), (0x8f, 0x96, 0xed), "keyword: indigo");
        assert_eq!(shade("count"), (0x8f, 0x96, 0xed), "function: indigo");
        assert_eq!(shade("1"), (0xdb, 0xa9, 0x24), "number: amber");
        assert!(code.text().starts_with("let shown"));

        // Copy, then "Copied" for 1.2 s.
        into_view(&mut h, "reply_2_4_code_copy");
        h.click("reply_2_4_code_copy");
        h.frames(2);
        let desktop = h.desktop.clone().unwrap();
        assert!(desktop.clipboard().starts_with("let shown = children"));
        assert!(h.texts().iter().any(|t| t == "Copied"));
        std::thread::sleep(std::time::Duration::from_millis(1300));
        h.frames(4);
        assert!(!h.texts().iter().any(|t| t == "Copied"), "it goes");

        // Fit content: the fence wraps rather than scrolls.
        assert!(h.find("reply_2_4_code_scroll").is_some());
        into_view(&mut h, "reply_2_4_code_fit");
        h.click("reply_2_4_code_fit");
        h.frames(4);
        assert!(h.find("reply_2_4_code_scroll").is_none(), "wrapped");
        into_view(&mut h, "reply_2_4_code_fit");
        h.click("reply_2_4_code_fit");
        h.frames(4);
        assert!(h.find("reply_2_4_code_scroll").is_some());

        // The diagram, drawn off the main thread; its source a click away.
        assert!(h.wait_until(|h| {
            h.frame();
            h.find("reply_2_6_code_diagram").is_some()
        }));
        snapshot(&h, "markdown_diagram");
        into_view(&mut h, "reply_2_6_code_source");
        h.click("reply_2_6_code_source");
        h.frames(4);
        assert!(h.find("reply_2_6_code_diagram").is_none());
        assert!(h.find("reply_2_6_code_code").is_some(), "its source");
        into_view(&mut h, "reply_2_6_code_source");
        h.click("reply_2_6_code_source");
        h.frames(4);
        assert!(h.find("reply_2_6_code_diagram").is_some());

        // A code span naming a file is a link under the file's name; an
        // authored label stays. Each has the open glyph after it.
        let para = rich(&mut h, "reply_2_5");
        assert!(
            para.text().contains("compose.rs\u{2060}"),
            "{}",
            para.text()
        );
        assert!(!para.text().contains("crates/zgx/compose.rs"));
        assert!(para.text().contains("scrollbar\u{2060}"));
        assert!(para.text().contains("Cargo.toml\u{2060}"));
        assert!(
            !para.text().contains("spec\u{2060}"),
            "no glyph on a web link"
        );

        // Under the pointer, where it goes, with no script.
        let calls = h.calls();
        let link = h.bounds("role:link \"flexbox spec\"");
        h.ui.dispatch(InputEvent::PointerMove {
            x: link.x + link.width / 2.,
            y: link.y + link.height / 2.,
        });
        assert!(
            h.wait_until(|h| {
                h.frame();
                painted(h, "https://www.w3.org/TR/css-flexbox-1/#main-sizing")
            }),
            "the destination"
        );
        assert_eq!(h.calls(), calls, "hovering a link ran the script");
        h.key(Key::Escape);
        assert!(
            h.wait_until(|h| {
                h.frame();
                !painted(h, "https://www.w3.org/TR/css-flexbox-1/#main-sizing")
            }),
            "Escape dismisses it"
        );

        // A web link's menu.
        secondary(&mut h, "role:link \"flexbox spec\"");
        h.frames(10);
        for row in [
            "link_menu_open_zeron",
            "link_menu_open_external",
            "link_menu_copy_address",
            "link_menu_default_destination",
        ] {
            assert!(h.find(row).is_some(), "{row}");
        }
        assert!(h.find("link_menu_copy_path").is_none());
        h.click("link_menu_copy_address");
        h.frames(10);
        assert_eq!(
            desktop.clipboard(),
            "https://www.w3.org/TR/css-flexbox-1/#main-sizing"
        );

        // A file link's menu.
        secondary(&mut h, "role:link \"compose.rs\"");
        h.frames(10);
        // (The web link's menu, closed, stays mounted under its link.)
        for row in [
            "link_menu_open_default",
            "link_menu_show_in_folder",
            "link_menu_copy_path",
        ] {
            assert!(h.shown(row), "{row}");
        }
        assert!(!h.shown("link_menu_open_external"));
        h.click("link_menu_copy_path");
        h.frames(10);
        assert_eq!(desktop.clipboard(), "crates/zgx/compose.rs");

        // A click on a file opens it in the pane.
        h.click("role:link \"compose.rs\"");
        h.frames(30);
        assert!(h.find("file_file_crates_zgx_compose_rs_editor").is_some());

        // A web link opens a browser tab; with "Open links in Zeron" off,
        // the system's browser.
        h.click("role:link \"flexbox spec\"");
        h.frames(30);
        assert!(h.find("zp_tab_preview_1").is_some(), "a browser tab");
        secondary(&mut h, "role:link \"flexbox spec\"");
        h.frames(10);
        h.click("link_menu_default_destination");
        h.frames(10);
        let before = desktop.opened().len();
        h.click("role:link \"flexbox spec\"");
        h.frames(10);
        assert_eq!(
            desktop.opened()[before..],
            ["https://www.w3.org/TR/css-flexbox-1/#main-sizing"]
        );
        assert!(h.find("zp_tab_preview_2").is_none(), "no second tab");
        healthy(&h);
    });
}

#[test]
fn the_composer_offers_references_after_an_at_and_commands_after_a_slash() {
    deep(|| {
        let mut h = app();
        // A slash at the start lists the commands; a pick completes it.
        h.type_text("composer_input", "/re");
        h.frames(10);
        assert!(h.find("composer_ref_cmd_review").is_some());
        assert!(h.find("composer_ref_cmd_clear").is_none());
        h.click("composer_ref_cmd_review");
        h.frames(10);
        assert_eq!(h.text("composer_input"), "/review ");
        // After an @, the files and sessions that match.
        h.type_text("composer_input", "@comp");
        h.frames(10);
        assert!(h.find("composer_references").is_some(), "the picker opens");
        assert!(
            h.find("composer_ref_file_1").is_some(),
            "compose.rs matches"
        );
        assert!(
            h.find("composer_ref_file_4").is_none(),
            "README.md does not"
        );
        snapshot(&h, "references");
        h.click("composer_ref_file_1");
        h.frames(10);
        assert!(h.find("composer_references").is_none(), "a pick closes it");
        assert_eq!(h.text("composer_input"), "/review @crates/zgx/compose.rs ");
        // The reference shows as a chip in the draft, and goes whole.
        let chips = |h: &mut Harness| {
            let input = h.find("composer_input").unwrap();
            let scene = h.ui.scene.borrow();
            let mut stack = vec![input];
            let mut n = 0;
            while let Some(node) = stack.pop() {
                if matches!(scene.kind(node), zgx::scene::NodeKind::Quad(q) if q.radius == 5.) {
                    n += 1;
                }
                stack.extend(scene.children(node).iter().copied());
            }
            n
        };
        // The command is one too.
        assert_eq!(chips(&mut h), 2, "two chips");
        h.key(Key::Backspace);
        h.key(Key::Backspace);
        h.frames(2);
        assert_eq!(h.text("composer_input"), "/review ");
        assert_eq!(chips(&mut h), 1);
    });
}

#[test]
fn zerons_own_commands_run_at_once_and_attachments_lead_the_references() {
    deep(|| {
        let mut h = app();
        // A pick of one of Zeron's commands takes the token out and runs it:
        // /diff opens the changes.
        h.type_text("composer_input", "Keep this /dif");
        h.frames(10);
        assert!(h.find("composer_ref_cmd_diff").is_some());
        h.click("composer_ref_cmd_diff");
        h.frames(30);
        healthy(&h);
        assert_eq!(h.text("composer_input"), "Keep this ");
        assert!(
            h.texts().iter().any(|t| t == "Changes"),
            "the changes tab opened"
        );
        // Sent alone, one runs instead of being sent.
        h.click("composer_input");
        h.key_with(
            Key::Character("a".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.ui.dispatch(InputEvent::Text("/settings".into()));
        h.settle();
        h.frames(5);
        // Escape puts the menu away; Enter sends the draft as it is.
        h.key(Key::Escape);
        h.key(Key::Enter);
        h.frames(30);
        healthy(&h);
        assert!(h.find("sent_turn_1").is_none(), "not sent");
        assert!(h.find("settings_page_general").is_some(), "settings opened");

        // Staged attachments come first under @, images as "Image n".
        let mut h = app();
        h.click("composer_add");
        h.frames(10);
        h.type_text("composer_input", "@");
        h.frames(10);
        assert!(
            h.find("composer_ref_attached_a1").is_some(),
            "the staged image"
        );
        let (attached, file) = (
            h.bounds("composer_ref_attached_a1"),
            h.bounds("composer_ref_file_1"),
        );
        assert!(attached.y < file.y, "pinned above the files");
        assert!(h.texts().iter().any(|t| t == "Image 1"));
    });
}

/// The completion menus as Zeron's (composer.rs): the keys move through the
/// rows and wrap, Enter or Tab take one, Escape dismisses the menu until
/// the token changes; an @ inside a word, a $ before a digit open nothing;
/// an empty list says so; the pointer over a row runs no script.
#[test]
fn the_completion_menus_answer_the_keys_as_zerons() {
    deep(|| {
        let mut h = app();
        // The skills in the / menu too (Separate / commands off).
        cmd(&mut h, ",", false);
        h.click("settings_nav_harnesses");
        h.frames(20);
        h.click("provider_claude_trigger");
        h.frames(20);
        h.click("provider_claude_separate_commands");
        h.key(Key::Escape);
        h.frames(30);
        h.type_text("composer_input", "/");
        h.frames(10);
        assert!(h.find("composer_references").is_some(), "a slash opens it");
        // Up from the first row wraps to the last (Zeron's own commands
        // follow the harness's and its skills), scrolled into view; up past
        // them, the last skill, which Enter takes in the slash's place.
        h.key(Key::ArrowUp);
        h.frames(4);
        assert!(h.find("composer_ref_cmd_stop").is_some());
        for _ in 0..8 {
            h.key(Key::ArrowUp);
        }
        h.frames(4);
        assert!(h.find("composer_ref_skill_webapp-testing").is_some());
        h.key(Key::Enter);
        h.frames(10);
        assert_eq!(h.text("composer_input"), "$webapp-testing ");
        assert!(h.find("composer_references").is_none(), "a pick closes it");
        // Tab takes the first file; the typed run ranks prefixes first.
        h.type_text("composer_input", "@rea");
        h.frames(10);
        let b = h.bounds("composer_ref_file_4");
        h.ui.dispatch(InputEvent::PointerMove {
            x: b.x + b.width / 2.,
            y: b.y + b.height / 2.,
        });
        h.frames(2);
        let calls = h.calls();
        h.ui.dispatch(InputEvent::PointerMove {
            x: b.x + b.width / 2. + 4.,
            y: b.y + b.height / 2.,
        });
        h.frames(4);
        assert_eq!(h.calls(), calls, "hover runs no script");
        h.key(Key::Tab);
        h.frames(10);
        assert_eq!(h.text("composer_input"), "$webapp-testing @README.md ");
        // Nothing matches: it says so; Escape dismisses it until the token
        // changes.
        // At the draft's end (a click in the one-row draft lands in it).
        let append = |h: &mut Harness, text: &str| {
            h.click("composer_input");
            // ⌘End: End alone scrolls a macOS field, its caret kept.
            h.key_with(
                Key::End,
                zgx::input::Modifiers {
                    meta: cfg!(target_os = "macos"),
                    control: !cfg!(target_os = "macos"),
                    ..Default::default()
                },
            );
            h.ui.dispatch(InputEvent::Text(text.into()));
            h.settle();
        };
        append(&mut h, "@zzz");
        h.frames(10);
        assert!(h.text("composer_ref_empty").contains("No matching files"));
        h.key(Key::Escape);
        h.frames(10);
        assert!(h.find("composer_references").is_none(), "dismissed");
        append(&mut h, "z");
        h.frames(10);
        assert!(
            h.find("composer_references").is_some(),
            "an edit reopens it"
        );
        // An address, an amount: no menu.
        append(&mut h, " mail@x");
        h.frames(10);
        assert!(
            h.find("composer_references").is_none(),
            "an @ inside a word"
        );
        append(&mut h, " $5");
        h.frames(10);
        assert!(
            h.find("composer_references").is_none(),
            "a $ before a digit"
        );
        healthy(&h);
    });
}

/// Dictation in the composer (composer.rs): the mic unrolls the track and
/// turns the paperclip into a cancel, the model chip stepping aside; the
/// stop plate ends it and the words join the draft; cancel drops them.
#[test]
fn the_composer_dictates_into_the_draft() {
    deep(|| {
        let mut h = app();
        assert!(h.find("composer_track").is_none());
        h.click("composer_mic");
        h.frames(30);
        assert!(h.find("composer_track").is_some(), "the track unrolls");
        assert!(h.find("composer_cancel").is_some(), "the cancel ✕");
        assert!(h.find("composer_model").is_none(), "the chip steps aside");
        h.click("composer_cancel");
        h.frames(30);
        assert!(h.find("composer_track").is_none(), "cancelled");
        assert!(
            !h.text("composer_input").contains("Windows"),
            "nothing said"
        );
        h.click("composer_mic");
        h.frames(10);
        h.click("composer_mic");
        assert!(
            h.wait_until(|h| h.text("composer_input").contains("Windows")),
            "the words join the draft"
        );
        h.frames(30);
        assert!(h.find("composer_track").is_none(), "idle again");
        assert!(h.find("composer_model").is_some());
        healthy(&h);
    });
}

#[test]
fn the_header_toggle_shows_the_session_card() {
    deep(|| {
        let mut h = app();
        assert!(h.find("z_session_card").is_none());
        h.click("ztitle_card");
        h.frames(20);
        healthy(&h);
        let card = h.bounds("z_session_card");
        assert_eq!(card.width, 272.);
        let column = h.bounds("conversation");
        assert!(
            (column.x + column.width - (card.x + card.width) - 12.).abs() < 0.5,
            "12 in from the right"
        );
        assert!(h.find("z_action_dev").is_some(), "the run actions");
        snapshot(&h, "session_card");
        h.click("ztitle_card");
        h.frames(20);
        assert!(h.find("z_session_card").is_none());
    });
}

/// A reload rebuilds the tabs layouts' first spaces once: the topbar shows
/// three, not three more after every save.
#[test]
fn a_reload_keeps_the_first_spaces_once() {
    deep(|| {
        let mut h = app();
        for _ in 0..4 {
            if h.find("ztopbar").is_some() {
                break;
            }
            cmd(&mut h, "l", true);
        }
        assert!(h.find("ztab_t3").is_some() && h.find("ztab_t4").is_none());
        h.host.reload().unwrap();
        h.settle();
        h.frames(30);
        healthy(&h);
        for _ in 0..4 {
            if h.find("ztopbar").is_some() {
                break;
            }
            cmd(&mut h, "l", true);
        }
        let named = h.texts().iter().filter(|t| *t == "Shell").count();
        assert_eq!(named, 1, "the first spaces once");
    });
}

/// The changes (kit/changes): the files of a scope as one virtual list, a
/// file folding under its header, split pairs, the scopes and their counts.
#[test]
fn the_changes_list_folds_splits_and_changes_scope() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        let id = "zt1_c_change";
        let counts = |h: &mut Harness| h.text(&format!("{id}_counts"));
        assert!(
            h.find(&format!("{id}_file_1")).is_some(),
            "the first file's header"
        );
        assert_eq!(counts(&mut h), "4 Uncommitted changes");
        // Folding the first file brings the second's header up under it
        // (built as it comes into view: the rows are virtual).
        h.click(&format!("{id}_file_1"));
        h.frames(10);
        let (first, second) = (
            h.bounds(&format!("{id}_file_1")),
            h.bounds(&format!("{id}_file_2")),
        );
        assert!(
            (second.y - (first.y + first.height)).abs() < 1.,
            "folded: {first:?} {second:?}"
        );
        h.click(&format!("{id}_file_1"));
        h.frames(10);
        // Split pairs, then back.
        h.click(&format!("{id}_split"));
        h.frames(10);
        healthy(&h);
        h.click(&format!("{id}_split"));
        h.frames(10);
        // The latest turn changed one file; the branch against main, six.
        h.click(&format!("{id}_scope"));
        h.frames(10);
        h.click(&format!("{id}_scope_turn"));
        h.frames(20);
        assert_eq!(counts(&mut h), "1 Changed file this turn");
        h.click(&format!("{id}_scope"));
        h.frames(10);
        h.click(&format!("{id}_scope_branch"));
        h.frames(20);
        assert_eq!(counts(&mut h), "6 Changed files vs main");
        snapshot(&h, "changes");
        healthy(&h);
    });
}

/// The working tree's trash (changes.rs): asked first, it discards every
/// uncommitted change, the tree's statuses with it ("No uncommitted
/// changes"); the branch's and the turn's scopes have none.
#[test]
fn discarding_the_working_tree_asks_first() {
    deep(|| {
        let mut h = app();
        h.type_text("composer_input", "/diff");
        h.key(Key::Escape);
        h.key(Key::Enter);
        h.frames(40);
        healthy(&h);
        let id = "zchange";
        assert_eq!(h.text(&format!("{id}_counts")), "4 Uncommitted changes");
        // README.md is modified in the tree.
        cmd(&mut h, "e", false);
        h.frames(30);
        assert_ne!(
            text_color(&mut h, "ztree_README.md", "README.md"),
            text_color(&mut h, "ztree_Cargo.toml", "Cargo.toml"),
        );
        cmd(&mut h, "e", false);
        h.frames(30);
        h.click(&format!("{id}_discard"));
        h.frames(20);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        assert!(says(&mut h, "Discard working tree changes?"));
        assert!(says(
            &mut h,
            "Discard all uncommitted changes in this working tree? This can’t be undone."
        ));
        // Cancel keeps them.
        h.click(&format!("{id}_discard_cancel"));
        h.frames(20);
        assert_eq!(h.text(&format!("{id}_counts")), "4 Uncommitted changes");
        h.click(&format!("{id}_discard"));
        h.frames(20);
        h.click(&format!("{id}_discard_confirm"));
        h.frames(30);
        healthy(&h);
        assert_eq!(h.text(&format!("{id}_counts")), "0 Uncommitted changes");
        assert_eq!(h.text(&format!("{id}_clean")), "No uncommitted changes");
        // Nothing left to discard: the trash is faint and inert.
        let trash = h.find(&format!("{id}_discard")).unwrap();
        assert!(!h.ui.input.is_enabled(&h.ui.scene.borrow(), trash));
        let faint = h.ui.scene.borrow().effects(trash).opacity;
        assert!((faint - 0.35).abs() < 0.01, "{faint}");
        // The tree's modified file is clean again.
        cmd(&mut h, "e", false);
        h.frames(30);
        assert_eq!(
            text_color(&mut h, "ztree_README.md", "README.md"),
            text_color(&mut h, "ztree_Cargo.toml", "Cargo.toml"),
            "no status colour left"
        );
    });
}

/// History's click (history.rs OpenCommit): the commit's own diff in a tab
/// of its own, named for its subject, its short SHA where the scope was,
/// "N Changed files in this commit"; a commit with nothing in it is an
/// "Empty commit". Comments go on its lines as on the working tree's.
#[test]
fn a_history_click_opens_the_commits_own_diff() {
    deep(|| {
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        for _ in 0..3 {
            cmd(&mut h, "w", false);
        }
        h.click("zpick_history");
        h.frames(40);
        h.click("history_history_1_commits_7f8e9d0c");
        h.frames(40);
        healthy(&h);
        let id = "commit_2_change";
        assert_eq!(h.text(&format!("{id}_sha")), "7f8e9d0");
        assert_eq!(
            h.text(&format!("{id}_counts")),
            "1 Changed file in this commit"
        );
        assert!(
            h.find(&format!("{id}_scope")).is_none(),
            "no scope to choose"
        );
        assert!(
            h.texts().iter().any(|t| t == "glass: press gives to 0.985"),
            "the tab, named for its subject"
        );
        assert!(h.texts().iter().any(|t| t == "M.PRESS = 0.985"));
        snapshot(&h, "commit_diff");
        // Back to History (the tab before it), the merge: nothing of its own.
        cmd(&mut h, "w", false);
        h.frames(30);
        h.click("history_history_1_commits_3b87140c");
        h.frames(40);
        assert_eq!(h.text("commit_3_change_clean"), "Empty commit");
    });
}

/// The changes' toolbar (changes.rs): every file folds and opens again at
/// once, long lines wrap (the headers still sticking), a file's notices
/// say what its lines can't, and the branch's base is picked from a
/// searchable list ("Partial snapshot" when the diff was cut short).
#[test]
fn the_changes_fold_all_wrap_notices_and_pick_a_base() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        let id = "zt1_c_change";
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        // The deleted image's notices, under its header (the last file).
        h.click(&format!("{id}_file_1"));
        h.frames(10);
        h.click(&format!("{id}_file_2"));
        h.frames(10);
        assert!(says(&mut h, "New file"), "docs/layout.md is new");
        assert!(says(&mut h, "Deleted file"));
        assert!(says(&mut h, "Binary file — contents not shown"));
        h.click(&format!("{id}_file_2"));
        h.frames(10);
        h.click(&format!("{id}_file_1"));
        h.frames(10);
        // Collapse all: every header one under another; then expand all.
        h.click(&format!("{id}_fold_all"));
        h.frames(10);
        for i in 1..4 {
            let (a, b) = (
                h.bounds(&format!("{id}_file_{i}")),
                h.bounds(&format!("{id}_file_{}", i + 1)),
            );
            assert!(
                (b.y - (a.y + a.height)).abs() < 1.,
                "all folded: {a:?} {b:?}"
            );
        }
        h.click(&format!("{id}_fold_all"));
        h.frames(10);
        // The first file's lines under it again (the second's header out of
        // view, or well below).
        let a = h.bounds(&format!("{id}_file_1"));
        if h.find(&format!("{id}_file_2")).is_some() {
            let b = h.bounds(&format!("{id}_file_2"));
            assert!(b.y - (a.y + a.height) > 40., "open again: {a:?} {b:?}");
        }
        assert!(says(
            &mut h,
            "    // A stretched child is never centred: it fills the cross axis."
        ));
        // Wrapping: the long line runs onto a second, its row measured.
        let line = "\"    let centred = parent.items == Align::Center && self_align.is_none();\"";
        let unwrapped = h.bounds(line);
        h.click(&format!("{id}_wrap"));
        h.frames(20);
        healthy(&h);
        let wrapped = h.bounds(line);
        assert!(
            wrapped.height > unwrapped.height + 10.,
            "wrapped: {unwrapped:?} {wrapped:?}"
        );
        assert!(h.find(&format!("{id}_file_1")).is_some(), "the header");
        h.click(&format!("{id}_wrap"));
        h.frames(20);
        // The base: its picker searches the branches.
        h.click(&format!("{id}_scope"));
        h.frames(10);
        h.click(&format!("{id}_scope_branch"));
        h.frames(20);
        assert!(says(&mut h, "gael/zeron-parity"), "the branch");
        h.click(&format!("{id}_base"));
        h.frames(20);
        assert!(
            h.find(&format!("{id}_bases_search")).is_some(),
            "the search"
        );
        assert!(h.find(&format!("{id}_bases_wing_glass")).is_some());
        h.type_text(&format!("{id}_bases_search"), "rel");
        h.frames(10);
        assert!(
            h.find(&format!("{id}_bases_wing_glass")).is_none(),
            "narrowed"
        );
        h.ui.dispatch(InputEvent::Text("zzz".into()));
        h.settle();
        h.frames(10);
        assert!(says(&mut h, "No matching branches"));
        for _ in 0..3 {
            h.key(Key::Backspace);
        }
        h.frames(10);
        h.click(&format!("{id}_bases_release_0_1"));
        h.frames(20);
        healthy(&h);
        assert_eq!(
            h.text(&format!("{id}_counts")),
            "4 Changed files vs release/0.1"
        );
        assert!(h.find(&format!("{id}_partial")).is_some(), "partial");
        assert!(says(&mut h, "Partial snapshot"));
        snapshot(&h, "changes_base");
    });
}

/// A box's quad: its fill, border and shadows.
fn quad(h: &mut Harness, id: &str) -> zgx::scene::QuadStyle {
    let node = h.find(id).unwrap_or_else(|| panic!("no {id}"));
    match h.ui.scene.borrow().kind(node) {
        zgx::scene::NodeKind::Panel { quad, .. } | zgx::scene::NodeKind::Quad(quad) => quad.clone(),
        _ => panic!("{id} paints no box"),
    }
}
fn casts_shadow(q: &zgx::scene::QuadStyle) -> bool {
    let listed = q.decoration.as_ref().and_then(|d| d.shadows.as_ref());
    match listed {
        Some(list) => !list.is_empty(),
        None => q.shadow.is_some(),
    }
}
fn rim_lines(q: &zgx::scene::QuadStyle) -> usize {
    q.decoration
        .as_ref()
        .and_then(|d| d.inset_shadows.as_ref())
        .map_or(0, |l| l.len())
}
/// Settings' Appearance page: open it, run `f`, close it.
fn in_appearance(h: &mut Harness, f: impl FnOnce(&mut Harness)) {
    cmd(h, ",", false);
    h.click("settings_nav_appearance");
    h.frames(20);
    f(h);
    h.key(Key::Escape);
    h.frames(30);
    healthy(h);
}

#[test]
fn settings_sections_take_the_sidebars_width_on_the_windows_glass() {
    deep(|| {
        let mut h = app();
        let sidebar = h.bounds("zcols_sidebar").width;
        assert_eq!(sidebar, 256., "Zeron's default sidebar");
        cmd(&mut h, ",", false);
        assert_eq!(h.bounds("settings_sections").width, sidebar);
        // The page paints nothing of its own: the window's glass shows,
        // and the app beneath stops painting.
        let page = h.find("settings").unwrap();
        assert!(matches!(
            h.ui.scene.borrow().kind(page),
            zgx::scene::NodeKind::Container(_)
        ));
        assert!(quad(&mut h, "zeron").fill.3 < 255);
        h.key(Key::Escape);
        h.frames(30);
        // Dragging the sidebar wider widens Settings' column with it.
        let seam = h.bounds("zcols_seam_sidebar");
        let (x, y) = (seam.x + seam.width / 2., seam.y + seam.height / 2.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerMove { x: x + 64., y });
        h.ui.dispatch(InputEvent::PointerUp {
            x: x + 64.,
            y,
            button,
        });
        h.frames(30);
        let wider = h.bounds("zcols_sidebar").width;
        assert!((wider - 320.).abs() < 1., "dragged to {wider}");
        cmd(&mut h, ",", false);
        assert_eq!(h.bounds("settings_sections").width, wider);
        snapshot(&h, "settings_dark");
    });
}

#[test]
fn surfaces_follow_the_surface_mode_and_the_double_border() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        // Frosted (Zeron's own): translucent glass and wells, the wells'
        // hairline and lit rim (a ring and a top band).
        let well = quad(&mut h, "well_conversation");
        assert!(quad(&mut h, "zeron").fill.3 < 255);
        assert!(well.fill.3 < 255, "{well:?}");
        assert_eq!(rim_lines(&well), 2);
        // The palette floats as frost: a faint tint, no shadow under it.
        cmd(&mut h, "k", false);
        let card = quad(&mut h, "palette");
        assert!(card.fill.3 < 64, "dark frost is faint: {card:?}");
        assert!(!casts_shadow(&card));
        snapshot(&h, "frosted_palette");
        h.key(Key::Escape);
        h.frames(30);
        snapshot(&h, "frosted_glass");

        // Opaque: solid glass and wells, the palette solid with its shadow.
        in_appearance(&mut h, |h| h.click("settings_surface_opaque"));
        assert_eq!(quad(&mut h, "zeron").fill.3, 255);
        assert_eq!(quad(&mut h, "well_conversation").fill.3, 255);
        cmd(&mut h, "k", false);
        let card = quad(&mut h, "palette");
        assert_eq!(card.fill.3, 255);
        assert!(casts_shadow(&card));
        h.key(Key::Escape);
        h.frames(30);
        snapshot(&h, "opaque_glass");

        // The double border turns off: the hairline stays, the rim goes.
        in_appearance(&mut h, |h| h.click("settings_rim"));
        assert_eq!(rim_lines(&quad(&mut h, "well_conversation")), 0);
        in_appearance(&mut h, |h| h.click("settings_rim"));
        assert_eq!(rim_lines(&quad(&mut h, "well_conversation")), 2);

        // Light frost: the overlay at 45% under the palette.
        in_appearance(&mut h, |h| {
            h.click("settings_surface_frosted");
            h.click("settings_mode_light");
        });
        assert_eq!(&*h.ui.theme().current(), "zeron-light");
        snapshot(&h, "frosted_glass_light");
        cmd(&mut h, "k", false);
        let card = quad(&mut h, "palette");
        assert!((card.fill.3 as i32 - 115).abs() <= 2, "{card:?}");
        h.key(Key::Escape);
        h.frames(30);
        in_appearance(&mut h, |h| h.click("settings_surface_opaque"));
        snapshot(&h, "opaque_glass_light");

        // The theme's own surface: Zeron's is frosted, an imported theme's
        // opaque (SurfaceTreatment), as in Zeron.
        in_appearance(&mut h, |h| {
            h.click("settings_surface_theme");
            h.click("settings_mode_dark");
        });
        assert!(quad(&mut h, "zeron").fill.3 < 255);
        h.ui.theme().set("dracula").unwrap();
        h.frames(20);
        assert_eq!(quad(&mut h, "zeron").fill.3, 255, "Dracula is opaque");
        healthy(&h);
    });
}

/// The traffic lights' centre line (the unified titlebar's: 4 down, 38 high).
const LIGHTS_LINE: f32 = 21.;

#[test]
fn every_layouts_window_controls_sit_on_the_lights_line() {
    deep(|| {
        let mut h = app();
        let on_line = |h: &mut Harness, id: &str| {
            let b = h.bounds(id);
            assert!(
                (b.y + b.height / 2. - LIGHTS_LINE).abs() < 0.5,
                "`{id}` is off the lights' line: {b:?}"
            );
        };
        // Zeron's titlebar, then glass with the sidebar open and shut.
        on_line(&mut h, "ztitle_sidebar");
        cmd(&mut h, "l", true);
        on_line(&mut h, "side_sidebar");
        cmd(&mut h, "b", false);
        on_line(&mut h, "well_sidebar");
        cmd(&mut h, "b", false);
        // The tabs layouts' topbar.
        cmd(&mut h, "l", true);
        on_line(&mut h, "ztopbar_project");
        cmd(&mut h, "l", true);
        on_line(&mut h, "ztopbar_sidebar");
        on_line(&mut h, "ztopbar_project");
    });
}

#[test]
fn menus_highlight_in_the_themes_hover_not_the_systems_accent() {
    deep(|| {
        let mut h = app();
        // As macOS's popup windows do: the menu's chosen item and the text
        // selection in the system's accent.
        let blue = zgx::scene::Color(10, 132, 255, 255);
        h.ui.theme().set_system_tokens([
            (zgx::theme::tok::MENU_HOVER.0, blue.into()),
            (zgx::theme::tok::SELECTION.0, blue.into()),
        ]);
        h.frames(5);
        cmd(&mut h, "l", true);
        h.click("side_filter");
        h.frames(20);
        hover_id(&mut h, "side_filter_all");
        h.frames(10);
        // The item's fills, its wash layer's among them.
        let node = h.find("side_filter_all").unwrap();
        let scene = h.ui.scene.borrow();
        let mut fills = Vec::new();
        let mut stack = vec![node];
        while let Some(n) = stack.pop() {
            if let zgx::scene::NodeKind::Panel { quad, .. } | zgx::scene::NodeKind::Quad(quad) =
                scene.kind(n)
                && quad.fill.3 > 0
            {
                fills.push(quad.fill);
            }
            stack.extend(scene.children(n));
        }
        assert!(!fills.is_empty(), "the item washes under the pointer");
        for zgx::scene::Color(r, g, b, a) in fills.iter().copied() {
            assert!(
                r.abs_diff(g) < 8 && g.abs_diff(b) < 8,
                "the hover is a neutral wash, not the system's accent: {:?}",
                (r, g, b, a)
            );
        }
    });
}

#[test]
fn what_is_active_is_a_ui_wash_whatever_the_accent() {
    deep(|| {
        let mut h = app();
        in_appearance(&mut h, |h| h.click("settings_accent_green"));
        // The chosen session's row: the text colour faintly, not the accent.
        let zgx::scene::Color(r, g, b, a) = quad(&mut h, "agent_a1").fill;
        assert!(a > 0, "the chosen row is washed");
        assert!(
            r.abs_diff(g) < 8 && g.abs_diff(b) < 8,
            "a neutral wash: {:?}",
            (r, g, b, a)
        );
    });
}

#[test]
fn the_tabs_panes_keep_the_gap_from_the_sidebar() {
    deep(|| {
        let mut h = app();
        for _ in 0..3 {
            cmd(&mut h, "l", true);
        }
        let side = h.bounds("ztabsh_sidebar");
        let body = h.bounds("ztabs_body");
        assert!(
            (body.x - (side.x + side.width)).abs() < 0.5,
            "the body starts at the sidebar: {side:?} {body:?}"
        );
        // Its panes a gap in, as from the window's other edges.
        let pane = h.bounds("zt1_zt1_a");
        assert!(
            (pane.x - (body.x + INSET)).abs() < 0.5,
            "a gap from the sidebar: {body:?} {pane:?}"
        );
    });
}

/// The sidebar's footer as Zeron's (shell.rs render_user_menu,
/// render_update_strip): its metrics in every layout with a sidebar, its
/// menu over the pill, the account's sync states and the update's flow.
#[test]
fn the_sidebar_footer_is_zerons() {
    deep(|| {
        let mut h = app();
        // Zeron's, then glass, then tabs and sidebar (tabs has none).
        for layout in 0..3 {
            if layout == 1 {
                cmd(&mut h, "l", true);
            } else if layout == 2 {
                cmd(&mut h, "l", true);
                cmd(&mut h, "l", true);
            }
            let footer = h.bounds("side_footer");
            let pill = h.bounds("side_account");
            let (voice, prs, settings) = (
                h.bounds("side_voice"),
                h.bounds("nav_prs"),
                h.bounds("side_settings"),
            );
            // 8 over and under the 28 pill; the buttons 28, 2 apart, 4 from
            // the pill, which fills the rest.
            assert_eq!(pill.height, 28., "layout {layout}");
            assert_eq!(pill.y - footer.y, 8.);
            assert_eq!(footer.y + footer.height - (pill.y + pill.height), 8.);
            assert_eq!(voice.x - (pill.x + pill.width), 4.);
            assert_eq!(prs.x - (voice.x + voice.width), 2.);
            assert_eq!(settings.x - (prs.x + prs.width), 2.);
            for b in [voice, prs, settings] {
                assert_eq!((b.width, b.height), (28., 28.));
            }
            // In line with the list's rows, its edges the list's inset in.
            let row = h.bounds("agent_a1");
            assert_eq!(pill.x, row.x);
            assert_eq!(settings.x + settings.width, row.x + row.width);
            // The avatar 16, 8 in; the label 8 after it.
            let avatar = h.bounds("side_account_avatar");
            assert_eq!((avatar.width, avatar.height), (16., 16.));
            assert_eq!(avatar.x - pill.x, 8.);
            assert_eq!(h.bounds("side_account_label").x - (avatar.x + 16.), 8.);
            assert_eq!(h.text("side_account_avatar"), "G");
            assert_eq!(h.text("side_account_label"), "Gaël Cado");
            // The update strip right over the footer, the pill's width.
            let strip = h.bounds("update_strip");
            assert_eq!(strip.y + strip.height, footer.y);
            assert_eq!((strip.x, strip.width), (pill.x, settings.x + 28. - pill.x));
            assert_eq!(h.text("update_strip"), "Update available — v0.2.117");
            // "Star on GitHub" 4 over it, as wide.
            let star = h.bounds("star_banner");
            assert_eq!(strip.y - (star.y + star.height), 4.);
            assert_eq!((star.x, star.width), (strip.x, strip.width));
            assert_eq!(h.bounds("star_banner_dismiss").width, 18.);
            snapshot(&h, ["footer", "footer_glass", "footer_tabs"][layout]);
        }
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);

        // Under the pointer the engine's washes come and go: no script.
        let calls = h.calls();
        for id in [
            "side_account",
            "side_voice",
            "nav_prs",
            "side_settings",
            "update_strip",
        ] {
            hover_id(&mut h, id);
        }
        h.frames(10);
        assert_eq!(h.calls(), calls, "hover ran the script");

        // The menu opens upward, 6 over the pill and from its left edge, as
        // wide as the footer up to 4 before Settings; the identity line, then
        // Sign out.
        let (pill, settings) = (h.bounds("side_account"), h.bounds("side_settings"));
        h.click("side_account");
        h.frames(30);
        let menu = h.bounds("side_account_menu");
        assert_eq!(menu.x, pill.x);
        assert_eq!(pill.y - (menu.y + menu.height), 6.);
        assert_eq!(menu.x + menu.width, settings.x - 4.);
        assert!(h.texts().iter().any(|t| t == "gael@zeron.dev"));
        assert_eq!(h.bounds("side_account_sign_out").height, 33.);
        snapshot(&h, "footer_menu");
        // It rises in at every opening, not the first alone (140 ms from 30%).
        h.key(zgx::input::Key::Escape);
        h.frames(20);
        h.click("side_account");
        h.frames(1);
        let rising = h.opacity("side_account_menu");
        assert!(rising < 0.9, "entering: {rising}");
        h.frames(20);
        assert_eq!(h.opacity("side_account_menu"), 1.);

        // Signing out asks first, says it is under way; then the workspace
        // is local: "Local", stored on this device, offering sync.
        h.click("side_account_sign_out");
        h.frames(20);
        assert!(h.find("signout_dialog").is_some());
        h.click("signout-confirm");
        h.frames(20);
        healthy(&h);
        assert!(h.find("signing_out_dialog").is_some(), "Signing out…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("side_account_label") == "Local"
        }));
        h.frames(30);
        assert_eq!(h.text("side_account_avatar"), "L");
        h.click("side_account");
        h.frames(20);
        assert!(h.texts().iter().any(|t| t == "Stored on this device"));
        // Enabling sync: the browser in the window's place, then the offer;
        // Later puts it off, and the menu finishes it.
        h.click("side_account_enable_sync");
        h.frames(20);
        assert!(h.find("sync_enabling").is_some());
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sync_offer").is_some()
        }));
        h.frames(30);
        h.click("sync_later");
        h.frames(30);
        h.click("side_account");
        h.frames(20);
        assert!(h.find("side_account_sync_restart").is_some());
        h.key(zgx::input::Key::Escape);
        h.frames(20);

        // The star goes for good when dismissed; the strip stays.
        h.click("star_banner_dismiss");
        h.frames(10);
        assert!(h.find("star_banner").is_none());
        let (strip, footer) = (h.bounds("update_strip"), h.bounds("side_footer"));
        assert_eq!(strip.y + strip.height, footer.y);

        // The update: the strip downloads, then restarts into it.
        h.click("update_strip");
        h.frames(4);
        assert_eq!(h.text("update_strip"), "Downloading v0.2.117…");
        assert!(h.wait_until(|h| h.text("update_strip") == "Update ready — restart to apply"));
        h.click("update_strip");
        h.frames(4);
        assert_eq!(h.text("update_strip"), "Restarting…");
        assert!(h.wait_until(|h| h.find("update_strip").is_none()));
        healthy(&h);
    });
}

/// The sidebar's sections fold eased, and its rows do as Zeron's: by
/// device and by date, renamed in place, deleted after asking, copied,
/// sections made and renamed, running subagents and remote sessions shown,
/// ⌃Tab and ⌘1–9 moving through them.
#[test]
fn the_sidebar_sorts_groups_renames_and_cycles_as_zerons() {
    deep(|| {
        let mut h = app();
        // Folding Pinned eases its rows away (the last first), then counts.
        let below = h.bounds("side_cloud_onboarding").y;
        h.click("side_pinned_header");
        h.frames(4);
        let mid = h.bounds("side_cloud_onboarding").y;
        assert!(mid < below && mid > below - 62., "easing: {mid} of {below}");
        h.frames(20);
        assert!(h.find("agent_a1").is_none(), "folded rows are not built");
        assert!(h.find("side_pinned_count").is_some());
        assert_eq!(h.text("side_pinned_count"), "2");
        h.click("side_pinned_header");
        h.frames(20);
        assert!(h.find("agent_a1").is_some());

        // Running subagents take the time's place; the corner keeps them.
        assert_eq!(h.text("agent_a1_subagents"), "3");
        assert_eq!(h.bounds("agent_a1_subagents").height, 16.);

        // ⌃Tab steps through the sidebar's order, wrapping; ⌘2 jumps.
        let ctrl = Modifiers {
            control: true,
            ..Default::default()
        };
        h.key_with(Key::Tab, ctrl);
        h.frames(10);
        healthy(&h);
        assert_eq!(turn_session(&mut h), "Refactor the layout engine");
        h.key_with(
            Key::Tab,
            Modifiers {
                control: true,
                shift: true,
                ..Default::default()
            },
        );
        h.frames(10);
        assert_eq!(turn_session(&mut h), "Write the release notes");
        h.key_with(
            Key::Character("3".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(10);
        assert_eq!(turn_session(&mut h), "Durable Object token vault");

        // ⌘ held alone: the first nine rows say their key in their corner,
        // the time giving way; let go, the time is back. No key handler runs
        // per row for it beyond the rows' own choice.
        // The hint, the time and Archive share one slot, swapped by opacity.
        let shown = |h: &mut Harness, id: &str| h.opacity(id) > 0.5;
        assert!(!shown(&mut h, "agent_a1_jump"));
        h.ui.set_held_keys(Modifiers {
            meta: true,
            ..Default::default()
        });
        h.frames(2);
        assert!(shown(&mut h, "agent_a1_jump"));
        assert_eq!(h.text("agent_a1_jump"), "⌘1");
        assert_eq!(h.text("agent_a4_jump"), "⌘3");
        // ⌘⇧ is another chord: no hints.
        h.ui.set_held_keys(Modifiers {
            meta: true,
            shift: true,
            ..Default::default()
        });
        h.frames(2);
        assert!(!shown(&mut h, "agent_a1_jump"));
        h.ui.set_held_keys(Modifiers::default());
        h.frames(2);
        assert!(!shown(&mut h, "agent_a4_jump"));

        // By device: this machine's group first.
        view_option(&mut h, Some("side_view_organize"), "side_view_device");
        let (here, there) = (
            h.bounds("side_device_macbook_pro"),
            h.bounds("side_device_mac_studio"),
        );
        assert!(here.y < there.y);
        assert_eq!(h.text("side_device_macbook_pro_header"), "MacBook Pro");
        // Two-line rows without the location: the remote glyph.
        view_option(&mut h, None, "side_view_compact");
        view_option(&mut h, Some("side_view_show"), "side_view_project_label");
        assert!(h.find("agent_a7_remote").is_some());
        assert!(h.find("agent_a6_remote").is_none());
        snapshot(&h, "sidebar_devices");
        for (group, id) in [
            (Some("side_view_show"), "side_view_project_label"),
            (None, "side_view_compact"),
            (Some("side_view_organize"), "side_view_list"),
        ] {
            view_option(&mut h, group, id);
        }
        // The project filter hides from the view menu, the menu's button
        // keeping its place at the end.
        let view = h.bounds("side_view");
        view_option(&mut h, Some("side_view_show"), "side_view_filter");
        assert_eq!(h.bounds("side_view").x, view.x);
        // Hidden, out of the row's layout.
        assert!(h.bounds("side_filter").width < 20.);
        view_option(&mut h, Some("side_view_show"), "side_view_filter");

        // A row is heard by its title, its status and its project.
        assert_eq!(
            heard(&mut h, "agent_a6"),
            "zgx prod: Windows platform, Done, zgx"
        );
        // Renamed in place: a second press, a name, Enter.
        double_click(&mut h, "agent_a6");
        h.frames(10);
        assert!(h.find("agent_a6_rename").is_some(), "the title's editor");
        // Its title selected: Right (to its end), then more of it.
        h.key(Key::ArrowRight);
        h.ui.dispatch(InputEvent::Text(" now".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("agent_a6_rename").is_none());
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "zgx prod: Windows platform now")
        );

        // Deleted from its menu, after asking.
        secondary(&mut h, "agent_a5");
        h.frames(10);
        assert!(h.find("agent_a5_menu_rename").is_some());
        assert!(h.find("agent_a5_menu_copy_trigger").is_some());
        h.click("agent_a5_menu_delete");
        h.frames(20);
        assert!(h.find("side_delete_dialog").is_some());
        h.click("side_delete_confirm");
        h.frames(20);
        healthy(&h);
        assert!(h.find("agent_a5").is_none());

        // A section of one's own, from the view menu, then renamed.
        h.click("side_view");
        h.frames(20);
        h.click("side_view_new_section");
        h.frames(20);
        h.type_text("side_section_name", "Later");
        h.click("side_section_save");
        h.frames(20);
        healthy(&h);
        assert!(h.find("side_later").is_some());
        assert!(h.texts().iter().any(|t| t == "Drop sessions here"));
        hover_id(&mut h, "side_later_header");
        h.click("side_later_more");
        h.frames(20);
        h.click("side_later_edit");
        h.frames(20);
        h.type_text("side_section_name", " on");
        h.click("side_section_save");
        h.frames(20);
        assert_eq!(h.text("side_later_header"), "Later on");

        // The pointer over rows still runs no script (the project icons
        // light by the engine's group hover). (Past the second in which a
        // hover card, having just shown, would show the next at once.)
        h.ui.dispatch(InputEvent::PointerMove { x: 700., y: 400. });
        std::thread::sleep(std::time::Duration::from_millis(1100));
        h.frames(2);
        let calls = h.calls();
        for id in ["agent_a1", "agent_a4", "agent_a3"] {
            hover_id(&mut h, id);
        }
        h.frames(10);
        assert_eq!(h.calls(), calls, "hover ran the script");

        // Resting on a row, its hover card comes beside it.
        hover_id(&mut h, "agent_a4");
        assert!(h.find("agent_a4_card").is_none(), "not at once");
        assert!(h.wait_until(|h| h.find("agent_a4_card").is_some()));
        h.frames(20);
        let (row, card) = (h.bounds("agent_a4"), h.bounds("agent_a4_card"));
        assert_eq!(card.width, 284.);
        assert_eq!(card.x, row.x + row.width + 10.);
        snapshot(&h, "sidebar_card");
        h.ui.dispatch(InputEvent::PointerMove { x: 700., y: 400. });
        h.frames(20);
    });
}

/// Two presses at node `id`, as a window delivers them (with the keys
/// held, so the second counts as a double click's).
fn double_click(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    let (x, y) = (b.x + b.width / 2., b.y + b.height / 2.);
    let button = zgx::input::PointerButton::Primary;
    for _ in 0..2 {
        h.ui.dispatch_with_modifiers(
            InputEvent::PointerDown { x, y, button },
            Modifiers::default(),
        );
        h.ui.dispatch_with_modifiers(InputEvent::PointerUp { x, y, button }, Modifiers::default());
        h.settle();
    }
}

/// Drags sidebar row `row` to `y` points into node `to` (from its top),
/// a frame at each step; `during` sees it before the release.
fn drag_row(h: &mut Harness, row: &str, to: &str, dy: f32, during: impl FnOnce(&mut Harness)) {
    use zgx::input::PointerButton::Primary;
    let from = h.bounds(row);
    let (fx, fy) = (from.x + 60., from.y + from.height / 2.);
    h.ui.dispatch(InputEvent::PointerMove { x: fx, y: fy });
    h.ui.dispatch(InputEvent::PointerDown {
        x: fx,
        y: fy,
        button: Primary,
    });
    let target = h.bounds(to);
    let (tx, ty) = (target.x + 60., target.y + dy);
    for step in 1..=10 {
        let k = step as f32 / 10.;
        h.ui.dispatch(InputEvent::PointerMove {
            x: fx + (tx - fx) * k,
            y: fy + (ty - fy) * k,
        });
        h.frames(2);
    }
    h.frames(20);
    // The rows part as it goes: aim at where the target is now.
    let target = h.bounds(to);
    let (tx, ty) = (target.x + 60., target.y + dy);
    h.ui.dispatch(InputEvent::PointerMove { x: tx, y: ty });
    h.frames(20);
    during(h);
    h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: Primary,
    });
    h.frames(30);
    healthy(h);
}

/// Sessions drag as Zeron's: into Pinned at a place (the rows there part
/// for it), out of Pinned into a section of one's own.
#[test]
fn sidebar_rows_drag_to_pin_reorder_and_file() {
    deep(|| {
        let mut h = app();
        // "Fix flaky test" (Sessions) between the two pins: over the second
        // pin's upper half, it opens a row's gap there.
        let second = h.bounds("agent_a2").y;
        drag_row(&mut h, "agent_a3", "agent_a2", 6., |h| {
            let parted = h.bounds("agent_a2").y;
            assert_eq!(parted, second + 29. + 2., "a row's gap opens");
        });
        let (a1, a3, a2) = (
            h.bounds("agent_a1").y,
            h.bounds("agent_a3").y,
            h.bounds("agent_a2").y,
        );
        assert!(a1 < a3 && a3 < a2, "pinned between: {a1} {a3} {a2}");
        assert_eq!(h.text("side_pinned_header"), "Pinned");
        // A pin into a section of one's own: unpinned, filed there.
        drag_row(
            &mut h,
            "agent_a2",
            "side_cross_platform_zgx_header",
            14.,
            |_| {},
        );
        let (header, row) = (
            h.bounds("side_cross_platform_zgx").y,
            h.bounds("agent_a2").y,
        );
        let pinned = h.bounds("side_pinned").y;
        assert!(row > header && header > pinned, "filed: {row} {header}");
        // The sections keep their order.
        assert!(h.bounds("side_cloud_onboarding").y < header);
        snapshot(&h, "sidebar_dragged");

        // Onto the chat: it offers to mention it, and the draft takes it;
        // the sidebar's gap closes as the row leaves it.
        let pinned = h.bounds("agent_a3").y;
        drag_row(&mut h, "agent_a4", "conversation", 200., |h| {
            assert_eq!(h.text("chat_dropzone_overlay"), "Drop to mention");
            assert_eq!(h.bounds("agent_a3").y, pinned, "no gap left open");
        });
        assert!(h.find("chat_dropzone_overlay").is_none());
    });
}

/// The title of the session the chat shows (Zeron's layout).
fn turn_session(h: &mut Harness) -> String {
    h.text("ztitle_title")
}

/// Popovers and menus leave as Zeron's do (motion.rs menu_out_toward): the
/// panel fades toward its trigger over 100 ms, drawn but inert, then hides;
/// every opening plays the entrance again.
#[test]
fn menus_and_pickers_animate_out_before_they_hide() {
    deep(|| {
        let mut h = app();
        let overlay = |h: &mut Harness, id: &str| {
            let panel = h.find(id).unwrap();
            let scene = h.ui.scene.borrow();
            let overlay = scene.parent(scene.parent(panel).unwrap()).unwrap();
            scene.effects(overlay).opacity
        };
        for round in 0..2 {
            h.click("composer_model");
            h.frames(1);
            assert!(h.opacity("zeron_picker") < 1., "entering ({round})");
            h.frames(20);
            assert_eq!(h.opacity("zeron_picker"), 1.);
            h.key(Key::Escape);
            h.frames(2);
            healthy(&h);
            assert_eq!(overlay(&mut h, "zeron_picker"), 1., "drawn while it leaves");
            let fading = h.opacity("zeron_picker");
            assert!(fading < 1. && fading > 0., "fading: {fading}");
            h.frames(20);
            assert_eq!(overlay(&mut h, "zeron_picker"), 0., "then hidden");
        }
    });
}

/// The thread's composer is one row while the draft fits it and opens out
/// as it grows past it (composer.rs composer_flip), keeping the focus and
/// the caret; it folds back once the draft is well inside the row again.
#[test]
fn the_threads_composer_folds_into_a_row_while_the_draft_fits() {
    deep(|| {
        let mut h = app();
        let row = h.bounds("composer_box").height;
        assert!(row < 60., "one row at first: {row}");
        h.type_text("composer_input", "A short note");
        h.frames(20);
        assert_eq!(h.bounds("composer_box").height, row, "still fits");
        h.ui.dispatch(InputEvent::Text(
            " that goes on and on, well past what the one row can hold beside its controls".into(),
        ));
        h.settle();
        h.frames(30);
        healthy(&h);
        assert!(h.bounds("composer_box").height > row + 40., "opened out");
        // The keyboard stayed in the draft, at its end.
        h.ui.dispatch(InputEvent::Text("!".into()));
        h.settle();
        h.frames(5);
        assert!(h.text("composer_input").ends_with("controls!"));
        // Cleared, it folds back.
        h.key_with(
            Key::Character("a".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.key(Key::Backspace);
        h.frames(30);
        assert_eq!(h.bounds("composer_box").height, row, "folded again");
        // Nothing runs while the composer rests.
        h.frames(10);
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
    });
}

/// Review comments (comments.rs, comment_ui.rs): a line's "+" (shown under
/// the pointer, no script) opens a draft under it; posted, the comment is a
/// card under the line and a badge on the composer; sending folds it into
/// the prompt, read back as a badge under the bubble.
#[test]
fn a_comment_on_a_diff_line_goes_with_the_next_message() {
    deep(|| {
        let mut h = app();
        // The right pane's changes, from the composer's command.
        h.type_text("composer_input", "/diff");
        h.key(Key::Escape);
        h.key(Key::Enter);
        h.frames(40);
        healthy(&h);
        assert!(h.find("zchange_file_1").is_some(), "the changes");
        // The first file's first line's "+": hidden until the pointer is
        // over the line, which runs no script.
        let file = h.bounds("zchange_file_1");
        let (x, y) = (file.x + 3. + 36. + 18., file.y + file.height + 28. + 10.);
        h.frames(5);
        let calls = h.calls();
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.frames(4);
        assert_eq!(h.calls(), calls, "hovering a line runs no script");
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: zgx::input::PointerButton::Primary,
        });
        h.ui.dispatch(InputEvent::PointerUp {
            x,
            y,
            button: zgx::input::PointerButton::Primary,
        });
        h.settle();
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_some(), "a draft under the line");
        h.ui.dispatch(InputEvent::Text("Keep the old name".into()));
        h.settle();
        // Enter posts it (comment_ui.rs: the composer's keys).
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_none(), "posted");
        assert!(
            h.texts().iter().any(|t| t == "Keep the old name"),
            "its card under the line"
        );
        assert_eq!(h.text("composer_comments"), "1 comment");
        snapshot(&h, "review_comment");
        // Its pen edits it in place: the draft again, filled, saved by Enter.
        let card = "zchange_comment_zchange_1";
        let shown = h.bounds(card);
        h.ui.dispatch(InputEvent::PointerMove {
            x: shown.x + 40.,
            y: shown.y + 10.,
        });
        h.frames(4);
        h.click(&format!("{card}_edit"));
        h.frames(10);
        healthy(&h);
        assert!(h.find(card).is_none(), "the card gives way to its draft");
        assert_eq!(h.text("zchange_draft_input"), "Keep the old name");
        assert_eq!(h.text("zchange_draft_submit"), "Save");
        h.key_with(
            Key::Character("a".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.ui.dispatch(InputEvent::Text("Keep Centre as an alias".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_none(), "saved");
        assert!(h.texts().iter().any(|t| t == "Keep Centre as an alias"));
        assert!(!h.texts().iter().any(|t| t == "Keep the old name"));
        assert_eq!(h.text("composer_comments"), "1 comment", "still one");
        // Split: the new side's "+" (the old side takes none); the card
        // stays under its line, full width.
        h.click("zchange_split");
        h.frames(10);
        assert!(h.texts().iter().any(|t| t == "Keep Centre as an alias"));
        let file = h.bounds("zchange_file_1");
        let (x, y) = (
            file.x + file.width / 2. + 0.5 + 18.,
            file.y + file.height + 28. + 10.,
        );
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.frames(2);
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerUp { x, y, button });
        h.settle();
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_some(), "a draft on the new side");
        h.ui.dispatch(InputEvent::Text("And document it".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        assert_eq!(h.text("composer_comments"), "2 comments");
        // Sent alone, they go as the ask to address them.
        h.click("composer_send");
        h.frames(10);
        healthy(&h);
        assert!(h.find("composer_comments").is_none(), "no longer staged");
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "Address the review comments below."),
            "the prompt"
        );
        assert_eq!(h.text("sent_comments_1"), "2 comments", "its badge");
    });
}

/// Settings' Voice, Files and Appshots pages, the providers' Completion
/// and Appearance's Wallpaper, as Zeron's (settings/*.rs).
#[test]
fn settings_has_voice_files_appshots_completion_and_wallpaper() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        for (section, line) in [
            ("voice", "Speech model"),
            ("files", "Show hidden and ignored files"),
            ("appshots", "Capture Appshots"),
            ("harnesses", "Use $ for skills"),
            ("appearance", "Wallpaper folder"),
        ] {
            h.click(&format!("settings_nav_{section}"));
            h.frames(20);
            healthy(&h);
            // A provider's completion is under its row.
            if section == "harnesses" {
                h.click("provider_claude_trigger");
                h.frames(20);
            }
            assert!(says(&mut h, line), "{section}: {line}");
        }
        // A select's menu picks a value; its detail follows.
        h.click("settings_nav_appshots");
        h.frames(20);
        h.click("settings_appshot_destination");
        h.frames(10);
        h.click("settings_appshot_destination_3");
        h.frames(20);
        assert_eq!(h.text("settings_appshot_destination"), "New session");
        assert!(says(
            &mut h,
            "Stage captures in a new-session composer, keeping existing drafts intact."
        ));
        snapshot(&h, "settings_appshots");
        // Files: the delay shows while autosave is on (off at first, as
        // Zeron's).
        h.click("settings_nav_files");
        h.frames(20);
        assert!(h.find("settings_autosave_delay").is_none());
        h.click("settings_autosave");
        h.frames(20);
        assert!(h.find("settings_autosave_delay").is_some());
    });
}

/// The new-session canvas wears the artwork chosen in Appearance (shell.rs
/// new_thread_background): across its top, fading out toward the composer
/// through a mask, at 84% while frosted; removed, it goes.
#[test]
fn the_new_session_canvas_wears_its_background() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_appearance");
        h.frames(20);
        // Down the page to the Wallpaper section.
        h.ui.dispatch(InputEvent::Scroll {
            x: 900.,
            y: 400.,
            delta_x: 0.,
            delta_y: 600.,
        });
        h.frames(10);
        h.click("settings_canvas_background");
        h.frames(10);
        assert!(h.find("settings_canvas_background_remove").is_some());
        h.key(Key::Escape);
        h.frames(30);
        h.click("ztitle_new");
        h.frames(40);
        healthy(&h);
        let hero = h.find("canvas_background").expect("the artwork");
        let (bounds, uniforms) = {
            let scene = h.ui.scene.borrow();
            (
                scene.bounds(hero),
                scene.layer_shader(hero).map(|s| s.uniforms.params),
            )
        };
        let canvas = h.bounds("canvas");
        assert_eq!(bounds, canvas, "the layer over the whole canvas");
        // The image across its top, 72% of it (at most 760), cropped.
        let image = h.bounds("canvas_background_image");
        assert_eq!(image.y, canvas.y, "across the canvas's top");
        assert_eq!(image.height, (canvas.height * 0.72).min(760.));
        // The shader fades it and cuts the composer out of it: it knows
        // where the canvas centres the composer.
        let uniforms = uniforms.expect("drawn through the artwork's layer shader");
        let composer = h.bounds("new_composer");
        let [top, tall, widest, inset] = uniforms[0];
        assert_eq!(tall, composer.height, "the composer's height");
        assert_eq!((widest, inset), (736., 16.));
        let column = tall + 60.;
        let y = top + (canvas.height - top - column) / 2. + 30.;
        assert!(
            (canvas.y + y - composer.y).abs() < 1.,
            "the cutout's top on the composer's: {y} {composer:?}"
        );
        assert!(
            (composer.width - widest.min(canvas.width - 2. * inset)).abs() < 1.,
            "and its width"
        );
        assert_eq!(
            uniforms[1],
            [0., 0., 720., 480.],
            "no effect, the art's size"
        );
        snapshot(&h, "canvas_background");
        // Nothing runs while it rests.
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);

        // An effect, from Appearance (shown while there is artwork):
        // Halftone, drawn by the same shader.
        cmd(&mut h, ",", false);
        h.click("settings_nav_appearance");
        h.frames(20);
        h.ui.dispatch(InputEvent::Scroll {
            x: 900.,
            y: 400.,
            delta_x: 0.,
            delta_y: 600.,
        });
        h.frames(10);
        h.click("settings_canvas_effect");
        h.frames(20);
        h.click("settings_canvas_effect_4");
        h.frames(20);
        healthy(&h);
        h.key(Key::Escape);
        h.frames(30);
        let hero = h.find("canvas_background").expect("the artwork");
        let effect =
            h.ui.scene
                .borrow()
                .layer_shader(hero)
                .unwrap()
                .uniforms
                .params[1][0];
        assert_eq!(effect, 3., "Halftone");
    });
}

/// Zeron's own items lead the application menu (app_menus.rs): About
/// Zeron, Check for Updates… and Settings above what the system puts
/// there; the Edit menu's standard items, sent to whatever has focus; the
/// appearance under View.
#[test]
fn the_app_menu_holds_zerons_own_items() {
    deep(|| {
        use zgx_desktop::{AppMenuEntry, StandardItem};
        let h = app();
        let menus = zgx_run::menus(&h.host.commands().get());
        assert!(menus[0].application, "the application's own menu first");
        let labels = |m: &zgx_desktop::AppMenu| -> Vec<String> {
            m.entries
                .iter()
                .map(|e| match e {
                    AppMenuEntry::Item { label, .. } => label.clone(),
                    AppMenuEntry::About { name, .. } => format!("About {name}"),
                    _ => String::new(),
                })
                .collect()
        };
        assert_eq!(
            labels(&menus[0]),
            ["About Zeron", "Check for Updates…", "", "Settings"]
        );
        let AppMenuEntry::About { version, .. } = &menus[0].entries[0] else {
            panic!("About first");
        };
        assert_eq!(version, "0.2.116");
        let edit = menus.iter().find(|m| m.label == "Edit").expect("Edit");
        assert_eq!(
            edit.entries,
            [
                AppMenuEntry::Standard(StandardItem::Undo),
                AppMenuEntry::Standard(StandardItem::Redo),
                AppMenuEntry::Separator,
                AppMenuEntry::Standard(StandardItem::Cut),
                AppMenuEntry::Standard(StandardItem::Copy),
                AppMenuEntry::Standard(StandardItem::Paste),
                AppMenuEntry::Separator,
                AppMenuEntry::Standard(StandardItem::SelectAll),
            ]
        );
        let view = menus.iter().find(|m| m.label == "View").expect("View");
        assert_eq!(
            labels(view),
            [
                "Appearance: System",
                "Appearance: Light",
                "Appearance: Dark"
            ]
        );
        assert!(
            !menus.iter().any(|m| m.label == "Zeron"),
            "no menu of its own beside the application's"
        );
    });
}

/// The bottom right's toasts (toast.rs, sonner's): collapsed, the newest in
/// front and the ones before it peeking 14 above it, each 5% narrower;
/// under the pointer they fan out 14 apart, and collapse when it leaves.
/// Engine errors say themselves this way: a change while the engine is
/// away ("Engine not connected"), or while the sidebar syncs.
#[test]
fn engine_errors_toast_and_the_toasts_peek_until_the_pointer_fans_them_out() {
    deep(|| {
        let mut h = app();
        // A command found by typing, run by Enter.
        let run = |h: &mut Harness, query: &str| {
            cmd(h, "k", false);
            h.click("palette_tab_commands");
            h.frames(10);
            h.type_text("palette_input", query);
            h.frames(10);
            h.key(Key::Enter);
            h.frames(30);
            healthy(h);
        };
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        let at = h.bounds("thread_h1").y;
        run(&mut h, "go offline");
        assert!(h.find("side_connection").is_some(), "the connection pill");
        secondary(&mut h, "thread_h1");
        h.frames(10);
        h.click("thread_h1_menu_pin");
        h.frames(30);
        assert!(says(&mut h, "Engine not connected"));
        assert_eq!(h.bounds("thread_h1").y, at, "not pinned");
        run(&mut h, "engine: sync");
        secondary(&mut h, "thread_h1");
        h.frames(10);
        h.click("thread_h1_menu_archive");
        h.frames(30);
        assert!(says(&mut h, "Sidebar is still syncing. Try again shortly."));
        assert_eq!(h.bounds("thread_h1").y, at, "not archived");
        // The two stacked: the newer in front, the other peeking 14 above
        // it, 5% narrower.
        let shown = |h: &mut Harness, id: &str| {
            let node = h.find(&format!("{id}_slot")).expect(id);
            h.ui.scene.borrow().transformed_bounds(node)
        };
        let (back, front) = (shown(&mut h, "toast1"), shown(&mut h, "toast2"));
        snapshot(&h, "engine_toasts");
        assert!((back.y - (front.y - 14.)).abs() < 1., "{back:?} {front:?}");
        assert!(
            (back.width - front.width * 0.95).abs() < 1.,
            "{back:?} {front:?}"
        );
        run(&mut h, "reconnect");
        assert!(h.wait_until(|h| h.find("side_connection").is_none()));
        h.frames(30);
        secondary(&mut h, "thread_h1");
        h.frames(10);
        h.click("thread_h1_menu_pin");
        h.frames(30);
        assert_ne!(h.bounds("thread_h1").y, at, "connected, it pins");
    });
}

/// A toast's four seconds count only while the window is active
/// (toast.rs): at the back it holds what it has left, and back in front it
/// goes when that runs out, not four seconds later.
#[test]
fn a_toast_holds_its_time_while_the_window_is_away_and_resumes_it() {
    deep(|| {
        use std::time::{Duration, Instant};
        let mut h = app();
        run_command(&mut h, "go offline");
        secondary(&mut h, "thread_h1");
        h.frames(10);
        h.click("thread_h1_menu_pin");
        h.frames(30);
        assert!(says(&mut h, "Engine not connected"));
        let wait = |h: &mut Harness, ms: u64| {
            let until = Instant::now() + Duration::from_millis(ms);
            while Instant::now() < until {
                h.settle();
                h.frames(1);
                std::thread::sleep(Duration::from_millis(10));
            }
        };
        wait(&mut h, 2000);
        assert!(says(&mut h, "Engine not connected"), "still counting");
        h.ui.set_window_active(false);
        h.frames(2);
        // Past its four seconds: held.
        wait(&mut h, 3000);
        assert!(says(&mut h, "Engine not connected"), "held at the back");
        h.ui.set_window_active(true);
        let back = Instant::now();
        let mut gone = false;
        while back.elapsed() < Duration::from_secs(10) {
            h.settle();
            h.frames(1);
            if !says(&mut h, "Engine not connected") {
                gone = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(gone, "it goes");
        assert!(
            back.elapsed() < Duration::from_millis(3500),
            "with what it had left, not four seconds more: {:?}",
            back.elapsed()
        );
        healthy(&h);
    });
}

/// The space switcher (spaces.rs) shows each project's artwork where its
/// checkout has one, the monogram otherwise, and the offline glyph after a
/// project no device holding it can reach.
#[test]
fn the_space_switcher_shows_art_and_the_offline_glyph() {
    deep(|| {
        let mut h = app();
        h.click("side_filter");
        h.frames(20);
        let svg_in = |h: &mut Harness, id: &str| {
            let node = h.find(id).expect(id);
            let scene = h.ui.scene.borrow();
            let mut stack = vec![node];
            let mut found = 0;
            while let Some(n) = stack.pop() {
                if matches!(scene.kind(n), zgx::scene::NodeKind::Svg(..)) {
                    found += 1;
                }
                stack.extend(scene.children(n).iter().copied());
            }
            found
        };
        assert_eq!(svg_in(&mut h, "side_filter_zgx"), 1, "zgx's art");
        assert!(
            h.find("side_filter_grid-website_offline").is_some(),
            "offline"
        );
        assert!(h.find("side_filter_zgx_offline").is_none());
        assert_eq!(
            svg_in(&mut h, "side_filter_grid-website"),
            1,
            "grid-website: its monogram, then the offline glyph"
        );
        snapshot(&h, "spaces_art_offline");
        h.click("side_filter_grid-website");
        h.frames(20);
        assert!(
            h.find("side_filter_offline").is_some(),
            "the trigger says it too"
        );
        h.click("side_filter");
        h.frames(20);
        h.click("side_filter_zgx");
        h.frames(20);
        assert!(h.find("side_filter_offline").is_none());
    });
}

/// ⌘K searches the workspace's files' text too ("In Files", as Zeron's
/// palette): from two characters, at most three matches a file, the line
/// in mono under its path and line; a match opens its file.
#[test]
fn the_palette_searches_inside_files() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "c");
        h.frames(10);
        assert!(
            h.find("palette_content_crates_zgx_compose_rs_3").is_none(),
            "one character"
        );
        h.type_text("palette_input", "entred");
        h.frames(10);
        healthy(&h);
        assert!(
            h.find("palette_content_crates_zgx_compose_rs_3").is_some(),
            "the match"
        );
        assert!(h.texts().iter().any(|t| t == "In Files"));
        assert!(h.texts().iter().any(|t| t == "crates/zgx/compose.rs:3"));
        snapshot(&h, "palette_in_files");
        h.click("palette_tab_files");
        h.frames(10);
        assert!(
            h.find("palette_content_crates_zgx_compose_rs_3").is_some(),
            "under Files too"
        );
        h.click("palette_content_crates_zgx_compose_rs_3");
        h.frames(40);
        healthy(&h);
        assert!(h.find("palette_input").is_none(), "closed");
        assert!(
            h.find("file_file_crates_zgx_compose_rs_editor").is_some(),
            "the file opened"
        );
    });
}

/// The boot splash (shell.rs, loaders.rs): while the engine connects at
/// launch, the window shows only the spinner and "Setting up Zeron
/// environment" on the glass; once it is ready the splash fades out over
/// the app.
#[test]
fn the_boot_splash_covers_the_app_until_the_engine_connects() {
    deep(|| {
        let mut h = Harness::new(|runtime| {
            let host = ScriptHost::new(
                runtime,
                Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide/app_zeron.luau"),
            );
            host.action("inspect", |_| {});
            host.action("close_window", |_| {});
            host.action("open_app", |_| {});
            host.shared("boot_splash", true);
            host
        });
        h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
        h.frames(10);
        healthy(&h);
        assert!(h.find("boot_splash_spinner").is_some(), "the spinner");
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "Setting up Zeron environment")
        );
        // What a press on the titlebar's + reaches.
        let reaches = |h: &mut Harness, id: &str| {
            let b = h.bounds("ztitle_new");
            let target = h.find(id).unwrap();
            let scene = h.ui.scene.borrow();
            scene
                .hit_test(b.x + b.width / 2., b.y + b.height / 2.)
                .is_some_and(|hit| scene.is_within(hit, target))
        };
        assert!(reaches(&mut h, "boot_splash"), "it covers the window");
        assert!(
            !reaches(&mut h, "ztitle_new"),
            "nothing beneath takes input"
        );
        snapshot(&h, "boot_splash");
        // The sample engine connects after a moment (real time), and the
        // splash plays its way out (150 ms held, 500 to fade).
        std::thread::sleep(std::time::Duration::from_millis(1400));
        h.settle();
        h.frames(60);
        healthy(&h);
        assert!(h.find("boot_splash").is_none(), "gone once it has faded");
        // The app beneath answers again.
        h.click("ztitle_new");
        h.frames(40);
        assert!(h.find("canvas").is_some(), "the new-session canvas");
    });
}

/// History as a right-pane surface (history.rs): the commits with their
/// graph, a search that narrows them ("No matching commits" when none
/// match), Fetch all, Load more; a click picks a commit.
#[test]
fn history_is_a_surface_that_searches_its_commits() {
    deep(|| {
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        for _ in 0..3 {
            cmd(&mut h, "w", false);
        }
        assert!(h.find("zpane_picker").is_some());
        h.click("zpick_history");
        h.frames(40);
        healthy(&h);
        let id = "history_history_1";
        assert!(h.find(id).is_some(), "the history surface");
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t.contains(what));
        assert!(says(&mut h, "glass: press gives to 0.985"));
        // Its graph is a chart a screen reader reads, not decoration.
        let graph = heard_under(&mut h, id);
        assert!(
            graph
                .iter()
                .any(|l| l.starts_with("Commit graph: ") && l.contains(" lanes, ")),
            "{graph:?}"
        );
        snapshot(&h, "history");
        h.type_text(&format!("{id}_search"), "wing");
        h.frames(10);
        assert!(says(&mut h, "glass: press gives to 0.985"), "Wing's");
        assert!(!says(&mut h, "the Zeron app's transcript"), "not Gaël's");
        h.type_text(&format!("{id}_search"), "zzz");
        h.frames(10);
        assert!(says(&mut h, "No matching commits"));
        h.click(&format!("{id}_fetch"));
        h.frames(2);
        assert!(says(&mut h, "Fetching…"));
    });
}

/// A click on `id` with the pointer brought over it first, as a hand
/// does: what shows only under the pointer (`group_hover`) is there then.
fn hover_click(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::PointerMove {
        x: b.x + b.width / 2.,
        y: b.y + b.height / 2.,
    });
    h.frames(10);
    h.click(id);
}

/// A pointer pressed at the middle of `from`, moved in steps to the middle
/// of `to` (or `dx` along from where it pressed), and released.
fn drag_between(h: &mut Harness, from: &str, to: Option<&str>, dx: f32) {
    use zgx::input::PointerButton::Primary;
    let a = h.bounds(from);
    let (fx, fy) = (a.x + a.width / 2., a.y + a.height / 2.);
    let (tx, ty) = match to {
        Some(to) => {
            let b = h.bounds(to);
            (b.x + b.width / 2., b.y + b.height / 2.)
        }
        None => (fx + dx, fy),
    };
    h.ui.dispatch(InputEvent::PointerMove { x: fx, y: fy });
    h.ui.dispatch(InputEvent::PointerDown {
        x: fx,
        y: fy,
        button: Primary,
    });
    for step in 1..=10 {
        let k = step as f32 / 10.;
        h.ui.dispatch(InputEvent::PointerMove {
            x: fx + (tx - fx) * k,
            y: fy + (ty - fy) * k,
        });
        h.frames(2);
    }
    h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: Primary,
    });
    h.frames(20);
    healthy(h);
}

/// History's toolbar and columns (history.rs): the count and how far the
/// branch is ahead and behind; a SHA copies; the Columns menu hides and
/// resets them, a column drags to another place and resizes by its edge;
/// a tip folds its branch; the tips alone; a fetch that fails says so.
#[test]
fn history_copies_folds_shows_tips_and_arranges_its_columns() {
    deep(|| {
        let mut h = desktop_app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        for _ in 0..3 {
            cmd(&mut h, "w", false);
        }
        h.click("zpick_history");
        h.frames(40);
        healthy(&h);
        let id = "history_history_1";
        let table = format!("{id}_commits");
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        assert!(says(&mut h, "10 commits"));
        assert!(says(&mut h, "3 ahead") && says(&mut h, "1 behind"));
        assert!(says(&mut h, "gael/zeron-parity"), "the branch");
        // A SHA copies, and says so for a moment.
        h.click(&format!("{table}_3b87140c_sha"));
        h.frames(2);
        assert_eq!(h.desktop.as_ref().unwrap().clipboard(), "3b87140c");
        assert!(says(&mut h, "Copied"));
        assert!(h.wait_until(|h| {
            h.frames(5);
            !h.texts().iter().any(|t| t == "Copied")
        }));
        // Columns: the date hidden, then everything reset.
        hover_click(&mut h, &format!("{table}_columns"));
        h.frames(20);
        h.click(&format!("{table}_columns_menu_date"));
        h.frames(10);
        assert!(h.find(&format!("{table}_col_date")).is_none(), "no date");
        assert!(!says(&mut h, "Oct 23, 2026"));
        h.click(&format!("{table}_columns_menu_reset"));
        h.frames(20);
        assert!(h.find(&format!("{table}_col_date")).is_some(), "reset");
        // The SHA dragged before the author.
        drag_between(
            &mut h,
            &format!("{table}_col_sha"),
            Some(&format!("{table}_col_author")),
            0.,
        );
        let (author, sha) = (
            h.bounds(&format!("{table}_col_author")),
            h.bounds(&format!("{table}_col_sha")),
        );
        assert!(sha.x < author.x, "moved: {sha:?} {author:?}");
        // The edge before a column widens it as it drags toward the subject.
        let before = h.bounds(&format!("{table}_col_sha")).width;
        drag_between(&mut h, &format!("{table}_resize_sha"), None, -24.);
        let after = h.bounds(&format!("{table}_col_sha")).width;
        assert!(after > before + 10., "resized: {before} → {after}");
        // Folding wing/glass hides its plain commits.
        assert!(says(&mut h, "glass: press gives to 0.985"));
        hover_click(&mut h, &format!("{table}_fold_a1c2e3f4"));
        h.frames(20);
        assert!(!says(&mut h, "glass: press gives to 0.985"), "folded");
        assert!(
            says(&mut h, "glass: a layer of its own for the hover"),
            "it branches off"
        );
        assert!(
            h.find("role:button \"Expand wing/glass (2 hidden)\"")
                .is_some(),
            "{:?}",
            h.texts()
        );
        h.click(&format!("{table}_fold_a1c2e3f4"));
        h.frames(20);
        assert!(says(&mut h, "glass: press gives to 0.985"), "open again");
        // The tips alone.
        h.click(&format!("{id}_view"));
        h.frames(20);
        assert!(says(&mut h, "glass: the hover layer under the active one"));
        assert!(!says(
            &mut h,
            "styleguide: the Zeron app's transcript from the kit"
        ));
        h.click(&format!("{id}_view"));
        h.frames(20);
        assert!(says(
            &mut h,
            "styleguide: the Zeron app's transcript from the kit"
        ));
        // The first fetch fails, the next clears it.
        h.click(&format!("{id}_fetch"));
        assert!(h.wait_until(|h| {
            h.frames(5);
            h.find(&format!("{id}_fetch_failed")).is_some()
        }));
        assert!(says(
            &mut h,
            "Fetch failed: Could not resolve host: github.com"
        ));
        snapshot(&h, "history_tools");
        h.click(&format!("{id}_fetch"));
        assert!(h.wait_until(|h| {
            h.frames(5);
            h.find(&format!("{id}_fetch_failed")).is_none()
        }));
        healthy(&h);
    });
}

/// Files (files/*.rs): folders fold; a file opens in the right pane (a
/// Markdown preview with its source a click away, the editor marking an
/// edit until ⌘S); a secondary click renames in place or deletes, asked
/// first; the magnifier searches the paths.
#[test]
fn files_open_edit_rename_delete_and_search() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        assert!(h.find("ztree_crates/zgx/compose.rs").is_some(), "the tree");
        // A folder folds.
        h.click("ztree_crates/zgx");
        h.frames(10);
        assert!(h.find("ztree_crates/zgx/compose.rs").is_none(), "folded");
        h.click("ztree_crates/zgx");
        h.frames(10);
        assert!(h.find("ztree_crates/zgx/compose.rs").is_some());
        // Markdown opens as its preview; Source shows the editor.
        h.click("ztree_README.md");
        h.frames(30);
        healthy(&h);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t.contains(what));
        assert!(says(&mut h, "Validation and current boundaries"));
        h.click("file_file_README_md_markdown");
        h.frames(10);
        assert!(h.find("file_file_README_md_editor").is_some());
        h.click("file_file_README_md_editor");
        h.ui.dispatch(InputEvent::Text("x".into()));
        h.settle();
        h.frames(5);
        assert!(h.find("file_file_README_md_edited").is_some(), "edited");
        h.key_with(
            Key::Character("s".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(5);
        assert!(h.find("file_file_README_md_edited").is_none(), "saved");
        snapshot(&h, "files");
        // Rename in place.
        secondary(&mut h, "ztree_Cargo.toml");
        h.click("files_menu_rename");
        h.frames(10);
        let field = "ztree_Cargo.toml_rename";
        assert!(h.find(field).is_some(), "the name in a field");
        h.key_with(
            Key::Character("a".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.ui.dispatch(InputEvent::Text("Workspace.toml".into()));
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("ztree_Workspace.toml").is_some(), "renamed");
        // Delete, asked first.
        secondary(&mut h, "ztree_Workspace.toml");
        h.click("files_menu_delete");
        h.frames(20);
        assert!(says(&mut h, "Delete permanently?"));
        h.click("files_delete_confirm");
        h.frames(20);
        assert!(h.find("ztree_Workspace.toml").is_none(), "deleted");
        // Search: the field is always there.
        h.click("files_search");
        h.frames(10);
        h.ui.dispatch(InputEvent::Text("scroll".into()));
        h.settle();
        h.frames(10);
        assert!(says(&mut h, "compose_scrollbar.rs"));
        assert!(
            h.find("ztree_README.md").is_none(),
            "results in the tree's place"
        );
        h.ui.dispatch(InputEvent::Text("zzz".into()));
        h.settle();
        h.frames(10);
        assert!(says(&mut h, "No files found."));
    });
}

/// Comments on a file's own text (comments.rs ReviewComment::file): a
/// Markdown preview's block takes one on the line it starts on, staged on
/// the composer with the diff's and sent under the files' header.
#[test]
fn a_markdown_files_block_takes_a_comment_on_its_line() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        h.click("ztree_README.md");
        h.frames(30);
        healthy(&h);
        let preview = "file_file_README_md";
        // Under the pointer, the block's "+" before it.
        let add = format!("{preview}_preview_add_1");
        let at = h.bounds(&add);
        h.ui.dispatch(InputEvent::PointerMove {
            x: at.x + 60.,
            y: at.y + 8.,
        });
        h.frames(4);
        h.click(&add);
        h.frames(10);
        healthy(&h);
        assert_eq!(h.text(&format!("{preview}_draft")), "README.md:1");
        h.ui.dispatch(InputEvent::Text("Say what it is first".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find(&format!("{preview}_draft")).is_none(), "posted");
        assert!(h.texts().iter().any(|t| t == "Say what it is first"));
        assert_eq!(h.text("composer_comments"), "1 comment");
        snapshot(&h, "file_comment");
        h.click("composer_send");
        h.frames(10);
        healthy(&h);
        assert_eq!(h.text("sent_comments_1"), "1 comment", "read back");
    });
}

/// Comments in the code editor (preview.rs editor overlays): under the
/// pointer a line's gutter offers "+" (the engine's, no script), a press
/// opens the draft card under the line; posted, the line's cell shows its
/// glyph, a press shows its card and hides it; the comment follows its
/// line as text is typed above it; posted over unsaved edits, the next
/// send waits for the file's save.
#[test]
fn the_code_editor_takes_comments_in_its_gutter() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        for folder in ["ztree_crates", "ztree_crates/zgx"] {
            if h.find("ztree_crates/zgx/compose.rs").is_none() {
                h.click(folder);
                h.frames(10);
            }
        }
        h.click("ztree_crates/zgx/compose.rs");
        h.frames(30);
        healthy(&h);
        let editor = h.find("file_file_crates_zgx_compose_rs_editor").unwrap();
        let cell = |h: &mut Harness, line: usize| {
            h.ui.editor(editor)
                .unwrap()
                .gutter_cell(line)
                .unwrap_or_else(|| panic!("line {line}'s cell"))
        };
        let press = |h: &mut Harness, line: usize| {
            let c = cell(h, line);
            press_at(h, c.x + c.width / 2., c.y + c.height / 2.);
        };
        // The pointer down the gutter runs nothing of the app's.
        h.frames(10);
        let calls = h.calls();
        for line in [1, 2, 3, 2] {
            let c = cell(&mut h, line);
            h.ui.dispatch(InputEvent::PointerMove {
                x: c.x + c.width / 2.,
                y: c.y + c.height / 2.,
            });
            h.frames(2);
        }
        assert_eq!(h.calls(), calls, "hovering the gutter runs no script");
        assert!(h.find("role:button \"Comment on line 2\"").is_some());
        // A press: the draft under its line.
        press(&mut h, 2);
        assert!(h.find("file_comment_draft").is_some());
        assert!(shows(&mut h, "crates/zgx/compose.rs:2"));
        let (line, card) = (cell(&mut h, 2), h.bounds("file_comment_draft"));
        assert!(
            (card.y - (line.y + line.height)).abs() < 1.5,
            "under its line: {line:?} {card:?}"
        );
        snapshot(&h, "editor_comment_draft");
        let input = h.find("file_comment_draft_input");
        assert_eq!(
            h.ui.focused_editor().map(|e| e.node),
            input,
            "the draft takes the keyboard"
        );
        h.ui.dispatch(InputEvent::Text("Name what the parent is".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("file_comment_draft").is_none(), "posted");
        assert_eq!(h.text("composer_comments"), "1 comment");
        assert!(h.find("role:button \"Open comment on line 2\"").is_some());
        // Its glyph's press shows its card, a second hides it.
        press(&mut h, 2);
        assert!(h.find("file_comment_card").is_some());
        assert!(shows(&mut h, "Name what the parent is"));
        press(&mut h, 2);
        assert!(h.find("file_comment_card").is_none());
        // A line typed above it: it follows its line, to line 3.
        let first = cell(&mut h, 1);
        press_at(
            &mut h,
            first.x + first.width + 2.,
            first.y + first.height / 2.,
        );
        h.ui.dispatch(InputEvent::Text("// The parent decides.\n".into()));
        h.settle();
        h.frames(10);
        healthy(&h);
        assert!(h.find("role:button \"Open comment on line 3\"").is_some());
        assert!(h.find("role:button \"Open comment on line 2\"").is_none());
        press(&mut h, 3);
        assert!(shows(&mut h, "crates/zgx/compose.rs:3"));
        press(&mut h, 3);
        // Posted over edits not saved: the send waits for the save.
        press(&mut h, 5);
        h.ui.dispatch(InputEvent::Text(
            "Centre only when nothing stretches".into(),
        ));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        assert_eq!(h.text("composer_comments"), "2 comments");
        h.click("composer_send");
        h.frames(10);
        assert!(h.find("sent_comments_1").is_none(), "held");
        assert_eq!(h.text("composer_comments"), "2 comments");
        press_at(
            &mut h,
            first.x + first.width + 40.,
            first.y + first.height / 2.,
        );
        cmd(&mut h, "s", false);
        h.frames(10);
        h.click("composer_send");
        h.frames(10);
        healthy(&h);
        assert_eq!(h.text("sent_comments_1"), "2 comments", "sent once saved");
    });
}

/// A comment on a renamed file's old side cites the file it was in before
/// the rename (comments.rs cite_path), its card and its prompt alike.
#[test]
fn an_old_sides_comment_on_a_renamed_file_cites_its_old_path() {
    deep(|| {
        let mut h = app();
        h.type_text("composer_input", "/diff");
        h.key(Key::Escape);
        h.key(Key::Enter);
        h.frames(40);
        healthy(&h);
        // The branch's changes hold the rename.
        h.click("zchange_scope");
        h.frames(10);
        h.click("zchange_scope_branch");
        h.frames(20);
        h.click("zchange_fold_all");
        h.frames(10);
        let renamed = (1..12)
            .map(|i| format!("zchange_file_{i}"))
            .find(|id| h.find(id).is_some() && h.text(id).contains("crates/zgx/src/layout.rs"))
            .unwrap_or_else(|| panic!("the renamed file: {:?}", h.texts()));
        h.click(&renamed);
        h.frames(10);
        // Its deletion, "-    Centre,": under its header, its notice and
        // its hunk's header, after a line of context.
        let file = h.bounds(&renamed);
        let (x, y) = (
            file.x + 3. + 18.,
            file.y + file.height + 24. + 28. + 21. + 10.,
        );
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.frames(4);
        press_at(&mut h, x, y);
        assert!(h.find("zchange_draft").is_some(), "a draft under the line");
        assert!(shows(&mut h, "crates/zgx/src/layout_old.rs:13"));
        h.ui.dispatch(InputEvent::Text("Keep Centre as an alias".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("zchange_draft").is_none(), "posted");
        assert!(shows(&mut h, "crates/zgx/src/layout_old.rs:13"), "its card");
        h.click("composer_send");
        h.frames(10);
        healthy(&h);
        // The prompt read back: its badge's card under the pointer.
        hover(&mut h, "sent_comments_1");
        arrives(&mut h, "sent_comments_1_card");
        assert!(
            shows(&mut h, "crates/zgx/src/layout_old.rs:13"),
            "the prompt"
        );
    });
}

/// Presses node `from`, drags to `to`'s point (`dx`, `dy` from its top
/// left), a frame a step; `during` sees it before the release.
fn drag_to(
    h: &mut Harness,
    from: &str,
    to: &str,
    (dx, dy): (f32, f32),
    during: impl FnOnce(&mut Harness),
) {
    use zgx::input::PointerButton::Primary;
    let a = h.bounds(from);
    let (fx, fy) = (a.x + 40., a.y + a.height / 2.);
    h.ui.dispatch(InputEvent::PointerMove { x: fx, y: fy });
    h.ui.dispatch(InputEvent::PointerDown {
        x: fx,
        y: fy,
        button: Primary,
    });
    let b = h.bounds(to);
    let (tx, ty) = (b.x + dx, b.y + dy);
    for step in 1..=10 {
        let k = step as f32 / 10.;
        h.ui.dispatch(InputEvent::PointerMove {
            x: fx + (tx - fx) * k,
            y: fy + (ty - fy) * k,
        });
        h.frames(2);
    }
    h.frames(5);
    during(h);
    h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: Primary,
    });
    h.frames(20);
    healthy(h);
}

/// `key`, then the frames it takes to land.
fn cmd_key(h: &mut Harness, key: Key) {
    h.key(key);
    h.frames(20);
    healthy(h);
}

/// Files' rows drag (files/drag.rs): into the chat, a mention in the draft
/// ("Drop to attach" over it meanwhile); onto a folder, or a file's
/// folder, or the workspace root, a move, never into where it is. The
/// workspace is live: what a turn writes recolours as it lands, and the
/// working tree's changes grow by it.
#[test]
fn files_drag_into_the_chat_and_onto_folders_and_show_what_a_turn_writes() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        drag_to(
            &mut h,
            "ztree_Cargo.toml",
            "chat_dropzone",
            (300., 200.),
            |h| {
                assert!(h.texts().iter().any(|t| t == "Drop to attach"));
                let chip = h.ui.input.drag_state().and_then(|d| d.preview);
                let chip = h.ui.scene.borrow().bounds(chip.expect("the chip follows"));
                assert_eq!(chip.height, 24., "{chip:?}");
            },
        );
        assert!(
            h.text("composer_input").contains("@Cargo.toml "),
            "{}",
            h.text("composer_input")
        );
        // Onto a folder: it moves there, chosen where it went.
        drag_to(&mut h, "ztree_README.md", "ztree_docs", (60., 13.), |h| {
            assert_eq!(h.text("ztree_root"), "Move to workspace root");
        });
        assert!(h.find("ztree_docs/README.md").is_some(), "moved");
        assert!(h.find("ztree_README.md").is_none());
        assert_eq!(h.text("ztree_root"), "Workspace root");
        // Onto a file of the root: its folder, the root.
        drag_to(
            &mut h,
            "ztree_docs/README.md",
            "ztree_Cargo.toml",
            (60., 13.),
            |_| {},
        );
        assert!(h.find("ztree_README.md").is_some(), "back at the root");
        // Never into itself, nor below it; dragged, it stays open.
        drag_to(
            &mut h,
            "ztree_crates/zgx",
            "ztree_crates/zgx/compose.rs",
            (60., 13.),
            |_| {},
        );
        assert!(
            h.find("ztree_crates/zgx/compose.rs").is_some(),
            "where it was"
        );
        drag_to(
            &mut h,
            "ztree_crates",
            "ztree_crates/zgx",
            (60., 13.),
            |_| {},
        );
        assert!(h.find("ztree_crates/zgx").is_some(), "where it was");
        // A turn's edit shows as it lands.
        let clean = text_color(&mut h, "ztree_Cargo.toml", "Cargo.toml");
        assert_eq!(
            text_color(&mut h, "ztree_docs/release-notes.md", "release-notes.md"),
            clean
        );
        h.type_text("composer_input", "Lead with the glass");
        h.click("composer_send");
        let edited = h.wait_until(|h| {
            h.frames(1);
            text_color(h, "ztree_docs/release-notes.md", "release-notes.md") != clean
        });
        assert!(edited, "modified as the edit lands");
        assert_eq!(
            text_color(&mut h, "ztree_docs", "docs"),
            text_color(&mut h, "ztree_docs/release-notes.md", "release-notes.md"),
            "its folder takes its colour"
        );
        // The turn runs on the clock: done, a command runs at once (sent
        // while it works, it would wait in the queue behind it).
        let done = h.wait_until(|h| {
            h.frames(1);
            !h.host
                .states()
                .iter()
                .any(|(k, v)| k.ends_with("agent:a1:working") && *v == Value::Bool(true))
        });
        assert!(done, "the turn ends");
        h.type_text("composer_input", "/diff");
        h.key(Key::Escape);
        h.key(Key::Enter);
        h.frames(40);
        assert_eq!(h.text("zchange_counts"), "5 Uncommitted changes");
    });
}

/// The Files tree (files/tree.rs, mod.rs, search.rs, context_menu.rs):
/// hidden and ignored files behind the toolbar's eye, "Empty folder", a big
/// folder a page at a time, the search capped at 200, Copy path's full
/// path, and the band when file updates stop.
#[test]
fn the_files_tree_pages_hides_and_says_what_it_cannot_list() {
    deep(|| {
        let mut h = desktop_app();
        cmd(&mut h, "e", false);
        h.frames(30);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        // Hidden and ignored files show only with the eye.
        assert!(h.find("ztree_target").is_none(), "ignored, hidden");
        assert!(h.find("ztree_.github").is_none(), "a dotfolder, hidden");
        h.click("files_hidden");
        h.frames(10);
        assert!(h.find("ztree_target").is_some() && h.find("ztree_.github").is_some());
        h.click("files_hidden");
        h.frames(10);
        assert!(h.find("ztree_target").is_none());
        // An empty folder says so.
        h.click("ztree_crates/zgx-desktop");
        h.frames(10);
        assert!(says(&mut h, "Empty folder"));
        // A big folder lists 100, then more.
        h.click("ztree_crates");
        h.frames(10);
        h.click("ztree_assets");
        h.frames(10);
        h.click("ztree_assets/icons");
        h.frames(10);
        assert!(h.find("ztree_assets/icons/glyph-001.svg").is_some());
        // At the page's end (End, from the tree's focus): "Load more…"
        // lists the next.
        let tree = h.find("role:tree").unwrap();
        h.ui.input.focus(&h.ui.scene, Some(tree));
        cmd_key(&mut h, Key::End);
        assert!(
            h.find("ztree_assets/icons/.load-more").is_some(),
            "{:?}",
            h.texts()
        );
        assert!(
            h.find("ztree_assets/icons/glyph-101.svg").is_none(),
            "a page"
        );
        h.click("ztree_assets/icons/.load-more");
        h.frames(10);
        h.ui.input.focus(&h.ui.scene, Some(tree));
        cmd_key(&mut h, Key::End);
        assert!(
            h.find("ztree_latest").is_some(),
            "the next page, then the rest"
        );
        cmd_key(&mut h, Key::Home);
        // The search stops at 200, and says so.
        h.type_text("files_search", "glyph");
        h.frames(10);
        assert!(says(&mut h, "Showing the first 200 matches"));
        h.key(Key::Escape);
        h.frames(10);
        assert!(h.find("ztree_Cargo.toml").is_some() || h.find("ztree_assets").is_some());
        // Copy path copies the full one.
        h.click("ztree_assets");
        h.frames(10);
        let row = h.find("ztree_Cargo.toml").is_some();
        assert!(row, "Cargo.toml in view");
        secondary(&mut h, "ztree_Cargo.toml");
        h.click("files_menu_copy");
        h.frames(5);
        assert_eq!(
            h.desktop.as_ref().unwrap().clipboard(),
            "/Users/gael/Developer/zgx/Cargo.toml"
        );
        // The failed run on the Mac mini: its file updates stopped.
        h.click("agent_a8");
        h.frames(30);
        assert!(h.find("files_watch_error").is_some(), "the band");
        assert!(says(&mut h, "Refresh now"));
        h.click("files_refresh_now");
        h.frames(10);
        assert!(h.find("files_watch_error").is_none(), "refreshed");
        healthy(&h);
    });
}

/// A file's surface (files/preview.rs): its toolbar (Reveal file in tree,
/// Open in default editor, word wrap), why a file can't be edited, a file
/// changed outside Zeron asking before its edits go, and a close saving
/// first, asking when it can't.
#[test]
fn a_file_says_why_it_cannot_be_edited_and_asks_before_losing_edits() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        let open = |h: &mut Harness, path: &str| {
            h.click(&format!("ztree_{path}"));
            h.frames(30);
            healthy(h);
        };
        let typed = |h: &mut Harness, editor: &str, text: &str| {
            h.click(editor);
            h.ui.dispatch(InputEvent::Text(text.into()));
            h.settle();
            h.frames(5);
        };
        let save = |h: &mut Harness| {
            h.key_with(
                Key::Character("s".into()),
                Modifiers {
                    meta: true,
                    ..Default::default()
                },
            );
            h.frames(5);
        };
        // The toolbar.
        open(&mut h, "crates/zgx/compose.rs");
        let id = "file_file_crates_zgx_compose_rs";
        h.click(&format!("{id}_wrap"));
        h.frames(10);
        assert!(
            h.target("\"Disable word wrap\"").is_ok(),
            "wrapping: {:?} {:?} {:?}",
            h.target("\"Enable word wrap\""),
            h.target("\"Reveal file in tree\""),
            h.bounds(&format!("{id}_wrap"))
        );
        h.click(&format!("{id}_wrap"));
        h.frames(10);
        h.click("ztree_crates");
        h.frames(10);
        assert!(
            h.find("ztree_crates/zgx/compose.rs").is_none(),
            "folded away"
        );
        h.click(&format!("{id}_reveal"));
        h.frames(20);
        assert!(h.find("ztree_crates/zgx/compose.rs").is_some(), "revealed");
        // Edits are saved as the tab closes.
        typed(&mut h, &format!("{id}_editor"), "x");
        assert!(h.find(&format!("{id}_edited")).is_some());
        cmd(&mut h, "w", false);
        assert!(h.find(&format!("{id}_editor")).is_none(), "closed");
        open(&mut h, "crates/zgx/compose.rs");
        assert!(h.find(&format!("{id}_edited")).is_none(), "saved");
        // What can't be edited says why.
        for (folder, path, why) in [
            ("secrets", "secrets/deploy.pem", "Permission denied."),
            (
                "assets",
                "assets/logo.icns",
                "Binary files cannot be previewed.",
            ),
            (
                "data",
                "data/telemetry.ndjson",
                "This file is too large to preview.",
            ),
            (
                "docs",
                "docs/legacy-latin1.txt",
                "This file encoding is not supported.",
            ),
            ("", "latest", "Symlink targets are read-only."),
        ] {
            if !folder.is_empty() && h.find(&format!("ztree_{path}")).is_none() {
                h.click(&format!("ztree_{folder}"));
                h.frames(10);
            }
            open(&mut h, path);
            assert!(says(&mut h, why), "{path}: {:?}", h.texts());
            cmd(&mut h, "w", false);
        }
        // Read-only text: a large file cut short, mixed line endings.
        h.click("ztree_logs");
        h.frames(10);
        open(&mut h, "logs/engine.log");
        assert!(says(
            &mut h,
            "Large file preview is truncated and read-only."
        ));
        typed(&mut h, "file_file_logs_engine_log_editor", "x");
        assert!(
            h.find("file_file_logs_engine_log_edited").is_none(),
            "read-only"
        );
        cmd(&mut h, "w", false);
        h.click("ztree_scripts");
        h.frames(10);
        open(&mut h, "scripts/build.bat");
        typed(&mut h, "file_file_scripts_build_bat_editor", "x");
        assert!(
            h.find("file_file_scripts_build_bat_edited").is_none(),
            "read-only"
        );
        cmd(&mut h, "w", false);
        // Changed outside Zeron: a save can't go over it, nor a close.
        open(&mut h, "crates/zgx/compose_scrollbar.rs");
        let id = "file_file_crates_zgx_compose_scrollbar_rs";
        assert!(says(&mut h, "This file changed outside Zeron."));
        typed(&mut h, &format!("{id}_editor"), "x");
        save(&mut h);
        assert!(says(&mut h, "Save conflict"));
        cmd(&mut h, "w", false);
        assert!(h.find(&format!("{id}_editor")).is_some(), "still open");
        assert!(says(&mut h, "Changes could not be saved safely."));
        snapshot(&h, "files_close_blocked");
        // Discarding closes it; reopened, the change on disk still asks.
        h.click(&format!("{id}_closing_discard"));
        h.frames(20);
        assert!(
            h.find(&format!("{id}_editor")).is_none(),
            "discarded and closed"
        );
        open(&mut h, "crates/zgx/compose_scrollbar.rs");
        assert!(h.find(&format!("{id}_edited")).is_none(), "the edit went");
        typed(&mut h, &format!("{id}_editor"), "x");
        cmd(&mut h, "w", false);
        h.click(&format!("{id}_closing_keep"));
        h.frames(10);
        assert!(
            says(&mut h, "This file changed outside Zeron."),
            "kept open"
        );
        h.click(&format!("{id}_external_reload"));
        h.frames(10);
        assert!(says(&mut h, "Discard unsaved changes?"));
        h.click(&format!("{id}_reload_confirm"));
        h.frames(10);
        assert!(
            says(&mut h, "    // The thumb follows the offset, eased."),
            "reloaded"
        );
        assert!(h.find(&format!("{id}_edited")).is_none());
        // Up to date now, its edits save as it closes.
        typed(&mut h, &format!("{id}_editor"), "y");
        cmd(&mut h, "w", false);
        assert!(
            h.find(&format!("{id}_editor")).is_none(),
            "saved and closed"
        );
        healthy(&h);
    });
}

/// A session opens at its end, and stays there as panels open beside it
/// (the transcript rewraps narrower and taller).
#[test]
fn a_transcript_opens_at_its_end_and_stays_there_through_a_resize() {
    deep(|| {
        let mut h = app();
        assert!(h.find("jump").is_none(), "at the end");
        cmd(&mut h, "e", false);
        h.frames(60);
        healthy(&h);
        assert!(h.find("jump").is_none(), "still at the end");
    });
}

/// The app on a fresh install: its host keeps what setup finished, and it
/// has finished nothing yet.
fn fresh_app() -> Harness {
    started(Harness::with_desktop(|runtime| {
        let host = host(runtime);
        host.shared("first_run", true);
        host
    }))
}

/// Onboarding (onboarding.rs v0.2.129): a fresh install opens on
/// first-run setup. Welcome; Make it yours (the scheme, the accent, the
/// new-chat wallpaper and its effect); Sync your work, logging in through
/// sync's own steps in setup's frame; Connect GitHub (Cloud turning itself
/// on, the device code, approved on GitHub); the agents found on this Mac;
/// You're all set, then the first project through the add-project flow.
#[test]
fn onboarding_walks_first_run_setup_and_adds_a_project() {
    deep(|| {
        let mut h = fresh_app();
        assert!(h.find("onboarding_welcome").is_some(), "{:?}", h.texts());
        assert!(says(&mut h, "Welcome to Zeron"));
        snapshot(&h, "onboarding");
        h.click("onboarding_start");
        assert!(appear(&mut h, "onboarding_appearance"));
        assert_eq!(h.text("onboarding_progress_label"), "1 of 3");
        assert!(says(&mut h, "Make it yours"));
        h.click("onboarding_mode_light");
        h.frames(10);
        h.click("onboarding_accent_green");
        h.frames(10);
        // A wallpaper of one's own, then its effect.
        assert!(h.find("onboarding_effect_row").is_none());
        h.click("onboarding_wallpaper_choose");
        h.frames(30);
        assert!(says(&mut h, "shadow.jpg"));
        assert!(h.find("onboarding_effect_row").is_some());
        assert!(h.find("onboarding_wallpaper").is_some(), "behind the page");
        snapshot(&h, "onboarding_appearance");
        // Back, and on again.
        h.click("onboarding_back");
        assert!(appear(&mut h, "onboarding_welcome"));
        h.click("onboarding_start");
        assert!(appear(&mut h, "onboarding_appearance"));
        h.click("onboarding_continue");
        assert!(appear(&mut h, "onboarding_sync"));
        assert_eq!(h.text("onboarding_progress_label"), "2 of 3");
        assert!(says(
            &mut h,
            "Not ready? Everything stays on this Mac until you log in."
        ));
        assert!(h.find("onboarding_skip_sync").is_some());

        // Logging in: sync's steps, in setup's frame, under its progress.
        h.click("onboarding_log_in");
        h.frames(20);
        assert!(says(&mut h, "Finish logging in"), "{:?}", h.texts());
        assert!(h.find("onboarding").is_some() && h.find("sync").is_none());
        assert!(appear(&mut h, "sync_offer"));
        assert_eq!(h.text("onboarding_progress_label"), "2 of 4");
        h.click("sync_start_fresh");
        // Signed in and offered Cloud: GitHub, which turns Cloud on.
        until_says(&mut h, "Turning on…");
        assert!(h.find("onboarding_github").is_some());
        assert_eq!(h.text("onboarding_progress_label"), "3 of 4");
        assert!(h.find("onboarding_skip_github").is_some());
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("cloud_status").is_none()
        }));
        h.frames(20);
        assert!(says(&mut h, "Not connected"));
        h.click("cloud_github_connect");
        assert!(appear(&mut h, "cloud_github_code_row"));
        assert_eq!(h.text("cloud_github_code"), "WDJB-MJHT");
        assert!(says(&mut h, "Waiting for you to approve on GitHub…"));
        snapshot(&h, "onboarding_github");
        h.click("cloud_github_open");
        assert!(appear(&mut h, "cloud_repos"));
        assert!(says(&mut h, "gaelcado"));
        assert!(h.find("onboarding_skip_github").is_none());
        h.click("onboarding_continue");

        // The agents on this Mac: Continue, since some are installed.
        assert!(appear(&mut h, "onboarding_providers"));
        assert_eq!(h.text("onboarding_progress_label"), "4 of 4");
        assert!(says(
            &mut h,
            "Found Claude Code, Codex and Cursor on this Mac. Sign in to any you'd like to use."
        ));
        assert!(h.find("provider_claude_row").is_some());
        h.click("onboarding_back");
        assert!(appear(&mut h, "onboarding_github"));
        h.click("onboarding_continue");
        assert!(appear(&mut h, "onboarding_providers"));
        h.click("onboarding_continue");

        // All set: what was chosen, then the first project.
        assert!(appear(&mut h, "onboarding_done"));
        assert!(says(&mut h, "You're all set"));
        assert!(says(&mut h, "Light · Green"));
        assert!(says(&mut h, "Signed in as gael@zeron.dev"));
        assert!(says(&mut h, "Connected"));
        assert!(says(&mut h, "Claude Code, Codex and Cursor"));
        assert!(h.find("onboarding_later").is_some());
        snapshot(&h, "onboarding_done");
        h.click("onboarding_add");
        h.frames(30);
        assert!(h.find("project_palette").is_some());
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding").is_none()
        }));
        h.click("project_device_mbp");
        h.frames(10);
        h.click("project_location_home");
        wait_for(&mut h, "project_folder_code");
        h.click("project_folder_code");
        wait_for(&mut h, "project_folder_rex");
        h.click("project_folder_rex");
        wait_for(&mut h, "project_folder_src");
        h.click("project_add");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("project_palette").is_none()
        }));
        h.frames(40);
        assert_eq!(h.text("new_project"), "rex", "the canvas in it");
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
    });
}

/// Setup's agents step waits for an agent: with none on this Mac it asks
/// for one (Continue inert, Skip for now), and an install lets it on; a
/// device with projects ends on Start using Zeron.
#[test]
fn onboarding_waits_for_an_agent_before_going_on() {
    deep(|| {
        let mut h = app();
        run_command(&mut h, "No agents on this Mac");
        run_command(&mut h, "First-run setup");
        assert!(appear(&mut h, "onboarding_welcome"));
        h.click("onboarding_start");
        assert!(appear(&mut h, "onboarding_appearance"));
        h.click("onboarding_continue");
        assert!(appear(&mut h, "onboarding_sync"));
        // Skipping sync skips GitHub: three steps.
        h.click("onboarding_skip_sync");
        assert!(appear(&mut h, "onboarding_providers"));
        assert_eq!(h.text("onboarding_progress_label"), "3 of 3");
        assert!(says(&mut h, "Install an agent"));
        h.click("onboarding_continue");
        h.frames(20);
        assert!(h.find("onboarding_providers").is_some(), "Continue waits");
        assert!(h.find("onboarding_skip_agents").is_some());
        h.click("provider_claude_install");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding_skip_agents").is_none()
        }));
        h.frames(20);
        assert!(says(&mut h, "Your agents"));
        h.click("onboarding_continue");
        assert!(appear(&mut h, "onboarding_done"));
        assert!(says(&mut h, "Only on this Mac"));
        assert!(h.find("onboarding_summary_github").is_none());
        assert!(h.find("onboarding_later").is_none());
        h.click("onboarding_finish");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding").is_none()
        }));
        healthy(&h);
    });
}

/// Signing out leads to Zeron's gates: "Log in to Zeron" over the grid;
/// logging in asks for a workspace; then the first project; then the app.
#[test]
fn signing_out_leads_through_the_gates_to_a_first_project() {
    deep(|| {
        let mut h = app();
        run_command(&mut h, "Sign out to onboarding");
        h.frames(40);
        healthy(&h);
        assert!(h.find("onboarding_signin").is_some(), "the sign-in card");
        snapshot(&h, "onboarding_gates");
        h.click("onboarding_login");
        let asked = h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding_workspace").is_some()
        });
        assert!(asked, "a workspace next");
        h.frames(40);
        h.type_text("onboarding_workspace_name", "Studio");
        h.key(Key::Enter);

        let project = h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding_project").is_some()
        });
        assert!(project, "then a first project");
        h.frames(40);
        // The add-project flow over it; a folder added ends it.
        h.click("onboarding_add_project");
        h.frames(30);
        assert!(h.find("onboarding").is_some() && h.find("project_palette").is_some());
        h.click("project_device_mbp");
        h.frames(10);
        h.click("project_location_home");
        wait_for(&mut h, "project_folder_code");
        h.click("project_folder_code");
        wait_for(&mut h, "project_folder_rex");
        h.click("project_folder_rex");
        wait_for(&mut h, "project_folder_src");
        h.click("project_add");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("onboarding").is_none()
        }));
        h.frames(40);
        assert_eq!(h.text("new_project"), "rex", "the canvas in it");
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
    });
}

/// Where a text starting with `prefix` shows, from the window's top.
fn text_y(h: &mut Harness, prefix: &str) -> Option<f32> {
    h.ui.prepare_frame();
    let scene = h.ui.scene.borrow();
    let mut stack = vec![scene.root()];
    while let Some(n) = stack.pop() {
        if let zgx::scene::NodeKind::Text { text, .. } = scene.kind(n)
            && text.starts_with(prefix)
        {
            return Some(scene.bounds(n).y);
        }
        stack.extend(scene.children(n).iter().rev());
    }
    None
}

#[test]
fn a_sent_prompt_glides_up_from_where_it_lands_without_a_flash() {
    deep(|| {
        let mut h = app();
        h.type_text("composer_input", "Glide check");
        h.click("composer_send");
        // From where it lands (under what was there) up to its rest, 10
        // under the band, and no further: never shown at the top first,
        // as following the stream's end would while the glide runs.
        let mut ys = vec![text_y(&mut h, "Glide check").expect("sent")];
        for _ in 0..240 {
            h.frame();
            ys.push(text_y(&mut h, "Glide check").unwrap());
        }
        let rest = *ys.last().unwrap();
        assert!(ys[0] > rest + 300., "it lands low: {ys:?}");
        assert!(
            ys.windows(2).all(|w| w[1] <= w[0] + 0.5),
            "it only rises: {ys:?}"
        );
        assert!(ys.iter().all(|y| *y >= rest - 0.5), "no overshoot: {ys:?}");
        let band = h.bounds("ztitle");
        assert!(
            (rest - (band.y + band.height + 10.)).abs() < 6.,
            "at rest under the band: {rest}"
        );
    });
}

/// What paints inside `area`: each box's fill alpha, for what shows there.
fn painted_in(h: &mut Harness, area: zgx::scene::Rect) -> Vec<u8> {
    h.ui.prepare_frame();
    let scene = h.ui.scene.borrow();
    let mut out = Vec::new();
    let mut stack = vec![scene.root()];
    while let Some(n) = stack.pop() {
        let b = scene.bounds(n);
        let inside = b.x >= area.x - 0.5
            && b.y >= area.y - 0.5
            && b.x + b.width <= area.x + area.width + 0.5
            && b.y + b.height <= area.y + area.height + 0.5;
        if inside
            && let zgx::scene::NodeKind::Panel { quad, .. } | zgx::scene::NodeKind::Quad(quad) =
                scene.kind(n)
            && quad.fill.3 > 0
        {
            out.push(quad.fill.3);
        }
        stack.extend(scene.children(n).iter().copied());
    }
    out
}

#[test]
fn the_dividers_line_and_a_panes_grabber_show_under_the_pointer_without_script() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        let (a, b) = (h.bounds("zt1_zt1_a"), h.bounds("zt1_zt1_b"));
        let gap = zgx::scene::Rect::new(a.x + a.width, a.y, b.x - (a.x + a.width), a.height);
        assert!(gap.width > 2., "a gap between the panes: {a:?} {b:?}");
        // At rest the gap shows nothing, nor the grabbers.
        assert!(painted_in(&mut h, gap).is_empty());
        assert_eq!(h.opacity("zt1_zt1_a_grip"), 0.);
        let calls = h.calls();
        // Over the pane: its grabber, and no other's.
        h.ui.dispatch(InputEvent::PointerMove {
            x: a.x + a.width / 2.,
            y: a.y + a.height / 2.,
        });
        h.frames(2);
        assert_eq!(h.opacity("zt1_zt1_a_grip"), 1.);
        assert_eq!(h.opacity("zt1_zt1_b_grip"), 0.);
        snapshot(&h, "grabber");
        // Over the gap: a slim line down its middle.
        h.ui.dispatch(InputEvent::PointerMove {
            x: gap.x + gap.width / 2.,
            y: gap.y + gap.height / 2.,
        });
        h.frames(2);
        assert_eq!(painted_in(&mut h, gap).len(), 1, "the line");
        snapshot(&h, "divider");
        assert_eq!(h.calls(), calls, "the pointer passing ran no script");
    });
}

/// The app with its sample voice session played `pace` times faster, in a
/// desktop window's place (its sounds asked for, none played).
fn voice_app_at(pace: f64) -> Harness {
    let h = Harness::with_desktop(move |runtime| {
        let host = ScriptHost::new(
            runtime,
            Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide/app_zeron.luau"),
        );
        host.action("inspect", |_| {});
        host.action("close_window", |_| {});
        host.action("open_app", |_| {});
        host.shared("voice_pace", pace);
        host
    });
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    // Its glyph says what the call does, to assistive technology.
    h.ui.set_assistive_technology(true);
    h.ui.prepare_frame();
    h.settle();
    h.frames(30);
    healthy(&h);
    h
}
/// The app with its sample voice session played ten times faster.
fn voice_app() -> Harness {
    voice_app_at(10.)
}

/// The app with a clipboard and a browser, as a desktop window gives it.
fn desktop_app() -> Harness {
    let h = Harness::with_desktop(|runtime| {
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
    h.frames(30);
    healthy(&h);
    h
}

/// What the glyph painted in `id` shows now: each of its dots' colour.
fn glyph_dots(h: &mut zgx_script::testing::TestApp, id: &str) -> Vec<zgx::scene::Color> {
    use zgx::canvas::{Brush, Draw};
    let node = h.find(id).unwrap_or_else(|| panic!("no `{id}`"));
    let scene = h.ui.scene.borrow();
    let mut pending = vec![node];
    while let Some(n) = pending.pop() {
        if let zgx::scene::NodeKind::Canvas(canvas) = scene.kind(n) {
            return canvas
                .commands()
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Fill {
                        brush: Brush::Solid(color),
                        ..
                    } => Some(*color),
                    _ => None,
                })
                .collect();
        }
        pending.extend(scene.children(n).iter().copied());
    }
    panic!("`{id}` paints no glyph")
}
/// The lit dots of `id`'s glyph: in Codex's sunrise inks, and in the
/// user's (the accent's).
fn lit_inks(h: &mut zgx_script::testing::TestApp, id: &str) -> (usize, usize) {
    const SUNRISE: [(u8, u8, u8); 3] = [(0xb6, 0xd3, 0xef), (0xed, 0xb1, 0x85), (0xf8, 0x88, 0xa0)];
    let lit: Vec<_> = glyph_dots(h, id)
        .into_iter()
        .filter(|c| c.3 > 150)
        .collect();
    let agent = lit
        .iter()
        .filter(|c| SUNRISE.contains(&(c.0, c.1, c.2)))
        .count();
    (agent, lit.len() - agent)
}

/// Waits (in real time, the sample's timers') until the stage's glyph
/// says `label` (its mode), then lets its passage play.
fn glyph_reads(h: &mut zgx_script::testing::TestApp, label: &str) {
    let target = format!("\"{label}\"");
    assert!(
        h.wait_until(|h| h.find(&target).is_some() && h.find(&target) == h.find("voice_orb")),
        "the glyph reads {label}"
    );
    h.frames(30);
    if let Some(e) = h.error() {
        panic!("script error: {e}");
    }
}

/// The voice stage (shell/voice_stage.rs, PR #916): the footer's voice
/// button places a call and opens the stage, its glyph in the composer's
/// disc reading each state of the sample call; every turn of the call is
/// kept under it, the user's in their bubble, centred in the band while
/// they fit; the call bar keeps time on the voice device. M mutes, Escape
/// steps aside with the call going on behind the footer's beam and the
/// tray over the conversation's composer, which come back to it; the bar's
/// way back opens the call's conversation, its words there as they are
/// said. The call sounds as it connects and as it ends. The glyph animates
/// in the engine: a call at rest runs no script but the clock's tick.
#[test]
fn the_voice_stage_plays_a_call_and_steps_aside() {
    deep(|| {
        let mut h = voice_app();
        assert!(h.find("voice_stage").is_none());
        h.click("side_voice");
        h.frames(1);
        // Connecting at once (the sample connects 160 ms later).
        assert!(
            h.find("voice_stage").is_some(),
            "the stage opens with the call"
        );
        assert!(h.find("\"Connecting…\"") == h.find("voice_orb"));
        assert_eq!(
            h.text("voice_bar_clock"),
            "–:––",
            "no time before it connects"
        );
        snapshot(&h, "voice_connecting");
        h.frames(40);
        assert!(h.shown("voice_stage"));
        // Frosted, the page under it fades out: only the window's frost shows.
        assert!(!h.shown("composer_input") && !h.shown("ztitle"));
        // Clear of the sidebar, which stays usable; the bar 28 from the
        // bottom, the orb (44 dots of 3 in its disc) 120 above the middle.
        let (stage, side) = (h.bounds("voice_stage"), h.bounds("side_footer"));
        assert!(stage.x >= side.x + side.width - 1., "{stage:?} {side:?}");
        let bar = h.bounds("voice_bar");
        assert!(
            (stage.y + stage.height - (bar.y + bar.height) - 28.).abs() < 0.5,
            "the bar 28 from the bottom: {bar:?} in {stage:?}"
        );
        assert!((bar.x + bar.width / 2. - (stage.x + stage.width / 2.)).abs() < 0.5);
        assert_eq!(bar.height, 50., "36 controls in 6 of padding and its edge");
        let orb = h.bounds("voice_stage_orb");
        assert_eq!((orb.width, orb.height), (175., 175.));
        assert!((orb.x + orb.width / 2. - (stage.x + stage.width / 2.)).abs() < 1.);
        let middle = stage.y + stage.height / 2.;
        assert!(
            (orb.y + orb.height / 2. - (middle - 120.)).abs() < 1.,
            "{orb:?} in {stage:?}"
        );
        assert!(h.find("voice_orb").is_some(), "the field in its disc");

        glyph_reads(&mut h, "Listening…");
        assert_eq!(h.text("voice_bar_clock"), "0:00");
        assert_eq!(h.text("voice_bar_host"), "MacBook Pro");
        assert!(
            h.desktop
                .as_ref()
                .unwrap()
                .played()
                .iter()
                .any(|p| p.ends_with("voice-start.wav")),
            "it sounds as it connects"
        );
        // The user's turn, in its bubble at the column's end.
        assert!(
            h.wait_until(|h| h.find("voice_turn_1").is_some()),
            "the user's turn shows once it is theirs"
        );
        glyph_reads(&mut h, "Working…");
        snapshot(&h, "voice_working");
        assert!(
            h.wait_until(|h| h.find("voice_turn_2").is_some()),
            "Codex's answer, named as it begins"
        );
        let (words, user, codex) = (
            h.bounds("voice_words"),
            h.bounds("voice_turn_1"),
            h.bounds("voice_turn_2"),
        );
        assert_eq!(words.width, 560., "the transcript's column");
        assert!(user.y < codex.y, "oldest first");
        snapshot(&h, "voice_speaking");
        // Codex asks: the glyph knocks, the way back is lit.
        glyph_reads(&mut h, "Waiting on you…");
        assert!(h.find("voice_bar_asking").is_some());
        assert!(h.find("\"Answer Codex in the conversation\"").is_some());
        snapshot(&h, "voice_asking");
        // Answered, the call listens again; every turn is kept, the newest
        // in view.
        assert!(h.wait_until(|h| h.find("voice_turn_6").is_some()));
        glyph_reads(&mut h, "Listening…");
        assert!(h.find("voice_bar_asking").is_none());
        for n in 1..=6 {
            assert!(
                h.find(&format!("voice_turn_{n}")).is_some(),
                "turn {n} kept"
            );
        }
        h.frames(30);
        let (band, newest) = (h.bounds("voice_transcript"), h.bounds("voice_turn_6"));
        assert!(
            newest.y + newest.height <= band.y + band.height + 0.5,
            "the newest in view: {newest:?} in {band:?}"
        );
        snapshot(&h, "voice_listening");

        // Codex's last word said, the sample is done and the call rests.
        assert!(h.wait_until(|h| h.find("voice_turn_6").is_some()));
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                lit_inks(h, "voice_orb").0 == 0
                    && h.texts()
                        .iter()
                        .any(|t| t.ends_with("as soon as the suite passes."))
            }),
            "Codex falls quiet"
        );
        // At rest the glyph moves in the engine: no script but the clock.
        let before = glyph_dots(&mut h, "voice_orb");
        let (calls, since) = (h.calls(), std::time::Instant::now());
        h.frames(90);
        let ticks = since.elapsed().as_secs() + 1;
        assert!(
            h.calls() - calls <= ticks,
            "{} script calls over 90 frames",
            h.calls() - calls
        );
        assert_ne!(before, glyph_dots(&mut h, "voice_orb"), "it breathes");

        // M mutes: the plate inverts and the glyph holds still.
        h.keys("m");
        h.frames(30);
        glyph_reads(&mut h, "Muted");
        assert!(h.find("#voice_bar >> \"Unmute microphone\"").is_some());
        snapshot(&h, "voice_muted");
        h.keys("m");
        glyph_reads(&mut h, "Listening…");

        // Escape steps aside; the call goes on behind the footer's beam and
        // the tray over the conversation's composer.
        h.key(Key::Escape);
        h.frames(40);
        assert!(h.find("voice_stage").is_none());
        assert!(h.shown("composer_input"), "the page is back");
        assert!(
            h.find("voice_footer_glyph").is_some(),
            "the footer shows the call"
        );
        assert!(h.find("\"Open voice\"").is_some() || h.find("side_voice").is_some());
        let (tray, composer) = (h.bounds("voice_tray"), h.bounds("composer"));
        assert!(
            tray.y < composer.y && tray.y + tray.height > composer.y,
            "tucked under the composer's top: {tray:?} over {composer:?}"
        );
        assert!(
            (tray.width - (composer.width - 52.)).abs() < 1.,
            "as wide as the composer's straight top: {tray:?} {composer:?}"
        );
        assert!(
            !glyph_dots(&mut h, "voice_tray_beam").is_empty(),
            "its beam"
        );
        snapshot(&h, "voice_tray");
        // Its mute is the call's.
        h.click("voice_tray_mic");
        h.frames(10);
        assert!(h.find("#voice_tray >> \"Unmute microphone\"").is_some());
        h.click("voice_tray_mic");
        h.frames(10);
        h.click("side_voice");
        h.frames(40);
        assert!(h.shown("voice_stage"), "back to the stage");
        assert!(h.find("\"Hide voice\"").is_some());

        // The way back: the call's conversation, its words, the tray there.
        h.click("voice_bar_back");
        h.frames(40);
        assert!(h.find("voice_stage").is_none());
        assert!(
            h.texts()
                .iter()
                .any(|t| t.contains("Is the release notes build green yet?")),
            "what was said"
        );
        assert!(h.find("voice_tray").is_some());
        h.click("voice_tray_open");
        h.frames(40);
        assert!(h.shown("voice_stage"));

        // Another session steps the stage aside too.
        h.key(Key::Escape);
        h.frames(10);
        h.click("side_voice");
        h.frames(40);
        h.click("agent_a1");
        h.frames(40);
        assert!(h.find("voice_stage").is_none(), "stepped aside");
        assert!(h.find("voice_tray").is_some(), "the call goes on");

        // End hangs up: the voice button again, nothing live, its sound.
        h.click("voice_tray_end");
        h.frames(40);
        assert!(h.find("voice_tray").is_none());
        assert!(h.find("voice_footer_glyph").is_none());
        assert!(h.find("\"Start voice\"").is_some());
        let played = h.desktop.as_ref().unwrap().played();
        assert!(played.last().is_some_and(|p| p.ends_with("voice-end.wav")));
        assert_eq!(played.len(), 2, "its two ends sound, nothing between");
        healthy(&h);
    });
}

/// The call's voices light its glyph in their own inks (the PR's): the
/// user's in the accent's, Codex's in the sunrise rows, on the stage's
/// field and the footer's beam alike. Played at its own pace, the voices
/// last long enough for the engine to hear them.
#[test]
fn a_call_s_voices_light_its_glyph_in_their_own_inks() {
    deep(|| {
        let mut h = voice_app_at(1.);
        h.click("side_voice");
        h.frames(10);
        assert!(
            h.wait_until(|h| {
                h.frames(2);
                let (agent, user) = lit_inks(h, "voice_orb");
                user > 10 && agent == 0
            }),
            "the user speaks in the accent"
        );
        assert!(
            h.wait_until(|h| {
                h.frames(2);
                let (agent, user) = lit_inks(h, "voice_orb");
                let (beam, _) = lit_inks(h, "voice_footer_glyph");
                agent > 10 && user == 0 && beam > 0
            }),
            "Codex in its sunrise, on the stage and the footer's beam"
        );
        healthy(&h);
    });
}

/// A call that cannot start (here, the USB microphone missing) closes its
/// stage and says why above the voice button, a warning dot on it; the
/// card stays through a click elsewhere until its ✕, then the button is
/// plain again.
#[test]
fn a_voice_call_that_cannot_start_explains_itself() {
    deep(|| {
        let mut h = voice_app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_voice");
        h.frames(20);
        h.click("settings_microphone");
        h.frames(20);
        h.click("settings_microphone_3");
        h.frames(20);
        cmd(&mut h, ",", false);
        h.click("side_voice");
        h.frames(1);
        assert!(h.find("voice_stage").is_some());
        assert!(h.wait_until(|h| h.find("side_voice_failed").is_some()));
        h.frames(40);
        assert!(h.find("voice_stage").is_none(), "the stage closes");
        let says = |h: &mut Harness| {
            h.texts()
                .iter()
                .any(|t| t == "Check microphone permission and your audio devices.")
        };
        assert!(says(&mut h), "it says why");
        snapshot(&h, "voice_failed");
        h.click("composer_input");
        h.frames(20);
        assert!(says(&mut h), "a click elsewhere leaves it");
        h.click("side_voice_dismiss");
        h.frames(20);
        assert!(h.find("side_voice_failed").is_none());
        assert!(!says(&mut h));
        assert!(h.find("\"Start voice\"").is_some());
        healthy(&h);
    });
}

/// Voice needs Codex on the device (VoiceController::offered): turned off
/// in Settings → Providers, the footer has no voice button; on again, it
/// comes back.
#[test]
fn the_voice_button_needs_codex_on_this_device() {
    deep(|| {
        let mut h = voice_app();
        assert!(h.find("side_voice").is_some());
        open_settings(&mut h, "harnesses");
        h.click("provider_codex_switch");
        h.frames(20);
        assert!(h.find("side_voice").is_none(), "no Codex, no voice");
        h.click("provider_codex_switch");
        h.frames(20);
        assert!(h.find("side_voice").is_some());
        healthy(&h);
    });
}

/// The call runs Codex on the voice device Settings → Voice chose: the
/// bar names it.
#[test]
fn a_call_runs_on_the_chosen_voice_device() {
    deep(|| {
        let mut h = voice_app();
        open_settings(&mut h, "voice");
        h.click("voice_host");
        h.frames(10);
        h.click("voice_host_3");
        h.frames(10);
        assert_eq!(h.text("voice_host"), "Build box");
        cmd(&mut h, ",", false);
        h.click("side_voice");
        h.frames(40);
        assert_eq!(h.text("voice_bar_host"), "Build box");
        h.click("voice_bar_end");
        h.frames(20);
        healthy(&h);
    });
}

/// Waits for `id` to show, as GitHub's answer arrives.
fn arrives(h: &mut Harness, id: &str) {
    assert!(
        h.wait_until(|h| h.find(id).is_some()),
        "`{id}` never showed"
    );
    h.frames(20);
    healthy(h);
}

fn meta(shift: bool) -> Modifiers {
    Modifiers {
        meta: true,
        shift,
        ..Default::default()
    }
}

fn open_settings(h: &mut Harness, section: &str) {
    if h.find("settings").is_none() {
        cmd(h, ",", false);
    }
    h.click(&format!("settings_nav_{section}"));
    h.frames(20);
    healthy(h);
}

fn shows(h: &mut zgx_script::testing::TestApp, what: &str) -> bool {
    h.texts().iter().any(|t| t.contains(what))
}

/// The board read, listing pull request `id`: Authored is the board's own
/// first choice, so another's shows under All; #398 is zeron/zgx's.
fn board_lists(h: &mut Harness, id: &str) {
    let row = format!("pr_{id}");
    assert!(
        h.wait_until(|h| h.find("prs_list").is_some() || h.find("prs_empty").is_some()),
        "the board never loaded"
    );
    h.frames(10);
    let repository = if id == "p4" { "zgx" } else { "comet" };
    if h.text("prs_repository_label") != format!("zeron/{repository}") {
        h.click("prs_repository");
        h.frames(20);
        h.click(&format!("prs_project_{repository}"));
        assert!(h.wait_until(|h| h.find("prs_list").is_some()));
        h.frames(10);
    }
    if h.find(&row).is_none() {
        h.click("prs_filter_all");
        arrives(h, &row);
    }
    on_board(h, &row);
}

/// The board is a virtual list: node `id` in it scrolled into its view.
fn on_board(h: &mut Harness, id: &str) {
    let (list, b) = (h.bounds("prs_list"), h.bounds(id));
    if b.y + b.height > list.y + list.height || b.y < list.y {
        h.ui.dispatch(InputEvent::Scroll {
            x: list.x + list.width / 2.,
            y: list.y + list.height / 2.,
            delta_x: 0.,
            delta_y: b.y + b.height / 2. - (list.y + list.height / 2.),
        });
        h.frames(10);
    }
}

/// The board, then pull request `id` beside it, read.
fn open_pr(h: &mut Harness, id: &str) {
    if h.find("prs_board").is_none() {
        h.click("nav_prs");
        h.frames(30);
    }
    board_lists(h, id);
    h.click(&format!("pr_{id}"));
    h.frames(30);
    healthy(h);
    arrives(h, "pr_overview");
}

/// Scrolls the pull request's page so `id` sits in its middle.
fn reveal(h: &mut Harness, id: &str) {
    let page = h.bounds("pr_detail_scroll");
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::Scroll {
        x: page.x + page.width / 2.,
        y: page.y + page.height / 2.,
        delta_x: 0.,
        delta_y: b.y + b.height / 2. - (page.y + page.height / 2.),
    });
    h.frames(10);
}

/// Field `id`'s text replaced by `text` (all of it selected first).
fn replace_text(h: &mut Harness, id: &str, text: &str) {
    h.click(id);
    h.key_with(
        Key::Character("a".into()),
        Modifiers {
            meta: true,
            ..Default::default()
        },
    );
    if text.is_empty() {
        h.key(Key::Backspace);
    } else {
        h.ui.dispatch(InputEvent::Text(text.into()));
    }
    h.settle();
}

/// The pointer over node `id` (what shows under it, shows).
fn hover(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::PointerMove {
        x: b.x + b.width / 2.,
        y: b.y + b.height / 2.,
    });
    h.frames(10);
}

fn opened(h: &Harness) -> Option<String> {
    h.desktop.as_ref().and_then(|d| d.opened().last().cloned())
}

#[test]
fn the_board_and_a_pull_request_stand_in_skeletons_until_they_load() {
    deep(|| {
        let mut h = app();
        h.click("nav_prs");
        h.frames(2);
        // The board's: a label's bar over six rows.
        assert!(h.find("prs_skeleton").is_some(), "the board loads");
        assert!(h.find("pr_p1").is_none());
        snapshot(&h, "prs_skeleton");
        arrives(&mut h, "pr_p1");
        assert!(h.find("prs_skeleton").is_none());
        // A pull request: its row's header over the Summary's skeleton.
        h.click("pr_p1");
        h.frames(2);
        assert!(h.find("pr_detail_skeleton").is_some());
        assert_eq!(
            h.text("pr_detail_title"),
            "Scroll fade on the transcript's bottom edge"
        );
        assert!(!shows(&mut h, "Loaded"), "not read yet");
        arrives(&mut h, "pr_overview");
        assert!(h.find("pr_detail_skeleton").is_none());
        assert!(shows(&mut h, "Loaded just now"));
        // Code: the diff and the tree stand in theirs until the patch comes.
        h.click("pr_nav_code");
        h.frames(2);
        assert!(h.find("pr_code_skeleton").is_some());
        assert_eq!(h.text("pr_code_position"), "Loading changes…");
        arrives(&mut h, "pr_code_stream");
        // Read once: opening it again shows it at once.
        h.click("pr_nav_summary");
        h.frames(20);
        board_lists(&mut h, "p2");
        h.click("pr_p2");
        h.frames(2);
        h.click("pr_p1");
        h.frames(2);
        assert!(h.find("pr_overview").is_some(), "kept");
        // Refresh reads it again with the page still up, the patch with it.
        h.click("pr_refresh");
        h.frames(2);
        assert!(h.find("pr_overview").is_some());
        assert_eq!(h.opacity("pr_refresh"), 0.4, "dim while it reads");
        assert!(h.wait_until(|h| h.opacity("pr_refresh") == 1.));
        // At rest, nothing runs.
        h.frames(30);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(h.calls(), calls, "idle runs no script");
    });
}

#[test]
fn a_pull_requests_summary_assesses_it_and_hands_it_to_an_agent() {
    deep(|| {
        let mut h = desktop_app();
        open_pr(&mut h, "p2");
        let desktop = h.desktop.clone().unwrap();
        // The overview and the assessment, as Zeron words them.
        assert!(shows(&mut h, "Changes requested"));
        assert!(shows(&mut h, "wing/dictation-accent-plate → main"));
        assert_eq!(h.text("pr_blockers"), "CI failing · Changes requested");
        assert_eq!(h.text("pr_next_action"), "Next: Fix failing checks");
        assert_eq!(h.text("pr_head_commit"), "Commit 51f122b");
        // The handoffs that apply, most useful first.
        for id in [
            "pr_handoff_checks",
            "pr_handoff_feedback",
            "pr_handoff_review",
        ] {
            assert!(h.find(id).is_some(), "{id}");
        }
        assert!(h.find("pr_handoff_conflicts").is_none());
        reveal(&mut h, "pr_checkout_command");
        assert_eq!(
            h.text("pr_checkout_command"),
            "gh pr checkout 409 --repo zeron/comet"
        );
        h.click("pr_copy_checkout");
        assert_eq!(desktop.clipboard(), "gh pr checkout 409 --repo zeron/comet");
        // The checks fold open; one with a link opens it.
        assert!(h.find("pr_check_1").is_none());
        h.click("pr_checks_toggle");
        h.frames(20);
        assert_eq!(h.text("pr_check_name_1"), "test (macos-latest)");
        assert!(shows(&mut h, "Failure"));
        h.click("pr_check_1");
        assert_eq!(
            opened(&h).as_deref(),
            Some("https://github.com/zeron/comet/actions/runs/2201/job/1")
        );
        // The description's media: GitHub's image loads where it is, a
        // missing one says so (a click opens it in the browser), and the
        // shown one opens in the viewer.
        arrives(&mut h, "pr_image_pr_body_1_shown");
        arrives(&mut h, "pr_image_pr_body_2_error");
        reveal(&mut h, "pr_image_pr_body_2");
        assert!(shows(&mut h, "Couldn’t load image. Open in browser ↗"));
        h.click("pr_image_pr_body_2");
        assert_eq!(
            opened(&h).as_deref(),
            Some("https://github.com/user-attachments/assets/91aa-missing")
        );
        // Its full size loads over the page first, then the viewer shows it.
        reveal(&mut h, "pr_image_pr_body_1");
        h.click("pr_image_pr_body_1");
        h.frames(2);
        assert_eq!(
            h.text("pr_image_loading_label"),
            "Loading image… · Escape to cancel"
        );
        arrives(&mut h, "image_viewer_image");
        assert!(h.find("pr_image_loading").is_none());
        h.key(Key::Escape);
        h.frames(30);
        snapshot(&h, "pr_summary");
        // The link, copied, and in the browser.
        h.click("pr_copy_link");
        assert_eq!(
            desktop.clipboard(),
            "https://github.com/zeron/comet/pull/409"
        );
        h.click("pr_external");
        assert_eq!(
            opened(&h).as_deref(),
            Some("https://github.com/zeron/comet/pull/409")
        );
        // A handoff: on macOS, finding a checkout, then a new session in
        // the project with the prompt staged, not sent.
        reveal(&mut h, "pr_handoff");
        h.click("pr_platform_macos");
        h.frames(10);
        h.click("pr_handoff_review");
        h.frames(2);
        assert!(h.find("pr_handoff_finding").is_some());
        assert!(shows(&mut h, "Finding a checkout…"));
        arrives(&mut h, "new_composer");
        let prompt = h.text("new_composer_input");
        assert!(
            prompt.starts_with(
                "Pull request #409 in zeron/comet: Dictation: the stop plate on the accent glass"
            ),
            "{prompt}"
        );
        assert!(prompt.contains("Requested verification platform: macOS."));
        assert!(prompt.contains("Blocker: CI failing."));
        assert!(prompt.contains("`gh pr diff 409 --repo zeron/comet`"));
        assert_eq!(h.text("new_project"), "comet");

        // Without a checkout on this device: why, and adding its project.
        cmd(&mut h, "[", false);
        open_pr(&mut h, "p4");
        assert_eq!(h.text("pr_blockers"), "Merge conflicts");
        assert!(shows(&mut h, "Some check details are unavailable"));
        reveal(&mut h, "pr_handoff");
        h.click("pr_handoff_conflicts");
        arrives(&mut h, "pr_handoff_error");
        assert!(shows(
            &mut h,
            "No checkout of zeron/zgx is available on this device. Add its project, then try again."
        ));
        h.click("pr_add_checkout");
        h.frames(10);
        assert!(h.find("pr_handoff_error").is_none());
        // A draft with nothing to hand off: an incomplete assessment, no
        // actions, no description.
        open_pr(&mut h, "p3");
        assert_eq!(h.text("pr_blockers"), "Assessment incomplete");
        assert_eq!(h.text("pr_next_action"), "Next: Refresh metadata");
        assert!(shows(&mut h, "No description provided."));
        assert!(h.find("pr_handoff_review").is_none());
    });
}

#[test]
fn a_pull_requests_code_steps_through_its_files_in_one_stream() {
    deep(|| {
        let mut h = desktop_app();
        open_pr(&mut h, "p1");
        h.click("pr_nav_code");
        arrives(&mut h, "pr_code_stream");
        let desktop = h.desktop.clone().unwrap();
        // The navigation's thumb lies under the chosen section.
        let (thumb, code) = (h.bounds("pr_nav_thumb"), h.bounds("pr_nav_code"));
        assert!((thumb.x - code.x).abs() < 2., "{thumb:?} {code:?}");
        assert_eq!(h.text("pr_code_position"), "File 1 of 6");
        assert_eq!(
            h.opacity("pr_code_previous"),
            0.4,
            "nothing before the first"
        );
        h.click("pr_code_next");
        h.frames(10);
        assert_eq!(h.text("pr_code_position"), "File 2 of 6");
        // Narrow, the tree is a picker under the toolbar.
        assert!(h.find("pr_code_tree").is_none());
        h.click("pr_code_files");
        h.frames(20);
        assert!(h.find("pr_code_picker").is_some());
        snapshot(&h, "pr_code_picker");
        h.click("pr_code_tree_5");
        h.frames(20);
        assert!(h.find("pr_code_picker").is_none(), "a pick closes it");
        assert_eq!(h.text("pr_code_position"), "File 5 of 6");
        // Every file folds to its header.
        h.click("pr_code_fold_all");
        h.frames(20);
        for i in 1..=6 {
            assert!(h.find(&format!("pr_code_file_{i}")).is_some(), "header {i}");
        }
        assert!(!shows(&mut h, "Renamed from"));
        h.click("pr_code_fold_all");
        h.frames(20);
        // Split, and the patch copied whole.
        h.click("pr_code_split");
        h.frames(20);
        snapshot(&h, "pr_code_split");
        h.click("pr_code_copy");
        assert!(
            desktop
                .clipboard()
                .starts_with("diff --git a/crates/ui/src/edge_fade.rs")
        );
        // A diff that fails to load says why and tries again.
        open_pr(&mut h, "p4");
        h.click("pr_nav_code");
        arrives(&mut h, "pr_diff_error");
        assert!(shows(&mut h, "Couldn’t load the diff."));
        h.click("pr_retry_diff");
        arrives(&mut h, "pr_code_stream");
        assert!(h.find("pr_diff_error").is_none());
        assert_eq!(h.text("pr_code_position"), "File 1 of 2");
    });
}

#[test]
fn a_pull_requests_activity_reads_its_threads_and_posts_a_comment() {
    deep(|| {
        let mut h = desktop_app();
        open_pr(&mut h, "p2");
        h.click("pr_nav_activity");
        h.frames(30);
        healthy(&h);
        // The viewer's own messages sit on the right in a bubble.
        let thread = h.bounds("pr_activity_thread");
        let own = h.bounds("pr_message_1");
        let theirs = h.bounds("pr_message_4");
        assert!(
            (own.x + own.width - (thread.x + thread.width)).abs() < 1.,
            "own: {own:?} in {thread:?}"
        );
        // Authors line up with the title above, 8 in.
        assert!(
            (theirs.x - (thread.x + 8.)).abs() < 1.,
            "theirs: {theirs:?}"
        );
        // Inline comments: where they sit (a link to GitHub) and their state.
        assert_eq!(
            h.text("pr_inline_location_2"),
            "crates/ui/src/dictation/stop_plate.rs:41"
        );
        assert!(shows(&mut h, "Unresolved · Outdated"));
        h.click("pr_inline_location_2");
        assert_eq!(
            opened(&h).as_deref(),
            Some("https://github.com/zeron/comet/pull/409#discussion_r201")
        );
        snapshot(&h, "pr_activity");
        // @ mentions the people here; Enter takes one, Enter again posts.
        h.type_text("pr_comment_input", "Thanks @w");
        h.frames(20);
        assert!(h.find("pr_mention_ref_wing").is_some());
        h.key(Key::Enter);
        h.frames(10);
        assert_eq!(h.text("pr_comment_input"), "Thanks @wing ");
        h.type_text("pr_comment_input", "that settles it");
        h.key(Key::Enter);
        h.frames(2);
        assert!(h.find("pr_comment_pending").is_some());
        assert!(shows(&mut h, "Posting comment"));
        arrives(&mut h, "pr_message_5");
        assert!(h.find("pr_comment_pending").is_none());
        assert!(shows(&mut h, "Thanks @wing that settles it"));
        // A post that cannot be confirmed keeps its draft and says why.
        open_pr(&mut h, "p4");
        h.click("pr_nav_activity");
        h.frames(20);
        assert!(h.find("pr_threads_unavailable").is_some());
        h.type_text("pr_comment_input", "Rebased.");
        h.key(Key::Enter);
        arrives(&mut h, "pr_comment_error");
        assert!(shows(&mut h, "Your draft is kept"));
        // Nothing yet: the empty state over the composer.
        open_pr(&mut h, "p3");
        h.click("pr_nav_activity");
        h.frames(20);
        assert!(h.find("pr_activity_empty").is_some());
        assert!(shows(&mut h, "No activity yet"));
    });
}

/// The board's rows and group headers shown, top to bottom.
fn board_rows(h: &mut Harness) -> Vec<String> {
    let mut shown: Vec<(f32, String)> = Vec::new();
    let ids = ["p1", "p2", "p3", "p4", "p5", "p6"]
        .iter()
        .map(|id| format!("pr_{id}"))
        .chain(
            ["attention", "review", "approved", "drafts"]
                .iter()
                .map(|g| format!("prs_group_{g}")),
        );
    for id in ids {
        if h.find(&id).is_some() {
            shown.push((h.bounds(&id).y, id));
        }
    }
    shown.sort_by(|a, b| a.0.total_cmp(&b.0));
    shown.into_iter().map(|(_, id)| id).collect()
}

/// The board (pull_requests.rs): one repository's open pull requests, the
/// viewer's own first (Authored, falling back to All when empty), in
/// Zeron's groups; All, the search and its count, the sort, Needs you
/// and Starred, a group folding shut, and "Load more" bringing GitHub's
/// next page.
#[test]
fn the_board_groups_a_repositorys_pull_requests_and_filters_them() {
    deep(|| {
        let mut h = app();
        h.click("nav_prs");
        h.frames(2);
        assert!(h.find("prs_skeleton").is_some());
        assert_eq!(h.text("prs_title"), "Pull requests");
        assert!(h.find("prs_count").is_none(), "no count while it reads");
        arrives(&mut h, "prs_list");
        // Authored: the viewer's, approved first, drafts last.
        assert_eq!(h.text("prs_count"), "3");
        assert_eq!(h.text("prs_repository_label"), "zeron/comet");
        assert_eq!(
            board_rows(&mut h),
            [
                "prs_group_approved",
                "pr_p1",
                "pr_p6",
                "prs_group_drafts",
                "pr_p3"
            ]
        );
        assert!(shows(&mut h, "Approved") && shows(&mut h, "Drafts"));
        snapshot(&h, "prs_board");
        // All: someone else's, a page at a time.
        h.click("prs_filter_all");
        h.frames(2);
        arrives(&mut h, "pr_p2");
        assert_eq!(h.text("prs_count"), "5");
        assert_eq!(
            board_rows(&mut h),
            [
                "prs_group_attention",
                "pr_p2",
                "prs_group_review",
                "pr_p5",
                "prs_group_approved",
                "pr_p1",
                "prs_group_drafts",
                "pr_p3"
            ]
        );
        assert_eq!(h.text("prs_load_more_label"), "Load 1 more");
        h.click("prs_load_more");
        h.frames(2);
        assert_eq!(h.text("prs_load_more_label"), "Loading more…");
        arrives(&mut h, "pr_p6");
        assert!(h.find("prs_load_more").is_none(), "nothing more to read");
        // A group folds shut and open again.
        h.click("prs_group_approved");
        h.frames(10);
        assert!(h.find("pr_p1").is_none() && h.find("pr_p6").is_none());
        h.click("prs_group_approved");
        h.frames(10);
        assert!(h.find("pr_p1").is_some());
        // The search: every word, in the title, repository, number, status.
        h.type_text("prs_search", "stop plate");
        h.frames(10);
        assert_eq!(board_rows(&mut h), ["prs_group_attention", "pr_p2"]);
        assert_eq!(h.text("prs_matches"), "1 of 5 pull requests");
        h.type_text("prs_search", " nowhere");
        h.frames(10);
        assert!(says(&mut h, "No matching pull requests"));
        h.click("prs_empty_clear_search");
        h.frames(10);
        assert!(h.find("prs_matches").is_none());
        assert!(h.find("pr_p5").is_some());
        // The sort: the oldest opened first, its rows saying when.
        h.click("prs_sort");
        h.frames(20);
        h.click("prs_sort_opened_asc");
        h.frames(20);
        let rows = board_rows(&mut h);
        let at = |id: &str| rows.iter().position(|r| r == id).unwrap();
        assert!(at("pr_p6") < at("pr_p1"), "{rows:?}");
        assert!(shows(&mut h, "Opened 3d ago"), "p1's");
        // Needs you: what asks for the viewer; Starred: the starred.
        h.click("pr_p1_star");
        h.click("prs_view_needs_you");
        h.frames(10);
        assert_eq!(board_rows(&mut h), ["prs_group_attention", "pr_p2"]);
        h.click("prs_view_starred");
        h.frames(10);
        assert_eq!(
            board_rows(&mut h),
            [
                "prs_group_attention",
                "pr_p2",
                "prs_group_approved",
                "pr_p1"
            ]
        );
        h.click("prs_view_starred");
        h.frames(10);
        assert!(h.find("pr_p5").is_some(), "everything again");
        // At rest, nothing runs.
        h.frames(30);
        let calls = h.calls();
        h.frames(60);
        assert_eq!(h.calls(), calls, "idle runs no script");
    });
}

/// The board's repository and device (pull_requests.rs): a project's
/// repository, or one typed; what a repository with none, one GitHub
/// refuses, and an offline device say, with Try again; a refresh that
/// fails keeping what showed, and saying so.
#[test]
fn the_board_reads_another_repository_or_device_and_says_what_failed() {
    deep(|| {
        let mut h = app();
        h.click("nav_prs");
        arrives(&mut h, "prs_list");
        // Another project's: nothing of the viewer's there, so All.
        h.click("prs_repository");
        h.frames(20);
        assert!(h.find("prs_project_comet").is_some());
        h.click("prs_project_zgx");
        arrives(&mut h, "pr_p4");
        assert_eq!(h.text("prs_repository_label"), "zeron/zgx");
        assert_eq!(board_rows(&mut h), ["prs_group_attention", "pr_p4"]);
        // A refresh that fails keeps the rows and says so once.
        h.click("prs_refresh");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "Showing the last loaded results.")
        }));
        assert!(h.find("pr_p4").is_some());
        // A repository typed: empty, GitHub's sign-in refused.
        let open = |h: &mut Harness, repo: &str| {
            h.click("prs_repository");
            h.frames(20);
            replace_text(h, "prs_repository_input", repo);
            h.key(Key::Enter);
            h.frames(2);
        };
        open(&mut h, "zeron/website");
        arrives(&mut h, "prs_empty");
        assert_eq!(h.text("prs_empty_title"), "No open pull requests");
        assert!(
            h.find("prs_recent_zeron_website").is_none(),
            "the menu closed"
        );
        open(&mut h, "zeron/private");
        arrives(&mut h, "prs_retry");
        assert_eq!(
            h.text("prs_empty_title"),
            "Sign in to GitHub on this device"
        );
        assert_eq!(
            h.text("prs_empty_description"),
            "Run gh auth login, then refresh this page."
        );
        // The repositories opened here come back in the menu.
        h.click("prs_repository");
        h.frames(20);
        assert!(h.find("prs_recent_zeron_website").is_some());
        h.click("prs_project_comet");
        arrives(&mut h, "pr_p1");
        // An offline device: why, and Try again.
        h.click("prs_device");
        h.frames(20);
        assert_eq!(h.text("prs_device_1"), "MacBook Pro");
        assert!(shows(&mut h, "This device") && shows(&mut h, "Offline"));
        h.click("prs_device_3");
        arrives(&mut h, "prs_retry");
        assert_eq!(h.text("prs_empty_title"), "Cloud is offline");
        h.click("prs_device");
        h.frames(20);
        h.click("prs_device_1");
        arrives(&mut h, "pr_p1");
        healthy(&h);
    });
}

/// A pull request whose read fails says why over its page, and Try again
/// reads it (pull_request_detail.rs error_strip, pr-retry).
#[test]
fn a_pull_request_that_fails_to_read_says_why_and_tries_again() {
    deep(|| {
        let mut h = app();
        open_pr(&mut h, "p2");
        // #391, on the board's second page.
        board_lists(&mut h, "p5");
        on_board(&mut h, "prs_load_more");
        h.click("prs_load_more");
        arrives(&mut h, "pr_p6");
        board_lists(&mut h, "p6");
        h.click("pr_p6");
        arrives(&mut h, "pr_read_error");
        assert!(shows(
            &mut h,
            "Couldn’t load this pull request. GitHub didn’t respond in time. Try again."
        ));
        assert!(h.find("pr_overview").is_none());
        h.click("pr_retry");
        arrives(&mut h, "pr_overview");
        assert!(h.find("pr_read_error").is_none());
    });
}

/// Each pull request's page keeps its own section and scroll as its tab
/// comes back, and each one opened is a place Back returns to; the
/// navigation's labels light as the thumb covers them, in the engine.
#[test]
fn pull_requests_keep_their_own_page_and_history_steps_through_them() {
    deep(|| {
        let mut h = app();
        open_pr(&mut h, "p1");
        let lit = |h: &mut Harness, tab: &str| {
            h.opacity(&format!("pr_nav_{tab}_cover")) * h.opacity(&format!("pr_nav_{tab}_lit"))
        };
        assert_eq!(lit(&mut h, "summary"), 1.);
        assert_eq!(lit(&mut h, "activity"), 0.);
        // Summary to Activity: Code, between them, lights as the thumb
        // passes and dims again; no script runs as it glides.
        let calls = h.calls();
        h.click("pr_nav_activity");
        let after_click = h.calls();
        h.frames(5);
        assert!(lit(&mut h, "code") > 0., "covered on the way");
        h.frames(40);
        assert_eq!(h.calls(), after_click, "the glide runs in the engine");
        assert!(after_click > calls);
        assert_eq!(lit(&mut h, "code"), 0.);
        assert_eq!(lit(&mut h, "activity"), 1.);
        assert!(h.find("pr_activity_thread").is_some());
        // Another pull request opens on its Summary; p1's comes back on
        // its Activity.
        open_pr(&mut h, "p3");
        assert!(h.find("pr_overview").is_some());
        h.click("zp_prs_tab_p1");
        h.frames(30);
        assert!(h.find("pr_activity_thread").is_some(), "its own section");
        h.click("pr_nav_summary");
        h.frames(30);
        // Its Summary scrolled, kept across another's.
        let page = h.bounds("pr_detail_scroll");
        h.ui.dispatch(InputEvent::Scroll {
            x: page.x + page.width / 2.,
            y: page.y + page.height / 2.,
            delta_x: 0.,
            delta_y: 300.,
        });
        h.frames(10);
        let title = h.bounds("pr_detail_title").y;
        assert!(title < page.y, "scrolled: {title}");
        h.click("zp_prs_tab_p3");
        h.frames(30);
        h.click("zp_prs_tab_p1");
        h.frames(30);
        assert!(
            (h.bounds("pr_detail_title").y - title).abs() < 1.,
            "where it was"
        );
        // Its Code too.
        h.click("pr_nav_code");
        arrives(&mut h, "pr_code_stream");
        let stream = h.bounds("pr_code_stream");
        h.ui.dispatch(InputEvent::Scroll {
            x: stream.x + stream.width / 2.,
            y: stream.y + stream.height / 2.,
            delta_x: 0.,
            delta_y: 700.,
        });
        h.frames(10);
        let at = h.text("pr_code_position");
        assert_ne!(at, "File 1 of 6", "scrolled");
        h.click("zp_prs_tab_p3");
        h.frames(30);
        h.click("zp_prs_tab_p1");
        arrives(&mut h, "pr_code_stream");
        assert_eq!(h.text("pr_code_position"), at, "where it was");
        h.click("pr_nav_summary");
        h.frames(30);
        // Back: p3, then p1, then p3 again… each opening was a place.
        cmd(&mut h, "[", false);
        h.frames(30);
        assert_eq!(h.text("pr_detail_title"), "WIP: queue tray drag");
        cmd(&mut h, "[", false);
        h.frames(30);
        assert_eq!(
            h.text("pr_detail_title"),
            "Scroll fade on the transcript's bottom edge"
        );
        cmd(&mut h, "[", false);
        h.frames(30);
        assert_eq!(h.text("pr_detail_title"), "WIP: queue tray drag");
        cmd(&mut h, "]", false);
        h.frames(30);
        assert_eq!(
            h.text("pr_detail_title"),
            "Scroll fade on the transcript's bottom edge"
        );
        healthy(&h);
    });
}

/// A pull request's code scrolls sideways as one, its numbers staying,
/// each file's lines in its syntax's colours (pull_request_code.rs); its
/// reading area's text copies with ⌘C; a full image that fails to load
/// says so and opens in the browser.
#[test]
fn a_pull_requests_code_scrolls_sideways_and_its_text_copies() {
    deep(|| {
        let mut h = desktop_app();
        open_pr(&mut h, "p1");
        // The reading area's text selects (what ⌘C copies, the window's),
        // and a press there leaves no field holding ⌘C for itself.
        h.click("pr_nav_activity");
        h.frames(30);
        h.click("pr_comment_input");
        assert!(h.ui.focused_editor().is_some());
        let title = h.bounds("pr_detail_title");
        let (y, x) = (title.y + title.height / 2., title.x + 2.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerMove { x: x + 30., y });
        h.ui.dispatch(InputEvent::PointerMove { x: x + 60., y });
        h.ui.dispatch(InputEvent::PointerUp {
            x: x + 60.,
            y,
            button,
        });
        h.frames(5);
        let selected = h.ui.selected_text();
        assert!(
            !selected.is_empty()
                && "Scroll fade on the transcript's bottom edge".contains(&selected),
            "{selected:?}"
        );
        assert!(h.ui.focused_editor().is_none(), "⌘C reaches the selection");
        h.click("pr_nav_summary");
        h.frames(30);
        // A full image that fails: why, and a press opens it in the browser.
        reveal(&mut h, "pr_image_pr_body_2");
        arrives(&mut h, "pr_image_pr_body_2_shown");
        h.click("pr_image_pr_body_2");
        h.frames(2);
        assert_eq!(
            h.text("pr_image_loading_label"),
            "Loading image… · Escape to cancel"
        );
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("pr_image_loading_label")
                .starts_with("Couldn’t load image.")
        }));
        h.click("pr_image_loading");
        assert_eq!(
            opened(&h).as_deref(),
            Some("https://github.com/user-attachments/assets/4be0a113-after")
        );
        assert!(h.find("pr_image_loading").is_none());
        // The code: every line on one sideways scroll.
        h.click("pr_nav_code");
        arrives(&mut h, "pr_code_stream");
        // Where each coloured line's text starts (the code's rich texts).
        let starts = |h: &mut Harness| -> Vec<zgx::scene::Rect> {
            let root = h.find("pr_code_stream").unwrap();
            let scene = h.ui.scene.borrow();
            let mut out = Vec::new();
            let mut stack = vec![root];
            while let Some(n) = stack.pop() {
                if matches!(scene.kind(n), zgx::scene::NodeKind::RichText { .. }) {
                    out.push(scene.transformed_bounds(n));
                }
                stack.extend(scene.children(n).iter().copied());
            }
            out.sort_by(|a, b| a.y.total_cmp(&b.y));
            out
        };
        let before = starts(&mut h);
        assert!(before.len() > 5, "the lines in syntax colours: {before:?}");
        assert!(before.iter().all(|b| (b.x - before[0].x).abs() < 0.5));
        let line = before[before.len() / 2];
        h.ui.dispatch(InputEvent::PointerMove {
            x: line.x + 60.,
            y: line.y + line.height / 2.,
        });
        h.ui.dispatch(InputEvent::Scroll {
            x: line.x + 60.,
            y: line.y + line.height / 2.,
            delta_x: 40.,
            delta_y: 0.,
        });
        h.frames(10);
        let after = starts(&mut h);
        assert!(
            after.iter().all(|a| (before[0].x - a.x - 40.).abs() < 0.5),
            "every line moved 40 together: {before:?} {after:?}"
        );
        healthy(&h);
    });
}

/// A press at window point `(x, y)`, as a click there.
fn press_at(h: &mut Harness, x: f32, y: f32) {
    let button = zgx::input::PointerButton::Primary;
    h.ui.dispatch(InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(InputEvent::PointerUp { x, y, button });
    h.frames(30);
    healthy(h);
}

/// The session card (session_info.rs) beside the transcript where the
/// column has room for both: shown until hidden, the reading column and the
/// composer moving left just enough to clear it; over a tighter column it
/// hides, and opening it floats it, a press elsewhere dismissing it.
#[test]
fn the_session_card_docks_beside_the_transcript_where_it_fits() {
    deep(|| {
        let mut h = app();
        // 1024 beside the sidebar: too tight, so it waits for the toggle.
        assert!(h.find("z_session_card").is_none());
        let centred = h.bounds("composer");
        // Without the sidebar the column has its 1092 and more: it shows.
        cmd(&mut h, "b", false);
        h.frames(40);
        let card = h.bounds("z_session_card");
        let column = h.bounds("conversation");
        assert_eq!(card.width, 272.);
        assert!((column.x + column.width - (card.x + card.width) - 12.).abs() < 0.5);
        let composer = h.bounds("composer");
        assert!(
            composer.x + composer.width <= card.x - 24. + 0.5,
            "the composer clears it by the gap: {composer:?} {card:?}"
        );
        assert_eq!(composer.width, 736., "at its full width");
        assert_eq!(
            h.text("ztitle_card_count"),
            "2",
            "a side chat and a subagent run"
        );
        snapshot(&h, "session_card_docked");
        // Hidden, it stays hidden, and the column centres again.
        h.click("ztitle_card");
        h.frames(40);
        assert!(h.find("z_session_card").is_none());
        let composer = h.bounds("composer");
        let column = h.bounds("conversation");
        assert!(
            (composer.x + composer.width / 2. - (column.x + column.width / 2.)).abs() < 1.,
            "centred: {composer:?} {column:?}"
        );
        h.click("ztitle_card");
        h.frames(40);
        assert!(h.find("z_session_card").is_some());
        // The sidebar back: no room, so it hides; the toggle floats it.
        cmd(&mut h, "b", false);
        h.frames(40);
        assert!(h.find("z_session_card").is_none());
        assert_eq!(h.bounds("composer").x, centred.x, "the composer centred");
        h.click("ztitle_card");
        h.frames(30);
        assert!(h.find("z_session_card").is_some(), "over the transcript");
        // A press on it keeps it; elsewhere, it goes (and the press goes on).
        let device = h.bounds("z_device");
        press_at(&mut h, device.x + 100., device.y + 16.);
        assert!(h.find("z_session_card").is_some());
        let column = h.bounds("conversation");
        press_at(&mut h, column.x + 100., column.y + 300.);
        assert!(h.find("z_session_card").is_none(), "dismissed");
        // The toggle opens it and closes it again.
        h.click("ztitle_card");
        h.frames(30);
        assert!(h.find("z_session_card").is_some());
        h.click("ztitle_card");
        h.frames(30);
        assert!(h.find("z_session_card").is_none());
    });
}

/// The lanes card lists the chat's side chats (session_lanes.rs), most
/// recent first; it forks the chat into a side chat in the pane, starts a
/// fresh one that lists only once its first message mints it, and opens a
/// row's chat in its tab.
#[test]
fn the_lanes_card_lists_forks_and_starts_side_chats() {
    deep(|| {
        let mut h = app();
        h.click("ztitle_card");
        h.frames(30);
        let (s2, s1) = (h.bounds("z_lane_side_s2"), h.bounds("z_lane_side_s1"));
        assert!(s2.y < s1.y, "the most recent first");
        assert!(h.find("z_fork").is_some() && h.find("z_side_chat_new").is_some());
        assert!(
            h.find("z_fork_row").is_none(),
            "the starters fold onto the heading"
        );
        assert!(h.find("z_subagent_sa1").is_some(), "a running subagent");
        assert!(h.find("z_subagent_sa2").is_none(), "the settled fold away");
        h.click("z_lanes_finished");
        h.frames(20);
        assert!(h.find("z_subagent_sa2").is_some());
        snapshot(&h, "session_card_floating");
        // A row opens its chat in the pane, which the card leaves for.
        h.click("z_lane_side_s1");
        h.frames(40);
        assert!(h.find("z_session_card").is_none(), "chosen, it goes");
        assert!(h.bounds("zcols_right").width > 300.);
        let tab = h.find("zp_tab_side_1").map(|_| h.text("zp_tab_side_1"));
        assert_eq!(tab.as_deref(), Some("Check the release links"));
        assert!(joined(&mut h, "side_1_fork").contains("Write the release notes"));
        // Forking: a new tab on the fork, listed first.
        h.click("ztitle_card");
        h.frames(30);
        h.click("z_fork");
        h.frames(40);
        assert!(h.find("side_2_fork").is_some(), "where it forked");
        h.click("ztitle_card");
        h.frames(30);
        let (fork, s2) = (h.bounds("z_lane_side_n1"), h.bounds("z_lane_side_s2"));
        assert!(fork.y < s2.y, "{fork:?} {s2:?}");
        h.click("ztitle_card");
        h.frames(30);
        // A chat with none offers the two starters as rows.
        h.click("agent_a2");
        h.frames(40);
        h.click("ztitle_card");
        h.frames(30);
        assert!(h.find("z_fork_row").is_some() && h.find("z_side_chat").is_some());
        h.click("z_side_chat");
        h.frames(40);
        let tab = h.text("zp_tab_side_3");
        assert_eq!(tab, "Side chat");
        assert!(h.find("side_3_fork").is_none(), "a fresh one forks nothing");
        h.click("ztitle_card");
        h.frames(30);
        assert!(h.find("z_lane_side_n2").is_none(), "unsaved: not listed");
        h.click("ztitle_card");
        h.frames(30);
        h.type_text("side_3_composer_input", "Sketch the gap fix");
        h.key(Key::Enter);
        h.frames(30);
        assert_eq!(h.text("zp_tab_side_3"), "Sketch the gap fix");
        h.click("ztitle_card");
        h.frames(30);
        assert_eq!(h.text("z_lane_side_n2_title"), "Sketch the gap fix");
    });
}

/// The project's actions on the session card (project_actions.rs): a row
/// runs its action in a terminal named for it; the gear edits it; zeron.json
/// imports and Add action open the editor, which checks what it saves; a
/// deletion asks first.
#[test]
fn project_actions_run_and_edit_from_the_session_card() {
    deep(|| {
        let mut h = app();
        let open = |h: &mut Harness| {
            if h.find("z_session_card").is_none() {
                h.click("ztitle_card");
                h.frames(30);
            }
        };
        open(&mut h);
        assert!(
            h.find("ztitle_actions").is_none(),
            "no split button in the header"
        );
        assert_eq!(h.text("z_action_install"), "Install (setup)");
        h.click("z_action_dev");
        h.frames(40);
        assert!(
            h.find("z_session_card").is_none(),
            "running it, the card goes"
        );
        assert!(
            h.texts().iter().any(|t| t == "Run dev"),
            "a terminal tab named for it"
        );
        // The gear edits it; an empty name is refused, as Zeron says.
        open(&mut h);
        hover(&mut h, "z_action_dev");
        h.click("z_edit_action_dev");
        h.frames(30);
        assert_eq!(h.text("action_name"), "Run dev");
        assert_eq!(h.text("action_command"), "cargo run -p zeron");
        replace_text(&mut h, "action_name", "");
        h.click("action_save");
        h.frames(20);
        assert_eq!(h.text("action_error"), "Action name is required");
        replace_text(&mut h, "action_name", "Serve");
        h.click("action_icon_debug");
        h.click("action_save");
        h.frames(30);
        assert!(h.find("action_editor").is_none());
        open(&mut h);
        assert_eq!(h.text("z_action_dev"), "Serve");
        // An import fills the editor; saved, it leaves the offers.
        h.click("z_import_1");
        h.frames(30);
        assert_eq!(h.text("action_name"), "Lint");
        h.click("action_save");
        h.frames(30);
        open(&mut h);
        assert!(h.find("z_import_1").is_none());
        assert!(h.find("z_action_lint").is_some());
        // Add action starts empty; a command is needed too.
        h.click("z_add_action");
        h.frames(30);
        h.type_text("action_name", "Docs");
        h.click("action_save");
        h.frames(20);
        assert_eq!(h.text("action_error"), "Action command is required");
        h.type_text("action_command", "mdbook serve");
        h.click("action_save");
        h.frames(30);
        open(&mut h);
        assert!(h.find("z_action_docs").is_some());
        // Deleting asks first.
        hover(&mut h, "z_action_docs");
        h.click("z_edit_action_docs");
        h.frames(30);
        h.click("action_delete");
        h.frames(30);
        assert!(h.text("action_delete_dialog").contains("Delete action?"));
        h.click("action_delete_confirm");
        h.frames(30);
        open(&mut h);
        assert!(h.find("z_action_docs").is_none());
        // The branch's changes open the changes on that scope (the base
        // beside it, as `{branch} → {base}`).
        h.click("z_diff");
        h.frames(40);
        assert!(
            joined(&mut h, "zchange_scope").contains("Branch changes"),
            "{}",
            joined(&mut h, "zchange_scope")
        );
        assert!(joined(&mut h, "zchange_base").contains("main"));
    });
}

/// The chat takes drops (chat_dropzone.rs): files from another app attach
/// to the draft, a session dropped becomes one chip naming it.
#[test]
fn files_from_other_apps_and_sessions_drop_into_the_draft() {
    deep(|| {
        let mut h = app();
        let column = h.bounds("conversation");
        let (x, y) = (column.x + 200., column.y + 300.);
        h.ui.dispatch(InputEvent::FileHover {
            x,
            y,
            path: "/Users/me/Desktop/shot.png".into(),
        });
        h.frames(10);
        assert_eq!(h.text("chat_dropzone_overlay"), "Drop to attach");
        h.ui.dispatch(InputEvent::FilesDrop {
            x,
            y,
            paths: vec![
                "/Users/me/Desktop/shot.png".into(),
                "/Users/me/notes.md".into(),
            ]
            .into(),
        });
        h.frames(30);
        healthy(&h);
        assert!(h.find("chat_dropzone_overlay").is_none());
        assert!(h.find("composer_att_d1").is_some() && h.find("composer_att_d2").is_some());
        assert!(h.texts().iter().any(|t| t == "notes.md"));
        // Files leaving again take the scrim with them.
        h.ui.dispatch(InputEvent::FileHover {
            x,
            y,
            path: "/tmp/a.txt".into(),
        });
        h.frames(10);
        assert!(h.find("chat_dropzone_overlay").is_some());
        h.ui.dispatch(InputEvent::FileHoverCancelled);
        h.frames(10);
        assert!(h.find("chat_dropzone_overlay").is_none());
        // A session: its title, one chip.
        drag_row(&mut h, "agent_a4", "conversation", 200., |_| {});
        assert_eq!(
            h.text("composer_input"),
            "@Durable\u{a0}Object\u{a0}token\u{a0}vault "
        );
    });
}

/// The composer shows the account's plan usage beside the context
/// (account_usage.rs): its ring opens the harness's accounts, and another
/// chosen is the one in use.
#[test]
fn the_composer_shows_the_accounts_usage_and_switches_accounts() {
    deep(|| {
        let mut h = app();
        assert_eq!(h.text("usage"), "42%");
        let (usage, context) = (h.bounds("usage"), h.bounds("composer_context"));
        assert!(usage.x < context.x, "before the context's ring");
        h.click("usage");
        h.frames(30);
        assert!(h.texts().iter().any(|t| t == "CLAUDE ACCOUNTS"));
        assert!(h.find("usage_row_1").is_some() && h.find("usage_row_2").is_some());
        snapshot(&h, "account_usage");
        h.click("usage_row_2");
        h.frames(30);
        assert_eq!(h.text("usage"), "61%", "the other account's busiest window");
        // A Codex session reads its own harness's.
        h.key(Key::Escape);
        h.frames(20);
        h.click("agent_a2");
        h.frames(40);
        assert_eq!(h.text("usage"), "86%");
    });
}

/// Side chats in the tabs layouts: a fork opens beside the focused pane,
/// and forking that side chat again copies its history, marker and all.
#[test]
fn the_tabs_layouts_fork_side_chats_beside_the_focused_pane() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        assert!(h.find("ztopbar").is_some());
        let fork = |h: &mut Harness| {
            cmd(h, "k", false);
            h.type_text("palette_input", "fork chat");
            h.frames(10);
            h.click("palette_fork_chat");
            h.frames(40);
            healthy(h);
        };
        fork(&mut h);
        let markers = |h: &mut Harness| h.texts().iter().filter(|t| *t == "Forked from").count();
        assert_eq!(markers(&mut h), 1, "the fork beside the chat");
        // The side chat's pane is focused: forking again copies it whole.
        fork(&mut h);
        assert_eq!(markers(&mut h), 3, "{:?}", h.texts());
        snapshot(&h, "tabs_side_chats");
    });
}

fn close_settings(h: &mut Harness) {
    h.key(Key::Escape);
    h.frames(30);
    assert!(h.find("settings").is_none(), "settings closed");
}

/// Settings → Shortcuts as Zeron's (settings/shortcuts.rs): its sections,
/// a click on a combo recording the next one, a combo another binding has
/// refused (and the composer's ⌘↩), Escape cancelling, Reset and Restore
/// defaults; and the window's keys follow what it binds.
#[test]
fn shortcuts_record_refuse_and_restore_and_the_keys_follow() {
    deep(|| {
        let mut h = app();
        open_settings(&mut h, "shortcuts");
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        for line in [
            "Keyboard shortcuts",
            "Appearance",
            "Files",
            "Browser",
            "Panels",
            "Sessions",
            "Projects",
            "Jump to session",
            "Toggle left sidebar",
            "Next session or right pane tab",
            "Navigate within the focused pane.",
            "Jump to session 9",
            "Shortcuts must be unique.",
        ] {
            assert!(says(&mut h, line), "{line}");
        }
        let chip = "settings_shortcut_toggle_sidebar_chip";
        assert_eq!(h.text(chip), "Cmd+B");
        assert_eq!(h.text("settings_shortcut_next_session_chip"), "Ctrl+Tab");
        assert!(h.find("settings_shortcut_toggle_sidebar_reset").is_none());
        snapshot(&h, "settings_shortcuts");

        // Recording: the chip asks for keys; ⌘G lands.
        h.click(chip);
        h.frames(5);
        assert_eq!(h.text(chip), "Press keys…");
        assert!(says(&mut h, "Press Escape to cancel."));
        snapshot(&h, "settings_shortcuts_recording");
        h.key_with(Key::Character("g".into()), meta(false));
        h.frames(5);
        assert_eq!(h.text(chip), "Cmd+G");
        assert!(h.find("settings_shortcut_toggle_sidebar_reset").is_some());
        assert!(says(&mut h, "Shortcuts must be unique."));

        // A combo another binding has is refused, naming it; the composer
        // keeps ⌘↩; Escape cancels and the settings stay.
        let files = "settings_shortcut_toggle_files_chip";
        h.click(files);
        h.frames(5);
        h.key_with(Key::Character("g".into()), meta(false));
        h.frames(5);
        assert_eq!(h.text(files), "Cmd+E");
        assert!(says(
            &mut h,
            "Cmd+G is already assigned to Toggle left sidebar."
        ));
        h.click(files);
        h.frames(5);
        h.key_with(Key::Enter, meta(false));
        h.frames(5);
        assert!(says(&mut h, "Cmd+Enter is reserved for the composer."));
        h.click(files);
        h.frames(5);
        h.key(Key::Escape);
        h.frames(5);
        assert!(h.find("settings").is_some(), "Escape only cancels");
        assert_eq!(h.text(files), "Cmd+E");
        // Voice's shortcut is the same binding: ⌘D is taken there.
        h.click(files);
        h.frames(5);
        h.key_with(Key::Character("d".into()), meta(false));
        h.frames(5);
        assert!(says(
            &mut h,
            "Cmd+D is already assigned to Hold to dictate in Settings → Voice."
        ));

        // The window's keys follow: ⌘G shuts the sidebar, ⌘B no longer.
        close_settings(&mut h);
        assert!(h.bounds("zcols_sidebar").width > 100.);
        cmd(&mut h, "b", false);
        assert!(h.bounds("zcols_sidebar").width > 100., "⌘B is free");
        cmd(&mut h, "g", false);
        assert!(h.bounds("zcols_sidebar").width < 0.5, "⌘G toggles it");
        cmd(&mut h, "g", false);

        // Reset puts one back; Restore defaults all, the send key and
        // Escape with them.
        open_settings(&mut h, "general");
        h.click("pref_send");
        h.frames(10);
        h.click("pref_send_cmd_enter");
        h.frames(20);
        open_settings(&mut h, "shortcuts");
        h.click("settings_shortcut_toggle_sidebar_reset");
        h.frames(5);
        assert_eq!(h.text(chip), "Cmd+B");
        h.click("settings_shortcut_random_wallpaper_chip");
        h.frames(5);
        h.key_with(Key::Character("y".into()), meta(true));
        h.frames(5);
        assert_eq!(
            h.text("settings_shortcut_random_wallpaper_chip"),
            "Cmd+Shift+Y"
        );
        h.click("shortcuts_restore");
        h.frames(10);
        assert_eq!(h.text("settings_shortcut_random_wallpaper_chip"), "Cmd+U");
        close_settings(&mut h);
        // Sending with Enter again.
        h.type_text("composer_input", "Back to Enter");
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("sent_turn_1").is_some(), "Enter sends");
    });
}

/// Zeron's default keys (shell.rs apply_keymap): ⌘N, ⌘B, ⌘R, ⌘E, ⌘J, ⌘/,
/// ⌘⇧A, ⌘⇧N and ⌘U.
#[test]
fn zerons_default_keys_drive_the_window() {
    deep(|| {
        let mut h = app();
        // ⌘B the sidebar, ⌘R the right pane, ⌘E Files.
        cmd(&mut h, "b", false);
        assert!(h.bounds("zcols_sidebar").width < 0.5);
        cmd(&mut h, "b", false);
        assert!(h.bounds("zcols_sidebar").width > 100.);
        assert!(h.bounds("zcols_right").width < 0.5);
        cmd(&mut h, "r", false);
        assert!(h.bounds("zcols_right").width > 300., "⌘R opens the pane");
        cmd(&mut h, "r", false);
        assert!(h.bounds("zcols_right").width < 0.5);
        cmd(&mut h, "e", false);
        assert!(h.find("ztree_Cargo.toml").is_some(), "⌘E opens Files");
        cmd(&mut h, "e", false);
        // ⌘J the terminal dock under the chat; again, it shuts.
        cmd(&mut h, "j", false);
        assert!(h.find("zdock").is_some(), "the terminal dock");
        cmd(&mut h, "j", false);
        h.frames(30);
        assert!(h.find("zdock").is_none() || h.bounds("zdock").height < 0.5);
        // ⌘/ the model picker.
        cmd(&mut h, "/", false);
        assert!(h.find("zeron_picker").is_some(), "the model picker");
        h.key(Key::Escape);
        h.frames(30);
        // ⌘⇧A archives the session: its row goes to the shelf.
        let row = h.bounds("agent_a1");
        assert!(row.y < h.bounds("side_archived").y);
        cmd(&mut h, "a", true);
        h.frames(20);
        assert!(
            h.find("agent_a1").is_none() || h.bounds("agent_a1").y > h.bounds("side_archived").y,
            "archived"
        );
        // ⌘⇧N adds a project (shell/spaces.rs open_add_space).
        cmd(&mut h, "n", true);
        assert!(h.find("project_palette").is_some(), "the add-project flow");
        h.key(Key::Escape);
        h.frames(30);
        assert!(h.find("project_palette").is_none());
        // ⌘N the new-session canvas, from Settings too.
        cmd(&mut h, ",", false);
        cmd(&mut h, "n", false);
        assert!(h.find("settings").is_none());
        assert!(h.find("canvas").is_some(), "⌘N: a new session");
        // ⌘U: without a folder, Appearance to choose one; with one, a
        // picture behind the canvas.
        cmd(&mut h, "u", false);
        assert!(h.find("settings_page_appearance").is_some());
        h.ui.dispatch(InputEvent::Scroll {
            x: 900.,
            y: 400.,
            delta_x: 0.,
            delta_y: 600.,
        });
        h.frames(10);
        h.click("settings_wallpaper_folder");
        h.frames(5);
        close_settings(&mut h);
        assert!(h.find("canvas_background").is_none());
        cmd(&mut h, "u", false);
        h.frames(30);
        assert!(h.find("canvas_background").is_some(), "a random picture");
        healthy(&h);
    });
}

/// ⌃Tab steps the right pane's tabs while it has the focus (a press in
/// it, or its strip's tabs), the sessions otherwise.
#[test]
fn control_tab_steps_the_right_panes_tabs_while_it_has_the_focus() {
    deep(|| {
        let mut h = app();
        h.click("zeron_pane_toggle");
        h.frames(40);
        assert!(h.find("zchange_file_1").is_some(), "the changes tab");
        let ctrl = |shift: bool| Modifiers {
            control: true,
            shift,
            ..Default::default()
        };
        let pane = h.bounds("zpane_body");
        let (x, y) = (pane.x + pane.width / 2., pane.y + pane.height - 20.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerUp { x, y, button });
        h.frames(5);
        let title = h.text("ztitle_title");
        h.key_with(Key::Tab, ctrl(false));
        h.frames(20);
        assert!(h.find("zchange_file_1").is_none(), "the next tab");
        assert_eq!(h.text("ztitle_title"), title, "the session stays");
        h.key_with(Key::Tab, ctrl(true));
        h.frames(20);
        assert!(h.find("zchange_file_1").is_some(), "back");
        // A press in the conversation: the sessions again.
        h.click("composer_input");
        h.key_with(Key::Tab, ctrl(false));
        h.frames(20);
        assert_ne!(h.text("ztitle_title"), title, "the next session");
        healthy(&h);
    });
}

/// The composer follows Settings: Send with ⌘↩ (Enter adds a line),
/// dictation and its shortcut held or tapped (⌘D).
#[test]
fn the_composer_follows_send_with_the_model_chip_and_dictation() {
    deep(|| {
        let mut h = app();
        open_settings(&mut h, "general");
        h.click("pref_send");
        h.frames(10);
        h.click("pref_send_cmd_enter");
        h.frames(5);
        close_settings(&mut h);
        h.type_text("composer_input", "One");
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("sent_turn_1").is_none(), "Enter adds a line");
        assert!(h.text("composer_input").contains('\n'));
        h.key_with(Key::Enter, meta(false));
        h.frames(10);
        assert!(h.find("sent_turn_1").is_some(), "⌘↩ sends");

        // ⌘D is held to talk: a tap says so (dictation.rs Phase::Tapped).
        h.click("composer_input");
        h.key_with(Key::Character("d".into()), meta(false));
        h.frames(10);
        assert!(h.find("composer_track").is_none(), "nothing heard");
        assert_eq!(h.text("composer_dictation_status_title"), "Hold to dictate");

        // Dictation off (Settings → Voice).
        assert!(h.find("composer_mic").is_some());
        open_settings(&mut h, "voice");
        h.click("settings_dictation");
        h.frames(10);
        close_settings(&mut h);
        assert!(h.find("composer_mic").is_none(), "no mic");
        h.click("composer_input");
        h.key_with(Key::Character("d".into()), meta(false));
        h.frames(10);
        assert!(h.find("composer_track").is_none(), "⌘D does nothing");
        healthy(&h);
    });
}

/// Escape stops the agent at work when General says so and nothing else
/// takes it.
#[test]
fn escape_stops_the_running_agent_when_general_says_so() {
    deep(|| {
        let mut h = app();
        let working = |h: &mut Harness| usize::from(h.find("sent_working_1").is_some());
        let idle = working(&mut h);
        let send = |h: &mut Harness, text: &str| {
            h.type_text("composer_input", text);
            h.key(Key::Enter);
            assert!(h.wait_until(|h| {
                h.frames(1);
                h.find("composer_sending").is_none()
            }));
        };
        send(&mut h, "First");
        assert!(working(&mut h) > idle, "working");
        h.key(Key::Escape);
        h.frames(10);
        assert!(working(&mut h) > idle, "off by default: it works on");
        open_settings(&mut h, "general");
        h.click("settings_escape_stops");
        h.frames(5);
        close_settings(&mut h);
        h.click("composer_input");
        h.key(Key::Escape);
        h.frames(10);
        assert_eq!(working(&mut h), idle, "stopped");
        healthy(&h);
    });
}

/// Files follows Settings: hidden and ignored entries shown at will, long
/// lines wrapping, edits saved once they rest; and the save key is the
/// binding's.
#[test]
fn files_show_hidden_entries_wrap_and_autosave_as_set() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        assert!(h.find("ztree_Cargo.toml").is_some());
        assert!(h.find("ztree_.gitignore").is_none(), "dotfiles hidden");
        assert!(h.find("ztree_target").is_none(), "ignored hidden");
        open_settings(&mut h, "files");
        h.click("settings_hidden_files");
        h.click("settings_word_wrap");
        h.click("settings_autosave");
        h.frames(10);
        h.click("settings_autosave_delay");
        h.frames(10);
        h.click("settings_autosave_delay_1");
        h.frames(10);
        assert_eq!(h.text("settings_autosave_delay"), "300 ms");
        close_settings(&mut h);
        assert!(h.find("ztree_.gitignore").is_some(), "shown");
        assert!(h.find("ztree_target").is_some());
        // Edits save themselves once they rest.
        h.click("ztree_Cargo.toml");
        h.frames(30);
        let editor = "file_file_Cargo_toml_editor";
        h.click(editor);
        h.ui.dispatch(InputEvent::Text(
            "a long line that runs on past the editor's width ".repeat(8),
        ));
        h.settle();
        h.frames(2);
        assert!(h.find("file_file_Cargo_toml_edited").is_some(), "edited");
        // Wrapped, the long line takes rows of its own; unwrapped, one.
        let tallest_line = |h: &mut Harness| {
            let node = h.find(editor).unwrap();
            h.ui.prepare_frame();
            let scene = h.ui.scene.borrow();
            let mut stack = vec![node];
            let mut tallest: f32 = 0.;
            while let Some(n) = stack.pop() {
                if matches!(scene.kind(n), zgx::scene::NodeKind::RichText { .. }) {
                    tallest = tallest.max(scene.bounds(n).height);
                }
                stack.extend(scene.children(n).iter().copied());
            }
            tallest
        };
        assert!(tallest_line(&mut h) > 21. * 2., "wrapped");
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.find("file_file_Cargo_toml_edited").is_none()
            }),
            "autosaved"
        );
        open_settings(&mut h, "files");
        h.click("settings_word_wrap");
        h.frames(5);
        close_settings(&mut h);
        assert_eq!(tallest_line(&mut h), 21., "one row");
        healthy(&h);
    });
}

/// The dead buttons of Settings do what they say (sample behaviour where
/// the engine is not wired): Unarchive, Install; and the run's end
/// notifies as Notifications say.
#[test]
fn settings_buttons_act_and_notifications_follow_the_switches() {
    deep(|| {
        let mut h = app();
        // Unarchive: the session leaves the page for the sidebar.
        open_settings(&mut h, "archived");
        assert_eq!(h.text("archived_count"), "585");
        h.click("archived_1_unarchive");
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.text("archived_count") == "584"
            }),
            "unarchived"
        );
        // Install.
        open_settings(&mut h, "harnesses");
        h.click("provider_opencode_install");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("provider_opencode_install").is_none() && h.texts().iter().any(|t| t == "v1.0.4")
        }));
        // A run's end, told while focused once not only in the background.
        open_settings(&mut h, "notifications");
        h.click("settings_background_only");
        h.frames(5);
        close_settings(&mut h);
        h.type_text("composer_input", "Tell me when it is done");
        h.key(Key::Enter);
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.texts().iter().any(|t| t == "Run finished")
            }),
            "the banner"
        );
        healthy(&h);
    });
}

/// Settings → General's Thread naming names a new session from its first
/// message whichever agent names it; $ and the / menu follow Completion.
#[test]
fn naming_and_completion_follow_their_settings() {
    deep(|| {
        let mut h = app();
        // Skills after a $, kept out of the / menu.
        h.type_text("composer_input", "/web");
        h.frames(10);
        assert!(h.find("composer_ref_skill_webapp-testing").is_none());
        h.click("composer_input");
        for _ in 0..4 {
            h.key(Key::Backspace);
        }
        h.ui.dispatch(InputEvent::Text("$web".into()));
        h.settle();
        h.frames(10);
        assert!(h.find("composer_ref_skill_webapp-testing").is_some());
        h.key(Key::Escape);
        for _ in 0..4 {
            h.key(Key::Backspace);
        }
        // $ off: no menu after it.
        open_settings(&mut h, "harnesses");
        h.click("provider_claude_trigger");
        h.frames(20);
        h.click("provider_claude_dollar_skills");
        h.frames(5);
        close_settings(&mut h);
        h.type_text("composer_input", "$web");
        h.frames(10);
        assert!(h.find("composer_references").is_none(), "$ is text");
        // A model names it.
        open_settings(&mut h, "general");
        h.click("settings_thread_naming");
        h.frames(20);
        h.click("settings_thread_naming_claude_2");
        h.frames(5);
        close_settings(&mut h);
        cmd(&mut h, "n", false);
        h.type_text("new_composer_input", "Tidy the sidebar's metrics");
        h.click("new_composer_send");
        h.frames(60);
        assert_eq!(h.text("ztitle_title"), "Tidy the sidebar's metrics");
        healthy(&h);
    });
}

/// Shortcuts and preferences last across runs (`ui.persist`, in the
/// host's storage), as Zeron's settings file keeps them.
#[test]
fn shortcuts_and_preferences_last_across_runs() {
    deep(|| {
        let storage = std::env::temp_dir().join(format!("zeron-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&storage);
        let run = |storage: &Path| {
            let storage = storage.to_owned();
            let h = Harness::new(move |runtime| {
                let host = ScriptHost::new(
                    runtime,
                    Path::new(env!("CARGO_MANIFEST_DIR"))
                        .join("examples/styleguide/app_zeron.luau"),
                )
                .storage(storage);
                host.action("inspect", |_| {});
                host.action("close_window", |_| {});
                host.action("open_app", |_| {});
                host
            });
            h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
            h.ui.prepare_frame();
            h.settle();
            h.frames(30);
            healthy(&h);
            h
        };
        let mut h = run(&storage);
        open_settings(&mut h, "shortcuts");
        h.click("settings_shortcut_toggle_sidebar_chip");
        h.frames(5);
        h.key_with(Key::Character("g".into()), meta(false));
        open_settings(&mut h, "general");
        h.click("settings_escape_stops");
        h.frames(5);
        h.host.save();
        drop(h);
        let mut h = run(&storage);
        open_settings(&mut h, "shortcuts");
        assert_eq!(h.text("settings_shortcut_toggle_sidebar_chip"), "Cmd+G");
        close_settings(&mut h);
        cmd(&mut h, "g", false);
        assert!(h.bounds("zcols_sidebar").width < 0.5, "bound as saved");
        let _ = std::fs::remove_dir_all(&storage);
    });
}

/// The transcript scrolled to its top (the release notes' first turn, its
/// calls).
fn to_top(h: &mut Harness) {
    h.ui.dispatch(InputEvent::Scroll {
        x: 800.,
        y: 300.,
        delta_x: 0.,
        delta_y: -5000.,
    });
    h.frames(10);
}

/// The transcript scrolled until node `id` sits in its middle, clear of
/// the composer under it.
fn into_view(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    h.ui.dispatch(InputEvent::Scroll {
        x: 800.,
        y: 300.,
        delta_x: 0.,
        delta_y: b.y + b.height / 2. - 300.,
    });
    h.frames(10);
}

/// Opens session `row` from the sidebar.
fn open_session(h: &mut Harness, row: &str) {
    h.click(row);
    h.frames(30);
    healthy(h);
}

/// Down or up the settings page until `id` is on screen.
fn scroll_to(h: &mut Harness, id: &str) {
    for _ in 0..30 {
        let b = h.bounds(id);
        if b.y > 60. && b.y + b.height < HEIGHT - 20. {
            return;
        }
        h.ui.dispatch(InputEvent::Scroll {
            x: 900.,
            y: 400.,
            delta_x: 0.,
            delta_y: if b.y > 400. { 240. } else { -240. },
        });
        h.frames(6);
    }
}

/// A ⌘K command, found by typing and run by Enter.
fn run_command(h: &mut Harness, query: &str) {
    cmd(h, "k", false);
    h.click("palette_tab_commands");
    h.frames(10);
    h.type_text("palette_input", query);
    h.frames(10);
    h.key(Key::Enter);
    h.frames(30);
    healthy(h);
}

/// The message rail (rail.rs): a tick per prompt beside the transcript,
/// lit while its prompt shows, its card under the pointer, a click taking
/// the transcript to it; hidden in a column under 768.
#[test]
fn the_rail_ticks_each_prompt_and_takes_the_transcript_there() {
    deep(|| {
        let mut h = app();
        let (one, two) = ("rail_turn_1", "rail_turn_2");
        assert!(
            h.find(one).is_some() && h.find(two).is_some(),
            "a tick a prompt"
        );
        let (a, b) = (h.bounds(one), h.bounds(two));
        assert_eq!(b.y - a.y, 8., "8 apart");
        assert_eq!(a.width, 32.);
        // At the end, the last prompt shows: its tick is lit (the text at
        // 80%), the first's is not.
        assert!(h.opacity("rail_turn_2_bar") < 0.9, "lit");
        assert_eq!(h.opacity("rail_turn_1_bar"), 1.);
        assert_eq!(h.bounds("rail_turn_1_bar").width, 8.);
        // Under the pointer: 24 wide, and its card.
        hover_id(&mut h, one);
        h.frames(20);
        assert_eq!(h.bounds("rail_turn_1_bar").width, 24.);
        assert!(
            h.wait_until(|h| shows(h, "Here is a first pass, grouped by area")),
            "the reply's opening in the card"
        );
        snapshot(&h, "rail_card");
        // A click glides the first prompt to the view's top.
        h.click(one);
        h.frames(60);
        let prompt = h.bounds("turn_1_prompt");
        assert!(prompt.y > 0. && prompt.y < 120., "at the top: {prompt:?}");
        h.frames(10);
        assert!(h.opacity("rail_turn_1_bar") < 0.9, "and lit");
        // A narrow column has none.
        h.ui.scene.borrow_mut().resize(700., HEIGHT);
        h.frames(10);
        assert!(h.find(one).is_none(), "hidden under 48rem");
    });
}

/// Thinking rides the tool group: "Thought process" rows that open on the
/// thought, named first in the summary; a live one opens while it streams.
#[test]
fn thoughts_ride_the_tool_group() {
    deep(|| {
        let mut h = app();
        to_top(&mut h);
        let summary = joined(&mut h, "turn_1_tools_header");
        assert!(summary.starts_with("Thought process"), "{summary}");
        h.click("turn_1_tools_t1_3_head");
        h.frames(30);
        assert!(shows(
            &mut h,
            "Five commits since v0.2.116, in three areas:"
        ));
        assert!(shows(
            &mut h,
            "• The Windows notes need the WebView2 work read closely."
        ));
        // A sent turn's thought opens as it arrives, and folds once done.
        h.type_text("composer_input", "Go");
        h.click("composer_send");
        let open = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_5_body").is_some()
        });
        assert!(open, "open while it streams");
        let folded = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_5_body").is_none()
        });
        assert!(folded, "folded once it settled");
        // The summary's roll to its new words settles on the frame clock.
        h.frames(40);
        let summary = joined(&mut h, "sent_tools_1_header");
        assert!(
            summary
                .trim_start_matches('·')
                .starts_with("Thought process·ran"),
            "{summary}"
        );
    });
}

/// Compact mode (Settings → General): a turn's work folds under one header
/// that says how long it worked, opening on the group as it was.
#[test]
fn compact_mode_folds_each_turns_work_under_how_long_it_took() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        assert!(shows(&mut h, "Collapse thinking and tools."));
        h.click("pref_compact_mode");
        h.frames(20);
        h.key(Key::Escape);
        h.frames(40);
        healthy(&h);
        assert!(h.find("turn_1_tools").is_none(), "folded");
        assert_eq!(joined(&mut h, "turn_1_work_header"), "Worked for 1m 10s");
        // The working turn says what it does until it is done.
        assert!(!joined(&mut h, "turn_2_work_header").starts_with("Worked"));
        h.click("turn_1_work_header");
        h.frames(30);
        assert!(h.find("turn_1_tools").is_some(), "the group under it");
        assert!(h.find("turn_1_tools_t1_1").is_none(), "itself folded");
        snapshot(&h, "compact");
        // A sent turn settles into "Worked for".
        h.type_text("composer_input", "Go");
        h.click("composer_send");
        let worked = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_work_1_header").is_some()
                && joined(h, "sent_work_1_header").starts_with("Worked for")
        });
        assert!(worked, "it says how long it worked");
    });
}

/// The working line: one of Zeron's words, seeded per chat, and the time
/// the turn has worked, both moved on by the engine with no script.
#[test]
fn the_working_line_ticks_its_timer_without_the_script() {
    deep(|| {
        let mut h = app();
        let words = [
            "Zeroning",
            "Thinking",
            "Pondering",
            "Scheming",
            "Brewing",
            "Weaving",
            "Tinkering",
            "Musing",
            "Composing",
            "Sifting",
            "Untangling",
            "Distilling",
            "Sketching",
            "Plotting",
            "Riffing",
            "Combobulating",
            "Percolating",
            "Marinating",
            "Noodling",
            "Puzzling",
            "Conjuring",
        ];
        let word = joined(&mut h, "turn_2_working");
        assert!(
            words.iter().any(|w| word.starts_with(&format!("{w}…"))),
            "{word}"
        );
        let timer = h.text("turn_2_working_timer");
        assert!(timer.starts_with("1m 5"), "{timer}");
        // What launch leaves to do a second on (the agent updates' banner)
        // done first: then only the clock moves.
        let launched = std::time::Instant::now();
        while launched.elapsed() < std::time::Duration::from_millis(1300) {
            h.frames(1);
        }
        let timer = h.text("turn_2_working_timer");
        let calls = h.calls();
        let ticked = h.wait_until(|h| h.text("turn_2_working_timer") != timer);
        assert!(ticked, "a second on");
        assert_eq!(h.calls(), calls, "no script ran as it ticked");
        // A device that is away holds the send: it queues.
        open_session(&mut h, "thread_h2");
        h.type_text("composer_input", "One more");
        h.click("composer_send");
        h.frames(10);
        assert!(shows(&mut h, "Queued — will send automatically"));
    });
}

/// Prompts: a long one folds with Show more; who sent one from another
/// chat; references as chips; what one carried; a send that never arrived.
#[test]
fn prompts_fold_name_their_sender_and_carry_their_files() {
    deep(|| {
        let mut h = app();
        open_session(&mut h, "agent_a7");
        assert_eq!(h.text("turn_1_prompt_expander"), "Show more");
        let folded = h.bounds("turn_1_prompt_body").height;
        assert_eq!(folded, 110., "five lines");
        h.click("turn_1_prompt_expander");
        h.frames(40);
        assert_eq!(h.text("turn_1_prompt_expander"), "Show less");
        assert!(h.bounds("turn_1_prompt_body").height > folded);

        open_session(&mut h, "agent_a2");
        assert!(h.find("turn_1_prompt_from").is_some());
        assert!(shows(&mut h, "Message from"));
        assert!(shows(&mut h, "Awaiting your answer…"), "its question waits");

        open_session(&mut h, "agent_a4");
        assert!(shows(&mut h, "crates/cloud/src/vault.rs"));
        assert!(!shows(&mut h, "@crates/cloud"), "a chip, not its token");

        open_session(&mut h, "agent_a5");
        assert!(h.find("turn_1_attachment_1").is_some(), "the picture");
        assert!(
            h.find("turn_1_attachment_2").is_some(),
            "the one unavailable"
        );
        assert!(shows(&mut h, "codex-install.log"), "the file's pill");
        h.click("turn_1_attachment_1");
        h.frames(20);
        assert!(
            h.texts().iter().any(|t| t == "Install failed.png"),
            "it opens in the viewer"
        );
        h.key(Key::Escape);
        h.frames(20);

        open_session(&mut h, "agent_a6");
        assert!(shows(&mut h, "Not delivered — click to retry"));
        assert!(!shows(&mut h, "Started on the ARM runner"));
        h.click("turn_2_retry");
        let delivered = h.wait_until(|h| {
            h.frames(1);
            shows(h, "Started on the ARM runner")
        });
        assert!(delivered, "a retry delivers it");
        assert!(!shows(&mut h, "Not delivered"));

        // A message sent with an image carries it, uploading, then shown.
        h.click("composer_add");
        h.frames(5);
        h.type_text("composer_input", "With a picture");
        h.click("composer_send");
        h.frames(2);
        assert!(h.find("sent_1_a1").is_some(), "it went with the message");
        let up = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_1_a1_upload").is_none()
        });
        assert!(up, "uploaded");
    });
}

/// The reply's other rows: an error, the images the agent made, subagents
/// opening their transcripts in a tab, and a file badge opening its file.
#[test]
fn replies_show_errors_images_and_subagents() {
    deep(|| {
        let mut h = app();
        to_top(&mut h);
        // A file's badge opens the file, the row left shut.
        h.click("turn_1_tools_t1_1_file");
        h.frames(30);
        assert!(
            h.find("turn_1_tools_t1_1_body").is_none(),
            "the row stays shut"
        );
        assert!(h.find("zp_tab_file_CHANGELOG_md").is_some(), "its tab");
        // A spawn row opens its subagent's transcript in a tab.
        assert!(h.find("turn_1_spawn_sa2").is_some());
        h.click("turn_1_spawn_sa2");
        h.frames(40);
        healthy(&h);
        assert!(shows(
            &mut h,
            "List the pull requests merged since v0.2.116"
        ));

        open_session(&mut h, "agent_a8");
        assert!(h.find("turn_1_error").is_some());
        assert!(shows(&mut h, "kCGErrorIllegalArgument"));

        open_session(&mut h, "thread_h2");
        let shown = h.wait_until(|h| {
            h.frames(1);
            h.find("turn_2_image_1").is_some() && !shows(h, "Loading image…")
        });
        assert!(shown, "the images load");
        assert!(shows(&mut h, "Image unavailable"));
        let image = h.bounds("turn_2_image_1");
        assert!(image.width <= 514. && image.height <= 422., "{image:?}");
    });
}

fn says(h: &mut Harness, what: &str) -> bool {
    h.texts().iter().any(|t| t == what)
}

/// Waits until `id` mounts, then lets it fade in.
fn appear(h: &mut Harness, id: &str) -> bool {
    let came = h.wait_until(|h| {
        h.frames(1);
        h.find(id).is_some()
    });
    h.frames(30);
    came
}

/// Appearance's fonts (appearance.rs v0.2.129): a search over the
/// catalog, prefixes first, a missing font dimmed and inert, the terminal's
/// fixed-width only; Conversation width sets the transcript's and the
/// composer's widest, its details under the pointer running nothing.
#[test]
fn appearance_picks_fonts_and_the_conversation_width() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_appearance");
        h.frames(20);
        scroll_to(&mut h, "settings_font_ui");
        assert_eq!(h.text("settings_font_ui"), "Geist");
        h.click("settings_font_ui");
        h.frames(20);
        assert!(h.find("settings_font_ui_search").is_some(), "the search");
        h.type_text("settings_font_ui_search", "i");
        h.frames(10);
        // "IBM…", "Inter", "Iosevka" before the names holding an i.
        let ibm = h.bounds("settings_font_ui_ibm_plex_mono").y;
        let inter = h.bounds("settings_font_ui_inter").y;
        let geist = h.bounds("settings_font_ui_geist").y;
        assert!(ibm < inter && inter < geist, "{ibm} {inter} {geist}");
        h.type_text("settings_font_ui_search", "nter");
        h.frames(10);
        h.key(Key::Enter);
        h.frames(20);
        assert_eq!(h.text("settings_font_ui"), "Inter");
        assert!(
            h.find("settings_font_ui_search").is_none(),
            "chosen, it closes"
        );
        h.click("settings_font_ui");
        h.frames(20);
        h.type_text("settings_font_ui_search", "zzz");
        h.frames(10);
        assert!(says(&mut h, "No matching fonts"));
        h.key(Key::Escape);
        h.frames(20);
        // A missing font is dimmed and does nothing; the terminal lists
        // fixed-width fonts only.
        h.click("settings_font_terminal");
        h.frames(20);
        assert!(h.find("settings_font_terminal_inter").is_none());
        assert_eq!(h.opacity("settings_font_terminal_berkeley_mono"), 0.45);
        h.click("settings_font_terminal_berkeley_mono");
        h.frames(10);
        assert_eq!(h.text("settings_font_terminal"), "Geist Mono");
        h.click("settings_font_terminal_jetbrains_mono");
        h.frames(20);
        assert_eq!(h.text("settings_font_terminal"), "JetBrains Mono");

        // Its details show under the pointer, by the engine alone.
        scroll_to(&mut h, "settings_conversation_width");
        let calls = h.calls();
        hover_id(&mut h, "settings_conversation_width");
        h.frames(10);
        assert_eq!(h.calls(), calls, "hover ran the script");
        assert_eq!(h.text("settings_conversation_width"), "736 px");
        // Its middle is 880 (by 16s); End the widest.
        h.click("settings_conversation_width_input");
        h.frames(10);
        assert_eq!(h.text("settings_conversation_width"), "880 px");
        h.key(Key::Home);
        h.frames(10);
        assert_eq!(h.text("settings_conversation_width"), "560 px");
        snapshot(&h, "settings_fonts");
        h.key(Key::Escape);
        h.frames(30);
        healthy(&h);
        // The composer and the transcript take it.
        assert_eq!(h.bounds("composer").width, 560.);
        cmd(&mut h, ",", false);
        scroll_to(&mut h, "settings_conversation_width");
        h.click("settings_conversation_width_reset");
        h.frames(10);
        h.key(Key::Escape);
        h.frames(30);
        assert_eq!(h.bounds("composer").width, 736.);
    });
}

/// The theme library (appearance.rs, theme_library.rs): Add a theme
/// analyses a source into its variants, imports the chosen ones linked or
/// copied; each theme reloads, reviews, duplicates, unlinks, goes.
#[test]
fn the_theme_library_adds_reviews_and_removes_themes() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_appearance");
        h.frames(20);
        scroll_to(&mut h, "theme_library_add");
        assert!(h.find("theme_tokyo_night").is_some());
        h.click("theme_library_add");
        h.frames(30);
        assert!(says(&mut h, "Add a theme"));
        assert!(says(
            &mut h,
            "Zeron finds light and dark variants automatically."
        ));
        // Nothing to analyse yet.
        h.click("theme_add_primary");
        h.frames(10);
        assert!(says(
            &mut h,
            "Choose a local theme file or extension folder."
        ));
        h.click("theme_add_browse");
        h.frames(20);
        assert!(says(&mut h, "Detected themes"));
        assert!(says(&mut h, "4 variants"));
        assert_eq!(h.text("theme_add_primary"), "Import selected");
        h.click("theme_add_pick_catppuccin_latte");
        h.click("theme_add_link");
        h.frames(10);
        h.click("theme_add_details_catppuccin_mocha");
        h.frames(10);
        assert!(
            h.find("theme_report_catppuccin_mocha").is_some(),
            "its mapping"
        );
        snapshot(&h, "theme_add");
        h.click("theme_add_primary");
        h.frames(30);
        healthy(&h);
        assert!(h.find("theme_add").is_none(), "imported, it closes");
        scroll_to(&mut h, "theme_catppuccin_4");
        assert!(
            joined(&mut h, "theme_catppuccin_4").contains("Linked package · 3 variants"),
            "{}",
            joined(&mut h, "theme_catppuccin_4")
        );
        // A reload that fails keeps the last good one, and says so.
        scroll_to(&mut h, "theme_studio_reload");
        h.click("theme_studio_reload");
        h.frames(10);
        assert!(joined(&mut h, "theme_studio").contains("Using last known good"));
        scroll_to(&mut h, "theme_rose_pine_review");
        h.click("theme_rose_pine_review");
        h.frames(30);
        assert!(says(&mut h, "Theme mapping"));
        h.click("theme_review_done");
        h.frames(30);
        scroll_to(&mut h, "theme_rose_pine_duplicate");
        h.click("theme_rose_pine_duplicate");
        h.frames(10);
        assert!(h.find("theme_rose_pine_copy").is_some());
        scroll_to(&mut h, "theme_rose_pine_unlink");
        h.click("theme_rose_pine_unlink");
        h.frames(10);
        assert!(joined(&mut h, "theme_rose_pine").starts_with("Rosé PineImported"));
        scroll_to(&mut h, "theme_tokyo_night_remove");
        h.click("theme_tokyo_night_remove");
        h.frames(10);
        assert!(h.find("theme_tokyo_night").is_none());
        healthy(&h);
    });
}

/// Waits (in real time: listings answer after a moment) until `id` shows.
fn wait_for(h: &mut Harness, id: &str) {
    let found = h.wait_until(|h| {
        h.frames(1);
        h.find(id).is_some()
    });
    assert!(found, "{id} never showed: {:?}", h.texts());
    healthy(h);
}

fn meta_key(h: &mut Harness, key: Key) {
    h.key_with(
        key,
        Modifiers {
            meta: true,
            ..Default::default()
        },
    );
    h.frames(5);
}

/// Adding a project (shell/spaces.rs): ⌘K's New project, then a device,
/// a location, its folders under crumbs; the search filters each step and,
/// in Home, finds folders anywhere under it; its ghost completes with Tab
/// and `/` goes in; ← goes up; ⌘↵ adds the open folder and lands on the
/// canvas in it.
#[test]
fn new_project_walks_devices_locations_and_folders() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "new project");
        h.frames(10);
        h.click("palette_new_project");
        h.frames(20);
        assert!(h.find("project_palette").is_some());
        assert!(h.texts().iter().any(|t| t == "Search devices…"));
        assert!(h.find("project_device_build").is_some(), "every device");
        h.type_text("project_search", "zz");
        h.frames(5);
        assert!(h.texts().iter().any(|t| t == "No devices found"));
        h.key(Key::Backspace);
        h.key(Key::Backspace);
        h.key(Key::Enter);
        h.frames(10);
        // MacBook Pro: Home and its drives.
        assert_eq!(h.text("project_crumb_device"), "MacBook Pro");
        assert!(h.find("project_location_backup").is_some());
        h.click("project_location_home");
        assert!(
            h.find("project_loading").is_some(),
            "skeletons while it lists"
        );
        wait_for(&mut h, "project_folder_code");
        snapshot(&h, "project_home");
        // The ghost: the rest of the first folder the query starts.
        h.type_text("project_search", "co");
        h.frames(5);
        assert!(h.texts().iter().any(|t| t == "de"), "{:?}", h.texts());
        h.key(Key::Tab);
        assert_eq!(h.text("project_search"), "code");
        h.keys("/");
        wait_for(&mut h, "project_folder_comet");
        assert_eq!(
            h.text("project_search"),
            "Search folders…",
            "the query starts over"
        );
        assert!(h.find("project_crumb_code").is_some());
        // ← goes up.
        h.key(Key::ArrowLeft);
        wait_for(&mut h, "project_folder_zeron");
        // In Home, folders from anywhere under it.
        h.type_text("project_search", "rust");
        h.frames(5);
        assert!(h.texts().iter().any(|t| t == "In Home"));
        h.key(Key::Enter);
        wait_for(&mut h, "project_crumb_rustconf_deck");
        // Nothing in it: it says how to go on.
        wait_for(&mut h, "project_empty");
        assert!(h.texts().iter().any(|t| t == "No folders here"));
        meta_key(&mut h, Key::Enter);
        assert!(h.texts().iter().any(|t| t == "Adding…"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("project_palette").is_none()
        }));
        h.frames(30);
        healthy(&h);
        assert_eq!(h.text("new_project"), "rustconf-deck");
        // The switcher lists it.
        h.click("side_filter");
        h.frames(20);
        assert!(h.find("side_filter_rustconf-deck").is_some());
    });
}

/// The crumbs as a typed path (⌘L): it completes with Tab, a folder that
/// does not list says why, and ⌘↵ on one already a project lands there.
/// An offline device's folders fail with Retry; a deep trail folds its
/// middle into "…".
#[test]
fn a_typed_path_completes_says_why_not_and_reuses_a_project() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "n", true);
        assert!(h.find("project_palette").is_some(), "⌘⇧N");
        h.click("project_device_build");
        h.frames(10);
        h.click("project_location_home");
        wait_for(&mut h, "project_load_error");
        assert!(h.texts().iter().any(|t| t == "Device is not connected"));
        assert!(h.find("project_retry").is_some());
        h.click("project_crumb_new");
        h.frames(10);
        h.click("project_device_mbp");
        h.frames(10);
        meta_key(&mut h, Key::Character("l".into()));
        assert_eq!(h.text("project_path"), "~/");
        h.ui.dispatch(InputEvent::Text("~/ze".into()));
        h.settle();
        h.frames(5);
        assert!(h.texts().iter().any(|t| t == "ron"), "the ghost");
        h.key(Key::Tab);
        assert_eq!(h.text("project_path"), "~/zeron/");
        h.ui.dispatch(InputEvent::Text("nope".into()));
        h.settle();
        h.key(Key::Enter);
        wait_for(&mut h, "project_path_error");
        assert_eq!(h.text("project_path_error"), "No folder at ~/zeron/nope");
        // A deep path: Home › … › 2026 › october.
        meta_key(&mut h, Key::Character("l".into()));
        h.ui.dispatch(InputEvent::Text(
            "~/code/experiments/notes/2026/october".into(),
        ));
        h.settle();
        h.key(Key::Enter);
        wait_for(&mut h, "project_crumb_october");
        assert!(h.find("project_crumb_more").is_some());
        assert!(h.find("project_crumb_code").is_none(), "folded");
        h.click("project_crumb_2026");
        wait_for(&mut h, "project_folder_october");
        h.click("project_crumb_more");
        h.frames(20);
        h.click("project_more_code");
        wait_for(&mut h, "project_folder_experiments");
        // Esc leaves the typed path; ⌘↵ on a project's folder lands in it.
        meta_key(&mut h, Key::Character("l".into()));
        h.ui.dispatch(InputEvent::Text("~/zeron/comet".into()));
        h.settle();
        h.key(Key::Escape);
        h.frames(5);
        assert!(h.find("project_path").is_none());
        meta_key(&mut h, Key::Character("l".into()));
        h.ui.dispatch(InputEvent::Text("~/zeron/comet".into()));
        h.settle();
        meta_key(&mut h, Key::Enter);
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("project_palette").is_none()
        }));
        h.frames(30);
        assert_eq!(h.text("new_project"), "comet", "the project it already is");
        healthy(&h);
    });
}

/// Match wallpaper colors and Adjust background (wallpaper_colors.rs,
/// appearance.rs): the artwork's colour takes the accent's place while it
/// is on; the artwork zoomed in the dialog lands on the canvas zoomed.
/// Reduce motion and pausing in the background follow their settings.
#[test]
fn the_background_tints_the_accent_and_is_placed_as_adjusted() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_appearance");
        h.frames(20);
        scroll_to(&mut h, "settings_canvas_background");
        h.click("settings_canvas_background");
        h.frames(10);
        // The accent, as the width slider's knob wears it.
        let accent = |h: &mut Harness| quad(h, "settings_conversation_width_knob").fill;
        let before = accent(&mut h);
        scroll_to(&mut h, "settings_wallpaper_colors");
        h.click("settings_wallpaper_colors");
        h.frames(10);
        assert_ne!(accent(&mut h), before, "the artwork's colour");
        assert!(says(
            &mut h,
            "Wallpaper colors are enabled; this accent is used when they are off."
        ));
        scroll_to(&mut h, "settings_canvas_background_adjust");
        h.click("settings_canvas_background_adjust");
        h.frames(30);
        assert!(says(&mut h, "Drag to reposition. Scroll or pinch to zoom."));
        for _ in 0..3 {
            h.click("background_adjust_in");
        }
        h.frames(10);
        assert_eq!(h.text("background_adjust_value"), "130%");
        h.click("background_adjust_apply");
        h.frames(30);
        healthy(&h);
        // Reduce motion On says what it does.
        scroll_to(&mut h, "settings_reduce_motion");
        h.click("settings_reduce_motion");
        h.frames(10);
        h.click("settings_reduce_motion_2");
        h.frames(10);
        assert!(says(
            &mut h,
            "Animations skip straight to their final state."
        ));
        h.click("settings_reduce_motion");
        h.frames(10);
        h.click("settings_reduce_motion_1");
        h.frames(10);
        h.key(Key::Escape);
        h.frames(30);
        h.click("ztitle_new");
        h.frames(40);
        let (art, room) = (
            h.bounds("canvas_background_art"),
            h.bounds("canvas_background_image"),
        );
        assert!(
            (art.width - room.width * 1.3).abs() < 1.,
            "{art:?} {room:?}"
        );
        assert!((art.x - (room.x - room.width * 0.15)).abs() < 1., "centred");

        // Paused at the back: what animates holds still until it is back.
        cmd(&mut h, ",", false);
        scroll_to(&mut h, "settings_pause_background");
        h.click("settings_pause_background");
        h.frames(10);
        h.key(Key::Escape);
        h.frames(30);
        h.ui.set_window_active(false);
        cmd(&mut h, ",", false);
        h.frames(20);
        assert!(h.opacity("settings") < 1., "held at the back");
        h.ui.set_window_active(true);
        h.frames(30);
        assert_eq!(h.opacity("settings"), 1.);
    });
}

/// Notifications (notifications.rs): Desktop then Sounds; a parent off
/// dims its rows to 55% and makes their switches inert.
#[test]
fn notifications_dim_what_their_parent_turns_off() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_notifications");
        h.frames(20);
        let desktop = h.bounds("settings_desktop_notifications").y;
        let sounds = h.bounds("settings_session_sounds").y;
        assert!(desktop < sounds, "Desktop first");
        assert!(says(&mut h, "Only when in the background"));
        assert!(says(&mut h, "Errors and disconnections"));
        assert_eq!(h.opacity("settings_sound_done_row"), 1.);
        h.click("settings_session_sounds");
        h.frames(10);
        assert_eq!(h.opacity("settings_sound_done_row"), 0.55);
        assert_eq!(h.opacity("settings_agent_updates_row"), 1.);
        h.click("settings_desktop_notifications");
        h.frames(10);
        assert_eq!(h.opacity("settings_agent_updates_row"), 0.55);
        assert_eq!(h.opacity("settings_background_only_row"), 0.55);
        snapshot(&h, "settings_notifications");
    });
}

/// General (shortcuts.rs general_page): where pull requests open, and
/// thread naming: the session's agent, or a model chosen; Reset goes back.
#[test]
fn general_opens_prs_and_names_threads_as_zerons() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_general");
        h.frames(20);
        assert_eq!(h.text("settings_open_prs"), "Pull request view");
        h.click("settings_open_prs");
        h.frames(10);
        h.click("settings_open_prs_3");
        h.frames(10);
        assert_eq!(h.text("settings_open_prs"), "Default browser");
        assert_eq!(h.text("settings_thread_naming"), "Session agent");
        assert!(says(&mut h, "Each thread is named by its own agent."));
        h.click("settings_thread_naming");
        h.frames(20);
        h.click("settings_thread_naming_claude_2");
        h.frames(20);
        assert_eq!(h.text("settings_thread_naming"), "Haiku 4.5");
        assert!(says(&mut h, "A small model keeps titles fast and cheap."));
        h.click("settings_thread_naming_reset");
        h.frames(10);
        assert_eq!(h.text("settings_thread_naming"), "Session agent");
        assert!(h.find("settings_thread_naming_reset").is_none());
    });
}

/// "Open pull requests in" the default browser: the board's rows open
/// there instead of the pull request's view.
#[test]
fn the_board_opens_pull_requests_where_general_says() {
    deep(|| {
        let mut h = desktop_app();
        let desktop = h.desktop.clone().unwrap();
        cmd(&mut h, ",", false);
        h.click("settings_open_prs");
        h.frames(10);
        h.click("settings_open_prs_3");
        h.frames(10);
        h.key(Key::Escape);
        h.frames(30);
        h.click("nav_prs");
        h.frames(30);
        arrives(&mut h, "pr_p1");
        h.click("pr_p1");
        h.frames(20);
        assert_eq!(
            desktop.opened(),
            ["https://github.com/zeron/comet/pull/412"]
        );
        healthy(&h);
    });
}

/// Providers (harnesses.rs, accounts.rs v0.2.129): each agent on the
/// device chosen, its update applied step by step, an install, its
/// policy; ↻ finds a newer Codex; Cloud's own; accounts switched and
/// added through the browser, a code pasted, a failure retried.
#[test]
fn providers_update_install_and_sign_in() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_harnesses");
        h.frames(20);
        assert!(says(&mut h, "Providers"));
        assert!(joined(&mut h, "provider_claude").contains("v2.1.308v2.1.310"));
        assert_eq!(h.opacity("provider_opencode_row"), 0.55, "not installed");
        h.click("provider_claude_update");
        h.frames(4);
        assert!(joined(&mut h, "provider_claude").contains("Preparing update…"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v2.1.310 · Updated")
        }));
        // An install, then it is on.
        h.click("provider_opencode_install");
        h.frames(4);
        assert!(joined(&mut h, "provider_opencode").contains("Installing OpenCode…"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v1.0.4")
        }));
        // ↻: a spinner, then a newer Codex.
        h.click("providers_check");
        h.frames(2);
        assert!(h.find("providers_checking").is_some());
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v0.165.0")
        }));
        // Opened: completion, delegation, the policy and the accounts.
        h.click("provider_claude_trigger");
        h.frames(20);
        assert!(says(&mut h, "Native subagents"));
        scroll_to(&mut h, "provider_claude_policy");
        h.click("provider_claude_policy");
        h.frames(10);
        h.click("provider_claude_policy_2");
        h.frames(10);
        assert!(says(
            &mut h,
            "Install automatically after active runs finish."
        ));
        scroll_to(&mut h, "provider_claude_accounts_2");
        assert!(joined(&mut h, "provider_claude_accounts_1").contains("In use"));
        h.click("provider_claude_accounts_2");
        h.frames(10);
        assert!(joined(&mut h, "provider_claude_accounts_2").contains("In use"));
        assert!(!joined(&mut h, "provider_claude_accounts_1").contains("In use"));
        // Add account: the browser, then Claude's code to paste.
        scroll_to(&mut h, "provider_claude_accounts_add_1");
        h.click("provider_claude_accounts_add_1");
        h.frames(10);
        assert_eq!(h.text("sign_in_status"), "Starting sign-in…");
        assert!(appear(&mut h, "sign_in_code"));
        h.frames(10);
        snapshot(&h, "sign_in_code");
        h.type_text("sign_in_code", "short");
        h.click("sign_in_submit");
        h.frames(2);
        assert_eq!(h.text("sign_in_submit"), "Verifying…");
        assert!(appear(&mut h, "sign_in_error"));
        h.type_text("sign_in_code", "-and-now-long-enough");
        h.click("sign_in_submit");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sign_in_dialog").is_none()
        }));
        h.frames(20);
        assert!(
            h.find("provider_claude_accounts_3").is_some(),
            "a third login"
        );
        // Cursor: its first sign-in fails; Retry gets it.
        h.click("provider_claude_trigger");
        h.frames(20);
        scroll_to(&mut h, "provider_cursor_switch");
        h.click("provider_cursor_switch");
        h.frames(10);
        h.click("provider_cursor_trigger");
        h.frames(20);
        scroll_to(&mut h, "provider_cursor_accounts_add_1");
        assert_eq!(
            h.text("provider_cursor_accounts_add_1"),
            "Connect a Cursor account"
        );
        h.click("provider_cursor_accounts_add_1");
        assert!(appear(&mut h, "sign_in_retry"));
        assert!(says(
            &mut h,
            "Couldn't start the sign-in: cursor-agent did not answer"
        ));
        h.click("sign_in_retry");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sign_in_dialog").is_none()
        }));
        h.frames(20);
        assert!(h.find("provider_cursor_accounts_1").is_some());
        // Cloud: its two providers, no switches, their accounts counted.
        scroll_to(&mut h, "providers_device");
        h.click("providers_device");
        h.frames(10);
        h.click("providers_device_cloud");
        h.frames(20);
        assert!(h.find("provider_cursor").is_none());
        assert!(h.find("provider_claude_switch").is_none());
        assert!(joined(&mut h, "provider_claude").contains("1 account"));
        assert!(joined(&mut h, "provider_codex").contains("No account"));
        healthy(&h);
    });
}

/// Devices (devices.rs): this one and the others with their presence;
/// Copy ID says Copied; Rename renames.
#[test]
fn devices_copy_their_ids_and_rename() {
    deep(|| {
        let mut h = desktop_app();
        let desktop = h.desktop.clone().unwrap();
        cmd(&mut h, ",", false);
        h.click("settings_nav_devices");
        h.frames(20);
        assert!(says(&mut h, "This device"));
        assert!(says(&mut h, "Other devices"));
        assert!(says(&mut h, "Last seen 2d ago"));
        assert!(says(&mut h, "Online"));
        h.click("device_mac_mini_copy");
        h.frames(4);
        assert_eq!(h.text("device_mac_mini_copy"), "Copied");
        assert_eq!(desktop.clipboard(), "4a90e2bb-7d13-4f0e-a1c6-92d5e8b37f10");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("device_mac_mini_copy") == "Copy ID"
        }));
        h.click("device_mac_mini_rename");
        h.frames(30);
        assert!(says(&mut h, "Rename device"));
        replace_text(&mut h, "device_rename_name", "Studio Mac");
        h.key(Key::Enter);
        h.frames(30);
        assert!(h.find("device_studio_mac").is_some());
        assert!(h.find("device_mac_mini").is_none());
    });
}

/// Archived sessions (archived.rs): 40 a page, Previous and Next;
/// Unarchiving… then gone; Delete all asks, then "Nothing archived".
#[test]
fn archived_sessions_page_unarchive_and_delete() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_archived");
        h.frames(20);
        assert_eq!(h.text("archived_count"), "585");
        assert_eq!(h.text("archived_range"), "1–40 of 585");
        assert!(h.find("archived_41").is_none());
        scroll_to(&mut h, "archived_next");
        h.click("archived_next");
        h.frames(20);
        assert_eq!(h.text("archived_range"), "41–80 of 585");
        assert!(h.find("archived_41").is_some());
        scroll_to(&mut h, "archived_previous");
        h.click("archived_previous");
        h.frames(20);
        scroll_to(&mut h, "archived_1_unarchive");
        h.click("archived_1_unarchive");
        h.frames(2);
        assert_eq!(h.text("archived_1_unarchive"), "Unarchiving…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("archived_count") == "584"
        }));
        scroll_to(&mut h, "archived_delete_all");
        h.click("archived_delete_all");
        h.frames(30);
        assert!(says(&mut h, "Delete all archived sessions?"));
        h.click("archived_delete_confirm");
        h.frames(4);
        assert_eq!(h.text("archived_delete_all"), "Deleting…");
        assert!(appear(&mut h, "archived_empty"));
        assert!(says(&mut h, "Nothing archived"));
        healthy(&h);
    });
}

/// Enabling sync (shell.rs v0.2.129 setup pages): the browser, the offer,
/// bringing this device's work over session by session, done; a failed
/// import retried; a switch that cannot happen in place asks for a
/// restart; a sign-out that cannot close the workspace offers local mode.
#[test]
fn sync_brings_the_work_over_and_recovers_from_failures() {
    deep(|| {
        let mut h = app();
        let local = |h: &mut Harness| {
            h.click("side_account");
            h.frames(20);
            h.click("side_account_sign_out");
            h.frames(20);
            h.click("signout-confirm");
            assert!(h.wait_until(|h| {
                h.frames(1);
                h.text("side_account_label") == "Local"
            }));
            h.frames(30);
        };
        let offer = |h: &mut Harness| {
            h.click("side_account");
            h.frames(20);
            h.click("side_account_enable_sync");
            assert!(appear(h, "sync_offer"));
            h.frames(30);
        };
        local(&mut h);
        // Cancelled while the browser is out: back to local.
        h.click("side_account");
        h.frames(20);
        h.click("side_account_enable_sync");
        h.frames(20);
        healthy(&h);
        assert!(says(&mut h, "Finish logging in"), "{:?}", h.texts());
        h.click("sync_cancel");
        h.frames(10);
        assert!(says(&mut h, "Canceling sign-in"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sync").is_none()
        }));

        offer(&mut h);
        assert!(says(&mut h, "Signed in as gael@zeron.dev"));
        snapshot(&h, "sync_offer");
        h.click("sync_bring_work");
        h.frames(10);
        assert!(says(&mut h, "Setting up sync"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t.starts_with("Importing session "))
        }));
        snapshot(&h, "sync_importing");
        assert!(appear(&mut h, "sync_done"));
        assert!(says(&mut h, "Your work is synced"));
        h.frames(30);
        h.click("sync_continue");
        h.frames(30);
        assert!(h.find("sync").is_none(), "{:?}", h.texts());
        assert_ne!(h.text("side_account_label"), "Local");

        // An import that fails: Later puts it off, the menu brings it
        // back, Retry copies what is missing.
        local(&mut h);
        run_command(&mut h, "Fail the next");
        offer(&mut h);
        h.click("sync_bring_work");
        assert!(appear(&mut h, "sync_import_failed"));
        assert!(h.text("sync_error").contains("1 failure"));
        h.click("sync_later");
        h.frames(30);
        assert!(h.find("sync").is_none());
        h.click("side_account");
        h.frames(20);
        h.click("side_account_sync_restart");
        h.frames(20);
        h.click("sync_retry_import");
        assert!(appear(&mut h, "sync_done"));
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("1 session imported, ") && t.ends_with(" already present.")),
            "{:?}",
            h.texts()
        );
        h.click("sync_continue");
        h.frames(30);

        // Starting fresh with the switch failing: a restart finishes it.
        local(&mut h);
        run_command(&mut h, "Fail the next");
        offer(&mut h);
        h.click("sync_start_fresh");
        assert!(appear(&mut h, "sync_restart"));
        h.click("sync_quit");
        h.frames(2);
        assert_eq!(h.text("sync_quit"), "Stopping engine…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sync").is_none()
        }));

        // Signing out without closing the workspace: Retry local mode.
        run_command(&mut h, "Fail the next");
        h.click("side_account");
        h.frames(20);
        h.click("side_account_sign_out");
        h.frames(20);
        h.click("signout-confirm");
        assert!(appear(&mut h, "sync_signed_out"));
        snapshot(&h, "sync_signed_out");
        h.click("sync_retry_local");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sync").is_none()
        }));
        assert_eq!(h.text("side_account_label"), "Local");
        // At rest, nothing runs.
        h.frames(30);
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
        healthy(&h);
    });
}

/// A right-pane tab's menu (Close tab, Close other tabs, Close tabs to
/// the left and right, inert where none would close), and its tabs
/// dragged along the strip, a copy following the pointer.
#[test]
fn the_right_panes_tabs_close_from_their_menu_and_drag_to_reorder() {
    deep(|| {
        let mut h = app();
        let ids = |h: &mut Harness| {
            ["zp_tab_changes", "zp_tab_zgx", "zp_tab_preview"]
                .iter()
                .filter(|id| h.find(id).is_some())
                .count()
        };
        assert_eq!(ids(&mut h), 3);
        if h.bounds("zcols_right").width < 0.5 {
            h.click("zeron_pane_toggle");
            h.frames(40);
        }
        secondary(&mut h, "zp_tab_changes");
        h.frames(20);
        assert!(h.texts().iter().any(|t| t == "Close tabs to the right"));
        // Nothing to its left.
        h.click("zp_tab_menu_left");
        h.frames(20);
        assert_eq!(ids(&mut h), 3);
        h.key(Key::Escape);
        h.frames(20);
        // Dragged past the others, it ends the strip.
        use zgx::input::PointerButton::Primary;
        let (from, to) = (h.bounds("zp_tab_changes"), h.bounds("zp_tab_preview"));
        let (x, y) = (from.x + 30., from.y + from.height / 2.);
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: Primary,
        });
        let end = to.x + to.width - 10.;
        for step in 1..=12 {
            let k = step as f32 / 12.;
            h.ui.dispatch(InputEvent::PointerMove {
                x: x + (end - x) * k,
                y,
            });
            h.frames(2);
        }
        assert_eq!(h.opacity("zp_tab_changes"), 0., "its place, empty");
        snapshot(&h, "pane_tab_drag");
        h.ui.dispatch(InputEvent::PointerUp {
            x: end,
            y,
            button: Primary,
        });
        h.frames(30);
        healthy(&h);
        assert!(h.bounds("zp_tab_changes").x > h.bounds("zp_tab_preview").x);
        // Close the others.
        secondary(&mut h, "zp_tab_changes");
        h.frames(20);
        h.click("zp_tab_menu_others");
        h.frames(30);
        assert_eq!(ids(&mut h), 1);
        assert!(h.find("zp_tab_changes").is_some());
    });
}

/// Chimes and desktop banners (sound.rs, desktop_notify.rs): a background
/// session's run finishing, asking and failing, and the connection lost,
/// each chime Zeron's sound and post a banner while the app is in the
/// background; focused, banners wait (unless asked for), and Sounds off
/// keeps them quiet. Nothing plays or shows for real.
#[test]
fn runs_and_the_connection_chime_and_post_banners_in_the_background() {
    deep(|| {
        let mut h = started(Harness::with_desktop(host));
        let desktop = h.desktop.clone().unwrap();
        let run = |h: &mut Harness, id: &str| {
            let label = match id {
                "engine_run_done" => "finish a run",
                "engine_run_input" => "ask for input",
                "engine_run_failed" => "fail a run",
                "engine_offline" => "go offline",
                _ => "sample engine: reconnect",
            };
            cmd(h, "k", false);
            h.type_text("palette_input", label);
            h.frames(10);
            h.click(&format!("palette_{id}"));
            h.frames(10);
            healthy(h);
        };
        let sounds = |d: &zgx_script::testing::FakeDesktop| {
            d.played()
                .iter()
                .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
                .collect::<Vec<_>>()
        };
        // (Agent updates post their own, a second after launch.)
        let banners = |d: &zgx_script::testing::FakeDesktop| {
            d.notified()
                .iter()
                .filter(|n| !n.title.contains("agent update"))
                .map(|n| format!("{}: {}", n.title, n.body))
                .collect::<Vec<_>>()
        };
        // Focused: the chime, no banner.
        run(&mut h, "engine_run_done");
        assert_eq!(sounds(&desktop), ["done.wav"]);
        assert!(banners(&desktop).is_empty());
        // In the background: banners too.
        desktop.set_active(false);
        run(&mut h, "engine_run_input");
        run(&mut h, "engine_run_failed");
        assert_eq!(sounds(&desktop)[1..], ["request.wav", "attention.wav"]);
        assert_eq!(
            banners(&desktop),
            [
                "Write the release notes: Waiting on your input",
                "Write the release notes: Run failed"
            ]
        );
        // The connection lost: one more.
        h.frames(30);
        run(&mut h, "engine_offline");
        assert_eq!(
            banners(&desktop).last().unwrap(),
            "Connection unavailable: Your device is offline"
        );
        // Sounds off: banners only.
        let played = desktop.played().len();
        open_settings(&mut h, "notifications");
        h.click("settings_session_sounds");
        h.frames(5);
        close_settings(&mut h);
        run(&mut h, "engine_connected");
        run(&mut h, "engine_run_done");
        assert_eq!(desktop.played().len(), played);
        assert_eq!(
            banners(&desktop).last().unwrap(),
            "Write the release notes: Run finished"
        );
        // A banner clicked opens its chat (lib.rs
        // open_notification_target); the connection's opens nothing.
        h.click("agent_a3");
        h.frames(40);
        let at = |d: &zgx_script::testing::FakeDesktop, title: &str| {
            d.notified().iter().position(|n| n.title == title).unwrap()
        };
        let shown = h.text("ztitle_title");
        desktop.click_notification(at(&desktop, "Connection unavailable"));
        h.frames(20);
        assert_eq!(h.text("ztitle_title"), shown, "nothing to open");
        desktop.click_notification(at(&desktop, "Write the release notes"));
        h.frames(40);
        healthy(&h);
        assert_eq!(h.text("ztitle_title"), "Write the release notes");
    });
}

/// Home's agent-update island (shell/harness_updates.rs): four updates
/// as a pill, opening into their list; Update steps through to Updated,
/// a failed download retries, View steps opens Settings → Harnesses,
/// Check again finds one; a banner a second after they are found.
#[test]
fn home_shows_agent_updates_and_steps_them_through() {
    deep(|| {
        // In the background from the start: the banner a second on posts.
        let desktop = std::rc::Rc::new(zgx_script::testing::FakeDesktop::default());
        desktop.set_active(false);
        let service = zgx::platform::PlatformService(desktop.clone());
        let mut h = started(Harness::wrapped(host, move |view| {
            zgx::compose::provide(service, view)
        }));
        cmd(&mut h, "n", false);
        h.frames(30);
        assert!(h.find("update_card").is_some(), "on Home");
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "4 agent updates · MacBook Pro"),
            "{:?}",
            h.texts()
        );
        let found = h.wait_until(|h| {
            h.frames(1);
            !desktop.notified().is_empty()
        });
        assert!(found, "the banner");
        assert_eq!(desktop.notified()[0].title, "3 agent updates available");
        // Clicked, it opens Settings on the agents' page.
        desktop.click_notification(0);
        h.frames(30);
        assert!(h.find("settings").is_some(), "Settings");
        assert!(
            h.find("provider_opencode_install").is_some(),
            "on the agents' page"
        );
        h.key(Key::Escape);
        h.frames(30);
        h.click("update_summary");
        h.frames(30);
        assert!(h.find("update_row_claude").is_some());
        assert_eq!(h.text("update_detail_claude"), "2.1.3 → 2.1.4");
        snapshot(&h, "agent_updates");
        h.click("update_row_action_claude");
        h.frames(5);
        assert_eq!(h.text("update_detail_claude"), "Preparing update…");
        assert_eq!(h.text("update_row_action_claude"), "Cancel");
        let updated = h.wait_until(|h| {
            h.frames(1);
            h.find("update_detail_claude").is_some()
                && h.text("update_detail_claude") == "Updated to 2.1.4"
        });
        assert!(updated, "{:?}", h.texts());
        // Codex's download breaks off: it retries.
        h.click("update_row_action_codex");
        let failed = h.wait_until(|h| {
            h.frames(1);
            h.text("update_detail_codex") == "The download was interrupted"
        });
        assert!(failed);
        assert_eq!(h.text("update_row_action_codex"), "Retry update");
        // A check that failed checks again.
        // (Half of the fourth row shows, three and a half fitting.)
        let b = h.bounds("update_row_action_opencode");
        let (x, y) = (b.x + b.width / 2., b.y + 4.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerUp { x, y, button });
        h.settle();
        let checked = h.wait_until(|h| {
            h.frames(1);
            h.find("update_detail_opencode").is_some()
                && h.text("update_detail_opencode") == "1.4.0 → 1.4.2"
        });
        assert!(
            checked,
            "{:?}",
            h.texts()
                .iter()
                .skip_while(|t| !t.contains("agent"))
                .collect::<Vec<_>>()
        );
        // View steps: Settings → Harnesses.
        h.click("update_row_action_cursor");
        h.frames(30);
        assert!(h.find("settings").is_some());
        healthy(&h);
    });
}

/// The engine out of reach (shell.rs render_gate_card): its error and
/// Retry in the window's place; Retry shows nothing until it answers.
#[test]
fn an_unreachable_engine_shows_its_error_and_retry() {
    deep(|| {
        let mut h = app();
        run_command(&mut h, "Become unreachable");
        assert!(h.find("engine_gate").is_some());
        assert!(says(
            &mut h,
            "Could not reach the zeron engine on port 27901"
        ));
        // It covers the window: a press on the titlebar's + reaches nothing.
        h.click("ztitle_new");
        h.frames(20);
        snapshot(&h, "engine_gate");
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls, "idle");
        h.click("engine_retry");
        assert!(appear(&mut h, "engine_loading"), "nothing while it tries");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("sync").is_none()
        }));
        h.frames(30);
        assert!(h.find("canvas").is_none(), "nothing beneath took the press");
        h.click("ztitle_new");
        h.frames(30);
        assert!(h.find("canvas").is_some(), "the app again");
        healthy(&h);
    });
}

/// Pins stop at Zeron's limit, a toast saying so; the row stays where it
/// was.
#[test]
fn pins_stop_at_the_limit() {
    deep(|| {
        let mut h = started(Harness::new(|runtime| {
            let host = host(runtime);
            host.shared("pin_limit", 2.);
            host
        }));
        let pinned = h.texts().iter().filter(|t| *t == "Pinned").count();
        assert!(pinned > 0);
        secondary(&mut h, "agent_a3");
        h.frames(20);
        h.click("agent_a3_menu_pin");
        h.frames(20);
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "You can pin up to 2 sessions"),
            "{:?}",
            h.texts()
        );
        healthy(&h);
    });
}

fn has_text(h: &mut Harness, wanted: &str) -> bool {
    h.texts().iter().any(|t| t.contains(wanted))
}

fn shift() -> Modifiers {
    Modifiers {
        shift: true,
        ..Default::default()
    }
}

/// A session waiting on input asks its questions in the composer's place
/// (composer.rs render_wizard): paged with a counter, a single choice going
/// on by itself, a multiple one ("Select one or more options.") picked by
/// its numbers, Back, a typed answer over the picked ones; answered, the
/// composer comes back as it was and the answers go.
#[test]
fn a_question_pages_through_its_questions_in_the_composers_place() {
    deep(|| {
        let mut h = app();
        h.click("agent_a2");
        h.frames(30);
        healthy(&h);
        assert!(h.find("composer_question").is_some(), "the panel");
        assert!(h.find("composer_box").is_none(), "in the pill's place");
        assert_eq!(h.text("composer_question_counter"), "1/3");
        assert!(has_text(&mut h, "Which node should own the root's insets?"));
        // A single choice goes on by itself.
        h.click("composer_question_option_2");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("composer_question_counter") == "2/3"
        }));
        assert!(has_text(&mut h, "Select one or more options."));
        snapshot(&h, "question");
        // Its numbers pick while the answer is empty; several stay picked.
        h.key(Key::Character("1".into()));
        h.key(Key::Character("4".into()));
        h.frames(10);
        assert_eq!(
            h.text("composer_question_counter"),
            "2/3",
            "a multiple choice waits"
        );
        h.click("composer_question_back");
        h.frames(10);
        assert_eq!(h.text("composer_question_counter"), "1/3");
        h.click("composer_question_next");
        h.frames(10);
        h.click("composer_question_next");
        h.frames(10);
        assert_eq!(h.text("composer_question_counter"), "3/3");
        // A typed answer wins over the options.
        h.type_text("composer_question_answer", "Just one line");
        h.click("composer_question_next");
        h.frames(30);
        healthy(&h);
        assert!(h.find("composer_question").is_none(), "answered");
        assert!(h.find("composer_box").is_some(), "the composer is back");
        let input = h.find("composer_input").unwrap();
        let draft = h.ui.editor(input).unwrap().value().get().to_string();
        assert_eq!(draft, "", "its draft as it was");
        assert!(h.find("sent_turn_1").is_some(), "the answers go");
        assert!(has_text(&mut h, "Layout, Native smokes"), "the picked ones");
        assert!(
            has_text(&mut h, "Release note: Just one line"),
            "the typed one"
        );
    });
}

/// Escape on the untouched first page closes the questions unanswered.
#[test]
fn escape_closes_an_untouched_question() {
    deep(|| {
        let mut h = app();
        h.click("agent_a2");
        h.frames(30);
        h.click("composer_question_answer");
        h.key(Key::Escape);
        h.frames(30);
        assert!(h.find("composer_question").is_none());
        assert!(h.find("sent_turn_1").is_none(), "nothing answered");
    });
}

/// The draft is Markdown as it is typed (composer_markdown.rs): a list goes
/// on at a line break and Tab and Shift+Tab indent and outdent its items;
/// a pasted reference resolves into a chip showing its file's name.
#[test]
fn the_draft_edits_markdown_and_resolves_pasted_references() {
    deep(|| {
        let mut h = app();
        h.type_text("composer_input", "- one");
        h.key_with(Key::Enter, shift());
        h.frames(10);
        assert_eq!(h.text("composer_input"), "- one\n- ");
        h.key(Key::Tab);
        assert_eq!(h.text("composer_input"), "- one\n  - ");
        h.key_with(Key::Tab, shift());
        assert_eq!(h.text("composer_input"), "- one\n- ");
        // Its bullet shows typographic, its bold in bold.
        h.ui.dispatch(InputEvent::Text("a **b**".into()));
        h.key_with(Key::Enter, shift());
        h.frames(10);
        let rich = {
            let input = h.find("composer_input").unwrap();
            let scene = h.ui.scene.borrow();
            let mut stack = vec![input];
            let mut found = None;
            while let Some(n) = stack.pop() {
                if let zgx::scene::NodeKind::RichText { text } = scene.kind(n) {
                    found = Some((**text).clone());
                }
                stack.extend(scene.children(n).iter().copied());
            }
            found.expect("the draft shows its runs")
        };
        assert!(rich.text().starts_with("• one\n• a b"), "{:?}", rich.text());
        assert!(rich.runs().iter().any(|r| r.font.weight >= 700));
        snapshot(&h, "markdown_draft");
        // A pasted reference is a chip at once.
        let editor = h.ui.focused_editor().expect("the draft");
        editor.paste("@crates/zgx/src/layout.rs");
        h.frames(5);
        assert!(
            h.text("composer_input")
                .ends_with("@crates/zgx/src/layout.rs ")
        );
        assert!(editor.editor.borrow_mut().undo());
        assert!(
            !editor.editor.borrow().text().contains("layout.rs"),
            "one undo step"
        );
    });
}

/// The composer's error strip (composer.rs failure): the sample engine's
/// failures say what went wrong over the pill, a click dismisses one; a
/// failed send keeps the message; offline with a draft, a caption says it
/// waits.
#[test]
fn the_composer_says_what_failed_and_waits_offline() {
    deep(|| {
        let mut h = app();
        run_command(&mut h, "fail the next send");
        h.type_text("composer_input", "Hello");
        h.click("composer_send");
        h.frames(10);
        assert!(has_text(&mut h, "Send failed"));
        snapshot(&h, "send_failed");
        assert_eq!(h.text("composer_input"), "Hello", "the message is kept");
        h.click("composer_failure");
        h.frames(20);
        assert!(!has_text(&mut h, "Send failed"), "dismissed");
        run_command(&mut h, "fail the next upload");
        h.click("composer_add");
        h.frames(10);
        assert!(has_text(
            &mut h,
            "Couldn't upload the attachment — the device may be offline."
        ));
        run_command(&mut h, "go offline");
        assert!(h.find("composer_offline").is_some(), "the caption");
        assert!(has_text(
            &mut h,
            "Offline — messages will send when you're back online."
        ));
        run_command(&mut h, "reconnect");
        assert!(h.find("composer_offline").is_none());
    });
}

/// The queue (queue.rs): a row's primary action by what it holds and the
/// harness (Steer for Claude's text, Send now with attachments), its
/// image's thumbnail opening the viewer, Edit moving it into the composer
/// while its row keeps its place, and rows dragged into a new order.
#[test]
fn queued_messages_edit_in_the_composer_reorder_and_show_their_images() {
    deep(|| {
        let mut h = app();
        h.type_text("composer_input", "First");
        h.click("composer_send");
        h.frames(10);
        h.click("composer_add");
        h.frames(20);
        h.type_text("composer_input", "Second");
        h.click("composer_send");
        h.frames(20);
        h.type_text("composer_input", "Third");
        h.click("composer_send");
        h.frames(10);
        // Stopped, the run sends nothing more by itself.
        h.click("composer_send");
        h.frames(20);
        assert_eq!(h.text("composer_queue_q1_send"), "Send now");
        assert_eq!(h.text("composer_queue_q2_send"), "Steer");
        snapshot(&h, "queue");
        // A staged image's click and a row's thumbnail open the viewer.
        h.click("composer_queue_q1_image_1");
        h.frames(20);
        assert!(h.find("image_viewer").is_some(), "the viewer");
        h.key(Key::Escape);
        h.frames(30);
        // Edit: the message fills the composer, the draft waits.
        h.type_text("composer_input", "half typed");
        h.click("composer_queue_q2_edit");
        h.frames(20);
        assert_eq!(h.text("composer_input"), "Third");
        assert!(has_text(&mut h, "Editing in composer"));
        h.click("composer_input");
        h.ui.dispatch(InputEvent::Text(" and more".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(20);
        assert!(has_text(&mut h, "Third and more"), "saved to the queue");
        assert_eq!(h.text("composer_input"), "half typed", "the draft is back");
        // Cancel leaves the row as it was.
        h.click("composer_queue_q2_edit");
        h.frames(10);
        h.click("composer_queue_q2_cancel");
        h.frames(10);
        assert!(has_text(&mut h, "Third and more"));
        // Dragged above the first, it goes first.
        drag_row(&mut h, "composer_queue_q2", "composer_queue_q1", 4., |_| {});
        let (q1, q2) = (h.bounds("composer_queue_q1"), h.bounds("composer_queue_q2"));
        assert!(q2.y < q1.y, "reordered: {q1:?} {q2:?}");
    });
}

/// The todo tray (todo_panel.rs): a long list folds to three around the
/// current item between "N earlier" and "N later", each shown in place;
/// Dismiss, while the turn rests, takes it away.
#[test]
fn a_long_todo_list_folds_and_dismisses() {
    deep(|| {
        let mut h = app();
        h.click("agent_a7");
        h.frames(30);
        h.click("todo_tray_header");
        h.frames(30);
        assert!(has_text(&mut h, "2 earlier"));
        assert!(has_text(&mut h, "3 later"));
        assert!(!has_text(&mut h, "Pin the Ubuntu runner"), "folded");
        h.click("todo_tray_earlier");
        h.frames(30);
        assert!(has_text(&mut h, "Pin the Ubuntu runner"), "shown in place");
        snapshot(&h, "todo_folds");
        h.click("todo_tray_dismiss");
        h.frames(30);
        assert!(h.find("todo_tray").is_none(), "dismissed");
    });
}

/// The new-session canvas's pickers (pickers.rs): the project searchable,
/// with "Don't work in a project" and Zeron's empty words; the devices;
/// the refs, capped with "Showing X of Y refs"; the checkout, its ref
/// then reading "From <ref>" for a new worktree.
#[test]
fn the_new_session_pickers_search_and_name_the_checkout() {
    deep(|| {
        let mut h = app();
        h.click("ztitle_new");
        h.frames(30);
        h.click("new_project");
        h.frames(20);
        assert!(has_text(&mut h, "Don't work in a project"));
        h.type_text("new_project_menu_search", "zzz");
        h.frames(10);
        assert_eq!(h.text("new_project_menu_empty"), "No projects match.");
        h.key(Key::Escape);
        h.frames(20);
        h.click("new_project");
        h.frames(20);
        h.click("new_project_menu_");
        h.frames(20);
        assert_eq!(h.text("new_project"), "No project");
        h.click("new_device");
        h.frames(20);
        assert!(
            h.find("new_device_menu_search").is_some(),
            "Search devices…"
        );
        h.click("new_device_menu_mac_studio");
        h.frames(20);
        assert_eq!(h.text("new_device"), "Mac Studio");
        h.click("new_branch");
        h.frames(20);
        assert_eq!(h.text("new_branch_menu_capped"), "Showing 300 of 335 refs");
        snapshot(&h, "refs");
        h.type_text("new_branch_menu_search", "layout");
        h.frames(10);
        h.key(Key::Enter);
        h.frames(20);
        assert_eq!(h.text("new_branch"), "layout-root");
        assert_eq!(h.text("new_checkout"), "Current worktree");
        h.click("new_checkout");
        h.frames(20);
        h.click("new_checkout_menu_worktree");
        h.frames(20);
        assert_eq!(h.text("new_checkout"), "New worktree");
        assert_eq!(h.text("new_branch"), "From layout-root");
    });
}

/// With Compact model picker off (Settings), the chip opens the full picker
/// (pickers.rs): the providers' strip and Starred, a search through every
/// provider, the model's settings under them; the chip reads its traits
/// ("High · 1M · Fast").
#[test]
fn the_full_model_picker_lists_providers_and_sets_the_traits() {
    deep(|| {
        let mut h = app();
        open_settings(&mut h, "general");
        h.click("pref_compact_picker");
        h.frames(5);
        close_settings(&mut h);
        h.click("composer_model");
        h.frames(30);
        assert!(h.find("zeron_models").is_some(), "the full picker");
        assert!(h.find("zeron_picker").is_none());
        assert!(
            h.find("zeron_models_model_opus").is_some(),
            "Claude's models"
        );
        snapshot(&h, "model_picker");
        h.click("zeron_models_tab_starred");
        h.frames(10);
        assert_eq!(
            h.text("zeron_models_empty"),
            "No starred models yet — hit a row's star"
        );
        h.type_text("zeron_models_search", "codex");
        h.frames(10);
        assert!(
            h.find("zeron_models_model_codex").is_some(),
            "found in any provider"
        );
        h.key_with(
            Key::Character("a".into()),
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.key(Key::Backspace);
        h.frames(10);
        h.click("zeron_models_tab_claude_code");
        h.frames(10);
        h.click("zeron_models_context");
        h.frames(20);
        h.click("zeron_models_context_1m_tokens");
        h.frames(20);
        h.click("zeron_models_tier");
        h.frames(20);
        h.click("zeron_models_tier_fast");
        h.frames(20);
        assert!(has_text(&mut h, "High · 1M · Fast"), "the chip's traits");
    });
}

/// The composer glides from the new-session canvas down to the thread it
/// starts (composer_dock.rs): one critically damped move, from where it
/// was to its dock, never past it.
#[test]
fn the_composer_glides_from_the_canvas_into_the_thread() {
    deep(|| {
        let mut h = app();
        h.click("ztitle_new");
        h.frames(30);
        let canvas = h.bounds("new_composer").y;
        h.type_text("new_composer_input", "Glide down");
        h.key(Key::Enter);
        let shown = |h: &mut Harness| {
            let node = h.find("composer").expect("the thread's composer");
            h.ui.scene.borrow().transformed_bounds(node).y
        };
        h.frame();
        let mut ys = vec![shown(&mut h)];
        for _ in 0..60 {
            h.frame();
            ys.push(shown(&mut h));
        }
        let rest = h.bounds("composer").y;
        assert!(rest > canvas + 100., "it docks lower: {canvas} {rest}");
        assert!(ys[0] < rest - 50., "it starts near the canvas: {ys:?}");
        assert!(
            ys.windows(2).all(|w| w[1] >= w[0] - 0.5),
            "it only descends: {ys:?}"
        );
        assert!(ys.iter().all(|y| *y <= rest + 0.5), "no overshoot: {ys:?}");
        assert!((ys.last().unwrap() - rest).abs() < 0.5, "at rest: {ys:?}");
    });
}

/// Settings search's hit `n`: its title (lit spans and all), then its trail.
fn hit(h: &mut Harness, n: usize) -> String {
    let node = h.find(&format!("settings_search_hit_{n}")).expect("a hit");
    let scene = h.ui.scene.borrow();
    let mut out = Vec::new();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        match scene.kind(n) {
            zgx::scene::NodeKind::Text { text, .. } => out.push(text.to_string()),
            zgx::scene::NodeKind::RichText { text, .. } => out.push(text.text().to_owned()),
            _ => {}
        }
        stack.extend(scene.children(n).iter().rev());
    }
    out.join(" | ")
}

/// Whether `id`'s box lies inside the settings page, clear of its edges.
fn in_page_view(h: &mut Harness, id: &str) -> bool {
    let b = h.bounds(id);
    b.y >= 38. && b.y + b.height <= HEIGHT
}

/// The glow lights the row holding `id`, once the page has landed on it.
fn lands_on(h: &mut Harness, id: &str) -> bool {
    let landed = h.wait_until(|h| {
        h.frames(1);
        h.opacity("settings_glow") > 0.5
    });
    let (glow, target) = (h.bounds("settings_glow"), h.bounds(id));
    landed && glow.y <= target.y + 0.5 && glow.y + glow.height >= target.y + target.height - 0.5
}

/// Settings search (settings/search.rs, shell/settings_search.rs): ⌘F
/// reaches the field; a query lists its hits where the sections were, each
/// over its page and block; Enter opens the page and lights the row, gliding
/// it into view; a typo still finds; a shortcut shows its binding and lands
/// on Shortcuts; a page opens at its top. Escape clears the query, then
/// leaves Settings; nothing found says so.
#[test]
fn settings_search_finds_a_setting_and_lands_on_it() {
    deep(|| {
        let mut h = app();
        open_settings(&mut h, "general");
        assert!(h.find("settings_nav_files").is_some());
        cmd(&mut h, "f", false);
        h.ui.dispatch(InputEvent::Text("wrap".into()));
        h.frames(10);
        healthy(&h);
        assert!(
            h.find("settings_nav_files").is_none(),
            "the hits in the sections' place"
        );
        assert!(hit(&mut h, 1).starts_with("Word wrap"));
        assert!(says(&mut h, "Files"), "its page under it");
        snapshot(&h, "settings_search");
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("settings_page_files").is_some(), "its page");
        assert!(lands_on(&mut h, "settings_word_wrap"), "lit");
        // The hits stay for the next pick: a typo, far down Appearance.
        h.key_with(Key::Character("a".into()), meta(false));
        h.ui.dispatch(InputEvent::Text("smoth scroling".into()));
        h.frames(10);
        assert!(hit(&mut h, 1).starts_with("Smooth scrolling"));
        assert!(says(&mut h, "Appearance · Motion"));
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("settings_page_appearance").is_some());
        assert!(lands_on(&mut h, "settings_smooth_scrolling"));
        assert!(
            in_page_view(&mut h, "settings_smooth_scrolling"),
            "glided into view"
        );
        // A shortcut, with its binding.
        h.key_with(Key::Character("a".into()), meta(false));
        h.ui.dispatch(InputEvent::Text("left sidebar".into()));
        h.frames(10);
        assert!(hit(&mut h, 1).contains("Toggle left sidebar"));
        assert!(says(&mut h, "Shortcuts · Panels"));
        h.click("settings_search_hit_1");
        h.frames(10);
        assert!(h.find("settings_page_shortcuts").is_some());
        assert!(lands_on(&mut h, "settings_shortcut_toggle_sidebar_chip"));
        // A page, at its top.
        h.key_with(Key::Character("a".into()), meta(false));
        h.ui.dispatch(InputEvent::Text("devices".into()));
        h.frames(10);
        assert_eq!(hit(&mut h, 1), "Devices");
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("settings_page_devices").is_some());
        // Nothing.
        h.key_with(Key::Character("a".into()), meta(false));
        h.ui.dispatch(InputEvent::Text("qqzzxx".into()));
        h.frames(10);
        assert!(says(&mut h, "No matching settings"));
        assert!(says(&mut h, "Try a setting, page, or shortcut."));
        // Escape clears the query, then leaves.
        h.key(Key::Escape);
        h.frames(10);
        assert!(h.find("settings_nav_files").is_some(), "the sections back");
        assert!(h.find("settings").is_some());
        h.key(Key::Escape);
        h.frames(30);
        assert!(h.find("settings").is_none(), "Settings left");
        // The next visit starts from the sections.
        cmd(&mut h, ",", false);
        h.frames(20);
        assert!(h.find("settings_nav_files").is_some());
        assert!(h.find("settings_search_hit_1").is_none());
        healthy(&h);
    });
}

/// General as v0.2.129's (settings/shortcuts.rs general_page,
/// settings/worktrees.rs): Send messages with, compact mode and picker,
/// Escape, Links, Thread naming, then the Git card: where new worktrees
/// go (a folder chosen in its browser, reset), each device's own (an old
/// one that cannot say, one set by ZERON_WORKTREES_DIR, Cloud's credit
/// always on), a load that fails and its Retry.
#[test]
fn general_has_zerons_rows_and_the_git_card() {
    deep(|| {
        let mut h = app();
        open_settings(&mut h, "general");
        for line in [
            "Send messages with",
            "Compact mode",
            "Compact model picker",
            "Stop agent with Escape",
            "Open pull requests in",
            "Thread naming",
            "Custom worktree location",
            "Credit Zeron in commits",
        ] {
            assert!(says(&mut h, line), "{line}");
        }
        assert!(!says(&mut h, "Confirm before quitting"));
        assert!(h.find("settings_nav_composer").is_none());
        assert!(h.find("settings_nav_worktrees").is_none());
        assert_eq!(h.text("pref_send"), "Enter");
        // Loaded: the default folder.
        scroll_to(&mut h, "git_custom");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "/Users/gael/.zeron/worktrees")
        }));
        assert!(says(
            &mut h,
            "Agents' commits add zeronsh[bot] as a co-author"
        ));
        // On: a folder to choose, in the browser.
        h.click("git_custom");
        h.frames(5);
        assert!(says(&mut h, "Choose a folder for new worktrees"));
        h.click("git_browse");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("git_folder_1").is_some()
        }));
        assert_eq!(h.text("git_browser_path"), "/Users/gael");
        h.click("git_folder_1");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("git_folder_3").is_some() && h.text("git_browser_path") == "/Users/gael/Code"
        }));
        h.click("git_use_folder");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "/Users/gael/Code")
        }));
        // Reset: the default again.
        h.click("git_reset");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "/Users/gael/.zeron/worktrees")
        }));
        // Another device: an old one cannot say, and offers Retry.
        h.click("git_device");
        h.frames(10);
        h.click("git_device_mac_mini");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "Couldn't load worktree settings")
        }));
        assert!(says(
            &mut h,
            "Update Zeron on the selected device to change this."
        ));
        assert!(h.find("git_retry").is_some());
        // One set by the environment.
        h.click("git_device");
        h.frames(10);
        h.click("git_device_build_box");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "Set by ZERON_WORKTREES_DIR")
        }));
        assert!(says(&mut h, "/srv/worktrees"));
        // Cloud: credit always on.
        h.click("git_device");
        h.frames(10);
        h.click("git_device_cloud");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "Always on for Cloud")
        }));
        // A load that fails, then Retry.
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "general");
        scroll_to(&mut h, "git_custom");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "Device is not connected")
        }));
        h.click("git_retry");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "Always on for Cloud")
        }));
        healthy(&h);
    });
}

/// Appearance as v0.2.129's: a light theme and a dark one, each picked
/// from its palette; the new-thread background (its tile and name, Replace
/// image, Remove; "Image unavailable" once its file is gone) and the
/// wallpaper folder with Shuffle and ⌘U's line. ⌘U without a folder says
/// to choose one.
#[test]
fn appearance_picks_light_and_dark_themes_and_the_background() {
    deep(|| {
        let mut h = app();
        // ⌘U, no folder yet: Appearance, and why.
        cmd(&mut h, "u", false);
        h.frames(20);
        assert!(h.find("settings_page_appearance").is_some());
        assert!(says(
            &mut h,
            "Choose a wallpaper folder in Appearance first."
        ));
        assert!(!says(&mut h, "Density"));
        assert!(!says(&mut h, "Effect"));
        // The themes.
        h.click("settings_dark_theme");
        h.frames(10);
        h.click("settings_dark_theme_dracula");
        h.frames(20);
        assert_eq!(&*h.ui.theme().current(), "dracula");
        assert_eq!(h.text("settings_dark_theme"), "Dracula");
        h.click("settings_light_theme");
        h.frames(10);
        h.click("settings_light_theme_catppuccin-latte");
        h.frames(20);
        assert_eq!(&*h.ui.theme().current(), "dracula", "dark stays shown");
        h.click("settings_mode_light");
        h.frames(20);
        assert_eq!(&*h.ui.theme().current(), "catppuccin-latte");
        h.click("settings_mode_dark");
        h.frames(20);
        // The toast goes in its time.
        assert!(h.wait_until(|h| {
            h.frames(1);
            !h.texts()
                .iter()
                .any(|t| t == "Choose a wallpaper folder in Appearance first.")
        }));
        // The background: none, chosen, lost, removed.
        scroll_to(&mut h, "settings_canvas_background");
        assert!(says(&mut h, "No image selected"));
        assert_eq!(h.text("settings_canvas_background"), "Choose image");
        h.click("settings_canvas_background");
        h.frames(10);
        assert_eq!(h.text("settings_canvas_background"), "Replace image");
        assert!(says(&mut h, "shadow"));
        assert!(h.find("settings_canvas_background_tile").is_some());
        close_settings(&mut h);
        run_command(&mut h, "Lose the background image");
        open_settings(&mut h, "appearance");
        scroll_to(&mut h, "settings_canvas_background");
        assert!(says(&mut h, "Image unavailable"));
        assert!(says(&mut h, "Choose a replacement or remove it."));
        assert!(!h.shown("settings_canvas_background_adjust"));
        h.click("settings_canvas_background_remove");
        h.frames(10);
        assert!(says(&mut h, "No image selected"));
        // The folder: ⌘U's line, Choose folder, Shuffle.
        assert!(h.texts().iter().any(|t| {
            t.starts_with("Choose a folder of wallpaper images. · ")
                && t.ends_with(" picks a random image")
        }));
        assert!(!h.shown("settings_wallpaper_shuffle"));
        scroll_to(&mut h, "settings_wallpaper_folder");
        h.click("settings_wallpaper_folder");
        h.frames(10);
        assert!(h.texts().iter().any(|t| {
            t.starts_with("~/Pictures/Wallpapers · ") && t.ends_with(" picks a random image")
        }));
        h.click("settings_wallpaper_shuffle");
        h.frames(10);
        assert_eq!(h.text("settings_canvas_background"), "Replace image");
        healthy(&h);
    });
}

/// Voice (dictation/model.rs): the speech model's Remove (refused while a
/// composer dictates), its download as dictation is turned on (progress,
/// then the microphone) and a failed one; a chosen microphone unplugged
/// stays chosen as "Disconnected microphone", and Codex's voice device gone
/// as "Unavailable device".
#[test]
fn voice_downloads_removes_and_follows_its_devices() {
    deep(|| {
        let mut h = app();
        // Dictating: the model stays. (⌘D tapped says "Hold to dictate";
        // the mic's click dictates until clicked again.)
        h.click("composer_mic");
        h.frames(10);
        assert!(h.find("composer_track").is_some());
        open_settings(&mut h, "voice");
        assert!(says(&mut h, "Runs Codex; audio stays on this device"));
        h.click("settings_speech_remove");
        h.frames(10);
        assert!(says(&mut h, "Stop dictation before removing the model."));
        close_settings(&mut h);
        h.click("composer_input");
        h.key_with(Key::Character("d".into()), meta(false));
        assert!(h.wait_until(|h| h.text("composer_input").contains("Windows")));
        // Removed (once its toast has gone): a download to turn dictation on.
        assert!(h.wait_until(|h| {
            h.frames(1);
            !h.texts()
                .iter()
                .any(|t| t == "Stop dictation before removing the model.")
        }));
        open_settings(&mut h, "voice");
        h.click("settings_speech_remove");
        h.frames(10);
        assert!(says(&mut h, "640 MB download"));
        assert!(h.find("settings_microphone").is_none());
        h.click("settings_dictation");
        h.frames(10);
        assert!(h.texts().iter().any(|t| t.starts_with("Downloading · ")));
        assert!(h.shown("voice_progress"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("settings_microphone").is_some()
        }));
        assert!(h.find("settings_speech_remove").is_some());
        // A download that fails.
        h.click("settings_speech_remove");
        h.frames(10);
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "voice");
        h.click("settings_dictation");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t.starts_with("Couldn’t download or verify the model."))
        }));
        assert!(says(&mut h, "640 MB download"));
        // Downloaded again; the USB microphone and the Build box chosen,
        // then gone.
        h.click("settings_dictation");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("settings_microphone").is_some()
        }));
        h.click("settings_microphone");
        h.frames(10);
        h.click("settings_microphone_3");
        h.frames(10);
        h.click("voice_host");
        h.frames(10);
        h.click("voice_host_3");
        h.frames(10);
        assert_eq!(h.text("voice_host"), "Build box");
        close_settings(&mut h);
        run_command(&mut h, "Unplug the USB microphone");
        open_settings(&mut h, "voice");
        assert_eq!(h.text("settings_microphone"), "Disconnected microphone");
        assert_eq!(h.text("voice_host"), "Unavailable device");
        healthy(&h);
    });
}

/// Appshots (settings/appshots.rs, appshots.rs): each permission's status;
/// the step that grants it, the system's prompt and then System Settings;
/// Check again reads them; a shortcut that cannot work system-wide is
/// refused.
#[test]
fn appshots_permissions_check_again_and_refuse_a_shortcut() {
    deep(|| {
        let mut h = desktop_app();
        let desktop = h.desktop.clone().unwrap();
        open_settings(&mut h, "appshots");
        assert_eq!(h.text("appshots_window_status"), "Ready");
        assert_eq!(h.text("appshots_text_status"), "Required");
        assert_eq!(h.text("appshots_text_access"), "Enable text capture");
        h.click("appshots_text_access");
        h.frames(5);
        assert_eq!(h.text("appshots_text_access"), "Open System Settings");
        h.click("appshots_check");
        h.frames(2);
        assert_eq!(h.text("appshots_text_status"), "Checking");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("appshots_text_status") == "Ready"
        }));
        assert!(!h.shown("appshots_text_access"));
        // Taken back: Allow window capture, then System Settings.
        close_settings(&mut h);
        run_command(&mut h, "Revoke capture permissions");
        open_settings(&mut h, "appshots");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.text("appshots_window_status") == "Required"
        }));
        assert_eq!(h.text("appshots_window_access"), "Allow window capture");
        h.click("appshots_window_access");
        h.frames(5);
        h.click("appshots_window_access");
        h.frames(5);
        assert_eq!(
            desktop.opened().last().map(String::as_str),
            Some("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        );
        // A shortcut with no modifier is refused.
        h.click("settings_appshot_key_chip");
        h.frames(5);
        assert_eq!(h.text("appshots_helper"), "Press Escape to cancel.");
        h.key(Key::Character("k".into()));
        h.frames(5);
        assert!(
            h.text("appshots_helper")
                .starts_with("Use Control, Option or Command with a letter")
        );
        healthy(&h);
    });
}

/// Providers' and accounts' states (settings/harnesses.rs, accounts.rs):
/// an update check that fails says so with Retry updates; an install that
/// fails; an update that fails; Auto when idle waits for the agent; Refresh
/// usage checks, and a refresh that fails offers Retry; a login signed out
/// says so.
#[test]
fn providers_and_accounts_show_their_failures_and_waits() {
    deep(|| {
        let mut h = app();
        // Settings reopens on Providers, the step left for its check.
        open_settings(&mut h, "harnesses");
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "harnesses");
        h.click("providers_check");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "Agent updates: Connection closed. Reconnecting to device…")
        }));
        h.click("providers_updates_retry");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v0.165.0")
        }));
        // An install that fails.
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "harnesses");
        h.click("provider_opencode_install");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts()
                .iter()
                .any(|t| t == "Installation failed — npm exited with code 1")
        }));
        // An update that fails, then Retry update.
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "harnesses");
        h.click("provider_claude_update");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v2.1.308 · Update failed")
        }));
        assert_eq!(h.text("provider_claude_update"), "Retry update");
        // Codex: Auto when idle waits for its runs, then updates itself.
        h.click("provider_codex_trigger");
        h.frames(20);
        scroll_to(&mut h, "provider_codex_policy");
        h.click("provider_codex_policy");
        h.frames(10);
        h.click("provider_codex_policy_2");
        h.frames(5);
        assert!(says(&mut h, "v0.164.0 · Waiting for agent to be idle"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.texts().iter().any(|t| t == "v0.165.0 · Updated")
        }));
        // Accounts: a login signed out; a refresh, then one that fails.
        close_settings(&mut h);
        run_command(&mut h, "Sign out a Claude login");
        open_settings(&mut h, "harnesses");
        if h.find("provider_claude_accounts_1").is_none() {
            h.click("provider_claude_trigger");
        }
        h.frames(20);
        scroll_to(&mut h, "provider_claude_accounts_refresh");
        assert!(says(&mut h, "Signed out — sign in again"));
        h.click("provider_claude_accounts_refresh");
        h.frames(2);
        assert!(h.shown("provider_claude_accounts_refreshing"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            !h.shown("provider_claude_accounts_refreshing")
        }));
        close_settings(&mut h);
        run_command(&mut h, "Fail the next settings step");
        open_settings(&mut h, "harnesses");
        h.click("provider_claude_trigger");
        h.frames(20);
        scroll_to(&mut h, "provider_claude_accounts_refresh");
        h.click("provider_claude_accounts_refresh");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("provider_claude_accounts_retry").is_some()
        }));
        h.click("provider_claude_accounts_retry");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("provider_claude_accounts_1").is_some()
        }));
        healthy(&h);
    });
}

/// A pull request opened from a chat (chat_pull_requests.rs): a reply's
/// link, a sidebar row's badge or the composer's badge opens that pull
/// request as a tab in the session's right pane (the tab it has, if any),
/// the session staying on screen; where General sends pull requests to a
/// browser tab or the default browser, they go there.
#[test]
fn pull_requests_open_beside_the_chat_from_links_and_badges() {
    deep(|| {
        let mut h = desktop_app();
        let desktop = h.desktop.clone().unwrap();
        h.click("agent_a2");
        h.frames(30);
        // The reply's link, scrolled into the transcript's view.
        let link = |h: &mut Harness| {
            let (b, at) = (h.bounds("role:link \"#398\""), h.bounds("composer"));
            h.ui.dispatch(InputEvent::Scroll {
                x: at.x + at.width / 2.,
                y: 300.,
                delta_x: 0.,
                delta_y: b.y + b.height / 2. - 300.,
            });
            h.frames(10);
            h.click("role:link \"#398\"");
            h.frames(30);
        };
        link(&mut h);
        healthy(&h);
        assert_eq!(h.text("zp_tab_pr_1"), "Rebase onto the new layout root");
        arrives(&mut h, "pr_overview");
        assert_eq!(h.text("pr_detail_title"), "Rebase onto the new layout root");
        assert_eq!(h.text("ztitle_title"), "Refactor the layout engine");
        snapshot(&h, "pr_beside_chat");

        // Another row's badge: its pull request, beside this session.
        h.click("agent_a4_pr");
        h.frames(30);
        healthy(&h);
        assert_eq!(h.text("zp_tab_pr_2"), "Durable Object token vault");
        assert_eq!(h.text("ztitle_title"), "Refactor the layout engine");

        // The composer's badge: the session's own, its tab brought forward.
        h.click("composer_pr");
        h.frames(30);
        assert!(h.find("zp_tab_pr_3").is_none(), "one tab a pull request");
        arrives(&mut h, "pr_overview");
        assert_eq!(h.text("pr_detail_title"), "Rebase onto the new layout root");

        // A browser tab, then the default browser, as General says.
        let send_to = |h: &mut Harness, option: &str| {
            cmd(h, ",", false);
            h.click("settings_nav_general");
            h.frames(20);
            h.click("settings_open_prs");
            h.frames(10);
            h.click(option);
            h.frames(10);
            h.key(Key::Escape);
            h.frames(30);
        };
        send_to(&mut h, "settings_open_prs_2");
        link(&mut h);
        assert!(h.find("zp_tab_preview_3").is_some(), "a browser tab");
        send_to(&mut h, "settings_open_prs_3");
        let before = desktop.opened().len();
        h.click("agent_a4_pr");
        h.frames(10);
        assert_eq!(
            desktop.opened()[before..],
            ["https://github.com/zeron/comet/pull/971"]
        );
        assert!(h.find("zp_tab_pr_3").is_none());
        healthy(&h);
    });
}

/// Settings at `section`, opening it if it is closed.
fn settings_at(h: &mut Harness, section: &str) {
    if h.find("settings").is_none() {
        cmd(h, ",", false);
    }
    h.click(&format!("settings_nav_{section}"));
    h.frames(30);
    healthy(h);
}

/// A ⌘K command with Settings closed (it covers the palette).
fn sample(h: &mut Harness, query: &str) {
    if h.find("settings").is_some() {
        h.key(Key::Escape);
        h.frames(30);
    }
    run_command(h, query);
}

/// Waits (in real time: the sample engine answers after a moment) until
/// `what` shows.
fn until_says(h: &mut Harness, what: &str) {
    let shown = h.wait_until(|h| {
        h.frames(1);
        h.texts().iter().any(|t| t == what)
    });
    assert!(shown, "{what:?} never showed: {:?}", h.texts());
    healthy(h);
}

/// The front toast's action, if one shows.
fn toast_action(h: &mut Harness) -> Option<String> {
    (1..40)
        .map(|n| format!("toast{n}_action"))
        .find(|id| h.find(id).is_some())
}

/// Settings → Cloud (settings/cloud.rs v0.2.129), shown while the account
/// is offered Cloud: no row of its own while Cloud is simply on; usage
/// over the range chosen, a bar a day; GitHub's repositories (six, then
/// how many more), Disconnect, and connecting again by device code (a
/// refusal says so and tries again). Turned off, it turns itself on again
/// as the page shows, a failure retrying what failed; its status out of
/// reach, Retry asks again. Without the offer, Cloud and Billing go.
#[test]
fn cloud_settings_turn_on_connect_by_code_and_show_usage() {
    deep(|| {
        let mut h = started(Harness::with_desktop(host));
        settings_at(&mut h, "cloud");
        assert!(h.find("settings_nav_billing").is_some());
        assert!(appear(&mut h, "cloud_page"));
        assert!(says(&mut h, "Run your agents in cloud sandboxes."));
        assert!(h.find("cloud_status").is_none(), "nothing to say");
        assert!(h.find("cloud_usage_bar_30").is_some() && h.find("cloud_usage_bar_31").is_none());
        assert!(says(&mut h, "96,210 credits left"));
        h.click("cloud_usage_range");
        h.frames(20);
        h.click("cloud_usage_range_1");
        h.frames(30);
        assert!(h.find("cloud_usage_bar_7").is_some() && h.find("cloud_usage_bar_8").is_none());
        assert!(says(&mut h, "Cloud sessions can open 8 repositories."));
        assert!(h.find("cloud_repo_6").is_some() && h.find("cloud_repo_7").is_none());
        assert!(says(&mut h, "and 2 more") && says(&mut h, "Private"));
        snapshot(&h, "settings_cloud");

        h.click("cloud_github_disconnect");
        h.frames(2);
        assert_eq!(h.text("cloud_github_disconnect"), "Removing…");
        until_says(&mut h, "Not connected");
        sample(&mut h, "Make Cloud's next step fail");
        settings_at(&mut h, "cloud");
        h.click("cloud_github_connect");
        h.frames(2);
        assert!(says(&mut h, "Contacting GitHub…"));
        assert!(appear(&mut h, "cloud_github_code_row"));
        assert!(says(&mut h, "Enter this code on GitHub"));
        h.click("cloud_github_code");
        h.frames(2);
        let desktop = h.desktop.clone().unwrap();
        assert_eq!(desktop.clipboard(), "WDJB-MJHT");
        h.click("cloud_github_open");
        until_says(&mut h, "GitHub didn't approve the connection.");
        assert_eq!(h.text("cloud_github_connect"), "Try again");
        h.click("cloud_github_connect");
        assert!(appear(&mut h, "cloud_github_code_row"));
        h.click("cloud_github_open");
        assert!(appear(&mut h, "cloud_repos"));
        assert!(says(&mut h, "gaelcado"));
        sample(&mut h, "GitHub needs reconnecting");
        settings_at(&mut h, "cloud");
        assert!(says(&mut h, "Needs reconnect"));
        assert_eq!(h.text("cloud_github_connect"), "Reconnect");

        // Off: it turns itself on as the page shows; GitHub, stored for
        // the Cloud that was, is allowed on this one with Connect.
        sample(&mut h, "Turn Cloud off");
        settings_at(&mut h, "cloud");
        until_says(&mut h, "Turning on…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("cloud_status").is_none()
        }));
        h.frames(20);
        h.click("cloud_github_authorize");
        h.frames(2);
        assert_eq!(h.text("cloud_github_authorize"), "Connecting…");
        assert!(appear(&mut h, "cloud_repos"));

        // Turning off fails: Retry turns it off again.
        sample(&mut h, "Make Cloud's next step fail");
        sample(&mut h, "Turn Cloud off");
        settings_at(&mut h, "cloud");
        until_says(&mut h, "A session's machine didn't stop");
        h.click("cloud_retry");
        h.frames(2);
        assert!(says(&mut h, "Turning off…"));
        until_says(&mut h, "Turning off Cloud…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("cloud_status").is_none()
        }));

        // Its status out of reach: only that, and Retry.
        sample(&mut h, "Lose Cloud's status");
        settings_at(&mut h, "cloud");
        assert!(says(&mut h, "Couldn't check Cloud: Engine not connected"));
        assert!(h.find("cloud_usage").is_none() && h.find("cloud_github").is_none());
        h.click("cloud_status_retry");
        assert!(appear(&mut h, "cloud_usage"));

        // Not offered: no Cloud, no Billing, General instead.
        sample(&mut h, "Offer Cloud, or stop offering it");
        cmd(&mut h, ",", false);
        assert!(h.find("settings_nav_cloud").is_none() && h.find("settings_nav_billing").is_none());
        assert!(h.find("cloud_page").is_none());
        sample(&mut h, "Offer Cloud, or stop offering it");
        settings_at(&mut h, "billing");
        assert!(h.find("billing_page").is_some());
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls, "idle");
    });
}

/// Settings → Billing (settings/billing.rs v0.2.129): the balance and the
/// hours it buys, plan and extra credits; the plans, the current one's
/// renewal and Manage subscription; packs bought in the browser, the page
/// waiting until they land (or Dismiss); no plan, a failed payment, a plan
/// ending, billing not set up, Stripe out of reach.
#[test]
fn billing_shows_credits_switches_plans_and_buys_packs() {
    deep(|| {
        let mut h = app();
        // Stripe out of reach: the page says so until clicked.
        run_command(&mut h, "Make Cloud's next step fail");
        settings_at(&mut h, "billing");
        assert!(appear(&mut h, "billing_page"));
        h.click("billing_buy");
        until_says(&mut h, "Couldn't reach Stripe: the request timed out");
        h.click("billing_error");
        h.frames(10);
        assert!(h.find("billing_error").is_none());
        assert!(says(&mut h, "96,210") && says(&mut h, "about 1,604 hours"));
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("Of 112,500 · resets "))
        );
        assert!(h.find("billing_plan_pro_current").is_some());
        assert_eq!(h.text("billing_plan_base_switch"), "Switch");
        assert!(says(&mut h, "Pro · $50 a month"));
        assert!(h.texts().iter().any(|t| t.starts_with("Renews ")));
        snapshot(&h, "settings_billing");

        // Packs: one at least, then three bought.
        h.click("billing_fewer");
        h.frames(5);
        assert_eq!(h.text("billing_packs"), "1");
        h.click("billing_more");
        h.click("billing_more");
        h.frames(5);
        assert_eq!(h.text("billing_packs"), "3");
        assert_eq!(h.text("billing_pack_credits"), "36,000 credits");
        assert_eq!(h.text("billing_buy"), "Buy for $30");
        h.click("billing_buy");
        h.frames(2);
        assert_eq!(h.text("billing_buy"), "Opening…");
        assert!(appear(&mut h, "billing_pending"));
        until_says(&mut h, "Added 36,000 credits");
        assert!(h.find("billing_pending").is_none());
        assert!(says(&mut h, "132,210"));

        // Another plan, through Stripe's portal.
        h.click("billing_plan_max_switch");
        until_says(&mut h, "You're on Max — 450,000 credits a month");
        assert!(h.find("billing_plan_max_current").is_some());
        // Manage subscription, put off.
        h.click("billing_manage");
        assert!(appear(&mut h, "billing_pending"));
        h.click("billing_pending_dismiss");
        h.frames(30);
        assert!(h.find("billing_pending").is_none());

        sample(&mut h, "Billing without a plan");
        settings_at(&mut h, "billing");
        assert!(says(&mut h, "No plan yet — choose one below"));
        assert!(says(&mut h, "Choose a plan or buy credits to run Cloud"));
        assert_eq!(h.text("billing_plan_base_choose"), "Choose Base");
        h.click("billing_plan_base_choose");
        until_says(&mut h, "You're on Base — 45,000 credits a month");

        sample(&mut h, "Billing with a failed payment");
        settings_at(&mut h, "billing");
        assert!(says(
            &mut h,
            "Your last payment didn't go through — update your card to keep your plan."
        ));
        sample(&mut h, "Billing with a plan ending");
        settings_at(&mut h, "billing");
        assert!(
            h.texts().iter().any(
                |t| t.starts_with("Ends ") && t.ends_with(". You keep its credits until then.")
            )
        );

        sample(&mut h, "Billing not set up on the server");
        settings_at(&mut h, "billing");
        assert!(says(
            &mut h,
            "Billing isn't set up on this server yet, so plans and credits can't be bought here."
        ));
        h.click("billing_buy");
        h.frames(40);
        assert!(h.find("billing_pending").is_none(), "nothing to buy here");
    });
}

/// Cloud elsewhere (cloud.rs, session_info.rs, files_panel.rs,
/// transcript.rs v0.2.129): a Cloud session's machine asleep in its card
/// and in Files (Wake up); out of credits, a send says so with the way to
/// Billing and keeps the draft; a send wakes the machine, or starts a new
/// one, and the working line says so.
#[test]
fn a_cloud_session_sleeps_wakes_and_runs_out_of_credits() {
    deep(|| {
        let mut h = app();
        h.click("thread_h3");
        h.frames(40);
        if h.find("z_session_card").is_none() {
            h.click("ztitle_card");
            h.frames(40);
        }
        assert!(h.text("z_device").starts_with("Cloud"));
        assert!(h.find("z_asleep").is_some());
        cmd(&mut h, "e", false);
        assert!(appear(&mut h, "files_cloud_asleep"));
        assert!(says(&mut h, "Cloud agent is asleep"));
        h.click("files_cloud_wake");
        h.frames(5);
        assert!(says(&mut h, "Waking up the Cloud agent…"));
        assert!(h.wait_until(|h| {
            h.frames(1);
            h.find("files_cloud_asleep").is_none()
        }));
        assert!(h.find("z_asleep").is_none(), "awake");

        // Out of credits: the send waits, saying why; Add credits opens
        // Billing.
        run_command(&mut h, "Run out of Cloud credits");
        h.type_text("composer_input", "Hi");
        h.click("composer_send");
        h.frames(10);
        assert!(says(
            &mut h,
            "You're out of Cloud credits. Add credits to send."
        ));
        assert_eq!(h.text("composer_input"), "Hi", "the draft kept");
        let action = toast_action(&mut h).expect("Add credits");
        assert_eq!(h.text(&action), "Add credits");
        h.click(&action);
        h.frames(30);
        assert!(appear(&mut h, "billing_page"));
        sample(&mut h, "Billing as it was");

        // Asleep again: the send wakes it first.
        run_command(&mut h, "Put the Cloud machine to sleep");
        h.click("composer_send");
        until_says(&mut h, "Waking the Cloud machine…");
        assert!(h.wait_until(|h| {
            h.frames(1);
            !h.texts().iter().any(|t| t == "Waking the Cloud machine…")
        }));
        healthy(&h);
    });
}

/// A Cloud session given a new machine starts it as a message goes.
#[test]
fn a_cloud_session_starts_a_new_machine_as_a_message_goes() {
    deep(|| {
        let mut h = app();
        h.click("thread_h3");
        h.frames(40);
        run_command(&mut h, "Give the Cloud session a new machine");
        h.type_text("composer_input", "Go");
        h.click("composer_send");
        until_says(&mut h, "Starting a Cloud machine…");
        healthy(&h);
    });
}

/// A prompt's Markdown shows in its bubble as a reply's would (code spans,
/// fences, links), folded past five lines as plain text is; a plain prompt
/// and one with references stay text (transcript.rs render_user_markdown).
#[test]
fn zeron_prompt_markdown_shows_in_the_bubble() {
    deep(|| {
        let mut h = app();
        to_top(&mut h);
        assert!(
            h.find("turn_1_prompt_md").is_none(),
            "a plain prompt stays text"
        );
        open_session(&mut h, "agent_a2");
        // "…the DPI fix changes `place` in layout.rs too": a code span.
        assert!(h.find("turn_1_prompt_md").is_some(), "its Markdown");
        assert!(!shows(&mut h, "`place`"), "not its backticks");
        open_session(&mut h, "agent_a7");
        to_top(&mut h);
        assert!(h.find("turn_1_prompt_md").is_some());
        assert_eq!(h.text("turn_1_prompt_expander"), "Show more", "folded");
        let folded = h.bounds("turn_1_prompt_body").height;
        h.click("turn_1_prompt_expander");
        h.frames(40);
        assert!(h.bounds("turn_1_prompt_body").height > folded, "it opens");
        open_session(&mut h, "agent_a4");
        to_top(&mut h);
        assert!(
            h.find("turn_1_prompt_md").is_none(),
            "references keep their chips"
        );
        healthy(&h);
    });
}

/// The provider switch's seam over the prompt that switched, and the
/// messages an agent sent other chats: "Message to" opening that chat,
/// "Couldn't message" naming one it could not reach.
#[test]
fn zeron_marker_switch_and_messages_to_other_chats() {
    deep(|| {
        let mut h = app();
        open_session(&mut h, "agent_a2");
        let seam = h.bounds("turn_2_prompt_switch");
        let bubble = h.bounds("turn_2_prompt");
        assert!(
            (seam.y - bubble.y).abs() < 0.5,
            "over the bubble: {seam:?} {bubble:?}"
        );
        assert!(says(&mut h, "Claude Code") && says(&mut h, "Codex"));

        open_session(&mut h, "agent_a3");
        to_top(&mut h);
        assert!(says(&mut h, "Message to"));
        assert!(says(&mut h, "Couldn't message"));
        assert!(says(&mut h, "Release checklist"), "the name it was given");
        into_view(&mut h, "turn_1_message_1");
        h.click("turn_1_message_1");
        h.frames(30);
        assert!(
            shows(&mut h, "Refactor the layout engine so a column"),
            "the chat it messaged"
        );
        healthy(&h);
    });
}

/// A run refused for want of signing in says why, and "Log in" opens
/// Settings → Providers on that provider's sign-in; another error offers
/// nothing (transcript.rs error_chip).
#[test]
fn zeron_signin_error_cards_offer_log_in() {
    deep(|| {
        let mut h = app();
        open_session(&mut h, "agent_a8");
        assert!(h.find("turn_1_error").is_some());
        assert!(h.find("turn_1_error_action").is_none(), "a plain error");
        open_session(&mut h, "agent_a4");
        assert!(says(&mut h, "Limit reached"));
        assert!(h.find("turn_2_error_action").is_some());
        open_session(&mut h, "agent_a5");
        assert!(says(&mut h, "Signed out"));
        assert_eq!(h.text("turn_2_error_action"), "Log in");
        into_view(&mut h, "turn_2_error_action");
        h.click("turn_2_error_action");
        h.frames(30);
        assert!(h.find("settings").is_some(), "Settings opens");
        assert!(h.find("sign_in_dialog").is_some(), "on its sign-in");
        assert!(shows(&mut h, "Sign in to Codex"));
        healthy(&h);
    });
}

/// Another device's chat while the connection is away: the loader says
/// what it waits on (offline, reconnecting, the replay) over a blank list,
/// then the history shows (transcript.rs render_loader).
#[test]
fn zeron_loader_waits_on_another_devices_chat() {
    deep(|| {
        let mut h = app();
        run_command(&mut h, "Go offline");
        open_session(&mut h, "agent_a8");
        assert!(h.find("turn_1_error").is_none(), "nothing yet");
        let caption = "transcript_loader_caption";
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.find(caption).is_some()
            }),
            "after a moment, the loader"
        );
        assert_eq!(
            h.text(caption),
            "Offline — this chat loads when you're back online"
        );
        run_command(&mut h, "Sample engine: Reconnect");
        let reconnecting = h.find(caption).is_some() && h.text(caption) == "Reconnecting…";
        assert!(
            reconnecting || h.find("turn_1_error").is_some(),
            "it reconnects"
        );
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.find("turn_1_error").is_some()
            }),
            "its history arrives"
        );
        h.frames(30);
        assert!(h.find(caption).is_none(), "the loader leaves");
        // A chat on this device shows at once, offline or not.
        run_command(&mut h, "Go offline");
        open_session(&mut h, "agent_a3");
        assert!(h.find("turn_1_prompt").is_some());
        assert!(h.find(caption).is_none());
        healthy(&h);
    });
}

/// What a dictation ended in shows under the composer until dismissed or
/// another starts: no speech heard, the microphone refused
/// (dictation.rs Phase::status).
#[test]
fn zeron_dictation_outcomes_show_under_the_composer() {
    deep(|| {
        let mut h = app();
        let title = "composer_dictation_status_title";
        run_command(&mut h, "Hear no speech");
        h.click("composer_mic");
        h.frames(10);
        h.click("composer_mic");
        assert!(
            h.wait_until(|h| {
                h.frames(1);
                h.find(title).is_some()
            }),
            "it says so"
        );
        assert_eq!(h.text(title), "No speech detected");
        assert!(shows(&mut h, "Check your microphone, then try again."));
        assert!(
            !h.text("composer_input").contains("Windows"),
            "nothing said"
        );
        let input = h.bounds("composer_input");
        let status = h.bounds("composer_dictation_status");
        assert!(status.y >= input.y + input.height, "under the composer");
        h.frames(40);
        h.click("composer_dictation_status_dismiss");
        h.frames(10);
        assert!(h.find(title).is_none(), "dismissed");

        run_command(&mut h, "Refuse the microphone");
        h.click("composer_mic");
        h.frames(10);
        assert!(h.find("composer_track").is_none(), "it never listens");
        assert_eq!(h.text(title), "Dictation unavailable");
        // The next one starts afresh.
        h.click("composer_mic");
        h.frames(10);
        assert!(h.find("composer_track").is_some());
        assert!(h.find(title).is_none());
        healthy(&h);
    });
}

/// How much of node `id` shows: its opacity and its ancestors'.
fn seen_opacity(h: &mut Harness, id: &str) -> f32 {
    let node = h.find(id).unwrap_or_else(|| panic!("no `{id}`"));
    let scene = h.ui.scene.borrow();
    std::iter::once(node)
        .chain(scene.ancestors(node))
        .map(|n| scene.effects(n).opacity)
        .product()
}

/// Navigation that moves the conversation's column fades it through
/// (composer_dock/panel_handoff.rs): out, the column switched unseen, in;
/// chats in the same column swap at once.
#[test]
fn zeron_width_fade_through_on_navigation() {
    deep(|| {
        let mut h = app();
        // Room for the session card beside the chat.
        cmd(&mut h, "b", false);
        assert!(h.find("z_session_card").is_some(), "the card is docked");
        h.click("ztitle_new");
        h.frame();
        h.frame();
        let out = seen_opacity(&mut h, "conversation");
        assert!(out < 1. && out > 0., "the chat fades out: {out}");
        assert!(h.find("new_composer").is_none(), "the canvas waits");
        h.frames(40);
        assert!(h.find("new_composer").is_some(), "the canvas, at rest");
        assert!(h.find("conversation").is_none());
        // Back to the chat beside the card: in again.
        h.key_with(Key::Character("[".into()), meta(false));
        let mut seen = Vec::new();
        for _ in 0..40 {
            h.frame();
            if h.find("conversation").is_some() {
                seen.push(seen_opacity(&mut h, "conversation"));
            }
        }
        assert!(
            seen.first().is_some_and(|o| *o < 1.),
            "it fades in: {seen:?}"
        );
        assert_eq!(seen.last(), Some(&1.), "{seen:?}");
        // Another chat in the same column: at once.
        h.key_with(
            Key::Tab,
            Modifiers {
                control: true,
                ..Default::default()
            },
        );
        h.frame();
        assert_eq!(seen_opacity(&mut h, "conversation"), 1.);
        healthy(&h);
    });
}

/// The placeholder run a formula sits on, and the room it keeps.
fn formula_room(text: &zgx::rich_text::RichText) -> Option<f32> {
    text.runs()
        .iter()
        .find(|run| text.text()[run.range.clone()] == *"\u{2060}")
        .map(|run| run.padding[0])
}

/// Math as Zeron sets it (zatex): `$…$` on the line's baseline and `$$…$$`
/// on a line of its own, each copying as its source; Appearance's Render
/// math off shows the source as code, Math font and Math size set it
/// again. Agent visuals run as sandboxed plugins: "Loading visual…", then
/// what the script returns with its controls working, and a visual that
/// reaches for what it was not given saying why it failed.
#[test]
fn zeron_math_and_visuals_in_a_reply() {
    deep(|| {
        let mut h = app();
        open_session(&mut h, "thread_h2");
        assert!(shows(&mut h, "Loading visual…"));
        let ready = h.wait_until(|h| {
            h.frames(1);
            h.find("signups_bars").is_some()
        });
        assert!(ready, "the chart runs");
        assert!(shows(&mut h, "156"));
        into_view(&mut h, "signups_team");
        h.click("signups_team");
        h.frames(5);
        assert!(
            shows(&mut h, "84") && !shows(&mut h, "156"),
            "its own handler"
        );
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("Visual failed:") && t.contains("ui.fetch")),
            "{:?}",
            h.texts()
        );
        // The rack's 3D scene, where the host draws scenes; elsewhere it
        // says it can't.
        #[cfg(feature = "scene3d")]
        assert!(h.find("rack_failing").is_some());
        #[cfg(not(feature = "scene3d"))]
        assert!(
            h.texts()
                .iter()
                .any(|t| t.starts_with("Visual failed:") && t.contains("`scene3d` feature")),
            "{:?}",
            h.texts()
        );
        healthy(&h);

        let inline = rich(&mut h, "reply_3_1");
        let room = formula_room(&inline).expect("a formula in the line");
        let copied = inline.copy_text(0..inline.text().len());
        assert!(
            copied.contains(r"$g_t = \frac{s_t - s_{t-1}}{s_{t-1}}$"),
            "{copied}"
        );
        assert!(h.find("reply_3_2_math").is_some(), "the display formula");
        assert!(h.find("reply_3_2_math_copy").is_none(), "set, not code");

        // Off: the source as code. Settings search finds the row.
        open_settings(&mut h, "general");
        cmd(&mut h, "f", false);
        h.ui.dispatch(InputEvent::Text("latex".into()));
        h.frames(10);
        assert!(
            hit(&mut h, 1).starts_with("Render math"),
            "{}",
            hit(&mut h, 1)
        );
        h.key(Key::Enter);
        h.frames(10);
        assert!(lands_on(&mut h, "settings_render_math"));
        h.click("settings_render_math");
        h.frames(10);
        let inline = rich(&mut h, "reply_3_1");
        assert!(formula_room(&inline).is_none());
        assert!(inline.text().contains(r"$g_t = \frac"));
        assert!(h.find("reply_3_2_math_copy").is_some(), "a math code block");
        // On again, in Euler at 150%.
        h.click("settings_render_math");
        scroll_to(&mut h, "settings_math_size");
        h.click("settings_math_font");
        h.frames(20);
        h.click("settings_math_font_euler");
        h.frames(20);
        h.click("settings_math_size");
        h.frames(20);
        h.click("settings_math_size_150");
        h.frames(20);
        assert_eq!(h.text("settings_math_font"), "Euler", "{:?}", h.texts());
        assert_eq!(h.text("settings_math_size"), "150%");
        assert!(shows(&mut h, "Zapf's upright, hand-drawn math."));
        let inline = rich(&mut h, "reply_3_1");
        let larger = formula_room(&inline).expect("set again");
        assert!(larger > room * 1.2, "{room} → {larger}");
        healthy(&h);
    });
}

/// The board's pane (pull_request_pane.rs): the pull requests opened beside
/// it as tabs over it, the least recently viewed closing past the cap
/// (eight; three here); they drag along the strip to reorder; a tab's menu
/// closes those to its side (inert where
/// there are none); ⌘W closes the active one and the last the pane, which
/// opens again only with a pull request to show. Where the window can't
/// keep the board's 360 beside it, the pane covers the board.
#[test]
fn the_boards_pane_keeps_pull_requests_as_tabs() {
    deep(|| {
        let mut h = started(Harness::new(|runtime| {
            let host = host(runtime);
            host.shared("pr_tabs_max", 3.);
            host
        }));
        h.click("nav_prs");
        h.frames(30);
        cmd(&mut h, "r", false);
        h.frames(30);
        assert!(h.bounds("zprs_right").width < 0.5, "nothing to show");
        for id in ["p1", "p2", "p3"] {
            open_pr(&mut h, id);
        }
        let open = |h: &mut Harness| {
            ["p1", "p2", "p3", "p4"]
                .into_iter()
                .filter(|id| h.find(&format!("zp_prs_tab_{id}")).is_some())
                .collect::<Vec<_>>()
        };
        assert_eq!(open(&mut h), ["p1", "p2", "p3"]);
        assert_eq!(
            h.text("zp_prs_tab_p2"),
            "Dictation: the stop plate on the accent glass"
        );
        snapshot(&h, "pr_pane_tabs");
        // p1 seen again: a fourth closes p2, the least recently viewed.
        h.click("zp_prs_tab_p1");
        h.frames(20);
        arrives(&mut h, "pr_overview");
        assert_eq!(
            h.text("pr_detail_title"),
            "Scroll fade on the transcript's bottom edge"
        );
        open_pr(&mut h, "p4");
        assert_eq!(open(&mut h), ["p1", "p3", "p4"]);

        // p4 dragged before p3.
        use zgx::input::PointerButton::Primary;
        let (from, to) = (h.bounds("zp_prs_tab_p4"), h.bounds("zp_prs_tab_p3"));
        let (x, y) = (from.x + 30., from.y + from.height / 2.);
        h.ui.dispatch(InputEvent::PointerMove { x, y });
        h.ui.dispatch(InputEvent::PointerDown {
            x,
            y,
            button: Primary,
        });
        let end = to.x + 10.;
        for step in 1..=12 {
            let k = step as f32 / 12.;
            h.ui.dispatch(InputEvent::PointerMove {
                x: x + (end - x) * k,
                y,
            });
            h.frames(2);
        }
        h.ui.dispatch(InputEvent::PointerUp {
            x: end,
            y,
            button: Primary,
        });
        h.frames(30);
        healthy(&h);
        assert!(h.bounds("zp_prs_tab_p4").x < h.bounds("zp_prs_tab_p3").x);

        // The menu: nothing left of the first; what is right of p4 closes.
        secondary(&mut h, "zp_prs_tab_p1");
        h.frames(20);
        h.click("zp_prs_tab_p1_menu_left");
        h.frames(20);
        assert_eq!(open(&mut h), ["p1", "p3", "p4"]);
        h.key(Key::Escape);
        h.frames(20);
        secondary(&mut h, "zp_prs_tab_p4");
        h.frames(20);
        h.click("zp_prs_tab_p4_menu_right");
        h.frames(30);
        healthy(&h);
        assert_eq!(open(&mut h), ["p1", "p4"]);
        assert!(h.find("pr_detail").is_some());

        // ⌘W: the active tab, then the last and the pane with it.
        cmd(&mut h, "w", false);
        h.frames(20);
        assert_eq!(open(&mut h).len(), 1);
        assert!(h.bounds("zprs_right").width > 300.);
        cmd(&mut h, "w", false);
        h.frames(40);
        assert!(open(&mut h).is_empty());
        assert!(h.bounds("zprs_right").width < 0.5);

        // Narrow: the board's 360 and the pane's don't fit beside the
        // sidebar, so the pane covers the board, without a seam.
        open_pr(&mut h, "p2");
        let sidebar = h.bounds("zprs_sidebar").width;
        let narrow = sidebar + 600.;
        h.ui.scene.borrow_mut().resize(narrow, HEIGHT);
        h.frames(40);
        healthy(&h);
        assert!(h.bounds("zprs_conversation").width < 0.5);
        assert!((h.bounds("zprs_right").width - (narrow - sidebar)).abs() <= 1.);
        let seam = |h: &mut Harness| {
            h.find("zprs_seam_right").is_none() || h.bounds("zprs_seam_right").width < 0.5
        };
        assert!(seam(&mut h), "no seam");
        h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
        h.frames(40);
        assert!(h.bounds("zprs_conversation").width > 300.);
        assert!(!seam(&mut h));
    });
}

/// Annotate (browser/mod.rs, annotate.js): the toolbar's toggle, inert
/// without a page, injects Zeron's picker into the page; what the page
/// posts back lands in the session's draft as "Annotation N" chips, their
/// markers numbered alike, a chip's card showing its element and code; a
/// chip taken out of the draft takes its marker off the page, and the
/// page's end of the pick (or Escape) ends it. A page whose view is still
/// starting says so.
#[test]
fn a_browser_annotates_an_element_into_the_draft() {
    deep(|| {
        let (mut h, natives) = native_app(false);
        h.click("zeron_pane_toggle");
        h.frames(40);
        open_from_palette(&mut h, "browser");
        // No page yet: nothing to annotate.
        assert!(h.find("preview_1_bar_annotate").is_some());
        h.click("preview_1_previews_docs");
        h.frames(10);
        assert!(h.find("preview_1_starting").is_some());
        assert!(h.texts().iter().any(|t| t == "Starting browser…"));
        let zgx::native_view::NativeContent::Web(web) = native(&mut h, &natives, "preview_1_page")
        else {
            panic!("not a page");
        };
        let asked = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
        web.attach(std::rc::Rc::new(Recorder(asked.clone())));
        h.frames(5);
        assert!(h.find("preview_1_starting").is_none(), "started");
        asked.borrow_mut().clear();

        h.click("preview_1_bar_annotate");
        h.frames(5);
        healthy(&h);
        let start = asked
            .borrow()
            .iter()
            .find(|c| c.contains("__zeronAnnotator.start("))
            .cloned()
            .expect("the picker injected");
        assert!(start.contains("Object.freeze(api)"), "Zeron's picker");
        let nonce: u64 = start
            .split("__zeronAnnotator.start(")
            .nth(1)
            .and_then(|s| s.split(',').next())
            .and_then(|s| s.trim().parse().ok())
            .expect("its nonce");
        assert_eq!(heard(&mut h, "preview_1_bar_annotate"), "Stop annotating");
        let pick = |state: &str, marker: u32, nonce: u64| zgx::web_view::WebViewEvent::Message {
            body: format!(
                r##"{{"zeron":"annotate","nonce":{nonce},"state":"{state}","picks":[{{"url":"http://localhost:5173/","title":"Docs","element":"button#save.btn.primary","selector":"#save","path":["body","main"],"role":"button","name":"Save","text":"Save","html":"<button id=\"save\" class=\"btn primary\">\n  <span>Save</span>\n</button>","rect":[10,20,96,32],"viewport":[1280,800],"styles":[["display","flex"]],"marker":{marker}}}]}}"##
            ),
            origin: "http://localhost:5173".into(),
            main_frame: true,
        };
        // Another nonce (a page forging one) is not heard.
        web.emit(pick("active", 9, nonce + 1));
        h.frames(5);
        assert_eq!(h.text("composer_input"), "");
        // Shift-picked: the pick goes on.
        web.emit(pick("active", 1, nonce));
        h.frames(5);
        healthy(&h);
        assert_eq!(h.text("composer_input"), "@annotation:1:1 ");
        assert!(
            asked
                .borrow()
                .iter()
                .any(|c| c.contains("__zeronAnnotator?.label(1, 1)")),
            "its marker numbered as its chip: {:?}",
            asked.borrow()
        );
        assert!(
            h.texts().iter().any(|t| t.contains("Annotation 1")),
            "its chip"
        );
        // A plain click ends the pick with the second.
        web.emit(pick("done", 2, nonce));
        h.frames(5);
        assert_eq!(h.text("composer_input"), "@annotation:1:1 @annotation:2:2 ");
        assert_eq!(
            heard(&mut h, "preview_1_bar_annotate"),
            "Annotate an element"
        );

        // A chip's card: the element, its size, the opening of its code.
        let chip = {
            let input = h.find("composer_input").unwrap();
            let scene = h.ui.scene.borrow();
            let mut stack = vec![input];
            let mut found: Option<zgx::scene::Rect> = None;
            while let Some(n) = stack.pop() {
                if let zgx::scene::NodeKind::Quad(q) = scene.kind(n)
                    && q.radius == 5.
                {
                    let b = scene.transformed_bounds(n);
                    if found.is_none_or(|f| b.x < f.x) {
                        found = Some(b);
                    }
                }
                stack.extend(scene.children(n).iter().copied());
            }
            found.expect("the first chip's fill")
        };
        h.ui.dispatch(InputEvent::PointerMove {
            x: chip.x + chip.width / 2.,
            y: chip.y + chip.height / 2.,
        });
        // It shows once the pointer rests (300 ms, on the real clock).
        let shown = h.wait_until(|h| h.find("annotation_card").is_some());
        assert!(shown, "its card");
        h.frames(20);
        let texts = h.texts();
        for t in [
            "button",
            "#save.btn.primary",
            "96 × 32",
            "<button id=\"save\" class=\"btn primary\">",
        ] {
            assert!(texts.iter().any(|s| s == t), "{t}: {texts:?}");
        }
        snapshot(&h, "browser_annotation_card");

        // A chip taken out takes its marker off the page.
        asked.borrow_mut().clear();
        h.click("composer_input");
        h.keys("cmd+a");
        h.key(Key::Backspace);
        h.frames(5);
        assert!(
            asked
                .borrow()
                .iter()
                .any(|c| c.contains("__zeronAnnotator?.keep([])")),
            "{:?}",
            asked.borrow()
        );

        // Escape in the browser ends a pick under way.
        h.click("preview_1_bar_annotate");
        h.frames(5);
        h.click("preview_1_bar_address");
        asked.borrow_mut().clear();
        h.key(Key::Escape);
        h.frames(5);
        assert!(asked.borrow().iter().any(|c| c.contains("stop()")));
        assert_eq!(
            heard(&mut h, "preview_1_bar_annotate"),
            "Annotate an element"
        );
    });
}

/// A browser outside a session (a tabs layout's pane) has no dev servers
/// to offer: "Preview your work", and Enter an address (⌘L).
#[test]
fn a_browser_without_dev_servers_asks_for_an_address() {
    deep(|| {
        let (mut h, _natives) = native_app(false);
        cmd(&mut h, "l", true);
        cmd(&mut h, "l", true);
        cmd(&mut h, "d", false);
        h.click("zt1_p1_preview");
        h.frames(40);
        healthy(&h);
        let texts = h.texts();
        assert!(texts.iter().any(|t| t == "Preview your work"), "{texts:?}");
        assert!(
            texts
                .iter()
                .any(|t| t == "Preview your local app or keep a website beside your conversation.")
        );
        assert!(texts.iter().any(|t| t == "Enter an address"));
        assert!(h.find("zt1_p1_previews").is_none());
        snapshot(&h, "browser_preview_your_work");
    });
}

/// Clicks the menu item `id` of the menu showing (each row's menu keeps
/// its items once closed, under the same ids).
fn click_shown(h: &mut Harness, id: &str) {
    h.ui.prepare_frame();
    let shown = h
        .handle
        .find_all(id)
        .into_iter()
        .find_map(|n| h.ui.scene.borrow().visible_bounds(n))
        .unwrap_or_else(|| panic!("no {id} showing"));
    let (x, y) = (shown.x + shown.width / 2., shown.y + shown.height / 2.);
    let button = zgx::input::PointerButton::Primary;
    h.ui.dispatch(InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(InputEvent::PointerUp { x, y, button });
    h.settle();
}

/// Files chooses several (files/tree.rs, context_menu.rs, drag.rs): ⌘ and
/// a click adds without opening, the menu acts on them all ("Copy paths",
/// a line each; "Delete 2 items…"; Rename… only for one), a drag carries
/// them all, Escape keeps the current one, ⇧ a range, and a press below
/// the rows chooses none. Delete says what it takes, a folder with what is
/// in it; a name with a separator is refused, the field kept.
#[test]
fn files_choose_several_to_copy_drag_and_delete_together() {
    deep(|| {
        let mut h = desktop_app();
        cmd(&mut h, "e", false);
        h.frames(30);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        h.click("ztree_Cargo.toml");
        h.frames(20);
        h.click_with("ztree_README.md", "cmd");
        h.frames(20);
        healthy(&h);
        assert!(
            h.find("file_file_README_md_crumbs").is_none(),
            "⌘ chooses, it doesn't open"
        );
        secondary(&mut h, "ztree_README.md");
        h.frames(10);
        assert!(says(&mut h, "Copy paths"));
        assert!(says(&mut h, "Delete 2 items…"));
        snapshot(&h, "files_several_menu");
        h.click("files_menu_copy");
        h.frames(5);
        assert_eq!(
            h.desktop.as_ref().unwrap().clipboard(),
            "/Users/gael/Developer/zgx/Cargo.toml\n/Users/gael/Developer/zgx/README.md"
        );
        // Dragged, both go into the draft.
        drag_to(
            &mut h,
            "ztree_README.md",
            "chat_dropzone",
            (300., 200.),
            |h| {
                assert!(h.ui.input.drag_state().and_then(|d| d.preview).is_some());
                assert!(h.texts().iter().any(|t| t == "2 items"));
            },
        );
        let draft = h.text("composer_input");
        assert!(
            draft.contains("@Cargo.toml") && draft.contains("@README.md"),
            "{draft}"
        );
        // Escape keeps the current one alone.
        let tree = h.find("role:tree").unwrap();
        h.ui.input.focus(&h.ui.scene, Some(tree));
        cmd_key(&mut h, Key::Escape);
        secondary(&mut h, "ztree_README.md");
        h.frames(10);
        assert!(says(&mut h, "Copy path") && says(&mut h, "Delete…"));
        h.key(Key::Escape);
        h.frames(10);
        // ⇧ chooses the rows from the anchor.
        h.click("ztree_Cargo.toml");
        h.frames(10);
        h.click_with("ztree_README.md", "shift");
        h.frames(10);
        secondary(&mut h, "ztree_README.md");
        h.frames(10);
        assert!(says(&mut h, "Delete 3 items…"), "{:?}", h.texts());
        h.click("files_menu_delete");
        h.frames(20);
        assert!(says(
            &mut h,
            "Permanently delete 3 items (Cargo.toml, latest and 1 more)? This cannot be undone. Open editor buffers will be kept for recovery."
        ));
        h.click("files_delete_cancel");
        h.frames(20);
        // A press below the rows chooses none.
        let b = h.bounds("ztree_latest");
        let (x, y) = (b.x + 40., b.y + b.height * 3.);
        let button = zgx::input::PointerButton::Primary;
        h.ui.dispatch(InputEvent::PointerDown { x, y, button });
        h.ui.dispatch(InputEvent::PointerUp { x, y, button });
        h.frames(10);
        healthy(&h);
        secondary(&mut h, "ztree_docs");
        h.frames(10);
        assert!(says(&mut h, "Delete…"));
        click_shown(&mut h, "files_menu_delete");
        h.frames(20);
        assert!(
            says(
                &mut h,
                "Permanently delete docs? All current folder contents will be deleted. Open editor buffers will be kept for recovery."
            ),
            "{:?}",
            h.texts()
                .iter()
                .filter(|t| t.contains("delete"))
                .collect::<Vec<_>>()
        );
        h.click("files_delete_cancel");
        h.frames(20);
        // A name with a separator: refused, said, the field kept.
        secondary(&mut h, "ztree_latest");
        click_shown(&mut h, "files_menu_rename");
        h.frames(10);
        h.keys("cmd+a");
        h.ui.dispatch(InputEvent::Text("a/b".into()));
        h.key(Key::Enter);
        h.frames(10);
        assert!(says(
            &mut h,
            "Enter a single file name without path separators"
        ));
        assert!(h.find("ztree_latest_rename").is_some(), "still renaming");
        h.keys("cmd+a");
        h.ui.dispatch(InputEvent::Text("newest".into()));
        h.key(Key::Enter);
        h.frames(10);
        assert!(h.find("ztree_newest").is_some(), "renamed");
        assert!(h.find("files_refused").is_none(), "the error goes");
    });
}

/// A file's save status (preview.rs): "Changed on disk" while the disk has
/// another, "Save failed" when the disk refuses (a press saves again, the
/// reason its tooltip), "Deleted on disk" when it is deleted while open,
/// its buffer kept.
#[test]
fn a_files_toolbar_says_how_its_save_stands() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", false);
        h.frames(30);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);
        h.click("ztree_crates/zgx/compose_scrollbar.rs");
        h.frames(30);
        assert!(says(&mut h, "Changed on disk"));
        cmd(&mut h, "w", false);
        // The disk refuses the save once.
        h.click("ztree_crates/styleguide/canvas.luau");
        h.frames(30);
        let id = "file_file_crates_styleguide_canvas_luau";
        h.click(&format!("{id}_editor"));
        h.ui.dispatch(InputEvent::Text("x".into()));
        h.settle();
        h.keys("cmd+s");
        h.frames(5);
        assert!(says(&mut h, "Save failed"));
        assert!(h.find(&format!("{id}_edited")).is_some(), "still edited");
        snapshot(&h, "files_save_failed");
        h.click(&format!("{id}_save_status"));
        h.frames(5);
        assert!(!says(&mut h, "Save failed"), "saved again");
        assert!(h.find(&format!("{id}_edited")).is_none());
        // Deleted while open: the buffer stays, and says so.
        h.click(&format!("{id}_editor"));
        h.ui.dispatch(InputEvent::Text("y".into()));
        h.settle();
        secondary(&mut h, "ztree_crates/styleguide/canvas.luau");
        h.click("files_menu_delete");
        h.frames(20);
        h.click("files_delete_confirm");
        h.frames(20);
        healthy(&h);
        assert!(h.find("ztree_crates/styleguide/canvas.luau").is_none());
        assert!(says(&mut h, "Deleted on disk"));
        assert!(h.find(&format!("{id}_editor")).is_some(), "kept open");
    });
}

/// ⌘K with nothing typed (command_palette.rs palette_sections): under All,
/// Recent Files (the files opened here, then the changed ones), Quick
/// Actions (New chat, New project, Open settings, the other theme, Archive
/// thread while the session can go) and Recent Threads (the one on show
/// aside); typed, Threads, Commands, Files and In Files. A file's row opens
/// the file; Files with nothing to list says so.
#[test]
fn the_palette_lists_recent_files_quick_actions_and_recent_threads() {
    deep(|| {
        let mut h = app();
        let order = |h: &mut Harness| -> Vec<String> {
            const SECTIONS: [&str; 7] = [
                "Recent Files",
                "Quick Actions",
                "Recent Threads",
                "Threads",
                "Commands",
                "Files",
                "In Files",
            ];
            // Between the tabs (All … Files) and the footer's hints.
            let texts = h.texts();
            let all = texts.iter().position(|t| t == "All").expect("tabs");
            let start = all + texts[all..].iter().position(|t| t == "Files").unwrap() + 1;
            let end = texts.iter().position(|t| t == "Navigate").expect("footer");
            texts[start..end]
                .iter()
                .filter(|t| SECTIONS.contains(&t.as_str()))
                .cloned()
                .collect()
        };
        cmd(&mut h, "k", false);
        assert_eq!(
            order(&mut h),
            ["Recent Files", "Quick Actions", "Recent Threads"]
        );
        for id in [
            "palette_new_chat",
            "palette_new_project",
            "palette_settings",
            "palette_archive_thread",
            "palette_file_crates_zgx_compose_rs",
        ] {
            assert!(h.find(id).is_some(), "{id}");
        }
        assert!(
            h.find("palette_theme_light").is_some() != h.find("palette_theme_dark").is_some(),
            "the other theme alone"
        );
        assert!(h.find("palette_split_right").is_none(), "Zeron's alone");
        snapshot(&h, "palette_empty_all");

        // Typed: Threads, Commands, Files, In Files, in that order.
        h.type_text("palette_input", "re");
        h.frames(10);
        healthy(&h);
        assert_eq!(order(&mut h), ["Threads", "Commands", "Files", "In Files"]);
        // A file opens itself, and leads Recent Files the next time.
        h.key(Key::Escape);
        h.frames(20);
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "canvas");
        h.frames(10);
        h.click("palette_file_crates_styleguide_canvas_luau");
        h.frames(40);
        healthy(&h);
        assert!(h.find("palette_input").is_none(), "closed");
        assert!(
            h.find("file_file_crates_styleguide_canvas_luau_editor")
                .is_some(),
            "the file, not the changes"
        );
        cmd(&mut h, "k", false);
        let first = h.bounds("palette_file_crates_styleguide_canvas_luau").y;
        assert!(first < h.bounds("palette_file_crates_zgx_compose_rs").y);

        // Archive thread archives the session on show, and goes.
        h.click("palette_archive_thread");
        h.frames(40);
        healthy(&h);
        cmd(&mut h, "k", false);
        assert!(h.find("palette_new_chat").is_some());
        assert!(h.find("palette_archive_thread").is_none(), "archived now");
        h.key(Key::Escape);
        h.frames(20);
    });
}

/// The sidebar's own sections reorder by their headers (sidebar_sections.rs):
/// lifted, a frosted card with its rows follows the pointer, the others
/// sliding to make its slot; dropped, it stays there. A pin dragged with
/// nothing unpinned finds "Drop here to unpin" (shell.rs); by project, a
/// device's No project group's + starts a chat there ("New chat on …").
#[test]
fn sidebar_sections_reorder_by_their_headers_and_pins_unpin_onto_sessions() {
    deep(|| {
        let mut h = app();
        let y = |h: &mut Harness, id: &str| h.bounds(id).y;
        assert!(
            y(&mut h, "side_cloud_onboarding_header") < y(&mut h, "side_cross_platform_zgx_header")
        );
        let cross = y(&mut h, "side_cross_platform_zgx_header");
        drag_to(
            &mut h,
            "side_cloud_onboarding_header",
            "agent_a8",
            (40., 30.),
            |h| {
                let preview = h.ui.input.drag_state().and_then(|d| d.preview);
                let card =
                    h.ui.scene
                        .borrow()
                        .bounds(preview.expect("the lifted card"));
                assert!(card.height > 28. * 3., "its header and rows: {card:?}");
                h.frames(30);
                assert!(
                    y(h, "side_cross_platform_zgx_header") < cross - 40.,
                    "the other slid up"
                );
                snapshot(h, "sidebar_section_lifted");
            },
        );
        h.frames(30);
        assert!(
            y(&mut h, "side_cross_platform_zgx_header") < y(&mut h, "side_cloud_onboarding_header"),
            "placed after the other"
        );
        assert!(y(&mut h, "side_cloud_onboarding_header") < y(&mut h, "agent_a4"));

        // Every zgx session pinned or in a section: a pin dragged finds
        // where it would unpin.
        h.click("side_filter");
        h.frames(20);
        h.click("side_filter_zgx");
        h.frames(20);
        secondary(&mut h, "agent_a3");
        h.frames(10);
        h.click("agent_a3_menu_pin");
        h.frames(30);
        assert!(h.find("side_unpin").is_none(), "only while a pin drags");
        {
            use zgx::input::PointerButton::Primary;
            let a = h.bounds("agent_a2");
            let (x, y) = (a.x + 40., a.y + a.height / 2.);
            h.ui.dispatch(InputEvent::PointerMove { x, y });
            h.ui.dispatch(InputEvent::PointerDown {
                x,
                y,
                button: Primary,
            });
            for step in 1..=4 {
                h.ui.dispatch(InputEvent::PointerMove {
                    x,
                    y: y + 4. * step as f32,
                });
                h.frames(2);
            }
            h.frames(30);
            assert_eq!(h.text("side_unpin"), "Drop here to unpin");
            let to = h.bounds("side_unpin");
            let (x, y) = (to.x + 40., to.y + to.height / 2.);
            for _ in 0..3 {
                h.ui.dispatch(InputEvent::PointerMove { x, y });
                h.frames(2);
            }
            h.ui.dispatch(InputEvent::PointerUp {
                x,
                y,
                button: Primary,
            });
            h.frames(30);
            healthy(&h);
        }
        assert!(h.find("side_unpin").is_none());
        assert!(
            h.find("side_sessions").is_some(),
            "unpinned among the sessions"
        );
        assert!(h.bounds("agent_a2").y > h.bounds("side_sessions").y);
        h.click("side_filter");
        h.frames(20);
        h.click("side_filter_all");
        h.frames(20);

        // A chat in no project, then its device's group by project.
        h.click("ztitle_new");
        h.frames(30);
        h.click("new_project");
        h.frames(20);
        h.click("new_project_menu_");
        h.frames(20);
        h.type_text("new_composer_input", "Scratch notes");
        h.click("new_composer_send");
        h.frames(40);
        healthy(&h);
        view_option(&mut h, Some("side_view_organize"), "side_view_project");
        assert!(h.find("side_noproject_macbook_pro").is_some(), "No project");
        assert!(h.texts().iter().any(|t| t == "No project"));
        // Folded above it, so it shows.
        for section in ["pinned", "cross_platform_zgx", "cloud_onboarding"] {
            h.click(&format!("side_{section}_header"));
            h.frames(20);
        }
        hover_id(&mut h, "side_noproject_macbook_pro_header");
        h.click("side_noproject_macbook_pro_new");
        h.frames(30);
        healthy(&h);
        assert!(h.find("new_composer").is_some(), "the canvas");
        assert_eq!(h.text("new_project"), "No project");
    });
}

/// The update dialog's other outcomes (shell.rs update prompt): a check
/// that fails says so with Try again; a copy a package manager installed
/// is told to run `zeron update`, one set up by no installer opens the
/// download page. The agents' updates wait for the run under way and,
/// with the engine away, say so with their actions inert; a harness that
/// reports no context usage says that; a side chat needs a conversation;
/// the composer's access chip picks the mode and plan mode.
#[test]
fn updates_access_and_context_say_what_zeron_says() {
    deep(|| {
        let mut h = started(Harness::with_desktop(host));
        let desktop = h.desktop.clone().unwrap();
        let run = |h: &mut Harness, query: &str, id: &str| {
            cmd(h, "k", false);
            h.type_text("palette_input", query);
            h.frames(10);
            h.click(&format!("palette_{id}"));
            h.frames(20);
            healthy(h);
        };
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t == what);

        run(&mut h, "fail the next update", "engine_fail_check");
        run(&mut h, "check for updates", "check_updates");
        assert!(says(&mut h, "Checking for updates…"));
        assert!(h.wait_until(|h| h.texts().iter().any(|t| t == "Couldn't check for updates")));
        snapshot(&h, "update_check_failed");
        h.frames(30);
        h.click("update-prompt-check");
        assert!(h.wait_until(|h| h.texts().iter().any(|t| t == "Zeron 0.2.117 is available")));
        h.click("update-prompt-close");
        h.frames(20);
        run(&mut h, "built from source", "engine_install_source");
        assert!(
            h.texts()
                .iter()
                .any(|t| t.ends_with("· download from GitHub"))
        );
        run(&mut h, "check for updates", "check_updates");
        assert!(h.wait_until(|h| h.texts().iter().any(|t| t == "This copy of Zeron wasn't set up by an installer (for example, a source build), so it can't update itself.")));
        h.frames(30);
        h.click("update-prompt-downloads");
        h.frames(20);
        assert_eq!(
            desktop.opened().last().map(String::as_str),
            Some("https://github.com/zeronsh/zeron/releases/latest")
        );
        run(&mut h, "installed by the cli", "engine_install_managed");
        assert!(
            h.texts()
                .iter()
                .any(|t| t.ends_with("· run `zeron update`"))
        );
        run(&mut h, "check for updates", "check_updates");
        assert!(h.wait_until(|h| {
            h.texts()
                .iter()
                .any(|t| t == "Run `zeron update` in a terminal to install it.")
        }));
        h.click("update-prompt-close");
        h.frames(20);

        // The access chip: the modes, then plan mode.
        assert_eq!(h.text("access"), "Full access");
        h.click("access");
        h.frames(20);
        assert!(says(&mut h, "Apply edits, ask before other actions."));
        snapshot(&h, "access_menu");
        h.click("access_supervised");
        h.frames(20);
        assert_eq!(h.text("access"), "Supervised");
        h.click("access");
        h.frames(20);
        h.click("access_plan");
        h.frames(20);
        assert!(says(&mut h, "Plan"), "plan mode in the accent");
        h.key(Key::Escape);
        h.frames(20);

        // An agent's update waits for the run under way.
        h.type_text("composer_input", "Tidy the sidebar");
        h.click("composer_send");
        h.frames(10);
        h.click("ztitle_new");
        h.frames(30);
        h.click("update_summary");
        h.frames(30);
        assert_eq!(h.text("update_detail_claude"), "2.1.3 → 2.1.4");
        h.click("update_row_action_claude");
        h.frames(5);
        assert_eq!(
            h.text("update_detail_claude"),
            "Waiting for the current run"
        );
        assert!(h.wait_until(|h| h.text("update_detail_claude") != "Waiting for the current run"));
        // With the engine away, the rows say so.
        run(&mut h, "go offline", "engine_offline");
        if h.find("update_detail_codex").is_none() {
            h.click("update_summary");
            h.frames(30);
        }
        assert_eq!(
            h.text("update_detail_codex"),
            "Disconnected · reconnect to update"
        );
        let before = h.text("update_detail_codex");
        h.click("update_row_action_codex");
        h.frames(10);
        assert_eq!(h.text("update_detail_codex"), before, "inert");
        run(&mut h, "sample engine: reconnect", "engine_connected");
        if h.find("update_detail_codex").is_none() {
            h.click("update_summary");
            h.frames(30);
        }
        assert!(h.wait_until(|h| h.text("update_detail_codex") == "0.48.0 → 0.49.1"));

        // Nothing to fork from the canvas.
        run(&mut h, "new side chat", "side_chat");
        assert!(says(
            &mut h,
            "Start a conversation before creating a side chat."
        ));

        // Cursor reports no context usage, and runs with full access alone.
        h.click("agent_a8");
        h.frames(30);
        h.click("composer_context");
        h.frames(20);
        assert!(says(
            &mut h,
            "Context usage not reported by this harness yet"
        ));
        h.key(Key::Escape);
        h.frames(10);
        h.click("access");
        h.frames(20);
        assert!(says(
            &mut h,
            "Cursor can't ask before acting, so it always runs with full access."
        ));
        assert!(h.find("access_plan").is_none() || h.bounds("access_plan").width == 0.);
    });
}
