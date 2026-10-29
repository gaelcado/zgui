-- Shell: Zeron's window as the app draws it, from the same kit pieces: the
-- titlebar beside the traffic lights, the sidebar, a pane with surface
-- chrome, the transcript's edge fade and the jump pill.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local tb = require("@kit/titlebar")
local session_sidebar = require("@kit/session_sidebar")

local active = ui.state("shell_active", "a2")
local tab = ui.state("shell_tab", "transcript")
local sidebar_open = ui.state("shell_sidebar", true)

-- The app's sidebar and titlebar, over sample sessions.
local SESSIONS: { session_sidebar.Session } = {
	{
		key = "a1",
		row = "shell_a1",
		title = "Refactor the layout engine",
		harness = "claude",
		status = "working",
		project = "zgx",
		ago = "2m",
	},
	{
		key = "a2",
		row = "shell_a2",
		title = "Write the release notes",
		harness = "claude",
		status = "input",
		project = "comet",
		ago = "6m",
		pinned = true,
	},
	{
		key = "a3",
		row = "shell_a3",
		title = "Fix flaky test",
		harness = "codex",
		status = "done",
		project = "zgx",
		ago = "1h",
	},
	{
		key = "a4",
		row = "shell_a4",
		title = "Casual greeting exchange",
		harness = "claude",
		status = "idle",
		project = "comet",
		ago = "3d",
	},
}

-- Three 12-point lights, 8 apart, 12 in: where macOS puts them.
local function lights(): Node
	local dots: { Node } = {}
	for _, c in { "$zeron.traffic.close", "$zeron.traffic.minimize", "$zeron.traffic.zoom" } do
		table.insert(dots, ui.div { w = 12, h = 12, rounded = "$zeron.radius.6", bg = c })
	end
	return ui.row { gap = "$zeron.space.8", pl = "$zeron.space.12", items = "center", dots }
end

local function titlebar(): Node
	return ui.overlay {
		w_full = true,
		h = tb.HEIGHT,
		shrink = 0,
		tb.titlebar {
			id = "shell_title",
			window_drag = false,
			sidebar = sidebar_open,
			on_sidebar = function()
				sidebar_open:toggle()
			end,
			sidebar_w = function()
				return if sidebar_open:get() then 240 else 0
			end,
			title = "Write the release notes",
			title_icon = "claude-mark",
			title_tint = T.claude,
		},
		ui.row { h_full = true, items = "center", pointer_events = "none", lights() },
	}
end

local function sidebar(): Node
	return ui.show(
		sidebar_open,
		ui.column {
			w = 240,
			h_full = true,
			shrink = 0,
			bg = T.ink1,
			border_sides = { 0, 1, 0, 0 },
			border_color = T.hairline,
			session_sidebar.view {
				id = "shell_sidebar",
				sessions = SESSIONS,
				projects = { "zgx", "comet" },
				harness = { claude = { icon = "claude-mark", tint = T.claude }, codex = { icon = "openai-mark" } },
				prs = 2,
				archived_total = 382,
				selected = function(key: string)
					return active:get() == key
				end,
				open = function(key: string)
					active:set(key)
				end,
				user = "Gaël Cado",
			},
		}
	)
end

local function transcript(): Node
	local lines: { Node } = {}
	for i = 1, 14 do
		table.insert(
			lines,
			ui.column {
				gap = "$zeron.space.6",
				px = "$zeron.space.16",
				py = "$zeron.space.8",
				kit.text.text { if i % 4 == 1 then "You" else "Claude", size = "xs", color = T.tertiary },
				kit.text.text {
					if i % 4 == 1
						then "Can you draft the release notes for 0.2.109?"
						else "Here is a first pass at the notes, grouped by area, with the breaking change first.",
					size = "lg",
					wrap = true,
					color = T.text,
				},
			}
		)
	end
	-- `grow` alone: `h_full` would measure against the whole pane, toolbar
	-- included, and overflow it.
	return kit.scroll {
		id = "shell_scroll",
		grow = 1,
		w_full = true,
		fade = 24,
		gap = "$zeron.space.4",
		py = "$zeron.space.8",
		over = {
			ui.row {
				absolute = true,
				left = 0,
				right = 0,
				bottom = 12,
				justify = "center",
				pointer_events = "none",
				kit.jump { id = "shell_jump" },
			},
		},
		lines,
	}
end

local function pane(): Node
	return ui.column {
		id = "shell_pane",
		grow = 1,
		shrink = 1,
		min_w = 0,
		min_h = 0,
		h_full = true,
		kit.chrome.toolbar {
			kit.chrome.tab {
				label = "Transcript",
				selected = function()
					return tab:get() == "transcript"
				end,
				on_click = ui.set(tab, "transcript"),
			},
			kit.chrome.tab {
				label = "Changes",
				icon = "git-branch",
				selected = function()
					return tab:get() == "changes"
				end,
				on_click = ui.set(tab, "changes"),
			},
			kit.chrome.tab {
				label = "Terminal",
				icon = "terminal",
				selected = function()
					return tab:get() == "terminal"
				end,
				on_click = ui.set(tab, "terminal"),
			},
			ui.div { grow = 1 },
			kit.chrome.control { icon = "sort" },
			kit.chrome.control { icon = "more-horizontal" },
		},
		transcript(),
	}
end

local function window(): Node
	return ui.column {
		id = "shell_window",
		w = 960,
		h = 520,
		rounded = T.radius_card,
		overflow = "hidden",
		bg = T.glass,
		border = 1,
		border_color = T.border,
		titlebar(),
		-- The row and the pane must be able to shrink to the window.
		ui.row { grow = 1, shrink = 1, min_h = 0, w_full = true, items = "stretch", sidebar(), pane() },
	}
end

return function(): Node
	local p = state.page_by("shell")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "Window",
			note = "titlebar 38 · sidebar 240 on wash 5% · rows 45 (29 compact) at radius 8 · footer 28-point buttons, 16 avatar · toolbar 38 · transcript fade 24 · jump pill 30.",
			window(),
		},
	}
end
