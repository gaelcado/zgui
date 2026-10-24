//! Scripts' input placeholders, selection API, select-on-focus, text
//! areas that grow with their text, window drag regions, and hover's enter/leave semantics.
mod common;

use common::Harness;
use zgui::{
    input::{InputEvent, Modifiers, PointerButton},
    scene::NodeKind,
    widgets::WindowGesture,
};

impl Harness {
    /// The first text a node paints.
    fn painted(&mut self, id: &str) -> String {
        self.ui.prepare_frame();
        let node = self.find(id).unwrap_or_else(|| panic!("no node `{id}`"));
        let scene = self.ui.scene.borrow();
        let mut stack = vec![node];
        while let Some(n) = stack.pop() {
            if let NodeKind::Text { text, .. } = scene.kind(n) {
                return text.to_string();
            }
            stack.extend(scene.children(n).iter().rev());
        }
        String::new()
    }
    fn press(&mut self, x: f32, y: f32) {
        let button = PointerButton::Primary;
        let none = Modifiers::default();
        self.ui
            .dispatch_with_modifiers(InputEvent::PointerDown { x, y, button }, none);
        self.ui
            .dispatch_with_modifiers(InputEvent::PointerUp { x, y, button }, none);
    }
}

#[test]
fn placeholders_show_while_empty() {
    let mut h = Harness::inline(
        r##"local query = ui.state("query", "")
        local hint = ui.state("hint", "Search notes")
        return ui.column {
            ui.input { id = "query", label = "Search", value = query, w = 200,
                placeholder = hint, placeholder_color = "#808080" },
            ui.textarea { id = "body", label = "Body", value = ui.state("body", ""), w = 200, h = 80,
                placeholder = function() return "Start writing" end },
            ui.button { id = "type", w = 10, h = 10, on_click = function() query:set("zgui") end },
            ui.button { id = "rename", w = 10, h = 10, on_click = function() hint:set("Find") end },
        }"##,
    );
    assert_eq!(h.painted("query"), "Search notes");
    assert_eq!(h.painted("body"), "Start writing");
    let node = h.find("query").unwrap();
    assert_eq!(
        h.ui.semantics
            .borrow()
            .get(node)
            .unwrap()
            .placeholder
            .as_deref(),
        Some("Search notes")
    );
    h.click("rename");
    assert_eq!(h.painted("query"), "Find");
    h.click("type");
    assert_eq!(h.painted("query"), "zgui");
}

#[test]
fn selection_api_counts_characters() {
    let mut h = Harness::inline(
        r##"local text = ui.state("text", "naïve café")
        local log = ui.state("log", "")
        local field
        return ui.column {
            ui.input { id = "field", label = "Text", value = text, w = 200,
                on_mount = function(el) field = el end },
            ui.button { id = "all", w = 10, h = 10, on_click = function()
                field:select_all()
                local a, b = field:selection()
                log:set(a .. "-" .. b)
            end },
            ui.button { id = "some", w = 10, h = 10, on_click = function()
                field:set_selection(6, 2)
                local a, b = field:selection()
                log:set(a .. "-" .. b)
            end },
            ui.button { id = "caret", w = 10, h = 10, on_click = function()
                field:set_selection(3)
                local a, b = field:selection()
                log:set(a .. "-" .. b)
            end },
            ui.text { "{log}", id = "log" },
        }"##,
    );
    h.click("all");
    assert_eq!(h.text("log"), "0-10");
    h.click("some");
    assert_eq!(h.text("log"), "6-2");
    let node = h.find("field").unwrap();
    let editor = h.ui.editor(node).unwrap();
    // "na" is two bytes, "naïve " seven.
    assert_eq!(editor.selection(), (7, 2));
    h.click("caret");
    assert_eq!(h.text("log"), "3-3");
}

#[test]
fn an_address_bar_selects_all_on_focus() {
    let mut h = Harness::inline(
        r##"local address = ui.state("address", "example.com")
        return ui.column {
            ui.input { id = "address", label = "Address", value = address, w = 300, h = 24,
                select_on_focus = true,
                -- Focus shows the whole URL, as Safari's bar does.
                on_focus = function() address:set("https://example.com/") end },
        }"##,
    );
    h.ui.prepare_frame();
    let node = h.find("address").unwrap();
    let at = h.ui.scene.borrow().bounds(node);
    let (x, y) = (at.x + 30., at.y + at.height / 2.);
    h.press(x, y);
    let editor = h.ui.editor(node).unwrap();
    assert_eq!(h.ui.input.focused(), Some(node));
    assert_eq!(editor.editor.borrow().text(), "https://example.com/");
    assert_eq!(editor.selection(), (0, "https://example.com/".len()));
    // Not a double click: a caret where the second click lands.
    h.ui.dispatch(InputEvent::PointerDown {
        x,
        y,
        button: PointerButton::Primary,
    });
    let (a, b) = editor.selection();
    assert_eq!(a, b);
    assert!(a > 0 && a < "https://example.com/".len());
}

#[test]
fn window_drag_regions_ask_the_host_to_move_the_window() {
    let mut h = Harness::inline(
        r##"return ui.row { id = "bar", w = 300, h = 40, window_drag = true,
            ui.div { w = 100, h = 40 },
            ui.button { id = "close", w = 40, h = 40, on_click = function() end },
        }"##,
    );
    h.ui.prepare_frame();
    h.press(50., 20.);
    assert_eq!(h.ui.take_window_gesture(), Some(WindowGesture::Drag));
    h.press(50., 20.);
    assert_eq!(h.ui.take_window_gesture(), Some(WindowGesture::DoubleClick));
    let close = h.find("close").unwrap();
    let at = h.ui.scene.borrow().bounds(close);
    h.press(at.x + 10., 20.);
    assert_eq!(h.ui.take_window_gesture(), None);
}

#[test]
fn hover_holds_across_children() {
    let mut h = Harness::inline(
        r##"local log = ui.state("log", "")
        return ui.column {
            ui.row { id = "area", w = 200, h = 50,
                on_hover = function(inside) log:set(log:peek() .. (inside and "[" or "]")) end,
                ui.button { w = 50, h = 50, on_click = function() end,
                    on_hover = function(inside) log:set(log:peek() .. (inside and "a" or "A")) end },
                ui.button { w = 50, h = 50, on_click = function() end },
            },
            ui.text { "{log}", id = "log" },
        }"##,
    );
    h.ui.prepare_frame();
    for x in [10., 60., 20., 150.] {
        h.ui.dispatch(InputEvent::PointerMove { x, y: 10. });
    }
    h.ui.dispatch(InputEvent::PointerLeave);
    // The row: one enter, one leave; the first button its own two pairs.
    assert_eq!(h.text("log"), "[aAaA]");
}

/// `auto_height = true`: a text area is as tall as its text (wrapped at its width)
/// and its padding, held between `min_h` and `max_h`, past which it
/// scrolls; restyling it keeps the fitted height, and it settles (no frame
/// asks for another).
#[test]
fn an_auto_height_text_area_grows_and_shrinks_with_its_text() {
    let mut h = Harness::new(|runtime| {
        zgui_script::ScriptHost::inline(
            runtime,
            "app",
            r##"
local v = ui.state("v", "one")
local lit = ui.state("lit", false)
local function set(text: string) return function() v:set(text) end end
return ui.column { w = 300,
    ui.textarea { id = "t", value = v, w = 200, auto_height = true, min_h = 30, max_h = 120,
        wrap = true, py = 4, line_height = 20,
        border_color = function() return if lit:get() then "#ff0000" else "#00ff00" end },
    ui.button { id = "three", w = 10, h = 10, on_click = set("one\ntwo\nthree") },
    ui.button { id = "nine", w = 10, h = 10, on_click = set(string.rep("line\n", 8) .. "end") },
    ui.button { id = "wrap", w = 10, h = 10, on_click = set("a few words that wrap once") },
    ui.button { id = "lit", w = 10, h = 10, on_click = function() lit:set(true) end },
}"##,
        )
    });
    h.frames(3);
    assert_eq!(h.bounds("t").height, 30., "one line (28) rises to min_h");
    h.click("three");
    h.frames(3);
    assert_eq!(
        h.bounds("t").height,
        68.,
        "three lines of 20 and 8 of padding"
    );
    h.click("lit");
    h.frames(3);
    assert_eq!(h.bounds("t").height, 68., "a restyle keeps it");
    h.click("nine");
    h.frames(3);
    assert_eq!(h.bounds("t").height, 120., "held at max_h");
    h.click("wrap");
    h.frames(3);
    let wrapped = h.bounds("t").height;
    assert!(
        wrapped == 48. || wrapped == 68.,
        "wrapped lines count: {wrapped}"
    );
    let calls = h.host.script_calls();
    h.frames(5);
    assert_eq!(h.host.script_calls(), calls, "it settles");
    assert!(!h.clock.wants_frame(), "and asks for no frame");
}
