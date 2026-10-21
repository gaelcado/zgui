-- The titlebar: the tab strip (each tab an icon per pane and a name),
-- the slot a dragged pane would open in, and the tools.
local theme = require("../theme")
local icons = require("../icons")
local state = require("../state")
local sessions = require("../sessions")
local actions = require("../actions")
local sidebar = require("./sidebar")
local controls = require("./controls")
local menu = require("./menu")
local layout = require("@lib/layout")

local tabs, active, focus = state.tabs, state.active, state.focus
local dragging, tab_drop, tab_slot = state.dragging, state.tab_drop, state.tab_slot

-- A pane's icon in a tab: on a little tile of its own, tinted for agents.
local function badge(pane: string, dim: () -> boolean): Node
	local desc = function()
		return sessions.describe(pane)
	end
	return ui.row {
		w = 20,
		h = 20,
		shrink = 0,
		rounded = 5,
		items = "center",
		justify = "center",
		bg = function()
			local tint = desc().tint
			if tint then
				return tint .. (if dim() then "1f" else "2e")
			end
			return if dim() then "#ffffff0d" else "#ffffff17"
		end,
		border = 1,
		border_color = function()
			local tint = desc().tint
			return if tint then tint .. "33" else "#ffffff0f"
		end,
		controls.glyph(desc, 12, dim),
	}
end

-- More panes than fit: "+3" on a tile like the icons'.
local function more_badge(count: number, dim: () -> boolean): Node
	return ui.row {
		h = 20,
		min_w = 20,
		px = 5,
		shrink = 0,
		rounded = 5,
		items = "center",
		justify = "center",
		bg = function()
			return if dim() then "#ffffff0d" else "#ffffff17"
		end,
		border = 1,
		border_color = "#ffffff0f",
		ui.text {
			`+{count}`,
			text_size = 10.5,
			weight = 600,
			color = function()
				return if dim() then theme.tertiary else theme.secondary
			end,
		},
	}
end

-- A tab's icon: a pane's, or the count of those that do not fit.
type Badge = { key: string, pane: string?, more: number? }

-- A tab shows an icon per pane, three at most: past that, two and "+n".
local function tab_slots(id: string): State<{ Badge }>
	return ui.computed(function()
		local root: layout.Tree? = nil
		for _, tab in tabs:get() do
			if tab.id == id then
				root = tab.root
			end
		end
		local panes = if root then layout.leaves(root) else {}
		local slots: { Badge } = {}
		for i, pane in panes do
			if #panes > 3 and i == 3 then
				table.insert(slots, { key = "more", more = #panes - 2 })
				break
			end
			table.insert(slots, { key = pane, pane = pane })
		end
		return slots
	end)
end

-- A tab's icons, `dim` while it is not active.
local function badges(id: string, dim: () -> boolean): Node
	return ui.each(tab_slots(id), function(slot: Badge)
		if slot.more then
			return more_badge(slot.more, dim)
		end
		return badge(slot.pane or "", dim)
	end, {
		key = function(slot: Badge)
			return if slot.more then `more{slot.more}` else slot.key
		end,
	})
end

local function never(): boolean
	return false
end

-- A pane's name, "Terminal" until it has one.
local function name_of(pane: string?): string
	local name = sessions.describe(pane).name
	return if name ~= "" then name else "Terminal"
end

local M = {}

-- What follows the pointer while dragging a tab or a pane: the tab as it
-- shows active in the strip (a pane alone, its own icon). Blurred behind,
-- as the strip's glass is, so it reads over a terminal.
function M.chip(pane: string?, tab: string?): Node
	local shown = if tab then badges(tab, never) else (if pane then badge(pane, never) else nil)
	return ui.row {
		h = 28,
		pl = 3,
		pr = 10,
		gap = 7,
		items = "center",
		rounded = 8,
		max_w = 210,
		font = theme.font,
		bg = theme.wash,
		backdrop_blur = 24,
		border = 1,
		border_color = theme.line,
		ui.row { gap = 3, shrink = 0, items = "center", shown },
		ui.text {
			function()
				return name_of(pane)
			end,
			shrink = 1,
			min_w = 0,
			text_size = 12.5,
			truncate = true,
			color = theme.text,
		},
	}
end

local function tab_button(id: string): Node
	local function pane(): string?
		return (focus:get())[id]
	end
	local function is_active()
		return active:get() == id
	end
	local function hovered()
		return state.hovered_tab:get() == id
	end
	return ui.row {
		h = 28,
		-- The icons' tiles sit as far in from the tab's edge as from its
		-- top; the name, without a tile, a little more.
		pl = 3,
		pr = 10,
		gap = 7,
		items = "center",
		rounded = 8,
		max_w = 210,
		shrink = 1,
		cursor = "default",
		-- Where it was while dragged: a dim slot.
		opacity = function()
			local d = dragging:get()
			return if d.kind == "tab" and d.id == id then 0.35 else 1
		end,
		bg = function()
			if tab_drop:get() == id then
				return "#ffffff1f"
			end
			if is_active() then
				return theme.wash
			end
			return if hovered() then theme.hover else theme.clear
		end,
		border = 1,
		border_color = function()
			return if is_active() then theme.line else theme.clear
		end,
		on_click = function()
			actions.activate(id)
		end,
		context_menu_style = menu.STYLE,
		context_menu_below = true,
		context_menu = function()
			local others = #tabs:peek() > 1
			local items = {
				menu.entry("New Tab", function()
					actions.new_tab(sessions.cwd_of((focus:peek())[id]))
				end),
				menu.separator(),
				menu.entry("Close Tab", function()
					actions.close_tab(id)
				end),
			}
			if others then
				table.insert(
					items,
					menu.entry("Close Other Tabs", function()
						for _, other in tabs:peek() do
							if other.id ~= id then
								actions.close_tab(other.id)
							end
						end
					end)
				)
			end
			return items
		end,
		on_hover = function(inside)
			if inside then
				state.hovered_tab:set(id)
			elseif state.hovered_tab:peek() == id then
				state.hovered_tab:set("")
			end
		end,
		on_drag = function(): state.Payload
			dragging:set { kind = "tab", id = id }
			return { kind = "tab", id = id }
		end,
		drag_preview = function()
			return M.chip(pane(), id)
		end,
		on_drag_end = function()
			dragging:set {}
			state.drop:set {}
		end,
		drop_when = function(payload: state.Payload)
			return payload.kind == "pane" or (payload.kind == "tab" and payload.id ~= id)
		end,
		-- A tab takes this one's place as it passes. A pane over its middle
		-- marks it (dropping moves the pane in); near an edge, a new tab
		-- opens up beside it.
		on_drag_over = function(payload: state.Payload, e)
			if payload.kind == "tab" then
				actions.reorder(payload.id, id, if e.local_x < e.w / 2 then "before" else "after")
				return
			end
			local edge = math.min(28, e.w * 0.3)
			if e.local_x < edge then
				actions.show_slot(payload.id, id)
			elseif e.local_x > e.w - edge then
				local list = tabs:peek()
				local after = ""
				for i, other in list do
					if other.id == id and list[i + 1] then
						after = list[i + 1].id
					end
				end
				actions.show_slot(payload.id, after)
			else
				actions.hide_slot()
				if tab_drop:peek() ~= id then
					tab_drop:set(id)
				end
			end
		end,
		on_drag_leave = function()
			if tab_drop:peek() == id then
				tab_drop:set("")
			end
		end,
		on_drop = function(payload: state.Payload)
			tab_drop:set("")
			if payload.kind == "pane" and not actions.commit_slot() then
				actions.move_pane_to_tab(payload.id, id)
			end
		end,
		ui.row {
			gap = 3,
			shrink = 0,
			items = "center",
			badges(id, function()
				return not is_active()
			end),
		},
		ui.text {
			function()
				return name_of(pane())
			end,
			shrink = 1,
			min_w = 0,
			text_size = 12.5,
			truncate = true,
			color = function()
				return if is_active() then theme.text else theme.secondary
			end,
		},
		-- The bell rang in a pane of a background tab.
		ui.div {
			hidden = function()
				local p = pane()
				return is_active() or p == nil or sessions.is_browser(p) or not ui.term(p).bell
			end,
			w = 6,
			h = 6,
			rounded = 3,
			bg = theme.bell,
			shrink = 0,
		},
	}
end

-- The tab strip's items: the tabs, and the slot a dragged pane would open
-- in (`slot` is that pane).
type Item = { id: string, slot: string? }
local strip = ui.computed(function(): { Item }
	local list = tabs:get()
	local s = tab_slot:get()
	local out: { Item } = {}
	for _, tab in list do
		if s.pane and tab.id == s.before then
			table.insert(out, { id = "slot", slot = s.pane })
		end
		table.insert(out, { id = tab.id })
	end
	if s.pane and (s.before == "" or #out == #list) then
		table.insert(out, { id = "slot", slot = s.pane })
	end
	return out
end)

-- Where a dragged pane would open as a tab: a ghost of that tab, opening
-- up so the tabs after it slide over.
local function slot_tab(pane: string): Node
	return ui.row {
		h = 28,
		w = 132,
		pl = 3,
		pr = 10,
		gap = 7,
		shrink = 0,
		items = "center",
		rounded = 8,
		overflow = "hidden",
		bg = "#ffffff0f",
		border = 1,
		border_color = "#ffffff29",
		on_mount = function(el)
			anime.animate(el, { width = { 0, 132 }, opacity = { 0, 1 }, duration = 200, ease = "outQuint" })
		end,
		drop_when = function(payload: state.Payload)
			return payload.kind == "pane"
		end,
		on_drop = function()
			actions.commit_slot()
		end,
		badge(pane, never),
		ui.text {
			function()
				return name_of(pane)
			end,
			shrink = 1,
			min_w = 0,
			text_size = 12.5,
			truncate = true,
			color = theme.secondary,
		},
	}
end

function M.Titlebar(): Node
	return ui.row {
		w_full = true,
		h = theme.titlebar,
		items = "center",
		-- A pane anywhere else on it (the new tab button, the tools) opens as
		-- a tab where the slot shows, at the end if none does yet.
		drop_when = function(payload: state.Payload)
			return payload.kind == "pane"
		end,
		on_drag_over = function(payload: state.Payload)
			if not (tab_slot:peek()).pane then
				actions.show_slot(payload.id, "")
			end
		end,
		on_drop = function()
			actions.commit_slot()
		end,
		gap = 3,
		pr = 6,
		-- Room for the traffic lights, and some air after them; the open
		-- sidebar holds them instead, and its toggle comes here when closed.
		controls.drag_space {
			w = function()
				return if state.sidebar:get() then 6 else 80
			end,
			shrink = 0,
		},
		ui.show(function()
			return not state.sidebar:get()
		end, sidebar.Toggle()),
		ui.row {
			gap = 3,
			items = "center",
			shrink = 1,
			min_w = 0,
			ui.each(strip, function(item: Item)
				if item.slot then
					return slot_tab(item.slot)
				end
				return tab_button(item.id)
			end, {
				key = function(item: Item)
					return item.id
				end,
				-- A reorder slides the tabs from where they were.
				animate = { duration = 240, ease = "outQuint" },
			}),
		},
		controls.tool(icons.plus, function()
			actions.new_tab(sessions.cwd_of(actions.current()))
		end),
		-- Dropping a pane here gives it a tab of its own.
		controls.drag_space {
			grow = 1,
			min_w = 16,
			drop_when = function(payload: state.Payload)
				return payload.kind == "pane"
			end,
			on_drag_over = function(payload: state.Payload)
				actions.show_slot(payload.id, "")
			end,
			on_drop = function()
				actions.commit_slot()
			end,
		},
		controls.tool(icons.split_right, function()
			actions.split("row")
		end),
		controls.tool(icons.split_down, function()
			actions.split("column")
		end),
		controls.tool(icons.browser, function()
			actions.split("row", "browser")
		end),
	}
end

return M
