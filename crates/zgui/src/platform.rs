//! What an app reaches on the machine beyond its window: the clipboard, the
//! file dialogs and the trackpad's haptics. A desktop host provides it to the components it renders
//! (`compose::provide`, as `Context::try_service::<PlatformService>()`);
//! headless runs have none, and tests provide a fake.
use std::{future::Future, path::PathBuf, pin::Pin, rc::Rc};

/// Work a dialog finishes later.
pub type Pending<T> = Pin<Box<dyn Future<Output = T>>>;

/// What a file dialog shows.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FilePicker {
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
    /// Put `text` on the clipboard with `html`, its rich form, where the
    /// platform takes both; plain text alone otherwise.
    fn set_clipboard_rich_text(&self, text: String, html: String) -> bool {
        let _ = html;
        self.set_clipboard_text(text)
    }
    /// The files the user picks to open: none if they cancel.
    fn open_files(&self, picker: FilePicker) -> Pending<Result<Vec<PathBuf>, String>>;
    /// Where the user chooses to save: none if they cancel.
    fn save_file(&self, picker: FilePicker) -> Pending<Result<Option<PathBuf>, String>>;
}

/// The platform, as a service components find.
#[derive(Clone)]
pub struct PlatformService(pub Rc<dyn Platform>);
