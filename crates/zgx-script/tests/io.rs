//! The machine beyond the window (`ui.clipboard`, `ui.open_files`,
//! `ui.save_file`, `ui.read_file`, `ui.write_file`) through a platform the
//! window provides: here a fake, as a desktop window provides the real one.
//! And `ui.haptic`, which taps the platform's trackpad, `ui.open_url`,
//! which hands a web address to its browser, and `ui.play_sound` and
//! `ui.notify`, its sounds and banners.
mod common;
use common::Harness;
use std::{
    cell::RefCell,
    path::PathBuf,
    rc::Rc,
    time::{Duration, Instant},
};
use zgx::platform::{FilePicker, Haptic, Pending, Platform, PlatformService};
use zgx_script::ScriptHost;

struct Fake {
    clipboard: RefCell<String>,
    image: RefCell<Option<std::sync::Arc<zgx::image::ImageData>>>,
    /// What the open dialog picks, and where the save dialog saves.
    opens: PathBuf,
    saves: PathBuf,
    tapped: RefCell<Vec<Haptic>>,
}
impl Platform for Fake {
    fn haptic(&self, haptic: Haptic) -> bool {
        self.tapped.borrow_mut().push(haptic);
        true
    }
    fn clipboard_text(&self) -> Option<String> {
        Some(self.clipboard.borrow().clone())
    }
    fn set_clipboard_text(&self, text: String) -> bool {
        *self.clipboard.borrow_mut() = text;
        true
    }
    fn clipboard_image(&self) -> Pending<Option<zgx::image::ImageData>> {
        // A copy sharing the pixels.
        let image = (self.image.borrow().as_ref())
            .map(|image| image.transformed(zgx::affine::Affine::IDENTITY));
        Box::pin(async move { image })
    }
    fn set_clipboard_image(&self, image: std::sync::Arc<zgx::image::ImageData>) -> Pending<bool> {
        *self.image.borrow_mut() = Some(image);
        Box::pin(async { true })
    }
    fn open_files(&self, _: FilePicker) -> Pending<Result<Vec<PathBuf>, String>> {
        let path = self.opens.clone();
        Box::pin(async move { Ok(vec![path]) })
    }
    fn save_file(&self, _: FilePicker) -> Pending<Result<Option<PathBuf>, String>> {
        let path = self.saves.clone();
        Box::pin(async move { Ok(Some(path)) })
    }
}

const APP: &str = r#"
local shown = ui.state("shown", "")
local kept = ui.state("kept", nil)
return ui.column {
    ui.text { id = "label", function() return shown:get() end },
    ui.button { id = "copy", w = 40, h = 20, "c", on_click = function()
        ui.clipboard.write("copied text")
        shown:set(ui.clipboard.read() or "")
    end },
    ui.button { id = "image", w = 40, h = 20, "i", on_click = function()
        ui.task(function()
            local before = ui.clipboard.read_image():await()
            local mask = ui.bitmap(3, 2, function(x, y) return x / 2 end)
            local written = ui.clipboard.write_image(mask):await()
            -- Kept in state, as a pasted image to show is.
            kept:set(ui.clipboard.read_image():await())
            shown:set(`{before == nil} {written} {kept:get().w}x{kept:get().h}`)
        end)
    end },
    ui.button { id = "open", w = 40, h = 20, "o", on_click = function()
        ui.task(function()
            local files = ui.open_files({ filters = { { "Text", { "txt" } } } }):await()
            shown:set(`{files[1].name}: {ui.read_file(files[1]):await()}`)
        end)
    end },
    ui.button { id = "save", w = 40, h = 20, "s", on_click = function()
        ui.task(function()
            local file = ui.save_file({ name = "out.txt" }):await()
            ui.write_file(file, "saved text"):await()
            shown:set(`wrote {file.name}`)
        end)
    end },
    ui.button { id = "sneak", w = 40, h = 20, "x", on_click = function()
        ui.read_file("/etc/hosts")
    end },
}
"#;

fn dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("zgx-io-{}-{name}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}
fn app(dir: &std::path::Path, code: &'static str, plugin: Option<&'static str>) -> Harness {
    let fake = Rc::new(Fake {
        clipboard: RefCell::new(String::new()),
        image: RefCell::new(None),
        opens: dir.join("in.txt"),
        saves: dir.join("out.txt"),
        tapped: RefCell::default(),
    });
    Harness::wrapped(
        move |runtime| {
            let host = ScriptHost::inline(runtime, "app", code);
            match plugin {
                Some(code) => host.plugin("peek.luau", code),
                None => host,
            }
        },
        move |view| zgx::compose::provide(PlatformService(fake), view),
    )
}
fn wait_for(h: &mut Harness, text: &str) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        h.settle();
        h.ui.prepare_frame();
        if h.text("label") == text {
            return;
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    panic!(
        "label reads {:?}, not {text:?} ({:?})",
        h.text("label"),
        h.host.error().get()
    );
}

#[test]
fn the_clipboard_takes_and_gives_text() {
    let dir = dir("clipboard");
    let mut h = app(&dir, APP, None);
    h.click("copy");
    wait_for(&mut h, "copied text");
}

#[test]
fn the_clipboard_takes_and_gives_images() {
    let dir = dir("clipboard-image");
    let mut h = app(&dir, APP, None);
    h.click("image");
    wait_for(&mut h, "true true 3x2");
}

/// An image's Copy Image: `write_image` takes its `src` as `ui.image`
/// does, its file decoded off the main thread; an SVG has no pixels.
#[test]
fn the_clipboard_takes_an_image_by_its_src() {
    let dir = dir("clipboard-src");
    let src = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("examples/styleguide/images/shadow.jpg")
        .display()
        .to_string();
    let code: &'static str = Box::leak(
        format!(
            r#"
local shown = ui.state("shown", "")
local src = {src:?}
local function copy(from)
    ui.task(function()
        local written = ui.clipboard.write_image(from):await()
        local image = ui.clipboard.read_image():await()
        shown:set(`{{written}} {{image.w}}x{{image.h}}`)
    end)
end
return ui.column {{
    ui.text {{ id = "label", function() return shown:get() end }},
    ui.button {{ id = "file", w = 40, h = 20, "f", on_click = function() copy(src) end }},
    ui.button {{ id = "svg", w = 40, h = 20, "s", on_click = function() copy("icons/x.svg") end }},
}}
"#
        )
        .into_boxed_str(),
    );
    let mut h = app(&dir, code, None);
    h.click("file");
    wait_for(&mut h, "true 720x480");
    h.click("svg");
    h.settle();
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("an SVG has no pixels"), "{error}");
}

#[test]
fn a_picked_file_reads_and_a_saved_one_is_written() {
    let dir = dir("files");
    std::fs::write(dir.join("in.txt"), "hello from disk").unwrap();
    let mut h = app(&dir, APP, None);
    h.click("open");
    wait_for(&mut h, "in.txt: hello from disk");
    h.click("save");
    wait_for(&mut h, "wrote out.txt");
    assert_eq!(
        std::fs::read_to_string(dir.join("out.txt")).unwrap(),
        "saved text"
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn a_file_the_user_did_not_pick_is_out_of_reach() {
    let dir = dir("sneak");
    let mut h = app(&dir, APP, None);
    h.click("sneak");
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("only files the user picked"), "{error}");
}

#[test]
fn a_plugin_needs_its_hosts_grant() {
    let dir = dir("plugin");
    let h = app(
        &dir,
        r#"return ui.text { "app", id = "label" }"#,
        Some(r#"ui.clipboard.read()"#),
    );
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("Capability::Clipboard"), "{error}");
    let h = app(
        &dir,
        r#"return ui.text { "app", id = "label" }"#,
        Some(r#"ui.clipboard.read_image()"#),
    );
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("Capability::Clipboard"), "{error}");
}

#[test]
fn without_a_platform_it_says_so() {
    let mut h = Harness::new(|runtime| ScriptHost::inline(runtime, "app", APP));
    h.click("copy");
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("need a desktop window"), "{error}");
}

/// `ui.args` is what the app was launched with; `ui.on_open` is handed the
/// files and URLs the system opens with it, the files the script's to read
/// as a dialog's are, and a launch's waiting until the script takes them.
#[test]
fn launch_arguments_and_files_the_system_opens_reach_the_script() {
    let file = std::env::temp_dir().join(format!("zgx-on-open-{}.txt", std::process::id()));
    std::fs::write(&file, "opened by the system").unwrap();
    let (opened, given) = (file.clone(), file.clone());
    let mut h = Harness::with_desktop(move |runtime| {
        let host = ScriptHost::inline(
            runtime,
            "app",
            r#"local args = ui.state("args", table.concat(ui.args, " "))
            local got = ui.state("got", "")
            ui.on_open(function(e)
                local urls = table.concat(e.urls, " ")
                for _, file in e.files do
                    ui.task(function()
                        got:set(`{file.name}: {ui.read_file(file):await()} {urls}`)
                    end)
                end
                if #e.files == 0 then got:set(urls) end
            end)
            return ui.column { ui.text { "{args}", id = "args" }, ui.text { "{got}", id = "got" } }"#,
        )
        .args(["--verbose", "notes.txt"]);
        // Asked before the script loads (a launch's file): it waits.
        host.open(vec![opened], vec!["zgx://launch".into()]);
        host
    });
    assert_eq!(h.text("args"), "--verbose notes.txt");
    let name = given.file_name().unwrap().to_string_lossy().into_owned();
    assert!(h.wait_until(|h| h.text("got").starts_with(&name)));
    assert_eq!(
        h.text("got"),
        format!("{name}: opened by the system zgx://launch")
    );
    h.host.open(vec![], vec!["https://example.org/a".into()]);
    h.settle();
    assert_eq!(h.text("got"), "https://example.org/a");
    let _ = std::fs::remove_file(&file);
}

const TAPS: &str = r#"
local felt = ui.state("felt", "")
return ui.column {
    ui.text { id = "label", function() return felt:get() end },
    ui.button { id = "tap", w = 40, h = 20, "t", on_click = function()
        felt:set(`{ui.haptic()} {ui.haptic("alignment")}`)
    end },
    ui.button { id = "bad", w = 40, h = 20, "b", on_click = function()
        ui.haptic("buzz" :: any)
    end },
}
"#;

#[test]
fn a_haptic_reaches_the_platform_and_is_counted() {
    let fake = Rc::new(Fake {
        clipboard: RefCell::new(String::new()),
        image: RefCell::default(),
        opens: PathBuf::new(),
        saves: PathBuf::new(),
        tapped: RefCell::default(),
    });
    let platform = fake.clone();
    let mut h = Harness::wrapped(
        |runtime| ScriptHost::inline(runtime, "app", TAPS),
        move |view| zgx::compose::provide(PlatformService(platform), view),
    );
    assert_eq!(h.host.haptics(), (0, None));
    h.click("tap");
    wait_for(&mut h, "true true");
    assert_eq!(*fake.tapped.borrow(), [Haptic::Level, Haptic::Alignment]);
    assert_eq!(h.host.haptics(), (2, Some(Haptic::Alignment)));
    h.click("bad");
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("not \"buzz\""), "{error}");
}

#[test]
fn headless_a_haptic_is_counted_and_felt_by_nothing() {
    let mut h = Harness::new(|runtime| ScriptHost::inline(runtime, "app", TAPS));
    h.click("tap");
    wait_for(&mut h, "false false");
    assert_eq!(h.host.haptics(), (2, Some(Haptic::Alignment)));
    assert_eq!(h.host.error().get(), None);
}

/// `ui.open_url` hands web addresses to the system's browser, and a pane of
/// the system's settings to them (where a permission is granted), and
/// nothing else; headless it opens nothing, and a plugin needs the web's
/// grant.
#[test]
fn only_web_addresses_open_in_the_systems_browser() {
    let mut h = Harness::with_desktop(|runtime| {
        ScriptHost::inline(
            runtime,
            "app",
            r#"local said = ui.state("said", "")
            local function open(url) said:set(said:peek() .. tostring(ui.open_url(url)) .. " ") end
            return ui.column {
                ui.text { "{said}", id = "label" },
                ui.button { id = "open", w = 20, h = 20, on_click = function()
                    for _, url in { "https://example.com/a", "http://localhost:3000/", "mailto:a@b.c",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                        "ms-settings:privacy-microphone", "file:///etc/passwd", "zeron://chat/1",
                        "https://", "javascript:alert(1)", "x-apple.systempreferences:" } do
                        open(url)
                    end
                end },
            }"#,
        )
    });
    h.click("open");
    wait_for(
        &mut h,
        "true true true true true false false false false false ",
    );
    let desktop = h.desktop.clone().unwrap();
    assert_eq!(
        desktop.opened(),
        [
            "https://example.com/a",
            "http://localhost:3000/",
            "mailto:a@b.c",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "ms-settings:privacy-microphone"
        ]
    );
    let mut h = Harness::new(|runtime| {
        ScriptHost::inline(
            runtime,
            "app",
            r#"local said = ui.state("said", "")
            return ui.column {
                ui.text { "{said}", id = "label" },
                ui.button { id = "open", w = 20, h = 20, on_click = function()
                    said:set(tostring(ui.open_url("https://example.com/")))
                end },
            }"#,
        )
    });
    h.click("open");
    wait_for(&mut h, "false");
    let dir = dir("open-url");
    let h = app(
        &dir,
        r#"return ui.text { "app", id = "label" }"#,
        Some(r#"ui.open_url("https://example.com/")"#),
    );
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("Capability::Web"), "{error}");
}

/// `ui.play_sound` hands the platform a sound from the script's directory,
/// and `ui.notify` a banner: one for the background posts only while the
/// app is not frontmost. Headless nothing plays nor shows, and a plugin
/// needs its host's grant.
#[test]
fn sounds_and_banners_reach_the_platform() {
    let dir = dir("notify");
    let script = dir.join("app.luau");
    std::fs::write(
        &script,
        r#"local said = ui.state("said", "")
        local function say(v) said:set(said:peek() .. tostring(v) .. " ") end
        return ui.column {
            ui.text { "{said}", id = "label" },
            ui.button { id = "go", w = 20, h = 20, on_click = function()
                say(ui.play_sound("sounds/done.wav"))
                say(ui.notify { title = "Write the notes", body = "Run finished" })
                say(ui.notify { title = "Away", body = "Waiting on your input", background = true })
            end },
        }"#,
    )
    .unwrap();
    let path = script.clone();
    let mut h = Harness::with_desktop(move |runtime| ScriptHost::new(runtime, path));
    h.click("go");
    wait_for(&mut h, "true true false ");
    let desktop = h.desktop.clone().unwrap();
    assert_eq!(desktop.played(), [dir.join("sounds/done.wav")]);
    let said = |d: &zgx_script::testing::FakeDesktop| {
        d.notified()
            .into_iter()
            .map(|n| format!("{}: {}", n.title, n.body))
            .collect::<Vec<_>>()
    };
    assert_eq!(said(&desktop), ["Write the notes: Run finished"]);
    // In the background, the background's banner posts too.
    desktop.set_active(false);
    h.click("go");
    wait_for(&mut h, "true true false true true true ");
    assert_eq!(desktop.played().len(), 2);
    assert_eq!(
        said(&desktop)[1..],
        [
            "Write the notes: Run finished",
            "Away: Waiting on your input"
        ]
    );
    // Headless: nothing to play or show on, and no error.
    let path = script.clone();
    let mut h = Harness::new(move |runtime| ScriptHost::new(runtime, path));
    h.click("go");
    wait_for(&mut h, "false false false ");
    let h = app(
        &dir,
        r#"return ui.text { "app", id = "label" }"#,
        Some(r#"ui.notify { title = "Your bank", body = "Type your password" }"#),
    );
    let error = h.host.error().get().unwrap_or_default();
    assert!(error.contains("Capability::Notify"), "{error}");
}

/// A banner posted with `data` hands it to `ui.on_notification` when it is
/// clicked, the handler of the script's run loaded now; one without is not
/// followed, nor is another host's.
#[test]
fn a_clicked_banner_hands_its_data_to_the_script() {
    let dir = dir("notify-click");
    let script = dir.join("app.luau");
    std::fs::write(
        &script,
        r#"local opened = ui.state("opened", "")
        ui.on_notification(function(data)
            opened:set(opened:peek() .. data.chat .. " ")
        end)
        return ui.column {
            ui.text { "{opened}", id = "label" },
            ui.button { id = "go", w = 20, h = 20, on_click = function()
                ui.notify { title = "Write the notes", body = "Run finished", data = { chat = "a1" } }
                ui.notify { title = "Offline", body = "Your device is offline" }
            end },
        }"#,
    )
    .unwrap();
    let path = script.clone();
    let mut h = Harness::with_desktop(move |runtime| ScriptHost::new(runtime, path));
    // Another host, with banners of its own.
    let other = dir.join("other.luau");
    std::fs::write(
        &other,
        r#"ui.on_notification(function() error("not mine") end)
        return ui.text { "other" }"#,
    )
    .unwrap();
    let o = Harness::with_desktop(move |runtime| ScriptHost::new(runtime, other));
    o.settle();
    h.click("go");
    h.settle();
    let desktop = h.desktop.clone().unwrap();
    assert_eq!(desktop.notified().len(), 2);
    assert!(desktop.notified()[1].id.is_empty(), "nothing to follow");
    desktop.click_notification(0);
    desktop.click_notification(1);
    wait_for(&mut h, "a1 ");
    // After a reload, the new run hears clicks on banners from before it.
    h.host.reload().unwrap();
    h.settle();
    desktop.click_notification(0);
    wait_for(&mut h, "a1 a1 ");
    o.settle();
    assert!(o.host.error().get().is_none());
}
