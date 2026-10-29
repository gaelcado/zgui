-- The image viewer (attachments.rs lightbox, image_viewer.rs): an image
-- over the window's scrim, fitted into 90% of its width and 85% of its
-- height, never past its own size; its name under it at 11 in the faint
-- ink, 12 below. A pinch zooms it about the fingers, ⌘ or Ctrl with the
-- wheel about the pointer (from a hundredth of its pixels to 32 times
-- them); the wheel and a drag (past 4 points) pan it, bounded by its
-- edges, an image smaller than the window kept in the middle. A click
-- that is no drag, Escape or the scrim closes it. It fades in over 140
-- ms; nothing runs while it rests.
--
-- One viewer for the window: `M.open(image)` from anywhere, `M.host()` at
-- the window's root (over everything, as the palette is).
local T = require("../theme")
local txt = require("./text")
local motion = require("./motion")

export type Image = { src: string, name: string, w: number, h: number }

local M = {}

-- What it shows, nil while it is closed.
M.image = ui.state("lightbox_image", nil :: Image?)

function M.open(image: Image)
	M.image:set(image)
end

function M.close()
	M.image:set(nil)
end

-- The fitted size of `image` in a `w`×`h` window.
function M.fit(image: Image, w: number, h: number): (number, number)
	local s = M.fit_scale(image, w, h)
	return image.w * s, image.h * s
end
function M.fit_scale(image: Image, w: number, h: number): number
	return math.min(w * 0.9 / image.w, h * 0.85 / image.h, 1)
end

-- Its scale's bounds, against its pixels (image_viewer.rs zoom_bounds):
-- a hundredth of them (or its fit, if smaller) to 32 times them, less for
-- a huge one, never under its fit.
function M.bounds(image: Image, fit: number): (number, number)
	local most = math.max(math.min(131072 / math.max(image.w, image.h), 32), fit)
	return math.min(fit, 0.01), most
end

-- Panning past this many points is a drag, not a click.
local DRAG = 4

local function view(image: Image): Node
	-- Its scale against the fit (1 fitted) and its offset from the middle.
	local zoom = ui.use_state(1)
	local pan_x = ui.use_state(0)
	local pan_y = ui.use_state(0)
	local size = ui.use_state { w = 0, h = 0 }
	local fitted = ui.computed(function(): { number }
		local s = size:get()
		local w, h = M.fit(image, s.w, s.h)
		return { w, h }
	end)
	local frame = ui.ref()
	-- Zoomed, the pan keeps the image over the window.
	local function clamp_pan(x: number, y: number, z: number?): (number, number)
		local f, s = fitted:peek(), size:peek()
		local k = z or zoom:peek()
		local lx = math.max((f[1] * k - s.w) / 2, 0)
		local ly = math.max((f[2] * k - s.h) / 2, 0)
		return math.clamp(x, -lx, lx), math.clamp(y, -ly, ly)
	end
	-- Zooms to `z` about the window's point (`x`, `y`): what is under it
	-- stays put (image_viewer.rs zoom_about).
	local function zoom_about(z: number, x: number, y: number)
		local s = size:peek()
		local fit = M.fit_scale(image, s.w, s.h)
		if fit <= 0 then
			return
		end
		local least, most = M.bounds(image, fit)
		local was = zoom:peek()
		local now = math.clamp(z, least / fit, most / fit)
		if now == was then
			return
		end
		-- From the image's middle as laid out (before its pan and scale).
		local el = frame:peek()
		local cx = if el and el.x and el.width then el.x + el.width / 2 else s.w / 2
		local cy = if el and el.y and el.height then el.y + el.height / 2 else s.h / 2
		local ax, ay = x - cx, y - cy
		local px, py = clamp_pan(ax - (ax - pan_x:peek()) * now / was, ay - (ay - pan_y:peek()) * now / was, now)
		zoom:set(now)
		pan_x:set(px)
		pan_y:set(py)
	end
	-- A press and where the image was then; whether it has moved a drag's
	-- worth since.
	local pressed: { x: number, y: number, px: number, py: number }? = nil
	local dragged = false
	return ui.column {
		id = "image_viewer",
		absolute = true,
		left = 0,
		top = 0,
		right = 0,
		bottom = 0,
		bg = T.scrim,
		items = "center",
		justify = "center",
		gap = "$zeron.space.12",
		overflow = "hidden",
		focusable = true,
		label = image.name,
		on_key = function(e: KeyEvent): boolean
			if e.key == "Escape" then
				M.close()
				return true
			end
			return false
		end,
		on_click = function()
			if not dragged then
				M.close()
			end
			dragged = false
		end,
		on_resize = function(s: Size)
			size:set(s)
			local x, y = clamp_pan(pan_x:peek(), pan_y:peek())
			pan_x:set(x)
			pan_y:set(y)
		end,
		on_pinch = function(e: PinchEvent): boolean
			zoom_about(zoom:peek() * math.max(1 + e.scale, 0.001), e.x, e.y)
			return true
		end,
		on_wheel = function(e: WheelEvent): boolean
			-- Scrolling up (the content coming down) zooms in.
			if e.ctrl or e.meta then
				zoom_about(zoom:peek() * math.exp(math.clamp(-e.dy * 0.0025, -2, 2)), e.x, e.y)
				return true
			end
			local x, y = clamp_pan(pan_x:peek() - e.dx, pan_y:peek() - e.dy)
			if x == pan_x:peek() and y == pan_y:peek() then
				return false
			end
			pan_x:set(x)
			pan_y:set(y)
			return true
		end,
		on_mount = function(el: Element)
			el:focus()
			anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(motion.FAST), ease = motion.EASE_OUT })
		end,
		ui.div {
			id = "image_viewer_image",
			ref = frame,
			label = image.name,
			w = function()
				return fitted:get()[1]
			end,
			h = function()
				return fitted:get()[2]
			end,
			shrink = 0,
			scale = zoom,
			x = pan_x,
			y = pan_y,
			on_press = function(e: PointerEvent)
				pressed = { x = e.x, y = e.y, px = pan_x:peek(), py = pan_y:peek() }
				dragged = false
			end,
			on_press_move = function(e: PointerEvent)
				local p = pressed
				if not p then
					return
				end
				if not dragged and math.sqrt((e.x - p.x) ^ 2 + (e.y - p.y) ^ 2) < DRAG then
					return
				end
				dragged = true
				local x, y = clamp_pan(p.px + e.x - p.x, p.py + e.y - p.y)
				pan_x:set(x)
				pan_y:set(y)
			end,
			on_release = function()
				pressed = nil
			end,
			ui.image { src = image.src, label = image.name, w_full = true, h_full = true, fit = "contain" },
		},
		txt.text {
			image.name,
			literal = true,
			size = "xs",
			color = T.tertiary,
			truncate = true,
			line = false,
			max_w = "90%",
		},
	}
end

-- The viewer, over the window while it holds an image; at the root.
function M.host(): Node
	return ui.presence(function()
		local image = M.image:get()
		return if image then image.src else nil
	end, function(): Node
		return view(M.image:peek() :: Image)
	end, {
		absolute = true,
		left = 0,
		top = 0,
		right = 0,
		bottom = 0,
		exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
	})
end

return M
