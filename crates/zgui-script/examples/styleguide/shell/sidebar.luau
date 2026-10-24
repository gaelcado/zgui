-- The sidebar: the pages as a tree, on the window's glass; built from the
-- kit's rows.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local icon_mod = require("@kit/icon")

local M = {}

M.TITLEBAR = 38

local function group(name: string): Node
	return ui.row { h = 28, px = "$zeron.space.12", items = "end", pb = "$zeron.space.6", kit.text.eyebrow(name) }
end

function M.Sidebar(): Node
	local rows: { Node } = {}
	local last = ""
	for _, page in state.PAGES do
		if page.group ~= last then
			if last ~= "" then
				table.insert(rows, ui.div { h = 8 })
			end
			table.insert(rows, group(page.group))
			last = page.group
		end
		table.insert(
			rows,
			kit.row {
				id = "nav_" .. page.id,
				label = page.title,
				icon = page.icon :: icon_mod.Name,
				group = "nav",
				glass = true,
				selected = function()
					return state.page:get() == page.id
				end,
				on_click = ui.set(state.page, page.id),
			}
		)
	end
	-- The column runs the window's full height; the titlebar's band sits
	-- over its top, its seam drawn by the shell.
	return ui.column {
		id = "sidebar",
		w_full = true,
		h_full = true,
		pt = "$zeron.titlebar.height",
		kit.scroll {
			grow = 1,
			w_full = true,
			px = "$zeron.space.8",
			py = "$zeron.space.4",
			fade = 24,
			kit.list { group = "nav", gap = "$zeron.space.1", color = T.glass_hover, rows },
		},
	}
end

return M
