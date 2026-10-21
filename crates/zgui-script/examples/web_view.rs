//! A web page in a Luau interface, with a frosted popover over it.
//! Run: cargo run --release -p zgui-script --example web_view
//! Edit `examples/web_view/app.luau` and save to reload it.
use std::{path::Path, time::Duration};
use zgui_desktop::{Application, WindowOptions};
use zgui_script::ScriptHost;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("examples/web_view/app.luau");
    Application::new()
        .window(WindowOptions {
            title: "zgui · web view".into(),
            width: 900.,
            height: 640.,
            ..Default::default()
        })
        .run(move |cx| {
            let host = ScriptHost::new(&cx.ui.runtime, script);
            let _ = host.reload();
            cx.tasks.spawn(host.watch(Duration::from_millis(250)));
            cx.render(host.view());
        })
}
