-- The sidebar, straight on the window's glass: the titlebar's controls
-- beside the traffic lights, a search field, pinned favourites, the spaces
-- and their items, and who is signed in.
local kit = require("./kit")
local state = require("../state")
local theme = require("../theme")
local sample = require("@lib/sample")

local M = {}

-- From the window's left edge past the traffic lights (an inset titlebar).
M.LIGHTS = 78
M.WIDTH = 236

-- The sidebar toggle's glyph: a window with its left column filled.
function M.glyph(): Node
	return ui.div {
		w = 16,
		h = 13,
		rounded = ui.raw(3.5, "the sidebar glyph's own drawing"),
		border = 1.5,
		border_color = "$text.secondary",
		ui.div { w = 5, h_full = true, bg = "$text.secondary", rounded = ui.raw(1, "the sidebar glyph's own drawing") },
	}
end

function M.toggle(id: string): Node
	return ui.button {
		id = id,
		variants = kit.icon_button { size = "md" },
		tooltip = "Toggle sidebar (⌘\\)",
		on_click = function()
			state.sidebar:toggle()
		end,
		M.glyph(),
	}
end

local function chrome(): Node
	return ui.row {
		h = 40,
		w_full = true,
		pl = "$shell.lights",
		items = "center",
		gap = "$shell.tight",
		window_drag = true,
		M.toggle("sidebar_toggle"),
		ui.button {
			variants = kit.icon_button { size = "md" },
			tooltip = "Back",
			kit.icon("arrow-left", 16),
		},
		ui.button {
			variants = kit.icon_button { size = "md" },
			tooltip = "Forward",
			kit.icon("arrow-right", 16, "$text.tertiary"),
		},
		ui.div { grow = 1 },
		ui.button {
			id = "new_item",
			variants = kit.icon_button { size = "md" },
			tooltip = "New (⌘N)",
			kit.icon("pen-new-square", 16),
		},
	}
end

local function search(): Node
	return ui.row {
		id = "search",
		variants = kit.field { kind = "search" },
		kit.icon("magnifer", 15, "$text.tertiary"),
		ui.text { "Search or ask", grow = 1, color = "$text.tertiary", text_size = "$font.size.sm" },
		ui.row { variants = kit.key, ui.text { "⌘K" } },
	}
end

local function pins(): Node
	local tiles: { Node } = {}
	for _, pin in sample.pins do
		table.insert(
			tiles,
			ui.button {
				id = pin.id,
				variants = kit.pin,
				tooltip = pin.title,
				kit.icon(pin.icon, 18),
			}
		)
	end
	return ui.grid { w_full = true, cols = #sample.pins, gap = "$shell.xs", tiles }
end

local function item(id: string): Node
	local it = sample.items[id]
	local function chosen(): boolean
		return state.current() == id
	end
	return ui.button {
		id = `item_{id}`,
		variants = kit.row { kind = "item", selected = chosen },
		on_click = function()
			state.open(id)
		end,
		ui.div { variants = kit.tile, kit.icon(sample.icons[it.kind], 13) },
		ui.text {
			it.title,
			grow = 1,
			shrink = 1,
			min_w = 0,
			truncate = true,
			text_size = "$font.size.sm",
			color = function()
				return if chosen() then "$text.primary" else "$text.secondary"
			end,
		},
		ui.text { it.meta, shrink = 0, text_size = "$font.size.xs", color = "$text.tertiary" },
	}
end

local function space(sp: sample.Space): Node
	local folded = ui.state(`fold_{sp.id}`, false)
	local rows: { Node } = {}
	for _, id in sp.items do
		table.insert(rows, item(id))
	end
	return ui.column {
		w_full = true,
		gap = "$shell.hair",
		ui.button {
			id = `space_{sp.id}`,
			variants = kit.row { kind = "section" },
			on_click = function()
				folded:toggle()
			end,
			ui.text {
				sp.title,
				grow = 1,
				text_size = "$font.size.xs",
				weight = "$font.weight.medium",
				color = "$text.tertiary",
			},
			ui.div {
				rotate = function()
					return if folded:get() then -90 else 0
				end,
				kit.icon("alt-arrow-down", 12, "$text.tertiary"),
			},
		},
		ui.show(function()
			return not folded:get()
		end, ui.column { w_full = true, gap = "$shell.hair", rows }),
	}
end

local function footer(): Node
	return ui.row {
		w_full = true,
		h = 36,
		px = "$space.1",
		gap = "$space.2",
		items = "center",
		ui.div {
			w = 22,
			h = 22,
			rounded = "$radius.full",
			bg = "$shell.selected",
			items = "center",
			justify = "center",
			ui.text { "g", text_size = "$font.size.xs", weight = "$font.weight.semibold" },
		},
		ui.text { "garl", grow = 1, text_size = "$font.size.sm", color = "$text.secondary" },
		ui.button {
			id = "theme_toggle",
			variants = kit.icon_button { size = "sm" },
			tooltip = "Light or dark",
			on_click = function()
				state.dark:toggle()
			end,
			ui.show(function()
				return state.dark:get()
			end, kit.icon("sun", 15)),
			ui.show(function()
				return not state.dark:get()
			end, kit.icon("moon", 15)),
		},
		ui.button {
			variants = kit.icon_button { size = "sm" },
			tooltip = "Settings",
			kit.icon("settings", 15),
		},
	}
end

function M.view(): Node
	local spaces: { Node } = {}
	for _, sp in sample.spaces do
		table.insert(spaces, space(sp))
	end
	-- The column clips a fixed-width sidebar as it eases shut, so nothing
	-- in it reflows on the way.
	return ui.column {
		id = "sidebar",
		w = ui.tween(state.sidebar, { from = 0, to = M.WIDTH, duration = 220, ease = "outQuart" }),
		h_full = true,
		shrink = 0,
		overflow = "hidden",
		ui.column {
			w = M.WIDTH,
			h_full = true,
			shrink = 0,
			px = "$shell.sm",
			pb = "$shell.xs",
			gap = "$space.3",
			chrome(),
			search(),
			pins(),
			ui.scroll {
				grow = 1,
				w_full = true,
				ui.column { w_full = true, gap = "$shell.md", spaces },
			},
			footer(),
		},
	}
end

-- The theme follows the toggle.
ui.effect(function()
	ui.theme.set(if state.dark:get() then theme.dark else theme.light)
end)

return M
