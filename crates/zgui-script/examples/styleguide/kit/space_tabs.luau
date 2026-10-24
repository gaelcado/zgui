-- The tabs layouts' topbar (Tern's, Rex's): beside the traffic lights, the
-- sidebar toggle, the project, the spaces (a tab is a named group of
-- panes) and +, then search and settings. The window drags from the bar.
-- The app gives it the spaces and what each action does.
--
-- A space is Wing's tab (zterm): 28 high at radius 8, its panes' glyphs on
-- 20 tiles 3 in from its edge (three at most, else two and "+n"), dimmer
-- while it is not active, its name 7 after; tabs 3 apart. The active tab's
-- glass is one piece sliding between tabs (320 ms); under the pointer a
-- tab washes. A space's close shows under the pointer (Wing's close from
-- the menu alone); two presses rename it in place, as does its menu.
-- Dragged, a space dims where it was and the others slide aside (240 ms
-- quint); a pane dragged by its grip onto a space lights it and moves in,
-- onto the bar's empty end opens a ghost tab and becomes a space of its own.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local wash = require("./wash")
local tb = require("./titlebar")
local sidebar_glyph = require("./sidebar_glyph")
local recipes = require("./recipes")
local motion = require("./motion")
local glass = require("./glass")
local panes = require("./panes")

export type Look = { icon: string, tint: Color? }
export type Context = {
	-- The spaces in order, the chosen one, their names, the one renamed.
	ids: State<{ string }>,
	active: State<string>,
	names: State<{ [string]: string }>,
	renaming: State<string>,
	-- A space's first panes (up to three are shown), read where it changes.
	panes: (space: string) -> { string },
	-- How a pane looks now (its surface's glyph; read without tracking),
	-- and a key that changes when it does.
	look: (pane: string) -> Look,
	look_key: (pane: string) -> string,
	activate: (space: string) -> (),
	rename: (space: string, name: string) -> (),
	new: () -> (),
	close: (space: string) -> (),
	close_others: (space: string) -> (),
	-- Move `space` next to `other` (`before` it, else after): a drag.
	move: ((space: string, other: string, before: boolean) -> ())?,
	-- A pane dragged by its grip (kit/panes) dropped on `space`, or on the
	-- bar's empty end (a space of its own).
	take_pane: ((space: string, pane: string) -> ())?,
	pane_to_new: ((pane: string) -> ())?,
	-- The sidebar toggle, when the layout has a sidebar.
	sidebar: State<boolean>?,
	on_sidebar: (() -> ())?,
	project: string,
	on_search: (() -> ())?,
	on_settings: (() -> ())?,
}

local M = {}

M.HEIGHT = 44

-- Two presses within this long rename a space in place.
local DOUBLE_CLICK = 350

local STRIP = "ztabs"
M.TAB = 28
M.SLOT = 132

-- The space being dragged, the space a dragged pane would move into, and
-- the pane a ghost tab at the end is waiting for.
local dragging = ui.state("ztabs_dragging", "")
local pane_target = ui.state("ztabs_pane_target", "")
local slot = ui.state("ztabs_slot", "")

local function is_pane(payload: any): boolean
	return type(payload) == "table" and payload.kind == "pane"
end

-- A space's glyphs: its first panes' on tiles, two and "+n" past three.
local function tiles(ctx: Context, tab: string, dim: () -> boolean): Node
	type Slot = { key: string, pane: string?, more: number? }
	return ui.row {
		gap = "$zeron.space.3",
		items = "center",
		shrink = 0,
		ui.each(
			ui.computed(function(): { Slot }
				local all = ctx.panes(tab)
				local out: { Slot } = {}
				for i, pane in all do
					if #all > 3 and i == 3 then
						table.insert(out, { key = "more", more = #all - 2 })
						break
					end
					table.insert(out, { key = pane, pane = pane })
				end
				return out
			end),
			function(item: Slot): Node
				if item.more then
					return ui.row {
						h = 20,
						min_w = 20,
						px = "$zeron.space.5",
						shrink = 0,
						items = "center",
						justify = "center",
						rounded = "$zeron.radius.5",
						border = 1,
						border_color = T.hairline,
						bg = function()
							return if dim() then T.hover else T.glass_active
						end,
						txt.text {
							`+{item.more}`,
							size = "micro",
							weight = "semibold",
							line = false,
							color = function()
								return if dim() then T.tertiary else T.secondary
							end,
						},
					}
				end
				local pane = item.pane or ""
				return ui.presence(function()
					return ctx.look_key(pane)
				end, function(): Node
					return panes.tile(ctx.look(pane), dim)
				end)
			end,
			{
				key = function(item: Slot)
					return if item.more then `more{item.more}` else item.key
				end,
			}
		),
	}
end

-- A space as it shows active, frosted: what follows the pointer dragging it.
local function drag_chip(ctx: Context, tab: string): Node
	return ui.row {
		h = M.TAB,
		max_w = 210,
		pl = "$zeron.space.3",
		pr = "$zeron.space.10",
		gap = "$zeron.space.7",
		items = "center",
		rounded = "$zeron.radius.8",
		bg = T.glass_active,
		backdrop_blur = 24,
		border = 1,
		border_color = T.hairline,
		tiles(ctx, tab, function()
			return false
		end),
		txt.text {
			function()
				return ctx.names:get()[tab] or ""
			end,
			size = "md",
			weight = "medium",
			line = false,
			truncate = true,
			min_w = 0,
		},
	}
end

local function chip(ctx: Context, tab: string): Node
	local function selected(): boolean
		return ctx.active:get() == tab
	end
	local armed, presses = 0, 0
	local draft = ui.state(`ztab_{tab}_draft`, "")
	local function editing(): boolean
		return ctx.renaming:get() == tab
	end
	local function start_rename()
		draft:set(ctx.names:peek()[tab] or "")
		ctx.renaming:set(tab)
	end
	return ui.button(wash.item(STRIP, {
		id = `ztab_{tab}`,
		h = M.TAB,
		-- The tiles as far in from the edge as from the top; the close 4 in.
		pl = "$zeron.space.3",
		pr = "$zeron.space.4",
		gap = "$zeron.space.7",
		-- Many spaces share the bar down to their glyphs and a few letters.
		min_w = 88,
		max_w = 210,
		shrink = 1,
		items = "center",
		rounded = "$zeron.radius.8",
		cursor = "default",
		focus = { border = 0 },
		-- A pane dragged over it lights it; where it was while dragged, dim.
		bg = function()
			return if pane_target:get() == tab then T.glass_active else T.clear
		end,
		opacity = function()
			return if dragging:get() == tab then 0.35 else 1
		end,
		-- Its close button shows while the pointer is over it.
		hover_group = true,
		on_click = function()
			ctx.activate(tab)
			-- A second press soon after renames it. Each press arms its own
			-- window, so a late timer never disarms a newer press.
			if armed ~= 0 then
				armed = 0
				start_rename()
				return
			end
			presses += 1
			local token = presses
			armed = token
			ui.after(DOUBLE_CLICK, function()
				if armed == token then
					armed = 0
				end
			end)
		end,
		-- Dragged, a space moves where it is over another: the others slide
		-- aside as it goes (the list's `animate`), as a browser's tabs do.
		on_drag = if ctx.move
			then function()
				dragging:set(tab)
				return { space = tab }
			end
			else nil,
		on_drag_end = function()
			dragging:set("")
		end,
		drag_preview = function(): Node
			return drag_chip(ctx, tab)
		end,
		drop_when = function(payload: any): boolean
			return type(payload) == "table" and (payload.space ~= nil or (is_pane(payload) and ctx.take_pane ~= nil))
		end,
		on_drag_over = function(payload: any, e: DragPoint)
			if is_pane(payload) then
				if slot:peek() ~= "" then
					slot:set("")
				end
				if pane_target:peek() ~= tab then
					pane_target:set(tab)
				end
				return
			end
			if ctx.move and payload.space ~= tab then
				local was = table.find(ctx.ids:peek(), payload.space)
				ctx.move(payload.space, tab, e.local_x < e.w / 2)
				-- A tap as the tabs swap places, not while hovering in place.
				if table.find(ctx.ids:peek(), payload.space) ~= was then
					ui.haptic("alignment")
				end
			end
		end,
		on_drag_leave = function()
			if pane_target:peek() == tab then
				pane_target:set("")
			end
		end,
		on_drop = function(payload: any)
			pane_target:set("")
			local take = ctx.take_pane
			if take and is_pane(payload) then
				take(tab, payload.id)
			end
		end,
		context_menu = function()
			return {
				ui.menu_item { "Rename", id = `ztab_{tab}_menu_rename`, on_click = start_rename },
				ui.menu_item { "New space", id = `ztab_{tab}_menu_new`, on_click = ctx.new },
				ui.div { h = 1, my = "$zeron.space.4", bg = T.hairline },
				ui.menu_item {
					"Close other spaces",
					id = `ztab_{tab}_menu_others`,
					on_click = function()
						ctx.close_others(tab)
					end,
				},
				ui.menu_item {
					"Close space",
					id = `ztab_{tab}_menu_close`,
					on_click = function()
						ctx.close(tab)
					end,
				},
			}
		end,
		-- The active space's glass: one piece, sliding between the tabs.
		glass.active("ztabs_glass", selected, "$zeron.radius.8"),
		tiles(ctx, tab, function()
			return not selected()
		end),
		ui.presence(function()
			return if editing() then "edit" else "name"
		end, function(mode: string): Node
			if mode == "edit" then
				return ui.input {
					id = `ztab_{tab}_name`,
					value = draft,
					grow = 1,
					min_w = 0,
					p = 0,
					border = 0,
					rounded = 0,
					bg = T.clear,
					focus = { border = 0, bg = T.clear },
					text_size = "$font.size.md",
					select_on_focus = true,
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = function(e: KeyEvent): boolean?
						if e.key == "Enter" then
							ctx.rename(tab, draft:peek())
							return true
						elseif e.key == "Escape" then
							ctx.renaming:set("")
							return true
						end
						return nil
					end,
					on_blur = function()
						if ctx.renaming:peek() == tab then
							ctx.rename(tab, draft:peek())
						end
					end,
				}
			end
			return txt.text {
				function()
					return ctx.names:get()[tab] or ""
				end,
				size = "md",
				weight = "medium",
				line = false,
				truncate = true,
				min_w = 0,
				color = "inherit",
				variants = recipes.strip_tab { selected = selected },
			}
		end, { grow = 1, shrink = 1, min_w = 0 }),
		ui.button {
			id = `ztab_{tab}_close`,
			w = 20,
			h = 20,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.5",
			bg = T.clear,
			hover = { bg = T.ink4 },
			focus = { border = 0 },
			cursor = "pointer",
			opacity = 0,
			group_hover = { opacity = 1 },
			on_click = function()
				ctx.close(tab)
			end,
			icon { name = "close", size = 12, color = T.secondary },
		},
	}, selected))
end

local function button(id: string, label: string, name: string, run: (() -> ())?): Node
	return tb.button { id = id, label = label, icon = name :: any, on_click = run }
end

-- The topbar.
function M.topbar(ctx: Context): Node
	return ui.row {
		id = "ztopbar",
		h = M.HEIGHT,
		w_full = true,
		shrink = 0,
		pl = "$zeron.lights",
		pr = "$zeron.well.gap",
		-- Its controls on the traffic lights' line, 21 down, as the
		-- unified titlebar's.
		pb = ui.raw(2 * (M.HEIGHT / 2 - 21), "the traffic lights' line, measured"),
		gap = "$zeron.space.6",
		items = "center",
		window_drag = true,
		ctx.sidebar and tb.control {
			id = "ztopbar_sidebar",
			label = "Toggle sidebar",
			glyph = sidebar_glyph { open = ctx.sidebar, size = 16 },
			on_click = ctx.on_sidebar,
		} or nil,
		ui.row {
			id = "ztopbar_project",
			h = 30,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			shrink = 0,
			items = "center",
			rounded = "$zeron.radius.9",
			hover = { bg = T.glass_hover },
			cursor = "pointer",
			icon { name = "folder", size = 14, color = T.secondary },
			txt.text { ctx.project, size = "md", color = T.secondary, line = false },
		},
		ui.div { w = 1, h = 16, bg = T.hairline, shrink = 0 },
		wash.list {
			group = STRIP,
			direction = "row",
			gap = "$zeron.space.3",
			shrink = 1,
			min_w = 0,
			-- Past that the strip clips: the tabs never run under search.
			overflow = "hidden",
			color = T.glass_hover,
			ui.each(ctx.ids, function(tab: string): Node
				return chip(ctx, tab)
			end, {
				key = function(tab: string)
					return tab
				end,
				-- Spaces that move slide to their place (Wing's 240 ms quint);
				-- a new one fades in, a closed one fades out as the others
				-- close up.
				animate = { duration = motion.d(240), ease = motion.EASE_OUT_QUINT },
				enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
				exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
			}),
		},
		-- Where a pane dropped on the bar's end would open: a ghost tab.
		ui.presence(slot, function(pane: string): Node
			if pane == "" then
				return ui.div {}
			end
			return ui.row {
				id = "ztopbar_slot",
				h = M.TAB,
				w = M.SLOT,
				shrink = 0,
				overflow = "hidden",
				rounded = "$zeron.radius.8",
				bg = T.hover,
				border = 1,
				border_color = T.strong,
				on_mount = function(el: Element)
					anime.animate(el, {
						width = { 0, M.SLOT },
						opacity = { 0, 1 },
						duration = motion.d(200),
						ease = motion.EASE_OUT_QUINT,
					})
				end,
			}
		end),
		button("ztopbar_new", "New space (⌘T)", "plus", ctx.new),
		-- The bar's empty end: a pane dropped here becomes a space of its own.
		ui.div {
			id = "ztopbar_end",
			grow = 1,
			h_full = true,
			drop_when = function(payload: any): boolean
				return is_pane(payload) and ctx.pane_to_new ~= nil
			end,
			on_drag_over = function(payload: any)
				if slot:peek() ~= payload.id then
					slot:set(payload.id)
				end
			end,
			on_drag_leave = function()
				if slot:peek() ~= "" then
					slot:set("")
				end
			end,
			on_drop = function(payload: any)
				slot:set("")
				local open = ctx.pane_to_new
				if open then
					open(payload.id)
				end
			end,
		},
		button("ztopbar_search", "Search (⌘K)", "magnifer", ctx.on_search),
		button("ztopbar_settings", "Settings (⌘,)", "settings", ctx.on_settings),
	}
end

return M
