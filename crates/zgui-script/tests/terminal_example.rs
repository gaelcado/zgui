//! The terminal example's interface (zgui-desktop/examples/terminal), run
//! headless: its commands split, close and move panes as its menus would.
mod common;

use common::Harness;
use std::{cell::RefCell, rc::Rc};
use zgui::scene::Rect;
use zgui_script::{ScriptHost, Value};

const APP: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../zgui-desktop/examples/terminal/app.luau"
);

struct App {
    h: Harness,
    actions: Rc<RefCell<Vec<String>>>,
    /// The last layout the script asked to save.
    saved: Rc<RefCell<Value>>,
}
impl App {
    fn new() -> Self {
        Self::with_saved(Value::Nil)
    }
    /// The app as a launch finds it, with the layout a run saved.
    fn with_saved(layout: Value) -> Self {
        let actions: Rc<RefCell<Vec<String>>> = Rc::default();
        let saved: Rc<RefCell<Value>> = Rc::default();
        let (log, keep) = (actions.clone(), saved.clone());
        let h = Harness::new(move |runtime| {
            let host = ScriptHost::new(runtime, APP);
            for name in [
                "zoom_window",
                "close_window",
                "set_title",
                "end_session",
                "keep_sessions",
            ] {
                let log = log.clone();
                host.action(name, move |value| {
                    let arg = match value {
                        Value::Str(s) => format!(" {s}"),
                        Value::List(ids) => format!(" {ids:?}"),
                        _ => String::new(),
                    };
                    log.borrow_mut().push(format!("{name}{arg}"));
                });
            }
            host.action("save_layout", move |layout| *keep.borrow_mut() = layout);
            host.shared("launch_dir", "/tmp");
            host.shared("home", "/Users/someone");
            host.shared("saved_layout", layout);
            host
        });
        assert_eq!(h.host.error().get(), None);
        let mut app = Self { h, actions, saved };
        // The test window is 400 points wide: panes get all of it.
        app.run("toggle_sidebar");
        app
    }
    fn run(&mut self, id: &str) {
        assert!(self.h.host.run_command(id), "no command `{id}`");
        self.settle();
    }
    /// Half a second of display frames: panes finish easing into place.
    fn settle(&mut self) {
        self.h.settle();
        for _ in 0..40 {
            self.h.frame();
        }
    }
    /// Each mounted terminal's box.
    fn panes(&mut self) -> Vec<Rect> {
        self.h.ui.prepare_frame();
        let scene = self.h.ui.scene.borrow();
        let mut rects: Vec<Rect> = self
            .h
            .natives
            .nodes()
            .into_iter()
            .map(|n| scene.bounds(n))
            .collect();
        rects.sort_by(|a, b| (a.x, a.y).partial_cmp(&(b.x, b.y)).unwrap());
        rects
    }
}

#[test]
fn panes_split_beside_and_below_and_close_back_to_one() {
    let mut app = App::new();
    let one = app.panes();
    assert_eq!(one.len(), 1);
    assert!(one[0].width > 300. && one[0].height > 200., "{one:?}");

    app.run("split_right");
    let two = app.panes();
    assert_eq!(two.len(), 2, "{two:?}");
    assert!(
        two[0].x < two[1].x && (two[0].y - two[1].y).abs() < 1.,
        "{two:?}"
    );
    assert!(
        (two[0].width - two[1].width).abs() < 2.,
        "even halves: {two:?}"
    );

    app.run("split_down");
    let three = app.panes();
    assert_eq!(three.len(), 3, "{three:?}");
    // The right half is now two panes, one above the other.
    assert!(
        (three[1].x - three[2].x).abs() < 1. && three[1].y < three[2].y,
        "{three:?}"
    );

    app.run("close_pane");
    assert_eq!(app.panes().len(), 2);
    app.run("close_pane");
    assert_eq!(app.panes().len(), 1);
    assert_eq!(
        app.panes()[0].width,
        one[0].width,
        "one pane fills the tab again"
    );
}

#[test]
fn tabs_open_switch_and_closing_the_last_pane_closes_the_window() {
    let mut app = App::new();
    app.run("new_tab");
    app.run("split_right");
    assert_eq!(app.panes().len(), 2, "the new tab shows");
    app.run("tab_1");
    assert_eq!(app.panes().len(), 1, "the first tab has one pane");
    app.run("next_tab");
    assert_eq!(app.panes().len(), 2);
    // Close everything: the second tab's panes, then the first tab's.
    app.run("close_tab");
    assert_eq!(app.panes().len(), 1);
    app.run("close_pane");
    assert!(app.actions.borrow().iter().any(|a| a == "close_window"));
}

#[test]
fn pane_navigation_runs_without_changing_the_layout() {
    let mut app = App::new();
    app.run("split_right");
    app.run("split_down");
    let before = app.panes();
    for id in [
        "focus_left",
        "focus_right",
        "focus_up",
        "focus_down",
        "previous_pane",
        "next_pane",
        "zoom_pane",
    ] {
        app.run(id);
        assert_eq!(app.h.host.error().get(), None, "{id}");
    }
    // Zoomed: the focused pane alone; again: the split back.
    assert_eq!(app.panes().len(), 1);
    app.run("zoom_pane");
    assert_eq!(app.panes(), before);
}

#[test]
fn dragging_a_pane_by_its_grip_previews_and_moves_it() {
    use zgui::input::{InputEvent, PointerButton};
    let mut app = App::new();
    app.run("split_right");
    let before = app.panes();
    let (left, right) = (before[0], before[1]);
    // The pointer near the left pane's top shows its grip.
    let node = app
        .h
        .natives
        .nodes()
        .into_iter()
        .find(|n| app.h.ui.scene.borrow().bounds(*n) == left)
        .unwrap();
    let Some(zgui::native_view::NativeContent::Terminal(term)) = app.h.natives.content(node) else {
        panic!("no terminal")
    };
    term.set_pointer(Some((left.width / 2., 10.)));
    app.settle();
    // The grip: centered, 6 points below the pane's top.
    let (gx, gy) = (left.x + left.width / 2., left.y + 1. + 6. + 11.);
    app.h.ui.dispatch(InputEvent::PointerMove { x: gx, y: gy });
    app.h.ui.dispatch(InputEvent::PointerDown {
        x: gx,
        y: gy,
        button: PointerButton::Primary,
    });
    // Over the right pane, nearest its bottom edge.
    let (tx, ty) = (right.x + right.width / 2., right.y + right.height - 20.);
    for step in 1..=8 {
        let t = step as f32 / 8.;
        app.h.ui.dispatch(InputEvent::PointerMove {
            x: gx + (tx - gx) * t,
            y: gy + (ty - gy) * t,
        });
    }
    app.settle();
    // The preview: the left pane moved under the right one, so the two
    // stack, each the full width.
    let preview = app.panes();
    assert_eq!(preview.len(), 2, "{preview:?}");
    assert!(
        preview.iter().all(|r| (r.x - left.x).abs() < 1.)
            && preview.iter().all(|r| r.width > left.width + right.width),
        "previewed stacked: {preview:?}"
    );
    app.h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: PointerButton::Primary,
    });
    app.settle();
    // Dropped: kept as previewed, the dragged pane below the other.
    assert_eq!(app.panes(), preview);
    assert!(preview[0].y < preview[1].y && preview[0].height > 100.);
    assert_eq!(app.h.host.error().get(), None);
}

impl App {
    /// Every text the window shows.
    fn texts(&mut self) -> Vec<String> {
        use zgui::scene::NodeKind;
        self.h.ui.prepare_frame();
        let scene = self.h.ui.scene.borrow();
        let mut out = Vec::new();
        let mut stack = vec![scene.root()];
        while let Some(n) = stack.pop() {
            if let NodeKind::Text { text, .. } = scene.kind(n) {
                out.push(text.to_string());
            }
            stack.extend(scene.children(n).iter().copied());
        }
        out
    }
}

#[test]
fn a_tab_shows_an_icon_per_pane_and_counts_past_three() {
    let mut app = App::new();
    app.run("split_right");
    app.run("split_down");
    assert!(
        !app.texts().iter().any(|t| t.starts_with('+')),
        "three panes, three icons"
    );
    app.run("split_down");
    assert_eq!(app.panes().len(), 4);
    assert!(
        app.texts().iter().any(|t| t == "+2"),
        "two icons and +2: {:?}",
        app.texts()
    );
}

#[test]
fn dropping_a_pane_on_the_tab_bar_opens_it_as_a_tab_where_previewed() {
    use zgui::input::{InputEvent, PointerButton};
    let mut app = App::new();
    app.run("split_right");
    let left = app.panes()[0];
    let node = app
        .h
        .natives
        .nodes()
        .into_iter()
        .find(|n| app.h.ui.scene.borrow().bounds(*n) == left)
        .unwrap();
    let Some(zgui::native_view::NativeContent::Terminal(term)) = app.h.natives.content(node) else {
        panic!("no terminal")
    };
    term.set_pointer(Some((left.width / 2., 10.)));
    app.settle();
    let named = |app: &mut App| app.texts().iter().filter(|t| *t == "Terminal").count();
    let (gx, gy) = (left.x + left.width / 2., left.y + 1. + 6. + 11.);
    app.h.ui.dispatch(InputEvent::PointerMove { x: gx, y: gy });
    app.h.ui.dispatch(InputEvent::PointerDown {
        x: gx,
        y: gy,
        button: PointerButton::Primary,
    });
    app.h
        .ui
        .dispatch(InputEvent::PointerMove { x: gx, y: gy + 20. });
    app.settle();
    // Dragging: the tab's name and the preview's.
    let dragging = named(&mut app);
    // Up to the empty titlebar, right of the tabs: a slot opens at the end.
    let (tx, ty) = (300., 20.);
    for step in 1..=8 {
        let t = step as f32 / 8.;
        app.h.ui.dispatch(InputEvent::PointerMove {
            x: gx + (tx - gx) * t,
            y: gy + (ty - gy) * t,
        });
    }
    app.settle();
    assert_eq!(
        named(&mut app),
        dragging + 1,
        "a slot previews the new tab: {:?}",
        app.texts()
    );
    app.h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: PointerButton::Primary,
    });
    app.settle();
    assert_eq!(app.panes().len(), 1, "the new tab, with the pane");
    app.run("tab_1");
    assert_eq!(app.panes().len(), 1, "the first tab, without it");
    assert_eq!(app.h.host.error().get(), None);
}

#[test]
fn a_browser_pane_opens_beside_with_its_address_bar_focused_and_closes() {
    use zgui::native_view::NativeContent;
    let mut app = App::new();
    app.run("new_browser");
    app.h.ui.prepare_frame();
    let contents: Vec<_> = app
        .h
        .natives
        .nodes()
        .into_iter()
        .filter_map(|n| app.h.natives.content(n))
        .collect();
    assert_eq!(contents.len(), 2, "a terminal and a page");
    assert!(contents.iter().any(|c| matches!(c, NativeContent::Web(_))));
    let texts = app.texts();
    assert!(
        texts.iter().any(|t| t == "New Tab"),
        "the tab is named for the page: {texts:?}"
    );
    assert!(texts.iter().any(|t| t == "Search or enter address"));
    // The address bar has the keyboard.
    let focused = app.h.ui.input.focused().expect("something focused");
    assert!(
        !app.h.natives.contains(focused),
        "zgui's address input, not the terminal or the page, has focus"
    );
    // Commands that would ask a terminal act on the page instead.
    for id in [
        "copy",
        "paste",
        "bigger",
        "smaller",
        "actual_size",
        "reload_page",
        "open_location",
    ] {
        app.run(id);
        assert_eq!(app.h.host.error().get(), None, "{id}");
    }
    app.run("close_pane");
    app.h.ui.prepare_frame();
    let left: Vec<_> = app
        .h
        .natives
        .nodes()
        .into_iter()
        .filter_map(|n| app.h.natives.content(n))
        .collect();
    assert_eq!(left.len(), 1);
    assert!(matches!(left[0], NativeContent::Terminal(_)));
}

#[test]
fn resizing_the_window_moves_the_panes_without_running_script() {
    // The panes' frames are percentages and points zgui resolves itself:
    // the script works them out when the split changes, not when the area
    // does (a window drag, the sidebar easing open).
    let mut app = App::new();
    app.run("split_right");
    app.run("split_down");
    let before = app.panes();
    let calls = app.h.host.script_calls();
    app.h.ui.scene.borrow_mut().resize(600., 300.);
    app.settle();
    let after = app.panes();
    assert_eq!(app.h.host.script_calls(), calls, "a resize ran script");
    assert_eq!(after.len(), 3);
    // Each pane kept its place in the split, wider by its share of 200.
    let grew: f32 = after
        .iter()
        .zip(&before)
        .map(|(a, b)| a.width - b.width)
        .sum();
    assert!((grew - 300.).abs() < 2., "{before:?} -> {after:?}");
    assert!(
        (after[0].width - after[1].width).abs() < 2. && after[1].x > after[0].x + after[0].width,
        "{after:?}"
    );
}

#[test]
fn agents_in_tabs_not_shown_are_listed_and_a_click_opens_their_tab() {
    // Two tabs, the second shown; an agent works in the first, which no
    // window shows: the session server reports it all the same.
    let layout = Value::from_json(
        r#"{"version":1,"active":"t3","next_id":7,"kinds":[],"pages":[],"zoom":[],"ratios":{},
            "focus":{"t1":"p6","t3":"p4"},"dirs":{},
            "tabs":[{"id":"t1","root":{"id":"s5","kind":"split","axis":"row",
                        "a":{"id":"p2","kind":"pane"},"b":{"id":"p6","kind":"pane"}}},
                    {"id":"t3","root":{"id":"p4","kind":"pane"}}]}"#,
    )
    .unwrap();
    let mut app = App::with_saved(layout);
    app.run("toggle_sidebar");
    assert_eq!(app.panes().len(), 1, "the second tab, one pane");
    let agents = app.h.host.shared("agents", Value::Nil);
    agents.set(
        Value::from_json(
            r#"{"sessions":{
                "p2":{"process":"claude","idle":false,"title":"◐ Fix the build",
                      "pwd":"file:///Users/someone/zgui",
                      "status":{"state":"working","since_ms":1000,"reported":false}},
                "p4":{"process":"zsh","idle":true,"title":"","pwd":"file:///Users/someone",
                      "status":{"state":"idle","since_ms":1000,"reported":false}}}}"#,
        )
        .unwrap(),
    );
    app.settle();
    let texts = app.texts();
    assert!(texts.iter().any(|t| t == "Fix the build"), "{texts:?}");
    assert!(texts.iter().any(|t| t == "Working · zgui"), "{texts:?}");
    assert!(app.h.find("agent:p4").is_none(), "a shell is no agent");
    // Its row opens its tab, with its pane focused.
    app.h.click("agent:p2");
    app.settle();
    assert_eq!(app.panes().len(), 2, "the first tab, two panes");
    assert_eq!(app.h.host.error().get(), None);
}

#[test]
fn the_agents_sidebar_opens_beside_the_panes() {
    let mut app = App::new();
    let wide = app.panes();
    assert!(!app.texts().iter().any(|t| t == "Agents"));
    app.run("toggle_sidebar");
    let texts = app.texts();
    assert!(texts.iter().any(|t| t == "Agents"), "{texts:?}");
    assert!(texts.iter().any(|t| t == "No agents running"), "{texts:?}");
    let narrow = app.panes();
    assert!(
        narrow[0].x >= wide[0].x + 200. && narrow[0].width < wide[0].width - 200.,
        "{wide:?} -> {narrow:?}"
    );
    assert_eq!(app.h.host.error().get(), None);
}

#[test]
fn a_long_address_stays_inside_its_browser_pane() {
    use zgui::input::InputEvent;
    let mut app = App::new();
    app.run("new_browser");
    // Type a very long address into the focused address bar.
    let long = format!("example.com/?{}", "solution=3893d11c553cebd6&".repeat(12));
    app.h.ui.dispatch(InputEvent::Text(long));
    app.settle();
    // The browser is the right half; its card ends 6 points in from the
    // window's 400-point edge.
    let right = 400. - 6.;
    let field = app.h.ui.input.focused().unwrap();
    let scene = app.h.ui.scene.borrow();
    // The address input and the bar row holding it end inside the pane.
    let mut node = Some(field);
    for _ in 0..3 {
        let n = node.unwrap();
        let b = scene.bounds(n);
        assert!(b.x + b.width <= right + 0.5, "{b:?} overflows the pane");
        node = scene.parent(n);
    }
    drop(scene);
    assert_eq!(app.h.host.error().get(), None);
}

#[test]
fn the_layout_is_saved_and_a_launch_opens_it_again() {
    let mut app = App::new();
    app.run("split_right");
    app.run("split_down");
    app.run("new_tab");
    app.run("tab_1");
    let before = app.panes();
    let saved = app.saved.borrow().clone();
    assert!(matches!(saved, Value::Map(_)), "saved: {saved:?}");
    // The JSON on disk, read back by the next launch.
    let saved = Value::from_json(&saved.to_json()).unwrap();
    let mut again = App::with_saved(saved);
    again.settle();
    assert_eq!(again.panes(), before, "the same panes, in the same places");
    // It keeps the restored panes' sessions (and only those).
    let log = again.actions.borrow().join("\n");
    assert!(log.contains("keep_sessions"), "{log}");
    again.run("tab_2");
    assert_eq!(again.panes().len(), 1, "and the second tab");
    // Closing a pane ends its session.
    again.run("close_pane");
    assert!(
        again
            .actions
            .borrow()
            .iter()
            .any(|a| a.starts_with("end_session")),
        "{:?}",
        again.actions.borrow()
    );
}

#[test]
fn clicking_a_blank_page_focuses_its_address_bar_without_an_error() {
    use zgui::input::{InputEvent, PointerButton};
    use zgui::scene::NodeKind;
    let mut app = App::new();
    app.run("new_browser");
    // The page has no address yet: its start says where to begin.
    app.h.ui.prepare_frame();
    let hint = {
        let scene = app.h.ui.scene.borrow();
        let mut stack = vec![scene.root()];
        let mut found = None;
        while let Some(n) = stack.pop() {
            if matches!(scene.kind(n), NodeKind::Text { text, .. } if &**text == "Search or enter an address above")
            {
                found = Some(scene.bounds(n));
            }
            stack.extend(scene.children(n).iter().copied());
        }
        found.expect("the blank page's hint")
    };
    let (x, y) = (hint.x + hint.width / 2., hint.y + hint.height / 2.);
    app.h.ui.dispatch(InputEvent::PointerDown {
        x,
        y,
        button: PointerButton::Primary,
    });
    app.h.ui.dispatch(InputEvent::PointerUp {
        x,
        y,
        button: PointerButton::Primary,
    });
    app.settle();
    assert_eq!(app.h.host.error().get(), None);
    let focused = app.h.ui.input.focused().expect("something focused");
    assert!(
        !app.h.natives.contains(focused),
        "zgui's address input has focus"
    );
}

/// Every fill and text colour in the scene.
fn colors(ui: &zgui::widgets::Ui) -> Vec<zgui::scene::Color> {
    use zgui::scene::NodeKind;
    let scene = ui.scene.borrow();
    let mut out = Vec::new();
    let mut stack = vec![scene.root()];
    while let Some(id) = stack.pop() {
        match scene.kind(id) {
            NodeKind::Panel { quad, .. } => out.push(quad.fill),
            NodeKind::Text { color, .. } => out.push(*color),
            _ => {}
        }
        stack.extend(scene.children(id).iter().copied());
    }
    out
}
/// The window's pixels, drawn as a window would (and written to
/// `target/theme-snapshots/<name>.ppm` to look at).
fn snapshot(ui: &zgui::widgets::Ui, name: &str) -> Vec<u8> {
    let mut gpu = zgui_gpu::GpuRenderer::new(400, 300).expect("a GPU");
    gpu.install_text(&mut ui.scene.borrow_mut());
    ui.prepare_frame();
    let full = [zgui::scene::Rect::new(0., 0., 400., 300.)];
    ui.scene.borrow_mut().flush();
    gpu.render(&ui.scene.borrow(), &full).unwrap();
    let pixels = gpu.readback().unwrap();
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target/theme-snapshots");
    if std::fs::create_dir_all(&dir).is_ok() {
        let mut ppm = b"P6 400 300 255\n".to_vec();
        for p in pixels.chunks(4) {
            ppm.extend_from_slice(&p[..3]);
        }
        let _ = std::fs::write(dir.join(format!("{name}.ppm")), ppm);
    }
    pixels
}

#[test]
fn any_theme_styles_it_the_light_theme_too() {
    use zgui::scene::Color;
    let mut app = App::new();
    app.settle();
    // Its own theme: exactly the palette theme.luau used to hold.
    assert_eq!(&*app.h.ui.theme().current(), "terminal-glass");
    let glass = colors(&app.h.ui);
    assert!(
        glass.contains(&Color(0x13, 0x14, 0x18, 0x73)),
        "the glass tint"
    );
    assert!(glass.contains(&Color(0x0a, 0x0b, 0x0e, 0x4d)), "the pane");
    assert!(glass.contains(&Color(255, 255, 255, 0xeb)), "the text");
    let dark = snapshot(&app.h.ui, "terminal-glass");
    // The built-in light theme knows nothing of the terminal, yet styles it:
    // its own tokens default to standard ones.
    app.h.ui.theme().set(zgui::theme::LIGHT).unwrap();
    app.settle();
    let light = colors(&app.h.ui);
    assert!(
        light.contains(&Color(0xf5, 0xf6, 0xf8, 0xb3)),
        "light glass"
    );
    assert!(
        light.contains(&Color(0xec, 0xee, 0xf2, 255)),
        "panes on the sunken surface"
    );
    assert!(light.contains(&Color(0x1a, 0x1f, 0x29, 255)), "dark text");
    assert!(
        !light.contains(&Color(255, 255, 255, 0xeb)),
        "no glass text left"
    );
    let lit = snapshot(&app.h.ui, "terminal-light");
    // Beside the panes, only the window's tint shows: it is light now.
    let at = |pixels: &[u8]| {
        let i = (150 * 400 + 2) * 4;
        pixels[i] as u32 + pixels[i + 1] as u32 + pixels[i + 2] as u32
    };
    assert!(at(&lit) > at(&dark) + 200, "{} vs {}", at(&lit), at(&dark));
    // Back to its own theme, as it was.
    app.h.ui.theme().set("terminal-glass").unwrap();
    app.settle();
    assert_eq!(colors(&app.h.ui).len(), glass.len());
    assert!(colors(&app.h.ui).contains(&Color(0x0a, 0x0b, 0x0e, 0x4d)));
}
