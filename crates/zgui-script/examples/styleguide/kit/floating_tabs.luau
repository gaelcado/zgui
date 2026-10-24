-- The floating tab nav (pull_request_detail.rs): a frosted pill 46 high
-- at radius 23 holding equal segments of 36 at full round, a glass thumb
-- under the chosen one; text and icon blend
-- muted → text under the thumb; the thumb stays where it is and a hover
-- glass marks the chosen segment, each washes under the pointer; ←→ Home End move.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local wash = require("./wash")

export type Tab = { id: string, label: string, icon: icon_mod.Name?, count: number? }
export type Props = { id: string, tabs: { Tab }, value: State<string> }

local M = {}

M.HEIGHT = 46
M.INSET = 2
M.SEGMENT = 36

return ui.component(function(props: Props): Node
	local segments: { Node } = {}
	-- The hover glass slides between the segments; the thumb stays put.
	-- Each item washes under the pointer (kit/wash), the chosen one excepted.
	local radius = T.radius_full
	local function choose(id: string)
		props.value:set(id)
	end
	for i, tab in props.tabs do
		local function on(): boolean
			return props.value:get() == tab.id
		end
		table.insert(
			segments,
			ui.button {
				id = `{props.id}_{tab.id}`,
				relative = true,
				hover_group = true,
				h = M.SEGMENT,
				px = "$zeron.space.14",
				gap = "$zeron.space.6",
				items = "center",
				justify = "center",
				variants = recipes.floating_tab { selected = on },
				on_click = function()
					choose(tab.id)
				end,
				-- A tab of a tab list: one Tab stop, the arrows, Home and End move
				-- the focus (zgui's focus group), and the choice follows it.
				role = "tab",
				selected = on,
				on_focus = function()
					choose(tab.id)
				end,
				wash.layer(on, radius),
				wash.selection(on, T.radius_full, T.glass_active, T.shadow_sm),
				tab.icon and icon { name = tab.icon, size = 14, color = "currentColor" },
				txt.text { tab.label, size = "sm", weight = "medium", line = false, color = "inherit" },
				tab.count and txt.text { tostring(tab.count), size = "xs", color = T.secondary, line = false },
			}
		)
	end
	return ui.row {
		id = props.id,
		h = M.HEIGHT,
		role = "tablist",
		p = T.space(M.INSET),
		variants = recipes.floating_tabs,
		relative = true,
		segments,
	}
end)
