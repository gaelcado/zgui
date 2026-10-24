-- Toasts: short notices stacked at the window's bottom right, each leaving
-- on its own after a few seconds, on dismissal, or when its action runs.
-- `toast.push` adds one from anywhere; `toast.host()` is placed once, in
-- the app's root (which must be `relative`).
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
local serial = 0

function M.dismiss(id: string)
	for i, t in M.toasts:peek() do
		if t.id == id then
			M.toasts:remove(i)
		end
	end
	handlers[id] = nil
	local stop = timers[id]
	if stop then
		stop()
		timers[id] = nil
	end
end

-- How long a toast stays (sonner's four seconds); what the pointer over
-- the stack holds.
M.DURATION = 4000

local function arm(id: string, duration: number)
	if timers[id] then
		timers[id]()
	end
	timers[id] = ui.after(duration, function()
		timers[id] = nil
		M.dismiss(id)
	end)
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
	if push.on_action then
		handlers[id] = push.on_action
	end
	local duration = push.duration or M.DURATION
	if duration > 0 then
		arm(id, duration)
	end
	return id
end

-- The pointer over the stack holds every toast; leaving, each has its
-- time again.
local function hold(on: boolean)
	for _, t in M.toasts:peek() do
		local duration = t.duration or M.DURATION
		if duration > 0 then
			if on then
				if timers[t.id] then
					timers[t.id]()
					timers[t.id] = nil
				end
			else
				arm(t.id, duration)
			end
		end
	end
end

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

-- The stack, 24 in from the app root's bottom right (which must be
-- `relative`), 14 apart, the newest at the bottom; the pointer over it
-- holds their time. New ones rise in, gone ones fade.
function M.host(): Node
	return ui.column {
		id = "toasts",
		absolute = true,
		right = "$zeron.space.24",
		bottom = "$zeron.space.24",
		items = "end",
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
			return M.card(props)
		end, {
			gap = "$zeron.space.14",
			items = "end",
			key = function(toast: Toast)
				return toast.id
			end,
			animate = { duration = 400, ease = "cubicBezier(0.215, 0.61, 0.355, 1)" },
			enter = { opacity = { 0, 1 }, y = { 76, 0 }, duration = 400, ease = "cubicBezier(0.215, 0.61, 0.355, 1)" },
			exit = { opacity = 0, duration = 200, ease = motion.EASE },
		}),
	}
end

return M
