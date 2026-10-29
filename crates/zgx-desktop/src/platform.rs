//! The desktop's `zgx::platform::Platform`: the native clipboard, the
//! window's file dialogs and the trackpad's haptics, provided to what a
//! window renders.
use std::{cell::RefCell, path::PathBuf, rc::Rc, sync::Arc};
use zgx::platform::{FilePicker, Pending, Platform};

pub(crate) struct Desktop {
    pub(crate) clipboard: Rc<RefCell<Option<crate::clipboard::Clipboard>>>,
    pub(crate) dialogs: crate::FileDialogs,
}

impl Desktop {
    fn images(&self) -> Option<crate::clipboard::Images> {
        self.clipboard
            .borrow()
            .as_ref()
            .map(|clipboard| clipboard.images())
    }
}

/// `work` on a thread of its own, its result later (none if it panicked):
/// decoding or encoding a large image for the clipboard takes tens of
/// milliseconds, a frame or more on the UI thread.
fn off_thread<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Pending<Option<T>> {
    let (tell, mut heard) = zgx::task::latest::<T>();
    std::thread::spawn(move || tell.send(work()));
    Box::pin(async move { heard.recv().await })
}

fn options(picker: &FilePicker) -> crate::FileDialogOptions {
    let mut options = crate::FileDialogOptions::new(picker.title.clone());
    options.directory = picker.directory.clone();
    options.file_name = picker.file_name.clone();
    options.filters = picker
        .filters
        .iter()
        .map(|(name, extensions)| crate::FileFilter::new(name.clone(), extensions.clone()))
        .collect();
    options
}

impl Platform for Desktop {
    fn clipboard_text(&self) -> Option<String> {
        self.clipboard.borrow_mut().as_mut()?.get_text().ok()
    }
    fn set_clipboard_text(&self, text: String) -> bool {
        self.clipboard
            .borrow_mut()
            .as_mut()
            .is_some_and(|clipboard| clipboard.set_text(text).is_ok())
    }
    #[cfg(target_os = "macos")]
    fn looks_up(&self) -> bool {
        true
    }
    #[cfg(target_os = "macos")]
    fn look_up(&self, text: &str, baseline: (f32, f32), size: f32) -> bool {
        self.dialogs
            .window()
            .is_some_and(|window| crate::look_up::show(&window, text, baseline, size))
    }
    fn open_url(&self, url: &str) -> bool {
        // The launcher runs detached: nothing waits on the browser.
        crate::url::valid_url(url) && open::that_detached(url).is_ok()
    }
    #[cfg(target_os = "macos")]
    fn haptic(&self, haptic: zgx::platform::Haptic) -> bool {
        haptics::perform(haptic)
    }
    #[cfg(target_os = "macos")]
    fn play_sound(&self, path: &std::path::Path) -> bool {
        sounds::play(path)
    }
    #[cfg(target_os = "macos")]
    fn notify(&self, notification: &zgx::platform::Notification) -> bool {
        banners::post(notification)
    }
    #[cfg(target_os = "macos")]
    fn app_active(&self) -> bool {
        objc2::MainThreadMarker::new()
            .is_none_or(|mtm| objc2_app_kit::NSApplication::sharedApplication(mtm).isActive())
    }
    #[cfg(any(target_os = "macos", windows, target_os = "linux"))]
    fn misspellings(&self, text: &str) -> Vec<std::ops::Range<usize>> {
        spelling::misspellings(text)
    }
    #[cfg(any(target_os = "macos", windows, target_os = "linux"))]
    fn spelling_guesses(&self, word: &str) -> Vec<String> {
        spelling::guesses(word)
    }
    #[cfg(any(target_os = "macos", windows, target_os = "linux"))]
    fn learn_spelling(&self, word: &str) {
        spelling::learn(word);
    }
    #[cfg(any(target_os = "macos", windows, target_os = "linux"))]
    fn ignore_spelling(&self, word: &str) {
        spelling::ignore(word);
    }
    fn set_clipboard_rich_text(&self, text: String, html: String) -> bool {
        self.clipboard
            .borrow_mut()
            .as_mut()
            .is_some_and(|clipboard| clipboard.set_rich_text(text, html).is_ok())
    }
    fn clipboard_image(&self) -> Pending<Option<zgx::image::ImageData>> {
        let images = self.images();
        Box::pin(async move {
            let images = images?;
            off_thread(move || crate::clipboard::read_image(&images).ok())
                .await
                .flatten()
        })
    }
    fn set_clipboard_image(&self, image: Arc<zgx::image::ImageData>) -> Pending<bool> {
        let images = self.images();
        Box::pin(async move {
            let Some(images) = images else {
                return false;
            };
            off_thread(move || crate::clipboard::write_image(&images, &image).is_ok())
                .await
                .unwrap_or(false)
        })
    }
    fn open_files(&self, picker: FilePicker) -> Pending<Result<Vec<PathBuf>, String>> {
        let dialogs = self.dialogs.clone();
        Box::pin(async move {
            let options = options(&picker);
            let picked = if picker.multiple {
                dialogs.open_files(options).await
            } else {
                dialogs
                    .open_file(options)
                    .await
                    .map(|one| one.map(|path| vec![path]))
            };
            picked
                .map(Option::unwrap_or_default)
                .map_err(|e| e.to_string())
        })
    }
    fn save_file(&self, picker: FilePicker) -> Pending<Result<Option<PathBuf>, String>> {
        let dialogs = self.dialogs.clone();
        Box::pin(async move {
            dialogs
                .save_file(options(&picker))
                .await
                .map_err(|e| e.to_string())
        })
    }
}

/// UTF-16 offset `units` into `text` as a UTF-8 byte offset: where the
/// system's spelling checkers count.
#[cfg(any(target_os = "macos", windows))]
fn byte_offset(text: &str, units: usize) -> usize {
    let mut seen = 0;
    for (byte, c) in text.char_indices() {
        if seen >= units {
            return byte;
        }
        seen += c.len_utf16();
    }
    text.len()
}

#[cfg(target_os = "linux")]
use crate::linux_spelling as spelling;

/// macOS's haptic feedback (`NSHapticFeedbackManager`), performed now
/// rather than at the next draw. AppKit does nothing where the trackpad
/// cannot (a mouse, an older trackpad).
#[cfg(target_os = "macos")]
mod haptics {
    use objc2_app_kit::{
        NSHapticFeedbackManager, NSHapticFeedbackPattern, NSHapticFeedbackPerformanceTime,
        NSHapticFeedbackPerformer,
    };
    use zgx::platform::Haptic;

    pub(super) fn perform(haptic: Haptic) -> bool {
        // AppKit's performer is the main thread's, where input is handled.
        if objc2::MainThreadMarker::new().is_none() {
            return false;
        }
        let pattern = match haptic {
            Haptic::Level => NSHapticFeedbackPattern::LevelChange,
            Haptic::Alignment => NSHapticFeedbackPattern::Alignment,
            Haptic::Generic => NSHapticFeedbackPattern::Generic,
        };
        NSHapticFeedbackManager::defaultPerformer()
            .performFeedbackPattern_performanceTime(pattern, NSHapticFeedbackPerformanceTime::Now);
        true
    }
}

/// macOS's sounds (`NSSound`): each file read once and kept, played on the
/// main thread, where AppKit mixes it without blocking; played again, it
/// starts over.
#[cfg(target_os = "macos")]
mod sounds {
    use objc2::{AnyThread, rc::Retained};
    use objc2_app_kit::NSSound;
    use objc2_foundation::NSString;
    use std::{
        cell::RefCell,
        collections::HashMap,
        path::{Path, PathBuf},
    };

    thread_local! {
        static LOADED: RefCell<HashMap<PathBuf, Retained<NSSound>>> = RefCell::default();
    }

    pub(super) fn play(path: &Path) -> bool {
        if objc2::MainThreadMarker::new().is_none() {
            return false;
        }
        let Some(name) = path.to_str() else {
            return false;
        };
        let sound = LOADED.with(|loaded| {
            let mut loaded = loaded.borrow_mut();
            if let Some(sound) = loaded.get(path) {
                return Some(sound.clone());
            }
            let sound = NSSound::initWithContentsOfFile_byReference(
                NSSound::alloc(),
                &NSString::from_str(name),
                true,
            )?;
            loaded.insert(path.to_path_buf(), sound.clone());
            Some(sound)
        });
        sound.is_some_and(|sound| {
            sound.stop();
            sound.play()
        })
    }
}

/// macOS's banners: the notification centre's (`NSUserNotification`, which
/// needs no permission prompt and carries the app's name and icon) where
/// the process has a bundle of its own; without one (`cargo run`), through
/// `osascript`, attributed to Script Editor. A delegate has the centre
/// show them while the app is frontmost too: whether to post is the app's
/// choice. A banner with an id hands it back when clicked
/// (`zgx::platform::notification_clicked`); one shown through `osascript`
/// cannot.
#[cfg(target_os = "macos")]
mod banners {
    #![allow(deprecated)]
    use objc2::{
        MainThreadMarker, MainThreadOnly, define_class, msg_send,
        rc::Retained,
        runtime::{NSObject, ProtocolObject},
    };
    use objc2_foundation::{
        NSBundle, NSObjectProtocol, NSString, NSUserNotification, NSUserNotificationCenter,
        NSUserNotificationCenterDelegate,
    };
    use zgx::platform::Notification;

    define_class!(
        // SAFETY: an NSObject subclass with no ivars, main-thread only (the
        // centre asks its delegate there); its methods have the delegate's
        // signatures.
        #[unsafe(super(NSObject))]
        #[thread_kind = MainThreadOnly]
        struct Presenter;
        unsafe impl NSObjectProtocol for Presenter {}
        unsafe impl NSUserNotificationCenterDelegate for Presenter {
            #[unsafe(method(userNotificationCenter:shouldPresentNotification:))]
            fn should_present(&self, _: &NSUserNotificationCenter, _: &NSUserNotification) -> bool {
                true
            }
            #[unsafe(method(userNotificationCenter:didActivateNotification:))]
            fn did_activate(&self, _: &NSUserNotificationCenter, banner: &NSUserNotification) {
                if let Some(id) = banner.identifier() {
                    zgx::platform::notification_clicked(&id.to_string());
                }
            }
        }
    );
    impl Presenter {
        fn new(mtm: MainThreadMarker) -> Retained<Self> {
            let this = Self::alloc(mtm).set_ivars(());
            unsafe { msg_send![super(this), init] }
        }
    }

    thread_local! {
        // The centre keeps its delegate weakly.
        static PRESENTER: std::cell::OnceCell<Retained<Presenter>> = const { std::cell::OnceCell::new() };
    }

    fn centre(mtm: MainThreadMarker) -> Option<Retained<NSUserNotificationCenter>> {
        NSBundle::mainBundle().bundleIdentifier()?;
        // Nil without a bundle: asked as an optional.
        let centre: Option<Retained<NSUserNotificationCenter>> = unsafe {
            msg_send![
                objc2::class!(NSUserNotificationCenter),
                defaultUserNotificationCenter
            ]
        };
        let centre = centre?;
        PRESENTER.with(|presenter| {
            let presenter = presenter.get_or_init(|| Presenter::new(mtm));
            unsafe { centre.setDelegate(Some(ProtocolObject::from_ref(&**presenter))) };
        });
        Some(centre)
    }

    pub(super) fn post(notification: &Notification) -> bool {
        let Some(mtm) = MainThreadMarker::new() else {
            return false;
        };
        if let Some(centre) = centre(mtm) {
            let banner = NSUserNotification::new();
            banner.setTitle(Some(&NSString::from_str(&notification.title)));
            banner.setInformativeText(Some(&NSString::from_str(&notification.body)));
            if !notification.id.is_empty() {
                banner.setIdentifier(Some(&NSString::from_str(&notification.id)));
            }
            centre.deliverNotification(&banner);
            return true;
        }
        let script = format!(
            "display notification \"{}\" with title \"{}\"",
            escape(&notification.body),
            escape(&notification.title),
        );
        // Off the main thread: osascript takes a moment to start.
        std::thread::spawn(move || {
            let _ = std::process::Command::new("osascript")
                .args(["-e", &script])
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status();
        });
        true
    }

    /// `text` inside an AppleScript string: its quotes and backslashes
    /// escaped, its line breaks spaces.
    pub(super) fn escape(text: &str) -> String {
        let mut out = String::with_capacity(text.len());
        for c in text.chars() {
            match c {
                '"' | '\\' => {
                    out.push('\\');
                    out.push(c);
                }
                '\n' | '\r' => out.push(' '),
                c if c.is_control() => {}
                c => out.push(c),
            }
        }
        out
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn a_banner_s_text_cannot_end_the_script_s_string() {
            assert_eq!(
                super::escape("Run \"x\" \\ done\nnow"),
                "Run \\\"x\\\" \\\\ done now"
            );
        }
    }
}

/// macOS's spelling checker (`NSSpellChecker`), for editors that check
/// (`View::spellcheck`). One document tag for the app: what Ignore Spelling
/// ignores, it ignores in every editor until the app quits.
#[cfg(target_os = "macos")]
mod spelling {
    use super::byte_offset;
    use objc2_app_kit::NSSpellChecker;
    use objc2_foundation::{NSRange, NSString};
    use std::ops::Range;

    fn tag() -> isize {
        static TAG: std::sync::OnceLock<isize> = std::sync::OnceLock::new();
        *TAG.get_or_init(NSSpellChecker::uniqueSpellDocumentTag)
    }
    pub(super) fn misspellings(text: &str) -> Vec<Range<usize>> {
        let checker = NSSpellChecker::sharedSpellChecker();
        let string = NSString::from_str(text);
        let length = string.length();
        let mut found = Vec::new();
        let mut from = 0;
        while from < length {
            // SAFETY: a start inside the string (`from < length`), no
            // language (the checker's own), and no word count asked for (a
            // null pointer, which the method allows).
            let range = unsafe {
                checker.checkSpellingOfString_startingAt_language_wrap_inSpellDocumentWithTag_wordCount(
                    &string,
                    from as isize,
                    None,
                    false,
                    tag(),
                    std::ptr::null_mut(),
                )
            };
            if range.length == 0 || range.location >= length {
                break;
            }
            let start = byte_offset(text, range.location);
            let end = byte_offset(text, range.location + range.length);
            found.push(start..end);
            from = range.location + range.length;
        }
        found
    }
    pub(super) fn guesses(word: &str) -> Vec<String> {
        let checker = NSSpellChecker::sharedSpellChecker();
        let string = NSString::from_str(word);
        let range = NSRange::new(0, string.length());
        checker
            .guessesForWordRange_inString_language_inSpellDocumentWithTag(
                range,
                &string,
                None,
                tag(),
            )
            .map(|guesses| guesses.iter().map(|g| g.to_string()).collect())
            .unwrap_or_default()
    }
    pub(super) fn learn(word: &str) {
        NSSpellChecker::sharedSpellChecker().learnWord(&NSString::from_str(word));
    }
    pub(super) fn ignore(word: &str) {
        NSSpellChecker::sharedSpellChecker()
            .ignoreWord_inSpellDocumentWithTag(&NSString::from_str(word), tag());
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn the_system_checker_finds_misspellings_as_byte_ranges() {
            let text = "Thé quikc brown fox";
            let found = super::misspellings(text);
            assert!(
                found.iter().any(|r| &text[r.clone()] == "quikc"),
                "{found:?}"
            );
            assert!(!super::guesses("quikc").is_empty());
        }
    }
}

/// Windows' spelling checker (`ISpellChecker`, Edge's and the system's text
/// fields'), for editors that check (`View::spellcheck`), in the language
/// the user types: the keyboard layout's, else the user's locale. One
/// checker a language for the app: what Ignore Spelling ignores, it ignores
/// in every editor until the app quits; Learn Spelling adds to the user's
/// dictionary, which the system's other checkers share.
#[cfg(windows)]
mod spelling {
    use super::byte_offset;
    use std::{cell::RefCell, collections::HashMap, ops::Range};
    use windows::{
        Win32::{
            Globalization::{
                CORRECTIVE_ACTION_GET_SUGGESTIONS, CORRECTIVE_ACTION_REPLACE,
                GetUserDefaultLocaleName, ISpellChecker, ISpellCheckerFactory, LCIDToLocaleName,
                SpellCheckerFactory,
            },
            System::Com::{
                CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED, CoCreateInstance, CoInitializeEx,
                CoTaskMemFree,
            },
            UI::Input::KeyboardAndMouse::GetKeyboardLayout,
        },
        core::{HSTRING, PWSTR},
    };

    /// The factory, and each language's checker as first asked for.
    type Checkers = (ISpellCheckerFactory, HashMap<String, Option<ISpellChecker>>);

    thread_local! {
        /// `None` where Windows has no checker (Windows 7, a server core).
        /// Never released: at the thread's exit COM is already shut down
        /// (winit uninitializes OLE), and releasing then hung the process.
        static CHECKERS: &'static RefCell<Option<Checkers>> =
            Box::leak(Box::new(RefCell::new({
                // SAFETY: COM on this (the UI) thread; winit's OLE already
                // made it a single-threaded apartment, which this joins.
                unsafe {
                    let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
                    CoCreateInstance(&SpellCheckerFactory, None, CLSCTX_INPROC_SERVER)
                        .ok()
                        .map(|factory| (factory, HashMap::new()))
                }
            })));
    }

    /// The language the user types now: the foreground keyboard layout's.
    fn language() -> String {
        let mut name = [0u16; 85];
        // SAFETY: reads this thread's layout; writes at most `name`'s length.
        let length = unsafe {
            let layout = GetKeyboardLayout(0).0 as usize & 0xffff;
            match LCIDToLocaleName(layout as u32, Some(&mut name), 0) {
                0 => GetUserDefaultLocaleName(&mut name),
                length => length,
            }
        };
        String::from_utf16_lossy(&name[..(length.max(1) - 1) as usize])
    }

    fn with_checker<T>(run: impl FnOnce(&ISpellChecker) -> T) -> Option<T> {
        CHECKERS.with(|checkers| {
            let mut checkers = checkers.borrow_mut();
            let (factory, languages) = checkers.as_mut()?;
            let checker = languages.entry(language()).or_insert_with_key(|language| {
                let tag = HSTRING::from(language.as_str());
                // SAFETY: plain COM calls on the factory.
                unsafe {
                    let supported = factory.IsSupported(&tag).is_ok_and(|s| s.as_bool());
                    let tag = if supported {
                        tag
                    } else {
                        HSTRING::from("en-US")
                    };
                    factory.CreateSpellChecker(&tag).ok()
                }
            });
            checker.as_ref().map(run)
        })
    }

    pub(super) fn misspellings(text: &str) -> Vec<Range<usize>> {
        with_checker(|checker| {
            let mut found = Vec::new();
            // Kept until the enumeration ends, which may check as it goes.
            let checked = HSTRING::from(text);
            // SAFETY: plain COM calls on a checker of this thread's, with a
            // string alive across them; each error is released as it goes.
            unsafe {
                let Ok(errors) = checker.Check(&checked) else {
                    return found;
                };
                let mut error = None;
                while errors.Next(&mut error).is_ok() {
                    let Some(error) = error.take() else {
                        break;
                    };
                    // Misspellings, not repeated words (to delete), as
                    // macOS's checker marks them.
                    if !error.CorrectiveAction().is_ok_and(|action| {
                        action == CORRECTIVE_ACTION_GET_SUGGESTIONS
                            || action == CORRECTIVE_ACTION_REPLACE
                    }) {
                        continue;
                    }
                    let (Ok(start), Ok(length)) = (error.StartIndex(), error.Length()) else {
                        continue;
                    };
                    let (start, length) = (start as usize, length as usize);
                    found.push(byte_offset(text, start)..byte_offset(text, start + length));
                }
            }
            found
        })
        .unwrap_or_default()
    }

    pub(super) fn guesses(word: &str) -> Vec<String> {
        with_checker(|checker| {
            let mut guesses = Vec::new();
            // SAFETY: plain COM calls; each suggestion fetched is a
            // NUL-terminated string the callee allocated with CoTaskMemAlloc,
            // ours to free once read.
            unsafe {
                let Ok(suggestions) = checker.Suggest(&HSTRING::from(word)) else {
                    return guesses;
                };
                let mut next = [PWSTR::null()];
                let mut fetched = 0;
                while suggestions.Next(&mut next, Some(&mut fetched)).is_ok() && fetched == 1 {
                    guesses.extend(next[0].to_string());
                    CoTaskMemFree(Some(next[0].0 as *const _));
                }
            }
            guesses
        })
        .unwrap_or_default()
    }

    pub(super) fn learn(word: &str) {
        // SAFETY: a plain COM call.
        with_checker(|checker| unsafe { checker.Add(&HSTRING::from(word)) });
    }

    pub(super) fn ignore(word: &str) {
        // SAFETY: a plain COM call.
        with_checker(|checker| unsafe { checker.Ignore(&HSTRING::from(word)) });
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn the_system_checker_finds_misspellings_as_byte_ranges() {
            let text = "Thé quikc brown fox";
            let found = super::misspellings(text);
            assert!(
                found.iter().any(|r| &text[r.clone()] == "quikc"),
                "{found:?}"
            );
            assert!(super::guesses("quikc").iter().any(|g| g == "quick"));
        }
    }
}
