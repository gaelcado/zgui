-- A button: four variants, three sizes, an icon before or after its label.
-- Every state is a prop (disabled, loading, selected) or the engine's
-- (hover, pressed, focus): one node, restyled, never a second drawing.
local T = require("../theme")
local recipes = require("./recipes")
local types = require("./types")
local icon = require("./icon")
local txt = require("./text")
local loaders = require("./loaders")
local glass = require("./glass")

-- Typed from the recipe's axes (kit/recipes.luau).
export type Variant = VariantOption<typeof(recipes.button), "tone">
export type Size = VariantOption<typeof(recipes.button), "size">
export type Props = {
	id: string?,
	class: string?,
	label: Text?,
	icon: icon.Props?,
	trailing: icon.Props?,
	variant: Variant?,
	size: Size?,
	disabled: types.Cond?,
	-- Shows a spinner in the icon's place and disables the button.
	loading: types.Cond?,
	-- A toggle button that is on.
	selected: types.Cond?,
	on_click: (Handler | Action)?,
	-- Layout: a width, a share of the row, or a full-width block.
	w: Reactive<Length>?,
	grow: number?,
	w_full: boolean?,
	-- The label's alignment when the button is wider than its content.
	justify: ("start" | "center")?,
	-- A pill rather than the control radius.
	pill: boolean?,
	-- Window chrome and the like: no focus ring.
	no_ring: boolean?,
	ref: Ref?,
	on_hover: ((inside: boolean) -> ())?,
	on_key: ((e: KeyEvent) -> boolean?)?,
	on_resize: ((size: Size2, el: Element) -> ())?,
}
type Size2 = { w: number, h: number }

local METRIC_H: { [Size]: Length } = { sm = 28, md = T.control, lg = 36 }
local METRICS: { [Size]: { text: txt.Size, icon: number } } = {
	sm = { text = "sm", icon = 14 },
	md = { text = "md", icon = 16 },
	lg = { text = "lg", icon = 16 },
}

return ui.component(function(props: Props): Node
	local variant: Variant = props.variant or "secondary"
	local size: Size = props.size or "md"
	local m = METRICS[size]
	local off = types.either(props.disabled, props.loading)
	local busy = props.loading
	-- The label takes the recipe's colour (a ghost's comes up under the
	-- pointer); a solid's icon too, the others' stay secondary but a ghost's.
	local follows = variant == "primary" or variant == "danger" or variant == "ghost"
	local icon_color: Color = if follows then "currentColor" else T.secondary
	local leading: Node? = nil
	if props.icon then
		local p = table.clone(props.icon)
		p.size = p.size or m.icon
		p.color = p.color or icon_color
		if busy ~= nil then
			p.hidden = busy
		end
		leading = icon(p)
	end
	local trailing: Node? = nil
	if props.trailing then
		local p = table.clone(props.trailing)
		p.size = p.size or m.icon - 2
		p.color = p.color or T.tertiary
		trailing = icon(p)
	end
	local spin: Node? = if busy ~= nil
		then ui.div {
			hidden = types.unless(busy),
			w = m.icon,
			h = m.icon,
			items = "center",
			justify = "center",
			loaders.mini_spinner {
				color = if variant == "primary"
					then T.on_solid
					elseif variant == "danger" then T.on_danger
					else T.secondary,
			},
		}
		else nil
	-- A label-less button is square.
	local square = props.label == nil and props.icon ~= nil
	-- Wing's press give: 0.985 on press, back with a little spring.
	local ref = props.ref or ui.ref()
	local press, release = glass.press(ref)
	local node: ContainerProps = {
		id = props.id,
		class = props.class,
		ref = ref,
		on_press = press,
		on_release = release,
		variants = recipes.button {
			tone = variant,
			size = size,
			square = square,
			pill = props.pill == true,
			ring = not props.no_ring,
			on = if props.selected ~= nil
				then function()
					return types.on(props.selected)
				end
				else false,
			dim = if props.disabled ~= nil
				then function()
					return types.on(props.disabled)
				end
				else false,
		},
		w = if square then METRIC_H[size] else props.w,
		w_full = props.w_full,
		grow = props.grow,
		justify = if square then nil else props.justify,
		disabled = off,
		on_click = props.on_click,
		on_hover = props.on_hover,
		on_key = props.on_key,
		on_resize = props.on_resize,
		spin,
		leading,
		props.label and txt.text { props.label, size = m.text, weight = "medium", color = "inherit", line = false },
		trailing,
	}
	return ui.button(node)
end)
