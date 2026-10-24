-- Dictation (composer.rs, dictation/waveform.rs, dictation/glass.rs): the
-- 28-point mic that morphs into an accent-glass stop plate, the 32-high
-- waveform track that unrolls from it (3-point bars at a 6-point pitch,
-- a mono clock), and the status line under the composer.
local T = require("../theme")
local icon = require("./icon")
local txt = require("./text")
local loaders = require("./loaders")
local motion = require("./motion")
local recipes = require("./recipes")

export type Phase = "idle" | "requesting" | "listening" | "processing"
export type MicProps = { id: string?, state: State<Phase>, on_click: (Handler | Action)? }
export type TrackProps = { id: string?, state: State<Phase>, clock: Text?, bars: number?, w: Length? }
export type StatusProps = { id: string?, title: string, detail: string?, failed: boolean?, on_dismiss: Handler? }
export type RowProps = { id: string?, state: State<Phase>, clock: Text?, on_click: (Handler | Action)? }

local M = {}

M.MORPH = motion.MORPH
M.SIZE = 28
M.TRACK = 32
M.BAR = 3
M.PITCH = 6

local function accent_plate(id: string?): Node
	local accent = ui.theme.get("accent")
	local top = ui.theme.get("zeron.accent.light") or accent
	return ui.div {
		id = id,
		w = M.SIZE,
		h = M.SIZE,
		rounded = T.radius_full,
		gradient = { angle = 180, stops = { { 0, top }, { 1, accent } } },
		border = 1,
		border_color = T.accent_hover,
		shadow = T.shadow_sm,
	}
end

-- The mic. Idle it is a clear circle with the mic glyph; live it is the
-- accent plate with a 9-point stop square; processing shows a spinner on
-- the plate. The morph runs 420 ms on ease-out-soft.
M.mic = ui.component(function(props: MicProps): Node
	local function live(): boolean
		local s = props.state:get()
		return s == "listening" or s == "processing" or s == "requesting"
	end
	return ui.button {
		variants = recipes.wash { hover = "ink3" },
		id = props.id,
		w = M.SIZE,
		h = M.SIZE,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		cursor = "pointer",
		focus = { border = 1, border_color = T.accent },
		on_click = props.on_click,
		ui.overlay {
			w = M.SIZE,
			h = M.SIZE,
			items = "center",
			justify = "center",
			ui.presence(function()
				return if live() then "plate" else nil
			end, function(): Node
				return accent_plate(props.id and `{props.id}_plate`)
			end, {
				w = M.SIZE,
				h = M.SIZE,
				enter = {
					opacity = { 0, 1 },
					scale = { 0.6, 1 },
					duration = motion.d(M.MORPH),
					ease = motion.EASE_OUT_SOFT,
				},
				exit = { opacity = 0, scale = 0.6, duration = motion.d(M.MORPH), ease = motion.EASE_OUT_SOFT },
			}),
			ui.presence(function()
				local s = props.state:get()
				return if s == "idle" then "mic" elseif s == "listening" then "stop" else "busy"
			end, function(kind: string): Node
				return ui.row {
					w = M.SIZE,
					h = M.SIZE,
					items = "center",
					justify = "center",
					if kind == "mic"
						then icon { name = "microphone", size = 18, color = T.secondary }
						elseif kind == "stop" then ui.div {
							id = props.id and `{props.id}_stop`,
							w = 9,
							h = 9,
							rounded = "$zeron.radius.2_5",
							bg = T.on_accent,
						}
						else loaders.mini_spinner { cell = 2, color = T.on_accent },
				}
			end, {
				w = M.SIZE,
				h = M.SIZE,
				items = "center",
				justify = "center",
				enter = {
					opacity = { 0, 1 },
					scale = { 0.25, 1 },
					duration = motion.d(M.MORPH),
					ease = motion.EASE_OUT_SOFT,
				},
				exit = { opacity = 0, scale = 0.25, duration = motion.d(M.MORPH * 0.6), ease = motion.EASE_OUT_SOFT },
			}),
		},
	}
end)

-- The bars: at rest they breathe at the floor on a 1.4 s wave; live they
-- rise and fall with staggered phases; processing freezes them under a
-- 1.6 s highlight sweeping right to left. The leftmost 28 points fade.
local function bars(props: TrackProps): Node
	local n = props.bars or 24
	local id = props.id or `dict{math.random(1, 1e9)}`
	local items: { Node } = {}
	for i = 1, n do
		local fade = math.min(1, (i - 1) * M.PITCH / 28)
		table.insert(
			items,
			ui.div {
				class = `{id}_bar {id}_bar_{i}`,
				w = M.BAR,
				h = M.BAR,
				rounded = "$zeron.radius.1_5",
				bg = T.text,
				opacity = 0.5 * fade,
				shrink = 0,
			}
		)
	end
	local function play(state: Phase)
		anime.utils.remove(`.{id}_bar`)
		if not motion.loops() then
			return
		end
		for i = 1, n do
			local sel = `.{id}_bar_{i}`
			if state == "listening" then
				local a = 0.35 + 0.65 * math.abs(math.sin(i * 1.7))
				anime.animate(sel, {
					height = { M.BAR, M.BAR + 13 * a, M.BAR },
					opacity = 0.8 * math.min(1, (i - 1) * M.PITCH / 28),
					duration = 700,
					delay = (n - i) * 60,
					ease = "inOutSine",
					loop = true,
					frameRate = 30,
				})
			elseif state == "processing" then
				anime.animate(sel, {
					opacity = { 0.35, 0.9, 0.35 },
					duration = 1600,
					delay = (n - i) * 1600 / n,
					ease = "inOutSine",
					loop = true,
					frameRate = 30,
				})
			else
				anime.animate(sel, {
					height = { M.BAR, M.BAR + 1.5, M.BAR },
					opacity = 0.4 * math.min(1, (i - 1) * M.PITCH / 28),
					duration = 1400,
					delay = i * 1400 / 18,
					ease = "inOutSine",
					loop = true,
					frameRate = 30,
				})
			end
		end
	end
	return ui.row {
		h = 16,
		gap = T.space(M.PITCH - M.BAR),
		items = "center",
		shrink = 0,
		on_mount = function()
			ui.effect(function()
				play(props.state:get())
			end)
		end,
		items,
	}
end

-- The track: light glass, fully rounded, 32 high, bars then the clock.
M.track = ui.component(function(props: TrackProps): Node
	local glass_top = ui.theme.get("zeron.glass.light.top") or ui.theme.get("zeron.ink.3")
	local glass_bottom = ui.theme.get("zeron.glass.light.bottom") or ui.theme.get("zeron.ink.1")
	return ui.row {
		id = props.id,
		h = M.TRACK,
		w = props.w,
		px = "$zeron.space.12",
		gap = "$zeron.space.10",
		items = "center",
		overflow = "hidden",
		rounded = T.radius_full,
		gradient = { angle = 180, stops = { { 0, glass_top }, { 1, glass_bottom } } },
		border = 1,
		border_color = T.hairline,
		shadow = T.shadow_sm,
		bars(props),
		txt.text {
			props.clock or "0:00",
			size = "xs",
			mono = true,
			tabular = true,
			line = false,
			shrink = 0,
			color = "inherit",
			variants = recipes.dictation_clock {
				listening = function()
					return props.state:get() == "listening"
				end,
			},
		},
	}
end)

-- Mic and track together: the track unrolls from the mic's side while
-- dictation is live.
M.row = ui.component(function(props: RowProps): Node
	return ui.row {
		id = props.id,
		gap = "$zeron.space.8",
		items = "center",
		ui.presence(function()
			return if props.state:get() == "idle" then nil else "track"
		end, function(): Node
			return M.track { id = props.id and `{props.id}_track`, state = props.state, clock = props.clock, w = 240 }
		end, {
			layout = "width",
			enter = { opacity = { 0, 1 }, duration = motion.d(M.MORPH), ease = motion.EASE_OUT_SOFT },
			exit = { opacity = 0, duration = motion.d(M.MORPH * 0.6), ease = motion.EASE_OUT_SOFT },
		}),
		M.mic { id = props.id and `{props.id}_mic`, state = props.state, on_click = props.on_click },
	}
end)

-- The outcome line under the composer: a 6-point dot (warning when it
-- failed), title, detail, and a 24-high dismiss pill.
M.status = ui.component(function(props: StatusProps): Node
	return ui.row {
		id = props.id,
		w_full = true,
		px = "$zeron.space.12",
		h = 24,
		gap = "$zeron.space.8",
		items = "center",
		ui.div {
			w = 6,
			h = 6,
			rounded = "$zeron.radius.3",
			bg = if props.failed then T.warning else T.tertiary,
			shrink = 0,
		},
		txt.text { props.title, size = "sm", line = false },
		props.detail and txt.text { props.detail, size = "sm", color = T.secondary, line = false, truncate = true },
		ui.div { grow = 1 },
		ui.button {
			variants = recipes.wash { hover = "ink3" },
			h = 24,
			px = "$zeron.space.8",
			items = "center",
			rounded = T.radius_full,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_dismiss,
			txt.text { "Dismiss", size = "sm", color = T.secondary, line = false },
		},
	}
end)

return M
