-- Changes (changes.rs): a file's header row at 38 with its counts, and
-- the diff beneath it; lines 21 high in mono 12, a 3-point rail, two
-- gutters of 36, a 28-point marker column, the add and delete tints at
-- 5.5% behind them.
local T = require("../theme")
local disclosure = require("./disclosure")
local wash = require("./wash")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Kind = "add" | "del" | "ctx"
export type Line = { kind: Kind, old: number?, new: number?, text: string }
export type FileProps = {
	id: string?,
	path: string,
	icon: icon_mod.Name?,
	added: number?,
	removed: number?,
	binary: boolean?,
	open: State<boolean>,
	-- Rows after the first carry a hairline above.
	first: boolean?,
	on_open: Handler?,
	-- The changes list's group: the header washes as its rows do.
	group: string?,
}
export type HunkProps = { header: string, lines: { Line } }

local M = {}

M.LINE = 21
M.GUTTER = 36
M.MARKER = 28

M.file = ui.component(function(props: FileProps): Node
	return ui.row(wash.maybe(props.group, {
		variants = recipes.wash { rest = "ink1" },
		id = props.id,
		w_full = true,
		h = 38,
		px = "$zeron.space.12",
		gap = "$zeron.space.8",
		items = "center",
		cursor = "pointer",
		border_sides = if props.first == false then { 1, 0, 0, 0 } else nil,
		border_color = T.hairline,
		on_click = ui.toggle(props.open),
		icon { name = props.icon or "file-code", size = 14, color = T.secondary },
		txt.text {
			props.path,
			size = "sm",
			mono = true,
			color = T.secondary,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
			line = false,
		},
		props.binary and txt.text { "BIN", size = "micro", color = T.tertiary, line = false },
		props.added and txt.text { `+{props.added}`, size = "xs", mono = true, color = T.diff_add, line = false },
		props.removed and txt.text { `−{props.removed}`, size = "xs", mono = true, color = T.diff_del, line = false },
		disclosure.chevron { open = props.open, size = 13, color = T.tertiary },
		ui.button {
			variants = recipes.wash { hover = "ink3" },
			w = 24,
			h = 24,
			p = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_open,
			icon { name = "document", size = 14, color = T.secondary },
		},
	}))
end)

local function gutter(n: number?, color: Color): Node
	return txt.text {
		if n then tostring(n) else "",
		size = "xs",
		mono = true,
		tabular = true,
		color = color,
		align = "end",
		w = M.GUTTER - 8,
		mr = "$zeron.space.8",
		line = false,
	}
end

-- A line is five nodes (a list builds one per row as it shows): the rail
-- is the row's left border, the code its own padding.
function M.line(l: Line): Node
	local tint = if l.kind == "add" then T.diff_add elseif l.kind == "del" then T.diff_del else nil
	local wash = if l.kind == "add" then T.diff_add_wash elseif l.kind == "del" then T.diff_del_wash else T.clear
	local rail = if l.kind == "add" then T.diff_add_rail elseif l.kind == "del" then T.diff_del_rail else T.clear
	local numbers = if tint then tint else T.tertiary
	return ui.row {
		w_full = true,
		h = M.LINE,
		items = "center",
		bg = wash,
		border_sides = { 0, 0, 0, 3 },
		border_color = rail,
		-- Both numbers in one text: right-aligned in their columns of mono
		-- digits, as two gutters would set them.
		txt.text {
			string.format("%4s %4s", if l.old then tostring(l.old) else "", if l.new then tostring(l.new) else ""),
			size = "xs",
			mono = true,
			tabular = true,
			color = numbers,
			align = "end",
			w = 2 * M.GUTTER - 8,
			mr = "$zeron.space.8",
			line = false,
		},
		txt.text {
			if l.kind == "add" then "+" elseif l.kind == "del" then "−" else "·",
			size = "sm",
			mono = true,
			color = tint or T.diff_dot,
			align = "center",
			w = M.MARKER,
			line = false,
		},
		txt.text {
			l.text,
			literal = true,
			size = "sm",
			mono = true,
			color = T.diff_code,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
			ml = "$zeron.space.12",
			mr = "$zeron.space.24",
			line = false,
		},
	}
end

M.HUNK = 28

-- A hunk's header row: where it starts, in the hunk wash.
function M.hunk_header(header: string): Node
	return ui.row {
		w_full = true,
		h = M.HUNK,
		px = "$zeron.space.16",
		items = "center",
		bg = T.diff_hunk,
		txt.text { header, literal = true, size = "xs", mono = true, color = T.tertiary, truncate = true, line = false },
	}
end

M.hunk = ui.component(function(props: HunkProps): Node
	local lines: { Node } = {}
	for _, l in props.lines do
		table.insert(lines, M.line(l))
	end
	return ui.column {
		w_full = true,
		M.hunk_header(props.header),
		lines,
	}
end)

-- One side of a split row: its number, its marker and its text, washed by
-- its kind; nothing where the other side has a line this one lacks.
local function side(l: Line?, old: boolean): Node
	if not l then
		return ui.div { grow = 1, basis = 0, h_full = true, bg = T.ink1 }
	end
	local tint = if l.kind == "add" then T.diff_add elseif l.kind == "del" then T.diff_del else nil
	local wash = if l.kind == "add" then T.diff_add_wash elseif l.kind == "del" then T.diff_del_wash else T.clear
	return ui.row {
		grow = 1,
		basis = 0,
		min_w = 0,
		h_full = true,
		items = "center",
		bg = wash,
		gutter(if old then l.old else l.new, tint or T.tertiary),
		txt.text {
			if l.kind == "add" then "+" elseif l.kind == "del" then "−" else "·",
			size = "sm",
			mono = true,
			color = tint or T.diff_dot,
			align = "center",
			w = 20,
			line = false,
		},
		txt.text {
			l.text,
			literal = true,
			size = "sm",
			mono = true,
			color = T.diff_code,
			truncate = true,
			grow = 1,
			min_w = 0,
			line = false,
		},
	}
end

-- A split row (changes.rs split_pairs): the old side's line beside the new
-- side's, a deletion paired with the addition that replaced it.
function M.split(left: Line?, right: Line?): Node
	return ui.row {
		w_full = true,
		h = M.LINE,
		side(left, true),
		ui.div { w = 1, h_full = true, bg = T.hairline, shrink = 0 },
		side(right, false),
	}
end

-- A file with its hunks folding under the header (180 ms ease-out).
export type ChangeProps = { file: FileProps, hunks: { HunkProps }, w: Length? }
M.change = ui.component(function(props: ChangeProps): Node
	local hunks: { Node } = {}
	for _, h in props.hunks do
		table.insert(hunks, M.hunk(h))
	end
	return ui.column {
		w = props.w,
		w_full = props.w == nil,
		overflow = "hidden",
		M.file(props.file),
		ui.presence(function()
			return if props.file.open:get() then "open" else nil
		end, function(): Node
			return ui.column { w_full = true, hunks }
		end, {
			w_full = true,
			layout = "height",
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.COLLAPSE), ease = motion.EASE_OUT },
			exit = { opacity = 0, duration = motion.d(motion.COLLAPSE), ease = motion.EASE_OUT },
		}),
	}
end)

return M
