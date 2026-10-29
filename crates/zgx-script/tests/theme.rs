//! Themes from scripts: `"$token"` values, `ui.theme`, app tokens, scoped
//! `theme = …` and theme files that reload in place.
mod common;

use common::Harness;
use std::time::Duration;
use zgx::scene::{Color, NodeKind};
use zgx_script::ScriptHost;

impl Harness {
    fn fill(&mut self, id: &str) -> Color {
        let node = self.find(id).unwrap_or_else(|| panic!("no node `{id}`"));
        match self.ui.scene.borrow().kind(node) {
            NodeKind::Panel { quad, .. } => quad.fill,
            NodeKind::Container(_) => Color(0, 0, 0, 0),
            other => panic!("`{id}` is not a box: {other:?}"),
        }
    }
    fn radius(&mut self, id: &str) -> f32 {
        let node = self.find(id).unwrap();
        match self.ui.scene.borrow().kind(node) {
            NodeKind::Panel { quad, .. } => quad.radius,
            other => panic!("`{id}` is not a box: {other:?}"),
        }
    }
    fn ink(&mut self, id: &str) -> Color {
        let node = self.find(id).unwrap_or_else(|| panic!("no node `{id}`"));
        let scene = self.ui.scene.borrow();
        let mut stack = vec![node];
        while let Some(n) = stack.pop() {
            if let NodeKind::Text { color, .. } = scene.kind(n) {
                return *color;
            }
            stack.extend(scene.children(n).iter().rev());
        }
        panic!("no text in `{id}`")
    }
}
const DARK_RAISED: Color = Color(35, 46, 64, 255);
const WHITE: Color = Color(255, 255, 255, 255);
const LIGHT_TEXT: Color = Color(0x1a, 0x1f, 0x29, 255);
const DARK_TEXT: Color = Color(229, 237, 247, 255);

#[test]
fn token_values_style_nodes_and_follow_the_theme() {
    let mut h = Harness::inline(
        r##"return ui.column {
            ui.div { id = "card", w = 40, h = 20, bg = "$surface.raised", rounded = "$radius.lg", p = "$space.2" },
            ui.text { "Muted", id = "muted", color = "$text.secondary" },
            ui.text { "Body", id = "body" },
            ui.button { id = "light", w = 20, h = 20, on_click = function() ui.theme.set("zgx-light") end },
        }"##,
    );
    assert_eq!(h.fill("card"), DARK_RAISED);
    assert_eq!(h.radius("card"), 10.);
    assert_eq!(h.ink("muted"), Color(138, 154, 176, 255));
    assert_eq!(h.ink("body"), DARK_TEXT);
    h.ui.scene.borrow_mut().flush();
    h.click("light");
    let report = h.ui.scene.borrow_mut().flush();
    assert_eq!(h.fill("card"), WHITE);
    assert_eq!(h.ink("body"), LIGHT_TEXT);
    assert_eq!(h.ink("muted"), Color(0x5a, 0x64, 0x74, 255));
    assert_eq!(report.layout_nodes, 0, "colours need no layout");
}

#[test]
fn app_tokens_and_luau_themes() {
    let mut h = Harness::inline(
        r##"ui.theme.tokens {
            ["app.card"] = "{surface.raised}",
            app = { badge = "alpha({accent}, 0.5)" },
        }
        ui.theme.register {
            name = "app-sepia",
            type = "light",
            tokens = { ["app.card"] = "#f4ecd8", accent = "#8a5a00" },
        }
        local accent = ui.theme.get("accent")
        return ui.column {
            ui.div { id = "card", w = 10, h = 10, bg = "$app.card" },
            ui.div { id = "badge", w = 10, h = 10, bg = "$app.badge" },
            ui.div { id = "unknown", w = 10, h = 10, bg = "$app.nowhere" },
            ui.text { accent, id = "accent" },
            ui.button { id = "sepia", w = 20, h = 20, on_click = function() ui.theme.set("app-sepia") end },
        }"##,
    );
    assert_eq!(h.fill("card"), DARK_RAISED, "declared in standard terms");
    assert_eq!(h.fill("badge"), Color(0x5e, 0xa5, 0xff, 128));
    assert_eq!(
        h.fill("unknown"),
        Color(0, 0, 0, 0),
        "unknown tokens are clear"
    );
    assert_eq!(h.text("accent"), "#5ea5ffff");
    h.click("sepia");
    assert_eq!(
        h.fill("card"),
        Color(0xf4, 0xec, 0xd8, 255),
        "the theme sets it"
    );
    assert_eq!(
        h.fill("badge"),
        Color(0x8a, 0x5a, 0x00, 128),
        "derived again"
    );
}

#[test]
fn ui_tokens_name_every_token_as_fields() {
    let mut h = Harness::inline(
        r##"ui.theme.tokens { app = { card = "#20242c" } }
        local before = ui.tokens.surface.raised
        -- Declared after the first read: found all the same.
        ui.theme.tokens { app = { late = "#ffffff" } }
        local typo = select(2, pcall(function() return ui.tokens.app.crad end))
        return ui.column {
            ui.div { id = "card", w = 10, h = 10, bg = ui.tokens.app.card },
            ui.div { id = "raised", w = 10, h = 10, bg = before, rounded = ui.tokens.radius.lg },
            ui.div { id = "late", w = 10, h = 10, bg = ui.tokens.app.late },
            ui.text { ui.tokens.accent.value .. " " .. ui.tokens.accent.hover .. " " .. ui.tokens.space[3], id = "names" },
            ui.text { tostring(typo), id = "typo" },
        }"##,
    );
    assert_eq!(h.fill("card"), Color(0x20, 0x24, 0x2c, 255));
    assert_eq!(h.fill("raised"), DARK_RAISED);
    assert_eq!(h.radius("raised"), 10.);
    assert_eq!(h.fill("late"), WHITE);
    assert_eq!(h.text("names"), "$accent $accent.hover $space.3");
    assert!(
        h.text("typo").contains("ui.tokens has no `app.crad`"),
        "{}",
        h.text("typo")
    );
}

#[test]
fn scoped_themes_restyle_their_subtrees() {
    let mut h = Harness::inline(
        r##"local light = ui.state("light", true)
        return ui.column {
            ui.div { id = "outer", w = 10, h = 10, bg = "$surface.raised" },
            ui.column {
                theme = "zgx-light",
                ui.div { id = "card", w = 10, h = 10, bg = "$surface.raised" },
                ui.text { "Inside", id = "inside" },
            },
            ui.div {
                theme = { accent = "#e5484d" },
                ui.div { id = "ring", w = 10, h = 10, bg = "$focus.ring" },
            },
            ui.div {
                theme = function() return if light:get() then "zgx-light" else "zgx-dark" end,
                ui.div { id = "switch", w = 10, h = 10, bg = "$background" },
            },
            ui.button { id = "toggle", w = 20, h = 20, on_click = ui.toggle(light) },
        }"##,
    );
    assert_eq!(h.fill("outer"), DARK_RAISED);
    assert_eq!(h.fill("card"), WHITE);
    assert_eq!(
        h.ink("inside"),
        LIGHT_TEXT,
        "text inherits the scope's body colour"
    );
    assert_eq!(
        h.fill("ring"),
        Color(0xe5, 0x48, 0x4d, 255),
        "derived from the scope's accent"
    );
    assert_eq!(h.fill("switch"), Color(0xf5, 0xf6, 0xf8, 255));
    h.click("toggle");
    assert_eq!(h.fill("switch"), Color(16, 20, 28, 255));
}

#[test]
fn spans_take_tokens() {
    let mut h = Harness::inline(
        r##"return ui.rich {
            id = "rich",
            ui.span { "plain" },
            ui.span { "accent", color = "$accent", bg = "$selection" },
        }"##,
    );
    assert!(h.find("rich").is_some());
    h.ui.scene.borrow_mut().flush();
    h.ui.theme().set(zgx::theme::LIGHT).unwrap();
    h.settle();
    let report = h.ui.scene.borrow_mut().flush();
    assert_eq!(report.layout_nodes, 0, "{report:?}");
}

#[test]
fn theme_files_reload_without_reloading_scripts() {
    let dir = std::env::temp_dir().join(format!("zgx-script-theme-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let theme = dir.join("brand.json");
    let write = |accent: &str, offset: u64| {
        std::fs::write(
            &theme,
            format!(
                r#"{{ "name": "brand", "type": "dark", "tokens": {{ "accent": "{accent}" }} }}"#
            ),
        )
        .unwrap();
        std::fs::File::options()
            .write(true)
            .open(&theme)
            .unwrap()
            .set_modified(std::time::SystemTime::now() + Duration::from_secs(offset))
            .unwrap();
    };
    write("#ff0000", 0);
    std::fs::write(
        dir.join("app.luau"),
        r##"local count = ui.state("count", 0)
        ui.theme.set(ui.theme.load("brand.json"))
        return ui.column {
            ui.div { id = "accent", w = 10, h = 10, bg = "$accent" },
            ui.button { id = "add", w = 20, h = 20, on_click = ui.add(count) },
            ui.text { "{count}", id = "count" },
        }"##,
    )
    .unwrap();
    let path = dir.join("app.luau");
    let mut h = Harness::new(|runtime| ScriptHost::new(runtime, &path));
    assert_eq!(h.fill("accent"), Color(255, 0, 0, 255));
    h.click("add");
    assert_eq!(h.text("count"), "1");
    let before = h.find("accent").unwrap();
    write("#00ff00", 2);
    assert!(h.host.reload_if_changed());
    // Restyled in place: the same node, the state where it was.
    assert_eq!(h.find("accent"), Some(before));
    assert_eq!(h.fill("accent"), Color(0, 255, 0, 255));
    assert_eq!(h.text("count"), "1");
    // A file that stops reading shows its error and keeps the last theme.
    std::fs::write(&theme, "{ nope").unwrap();
    std::fs::File::options()
        .write(true)
        .open(&theme)
        .unwrap()
        .set_modified(std::time::SystemTime::now() + Duration::from_secs(4))
        .unwrap();
    assert!(h.host.reload_if_changed());
    assert!(
        h.host
            .error()
            .get()
            .is_some_and(|e| e.contains("brand.json"))
    );
    assert_eq!(h.fill("accent"), Color(0, 255, 0, 255));
    write("#0000ff", 6);
    assert!(h.host.reload_if_changed());
    assert_eq!(h.host.error().get(), None);
    assert_eq!(h.fill("accent"), Color(0, 0, 255, 255));
    // Theme files stay inside the script's directory.
    std::fs::write(
        dir.join("app.luau"),
        r##"ui.theme.load("../elsewhere.json") return ui.div {}"##,
    )
    .unwrap();
    assert!(h.host.reload().is_err());
    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn defaults_survive_reloads_but_not_a_choice() {
    let h = Harness::inline(
        r##"ui.theme.default("zgx-light")
        return ui.div {}"##,
    );
    assert_eq!(&*h.ui.theme().current(), "zgx-light");
    h.ui.theme().set(zgx::theme::DARK).unwrap();
    h.host.reload().unwrap();
    assert_eq!(
        &*h.ui.theme().current(),
        "zgx-dark",
        "the app's choice stands"
    );
}

#[test]
fn the_current_theme_is_state() {
    let mut h = Harness::inline(
        r##"return ui.column {
            ui.text { function() return ui.theme.current:get() .. " " .. ui.theme.kind() end, id = "current" },
            ui.button { id = "light", w = 20, h = 20, on_click = function() ui.theme.current:set("zgx-light") end },
            ui.button { id = "bad", w = 20, h = 20, on_click = function() ui.theme.current:set("no-such") end },
        }"##,
    );
    assert_eq!(h.text("current"), "zgx-dark dark");
    h.ui.theme().set("zgx-light").unwrap();
    h.settle();
    assert_eq!(h.text("current"), "zgx-light light", "Rust's switch shows");
    h.ui.theme().set("zgx-dark").unwrap();
    h.click("light");
    assert_eq!(
        &*h.ui.theme().current(),
        "zgx-light",
        "the script's applies"
    );
    h.click("bad");
    assert_eq!(&*h.ui.theme().current(), "zgx-light");
    assert_eq!(h.text("current"), "zgx-light light");
}

/// Every fill and text colour in the scene.
fn colors(ui: &zgx::widgets::Ui) -> Vec<Color> {
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

#[test]
fn the_notes_example_keeps_its_look_and_takes_any_theme() {
    let app = concat!(env!("CARGO_MANIFEST_DIR"), "/examples/notes/app.luau");
    let h = Harness::new(|runtime| ScriptHost::new(runtime, app));
    assert_eq!(h.host.error().get(), None);
    h.ui.prepare_frame();
    assert_eq!(&*h.ui.theme().current(), "notes-glass");
    let glass = colors(&h.ui);
    for (color, what) in [
        (Color(0x12, 0x14, 0x16, 0x6b), "the window's glass"),
        (Color(0x1b, 0x1c, 0x20, 0xd9), "the editor"),
        (Color(0x1b, 0x1c, 0x20, 0xf0), "the preview"),
        (Color(0xff, 0xff, 0xff, 0x10), "the search field"),
        (Color(0xff, 0xff, 0xff, 0xeb), "text"),
        (Color(0xf5, 0xb7, 0x0a, 0x3d), "the selected note"),
    ] {
        assert!(glass.contains(&color), "{what}: {color:?} not in {glass:?}");
    }
    h.ui.theme().set(zgx::theme::LIGHT).unwrap();
    h.settle();
    h.ui.prepare_frame();
    let light = colors(&h.ui);
    assert!(light.contains(&WHITE), "the editor on the light base");
    assert!(light.contains(&LIGHT_TEXT));
    assert!(!light.contains(&Color(0xff, 0xff, 0xff, 0xeb)));
    assert_eq!(h.host.error().get(), None);
}

#[test]
fn ui_prefers_follows_the_systems_display_settings() {
    use zgx::theme::SystemPreferences;
    let mut h = Harness::inline(
        r##"return ui.column {
            ui.text { function()
                local p = ui.prefers
                return `{p.reduced_motion:get()} {p.more_contrast:get()} {p.reduced_transparency:get()}`
            end, id = "p" } }"##,
    );
    h.frames(2);
    assert_eq!(h.text("p"), "false false false");
    h.ui.theme().set_system_preferences(SystemPreferences {
        reduced_motion: true,
        increased_contrast: false,
        reduced_transparency: true,
    });
    h.frames(1);
    assert_eq!(h.text("p"), "true false true", "as the system changes");
}

#[test]
fn single_corners_take_tokens_after_the_radius() {
    // A token on one corner refines the radius set with it, whatever order
    // the table lists them in, and follows the theme.
    let mut h = Harness::inline(
        r##"return ui.column {
            ui.div { id = "a", w = 40, h = 20, bg = "#223344", rounded = 8, rounded_tr = "$radius.lg" },
            ui.div { id = "b", w = 40, h = 20, bg = "#223344", rounded_bl = "$radius.sm", rounded = "$radius.md" },
            ui.button { id = "light", w = 20, h = 20, on_click = function() ui.theme.set("zgx-light") end },
        }"##,
    );
    let corners = |h: &mut Harness, id: &str| {
        let node = h.find(id).unwrap();
        match h.ui.scene.borrow().kind(node) {
            NodeKind::Panel { quad, .. } => {
                let c = quad
                    .decoration
                    .as_ref()
                    .and_then(|d| d.corners)
                    .expect("corners of its own");
                [c.top_left, c.top_right, c.bottom_right, c.bottom_left]
            }
            other => panic!("`{id}` is not a box: {other:?}"),
        }
    };
    h.frames(2);
    assert_eq!(corners(&mut h, "a"), [8., 10., 8., 8.]);
    assert_eq!(corners(&mut h, "b"), [6., 6., 6., 4.]);
    h.click("light");
    h.frames(2);
    assert_eq!(corners(&mut h, "a"), [8., 10., 8., 8.]);
}

#[test]
fn gaps_per_axis_take_tokens() {
    // The design lint asks for tokens on `gap_x` and `gap_y` as on `gap`:
    // they lay out as their values.
    let mut h = Harness::inline(
        r##"local cells = {}
        for i = 1, 3 do
            table.insert(cells, ui.div { id = `c{i}`, w = 40, h = 10, bg = "#223344" })
        end
        return ui.row { w = 100, flex_wrap = true, gap_x = "$space.3", gap_y = "$space.2", cells }"##,
    );
    h.frames(2);
    let (a, b, c) = (h.bounds("c1"), h.bounds("c2"), h.bounds("c3"));
    assert_eq!(b.x - (a.x + a.width), 12., "gap_x is space.3");
    assert_eq!(c.y - (a.y + a.height), 8., "gap_y is space.2");
}

#[test]
fn insets_take_tokens() {
    // An absolute node placed by tokens (a bar 32 up from the bottom) sits
    // where their values put it, as a number would.
    let mut h = Harness::inline(
        r##"return ui.div {
            w = 200, h = 100, relative = true,
            ui.div { id = "bar", absolute = true, left = "$space.2", right = "$space.3", bottom = "$space.4", h = 10 },
            ui.div { id = "tag", absolute = true, top = "$space.1", left = 0, w = 10, h = 10 },
        }"##,
    );
    h.frames(2);
    let (bar, tag) = (h.bounds("bar"), h.bounds("tag"));
    assert_eq!(
        (bar.x, bar.width),
        (8., 180.),
        "left space.2, right space.3"
    );
    assert_eq!(bar.y + bar.height, 84., "bottom space.4");
    assert_eq!(tag.y, 4., "top space.1");
}
