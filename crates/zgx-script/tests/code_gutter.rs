//! A textarea's `gutter` (review comments): marks in their lines' numbers'
//! place, the plate under the pointer with no script run as it moves, a
//! press on a cell told with its line, marks following an edit and told
//! where, and a card under its line.
mod common;

use common::Harness;
use zgx::{
    input::{InputEvent, PointerButton},
    scene::Rect,
    widgets::EditorHandle,
};

fn gutter() -> Harness {
    let h = Harness::inline(
        r##"
local lines = {}
for i = 1, 30 do
    table.insert(lines, "line " .. i)
end
local text = ui.state("text", table.concat(lines, "\n"))
local marks = ui.state("marks", { { id = "c1", line = 3 } })
local pressed = ui.state("pressed", "")
local open = ui.state("open", nil)
local note = ui.state("note", "")
local glyph = "code:<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><rect x='2' y='2' width='12' height='12'/></svg>"
return ui.column { w = 400,
    ui.textarea { id = "code", value = text, w = 300, h = 200, text_size = 10, line_height = 20,
        line_numbers = true,
        gutter = {
            marks = marks,
            mark = glyph, mark_color = "$text.secondary", mark_fill = "#0a141e",
            add = glyph, add_color = "#ffffff", add_fill = "$accent",
            label = "Comment",
            on_press = function(line: number, id: string?)
                pressed:set(tostring(line) .. ":" .. (id or "-"))
                open:set(line)
            end,
            on_move = function(now)
                marks:set(now)
            end,
            card = ui.column { id = "card", h = 60,
                ui.textarea { id = "note", value = note, w = 200, h = 40 },
            },
            card_line = open,
        },
    },
    ui.text { id = "pressed", function() return pressed:get() end },
    ui.text { id = "marked", function()
        local all = marks:get()
        return if #all > 0 then all[1].id .. "@" .. tostring(all[1].line) else "none"
    end },
}"##,
    );
    h.frames(2);
    if let Some(e) = h.error() {
        panic!("{e}");
    }
    h
}

fn editor(h: &mut Harness) -> EditorHandle {
    let node = h.find("code").expect("the textarea");
    h.ui.editor(node).expect("its editor")
}
fn cell(h: &mut Harness, line: usize) -> Rect {
    editor(h)
        .gutter_cell(line)
        .unwrap_or_else(|| panic!("line {line}'s cell is not in view"))
}
fn click(h: &mut Harness, x: f32, y: f32) {
    let button = PointerButton::Primary;
    h.ui.dispatch(InputEvent::PointerDown { x, y, button });
    h.ui.dispatch(InputEvent::PointerUp { x, y, button });
    h.settle();
    h.frames(1);
}
fn card_shown(h: &mut Harness) -> Option<Rect> {
    let node = h.find("card")?;
    let scene = h.ui.scene.borrow();
    scene
        .layout_visible(node)
        .then(|| scene.transformed_bounds(node))
}

#[test]
fn a_gutter_offers_its_plate_without_script_and_tells_presses_and_moves() {
    let mut h = gutter();
    // The plate follows the pointer in the engine alone.
    let five = cell(&mut h, 5);
    let calls = h.calls();
    for dy in [3., 6., 9.] {
        h.ui.dispatch(InputEvent::PointerMove {
            x: five.x + 2.,
            y: five.y + dy,
        });
        h.frames(1);
    }
    let six = cell(&mut h, 6);
    h.ui.dispatch(InputEvent::PointerMove {
        x: six.x + 2.,
        y: six.y + 3.,
    });
    h.frames(1);
    assert_eq!(h.calls(), calls, "hovering the gutter runs no script");

    // A press on a cell tells its line, and opens the card under it.
    let before = editor(&mut h).selection();
    click(&mut h, five.x + five.width / 2., five.y + five.height / 2.);
    assert_eq!(h.text("pressed"), "5:-");
    assert_eq!(editor(&mut h).selection(), before, "no caret placed");
    let card = card_shown(&mut h).expect("the card under line 5");
    assert_eq!(card.y, five.y + five.height);
    // On a mark, its id with it.
    let three = cell(&mut h, 3);
    click(
        &mut h,
        three.x + three.width / 2.,
        three.y + three.height / 2.,
    );
    assert_eq!(h.text("pressed"), "3:c1");
    let card = card_shown(&mut h).unwrap();
    assert_eq!(card.y, three.y + three.height);

    // The card's text area types into itself.
    h.type_text("note", "draft");
    assert_eq!(h.text("note"), "draft");
    assert!(h.text("code").starts_with("line 1\nline 2\n"));

    // A line typed above the mark: it moves, and the script is told.
    let node = h.find("code").unwrap();
    h.ui.input.focus(&h.ui.scene, Some(node));
    editor(&mut h).set_selection(0, 0);
    h.frames(1);
    h.ui.dispatch(InputEvent::Text("\n".into()));
    h.settle();
    h.frames(1);
    assert_eq!(h.text("marked"), "c1@4");
    assert_eq!(
        editor(&mut h).gutter_marks(),
        [zgx::editor_gutter::GutterMark {
            id: "c1".into(),
            line: 4
        }]
    );
    if let Some(e) = h.error() {
        panic!("{e}");
    }
}

#[test]
fn a_gutters_unknown_option_is_an_error() {
    let runtime = zgx::reactive::Runtime::new();
    let code = r#"return ui.textarea { value = ui.state("t", ""), gutter = { mraks = {} } }"#;
    let error = zgx_script::ScriptHost::inline(&runtime, "app", code)
        .reload()
        .unwrap_err()
        .to_string();
    assert!(error.contains("not `mraks`"), "{error}");
}
