-- Hoverable rows: a list's rows wash under the pointer, the selected one
-- excepted, as Zeron's do (instant, the engine's hover; no slide and no
-- script). The list scopes the wash's colour (`zeron.list.wash`) to its
-- rows; each row paints it from a layer behind its content, shown while
-- the pointer is over the row (`group_hover`), whatever recipe the row
-- carries. A strip (tabs, a segmented control) is the same with its items.
local T = require("../theme")
local motion = require("./motion")
local recipes = require("./recipes")

export type ListProps = {
	-- The rows' group: a name for the list, kept for the callers' ids.
	group: string,
	id: string?,
	[number]: Child,
	gap: Num?,
	p: Length?,
	px: Length?,
	py: Length?,
	-- A strip or a grid instead of a column.
	direction: ("row" | "column")?,
	flex_wrap: boolean?,
	items: Align?,
	-- `"hidden"`: a strip clips what runs past it.
	overflow: ("hidden" | "visible")?,
	w_full: boolean?,
	w: Length?,
	h: (Length | (() -> Length))?,
	grow: number?,
	min_w: Length?,
	shrink: number?,
	-- The wash (a token, `"$…"`): the hover wash unless set.
	color: Color?,
}

local M = {}

-- `"$zeron.glass.hover"` as a scope's reference, `"{zeron.glass.hover}"`.
local function reference(color: Color?): string?
	if type(color) ~= "string" then
		return nil
	end
	if string.sub(color, 1, 1) == "$" then
		return `\{{string.sub(color, 2)}}`
	end
	return color
end

function M.list(props: ListProps): Node
	local row = props.direction == "row"
	local wash = reference(props.color)
	return ui.div {
		id = props.id,
		direction = if row then "row" else "column",
		flex_wrap = props.flex_wrap,
		w_full = if props.w_full ~= nil then props.w_full elseif props.w then nil else not row,
		w = props.w,
		h = props.h,
		grow = props.grow,
		min_w = props.min_w,
		shrink = props.shrink,
		overflow = props.overflow,
		items = props.items or (if row then "center" else "stretch"),
		gap = props.gap,
		p = props.p,
		px = props.px,
		py = props.py,
		theme = if wash then { ["zeron.list.wash"] = wash } else nil,
		{ table.unpack(props) },
	}
end

-- A fresh group name for a list built more than once (menus, pickers).
local counter = 0
function M.group(prefix: string?): string
	counter += 1
	return `{prefix or "list"}_{counter}`
end

-- The wash behind a row's content: shown under the pointer, not on the
-- selected row. `radius` is the row's.
function M.layer(selected: (State<boolean> | (() -> boolean))?, radius: Num?): Node
	return ui.div {
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		bottom = 0,
		rounded = radius or T.radius_button,
		pointer_events = "none",
		variants = recipes.list_wash { selected = selected or false },
	}
end

-- A row of a list, from its props: a wash under the pointer (not its own
-- hover fill), none on the selected row. Returns the props.
function M.item(_group: string, props: ContainerProps, selected: (State<boolean> | (() -> boolean))?): ContainerProps
	local own: any = props
	own.relative = true
	own.hover_group = true
	if props.hover then
		local styles = table.clone(props.hover :: any)
		styles.bg = nil
		props.hover = styles
	end
	if props.bg == nil and props.variants == nil then
		props.bg = T.clear
	end
	table.insert(own, 1, M.layer(selected, own.rounded))
	return props
end

-- `item` when the caller gave a group, else the props as they are (their
-- own hover).
function M.maybe(group: string?, props: ContainerProps, selected: (() -> boolean)?): ContainerProps
	if group then
		return M.item(group, props, selected)
	end
	return props
end

-- A grouped row's selection: its own fill, easing in and out over 90 ms
-- where it is (no slide).
function M.selection(selected: () -> boolean, radius: Num, fill: Color, shadow: Shadow?): Node
	return ui.div {
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		bottom = 0,
		rounded = radius,
		bg = fill,
		shadow = shadow,
		pointer_events = "none",
		opacity = ui.tween(ui.computed(selected), { from = 0, to = 1, duration = motion.d(90) }),
	}
end

return M
