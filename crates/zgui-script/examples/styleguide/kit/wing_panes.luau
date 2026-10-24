-- Wing's zterm panes, as his demos show them: an editor (a 44 header
-- with the file, its path, Open and Save; a 48 line-number gutter in
-- mono; a 32 status row), a Hacker News reader (a 44 header with the Y
-- tile and a refresh, filter pills, numbered stories with score, author,
-- age and comments), a notes pane, and a Claude Code terminal pane.
local T = require("../theme")
local recipes = require("./recipes")
local wash = require("./wash")
local icon = require("./icon")
local txt = require("./text")
local button = require("./button")
local icon_button = require("./icon_button")
local scroll = require("./scroll")
local types = require("./types")

export type EditorProps = {
	id: string?,
	name: string,
	path: string?,
	lines: { string },
	first_line: number?,
	language: string?,
	-- Lines selected (from, to), one-based within `lines`.
	selection: { number }?,
	saved: boolean?,
}
export type Story = { title: string, domain: string, score: number, by: string, age: string, comments: number }
export type HnProps =
	{ id: string?, stories: { Story }, filter: State<string>, on_refresh: Handler?, compact: boolean? }
export type NotesProps = { id: string?, value: State<string> }
export type ClaudeProps = { id: string?, version: string?, model: string?, plan: string?, cwd: string? }

local M = {}

M.HEADER = 44
M.GUTTER = 48

M.editor = ui.component(function(props: EditorProps): Node
	local rows: { Node } = {}
	local first = props.first_line or 1
	local sel = props.selection
	for i, line in props.lines do
		local n = first + i - 1
		local selected = sel ~= nil and i >= sel[1] and i <= sel[2]
		table.insert(
			rows,
			ui.row {
				w_full = true,
				h = 21,
				items = "center",
				txt.text {
					tostring(n),
					size = "sm",
					mono = true,
					color = T.tertiary,
					w = M.GUTTER - 12,
					align = "end",
					line = false,
				},
				ui.row {
					grow = 1,
					shrink = 1,
					min_w = 0,
					ml = "$zeron.space.12",
					h_full = true,
					items = "center",
					bg = if selected then T.selection else T.clear,
					txt.text { line, size = "md", mono = true, truncate = true, line = false },
				},
			}
		)
	end
	return ui.column {
		id = props.id,
		grow = 1,
		w_full = true,
		min_h = 0,
		items = "stretch",
		ui.row {
			h = M.HEADER,
			px = "$zeron.space.14",
			gap = "$zeron.space.10",
			items = "center",
			shrink = 0,
			icon { name = "document", size = 16, color = T.secondary },
			txt.text { props.name, size = "lg", weight = "semibold", line = false },
			props.path and txt.text {
				props.path,
				size = "sm",
				color = T.tertiary,
				truncate = true,
				line = false,
				shrink = 1,
				min_w = 0,
			},
			ui.div { grow = 1 },
			button {
				id = props.id and `{props.id}_open`,
				label = "Open",
				icon = { name = "folder" },
				variant = "ghost",
				size = "sm",
			},
			button {
				id = props.id and `{props.id}_save`,
				label = "Save",
				icon = { name = "floppy-disk" },
				variant = "ghost",
				size = "sm",
			},
		},
		scroll { grow = 1, w_full = true, px = "$zeron.space.12", py = "$zeron.space.8", fade = 18, rows },
		ui.row {
			h = 32,
			px = "$zeron.space.14",
			gap = "$zeron.space.16",
			items = "center",
			shrink = 0,
			border_sides = { 1, 0, 0, 0 },
			border_color = T.hairline,
			txt.text {
				if props.saved == false then "Edited" else "Saved",
				size = "sm",
				color = T.tertiary,
				line = false,
			},
			ui.div { grow = 1 },
			txt.text { `{#props.lines + first - 1} lines`, size = "sm", color = T.tertiary, line = false },
			txt.text { props.language or "Plain text", size = "sm", color = T.tertiary, line = false },
		},
	}
end)

local FILTERS = { "Top", "New", "Best", "Ask", "Show" }

local function pill(label: string, on: () -> boolean, on_click: () -> (), group: string): Node
	return ui.button(wash.item(group, {
		h = 28,
		px = "$zeron.space.12",
		items = "center",
		rounded = "$zeron.radius.8",
		variants = recipes.listed_pick { selected = on },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = on_click,
		txt.text {
			label,
			size = "md",
			weight = "medium",
			line = false,
			color = "inherit",
		},
	}, on))
end

local function story(i: number, s: Story, compact: boolean, group: string): Node
	return ui.row(wash.item(group, {
		w_full = true,
		px = "$zeron.space.12",
		py = if compact then 8 else 10,
		gap = "$zeron.space.10",
		items = "start",
		rounded = T.radius_lg,
		txt.text {
			tostring(i),
			size = "sm",
			color = T.tertiary,
			w = 16,
			align = "end",
			line = false,
			mt = "$zeron.space.2",
		},
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.4",
			if compact
				then txt.text { `{i}. {s.title}`, size = "md", wrap = true }
				else ui.rich {
					wrap = true,
					text_size = "$font.size.lg",
					color = T.text,
					s.title,
					ui.span { "  " .. s.domain, color = T.tertiary, text_size = 12 },
				},
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				if compact
					then txt.text {
						`{s.score} points by {s.by} · {s.comments} comments`,
						size = "sm",
						color = T.tertiary,
						line = false,
					}
					else ui.row {
						gap = "$zeron.space.8",
						items = "center",
						icon { name = "alt-arrow-up", size = 11, color = T.claude },
						txt.text { tostring(s.score), size = "sm", color = T.secondary, line = false },
						txt.text { s.by, size = "sm", color = T.tertiary, line = false },
						txt.text { s.age, size = "sm", color = T.tertiary, line = false },
						icon { name = "chat-round-line", size = 12, color = T.tertiary },
						txt.text { tostring(s.comments), size = "sm", color = T.tertiary, line = false },
					},
			},
		},
	}))
end

M.hn = ui.component(function(props: HnProps): Node
	local pills: { Node } = {}
	local filters = wash.group("hn_filters")
	for _, f in FILTERS do
		table.insert(
			pills,
			pill(f, function()
				return props.filter:get() == f
			end, function()
				props.filter:set(f)
			end, filters)
		)
	end
	local group = wash.group("hn")
	local rows: { Node } = {}
	for i, s in props.stories do
		table.insert(rows, story(i, s, props.compact == true, group))
	end
	return ui.column {
		id = props.id,
		grow = 1,
		w_full = true,
		min_h = 0,
		items = "stretch",
		ui.row {
			h = M.HEADER,
			px = "$zeron.space.14",
			gap = "$zeron.space.10",
			items = "center",
			shrink = 0,
			ui.row {
				w = 24,
				h = 24,
				rounded = "$zeron.radius.6",
				bg = T.claude,
				items = "center",
				justify = "center",
				txt.text { "Y", size = "sm", weight = "semibold", color = "#ffffff", line = false },
			},
			txt.text { "Hacker News", size = "lg", weight = "semibold", line = false },
			ui.div { grow = 1 },
			icon_button {
				id = props.id and `{props.id}_refresh`,
				icon = "refresh",
				size = 28,
				icon_size = 15,
				label = "Refresh",
				no_ring = true,
				on_click = props.on_refresh,
			},
		},
		ui.row {
			px = "$zeron.space.12",
			pb = "$zeron.space.8",
			gap = "$zeron.space.2",
			items = "center",
			shrink = 0,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			wash.list {
				group = filters,
				direction = "row",
				gap = "$zeron.space.2",
				color = T.ink2,
				pills,
			},
		},
		scroll {
			grow = 1,
			w_full = true,
			px = "$zeron.space.4",
			py = "$zeron.space.6",
			fade = 18,
			wash.list { group = group, color = T.ink1, rows },
		},
	}
end)

M.notes = ui.component(function(props: NotesProps): Node
	return ui.textarea {
		id = props.id,
		value = props.value,
		label = "Notes",
		placeholder = "Notes for this pane",
		placeholder_color = T.tertiary,
		grow = 1,
		w_full = true,
		p = "$zeron.space.14",
		bg = T.clear,
		border = 0,
		rounded = 0,
		font = T.sans,
		text_size = "$font.size.lg",
		line_height = 22,
		color = T.text,
		focus = { border = 0 },
	}
end)

-- Claude Code's welcome, as it prints in a terminal pane.
M.claude = ui.component(function(props: ClaudeProps): Node
	local function mono(s: string, color: Color?): Node
		return txt.text { s, size = "md", mono = true, color = color or T.text, line = false }
	end
	return ui.column {
		id = props.id,
		grow = 1,
		w_full = true,
		min_h = 0,
		p = "$zeron.space.16",
		gap = "$zeron.space.4",
		ui.row {
			gap = "$zeron.space.18",
			items = "start",
			icon { name = "claude-mark", size = 56, color = T.claude },
			ui.column {
				gap = "$zeron.space.4",
				pt = "$zeron.space.4",
				ui.row {
					gap = "$zeron.space.8",
					mono("Claude Code", T.text),
					mono(props.version or "v2.1.308", T.tertiary),
				},
				mono(`{props.model or "Opus 5.5"} · {props.plan or "Claude Max"}`, T.secondary),
				mono(props.cwd or "~/Documents/GitHub/zgui", T.secondary),
			},
		},
		ui.div { grow = 1 },
		ui.div { h = 1, w_full = true, bg = T.hairline },
		ui.row {
			py = "$zeron.space.10",
			gap = "$zeron.space.8",
			items = "center",
			mono("❯", T.secondary),
			mono('Try "refactor lib.rs"', T.tertiary),
		},
		ui.div { h = 1, w_full = true, bg = T.hairline },
		ui.row {
			pt = "$zeron.space.10",
			gap = "$zeron.space.8",
			items = "center",
			mono("▶▶ bypass permissions on", T.danger),
			mono("(shift+tab to cycle)", T.tertiary),
		},
	}
end)

local _ = types
return M
