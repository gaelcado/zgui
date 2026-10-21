//! Notes in Luau: the same app as NSH's `examples/notes`, for comparison.
//! Run: cargo run --release -p zgui-script --example notes
//! Edit `examples/notes/app.luau` and save to reload it; notes are kept.
//!
//! Rust owns what a script can't reach: the native menu bar (its commands
//! arrive in the script as `ui.shared("command")`) and the notes file (the
//! script edits `ui.shared("notes")`, Rust writes it to disk on change).
#[cfg(target_os = "macos")]
#[path = "../../zgui-desktop/examples/support/glass.rs"]
mod glass;

use std::{path::PathBuf, rc::Rc, time::Duration};
use zgui::input::{Key, Modifiers};
use zgui_desktop::{AppMenu, AppMenuEntry, Application, MenuAccelerator, WindowOptions};
use zgui_script::{ScriptHost, Value};

const TITLE: &str = "zgui · notes";
const WIDTH: f64 = 1200.;
const HEIGHT: f64 = 800.;

fn menus() -> Vec<AppMenu> {
    let key = |c: &str| Key::Character(c.into());
    vec![
        AppMenu::new(
            "File",
            [
                AppMenuEntry::item("New Note", "new")
                    .accelerator(MenuAccelerator::primary(key("n"))),
                AppMenuEntry::item("Duplicate Note", "duplicate")
                    .accelerator(MenuAccelerator::primary(key("d"))),
                AppMenuEntry::item("Pin Note", "pin"),
                AppMenuEntry::item("Delete Note…", "delete"),
            ],
        ),
        AppMenu::new(
            "View",
            [AppMenuEntry::item("Show Preview", "preview")
                .checked(true)
                .accelerator(MenuAccelerator::new(
                    key("p"),
                    Modifiers {
                        shift: true,
                        meta: cfg!(target_os = "macos"),
                        control: !cfg!(target_os = "macos"),
                        ..Default::default()
                    },
                ))],
        ),
    ]
}

fn store() -> PathBuf {
    let home = std::env::var_os("HOME").map_or_else(|| PathBuf::from("."), PathBuf::from);
    home.join(".zgui-notes.json")
}

fn to_json(value: &Value) -> serde_json::Value {
    match value {
        Value::Nil => serde_json::Value::Null,
        Value::Bool(b) => (*b).into(),
        Value::Num(n) => (*n).into(),
        Value::Str(s) => s.as_ref().into(),
        Value::List(items) => items.iter().map(to_json).collect(),
        Value::Map(entries) => entries
            .iter()
            .map(|(k, v)| (k.to_string(), to_json(v)))
            .collect::<serde_json::Map<_, _>>()
            .into(),
    }
}

fn from_json(json: &serde_json::Value) -> Value {
    match json {
        serde_json::Value::Null => Value::Nil,
        serde_json::Value::Bool(b) => Value::Bool(*b),
        serde_json::Value::Number(n) => Value::Num(n.as_f64().unwrap_or(0.)),
        serde_json::Value::String(s) => Value::Str(s.as_str().into()),
        serde_json::Value::Array(items) => Value::List(items.iter().map(from_json).collect()),
        serde_json::Value::Object(entries) => {
            let mut entries: Vec<(Rc<str>, Value)> = entries
                .iter()
                .map(|(k, v)| (k.as_str().into(), from_json(v)))
                .collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            Value::Map(entries.into())
        }
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let script = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/notes/app.luau");
    Application::new()
        .menus(menus())?
        .window(WindowOptions {
            title: TITLE.into(),
            width: WIDTH,
            height: HEIGHT,
            transparent: true,
            decorations: cfg!(target_os = "macos"),
            min_size: Some((760., 480.)),
            ..Default::default()
        })
        .run(move |cx| {
            let host = ScriptHost::new(&cx.ui.runtime, script);

            // Saved notes, or nil: the script seeds its welcome notes.
            let saved = std::fs::read_to_string(store())
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .map_or(Value::Nil, |json| from_json(&json));
            let notes = host.shared("notes", saved);
            let save = cx.ui.runtime.effect(move || {
                let value = notes.get();
                if !matches!(value, Value::Nil) {
                    let _ = std::fs::write(store(), to_json(&value).to_string());
                }
            });

            // The preview's state is shared, so the menu's check mark follows
            // the script's toolbar button too.
            let preview = host.shared("preview", true);
            let windows = cx.windows.clone();
            let check = cx.ui.runtime.effect({
                let preview = preview.clone();
                move || {
                    let _ = windows.set_menu_state("preview", None, Some(preview.get().truthy()));
                }
            });

            // Other menu commands reach the script as `{ name, seq }`.
            let command = host.shared("command", Value::Nil);
            let mut seq = 0.;
            cx.on_menu_action(move |action| {
                let _keep = (&save, &check);
                if action.0 == "preview" {
                    preview.set(Value::Bool(!preview.with_untracked(Value::truthy)));
                    return;
                }
                seq += 1.;
                command.set(Value::Map(
                    [
                        ("name".into(), Value::Str(action.0.as_str().into())),
                        ("seq".into(), Value::Num(seq)),
                    ]
                    .into(),
                ));
            });

            let radius = host.shared("window_radius", 10.);
            #[cfg(target_os = "macos")]
            {
                let window = cx.window.clone();
                cx.tasks.spawn(async move {
                    zgui::timer::sleep(Duration::from_millis(1)).await;
                    if glass::inset_titlebar(TITLE) {
                        window.set_inner_size(WIDTH, HEIGHT);
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
            let _ = host.reload();
            cx.tasks.spawn(host.watch(Duration::from_millis(250)));
            cx.render(host.view());
        })
}
