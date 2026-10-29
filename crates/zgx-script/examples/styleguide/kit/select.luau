-- A select: zgx's (`ui.select`: a button that opens a menu of choices,
-- typing chooses while it is closed, a combobox to assistive technology),
-- in Zeron's look. The button is a settings field (32 high on wash 6% to
-- 10%) or a quiet header button (26, washing under the pointer); the menu
-- is Zeron's frosted card under it, each choice a menu row with a check
-- column, an icon, the label and a muted detail.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local frost = require("./frost")
local recipes = require("./recipes")
local motion_of = require("./popover")

export type Option = {
	value: string,
	label: string,
	-- Its row's id: `{select's id}_{value}` unless set.
	id: string?,
	detail: string?,
	icon: icon_mod.Name?,
	-- Drawn before its label in place of an icon (a theme's palette).
	leading: Node?,
}
export type Look = "field" | "quiet"
export type Props = {
	id: string,
	value: State<string>,
	options: { Option },
	-- Its accessible name.
	label: string?,
	look: Look?,
	-- What the button says: the chosen option's label unless given.
	text: Text?,
	-- The button's face instead of its text and chevron.
	face: { Child }?,
	w: Length?,
	-- The button's gap between its parts, over its look's.
	gap: Num?,
	-- The menu's width (the button's at least) and its height before it
	-- scrolls.
	menu_w: number?,
	max_h: number?,
}

-- Under its button, as Zeron's menus open (popover.rs).
local BELOW: Placement = { side = "bottom", align = "start", offset = 4 }

-- The button's look.
local BUTTON: { [Look]: ContainerProps } = {
	field = {
		variants = recipes.wash { rest = "ink2", hover = "ink4" },
		h = 32,
		px = "$zeron.space.10",
		gap = "$zeron.space.8",
		rounded = T.radius_button,
	},
	quiet = {
		variants = recipes.wash { hover = "ink3" },
		h = 26,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		rounded = T.radius_md,
	},
}

-- A choice's row: the check (there while chosen), the icon, the label, the
-- detail; the menu's wash under the pointer and the keyboard's focus.
local function row(props: Props, option: Option): any
	local function on(): boolean
		return props.value:get() == option.value
	end
	return {
		value = option.value,
		label = option.label,
		id = option.id or `{props.id}_{option.value}`,
		variants = recipes.menu_item { check = true },
		ui.div {
			w = 14,
			shrink = 0,
			icon {
				name = "check",
				size = 14,
				color = "currentColor",
				variants = recipes.menu_check { on = on },
			},
		},
		option.leading
			or option.icon
				and icon { name = option.icon, size = 15, color = "currentColor", variants = recipes.menu_icon {} },
		txt.text {
			option.label,
			size = "md",
			line = false,
			grow = 1,
			shrink = 1,
			min_w = 0,
			truncate = true,
			color = "inherit",
		},
		option.detail and txt.text { option.detail, size = "xs", color = T.tertiary, line = false },
	}
end

return ui.component(function(props: Props): Node
	local look: Look = props.look or "field"
	local options: { any } = {}
	for i, option in props.options do
		options[i] = row(props, option)
	end
	local function chosen(): string
		local v = props.value:get()
		for _, option in props.options do
			if option.value == v then
				return option.label
			end
		end
		return v
	end
	local button = table.clone(BUTTON[look]) :: any
	button.id = props.id
	button.label = props.label or ""
	button.value = props.value
	button.options = options
	button.w = props.w
	button.gap = props.gap or button.gap
	button.items = "center"
	button.focus = { border = 0 }
	button.cursor = "pointer"
	button.placement = BELOW
	button.menu = {
		id = `{props.id}_menu`,
		w = props.menu_w,
		max_h = props.max_h,
		p = T.space(frost.INSET),
		gap = "$zeron.space.1",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		-- 2 down from the button as it opens, back toward it as it closes
		-- (popover.rs menu_motion).
		enter = motion_of.enter(BELOW, 2),
		exit = motion_of.exit(BELOW, 2),
	}
	if props.face then
		for i, child in props.face do
			button[i] = child
		end
	else
		button[1] = txt.text {
			props.text or chosen,
			size = if look == "field" then "md" else "sm",
			weight = if look == "quiet" then "medium" else nil,
			line = false,
			grow = if look == "field" then 1 else nil,
		}
		button[2] = icon { name = "alt-arrow-down", size = 12, color = T.tertiary }
	end
	-- Built up field by field (an `any`): checked against SelectProps, its
	-- union of option lists is too much for luau-lsp to follow.
	local select: (any) -> Node = ui.select :: any
	return select(button)
end)
