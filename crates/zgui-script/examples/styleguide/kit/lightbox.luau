-- The image viewer (attachments.rs lightbox, image_viewer.rs): an image
-- over the window's scrim, fitted into 90% of its width and 85% of its
-- height, never past its own size; its name under it at 11 in the faint
-- ink, 12 below. A click on the image zooms it to its pixels about the
-- click (2× one shown at its size) and back; zoomed, the wheel pans it,
-- bounded by its edges. Escape or a click on the scrim closes it. It
-- fades in over 140 ms and the zoom springs; nothing runs while it rests.
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
	local s = math.min(w * 0.9 / image.w, h * 0.85 / image.h, 1)
	return image.w * s, image.h * s
end

local SPRING = { stiffness = 320, damping = 32 }

local function view(image: Image): Node
	local zoom = ui.use_state(1)
	local pan_x = ui.use_state(0)
	local pan_y = ui.use_state(0)
	local size = ui.use_state { w = 0, h = 0 }
	local fitted = ui.computed(function(): { number }
		local s = size:get()
		local w, h = M.fit(image, s.w, s.h)
		return { w, h }
	end)
	-- Zoomed, the pan keeps the image over the window.
	local function clamp_pan(x: number, y: number): (number, number)
		local f, s, z = fitted:peek(), size:peek(), zoom:peek()
		local lx = math.max((f[1] * z - s.w) / 2, 0)
		local ly = math.max((f[2] * z - s.h) / 2, 0)
		return math.clamp(x, -lx, lx), math.clamp(y, -ly, ly)
	end
	-- Where the last press on the image was, in it: the zoom's centre.
	local pressed = { x = 0, y = 0 }
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
		on_click = M.close,
		on_resize = function(s: Size)
			size:set(s)
		end,
		on_wheel = function(e: WheelEvent)
			if zoom:peek() > 1 then
				local x, y = clamp_pan(pan_x:peek() - e.dx, pan_y:peek() - e.dy)
				pan_x:set(x)
				pan_y:set(y)
			end
		end,
		on_mount = function(el: Element)
			el:focus()
			anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(motion.FAST), ease = motion.EASE_OUT })
		end,
		ui.button {
			id = "image_viewer_image",
			label = image.name,
			p = 0,
			bg = T.clear,
			border = 0,
			focus = { border = 0 },
			cursor = function()
				return if zoom:get() > 1 then "zoom_out" else "zoom_in"
			end,
			w = function()
				return fitted:get()[1]
			end,
			h = function()
				return fitted:get()[2]
			end,
			shrink = 0,
			scale = ui.spring(zoom, { stiffness = SPRING.stiffness, damping = SPRING.damping }),
			x = ui.spring(pan_x, { stiffness = SPRING.stiffness, damping = SPRING.damping }),
			y = ui.spring(pan_y, { stiffness = SPRING.stiffness, damping = SPRING.damping }),
			on_press = function(e: PointerEvent)
				pressed = { x = e.local_x, y = e.local_y }
			end,
			on_click = function()
				if zoom:peek() > 1 then
					zoom:set(1)
					pan_x:set(0)
					pan_y:set(0)
					return
				end
				-- About the press: the point under it stays put.
				local f = fitted:peek()
				local natural = image.w / f[1]
				local z = if natural > 1.05 then math.min(natural, 8) else 2
				zoom:set(z)
				local px, py = clamp_pan((f[1] / 2 - pressed.x) * (z - 1), (f[2] / 2 - pressed.y) * (z - 1))
				pan_x:set(px)
				pan_y:set(py)
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
