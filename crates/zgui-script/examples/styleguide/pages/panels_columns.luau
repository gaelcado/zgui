-- The Panels page's window: Zeron's titlebar over its four columns, under
-- the panel policy (kit/panel_shell). Drag the grip on the frame's right
-- edge to narrow the window: columns that no longer fit leave, least
-- recently opened first, and come back when asked for or when there is
-- room. The readout under it names the arrangement.
local T = require("../theme")
local kit = require("@kit")
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local right_panel = require("@kit/right_panel")
local file_tree = require("@kit/file_tree")
local agent_row = require("@kit/agent_row")
local tr = require("@kit/transcript")

local M = {}

M.HEIGHT = 460
M.MIN_W = 480

local shell = ps.new { id = "pd", sidebar = true, right = true, files = true, sidebar_open = true }
M.shell = shell

local active = ui.state("pd_active", "diff")
local card = ui.state("pd_card", false)
local tree_sel = ui.state("pd_tree_sel", "f1")
local agent = ui.state("pd_agent", "a1")
local address = ui.state("pd_address", "localhost:5173")
-- The room the page gives the frame, and the frame's width (0: all of it).
local room = ui.state("pd_room", 816)
local frame_w = ui.state("pd_frame_w", 0)

local TABS: { right_panel.Tab } = {
	{ id = "diff", title = "Changes", icon = "list", dot = true },
	{ id = "browser", title = "Preview", letter = "P", tint = T.info },
	{ id = "terminal", title = "zsh", icon = "terminal" },
}

local AGENTS: { agent_row.Agent } = {
	{
		id = "a1",
		name = "Write the release notes",
		where = "zgui",
		status = "working",
		icon = "claude-mark",
		tint = T.claude,
		ago = "2m",
	},
	{
		id = "a2",
		name = "Refactor the layout",
		where = "zgui",
		status = "blocked",
		waits = "question",
		icon = "openai-mark",
		ago = "now",
	},
	{
		id = "a3",
		name = "Fix flaky test",
		where = "comet",
		status = "done",
		icon = "claude-mark",
		tint = T.claude,
		ago = "2h",
	},
}

local ENTRIES: { file_tree.Entry } = {
	{ id = "src", name = "src", level = 0, folder = true, open = true },
	{ id = "kit", name = "kit", level = 1, folder = true, open = true, icon = "folder-with-files" },
	{ id = "f1", name = "panel_shell.luau", level = 2, icon = "file-code", git = "added" },
	{ id = "f2", name = "titlebar.luau", level = 2, icon = "file-code", git = "added" },
	{ id = "f3", name = "right_panel.luau", level = 2, icon = "file-code", git = "modified" },
	{ id = "f4", name = "README.md", level = 0, icon = "file-markdown" },
}

local function surface(id: string): Node
	if id == "browser" then
		return ui.column {
			w_full = true,
			h_full = true,
			items = "stretch",
			kit.browser.toolbar { value = address },
			ui.column {
				grow = 1,
				items = "center",
				justify = "center",
				kit.browser.empty {
					title = "Preview your work",
					body = "Start a dev server and its address shows up here.",
				},
			},
		}
	elseif id == "terminal" then
		return ui.column {
			p = "$zeron.space.12",
			gap = "$zeron.space.3",
			kit.text.text { "$ cargo test -p zgui-script", size = "sm", mono = true },
			kit.text.text { "test result: ok. 10 passed", size = "sm", mono = true, color = T.secondary },
		}
	end
	return ui.column {
		w_full = true,
		p = "$zeron.space.12",
		gap = "$zeron.space.8",
		kit.text.text { "kit/panel_shell.luau", size = "sm", mono = true, color = T.secondary },
		kit.text.text { "+ local fit = L.fit(viewport, …)", size = "sm", mono = true, color = T.success },
		kit.text.text { "- local width = 520", size = "sm", mono = true, color = T.danger },
	}
end

local function sidebar(): Node
	local rows: { Node } = {}
	for _, a in AGENTS do
		local snapshot = a
		table.insert(
			rows,
			agent_row.row {
				id = `pd_agent_{a.id}`,
				agent = function()
					return snapshot
				end,
				selected = function()
					return agent:get() == snapshot.id
				end,
				group = "pd-agents",
				on_click = ui.set(agent, a.id),
			}
		)
	end
	return ui.column {
		w_full = true,
		h_full = true,
		pt = "$zeron.titlebar.height",
		px = "$zeron.space.8",
		gap = "$zeron.space.1",
		rows,
	}
end

local function conversation(): Node
	return ui.column {
		w_full = true,
		h_full = true,
		relative = true,
		pt = "$zeron.titlebar.height",
		px = "$zeron.space.20",
		pb = "$zeron.space.14",
		gap = "$zeron.space.16",
		tr.user_bubble { text = "Make the panels follow Zeron's layout policy." },
		tr.paragraph(
			"The sidebar and Files keep their widths; the conversation and the pane share the rest equally, and the least recently opened column leaves when the window is too narrow."
		),
		ui.div { grow = 1 },
		kit.composer { id = "pd_composer", w = "100%", value = ui.state("pd_draft", "") },
		-- The session card, behind the header's toggle: the app's.
		ui.show(
			card,
			ui.div {
				absolute = true,
				top = "$zeron.titlebar.height",
				right = 0,
				kit.session_card.card({
					title = "Make the panels follow Zeron's policy",
					harness = { icon = "claude-mark", tint = T.claude },
					device = "MacBook Pro",
					project = "zgui",
					branch = "panels",
					pr = { number = 914, state = "open" },
				}, "pd"),
			}
		),
	}
end

local function pane(): Node
	return ui.column {
		w_full = true,
		h_full = true,
		pt = "$zeron.titlebar.height",
		bg = T.panel,
		items = "stretch",
		right_panel.surface { id = "pd_surface", tabs = TABS, active = active, render = surface },
	}
end

local function files(): Node
	return ui.column {
		w_full = true,
		h_full = true,
		pt = "$zeron.titlebar.height",
		bg = T.panel,
		ui.row {
			h = 32,
			px = "$zeron.space.12",
			items = "center",
			kit.text.text { "Files", size = "sm", weight = "semibold", line = false },
		},
		file_tree.tree { id = "pd_tree", entries = ENTRIES, selected = tree_sel },
	}
end

local function titlebar(): Node
	local function expanded(): boolean
		return shell.expanded:get()
	end
	return tb.titlebar {
		id = "pd_titlebar",
		window_drag = false,
		sidebar = shell.open.sidebar,
		on_sidebar = function()
			ps.toggle(shell, "sidebar")
		end,
		on_back = function() end,
		on_forward = function() end,
		can_back = function()
			return false
		end,
		can_forward = function()
			return false
		end,
		sidebar_w = function()
			return shell.w.sidebar:get()
		end,
		title = "Write the release notes",
		title_icon = "claude-mark",
		title_tint = T.claude,
		takeover = expanded,
		actions = {
			tb.button {
				id = "pd_card_toggle",
				label = "Session details",
				glyph = tb.card_glyph(16),
				on = function()
					return card:get()
				end,
				on_click = ui.toggle(card),
			},
		},
		pane = ui.row {
			grow = 1,
			shrink = 1,
			w_full = true,
			min_w = 0,
			gap = "$zeron.space.4",
			items = "center",
			ui.row {
				grow = 1,
				shrink = 1,
				min_w = 0,
				overflow = "hidden",
				right_panel.strip { id = "pd", tabs = TABS, active = active, render = surface },
			},
			ui.show(
				expanded,
				tb.button {
					id = "pd_collapse",
					label = "Collapse panel",
					icon = "collapse-arrows",
					on_click = function()
						ps.toggle_expand(shell)
					end,
				},
				tb.button {
					id = "pd_expand",
					label = "Expand panel",
					icon = "expand-arrows",
					on_click = function()
						ps.toggle_expand(shell)
					end,
				}
			),
		},
		pane_w = function()
			return shell.w.right:get()
		end,
		pane_content_w = function()
			shell.version:get()
			return math.max(ps.targets(shell).right, shell.w.right:get())
		end,
		files_w = function()
			return shell.w.files:get()
		end,
		anchors = {
			tb.button {
				id = "pd_files_toggle",
				label = "Files",
				icon = "folder-tree",
				on = function()
					return ps.shown(shell, "files")
				end,
				on_click = function()
					ps.toggle(shell, "files")
				end,
			},
			tb.button {
				id = "pd_pane_toggle",
				label = "Pane",
				glyph = tb.pane_glyph {
					open = function()
						return ps.shown(shell, "right")
					end,
					size = 16,
				},
				on_click = function()
					ps.toggle(shell, "right")
				end,
			},
		},
	}
end

-- macOS's traffic lights, drawn: the titlebar's controls sit at 88 beside
-- them.
local function lights(): Node
	local dots: { Node } = {}
	for _, c in { "$zeron.traffic.close", "$zeron.traffic.minimize", "$zeron.traffic.zoom" } do
		table.insert(dots, ui.div { w = 12, h = 12, rounded = "$zeron.radius.6", bg = c })
	end
	return ui.row { absolute = true, left = 14, top = 15, gap = "$zeron.space.8", pointer_events = "none", dots }
end

-- The frame's right edge, standing in for the window's: dragging it
-- resizes the window, which the columns follow at once.
local function grip(): Node
	local start: { x: number, w: number }? = nil
	return ui.div {
		id = "pd_grip",
		absolute = true,
		top = 0,
		bottom = 0,
		right = 0,
		w = 10,
		cursor = "col_resize",
		on_press = function(e: PointerEvent)
			local now = frame_w:peek()
			start = { x = e.x, w = if now > 0 then now else room:peek() }
		end,
		on_pointer_move = function(e: PointerEvent)
			local s = start
			if s then
				frame_w:set(math.clamp(s.w + e.x - s.x, M.MIN_W, room:peek()))
			end
		end,
		on_release = function()
			start = nil
		end,
	}
end

function M.view(): Node
	return ui.column {
		w_full = true,
		gap = "$zeron.space.12",
		on_resize = function(size: Size)
			if size.w > 0 and math.abs(size.w - room:peek()) > 0.5 then
				room:set(size.w)
			end
		end,
		ui.div {
			id = "pd_window",
			relative = true,
			h = M.HEIGHT,
			w = function()
				local f = frame_w:get()
				return if f > 0 then math.min(f, room:get()) else room:get()
			end,
			rounded = T.radius_card,
			bg = T.glass,
			border = 1,
			border_color = T.hairline,
			overflow = "hidden",
			ps.view(shell, {
				w_full = true,
				h_full = true,
				sidebar = sidebar(),
				conversation = conversation(),
				right = pane(),
				files = files(),
			}),
			ui.div { absolute = true, top = 0, left = 0, right = 0, titlebar() },
			lights(),
			grip(),
		},
		ui.row {
			gap = "$zeron.space.8",
			items = "center",
			flex_wrap = true,
			kit.text.text {
				function()
					return ps.describe(shell)
				end,
				id = "pd_state",
				size = "xs",
				mono = true,
				color = T.tertiary,
			},
			ui.div { grow = 1 },
			kit.button {
				id = "pd_full",
				label = "Full width",
				size = "sm",
				variant = "ghost",
				on_click = ui.set(frame_w, 0),
			},
			kit.button {
				id = "pd_open_zeron",
				label = "Open Zeron",
				size = "sm",
				variant = "secondary",
				icon = { name = "arrow-up-right" },
				on_click = ui.action("open_app", "zeron"),
			},
		},
	}
end

return M
