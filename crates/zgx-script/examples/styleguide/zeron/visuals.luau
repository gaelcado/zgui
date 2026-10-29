-- Sample visuals: the Luau scripts an agent shows with `show_visual`, as
-- the engine would hand them over. Each runs as a sandboxed plugin of the
-- app's (`ui.sandbox`), so it reaches nothing it was not granted and is
-- styled by the theme's tokens where it sits.
local M = {}

-- Sign-ups by plan over six weeks: bars, their values, and a control
-- switching the plan (its handler is the visual's own).
M.SIGNUPS = [[
local weeks = { "Sep 15", "Sep 22", "Sep 29", "Oct 6", "Oct 13", "Oct 20" }
local plans = {
	Pro = { 118, 124, 131, 129, 142, 156 },
	Team = { 42, 51, 48, 63, 71, 84 },
}
local plan = ui.state("plan", "Pro")
local function counts(): { number }
	return plans[plan:get()]
end
local function peak(): number
	return math.max(table.unpack(counts()))
end

local choices = {}
for _, name in { "Pro", "Team" } do
	table.insert(choices, ui.button {
		name,
		id = `signups_{string.lower(name)}`,
		px = "$zeron.space.10",
		h = 26,
		rounded = "$zeron.radius.item",
		text_size = "$font.size.sm",
		bg = function()
			return if plan:get() == name then "$hover" else "transparent"
		end,
		color = function()
			return if plan:get() == name then "$text.primary" else "$text.secondary"
		end,
		on_click = function()
			plan:set(name)
		end,
	})
end

local bars = {}
for i, week in weeks do
	table.insert(bars, ui.column {
		grow = 1,
		basis = 0,
		h_full = true,
		gap = "$zeron.space.4",
		items = "center",
		justify = "end",
		ui.text {
			function()
				return tostring(counts()[i])
			end,
			text_size = "$font.size.xs",
			color = "$text.secondary",
			tabular = true,
		},
		ui.div {
			w_full = true,
			rounded = "$zeron.radius.4",
			bg = "$accent",
			opacity = if i == #weeks then 1 else 0.55,
			h = function()
				return math.max(4, 120 * counts()[i] / peak())
			end,
		},
		ui.text { week, text_size = "$font.size.xs", color = "$text.tertiary" },
	})
end

return ui.column {
	w_full = true,
	gap = "$zeron.space.12",
	ui.row {
		w_full = true,
		items = "center",
		ui.text { "Sign-ups by week", text_size = "$font.size.md", weight = "$font.weight.semibold", grow = 1 },
		ui.row { gap = "$zeron.space.2", choices },
	},
	ui.row { id = "signups_bars", w_full = true, h = 160, gap = "$zeron.space.8", items = "end", bars },
}
]]

-- The cluster's rack in 3D, turning; a control lights the server whose
-- jobs failed.
M.RACK = [[
local failing = ui.state("failing", false)
local function led(i: number): string
	return if failing:get() and i == 2 then "#ef4444" else "#22c55e"
end
local servers = {}
for i = 0, 3 do
	table.insert(servers, ui.mesh {
		geometry = "box",
		size = { 1.6, 0.26, 1 },
		position = { 0, 0.32 * i, 0 },
		material = { color = "#3a4250", metallic = 0.6, roughness = 0.4 },
	})
	table.insert(servers, ui.mesh {
		geometry = "sphere",
		radius = 0.035,
		position = { 0.68, 0.32 * i, 0.51 },
		material = {
			color = function()
				return led(i)
			end,
			emissive = function()
				return led(i)
			end,
		},
	})
end
return ui.column {
	w_full = true,
	gap = "$zeron.space.8",
	ui.button {
		function()
			return if failing:get() then "Show all healthy" else "Show the failing server"
		end,
		id = "rack_failing",
		self = "start",
		px = "$zeron.space.10",
		h = 26,
		rounded = "$zeron.radius.item",
		text_size = "$font.size.sm",
		color = "$text.secondary",
		on_click = function()
			failing:set(not failing:get())
		end,
	},
	ui.scene3d {
		w_full = true,
		h = 240,
		rounded = "$zeron.radius.card",
		background = "#00000000",
		camera = { position = { 2.4, 1.6, 3 }, target = { 0, 0.5, 0 }, fov = 40 },
		orbit = { auto_rotate = 8 },
		ui.light { kind = "directional", direction = { -0.5, -1, -0.4 }, intensity = 2.5 },
		ui.light { kind = "hemisphere", color = "#8899aa", ground = "#221a14", intensity = 0.6 },
		ui.group(servers),
	},
}
]]

-- Uptime by region, read from a status page: a visual has no network, so
-- it fails, saying why.
M.UPTIME = [[
local regions = ui.fetch("https://status.example.com/regions.json")
return ui.text { "Uptime", id = "uptime" }
]]

return M
