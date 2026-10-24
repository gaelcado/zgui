-- The headers each layout draws. Zeron's: one unified titlebar across the
-- window, its identity gliding with the sidebar, the pane's strip over the
-- pane, the anchors over Files. Glass: a header per well, the same pieces
-- spread over them (the conversation's carries the window's controls while
-- the sidebar is shut).
local T = require("../theme")
local kit = require("@kit")
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local state = require("./state")
local chrome = require("./chrome")
local pane = require("./pane")
local prs = require("./prs")
local sidebar = require("./sidebar")

local M = {}

local function chat(): boolean
	return state.route:get() == "chat"
end

-- The Files and pane toggles (Files only where the route has it).
local function anchors(prefix: string): { Node }
	return {
		ui.show(
			chat,
			tb.button {
				id = `{prefix}_files_toggle`,
				label = "Files",
				icon = "folder-tree",
				on = function()
					return ps.shown(state.chat, "files")
				end,
				on_click = function()
					ps.toggle(state.chat, "files")
				end,
			}
		),
		tb.button {
			id = `{prefix}_pane_toggle`,
			label = "Pane",
			glyph = tb.pane_glyph {
				open = function()
					return ps.shown(state.shell(), "right")
				end,
				size = 16,
			},
			on_click = function()
				ps.toggle(state.shell_now(), "right")
			end,
		},
	}
end

local function actions(prefix: string): { Node }
	return {
		ui.show(chat, kit.actions_pill { id = `{prefix}_actions`, label = "Run dev", kind = "play" }),
		ui.show(
			chat,
			tb.button {
				id = `{prefix}_card`,
				label = "Session details",
				glyph = tb.card_glyph(16),
				on = function()
					return state.card:get()
				end,
				on_click = ui.toggle(state.card),
			}
		),
	}
end

-- The pane's header strip for the route: the chat's tabs with expand, or
-- the open pull request.
local function strip(prefix: string): Node
	return ui.presence(state.route, function(route: string): Node
		if route == "prs" then
			return ui.row { grow = 1, min_w = 0, items = "center", prs.tab() }
		end
		return ui.row {
			grow = 1,
			shrink = 1,
			w_full = true,
			min_w = 0,
			gap = "$zeron.space.4",
			items = "center",
			ui.row { grow = 1, shrink = 1, min_w = 0, overflow = "hidden", pane.strip(prefix) },
			pane.expand(prefix),
		}
	end, { grow = 1, min_w = 0, w_full = true })
end

-- Zeron's unified titlebar.
function M.titlebar(): Node
	local function shell(): ps.Shell
		return state.shell()
	end
	return tb.titlebar {
		id = "ztitle",
		sidebar = state.sidebar,
		on_sidebar = function()
			ps.toggle(state.shell_now(), "sidebar")
		end,
		on_back = state.back,
		on_forward = state.forward,
		can_back = state.can_back,
		can_forward = state.can_forward,
		on_new = function()
			state.go("chat", "new")
		end,
		sidebar_w = function()
			return shell().w.sidebar:get()
		end,
		title = state.title,
		title_icon = "claude-mark",
		title_tint = T.claude,
		takeover = function()
			return shell().expanded:get()
		end,
		actions = actions("ztitle"),
		pane = strip("zp"),
		pane_w = function()
			return shell().w.right:get()
		end,
		pane_content_w = function()
			local s = shell()
			s.version:get()
			return math.max(ps.targets(s).right, s.w.right:get())
		end,
		files_w = function()
			return if chat() then state.chat.w.files:get() else 0
		end,
		anchors = anchors("zeron"),
	}
end

-- The glass layout's conversation (or board) header: the window's controls
-- while the sidebar is shut, what the window shows, its actions, and the
-- toggles.
function M.conversation(): Node
	local function shut(): boolean
		return state.shell().w.sidebar:get() < 0.5
	end
	return chrome.header {
		id = "well_conversation_head",
		pl = function()
			return if shut() then "$zeron.lights_header" else "$zeron.space.14"
		end,
		ui.show(
			shut,
			ui.row {
				gap = "$zeron.titlebar.group_gap",
				items = "center",
				pr = "$zeron.space.4",
				-- On the lights' line, above the header's own (the well
				-- starts a gap and its hairline down): the window's
				-- controls stay level with the lights in every layout.
				mb = ui.raw(
					2 * (chrome.GAP + 1 + chrome.HEADER / 2 - chrome.LIGHTS_LINE),
					"the traffic lights' line, measured"
				),
				sidebar.controls("well"),
			}
		),
		ui.show(chat, kit.icon { name = "claude-mark", size = 15, color = T.claude }),
		kit.text.text { state.title, size = "md", weight = "medium", line = false, truncate = true, shrink = 1 },
		ui.div { grow = 1 },
		actions("well"),
		anchors("glass"),
	}
end

-- The glass layout's pane header: the strip.
function M.pane(): Node
	return chrome.header {
		id = "well_right_head",
		pl = function()
			return "$zeron.space.8"
		end,
		strip("wp"),
	}
end

function M.files(): Node
	return chrome.header {
		id = "well_files_head",
		kit.text.text { "Files", size = "sm", weight = "semibold", line = false },
	}
end

return M
