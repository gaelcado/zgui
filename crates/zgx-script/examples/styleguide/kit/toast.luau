-- Toasts: short notices stacked at the window's bottom right, each leaving
-- on its own after a few seconds, on dismissal, or when its action runs.
-- `toast.push` adds one from anywhere; `toast.host()` is placed once, in
-- the app's root (its stack on a layer of its own, over dialogs).
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Tone = VariantOption<typeof(recipes.toast_icon), "tone">
export type Toast = {
	id: string,
	title: string,
	description: string?,
	tone: Tone?,
	action: string?,
	-- How long it stays, in ms; 0 keeps it until dismissed.
	duration: number?,
}
export type Push = {
	title: string,
	description: string?,
	tone: Tone?,
	action: string?,
	on_action: Handler?,
	duration: number?,
}

local M = {}

M.toasts = ui.state("toasts", {} :: { Toast })
local handlers: { [string]: Handler } = {}
local timers: { [string]: () -> () } = {}
-- Each toast's time left, in ms, and when it last started counting it
-- down (nil while held).
local left: { [string]: number } = {}
local since: { [string]: number } = {}
local serial = 0

-- How long a dismissed toast fades.
local EXIT = 200

-- The stack (sonner's, toast.rs): collapsed, the newest in front and the
-- two before it peeking 14 above it, each 5% narrower, clipped to the
-- front's height (later ones wait unseen behind them); under the pointer
-- it fans out into a list, 14 apart. Each toast eases to its place over
-- 400 ms on sonner's curve, in the engine (an animatable per toast, set
-- as the stack changes: no script per frame).
local GAP = 14
local VISIBLE = 3
local STEP = 0.05
local MOVE = 400
local EASE = "cubicBezier(0.215, 0.61, 0.355, 1)"
-- A toast's height until it is measured.
local FRONT = 52
local expanded = false
local heights: { [string]: number } = {}
local slots: { [string]: Animatable } = {}
local stack_h = ui.state("toasts_height", 0)

-- Where toast `id` rests now: its offset from the stack's foot, scale,
-- clip at its foot and opacity.
local function targets(): { [string]: { number } }
	local list = M.toasts:peek()
	local n = #list
	local front = list[n]
	local tall = if front then heights[front.id] or FRONT else FRONT
	local out: { [string]: { number } } = {}
	local below = 0
	for i = n, 1, -1 do
		local t = list[i]
		local depth = n - i
		local h = heights[t.id] or tall
		out[t.id] = if expanded
			then { -below, 1, 0, 1 }
			else {
				h - tall - GAP * depth,
				1 - STEP * math.min(depth, VISIBLE),
				math.max(0, h - tall),
				if depth >= VISIBLE then 0 else 1,
			}
		below += h + GAP
	end
	stack_h:set(if n == 0 then 0 elseif expanded then below - GAP else tall + GAP * (n - 1))
	return out
end

-- Whether toast `id` is up (not leaving).
local function live(id: string): boolean
	for _, t in M.toasts:peek() do
		if t.id == id then
			return true
		end
	end
	return false
end

local function place(a: Animatable, at: { number }, duration: number)
	a.y(at[1], duration)
	a.scale(at[2], duration)
	a.clipBottom(at[3], duration)
	a.opacity(at[4], duration)
end

-- Every toast to its place; `snap` lands at once.
local function relayout(snap: string?)
	for id, at in targets() do
		local a = slots[id]
		if a then
			place(a, at, if id == snap then 0 else motion.d(MOVE))
		end
	end
end
-- The stack's layer is open while a toast shows, and through the last
-- one's fade: each time it opens it is raised over everything, a dialog's
-- backdrop included.
local shown = ui.state("toasts_shown", false)
local hiding: (() -> ())? = nil
local function show()
	if hiding then
		hiding()
		hiding = nil
	end
	if not shown:peek() then
		shown:set(true)
	end
end

function M.dismiss(id: string)
	for i, t in M.toasts:peek() do
		if t.id == id then
			M.toasts:remove(i)
		end
	end
	handlers[id] = nil
	slots[id] = nil
	heights[id] = nil
	left[id] = nil
	since[id] = nil
	local stop = timers[id]
	if stop then
		stop()
		timers[id] = nil
	end
	if #M.toasts:peek() == 0 then
		expanded = false
	end
	relayout()
	if #M.toasts:peek() == 0 and shown:peek() and not hiding then
		hiding = ui.after(EXIT, function()
			hiding = nil
			if #M.toasts:peek() == 0 then
				shown:set(false)
			end
		end)
	end
end

-- How long a toast stays (sonner's four seconds), counted down only while
-- the pointer is off the stack and the window is active: paused, a toast
-- keeps the time it has left, and resumes it.
M.DURATION = 4000

local function paused(): boolean
	return expanded or not ui.window.active:peek()
end

-- Count `id`'s time down from what it has left.
local function resume(id: string)
	local ms = left[id]
	if not ms or since[id] or paused() then
		return
	end
	since[id] = ui.now()
	timers[id] = ui.after(ms, function()
		timers[id] = nil
		M.dismiss(id)
	end)
end

-- Hold `id`'s time where it is.
local function pause(id: string)
	local at = since[id]
	if not at then
		return
	end
	since[id] = nil
	left[id] = math.max(0, (left[id] or 0) - (ui.now() - at))
	local stop = timers[id]
	if stop then
		stop()
		timers[id] = nil
	end
end

-- `id`'s time from the start, counting now unless paused.
local function arm(id: string, duration: number)
	pause(id)
	left[id] = duration
	resume(id)
end

function M.push(push: Push): string
	-- The same message as the front toast's restarts its time instead.
	local list = M.toasts:peek()
	local front = list[#list]
	local title = string.match(push.title, "^%s*(.-)%s*$") or ""
	if title == "" then
		return ""
	end
	if front and front.title == title and front.tone == push.tone and front.description == push.description then
		if (front.duration or M.DURATION) > 0 then
			arm(front.id, front.duration or M.DURATION)
		end
		return front.id
	end
	serial += 1
	local id = `toast{serial}`
	M.toasts:push {
		id = id,
		title = title,
		description = push.description,
		tone = push.tone,
		action = push.action,
		duration = push.duration,
	}
	relayout()
	show()
	if push.on_action then
		handlers[id] = push.on_action
	end
	-- Under the pointer it waits with the others, timed once it leaves.
	local duration = push.duration or M.DURATION
	if duration > 0 then
		arm(id, duration)
	end
	return id
end

-- Every toast's time held, or counting again.
local function follow()
	for _, t in M.toasts:peek() do
		if paused() then
			pause(t.id)
		else
			resume(t.id)
		end
	end
end

-- The pointer over the stack fans it out and holds every toast; leaving,
-- it collapses and each counts down what it had left.
local function hold(on: boolean)
	if expanded ~= on then
		expanded = on
		relayout()
	end
	follow()
end

-- The window going to the back holds them too; coming forward, they go on.
ui.effect(function()
	local _ = ui.window.active:get()
	follow()
end)

local ICON: { [Tone]: icon_mod.Name } = {
	neutral = "info-circle",
	success = "check",
	danger = "danger-triangle",
	warning = "danger-triangle",
	info = "info-circle",
}

-- One toast, as a card (toast.rs, sonner's): 356 wide, radius 12, the
-- popover's frosted surface edged in the border; 14 by 13 inside, its 16
-- icon in its tone 10 from the message at 13. No close button: a swipe to
-- the right of 45 or more dismisses it (it fades as it goes), less springs
-- back. An action is a small solid button (24, the text colour).
export type CardProps = Toast & { on_dismiss: (() -> ())?, on_action: (() -> ())? }
M.card = ui.component(function(toast: CardProps): Node
	local on_dismiss, on_action = toast.on_dismiss, toast.on_action
	local tone: Tone = toast.tone or "neutral"
	local swipe = ui.use_state(0)
	local from: number? = nil
	return ui.row {
		id = toast.id,
		variants = recipes.toast,
		role = "status",
		x = function()
			return swipe:get()
		end,
		opacity = function()
			return math.clamp(1 - swipe:get() / (M.WIDTH * 0.6), 0, 1)
		end,
		on_press = function(e: PointerEvent)
			from = e.x
		end,
		on_press_move = function(e: PointerEvent)
			if from then
				swipe:set(math.max(0, e.x - from))
			end
		end,
		on_release = function()
			from = nil
			if swipe:peek() >= M.SWIPE then
				if on_dismiss then
					on_dismiss()
				end
			else
				swipe:set(0)
			end
		end,
		icon { name = ICON[tone], size = 16, color = "currentColor", variants = recipes.toast_icon { tone = tone } },
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { toast.title, literal = true, size = "md", wrap = true },
			toast.description and txt.text {
				toast.description,
				literal = true,
				size = "sm",
				color = T.secondary,
				wrap = true,
			},
		},
		toast.action and ui.button {
			id = `{toast.id}_action`,
			h = 24,
			px = "$zeron.space.8",
			shrink = 0,
			items = "center",
			rounded = T.radius_md,
			bg = T.text,
			color = T.bg,
			hover = { opacity = 0.85 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = on_action,
			txt.text { toast.action, literal = true, size = "sm", weight = "medium", color = "inherit", line = false },
		},
	}
end)

M.WIDTH = 356
M.SWIPE = 45

-- The stack, 24 in from the window's bottom right, on a layer of its own
-- (`ui.layer`: over dialogs, taking no focus, clickable while a dialog
-- holds it): each toast stands at its foot and is moved to its place
-- (`targets`), the newest in front; the stack is as tall as it shows, so
-- the pointer over it, and only then, fans it out and holds their time.
-- New ones rise in from below, gone ones fade as they sink.
function M.host(): Node
	return ui.layer {
		open = shown,
		placement = { x = "end", y = "end", inset = 24 },
		ui.div {
			id = "toasts",
			relative = true,
			w = M.WIDTH,
			h = function()
				return stack_h:get()
			end,
			on_hover = hold,
			ui.each(M.toasts, function(toast: Toast)
				local props = table.clone(toast) :: CardProps
				props.on_dismiss = function()
					M.dismiss(toast.id)
				end
				props.on_action = function()
					local run = handlers[toast.id]
					M.dismiss(toast.id)
					if run then
						run()
					end
				end
				local id = toast.id
				return ui.div {
					absolute = true,
					left = 0,
					bottom = 0,
					w = M.WIDTH,
					ui.div {
						id = `{id}_slot`,
						w_full = true,
						origin = { 0.5, 0 },
						on_mount = function(el: Element)
							local timing = { duration = motion.d(MOVE), ease = EASE }
							slots[id] = anime.createAnimatable(el, {
								y = timing,
								scale = timing,
								clipBottom = timing,
								opacity = timing,
							})
							local at = targets()[id]
							if at then
								place(slots[id], at, 0)
							end
						end,
						-- Its height places the others; the first lands at once.
						on_resize = function(size: Size)
							if not live(id) then
								return
							end
							local first = heights[id] == nil
							heights[id] = size.h
							relayout(if first then id else nil)
						end,
						M.card(props),
					},
				}
			end, {
				key = function(toast: Toast)
					return toast.id
				end,
				enter = {
					opacity = { 0, 1 },
					y = { 76, 0 },
					duration = MOVE,
					ease = EASE,
				},
				exit = { opacity = 0, y = GAP, duration = EXIT, ease = motion.EASE },
			}),
		},
	}
end

return M
