-- Context menus: frosted like the rest of the window.
local theme = require("../theme")

local M = {}

local STYLE: Styles = {
	font = theme.font,
	w = 180,
	p = 3,
	gap = 0,
	rounded = 10,
	bg = "#24252a99",
	backdrop_blur = 30,
	border = 1,
	border_color = "#ffffff14",
	shadow = { y = 6, blur = 18, color = "#00000040" },
}
M.STYLE = STYLE

function M.entry(label: string, run: () -> ()): Node
	return ui.menu_item {
		label,
		h = 24,
		px = 8,
		rounded = 6,
		text_size = 12.5,
		color = theme.text,
		bg = theme.clear,
		hover = { bg = "#ffffff12" },
		focus = { bg = "#ffffff12", border = 0 },
		on_click = run,
	}
end

function M.separator(): Node
	return ui.div { h = 1, mx = 8, my = 4, bg = "#ffffff0f" }
end

return M
