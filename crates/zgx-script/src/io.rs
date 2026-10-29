//! The machine beyond the window, through the host's platform
//! (`zgx::platform`, which a desktop window provides): `ui.clipboard`,
//! file dialogs (`ui.open_files`, `ui.save_file`) and the files the user
//! picked in them (`ui.read_file`, `ui.write_file`), the trackpad's
//! haptics (`ui.haptic`), the system's browser (`ui.open_url`), sounds
//! (`ui.play_sound`) and the desktop's banners (`ui.notify`). A
//! script reaches only
//! files the user chose, as a web page does; reads and writes run off the
//! main thread. A plugin gets none of it unless its host grants it.
use crate::{
    calls::{PromiseUd, pending, settle_with},
    value::Value,
};
use mlua::{Lua, Table};
use std::{
    cell::{Cell, RefCell},
    collections::HashSet,
    path::{Path, PathBuf},
    rc::Rc,
    sync::Arc,
};
use zgx::platform::{FilePicker, Haptic, Notification, PlatformService};

/// The window's platform, once the host's view mounts in one.
pub(crate) type SharedPlatform = Rc<RefCell<Option<PlatformService>>>;
/// The files the user picked in this host's dialogs: the only ones scripts
/// may read or write.
pub(crate) type Picked = Rc<RefCell<HashSet<PathBuf>>>;
/// The haptics scripts asked for (`ui.haptic`), felt or not: what a test
/// reads (`ScriptHost::haptics`), as no headless trackpad taps.
#[derive(Default)]
pub(crate) struct Felt {
    pub(crate) count: Cell<u64>,
    pub(crate) last: Cell<Option<Haptic>>,
}

/// The banners scripts posted with `data` (`ui.notify`) and the scripts'
/// `ui.on_notification` handlers: a click on one of them hands its `data`
/// to the handlers of the script that posted it (the app's, or a
/// plugin's), whichever run of it is loaded now.
pub(crate) struct Banners {
    /// The last banners posted: their id, who posted them and what they
    /// carry.
    posted: RefCell<std::collections::VecDeque<(String, Rc<str>, Value)>>,
    handlers: RefCell<Vec<BannerHandler>>,
    clicks: RefCell<Option<zgx::platform::NotificationClicks>>,
}
/// A script's `ui.on_notification`: who it is, its run and its handler.
type BannerHandler = (Rc<str>, std::rc::Weak<crate::Vm>, mlua::Function);
/// How many posted banners a click can still find.
const BANNERS_KEPT: usize = 64;
impl Banners {
    pub(crate) fn new() -> Rc<Self> {
        let banners = Rc::new(Self {
            posted: RefCell::default(),
            handlers: RefCell::default(),
            clicks: RefCell::default(),
        });
        let weak = Rc::downgrade(&banners);
        let clicks = zgx::platform::on_notification_click(move |id| {
            if let Some(banners) = weak.upgrade() {
                banners.clicked(id);
            }
        });
        *banners.clicks.borrow_mut() = Some(clicks);
        banners
    }
    /// A new banner's id, kept with what a click on it hands back.
    fn post(&self, owner: Rc<str>, data: Value) -> String {
        thread_local! {
            static NEXT: Cell<u64> = const { Cell::new(0) };
        }
        let n = NEXT.with(|next| {
            next.set(next.get() + 1);
            next.get()
        });
        let id = format!("zgx-banner-{}-{n}", std::process::id());
        let mut posted = self.posted.borrow_mut();
        if posted.len() >= BANNERS_KEPT {
            posted.pop_front();
        }
        posted.push_back((id.clone(), owner, data));
        id
    }
    fn clicked(&self, id: &str) {
        let Some((owner, data)) = self
            .posted
            .borrow()
            .iter()
            .find(|(posted, _, _)| posted == id)
            .map(|(_, owner, data)| (owner.clone(), data.clone()))
        else {
            return;
        };
        self.handlers
            .borrow_mut()
            .retain(|(_, vm, _)| vm.strong_count() > 0);
        let handlers: Vec<_> = self
            .handlers
            .borrow()
            .iter()
            .filter(|(own, _, _)| *own == owner)
            .filter_map(|(_, vm, f)| Some((vm.upgrade()?, f.clone())))
            .collect();
        for (vm, handler) in handlers {
            if let Err(error) = vm
                .runtime
                .clone()
                .batch(|| vm.call::<()>(&handler, data.clone()))
            {
                vm.report(error);
            }
        }
    }
}

fn platform(shared: &SharedPlatform, what: &str) -> mlua::Result<PlatformService> {
    shared.borrow().clone().ok_or_else(|| {
        mlua::Error::runtime(format!(
            "{what}: no platform here (the clipboard and file dialogs need a desktop window)"
        ))
    })
}
fn denied(what: &str, capability: &str) -> mlua::Error {
    mlua::Error::runtime(format!(
        "{what}: a plugin does this only if the host grants it \
         (`ScriptHost::grant(plugin, Capability::{capability})`)"
    ))
}

/// `{ path, name }`, as dialogs give files to scripts.
pub(crate) fn file_value(path: &Path) -> Value {
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    Value::Map(
        vec![
            (Rc::from("name"), Value::Str(name.into())),
            (Rc::from("path"), Value::Str(path.to_string_lossy().into())),
        ]
        .into(),
    )
}
/// A dialog's options: `title`, `directory`, `name` (to save as),
/// `filters` (`{ { "Images", { "png", "jpg" } } }`) and `multiple`.
fn picker(opts: Option<Table>, title: &str) -> mlua::Result<FilePicker> {
    let mut picker = FilePicker {
        title: title.into(),
        ..Default::default()
    };
    let Some(opts) = opts else {
        return Ok(picker);
    };
    if let Some(title) = opts.get::<Option<String>>("title")? {
        picker.title = title;
    }
    picker.directory = opts.get::<Option<String>>("directory")?.map(PathBuf::from);
    picker.file_name = opts.get::<Option<String>>("name")?;
    picker.multiple = opts.get::<Option<bool>>("multiple")?.unwrap_or(false);
    if let Some(filters) = opts.get::<Option<Table>>("filters")? {
        for filter in filters.sequence_values::<Table>() {
            let filter = filter?;
            let name: String = filter.get(1)?;
            let extensions: Vec<String> = filter.get(2)?;
            picker.filters.push((name, extensions));
        }
    }
    Ok(picker)
}
/// A file a script names (`{ path }` from a dialog, or its path), if the
/// user picked it.
fn chosen(picked: &Picked, file: &mlua::Value, what: &str) -> mlua::Result<PathBuf> {
    let path = match file {
        mlua::Value::String(path) => path.to_str()?.to_string(),
        mlua::Value::Table(file) => file.get::<String>("path")?,
        other => {
            return Err(mlua::Error::runtime(format!(
                "{what} takes a file from ui.open_files or ui.save_file, not {}",
                other.type_name()
            )));
        }
    };
    let path = PathBuf::from(path);
    if !picked.borrow().contains(&path) {
        return Err(mlua::Error::runtime(format!(
            "{what}: a script reads and writes only files the user picked \
             (ui.open_files, ui.save_file), not {}",
            path.display()
        )));
    }
    Ok(path)
}
/// Run `work` on a thread of its own and settle a promise with what it
/// gives: text, or nil.
fn off_thread(
    lua: &Lua,
    name: String,
    work: impl FnOnce() -> Result<Option<String>, String> + Send + 'static,
) -> mlua::Result<PromiseUd> {
    let (tell, mut heard) = zgx::task::latest::<Result<Option<String>, String>>();
    let promise = pending(lua, name)?;
    std::thread::spawn(move || {
        tell.send(work());
    });
    settle_with(lua, &promise, async move {
        match heard.recv().await {
            Some(Ok(Some(text))) => Ok(Value::Str(text.into())),
            Some(Ok(None)) => Ok(Value::Nil),
            Some(Err(error)) => Err(error),
            None => Err("the file thread stopped".into()),
        }
    })?;
    Ok(PromiseUd(promise))
}

/// A sound a script names, from its directory: a plugin's from its own
/// directory or below.
fn sound_path(dir: Option<&Path>, path: &str, plugin: bool) -> mlua::Result<PathBuf> {
    let given = Path::new(path);
    let Some(dir) = dir.filter(|_| given.is_relative()) else {
        if plugin {
            return Err(mlua::Error::runtime(format!(
                "ui.play_sound: a plugin's sounds come from its directory, not {path}"
            )));
        }
        return Ok(given.to_path_buf());
    };
    if !plugin {
        return Ok(dir.join(given));
    }
    let root = dir.canonicalize().unwrap_or_else(|_| dir.to_path_buf());
    let resolved = crate::normalize(&root.join(given));
    if !crate::within(&root, &resolved) {
        return Err(mlua::Error::runtime(format!(
            "ui.play_sound: a plugin's sounds come from its directory or below, not {path}"
        )));
    }
    Ok(resolved)
}

/// Installs `ui.clipboard` (text and images), `ui.open_files`, `ui.save_file`,
/// `ui.read_file`, `ui.write_file`, `ui.haptic`, `ui.open_url`,
/// `ui.play_sound`, `ui.notify` and `ui.on_notification`. A plugin gets the
/// clipboard, files, the browser, sounds and banners only if its host
/// granted them.
#[allow(clippy::too_many_arguments)]
pub(crate) fn install(
    lua: &Lua,
    ui: &Table,
    shared: SharedPlatform,
    picked: Picked,
    felt: Rc<Felt>,
    banners: Rc<Banners>,
    grants: &crate::Grants,
    dir: Option<PathBuf>,
) -> mlua::Result<()> {
    let clipboard = grants.allows(&crate::Capability::Clipboard);
    let files = grants.allows(&crate::Capability::Files);
    let web = grants.allows(&crate::Capability::Web);
    let notify = grants.allows(&crate::Capability::Notify);
    let plugin = matches!(grants, crate::Grants::Only(_));
    {
        let shared = shared.clone();
        ui.set(
            "play_sound",
            lua.create_function(move |_, path: String| {
                if !notify {
                    return Err(denied("ui.play_sound", "Notify"));
                }
                let path = sound_path(dir.as_deref(), &path, plugin)?;
                // Headless, nothing plays: not an error.
                let platform = shared.borrow().clone();
                Ok(platform.is_some_and(|p| p.0.play_sound(&path)))
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        let banners = banners.clone();
        ui.set(
            "notify",
            lua.create_function(move |lua, opts: Table| {
                if !notify {
                    return Err(denied("ui.notify", "Notify"));
                }
                let mut notification = Notification {
                    title: opts.get::<Option<String>>("title")?.unwrap_or_default(),
                    body: opts.get::<Option<String>>("body")?.unwrap_or_default(),
                    id: String::new(),
                };
                if notification.title.is_empty() && notification.body.is_empty() {
                    return Err(mlua::Error::runtime(
                        "ui.notify takes a `title` or a `body`",
                    ));
                }
                let background = opts.get::<Option<bool>>("background")?.unwrap_or(false);
                // What a click on it hands to `ui.on_notification`.
                let data = opts.get::<Option<Value>>("data")?;
                // Headless, nothing shows: not an error.
                let Some(platform) = shared.borrow().clone() else {
                    return Ok(false);
                };
                // `background`: only while the app is not frontmost.
                if background && platform.0.app_active() {
                    return Ok(false);
                }
                if let Some(data) = data {
                    let owner = crate::node::env(lua)?.owner.clone();
                    notification.id = banners.post(owner, data);
                }
                Ok(platform.0.notify(&notification))
            })?,
        )?;
    }
    {
        ui.set(
            "on_notification",
            lua.create_function(move |lua, handler: mlua::Function| {
                if !notify {
                    return Err(denied("ui.on_notification", "Notify"));
                }
                let env = crate::node::env(lua)?;
                banners
                    .handlers
                    .borrow_mut()
                    .push((env.owner.clone(), env.vm.clone(), handler));
                Ok(())
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        ui.set(
            "open_url",
            lua.create_function(move |_, url: String| {
                if !web {
                    return Err(denied("ui.open_url", "Web"));
                }
                // Web addresses only, and a pane of the system's settings
                // (where a permission is granted): not a file, nor another
                // app's scheme.
                let scheme = url
                    .split_once(':')
                    .map(|(scheme, _)| scheme.to_ascii_lowercase());
                let web_address = match scheme.as_deref() {
                    Some("http" | "https") => url.split_once("://").is_some_and(|(_, rest)| {
                        !rest.is_empty() && !rest.starts_with(['/', '?', '#'])
                    }),
                    Some("mailto") => true,
                    Some("x-apple.systempreferences" | "ms-settings") => url
                        .split_once(':')
                        .is_some_and(|(_, pane)| !pane.is_empty()),
                    _ => false,
                };
                if !web_address || url.chars().any(char::is_control) {
                    return Ok(false);
                }
                // Headless, nothing opens: not an error.
                let platform = shared.borrow().clone();
                Ok(platform.is_some_and(|p| p.0.open_url(&url)))
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        ui.set(
            "haptic",
            lua.create_function(move |_, name: Option<String>| {
                let name = name.as_deref().unwrap_or("level");
                let haptic = Haptic::from_name(name).ok_or_else(|| {
                    mlua::Error::runtime(format!(
                        "ui.haptic takes \"level\", \"alignment\" or \"generic\", not {name:?}"
                    ))
                })?;
                felt.count.set(felt.count.get() + 1);
                felt.last.set(Some(haptic));
                // Headless, or off macOS, nothing taps: not an error.
                let platform = shared.borrow().clone();
                Ok(platform.is_some_and(|p| p.0.haptic(haptic)))
            })?,
        )?;
    }
    let board = lua.create_table()?;
    {
        let shared = shared.clone();
        board.set(
            "read",
            lua.create_function(move |_, ()| {
                if !clipboard {
                    return Err(denied("ui.clipboard.read", "Clipboard"));
                }
                Ok(platform(&shared, "ui.clipboard.read")?.0.clipboard_text())
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        board.set(
            "write",
            lua.create_function(move |_, text: String| {
                if !clipboard {
                    return Err(denied("ui.clipboard.write", "Clipboard"));
                }
                Ok(platform(&shared, "ui.clipboard.write")?
                    .0
                    .set_clipboard_text(text))
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        board.set(
            "read_image",
            // A promise: a large image is decoded off the main thread.
            lua.create_function(move |lua, ()| {
                if !clipboard {
                    return Err(denied("ui.clipboard.read_image", "Clipboard"));
                }
                let reading = platform(&shared, "ui.clipboard.read_image")?
                    .0
                    .clipboard_image();
                let promise = pending(lua, "clipboard.read_image".into())?;
                settle_with(lua, &promise, async move {
                    Ok(reading
                        .await
                        .map_or(Value::Nil, |image| Value::Image(Arc::new(image))))
                })?;
                Ok(PromiseUd(promise))
            })?,
        )?;
    }
    {
        let shared = shared.clone();
        board.set(
            "write_image",
            // A promise too: encoding a large image takes frames. A bitmap,
            // or an image's `src` as `ui.image` takes it (a file decoded off
            // the main thread unless something shows it already).
            lua.create_function(move |lua, image: mlua::Value| {
                if !clipboard {
                    return Err(denied("ui.clipboard.write_image", "Clipboard"));
                }
                let board = platform(&shared, "ui.clipboard.write_image")?;
                let promise = pending(lua, "clipboard.write_image".into())?;
                let pixels = match &image {
                    mlua::Value::UserData(ud) if ud.is::<crate::node::BitmapUd>() => {
                        crate::lower::Pixels::Decoded(
                            ud.borrow::<crate::node::BitmapUd>()?.0.clone(),
                        )
                    }
                    mlua::Value::String(src) => {
                        let src = src.to_str()?.to_string();
                        let env = lua.app_data_ref::<crate::node::Env>().ok_or_else(|| {
                            mlua::Error::runtime("ui.clipboard.write_image: no script")
                        })?;
                        let vm = env.vm.upgrade().ok_or_else(|| {
                            mlua::Error::runtime("ui.clipboard.write_image: the script has ended")
                        })?;
                        crate::lower::pixels(&vm, &env.assets, &src).map_err(|e| {
                            mlua::Error::runtime(format!("ui.clipboard.write_image: {e}"))
                        })?
                    }
                    other => {
                        return Err(mlua::Error::runtime(format!(
                            "ui.clipboard.write_image takes a Bitmap or an image's src, not {}",
                            other.type_name()
                        )));
                    }
                };
                match pixels {
                    crate::lower::Pixels::Decoded(image) => {
                        let writing = board.0.set_clipboard_image(image);
                        settle_with(lua, &promise, async move { Ok(Value::Bool(writing.await)) })?;
                    }
                    crate::lower::Pixels::Encoded(bytes, path) => {
                        let (tell, mut heard) =
                            zgx::task::latest::<Result<Arc<zgx::image::ImageData>, String>>();
                        std::thread::spawn(move || {
                            tell.send(
                                zgx_gpu::assets::decode_image(&bytes)
                                    .map_err(|e| format!("{}: {e}", path.display())),
                            );
                        });
                        settle_with(lua, &promise, async move {
                            let image = heard
                                .recv()
                                .await
                                .unwrap_or_else(|| Err("the decoder stopped".into()))?;
                            Ok(Value::Bool(board.0.set_clipboard_image(image).await))
                        })?;
                    }
                }
                Ok(PromiseUd(promise))
            })?,
        )?;
    }
    board.set_readonly(true);
    ui.set("clipboard", board)?;
    {
        let (shared, picked) = (shared.clone(), picked.clone());
        ui.set(
            "open_files",
            lua.create_function(move |lua, opts: Option<Table>| {
                if !files {
                    return Err(denied("ui.open_files", "Files"));
                }
                let dialog = platform(&shared, "ui.open_files")?
                    .0
                    .open_files(picker(opts, "Open")?);
                let promise = pending(lua, "open_files".into())?;
                let picked = picked.clone();
                settle_with(lua, &promise, async move {
                    let paths = dialog.await?;
                    picked.borrow_mut().extend(paths.iter().cloned());
                    Ok(Value::List(paths.iter().map(|p| file_value(p)).collect()))
                })?;
                Ok(PromiseUd(promise))
            })?,
        )?;
    }
    {
        let (shared, picked) = (shared.clone(), picked.clone());
        ui.set(
            "save_file",
            lua.create_function(move |lua, opts: Option<Table>| {
                if !files {
                    return Err(denied("ui.save_file", "Files"));
                }
                let dialog = platform(&shared, "ui.save_file")?
                    .0
                    .save_file(picker(opts, "Save")?);
                let promise = pending(lua, "save_file".into())?;
                let picked = picked.clone();
                settle_with(lua, &promise, async move {
                    Ok(match dialog.await? {
                        Some(path) => {
                            picked.borrow_mut().insert(path.clone());
                            file_value(&path)
                        }
                        None => Value::Nil,
                    })
                })?;
                Ok(PromiseUd(promise))
            })?,
        )?;
    }
    {
        let picked = picked.clone();
        ui.set(
            "read_file",
            lua.create_function(move |lua, file: mlua::Value| {
                if !files {
                    return Err(denied("ui.read_file", "Files"));
                }
                let path = chosen(&picked, &file, "ui.read_file")?;
                off_thread(lua, format!("read {}", path.display()), move || {
                    std::fs::read(&path)
                        .map(|bytes| Some(String::from_utf8_lossy(&bytes).into_owned()))
                        .map_err(|e| format!("{}: {e}", path.display()))
                })
            })?,
        )?;
    }
    ui.set(
        "write_file",
        lua.create_function(move |lua, (file, text): (mlua::Value, String)| {
            if !files {
                return Err(denied("ui.write_file", "Files"));
            }
            let path = chosen(&picked, &file, "ui.write_file")?;
            off_thread(lua, format!("write {}", path.display()), move || {
                // Beside it, then over it: never half a file.
                let temp = path.with_extension("zgx-write");
                std::fs::write(&temp, text)
                    .and_then(|()| std::fs::rename(&temp, &path))
                    .map(|()| None)
                    .map_err(|e| format!("{}: {e}", path.display()))
            })
        })?,
    )?;
    Ok(())
}
