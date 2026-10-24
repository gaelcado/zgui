-- The reasoning slider (pickers/compact.rs): a 28 rail of light glass
-- under a 44×32 white pill thumb that overhangs it by 2, in a 36 box. The
-- stops (both ends and every advertised level) and the pointer share the
-- thumb's centre inset of 22; the accent fill runs from the rail's start to
-- 14 past the centre, always hidden under the thumb. The thumb glides to a
-- stop over 200 ms ease-out, follows the pointer while dragging, and a
-- press only lifts it on a softer, wider drop. Fast mode breathes an accent
-- halo under the thumb and a band of light flows through the fill toward
-- it; the filled stops follow the animated front, never ahead of it.
-- Each stop the pointer crosses taps the trackpad (`ui.haptic`).
local T = require("../theme")
local recipes = require("./recipes")
local motion = require("./motion")

export type Props = {
	id: string?,
	-- The level names, left to right.
	levels: { string },
	-- The chosen level, 1-based.
	selected: State<number>,
	-- Fast mode on: the fill comes alive.
	fast: State<boolean>?,
	-- Set while the thumb is being dragged, for the title to follow.
	dragging: State<boolean>?,
	w: Length?,
	on_change: ((index: number) -> ())?,
}

local M = {}

M.HEIGHT = 36
M.RAIL = 28
M.RAIL_TOP = (36 - 28) / 2
M.THUMB_W = 44
M.THUMB_H = 32
M.INSET = 22
M.FILL_PAST = 14
M.STOP = 4
M.MOVE = motion.RESIZE
M.BAND = 72
M.FLOW = 1800
M.BREATH = 1600

local function fraction_at(x: number, width: number): number
	return math.clamp((x - M.INSET) / math.max(width - 2 * M.INSET, 1), 0, 1)
end

local function index_at(x: number, width: number, count: number): number
	return math.floor(fraction_at(x, width) * (count - 1) + 0.5) + 1
end

return ui.component(function(props: Props): Node
	local count = #props.levels
	-- Gradients take colours, not tokens: resolved when the slider is built.
	local band = ui.theme.get("zeron.effort.band")
	local glass_top = ui.theme.get("zeron.glass.light.top")
	local glass_bottom = ui.theme.get("zeron.glass.light.bottom")
	local key = props.id or "effort_slider"
	local ref = ui.ref()
	local width = ui.state(`{key}_width`, 0)
	local dragging = props.dragging or ui.state(`{key}_dragging`, false)
	local function stop_fraction(i: number): number
		return if count > 1 then (i - 1) / (count - 1) else 0
	end
	-- The front: animated to the stop, or the pointer while dragging.
	local frac = ui.state(`{key}_frac`, stop_fraction(props.selected:peek()))
	local glide: Animation? = nil
	local function glide_to(to: number)
		if glide then
			glide:cancel()
		end
		if math.abs(to - frac:peek()) < 0.0005 then
			frac:set(to)
			return
		end
		-- anime writes the state itself, without a script call per frame.
		glide = (anime.animate :: any)(frac, {
			value = to,
			duration = motion.d(M.MOVE),
			ease = motion.EASE_OUT,
			onComplete = function()
				glide = nil
				frac:set(to)
			end,
		}) :: Animation
	end
	ui.effect(function()
		local i = props.selected:get()
		if not dragging:peek() then
			glide_to(stop_fraction(i))
		end
	end)
	local function fast_on(): boolean
		return if props.fast then props.fast:get() else false
	end
	local function run(): number
		return math.max(width:get() - 2 * M.INSET, 0)
	end
	local function center(): number
		return M.INSET + frac:get() * run()
	end
	local function fill_end(): number
		return math.min(center() + M.FILL_PAST, width:get())
	end

	local function pick(x: number)
		local el = ref:peek()
		local w = width:peek()
		if not el or w <= 0 then
			return
		end
		local local_x = x - (el.x or 0)
		frac:set(fraction_at(local_x, w))
		local i = index_at(local_x, w, count)
		if i ~= props.selected:peek() then
			props.selected:set(i)
			-- A detent under the finger at each stop crossed (haptics.rs).
			ui.haptic("level")
			if props.on_change then
				props.on_change(i)
			end
		end
	end

	-- The stops, on a canvas over rail and fill in one coordinate space.
	local stops = ui.canvas {
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		bottom = 0,
		pointer_events = "none",
		draw = function(cv: Canvas, w: number, _h: number)
			local f = frac:get()
			local span = math.max(w - 2 * M.INSET, 0)
			local filled = tostring(ui.theme.get("zeron.effort.stop.filled"))
			local open = tostring(ui.theme.get("zeron.effort.stop.open"))
			for i = 1, count do
				local s = stop_fraction(i)
				local x = M.INSET + s * span
				cv.rect(
					cv,
					x - M.STOP / 2,
					M.HEIGHT / 2 - M.STOP / 2,
					M.STOP,
					M.STOP,
					if s <= f + 0.0005 then filled else open,
					M.STOP / 2
				)
			end
		end,
	}

	-- The accent fill, from the rail's start to just past the thumb's
	-- centre; in fast mode a band of light flows through it toward the
	-- thumb, clipped to the plate.
	local fill = ui.div {
		absolute = true,
		left = 0,
		top = M.RAIL_TOP,
		h = M.RAIL,
		w = fill_end,
		rounded = T.radius_full,
		overflow = "hidden",
		bg = T.accent,
		pointer_events = "none",
		ui.div {
			absolute = true,
			left = 1,
			right = 1,
			top = 1,
			h = M.RAIL / 2 - 1,
			rounded = T.radius_full,
			bg = "$zeron.effort.gloss",
		},
		-- A presence, not `show`: a hidden loop would keep asking for frames.
		ui.presence(function()
			return if fast_on() then "on" else nil
		end, function(): Node
			return ui.div {
				absolute = true,
				top = 0,
				bottom = 0,
				w = M.BAND,
				left = if motion.loops()
					then ui.loop { from = -M.BAND, to = 320, duration = M.FLOW, yoyo = false }
					else 0,
				gradient = { angle = 90, stops = { { 0, "#ffffff00" }, { 0.5, band }, { 1, "#ffffff00" } } },
			}
		end, {
			absolute = true,
			top = 0,
			left = 0,
			right = 0,
			bottom = 0,
			enter = { opacity = { 0, 1 }, duration = motion.d(M.MOVE) },
			exit = { opacity = 0, duration = motion.d(M.MOVE) },
		}),
	}

	local thumb = ui.div {
		id = props.id and props.id .. "_thumb",
		absolute = true,
		top = (M.HEIGHT - M.THUMB_H) / 2,
		left = function()
			return center() - M.THUMB_W / 2
		end,
		w = M.THUMB_W,
		h = M.THUMB_H,
		rounded = T.radius_full,
		pointer_events = "none",
		-- Fast mode breathes an accent halo under the handle.
		ui.presence(function()
			return if fast_on() then "on" else nil
		end, function(): Node
			return ui.div {
				w_full = true,
				h_full = true,
				rounded = T.radius_full,
				shadow = "$zeron.effort.glow",
				opacity = if motion.loops() then ui.loop { from = 0.55, to = 1, duration = M.BREATH } else 0.8,
			}
		end, {
			absolute = true,
			top = 0,
			left = 0,
			right = 0,
			bottom = 0,
			enter = { opacity = { 0, 1 }, duration = motion.d(M.MOVE) },
			exit = { opacity = 0, duration = motion.d(M.MOVE) },
		}),
		ui.div {
			absolute = true,
			top = 0,
			left = 0,
			right = 0,
			bottom = 0,
			rounded = T.radius_full,
			gradient = { angle = 180, stops = { { 0, "#ffffff" }, { 1, "#f6f6f6" } } },
			border = 1,
			border_color = "$zeron.effort.thumb.border",
			variants = recipes.effort_thumb { lifted = dragging },
		},
	}

	return ui.div {
		id = props.id,
		ref = ref,
		relative = true,
		h = M.HEIGHT,
		w = props.w,
		w_full = props.w == nil,
		cursor = "pointer",
		-- A press takes the keyboard, so the card's keys follow a click here.
		focusable = true,
		focus = { border = 0 },
		on_resize = function(size: Size)
			width:set(size.w)
		end,
		on_press = function(e: PointerEvent)
			local el = ref:peek()
			if el then
				el:focus()
			end
			dragging:set(true)
			if glide then
				glide:cancel()
				glide = nil
			end
			pick(e.x)
		end,
		on_pointer_move = function(e: PointerEvent)
			if dragging:peek() then
				pick(e.x)
			end
		end,
		on_release = function()
			if dragging:peek() then
				dragging:set(false)
				glide_to(stop_fraction(props.selected:peek()))
			end
		end,
		-- The rail: light glass, a hairline rim.
		ui.div {
			absolute = true,
			left = 0,
			right = 0,
			top = M.RAIL_TOP,
			h = M.RAIL,
			rounded = T.radius_full,
			gradient = { angle = 180, stops = { { 0, glass_top }, { 1, glass_bottom } } },
			border = 1,
			border_color = T.ink3,
			pointer_events = "none",
		},
		fill,
		stops,
		thumb,
	}
end)
