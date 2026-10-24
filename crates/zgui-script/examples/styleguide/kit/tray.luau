-- Trays (queue.rs, todo_panel.rs): the frosted surface that rises behind
-- the composer, top corners at 16, rows at the concentric 11; the todo
-- list with its header and glyphs, and queued messages with their drag
-- handle and actions.
local T = require("../theme")
local disclosure = require("./disclosure")
local wash = require("./wash")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")
local frost = require("./frost")
local loaders = require("./loaders")
local icon_button = require("./icon_button")

export type TodoState = "done" | "active" | "pending"
export type Todo = { id: string, text: string, state: TodoState }
export type TodoProps = {
	id: string?,
	items: { Todo },
	-- Whether the turn is live (the active glyph spins).
	live: boolean?,
	open: State<boolean>,
	on_dismiss: Handler?,
	w: Reactive<Length>?,
}
export type Queued = { id: string, text: string, attachments: number? }
export type QueueProps = {
	id: string?,
	items: State<{ Queued }>,
	-- "Steer", "Send next" or "Send now".
	action: string?,
	on_remove: ((id: string) -> ())?,
	on_edit: ((id: string) -> ())?,
	on_send: ((id: string) -> ())?,
	w: Reactive<Length>?,
}
export type SurfaceProps = { id: string?, [number]: Child, w: Reactive<Length>?, overlap: number? }

local M = {}

M.RADIUS = 16
-- Concentric: a row 4 in from the surface's 16 corner, inside its 1-point
-- border, rounds at 11; a 24 control 4 in from the 32 row, at 7.
M.ROW_RADIUS = T.inset_radius(M.RADIUS, frost.INSET, 1)
M.CONTROL_INSET = (32 - 24) / 2
M.CONTROL_RADIUS = T.inset_radius(M.ROW_RADIUS, M.CONTROL_INSET)
M.OVERLAP = 18

-- The surface: the top corners rounded, the bottom tucked under what
-- overlaps it by 18.
M.surface = ui.component(function(props: SurfaceProps): Node
	local overlap = props.overlap or M.OVERLAP
	return ui.column {
		id = props.id,
		w = props.w,
		pt = T.space(frost.INSET),
		px = T.space(frost.INSET),
		pb = T.space(frost.INSET + overlap),
		gap = "$zeron.space.4",
		rounded_tl = T.radius(M.RADIUS),
		rounded_tr = T.radius(M.RADIUS),
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		{ table.unpack(props) },
	}
end)

local function glyph(t: Todo, live: boolean): Node
	return ui.row {
		w = 14,
		h = 17,
		items = "center",
		justify = "center",
		shrink = 0,
		if t.state == "done"
			then icon { name = "check", size = 12, color = T.success }
			elseif t.state == "active" and live then loaders.mini_spinner { cell = 2 }
			elseif t.state == "active" then ui.row {
				w = 10,
				h = 10,
				rounded = "$zeron.radius.5",
				border = 1,
				border_color = T.accent,
				items = "center",
				justify = "center",
				ui.div { w = 4, h = 4, rounded = "$zeron.radius.2", bg = T.accent },
			}
			else ui.div {
				w = 10,
				h = 10,
				rounded = "$zeron.radius.5",
				border = 1,
				border_color = T.tertiary,
				opacity = 0.7,
			},
	}
end

local function todo_row(t: Todo, live: boolean): Node
	return ui.row {
		min_h = 26,
		px = "$zeron.space.8",
		py = "$zeron.space.4",
		gap = "$zeron.space.8",
		items = "center",
		glyph(t, live),
		txt.text {
			t.text,
			size = "sm",
			weight = if t.state == "active" then "medium" else "regular",
			color = if t.state == "done" then T.tertiary elseif t.state == "active" then T.text else T.secondary,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
		},
	}
end

-- The todo tray: a 32-high header row (icon, "Todo", done/total, the
-- current item when collapsed, a chevron, dismiss), rows at 26 that fold.
-- Docked over the composer, it rises as it opens: its chevron turns up.
M.todo = ui.component(function(props: TodoProps): Node
	local done, total, current = 0, #props.items, nil :: Todo?
	for _, t in props.items do
		if t.state == "done" then
			done += 1
		elseif t.state == "active" and not current then
			current = t
		end
	end
	local all_done = done == total
	local rows: { Node } = {}
	for _, t in props.items do
		table.insert(rows, todo_row(t, props.live == true))
	end
	return M.surface {
		id = props.id,
		w = props.w,
		ui.button {
			variants = recipes.disclosure { tone = "plain" },
			id = props.id and `{props.id}_header`,
			w_full = true,
			h = 32,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			rounded = T.radius(M.ROW_RADIUS),
			cursor = "pointer",
			focus = { border = 0 },
			on_click = ui.toggle(props.open),
			icon {
				name = if all_done then "check" else "checklist",
				size = 14,
				color = if all_done then T.success else T.secondary,
			},
			txt.text { "Todo", size = "sm", weight = "medium", line = false },
			txt.text { `{done}/{total}`, size = "sm", color = T.tertiary, line = false },
			ui.presence(function()
				return if props.open:get() then nil else "current"
			end, function(): Node
				return txt.text {
					if all_done then "All done" elseif current then current.text else "",
					size = "sm",
					color = if all_done then T.tertiary else T.secondary,
					truncate = true,
					line = false,
					grow = 1,
					shrink = 1,
					min_w = 0,
				}
			end, {
				grow = 1,
				shrink = 1,
				min_w = 0,
				enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
				exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
			}),
			ui.div { grow = 1 },
			disclosure.chevron {
				id = props.id and `{props.id}_chevron`,
				open = props.open,
				opens = "up",
				size = 13,
			},
			icon_button {
				icon = "close",
				size = 24,
				icon_size = 11,
				label = "Dismiss",
				no_ring = true,
				on_click = props.on_dismiss,
			},
		},
		ui.presence(function()
			return if props.open:get() then "rows" else nil
		end, function(): Node
			return ui.column { w_full = true, rows }
		end, {
			w_full = true,
			layout = "height",
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST), ease = motion.EASE },
			exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
		}),
	}
end)

-- A queued message row: handle, text at 12.5 on 90%, attachment count,
-- then remove, edit and the primary action, 24-point at radius 7.
local function queue_row(q: Queued, props: QueueProps, group: string): Node
	local function act(name: ((id: string) -> ())?): (() -> ())?
		return if name
			then function()
				name(q.id)
			end
			else nil
	end
	return ui.row(wash.item(group, {
		id = props.id and `{props.id}_{q.id}`,
		h = 32,
		px = "$zeron.space.4",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius(M.ROW_RADIUS),
		ui.row {
			w = 14,
			h = 22,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.4",
			cursor = "pointer",
			shrink = 0,
			icon { name = "drag-handle", size = 13, color = T.tertiary },
		},
		txt.text { q.text, size = "sm", truncate = true, line = false, grow = 1, shrink = 1, min_w = 0, opacity = 0.9 },
		q.attachments and ui.row {
			h = 24,
			px = "$zeron.space.6",
			items = "center",
			rounded = T.radius(M.CONTROL_RADIUS),
			bg = T.ink2,
			shrink = 0,
			txt.text { `+{q.attachments}`, size = "xs", color = T.secondary, line = false },
		},
		ui.row {
			gap = "$zeron.space.3",
			items = "center",
			shrink = 0,
			icon_button {
				icon = "close",
				size = 24,
				icon_size = 13,
				label = "Remove",
				rounded = T.radius(M.CONTROL_RADIUS),
				no_ring = true,
				on_click = act(props.on_remove),
			},
			icon_button {
				icon = "pen",
				size = 24,
				icon_size = 13,
				label = "Edit",
				rounded = T.radius(M.CONTROL_RADIUS),
				no_ring = true,
				on_click = act(props.on_edit),
			},
			ui.button {
				variants = recipes.wash { hover = "ink3" },
				h = 24,
				w = 72,
				items = "center",
				justify = "center",
				rounded = T.radius(M.CONTROL_RADIUS),
				cursor = "pointer",
				focus = { border = 0 },
				on_click = act(props.on_send),
				txt.text { props.action or "Send next", size = "xs", color = T.secondary, line = false },
			},
		},
	}))
end

-- The queue tray: rows that slide as the list changes (150 ms ease-out).
M.queue = ui.component(function(props: QueueProps): Node
	local group = wash.group("queue")
	return M.surface {
		id = props.id,
		w = props.w,
		wash.list {
			group = group,
			color = T.ink1,
			ui.each(props.items, function(q: Queued)
				return queue_row(q, props, group)
			end, {
				w_full = true,
				gap = "$zeron.space.4",
				key = function(q: Queued)
					return q.id
				end,
				animate = { duration = motion.d(motion.TAB_SLIDE), ease = motion.EASE_OUT },
				enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
				exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
			}),
		},
	}
end)

return M
