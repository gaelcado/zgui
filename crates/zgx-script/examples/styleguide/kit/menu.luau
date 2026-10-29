-- A menu: items with an icon, a label, a shortcut and a check, in a frosted
-- card. It is zgx's (`ui.menu`): its roles, Up and Down (round past the
-- ends), Home and End, typing a letter to find an item, Enter chooses,
-- Escape closes, and an item closes it before its `on_click` runs. The
-- items are `ui.menu_item`s drawn by the kit (their label names them).
local T = require("../theme")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local kbd = require("./kbd")
local frost = require("./frost")
local wash = require("./wash")
local recipes = require("./recipes")
local toggle_switch = require("./toggle")
-- Zeron's popover motion (kit/popover).
local motion_of = require("./popover")

export type Item = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	keys: { string }?,
	detail: string?,
	-- What it does, under its label at 11 in the secondary colour (the
	-- access modes'): give the row the height for both.
	description: string?,
	danger: boolean?,
	disabled: types.Cond?,
	checked: types.Cond?,
	on_click: Handler?,
	-- Shown at 60% and inert: a step under way ("Sync setup in progress").
	faded: boolean?,
	-- Chosen, it leaves the menu open (a toggle among several).
	keep_open: boolean?,
	-- A switch at its end, which choosing it turns (the view menu's
	-- Compact).
	toggle: State<boolean>?,
	-- Its own height, over the rows' (Zeron's 30-high group rows).
	h: number?,
	-- Its icon's size, over the rows' (a 14 plus).
	icon_size: number?,
}
-- A row opening a card of its own beside the menu (popover.rs
-- nested_menu): the label, a value in the secondary colour (what is chosen
-- in it), a chevron; the card 232 wide, 10 off the row, a heading over its
-- items. It opens as the pointer comes to it, or by the Right arrow.
export type Submenu = {
	id: string,
	label: string,
	icon: icon_mod.Name?,
	value: Text?,
	submenu: { Entry },
	-- Over its items: the label unless set ("" for none).
	heading: string?,
	w: number?,
	open: State<boolean>?,
	-- Its items' checks at their end, as Zeron's view options.
	checks: ("start" | "end")?,
	h: number?,
	-- The chevron's size (12 unless set).
	chevron: number?,
}
-- A separator, a section heading, or a note (the account menu's identity
-- line: 11 in the secondary colour, 8 in, 6 over and 4 under).
export type Entry = Item | Submenu | "-" | { heading: string } | { note: string }
-- How its items are cut: "menu" (30 high, the 15 icon 9 from the label),
-- or "popover" (popover.rs menu_row: 8 by 6 around a 13 label on gpui's
-- 1.618 line, 33 high; the 16 icon 10 from the label).
export type Rows = "menu" | "popover"
export type Props = {
	id: string?,
	open: State<boolean>,
	anchor: Node,
	label: string?,
	items: { Entry },
	w: Length?,
	-- Shown open and anchored in the flow, for specimens: the panel is laid
	-- out where it is written instead of floating.
	inline: boolean?,
	-- A long list scrolls past this height, fading at its edges (12).
	max_h: number?,
	-- Where it opens (under its trigger unless set; `side = "top"` above
	-- it, as the sidebar's account menu does).
	placement: Placement?,
	rows: Rows?,
	-- How far it travels in as it opens (2 down, 4 up from under it,
	-- unless set): Zeron's dropdowns drop 4, its menus 2.
	travel: number?,
	-- Its items' checks at their end rather than their start.
	checks: ("start" | "end")?,
}

local M = {}

-- One item, as a row; `focus` moves keyboard focus to it. In a list's
-- `group` it glides: the list's one wash comes to it.
function M.item(
	item: Item,
	close: () -> (),
	check_column: boolean?,
	group: string?,
	rows: Rows?,
	check_end: boolean?
): Node
	local has_check = check_column or item.checked ~= nil
	local check_slot = has_check
		and ui.div {
			w = 14,
			shrink = 0,
			icon {
				name = "check",
				size = 14,
				color = if check_end then T.secondary else "currentColor",
				variants = recipes.menu_check {
					on = function()
						return types.on(item.checked)
					end,
				},
			},
		}
	local tone = if item.danger then "danger" else "plain"
	local popover_rows = rows == "popover"
	local node: ContainerProps = {
		id = item.id,
		variants = recipes.menu_item { tone = tone, check = has_check == true, listed = group ~= nil },
		h = item.h or (if popover_rows then 33 else nil),
		pl = if popover_rows or check_end then "$zeron.space.8" else nil,
		gap = if popover_rows then "$zeron.space.10" else nil,
		label = item.label,
		-- Heard as a checkbox item, its check drawn below.
		checked = item.checked,
		opacity = if item.faded then 0.6 else nil,
		cursor = if item.faded then "default" else nil,
		disabled = item.disabled,
		on_click = if item.faded
			then nil
			else function()
				if not item.keep_open then
					close()
				end
				if item.toggle then
					item.toggle:toggle()
				end
				if item.on_click then
					item.on_click()
				end
			end,
		if check_end then nil else check_slot,
		item.icon and icon {
			name = item.icon,
			size = item.icon_size or (if popover_rows then 16 else 15),
			color = "currentColor",
			variants = recipes.menu_icon { tone = tone },
		},
		if item.description
			then ui.column {
				grow = 1,
				shrink = 1,
				min_w = 0,
				txt.text { item.label, size = "md", line = false, truncate = true, color = "inherit" },
				txt.text { item.description, size = "xs", color = T.secondary, line = false, truncate = true },
			}
			else txt.text {
				item.label,
				size = "md",
				line = false,
				grow = 1,
				shrink = 1,
				min_w = 0,
				truncate = true,
				color = "inherit",
			},
		item.detail and txt.text { item.detail, size = "xs", color = T.tertiary, line = false },
		item.keys and kbd(table.clone(item.keys) :: kbd.Props),
		if check_end then check_slot else nil,
		-- The switch shows the state; the row turns it.
		item.toggle and ui.div {
			shrink = 0,
			pointer_events = "none",
			toggle_switch { value = item.toggle, size = "lg" },
		} or nil,
	}
	-- A row's props (the wash's too), on an item: its label a plain string.
	local props = (if group then wash.item(group, node) else node) :: any
	props.keep_open = item.keep_open
	return ui.menu_item(props :: MenuItemProps)
end

-- A hairline from edge to edge of the card, 2 over and under it
-- (popover.rs menu_separator).
local function separator(): Node
	return ui.div { h = 1, shrink = 0, my = "$zeron.space.2", mx = T.pull(frost.INSET), bg = T.hairline }
end
-- A section's heading (menu_heading): 10 medium in capitals, tracked out
-- (0.1em), the secondary colour, 8 in, 6 over and 4 under.
local function heading(text: string): Node
	return ui.row {
		px = "$zeron.space.8",
		pt = "$zeron.space.6",
		pb = "$zeron.space.4",
		shrink = 0,
		txt.text {
			string.upper(text),
			literal = true,
			size = "micro",
			weight = "medium",
			color = T.secondary,
			letter_spacing = 1,
			line = false,
		},
	}
end
M.separator = separator
M.heading = heading

-- The card a menu, a context menu or a nested menu is drawn on
-- (popover.rs popover_card): the frost, a hairline, radius 12, 4 in, its
-- rows 2 apart.
M.CARD = {
	p = T.space(frost.INSET),
	gap = "$zeron.space.2",
	rounded = T.radius_card,
	bg = T.frost,
	backdrop_blur = frost.BLUR,
	border = 1,
	border_color = T.border,
	shadow = T.float_shadow,
	color = T.text,
}
local function card(props: { [any]: any }): { [any]: any }
	local out = table.clone(M.CARD) :: { [any]: any }
	for k, v in props do
		out[k] = v
	end
	return out
end
M.card = card

-- A nested menu (popover.rs nested_menu): its row, the card beside it.
function M.nested(entry: Submenu, close: () -> (), rows_cut: Rows?, group: string?): Node
	local open = entry.open or ui.use_state(false)
	local inner, _ = M.list(entry.submenu, close, rows_cut, entry.checks == "end")
	local title = if entry.heading == nil then entry.label else entry.heading
	local row: ContainerProps = {
		id = entry.id,
		variants = recipes.menu_item { listed = group ~= nil },
		h = entry.h or 30,
		pl = "$zeron.space.8",
		gap = "$zeron.space.10",
		label = entry.label,
		-- Lit while its card is up.
		bg = function()
			return if open:get() then T.menu_hover else T.clear
		end,
		entry.icon and icon {
			name = entry.icon,
			size = 16,
			color = "currentColor",
			variants = recipes.menu_icon {},
		} or nil,
		txt.text { entry.label, literal = true, size = "md", line = false, grow = 1, color = "inherit" },
		entry.value and txt.text { entry.value, size = "md", color = T.secondary, line = false } or nil,
		icon { name = "alt-arrow-right", size = entry.chevron or 12, color = T.secondary },
	}
	local trigger = ui.menu_item((if group then wash.item(group, row) else row) :: any)
	return ui.submenu(card {
		id = `{entry.id}_menu`,
		open = open,
		label = entry.label,
		w = entry.w or 232,
		-- 10 beside its row: the card's inset and 6.
		placement = { offset = frost.INSET + 6 },
		enter = motion_of.enter(nil, 2),
		trigger = trigger,
		title ~= "" and heading(title) or nil,
		inner,
	} :: any)
end
local function note(text: string): Node
	return ui.row {
		w_full = true,
		px = "$zeron.space.8",
		pt = "$zeron.space.6",
		pb = "$zeron.space.4",
		txt.text {
			text,
			literal = true,
			size = "xs",
			color = T.secondary,
			-- gpui's 1.618 line at 11.
			line_height = ui.raw(18, "gpui's default line, 1.618 at 11"),
			truncate = true,
			min_w = 0,
			shrink = 1,
		},
	}
end

-- The panel's rows, and arrow-key movement between the enabled items.
function M.list(
	entries: { Entry },
	close: () -> (),
	rows_cut: Rows?,
	check_end: boolean?
): (Node, (e: KeyEvent) -> boolean)
	local refs: { Ref } = {}
	local rows: { Node } = {}
	local check_column = false
	local group = wash.group("menu")
	for _, entry in entries do
		if type(entry) == "table" and (entry :: any).checked ~= nil then
			check_column = true
		end
	end
	for _, entry in entries do
		if entry == "-" then
			table.insert(rows, separator())
		elseif type(entry) == "table" and (entry :: any).heading then
			table.insert(rows, heading((entry :: any).heading))
		elseif type(entry) == "table" and (entry :: any).note then
			table.insert(rows, note((entry :: any).note))
		elseif type(entry) == "table" and (entry :: any).submenu then
			local ref = ui.ref()
			table.insert(refs, ref)
			table.insert(rows, ui.div { ref = ref, w_full = true, M.nested(entry :: Submenu, close, rows_cut, group) })
		else
			local item = entry :: Item
			local ref = ui.ref()
			table.insert(refs, ref)
			local node = M.item(item, close, check_column and not check_end, group, rows_cut, check_end)
			-- The row carries the ref; the item is a button already.
			table.insert(rows, ui.div { ref = ref, w_full = true, node })
		end
	end
	local function focused(): number
		for i, ref in refs do
			local el = ref:peek()
			if el and (el :: any).focused then
				return i
			end
		end
		return 0
	end
	local function focus(i: number)
		local n = #refs
		if n == 0 then
			return
		end
		local j = ((i - 1) % n) + 1
		local el = refs[j]:peek()
		if el then
			el:focus()
		end
	end
	-- Inside the list zgx's focus group moves the focus (the arrows, round
	-- past the ends, Home and End); from the card, before anything in it has it, Down lands on
	-- the first item and Up on the last.
	local function on_key(e: KeyEvent): boolean
		if #refs == 0 or focused() ~= 0 then
			return false
		end
		if e.key == "ArrowDown" or e.key == "Home" then
			focus(1)
			return true
		elseif e.key == "ArrowUp" or e.key == "End" then
			focus(#refs)
			return true
		end
		return false
	end
	return ui.column {
		w_full = true,
		items = "stretch",
		focus_group = "vertical",
		-- Past the last item, the first, as a menu's arrows go.
		focus_wrap = true,
		-- Rows 2 apart (popover.rs MENU_GAP).
		wash.list { group = group, gap = "$zeron.space.2", color = T.menu_hover, rows },
	},
		on_key
end

M.menu = ui.component(function(props: Props): Node
	local function close()
		props.open:set(false)
	end
	local function list(): (Node, (e: KeyEvent) -> boolean)
		local rows, on_key = M.list(props.items, close, props.rows, props.checks == "end")
		return if props.max_h
			then ui.scroll { w_full = true, max_h = props.max_h, fade = { 12, 12 }, fade_overflow = true, rows }
			else rows,
			on_key
	end
	if props.inline then
		local rows, on_key = list()
		local panel: ContainerProps = card {
			id = props.id,
			w = props.w or 240,
			on_key = on_key,
			rows,
		} :: any
		return ui.column(panel)
	end
	local travel = props.travel or (if props.placement and props.placement.side == "top" then 4 else 2)
	return ui.menu {
		id = props.id,
		open = props.open,
		anchor = props.anchor,
		label = props.label or "Menu",
		w = props.w or 240,
		p = M.CARD.p,
		rounded = M.CARD.rounded,
		bg = M.CARD.bg,
		backdrop_blur = M.CARD.backdrop_blur,
		border = M.CARD.border,
		border_color = M.CARD.border_color,
		shadow = M.CARD.shadow,
		color = M.CARD.color,
		placement = props.placement,
		-- Each time it opens: 2 down from its trigger, or 4 up from one
		-- under it (popover.rs menu_motion, anchored_menu_above's
		-- MENU_TRAVEL); it leaves toward it by half that.
		enter = motion_of.enter(props.placement, travel),
		exit = motion_of.exit(props.placement, travel),
		-- Its rows, built as it opens: a closed menu (every row's, every
		-- picker's) costs its trigger alone.
		build = function(): Node
			return (list())
		end,
	}
end)

return M
