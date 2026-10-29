-- Zeron's loaders (loaders.rs, popover.rs, proto/src/motion.rs): the 3×3
-- gradient spinner, the 2×3 mini glyph spinner, and the skeletons breathing
-- on the 2.4 s pulse. Cells sit in fixed slots (cell, half a cell apart),
-- so a loader never moves what is around it; only their opacity animates,
-- in the engine (no script per frame), every loader on one clock (Zeron's
-- PulseClock: an animation seeks to where the engine's time has it). Under
-- reduced motion they hold still: the spinners' cells at 0.6, the
-- skeletons at the pulse's rest.
local T = require("../theme")
local motion = require("./motion")
local txt = require("./text")

local M = {}

-- The activity wave (gspin_opacity): a cell is full at its cycle's start,
-- fades linearly to 0.1 by 45%, rests there until 92%, and rises back to
-- full; 750 ms a cycle. Each cell runs it shifted by its phase.
M.PERIOD = 750
M.DIM = 0.1
-- The cells' still opacity under reduced motion (ActivityPulse, subtle).
M.STILL = 0.6
-- The zeron pulse: 2.4 s a cycle, a cosine between its floor and peak.
M.PULSE = 2400
-- A skeleton row lags the one above by 8% of the pulse.
M.PULSE_STAGGER = 0.08

local WAVE = {
	["0%"] = { opacity = 1, ease = "linear" },
	["45%"] = { opacity = M.DIM, ease = "linear" },
	["92%"] = { opacity = M.DIM, ease = "linear" },
	["100%"] = { opacity = 1, ease = "linear" },
}

-- The wave's opacity at `t` (0 to 1 of the cycle): a cell's first frame.
function M.wave(t: number): number
	t = t % 1
	if t < 0.45 then
		return 1 + (M.DIM - 1) * t / 0.45
	elseif t < 0.92 then
		return M.DIM
	end
	return M.DIM + (1 - M.DIM) * (t - 0.92) / 0.08
end

-- Where a loop of `period` is on the shared clock, `ahead` ms further on.
local function clock(period: number, ahead: number): number
	return (anime.engine.currentTime + ahead) % period
end

-- Plays the wave on each ref's cells, each ref `phases[i]` of a cycle
-- ahead, at `fps`.
local function play_wave(refs: { Ref }, phases: { number }, fps: number)
	for i, r in refs do
		local a = anime.animate(r, {
			keyframes = WAVE,
			duration = M.PERIOD,
			ease = "linear",
			loop = true,
			frameRate = fps,
		})
		a:seek(clock(M.PERIOD, phases[i] * M.PERIOD))
	end
end

-- Breathes `target` between `from` and `to` on the 2.4 s pulse (a cosine:
-- out and back on inOutSine), `lag` of a cycle behind the clock. For
-- skeletons and anything that pulses as Zeron's loaders do.
function M.breathe(target: Element | Ref, from: number, to: number, lag: number?)
	if not motion.loops() then
		return
	end
	local a = anime.animate(target, {
		opacity = { from, to },
		duration = M.PULSE / 2,
		ease = "inOutSine",
		alternate = true,
		loop = true,
		frameRate = 30,
	})
	a:seek(clock(M.PULSE, M.PULSE - (lag or 0) * M.PULSE))
end

-- The 3×3 gradient spinner (gradient_spinner): round cells tinted per row
-- from the sunrise gradient (blue, amber, pink, top to bottom), half a cell
-- apart; a cell's phase is its distance from the bottom centre, a quarter
-- of the cycle a step, so the light sweeps the grid. Cell 2.5 everywhere
-- Zeron shows it (sending, working, the boot splash). 15 frames a second,
-- as Zeron's shell loaders.
export type SpinnerProps = { id: string?, cell: number? }
M.gradient_spinner = ui.component(function(props: SpinnerProps): Node
	local p: SpinnerProps = props or {}
	local cell = p.cell or 2.5
	local gap = ui.raw(cell / 2, "half a cell")
	local tints = { T.loader1, T.loader2, T.loader3 }
	local loops = motion.loops()
	-- One ref per phase (gspin_cell_phase: 0, ¼, ½, ¾).
	local refs: { Ref } = { ui.ref(), ui.ref(), ui.ref(), ui.ref() }
	local rows: { Node } = {}
	for r = 0, 2 do
		local cells: { Node } = {}
		for c = 0, 2 do
			local d = 2 - r + math.abs(c - 1)
			table.insert(
				cells,
				ui.div {
					ref = refs[d + 1],
					w = cell,
					h = cell,
					shrink = 0,
					rounded = T.radius_full,
					bg = tints[r + 1],
					opacity = if loops then M.wave(d / 4) else M.STILL,
				}
			)
		end
		table.insert(rows, ui.row { gap = gap, cells })
	end
	return ui.column {
		id = p.id,
		gap = gap,
		shrink = 0,
		on_mount = if loops
			then function()
				play_wave(refs, { 0, 0.25, 0.5, 0.75 }, 15)
			end
			else nil,
		rows,
	}
end)

-- The 2×3 mini glyph spinner (mini_glyph_spinner): two columns by three
-- rows, the same wave chasing round the ring (a sixth of the cycle a
-- cell), its footprint 2.5 cells by 4. Its rows are the accent's glyph
-- palette (light, the accent, deep); `color` makes it one tone
-- (mini_mono_spinner: the connection line, dictation, settings). Cell 2 in
-- the sidebar's rows, tabs and chips; 2.5 for a todo; 1.5 beside a 12-point
-- line of meta text.
export type MiniProps = { id: string?, cell: number?, color: Color? }
M.mini_spinner = ui.component(function(props: MiniProps): Node
	local p: MiniProps = props or {}
	local cell = p.cell or 2
	local gap = ui.raw(cell / 2, "half a cell")
	local tints: { Color } = if p.color
		then { p.color, p.color, p.color }
		else { T.glyph_light, T.glyph_mid, T.glyph_deep }
	local loops = motion.loops()
	-- Each cell's place on the ring, clockwise from the top left
	-- (MINI_RING): (1,1) (1,2) (2,2) (3,2) (3,1) (2,1).
	local ring = { { 0, 1 }, { 5, 2 }, { 4, 3 } }
	local refs: { Ref } = {}
	for i = 1, 6 do
		refs[i] = ui.ref()
	end
	local rows: { Node } = {}
	for r = 1, 3 do
		local cells: { Node } = {}
		for c = 1, 2 do
			local k = ring[r][c]
			table.insert(
				cells,
				ui.div {
					ref = refs[k + 1],
					w = cell,
					h = cell,
					shrink = 0,
					rounded = T.radius_full,
					bg = tints[r],
					opacity = if loops then M.wave(k / 6) else M.STILL,
				}
			)
		end
		table.insert(rows, ui.row { gap = gap, cells })
	end
	return ui.column {
		id = p.id,
		w = cell * 2.5,
		h = cell * 4,
		gap = gap,
		shrink = 0,
		on_mount = if loops
			then function()
				play_wave(refs, { 0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6 }, 30)
			end
			else nil,
		rows,
	}
end)

-- The ring spinner (ring_spinner): twelve dashes round a ring, the head
-- at the top and each one behind it dimmer ((1 - age/12)^1.6), the stroke
-- 11% of the diameter, turning once in 900 ms (in the engine). In the
-- text's colour; still under reduced motion.
M.SPIN = 900
local function ring_svg(d: number): string
	local stroke = math.max(d * 0.11, 1.5)
	local r = d / 2 - stroke
	local slot = 2 * math.pi / 12
	local paths: { string } = {}
	for age = 0, 11 do
		local opacity = (1 - age / 12) ^ 1.6
		if opacity >= 0.04 then
			local head = -math.pi / 2 - slot * age
			local a, b = head - slot * 0.62, head
			table.insert(
				paths,
				string.format(
					'<path d="M%.2f %.2fA%.2f %.2f 0 0 1 %.2f %.2f" stroke-opacity="%.3f"/>',
					d / 2 + r * math.cos(a),
					d / 2 + r * math.sin(a),
					r,
					r,
					d / 2 + r * math.cos(b),
					d / 2 + r * math.sin(b),
					opacity
				)
			)
		end
	end
	return `<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}" fill="none" stroke="currentColor" stroke-width="{stroke}">{table.concat(
		paths
	)}</svg>`
end
export type RingProps = { id: string?, size: number?, color: Color? }
M.ring = ui.component(function(props: RingProps): Node
	local d = props.size or 20
	return ui.svg {
		id = props.id,
		code = ring_svg(d),
		w = d,
		h = d,
		shrink = 0,
		tint = props.color or T.secondary,
		on_mount = function(el: Element)
			if motion.loops() then
				anime.animate(el, { rotate = 360, duration = M.SPIN, ease = "linear", loop = true, frameRate = 30 })
			end
		end,
	}
end)

-- Skeletons (popover.rs skeleton_rows, skeleton_menu_rows, skeleton_bar):
-- rows 28 high at radius 6 on ink 4%, 6 apart, 4 down; a menu's bars 14
-- high at radius 7 on ink 5% across a ladder of widths, 8 apart inside 6
-- by 4; a bar 11 high on ink 8%. Each breathes 0.35 + 0.4 of the pulse, a
-- row 8% of it behind the one above.
local WIDTHS = { 0.42, 0.58, 0.48, 0.66 }
export type SkeletonProps = { id: string?, rows: number?, w: Length?, kind: ("rows" | "menu")? }
M.skeleton = ui.component(function(props: SkeletonProps): Node
	local p: SkeletonProps = props or {}
	local menu = p.kind == "menu"
	local count = p.rows or 4
	local refs: { Ref } = {}
	local bars: { Node } = {}
	for i = 1, count do
		refs[i] = ui.ref()
		table.insert(
			bars,
			ui.div {
				ref = refs[i],
				w = if menu then `{WIDTHS[(i - 1) % 4 + 1] * 100}%` else nil,
				w_full = not menu,
				h = if menu then 14 else 28,
				rounded = if menu then "$zeron.radius.7" else T.radius_md,
				bg = if menu then T.skeleton_menu else T.skeleton,
				opacity = 0.35,
			}
		)
	end
	return ui.column {
		id = p.id,
		w = p.w or 240,
		gap = if menu then "$zeron.space.8" else "$zeron.space.6",
		py = if menu then "$zeron.space.6" else "$zeron.space.4",
		px = if menu then "$zeron.space.4" else nil,
		on_mount = if motion.loops()
			then function()
				for i, r in refs do
					M.breathe(r, 0.35, 0.75, (i - 1) * M.PULSE_STAGGER)
				end
			end
			else nil,
		bars,
	}
end)

-- One ghost label (skeleton_bar): a trigger's label slot while what it
-- names resolves.
export type BarProps = { id: string?, w: number? }
M.bar = ui.component(function(props: BarProps): Node
	local p: BarProps = props or {}
	return ui.div {
		id = p.id,
		w = p.w or 56,
		h = 11,
		shrink = 0,
		rounded = T.radius_full,
		bg = T.skeleton_bar,
		opacity = 0.35,
		on_mount = if motion.loops()
			then function(el: Element)
				M.breathe(el, 0.35, 0.75)
			end
			else nil,
	}
end)

-- The boot splash (loaders.rs splash_overlay): the whole window on the
-- glass's frost tint, the gradient spinner at 2.5 over "Setting up Zeron
-- environment" (12, the muted text at 70%), 12 apart. Leaving
-- (`SPLASH_OUT`), it holds 150 ms, then fades over 500 lifting 6.
M.SPLASH_OUT = { opacity = 0, y = -6, delay = 150, duration = motion.d(500), ease = motion.EASE } :: ElementParams
M.splash = ui.component(function(props: { id: string? }): Node
	return ui.column {
		id = props.id,
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		bg = T.glass,
		items = "center",
		justify = "center",
		gap = "$zeron.space.12",
		M.gradient_spinner { id = if props.id then `{props.id}_spinner` else nil, cell = 2.5 },
		txt.text {
			"Setting up Zeron environment",
			size = "sm",
			color = T.secondary,
			opacity = 0.7,
			line = false,
		},
	}
end)

return M
