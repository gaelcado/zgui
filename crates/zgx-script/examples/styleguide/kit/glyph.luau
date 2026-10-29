-- The voice glyph (voice/glyph.rs, zeron-orb's glyph): a dot matrix a
-- call's two voices light band by band, the engine's `ui.voice_glyph`. The
-- stage's field is the call's disc, graded from a hot heart to small dots
-- at its rim and lit under the pointer; the beam is its strip, in the call
-- tray, the dictation track and, in miniature, the sidebar's footer. Codex
-- speaks in the sunrise rows, the user in the accent's; each dot takes one
-- of its voice's three inks. The engine steps it while it moves and rests
-- it otherwise; under reduced motion it holds still.
local motion = require("./motion")

export type Mode = "connecting" | "listening" | "thinking" | "asking" | "processing" | "muted"
export type Props = {
	id: string?,
	mode: Mode | State<Mode> | (() -> Mode),
	-- Who talks: "user", "agent", or "" (a sample's voices).
	speaking: (State<string> | (() -> string))?,
}
export type BeamProps = {
	id: string?,
	mode: Mode | State<Mode> | (() -> Mode),
	speaking: (State<string> | (() -> string))?,
	outline: ("square" | "stadium")?,
	w: Length?,
	h: Length?,
	grow: number?,
	-- It dissolves over this many points at its right end, into what
	-- follows it.
	fade_right: number?,
}

local M = {}

-- Every beam's dots: the tray's, the dictation track's (BEAM_DOT).
M.BEAM_DOT = 2.4
-- The stage's field (STAGE_FIELD): 44 dots of 3, its disc 175 across.
M.STAGE_DOTS = 44
M.STAGE_DOT = 3
M.STAGE_ROOM = M.STAGE_DOTS * (M.STAGE_DOT * 4 / 3) - M.STAGE_DOT / 3
-- The footer's beam in miniature (FOOTER_BEAM): its dots, width, height.
M.FOOTER = { dot = 1.4, w = 22, h = 11 }
-- What each mode says to assistive technology.
M.LABEL = {
	connecting = "Connecting…",
	listening = "Listening…",
	thinking = "Working…",
	asking = "Waiting on you…",
	processing = "Transcribing…",
	muted = "Muted",
}

local AGENT = { "$zeron.loader.1", "$zeron.loader.2", "$zeron.loader.3" }
local USER = { "$zeron.glyph.light", "$zeron.glyph.mid", "$zeron.glyph.deep" }

local function reading(mode: Mode | State<Mode> | (() -> Mode)): () -> Mode
	if type(mode) == "function" then
		return mode
	elseif type(mode) == "string" then
		return function(): Mode
			return mode
		end
	end
	return function(): Mode
		return (mode :: State<Mode>):get()
	end
end

-- The stage's orb: the field filling its disc, a voice losing most of
-- itself by the rim (falling 0.78), its grid at rest kept quiet (0.45).
function M.stage(props: Props): Node
	local mode = reading(props.mode)
	return ui.voice_glyph {
		id = props.id,
		dots = M.STAGE_DOTS,
		dot = M.STAGE_DOT,
		outline = "disc",
		soft_rim = true,
		falloff = 0.78,
		rest = 0.45,
		touch = true,
		mode = mode,
		speaking = props.speaking,
		still = motion.reduced,
		agent_inks = AGENT,
		user_inks = USER,
		label = function(): string
			return M.LABEL[mode()] or ""
		end,
	}
end

-- The call's beam, filling the box it is given.
function M.beam(props: BeamProps): Node
	return ui.div {
		w = props.w,
		h = props.h,
		grow = props.grow,
		min_w = 0,
		overflow = "hidden",
		fade_x = if props.fade_right then { 0, props.fade_right } else nil,
		pointer_events = "none",
		ui.voice_glyph {
			id = props.id,
			kind = "beam",
			dot = M.BEAM_DOT,
			outline = props.outline or "stadium",
			mode = props.mode,
			speaking = props.speaking,
			still = motion.reduced,
			agent_inks = AGENT,
			user_inks = USER,
			w_full = true,
			h_full = true,
		},
	}
end

-- The beam in miniature, the size of an icon (the footer's): its button
-- names it.
function M.mini(props: Props): Node
	return ui.voice_glyph {
		id = props.id,
		kind = "beam",
		dot = M.FOOTER.dot,
		outline = "stadium",
		mode = props.mode,
		speaking = props.speaking,
		still = motion.reduced,
		agent_inks = AGENT,
		user_inks = USER,
		w = M.FOOTER.w,
		h = M.FOOTER.h,
		shrink = 0,
		pointer_events = "none",
	}
end

-- The working glyph in a control's spot (dictation transcribing): 6 by 6
-- dots of 2.2, thinking.
function M.spinner(id: string?): Node
	return ui.voice_glyph {
		id = id,
		dots = 6,
		dot = 2.2,
		mode = "thinking",
		still = motion.reduced,
		agent_inks = AGENT,
		user_inks = USER,
		pointer_events = "none",
		label = M.LABEL.processing,
	}
end

return M
