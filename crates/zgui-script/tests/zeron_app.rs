//! The Zeron app (examples/styleguide/app_zeron.luau), headless: its two
//! layouts around the same columns, its two routes each under the panel
//! policy, the right pane's tabs and ⌘W, and back and forward. With
//! `STYLEGUIDE_SNAPSHOT=<dir>` it writes PPM snapshots there.
mod common;

use common::Harness;
use std::path::Path;
use zgui::input::{InputEvent, Key, Modifiers};
use zgui_script::ScriptHost;

const WIDTH: f32 = 1280.;
const HEIGHT: f32 = 800.;
/// The shell's inset (`zeron.well.gap`): from the window's edges to a card,
/// and between two cards.
const INSET: f32 = 6.;

fn app() -> Harness {
    let h = Harness::new(|runtime| {
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
    // `STYLEGUIDE_GPU=1`: through the GPU renderer, offscreen, as the window
    // draws (blur, layers and shadows as they look there).
    if std::env::var_os("STYLEGUIDE_GPU").is_some() {
        let scale: f32 = std::env::var("STYLEGUIDE_SCALE")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(1.);
        let (w, hgt) = ((WIDTH * scale) as u32, (HEIGHT * scale) as u32);
        let mut gpu = zgui_gpu::GpuRenderer::new(w, hgt).expect("a GPU adapter");
        gpu.set_scale_factor(scale);
        for bytes in [
            &include_bytes!("../../zgui-desktop/examples/support/fonts/GeistVariable.ttf")[..],
            &include_bytes!("../../zgui-desktop/examples/support/fonts/GeistMonoVariable.ttf")[..],
        ] {
            gpu.text_system()
                .borrow_mut()
                .db_mut()
                .load_font_data(bytes.to_vec());
        }
        gpu.render(
            &h.ui.scene.borrow(),
            &[zgui::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
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
    let mut raster = zgui_desktop::raster::Raster::new(WIDTH as usize, HEIGHT as usize);
    for bytes in [
        &include_bytes!("../../zgui-desktop/examples/support/fonts/GeistVariable.ttf")[..],
        &include_bytes!("../../zgui-desktop/examples/support/fonts/GeistMonoVariable.ttf")[..],
    ] {
        raster.register_font(&zgui_gpu::text::FontData::new(bytes).unwrap());
    }
    raster.render(
        &h.ui.scene.borrow(),
        &[zgui::scene::Rect::new(0., 0., WIDTH, HEIGHT)],
    );
    raster
        .write_ppm(&dir.join(format!("zeron_{name}.ppm")))
        .unwrap();
}

/// A secondary click near the left of node `id` (its context menu).
fn secondary(h: &mut Harness, id: &str) {
    let b = h.bounds(id);
    let (x, y) = (b.x + 20., b.y + b.height / 2.);
    let button = zgui::input::PointerButton::Secondary;
    h.ui.dispatch(zgui::input::InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(zgui::input::InputEvent::PointerUp { x, y, button });
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
        cmd(&mut h, "\\", false);
        assert!(h.bounds("zcols_sidebar").width < 0.5);
        assert!(h.find("well_sidebar").is_some());
        assert_eq!(h.bounds("well_conversation").x, INSET);
        snapshot(&h, "glass_shut");
        cmd(&mut h, "\\", false);

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
        // chat arrives at rest with its pane as it was.
        cmd(&mut h, "\\", false);
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

        // Forward again: the board's pane is still open.
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
        h.click("agent_a1");
        h.frames(40);
        assert!(h.find("zt1_zt1_a").is_some(), "back to the first tab");
        h.click("agent_a3");
        h.frames(40);
        healthy(&h);
        assert!(h.find("ztab_t5").is_some(), "a tab for the third agent");
        snapshot(&h, "tabs_sidebar");
        cmd(&mut h, "\\", false);
        assert!(h.bounds("ztabsh_sidebar").width < 0.5);
    });
}

#[test]
fn a_side_chat_forks_the_conversation_beside_it() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "k", false);
        h.type_text("palette_input", "side chat");
        h.frames(10);
        h.click("palette_side_chat");
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
    use zgui::input::PointerButton::Primary;
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
    h.ui.dispatch(InputEvent::PointerUp {
        x: tx,
        y: ty,
        button: Primary,
    });
    h.frames(40);
    healthy(h);
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
        drag_pane(&mut h, "zt2_zt1_b", "ztopbar_end", |h| {
            assert!(h.find("ztopbar_slot").is_some(), "the ghost tab");
        });
        assert!(h.find("ztab_t4").is_some(), "a space of its own");
        assert!(h.find("zt4_zt1_b").is_some(), "showing the pane");
        assert!(h.find("ztopbar_slot").is_none(), "the ghost goes");
        assert!(
            h.text("ztab_t4").contains("zsh"),
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
            "side_cross_platform_zgui",
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
            h.find("thread_h4").is_none(),
            "the archived shelf is folded"
        );
        // Open sections' chevrons point down, the folded shelf's right.
        assert_eq!(turn(&mut h, "side_pinned_chevron"), 90.);
        assert_eq!(turn(&mut h, "side_archived_chevron"), 0.);
        snapshot(&h, "sidebar");

        // Hovering the rows runs no script: the wash and the corner's
        // Archive are the engine's.
        let calls = h.calls();
        for id in ["agent_a1", "agent_a4", "agent_a3", "thread_h1"] {
            hover_id(&mut h, id);
        }
        h.frames(20);
        assert_eq!(h.calls(), calls, "hover ran the script");

        // The shelf opens, its chevron turning down; it shows what it holds
        // and pages in the rest.
        h.click("side_archived_header");
        h.frames(4);
        let mid = turn(&mut h, "side_archived_chevron");
        assert!(mid > 0. && mid < 90., "turning: {mid}");
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
        h.click("side_view");
        h.frames(20);
        h.click("side_view_compact");
        h.frames(20);
        assert_eq!(h.bounds("agent_a1").height, 61.);
        assert_eq!(h.bounds("thread_h1").height, 45.);
        assert_eq!(h.bounds("agent_a3").height, 63.);
        h.click("side_view");
        h.frames(20);
        h.click("side_view_project");
        h.frames(20);
        assert!(h.find("side_sessions").is_none());
        assert!(h.find("side_project_comet").is_some());
        snapshot(&h, "sidebar_tall");
        // A project's + starts a session there.
        hover_id(&mut h, "side_project_comet_header");
        h.click("side_project_comet_new");
        h.frames(30);
        healthy(&h);
        assert!(h.find("new_composer").is_some(), "the new session's canvas");

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
        h.ui.dispatch(zgui::input::InputEvent::PointerMove {
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
                zgui::scene::NodeKind::Panel { quad, .. } => quad.fill.3,
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

#[test]
fn command_return_on_an_empty_draft_sends_the_latest_queued_message() {
    deep(|| {
        let mut h = app();
        // The thread's composer shows how full its context is.
        assert!(h.find("composer_context").is_some(), "the context ring");
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
        let mut h = app();
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
        assert_eq!(
            h.bounds("sent_tools_1_live1_1").height,
            0.,
            "it opens from nothing"
        );
        h.frames(40);
        healthy(&h);
        assert_eq!(
            h.bounds("sent_tools_1_live1_1").height,
            32.,
            "and lands at a row's"
        );
        assert!(joined(&mut h, "sent_tools_1_header").contains("Searched once"));
        let more = h.wait_until(|h| {
            h.frames(1);
            h.find("sent_tools_1_live1_3").is_some()
        });
        assert!(more, "the third call");
        h.frames(5);
        snapshot(&h, "tools_arriving");
        h.frames(35);
        assert!(
            joined(&mut h, "sent_tools_1_header").contains("Read 1 file"),
            "{}",
            joined(&mut h, "sent_tools_1_header")
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

#[test]
fn a_tool_row_opens_on_its_call_its_output_its_diff_and_its_images() {
    deep(|| {
        let mut h = app();
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
        let images: Vec<zgui::scene::Rect> = {
            let scene = h.ui.scene.borrow();
            let mut out = Vec::new();
            let mut stack = vec![scene.root()];
            while let Some(n) = stack.pop() {
                if let zgui::scene::NodeKind::Image(_) = scene.kind(n) {
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
            h.texts().iter().any(|t| t == "k; done"),
            "the call wraps at 80 columns"
        );
        h.click("turn_1_tools_t1_1_head");
        h.click("turn_1_tools_t1_3_head");
        h.frames(30);
        assert!(says(&mut h, "@@ -404,7 +404,9 @@"));
        h.click("turn_1_tools_t1_3_head");
        h.click("turn_1_tools_t1_2_head");
        h.frames(30);
        let frame = h.bounds("turn_1_tools_t1_2_image_1");
        assert_eq!(frame.height, 220.);
        assert_eq!(frame.width, 330., "220 high at its 3:2");
        assert_eq!(
            h.bounds("turn_1_tools_t1_2_image_2").width,
            220. * 480. / 720.
        );
        h.click("turn_1_tools_t1_2_image_1");
        h.frames(30);
        healthy(&h);
        let shown = h.bounds("image_viewer_image");
        assert!(
            (shown.width - 720.).abs() < 0.5 && (shown.height - 480.).abs() < 0.5,
            "fitted at its own size: {shown:?}"
        );
        snapshot(&h, "image_viewer");
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
        h.ui.dispatch(zgui::input::InputEvent::Text("Ship it".into()));
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
        // Its × closes a space, the one under the pointer; the others close up.
        let third = h.bounds("ztab_t3").x;
        hover_id(&mut h, "ztab_t2");
        h.click("ztab_t2_close");
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
            button: zgui::input::PointerButton::Primary,
        });
        let (taps, _) = h.host.haptics();
        for step in 1..=10 {
            let x = fx + (to.x + 8. - fx) * step as f32 / 10.;
            h.ui.dispatch(InputEvent::PointerMove { x, y: fy });
            h.frames(2);
        }
        // Each swap taps the trackpad; hovering where it is taps nothing.
        let (swapped, last) = h.host.haptics();
        assert!(swapped > taps, "the tabs swapped without a tap");
        assert_eq!(last, Some(zgui::platform::Haptic::Alignment));
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
            button: zgui::input::PointerButton::Primary,
        });
        h.frames(40);
        healthy(&h);
        assert!(
            h.bounds("ztab_t4").x < h.bounds("ztab_t1").x,
            "dropped before the first: {:?} {:?}",
            h.bounds("ztab_t4"),
            h.bounds("ztab_t1")
        );
    });
}

/// Every text under node `id`, joined (a rolling label is a text a glyph).
fn joined(h: &mut Harness, id: &str) -> String {
    let node = h.find(id).unwrap_or_else(|| panic!("{id}"));
    let scene = h.ui.scene.borrow();
    let mut out = String::new();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let zgui::scene::NodeKind::Text { text, .. } = scene.kind(n) {
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
        assert_eq!(h.text("composer_input"), "/review @crates/zgui/compose.rs ");
        // The reference shows as a chip in the draft, and goes whole.
        let chips = |h: &mut Harness| {
            let input = h.find("composer_input").unwrap();
            let scene = h.ui.scene.borrow();
            let mut stack = vec![input];
            let mut n = 0;
            while let Some(node) = stack.pop() {
                if matches!(scene.kind(node), zgui::scene::NodeKind::Quad(q) if q.radius == 5.) {
                    n += 1;
                }
                stack.extend(scene.children(node).iter().copied());
            }
            n
        };
        assert_eq!(chips(&mut h), 1, "a chip");
        h.key(Key::Backspace);
        h.key(Key::Backspace);
        h.frames(2);
        assert_eq!(h.text("composer_input"), "/review ");
        assert_eq!(chips(&mut h), 0);
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
            h.key(Key::End);
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
        assert!(h.find("z_card_dev").is_some(), "the run actions");
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
        assert!(counts(&mut h).starts_with("4 files"), "{}", counts(&mut h));
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
        h.click(&format!("{id}_mode_split"));
        h.frames(10);
        healthy(&h);
        h.click(&format!("{id}_mode_unified"));
        h.frames(10);
        // The latest turn changed one file; the branch against main, five.
        h.click(&format!("{id}_scope"));
        h.frames(10);
        h.click(&format!("{id}_scope_turn"));
        h.frames(20);
        assert!(counts(&mut h).starts_with("1 file "), "{}", counts(&mut h));
        h.click(&format!("{id}_scope"));
        h.frames(10);
        h.click(&format!("{id}_scope_branch"));
        h.frames(20);
        assert!(counts(&mut h).starts_with("5 files"), "{}", counts(&mut h));
        snapshot(&h, "changes");
        healthy(&h);
    });
}

/// A box's quad: its fill, border and shadows.
fn quad(h: &mut Harness, id: &str) -> zgui::scene::QuadStyle {
    let node = h.find(id).unwrap_or_else(|| panic!("no {id}"));
    match h.ui.scene.borrow().kind(node) {
        zgui::scene::NodeKind::Panel { quad, .. } | zgui::scene::NodeKind::Quad(quad) => {
            quad.clone()
        }
        _ => panic!("{id} paints no box"),
    }
}
fn casts_shadow(q: &zgui::scene::QuadStyle) -> bool {
    let listed = q.decoration.as_ref().and_then(|d| d.shadows.as_ref());
    match listed {
        Some(list) => !list.is_empty(),
        None => q.shadow.is_some(),
    }
}
fn rim_lines(q: &zgui::scene::QuadStyle) -> usize {
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
            zgui::scene::NodeKind::Container(_)
        ));
        assert!(quad(&mut h, "zeron").fill.3 < 255);
        h.key(Key::Escape);
        h.frames(30);
        // Dragging the sidebar wider widens Settings' column with it.
        let seam = h.bounds("zcols_seam_sidebar");
        let (x, y) = (seam.x + seam.width / 2., seam.y + seam.height / 2.);
        let button = zgui::input::PointerButton::Primary;
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
        cmd(&mut h, "\\", false);
        on_line(&mut h, "well_sidebar");
        cmd(&mut h, "\\", false);
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
        let blue = zgui::scene::Color(10, 132, 255, 255);
        h.ui.theme().set_system_tokens([
            (zgui::theme::tok::MENU_HOVER.0, blue.into()),
            (zgui::theme::tok::SELECTION.0, blue.into()),
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
            if let zgui::scene::NodeKind::Panel { quad, .. } | zgui::scene::NodeKind::Quad(quad) =
                scene.kind(n)
                && quad.fill.3 > 0
            {
                fills.push(quad.fill);
            }
            stack.extend(scene.children(n));
        }
        assert!(!fills.is_empty(), "the item washes under the pointer");
        for zgui::scene::Color(r, g, b, a) in fills.iter().copied() {
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
        let zgui::scene::Color(r, g, b, a) = quad(&mut h, "agent_a1").fill;
        assert!(a > 0, "the chosen row is washed");
        assert!(
            r.abs_diff(g) < 8 && g.abs_diff(b) < 8,
            "a neutral wash: {:?}",
            (r, g, b, a)
        );
    });
}

#[test]
fn the_tabs_panes_start_at_the_sidebars_edge() {
    deep(|| {
        let mut h = app();
        for _ in 0..3 {
            cmd(&mut h, "l", true);
        }
        let side = h.bounds("ztabsh_sidebar");
        let body = h.bounds("ztabs_body");
        assert!(
            (body.x - (side.x + side.width)).abs() < 0.5,
            "no strip between them: {side:?} {body:?}"
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
        h.key(zgui::input::Key::Escape);
        h.frames(20);
        h.click("side_account");
        h.frames(1);
        let rising = h.opacity("side_account_menu");
        assert!(rising < 0.9, "entering: {rising}");
        h.frames(20);
        assert_eq!(h.opacity("side_account_menu"), 1.);

        // Signing out asks first; then the workspace is local: "Local",
        // stored on this device, offering sync.
        h.click("side_account_sign_out");
        h.frames(20);
        assert!(h.find("signout_dialog").is_some());
        h.click("signout-confirm");
        h.frames(20);
        healthy(&h);
        assert_eq!(h.text("side_account_label"), "Local");
        assert_eq!(h.text("side_account_avatar"), "L");
        h.click("side_account");
        h.frames(20);
        assert!(h.texts().iter().any(|t| t == "Stored on this device"));
        // Enabling sync: the browser, then a restart to finish.
        h.click("side_account_enable_sync");
        h.frames(20);
        h.click("sync-enable-open-browser");
        h.frames(20);
        h.click("sync-restart-later");
        h.frames(20);
        h.click("side_account");
        h.frames(20);
        assert!(h.texts().iter().any(|t| t == "Sync ready after restart"));
        assert!(h.find("side_account_sync_restart").is_some());
        h.key(zgui::input::Key::Escape);
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
        h.click("side_view");
        h.frames(20);
        h.click("side_view_device");
        h.frames(20);
        let (here, there) = (
            h.bounds("side_device_macbook_pro"),
            h.bounds("side_device_mac_studio"),
        );
        assert!(here.y < there.y);
        assert_eq!(h.text("side_device_macbook_pro_header"), "MacBook Pro");
        // Two-line rows without the location: the remote glyph.
        h.click("side_view");
        h.frames(20);
        h.click("side_view_compact");
        h.frames(20);
        h.click("side_view");
        h.frames(20);
        h.click("side_view_project_label");
        h.frames(20);
        assert!(h.find("agent_a7_remote").is_some());
        assert!(h.find("agent_a6_remote").is_none());
        snapshot(&h, "sidebar_devices");
        for id in [
            "side_view_project_label",
            "side_view_compact",
            "side_view_list",
        ] {
            h.click("side_view");
            h.frames(20);
            h.click(id);
            h.frames(20);
        }
        // The project filter hides from the view menu, the menu's button
        // keeping its place at the end.
        let view = h.bounds("side_view");
        h.click("side_view");
        h.frames(20);
        h.click("side_view_filter");
        h.frames(20);
        assert_eq!(h.bounds("side_view").x, view.x);
        // Hidden, out of the row's layout.
        assert!(h.bounds("side_filter").width < 20.);
        h.click("side_view");
        h.frames(20);
        h.click("side_view_filter");
        h.frames(20);

        // Renamed in place: a second press, a name, Enter.
        double_click(&mut h, "agent_a6");
        h.frames(10);
        assert!(h.find("agent_a6_rename").is_some(), "the title's editor");
        // Its title selected: End, then more of it.
        h.key(Key::End);
        h.ui.dispatch(InputEvent::Text(" now".into()));
        h.settle();
        h.key(Key::Enter);
        h.frames(10);
        healthy(&h);
        assert!(h.find("agent_a6_rename").is_none());
        assert!(
            h.texts()
                .iter()
                .any(|t| t == "zgui prod: Windows platform now")
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
    let button = zgui::input::PointerButton::Primary;
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
    use zgui::input::PointerButton::Primary;
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
            "side_cross_platform_zgui_header",
            14.,
            |_| {},
        );
        let (header, row) = (
            h.bounds("side_cross_platform_zgui").y,
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
            button: zgui::input::PointerButton::Primary,
        });
        h.ui.dispatch(InputEvent::PointerUp {
            x,
            y,
            button: zgui::input::PointerButton::Primary,
        });
        h.settle();
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_some(), "a draft under the line");
        h.ui.dispatch(InputEvent::Text("Keep the old name".into()));
        h.settle();
        h.key_with(
            Key::Enter,
            Modifiers {
                meta: true,
                ..Default::default()
            },
        );
        h.frames(10);
        healthy(&h);
        assert!(h.find("zchange_draft").is_none(), "posted");
        assert!(
            h.texts().iter().any(|t| t == "Keep the old name"),
            "its card under the line"
        );
        assert_eq!(h.text("composer_comments"), "1 comment");
        snapshot(&h, "review_comment");
        // Sent alone, it goes as the ask to address it.
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
        assert_eq!(h.text("sent_comments_1"), "1 comment", "its badge");
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
            ("appearance", "Random wallpaper"),
        ] {
            h.click(&format!("settings_nav_{section}"));
            h.frames(20);
            healthy(&h);
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
        // Files: the delay shows while autosave is on.
        h.click("settings_nav_files");
        h.frames(20);
        assert!(h.find("settings_autosave_delay").is_some());
        h.click("settings_autosave");
        h.frames(20);
        assert!(h.find("settings_autosave_delay").is_none());
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
        let (bounds, masked) = {
            let scene = h.ui.scene.borrow();
            (scene.bounds(hero), scene.mask(hero).is_some())
        };
        assert!(masked, "faded by a mask");
        assert_eq!(bounds.height, 576.);
        assert_eq!(bounds.y, h.bounds("canvas").y, "across the canvas's top");
        snapshot(&h, "canvas_background");
        // Nothing runs while it rests.
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
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

/// Files (files/*.rs): folders fold; a file opens in the right pane (a
/// Markdown preview with its source a click away, the editor marking an
/// edit until ⌘S); a secondary click renames in place or deletes, asked
/// first; the magnifier searches the paths.
#[test]
fn files_open_edit_rename_delete_and_search() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, "e", true);
        h.frames(30);
        assert!(h.find("ztree_crates/zgui/compose.rs").is_some(), "the tree");
        // A folder folds.
        h.click("ztree_crates/zgui");
        h.frames(10);
        assert!(h.find("ztree_crates/zgui/compose.rs").is_none(), "folded");
        h.click("ztree_crates/zgui");
        h.frames(10);
        assert!(h.find("ztree_crates/zgui/compose.rs").is_some());
        // Markdown opens as its preview; Source shows the editor.
        h.click("ztree_README.md");
        h.frames(30);
        healthy(&h);
        let says = |h: &mut Harness, what: &str| h.texts().iter().any(|t| t.contains(what));
        assert!(says(&mut h, "Validation and current boundaries"));
        h.click("file_file_README_md_mode_source");
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
        // Search.
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

/// A session opens at its end, and stays there as panels open beside it
/// (the transcript rewraps narrower and taller).
#[test]
fn a_transcript_opens_at_its_end_and_stays_there_through_a_resize() {
    deep(|| {
        let mut h = app();
        assert!(h.find("jump").is_none(), "at the end");
        cmd(&mut h, "e", true);
        h.frames(60);
        healthy(&h);
        assert!(h.find("jump").is_none(), "still at the end");
    });
}

/// Onboarding, as Zeron's gates: Sign out leads to "Log in to Zeron" over
/// the grid; logging in asks for a workspace; then the first project; then
/// the app.
#[test]
fn onboarding_signs_in_creates_a_workspace_and_adds_a_project() {
    deep(|| {
        let mut h = app();
        cmd(&mut h, ",", false);
        h.click("settings_nav_general");
        h.frames(20);
        h.click("settings_sign_out");
        h.frames(40);
        healthy(&h);
        assert!(h.find("onboarding_signin").is_some(), "the sign-in card");
        snapshot(&h, "onboarding");
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
        h.click("onboarding_add_project");
        h.frames(40);
        assert!(h.find("onboarding").is_none(), "the app");
        let calls = h.calls();
        h.frames(30);
        assert_eq!(h.calls(), calls);
    });
}
