-- Wing's tab strip (zterm): 28-high tabs at radius 8, 3 apart, with the
-- icon's 20 tile (radius 5, a hairline, dimmer in a background tab) as far
-- in from the edge as from the top and the name 7 after; the active tab's
-- glass one piece sliding between the tabs (320 ms); under the pointer a
-- tab washes; a bell dot on a background tab.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local txt = require("./text")
local wash = require("./wash")
local icon_button = require("./icon_button")
local panes = require("./panes")
local glass = require("./glass")

export type Tab = { id: string, label: string, icon: icon_mod.Name?, tint: Color?, bell: boolean?, closable: boolean? }
export type Props = {
	id: string,
	tabs: { Tab },
	value: State<string>,
	on_close: ((id: string) -> ())?,
	on_add: (Handler | Action)?,
}

-- An icon on Wing's tile (kit/panes).
local function tile(tab: Tab, dim: () -> boolean): Node
	return panes.tile({ icon = tab.icon or "terminal", tint = tab.tint }, dim)
end

return ui.component(function(props: Props): Node
	local items: { Node } = {}
	-- The hover glass slides between the tabs; the active glass stays put.
	-- Each item washes under the pointer (kit/wash), the chosen one excepted.
	local radius = T.radius(8)
	for _, tab in props.tabs do
		local function active(): boolean
			return props.value:get() == tab.id
		end
		table.insert(
			items,
			ui.button {
				id = `{props.id}_{tab.id}`,
				relative = true,
				h = 28,
				pl = "$zeron.space.3",
				pr = if tab.closable then "$zeron.space.4" else "$zeron.space.10",
				gap = "$zeron.space.7",
				items = "center",
				rounded = T.radius_button,
				max_w = 210,
				shrink = 1,
				min_w = 0,
				bg = T.clear,
				hover = { bg = T.clear },
				variants = recipes.strip_tab { selected = active },
				focus = { border = 0 },
				cursor = "default",
				hover_group = true,
				on_click = function()
					props.value:set(tab.id)
				end,
				wash.layer(active, radius),
				glass.active(`{props.id}_glass`, active, T.radius(8)),
				tile(tab, function()
					return not active()
				end),
				txt.text {
					tab.label,
					size = "sm",
					truncate = true,
					shrink = 1,
					min_w = 0,
					line = false,
					color = "inherit",
				},
				tab.bell and ui.div {
					w = 6,
					h = 6,
					rounded = "$zeron.radius.3",
					shrink = 0,
					bg = T.warning,
					hidden = active,
				},
				tab.closable and icon_button {
					icon = "close",
					size = 20,
					icon_size = 12,
					no_ring = true,
					on_click = function()
						if props.on_close then
							props.on_close(tab.id)
						end
					end,
				},
			}
		)
	end
	return ui.row {
		id = props.id,
		h = 28,
		gap = "$zeron.space.3",
		items = "center",
		shrink = 1,
		min_w = 0,
		relative = true,
		items,
		props.on_add
			and icon_button { icon = "plus", size = 28, icon_size = 14, no_ring = true, on_click = props.on_add },
	}
end)
