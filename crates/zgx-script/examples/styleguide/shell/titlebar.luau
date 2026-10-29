-- The workbench's titlebar, Zeron's unified titlebar (kit/titlebar): the
-- window controls (the sidebar toggle, Back and Forward through the pages
-- visited), no title (each page names itself), the appearance button that
-- ends the canvas's stretch, and the inspector's toggle anchored at the
-- right edge over its column. The whole band moves the window.
--
-- Appearance (palette): the theme, its dark or light variant, the accent,
-- the material, the density and reduced motion, in one card.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local look = require("@kit/look")
local tb = require("@kit/titlebar")
local menu = require("@kit/menu")
local panel_shell = require("@kit/panel_shell")

local M = {}

M.HEIGHT = tb.HEIGHT

local appearance_open = ui.state("appearance_open", false)

-- The themes by family, as menu rows with a check on the current one.
local function theme_list(): Node
	local entries: { menu.Entry } = {}
	local family = ""
	for _, t in state.THEMES do
		if t.family ~= family then
			family = t.family
			table.insert(entries, { heading = t.family_name })
		end
		table.insert(
			entries,
			{
				id = `theme_pick_{t.id}`,
				label = t.name,
				icon = if t.kind == "dark" then "moon" else "sun",
				checked = function()
					return look.showing(t.id)
				end,
				on_click = function()
					look.choose(state.look, t.id)
				end,
			} :: menu.Item
		)
	end
	local rows = menu.list(entries, function() end)
	return kit.scroll { id = "theme_menu", w_full = true, h = 216, fade = 12, rows }
end

local function field(label: string, control: Node): Node
	return ui.row {
		w_full = true,
		h = 32,
		px = "$zeron.space.8",
		gap = "$zeron.space.12",
		items = "center",
		kit.text.text { label, size = "sm", color = T.secondary, grow = 1, line = false },
		control,
	}
end

local function accent_swatches(): Node
	return look.swatches(state.look, "accent")
end

local function appearance(): Node
	return kit.popover {
		id = "appearance",
		open = appearance_open,
		w = 300,
		p = "$zeron.space.4",
		gap = "$zeron.space.2",
		anchor = tb.button {
			id = "appearance_toggle",
			label = "Appearance",
			icon = "palette",
			on = function()
				return appearance_open:get()
			end,
			on_click = ui.toggle(appearance_open),
		},
		ui.row { h = 26, px = "$zeron.space.8", items = "end", pb = "$zeron.space.4", kit.text.eyebrow("Theme") },
		theme_list(),
		kit.divider { inset = "$zeron.space.8" },
		field(
			"Variant",
			kit.segmented {
				id = "theme",
				size = "sm",
				value = state.look.mode :: any,
				options = {
					{ id = "dark", icon = "moon", tip = "Dark variant" },
					{ id = "light", icon = "sun", tip = "Light variant" },
				},
			}
		),
		field(
			"Material",
			kit.segmented {
				id = "material",
				size = "sm",
				value = state.look.surface :: any,
				options = {
					{ id = "theme", label = "Theme", tip = "The theme's own surfaces" },
					{ id = "frosted", label = "Frosted", tip = "The window's blur shows through" },
					{ id = "opaque", label = "Opaque", tip = "Opaque surfaces" },
				},
			}
		),
		field(
			"Density",
			kit.segmented {
				id = "density",
				size = "sm",
				value = state.density,
				options = { { id = "comfortable", label = "Comfortable" }, { id = "compact", label = "Compact" } },
			}
		),
		field("Reduce motion", kit.toggle { id = "reduced_motion", value = kit.motion.reduced, size = "sm" }),
		kit.divider { inset = "$zeron.space.8" },
		ui.column {
			px = "$zeron.space.8",
			pt = "$zeron.space.4",
			pb = "$zeron.space.8",
			gap = "$zeron.space.8",
			kit.text.text { "Accent", size = "sm", color = T.secondary },
			accent_swatches(),
		},
	}
end

function M.Titlebar(): Node
	local layout = state.layout
	return tb.titlebar {
		id = "titlebar",
		sidebar = state.sidebar,
		on_sidebar = function()
			panel_shell.toggle(layout, "sidebar")
		end,
		on_back = state.back,
		on_forward = state.forward,
		can_back = function()
			return state.can_back:get()
		end,
		can_forward = function()
			return state.can_forward:get()
		end,
		sidebar_w = function()
			return layout.w.sidebar:get()
		end,
		actions = { appearance() },
		files_w = function()
			return layout.w.files:get()
		end,
		anchors = {
			tb.button {
				id = "inspector_toggle",
				label = "Inspector",
				glyph = tb.pane_glyph { open = state.inspector, size = 16 },
				on = function()
					return panel_shell.shown(layout, "files")
				end,
				on_click = function()
					panel_shell.toggle(layout, "files")
				end,
			},
		},
	}
end

return M
