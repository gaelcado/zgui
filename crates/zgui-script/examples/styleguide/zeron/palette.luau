-- ⌘K's content: the commands (each running what the app's key runs), the
-- threads and the files it lists; the kit draws it (kit/command_palette).
local command_palette = require("@kit/command_palette")
local data = require("./data")
local state = require("./state")
local sidebar = require("./sidebar")

local M = {}

type Row = command_palette.Row

-- The commands, with their shortcuts. `act` runs what the app's keys run,
-- so a command and its key never drift apart.
local commands: { Row } = {}
local function command(id: string, label: string, icon: string, keys: { string }?, run: () -> ())
	table.insert(commands, { id = id, section = "Commands", label = label, icon = icon, keys = keys, run = run })
end

-- What the app wires: the actions its keys take (app_zeron.luau).
M.act = {} :: { [string]: () -> () }
local function act(name: string): () -> ()
	return function()
		local f = M.act[name]
		if f then
			f()
		end
	end
end

command("new_tab", "New space", "add-circle", { "⌘", "T" }, act("new_tab"))
command("split_right", "Split right", "split-columns", { "⌘", "D" }, act("split_right"))
command("split_down", "Split down", "split-columns", { "⌘", "⇧", "D" }, act("split_down"))
command("close", "Close pane or space", "close", { "⌘", "W" }, act("close"))
command("sidebar", "Toggle sidebar", "list", { "⌘", "\\" }, act("sidebar"))
command("files", "Toggle Files", "folder-tree", { "⌘", "⇧", "E" }, act("files"))
command("terminal", "Open a terminal", "terminal", nil, function()
	state.open_tab("terminal")
end)
command("browser", "Open a browser", "globe", nil, function()
	state.open_tab("preview")
end)
command("notes", "Open notes", "pen", nil, function()
	state.open_tab("notes")
end)
command("side_chat", "New side chat", "chat-round-line", nil, function()
	state.open_side_chat()
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
command("settings", "Settings", "settings", { "⌘", "," }, function()
	state.settings:set(true)
end)
command("check_updates", "Check for updates", "refresh", nil, function()
	require("./account").check_for_updates()
end)

-- Each thread with what search weighs (thread_search.rs): its title,
-- project, branch, device and pull request.
local threads: { Row } = {}
for _, s in sidebar.sessions() do
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

local files: { Row } = {}
do
	-- Each file under the folders above it.
	local path: { string } = {}
	for _, f in data.FILES do
		path[f.level + 1] = f.name
		for i = f.level + 2, #path do
			path[i] = nil
		end
		if not f.folder then
			table.insert(files, {
				id = `file_{f.id}`,
				section = "Files",
				label = f.name,
				detail = table.concat(path, "/", 1, f.level),
				icon = (f.icon or "document") :: string,
				run = function()
					state.open_tab("changes")
				end,
			})
		end
	end
end

local palette = command_palette.new("palette", {
	query = state.query,
	commands = commands,
	threads = threads,
	files = files,
	on_close = function()
		state.palette:set(false)
	end,
})

-- The palette over the window.
function M.view(): Node
	return command_palette.overlay(palette, state.palette)
end

return M
