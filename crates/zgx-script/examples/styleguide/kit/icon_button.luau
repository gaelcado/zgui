-- A square button holding one icon: toolbars, row actions, window chrome.
-- `button` with an icon and no label is the same control; this one takes
-- the icon's name directly and defaults to the ghost look. Its look is
-- `recipes.icon_button`.
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local glass = require("./glass")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	class: string?,
	icon: icon_mod.Name,
	-- 28 (toolbar), the control height, or any number.
	size: number?,
	icon_size: number?,
	variant: VariantOption<typeof(recipes.icon_button), "tone">?,
	color: Color?,
	disabled: types.Cond?,
	selected: types.Cond?,
	on_click: (Handler | Action)?,
	on_hover: ((inside: boolean) -> ())?,
	rounded: Num?,
	no_ring: boolean?,
	ref: Ref?,
	-- An accessible name (tooltips and tests read it).
	label: string?,
}

return ui.component(function(props: Props): Node
	local size = props.size or 28
	-- Wing's press give: 0.985 on press, back with a little spring.
	local ref = props.ref or ui.ref()
	local press, release = glass.press(ref)
	return ui.button {
		id = props.id,
		class = props.class,
		ref = ref,
		on_press = press,
		on_release = release,
		variants = recipes.icon_button {
			tone = props.variant or "ghost",
			on = if props.selected ~= nil
				then function()
					return types.on(props.selected)
				end
				else false,
			ring = not props.no_ring,
		},
		w = size,
		h = size,
		rounded = props.rounded,
		disabled = props.disabled,
		on_click = props.on_click,
		on_hover = props.on_hover,
		label = props.label,
		icon {
			name = props.icon,
			size = props.icon_size or math.floor(size * 0.55 + 0.5),
			-- The button's colour, as it changes with hover and selection.
			color = props.color or "currentColor",
		},
	}
end)
