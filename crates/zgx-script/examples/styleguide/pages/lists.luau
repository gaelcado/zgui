-- Lists and navigation: rows, a sidebar fragment, tabs, a scroll area,
-- dividers and key caps.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local tabs_kit = require("@kit/tabs")

local selected = ui.state("row_selected", "b")
local sidebar_sel = ui.state("sidebar_selected", "a1")
local tab = ui.state("tab", "transcript")
local pill = ui.state("pill", "all")
local open_tabs = ui.state(
	"open_tabs",
	{
		{ id = "t1", label = "zgx", icon = "folder", closable = true },
		{ id = "t2", label = "comet", icon = "folder", closable = true },
		{ id = "t3", label = "notes.md", icon = "document", closable = true },
	} :: { tabs_kit.Tab }
)
local open_tab = ui.state("open_tab", "t1")

local function rows(): Node
	local function sel(id: string): () -> boolean
		return function()
			return selected:get() == id
		end
	end
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.frame {
			w = 300,
			p = "$zeron.space.6",
			items = "stretch",
			kit.list {
				group = "rows",
				gap = "$zeron.space.1",
				kit.row {
					id = "row_a",
					label = "Rest",
					icon = "document",
					group = "rows",
					selected = sel("a"),
					on_click = ui.set(selected, "a"),
				},
				kit.row {
					id = "row_b",
					label = "Selected",
					icon = "file-code",
					group = "rows",
					selected = sel("b"),
					on_click = ui.set(selected, "b"),
				},
				kit.row {
					label = "With a detail",
					icon = "clock-circle",
					detail = "4m",
					group = "rows",
					selected = sel("c"),
					on_click = ui.set(selected, "c"),
				},
				kit.row {
					label = "With a badge",
					icon = "archive-minimalistic",
					trailing = kit.badge { label = "3" },
					group = "rows",
					selected = sel("d"),
					on_click = ui.set(selected, "d"),
				},
				kit.row {
					label = "With a shortcut",
					icon = "magnifer",
					trailing = kit.kbd { "⌘", "K", flat = true, size = "sm" },
					group = "rows",
					selected = sel("e"),
					on_click = ui.set(selected, "e"),
				},
				kit.row { label = "Disabled", icon = "key-minimalistic", disabled = true },
				kit.row {
					label = "Indented",
					icon = "document",
					indent = 1,
					group = "rows",
					selected = sel("f"),
					on_click = ui.set(selected, "f"),
				},
			},
		},
		specimen.frame {
			w = 320,
			p = "$zeron.space.6",
			items = "stretch",
			kit.list {
				group = "rows2",
				gap = "$zeron.space.1",
				kit.row {
					label = "Two lines",
					description = "A description under the label, truncated when long.",
					icon = "chat-round-line",
					group = "rows2",
					selected = function()
						return selected:get() == "g"
					end,
					on_click = ui.set(selected, "g"),
				},
				kit.row {
					label = "Status dot",
					description = "Blocked on a question",
					dot = T.warning,
					group = "rows2",
					selected = function()
						return selected:get() == "h"
					end,
					on_click = ui.set(selected, "h"),
				},
				kit.row {
					label = "Working",
					description = "Editing src/lib.rs",
					dot = T.accent,
					group = "rows2",
					selected = function()
						return selected:get() == "i"
					end,
					on_click = ui.set(selected, "i"),
				},
				kit.row {
					label = "Small",
					icon = "document",
					size = "sm",
					group = "rows2",
					selected = function()
						return selected:get() == "j"
					end,
					on_click = ui.set(selected, "j"),
				},
			},
		},
	}
end

-- A sidebar fragment: sections, rows with counts, an agent with a status.
-- The app's sidebar, over sample sessions.
local session_sidebar = require("@kit/session_sidebar")
local SESSIONS: { session_sidebar.Session } = {
	{
		key = "a1",
		row = "sg_a1",
		title = "Refactor the layout engine",
		harness = "claude",
		status = "working",
		project = "zgx",
		ago = "2m",
		pr = { number = 914, state = "open" },
	},
	{
		key = "a2",
		row = "sg_a2",
		title = "Write the release notes",
		harness = "codex",
		status = "input",
		project = "zeron",
		ago = "8m",
	},
	{
		key = "a3",
		row = "sg_a3",
		title = "Fix the flaky test",
		harness = "claude",
		status = "done",
		project = "zgx",
		ago = "1h",
		pinned = true,
	},
	{
		key = "a4",
		row = "sg_a4",
		title = "Token audit",
		harness = "claude",
		status = "idle",
		project = "zeron",
		ago = "3d",
		archived = true,
	},
}
local function sidebar(): Node
	return specimen.frame {
		w = 260,
		h = 520,
		p = 0,
		items = "stretch",
		bg = T.glass,
		session_sidebar.view {
			id = "sg_sidebar",
			sessions = SESSIONS,
			-- An empty section of the user's own.
			sections = { "Later" },
			projects = { "zgx", "zeron" },
			harness = {
				claude = { icon = "claude-mark", tint = T.claude },
				codex = { icon = "openai-mark" },
			},
			prs = 3,
			archived_total = 1,
			selected = function(key: string)
				return sidebar_sel:get() == key
			end,
			open = function(key: string)
				sidebar_sel:set(key)
			end,
			user = "Gaël Cado",
			head = ui.div { h = 8, shrink = 0 },
		},
	}
end

local function tabs(): Node
	return ui.column {
		gap = "$zeron.space.24",
		specimen.cell {
			label = "underline",
			kit.tabs {
				id = "tabs_underline",
				value = tab,
				tabs = {
					{ id = "transcript", label = "Transcript" },
					{ id = "changes", label = "Changes", count = 3 },
					{ id = "terminal", label = "Terminal", icon = "terminal" },
					{ id = "browser", label = "Browser", icon = "globe" },
				},
			},
		},
		specimen.cell {
			label = "pills",
			kit.tabs {
				id = "tabs_pills",
				variant = "pills",
				value = pill,
				tabs = {
					{ id = "all", label = "All" },
					{ id = "open", label = "Open" },
					{ id = "done", label = "Done" },
				},
			},
		},
		specimen.cell {
			label = "closable (the strip writes the state; Delete closes too)",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				kit.tabs {
					id = "tabs_closable",
					variant = "pills",
					value = open_tab,
					items = open_tabs,
				},
				kit.button {
					id = "tabs_reset",
					label = "Reset",
					size = "sm",
					variant = "ghost",
					on_click = function()
						open_tabs:set {
							{ id = "t1", label = "zgx", icon = "folder", closable = true },
							{ id = "t2", label = "comet", icon = "folder", closable = true },
							{ id = "t3", label = "notes.md", icon = "document", closable = true },
						}
					end,
				},
			},
		},
	}
end

local function scroll_area(): Node
	local lines: { Node } = {}
	for i = 1, 40 do
		table.insert(
			lines,
			kit.row { label = `Line {i}`, detail = if i % 7 == 0 then "edited" else nil, icon = "document", size = "sm" }
		)
	end
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "scroll to see the thumb; it fades at rest",
			specimen.frame {
				w = 300,
				h = 220,
				p = 0,
				kit.scroll {
					id = "scroll_demo",
					h_full = true,
					w_full = true,
					p = "$zeron.space.6",
					gap = "$zeron.space.1",
					lines,
				},
			},
		},
		specimen.cell {
			label = "thumb shown",
			specimen.frame {
				w = 300,
				h = 220,
				p = 0,
				kit.scroll {
					h_full = true,
					w_full = true,
					p = "$zeron.space.6",
					gap = "$zeron.space.1",
					preview = true,
					lines,
				},
			},
		},
	}
end

local function dividers(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "between sections",
			ui.column {
				w = 240,
				gap = "$zeron.space.12",
				kit.text.text { "Above", size = "sm", color = T.secondary },
				kit.divider {},
				kit.text.text { "Below", size = "sm", color = T.secondary },
			},
		},
		specimen.cell {
			label = "labelled, inset",
			ui.column {
				w = 240,
				gap = "$zeron.space.12",
				kit.text.text { "Today", size = "sm", color = T.secondary },
				kit.divider { label = "Yesterday", inset = "$zeron.space.8" },
				kit.text.text { "Older", size = "sm", color = T.secondary },
			},
		},
		specimen.cell {
			label = "vertical, in a toolbar",
			ui.row {
				h = 28,
				gap = "$zeron.space.8",
				items = "center",
				kit.icon_button { icon = "copy" },
				kit.icon_button { icon = "pen" },
				kit.divider { vertical = true, inset = "$zeron.space.6" },
				kit.icon_button { icon = "trash-bin-minimalistic" },
			},
		},
	}
end

local function keys(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell { label = "a chord", kit.kbd { "⌘", "K" } },
		specimen.cell { label = "a key", kit.kbd { "esc" } },
		specimen.cell { label = "arrows", kit.kbd { "↑", "↓" } },
		specimen.cell {
			label = "flat, on a raised surface",
			ui.row {
				p = "$zeron.space.6",
				rounded = T.radius_md,
				bg = T.overlay,
				kit.kbd { "⌘", "⇧", "P", flat = true },
			},
		},
		specimen.cell { label = "small", kit.kbd { "⌘", "F", size = "sm" } },
	}
end

return function(): Node
	local page = state.page_by("lists")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Rows",
			rows(),
		},
		specimen.section {
			title = "Sidebar",
			sidebar(),
		},
		specimen.section {
			title = "Tabs",
			tabs(),
		},
		specimen.section {
			title = "Scroll area",
			note = "The thumb is drawn from the offset; zgx's scroll has none.",
			scroll_area(),
		},
		specimen.section {
			title = "Dividers",
			dividers(),
		},
		specimen.section {
			title = "Key caps",
			keys(),
		},
	}
end
