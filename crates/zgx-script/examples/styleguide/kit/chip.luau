-- A chip: a small rounded label in a tone, as a tag, a filter (selectable)
-- or an attachment (dismissible). `badge` is the same at the smallest size,
-- never interactive, for counts and statuses. Its look is `recipes.chip`.
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")

export type Tone = "neutral" | "accent" | "danger" | "warning" | "success" | "info"
export type Variant = VariantOption<typeof(recipes.chip), "variant">
export type Props = {
	id: string?,
	label: Text,
	icon: icon_mod.Name?,
	-- A coloured dot before the label.
	dot: boolean?,
	tone: Tone?,
	variant: Variant?,
	size: VariantOption<typeof(recipes.chip), "size">?,
	mono: boolean?,
	-- A filter chip: clicking toggles `selected`.
	selected: types.Cond?,
	on_click: (Handler | Action)?,
	-- Shows an × that calls this.
	on_remove: Handler?,
	disabled: types.Cond?,
	pill: boolean?,
}

-- The icon and the label's size at each chip size.
local INNER = {
	xs = { text = "micro" :: txt.Size, icon = 10 },
	sm = { text = "xs" :: txt.Size, icon = 12 },
	md = { text = "sm" :: txt.Size, icon = 14 },
}

return ui.component(function(props: Props): Node
	local tone: Tone = props.tone or "neutral"
	local variant: Variant = props.variant or "soft"
	local size = props.size or "sm"
	local inner = if variant == "trigger" then { text = "sm" :: txt.Size, icon = 12 } else INNER[size]
	local height = if variant == "trigger" then 20 elseif size == "xs" then 18 elseif size == "sm" then 22 else 26
	local interactive = props.on_click ~= nil or props.selected ~= nil
	local body: ContainerProps = {
		id = props.id,
		variants = recipes.chip {
			size = size,
			tone = tone,
			variant = variant,
			on = if props.selected ~= nil
				then function()
					return types.on(props.selected)
				end
				else false,
			dot = props.dot == true,
			remove = props.on_remove ~= nil,
			interactive = interactive,
			pill = props.pill ~= false and variant ~= "trigger",
		},
		disabled = props.disabled,
		props.dot and ui.div {
			w = 6,
			h = 6,
			rounded = "$zeron.radius.3",
			bg = recipes.CHIP_TONES[tone].border,
		},
		-- The icon and the label take the chip's colour, as selection
		-- changes it.
		props.icon and icon { name = props.icon, size = inner.icon, color = "currentColor" },
		txt.text {
			props.label,
			size = inner.text,
			weight = "medium",
			mono = props.mono,
			line = false,
			color = "inherit",
		},
		props.on_remove and ui.button {
			variants = recipes.chip_remove,
			w = height - 6,
			h = height - 6,
			on_click = props.on_remove,
			icon { name = "close", size = inner.icon, color = "currentColor" },
		},
	}
	if interactive then
		body.on_click = props.on_click
		return ui.button(body)
	end
	return ui.row(body)
end)
