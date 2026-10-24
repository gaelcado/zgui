-- Tabs: a strip of labels with an underline under the selected one, or
-- pills; the selection stays where it is, a hover wash slides between the
-- tabs; each washes under the pointer (kit/wash). Left and Right move; a closable tab shows its × on hover.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local badge = require("./badge")
local wash = require("./wash")
local recipes = require("./recipes")

export type Tab = { id: string, label: string, icon: icon_mod.Name?, count: number?, closable: boolean? }
export type Props = {
	id: string,
	tabs: { Tab },
	value: State<string>,
	variant: VariantOption<typeof(recipes.tabs), "variant">?,
	size: VariantOption<typeof(recipes.tab), "size">?,
	on_close: ((id: string) -> ())?,
	grow: number?,
}

return ui.component(function(props: Props): Node
	local pills = props.variant == "pills"
	local small = props.size == "sm"
	local items: { Node } = {}
	local function choose(id: string)
		props.value:set(id)
	end
	-- One hover wash slides between the tabs; the selection stays put.
	-- Each item washes under the pointer (kit/wash), the chosen one excepted.
	local radius = if pills then T.radius_item else T.radius_sm
	for i, tab in props.tabs do
		local function on(): boolean
			return props.value:get() == tab.id
		end
		-- The chosen tab's pill or underline, where it is.
		local indicator = if pills
			then wash.selection(on, T.radius_item, T.selected)
			else ui.div {
				absolute = true,
				left = 0,
				right = 0,
				bottom = 0,
				h = 2,
				rounded = "$zeron.radius.1",
				bg = T.text,
				pointer_events = "none",
				opacity = ui.tween(ui.computed(on), { from = 0, to = 1, duration = motion.d(90) }),
			}
		items[i] = ui.button {
			id = `{props.id}_{tab.id}`,
			relative = true,
			hover_group = true,
			variants = recipes.tab {
				variant = if pills then "pills" else "underline",
				size = if small then "sm" else "md",
				on = on,
			},
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
			indicator,
			tab.icon and icon { name = tab.icon, size = 14, color = "currentColor" },
			txt.text {
				tab.label,
				size = if small then "sm" else "md",
				weight = "medium",
				line = false,
				color = "inherit",
			},
			tab.count and badge { label = tostring(tab.count) },
			tab.closable and ui.button {
				variants = recipes.tab_close,
				-- Not a stop of its own: the arrows go tab to tab.
				focusable = false,
				on_click = function()
					if props.on_close then
						props.on_close(tab.id)
					end
				end,
				icon { name = "close", size = 12, color = "currentColor" },
			},
		}
	end
	return ui.row {
		id = props.id,
		variants = recipes.tabs { variant = if pills then "pills" else "underline" },
		role = "tablist",
		grow = props.grow,
		items,
	}
end)
