-- The canvas: the current page, scrolling, under the density's and the
-- zoom's tokens. Pages are modules returning a function that builds them;
-- a page is built when shown and dropped when it leaves.
local state = require("../state")
local kit = require("@kit")

local pages: { [string]: () -> Node } = {
	colour = require("@pages/colour"),
	typography = require("@pages/typography"),
	metrics = require("@pages/metrics"),
	motion = require("@pages/motion"),
	patterns = require("@pages/patterns"),
	parity = require("@pages/parity"),
	buttons = require("@pages/buttons"),
	inputs = require("@pages/inputs"),
	chips = require("@pages/chips"),
	overlays = require("@pages/overlays"),
	lists = require("@pages/lists"),
	settings = require("@pages/settings"),
	apps = require("@pages/apps"),
	shell = require("@pages/shell"),
	panels = require("@pages/panels"),
	transcript = require("@pages/transcript"),
	icons = require("@pages/icons"),
	panes = require("@pages/panes"),
	agent = require("@pages/agent"),
	changes = require("@pages/changes"),
	workspace = require("@pages/workspace"),
	composer = require("@pages/composer"),
	pickers = require("@pages/pickers"),
}

local M = {}

local offset = ui.state("offset", 0)
-- A new page starts at its top.
ui.effect(function()
	state.page:get()
	offset:set(0)
end)

-- The canvas's width, read when it resizes (the page column centres in it).
local canvas_w = ui.state("canvas_w", 1048)

local function page_body(): Node
	-- Keyed on the page and the reduced-motion switch, so loops stop or start
	-- with it (they decide at mount).
	return ui.presence(function()
		return `{state.page:get()}{if kit.motion.reduced:get() then "/still" else ""}`
	end, function(key: string): Node
		local id = string.gsub(key, "/still$", "")
		-- A reading column of 880 (narrower only when the canvas is), placed
		-- by a measured margin rather than flex centring: a centred column
		-- moves when anything's width changes mid-press (a focus ring), and the
		-- click is lost.
		return ui.column {
			w_full = true,
			items = "start",
			ui.column {
				id = "page_" .. id,
				w = function()
					return math.min(880, canvas_w:get())
				end,
				ml = function()
					return ui.raw(math.max(0, (canvas_w:get() - 880) / 2), "centres the reading column")
				end,
				px = "$zeron.space.32",
				pt = "$zeron.space.24",
				pb = "$zeron.space.64",
				gap = "$zeron.space.48",
				pages[id](),
			},
		}
	end, {
		w_full = true,
		items = "center",
		enter = {
			opacity = { 0, 1 },
			y = { 4, 0 },
			duration = kit.motion.d(kit.motion.NORMAL),
			ease = kit.motion.EASE_OUT_EXPO,
		},
		exit = { opacity = 0, duration = kit.motion.d(80) },
	})
end

function M.Canvas(): Node
	return ui.column {
		id = "canvas",
		w_full = true,
		h_full = true,
		-- As Zeron's chat column: nothing of its own over the window glass,
		-- the sidebar's seam between them, the titlebar's band above.
		pt = "$zeron.titlebar.height",
		kit.scroll {
			id = "canvas_scroll",
			grow = 1,
			w_full = true,
			offset = offset,
			fade = 24,
			ui.column {
				id = "page",
				w_full = true,
				items = "start",
				on_resize = function(size: { w: number, h: number })
					if size.w > 0 and size.w ~= canvas_w:peek() then
						canvas_w:set(size.w)
					end
				end,
				-- Density and zoom are token overrides scoped to the page.
				theme = function()
					return state.overrides()
				end,
				page_body(),
			},
		},
	}
end

return M
