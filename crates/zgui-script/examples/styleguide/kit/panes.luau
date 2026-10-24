-- Panes (Wing's zterm shell): a tab's panes as cards placed absolutely in
-- an area, at frames from a split tree; 4 apart, radius concentric with
-- the window, a hairline (the ring when focused among several, bright
-- while moving). Dividers are the gap itself and drag the split, each side
-- keeping 160. A grip of 36×22 shows near a pane's top; dragging it over
-- another pane previews the drop at the nearest edge, live, and dropping
-- keeps it.
--
-- Under Zeron's panel policy (panel_layout.luau), as its columns are:
-- panes along an axis share it equally; a dragged divider holds until the
-- next split, close or move, and a double click on it shares equally
-- again; a change of structure eases every card on the panel curve (180
-- ms, up to 240 for long moves), a card arriving with it fading in; the
-- area resizing applies at once; an area too small for every pane's 160
-- hides the least recently focused, which come back when focused or when
-- there is room.
local T = require("../theme")
local layout = require("./layout")
local motion = require("./motion")
local L = require("./panel_layout")

export type Zone = "left" | "right" | "top" | "bottom"
export type Drop = { target: string?, zone: Zone?, id: string? }
-- A dragged pane: its id and its workspace's (a tab strip takes it).
export type Payload = { kind: "pane", id: string, ws: string }
-- How a pane shows in a tab or the chip that follows a drag: its glyph
-- and its own colour (an agent's).
export type Look = { icon: string, tint: Color? }

-- A workspace: its tree and the states around it. Make one with `new`,
-- show it with `view`, change it with the functions below.
export type Workspace = {
	id: string,
	root: State<layout.Tree?>,
	ratios: State<{ [string]: number }>,
	focus: State<string?>,
	zoom: State<string?>,
	drop: State<Drop>,
	dragging: State<string?>,
	-- What a pane shows: its id and the inner radius.
	render: (pane: string, inner: () -> number) -> Node,
	-- A pane's name and glyph for the drag chip.
	name: ((pane: string) -> string)?,
	look: ((pane: string) -> Look)?,
	-- Whether a lone pane has somewhere to go (another tab): its grip shows.
	movable: (() -> boolean)?,
	gap: number,
	radius: number,
	card: Card,
	counter: number,
	area: Element?,
	last_shape: string?,
	on_change: ((ws: Workspace) -> ())?,
	-- When each pane was last focused (a rising sequence).
	seen: { [string]: number },
	seq: number,
	-- The area's size, as layout gives it.
	size: State<{ w: number, h: number }>,
	last_size: string?,
	-- A divider's double-click window: the press that opened it.
	armed: { [string]: number? },
}
-- How the cards look: zterm's by default (the pane fill, a hairline, the
-- strong line on the focused card among several) inside the double
-- border's lit rim (theme `rim`). A layout of wells gives
-- its own: a fill, an edge (which then stays as the focus moves), and
-- the inner ring of a focused card and of one that is not.
export type Card = {
	bg: Color?,
	line: Color?,
	shadow: any?,
	inner: any?,
	inner_dim: any?,
}
export type Options = {
	id: string,
	card: Card?,
	-- The first pane's id, or a whole tree.
	root: layout.Tree?,
	render: (pane: string, inner: () -> number) -> Node,
	name: ((pane: string) -> string)?,
	look: ((pane: string) -> Look)?,
	movable: (() -> boolean)?,
	gap: number?,
	radius: number?,
	on_change: ((ws: Workspace) -> ())?,
}

local M = {}

M.GAP = 4
M.RADIUS = 6
M.MIN = 160
M.DOUBLE_CLICK = 350

function M.new(o: Options): Workspace
	local ws: Workspace = {
		id = o.id,
		root = ui.state(`{o.id}_root`, o.root),
		ratios = ui.state(`{o.id}_ratios`, {} :: { [string]: number }),
		focus = ui.state(`{o.id}_focus`, if o.root then layout.leaves(o.root)[1] else nil),
		zoom = ui.state(`{o.id}_zoom`, nil :: string?),
		drop = ui.state(`{o.id}_drop`, {} :: Drop),
		dragging = ui.state(`{o.id}_dragging`, nil :: string?),
		render = o.render,
		name = o.name,
		look = o.look,
		movable = o.movable,
		gap = o.gap or M.GAP,
		radius = o.radius or M.RADIUS,
		card = o.card or {},
		counter = 0,
		area = nil,
		last_shape = nil,
		on_change = o.on_change,
		seen = {},
		seq = 0,
		size = ui.state(`{o.id}_size`, { w = 0, h = 0 }),
		last_size = nil,
		armed = {},
	}
	return ws
end

function M.fresh(ws: Workspace, prefix: string): string
	ws.counter += 1
	return `{ws.id}_{prefix}{ws.counter}`
end

local function changed(ws: Workspace)
	if ws.on_change then
		ws.on_change(ws)
	end
end

-- Focus a pane and rank it most recent (a pane the area hid comes back).
local function mark(ws: Workspace, pane: string)
	ws.seq += 1
	ws.seen[pane] = ws.seq
	ws.focus:set(pane)
end

function M.panes(ws: Workspace): { string }
	local root = ws.root:peek()
	return if root then layout.leaves(root) else {}
end

-- Split the focused pane (the new one after it) and focus the new pane.
function M.split(ws: Workspace, axis: layout.Axis): string?
	local root = ws.root:peek()
	local focus = ws.focus:peek()
	local pane = M.fresh(ws, "p")
	if not root or not focus then
		ws.root:set(layout.pane(pane))
	else
		ws.root:set(layout.split(root, focus, axis, pane, M.fresh(ws, "s")))
	end
	-- A change of structure shares the room equally again.
	ws.ratios:set {}
	ws.zoom:set(nil)
	mark(ws, pane)
	changed(ws)
	return pane
end

-- Bring `pane` (from another workspace, its content kept by the caller)
-- in beside the focused pane, and focus it.
function M.insert(ws: Workspace, pane: string, axis: layout.Axis?)
	local root = ws.root:peek()
	local focus = ws.focus:peek()
	if root and layout.contains(root, pane) then
		mark(ws, pane)
		return
	end
	if not root or not focus then
		ws.root:set(layout.pane(pane))
	else
		ws.root:set(layout.split(root, focus, axis or "row", pane, M.fresh(ws, "s")))
	end
	ws.ratios:set {}
	ws.zoom:set(nil)
	mark(ws, pane)
	changed(ws)
end

-- Close a pane; its sibling takes the room and the nearest pane is focused.
function M.close(ws: Workspace, pane: string?)
	local root = ws.root:peek()
	local id = pane or ws.focus:peek()
	if not root or not id or not layout.contains(root, id) then
		return
	end
	local rest, near = layout.remove(root, id)
	ws.root:set(rest)
	ws.ratios:set {}
	ws.seen[id] = nil
	if ws.zoom:peek() == id then
		ws.zoom:set(nil)
	end
	ws.focus:set(if rest then (near or layout.leaves(rest)[1]) else nil)
	changed(ws)
end

function M.focus(ws: Workspace, pane: string)
	mark(ws, pane)
end

function M.toggle_zoom(ws: Workspace)
	local focus = ws.focus:peek()
	ws.zoom:set(if ws.zoom:peek() or not focus then nil else focus)
	changed(ws)
end

function M.equalize(ws: Workspace)
	ws.ratios:set {}
	changed(ws)
end

function M.go(ws: Workspace, direction: layout.Direction)
	local root, focus = ws.root:peek(), ws.focus:peek()
	if root and focus then
		local next = layout.neighbor(root, focus, direction)
		if next then
			ws.focus:set(next)
		end
	end
end

-- Panes the area is too small for: the least recently focused leave
-- first (never the focused one) until the rest fit at 160 each.
local function fitted(ws: Workspace, tree: layout.Tree, w: number, h: number): (layout.Tree, { string })
	local hidden: { string } = {}
	if w <= 0 or h <= 0 then
		return tree, hidden
	end
	local current = tree
	while true do
		local need_w, need_h = layout.least(current, M.MIN, ws.gap)
		local leaves = layout.leaves(current)
		if (need_w <= w and need_h <= h) or #leaves <= 1 then
			return current, hidden
		end
		local focus = ws.focus:peek()
		local victim: string? = nil
		for _, pane in leaves do
			if pane ~= focus and (victim == nil or (ws.seen[pane] or 0) < (ws.seen[victim :: string] or 0)) then
				victim = pane
			end
		end
		if not victim then
			return current, hidden
		end
		table.insert(hidden, victim)
		current = (layout.remove(current, victim)) :: layout.Tree
	end
end

-- The panes the area hides right now.
function M.hidden(ws: Workspace): { string }
	local root = ws.root:get()
	local size = ws.size:get()
	ws.focus:get()
	if not root then
		return {}
	end
	local _, hidden = fitted(ws, root, size.w, size.h)
	return hidden
end

-- Move `pane` beside `target`, at the zone's side.
function M.move(ws: Workspace, pane: string, target: string, zone: Zone)
	local root = ws.root:peek()
	if not root or pane == target or not layout.contains(root, target) then
		return
	end
	local base = layout.remove(root, pane)
	if not base or not layout.contains(base, target) then
		return
	end
	local axis: layout.Axis = if zone == "left" or zone == "right" then "row" else "column"
	ws.root:set(layout.split(base, target, axis, pane, M.fresh(ws, "s"), zone == "left" or zone == "top"))
	ws.ratios:set {}
	ws.zoom:set(nil)
	mark(ws, pane)
	changed(ws)
end

-- The tree a hovering drag would make.
local function previewed(ws: Workspace, root: layout.Tree): layout.Tree
	local d = ws.drop:get()
	if not d.target or not d.id or not layout.contains(root, d.target) then
		return root
	end
	local base = if layout.contains(root, d.id) then layout.remove(root, d.id) else root
	if not base or not layout.contains(base, d.target) then
		return root
	end
	local axis: layout.Axis = if d.zone == "left" or d.zone == "right" then "row" else "column"
	return layout.split(base, d.target, axis, d.id, "preview", d.zone == "left" or d.zone == "top")
end

export type Shown = layout.Frames & { order: { string }, smooth: boolean }

local function shown_of(el: Element?): layout.Rect
	if not el then
		return { x = 0, y = 0, w = 0, h = 0 }
	end
	return { x = el.x or 0, y = el.y or 0, w = el.width or 0, h = el.height or 0 }
end

local function percent(p: number): string
	return `{p * 100}%`
end
type Insets =
	{ left: string, ml: number, right: string, mr: number, top: string, mt: number, bottom: string, mb: number }
local function insets(box: layout.Box): Insets
	return {
		left = percent(box.left.p),
		ml = box.left.q,
		right = percent(1 - box.right.p),
		mr = -box.right.q,
		top = percent(box.top.p),
		mt = box.top.q,
		bottom = percent(1 - box.bottom.p),
		mb = -box.bottom.q,
	}
end

local EASED = { "left", "top", "width", "height", "marginLeft", "marginTop" }

-- The workspace's node: the area, its pane cards and dividers.
export type ViewProps = { grow: number?, w: Length?, h: Length?, w_full: boolean?, h_full: boolean?, min_h: number? }
function M.view(ws: Workspace, props: ViewProps?): Node
	local p: ViewProps = props or {}
	local frames = ui.computed(function(): Shown
		local root = ws.root:get()
		if not root then
			return { panes = {}, dividers = {}, order = {}, smooth = false }
		end
		local size = ws.size:get()
		ws.focus:get()
		local shown = fitted(ws, previewed(ws, root), size.w, size.h)
		local zoomed = ws.zoom:get()
		local out: Shown
		if zoomed and layout.contains(shown, zoomed) and not (ws.drop:get()).target then
			out = { panes = { [zoomed] = layout.WHOLE }, dividers = {}, order = { zoomed }, smooth = false }
		else
			local placed = layout.frames(shown, ws.ratios:get(), ws.gap)
			out = { panes = placed.panes, dividers = placed.dividers, order = layout.leaves(shown), smooth = false }
		end
		local shape = `{layout.signature(shown)}#{zoomed or ""}`
		-- The area resizing is direct manipulation: what it hides or brings
		-- back lands at once.
		local sized = `{size.w}x{size.h}`
		out.smooth = ws.last_shape ~= nil and shape ~= ws.last_shape and sized == ws.last_size
		ws.last_shape = shape
		ws.last_size = sized
		return out
	end)
	local pane_ids = ui.computed(function()
		return (frames:get()).order
	end)
	local divider_ids = ui.computed(function()
		local ids: { string } = {}
		for _, d in (frames:get()).dividers do
			table.insert(ids, d.id)
		end
		return ids
	end)
	local function area_size(): { w: number, h: number }
		local r = shown_of(ws.area)
		return { w = r.w, h = r.h }
	end
	-- On a change of structure, ease an element from where it shows to its box.
	local function follow(element: () -> Element?, box: () -> layout.Box?)
		ui.effect(function()
			local f = frames:get()
			local b = box()
			local el = element()
			if not (f.smooth and b and el and ws.area) then
				return
			end
			local area, from = shown_of(ws.area), shown_of(el)
			if from.w <= 0 and from.h <= 0 then
				return
			end
			local to = layout.resolve(b, area.w, area.h)
			local far = math.max(
				math.abs(to.x - (from.x - area.x)),
				math.abs(to.y - (from.y - area.y)),
				math.abs(to.w - from.w),
				math.abs(to.h - from.h)
			)
			anime.animate(el, {
				left = { from.x - area.x, to.x },
				top = { from.y - area.y, to.y },
				width = { from.w, to.w },
				height = { from.h, to.h },
				marginLeft = 0,
				marginTop = 0,
				duration = motion.d(L.duration(0, far)),
				ease = L.EASE,
				onComplete = function()
					anime.utils.cleanInlineStyles(el, EASED)
				end,
			})
		end)
	end
	local function placed(box: () -> layout.Box?): ContainerProps
		local function at(): Insets
			return insets(box() or layout.WHOLE)
		end
		return {
			absolute = true,
			snap = true,
			left = function()
				return at().left
			end,
			ml = function()
				return ui.raw(at().ml, "the layout's gap, measured")
			end,
			right = function()
				return at().right
			end,
			mr = function()
				return ui.raw(at().mr, "the layout's gap, measured")
			end,
			top = function()
				return at().top
			end,
			mt = function()
				return ui.raw(at().mt, "the layout's gap, measured")
			end,
			bottom = function()
				return at().bottom
			end,
			mb = function()
				return ui.raw(at().mb, "the layout's gap, measured")
			end,
		}
	end
	-- The pane under a point, and the edge it is nearest.
	local function target_at(x: number, y: number): (string?, Zone?)
		local root = ws.root:peek()
		if not root then
			return nil, nil
		end
		local size = area_size()
		local zoomed = ws.zoom:peek()
		local boxes = if zoomed and layout.contains(root, zoomed)
			then { [zoomed] = layout.WHOLE }
			else layout.frames(root, ws.ratios:peek(), ws.gap).panes
		for pane, box in boxes do
			local r = layout.resolve(box, size.w, size.h)
			if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
				local fx, fy = (x - r.x) / math.max(r.w, 1), (y - r.y) / math.max(r.h, 1)
				local zone: Zone, best = "right", 1 - fx
				if fx < best then
					zone, best = "left", fx
				end
				if fy < best then
					zone, best = "top", fy
				end
				if 1 - fy < best then
					zone = "bottom"
				end
				return pane, zone
			end
		end
		return nil, nil
	end

	local function Pane(pane: string): Node
		local element: Element? = nil
		local grip = ui.state(`{ws.id}_{pane}_grip`, 0)
		local near = ui.state(`{ws.id}_{pane}_near`, false)
		local function box(): layout.Box?
			return (frames:get()).panes[pane]
		end
		local function several(): boolean
			return #(pane_ids:get()) > 1
		end
		local function focused(): boolean
			return ws.focus:get() == pane
		end
		local function moving(): boolean
			return ws.dragging:get() == pane
		end
		follow(function()
			return element
		end, box)
		ui.effect(function()
			local d = ws.dragging:get()
			-- Near the top, with somewhere to go: beside another pane, or
			-- into another tab. While dragging, only the dragged one's.
			local movable = ws.movable
			local show = if d ~= nil then d == pane else near:get() and (several() or (movable ~= nil and movable()))
			grip:set(if show then 1 else 0)
		end)
		local function inner(): number
			return ws.radius - 1
		end
		local node = placed(box)
		node.id = `{ws.id}_{pane}`
		node.on_mount = function(el: Element)
			element = el
			if (frames:peek()).smooth then
				anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(220), ease = "outQuad" })
			end
		end
		node.items = "stretch"
		node.rounded = T.radius(ws.radius)
		node.overflow = "hidden"
		local card = ws.card
		node.bg = card.bg or T.pane
		node.border = 1
		node.border_color = function(): Color
			if moving() then
				return T.pane_moving
			end
			if card.line then
				-- Wells mark the focus with their inner ring instead.
				return card.line :: Color
			end
			return if several() and focused() then T.strong else T.hairline
		end
		node.shadow = card.shadow
		-- The double border's lit rim inside the hairline (a well's own
		-- when it gives one), dimmer on a card out of focus.
		local lit = card.inner or T.rim_light
		local dim = card.inner_dim or (if card.inner then card.inner else T.rim_light_dim)
		node.inset_shadow = function()
			return if several() and not focused() then dim else lit
		end
		node.on_pointer_move = function(e: PointerEvent)
			local n = e.local_y < 32
			if near:peek() ~= n then
				near:set(n)
			end
		end
		node.on_hover = function(inside: boolean)
			if not inside and near:peek() then
				near:set(false)
			end
		end
		node.on_press = function()
			if ws.focus:peek() ~= pane then
				mark(ws, pane)
			end
		end
		node[1] = ws.render(pane, inner)
		node[2] = ui.row {
			absolute = true,
			top = 6,
			left = 0,
			w_full = true,
			justify = "center",
			pointer_events = "none",
			hidden = function()
				return grip:get() == 0
			end,
			ui.column {
				id = `{ws.id}_{pane}_grip`,
				w = 36,
				h = 22,
				rounded = "$zeron.radius.7",
				items = "center",
				justify = "center",
				pointer_events = "auto",
				bg = T.grip,
				backdrop_blur = 14,
				border = 1,
				border_color = T.border,
				shadow = T.shadow_sm,
				cursor = "grab",
				opacity = ui.tween(grip, { duration = motion.d(160) }),
				on_click = function()
					mark(ws, pane)
				end,
				on_drag = function(): Payload
					ws.dragging:set(pane)
					return { kind = "pane", id = pane, ws = ws.id }
				end,
				drag_preview = function(): Node
					return M.chip(ws, pane)
				end,
				on_drag_end = function()
					ws.dragging:set(nil)
				end,
				M.dots(),
			},
		}
		return ui.column(node)
	end

	local function Divider(id: string): Node
		local element: Element? = nil
		local function find(list: { layout.Divider }): layout.Divider?
			for _, d in list do
				if d.id == id then
					return d
				end
			end
			return nil
		end
		local function box(): layout.Box?
			return find((frames:get()).dividers)
		end
		local first = find((frames:peek()).dividers)
		local row = first == nil or first.axis == "row"
		follow(function()
			return element
		end, box)
		local start: { at: number, ratio: number, length: number }? = nil
		local node = placed(box)
		node.id = `{ws.id}_{id}`
		node.on_mount = function(el: Element)
			element = el
		end
		node.rounded = T.radius_full
		node.cursor = if row then "col_resize" else "row_resize"
		node.bg = T.clear
		node.hover = { bg = T.ink3 }
		node.on_press = function(e: PointerEvent)
			-- A double click shares the room equally again.
			if ws.armed[id] then
				ws.armed[id] = nil
				start = nil
				M.equalize(ws)
				return
			end
			-- Each press arms its own window; a late timer from an older
			-- press must not disarm a newer one.
			ws.seq += 1
			local token = ws.seq
			ws.armed[id] = token
			ui.after(M.DOUBLE_CLICK, function()
				if ws.armed[id] == token then
					ws.armed[id] = nil
				end
			end)
			local d = find((frames:peek()).dividers)
			if d then
				local area = area_size()
				local length = layout.at(d.length, if row then area.w else area.h)
				local split = layout.find_split(ws.root:peek(), id)
				local ratio = (ws.ratios:peek())[id] or (if split then layout.share(split) else 0.5)
				start = { at = if row then e.x else e.y, ratio = ratio, length = length }
			end
		end
		node.on_pointer_move = function(e: PointerEvent)
			local s = start
			if not s or s.length <= 0 then
				return
			end
			local moved = (if row then e.x else e.y) - s.at
			if moved ~= 0 then
				ws.armed[id] = nil
			end
			local least = math.min(0.45, M.MIN / s.length)
			ws.ratios:set_key(id, math.clamp(s.ratio + moved / s.length, least, 1 - least))
		end
		node.on_release = function()
			start = nil
		end
		return ui.div(node)
	end

	return ui.div {
		id = ws.id,
		grow = p.grow,
		w = p.w,
		h = p.h,
		w_full = p.w_full,
		h_full = p.h_full,
		min_h = p.min_h or 0,
		min_w = 0,
		relative = true,
		on_mount = function(el: Element)
			ws.area = el
		end,
		on_resize = function(size: Size)
			local now = ws.size:peek()
			if math.abs(now.w - size.w) > 0.5 or math.abs(now.h - size.h) > 0.5 then
				ws.size:set { w = size.w, h = size.h }
			end
		end,
		drop_when = function(payload: Payload)
			return payload.kind == "pane"
		end,
		on_drag_over = function(payload: Payload, e: DragPoint)
			local target, zone = target_at(e.local_x, e.local_y)
			if target == payload.id then
				target = nil
			end
			local d = ws.drop:peek()
			if d.target ~= target or d.zone ~= zone or d.id ~= payload.id then
				ws.drop:set(if target then { target = target, zone = zone, id = payload.id } else {})
			end
		end,
		on_drag_leave = function()
			if (ws.drop:peek()).target then
				ws.drop:set {}
			end
		end,
		on_drop = function()
			local d = ws.drop:peek()
			ws.drop:set {}
			if d.target and d.id and d.zone then
				M.move(ws, d.id, d.target, d.zone)
			end
		end,
		ui.each(pane_ids, function(id: string)
			return Pane(id)
		end, {
			key = function(id: string)
				return id
			end,
		}),
		ui.each(divider_ids, function(id: string)
			return Divider(id)
		end, {
			key = function(id: string)
				return id
			end,
		}),
	}
end

-- The grip's dots: two rows of three.
function M.dots(): Node
	local rows: { Node } = {}
	for _ = 1, 2 do
		local dots: { Node } = {}
		for _ = 1, 3 do
			table.insert(dots, ui.div { w = 3, h = 3, rounded = T.radius_full, bg = T.secondary })
		end
		table.insert(rows, ui.row { gap = "$zeron.space.3", items = "center", dots })
	end
	return ui.column { gap = "$zeron.space.3", items = "center", rows }
end

-- A pane's glyph on a 20 tile at radius 5 (Wing's tab icons): dimmer in
-- what is not active; an item's own colour tints its glyph.
function M.tile(look: Look, dim: () -> boolean): Node
	local icon = require("./icon")
	return ui.row {
		h = 20,
		min_w = 20,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.5",
		border = 1,
		border_color = T.hairline,
		bg = function()
			return if dim() then T.hover else T.glass_active
		end,
		icon {
			name = look.icon :: any,
			size = 12,
			color = function()
				return look.tint or (if dim() then T.tertiary else T.secondary)
			end,
		},
	}
end

-- The chip that follows a dragged pane: a tab, as it shows active in the
-- strip (its glyph's tile and its name), frosted.
function M.chip(ws: Workspace, pane: string): Node
	local txt = require("./text")
	local look = if ws.look then ws.look(pane) else nil
	return ui.row {
		h = 28,
		max_w = 210,
		pl = if look then "$zeron.space.3" else "$zeron.space.10",
		pr = "$zeron.space.10",
		gap = "$zeron.space.7",
		items = "center",
		rounded = "$zeron.radius.8",
		bg = T.glass_active,
		backdrop_blur = 24,
		border = 1,
		border_color = T.hairline,
		look and M.tile(look, function()
			return false
		end) or nil,
		txt.text { if ws.name then ws.name(pane) else pane, size = "sm", truncate = true, line = false },
	}
end

return M
