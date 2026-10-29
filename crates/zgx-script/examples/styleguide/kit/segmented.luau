-- A segmented control: zgx's (`ui.segmented`: a radio group, one Tab
-- stop, the arrows moving the choice), in Zeron's look. Options sit in a
-- well, the chosen one's pill under it, where it is; each option washes
-- under the pointer (kit/wash). An option draws its own segment: an icon,
-- a label, or both.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local wash = require("./wash")
local recipes = require("./recipes")

-- `tip` names an icon alone (its accessible name).
export type Option = { id: string, label: string?, icon: icon_mod.Name?, tip: string? }
export type Props = {
	id: string,
	options: { Option },
	value: State<string>,
	-- The group's accessible name.
	label: string?,
	size: VariantOption<typeof(recipes.segment), "size">?,
	-- Options share the width equally.
	even: boolean?,
	grow: number?,
	disabled: boolean?,
	-- Told the option chosen; `value` may then be read-only (a computed).
	on_change: ((id: string) -> ())?,
}

return ui.component(function(props: Props): Node
	local small = props.size == "sm"
	local h = if small then 24 else 28
	-- With `on_change`, the control holds a choice of its own, following
	-- `value`, and tells each change the user makes.
	local value = props.value
	local on_change = props.on_change
	if on_change then
		local own = ui.use_state(props.value:peek())
		ui.effect(function()
			own:set(props.value:get())
		end)
		ui.effect(function()
			local id = own:get()
			if id ~= props.value:peek() then
				on_change(id)
			end
		end)
		value = own
	end
	local options: { any } = {}
	for i, option in props.options do
		local function on(): boolean
			return value:get() == option.id
		end
		options[i] = {
			value = option.id,
			label = option.label or option.tip or option.id,
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
			-- The chosen one's pill, where it is.
			wash.layer(on, T.radius_md),
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
	return ui.segmented {
		id = props.id,
		label = props.label,
		value = value,
		options = options,
		variants = recipes.segmented { size = if small then "sm" else "md" },
		grow = props.grow,
		disabled = props.disabled,
	}
end)
