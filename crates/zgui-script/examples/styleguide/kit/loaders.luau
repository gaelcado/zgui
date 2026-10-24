-- Zeron's loaders: the 3×3 gradient spinner (a 750 ms wave climbing the
-- rows), the 2×3 mini spinner (a chase around the perimeter), and skeleton
-- bars breathing on the 2.4 s pulse. All run on the engine; no script per
-- frame.
local T = require("../theme")
local motion = require("./motion")

local M = {}

-- Nine round cells tinted per row, the wave rising at 750 ms.
export type SpinnerProps = { id: string?, cell: number?, gap: number? }
M.gradient_spinner = ui.component(function(props: SpinnerProps): Node
	local p: SpinnerProps = props or {}
	local cell = p.cell or 2.5
	local gap = p.gap or cell * 0.8
	local tints = { T.loader3, T.loader2, T.loader1 }
	local rows: { Node } = {}
	for r = 1, 3 do
		local cells: { Node } = {}
		for _ = 1, 3 do
			table.insert(
				cells,
				ui.div { w = cell, h = cell, rounded = T.radius_full, bg = tints[r], class = `gspin_{r}` }
			)
		end
		table.insert(rows, ui.row { gap = ui.raw(gap, "scales with the cell"), cells })
	end
	return ui.column {
		id = p.id,
		gap = ui.raw(gap, "scales with the cell"),
		shrink = 0,
		on_mount = function()
			if not motion.loops() then
				return
			end
			for r = 1, 3 do
				anime.animate(`.gspin_{r}`, {
					opacity = { 0.25, 1, 0.25 },
					duration = 750,
					delay = (3 - r) * 750 / 3,
					ease = motion.EASE,
					loop = true,
					frameRate = 30,
				})
			end
		end,
		rows,
	}
end)

-- Six cells, two columns by three rows, lit in turn around the edge.
export type MiniProps = { id: string?, cell: number?, color: Color? }
M.mini_spinner = ui.component(function(props: MiniProps): Node
	local p: MiniProps = props or {}
	local cell = p.cell or 2
	local gap = cell * 0.75
	local color = p.color or T.secondary
	-- Perimeter order: top left, top right, middle right, bottom right,
	-- bottom left, middle left.
	local order = { { 1, 1 }, { 1, 2 }, { 2, 2 }, { 3, 2 }, { 3, 1 }, { 2, 1 } }
	local index: { [string]: number } = {}
	for i, rc in order do
		index[`{rc[1]},{rc[2]}`] = i
	end
	local id = p.id or `mini{math.random(1, 1e9)}`
	local rows: { Node } = {}
	for r = 1, 3 do
		local cells: { Node } = {}
		for c = 1, 2 do
			table.insert(
				cells,
				ui.div {
					w = cell,
					h = cell,
					rounded = T.radius_full,
					bg = color,
					opacity = 0.25,
					class = `{id}_{index[`{r},{c}`]}`,
				}
			)
		end
		table.insert(rows, ui.row { gap = ui.raw(gap, "scales with the cell"), cells })
	end
	return ui.column {
		id = id,
		gap = ui.raw(gap, "scales with the cell"),
		shrink = 0,
		on_mount = function()
			if not motion.loops() then
				return
			end
			local step = 110
			for i = 1, 6 do
				anime.animate(`.{id}_{i}`, {
					opacity = { 0.25, 1, 0.25 },
					duration = step * 2,
					delay = (i - 1) * step,
					loopDelay = step * 4,
					ease = motion.EASE,
					loop = true,
					frameRate = 30,
				})
			end
		end,
		rows,
	}
end)

-- Skeleton rows: bars on ink 4–8%, breathing 0.35 ± 0.4 on the 2.4 s pulse.
export type SkeletonProps = { id: string?, rows: number?, w: Length?, kind: ("rows" | "menu")? }
M.skeleton = ui.component(function(props: SkeletonProps): Node
	local p: SkeletonProps = props or {}
	local menu = p.kind == "menu"
	local widths = { 0.42, 0.58, 0.48, 0.66 }
	local bars: { Node } = {}
	for i = 1, p.rows or 4 do
		if menu then
			table.insert(
				bars,
				ui.div { h = 14, rounded = "$zeron.radius.7", w = `{widths[(i - 1) % 4 + 1] * 100}%`, bg = T.ink2 }
			)
		else
			table.insert(
				bars,
				ui.row {
					w_full = true,
					h = 28,
					px = "$zeron.space.8",
					gap = "$zeron.space.10",
					items = "center",
					rounded = T.radius_md,
					bg = T.ink1,
					ui.div { w = 14, h = 14, rounded = "$zeron.radius.7", bg = T.ink3 },
					ui.div { h = 10, rounded = "$zeron.radius.5", w = `{widths[(i - 1) % 4 + 1] * 100}%`, bg = T.ink3 },
				}
			)
		end
	end
	return ui.column {
		id = p.id,
		w = p.w or 240,
		gap = if menu then "$zeron.space.10" else "$zeron.space.4",
		opacity = if motion.loops() then ui.loop { from = 0.35, to = 0.75, duration = 2400, fps = 30 } else 0.55,
		bars,
	}
end)

return M
