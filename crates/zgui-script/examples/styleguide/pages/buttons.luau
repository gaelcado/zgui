-- Buttons: every variant by every state, the sizes, icon buttons and the
-- segmented control.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local button = require("@kit/button")

local VARIANTS: { string } = { "primary", "secondary", "ghost", "danger" }
local STATES: { string } = { "rest", "disabled", "loading", "selected", "icon", "icon only" }
local clicks = ui.state("clicks", 0)
local seg = ui.state("seg", "day")
local seg_icons = ui.state("seg_icons", "list")
local on = ui.state("toggle_btn", false)

local function variants(): Node
	return specimen.matrix {
		id = "button_states",
		columns = VARIANTS,
		rows = STATES,
		col_w = 140,
		build = function(column: string, row: string): Node
			local variant = column :: button.Variant
			if row == "disabled" then
				return kit.button { label = "Button", variant = variant, disabled = true }
			elseif row == "loading" then
				return kit.button { label = "Saving", variant = variant, loading = true, icon = { name = "check" } }
			elseif row == "selected" then
				if variant == "primary" or variant == "danger" then
					return kit.text.text { "—", size = "sm", color = T.tertiary }
				end
				return kit.button { label = "Button", variant = variant, selected = true }
			elseif row == "icon" then
				return kit.button { label = "Button", variant = variant, icon = { name = "plus" } }
			elseif row == "icon only" then
				return kit.button { variant = variant, icon = { name = "plus" } }
			end
			return kit.button { id = `button_{column}`, label = "Button", variant = variant, on_click = ui.add(clicks) }
		end,
	}
end

local function sizes(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell { label = "sm", kit.button { label = "Small", size = "sm", icon = { name = "plus" } } },
		specimen.cell { label = "md", kit.button { label = "Medium", icon = { name = "plus" } } },
		specimen.cell { label = "lg", kit.button { label = "Large", size = "lg", icon = { name = "plus" } } },
		specimen.cell {
			label = "pill",
			kit.button { label = "Send", variant = "primary", pill = true, trailing = { name = "arrow-up" } },
		},
		specimen.cell { label = "trailing", kit.button { label = "Model", trailing = { name = "alt-arrow-down" } } },
		specimen.cell {
			label = "full width",
			ui.div { w = 200, kit.button { label = "Continue", variant = "primary", w_full = true } },
		},
		specimen.cell {
			label = "start-aligned",
			ui.div {
				w = 200,
				kit.button {
					label = "Settings…",
					variant = "ghost",
					icon = { name = "settings" },
					w_full = true,
					justify = "start",
				},
			},
		},
	}
end

local function icon_buttons(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell { label = "ghost 28", kit.icon_button { id = "icon_ghost", icon = "settings" } },
		specimen.cell { label = "secondary", kit.icon_button { icon = "settings", variant = "secondary" } },
		specimen.cell {
			label = "primary",
			kit.icon_button { icon = "arrow-up", variant = "primary", rounded = T.radius_full, size = 32 },
		},
		specimen.cell {
			label = "selected (a toggle)",
			kit.icon_button { id = "icon_toggle", icon = "split-columns", selected = on, on_click = ui.toggle(on) },
		},
		specimen.cell { label = "disabled", kit.icon_button { icon = "settings", disabled = true } },
		specimen.cell { label = "24", kit.icon_button { icon = "close", size = 24 } },
		specimen.cell {
			label = "32",
			kit.icon_button { icon = "microphone", size = 32, rounded = T.radius_full, variant = "secondary" },
		},
		specimen.cell { label = "coloured", kit.icon_button { icon = "trash-bin-minimalistic", color = T.danger } },
	}
end

local function segmented(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell {
			label = "labels",
			kit.segmented {
				id = "seg_labels",
				value = seg,
				options = {
					{ id = "day", label = "Day" },
					{ id = "week", label = "Week" },
					{ id = "month", label = "Month" },
				},
			},
		},
		specimen.cell {
			label = "icons",
			kit.segmented {
				id = "seg_icons",
				value = seg_icons,
				options = {
					{ id = "list", icon = "list" },
					{ id = "grid", icon = "widget" },
					{ id = "cols", icon = "split-columns" },
				},
			},
		},
		specimen.cell {
			label = "small, even widths",
			ui.div {
				w = 240,
				kit.segmented {
					id = "seg_even",
					size = "sm",
					even = true,
					value = seg,
					options = {
						{ id = "day", label = "Day" },
						{ id = "week", label = "Week" },
						{ id = "month", label = "Month" },
					},
				},
			},
		},
		specimen.cell {
			label = "disabled",
			kit.segmented {
				id = "seg_off",
				value = seg,
				disabled = true,
				options = { { id = "day", label = "Day" }, { id = "week", label = "Week" } },
			},
		},
	}
end

return function(): Node
	local page = state.page_by("buttons")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Variants by state",
			note = "Hover, press and focus are live.",
			variants(),
			kit.text.text {
				function()
					return `clicks: {clicks:get()}`
				end,
				id = "button_clicks",
				size = "xs",
				mono = true,
				color = T.tertiary,
			},
		},
		specimen.section {
			title = "Sizes and shapes",
			sizes(),
		},
		specimen.section {
			title = "Icon buttons",
			icon_buttons(),
		},
		specimen.section {
			title = "Segmented control",
			segmented(),
		},
	}
end
