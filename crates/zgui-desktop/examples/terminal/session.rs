//! Shells that outlive the window: a session server, the same binary run
//! with `--session-daemon`, owns every pane's pseudo-terminal and shell.
//! Each pane's Ghostty surface runs this binary with `--attach <id>`, a thin
//! client relaying its terminal to the session `<id>` (made the first time),
//! so closing the window detaches and the next window attaches again.
//!
//! The server keeps each session's screen (and some scrollback) with `vt100`
//! and redraws it for a client that attaches, then streams the shell's
//! output as it comes. It answers what runs in front of a session (the app
//! names panes by it), ends sessions the app closes, and exits once it has
//! had none for a while.
//!
//! Frames on the socket: a kind byte, a little-endian u32 length, the
//! payload. JSON for control; raw bytes for input and output.
use std::{
    collections::HashMap,
    ffi::CString,
    io::{self, Read, Write},
    os::{
        fd::RawFd,
        unix::{
            net::{UnixListener, UnixStream},
            process::CommandExt,
        },
    },
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

const HELLO: u8 = 1;
const INPUT: u8 = 2;
const RESIZE: u8 = 3;
const INFO: u8 = 4;
const KILL: u8 = 5;
const KEEP: u8 = 6;
const OUTPUT: u8 = 10;
const EXIT: u8 = 11;
const REPLY: u8 = 12;

/// Lines of scrollback a session keeps to redraw.
const SCROLLBACK: usize = 2000;
/// How long the server waits with no sessions before it exits.
const IDLE_EXIT: Duration = Duration::from_secs(30);

/// Where the app keeps its state (`ZGUI_TERMINAL_DIR` to keep another, as
/// a second instance or a test does).
pub fn dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("ZGUI_TERMINAL_DIR") {
        return PathBuf::from(dir);
    }
    let home = std::env::var_os("HOME").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from);
    home.join("Library/Application Support/zgui-terminal")
}
fn socket_path() -> PathBuf {
    dir().join("sessions.sock")
}

fn write_frame(w: &mut impl Write, kind: u8, payload: &[u8]) -> io::Result<()> {
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.push(kind);
    frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    frame.extend_from_slice(payload);
    w.write_all(&frame)
}
fn read_frame(r: &mut impl Read) -> io::Result<(u8, Vec<u8>)> {
    let mut head = [0u8; 5];
    r.read_exact(&mut head)?;
    let len = u32::from_le_bytes([head[1], head[2], head[3], head[4]]) as usize;
    if len > 64 << 20 {
        return Err(io::Error::other("frame too large"));
    }
    let mut payload = vec![0u8; len];
    r.read_exact(&mut payload)?;
    Ok((head[0], payload))
}

// The app's side ---------------------------------------------------------------

/// Start the server unless one is listening.
pub fn ensure_daemon() {
    if UnixStream::connect(socket_path()).is_ok() {
        return;
    }
    let Ok(exe) = std::env::current_exe() else {
        return;
    };
    let _ = std::fs::create_dir_all(dir());
    let mut command = std::process::Command::new(exe);
    command
        .arg("--session-daemon")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    // Its own session: no controlling terminal to hang it up with.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    if command.spawn().is_err() {
        return;
    }
    let start = Instant::now();
    while start.elapsed() < Duration::from_secs(3) {
        if UnixStream::connect(socket_path()).is_ok() {
            return;
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn request(kind: u8, body: serde_json::Value) -> Option<serde_json::Value> {
    let mut stream = UnixStream::connect(socket_path()).ok()?;
    stream
        .set_read_timeout(Some(Duration::from_millis(200)))
        .ok()?;
    write_frame(&mut stream, kind, body.to_string().as_bytes()).ok()?;
    let (reply, payload) = read_frame(&mut stream).ok()?;
    (reply == REPLY).then(|| serde_json::from_slice(&payload).ok())?
}

/// End session `id` (its pane closed).
pub fn kill(id: &str) {
    request(KILL, serde_json::json!({ "id": id }));
}
/// End every session but `ids` (the panes a restored layout has).
pub fn keep(ids: &[String]) {
    request(KEEP, serde_json::json!({ "ids": ids }));
}

/// The command a pane's terminal runs to attach to session `id`, starting
/// it in `cwd`.
pub fn attach_command(id: &str, cwd: &str) -> String {
    let exe = std::env::current_exe()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    let quote = |s: &str| format!("'{}'", s.replace('\'', "'\\''"));
    format!(
        "{} --attach {} --cwd {}",
        quote(&exe),
        quote(id),
        quote(cwd)
    )
}

/// Seen through a terminal's attach client (by its pid): what runs in front
/// of its session.
pub fn resolve(pid: u32) -> Option<zgui_desktop::ForegroundProcess> {
    let id = attached_session(pid)?;
    let info = request(INFO, serde_json::json!({ "id": id }))?;
    if !info["exists"].as_bool()? {
        return None;
    }
    Some(zgui_desktop::ForegroundProcess {
        name: info["name"].as_str()?.to_owned(),
        pid: info["pid"].as_u64()? as u32,
        idle: info["idle"].as_bool()?,
    })
}

thread_local! {
    /// Attach clients' sessions by pid (their arguments never change).
    static ATTACHED: std::cell::RefCell<HashMap<u32, Option<String>>> = Default::default();
}
fn attached_session(pid: u32) -> Option<String> {
    ATTACHED.with(|cache| {
        cache
            .borrow_mut()
            .entry(pid)
            .or_insert_with(|| {
                let args = arguments(pid as i32)?;
                let at = args.iter().position(|a| a == "--attach")?;
                args.get(at + 1).cloned()
            })
            .clone()
    })
}

// The attach client --------------------------------------------------------------

/// Relay this terminal to session `id` until it ends (exit with its code)
/// or the terminal goes.
pub fn attach(id: &str, cwd: &str) -> ! {
    ensure_daemon();
    let Ok(mut stream) = UnixStream::connect(socket_path()) else {
        eprintln!("zgui-terminal: no session server");
        std::process::exit(1);
    };
    let (cols, rows) = tty_size();
    let env: Vec<(String, String)> = std::env::vars().collect();
    let hello = serde_json::json!({
        "id": id, "cwd": cwd, "cols": cols, "rows": rows, "env": env,
    });
    if write_frame(&mut stream, HELLO, hello.to_string().as_bytes()).is_err() {
        std::process::exit(1);
    }
    let restore = raw_mode();
    let exit = move |code: i32| -> ! {
        if let Some(termios) = &restore {
            unsafe { libc::tcsetattr(0, libc::TCSANOW, termios) };
        }
        std::process::exit(code)
    };
    // Keystrokes to the session.
    let mut input = stream.try_clone().expect("socket");
    thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            let n = unsafe { libc::read(0, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 || write_frame(&mut input, INPUT, &buf[..n as usize]).is_err() {
                // The terminal went: detach (the session runs on).
                std::process::exit(0);
            }
        }
    });
    // Size changes.
    static RESIZED: AtomicBool = AtomicBool::new(false);
    extern "C" fn on_winch(_: libc::c_int) {
        RESIZED.store(true, Ordering::Relaxed);
    }
    unsafe { libc::signal(libc::SIGWINCH, on_winch as *const () as libc::sighandler_t) };
    let mut sizes = stream.try_clone().expect("socket");
    thread::spawn(move || {
        let mut last = (cols, rows);
        loop {
            thread::sleep(Duration::from_millis(16));
            if RESIZED.swap(false, Ordering::Relaxed) {
                let size = tty_size();
                if size != last {
                    last = size;
                    let mut payload = Vec::with_capacity(4);
                    payload.extend_from_slice(&size.0.to_le_bytes());
                    payload.extend_from_slice(&size.1.to_le_bytes());
                    if write_frame(&mut sizes, RESIZE, &payload).is_err() {
                        return;
                    }
                }
            }
        }
    });
    // The session's output to the terminal.
    let mut stdout = io::stdout().lock();
    loop {
        match read_frame(&mut stream) {
            Ok((OUTPUT, bytes)) => {
                if stdout
                    .write_all(&bytes)
                    .and_then(|()| stdout.flush())
                    .is_err()
                {
                    exit(0);
                }
            }
            Ok((EXIT, code)) => {
                let code = code.first().copied().unwrap_or(0) as i32;
                exit(code);
            }
            Ok(_) => {}
            // Another window took the session, or the server went.
            Err(_) => exit(0),
        }
    }
}

fn tty_size() -> (u16, u16) {
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    if unsafe { libc::ioctl(0, libc::TIOCGWINSZ, &mut size) } == 0 && size.ws_col > 0 {
        (size.ws_col, size.ws_row)
    } else {
        (80, 24)
    }
}
fn raw_mode() -> Option<libc::termios> {
    unsafe {
        let mut termios: libc::termios = std::mem::zeroed();
        if libc::tcgetattr(0, &mut termios) != 0 {
            return None;
        }
        let saved = termios;
        libc::cfmakeraw(&mut termios);
        libc::tcsetattr(0, libc::TCSANOW, &termios);
        Some(saved)
    }
}

// The server -----------------------------------------------------------------------

/// What the screen copy also keeps: the title and directory the shell last
/// set, to tell a terminal that attaches.
#[derive(Default)]
struct Recorder {
    title: Option<Vec<u8>>,
    pwd: Option<Vec<u8>>,
}
impl vt100::Callbacks for Recorder {
    fn set_window_title(&mut self, _: &mut vt100::Screen, title: &[u8]) {
        self.title = Some(title.to_vec());
    }
    fn unhandled_osc(&mut self, _: &mut vt100::Screen, params: &[&[u8]]) {
        if params.first() == Some(&&b"7"[..]) {
            self.pwd = Some(params[1..].join(&b';'));
        }
    }
}

/// A session: its pseudo-terminal and shell, fixed for its life, and what
/// changes, under a lock of its own (writing to a slow terminal holds it,
/// never the server's).
struct Session {
    master: RawFd,
    child: libc::pid_t,
    live: Mutex<Live>,
}
struct Live {
    screen: vt100::Parser<Recorder>,
    client: Option<(u64, UnixStream)>,
}
#[derive(Default)]
struct Server {
    sessions: HashMap<String, Arc<Session>>,
    empty_since: Option<Instant>,
}
type Shared = Arc<Mutex<Server>>;
static TOKENS: AtomicU64 = AtomicU64::new(1);

/// Run the server: one per user, until it has had no sessions for a while.
pub fn daemon() -> ! {
    let _ = std::fs::create_dir_all(dir());
    let path = socket_path();
    if UnixStream::connect(&path).is_ok() {
        // One is running.
        std::process::exit(0);
    }
    let _ = std::fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        std::process::exit(1);
    };
    unsafe { libc::signal(libc::SIGPIPE, libc::SIG_IGN) };
    let server: Shared = Arc::new(Mutex::new(Server {
        empty_since: Some(Instant::now()),
        ..Default::default()
    }));
    // Leave once there has been nothing to keep for a while.
    {
        let server = server.clone();
        let path = path.clone();
        thread::spawn(move || {
            loop {
                thread::sleep(Duration::from_secs(1));
                let server = server.lock().unwrap();
                if server
                    .empty_since
                    .is_some_and(|since| since.elapsed() > IDLE_EXIT)
                {
                    let _ = std::fs::remove_file(&path);
                    std::process::exit(0);
                }
            }
        });
    }
    for stream in listener.incoming().flatten() {
        let server = server.clone();
        thread::spawn(move || serve(stream, server));
    }
    std::process::exit(0)
}

fn session(server: &Shared, id: &str) -> Option<Arc<Session>> {
    server.lock().unwrap().sessions.get(id).cloned()
}

fn serve(mut stream: UnixStream, server: Shared) {
    let Ok((kind, payload)) = read_frame(&mut stream) else {
        return;
    };
    let body: serde_json::Value = serde_json::from_slice(&payload).unwrap_or_default();
    let id = body["id"].as_str().unwrap_or_default().to_owned();
    match kind {
        HELLO => attach_client(stream, server, &id, &body),
        INFO => {
            let reply = match session(&server, &id) {
                Some(session) => {
                    let front = unsafe { libc::tcgetpgrp(session.master) };
                    let pid = if front > 0 { front } else { session.child };
                    serde_json::json!({
                        "exists": true,
                        "pid": pid,
                        "name": process_name(pid),
                        "idle": pid == session.child,
                    })
                }
                None => serde_json::json!({ "exists": false }),
            };
            let _ = write_frame(&mut stream, REPLY, reply.to_string().as_bytes());
        }
        KILL => {
            end(&server, |session_id| session_id == id);
            let _ = write_frame(&mut stream, REPLY, b"{}");
        }
        KEEP => {
            let keep: Vec<String> = body["ids"]
                .as_array()
                .map(|ids| {
                    ids.iter()
                        .filter_map(|id| id.as_str().map(str::to_owned))
                        .collect()
                })
                .unwrap_or_default();
            end(&server, |session_id| !keep.iter().any(|k| k == session_id));
            let _ = write_frame(&mut stream, REPLY, b"{}");
        }
        _ => {}
    }
}

/// Hang up the shells of the sessions `which` picks (their reader threads
/// tidy up when they exit).
fn end(server: &Shared, which: impl Fn(&str) -> bool) {
    let server = server.lock().unwrap();
    for (id, session) in &server.sessions {
        if which(id) {
            let child = session.child;
            unsafe { libc::killpg(child, libc::SIGHUP) };
            thread::spawn(move || {
                thread::sleep(Duration::from_secs(2));
                unsafe { libc::killpg(child, libc::SIGKILL) };
            });
        }
    }
}

fn attach_client(mut stream: UnixStream, server: Shared, id: &str, hello: &serde_json::Value) {
    let cols = hello["cols"].as_u64().unwrap_or(80).clamp(1, 1000) as u16;
    let rows = hello["rows"].as_u64().unwrap_or(24).clamp(1, 1000) as u16;
    let token = TOKENS.fetch_add(1, Ordering::Relaxed);
    let session = {
        let mut guard = server.lock().unwrap();
        match guard.sessions.get(id) {
            Some(session) => session.clone(),
            None => {
                let Some(session) = spawn(hello, cols, rows) else {
                    let _ = write_frame(&mut stream, EXIT, &[127]);
                    return;
                };
                let session = Arc::new(session);
                guard.sessions.insert(id.to_owned(), session.clone());
                guard.empty_since = None;
                let (server, id, reading) = (server.clone(), id.to_owned(), session.clone());
                thread::spawn(move || read_session(server, id, reading));
                session
            }
        }
    };
    {
        let mut live = session.live.lock().unwrap();
        resize(&session, &mut live, cols, rows);
        let replay = replay(&mut live.screen);
        if write_frame(&mut stream, OUTPUT, &replay).is_err() {
            return;
        }
        // The last terminal to attach has it; an earlier one is let go.
        if let Some((_, old)) = live.client.take() {
            let _ = old.shutdown(std::net::Shutdown::Both);
        }
        live.client = stream.try_clone().ok().map(|s| (token, s));
    }
    loop {
        match read_frame(&mut stream) {
            Ok((INPUT, bytes)) => write_all(session.master, &bytes),
            Ok((RESIZE, size)) if size.len() == 4 => {
                let cols = u16::from_le_bytes([size[0], size[1]]);
                let rows = u16::from_le_bytes([size[2], size[3]]);
                let mut live = session.live.lock().unwrap();
                resize(&session, &mut live, cols, rows);
            }
            Ok(_) => {}
            Err(_) => break,
        }
    }
    // Detached: the shell runs on.
    let mut live = session.live.lock().unwrap();
    if live.client.as_ref().is_some_and(|(t, _)| *t == token) {
        live.client = None;
    }
}

fn resize(session: &Session, live: &mut Live, cols: u16, rows: u16) {
    if live.screen.screen().size() == (rows, cols) {
        return;
    }
    live.screen.screen_mut().set_size(rows, cols);
    let size = libc::winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    unsafe { libc::ioctl(session.master, libc::TIOCSWINSZ, &size) };
}

/// What redraws a session for a terminal that attaches: its scrollback
/// (scrolled up out of view), then its screen, modes, title and directory.
fn replay(screen: &mut vt100::Parser<Recorder>) -> Vec<u8> {
    let mut out = b"\x1b[0m\x1b[H\x1b[2J".to_vec();
    let s = screen.screen_mut();
    if !s.alternate_screen() {
        s.set_scrollback(usize::MAX);
        let depth = s.scrollback();
        let (rows, cols) = s.size();
        for offset in (1..=depth).rev() {
            s.set_scrollback(offset);
            if let Some(row) = s.rows_formatted(0, cols).next() {
                out.extend_from_slice(&row);
            }
            out.extend_from_slice(b"\x1b[0m\r\n");
        }
        s.set_scrollback(0);
        if depth > 0 {
            // Push it all above the screen.
            for _ in 0..rows {
                out.extend_from_slice(b"\r\n");
            }
        }
    }
    out.extend_from_slice(&screen.screen().state_formatted());
    let recorded = screen.callbacks();
    if let Some(title) = &recorded.title {
        out.extend_from_slice(b"\x1b]2;");
        out.extend_from_slice(title);
        out.extend_from_slice(b"\x07");
    }
    if let Some(pwd) = &recorded.pwd {
        out.extend_from_slice(b"\x1b]7;");
        out.extend_from_slice(pwd);
        out.extend_from_slice(b"\x07");
    }
    out
}

/// The shell's output: into the screen copy and to the attached terminal.
/// When it exits, the session ends and its terminal is told the code.
fn read_session(server: Shared, id: String, session: Arc<Session>) {
    let mut buf = vec![0u8; 65536];
    loop {
        let n = unsafe { libc::read(session.master, buf.as_mut_ptr().cast(), buf.len()) };
        if n <= 0 {
            break;
        }
        let bytes = &buf[..n as usize];
        let mut live = session.live.lock().unwrap();
        live.screen.process(bytes);
        if let Some((_, client)) = &mut live.client
            && write_frame(client, OUTPUT, bytes).is_err()
        {
            live.client = None;
        }
    }
    let mut status = 0;
    unsafe { libc::waitpid(session.child, &mut status, 0) };
    let code = if libc::WIFEXITED(status) {
        libc::WEXITSTATUS(status)
    } else {
        1
    };
    {
        let mut guard = server.lock().unwrap();
        guard.sessions.remove(&id);
        if guard.sessions.is_empty() {
            guard.empty_since = Some(Instant::now());
        }
    }
    let mut live = session.live.lock().unwrap();
    if let Some((_, client)) = &mut live.client {
        let _ = write_frame(client, EXIT, &[code as u8]);
    }
    unsafe { libc::close(session.master) };
}

fn write_all(fd: RawFd, mut bytes: &[u8]) {
    while !bytes.is_empty() {
        let n = unsafe { libc::write(fd, bytes.as_ptr().cast(), bytes.len()) };
        if n <= 0 {
            return;
        }
        bytes = &bytes[n as usize..];
    }
}

/// A login shell on a new pseudo-terminal, in the terminal's environment
/// (Ghostty's TERM and shell integration included).
fn spawn(hello: &serde_json::Value, cols: u16, rows: u16) -> Option<Session> {
    let mut env: Vec<(String, String)> = hello["env"]
        .as_array()
        .map(|pairs| {
            pairs
                .iter()
                .filter_map(|pair| {
                    Some((
                        pair.get(0)?.as_str()?.to_owned(),
                        pair.get(1)?.as_str()?.to_owned(),
                    ))
                })
                .collect()
        })
        .unwrap_or_default();
    let var = |env: &[(String, String)], key: &str| {
        env.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone())
    };
    let shell = var(&env, "SHELL").unwrap_or_else(|| "/bin/zsh".into());
    let name = shell.rsplit('/').next().unwrap_or("zsh").to_owned();
    // Ghostty's zsh integration (prompt marks, the directory, titles), as it
    // sets it up for a zsh of its own.
    if name == "zsh"
        && let Some(resources) = var(&env, "GHOSTTY_RESOURCES_DIR")
    {
        if let Some(zdotdir) = var(&env, "ZDOTDIR") {
            env.push(("GHOSTTY_ZSH_ZDOTDIR".into(), zdotdir));
        }
        env.retain(|(k, _)| k != "ZDOTDIR");
        env.push((
            "ZDOTDIR".into(),
            format!("{resources}/shell-integration/zsh"),
        ));
    }
    let cwd = hello["cwd"].as_str().unwrap_or_default();
    let cwd = CString::new(if cwd.is_empty() { "/" } else { cwd }).ok()?;
    let path = CString::new(shell.clone()).ok()?;
    let argv0 = CString::new(format!("-{name}")).ok()?;
    let argv = [argv0.as_ptr(), std::ptr::null()];
    let envs: Vec<CString> = env
        .iter()
        .filter_map(|(k, v)| CString::new(format!("{k}={v}")).ok())
        .collect();
    let mut envp: Vec<*const libc::c_char> = envs.iter().map(|e| e.as_ptr()).collect();
    envp.push(std::ptr::null());
    let size = libc::winsize {
        ws_row: rows,
        ws_col: cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let mut master: libc::c_int = -1;
    let child = unsafe {
        libc::forkpty(
            &mut master,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &size as *const _ as *mut _,
        )
    };
    if child < 0 {
        return None;
    }
    if child == 0 {
        // The child: only async-signal-safe calls until exec.
        unsafe {
            libc::chdir(cwd.as_ptr());
            libc::execve(path.as_ptr(), argv.as_ptr(), envp.as_ptr());
            libc::_exit(127);
        }
    }
    Some(Session {
        master,
        child,
        live: Mutex::new(Live {
            screen: vt100::Parser::new_with_callbacks(rows, cols, SCROLLBACK, Recorder::default()),
            client: None,
        }),
    })
}

// Processes ----------------------------------------------------------------------

/// A process's name as it presents itself: its `argv[0]` (Claude Code sets
/// its own), else its executable's.
fn process_name(pid: libc::pid_t) -> String {
    arguments(pid)
        .and_then(|args| args.into_iter().next())
        .or_else(|| {
            let mut buffer = [0u8; 256];
            let len =
                unsafe { libc::proc_name(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
            (len > 0).then(|| String::from_utf8_lossy(&buffer[..len as usize]).into_owned())
        })
        .map(|name| {
            let first = name.split(' ').next().unwrap_or(&name).to_owned();
            let base = first.rsplit('/').next().unwrap_or(&first).to_owned();
            base.strip_prefix('-').map(str::to_owned).unwrap_or(base)
        })
        .unwrap_or_default()
}

/// A process's arguments (`KERN_PROCARGS2`).
fn arguments(pid: libc::pid_t) -> Option<Vec<String>> {
    let mut mib = [libc::CTL_KERN, libc::KERN_PROCARGS2, pid];
    let mut size: libc::size_t = 0;
    unsafe {
        if libc::sysctl(
            mib.as_mut_ptr(),
            3,
            std::ptr::null_mut(),
            &mut size,
            std::ptr::null_mut(),
            0,
        ) != 0
        {
            return None;
        }
        let mut buffer = vec![0u8; size];
        if libc::sysctl(
            mib.as_mut_ptr(),
            3,
            buffer.as_mut_ptr().cast(),
            &mut size,
            std::ptr::null_mut(),
            0,
        ) != 0
        {
            return None;
        }
        buffer.truncate(size);
        let argc = i32::from_ne_bytes(buffer.get(..4)?.try_into().ok()?) as usize;
        let rest = buffer.get(4..)?;
        // The executable's path, NUL padding, then argv.
        let exe_end = rest.iter().position(|b| *b == 0)?;
        let after = &rest[exe_end..];
        let start = after.iter().position(|b| *b != 0)?;
        let args = after[start..]
            .split(|b| *b == 0)
            .take(argc)
            .map(|a| String::from_utf8_lossy(a).into_owned())
            .collect();
        Some(args)
    }
}
