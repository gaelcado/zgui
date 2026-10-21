//! A terminal multiplexer written in Luau: tabs, split panes you can resize
//! and drag, and Ghostty terminals, on frosted glass.
//! Run: cargo run --release -p zgui-desktop --features ghostty --example terminal
//! The interface is `examples/terminal/*.luau`; edit and save to reload it
//! (shells keep running).
//!
//! Shells outlive the window: they run in a session server (this binary,
//! `--session-daemon`) and each pane attaches to its own (`--attach`), so
//! closing the app detaches them and opening it again, with the tabs and
//! panes it had, attaches them again (see `terminal/session.rs`).
#[cfg(target_os = "macos")]
#[path = "support/glass.rs"]
mod glass;
#[path = "terminal/session.rs"]
mod session;

use std::{path::Path, time::Duration};
use zgui::input::{Key, Modifiers};
use zgui_desktop::{AppMenu, AppMenuEntry, Application, FontData, MenuAccelerator, WindowOptions};
use zgui_script::{Command, ScriptHost, Value};

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
        .unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/terminal/app.luau"));
    let mut application = Application::new();
    // Geist, the interface's typeface (`theme.font`).
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
            transparent: true,
            decorations: cfg!(target_os = "macos"),
            min_size: Some((520., 360.)),
            ..Default::default()
        })
        .run(move |cx| {
            let host = ScriptHost::new(&cx.ui.runtime, script);
            // The script's view of the window: its corner radius (panes
            // stay concentric with it) and where the app was started.
            let radius = host.shared("window_radius", 10.);
            let launch = std::env::current_dir()
                .ok()
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
            // The window keeps its title until the glass finds it by it;
            // the script's titles wait until then.
            let titles = std::rc::Rc::new(std::cell::RefCell::new((false, None::<String>)));
            #[cfg(target_os = "macos")]
            {
                let window = cx.window.clone();
                let radius = radius.clone();
                let titles = titles.clone();
                cx.tasks.spawn(async move {
                    zgui::timer::sleep(Duration::from_millis(1)).await;
                    if glass::inset_titlebar(TITLE) {
                        window.set_inner_size(WIDTH, HEIGHT);
                    }
                    let pending = {
                        let mut titles = titles.borrow_mut();
                        titles.0 = true;
                        titles.1.take()
                    };
                    if let Some(title) = pending {
                        window.set_title(title);
                    }
                    if let Some(r) = glass::corner_radius(TITLE) {
                        radius.set(r.into());
                    }
                });
            }
            #[cfg(not(target_os = "macos"))]
            let _ = radius;

            let window = cx.window.clone();
            host.action("drag_window", move |_| window.drag_window());
            let (window, zoomed) = (cx.window.clone(), std::cell::Cell::new(false));
            host.action("zoom_window", move |_| {
                zoomed.set(!zoomed.get());
                window.set_maximized(zoomed.get());
            });
            let window = cx.window.clone();
            host.action("close_window", move |_| window.close());
            let window = cx.window.clone();
            if !cfg!(target_os = "macos") {
                titles.borrow_mut().0 = true;
            }
            host.action("set_title", move |title| {
                let Value::Str(title) = title else { return };
                let mut titles = titles.borrow_mut();
                if titles.0 {
                    window.set_title(title.to_string());
                } else {
                    titles.1 = Some(title.to_string());
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
                if let Err(error) = windows.set_menus(menus(&list)) {
                    eprintln!("terminal: menus: {error}");
                }
            });
            let commands = host.clone();
            cx.on_menu_action(move |action| {
                commands.run_command(&action.0);
            });
            let keep = std::cell::RefCell::new(Some(menus));
            cx.on_closed(move || {
                save();
                drop(keep.borrow_mut().take());
            });
            cx.render(host.view());
        })
}

/// Menus in the order the script first names them, items in its order.
fn menus(commands: &[Command]) -> Vec<AppMenu> {
    let mut menus: Vec<AppMenu> = Vec::new();
    for command in commands {
        let index = match menus.iter().position(|m| m.label == command.menu) {
            Some(index) => index,
            None => {
                menus.push(AppMenu::new(command.menu.clone(), []));
                menus.len() - 1
            }
        };
        let entry = if command.separator {
            AppMenuEntry::Separator
        } else {
            let item = AppMenuEntry::item(command.title.clone(), command.id.as_str());
            match command.key.as_deref().and_then(accelerator) {
                Some(key) => item.accelerator(key),
                None => item,
            }
        };
        menus[index].entries.push(entry);
    }
    menus
}

/// `cmd+shift+d`, `cmd+alt+arrowleft`, `cmd+1`, `cmd+[` as an accelerator.
fn accelerator(text: &str) -> Option<MenuAccelerator> {
    let mut modifiers = Modifiers::default();
    let mut parts: Vec<&str> = text.split('+').collect();
    // `cmd++` would be a plus key; none of ours use it.
    let key = parts.pop()?.to_ascii_lowercase();
    for part in parts {
        match part.to_ascii_lowercase().as_str() {
            "cmd" | "command" | "super" | "meta" => modifiers.meta = true,
            "ctrl" | "control" => modifiers.control = true,
            "alt" | "opt" | "option" => modifiers.alt = true,
            "shift" => modifiers.shift = true,
            other => {
                eprintln!("terminal: unknown modifier `{other}` in `{text}`");
                return None;
            }
        }
    }
    let key = match key.as_str() {
        "arrowleft" | "left" => Key::ArrowLeft,
        "arrowright" | "right" => Key::ArrowRight,
        "arrowup" | "up" => Key::ArrowUp,
        "arrowdown" | "down" => Key::ArrowDown,
        "enter" | "return" => Key::Enter,
        "tab" => Key::Tab,
        "escape" | "esc" => Key::Escape,
        "backspace" => Key::Backspace,
        "delete" => Key::Delete,
        "home" => Key::Home,
        "end" => Key::End,
        "pageup" => Key::PageUp,
        "pagedown" => Key::PageDown,
        "space" => Key::Space,
        f if f.len() > 1 && f.starts_with('f') && f[1..].parse::<u8>().is_ok() => {
            Key::Function(f[1..].parse().ok()?)
        }
        single if single.chars().count() == 1 => Key::Character(single.into()),
        other => {
            eprintln!("terminal: unknown key `{other}` in `{text}`");
            return None;
        }
    };
    Some(MenuAccelerator::new(key, modifiers))
}
