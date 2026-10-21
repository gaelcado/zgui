//! Luau scripts that describe zgui interfaces, animated with anime.js's API.
//!
//! A script runs once per (re)load and returns a description of components,
//! state bindings and animations. Rust lowers that description to ordinary
//! retained views: layout, drawing, state and animation all stay in Rust,
//! and the script is called again only for event handlers, components as
//! they mount, and properties the script explicitly computes with a
//! function. Text templates such as `"Count: {count}"` and every animation
//! run without calling the script.
//!
//! State is Rust-owned and keyed, so a hot reload keeps it. Each script gets
//! its own sandboxed VM with a memory limit and a time budget per call, which
//! makes plugins safe to load next to the application script.
//!
//! ```lua
//! local count = ui.state("count", 0)
//! anime.animate(".dot", { y = { 0, -8, 0 }, delay = anime.stagger(40), loop = true })
//! return ui.column {
//!     p = 24, gap = 12, bg = "#172030",
//!     ui.text { "Count: {count}", text_size = 18 },
//!     ui.button { on_click = ui.add(count), px = 16, py = 10, "Increment" },
//! }
//! ```
//!
//! The `ui` and `anime` libraries are documented in `docs/scripting.md`.
mod anim;
mod anime;
mod canvas;
pub mod check;
mod command;
mod element;
mod lower;
mod motion;
mod node;
mod persist;
mod term;
mod theme;
mod timers;
mod transform;
mod value;

pub use command::Command;
pub use persist::app_data_dir;
pub use value::{ElementHandle, PathKey, Store, Value};

use mlua::{Lua, VmState};
use std::{
    cell::{Cell, RefCell},
    collections::HashMap,
    path::PathBuf,
    rc::Rc,
    time::{Duration, Instant, SystemTime},
};
use zgui::{
    compose::{View, prelude::*, switch},
    reactive::{Runtime, Signal},
};

/// Resource limits for each script.
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    /// Heap limit per script VM.
    pub memory: usize,
    /// Budget for evaluating a script on load.
    pub load: Duration,
    /// Budget for one handler or computed property call.
    pub call: Duration,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            memory: 32 << 20,
            load: Duration::from_millis(500),
            call: Duration::from_millis(50),
        }
    }
}

pub(crate) type Actions = Rc<RefCell<HashMap<String, Rc<dyn Fn(Value)>>>>;

/// One script's VM.
/// `.luaurc`'s `aliases` in `dir`, resolved against it.
fn read_aliases(dir: &std::path::Path) -> HashMap<String, PathBuf> {
    let Ok(text) = std::fs::read_to_string(dir.join(".luaurc")) else {
        return HashMap::new();
    };
    let Ok(config) = serde_json::from_str::<serde_json::Value>(&text) else {
        eprintln!("{}: .luaurc is not JSON", dir.display());
        return HashMap::new();
    };
    config
        .get("aliases")
        .and_then(|a| a.as_object())
        .map(|aliases| {
            aliases
                .iter()
                .filter_map(|(name, path)| {
                    Some((name.to_lowercase(), normalize(&dir.join(path.as_str()?))))
                })
                .collect()
        })
        .unwrap_or_default()
}
/// `path` with `.` and `..` resolved in place, without touching the disk.
fn normalize(path: &std::path::Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

/// A script call's time budget. It counts the CPU time the thread spends,
/// so a busy machine does not fail a script that is not looping; the cheap
/// wall clock decides when the CPU time is worth reading.
#[derive(Clone, Copy)]
struct Deadline {
    wall: Instant,
    cpu: Duration,
    budget: Duration,
}
impl Deadline {
    fn start(budget: Duration) -> Self {
        Self {
            wall: Instant::now(),
            cpu: thread_cpu(),
            budget,
        }
    }
    /// The same budget with the time `other` has run since it started
    /// taken off the clock.
    fn shifted(self, other: &Deadline) -> Self {
        Self {
            wall: self.wall + other.wall.elapsed(),
            cpu: self.cpu + thread_cpu().saturating_sub(other.cpu),
            budget: self.budget,
        }
    }
    fn exceeded(&self) -> bool {
        self.wall.elapsed() > self.budget && thread_cpu().saturating_sub(self.cpu) > self.budget
    }
}
/// CPU time this thread has used.
#[cfg(unix)]
fn thread_cpu() -> Duration {
    let mut t = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: `t` is a valid out-pointer for the duration of the call.
    let ok = unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut t) } == 0;
    if ok {
        Duration::new(t.tv_sec as u64, t.tv_nsec as u32)
    } else {
        Duration::ZERO
    }
}
/// Without a thread CPU clock, wall time stands in.
#[cfg(not(unix))]
fn thread_cpu() -> Duration {
    thread_local! { static START: Instant = Instant::now(); }
    START.with(|s| s.elapsed())
}

pub(crate) struct Vm {
    name: String,
    /// Keeps the state alive: script values only hold weak references to it.
    pub(crate) lua: Lua,
    /// Where relative image and SVG paths resolve from.
    pub(crate) base: Option<PathBuf>,
    deadline: Rc<Cell<Option<Deadline>>>,
    budget: Duration,
    pub(crate) runtime: Runtime,
    errors: Signal<Option<String>>,
    /// The script's mounted `layout_id` nodes: ids are scoped per script.
    pub(crate) layout_ids: motion::LayoutIds,
    /// Whether nodes record the script line that creates them (for the
    /// layout inspector): shared with the host, off unless it records.
    pub(crate) locate: Rc<Cell<bool>>,
    /// Calls into the script so far, shared with the host (`script_calls`).
    calls: Rc<Cell<u64>>,
}
impl Vm {
    /// Runs `f` with its own budget. A nested call (a component built
    /// while a handler runs) stops the outer call's clock meanwhile.
    fn guard<R>(&self, budget: Duration, f: impl FnOnce() -> mlua::Result<R>) -> mlua::Result<R> {
        self.calls.set(self.calls.get() + 1);
        let started = Deadline::start(budget);
        let outer = self.deadline.replace(Some(started));
        let result = f();
        self.deadline.set(outer.map(|d| d.shifted(&started)));
        result
    }
    /// Runs Rust work a script asked for (a state write and the interface
    /// it rebuilds) off the script's clock: the budget stops runaway
    /// scripts, not the updates they cause.
    pub(crate) fn off_clock<R>(&self, f: impl FnOnce() -> R) -> R {
        let started = Deadline::start(Duration::ZERO);
        let result = f();
        if let Some(d) = self.deadline.get() {
            self.deadline.set(Some(d.shifted(&started)));
        }
        result
    }
    pub(crate) fn call<R: mlua::FromLuaMulti>(
        &self,
        f: &mlua::Function,
        args: impl mlua::IntoLuaMulti,
    ) -> mlua::Result<R> {
        self.guard(self.budget, || f.call(args))
    }
    pub(crate) fn report(&self, error: mlua::Error) {
        let message = describe(&self.name, &error);
        eprintln!("{message}");
        self.errors.set(Some(message));
    }
}

/// An error with Rust-side frames removed from its traceback.
fn describe(name: &str, error: &mlua::Error) -> String {
    let text = error.to_string();
    let lines: Vec<_> = text
        .lines()
        .filter(|line| line.trim() != "[C]: in ?")
        .collect();
    let lines = match lines.as_slice() {
        [message @ .., last] if *last == "stack traceback:" => message,
        all => all,
    };
    let mut message = format!("{name}: {}", lines.join("\n"));
    // State values are read-only snapshots: say how to change them.
    if text.contains("attempt to modify a readonly table") {
        message.push_str(
            "\n(state values are read-only: change state with state:set_key(key, value), \
             state:patch({ … }), state:update(function(t) … end), state:insert(i, v) \
             or state:set(value))",
        );
    }
    message
}

/// The host's script warnings: each once, in the order they came.
#[derive(Default)]
pub(crate) struct Warnings {
    seen: std::collections::HashSet<String>,
    list: Vec<String>,
}
pub(crate) type SharedWarnings = Rc<RefCell<Warnings>>;
/// Where script warnings go: stderr and the host's list
/// ([`ScriptHost::warnings`]). Everything that warns comes through here, so
/// a host can show them elsewhere too.
pub(crate) fn warning(warnings: Option<&SharedWarnings>, message: String) {
    if let Some(warnings) = warnings {
        let mut w = warnings.borrow_mut();
        if !w.seen.insert(message.clone()) {
            return;
        }
        w.list.push(message.clone());
    }
    eprintln!("warning: {message}");
}
/// A warning about the script code calling into Rust, once per call site
/// (across reloads), with its file and line.
pub(crate) fn warn(lua: &Lua, message: &str) {
    let site = lua
        .inspect_stack(1, |d| {
            let source = d.source().short_src.map(|s| s.into_owned());
            (source, d.current_line())
        })
        .and_then(|(source, line)| Some(format!("{}:{}", source?, line?)));
    let message = match site {
        Some(site) => format!("{site}: {message}"),
        None => message.to_owned(),
    };
    let warnings = lua
        .app_data_ref::<node::Env>()
        .map(|env| env.warnings.clone());
    warning(warnings.as_ref(), message);
}
/// Durations are milliseconds everywhere: warn about one that reads as
/// seconds (fractional and under 10) or that runs over a minute once.
pub(crate) fn check_duration(lua: &Lua, what: &str, ms: f64, looping: bool) {
    if ms > 0. && ms < 10. && ms.fract() != 0. {
        let as_ms = (ms * 1e6).round() / 1e3;
        warn(
            lua,
            &format!(
                "`{what} = {ms}` is milliseconds, under a frame; for {ms} seconds write {as_ms}"
            ),
        );
    } else if !looping && ms > 60_000. {
        warn(
            lua,
            &format!(
                "`{what} = {ms}` is milliseconds: over a minute ({} s)",
                ms / 1000.
            ),
        );
    }
}

/// A script error, split for the banner: where it happened (`app.luau:12`),
/// what happened, and the lines after (the traceback).
#[derive(Debug, PartialEq)]
struct ErrorText {
    location: Option<String>,
    message: String,
    details: Vec<String>,
}
fn split_error(text: &str) -> ErrorText {
    let lines: Vec<&str> = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && *l != "stack traceback:" && !l.starts_with("[C]:"))
        .collect();
    // The headline: the first line naming a script line, else the first.
    let index = lines.iter().position(|l| locate(l).is_some()).unwrap_or(0);
    let headline = lines.get(index).copied().unwrap_or_default();
    let (location, message) = match locate(headline) {
        Some((start, end)) => (
            Some(headline[start..end].to_string()),
            headline[end..].trim_start_matches(':').trim().to_string(),
        ),
        None => (None, headline.to_string()),
    };
    let details = lines
        .iter()
        .enumerate()
        .filter(|(i, _)| *i != index)
        .map(|(_, l)| l.to_string())
        .collect();
    ErrorText {
        location,
        message,
        details,
    }
}
/// The byte range of the first `chunk:12` followed by `:` in `line` (a
/// script's name and line, as Luau reports them: `app.luau:12: …`).
fn locate(line: &str) -> Option<(usize, usize)> {
    let bytes = line.as_bytes();
    let mut search = 0;
    while let Some(found) = line[search..].find(':') {
        let colon = search + found;
        search = colon + 1;
        let digits = bytes[colon + 1..]
            .iter()
            .take_while(|b| b.is_ascii_digit())
            .count();
        if digits == 0 || bytes.get(colon + 1 + digits) != Some(&b':') {
            continue;
        }
        let start = line[..colon]
            .rfind(|c: char| c.is_whitespace() || c == '"' || c == '\'' || c == '[')
            .map_or(0, |i| i + 1);
        let chunk = &line[start..colon];
        if chunk.is_empty() || chunk.bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        return Some((start, colon + 1 + digits));
    }
    None
}

/// The error banner: small and dark over the bottom of the window, the
/// location in monospace, then the message and as much of the traceback
/// as fits; × dismisses it.
fn banner(text: &str, dismiss: impl Fn() + 'static) -> View {
    let parts = split_error(text);
    let mono = |line: String| {
        zgui::compose::text(line)
            .font_family(FontFamily::Monospace)
            .text_size(11.)
    };
    let mut headline = row().w_full().gap(8.).items_start();
    if let Some(location) = parts.location {
        headline = headline.child(
            mono(location)
                .id("script-error-location")
                .text_size(12.)
                .text_color(rgb(0xff8f8f)),
        );
    }
    headline = headline
        .child(
            zgui::compose::text(parts.message)
                .id("script-error")
                .text_size(12.5)
                .text_color(rgb(0xf1f2f5))
                .text_wrap(true)
                .grow()
                .flex_shrink(1.)
                .min_w(0.),
        )
        .child(
            button()
                .id("script-error-dismiss")
                .on_click(dismiss)
                .w(18.)
                .h(18.)
                .rounded(4.)
                .items_center()
                .justify_center()
                .text_color(rgb(0x9aa0ab))
                .hover(|s| s.bg(rgba(0xffffff1a)).text_color(rgb(0xf1f2f5)))
                .child(zgui::compose::text("×").text_size(13.)),
        );
    let details = parts
        .details
        .into_iter()
        .take(8)
        .map(|line| mono(line).text_color(rgb(0x9aa0ab)).truncate());
    column()
        .id("script-error-banner")
        .absolute()
        .left(12.)
        .right(12.)
        .bottom(12.)
        .max_h(200.)
        .overflow_hidden()
        .px(12.)
        .py(9.)
        .gap(3.)
        .rounded(8.)
        .bg(rgb(0x17191e))
        .border(1.)
        .border_color(rgba(0xff6b6b59))
        .child(headline)
        .children(details)
}

enum Script {
    File(PathBuf),
    Inline { name: String, code: String },
}
impl Script {
    /// Shown in errors and tracebacks.
    fn name(&self) -> String {
        match self {
            Script::File(path) => path
                .file_name()
                .unwrap_or(path.as_os_str())
                .to_string_lossy()
                .into_owned(),
            Script::Inline { name, .. } => name.clone(),
        }
    }
    /// The directory a file script is in.
    fn dir(&self) -> Option<PathBuf> {
        match self {
            Script::File(path) => path.parent().map(PathBuf::from),
            Script::Inline { .. } => None,
        }
    }
    /// Keys the script's state across reloads.
    fn key(&self) -> String {
        match self {
            Script::File(path) => path.display().to_string(),
            Script::Inline { name, .. } => format!("inline:{name}"),
        }
    }
    fn code(&self) -> Result<String, String> {
        match self {
            Script::File(path) => {
                std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))
            }
            Script::Inline { code, .. } => Ok(code.clone()),
        }
    }
}

struct Loaded {
    _vms: Vec<Rc<Vm>>,
    root: Rc<node::Node>,
    lowering: Rc<lower::Lowering>,
}

struct Inner {
    runtime: Runtime,
    app: Script,
    plugin_dir: Option<PathBuf>,
    plugins: Vec<Script>,
    limits: Limits,
    stores: RefCell<HashMap<String, Rc<Store>>>,
    shared: Rc<Store>,
    elements: Rc<element::Elements>,
    engine: Rc<anime::Engine>,
    assets: Rc<lower::Assets>,
    actions: Actions,
    current: RefCell<Option<Rc<Loaded>>>,
    generation: Signal<u64>,
    error: Signal<Option<String>>,
    stamps: RefCell<Vec<(PathBuf, Option<SystemTime>)>>,
    /// Files scripts `require`d in the last load: watched with the scripts.
    required: RefCell<Vec<PathBuf>>,
    /// Terminal sessions (`ui.term`): they outlive reloads.
    terms: Rc<term::Terms>,
    /// Web pages by id (`ui.web(id)`): they outlive reloads too.
    webs: Rc<node::Webs>,
    /// App commands (`ui.command`) the last successful load declared.
    commands: Rc<command::Commands>,
    /// State saved across runs (`ui.persist`).
    persist: Rc<persist::Persist>,
    /// `ui.every` and `ui.after`.
    timers: Rc<timers::Timers>,
    /// Script warnings so far.
    warnings: SharedWarnings,
    /// Nodes record where scripts create them (see `Vm::locate`).
    locate: Rc<Cell<bool>>,
    /// Calls into scripts so far (`script_calls`).
    calls: Rc<Cell<u64>>,
    /// The window's layout inspector, from the mounted view's services.
    inspector: Rc<RefCell<Option<zgui::inspect::Inspector>>>,
    /// `inspect(true)` before the view mounted.
    inspect: Cell<bool>,
    /// Asks the view's task to reload, so nodes record their sources.
    relocate: Rc<Notify>,
    /// Type check after reloads (`check_on_reload`, `ZGUI_CHECK`); unset,
    /// a debug build's `watch` turns it on when luau-lsp is installed.
    check: Cell<Option<bool>>,
    /// The check running since the last reload.
    checker: RefCell<Option<check::Background>>,
    type_errors: Signal<Option<String>>,
    /// The theme file error shown, if any (cleared when the file reads).
    theme_error: RefCell<Option<String>>,
}

/// A wake-up for one waiting task: `notify` before or during the wait ends it.
#[derive(Default)]
struct Notify {
    set: Cell<bool>,
    waker: RefCell<Option<std::task::Waker>>,
}
impl Notify {
    fn notify(&self) {
        self.set.set(true);
        if let Some(waker) = self.waker.borrow_mut().take() {
            waker.wake();
        }
    }
    fn wait(self: &Rc<Self>) -> impl std::future::Future<Output = ()> + use<> {
        let this = self.clone();
        std::future::poll_fn(move |cx| {
            if this.set.replace(false) {
                std::task::Poll::Ready(())
            } else {
                *this.waker.borrow_mut() = Some(cx.waker().clone());
                std::task::Poll::Pending
            }
        })
    }
}

/// Whether `ZGUI_INSPECT` or `ZGUI_LAYOUT_WARNINGS` asks for diagnostics.
fn diagnostics_requested() -> bool {
    ["ZGUI_INSPECT", "ZGUI_LAYOUT_WARNINGS"]
        .iter()
        .any(|name| std::env::var_os(name).is_some_and(|v| !v.is_empty() && v != "0"))
}

/// Loads an application script and its plugins and mounts what they describe.
#[derive(Clone)]
pub struct ScriptHost(Rc<Inner>);
/// A script run: its VM, the view it returned and its slot contributions.
type Ran = (
    Rc<Vm>,
    Option<Rc<node::Node>>,
    Vec<(String, Rc<node::Node>)>,
);

impl ScriptHost {
    /// A host for the application script at `path`.
    pub fn new(runtime: &Runtime, path: impl Into<PathBuf>) -> Self {
        Self::with(runtime, Script::File(path.into()))
    }
    /// A host for script source held in memory.
    pub fn inline(runtime: &Runtime, name: impl Into<String>, code: impl Into<String>) -> Self {
        Self::with(
            runtime,
            Script::Inline {
                name: name.into(),
                code: code.into(),
            },
        )
    }
    fn with(runtime: &Runtime, app: Script) -> Self {
        let elements = Rc::new(element::Elements::default());
        let warnings = SharedWarnings::default();
        Self(Rc::new(Inner {
            runtime: runtime.clone(),
            app,
            plugin_dir: None,
            plugins: Vec::new(),
            limits: Limits::default(),
            stores: RefCell::default(),
            elements: elements.clone(),
            engine: {
                let engine = anime::Engine::new(runtime, elements.clone());
                let weak = Rc::downgrade(&engine);
                elements.set_wake(Rc::new(move || {
                    if let Some(engine) = weak.upgrade() {
                        engine.wake();
                    }
                }));
                engine
            },
            assets: Rc::default(),
            shared: Rc::new(Store::new(runtime)),
            actions: Actions::default(),
            current: RefCell::default(),
            generation: runtime.signal(0),
            error: runtime.signal(None),
            stamps: RefCell::default(),
            required: RefCell::default(),
            terms: Rc::default(),
            webs: Rc::default(),
            commands: Rc::new(command::Commands::new(runtime)),
            persist: persist::Persist::new(runtime, warnings.clone()),
            timers: Rc::default(),
            warnings,
            locate: Rc::new(Cell::new(diagnostics_requested())),
            calls: Rc::default(),
            inspector: Rc::default(),
            inspect: Cell::new(false),
            relocate: Rc::default(),
            check: Cell::new(
                std::env::var_os("ZGUI_CHECK")
                    .filter(|v| !v.is_empty())
                    .map(|v| v != "0"),
            ),
            checker: RefCell::default(),
            type_errors: runtime.signal(None),
            theme_error: RefCell::default(),
        }))
    }
    fn configure(self, f: impl FnOnce(&mut Inner)) -> Self {
        let mut inner = Rc::try_unwrap(self.0)
            .unwrap_or_else(|_| panic!("configure a ScriptHost before cloning it"));
        f(&mut inner);
        Self(Rc::new(inner))
    }
    /// Loads every `.luau` file in `dir` as a plugin.
    pub fn plugins(self, dir: impl Into<PathBuf>) -> Self {
        let dir = dir.into();
        self.configure(|inner| inner.plugin_dir = Some(dir))
    }
    /// Adds a plugin from source held in memory.
    pub fn plugin(self, name: impl Into<String>, code: impl Into<String>) -> Self {
        let script = Script::Inline {
            name: name.into(),
            code: code.into(),
        };
        self.configure(|inner| inner.plugins.push(script))
    }
    pub fn limits(self, limits: Limits) -> Self {
        self.configure(|inner| inner.limits = limits)
    }
    /// Names the application: `ui.persist` saves under its data directory
    /// ([`app_data_dir`]), in `script-state`.
    pub fn app_id(self, id: &str) -> Self {
        let dir = app_data_dir(id).map(|dir| dir.join("script-state"));
        self.configure(|inner| inner.persist.set_dir(dir))
    }
    /// Where `ui.persist` saves, instead of the app's data directory. Without
    /// this or [`ScriptHost::app_id`], saved state lasts until the app quits.
    pub fn storage(self, dir: impl Into<PathBuf>) -> Self {
        let dir = dir.into();
        self.configure(|inner| inner.persist.set_dir(Some(dir)))
    }
    /// The directory `ui.persist` saves in, if it has one.
    pub fn storage_dir(&self) -> Option<PathBuf> {
        self.0.persist.dir()
    }
    /// Saves every `ui.persist` change now and waits until it is on disk.
    /// Changes are otherwise saved in batches, 250 ms after the first, off
    /// the main thread, and when the host is dropped.
    pub fn save(&self) {
        self.0.persist.save();
    }

    /// Registers a Rust function scripts can bind with `ui.action(name, arg)`.
    pub fn action(&self, name: impl Into<String>, action: impl Fn(Value) + 'static) {
        self.0
            .actions
            .borrow_mut()
            .insert(name.into(), Rc::new(action));
    }
    /// State shared by the application and every script (`ui.shared`). Rust
    /// can publish model data here and observe what scripts write.
    pub fn shared(&self, key: &str, initial: impl Into<Value>) -> Signal<Value> {
        self.0.shared.state(key, initial.into())
    }
    /// The app commands scripts declare (`ui.command`), in declaration
    /// order, as of the last successful load: show them as menu items.
    pub fn commands(&self) -> Signal<Vec<Command>> {
        self.0.commands.list.clone()
    }
    /// Run the command `id` (a menu item was chosen); whether one ran.
    pub fn run_command(&self, id: &str) -> bool {
        self.0.commands.run(id)
    }
    /// The warnings scripts have caused (a duration that reads as seconds,
    /// a saved value that is not JSON), each once, oldest first. They also
    /// go to stderr.
    pub fn warnings(&self) -> Vec<String> {
        self.0.warnings.borrow().list.clone()
    }
    /// How many times Rust has called into the scripts (a prop, an effect,
    /// a handler, a component built), counting from the host's start: what
    /// a test reads before and after an interaction to check that it runs
    /// no script (a resize the layout engine handles alone).
    pub fn script_calls(&self) -> u64 {
        self.0.calls.get()
    }
    /// The latest load or script error, shown over the interface until fixed.
    pub fn error(&self) -> Signal<Option<String>> {
        self.0.error.clone()
    }
    /// Type errors the last background check found (`check_on_reload`),
    /// shown over the interface while there is no script error.
    pub fn type_errors(&self) -> Signal<Option<String>> {
        self.0.type_errors.clone()
    }
    /// Turns the window's layout inspector on or off (`zgui::inspect`):
    /// boxes outlined, the one under the pointer described with the script
    /// line that created it, and layout warnings. Before the view mounts,
    /// it turns on with it. Ctrl+Option+Cmd+I toggles it in a desktop
    /// window (Ctrl+Alt+Shift+I elsewhere), as `ZGUI_INSPECT=1` does.
    pub fn inspect(&self, on: bool) {
        self.0.inspect.set(on);
        let inspector = self.0.inspector.borrow().clone();
        match inspector {
            Some(inspector) => inspector.set_enabled(on),
            // Record sources from the first load.
            None if on => self.0.locate.set(true),
            None => {}
        }
    }
    /// Type checks the scripts in the background after every reload, as
    /// `zgui check` does, and shows the errors over the interface (with
    /// `watch`, which collects the results). It needs luau-lsp; a check
    /// runs luau-lsp on another thread, about 0.1 s of its CPU for a
    /// twenty-module app. In a debug build `watch` turns it on when
    /// luau-lsp is installed; `ZGUI_CHECK=1` or `0` (or this) decides
    /// instead.
    pub fn check_on_reload(&self, on: bool) {
        self.0.check.set(Some(on));
        if !on {
            *self.0.checker.borrow_mut() = None;
            self.0.type_errors.set(None);
        }
    }
    /// Collects a finished background check (see `check_on_reload`).
    pub fn poll_check(&self) {
        let result = self.0.checker.borrow().as_ref().and_then(|c| c.take());
        let Some(result) = result else {
            return;
        };
        *self.0.checker.borrow_mut() = None;
        let shown = match result {
            Ok(report) if report.errors() == 0 => None,
            Ok(report) => {
                let errors: Vec<String> = report
                    .diagnostics
                    .iter()
                    .filter(|d| d.severity == check::Severity::Error)
                    .map(|d| {
                        let file = d.file.file_name().unwrap_or(d.file.as_os_str());
                        let message = d.message.lines().next().unwrap_or_default();
                        format!(
                            "{}:{}:{}: {message}",
                            file.to_string_lossy(),
                            d.line,
                            d.column
                        )
                    })
                    .collect();
                Some(format!(
                    "type check: {} error{}\n{}",
                    errors.len(),
                    if errors.len() == 1 { "" } else { "s" },
                    errors.join("\n")
                ))
            }
            Err(check::CheckError::NotInstalled) => {
                eprintln!("zgui-script: check_on_reload: {}", check::INSTALL);
                self.0.check.set(Some(false));
                None
            }
            Err(error) => Some(format!("type check: {error}")),
        };
        if let Some(text) = &shown {
            eprintln!("{text}");
        }
        self.0.type_errors.set(shown);
    }
    fn start_check(&self) {
        if self.0.check.get() != Some(true) {
            return;
        }
        let Script::File(app) = &self.0.app else {
            return;
        };
        let mut paths = vec![app.clone()];
        paths.extend(self.0.plugin_dir.iter().filter(|d| d.is_dir()).cloned());
        *self.0.checker.borrow_mut() =
            Some(check::Background::start(paths, check::Options::default()));
    }
    /// Connects the window's inspector: nodes record their sources while
    /// it records, which takes a reload to apply to what is mounted.
    fn attach(&self, inspector: &zgui::inspect::Inspector) {
        let attached = self.0.inspector.borrow().is_some();
        if attached {
            return;
        }
        *self.0.inspector.borrow_mut() = Some(inspector.clone());
        let weak = Rc::downgrade(&self.0);
        inspector.on_recording(move |recording| {
            let Some(inner) = weak.upgrade() else {
                return;
            };
            if recording && !inner.locate.get() {
                inner.locate.set(true);
                inner.relocate.notify();
            } else if !recording {
                inner.locate.set(false);
            }
        });
        if self.0.inspect.get() {
            inspector.set_enabled(true);
        }
        if inspector.recording() && !self.0.locate.get() {
            self.0.locate.set(true);
            self.0.relocate.notify();
        }
    }

    /// Evaluates every script again and remounts the interface. State is kept.
    /// On failure the previous interface stays mounted and the error is shown.
    pub fn reload(&self) -> Result<(), String> {
        self.0.commands.begin();
        let loaded = self.load();
        // After loading: the files it required are watched too.
        *self.0.stamps.borrow_mut() = self.stamps();
        match loaded {
            Ok(loaded) => {
                *self.0.current.borrow_mut() = Some(Rc::new(loaded));
                self.0.commands.publish();
                self.0.runtime.batch(|| {
                    self.0.error.set(None);
                    self.0.generation.update(|g| *g += 1);
                });
                // The replaced scripts' animations end with them.
                self.0.engine.drop_orphans();
                self.start_check();
                Ok(())
            }
            Err(error) => {
                eprintln!("{error}");
                self.0.error.set(Some(error.clone()));
                self.start_check();
                Err(error)
            }
        }
    }
    /// Reloads if any script file, or an image or SVG file it shows,
    /// changed since the last load. Theme files (`ui.theme.load`) that
    /// changed are read again without reloading the scripts: what their new
    /// values change restyles in place.
    pub fn reload_if_changed(&self) -> bool {
        let themes = self.reload_themes();
        // `changed` forgets edited images, so the reload reads them again.
        let assets = self.0.assets.changed();
        if self.stamps() == *self.0.stamps.borrow() && !assets {
            return themes;
        }
        let _ = self.reload();
        true
    }
    /// Read again the theme files that changed; whether any did. An error
    /// shows over the interface until the file reads again.
    fn reload_themes(&self) -> bool {
        match zgui::theme::Themes::of(&self.0.runtime).reload_if_changed() {
            Ok(changed) => {
                if changed
                    && let Some(shown) = self.0.theme_error.take()
                    && self
                        .0
                        .error
                        .with_untracked(|e| e.as_deref() == Some(&*shown))
                {
                    self.0.error.set(None);
                }
                changed
            }
            Err(error) => {
                let message = error.to_string();
                eprintln!("{message}");
                self.0.error.set(Some(message.clone()));
                *self.0.theme_error.borrow_mut() = Some(message);
                true
            }
        }
    }
    /// Polls script files and reloads when they change. Spawn this on the
    /// window's tasks during development; it only stats files. In a debug
    /// build it also turns on type checks after each reload (see
    /// `check_on_reload`) when luau-lsp is installed and nothing chose
    /// otherwise.
    pub fn watch(&self, every: Duration) -> impl std::future::Future<Output = ()> + 'static {
        if self.0.check.get().is_none()
            && cfg!(debug_assertions)
            && check::find_luau_lsp().is_some()
        {
            self.0.check.set(Some(true));
            // The load before this watch is checked too.
            if self.0.current.borrow().is_some() || self.0.error.with_untracked(Option::is_some) {
                self.start_check();
            }
        }
        let host = self.clone();
        async move {
            loop {
                zgui::timer::sleep(every).await;
                host.reload_if_changed();
                host.poll_check();
            }
        }
    }

    /// The mounted interface, with an error banner above it.
    pub fn view(&self) -> View {
        let host = self.0.clone();
        let generation = self.0.generation.clone();
        let app = switch(
            move || generation.get(),
            move |_, _| {
                let current = host.current.borrow().clone();
                current.map_or_else(div, |loaded| lower::lower(&loaded.root, &loaded.lowering))
            },
        );
        let (error, type_errors) = (self.0.error.clone(), self.0.type_errors.clone());
        let (dismiss_error, dismiss_types) = (error.clone(), type_errors.clone());
        let engine = self.0.engine.clone();
        let persist = self.0.persist.clone();
        let timers = self.0.timers.clone();
        let host = self.clone();
        component(move |cx| {
            // One frame loop ticks every animation; it idles at rest.
            if let Some(frames) = cx.try_service::<zgui::frame::FrameClock>() {
                cx.tasks().spawn(engine.run((*frames).clone()));
            }
            // `ui.persist` saves on a timer from here, and `ui.every` runs.
            if cx.try_service::<zgui::compose::TaskRunner>().is_some() {
                persist.set_tasks(cx.tasks());
                timers.set_tasks(cx.tasks());
            }
            if let Some(inspector) = cx.try_service::<zgui::inspect::Inspector>() {
                // When the inspector starts recording, a reload records
                // where every node comes from. The task waits otherwise.
                let (relocate, weak) = (host.0.relocate.clone(), Rc::downgrade(&host.0));
                cx.tasks().spawn(async move {
                    loop {
                        relocate.wait().await;
                        match weak.upgrade() {
                            Some(inner) => {
                                let _ = ScriptHost(inner).reload();
                            }
                            None => return,
                        }
                    }
                });
                host.attach(&inspector);
            }
            // The banner exists only while there is an error: no node, no
            // work otherwise. It is absolute, over the interface and taking
            // none of its room; insets resolve against the window.
            let (error, type_errors) = (error.clone(), type_errors.clone());
            let (dismiss_error, dismiss_types) = (dismiss_error.clone(), dismiss_types.clone());
            overlay()
                .w_full()
                .h_full()
                .child(app.w_full().h_full())
                .child_when(
                    move || error.get().or_else(|| type_errors.get()),
                    move |message, _| {
                        let (error, types) = (dismiss_error.clone(), dismiss_types.clone());
                        banner(&message, move || {
                            error.set(None);
                            types.set(None);
                        })
                    },
                )
        })
    }

    fn scripts(&self) -> Vec<Script> {
        let mut files: Vec<_> = self
            .0
            .plugin_dir
            .as_ref()
            .and_then(|dir| std::fs::read_dir(dir).ok())
            .into_iter()
            .flatten()
            .filter_map(|entry| entry.ok().map(|e| e.path()))
            .filter(|path| path.extension().is_some_and(|ext| ext == "luau"))
            .collect();
        files.sort();
        files.into_iter().map(Script::File).collect()
    }
    fn stamps(&self) -> Vec<(PathBuf, Option<SystemTime>)> {
        let mut paths: Vec<_> = self
            .scripts()
            .into_iter()
            .filter_map(|s| match s {
                Script::File(path) => Some(path),
                Script::Inline { .. } => None,
            })
            .collect();
        if let Script::File(path) = &self.0.app {
            paths.push(path.clone());
        }
        paths.extend(self.0.required.borrow().iter().cloned());
        paths
            .into_iter()
            .map(|path| {
                let modified = std::fs::metadata(&path).and_then(|m| m.modified()).ok();
                (path, modified)
            })
            .collect()
    }

    fn load(&self) -> Result<Loaded, String> {
        self.0.required.borrow_mut().clear();
        let mut vms = Vec::new();
        let mut slots: HashMap<String, Vec<Rc<node::Node>>> = HashMap::new();
        let files = self.scripts();
        for script in self.0.plugins.iter().chain(&files) {
            let (vm, root, contributions) = self.run(script)?;
            if root.is_some() {
                return Err(format!(
                    "{}: a plugin contributes with ui.contribute; it returns nothing",
                    script.name()
                ));
            }
            for (slot, node) in contributions {
                slots.entry(slot).or_default().push(node);
            }
            vms.push(vm);
        }
        let (vm, root, contributions) = self.run(&self.0.app)?;
        for (slot, node) in contributions {
            slots.entry(slot).or_default().push(node);
        }
        vms.push(vm);
        let root = root.ok_or_else(|| {
            format!(
                "{}: the application script must return a ui node",
                self.0.app.name()
            )
        })?;
        Ok(Loaded {
            _vms: vms,
            root,
            lowering: Rc::new(lower::Lowering {
                slots,
                actions: self.0.actions.clone(),
                elements: self.0.elements.clone(),
                runtime: self.0.runtime.clone(),
                assets: self.0.assets.clone(),
                inspector: self.0.inspector.clone(),
            }),
        })
    }

    #[allow(clippy::type_complexity)]
    /// `require(path)`, as Luau resolves it: `"./card"` and `"../ui/card"`
    /// from the requiring file, `"@alias/card"` from the `.luaurc` aliases
    /// beside the script, `"@self/card"` from the requiring file's own
    /// directory, a directory as its `init.luau`; a bare `"card"` from the
    /// script's directory. Modules stay inside the script's directory, run
    /// once and return what they return; a change to one reloads the scripts.
    fn install_require(&self, lua: &Lua, dir: Option<PathBuf>) -> mlua::Result<()> {
        let host = Rc::downgrade(&self.0);
        let modules: Rc<RefCell<HashMap<PathBuf, Option<mlua::Value>>>> = Rc::default();
        let root = dir.map(|d| d.canonicalize().unwrap_or(d));
        let aliases = root.as_deref().map(read_aliases).unwrap_or_default();
        let require = lua.create_function(move |lua, name: String| {
            let Some(root) = &root else {
                return Err(mlua::Error::runtime(
                    "require needs a script loaded from a file",
                ));
            };
            let fail = |why: String| mlua::Error::runtime(format!("require(\"{name}\"): {why}"));
            // The requiring file, from its chunk name (its path in the root).
            let caller = lua
                .inspect_stack(1, |d| d.source().source.map(|s| s.into_owned()))
                .flatten()
                .and_then(|s| s.strip_prefix('@').map(|rel| root.join(rel)));
            let here = caller
                .as_deref()
                .and_then(std::path::Path::parent)
                .unwrap_or(root)
                .to_path_buf();
            let joined = if let Some(rest) = name.strip_prefix("@self") {
                here.join(rest.trim_start_matches('/'))
            } else if let Some(rest) = name.strip_prefix('@') {
                let (alias, rest) = rest.split_once('/').unwrap_or((rest, ""));
                let base = aliases
                    .get(alias)
                    .ok_or_else(|| fail(format!("no alias `@{alias}` in .luaurc")))?;
                base.join(rest)
            } else if name.starts_with("./") || name.starts_with("../") {
                here.join(&name)
            } else {
                root.join(&name)
            };
            let mut path = normalize(&joined);
            if !path.starts_with(root) {
                return Err(fail(
                    "modules come from the script's directory or below".into(),
                ));
            }
            if path.is_dir() {
                path = path.join("init.luau");
            } else if path.extension().is_none() {
                path.set_extension("luau");
            }
            match modules.borrow().get(&path) {
                Some(Some(value)) => return Ok(value.clone()),
                Some(None) => return Err(fail("a require cycle".into())),
                None => {}
            }
            let code = std::fs::read_to_string(&path)
                .map_err(|e| fail(format!("{}: {e}", path.display())))?;
            if let Some(host) = host.upgrade() {
                host.required.borrow_mut().push(path.clone());
            }
            modules.borrow_mut().insert(path.clone(), None);
            // Named by its path in the root: errors show it, and its own
            // requires resolve from it.
            let chunk = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .into_owned();
            let value = match lua
                .load(code)
                .set_name(format!("@{chunk}"))
                .eval::<mlua::Value>()
            {
                Ok(mlua::Value::Nil) => mlua::Value::Boolean(true),
                Ok(value) => value,
                Err(e) => {
                    modules.borrow_mut().remove(&path);
                    return Err(e);
                }
            };
            modules.borrow_mut().insert(path, Some(value.clone()));
            Ok(value)
        })?;
        lua.globals().set("require", require)
    }

    fn run(&self, script: &Script) -> Result<Ran, String> {
        let name = script.name();
        let fail = |error: mlua::Error| describe(&name, &error);
        let code = script.code()?;
        let lua = Lua::new();
        let limits = self.0.limits;
        lua.set_memory_limit(limits.memory).map_err(fail)?;
        let deadline: Rc<Cell<Option<Deadline>>> = Rc::default();
        {
            let deadline = deadline.clone();
            lua.set_interrupt(move |_| match deadline.get() {
                Some(d) if d.exceeded() => {
                    Err(mlua::Error::runtime("script exceeded its time budget"))
                }
                _ => Ok(VmState::Continue),
            });
        }
        let vm = Rc::new(Vm {
            name: name.clone(),
            lua: lua.clone(),
            base: script.dir(),
            deadline,
            budget: limits.call,
            runtime: self.0.runtime.clone(),
            errors: self.0.error.clone(),
            layout_ids: Default::default(),
            locate: self.0.locate.clone(),
            calls: self.0.calls.clone(),
        });
        let store = self
            .0
            .stores
            .borrow_mut()
            .entry(script.key())
            .or_insert_with(|| Rc::new(Store::new(&self.0.runtime)))
            .clone();
        lua.set_app_data(node::Env {
            vm: Rc::downgrade(&vm),
            store,
            shared: self.0.shared.clone(),
            contributions: RefCell::default(),
            engine: self.0.engine.clone(),
            runtime: self.0.runtime.clone(),
            scope: RefCell::default(),
            retained: RefCell::default(),
            actions: self.0.actions.clone(),
            persist: self.0.persist.clone(),
            warnings: self.0.warnings.clone(),
            timers: self.0.timers.clone(),
        });
        node::install(&lua).map_err(fail)?;
        let ui: mlua::Table = lua.globals().get("ui").map_err(fail)?;
        term::install(&lua, &ui, self.0.terms.clone()).map_err(fail)?;
        node::install_web(&lua, &ui, self.0.webs.clone()).map_err(fail)?;
        command::install(&lua, &ui, self.0.commands.clone()).map_err(fail)?;
        theme::install(&lua, &ui, script.dir()).map_err(fail)?;
        ui.set_readonly(true);
        anime::api::install(&lua).map_err(fail)?;
        self.install_require(&lua, script.dir()).map_err(fail)?;
        lua.sandbox(true).map_err(fail)?;
        // Building runs untracked: reading state while describing the tree
        // must not subscribe whatever is currently mounting.
        let result = self.0.runtime.untracked(|| {
            vm.guard(limits.load, || {
                lua.load(code)
                    .set_name(format!("@{name}"))
                    .eval::<mlua::Value>()
            })
        });
        let root = match result.map_err(fail)? {
            mlua::Value::Nil => None,
            mlua::Value::UserData(ud) if ud.is::<node::NodeUd>() => {
                Some(ud.borrow::<node::NodeUd>().map_err(fail)?.0.clone())
            }
            other => {
                return Err(format!(
                    "{name}: a script returns a ui node or nothing, not {}",
                    other.type_name()
                ));
            }
        };
        let contributions = lua
            .app_data_ref::<node::Env>()
            .map(|env| env.contributions.take())
            .unwrap_or_default();
        Ok((vm, root, contributions))
    }
}
