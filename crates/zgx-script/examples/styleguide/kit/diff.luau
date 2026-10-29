-- Changes (changes.rs): a file's header row at 38 (the chevron, the file's
-- icon, its path, its counts), and the diff beneath it; lines 21 high in
-- mono 12, a 3-point rail, two gutters of 36, a 28-point marker column,
-- the add and delete tints at 5.5% behind them. Wrapped, a long line runs
-- on under itself, its numbers and marker on its first line.
local T = require("../theme")
local disclosure = require("./disclosure")
local wash = require("./wash")
local icon = require("./icon")
local file_icon = require("./file_icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Kind = "add" | "del" | "ctx"
export type Line = { kind: Kind, old: number?, new: number?, text: string }
export type FileProps = {
	id: string?,
	path: string,
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
-- How a review stream's code shows (pull_request_code.rs): in its syntax's
-- colours, and scrolling sideways together, every line's text a viewport
-- on the one offset, as wide as the longest line (`width`), the numbers
-- and markers staying where they are.
export type Code = {
	highlight: ((line: string, state: number) -> ({ { number | string } }, number))?,
	scroll: State<number>,
	width: number,
}

local M = {}

M.LINE = 21
M.GUTTER = 36
M.MARKER = 28
-- Mono 12's advance (0.6 em), with slack for wide glyphs (code_text_width).
M.ADVANCE = 12 * 0.6 * 1.05
-- The text's insets in its line: 12 before it, 24 after.
M.TEXT_INSETS = 36

-- The width every line of `lines` fits in.
function M.code_width(lines: { Line }): number
	local columns = 0
	for _, l in lines do
		columns = math.max(columns, utf8.len(l.text) or #l.text)
	end
	return math.ceil(columns * M.ADVANCE) + M.TEXT_INSETS
end

-- A line's text on the stream's shared sideways scroll, coloured.
local function plane(text: string, code: Code, inset: boolean): Node
	return ui.scroll_x {
		grow = 1,
		shrink = 1,
		basis = 0,
		min_w = 0,
		h = M.LINE,
		items = "center",
		offset = code.scroll,
		ui.rich {
			w = code.width,
			shrink = 0,
			pl = if inset then "$zeron.space.12" else nil,
			pr = "$zeron.space.24",
			text_size = "$font.size.sm",
			line_height = M.LINE,
			font = T.mono,
			color = T.diff_code,
			ui.span { text, literal = true, highlight = code.highlight },
		},
	}
end

-- The header's node; `folds`: a disclosure's summary, which toggles it.
local function file_row(props: FileProps, folds: boolean?): Node
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
		on_click = if folds then nil else ui.toggle(props.open),
		ui.row {
			w = 14,
			h = 14,
			shrink = 0,
			items = "center",
			justify = "center",
			disclosure.chevron { open = props.open, size = 13, color = T.tertiary },
		},
		file_icon.icon { path = props.path, size = 14 },
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
end
M.file = ui.component(function(props: FileProps): Node
	return file_row(props)
end)

local function gutter(n: number?, color: Color, wrap: boolean?): Node
	return txt.text {
		if n then tostring(n) else "",
		size = "xs",
		mono = true,
		tabular = true,
		color = color,
		align = "end",
		w = M.GUTTER - 8,
		line_height = if wrap then M.LINE else nil,
		mr = "$zeron.space.8",
		line = false,
	}
end

-- A line is five nodes (a list builds one per row as it shows): the rail
-- is the row's left border, the code its own padding. `wrap` runs a long
-- line on under itself (a measured list's row) rather than cutting it;
-- `code` scrolls it sideways with the stream's others, coloured.
function M.line(l: Line, wrap: boolean?, code: Code?): Node
	local tint = if l.kind == "add" then T.diff_add elseif l.kind == "del" then T.diff_del else nil
	local wash = if l.kind == "add" then T.diff_add_wash elseif l.kind == "del" then T.diff_del_wash else T.clear
	local rail = if l.kind == "add" then T.diff_add_rail elseif l.kind == "del" then T.diff_del_rail else T.clear
	local numbers = if tint then tint else T.tertiary
	return ui.row {
		w_full = true,
		h = if wrap then nil else M.LINE,
		min_h = if wrap then M.LINE else nil,
		items = if wrap then "start" else "center",
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
			line_height = if wrap then M.LINE else nil,
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
			line_height = if wrap then M.LINE else nil,
			line = false,
		},
		if code
			then plane(l.text, code, true)
			else txt.text {
				l.text,
				literal = true,
				size = "sm",
				mono = true,
				color = T.diff_code,
				truncate = not wrap,
				wrap = wrap,
				line_height = if wrap then M.LINE else nil,
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
local function side(l: Line?, old: boolean, wrap: boolean?, code: Code?): Node
	if not l then
		return ui.div { grow = 1, basis = 0, min_w = 0, self = "stretch", bg = T.ink1 }
	end
	local tint = if l.kind == "add" then T.diff_add elseif l.kind == "del" then T.diff_del else nil
	local wash = if l.kind == "add" then T.diff_add_wash elseif l.kind == "del" then T.diff_del_wash else T.clear
	return ui.row {
		grow = 1,
		basis = 0,
		min_w = 0,
		self = "stretch",
		items = if wrap then "start" else "center",
		bg = wash,
		gutter(if old then l.old else l.new, tint or T.tertiary, wrap),
		txt.text {
			if l.kind == "add" then "+" elseif l.kind == "del" then "−" else "·",
			size = "sm",
			mono = true,
			color = tint or T.diff_dot,
			align = "center",
			w = 20,
			line_height = if wrap then M.LINE else nil,
			line = false,
		},
		if code
			then plane(l.text, code, false)
			else txt.text {
				l.text,
				literal = true,
				size = "sm",
				mono = true,
				color = T.diff_code,
				truncate = not wrap,
				wrap = wrap,
				line_height = if wrap then M.LINE else nil,
				grow = 1,
				min_w = 0,
				line = false,
			},
	}
end

-- A split row (changes.rs split_pairs): the old side's line beside the new
-- side's, a deletion paired with the addition that replaced it; wrapped,
-- as tall as its longer side. `over` sits over the new side, from its
-- start (a comment's "+"). `code` as a line's.
function M.split(left: Line?, right: Line?, over: Node?, wrap: boolean?, code: Code?): Node
	return ui.row {
		w_full = true,
		h = if wrap then nil else M.LINE,
		min_h = if wrap then M.LINE else nil,
		items = "stretch",
		hover_group = if over then true else nil,
		side(left, true, wrap, code),
		ui.div { w = 1, bg = T.hairline, shrink = 0 },
		if over
			then ui.row { grow = 1, basis = 0, min_w = 0, relative = true, side(right, false, wrap, code), over }
			else side(right, false, wrap, code),
	}
end

M.NOTICE = 24

-- A file's notice ("New file", "Binary file — contents not shown", …): 24
-- high, 16 in, at 11 in the faint text.
function M.notice(text: string): Node
	return ui.row {
		w_full = true,
		h = M.NOTICE,
		px = "$zeron.space.16",
		items = "center",
		txt.text { text, literal = true, size = "xs", color = T.tertiary, truncate = true, line = false },
	}
end

-- A file with its hunks folding under the header (180 ms ease-out).
export type ChangeProps = { file: FileProps, hunks: { HunkProps }, w: Length? }
M.change = ui.component(function(props: ChangeProps): Node
	local hunks: { Node } = {}
	for _, h in props.hunks do
		table.insert(hunks, M.hunk(h))
	end
	-- zgx's disclosure: the header its summary button.
	return ui.disclosure {
		open = props.file.open,
		bare = true,
		w = props.w,
		w_full = props.w == nil,
		overflow = "hidden",
		summary = file_row(props.file, true),
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
