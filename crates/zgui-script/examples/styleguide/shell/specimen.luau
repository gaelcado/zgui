-- How a page lays its specimens out: a page is sections, a section is a
-- titled block holding a grid of cells, each a labelled specimen. Variants
-- run across and states down, so every variant × state is in view at once.
local T = require("../theme")
local kit = require("@kit")

local M = {}

-- The page's header: its title and what it shows.
function M.header(title: string, blurb: string): Node
	return ui.column {
		w_full = true,
		gap = "$zeron.space.6",
		pb = "$zeron.space.20",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		kit.text.text { title, id = "page_title", size = "xxl", weight = "semibold" },
		kit.text.text { blurb, size = "lg", color = T.secondary, wrap = true, max_w = 720 },
	}
end

export type SectionProps = { title: string, note: string?, [number]: Child, id: string? }
function M.section(props: SectionProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.16",
		ui.column {
			gap = "$zeron.space.4",
			kit.text.text { props.title, size = "lg", weight = "semibold" },
			props.note and kit.text.text { props.note, size = "sm", color = T.secondary, wrap = true, max_w = 640 },
		},
		{ table.unpack(props) },
	}
end

-- A labelled specimen: the thing, and its name under it.
export type CellProps = { label: string?, [number]: Child, w: Length?, id: string?, fill: boolean? }
function M.cell(props: CellProps): Node
	-- `fill`: the cell takes the row's width (its label wraps rather than
	-- setting it), and its content fills the cell.
	return ui.column {
		id = props.id,
		w = props.w,
		w_full = props.fill,
		min_w = if props.fill then 0 else nil,
		shrink = if props.fill then 1 else nil,
		gap = "$zeron.space.8",
		ui.row {
			min_h = 36,
			items = "center",
			gap = "$zeron.space.8",
			w_full = props.fill,
			{ table.unpack(props) },
		},
		props.label and kit.text.text { props.label, size = "xs", color = T.tertiary, wrap = props.fill },
	}
end

-- A matrix: column headings along the top, row headings down the side,
-- `build(column, row)` in each cell.
export type MatrixProps = {
	id: string?,
	columns: { string },
	rows: { string },
	build: (column: string, row: string) -> Node,
	col_w: number?,
	-- A row's height (36 unless the cells carry more, a hint line say).
	row_h: number?,
}
function M.matrix(props: MatrixProps): Node
	local col_w = props.col_w or 132
	local head: { Node } = { ui.div { w = 88 } }
	for _, c in props.columns do
		table.insert(head, ui.div { w = col_w, kit.text.text { c, size = "xs", color = T.tertiary } })
	end
	local lines: { Node } = { ui.row { gap = "$zeron.space.12", items = "center", head } }
	for _, r in props.rows do
		local cells: { Node } = {
			ui.div { w = 88, kit.text.text { r, size = "xs", color = T.tertiary, line = false } },
		}
		for _, c in props.columns do
			table.insert(cells, ui.row { w = col_w, min_h = props.row_h or 36, items = "center", props.build(c, r) })
		end
		table.insert(lines, ui.row { gap = "$zeron.space.12", items = "center", cells })
	end
	-- Wider than the canvas, it scrolls sideways. (A scroll view has no
	-- content height of its own, so the rows' is given: a 16 header and
	-- 36-high rows, 10 apart.)
	return ui.scroll_x {
		id = props.id,
		w_full = true,
		-- Zeron's edge fade, sideways, as far as the matrix runs past.
		fade_x = { 24, 24 },
		fade_overflow = true,
		h = 16 + #props.rows * ((props.row_h or 36) + 10) + 8,
		ui.column { gap = "$zeron.space.10", lines },
	}
end

-- A card a specimen sits on when it needs a surface of its own (a popover
-- shown open, a sidebar fragment).
export type FrameProps = {
	w: Length?,
	h: Length?,
	p: Length?,
	[number]: Child,
	bg: Color?,
	id: string?,
	items: ("start" | "center" | "stretch")?,
	gap: Num?,
	overflow: ("hidden" | "visible")?,
}
function M.frame(props: FrameProps): Node
	return ui.column {
		id = props.id,
		w = props.w,
		h = props.h,
		p = props.p or "$zeron.space.16",
		gap = props.gap,
		items = props.items,
		overflow = props.overflow,
		rounded = T.radius_card,
		bg = props.bg or T.base,
		border = 1,
		border_color = T.hairline,
		{ table.unpack(props) },
	}
end

return M
