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
local types = require("./types")

export type TodoState = "done" | "active" | "pending"
export type Todo = { id: string, text: string, state: TodoState }
export type TodoProps = {
	id: string?,
	items: { Todo },
	-- Whether the turn is live (the active glyph spins); the list is
	-- dismissable only while it is not.
	live: types.Cond?,
	open: State<boolean>,
	on_dismiss: Handler?,
	w: Reactive<Length>?,
}
-- A queued message's attachment: an image shows as its thumbnail.
export type QueuedFile = { name: string, src: string? }
export type Queued = { id: string, text: string, attachments: number?, files: { QueuedFile }? }
export type QueueProps = {
	id: string?,
	items: State<{ Queued }>,
	-- "Steer", "Send next" or "Send now" for every row; else each row's by
	-- what it holds and whether the harness steers mid-turn (`steers`).
	action: string?,
	steers: types.Cond?,
	on_remove: ((id: string) -> ())?,
	on_edit: ((id: string) -> ())?,
	on_send: ((id: string) -> ())?,
	-- The row being edited in the composer, which keeps its place: Save to
	-- queue and Cancel in place of its actions.
	editing: State<string?>?,
	on_save: Handler?,
	on_cancel: Handler?,
	-- A row dragged to `index`.
	on_move: ((id: string, index: number) -> ())?,
	on_open: ((file: QueuedFile) -> ())?,
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

-- The surface: the composer's material (queue_panel_surface) edged with
-- the border, the top corners rounded, the bottom tucked under what
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
		variants = recipes.composer { edge = "panel" },
		{ table.unpack(props) },
	}
end)

-- The active item's glyph spins while the turn is live.
local function active(live: types.Cond?): Node
	return ui.presence(function()
		return types.on(live)
	end, function(spinning: boolean): Node
		if spinning then
			return loaders.mini_spinner { cell = 2.5 }
		end
		return ui.row {
			w = 10,
			h = 10,
			rounded = "$zeron.radius.5",
			border = 1,
			border_color = T.accent,
			items = "center",
			justify = "center",
			ui.div { w = 4, h = 4, rounded = "$zeron.radius.2", bg = T.accent },
		}
	end)
end

local function glyph(t: Todo, live: types.Cond?): Node
	return ui.row {
		w = 14,
		h = 17,
		items = "center",
		justify = "center",
		shrink = 0,
		if t.state == "done"
			then icon { name = "check", size = 12, color = T.success }
			elseif t.state == "active" then active(live)
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

local function todo_row(t: Todo, live: types.Cond?): Node
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

-- Lists longer than this fold to three items around the current one
-- (todo_panel.rs FOLD_ABOVE, FOCUS_WINDOW).
M.FOLD_ABOVE = 6
M.FOCUS_WINDOW = 3

-- The items a long list keeps in view: the current one in the middle of
-- three (what is worked on, else what is next, else the last), clamped to
-- the ends.
function M.focus_window(items: { Todo }): (number, number)
	local total = #items
	if total <= M.FOLD_ABOVE then
		return 1, total
	end
	local focus: number? = nil
	for i, t in items do
		if t.state == "active" then
			focus = i
			break
		end
	end
	if not focus then
		for i, t in items do
			if t.state ~= "done" then
				focus = i
				break
			end
		end
	end
	local first = math.min(math.max((focus or total) - 1, 1), total - M.FOCUS_WINDOW + 1)
	return first, first + M.FOCUS_WINDOW - 1
end

-- "N earlier" / "N later": the items folded off one end, shown in place by
-- a click and folded by another; its arrow points where they are.
local function fold_row(id: string?, count: number, earlier: boolean, open: State<boolean>): Node
	local noun = if earlier then "earlier" else "later"
	return ui.button {
		variants = recipes.wash { hover = "hover" },
		id = id,
		label = function()
			return `{if open:get() then "Hide" else "Show"} {count} {noun} items`
		end,
		h = 24,
		px = "$zeron.space.8",
		gap = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.6",
		cursor = "pointer",
		focus = { border = 0 },
		on_click = ui.toggle(open),
		ui.row {
			w = 14,
			justify = "center",
			shrink = 0,
			ui.presence(function()
				return if open:get() == earlier then "alt-arrow-down" else "alt-arrow-up"
			end, function(name: string): Node
				return icon { name = name :: any, size = 12, color = T.tertiary }
			end),
		},
		txt.text { `{count} {noun}`, size = "xs", color = T.tertiary, line = false },
	}
end

-- The todo tray: a 32-high header row (icon, "Todo", done/total, the
-- current item when collapsed, a chevron, dismiss while the turn rests),
-- rows at 26 that fold; a long list keeps three in view between its folds.
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
	local first, last = M.focus_window(props.items)
	local earlier = ui.use_state(false)
	local later = ui.use_state(false)
	local function rows_of(from: number, to: number): Node
		local out: { Node } = {}
		for i = from, to do
			table.insert(out, todo_row(props.items[i], props.live))
		end
		return ui.column { w_full = true, out }
	end
	local rows: { Node } = {}
	if first > 1 then
		table.insert(rows, fold_row(props.id and `{props.id}_earlier`, first - 1, true, earlier))
		table.insert(rows, ui.show(earlier, rows_of(1, first - 1)))
	end
	table.insert(rows, rows_of(first, last))
	if last < total then
		table.insert(rows, ui.show(later, rows_of(last + 1, total)))
		table.insert(rows, fold_row(props.id and `{props.id}_later`, total - last, false, later))
	end
	return M.surface {
		id = props.id,
		w = props.w,
		-- zgx's disclosure: the header its summary button.
		ui.disclosure {
			open = props.open,
			bare = true,
			w_full = true,
			gap = "$zeron.space.4",
			summary = ui.button {
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
				ui.show(
					types.unless(props.live),
					icon_button {
						id = props.id and `{props.id}_dismiss`,
						icon = "close",
						size = 24,
						icon_size = 11,
						label = "Dismiss todo list",
						no_ring = true,
						on_click = props.on_dismiss,
					}
				),
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
		},
	}
end)

-- A queued message row (queue.rs): handle, its images' thumbnails, the text
-- at 12.5 on 90%, then remove, edit and the primary action, 24-point at
-- radius 7. The row being edited in the composer keeps its place: "Editing
-- in composer", Save to queue and Cancel. A drag reorders the rows.
M.THUMBS = 3
local function thumbs(q: Queued, props: QueueProps, key: string): { Node }
	local out: { Node } = {}
	local files: { QueuedFile } = q.files or {}
	for i, f in files do
		if i > M.THUMBS then
			break
		end
		table.insert(
			out,
			ui.button {
				id = `{key}_image_{i}`,
				label = f.name,
				tooltip = f.name,
				w = 40,
				h = 28,
				shrink = 0,
				p = 0,
				rounded = "$zeron.radius.5",
				border = 1,
				border_color = T.hairline,
				bg = T.ink1,
				overflow = "hidden",
				items = "center",
				justify = "center",
				cursor = "pointer",
				focus = { border = 1, border_color = T.accent },
				on_click = function()
					if props.on_open then
						props.on_open(f)
					end
				end,
				if f.src
					then ui.image { src = f.src, label = "", w_full = true, h_full = true, fit = "cover" }
					else icon { name = "document", size = 13, color = T.secondary },
			}
		)
	end
	if #files > M.THUMBS then
		table.insert(
			out,
			ui.row {
				id = `{key}_more`,
				w = 24,
				h = 24,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = T.radius(M.CONTROL_RADIUS),
				bg = T.ink2,
				tooltip = `{#files - M.THUMBS} more attachments`,
				txt.text { `+{#files - M.THUMBS}`, size = "xs", color = T.secondary, line = false },
			}
		)
	end
	return out
end

-- A 24-point action: its icon, or its words.
local function action(id: string, label: string, on_click: Handler?, glyph: string?): Node
	return ui.button {
		variants = recipes.wash { hover = "ink3" },
		id = id,
		label = label,
		tooltip = label,
		h = 24,
		w = if glyph then 24 else nil,
		px = if glyph then 0 else "$zeron.space.8",
		items = "center",
		justify = "center",
		rounded = T.radius(M.CONTROL_RADIUS),
		cursor = "pointer",
		color = T.secondary,
		hover = { color = T.text },
		focus = { border = 0 },
		on_click = on_click,
		if glyph
			then icon { name = glyph :: any, size = 13, color = "currentColor" }
			else txt.text { label, size = "xs", color = "currentColor", line = false },
	}
end

-- What a row's primary action is: attachments need a new request (Send
-- now); text steers a harness that takes it mid-turn, else waits for the
-- next turn (available_queue_primary_action).
local function primary(q: Queued, props: QueueProps): string
	if props.action then
		return props.action
	end
	if (q.attachments or 0) > 0 or (q.files and #q.files > 0) then
		return "Send now"
	end
	return if types.on(props.steers) then "Steer" else "Send next"
end

local function queue_row(q: Queued, props: QueueProps, group: string): Node
	local key = if props.id then `{props.id}_{q.id}` else q.id
	local function act(name: ((id: string) -> ())?): (() -> ())?
		return if name
			then function()
				name(q.id)
			end
			else nil
	end
	local function edited(): boolean
		return props.editing ~= nil and props.editing:get() == q.id
	end
	-- Where the row is now, by its id.
	local function index(): number
		for i, item in props.items:peek() do
			if item.id == q.id then
				return i
			end
		end
		return 0
	end
	local count = q.attachments or 0
	return ui.row(wash.item(group, {
		id = key,
		h = 32,
		px = "$zeron.space.4",
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.radius(M.ROW_RADIUS),
		bg = function()
			return if edited() then T.ink2 else T.clear
		end,
		-- Dragged by its handle or anywhere on it, not while it is edited;
		-- the rows it passes give way (by the half they are crossed).
		on_drag = if props.on_move
			then function(): any
				if edited() then
					return nil
				end
				return { kind = "queued", id = q.id }
			end
			else nil,
		drop_when = function(payload: any): boolean
			return type(payload) == "table" and payload.kind == "queued"
		end,
		on_drag_over = function(payload: any, p: DragPoint)
			if payload.id == q.id or not props.on_move then
				return
			end
			local from, to = 0, index()
			for i, item in props.items:peek() do
				if item.id == payload.id then
					from = i
				end
			end
			if from == 0 or to == 0 then
				return
			end
			if (from < to and p.local_y > p.h / 2) or (from > to and p.local_y < p.h / 2) then
				(props.on_move :: (id: string, index: number) -> ())(payload.id, to)
			end
		end,
		ui.row {
			id = `{key}_drag`,
			w = 14,
			h = 22,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.4",
			cursor = "pointer",
			shrink = 0,
			ui.show(function()
				return not edited()
			end, icon { name = "queue-drag-handle", size = 13, color = T.tertiary, opacity = 0.7 }),
		},
		ui.presence(function()
			return if edited() then "editing" else "row"
		end, function(mode: string): Node
			if mode == "editing" then
				return ui.row {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.8",
					items = "center",
					txt.text {
						"Editing in composer",
						size = "sm",
						color = T.secondary,
						truncate = true,
						line = false,
						grow = 1,
						shrink = 1,
						min_w = 0,
					},
					ui.row {
						gap = "$zeron.space.3",
						items = "center",
						shrink = 0,
						action(`{key}_save`, "Save to queue", props.on_save, "queue-check"),
						action(`{key}_cancel`, "Cancel", props.on_cancel, "queue-close"),
					},
				}
			end
			local tiles = thumbs(q, props, key)
			return ui.row {
				grow = 1,
				shrink = 1,
				min_w = 0,
				gap = "$zeron.space.8",
				items = "center",
				tiles,
				txt.text {
					q.text,
					size = "sm",
					truncate = true,
					line = false,
					grow = 1,
					shrink = 1,
					min_w = 0,
					opacity = 0.9,
				},
				#tiles == 0 and count > 0 and ui.row {
					h = 24,
					px = "$zeron.space.6",
					items = "center",
					rounded = T.radius(M.CONTROL_RADIUS),
					bg = T.ink2,
					shrink = 0,
					txt.text { `+{count}`, size = "xs", color = T.secondary, line = false },
				},
				ui.row {
					gap = "$zeron.space.3",
					items = "center",
					shrink = 0,
					action(`{key}_remove`, "Remove", act(props.on_remove), "trash-bin-minimalistic"),
					action(`{key}_edit`, "Edit", act(props.on_edit), "pen"),
					action(`{key}_send`, primary(q, props), act(props.on_send)),
				},
			}
		end, { grow = 1, shrink = 1, min_w = 0 }),
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
