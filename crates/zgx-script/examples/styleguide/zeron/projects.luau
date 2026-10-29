-- Adding a project (shell/spaces.rs, the add-space flow): ⌘K's card, a
-- step at a time. A device, then where on it (Home or a drive), then its
-- folders, the crumbs above the list saying where it is ("New project ›
-- MacBook Pro › Home › code"; the middle of a deep trail folded into "…",
-- "Show hidden folders"). The search filters each step; in Home it finds
-- folders anywhere under it too. Typing a folder's name and `/` goes in,
-- Tab takes the ghost's completion, ← goes up; ⌘L, the pen or a click
-- beside the crumbs types a path instead ("Folder path, like ~/code"),
-- completing as it goes. ⌘↵ or "Add project" makes the open folder a
-- project (the one already there for that folder is reused) and lands on
-- the new-session canvas in it. Sample devices and folders, read with a
-- little latency, until the engine lists them.
local T = require("../theme")
local kit = require("@kit")
local data = require("./data")
local state = require("./state")
local account = require("./account")

local M = {}

-- A project added or landed in (onboarding's last step ends).
M.on_added = nil :: (() -> ())?

export type Device = {
	id: string,
	name: string,
	platform: "macos" | "linux",
	home: string,
	drives: { { name: string, path: string } },
}
M.DEVICES = {
	{
		id = "mbp",
		name = "MacBook Pro",
		platform = "macos",
		home = "/Users/gael",
		drives = { { name = "Macintosh HD", path = "/" }, { name = "Backup", path = "/Volumes/Backup" } },
	},
	{
		id = "studio",
		name = "Mac Studio",
		platform = "macos",
		home = "/Users/gael",
		drives = { { name = "Macintosh HD", path = "/" } },
	},
	{
		id = "build",
		name = "Build server",
		platform = "linux",
		home = "/home/gael",
		drives = { { name = "/", path = "/" }, { name = "data", path = "/mnt/data" } },
	},
} :: { Device }
local ONLINE = { mbp = true, studio = true, build = false } :: { [string]: boolean }

-- Each platform's folders: a name ending in `*` is a repository; `false`
-- a folder that cannot be listed.
local FS: { [string]: { [string]: { string } | false } } = {
	macos = {
		["/"] = { "Applications", "Library", "System", "Users", "Volumes" },
		["/Applications"] = {},
		["/Library"] = false,
		["/System"] = false,
		["/Users"] = { "gael", "Shared" },
		["/Users/Shared"] = {},
		["/Users/gael"] = {
			"code",
			"Desktop",
			"Documents",
			"Downloads",
			"Library",
			"Sites",
			"zeron",
		},
		["/Users/gael/code"] = { "comet*", "dotfiles*", "experiments", "rex*", "tern*" },
		["/Users/gael/code/comet"] = { "assets", "crates", "docs" },
		["/Users/gael/code/dotfiles"] = {},
		["/Users/gael/code/rex"] = { "src" },
		["/Users/gael/code/tern"] = { "src" },
		["/Users/gael/code/experiments"] = { "luau-bench*", "notes", "wgpu-triangle*" },
		["/Users/gael/code/experiments/luau-bench"] = {},
		["/Users/gael/code/experiments/notes"] = { "2026" },
		["/Users/gael/code/experiments/notes/2026"] = { "october" },
		["/Users/gael/code/experiments/notes/2026/october"] = {},
		["/Users/gael/code/experiments/wgpu-triangle"] = {},
		["/Users/gael/Desktop"] = {},
		["/Users/gael/Documents"] = { "Invoices", "Talks" },
		["/Users/gael/Documents/Invoices"] = {},
		["/Users/gael/Documents/Talks"] = { "rustconf-deck*" },
		["/Users/gael/Documents/Talks/rustconf-deck"] = {},
		["/Users/gael/Downloads"] = {},
		["/Users/gael/Library"] = false,
		["/Users/gael/Sites"] = { "blog*", "grid-website*" },
		["/Users/gael/Sites/blog"] = {},
		["/Users/gael/Sites/grid-website"] = {},
		["/Users/gael/zeron"] = { "comet*", "zgui*", "zgx*", "zimmer-v2*" },
		["/Users/gael/zeron/comet"] = { "crates", "docs" },
		["/Users/gael/zeron/zgui"] = { "crates", "docs" },
		["/Users/gael/zeron/zgx"] = { "crates", "docs" },
		["/Users/gael/zeron/zimmer-v2"] = {},
		["/Volumes"] = { "Backup", "Macintosh HD" },
		["/Volumes/Backup"] = { "archive", "photos" },
		["/Volumes/Backup/archive"] = { "old-site*" },
		["/Volumes/Backup/archive/old-site"] = {},
		["/Volumes/Backup/photos"] = {},
	},
	linux = {
		["/"] = { "home", "mnt", "srv" },
		["/home"] = { "gael" },
		["/home/gael"] = { "builds", "code" },
		["/home/gael/builds"] = {},
		["/home/gael/code"] = { "comet*" },
		["/mnt"] = { "data" },
		["/mnt/data"] = {},
		["/srv"] = {},
	},
}
-- How long a device takes to list a folder.
M.LATENCY = 160

export type Step = "devices" | "locations" | "folders"
export type Row = {
	id: string,
	label: string,
	glyph: string,
	-- Muted after the label (where a folder from under Home lives).
	detail: string?,
	-- A device's presence dot, a repository's branch glyph.
	online: boolean?,
	repo: boolean?,
	-- Over the row: its section ("In Home").
	header: string?,
	run: () -> (),
}

-- ---- paths -----------------------------------------------------------------

local function join(base: string, name: string): string
	return if base == "/" then `/{name}` else `{base}/{name}`
end
local function parent(path: string): string?
	if path == "/" then
		return nil
	end
	local up = string.match(path, "^(.*)/[^/]+$")
	return if up == nil or up == "" then "/" else up
end
local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end
-- At or under `root` (`/media/a` is not under `/media/ab`).
local function under(path: string, root: string): boolean
	return path == root or root == "/" or string.sub(path, 1, #root + 1) == `{root}/`
end
-- Spelled from `~` under home.
local function tilde(path: string, home: string): string
	if path == home then
		return "~"
	elseif under(path, home) then
		return "~" .. string.sub(path, #home + 1)
	end
	return path
end
-- `.` and `..` resolved.
local function normal(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return "/" .. table.concat(parts, "/")
end
-- A typed path: absolute, from home (`~`, `~/code`) or from `base`.
local function resolve(text: string, base: string?, home: string): string?
	local t = string.match(text, "^%s*(.-)%s*$") or ""
	if t == "" then
		return nil
	elseif t == "~" then
		return home
	elseif string.sub(t, 1, 2) == "~/" then
		return normal(home .. string.sub(t, 2))
	elseif string.sub(t, 1, 1) == "/" then
		return normal(t)
	elseif base then
		return normal(`{base}/{t}`)
	end
	return nil
end
local function typed_path(text: string): boolean
	local c = string.sub(text, 1, 1)
	return c == "/" or c == "~"
end
-- Case-insensitive prefix: `query` starts `name`.
local function prefixes(name: string, query: string): boolean
	return query ~= "" and string.lower(string.sub(name, 1, #query)) == string.lower(query)
end
-- popover.rs match_rank: a prefix 0, inside 1, else none.
local function rank(label: string, query: string): number?
	local q = string.lower(string.match(query, "^%s*(.-)%s*$") or "")
	if q == "" then
		return 1
	end
	local l = string.lower(label)
	if string.sub(l, 1, #q) == q then
		return 0
	end
	return if string.find(l, q, 1, true) then 1 else nil
end
local function filtered<T>(list: { T }, label: (T) -> string, query: string): { T }
	type Ranked = { item: T, rank: number, at: number }
	local ranked: { Ranked } = {}
	for i, item in list do
		local r = rank(label(item), query)
		if r then
			table.insert(ranked, { item = item, rank = r, at = i })
		end
	end
	table.sort(ranked, function(a: Ranked, b: Ranked): boolean
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.at < b.at
	end)
	local out: { T } = {}
	for _, r in ranked do
		table.insert(out, r.item)
	end
	return out
end
local function slug(text: string): string
	return (string.gsub(string.lower(text), "[^%w]+", "_"))
end

-- ---- the flow's state ---------------------------------------------------------

M.open = ui.state("proj_open", false)
local step = ui.state("proj_step", "devices" :: Step)
local device_id = ui.state("proj_device", "")
-- The location: its name ("Home", a drive's) and its path ("" for Home).
local location = ui.state("proj_location", "")
local location_path = ui.state("proj_location_path", "")
-- The folder asked for, and the one listed (`listing`, its folders).
local wanted = ui.state("proj_wanted", "")
local load = ui.state("proj_load", "idle" :: "idle" | "loading" | "ready" | "error")
local load_error = ui.state("proj_load_error", "")
local listed = ui.state("proj_listed", "")
local listing = ui.state("proj_listing", {} :: { string })
M.query = ui.state("proj_query", "")
local active = ui.state("proj_active", 1)
local busy = ui.state("proj_busy", false)
local failure = ui.state("proj_failure", "")
-- The crumbs as a typed path.
local editing = ui.state("proj_editing", false)
M.path = ui.state("proj_path", "")
local path_error = ui.state("proj_path_error", "")
local opening = ui.state("proj_opening", false)
local folded_open = ui.state("proj_folded_open", false)
-- Each listing asked for: a stale answer is dropped.
local asked = 0
local search_ref = ui.ref()
local path_ref = ui.ref()

-- Focus to `ref`'s field, all its text selected with `select`: now, or
-- once it is built.
local function focus(ref: Ref, select: boolean?)
	local function now(): boolean
		local el = ref:get()
		if el then
			el:focus()
			if select then
				el:select_all()
			end
		end
		return el ~= nil
	end
	if not now() then
		ui.after(0, function()
			now()
		end)
	end
end

local function device(): Device?
	local id = device_id:peek()
	for _, d in M.DEVICES do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function device_now(): Device?
	device_id:get()
	return device()
end

-- A folder's listing on device `d`: its folders, or why not.
function M.list(d: Device, path: string): ({ string }?, string?)
	if not ONLINE[d.id] then
		return nil, "Device is not connected"
	end
	local entries = FS[d.platform][path]
	if entries == nil then
		return nil, `No folder at {tilde(path, d.home)}`
	elseif entries == false then
		return nil, `Can't open {tilde(path, d.home)}: permission denied`
	end
	return entries, nil
end
local function entry_name(entry: string): string
	return (string.gsub(entry, "%*$", ""))
end
local function is_repo(entry: string): boolean
	return string.sub(entry, -1) == "*"
end

local function reset_query()
	M.query:set("")
	active:set(1)
end

-- Lists `path` (a moment later, as a device answers).
local function load_folder(path: string)
	local d = device()
	if not d then
		return
	end
	asked += 1
	local this = asked
	wanted:set(path)
	load:set("loading")
	editing:set(false)
	active:set(1)
	focus(search_ref)
	ui.after(M.LATENCY, function()
		if this ~= asked then
			return
		end
		local entries, err = M.list(d, path)
		if entries then
			listed:set(path)
			listing:set(entries)
			load:set("ready")
		else
			load_error:set(err or "")
			load:set("error")
		end
	end)
end

function M.pick_device(id: string)
	device_id:set(id)
	step:set("locations")
	location:set("")
	load:set("idle")
	failure:set("")
	editing:set(false)
	reset_query()
	focus(search_ref)
end

local function goto_location(name: string, path: string)
	local d = device()
	if not d then
		return
	end
	step:set("folders")
	location:set(name)
	location_path:set(path)
	listed:set("")
	reset_query()
	load_folder(if path == "" then d.home else path)
end

local function back_to(to: Step)
	asked += 1
	step:set(to)
	location:set("")
	load:set("idle")
	listed:set("")
	failure:set("")
	editing:set(false)
	if to == "devices" then
		device_id:set("")
	end
	reset_query()
	focus(search_ref)
end

-- The location's root: its drive's path, or the device's home.
local function root(): string
	local d = device()
	local p = location_path:peek()
	return if p ~= "" then p elseif d then d.home else "/"
end

-- The folder the trail ends in: the one listed, or the one on its way.
local function open_folder(): string?
	if step:peek() ~= "folders" then
		return nil
	end
	return if load:peek() == "ready" then listed:peek() else wanted:peek()
end

function M.descend(path: string)
	reset_query()
	load_folder(path)
end

local function go_up()
	local s = step:peek()
	if s == "locations" then
		back_to("devices")
	elseif s == "folders" then
		local here = open_folder()
		local up = here and here ~= root() and parent(here)
		if up then
			M.descend(up)
		else
			back_to("locations")
		end
	end
end

-- ---- what the step lists ------------------------------------------------------

local function folder_rows(query: string): { Row }
	local d = device()
	if not d or load:get() ~= "ready" then
		return {}
	end
	local base = listed:get()
	local out: { Row } = {}
	local seen: { [string]: boolean } = { [base] = true }
	for _, entry in filtered(listing:get(), entry_name, query) do
		local name = entry_name(entry)
		local full = join(base, name)
		seen[full] = true
		table.insert(out, {
			id = `project_folder_{slug(name)}`,
			label = name,
			glyph = "folder",
			repo = is_repo(entry),
			run = function()
				M.descend(full)
			end,
		})
	end
	-- In Home, the folders anywhere under it that match (two letters on).
	if location:get() == "Home" and #query >= 2 and not typed_path(query) then
		local found: { { path: string, repo: boolean } } = {}
		for path, entries in FS[d.platform] do
			if entries ~= false and under(path, d.home) and path ~= d.home and not seen[path] then
				if rank(basename(path), query) == 0 or rank(basename(path), query) == 1 then
					local up = parent(path) :: string
					local repo = false
					for _, e in FS[d.platform][up] or {} do
						if entry_name(e) == basename(path) then
							repo = is_repo(e)
						end
					end
					table.insert(found, { path = path, repo = repo })
				end
			end
		end
		table.sort(found, function(a, b): boolean
			local ra, rb = rank(basename(a.path), query) :: number, rank(basename(b.path), query) :: number
			if ra ~= rb then
				return ra < rb
			end
			return a.path < b.path
		end)
		for i, f in found do
			if i > 20 then
				break
			end
			local path = f.path
			table.insert(out, {
				id = `project_home_{slug(tilde(path, d.home))}`,
				label = basename(path),
				detail = tilde(parent(path) :: string, d.home),
				glyph = "folder",
				repo = f.repo,
				header = if i == 1 then "In Home" else nil,
				run = function()
					M.descend(path)
				end,
			})
		end
	end
	return out
end

local function device_name(d: Device): string
	return d.name
end
local function place_name(p: { name: string, path: string }): string
	return p.name
end

-- What the open step lists for the query, in order. (Rows hold
-- functions, which a computed cannot carry, so this runs where read.)
local function rows(): { Row }
	local s = step:get()
	local query = M.query:get()
	local out: { Row } = {}
	if s == "devices" then
		for _, d in filtered(M.DEVICES, device_name, query) do
			local id = d.id
			table.insert(out, {
				id = `project_device_{id}`,
				label = d.name,
				glyph = if d.platform == "macos" then "laptop" else "monitor",
				online = ONLINE[id],
				run = function()
					M.pick_device(id)
				end,
			})
		end
	elseif s == "locations" then
		local d = device_now()
		if d then
			local places = { { name = "Home", path = "" } }
			for _, drive in d.drives do
				table.insert(places, drive)
			end
			for _, place in filtered(places, place_name, query) do
				table.insert(out, {
					id = `project_location_{slug(place.name)}`,
					label = place.name,
					glyph = if place.path == "" then "home" else "hard-drive",
					run = function()
						goto_location(place.name, place.path)
					end,
				})
			end
		end
	else
		out = folder_rows(query)
	end
	return out
end

-- The ghost after the query: the rest of the highlighted folder's name
-- when the query starts it, else the first that it starts.
local function completion(): string?
	if step:get() ~= "folders" or load:get() ~= "ready" then
		return nil
	end
	local query = M.query:get()
	if query == "" then
		return nil
	end
	local names: { string } = {}
	for _, entry in filtered(listing:get(), entry_name, query) do
		table.insert(names, entry_name(entry))
	end
	local pick = names[active:get()]
	if not (pick and prefixes(pick, query)) then
		pick = nil
		for _, name in names do
			if prefixes(name, query) then
				pick = name
				break
			end
		end
	end
	if pick == nil or #pick <= #query then
		return nil
	end
	return pick
end

-- The typed path's completion: its last name finished from its parent's
-- folders, a slash after it; and the rest the ghost shows.
local function path_completion(): (string?, string?)
	local d = device_now()
	if not d then
		return nil, nil
	end
	local text = M.path:get()
	local folder, name = string.match(text, "^(.*/)([^/]*)$")
	if folder == nil or name == nil or name == "" or name == "." or name == ".." then
		return nil, nil
	end
	local up = resolve(folder, open_folder(), d.home)
	local entries = up and FS[d.platform][up]
	if not entries then
		return nil, nil
	end
	local pick: string? = nil
	for _, e in entries do
		if entry_name(e) == name then
			pick = entry_name(e)
		end
	end
	if not pick then
		for _, e in entries do
			if prefixes(entry_name(e), name) then
				pick = entry_name(e)
				break
			end
		end
	end
	if not pick then
		return nil, nil
	end
	local rest = if #pick > #name then string.sub(pick, #name + 1) else nil
	return `{folder}{pick}/`, rest
end

-- ---- acting -------------------------------------------------------------------

local function close()
	asked += 1
	M.open:set(false)
end

-- Starts the flow (⌘K's New project, the space switcher's, onboarding's,
-- ⌘⇧N), on `device` if given.
function M.start(on: string?)
	asked += 1
	step:set("devices")
	device_id:set("")
	location:set("")
	load:set("idle")
	listed:set("")
	busy:set(false)
	failure:set("")
	editing:set(false)
	path_error:set("")
	opening:set(false)
	reset_query()
	state.palette:set(false)
	M.open:set(true)
	if on then
		M.pick_device(on)
	end
end

-- The new project, or the one already made of that folder, and the
-- new-session canvas in it (land_in_space): an explicit project filter
-- follows it, "All" stays.
local function land(name: string)
	close()
	if state.hooks.canvas_project then
		state.hooks.canvas_project(name)
	end
	require("@kit/session_sidebar").follow_project(name)
	state.go("chat", "new")
	state.sessions_version:set(state.sessions_version:peek() + 1)
	if M.on_added then
		M.on_added()
	end
end

-- The project of folder `path` on device `d`, if one is.
local function existing(d: Device, path: string): string?
	local shown = tilde(path, d.home)
	for name, at in data.PROJECT_PATHS do
		if at == shown and table.find(data.PROJECT_DEVICES[name] or {}, d.name) then
			return name
		end
	end
	return nil
end

-- Makes the open folder a project (⌘↵, "Add project").
function M.submit()
	local d = device()
	if busy:peek() or step:peek() ~= "folders" or load:peek() ~= "ready" or not d then
		return
	end
	local path = listed:peek()
	local found = existing(d, path)
	if found then
		land(found)
		return
	end
	if account.connection:peek() ~= "connected" then
		failure:set("Engine not connected")
		return
	end
	busy:set(true)
	failure:set("")
	local this = asked
	ui.after(M.LATENCY * 2, function()
		if this ~= asked then
			return
		end
		busy:set(false)
		local name = basename(path)
		if data.PROJECT_PATHS[name] then
			name = `{name} ({d.name})`
		end
		table.insert(data.PROJECTS, name)
		data.PROJECT_PATHS[name] = tilde(path, d.home)
		data.PROJECT_DEVICES[name] = { d.name }
		land(name)
	end)
end

local function open_active()
	local list = rows()
	local r = list[active:peek()]
	if r then
		r.run()
		return
	end
	-- A path typed with nothing listed for it: there.
	local d = device()
	local query = M.query:peek()
	if d and step:peek() == "folders" and typed_path(query) then
		local target = resolve(query, open_folder(), d.home)
		if target then
			M.descend(target)
		end
	end
end

-- The trail as a typed path: the open folder from `~`, a slash after it
-- (all of it selected: a paste replaces it). On the devices, on the
-- highlighted one.
function M.edit_path()
	if step:peek() == "devices" then
		local r = rows()[active:peek()]
		if not r then
			return
		end
		r.run()
	end
	local d = device()
	if not d then
		return
	end
	local here = open_folder()
	local text = if here then tilde(here, d.home) else "~"
	if string.sub(text, -1) ~= "/" then
		text ..= "/"
	end
	M.path:set(text)
	path_error:set("")
	opening:set(false)
	editing:set(true)
	focus(path_ref, true)
end

local function cancel_path()
	editing:set(false)
	focus(search_ref)
end

-- ↵ in the path field (⌘↵: and add it): the typed folder, once the
-- device lists it, opens under the location holding it.
function M.open_path(add: boolean)
	local d = device()
	if not d or opening:peek() then
		return
	end
	local text = M.path:peek()
	if string.match(text, "^%s*$") then
		path_error:set("Type the folder's path")
		return
	end
	local target = resolve(text, open_folder(), d.home)
	if not target then
		path_error:set(`Can't open {text}`)
		return
	end
	opening:set(true)
	path_error:set("")
	asked += 1
	local this = asked
	ui.after(M.LATENCY, function()
		if this ~= asked then
			return
		end
		opening:set(false)
		local entries, err = M.list(d, target)
		if not entries then
			path_error:set(err or "")
			focus(path_ref)
			return
		end
		-- Home when under it, else the deepest drive holding it.
		local name, at = "Home", ""
		if not under(target, d.home) then
			name, at = "/", "/"
			local best = 0
			for _, drive in d.drives do
				if under(target, drive.path) and #drive.path >= best then
					name, at, best = drive.name, drive.path, #drive.path
				end
			end
		end
		step:set("folders")
		location:set(name)
		location_path:set(at)
		wanted:set(target)
		listed:set(target)
		listing:set(entries)
		load:set("ready")
		editing:set(false)
		reset_query()
		focus(search_ref)
		if add then
			M.submit()
		end
	end)
end

-- `/` after a folder's name goes into it (an exact name, then a unique
-- prefix), and after a typed path to it.
local function slash(): boolean
	local d = device()
	if not d or step:peek() ~= "folders" or load:peek() ~= "ready" then
		return false
	end
	local query = M.query:peek()
	if typed_path(query) then
		local target = resolve(query, open_folder(), d.home)
		if target then
			M.descend(target)
			return true
		end
		return false
	end
	if query == "" or string.find(query, "/", 1, true) then
		return false
	end
	local base = listed:peek()
	local exact, folded, starts = nil, nil, {}
	for _, e in listing:peek() do
		local name = entry_name(e)
		if name == query then
			exact = name
		elseif string.lower(name) == string.lower(query) then
			folded = name
		elseif prefixes(name, query) then
			table.insert(starts, name)
		end
	end
	local pick = exact or folded or (if #starts == 1 then starts[1] else nil)
	if pick then
		M.descend(join(base, pick))
		return true
	end
	return false
end

local function on_key(e: KeyEvent): boolean?
	local k = e.key
	if editing:peek() then
		if k == "Tab" and not e.shift then
			local text = path_completion()
			if text then
				M.path:set(text)
			end
		elseif k == "Escape" then
			cancel_path()
		elseif k == "Enter" then
			M.open_path(e.meta or e.ctrl)
		elseif k == "l" and e.meta then
			focus(path_ref, true)
		else
			return nil
		end
		return true
	end
	local n = #rows()
	if k == "ArrowDown" or (k == "n" and e.ctrl) then
		active:set(if n == 0 then 1 else active:peek() % n + 1)
	elseif k == "ArrowUp" or (k == "p" and e.ctrl) then
		active:set(if n == 0 then 1 else (active:peek() - 2) % n + 1)
	elseif k == "Enter" and (e.meta or e.ctrl) then
		M.submit()
	elseif k == "Enter" or k == "ArrowRight" then
		open_active()
	elseif k == "ArrowLeft" then
		go_up()
	elseif k == "Tab" then
		local name = completion()
		if name then
			M.query:set(name)
		end
	elseif k == "Backspace" and M.query:peek() == "" then
		go_up()
	elseif k == "/" and not e.meta then
		return if slash() then true else nil
	elseif k == "l" and e.meta then
		M.edit_path()
	elseif k == "Escape" then
		close()
	else
		return nil
	end
	return true
end

-- Typing starts the highlight over.
ui.effect(function()
	M.query:get()
	active:set(1)
end)

-- ---- drawing ------------------------------------------------------------------

local function hint(keys: { string }, label: string): Node
	return ui.row {
		gap = "$zeron.space.5",
		items = "center",
		kit.kbd { size = "sm", flat = true, table.unpack(keys) },
		kit.text.text { label, size = "xs", color = T.tertiary, line = false },
	}
end

-- The label, the typed run on the code wash (popover.rs search_highlight).
local function highlighted(label: string, query: string): Node
	local q = string.lower(string.match(query, "^%s*(.-)%s*$") or "")
	local at = if q ~= "" then string.find(string.lower(label), q, 1, true) else nil
	if not at then
		return kit.text.text { label, literal = true, size = "md", line = false, truncate = true, shrink = 1 }
	end
	local stop = at + #q - 1
	return ui.rich {
		shrink = 1,
		min_w = 0,
		truncate = true,
		text_size = "$font.size.md",
		string.sub(label, 1, at - 1),
		ui.span { string.sub(label, at, stop), color = T.text, bg = T.code_wash },
		string.sub(label, stop + 1),
	}
end

local function row(r: Row, index: number, query: string): Node
	return ui.column {
		w_full = true,
		px = "$zeron.space.8",
		r.header and ui.row {
			px = "$zeron.space.8",
			pt = if index > 1 then "$zeron.space.6" else "$zeron.space.2",
			pb = "$zeron.space.4",
			kit.text.text { r.header, size = "xs", color = T.tertiary, line = false },
		} or nil,
		ui.button {
			id = r.id,
			w_full = true,
			min_h = 30,
			py = "$zeron.space.4",
			px = "$zeron.space.8",
			gap = "$zeron.space.10",
			items = "center",
			rounded = "$zeron.radius.8",
			cursor = "pointer",
			focusable = false,
			focus = { border = 0 },
			variants = kit.recipes.active_glass {
				selected = function()
					return active:get() == index
				end,
			},
			on_hover = function(inside: boolean)
				if inside then
					active:set(index)
				end
			end,
			on_click = r.run,
			kit.icon { name = r.glyph :: any, size = 16, color = T.secondary },
			ui.row {
				grow = 1,
				shrink = 1,
				min_w = 0,
				gap = "$zeron.space.8",
				items = "center",
				overflow = "hidden",
				highlighted(r.label, query),
				r.detail and kit.text.text {
					r.detail,
					literal = true,
					size = "md",
					color = T.tertiary,
					line = false,
					truncate = true,
					shrink = 1,
					min_w = 0,
				} or nil,
			},
			r.repo and kit.icon { name = "git-branch", size = 14, color = T.tertiary } or nil,
			r.online ~= nil and ui.div {
				w = 5,
				h = 5,
				shrink = 0,
				rounded = T.radius_full,
				bg = if r.online then T.success else T.disabled,
			} or nil,
		},
	}
end

-- What an empty step says (palette_empty).
local function empty(): (string, string)
	local s = step:get()
	if s == "devices" then
		return "No devices found", "Try another device name."
	elseif s == "locations" then
		return "No locations found", "Try Home or a drive name."
	elseif M.query:get() == "" and editing:get() then
		return "No folders here", "Type another path, or press Esc for the folder trail."
	elseif M.query:get() == "" then
		return "No folders here", "Add this folder with ⌘↵, or go back with ←."
	end
	return "No folders match", "Type a path like ~/code or /mnt to jump there."
end

local function results(): Node
	return ui.presence(function()
		local ids: { string } = { step:get(), load:get(), tostring(editing:get()) }
		for _, r in rows() do
			table.insert(ids, r.id)
		end
		return table.concat(ids, ",")
	end, function(): Node
		local list = rows()
		local query = M.query:peek()
		local children: { Node } = {}
		for i, r in list do
			table.insert(children, row(r, i, query))
		end
		local status = load:peek()
		if step:peek() == "folders" and (status == "loading" or status == "idle") then
			table.insert(
				children,
				ui.column {
					id = "project_loading",
					w_full = true,
					px = "$zeron.space.8",
					kit.loaders.skeleton { rows = 5, w = "100%" },
				}
			)
		elseif step:peek() == "folders" and status == "error" then
			table.insert(
				children,
				ui.row {
					id = "project_load_error",
					w_full = true,
					p = "$zeron.space.16",
					gap = "$zeron.space.10",
					items = "center",
					kit.icon { name = "danger-triangle", size = 14, color = T.danger },
					kit.text.text {
						function()
							return load_error:get()
						end,
						size = "sm",
						color = T.danger,
						line = false,
						grow = 1,
						shrink = 1,
						truncate = true,
					},
					kit.button {
						id = "project_retry",
						label = "Retry",
						variant = "ghost",
						size = "sm",
						on_click = function()
							load_folder(wanted:peek())
						end,
					},
				}
			)
		elseif #list == 0 then
			local title, body = empty()
			table.insert(
				children,
				ui.column {
					id = "project_empty",
					w_full = true,
					py = "$zeron.space.24",
					px = "$zeron.space.16",
					gap = "$zeron.space.6",
					items = "center",
					kit.text.text { title, size = "md", line = false },
					kit.text.text { body, size = "sm", color = T.tertiary, line = false },
				}
			)
		end
		return ui.scroll {
			w_full = true,
			max_h = 360,
			fade = { 18, 18 },
			fade_overflow = true,
			ui.column { w_full = true, py = "$zeron.space.8", gap = "$zeron.space.2", children },
		}
	end, { w_full = true })
end

-- The typed path: a folder glyph, the field, its ↵ (or "Opening…").
local function path_field(): Node
	local function ghost(): string
		local _, rest = path_completion()
		return rest or ""
	end
	return ui.row {
		id = "project_path_box",
		ml = "$zeron.space.4",
		grow = 1,
		min_w = 0,
		h = 26,
		pl = "$zeron.space.8",
		pr = "$zeron.space.3",
		gap = "$zeron.space.6",
		items = "center",
		rounded = "$zeron.radius.7",
		bg = T.ink1,
		border = 1,
		border_color = function(): Color
			return if path_error:get() ~= "" then T.danger else T.accent
		end,
		kit.icon { name = "folder", size = 14, color = T.tertiary },
		ui.input {
			id = "project_path",
			ref = path_ref,
			label = "Folder path",
			value = M.path,
			placeholder = "Folder path, like ~/code",
			placeholder_color = T.tertiary,
			ghost = ghost,
			select_on_focus = true,
			grow = 1,
			min_w = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			focus = { border = 0, bg = T.clear },
			hover = { bg = T.clear },
			p = 0,
			text_size = "$font.size.sm",
			on_key = on_key,
			on_mount = function(el: Element)
				el:focus()
				el:select_all()
			end,
		},
		ui.show(
			function()
				return opening:get()
			end,
			kit.text.text { "Opening…", size = "xs", color = T.tertiary, line = false, px = "$zeron.space.5" },
			ui.button {
				id = "project_path_open",
				w = 20,
				h = 20,
				p = 0,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.5",
				focusable = false,
				focus = { border = 0 },
				cursor = "pointer",
				bg = T.clear,
				hover = { bg = T.ink3 },
				tooltip = "Open this path",
				label = "Open this path",
				on_click = function()
					M.open_path(false)
				end,
				kit.icon { name = "return", size = 12, color = T.tertiary },
			}
		),
	}
end

-- A crumb: where the flow has been, the open one in the text colour and
-- inert, the rest washing under the pointer.
type Crumb = { id: string, name: string, glyph: string?, current: boolean, run: (() -> ())? }

local function crumb_node(c: Crumb): Node
	return ui.button {
		id = c.id,
		h = 24,
		px = "$zeron.space.6",
		gap = "$zeron.space.5",
		shrink = 0,
		items = "center",
		rounded = "$zeron.radius.6",
		focusable = false,
		focus = { border = 0 },
		cursor = if c.current then nil else "pointer",
		color = if c.current then T.text else T.tertiary,
		bg = T.clear,
		hover = if c.current then nil else { bg = T.ink3, color = T.text },
		tooltip = if #c.name > 26 then c.name else nil,
		on_click = c.run,
		c.glyph and kit.icon { name = c.glyph :: any, size = 14, color = "currentColor" } or nil,
		kit.text.text {
			c.name,
			literal = true,
			size = "sm",
			color = "inherit",
			line = false,
			truncate = true,
			max_w = 180,
		},
	}
end

local function chevron(): Node
	return kit.icon { name = "alt-arrow-right", size = 12, color = T.disabled }
end

-- The trail: New project, the device, the location, its folders (past
-- three, the middle folded into "…", a menu of them).
local function trail(): Node
	return ui.presence(function()
		local d = device_now()
		local parts: { string } = { step:get(), location:get(), tostring(editing:get()) }
		if d then
			table.insert(parts, d.id)
		end
		if step:get() == "folders" then
			table.insert(parts, if load:get() == "ready" then listed:get() else wanted:get())
		end
		return table.concat(parts, "|")
	end, function(): Node
		local s = step:peek()
		local d = device()
		local crumbs: { Crumb } = {
			{
				id = "project_crumb_new",
				name = "New project",
				current = s == "devices",
				run = function()
					back_to("devices")
				end,
			},
		}
		if d then
			table.insert(crumbs, {
				id = "project_crumb_device",
				name = d.name,
				glyph = if d.platform == "macos" then "laptop" else "monitor",
				current = s == "locations",
				run = function()
					back_to("locations")
				end,
			})
		end
		local hidden: { { name: string, path: string } } = {}
		local at_folders = s == "folders" and location:peek() ~= "" and not editing:peek()
		if at_folders and d then
			local base = root()
			local here = open_folder() or base
			local name, path = location:peek(), location_path:peek()
			table.insert(crumbs, {
				id = "project_crumb_location",
				name = name,
				glyph = if path == "" then "home" else "hard-drive",
				current = here == base,
				run = function()
					goto_location(name, path)
				end,
			})
			local folders: { { name: string, path: string } } = {}
			local walk: string? = here
			while walk and walk ~= base and under(walk, base) do
				table.insert(folders, 1, { name = basename(walk), path = walk })
				walk = parent(walk)
			end
			if #folders > 3 then
				for _ = 1, #folders - 2 do
					table.insert(hidden, table.remove(folders, 1) :: any)
				end
			end
			if #hidden > 0 then
				table.insert(crumbs, { id = "project_crumb_more", name = "…", current = false })
			end
			for i, f in folders do
				local full = f.path
				table.insert(crumbs, {
					id = `project_crumb_{slug(f.name)}`,
					name = f.name,
					current = i == #folders,
					run = function()
						M.descend(full)
					end,
				})
			end
		end
		local nodes: { Node } = {}
		for i, c in crumbs do
			if i > 1 then
				table.insert(nodes, chevron())
			end
			if c.id == "project_crumb_more" then
				local items: { any } = {}
				for _, h in hidden do
					local full = h.path
					table.insert(items, {
						id = `project_more_{slug(h.name)}`,
						label = h.name,
						icon = "folder",
						on_click = function()
							M.descend(full)
						end,
					})
				end
				table.insert(
					nodes,
					kit.menu {
						id = "project_more_menu",
						open = folded_open,
						items = items,
						w = 200,
						anchor = ui.button {
							id = c.id,
							h = 24,
							min_w = 24,
							px = "$zeron.space.6",
							shrink = 0,
							items = "center",
							justify = "center",
							rounded = "$zeron.radius.6",
							focusable = false,
							focus = { border = 0 },
							cursor = "pointer",
							color = T.tertiary,
							bg = T.clear,
							hover = { bg = T.ink3, color = T.text },
							tooltip = "Show hidden folders",
							label = "Show hidden folders",
							on_click = ui.toggle(folded_open),
							kit.text.text { "…", size = "sm", color = "inherit", line = false },
						},
					}
				)
			else
				table.insert(nodes, crumb_node(c))
			end
		end
		if editing:peek() then
			table.insert(nodes, chevron())
			return ui.row { grow = 1, min_w = 0, gap = "$zeron.space.2", items = "center", nodes, path_field() }
		end
		-- The row's empty end types the path, as an address bar's does.
		local editable = s ~= "devices"
		return ui.row {
			grow = 1,
			min_w = 0,
			h_full = true,
			gap = "$zeron.space.2",
			items = "center",
			overflow = "hidden",
			nodes,
			editable and ui.div {
				id = "project_crumb_edit",
				grow = 1,
				min_w = 24,
				h_full = true,
				cursor = "text",
				on_click = M.edit_path,
			} or nil,
		}
	end, { grow = 1, min_w = 0, h_full = true })
end

local function square(id: string, glyph: string, label: string, run: () -> ()): Node
	return ui.button {
		id = id,
		w = 24,
		h = 24,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		focusable = false,
		focus = { border = 0 },
		cursor = "pointer",
		color = T.tertiary,
		bg = T.clear,
		hover = { bg = T.ink3, color = T.text },
		tooltip = label,
		label = label,
		on_click = run,
		kit.icon { name = glyph :: any, size = if glyph == "pen" then 14 else 16, color = "currentColor" },
	}
end

local function crumbs_row(): Node
	return ui.row {
		id = "project_crumbs",
		w_full = true,
		h = 36,
		shrink = 0,
		px = "$zeron.space.12",
		gap = "$zeron.space.6",
		items = "center",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		ui.presence(step, function(s: string): Node
			return square(
				"project_back",
				"arrow-left",
				if s == "devices" then "Back to commands" else "Back",
				function()
					if step:peek() == "devices" then
						close()
						state.palette:set(true)
					else
						go_up()
					end
				end
			)
		end, { shrink = 0 }),
		trail(),
		ui.show(function()
			return step:get() ~= "devices" and not editing:get()
		end, square("project_path_edit", "pen", "Edit path ⌘L", M.edit_path)),
	}
end

local function footer(): Node
	local function can_add(): boolean
		if busy:get() then
			return false
		end
		if editing:get() then
			return not opening:get() and not string.match(M.path:get(), "^%s*$")
		end
		return load:get() == "ready"
	end
	return ui.row {
		w_full = true,
		px = "$zeron.space.16",
		py = "$zeron.space.7",
		gap = "$zeron.space.12",
		items = "center",
		border_sides = { 1, 0, 0, 0 },
		border_color = T.hairline,
		ui.presence(function()
			return `{step:get()}|{editing:get()}`
		end, function(): Node
			if editing:peek() then
				return ui.row {
					gap = "$zeron.space.12",
					items = "center",
					hint({ "⇥" }, "Complete"),
					hint({ "↵" }, "Open"),
					hint({ "esc" }, "Cancel"),
				}
			end
			local s = step:peek()
			return ui.row {
				gap = "$zeron.space.12",
				items = "center",
				hint({ "↑", "↓" }, "Navigate"),
				hint({ "↵" }, if s == "folders" then "Open" else "Select"),
				s ~= "devices" and hint({ "←" }, "Back") or nil,
				hint({ "esc" }, "Close"),
				s ~= "devices" and hint({ "⌘", "L" }, "Edit path") or nil,
			}
		end),
		ui.div { grow = 1 },
		ui.show(
			function()
				return step:get() == "folders" or editing:get()
			end,
			ui.button {
				id = "project_add",
				label = "Add project",
				pl = "$zeron.space.3",
				pr = "$zeron.space.8",
				py = "$zeron.space.3",
				gap = "$zeron.space.6",
				items = "center",
				rounded = "$zeron.radius.8",
				focusable = false,
				focus = { border = 0 },
				bg = T.clear,
				hover = { bg = T.selected },
				disabled = function()
					return not can_add()
				end,
				opacity = function(): number
					return if can_add() then 1 else 0.5
				end,
				cursor = "pointer",
				on_click = function()
					if editing:peek() then
						M.open_path(true)
					else
						M.submit()
					end
				end,
				kit.kbd { size = "sm", flat = true, "⌘", "↵" },
				kit.text.text {
					function()
						return if busy:get() then "Adding…" else "Add project"
					end,
					size = "xs",
					weight = "medium",
					line = false,
				},
			}
		),
	}
end

local PLACEHOLDER = {
	devices = "Search devices…",
	locations = "Search locations…",
	folders = "Search folders…",
}

M.card = ui.component(function(): Node
	return ui.column {
		id = "project_palette",
		w = 560,
		max_w = "90%",
		rounded = "$zeron.radius.16",
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		overflow = "hidden",
		on_click = function() end,
		on_key = on_key,
		ui.row {
			w_full = true,
			min_h = 44,
			px = "$zeron.space.16",
			py = "$zeron.space.8",
			gap = "$zeron.space.10",
			items = "center",
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			kit.icon { name = "magnifer", size = 16, color = T.tertiary },
			ui.input {
				id = "project_search",
				ref = search_ref,
				label = "Search",
				value = M.query,
				placeholder = function(): string
					return PLACEHOLDER[step:get()]
				end,
				placeholder_color = T.tertiary,
				ghost = function(): string
					local name = completion()
					return if name then string.sub(name, #M.query:get() + 1) else ""
				end,
				grow = 1,
				min_w = 0,
				bg = T.clear,
				border = 0,
				rounded = 0,
				focus = { border = 0, bg = T.clear },
				hover = { bg = T.clear },
				p = 0,
				text_size = "$font.size.lg",
				on_key = on_key,
				on_mount = function(el: Element)
					el:focus()
				end,
			},
			kit.kbd { size = "sm", flat = true, table.unpack(require("./keys").caps("new_project")) },
		},
		crumbs_row(),
		ui.show(
			function()
				return editing:get() and path_error:get() ~= ""
			end,
			ui.row {
				id = "project_path_error",
				w_full = true,
				px = "$zeron.space.16",
				pt = "$zeron.space.8",
				pb = "$zeron.space.2",
				kit.text.text {
					function()
						return path_error:get()
					end,
					size = "sm",
					color = T.danger,
					line = false,
				},
			}
		),
		results(),
		ui.show(
			function()
				return failure:get() ~= ""
			end,
			ui.row {
				id = "project_failure",
				w_full = true,
				px = "$zeron.space.16",
				pb = "$zeron.space.8",
				kit.text.text {
					function()
						return failure:get()
					end,
					size = "sm",
					color = T.danger,
					line = false,
				},
			}
		),
		footer(),
	}
end)

-- The flow over the window while it is open: ⌘K's scrim and place.
function M.view(): Node
	return ui.presence(function()
		return if M.open:get() then "on" else nil
	end, function(): Node
		return ui.column {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			items = "center",
			pt = "14%",
			bg = T.scrim_soft,
			on_click = close,
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.FAST) })
			end,
			M.card(),
		}
	end, { exit = { opacity = 0, duration = kit.motion.d(kit.motion.MENU_OUT) } })
end

return M
