-- A row in a list or a sidebar: an icon, a label, a detail and what sits
-- at its end. Rows of a `group` sit in a `kit.list`, whose one hover wash
-- slides between them; their selection stays where it is. Its look is
-- `recipes.row`.
local T = require("../theme")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local glass = require("./glass")
local wash = require("./wash")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	label: Text,
	icon: icon_mod.Name?,
	-- A coloured dot before the label (a status) instead of an icon.
	dot: Reactive<Color>?,
	detail: Text?,
	-- Under the label (two-line rows).
	description: Text?,
	-- At the end: a count, a shortcut, an action.
	trailing: Child?,
	selected: types.Cond?,
	disabled: types.Cond?,
	-- The `kit.list` this row is in (its hover wash).
	group: string?,
	-- 8 in the sidebar (default), 7 in menus, 10 in the palette.
	radius: Num?,
	-- Wing's glass for hover and selection (the row's surface is the
	-- window's blur) instead of the washes.
	glass: boolean?,
	indent: number?,
	size: VariantOption<typeof(recipes.row), "size">?,
	on_click: (Handler | Action)?,
	context_menu: ((e: PointerEvent) -> { Node }?)?,
	on_hover: ((inside: boolean) -> ())?,
}

return ui.component(function(props: Props): Node
	local radius = props.radius or T.radius_button
	local small = props.size == "sm"
	local two = props.description ~= nil
	local sel = props.selected
	local function on(): boolean
		return types.on(sel)
	end
	local ref = ui.ref()
	-- The layers that paint the hover and the selection, when not the row:
	-- in a list (or on Wing's glass) the wash under the pointer (kit/wash,
	-- instant) and the selection's fill.
	local hover_layer: Node? = nil
	local pill: Node? = nil
	if props.group then
		hover_layer = wash.layer(on, radius)
		pill = wash.selection(on, radius, if props.glass then T.glass_active else T.selected)
	elseif props.glass then
		hover_layer = wash.layer(on, radius)
		pill = glass.active("row_glass", on, radius)
	end
	local layered = props.group ~= nil or props.glass == true
	return ui.button {
		id = props.id,
		ref = ref,
		variants = recipes.row {
			size = if small then "sm" else "md",
			lines = if two then "two" else "one",
			indent = tostring(math.clamp(props.indent or 0, 0, 3)) :: any,
			surface = if layered then "layered" else "plain",
			on = if sel ~= nil then on else false,
		},
		rounded = props.radius,
		disabled = props.disabled,
		on_click = props.on_click,
		on_hover = props.on_hover,
		hover_group = if layered then true else nil,
		relative = if layered then true else nil,
		context_menu = props.context_menu,
		hover_layer,
		pill,
		props.dot and ui.div {
			w = 7,
			h = 7,
			mx = "$zeron.space.4",
			rounded = "$zeron.radius.4",
			bg = props.dot,
			shrink = 0,
		},
		props.icon and icon {
			name = props.icon,
			size = if small then 14 else 16,
			color = "currentColor",
			variants = recipes.row_icon { on = if sel ~= nil then on else false },
		},
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.1",
			txt.text {
				props.label,
				size = if small then "sm" else "md",
				weight = if two then "medium" else "regular",
				truncate = true,
				line = not two,
				-- The row's: muted, full under the pointer or chosen.
				color = "inherit",
			},
			props.description and txt.text { props.description, size = "sm", color = T.secondary, truncate = true },
		},
		props.detail and txt.text { props.detail, size = "sm", color = T.tertiary, line = false, shrink = 0 },
		props.trailing,
	}
end)
