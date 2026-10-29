//! `ui.sandbox`: a script the app holds as text (an agent's visual) run in
//! a VM of its own, sandboxed as a plugin is, its node shown in place; its
//! failures shown as its fallback says, never the app's.
mod common;
use common::Harness;
use zgx_script::{ScriptHost, Value};

const APP: &str = r#"
local source = ui.state("source", "")
local seen = ui.state("seen", "")
return ui.column {
    ui.sandbox(source, {
        id = "visual",
        name = "visual-1",
        fallback = function(why)
            seen:set(why)
            return ui.text { "Visual failed", id = "failed" }
        end,
    }),
    ui.text { "{seen}", id = "why" },
}
"#;

fn set(h: &mut Harness, source: &str) {
    h.host.set_state("source", Value::from(source)).unwrap();
    h.settle();
}

#[test]
fn a_sandboxed_script_shows_its_node_and_keeps_its_state_and_handlers() {
    let mut h = Harness::inline(APP);
    assert!(h.find("failed").is_none(), "nothing yet, and no failure");
    set(
        &mut h,
        r#"
local n = ui.state("n", 0)
return ui.column {
    ui.text { "count {n}", id = "count" },
    ui.button { "add", id = "add", on_click = function() n:set(n:get() + 1) end },
}
"#,
    );
    assert_eq!(h.text("count"), "count 0");
    h.click("add");
    h.click("add");
    assert_eq!(h.text("count"), "count 2");
    assert_eq!(h.host.error().get(), None);
}

#[test]
fn a_failing_script_shows_its_fallback_with_why_not_the_apps_banner() {
    let mut h = Harness::inline(APP);
    set(&mut h, "error('no data')");
    assert_eq!(h.text("failed"), "Visual failed");
    assert!(h.text("why").contains("no data"), "{}", h.text("why"));
    assert_eq!(
        h.host.error().get(),
        None,
        "the app's own error stays clear"
    );
    // A script returning nothing is no visual.
    set(&mut h, "local x = 1");
    assert!(
        h.text("why").contains("returns a ui node"),
        "{}",
        h.text("why")
    );
    // A handler's error, once it runs, takes it down too.
    set(
        &mut h,
        r#"return ui.button { "boom", id = "boom", on_click = function() error("handler broke") end }"#,
    );
    assert!(h.find("failed").is_none());
    h.click("boom");
    h.settle();
    assert_eq!(h.text("failed"), "Visual failed");
    assert!(h.text("why").contains("handler broke"), "{}", h.text("why"));
    assert_eq!(h.host.error().get(), None);
}

#[test]
fn a_sandboxed_script_reaches_nothing_it_was_not_granted() {
    let mut h = Harness::new(|runtime| {
        let host = ScriptHost::inline(runtime, "app", APP);
        host.action("secret", |_| {});
        host.shared("sessions", Value::from("every session"));
        host
    });
    for (code, needs) in [
        (r#"ui.invoke("secret", 1) return ui.text { "x" }"#, "secret"),
        (
            r#"local s = ui.shared("sessions", "") return ui.text { "x" }"#,
            "sessions",
        ),
        (
            r#"ui.clipboard.write("x") return ui.text { "x" }"#,
            "lipboard",
        ),
        (
            r#"return ui.text { "x", id = require("./other") }"#,
            "require",
        ),
    ] {
        set(&mut h, code);
        assert_eq!(h.text("failed"), "Visual failed", "{code}");
        assert!(h.text("why").contains(needs), "{code}: {}", h.text("why"));
    }
    // A runaway script is stopped by the plugins' budget.
    set(&mut h, "while true do end");
    assert_eq!(h.text("failed"), "Visual failed");
    // Bytecode is read as source, and so never runs.
    set(&mut h, "\u{6}\u{3}garbage");
    assert_eq!(h.text("failed"), "Visual failed");
    assert_eq!(h.host.error().get(), None);
}

#[test]
fn with_on_error_an_error_as_it_runs_is_told_and_what_it_shows_stays() {
    let mut h = Harness::inline(
        r#"
local source = ui.state("source", "")
local told = ui.state("told", "")
return ui.column {
    ui.sandbox(source, {
        name = "visual-2",
        fallback = function(why) return ui.text { "Visual failed", id = "failed" } end,
        on_error = function(why) told:set(why) end,
    }),
    ui.text { "{told}", id = "told" },
}
"#,
    );
    set(
        &mut h,
        r#"return ui.button { "boom", id = "boom", on_click = function() error("handler broke") end }"#,
    );
    h.click("boom");
    h.settle();
    assert!(h.find("boom").is_some(), "what it showed stays");
    assert!(h.find("failed").is_none());
    assert!(
        h.text("told").contains("handler broke"),
        "{}",
        h.text("told")
    );
    assert_eq!(h.host.error().get(), None);
}
