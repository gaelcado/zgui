//! Zeron's UI kit and styleguide, in Luau: a workbench showing every
//! component of `examples/styleguide/kit` in every variant and state, on
//! Zeron's tokens (`zeron-dark.json`, `zeron-light.json`), with controls
//! for theme, density, zoom and motion. The Apps page opens the kit's mini
//! apps (`app_*.luau`) in windows of their own.
//! Run: cargo run --release -p zgui-script --example styleguide
//! Edit `examples/styleguide/**/*.luau` and save to reload it.
use std::{path::PathBuf, sync::Arc, time::Duration};
use zgui_desktop::{Application, FontData, Glass, Titlebar, WindowContext, WindowOptions};
use zgui_script::{ScriptHost, Value};

const TITLE: &str = "Zeron UI · styleguide";
const WIDTH: f64 = 1280.;
const HEIGHT: f64 = 860.;

fn dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/styleguide")
}

/// A mini app's window: `app_<name>.luau` beside the workbench, in a
/// window shaped for it.
fn app_window(name: &str) -> Option<WindowOptions> {
    let (title, width, height, titlebar, decorations) = match name {
        "zeron" => ("Zeron", 1180., 760., Titlebar::Inset, true),
        "palette" => ("Palette", 560., 440., Titlebar::Hidden, false),
        "settings" => ("Zeron Settings", 760., 600., Titlebar::Inset, true),
        _ => return None,
    };
    Some(WindowOptions {
        title: title.into(),
        width,
        height,
        transparent: true,
        titlebar,
        glass: Some(Glass::default()),
        decorations: decorations && cfg!(target_os = "macos"),
        min_size: Some((420., 320.)),
        ..Default::default()
    })
}

/// Mounts `script` in `cx` with the actions every script here gets: the
/// layout inspector, closing its own window, and opening a mini app.
fn mount(cx: &mut WindowContext, script: PathBuf) {
    let host = ScriptHost::new(&cx.ui.runtime, script).app_id("zeron-styleguide");
    let toggle = {
        let host = host.clone();
        let on = std::cell::Cell::new(false);
        move |_| {
            on.set(!on.get());
            host.inspect(on.get());
        }
    };
    host.action("inspect", toggle);
    // The titlebar places its window controls beside macOS's traffic lights.
    host.shared("platform", std::env::consts::OS);
    // STYLEGUIDE_PAGE=<id> opens the workbench on a page.
    host.shared(
        "start_page",
        std::env::var("STYLEGUIDE_PAGE")
            .unwrap_or_default()
            .as_str(),
    );
    let window = cx.window.clone();
    host.action("close_window", move |_| window.close());
    let windows = cx.windows.clone();
    host.action("open_app", move |name: Value| {
        let Value::Str(name) = name else { return };
        let Some(options) = app_window(&name) else {
            eprintln!("styleguide: no app `{name}`");
            return;
        };
        let script = dir().join(format!("app_{name}.luau"));
        windows.open(options, move |cx| mount(cx, script));
    });
    if let Err(error) = host.reload() {
        eprintln!("styleguide: {error}");
    }
    cx.tasks.spawn(host.watch(Duration::from_millis(250)));
    cx.render(host.view());
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut app = Application::new();
    // Zeron's faces: variable Geist and Geist Mono.
    for bytes in [
        &include_bytes!("../../zgui-desktop/examples/support/fonts/GeistVariable.ttf")[..],
        include_bytes!("../../zgui-desktop/examples/support/fonts/GeistMonoVariable.ttf"),
    ] {
        app = app.font(FontData::new(Arc::<[u8]>::from(bytes))?);
    }
    // `STYLEGUIDE_APP=zeron` opens a mini app on its own.
    if let Ok(name) = std::env::var("STYLEGUIDE_APP") {
        let options = app_window(&name).ok_or_else(|| format!("no app `{name}`"))?;
        let script = dir().join(format!("app_{name}.luau"));
        return app.window(options).run(move |cx| mount(cx, script));
    }
    app.window(WindowOptions {
        title: TITLE.into(),
        width: WIDTH,
        height: HEIGHT,
        transparent: true,
        titlebar: Titlebar::Inset,
        glass: Some(Glass::default()),
        decorations: cfg!(target_os = "macos"),
        min_size: Some((960., 600.)),
        ..Default::default()
    })
    .run(move |cx| mount(cx, dir().join("app.luau")))
}
