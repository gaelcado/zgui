//! A terminal multiplexer written in Luau: tabs, split panes you can resize
//! and drag, and Ghostty terminals, on frosted glass.
//! Run: cargo run --release -p zgui-desktop --features ghostty --example terminal
//! The interface is `examples/terminal/app.luau` and the modules it
//! requires (see `docs/reference/app-structure.md`); edit and save to reload it
//! (shells keep running).
//!
//! Shells outlive the window: they run in a session server (this binary,
//! `--session-daemon`) and each pane attaches to its own (`--attach`), so
//! closing the app detaches them and opening it again, with the tabs and
//! panes it had, attaches them again (see `terminal/session.rs`).
#[path = "terminal/activity.rs"]
mod activity;
#[path = "terminal/program_status.rs"]
mod program_status;
#[path = "support/script_menus.rs"]
mod script_menus;
#[path = "terminal/session.rs"]
mod session;

use std::{path::Path, time::Duration};
use zgui_desktop::{Application, FontData, Glass, Titlebar, WindowOptions};
use zgui_script::{ScriptHost, Value};

const TITLE: &str = "Terminal";
const WIDTH: f64 = 1180.;
const HEIGHT: f64 = 760.;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // The session server, or a pane's client to it.
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--session-daemon") {
        session::daemon();
    }
    if let Some(at) = args.iter().position(|a| a == "--attach") {
        let id = args.get(at + 1).cloned().unwrap_or_default();
        let cwd = args
            .iter()
            .position(|a| a == "--cwd")
            .and_then(|at| args.get(at + 1).cloned())
            .unwrap_or_default();
        session::attach(&id, &cwd);
    }
    session::ensure_daemon();
    zgui_desktop::resolve_terminal_processes(session::resolve);
    // In an app bundle (scripts/zterm-app.sh), the interface it carries;
    // else the source tree's, live.
    let script = std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.parent()?.join("Resources/terminal/app.luau")))
        .filter(|bundled| bundled.exists())
        .unwrap_or_else(|| {
            Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/terminal/app.luau")
        });
    let mut application = Application::new();
    // Geist, the interface's typeface (`font.sans` in terminal/glass.json).
    for bytes in [
        &include_bytes!("support/fonts/Geist.ttf")[..],
        include_bytes!("support/fonts/Geist-Medium.ttf"),
        include_bytes!("support/fonts/Geist-SemiBold.ttf"),
    ] {
        application = application.font(FontData::new(std::sync::Arc::<[u8]>::from(bytes))?);
    }
    application
        .window(WindowOptions {
            title: TITLE.into(),
            width: WIDTH,
            height: HEIGHT,
            decorations: cfg!(target_os = "macos"),
            min_size: Some((520., 360.)),
            // Frosted glass, content under inset traffic lights.
            titlebar: Titlebar::Inset,
            glass: Some(Glass::default()),
            ..Default::default()
        })
        .run(move |cx| {
            let host = ScriptHost::new(&cx.ui.runtime, script);
            // The script's view of the window: its corner radius (panes
            // stay concentric with it) and where the app was started.
            let radius = host.shared("window_radius", 10.);
            let corner = cx.window_info.corner_radius.clone();
            let follow_radius = cx.ui.runtime.effect(move || {
                let r = corner.get();
                if r > 0. {
                    radius.set(r.into());
                }
            });
            // Opened from the Finder or `open`, the app starts in `/`: new
            // shells start at home then, as Terminal's do.
            let launch = std::env::current_dir()
                .ok()
                .filter(|dir| dir != std::path::Path::new("/"))
                .or_else(|| std::env::var_os("HOME").map(Into::into))
                .map(|dir| dir.to_string_lossy().into_owned())
                .unwrap_or_default();
            host.shared("launch_dir", launch.as_str());
            let home = std::env::var("HOME").unwrap_or_default();
            host.shared("home", home.as_str());
            // Panes attach to the session server by this command; it keeps
            // their shells. The layout they were in comes back from disk.
            let attach = session::attach_command("", "");
            let attach = attach.split(" --attach").next().unwrap_or_default();
            host.shared("attach", attach);
            let layout_file = session::dir().join("layout.json");
            let saved = std::fs::read_to_string(&layout_file)
                .ok()
                .and_then(|json| Value::from_json(&json))
                .unwrap_or(Value::Nil);
            host.shared("saved_layout", saved);
            host.action("end_session", |id| {
                if let Value::Str(id) = id {
                    session::kill(&id);
                }
            });
            // Every session's activity, from the session server as it
            // changes (an agent in a tab not shown, or finished while the
            // window was closed): what the agents sidebar lists. A thread
            // waits on the server; nothing runs while nothing changes.
            let agents = host.shared("agents", Value::Nil);
            let (heard, mut hearing) = zgui::task::latest::<String>();
            std::thread::spawn(move || session::watch(|json| heard.send(json)));
            cx.tasks.spawn(async move {
                while let Some(json) = hearing.recv().await {
                    agents.set(Value::from_json(&json).unwrap_or(Value::Nil));
                }
            });
            host.action("seen_session", |id| {
                if let Value::Str(id) = id {
                    session::seen(&id);
                }
            });
            host.action("keep_sessions", |ids| {
                let ids: Vec<String> = match ids {
                    Value::List(ids) => ids
                        .iter()
                        .filter_map(|id| match id {
                            Value::Str(id) => Some(id.to_string()),
                            _ => None,
                        })
                        .collect(),
                    _ => Vec::new(),
                };
                session::keep(&ids);
            });
            // Saved a moment after it changes (a divider drag changes it
            // on every move), and when the window closes.
            let pending = std::rc::Rc::new(std::cell::RefCell::new(None::<String>));
            let save = {
                let (pending, layout_file) = (pending.clone(), layout_file.clone());
                move || {
                    if let Some(json) = pending.borrow_mut().take() {
                        let _ = std::fs::create_dir_all(session::dir());
                        let temp = layout_file.with_extension("json.tmp");
                        if std::fs::write(&temp, json).is_ok() {
                            let _ = std::fs::rename(&temp, &layout_file);
                        }
                    }
                }
            };
            {
                let pending = pending.clone();
                host.action("save_layout", move |layout| {
                    *pending.borrow_mut() = Some(layout.to_json());
                });
            }
            {
                let save = save.clone();
                cx.tasks.spawn(async move {
                    loop {
                        zgui::timer::sleep(Duration::from_millis(500)).await;
                        save();
                    }
                });
            }
            let (window, zoomed) = (cx.window.clone(), std::cell::Cell::new(false));
            host.action("zoom_window", move |_| {
                zoomed.set(!zoomed.get());
                window.set_maximized(zoomed.get());
            });
            let window = cx.window.clone();
            host.action("close_window", move |_| window.close());
            let window = cx.window.clone();
            host.action("set_title", move |title| {
                if let Value::Str(title) = title {
                    window.set_title(title.to_string());
                }
            });

            let _ = host.reload();
            cx.tasks.spawn(host.watch(Duration::from_millis(250)));

            // The menus are the script's commands: their shortcuts work
            // wherever focus is, a terminal included.
            let commands = host.commands();
            let windows = cx.windows.clone();
            let menus = cx.ui.runtime.effect(move || {
                let list = commands.get();
                if let Err(error) = windows.set_menus(script_menus::menus(&list)) {
                    eprintln!("terminal: menus: {error}");
                }
            });
            let commands = host.clone();
            cx.on_menu_action(move |action| {
                commands.run_command(&action.0);
            });
            let keep = std::cell::RefCell::new(Some((menus, follow_radius)));
            cx.on_closed(move || {
                save();
                drop(keep.borrow_mut().take());
            });
            cx.render(host.view());
        })
}
