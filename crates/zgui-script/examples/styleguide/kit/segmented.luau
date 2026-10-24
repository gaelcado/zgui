-- A segmented control: options in a well, a pill under the selected one,
-- where it is; each option washes under the pointer (kit/wash). Left
-- and Right move the selection.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local wash = require("./wash")
local recipes = require("./recipes")

export type Option = { id: string, label: string?, icon: icon_mod.Name?, tip: string? }
export type Props = {
	id: string,
	options: { Option },
	value: State<string>,
	size: VariantOption<typeof(recipes.segment), "size">?,
	-- Options share the width equally.
	even: boolean?,
	grow: number?,
	disabled: boolean?,
	on_change: ((id: string) -> ())?,
}

return ui.component(function(props: Props): Node
	local small = props.size == "sm"
	local h = if small then 24 else 28
	local items: { Node } = {}
	local function choose(id: string)
		if props.value:peek() ~= id then
			props.value:set(id)
			if props.on_change then
				props.on_change(id)
			end
		end
	end
	-- Each item washes under the pointer (kit/wash), the chosen one excepted.
	local radius = T.radius_md
	for i, option in props.options do
		local function on(): boolean
			return props.value:get() == option.id
		end
		items[i] = ui.button {
			id = `{props.id}_{option.id}`,
			relative = true,
			hover_group = true,
			variants = recipes.segment {
				size = if small then "sm" else "md",
				labelled = option.label ~= nil,
				even = props.even == true,
				on = on,
			},
			-- An icon alone is square.
			w = if option.label then nil else h + 4,
			-- A tab of the strip's tab list: one Tab stop, the arrows, Home and
			-- End move the focus (zgui's focus group), and the choice follows.
			role = "tab",
			selected = on,
			on_click = function()
				choose(option.id)
			end,
			on_focus = function()
				choose(option.id)
			end,
			-- The chosen one's pill, where it is.
			wash.layer(on, radius),
			wash.selection(on, T.radius_md, T.raised, T.shadow_sm),
			option.icon and icon { name = option.icon, size = if small then 13 else 14, color = "currentColor" },
			option.label and txt.text {
				option.label,
				size = if small then "xs" else "sm",
				weight = "medium",
				line = false,
				color = "inherit",
			},
		}
	end
	return ui.row {
		id = props.id,
		variants = recipes.segmented { size = if small then "sm" else "md" },
		role = "tablist",
		grow = props.grow,
		disabled = props.disabled,
		items,
	}
end)
