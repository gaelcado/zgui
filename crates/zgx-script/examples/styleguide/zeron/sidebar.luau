-- The sidebar: the kit's (kit/session_sidebar) over the app's sessions. In
-- Zeron's layout it runs under the titlebar's band; in the glass layout it
-- carries the window's controls itself, beside the traffic lights, and sits
-- on the glass.
local kit = require("@kit")
local session_sidebar = require("@kit/session_sidebar")
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local data = require("./data")
local state = require("./state")
local chrome = require("./chrome")
local account = require("./account")
local voice = require("./voice")

local M = {}

-- The projects' artwork, wherever their icons show.
for name, art in data.PROJECT_ART do
	kit.project_icon.art[name] = art
end

-- The window's controls: the sidebar toggle, back and forward, and new.
function M.controls(prefix: string): { Node }
	return {
		tb.control {
			id = `{prefix}_sidebar`,
			label = "Toggle sidebar",
			glyph = kit.sidebar_glyph { open = state.sidebar, size = 16 },
			on_click = function()
				ps.toggle(state.shell_now(), "sidebar")
			end,
		},
		ui.row {
			gap = "$zeron.titlebar.control_gap",
			tb.control {
				id = `{prefix}_back`,
				label = "Back",
				icon = "arrow-left",
				on_click = state.back,
				disabled = function()
					return not state.can_back()
				end,
			},
			tb.control {
				id = `{prefix}_forward`,
				label = "Forward",
				icon = "arrow-right",
				on_click = state.forward,
				disabled = function()
					return not state.can_forward()
				end,
			},
		},
		tb.control {
			id = `{prefix}_new`,
			label = "New session",
			icon = "plus",
			on_click = function()
				state.go("chat", "new")
			end,
		},
	}
end

-- The glass layout's top row: past the traffic lights, the controls.
local function glass_head(): Node
	return ui.row {
		id = "side_head",
		h = chrome.HEADER,
		w_full = true,
		shrink = 0,
		pl = "$zeron.lights",
		-- Centred on the lights' line.
		pt = ui.raw(2 * chrome.LIGHTS_LINE - chrome.HEADER, "the traffic lights' line, measured"),
		gap = "$zeron.titlebar.group_gap",
		items = "center",
		window_drag = true,
		M.controls("side"),
	}
end

-- Where each session runs, how long ago it started and last spoke, and
-- its running subagents: sample metadata over the data's sessions until
-- the engine is wired. This machine is THIS; a session not listed runs
-- here, created as it last spoke.
M.THIS = data.THIS
local ELSEWHERE = data.ELSEWHERE
local CREATED: { [string]: number } = {
	["agent:a1"] = 180,
	["agent:a2"] = 2900,
	["agent:a6"] = 50,
	["agent:a3"] = 400,
	["thread:h1"] = 9000,
}
local UNIT: { [string]: number } = { m = 1, h = 60, d = 1440, w = 10080 }

-- "42m" as minutes ("now" is 0).
local function minutes(ago: string): number
	local n, unit = string.match(ago, "^(%d+)(%a)$")
	if n and unit then
		return (tonumber(n) or 0) * (UNIT[unit] or 1)
	end
	return 0
end

local decorated: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
function M.sessions(): { any }
	local out = {}
	for _, s in data.SESSIONS do
		local d = decorated[s]
		if not d then
			d = table.clone(s) :: any
			local updated = minutes(s.ago)
			d.device = ELSEWHERE[s.key] or s.device or M.THIS
			d.remote = d.device ~= M.THIS
			d.subagents = data.RUNNING_SUBAGENTS[s.key]
			d.updated = updated
			d.created = math.max(CREATED[s.key] or updated, updated)
			decorated[s] = d
		end
		table.insert(out, d)
	end
	return out
end

-- Whether the sidebar marks `session`: the chat's (or the board) in the
-- classic layouts, the focused pane's in the tabs layouts.
local function selected(session: string): boolean
	if state.tabbed() then
		return state.pane_session:get() == session
	end
	if session == "prs" then
		return state.route:get() == "prs"
	end
	return state.route:get() == "chat" and state.session:get() == session
end

-- ⌃Tab and ⌃⇧Tab (tabs.rs): the next or previous session in the
-- sidebar's order, wrapping; with none chosen, the first or the last. One
-- press, one session: no switcher held open on the modifier.
function M.cycle(by: number)
	local order = session_sidebar.visible("sidebar")
	if #order == 0 then
		return
	end
	local now = if state.tabbed_now() then state.pane_session:peek() else state.session:peek()
	local at = table.find(order, now)
	local next = if at then (at - 1 + by) % #order + 1 elseif by > 0 then 1 else #order
	state.open_session(order[next])
end

-- ⌘1 to ⌘9: the session in that place of the sidebar's order.
function M.jump(n: number): boolean
	local key = session_sidebar.visible("sidebar")[n]
	if not key then
		return false
	end
	state.open_session(key)
	return true
end

function M.view(): Node
	return session_sidebar.view {
		sessions = M.sessions :: any,
		this_device = M.THIS,
		on_copied = function(what: string)
			kit.toast.push { title = `{what} copied`, tone = "success" }
		end,
		projects = data.PROJECTS,
		offline = data.project_offline,
		can_change = account.can_change,
		-- The engine's limit (a host may set another).
		max_pins = ui.shared("pin_limit", 200):peek(),
		on_notice = function(message: string)
			kit.toast.push { title = message, tone = "danger" }
		end,
		harness = {
			claude = { icon = data.HARNESS.claude.icon, tint = data.HARNESS.claude.tint, name = "Claude Code" },
			codex = { icon = data.HARNESS.codex.icon, name = "Codex" },
			cursor = { icon = data.HARNESS.cursor.icon, name = "Cursor" },
		} :: any,
		prs = #data.PRS,
		archived_total = data.ARCHIVED_TOTAL,
		version = state.sessions_version,
		selected = selected,
		open = state.open_session,
		-- Beside the session on screen, where General says.
		open_pr = function(key: string)
			if state.hooks.open_session_pr then
				state.hooks.open_session_pr(key)
			end
		end,
		open_in_tab = function(key: string)
			if state.hooks.open_in_tab then
				state.hooks.open_in_tab(key)
			end
		end,
		tabbed = state.tabbed_now,
		new_session = function(project: string, device: string?)
			if state.hooks.canvas_project then
				state.hooks.canvas_project(project, device)
			end
			state.go("chat", "new")
		end,
		-- Cloud machines start chats in a project only.
		devices = { M.THIS, "Mac Studio" },
		on_new_project = function()
			require("./projects").start()
		end,
		on_settings = function()
			state.settings:set(not state.settings:peek())
		end,
		settings_open = function()
			return state.settings:get()
		end,
		account = account.account,
		on_sign_out = account.request_sign_out,
		on_enable_sync = account.start_sign_in,
		on_finish_sync = account.reopen_sync_notice,
		-- macOS keeps it in the app menu, under About.
		on_check_updates = if ui.shared("platform", ""):peek() == "macos" then nil else account.check_for_updates,
		update = account.update,
		on_update = account.on_update,
		connection = account.connection,
		star = account.star,
		voice = true,
		on_voice = voice.start,
		voice_call = voice.call,
		width = function(): number
			return ps.sidebar_width(state.shell_now())
		end,
		head = ui.presence(state.layout, function(layout: string): Node
			if layout == "glass" then
				return glass_head()
			elseif layout == "tabs_sidebar" then
				-- The topbar runs over it.
				return ui.div { h = 4, shrink = 0 }
			end
			return ui.div { h = tb.HEIGHT, shrink = 0 }
		end, { w_full = true, shrink = 0 }),
	}
end

return M
