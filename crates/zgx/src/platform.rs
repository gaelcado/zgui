//! What an app reaches on the machine beyond its window: the clipboard (text,
//! HTML and images), the file dialogs, the trackpad's haptics, sounds and
//! the desktop's banners. A desktop host provides it to the components it renders
//! (`compose::provide`, as `Context::try_service::<PlatformService>()`);
//! headless runs have none, and tests provide a fake.
use std::{future::Future, path::PathBuf, pin::Pin, rc::Rc, sync::Arc};

/// Work a dialog finishes later.
pub type Pending<T> = Pin<Box<dyn Future<Output = T>>>;

/// What a file dialog shows.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FilePicker {
    /// The dialog's title.
    pub title: String,
    /// Where it opens.
    pub directory: Option<PathBuf>,
    /// The name a save dialog suggests.
    pub file_name: Option<String>,
    /// Filters: a name and its extensions, without the dot.
    pub filters: Vec<(String, Vec<String>)>,
    /// An open dialog lets the user pick several files.
    pub multiple: bool,
}

/// A tap of the trackpad under the user's finger (`Platform::haptic`), as
/// macOS names its patterns.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Haptic {
    /// A control moved to its next detent: a slider's step, a stepper.
    Level,
    /// Something snapped into place: a dragged item settling, a guide met.
    Alignment,
    /// Any other feedback.
    Generic,
}

impl Haptic {
    /// The pattern a name gives (`"level"`, `"alignment"`, `"generic"`).
    pub fn from_name(name: &str) -> Option<Self> {
        Some(match name {
            "level" => Self::Level,
            "alignment" => Self::Alignment,
            "generic" => Self::Generic,
            _ => return None,
        })
    }
}

/// A desktop banner (`Platform::notify`): the system's notification, the
/// app's name and icon on it.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Notification {
    /// Its first line.
    pub title: String,
    /// What it says under the title.
    pub body: String,
    /// What a click on it hands back ([`notification_clicked`]); empty for
    /// a banner the app does not follow.
    pub id: String,
}

type ClickListener = Rc<dyn Fn(&str)>;
thread_local! {
    static CLICK_LISTENERS: std::cell::RefCell<Vec<(u64, ClickListener)>> =
        const { std::cell::RefCell::new(Vec::new()) };
    static NEXT_CLICK_LISTENER: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

/// A banner was clicked: the platform calls this with its
/// [`Notification::id`], on the UI thread, and every listener
/// ([`on_notification_click`]) hears it.
pub fn notification_clicked(id: &str) {
    if id.is_empty() {
        return;
    }
    let listeners: Vec<ClickListener> =
        CLICK_LISTENERS.with(|l| l.borrow().iter().map(|(_, f)| f.clone()).collect());
    for listener in listeners {
        listener(id);
    }
}

/// Hear each banner clicked (its [`Notification::id`]) until the
/// subscription drops. A platform that cannot tell (a banner shown by
/// another program) never calls it.
pub fn on_notification_click(listener: impl Fn(&str) + 'static) -> NotificationClicks {
    let id = NEXT_CLICK_LISTENER.with(|next| {
        next.set(next.get() + 1);
        next.get()
    });
    CLICK_LISTENERS.with(|l| l.borrow_mut().push((id, Rc::new(listener))));
    NotificationClicks(id)
}

/// Keeps an [`on_notification_click`] listener; dropping it stops it.
pub struct NotificationClicks(u64);
impl Drop for NotificationClicks {
    fn drop(&mut self) {
        let id = self.0;
        let _ = CLICK_LISTENERS.try_with(|l| {
            if let Ok(mut l) = l.try_borrow_mut() {
                l.retain(|(own, _)| *own != id);
            }
        });
    }
}

/// The clipboard, the system's URL handler and file dialogs, as a desktop
/// host provides them (see the module docs).
pub trait Platform {
    /// The clipboard's text, if it holds text.
    fn clipboard_text(&self) -> Option<String>;
    /// Put `text` on the clipboard; whether it took it.
    fn set_clipboard_text(&self, text: String) -> bool;
    /// Open `url` with the system's handler for it (a browser for
    /// `https:`); whether the request was made. None opens nothing.
    fn open_url(&self, url: &str) -> bool {
        let _ = url;
        false
    }
    /// Tap the trackpad now; whether the platform could. A machine without a
    /// haptic trackpad (and every platform but macOS) feels nothing.
    fn haptic(&self, haptic: Haptic) -> bool {
        let _ = haptic;
        false
    }
    /// Play the sound file at `path` (a WAV, an AIFF, an MP3) now, over what
    /// it played before; whether the platform could. The same file played
    /// again starts over. None plays nothing.
    fn play_sound(&self, path: &std::path::Path) -> bool {
        let _ = path;
        false
    }
    /// Show `notification` as the desktop's banner, even while the app is
    /// frontmost (whether to is the app's to decide, with `app_active`);
    /// whether it was handed to the system. None shows nothing. A click on
    /// it calls [`notification_clicked`] with its id, where the platform
    /// tells.
    fn notify(&self, notification: &Notification) -> bool {
        let _ = notification;
        false
    }
    /// Whether the app is frontmost: one of its windows has the keyboard.
    /// A platform that cannot tell says it is.
    fn app_active(&self) -> bool {
        true
    }
    /// The misspelled words in `text`, as UTF-8 byte ranges, by the system's
    /// spelling checker (`View::spellcheck`). None checks nothing.
    fn misspellings(&self, text: &str) -> Vec<std::ops::Range<usize>> {
        let _ = text;
        Vec::new()
    }
    /// The checker's suggestions for misspelled `word`, best first.
    fn spelling_guesses(&self, word: &str) -> Vec<String> {
        let _ = word;
        Vec::new()
    }
    /// Add `word` to the user's dictionary (the menu's Learn Spelling).
    fn learn_spelling(&self, word: &str) {
        let _ = word;
    }
    /// Stop flagging `word` for the rest of the session (Ignore Spelling).
    fn ignore_spelling(&self, word: &str) {
        let _ = word;
    }
    /// Whether the platform looks words up (`look_up`): macOS's dictionary
    /// panel. A context menu offers Look Up where it does.
    fn looks_up(&self) -> bool {
        false
    }
    /// Show the dictionary's entry for `text` over it, as AppKit's Look Up
    /// does: `baseline` is where its first character's baseline starts, in
    /// the window's points, and `size` its font size. Whether it showed.
    fn look_up(&self, text: &str, baseline: (f32, f32), size: f32) -> bool {
        let _ = (text, baseline, size);
        false
    }
    /// Put `text` on the clipboard with `html`, its rich form, where the
    /// platform takes both; plain text alone otherwise.
    fn set_clipboard_rich_text(&self, text: String, html: String) -> bool {
        let _ = html;
        self.set_clipboard_text(text)
    }
    /// The clipboard's image, if it holds one: a screenshot, an image
    /// editor's copy, a browser's Copy Image. Later, as decoding a large one
    /// takes a frame or more: a desktop host reads it off the UI thread.
    /// None reads none.
    fn clipboard_image(&self) -> Pending<Option<crate::image::ImageData>> {
        Box::pin(async { None })
    }
    /// Put `image` on the clipboard in the formats the platform's apps paste
    /// (its transform left out), encoded off the UI thread as reading is;
    /// whether it took it. None takes none.
    fn set_clipboard_image(&self, image: Arc<crate::image::ImageData>) -> Pending<bool> {
        let _ = image;
        Box::pin(async { false })
    }
    /// The files the user picks to open: none if they cancel.
    fn open_files(&self, picker: FilePicker) -> Pending<Result<Vec<PathBuf>, String>>;
    /// Where the user chooses to save: none if they cancel.
    fn save_file(&self, picker: FilePicker) -> Pending<Result<Option<PathBuf>, String>>;
}

/// The platform, as a service components find.
#[derive(Clone)]
pub struct PlatformService(pub Rc<dyn Platform>);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_banner_s_click_reaches_its_listeners_while_they_listen() {
        let heard = Rc::new(std::cell::RefCell::new(Vec::new()));
        let into = heard.clone();
        let listening = on_notification_click(move |id| into.borrow_mut().push(id.to_owned()));
        notification_clicked("chat:a1");
        // A banner without an id is not followed.
        notification_clicked("");
        drop(listening);
        notification_clicked("chat:a2");
        assert_eq!(*heard.borrow(), ["chat:a1"]);
    }
}
