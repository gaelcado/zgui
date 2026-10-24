-- The glass layout's well (Rex's): a column inset into the window's blur,
-- translucent and darker than the glass, a dark hairline outside and a
-- light one inside, dimmer while another well has the focus; its header a
-- 40-high row the window drags from.
local T = require("../theme")
local recipes = require("./recipes")

local M = {}

export type WellProps = {
	id: string?,
	-- Whether it has the focus (its inner line lit).
	focused: (boolean | (() -> boolean))?,
	on_press: ((e: PointerEvent) -> ())?,
	header: Node?,
	[number]: Child,
}
M.well = ui.component(function(p: WellProps): Node
	return ui.column {
		id = p.id,
		variants = recipes.well { focused = if p.focused == nil then true else p.focused },
		on_press = p.on_press,
		p.header,
		ui.column { grow = 1, min_h = 0, w_full = true, items = "stretch", { table.unpack(p :: any) } },
	}
end)

-- A split's glyph: a window divided side by side (`row`) or one over the
-- other (`column`).
function M.split_glyph(axis: "row" | "column", size: number?, color: Color?): Node
	local s = size or 14
	local c = color or T.tertiary
	return ui.div {
		w = s,
		h = s - 2,
		rounded = "$zeron.radius.3",
		border = 1.5,
		border_color = c,
		direction = if axis == "row" then "row" else "column",
		items = "center",
		justify = "center",
		ui.div { w = if axis == "row" then 1.5 else "100%", h = if axis == "row" then "100%" else 1.5, bg = c },
	}
end

-- A well's header row: the window drags from it.
M.HEADER = 40
export type HeaderProps = { id: string?, pl: (() -> Length)?, [number]: Child }
M.header = ui.component(function(p: HeaderProps): Node
	return ui.row {
		id = p.id,
		h = M.HEADER,
		w_full = true,
		shrink = 0,
		pl = p.pl or "$zeron.space.12",
		pr = "$zeron.space.6",
		gap = "$zeron.space.8",
		items = "center",
		window_drag = true,
		{ table.unpack(p :: any) },
	}
end)

return M
