-- Small pieces the bars and tabs share.
local theme = require("../theme")
local icons = require("../icons")
local names = require("@lib/names")

local M = {}

-- A pane's icon: its program's, or the glyph its title starts with.
function M.glyph(desc: () -> names.Description, size: number, dim: () -> boolean): Node
	return ui.overlay {
		w = size + 2,
		h = size + 2,
		shrink = 0,
		items = "center",
		justify = "center",
		ui.svg {
			src = function()
				return "code:" .. icons[desc().icon]
			end,
			hidden = function()
				return desc().glyph ~= nil
			end,
			w = size,
			h = size,
			tint = function()
				local d = desc()
				return d.tint or (if dim() then theme.tertiary else theme.secondary)
			end,
		},
		ui.text {
			function()
				return desc().glyph or ""
			end,
			hidden = function()
				return desc().glyph == nil
			end,
			text_size = size,
			color = function()
				return desc().tint or theme.secondary
			end,
		},
	}
end

-- A square icon button in the titlebar.
function M.tool(svg: string, on_click: () -> (), size: number?): Node
	return ui.button {
		w = size or 28,
		h = size or 28,
		rounded = 8,
		items = "center",
		justify = "center",
		shrink = 0,
		bg = theme.clear,
		hover = { bg = "#ffffff14" },
		focus = { border = 0 },
		on_click = on_click,
		ui.svg { code = svg, w = 15, h = 15, tint = theme.secondary },
	}
end

-- Empty titlebar space moves the window (a double click zooms it).
function M.drag_space(props: ContainerProps): Node
	props.h_full = true
	props.window_drag = true
	return ui.div(props)
end

-- Six dots, two rows of three: a grip.
function M.dots(): Node
	local function row()
		local out: ContainerProps = { gap = 3, items = "center" }
		for _ = 1, 3 do
			table.insert(out, ui.div { w = 3, h = 3, rounded = 2, bg = "#ffffff99" })
		end
		return ui.row(out)
	end
	return ui.column { gap = 3, items = "center", row(), row() }
end

return M
