-- Dictation (composer.rs, dictation.rs, dictation/glass.rs): the 28-point
-- mic that morphs into the stop square, the 28-high track that unrolls
-- from it, the voice glyph's beam rising in it as the voice does (the call
-- tray's twin) and dissolving into its mono clock, and the status line
-- under the composer. Transcribing, the working glyph takes the stop's
-- spot.
local T = require("../theme")
local icon = require("./icon")
local txt = require("./text")
local glyph = require("./glyph")
local motion = require("./motion")
local recipes = require("./recipes")

export type Phase = "idle" | "requesting" | "listening" | "processing"
export type MicProps = { id: string?, state: State<Phase>, on_click: (Handler | Action)? }
export type TrackProps = { id: string?, state: State<Phase>, clock: Text?, w: Length? }
export type StatusProps = { id: string?, title: string, detail: string?, failed: boolean?, on_dismiss: Handler? }
export type RowProps = { id: string?, state: State<Phase>, clock: Text?, on_click: (Handler | Action)? }

local M = {}

-- Whether a composer dictates now (zeron_voice::busy): Settings → Voice
-- keeps the speech model while one does. A composer notes its phase as it
-- starts; nothing runs until asked.
local live: { [State<Phase>]: boolean } = {}
function M.started(phase: State<Phase>)
	live[phase] = true
end
function M.busy(): boolean
	for phase in live do
		if phase:peek() ~= "idle" then
			return true
		end
		live[phase] = nil
	end
	return false
end

M.MORPH = motion.MORPH
M.SIZE = 28
M.TRACK = 28
-- The room the beam leaves for the clock, and how far it dissolves before
-- it (VOICE_CLOCK_ROOM, VOICE_BEAM_FADE).
M.CLOCK_ROOM = 38
M.BEAM_FADE = 56

-- What the beam shows in each phase (waveform::Mode::glyph).
function M.mode(phase: Phase): glyph.Mode
	return if phase == "listening" then "listening" elseif phase == "processing" then "processing" else "connecting"
end

-- The mic. Idle it is a clear circle with the mic glyph; live, the stop
-- square in the text's colour (10, rounded 2) grows in as the glyph
-- shrinks away; transcribing, the working glyph. The morph runs 420 ms on
-- ease-out-soft.
M.mic = ui.component(function(props: MicProps): Node
	return ui.button {
		variants = recipes.wash { hover = "ink3" },
		id = props.id,
		label = function(): string
			local s = props.state:get()
			return if s == "idle"
				then "Dictate"
				elseif s == "processing" then "Cancel transcription"
				else "Stop dictation"
		end,
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
							w = 10,
							h = 10,
							rounded = "$zeron.radius.2",
							bg = T.text,
						}
						else glyph.spinner(props.id and `{props.id}_working`),
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

-- The track: light glass, fully rounded, 28 high: the beam filling it to
-- its rim, round at its start, rising from its bottom as the voice does
-- and dissolving into the clock rather than stopping at it.
M.track = ui.component(function(props: TrackProps): Node
	local glass_top = ui.theme.get("zeron.glass.light.top") or ui.theme.get("zeron.ink.3")
	local glass_bottom = ui.theme.get("zeron.glass.light.bottom") or ui.theme.get("zeron.ink.1")
	return ui.row {
		id = props.id,
		relative = true,
		h = M.TRACK,
		w = props.w,
		pr = "$zeron.space.12",
		justify = "end",
		items = "center",
		overflow = "hidden",
		rounded = T.radius_full,
		gradient = { angle = 180, stops = { { 0, glass_top }, { 1, glass_bottom } } },
		border = 1,
		border_color = T.hairline,
		shadow = T.shadow_sm,
		ui.div {
			absolute = true,
			top = 0,
			bottom = 0,
			left = 0,
			right = ui.raw(M.CLOCK_ROOM, "the room the clock keeps (VOICE_CLOCK_ROOM)"),
			glyph.beam {
				id = props.id and `{props.id}_beam`,
				mode = function(): glyph.Mode
					return M.mode(props.state:get())
				end,
				speaking = function(): string
					return if props.state:get() == "listening" then "user" else ""
				end,
				w = "100%",
				h = "100%",
				fade_right = M.BEAM_FADE,
			},
		},
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

-- What a dictation ended in that needs reading (dictation.rs
-- Phase::status): the tap that should have been a hold, no speech heard,
-- or why it could not go on (`failed`: the warning's dot). `at` says when
-- a sample engine reports it: as it starts (the microphone refused) or
-- as it transcribes.
export type Outcome = { title: string, detail: string, failed: boolean?, at: ("start" | "end")? }
M.TAPPED = {
	title = "Hold to dictate",
	detail = "Keep holding the microphone or the shortcut while you speak.",
} :: Outcome
M.NO_SPEECH = { title = "No speech detected", detail = "Check your microphone, then try again." } :: Outcome

-- The outcome under the composer (render_dictation_status), 12 in, at
-- 12 on 18: the 6 dot (the warning's when it failed, else faint) 6 down,
-- 8 before the title and its detail in the muted colour (wrapping
-- under it), then "Dismiss" (24 high, 8 in, round, the muted colour; the
-- raised wash and the text's under the pointer). It fades in rising 4.
M.status = ui.component(function(props: StatusProps): Node
	return ui.row {
		id = props.id,
		w_full = true,
		px = "$zeron.space.12",
		gap = "$zeron.space.8",
		items = "start",
		label = if props.detail then `{props.title}. {props.detail}` else props.title,
		on_mount = function(el: Element)
			anime.animate(
				el,
				{ opacity = { 0, 1 }, y = { 4, 0 }, duration = motion.d(500), ease = motion.EASE_OUT_EXPO }
			)
		end,
		ui.div {
			w = 6,
			h = 6,
			mt = "$zeron.space.6",
			rounded = "$zeron.radius.3",
			bg = if props.failed then T.warning else T.tertiary,
			shrink = 0,
		},
		ui.row {
			grow = 1,
			min_w = 0,
			flex_wrap = true,
			gap_x = "$zeron.space.8",
			txt.text { props.title, id = props.id and `{props.id}_title`, size = "sm", line_height = "$font.line.md" },
			props.detail and txt.text {
				props.detail,
				id = props.id and `{props.id}_detail`,
				size = "sm",
				color = T.secondary,
				wrap = true,
				min_w = 0,
				line_height = "$font.line.md",
			},
		},
		ui.button {
			id = props.id and `{props.id}_dismiss`,
			label = "Dismiss dictation message",
			h = 24,
			mt = ui.raw(-3, "level with the title's first line"),
			px = "$zeron.space.8",
			shrink = 0,
			items = "center",
			rounded = T.radius_full,
			bg = T.clear,
			color = T.secondary,
			hover = { bg = T.raised, color = T.text },
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_dismiss,
			txt.text { "Dismiss", size = "sm", color = "inherit", line = false },
		},
	}
end)

return M
