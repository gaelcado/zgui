-- zimmer's title-bar tabs, after Dia (ds/chrome.go): tabs 30 high in a 42
-- bar, 200 wide shrinking together to 96, 2 apart, the top corners at 10;
-- the chosen tab filled in the canvas colour, an inactive one clear with a
-- lift wash on hover over 90 ms; a 16 mark, the title at 12.5 medium, a
-- 24 close that keeps its room and fades in on hover; a 26 plus; tabs
-- open and close over 240 ms on the emphasized curve.
local T = require("../theme")
local wash = require("./wash")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Tab = {
	id: string,
	title: string,
	icon: icon_mod.Name?,
	tint: Color?,
	count: number?,
	working: boolean?,
	pinned: boolean?,
}
export type Props = {
	id: string,
	tabs: State<{ Tab }>,
	value: State<string>,
	on_close: ((id: string) -> ())?,
	on_add: (Handler | Action)?,
}

local M = {}

M.BAR = 42
M.TAB = 30
M.WIDTH = 200
M.MIN = 96
M.RADIUS = 10
M.EMPHASIZED = "cubicBezier(0.2, 0, 0, 1)"

local function tab(t: Tab, props: Props): Node
	local function on(): boolean
		return props.value:get() == t.id
	end
	-- Shown on the chosen tab, and on the others while the pointer is over
	-- them.
	local close = ui.button {
		id = `{props.id}_{t.id}_close`,
		w = 24,
		h = 24,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_md,
		bg = T.clear,
		hover = { bg = T.ink3 },
		focus = { border = 0 },
		cursor = "pointer",
		variants = recipes.tabbar_close { selected = on },
		on_click = function()
			if props.on_close then
				props.on_close(t.id)
			end
		end,
		icon { name = "close", size = 12, color = T.secondary },
	}
	if t.pinned then
		return ui.button(wash.item(`{props.id}_tabs`, {
			id = `{props.id}_{t.id}`,
			w = 40,
			h = M.TAB,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = T.radius(M.RADIUS),
			cursor = "pointer",
			focus = { border = 0 },
			on_press = ui.set(props.value, t.id),
			icon { name = t.icon or "globe", size = 16, color = t.tint or T.secondary },
		}, on))
	end
	return ui.button(wash.item(`{props.id}_tabs`, {
		id = `{props.id}_{t.id}`,
		basis = M.WIDTH,
		min_w = M.MIN,
		shrink = 1,
		h = M.TAB,
		pl = "$zeron.space.10",
		pr = "$zeron.space.4",
		gap = "$zeron.space.8",
		items = "center",
		rounded_tl = T.radius(M.RADIUS),
		rounded_tr = T.radius(M.RADIUS),
		rounded_bl = 0,
		rounded_br = 0,
		cursor = "pointer",
		focus = { border = 0 },
		-- Chosen: the canvas colour. Hovered: its wash (kit/wash).
		variants = recipes.tabbar_tab { selected = on },
		hover_group = true,
		-- Chosen on press, as zimmer does.
		on_press = ui.set(props.value, t.id),
		if t.working
			then ui.div {
				w = 16,
				h = 16,
				items = "center",
				justify = "center",
				require("./loaders").mini_spinner { cell = 2, color = t.tint },
			}
			else icon { name = t.icon or "folder", size = 16, color = t.tint or T.secondary },
		txt.text {
			t.title,
			size = "sm",
			weight = "medium",
			truncate = true,
			line = false,
			grow = 1,
			shrink = 1,
			min_w = 0,
			color = "inherit",
		},
		t.count and ui.row {
			h = 16,
			px = "$zeron.space.5",
			items = "center",
			rounded = T.radius_full,
			bg = T.ink3,
			txt.text { tostring(t.count), size = "micro", weight = "medium", color = T.secondary, line = false },
		},
		close,
	}, on))
end

M.bar = ui.component(function(props: Props): Node
	return ui.row {
		id = props.id,
		w_full = true,
		h = M.BAR,
		pr = "$zeron.space.8",
		items = "end",
		-- The tabs wash under the pointer (kit/wash).
		wash.list {
			group = `{props.id}_tabs`,
			direction = "row",
			grow = 1,
			shrink = 1,
			min_w = 0,
			w_full = false,
			items = "end",
			color = T.ink2,
			ui.each(props.tabs, function(t: Tab)
				return tab(t, props)
			end, {
				grow = 1,
				shrink = 1,
				min_w = 0,
				items = "end",
				gap = "$zeron.space.2",
				direction = "row",
				key = function(t: Tab)
					return t.id
				end,
				animate = { duration = motion.d(240), ease = M.EMPHASIZED },
				enter = { opacity = { 0, 1 }, scaleX = { 0.6, 1 }, duration = motion.d(240), ease = M.EMPHASIZED },
				exit = { opacity = 0, scaleX = 0.6, duration = motion.d(240), ease = M.EMPHASIZED },
			}),
		},
		ui.button {
			variants = recipes.wash { hover = "ink2" },
			id = `{props.id}_add`,
			w = 26,
			h = 26,
			mb = "$zeron.space.2",
			ml = "$zeron.space.4",
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.7",
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_add,
			icon { name = "plus", size = 14, color = T.secondary },
		},
	}
end)

return M
