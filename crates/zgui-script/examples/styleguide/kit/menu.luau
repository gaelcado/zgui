-- A menu: items with an icon, a label, a shortcut and a check, in a popover
-- card; Up and Down move, Home and End jump, Enter chooses, Escape closes.
-- (The engine's `menu_item` takes a label only, so the items are the kit's
-- own buttons and the keyboard is handled here.)
local T = require("../theme")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local kbd = require("./kbd")
local frost = require("./frost")
local wash = require("./wash")
local recipes = require("./recipes")

export type Item = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	keys: { string }?,
	detail: string?,
	danger: boolean?,
	disabled: types.Cond?,
	checked: types.Cond?,
	on_click: Handler?,
	-- Shown at 60% and inert: a step under way ("Sync setup in progress").
	faded: boolean?,
}
-- A separator, a section heading, or a note (the account menu's identity
-- line: 11 in the secondary colour, 8 in, 6 over and 4 under).
export type Entry = Item | "-" | { heading: string } | { note: string }
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
}

local M = {}

-- One item, as a row; `focus` moves keyboard focus to it. In a list's
-- `group` it glides: the list's one wash comes to it.
function M.item(item: Item, close: () -> (), check_column: boolean?, group: string?, rows: Rows?): Node
	local has_check = check_column or item.checked ~= nil
	local tone = if item.danger then "danger" else "plain"
	local popover_rows = rows == "popover"
	local node: ContainerProps = {
		id = item.id,
		variants = recipes.menu_item { tone = tone, check = has_check == true, listed = group ~= nil },
		h = if popover_rows then 33 else nil,
		pl = if popover_rows then "$zeron.space.8" else nil,
		gap = if popover_rows then "$zeron.space.10" else nil,
		opacity = if item.faded then 0.6 else nil,
		cursor = if item.faded then "default" else nil,
		disabled = item.disabled,
		on_click = if item.faded
			then nil
			else function()
				close()
				if item.on_click then
					item.on_click()
				end
			end,
		has_check and ui.div {
			w = 14,
			shrink = 0,
			icon {
				name = "check",
				size = 14,
				color = "currentColor",
				variants = recipes.menu_check {
					on = function()
						return types.on(item.checked)
					end,
				},
			},
		},
		item.icon and icon {
			name = item.icon,
			size = if popover_rows then 16 else 15,
			color = "currentColor",
			variants = recipes.menu_icon { tone = tone },
		},
		txt.text {
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
	}
	if group then
		return ui.button(wash.item(group, node))
	end
	return ui.button(node)
end

local function separator(): Node
	return ui.div { h = 1, my = "$zeron.space.4", mx = "$zeron.space.6", bg = T.hairline }
end
local function heading(text: string): Node
	return ui.row { h = 24, px = "$zeron.space.10", items = "end", pb = "$zeron.space.4", txt.eyebrow(text) }
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
function M.list(entries: { Entry }, close: () -> (), rows_cut: Rows?): (Node, (e: KeyEvent) -> boolean)
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
		else
			local item = entry :: Item
			local ref = ui.ref()
			table.insert(refs, ref)
			local node = M.item(item, close, check_column, group, rows_cut)
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
	-- Inside the list zgui's focus group moves the focus (the arrows, round
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
		wash.list { group = group, gap = "$zeron.space.1", color = T.menu_hover, rows },
	},
		on_key
end

-- Zeron's popover motion (kit/popover).
local motion_of = require("./popover")

M.menu = ui.component(function(props: Props): Node
	local function close()
		props.open:set(false)
	end
	local rows, on_key = M.list(props.items, close, props.rows)
	local list: Node = if props.max_h
		then ui.scroll { w_full = true, max_h = props.max_h, fade = { 12, 12 }, fade_overflow = true, rows }
		else rows
	local panel: ContainerProps = {
		id = props.id,
		w = props.w or 240,
		p = T.space(frost.INSET),
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		on_key = on_key,
		list,
	}
	if props.inline then
		return ui.column(panel)
	end
	return ui.popover {
		id = props.id,
		open = props.open,
		anchor = props.anchor,
		label = props.label or "Menu",
		w = props.w or 240,
		p = T.space(frost.INSET),
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		on_key = on_key,
		placement = props.placement,
		-- Each time it opens: 2 down from its trigger, or 4 up from one
		-- under it (popover.rs menu_motion, anchored_menu_above's
		-- MENU_TRAVEL); it leaves toward it by half that.
		enter = motion_of.enter(props.placement, if props.placement and props.placement.side == "top" then 4 else 2),
		exit = motion_of.exit(props.placement, if props.placement and props.placement.side == "top" then 4 else 2),
		list,
	}
end)

return M
