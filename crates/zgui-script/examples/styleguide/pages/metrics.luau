-- Space, radius and shadow: the metric tokens, and the rules that use them
-- (concentric corners, control heights, elevation).
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")

local function num(token: string): Node
	return kit.text.text {
		function()
			return tostring(ui.theme.get(token))
		end,
		size = "xs",
		mono = true,
		color = T.tertiary,
		w = 32,
	}
end

local function spacing(): Node
	local rows: { Node } = {}
	for i = 1, 8 do
		local token = `space.{i}`
		table.insert(
			rows,
			ui.row {
				items = "center",
				gap = "$zeron.space.12",
				h = 24,
				kit.text.text { token, size = "xs", mono = true, color = T.secondary, w = 64 },
				num(token),
				ui.div {
					w = "$" .. token,
					h = 16,
					rounded = "$zeron.radius.3",
					bg = T.ink4,
					border = 1,
					border_color = T.strong,
				},
			}
		)
	end
	return ui.column { gap = "$zeron.space.2", rows }
end

-- Concentric corners: an inner radius is the outer minus the padding
-- between them, so the curves share a centre.
local function concentric(): Node
	local function nest(outer: string, pad: string, inner: string, label: string): Node
		return specimen.cell {
			label = label,
			ui.column {
				w = 128,
				h = 88,
				p = "$" .. pad,
				rounded = "$" .. outer,
				bg = T.base,
				border = 1,
				border_color = T.border,
				ui.div { grow = 1, rounded = "$" .. inner, bg = T.raised },
			},
		}
	end
	return ui.row {
		gap = "$zeron.space.24",
		nest("radius.xl", "space.2", "radius.lg", "xl − 8 = lg"),
		nest("radius.lg", "space.1", "radius.md", "lg − 4 = md"),
		nest("zeron.radius.card", "space.1", "zeron.radius.item", "card 12 − 4 = item 7 (menus)"),
		nest("zeron.radius.composer", "space.2", "radius.xl", "composer 26 − 8 ≈ bubble 16"),
	}
end

local function radii(): Node
	local cells: { Node } = {}
	for _, r in
		{
			"radius.sm",
			"radius.md",
			"radius.lg",
			"radius.xl",
			"zeron.radius.card",
			"zeron.radius.composer",
			"radius.full",
		}
	do
		table.insert(
			cells,
			specimen.cell {
				label = r,
				ui.column {
					items = "center",
					gap = "$zeron.space.6",
					ui.div { w = 56, h = 56, rounded = "$" .. r, bg = T.raised, border = 1, border_color = T.border },
					num(r),
				},
			}
		)
	end
	return ui.row { gap = "$zeron.space.20", items = "end", cells }
end

local function shadows(): Node
	local cells: { Node } = {}
	for _, s in { "shadow.sm", "shadow.md", "shadow.lg" } do
		table.insert(
			cells,
			specimen.cell {
				label = s,
				ui.column {
					w = 160,
					h = 96,
					p = "$zeron.space.12",
					rounded = T.radius_card,
					bg = T.overlay,
					border = 1,
					border_color = T.hairline,
					shadow = "$" .. s,
					kit.text.text {
						if s == "shadow.sm"
							then "glass plates"
							elseif s == "shadow.md" then "cards, toasts"
							else "menus, dialogs",
						size = "sm",
						color = T.secondary,
					},
				},
			}
		)
	end
	return ui.row { gap = "$zeron.space.32", p = "$zeron.space.24", rounded = T.radius_card, bg = T.sunken, cells }
end

local function controls(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell {
			label = "sm · zeron.control.sm",
			kit.button { label = "Small", size = "sm" },
			num("zeron.control.sm"),
		},
		specimen.cell { label = "md · control.height", kit.button { label = "Medium" }, num("control.height") },
		specimen.cell {
			label = "lg · zeron.control.lg",
			kit.button { label = "Large", size = "lg" },
			num("zeron.control.lg"),
		},
		specimen.cell { label = "icon button 28", kit.icon_button { icon = "settings" } },
		specimen.cell {
			label = "hit area ≥ 24",
			ui.div {
				w = 24,
				h = 24,
				rounded = "$zeron.radius.4",
				border = 1,
				border_dash = { 3, 3 },
				border_color = T.strong,
			},
		},
	}
end

return function(): Node
	local page = state.page_by("metrics")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Spacing",
			note = "A 4-point scale.",
			spacing(),
		},
		specimen.section {
			title = "Radius",
			radii(),
		},
		specimen.section {
			title = "Concentric corners",
			note = "Inner radius = outer radius − padding.",
			concentric(),
		},
		specimen.section {
			title = "Elevation",
			shadows(),
		},
		specimen.section {
			title = "Control heights",
			note = "Hit areas stay at least 24 points.",
			controls(),
		},
	}
end
