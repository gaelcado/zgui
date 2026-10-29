//! A textarea as a Markdown draft (`markdown = true`, Zeron's composer):
//! faces as it is typed, markers hidden off the caret's lines, lists going
//! on at a break and indenting on Tab; and its pastes (`on_paste`) and
//! chips' labels (`chip_label`) and cards (`chip_tooltip`).
mod common;

use common::Harness;
use zgx::{
    input::{Key, Modifiers},
    scene::NodeKind,
    widgets::EditorHandle,
};

fn draft() -> Harness {
    let h = Harness::inline(
        r##"
local v = ui.state("v", "a **b** `c`\nnext")
return ui.column { w = 400,
    ui.textarea { id = "t", value = v, w = 300, h = 120, line_height = 20,
        markdown = true, chips = "@",
        chip_label = function(token: string) return string.match(token, "([^/]+)$") end,
        on_paste = function(text: string)
            return if text == "main.rs" then "@src/main.rs " else nil
        end,
    },
}"##,
    );
    h.frames(2);
    if let Some(e) = h.error() {
        panic!("{e}");
    }
    h
}

fn editor(h: &mut Harness) -> EditorHandle {
    let node = h.find("t").expect("the draft");
    h.ui.input.focus(&h.ui.scene, Some(node));
    h.ui.focused_editor().expect("its editor")
}

fn at(h: &mut Harness, e: &EditorHandle, offset: usize) {
    e.editor.borrow_mut().set_selection(offset, offset);
    e.refresh();
    h.frames(1);
}

/// What the draft shows, in runs.
fn shown(h: &mut Harness) -> zgx::rich_text::RichText {
    h.ui.prepare_frame();
    let node = h.find("t").unwrap();
    let scene = h.ui.scene.borrow();
    let mut stack = vec![node];
    while let Some(n) = stack.pop() {
        if let NodeKind::RichText { text } = scene.kind(n) {
            return (**text).clone();
        }
        stack.extend_from_slice(scene.children(n));
    }
    panic!("the draft shows no runs");
}

fn value(h: &mut Harness) -> String {
    let e = editor(h);
    e.value().get()
}

fn press(h: &mut Harness, key: Key, shift: bool) {
    h.key_with(
        key,
        Modifiers {
            shift,
            ..Default::default()
        },
    );
}

#[test]
fn a_markdown_draft_shows_its_faces_and_hides_its_markers_off_the_carets_line() {
    let mut h = draft();
    let e = editor(&mut h);
    // On the first line: its markers show, the bold and the code in their faces.
    at(&mut h, &e, 0);
    let rich = shown(&mut h);
    assert_eq!(rich.text(), "a **b** `c`\nnext");
    let run = |rich: &zgx::rich_text::RichText, text: &str| {
        let at = rich.text().find(text).unwrap();
        rich.runs()
            .iter()
            .find(|r| r.range.contains(&at))
            .unwrap()
            .clone()
    };
    assert_eq!(run(&rich, "b").font.weight, 700);
    let code = run(&rich, "c`");
    assert_eq!(code.font.family, zgx::text_layout::FontFamily::Monospace);
    assert!(code.background.is_some(), "inline code on its wash");
    // On the second, the first's markers hide.
    at(&mut h, &e, 13);
    let rich = shown(&mut h);
    assert_eq!(rich.text(), "a b c\nnext");
    assert_eq!(run(&rich, "b").font.weight, 700);
    // The value is the Markdown as written.
    assert_eq!(value(&mut h), "a **b** `c`\nnext");
    // Up from the end of "next" (four glyphs in) lands four glyphs into
    // "a b c" as it shows: before "c", after its hidden backtick.
    at(&mut h, &e, 16);
    press(&mut h, Key::ArrowUp, false);
    assert_eq!(e.editor.borrow().selection().focus, 9);
}

#[test]
fn a_break_goes_on_with_a_list_and_tab_indents_its_items() {
    let mut h = draft();
    let e = editor(&mut h);
    e.editor.borrow_mut().set_text("- a");
    at(&mut h, &e, 3);
    // Shift+Enter (plain Enter is a composer's to send) goes on with it.
    press(&mut h, Key::Enter, true);
    assert_eq!(value(&mut h), "- a\n- ");
    // Tab nests the new item, Shift+Tab takes it back out.
    press(&mut h, Key::Tab, false);
    assert_eq!(value(&mut h), "- a\n  - ");
    press(&mut h, Key::Tab, true);
    assert_eq!(value(&mut h), "- a\n- ");
    // A break on an empty item leaves the list.
    press(&mut h, Key::Enter, true);
    assert_eq!(value(&mut h), "- a\n");
    // Bullets are typographic on every line, the caret's too.
    e.editor.borrow_mut().set_text("- one\n- two");
    at(&mut h, &e, 2);
    assert_eq!(shown(&mut h).text(), "• one\n• two");
}

#[test]
fn a_paste_resolves_into_a_chip_that_shows_its_label_in_one_undo_step() {
    let mut h = draft();
    let e = editor(&mut h);
    e.editor.borrow_mut().set_text("see ");
    at(&mut h, &e, 4);
    e.paste("main.rs");
    h.frames(1);
    assert_eq!(value(&mut h), "see @src/main.rs ");
    // The chip shows its file's name, not its path.
    let rich = shown(&mut h);
    assert!(
        rich.text().contains("main.rs") && !rich.text().contains("src/"),
        "{:?}",
        rich.text()
    );
    assert!(e.editor.borrow_mut().undo());
    assert_eq!(e.editor.borrow().text(), "see ");
}

/// A draft's own keys come after the script's: an `on_key` that takes Tab
/// (a completion menu's pick) leaves the list as it is; a `highlight`
/// colours a fence's lines over the code's face.
#[test]
fn the_scripts_keys_come_first_and_highlight_colours_over_the_faces() {
    let mut h = Harness::inline(
        r##"
local v = ui.state("v", "- a")
return ui.textarea { id = "t", value = v, w = 300, h = 120, markdown = true,
    on_key = function(e: KeyEvent): boolean return e.key == "Tab" end,
    highlight = function(line: string, state: number)
        if string.sub(line, 1, 3) == "```" then
            return {}, 1 - state
        end
        return if state == 1 then { { 1, #line, "#ff0000" } } else {}, state
    end,
}"##,
    );
    h.frames(2);
    let e = editor(&mut h);
    at(&mut h, &e, 3);
    press(&mut h, Key::Tab, false);
    assert_eq!(value(&mut h), "- a");
    e.editor.borrow_mut().set_text("```rust\nlet x\n```\nafter");
    at(&mut h, &e, 0);
    let rich = shown(&mut h);
    let x = rich.text().find("let").unwrap();
    let run = rich.runs().iter().find(|r| r.range.contains(&x)).unwrap();
    assert_eq!(run.color, zgx::scene::Color(255, 0, 0, 255));
    assert_eq!(run.font.family, zgx::text_layout::FontFamily::Monospace);
}

/// A chip's card (`chip_tooltip`): the script's node for the chip under the
/// pointer, made as it shows (once for each showing), none off a chip.
#[test]
fn a_chips_card_is_the_scripts_node_made_as_it_shows() {
    let mut h = Harness::inline(
        r##"
local made = ui.state("made", 0)
return ui.column { w = 400, p = 40,
    ui.textarea { id = "t", value = ui.state("v", "see @card now"), w = 300, h = 120, line_height = 20,
        chips = "@",
        chip_tooltip = function(token: string)
            made:set(made:peek() + 1)
            return ui.text { id = "card", "card for " .. token }
        end,
    },
    ui.text { id = "made", function() return tostring(made:get()) end },
}"##,
    );
    h.frames(2);
    if let Some(e) = h.error() {
        panic!("{e}");
    }
    let chip = {
        let node = h.find("t").unwrap();
        let scene = h.ui.scene.borrow();
        let mut stack = vec![node];
        let mut found = None;
        while let Some(n) = stack.pop() {
            if let NodeKind::Quad(q) = scene.kind(n)
                && q.radius == 5.
            {
                found = Some(scene.transformed_bounds(n));
            }
            stack.extend_from_slice(scene.children(n));
        }
        found.expect("the chip's fill")
    };
    let y = chip.y + chip.height / 2.;
    h.ui.dispatch(zgx::input::InputEvent::PointerMove { x: chip.x - 8., y });
    h.frames(2);
    assert_eq!(h.text("made"), "0", "nothing made off a chip");
    h.ui.dispatch(zgx::input::InputEvent::PointerMove {
        x: chip.x + chip.width / 2.,
        y,
    });
    assert!(h.wait_until(|h| h.find("card").is_some()), "its card");
    assert_eq!(h.text("card"), "card for @card");
    assert_eq!(h.text("made"), "1");
}
