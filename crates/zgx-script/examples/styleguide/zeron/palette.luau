-- ⌘K's content: the commands (each running what the app's key runs), the
-- threads and the files it lists; the kit draws it (kit/command_palette).
-- Zeron's own commands come first, its Quick Actions (commands_for).
local command_palette = require("@kit/command_palette")
local data = require("./data")
local state = require("./state")
local sidebar = require("./sidebar")
local keys = require("./keys")

local M = {}

type Row = command_palette.Row

-- The commands, with their shortcuts. `act` runs what the app's keys run,
-- so a command and its key never drift apart.
local commands: { Row } = {}
local function command(
	id: string,
	label: string,
	icon: string,
	keys: { string }?,
	run: () -> (),
	quick: boolean?,
	shown: (() -> boolean)?
)
	table.insert(commands, {
		id = id,
		section = "Commands",
		label = label,
		icon = icon,
		keys = keys,
		run = run,
		quick = quick,
		shown = shown,
	})
end

-- What the app wires: the actions its keys take (app_zeron.luau), and
-- whether the session on show can be archived.
M.act = {} :: { [string]: () -> () }
M.can_archive = function(): boolean
	return false
end
local function act(name: string): () -> ()
	return function()
		local f = M.act[name]
		if f then
			f()
		end
	end
end

local function dark(): boolean
	return require("@kit/look").is_dark()
end
command("new_chat", "New chat", "pen-new-square", keys.caps("new_session"), act("new_chat"), true)
command("new_project", "New project", "folder", keys.caps("new_project"), function()
	require("./projects").start()
end, true)
command("settings", "Open settings", "settings", { "⌘", "," }, function()
	state.settings:set(true)
end, true)
command("theme_light", "Switch to light theme", "sun", nil, function()
	state.look.mode:set("light")
end, true, dark)
command(
	"theme_dark",
	"Switch to dark theme",
	"moon",
	nil,
	function()
		state.look.mode:set("dark")
	end,
	true,
	function()
		return not dark()
	end
)
command(
	"archive_thread",
	"Archive thread",
	"archive-minimalistic",
	keys.caps("archive_session"),
	act("archive_thread"),
	true,
	function()
		return M.can_archive()
	end
)
command("new_tab", "New space", "add-circle", { "⌘", "T" }, act("new_tab"))
command("split_right", "Split right", "split-columns", { "⌘", "D" }, act("split_right"))
command("split_down", "Split down", "split-columns", { "⌘", "⇧", "D" }, act("split_down"))
command("close", "Close pane or space", "close", { "⌘", "W" }, act("close"))
command("sidebar", "Toggle sidebar", "list", keys.caps("toggle_sidebar"), act("sidebar"))
command("files", "Toggle Files", "folder-tree", keys.caps("toggle_files"), act("files"))
command("terminal", "Open a terminal", "terminal", nil, function()
	state.open_tab("terminal")
end)
command("terminal_dock", "Toggle terminal", "terminal", { "⌘", "J" }, act("terminal_dock"))
command("browser", "Open a browser", "globe", nil, function()
	state.open_tab("preview")
end)
command("notes", "Open notes", "pen", nil, function()
	state.open_tab("notes")
end)
command("side_chat", "New side chat", "chat-round-line", nil, function()
	state.new_side_chat()
end)
command("fork_chat", "Fork chat", "fork", nil, function()
	state.fork_chat()
end)
command("prs", "Pull requests", "pull-request", nil, function()
	state.open_session("prs")
end)
for _, l in state.LAYOUTS do
	command(`layout_{l.id}`, `Layout: {l.label}`, "widget", nil, function()
		state.layout:set(l.id :: any)
	end)
end
command("appearance_light", "Appearance: Light", "sun", nil, function()
	state.look.mode:set("light")
end)
command("appearance_dark", "Appearance: Dark", "moon", nil, function()
	state.look.mode:set("dark")
end)
command("appearance_system", "Appearance: Match the system", "monitor", nil, function()
	state.look.mode:set("system")
end)
command("check_updates", "Check for updates", "refresh", nil, function()
	require("./account").check_for_updates()
end)
-- The sample engine's connection, until one is wired: the sidebar's
-- changes then say why they cannot go.
command("engine_offline", "Sample engine: Go offline", "wifi-off", nil, function()
	require("./account").sample_connection("offline")
end)
command("engine_syncing", "Sample engine: Sync", "cloud", nil, function()
	require("./account").sample_connection("syncing")
end)
command("engine_connected", "Sample engine: Reconnect", "refresh", nil, function()
	require("./account").sample_connection("connected")
end)
-- Out of reach (the gate and its Retry), and the next sync step failing
-- (the switch, an import, closing the workspace on sign-out).
command("engine_unreachable", "Sample engine: Become unreachable", "wifi-off", nil, function()
	require("./sync").fail_connection()
end)
command("engine_fail_next", "Sample engine: Fail the next step", "danger-triangle", nil, function()
	require("./sync").fail_next:set(true)
end)
-- How this copy was installed, and the next update check failing.
command("engine_install_desktop", "Sample engine: Installed as the app", "monitor", nil, function()
	require("./account").sample_install("desktop")
end)
command("engine_install_managed", "Sample engine: Installed by the CLI", "terminal", nil, function()
	require("./account").sample_install("managed")
end)
command("engine_install_source", "Sample engine: Built from source", "file-code", nil, function()
	require("./account").sample_install("source")
end)
command("engine_fail_check", "Sample engine: Fail the next update check", "danger-triangle", nil, function()
	require("./account").sample_fail_check()
end)
-- A background session's run, for the chimes and banners (zeron/notify).
command("engine_run_done", "Sample engine: Finish a run", "check", nil, function()
	require("./notify").sample("done")
end)
command("engine_run_input", "Sample engine: Ask for input", "chat-round-line", nil, function()
	require("./notify").sample("input")
end)
command("engine_run_failed", "Sample engine: Fail a run", "danger-triangle", nil, function()
	require("./notify").sample("failed")
end)
-- And its failures, as the composer reports them.
command("engine_fail_send", "Sample engine: Fail the next send", "danger-triangle", nil, function()
	require("./conversation").fail_next("send")
end)
command("engine_fail_stop", "Sample engine: Fail the next stop", "danger-triangle", nil, function()
	require("./conversation").fail_next("stop")
end)
command("engine_fail_upload", "Sample engine: Fail the next upload", "danger-triangle", nil, function()
	require("./conversation").fail_next("upload")
end)
-- And Settings' states (zeron/settings).
command("engine_fail_settings", "Sample engine: Fail the next settings step", "danger-triangle", nil, function()
	require("./settings").sample.fail_next()
end)
command("engine_unplug", "Sample engine: Unplug the USB microphone and the Build box", "microphone-off", nil, function()
	require("./settings").sample.unplug()
end)
command("engine_sign_out_login", "Sample engine: Sign out a Claude login", "key-minimalistic", nil, function()
	require("./settings").sample.sign_out_login()
end)
command("engine_revoke", "Sample engine: Revoke capture permissions", "danger-triangle", nil, function()
	require("./settings").sample.revoke()
end)
command("engine_lose_background", "Sample engine: Lose the background image", "gallery", nil, function()
	require("./settings").sample.lose_background()
end)
command("engine_onboarding", "Sample engine: Sign out to onboarding", "logout-2", nil, function()
	state.settings:set(false)
	require("./onboarding").start()
end)
-- Cloud and billing (Settings → Cloud and Billing, and Cloud's machines
-- elsewhere), and first-run setup.
local function cloud(kind: string): () -> ()
	return function()
		require("./cloud").sample(kind)
	end
end
local function billing(kind: string): () -> ()
	return function()
		require("./billing").sample(kind)
	end
end
command("cloud_offer", "Sample engine: Offer Cloud, or stop offering it", "cloud", nil, cloud("offer"))
command("cloud_off", "Sample engine: Turn Cloud off", "cloud", nil, cloud("off"))
command("cloud_unreachable", "Sample engine: Lose Cloud's status", "wifi-off", nil, cloud("unreachable"))
command("cloud_fail_next", "Sample engine: Make Cloud's next step fail", "danger-triangle", nil, function()
	require("./billing").fail_next:set(true)
end)
command("cloud_reconnect", "Sample engine: GitHub needs reconnecting", "github-mark", nil, cloud("reconnect"))
command("cloud_asleep", "Sample engine: Put the Cloud machine to sleep", "cloud", nil, cloud("asleep"))
command("cloud_new", "Sample engine: Give the Cloud session a new machine", "cloud", nil, cloud("new"))
command("billing_none", "Sample engine: Billing without a plan", "wallet", nil, billing("none"))
command("billing_past_due", "Sample engine: Billing with a failed payment", "wallet", nil, billing("past_due"))
command("billing_ends", "Sample engine: Billing with a plan ending", "wallet", nil, billing("ends"))
command("billing_empty", "Sample engine: Run out of Cloud credits", "wallet", nil, billing("empty"))
command("billing_unavailable", "Sample engine: Billing not set up on the server", "wallet", nil, billing("unavailable"))
command("billing_reset", "Sample engine: Billing as it was", "wallet", nil, billing("sample"))
command("setup_start", "Sample engine: First-run setup", "zeron-logo", nil, function()
	require("./onboarding").begin()
end)
command("setup_fresh", "Sample engine: First-run setup on a fresh install", "zeron-logo", nil, function()
	require("./onboarding").begin(true)
end)
command("setup_no_agents", "Sample engine: No agents on this Mac", "bot", nil, function()
	require("./onboarding").sample_no_agents()
end)
-- And dictation's outcomes, as the status under the composer says them.
command("engine_no_speech", "Sample engine: Hear no speech next", "microphone", nil, function()
	require("./conversation").fail_dictation("no_speech")
end)
command("engine_deny_mic", "Sample engine: Refuse the microphone", "microphone", nil, function()
	require("./conversation").fail_dictation("denied")
end)
command("engine_fail_dictation", "Sample engine: Stop the next dictation", "danger-triangle", nil, function()
	require("./conversation").fail_dictation("failed")
end)

-- Each thread with what search weighs (thread_search.rs): its title,
-- project, branch, device and pull request.
local threads: { Row } = {}
-- Each session's row, by its key.
local thread_of: { [string]: string } = {}
for _, s in sidebar.sessions() do
	thread_of[s.key] = s.row
	local h = data.HARNESS[s.harness]
	local fields = {
		{ text = s.title, weight = 100 },
		{ text = s.project, weight = 40 },
	}
	if s.branch then
		table.insert(fields, { text = s.branch, weight = 30 })
	end
	if s.device then
		table.insert(fields, { text = s.device, weight = 20 })
	end
	if s.pr then
		table.insert(fields, { text = `#{s.pr.number} {s.title} {s.branch or ""}`, weight = 20 })
	end
	table.insert(threads, {
		id = s.row,
		section = "Threads",
		label = s.title,
		detail = if s.remote then `{s.project} @ {s.device} · {s.ago}` else `{s.project} · {s.ago}`,
		icon = h.icon,
		tint = h.tint,
		fields = fields,
		archived = s.archived,
		recency = s.updated,
		run = function()
			state.open_session(s.key)
		end,
	})
end

-- A workspace file's row: its name, its folder; it opens the file.
local function file_row(path: string): Row
	return {
		id = `file_{string.gsub(path, "[^%w]", "_")}`,
		section = "Files",
		label = string.match(path, "([^/]+)$") or path,
		detail = string.match(path, "^(.*)/[^/]+$"),
		icon = "document",
		file = path,
		run = function()
			require("./files").open(path)
		end,
	}
end

-- The workspace's files as they are now.
local function files(): { Row }
	local out: { Row } = {}
	for _, n in require("./files").paths:get() do
		if not n.folder and n.git ~= "deleted" then
			table.insert(out, file_row(n.path))
		end
	end
	return out
end

-- With nothing typed: the files opened in this session, the latest first,
-- then the workspace's changed ones (the host's recently changed), each once.
local function recent_files(): { Row }
	local workspace = require("./files")
	local out: { Row } = {}
	local seen: { [string]: boolean } = {}
	local function add(path: string)
		if not seen[path] then
			seen[path] = true
			table.insert(out, file_row(path))
		end
	end
	for _, path in workspace.recent(state.session:get()) do
		add(path)
	end
	for _, n in workspace.paths:get() do
		if not n.folder and (n.git == "modified" or n.git == "added" or n.git == "renamed") then
			add(n.path)
		end
	end
	return out
end

-- The workspace's files, their text searched as it is typed ("In Files");
-- a match opens its file in the right pane.
local contents: { command_palette.Content } = {}
do
	local workspace = require("./files")
	local ICONS: { [string]: string } =
		{ rs = "file-code", luau = "file-code", md = "file-markdown", toml = "file-data" }
	local paths: { string } = {}
	for path in workspace.TEXT do
		table.insert(paths, path)
	end
	table.sort(paths)
	for _, path in paths do
		table.insert(contents, {
			path = path,
			text = workspace.TEXT[path],
			icon = ICONS[string.match(path, "%.(%w+)$") or ""] or "document",
			open = function(_line: number)
				workspace.open(path)
			end,
		})
	end
end

local palette = command_palette.new("palette", {
	query = state.query,
	commands = commands,
	threads = threads,
	files = files,
	recent_files = recent_files,
	current_thread = function(): string?
		return thread_of[state.session:get()]
	end,
	contents = contents,
	on_close = function()
		state.palette:set(false)
	end,
})

-- The palette over the window.
function M.view(): Node
	return command_palette.overlay(palette, state.palette)
end

return M
