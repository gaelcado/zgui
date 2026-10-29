-- The tabs layouts' topbar (Tern's, Rex's): beside the traffic lights, the
-- sidebar toggle, the project, the spaces (a tab is a named group of
-- panes) and +, then the focused pane's split and zoom, search and
-- settings. The window drags from the bar. The app gives it the spaces and
-- what each action does.
--
-- The spaces are zgx's tabs (`ui.tabs`: one Tab stop, the arrows choose,
-- Delete closes, ⌘⇧ and an arrow or a drag reorders; too many scroll, with
-- a menu of them all), each drawn as the surface chrome's tab (kit/chrome:
-- 24 high at radius 6, a 10% wash chosen, 6% under the pointer): its panes'
-- glyphs at 14 (three at most, else two and "+n"), then its name at 12;
-- tabs 3 apart, sharing the bar down to 88. The choice moves at once, as
-- Zeron's and Tern's do: no highlight slides after it. A space's close
-- shows under the pointer; two presses rename it in place, as does its
-- menu. Dragged along the bar, a space lifts: a frosted copy follows the
-- pointer, it dims where it was, and it takes its neighbours' places as it
-- passes them, sliding (240 ms quint) with a tap of the trackpad at each
-- swap. That slide is the strip's one motion: a new space fades in where it
-- opens, a closed one fades where it was as the others close up over it. A
-- pane dragged by its grip onto a space lights it and moves in, onto the
-- bar's empty end opens a ghost tab and becomes a space of its own there
-- (shown at once, where the ghost was).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local tb = require("./titlebar")
local chrome = require("./chrome")
local well = require("./well")
local sidebar_glyph = require("./sidebar_glyph")
local motion = require("./motion")

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
	-- The spaces reorder (dragged along the bar, or ⌘⇧ and an arrow): the
	-- strip writes `ids`.
	reorderable: boolean?,
	-- A pane dragged by its grip (kit/panes) dropped on `space`, or on the
	-- bar's empty end (a space of its own).
	take_pane: ((space: string, pane: string) -> ())?,
	pane_to_new: ((pane: string) -> ())?,
	-- The focused pane's controls, in the bar as Tern's are: split it
	-- beside ("row") or below ("column"), zoom it, and whether it is.
	split: ((axis: "row" | "column") -> ())?,
	zoom: (() -> ())?,
	zoomed: (() -> boolean)?,
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
M.TAB = chrome.CONTROL
M.SLOT = 132
-- How far apart the spaces lie ("$zeron.space.3"), for a closing one's
-- margin to take its room and the gap after it.
local GAP = 3

-- The space being dragged, the space a dragged pane would move into, and
-- the pane a ghost tab at the end is waiting for.
local dragging = ui.state("ztabs_dragging", "")
local pane_target = ui.state("ztabs_pane_target", "")
local slot = ui.state("ztabs_slot", "")

local function is_pane(payload: any): boolean
	return type(payload) == "table" and payload.kind == "pane"
end

-- A space's glyphs: its first panes', two and "+n" past three. They take
-- the tab's colour (an agent keeps its own).
local function glyphs(ctx: Context, tab: string): Node
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
					return txt.text { `+{item.more}`, size = "xs", weight = "medium", line = false, color = T.tertiary }
				end
				local pane = item.pane or ""
				return ui.presence(function()
					return ctx.look_key(pane)
				end, function(): Node
					local look = ctx.look(pane)
					return icon { name = look.icon :: any, size = chrome.ICON, color = look.tint or "currentColor" }
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

-- A space as it shows chosen, frosted: what follows the pointer dragging it.
local function drag_chip(ctx: Context, tab: string): Node
	return ui.row {
		h = M.TAB,
		max_w = 200,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = T.glass_active,
		backdrop_blur = 24,
		border = 1,
		border_color = T.hairline,
		color = T.text,
		glyphs(ctx, tab),
		txt.text {
			function()
				return ctx.names:get()[tab] or ""
			end,
			size = "sm",
			weight = "medium",
			line = false,
			truncate = true,
			min_w = 0,
			color = "inherit",
		},
	}
end

-- `own` over the chrome tab's frame: what it does not set, the frame's.
local function framed(frame: ContainerProps, own: { [any]: any }): any
	for k, v in frame :: any do
		if own[k] == nil then
			own[k] = v
		end
	end
	return own
end

-- A space's tab: the strip's bare tab, dressed as the chrome's.
local function chip(ctx: Context, tab: string, close: () -> (), fresh: boolean, ref: Ref): Node
	local function selected(): boolean
		return ctx.active:get() == tab
	end
	-- A pane dragged over it lights it.
	local function lit(): boolean
		return pane_target:get() == tab
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
	local frame: any = chrome.tab_frame(selected, lit)
	frame.px = nil
	return ui.button(framed(frame, {
		id = `ztab_{tab}`,
		-- Its name, worked out only while a screen reader reads it.
		label = function(): string
			local name = ctx.names:get()[tab] or ""
			return if name == "" then "Space" else name
		end,
		ref = ref,
		-- Spaces that move slide to their place (Wing's 240 ms quint), the
		-- others closing up as one goes; a new one fades in.
		layout = "position",
		layout_duration = motion.d(240),
		layout_ease = motion.EASE_OUT_QUINT,
		on_mount = if fresh
			then function(el: Element)
				-- Then its own opacity rules again (dim while dragged).
				anime.animate(el, {
					opacity = { 0, 1 },
					duration = motion.d(motion.FAST),
					onComplete = function()
						anime.utils.cleanInlineStyles(el, "opacity")
					end,
				})
			end
			else nil,
		-- Its close 4 in from the edge, as far as from the top.
		pl = "$zeron.space.8",
		pr = "$zeron.space.4",
		-- Many spaces share the bar down to their glyphs and a few letters.
		min_w = 88,
		max_w = 200,
		shrink = 1,
		cursor = "default",
		-- Where it was while dragged, dim.
		opacity = function()
			return if dragging:get() == tab then 0.35 else 1
		end,
		-- Its close button shows while the pointer is over it.
		hover_group = true,
		-- Chosen as it is pressed (the strip). A second press soon after
		-- renames it. Each press arms its own window, so a late timer never
		-- disarms a newer press.
		on_click = function()
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
		-- A pane dragged by its grip onto it moves in.
		drop_when = function(payload: any): boolean
			return is_pane(payload) and ctx.take_pane ~= nil
		end,
		on_drag_over = function()
			if slot:peek() ~= "" then
				slot:set("")
			end
			if pane_target:peek() ~= tab then
				pane_target:set(tab)
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
				ui.menu_item { "Close space", id = `ztab_{tab}_menu_close`, on_click = close },
			}
		end,
		glyphs(ctx, tab),
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
					text_size = "$font.size.sm",
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
				size = "sm",
				weight = "medium",
				line = false,
				truncate = true,
				min_w = 0,
				color = "inherit",
			}
		end, { grow = 1, shrink = 1, min_w = 0 }),
		ui.button {
			id = `ztab_{tab}_close`,
			w = 16,
			h = 16,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.4",
			bg = T.clear,
			hover = { bg = T.ink4 },
			focus = { border = 0 },
			cursor = "pointer",
			-- Not a stop of its own: the arrows go space to space.
			focusable = false,
			opacity = 0,
			group_hover = { opacity = 1 },
			on_click = close,
			icon { name = "close", size = 12, color = T.secondary },
		},
	}))
end

local function button(id: string, label: string, name: string, run: (() -> ())?): Node
	return tb.button { id = id, label = label, icon = name :: any, on_click = run }
end

-- The focused pane's controls: split beside, split below, zoom (washed
-- while zoomed); titlebar buttons 4 apart, as the anchors.
local function pane_controls(ctx: Context): Node?
	local split, zoom = ctx.split, ctx.zoom
	if not split and not zoom then
		return nil
	end
	local function zoomed(): boolean
		return ctx.zoomed ~= nil and ctx.zoomed()
	end
	local controls: { Node } = {}
	if split then
		for _, s in { { "row", "right", "Split right (⌘D)" }, { "column", "down", "Split down (⌘⇧D)" } } do
			local axis: any = s[1]
			table.insert(
				controls,
				tb.button {
					id = `ztopbar_split_{s[2]}`,
					label = s[3],
					glyph = well.split_glyph(axis, chrome.ICON, T.secondary),
					on_click = function()
						split(axis)
					end,
				}
			)
		end
	end
	if zoom then
		table.insert(
			controls,
			tb.button {
				id = "ztopbar_zoom",
				label = "Zoom (⌘⇧↩)",
				on = zoomed,
				glyph = ui.presence(function()
					return if zoomed() then "collapse-arrows" else "expand-arrows"
				end, function(name: string): Node
					return icon { name = name :: any, size = 16, color = T.secondary }
				end),
				on_click = zoom,
			}
		)
	end
	return ui.row {
		id = "ztopbar_pane",
		gap = "$zeron.titlebar.anchor_gap",
		shrink = 0,
		items = "center",
		controls,
	}
end

-- The topbar.
function M.topbar(ctx: Context): Node
	-- The spaces showing as it is built show at once; those that come later
	-- fade in, but for one a pane dropped on the ghost tab opens, shown at
	-- once where the ghost was.
	local known: { [string]: boolean } = {}
	for _, tab in ctx.ids:peek() do
		known[tab] = true
	end
	local landing = false
	-- Each space's tab, and those fading as they close.
	local refs: { [string]: Ref } = {}
	local closing: { [string]: boolean } = {}
	-- A closed space leaves the flow at once, its neighbours sliding over
	-- it (their `layout`), and fades where it was; then it goes. The next
	-- space is chosen as it starts, as the strip would.
	local function close_space(tab: string)
		local el = refs[tab] and refs[tab]:peek()
		if el == nil or not el.mounted then
			ctx.close(tab)
			return
		end
		if closing[tab] then
			return
		end
		closing[tab] = true
		local ids = ctx.ids:peek()
		local at = table.find(ids, tab)
		if at and ctx.active:peek() == tab then
			local next = ids[at + 1] or ids[at - 1]
			if next then
				ctx.activate(next)
			end
		end
		anime.utils.set(el, { marginRight = -((el.width or 0) + GAP) })
		anime.animate(el, {
			opacity = 0,
			duration = motion.d(motion.MENU_OUT),
			onComplete = function()
				closing[tab] = nil
				ctx.close(tab)
			end,
		})
	end
	return ui.row {
		id = "ztopbar",
		h = M.HEIGHT,
		w_full = true,
		shrink = 0,
		-- Its first control where Zeron's titlebar puts its window controls:
		-- 88 in on macOS (20 clear of the traffic lights), 12 elsewhere;
		-- groups 8 apart, 6 from the window's right edge.
		pl = if tb.inset() == 88 then "$zeron.titlebar.inset_mac" else "$zeron.titlebar.inset",
		pr = "$zeron.titlebar.edge",
		-- Its controls on the traffic lights' line, 21 down, as the
		-- unified titlebar's.
		pb = ui.raw(2 * (M.HEIGHT / 2 - 21), "the traffic lights' line, measured"),
		gap = "$zeron.titlebar.group_gap",
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
		ui.tabs {
			id = STRIP,
			label = "Spaces",
			items = ctx.ids,
			value = ctx.active,
			gap = "$zeron.space.3",
			shrink = 1,
			min_w = 0,
			closable = true,
			reorderable = ctx.reorderable,
			dragging = dragging,
			preview = function(tab: string): Node
				return drag_chip(ctx, tab)
			end,
			-- The app closes a space (its panes with it), once it has
			-- faded.
			on_close = function(tab: string): boolean
				close_space(tab)
				return false
			end,
			-- A tap as the spaces swap places, not while hovering in place.
			on_move = function()
				ui.haptic("alignment")
			end,
			tab = function(tab: string, close: () -> ()): Node
				local fresh = not known[tab] and not landing
				if not known[tab] then
					landing = false
				end
				known[tab] = true
				local ref = ui.ref()
				refs[tab] = ref
				return chip(ctx, tab, close, fresh, ref)
			end,
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
				rounded = T.radius_md,
				bg = T.ink2,
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
					local before = #ctx.ids:peek()
					landing = true
					open(payload.id)
					if #ctx.ids:peek() == before then
						landing = false
					end
				end
			end,
		},
		pane_controls(ctx),
		-- Search and settings, 4 apart as Zeron's anchors are; search is the
		-- linear family's compact magnifier, the size of the gear beside it.
		ui.row {
			id = "ztopbar_anchors",
			gap = "$zeron.titlebar.anchor_gap",
			shrink = 0,
			items = "center",
			button("ztopbar_search", "Search (⌘K)", "palette-search", ctx.on_search),
			button("ztopbar_settings", "Settings (⌘,)", "settings", ctx.on_settings),
		},
	}
end

return M
