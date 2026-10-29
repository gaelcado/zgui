//! The glass example (examples/glass), run headless: the sidebar on the
//! glass and the inset well beside it, an item opening, a split, the
//! sidebar shutting, a message sent, and the light theme. With
//! `STYLEGUIDE_SNAPSHOT=<dir>` it writes PPM snapshots there.
mod common;

use common::Harness;
use std::path::Path;
use zgx_script::ScriptHost;

const WIDTH: f32 = 1180.;
const HEIGHT: f32 = 760.;
const APP: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/examples/glass/app.luau");

fn healthy(h: &Harness) {
    if let Some(e) = h.error() {
        panic!("script error: {e}");
    }
    let warnings = h.host.warnings();
    assert!(warnings.is_empty(), "warnings: {warnings:#?}");
}

fn snapshot(h: &Harness, name: &str) {
    let Some(dir) = std::env::var_os("STYLEGUIDE_SNAPSHOT") else {
        return;
    };
    let dir = Path::new(&dir);
    let _ = std::fs::create_dir_all(dir);
    h.ui.prepare_frame();
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
        .write_ppm(&dir.join(format!("glass_{name}.ppm")))
        .unwrap();
}

#[test]
fn the_glass_example_insets_its_wells_splits_and_shuts_its_sidebar() {
    let mut h = Harness::new(|runtime| ScriptHost::new(runtime, APP));
    h.ui.scene.borrow_mut().resize(WIDTH, HEIGHT);
    h.frames(30);
    healthy(&h);
    snapshot(&h, "chat");

    // The sidebar sits on the glass at its width; the well is inset from
    // the window's top, right and bottom edges.
    let side = h.bounds("sidebar");
    assert_eq!(side.width, 236.);
    let well = h.bounds("well_1");
    assert_eq!(well.y, 8.);
    assert_eq!(well.x + well.width, WIDTH - 8.);
    assert_eq!(well.y + well.height, HEIGHT - 8.);
    assert!(well.x > side.width, "the well starts past the sidebar");

    // An item opens in the well.
    h.click("item_story");
    h.frames(30);
    healthy(&h);
    assert!(h.texts().iter().any(|t| t == "Three thousand word story"));
    snapshot(&h, "doc");

    // A split puts a second well beside the first, a gap apart.
    assert!(h.host.run_command("split"));
    h.frames(30);
    healthy(&h);
    let (a, b) = (h.bounds("well_1"), h.bounds("well_2"));
    assert!((b.x - (a.x + a.width) - 8.).abs() < 0.5, "{a:?} {b:?}");
    assert!((a.width - b.width).abs() < 1., "equal shares: {a:?} {b:?}");
    // A sidebar click opens in the focused well, the second.
    h.click("item_build");
    h.frames(30);
    assert!(h.texts().iter().any(|t| t.starts_with("$ cargo build")));
    snapshot(&h, "split");
    assert!(h.host.run_command("close_split"));
    h.frames(30);
    assert!(h.find("well_2").is_none());

    // Shutting the sidebar eases it to nothing; the well takes the window
    // and its header the sidebar's toggle.
    assert!(h.host.run_command("sidebar"));
    h.frames(4);
    let mid = h.bounds("sidebar").width;
    assert!(mid > 1. && mid < 235., "eases: {mid}");
    h.frames(30);
    assert_eq!(h.bounds("sidebar").width, 0.);
    assert_eq!(h.bounds("well_1").x, 8.);
    assert!(h.find("well_sidebar_toggle").is_some());
    snapshot(&h, "collapsed");
    h.click("well_sidebar_toggle");
    h.frames(30);
    assert_eq!(h.bounds("sidebar").width, 236.);

    // A message sent in a chat shows in its thread.
    h.click("item_plan");
    h.frames(30);
    h.type_text("composer_plan", "And the notarized build?");
    h.click("send_plan");
    h.frames(30);
    healthy(&h);
    assert!(h.texts().iter().any(|t| t == "And the notarized build?"));

    // The light theme restyles it in place.
    assert!(h.host.run_command("appearance"));
    h.frames(30);
    healthy(&h);
    assert_eq!(&*h.ui.theme().current(), "glass-light");
    snapshot(&h, "light");
}
