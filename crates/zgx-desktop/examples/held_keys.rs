//! Native X11 focus-transfer regression; run with --smoke-test and held_keys_smoke.py.
use std::{cell::Cell, rc::Rc, time::Duration};
use zgx::compose::prelude::*;
use zgx_desktop::{Application, WindowContext, WindowOptions};
fn form(cx: &mut WindowContext, name: &'static str, smoke: bool) {
    let value = cx.ui.signal(String::new());
    let actions = Rc::new(Cell::new(0));
    let write = actions.clone();
    cx.render(
        column()
            .p(20.)
            .gap(12.)
            .child(text(name).h(24.))
            .child(text_input("Text", value.clone()).size(300., 40.))
            .child(
                button()
                    .child(text("Action"))
                    .size(300., 40.)
                    .on_click(move || write.set(write.get() + 1)),
            ),
    );
    // The modifiers the window says are held: whether Control was seen
    // down, and what is held at the end.
    let held = cx.ui.held_keys();
    let saw = Rc::new(Cell::new(false));
    let seen = saw.clone();
    let watch = held.clone();
    let effect = cx.ui.runtime.effect(move || {
        if watch.get().control {
            seen.set(true);
        }
    });
    if smoke {
        cx.on_closed(move || {
            let _ = &effect;
            println!(
                "HELD {name} value={:?} actions={}",
                value.get(),
                actions.get()
            );
            println!(
                "MODS {name} saw_control={} now_control={}",
                saw.get(),
                held.get().control
            );
        });
    }
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let smoke = std::env::args().any(|arg| arg == "--smoke-test");
    Application::new()
        .window(WindowOptions {
            title: "zgx held keys source".into(),
            width: 360.,
            height: 200.,
            ..Default::default()
        })
        .run(move |cx| {
            form(cx, "source", smoke);
            let child = cx.windows.open(
                WindowOptions {
                    title: "zgx held keys target".into(),
                    width: 360.,
                    height: 200.,
                    ..Default::default()
                },
                move |cx| form(cx, "target", smoke),
            );
            if smoke {
                let root = cx.window.clone();
                cx.tasks.spawn(async move {
                    zgx::timer::sleep(Duration::from_secs(9)).await;
                    child.close();
                    root.close();
                });
            }
        })
}
