-- General's Git card (settings/worktrees.rs, v0.2.129): the device it
-- edits, where new worktrees go (the default, or a folder of the user's
-- chosen with Browse in a folder browser; Reset back; a folder set by
-- ZERON_WORKTREES_DIR says so and cannot change), and whether agents'
-- commits credit Zeron (always on for Cloud). Each device's settings load
-- as the card shows (Loading…, the error and Retry). Sample devices and
-- folders until the engine is wired.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local icon_button = require("./icon_button")
local button = require("./button")
local select = require("./select")
local settings = require("./settings")
local tooltip = require("./tooltip")
local recipes = require("./recipes")
local agents = require("./settings_agents")

local M = {}

-- A device's worktree settings (WorktreeSettingsStatus): its default folder,
-- the custom one and whether it is used, an environment override; and its
-- commit credit. `old`: a version that cannot answer.
export type Worktrees = {
	default: string,
	custom: string?,
	use_custom: boolean,
	env: string?,
	credit: boolean,
	cloud: boolean?,
	old: boolean?,
}
local function home(device: string): string
	for _, d in agents.devices:peek() do
		if d.id == device then
			return if d.platform == "Linux" then "/home/gael" elseif d.cloud then "/workspace" else "/Users/gael"
		end
	end
	return "/Users/gael"
end
local function sample(device: string): Worktrees
	for _, d in agents.devices:peek() do
		if d.id == device then
			if d.cloud then
				return { default = "/workspace/.zeron/worktrees", use_custom = false, credit = true, cloud = true }
			elseif d.version and d.version < "0.2.128" then
				return { default = "", use_custom = false, credit = false, old = true }
			elseif d.platform == "Linux" then
				return {
					default = "/home/gael/.zeron/worktrees",
					use_custom = false,
					env = "/srv/worktrees",
					credit = false,
				}
			end
		end
	end
	return { default = `{home(device)}/.zeron/worktrees`, use_custom = false, credit = true }
end
M.saved = ui.state("settings_git", {} :: { [string]: Worktrees })
-- Read where it changes (the row's meta, the switches).
local function saved_of(device: string): Worktrees
	return M.saved:get()[device] or sample(device)
end
local function store(device: string, w: Worktrees)
	local all = table.clone(M.saved:peek())
	all[device] = w
	M.saved:set(all)
end

-- The sample's folders under a home: each folder's subfolders, and the
-- ones that list more than they show.
local TREE: { [string]: { string } } = {
	[""] = { "Code", "Desktop", "Documents", "Downloads", "Worktrees" },
	["/Code"] = { "comet", "zeron-site", "zgui" },
	["/Code/zgui"] = { "crates", "docs", "scripts" },
	["/Downloads"] = { "archive-2024", "fonts", "invoices", "screenshots", "talks", "wallpapers" },
}
local TRUNCATED: { [string]: boolean } = { ["/Downloads"] = true }
export type Listing = { path: string, folders: { string }, truncated: boolean }
local function list(device: string, path: string): Listing
	local root = home(device)
	local rel = if string.sub(path, 1, #root) == root then string.sub(path, #root + 1) else nil
	return {
		path = path,
		folders = if rel then TREE[rel] or {} else {},
		truncated = rel ~= nil and TRUNCATED[rel] == true,
	}
end
local function parent(path: string): string?
	local up = string.match(path, "^(.*)/[^/]+$")
	if up == nil or up == "" then
		return if path ~= "/" then "/" else nil
	end
	return up
end

-- The Git card on `device` (a state the page keeps: this device unless
-- chosen).
function M.card(device: State<string>): Node
	-- "loading", "ready", or why it could not load.
	local status = ui.use_state("loading")
	local credit_status = ui.use_state("loading")
	local enabled = ui.use_state(false)
	local saving = ui.use_state(false)
	local credit_saving = ui.use_state(false)
	local failed = ui.use_state("")
	local browsing = ui.use_state(false)
	-- The folder shown, "" while it loads, or why it could not.
	local folders = ui.use_state(nil :: Listing?)
	local folders_error = ui.use_state("")
	local generation = 0

	local function load()
		generation += 1
		local at = generation
		local d = device:peek()
		status:set("loading")
		credit_status:set("loading")
		enabled:set(false)
		saving:set(false)
		failed:set("")
		browsing:set(false)
		local fails = agents.failing()
		ui.after(350, function()
			if at ~= generation then
				return
			end
			local w = saved_of(d)
			if fails then
				status:set("Device is not connected")
				credit_status:set("Device is not connected")
			elseif w.old then
				status:set("Update Zeron on the selected device to configure worktree locations.")
				credit_status:set("Update Zeron on the selected device to change this.")
			else
				enabled:set(w.use_custom)
				status:set("ready")
				credit_status:set("ready")
			end
		end)
	end
	load()

	local function ready(): Worktrees?
		return if status:get() == "ready" then saved_of(device:get()) else nil
	end
	-- What can be saved: loaded, and not set by the environment.
	local function editable(): Worktrees?
		local w = if status:peek() == "ready" then saved_of(device:peek()) else nil
		return if w and not w.env then w else nil
	end
	local function save(next: Worktrees)
		if saving:peek() or not editable() then
			return
		end
		browsing:set(false)
		saving:set(true)
		failed:set("")
		local at = generation
		local fails = agents.failing()
		ui.after(400, function()
			if at ~= generation then
				return
			end
			saving:set(false)
			if fails then
				failed:set("Couldn't save worktree settings. Check that the folder exists and is writable.")
				return
			end
			store(device:peek(), next)
			enabled:set(next.use_custom)
		end)
	end
	-- The switch turned: on reuses the remembered folder, or waits for
	-- Browse to pick one; off keeps the folder for next time.
	local function toggled(on: boolean)
		local w = editable()
		browsing:set(false)
		failed:set("")
		if w and on ~= w.use_custom and w.custom then
			local next = table.clone(w)
			next.use_custom = on
			save(next)
		end
	end
	local function reset()
		local w = editable()
		if not w or saving:peek() then
			return
		end
		enabled:set(false)
		browsing:set(false)
		failed:set("")
		if w.use_custom or w.custom then
			local next = table.clone(w)
			next.use_custom = false
			next.custom = nil
			save(next)
		end
	end
	local function browse(path: string?)
		if saving:peek() then
			return
		end
		local d = device:peek()
		local to = path or home(d)
		browsing:set(true)
		folders:set(nil)
		folders_error:set("")
		local at = generation
		local fails = agents.failing()
		ui.after(250, function()
			if at ~= generation or not browsing:peek() then
				return
			end
			if fails then
				folders_error:set(`Couldn't list {to}: permission denied`)
			else
				folders:set(list(d, to))
			end
		end)
	end
	local function use_folder(path: string)
		local w = editable()
		if w then
			local next = table.clone(w)
			next.use_custom = true
			next.custom = path
			save(next)
		end
	end
	-- The credit's switch shows the device's, and saving it asks the device.
	local credit_on = ui.use_state(false)
	local function credit_toggled(on: boolean)
		credit_saving:set(true)
		local at = generation
		local fails = agents.failing()
		ui.after(300, function()
			if at ~= generation then
				return
			end
			credit_saving:set(false)
			if fails then
				credit_on:set(not on)
				credit_status:set("Couldn't save the commit credit. Try again.")
				return
			end
			local next = table.clone(saved_of(device:peek()))
			next.credit = on
			store(device:peek(), next)
		end)
	end
	ui.effect(function()
		local on = credit_status:get() == "ready" and saved_of(device:get()).credit
		if credit_on:peek() ~= on then
			credit_on:set(on)
		end
	end)
	-- A device chosen loads its own (and drops what was under way).
	local first = true
	ui.effect(function()
		device:get()
		if first then
			first = false
			return
		end
		load()
	end)

	local function interactive(): boolean
		local w = ready()
		return w ~= nil and not w.env and not saving:get()
	end
	local function meta(): { Text }
		return {
			function()
				local s = status:get()
				local w = ready()
				if w then
					if w.env then
						return w.env
					elseif enabled:get() and w.use_custom and w.custom then
						return w.custom
					elseif enabled:get() then
						return "Choose a folder for new worktrees"
					end
					return w.default
				end
				return if s == "loading" then "Loading…" else "Couldn't load worktree settings"
			end,
			function()
				local w = ready()
				return if w and w.env then "Set by ZERON_WORKTREES_DIR" else ""
			end,
		}
	end
	local function resettable(): boolean
		local w = ready()
		return w ~= nil and not w.env and (enabled:get() or w.use_custom or w.custom ~= nil)
	end

	-- The device select (render_device_switcher): each device with its
	-- platform's glyph, this one "You".
	local options: { select.Option } = {}
	for _, d in agents.devices:peek() do
		table.insert(options, {
			value = d.id,
			label = d.name,
			id = `git_device_{string.lower((string.gsub(d.name, "%W+", "_")))}`,
			icon = (if d.cloud then "cloud" elseif d.platform == "Linux" then "monitor" else "laptop") :: any,
			detail = if d.you then "You" else nil,
		})
	end

	local function folder_row(name: string, path: string, i: number): Node
		return ui.button {
			id = `git_folder_{i}`,
			w_full = true,
			h = 30,
			px = "$zeron.space.10",
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.6",
			variants = recipes.wash { hover = "ink3" },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = function()
				browse(path)
			end,
			icon { name = "folder", size = 16, color = T.secondary },
			txt.text { name, literal = true, size = "md", grow = 1, truncate = true, line = false },
			icon { name = "alt-arrow-right", size = 12, color = T.tertiary, opacity = 0.5 },
		}
	end
	local function ghost(id: string, label: string, glyph: string?, run: () -> (), enabled_now: (() -> boolean)?): Node
		return ui.button {
			id = id,
			h = 28,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			items = "center",
			rounded = "$zeron.radius.6",
			variants = recipes.wash { hover = "ink3" },
			focus = { border = 0 },
			cursor = "pointer",
			opacity = if enabled_now
				then function()
					return if enabled_now() then 1 else 0.5
				end
				else nil,
			on_click = run,
			glyph and icon { name = glyph :: any, size = 14, color = T.secondary } or nil,
			txt.text { label, size = "md", line = false },
		}
	end
	-- The folder browser (render_browser): Home and Up, the folder, its
	-- subfolders, Use this folder.
	local function browser(): Node
		local function divider(): Node
			return ui.div { w_full = true, h = 1, bg = T.hairline }
		end
		return ui.column {
			id = "git_browser",
			w_full = true,
			mt = "$zeron.space.12",
			rounded = "$zeron.radius.10",
			border = 1,
			border_color = T.hairline,
			overflow = "hidden",
			ui.row {
				w_full = true,
				p = "$zeron.space.4",
				gap = "$zeron.space.2",
				items = "center",
				ghost("git_home", "Home", "home", function()
					browse(nil)
				end),
				ghost("git_up", "Up", "arrow-up", function()
					local now = folders:peek()
					local up = now and parent(now.path)
					if up then
						browse(up)
					end
				end, function()
					local now = folders:get()
					return now ~= nil and parent(now.path) ~= nil
				end),
			},
			divider(),
			ui.presence(function(): string
				local now = folders:get()
				if folders_error:get() ~= "" then
					return "error"
				end
				return if now then now.path else ""
			end, function(key: string): Node
				if key == "error" then
					return ui.column { w_full = true, p = "$zeron.space.10", settings.error_strip(folders_error:peek()) }
				elseif key == "" then
					return ui.row {
						w_full = true,
						px = "$zeron.space.14",
						py = "$zeron.space.10",
						txt.text { "Loading folders…", size = "sm", color = T.secondary, line = false },
					}
				end
				local now = folders:peek() :: Listing
				local rows: { Node } = {}
				for i, name in now.folders do
					table.insert(rows, folder_row(name, `{now.path}/{name}`, i))
				end
				if #rows == 0 then
					table.insert(
						rows,
						ui.row {
							px = "$zeron.space.10",
							py = "$zeron.space.8",
							txt.text { "No subfolders", size = "sm", color = T.secondary, line = false },
						}
					)
				end
				return ui.column {
					w_full = true,
					ui.row {
						w_full = true,
						px = "$zeron.space.14",
						pt = "$zeron.space.10",
						pb = "$zeron.space.6",
						txt.text {
							now.path,
							id = "git_browser_path",
							literal = true,
							size = "sm",
							color = T.secondary,
							truncate = true,
							line = false,
						},
					},
					ui.scroll {
						id = "git_folders",
						w_full = true,
						max_h = 200,
						p = "$zeron.space.4",
						rows,
					},
					now.truncated and ui.row {
						px = "$zeron.space.14",
						py = "$zeron.space.6",
						txt.text { "More folders exist than are shown here.", size = "sm", color = T.secondary },
					} or nil,
					divider(),
					ui.row {
						w_full = true,
						p = "$zeron.space.4",
						justify = "end",
						ghost("git_use_folder", "Use this folder", nil, function()
							use_folder(now.path)
						end),
					},
				}
			end, { w_full = true }),
		}
	end

	local location = settings.row {
		id = "git_location_row",
		anchor = "worktree_location",
		title = "Custom worktree location",
		meta = meta(),
		control = ui.row {
			gap = "$zeron.space.8",
			items = "center",
			shrink = 0,
			ui.show(
				resettable,
				tooltip {
					label = "Reset to default",
					icon_button {
						id = "git_reset",
						icon = "refresh",
						size = 32,
						icon_size = 14,
						label = "Use the default worktree location",
						no_ring = true,
						disabled = function()
							return not interactive()
						end,
						on_click = reset,
					},
				}
			),
			ui.show(
				function()
					local s = status:get()
					return s ~= "loading" and s ~= "ready"
				end,
				button {
					id = "git_retry",
					label = "Retry",
					size = "sm",
					variant = "ghost",
					on_click = load,
				}
			),
			select {
				id = "git_device",
				label = "Device",
				value = device,
				options = options,
				w = 160,
				menu_w = 260,
			},
			ui.show(
				function()
					local w = ready()
					return w ~= nil and not w.env and enabled:get()
				end,
				button {
					id = "git_browse",
					label = "Browse",
					icon = { name = "folder", size = 14 },
					size = "sm",
					variant = "secondary",
					disabled = function()
						return not interactive()
					end,
					on_click = function()
						local w = editable()
						browse(w and w.custom)
					end,
				}
			),
			settings.switch {
				id = "git_custom",
				value = enabled,
				disabled = function()
					return not interactive()
				end,
				on_change = toggled,
			},
		},
	}

	local credit = settings.row {
		id = "git_credit_row",
		anchor = "commit_credit",
		title = "Credit Zeron in commits",
		meta = {
			function()
				local s = credit_status:get()
				if s == "ready" then
					local w = saved_of(device:get())
					return if w.cloud then "Always on for Cloud" else "Agents' commits add zeronsh[bot] as a co-author"
				end
				return if s == "loading" then "Loading…" else s
			end,
		},
		control = settings.switch {
			id = "git_credit",
			value = credit_on,
			disabled = function()
				return credit_status:get() ~= "ready" or saved_of(device:get()).cloud == true or credit_saving:get()
			end,
			on_change = credit_toggled,
		},
	}

	return settings.section {
		id = "git_card",
		title = "Git",
		location,
		ui.show(
			function()
				return browsing:get() or failed:get() ~= ""
			end,
			ui.column {
				w_full = true,
				px = "$zeron.space.16",
				pb = "$zeron.space.16",
				gap = "$zeron.space.8",
				ui.show(browsing, browser()),
				ui.show(
					function()
						return failed:get() ~= ""
					end,
					settings.error_strip(function()
						return failed:get()
					end, "git_error")
				),
			}
		),
		credit,
	}
end

return M
