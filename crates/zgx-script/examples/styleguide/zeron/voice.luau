-- Voice (voice.rs, shell/voice_stage.rs): the Codex orchestrator's call.
-- The footer's voice button places it in its own chat on the voice device
-- (Settings → Voice; "Voice session", kept out of the sidebar) and opens
-- the stage over the window: the call's glyph in the composer's disc, the
-- call's words, the call bar. Esc steps the stage aside and the call goes
-- on; the footer's beam and the tray over every conversation's composer
-- bring it back. No engine yet: a sample session plays a call through
-- every state (connecting, listening, thinking, speaking, a question), its
-- voices made up in the engine; with the USB microphone chosen it fails to
-- start, as a missing device does.
local T = require("../theme")
local kit = require("@kit")
local glyph = require("@kit/glyph")
local motion = require("@kit/motion")
local recipes = require("@kit/recipes")
local ps = require("@kit/panel_shell")
local look = require("@kit/look")
local tb = require("@kit/titlebar")
local tray = require("@kit/tray")
local agents = require("@kit/settings_agents")
local data = require("./data")
local state = require("./state")

export type Phase = "closed" | "checking" | "starting" | "active" | "stopping" | "failed"
export type Work = "idle" | "working" | "awaiting"
-- One turn of the call: who speaks ("" until it is known), what was said
-- so far, and who spoke the turn before (its spacing).
export type Line = { id: string, speaker: string, text: string, after: string }

local M = {}

-- The stage (voice_stage.rs): the orb settles 120 above the middle, the
-- words in the band under it, 560 wide; the bar 28 from the bottom.
M.ROOM = glyph.STAGE_ROOM
M.LIFT = 120
M.WORDS = 560
M.ENTER = 620
M.EXIT = 300
M.CONTROL = 36
M.BAR_PAD = 6
M.BAR_BOTTOM = 28
-- The call tray over a conversation's composer (COMPOSER_BEAM, TRAY_CONTROL):
-- its beam 22 high, dissolving over 20 into the controls, which are 24.
M.TRAY_BEAM = 22
M.TRAY_FADE = 20
M.TRAY_CONTROL = 24
-- A turn nobody has named yet is the user's after this long
-- (Caption::GRACE): Codex's turns are named as they begin.
M.GRACE = 220
M.CHAT = "agent:voice-orchestrator-1"
M.DEVICE_FAILURE = "Check microphone permission and your audio devices."
M.SOUNDS = { start = "sounds/voice-start.wav", stop = "sounds/voice-end.wav" }

M.phase = ui.state("voice_phase", "closed" :: Phase)
M.muted = ui.state("voice_muted", false)
M.work = ui.state("voice_work", "idle" :: Work)
-- The orchestrator's voice is playing.
M.playing = ui.state("voice_playing", false)
-- Who talks now, as the glyph hears it: "user", "agent" or "".
M.speaking = ui.state("voice_speaking", "")
M.stage = ui.state("voice_stage", false)
-- Why the last start failed ("" while nothing did).
M.reason = ui.state("voice_reason", "")
-- The call's running time, "" until it connects.
M.clock = ui.state("voice_clock", "")
-- The chat the call runs in, once its session answers.
M.chat = ui.state("voice_chat", "")
-- The device the call runs Codex on, by name.
M.host = ui.state("voice_host_name", data.THIS)
-- Every turn of the call, oldest first.
M.lines = ui.state("voice_lines", {} :: { Line })
-- Bumps as a call ends: an open transcript takes its turns in.
M.calls = ui.state("voice_calls", 0)

-- A reload drops the sample's timers: no call survives it.
if M.phase:peek() ~= "closed" and M.phase:peek() ~= "failed" then
	M.phase:set("closed")
	M.stage:set(false)
	M.clock:set("")
	M.speaking:set("")
	M.lines:set {}
end

-- ---- the call ------------------------------------------------------------

-- Underway, from its preparation to the provider's stop.
function M.live(): boolean
	local p = M.phase:get()
	return p == "checking" or p == "starting" or p == "active" or p == "stopping"
end
local function live_now(): boolean
	local p = M.phase:peek()
	return p == "checking" or p == "starting" or p == "active" or p == "stopping"
end

-- Kept in Rust, so what builds on them runs nothing to read them: "live"
-- while a call is.
local live_key = ui.computed(function(): string?
	return if M.live() then "live" else nil
end)
-- Voice can be offered: this device's Codex installed and on (Settings →
-- Providers), or a call or its failure to explain.
local offered = ui.computed(function(): boolean
	return agents.codex_ready() or M.live() or M.reason:get() ~= ""
end)
function M.offered(): boolean
	return offered:get()
end

-- What the glyph shows between voices (glyph_mode): muted first, then
-- the call's state as the orb read it, a voice playing outranking work.
function M.mode(): glyph.Mode
	if M.muted:get() then
		return "muted"
	end
	local p = M.phase:get()
	if p == "checking" or p == "starting" or p == "stopping" then
		return "connecting"
	elseif M.playing:get() then
		return "listening"
	end
	local w = M.work:get()
	if w == "awaiting" then
		return "asking"
	elseif w == "working" then
		return "thinking"
	end
	return "listening"
end
-- Who the glyph hears: the user's voice is not shown while muted.
function M.voice(): string
	return M.speaking:get()
end

-- `m:ss`, or `h:mm:ss` past the hour.
function M.format_elapsed(seconds: number): string
	local h, m, s = seconds // 3600, seconds // 60 % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- The page the stage covers fades as it arrives when the surfaces are
-- frosted: the stage has no fill there, only the window's frost.
local function opaque(): boolean
	return not look.frosted(state.look)
end
M.UNDER = "voice_under"

-- Shows or hides the stage; only a live call has one.
function M.set_stage(open: boolean)
	open = open and live_now()
	if M.stage:peek() == open then
		return
	end
	M.stage:set(open)
	if open then
		if not opaque() then
			anime.animate(`.{M.UNDER}`, { opacity = 0, duration = motion.d(M.ENTER), ease = motion.EASE_OUT_EXPO })
		end
	else
		anime.animate(`.{M.UNDER}`, { opacity = 1, duration = motion.d(M.EXIT), ease = motion.EASE })
		anime.animate("#voice_stage_orb", { y = 28, scale = 0.84, duration = motion.d(M.EXIT), ease = motion.EASE })
		anime.animate("#voice_bar_row", { y = 12, duration = motion.d(M.EXIT), ease = motion.EASE })
	end
end

local run = 0
local stop_clock: (() -> ())? = nil
-- A line the user would say while muted waits for the microphone.
local held: (() -> ())? = nil
-- The call connected and sounded its start: it owes its end.
local cued = false

-- The call's turns join the chat's history as it ends.
local function keep_lines()
	local lines = M.lines:peek()
	if #lines == 0 then
		return
	end
	local turns = data.voice_turns()
	for _, line in lines do
		local last = turns[#turns]
		if line.speaker == "user" or not last then
			table.insert(turns, { user = if line.speaker == "user" then line.text else "", reply = "" })
		else
			last.reply = if last.reply == "" then line.text else `{last.reply}\n\n{line.text}`
		end
	end
	M.lines:set {}
	M.calls:set(M.calls:peek() + 1)
end

local function reset_session()
	if stop_clock then
		stop_clock()
		stop_clock = nil
	end
	if cued then
		ui.play_sound(M.SOUNDS.stop)
	end
	cued = false
	held = nil
	M.set_stage(false)
	M.muted:set(false)
	M.work:set("idle")
	M.playing:set(false)
	M.speaking:set("")
	M.clock:set("")
	keep_lines()
end

-- Ends the call (any phase); the provider stops in the background.
function M.cancel()
	run += 1
	reset_session()
	M.phase:set("closed")
	M.reason:set("")
end

-- A failure explains itself once, beside the voice button.
local function fail(reason: string)
	run += 1
	reset_session()
	M.phase:set("failed")
	M.reason:set(reason)
end

-- Forgets a failure once it has been seen.
function M.dismiss()
	if M.reason:peek() ~= "" then
		M.reason:set("")
		if M.phase:peek() == "failed" then
			M.phase:set("closed")
		end
	end
end

function M.toggle_mute()
	local muted = not M.muted:peek()
	M.muted:set(muted)
	if not muted and held then
		local go = held
		held = nil
		go()
	end
end

-- ---- the sample session ----------------------------------------------------

type Step = { wait: number?, user: string?, assistant: string?, work: Work?, hold: number?, ask: boolean? }
local SCRIPT: { Step } = {
	{ wait = 900, user = "Is the release notes build green yet?" },
	{ work = "working", hold = 1800 },
	{ assistant = "Not yet. The Claude session in comet is still running the suite, about two thirds through." },
	{ wait = 1400, user = "Then open a pull request once it passes." },
	{ work = "working", hold = 1600 },
	{
		assistant = "There are changes on two branches, release/0.2.117 and wing/layout. Which one should it come from?",
		ask = true,
	},
	{ wait = 2600, user = "The release branch." },
	{ work = "working", hold = 1400 },
	{ assistant = "Done. I'll open it from release/0.2.117 as soon as the suite passes." },
}
-- How fast each speaker's words arrive.
local USER_WORD = 150
local VOICE_WORD = 170
-- The session's pace (tests play it faster): `ms` of it, in real time.
local pace = ui.shared("voice_pace", 1)
local function after(ms: number, f: () -> ())
	ui.after(ms / math.max(pace:peek(), 0.01), f)
end

-- A new turn of the call: Codex's is named as it begins, the user's is
-- not (the provider says nothing of it until its final), and is taken to
-- be theirs after the grace (Caption::assume).
local function begin(role: string): number
	local lines = M.lines:peek()
	local before = lines[#lines]
	M.lines:push {
		id = `turn_{#lines + 1}`,
		speaker = if role == "user" then "" else role,
		text = "",
		after = if before then (if before.speaker == "" then "user" else before.speaker) else "",
	}
	return #lines + 1
end
local function unnamed(i: number): boolean
	local line = M.lines:peek()[i]
	return line ~= nil and line.speaker == ""
end

-- One speaker turn, word by word: the stage and the transcript follow it;
-- final, it is settled.
local function speak(this: number, role: string, text: string, done: () -> ())
	local i = begin(role)
	M.work:set("idle")
	M.playing:set(role == "assistant")
	M.speaking:set(if role == "user" then "user" else "agent")
	local gap = if role == "user" then USER_WORD else VOICE_WORD
	local spoken: { string } = {}
	for word in string.gmatch(text, "%S+") do
		table.insert(spoken, word)
	end
	if role == "user" then
		after(M.GRACE, function()
			if run == this and unnamed(i) then
				M.lines:set_key({ i, "speaker" }, "user")
			end
		end)
	end
	for n, word in spoken do
		after((n - 1) * gap, function()
			if run == this then
				local now = M.lines:peek()[i].text
				M.lines:set_key({ i, "text" }, if now == "" then word else `{now} {word}`)
			end
		end)
	end
	after(#spoken * gap + 300, function()
		if run == this then
			M.playing:set(false)
			M.speaking:set("")
			-- The final names the turn, whatever was assumed.
			M.lines:set_key({ i, "speaker" }, role)
			M.lines:set_key({ i, "text" }, text)
			done()
		end
	end)
end

local function play(this: number, i: number)
	local step = SCRIPT[i]
	if not step then
		return
	end
	local function next_in(ms: number)
		after(ms, function()
			if run == this then
				play(this, i + 1)
			end
		end)
	end
	local function go()
		if step.work then
			M.work:set(step.work)
			next_in(step.hold or 0)
		elseif step.user then
			speak(this, "user", step.user, function()
				next_in(0)
			end)
		elseif step.assistant then
			speak(this, "assistant", step.assistant, function()
				if step.ask then
					M.work:set("awaiting")
				end
				next_in(0)
			end)
		end
	end
	after(step.wait or 0, function()
		if run ~= this then
			return
		end
		if step.user and M.muted:peek() then
			held = go
		else
			go()
		end
	end)
end

-- The device Codex runs on (Settings → Voice): this one, or another by
-- name.
local function host_name(id: string): string
	for _, d in agents.devices:peek() do
		if id ~= "" and d.id == id then
			return d.name
		end
	end
	return data.THIS
end

-- Places a call (the footer's voice button): checking, starting, then
-- live in its chat on the voice device, with the voice style chosen, the
-- stage up from the first moment. It sounds as it connects.
function M.start()
	M.cancel()
	local this = run
	local prefs = require("./settings").pref
	M.host:set(host_name(prefs.voice_host:peek()))
	M.phase:set("checking")
	M.set_stage(true)
	local mic = prefs.microphone:peek()
	after(800, function()
		if run ~= this then
			return
		end
		if mic == "USB Microphone" then
			fail(M.DEVICE_FAILURE)
			return
		end
		M.phase:set("starting")
	end)
	after(1600, function()
		if run ~= this then
			return
		end
		M.phase:set("active")
		M.chat:set(M.CHAT)
		ui.play_sound(M.SOUNDS.start)
		cued = true
		local since = ui.now()
		M.clock:set(M.format_elapsed(0))
		stop_clock = ui.every(1000, function()
			if run ~= this then
				return false
			end
			M.clock:set(M.format_elapsed(math.floor((ui.now() - since) / 1000)))
			return true
		end)
		play(this, 1)
	end)
end

-- The call's conversation: opening it steps the stage aside, the call
-- going on.
function M.open_transcript()
	M.set_stage(false)
	state.open_session(M.CHAT)
end

-- Going anywhere else (another session, the board, Settings, a layout)
-- steps the stage aside without ending the call.
local was = ""
ui.effect(function()
	local here = `{state.route:get()}|{state.session:get()}|{state.settings:get()}|{state.layout:get()}`
	if here ~= was then
		was = here
		if M.stage:peek() then
			M.set_stage(false)
		end
	end
end)

-- ---- the stage -------------------------------------------------------------

-- A round control of the bar (round_control); `on` puts it on the solid
-- plate (muted).
local function control(p: {
	id: string,
	label: string,
	tooltip: string,
	icon: string,
	size: number,
	on: boolean?,
	color: string?,
	on_click: () -> (),
	[number]: Node?,
}): Node
	return ui.button {
		id = p.id,
		label = p.label,
		tooltip = p.tooltip,
		relative = true,
		w = ui.raw(p.size, "the call's round controls (BAR_CONTROL, TRAY_CONTROL)"),
		h = ui.raw(p.size, "the call's round controls (BAR_CONTROL, TRAY_CONTROL)"),
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		variants = recipes.voice_control { on = p.on or false },
		focus = { border = 2, border_over = true, border_color = T.accent },
		cursor = "pointer",
		on_click = p.on_click,
		kit.icon { name = p.icon :: any, size = if p.size > 30 then 16 else 13, color = p.color or "currentColor" },
		p[1],
	}
end

local function mute(id: string, size: number, keys: boolean): Node
	return ui.presence(M.muted, function(muted: boolean): Node
		local tip = if muted then "Unmute" else "Mute"
		return control {
			id = id,
			label = if muted then "Unmute microphone" else "Mute microphone",
			tooltip = if keys then `{tip} · M` else tip,
			icon = if muted then "microphone-off" else "microphone",
			size = size,
			on = muted,
			on_click = M.toggle_mute,
		}
	end, { shrink = 0 })
end

-- The hang-up: the one saturated control.
local function hang_up(id: string, wide: boolean): Node
	return ui.button {
		id = id,
		label = "End voice",
		tooltip = "End voice",
		w = if wide then nil else ui.raw(M.TRAY_CONTROL, "the tray's round controls (TRAY_CONTROL)"),
		h = ui.raw(if wide then M.CONTROL else M.TRAY_CONTROL, "the call's round controls"),
		px = if wide then "$zeron.space.14" else 0,
		gap = "$zeron.space.6",
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		variants = recipes.voice_end,
		focus = { border = 2, border_over = true, border_color = T.accent },
		cursor = "pointer",
		on_click = M.cancel,
		kit.icon { name = "phone-hang-up", size = if wide then 16 else 13, color = "currentColor" },
		wide and kit.text.text { "End", size = "sm", weight = "semibold", color = "inherit", line = false } or nil,
	}
end

-- The bar (render_voice_call_bar): who the call is with and for how long,
-- the microphone, the way back to the call's conversation (where Codex's
-- question waits) and the red hang-up, in a floating frosted pill.
local function bar(): Node
	return ui.row {
		id = "voice_bar",
		items = "center",
		gap = "$zeron.space.6",
		p = T.space(M.BAR_PAD),
		pl = T.space(M.BAR_PAD + 4),
		rounded = ui.raw(M.CONTROL / 2 + M.BAR_PAD, "the bar's corners, concentric with its controls"),
		border = 1,
		border_color = "$zeron.voice.bar_border",
		bg = T.frost,
		backdrop_blur = function(): any
			return if not look.frosted(state.look) then 0 else ui.raw(18, "the call bar's own frost")
		end,
		shadow = T.float_shadow,
		color = T.text,
		ui.row {
			items = "center",
			gap = "$zeron.space.8",
			mr = "$zeron.space.10",
			kit.text.text {
				function(): string
					local c = M.clock:get()
					return if c == "" then "–:––" else c
				end,
				id = "voice_bar_clock",
				size = "sm",
				mono = true,
				tabular = true,
				color = T.secondary,
				line = false,
			},
			kit.text.text {
				function(): string
					return M.host:get()
				end,
				id = "voice_bar_host",
				size = "sm",
				color = T.tertiary,
				line = false,
			},
		},
		mute("voice_bar_mic", M.CONTROL, true),
		ui.presence(function(): boolean
			return M.work:get() == "awaiting"
		end, function(asking: boolean): Node
			local chat = M.chat:peek() ~= ""
			return control {
				id = "voice_bar_back",
				label = if asking then "Answer Codex in the conversation" else "Back to the conversation",
				tooltip = if asking then "Codex is asking you something" else "Back to the conversation · Esc",
				icon = "alt-arrow-down",
				size = M.CONTROL,
				color = if asking then T.warning else T.secondary,
				on_click = function()
					if M.chat:peek() ~= "" then
						M.open_transcript()
					else
						M.set_stage(false)
					end
				end,
				if asking and chat
					then ui.div {
						id = "voice_bar_asking",
						absolute = true,
						top = 6,
						right = 6,
						w = 7,
						h = 7,
						rounded = T.radius_full,
						border = 2,
						border_color = T.frost,
						bg = T.warning,
					}
					else nil,
			}
		end, { shrink = 0 }),
		hang_up("voice_bar_end", true),
	}
end

-- A turn's words (zeron-veil): what arrives fades in, in the engine.
local function words(row: State<Line>, id: string): Node
	return ui.rich {
		id = id,
		veil = id,
		wrap = true,
		text_size = "$font.size.xl",
		line_height = "$font.line.xl",
		color = T.text,
		function(): string
			return row:get().text
		end,
	}
end

-- The words as the conversation reads them: the user's turns in their
-- bubble on the right, Codex's on the page; 12 between two of one voice,
-- 20 where the voice changes. A turn shows once its speaker is known.
local function turn(line: Line, _: number, row: State<Line>): Node
	return ui.presence(function(): string?
		local s = row:get().speaker
		return if s == "" then nil else s
	end, function(speaker: string): Node
		local user = speaker == "user"
		local first = line.after == ""
		return ui.row {
			id = `voice_{line.id}`,
			w_full = true,
			justify = if user then "end" else "start",
			pt = if first then 0 elseif (line.after == "user") == user then "$zeron.space.12" else "$zeron.space.20",
			on_mount = function(el: Element)
				anime.animate(
					el,
					{ opacity = { 0, 1 }, duration = motion.d(motion.FADE_IN), ease = motion.EASE_OUT_EXPO }
				)
			end,
			if user
				then ui.column {
					max_w = "80%",
					min_w = 0,
					px = "$zeron.space.16",
					py = "$zeron.space.10",
					rounded = T.radius_xl,
					bg = T.ink3,
					words(row, `voice_{line.id}_words`),
				}
				else ui.column { max_w = "86%", min_w = 0, words(row, `voice_{line.id}_words`) },
		}
	end, { w_full = true })
end

-- The stage (render_voice_stage): over everything right of the sidebar,
-- the new-session artwork across its top. The orb settles above the
-- middle, rising 28 as the stage arrives and growing the last of the way:
-- the composer's material in a disc with the field inside it, a round
-- veil of the page's colour behind it so the picture recedes evenly round
-- it. The words live in the band between the orb and the bar, centred
-- while they fit and scrolling once they do not, the newest in view and
-- the rest fading out under the band's top. It holds the keys while up:
-- Esc steps aside, M mutes. The app gives it the artwork (the new-session
-- canvas's) and how far down it starts (under a topbar).
export type StageProps = { artwork: (id: string) -> Node, top: () -> number }
function M.stage_view(props: StageProps): Node
	local room = ui.raw(M.ROOM, "the stage's field: 44 dots of 3")
	return ui.presence(function(): string?
		return if M.stage:get() then "on" else nil
	end, function(): Node
		return ui.div {
			id = "voice_stage",
			w_full = true,
			h_full = true,
			relative = true,
			overflow = "hidden",
			focusable = true,
			focus = { border = 0 },
			bg = function(): string
				return if not look.frosted(state.look) then T.bg else T.clear
			end,
			on_mount = function(el: Element)
				el:focus()
			end,
			on_key = function(e: KeyEvent): boolean
				if e.key == "Escape" then
					M.set_stage(false)
					return true
				elseif (e.key == "m" or e.key == "M") and not (e.meta or e.ctrl or e.alt or e.shift or e.editing) then
					M.toggle_mute()
					return true
				end
				return false
			end,
			props.artwork("voice_stage_art"),
			ui.column {
				absolute = true,
				top = 0,
				left = 0,
				right = 0,
				bottom = 0,
				px = "$zeron.space.24",
				items = "center",
				-- Above the orb: half the room left, less its lift, and never
				-- under the titlebar.
				ui.div { grow = 1, basis = 0, min_h = ui.raw(tb.HEIGHT + 20, "20 under the titlebar") },
				ui.div {
					id = "voice_stage_orb",
					relative = true,
					w = room,
					h = room,
					shrink = 0,
					on_mount = function(el: Element)
						anime.animate(el, {
							y = { 28, 0 },
							scale = { 0.84, 1 },
							duration = motion.d(M.ENTER),
							ease = motion.EASE_OUT_EXPO,
						})
					end,
					ui.div {
						absolute = true,
						top = 0,
						left = 0,
						w = room,
						h = room,
						rounded = T.radius_full,
						shadow = {
							x = 0,
							y = 0,
							blur = ui.raw(M.ROOM * 0.75, "the veil's blur, three quarters of the orb"),
							spread = ui.raw(M.ROOM * 0.5, "the veil's reach, half the orb"),
							color = "$zeron.voice.veil",
						},
					},
					ui.row {
						absolute = true,
						top = 0,
						left = 0,
						w = room,
						h = room,
						items = "center",
						justify = "center",
						rounded = T.radius_full,
						bg = T.composer,
						border = 1,
						border_color = T.input_border,
						shadow = T.float_shadow,
						glyph.stage { id = "voice_orb", mode = M.mode, speaking = M.voice },
					},
				},
				-- Under it: the band down to the bar, its lift twice over.
				ui.column {
					grow = 1,
					basis = ui.raw(2 * M.LIFT, "the orb's lift, twice: it settles 120 above the middle"),
					min_h = 0,
					w_full = true,
					items = "center",
					pt = "$zeron.space.24",
					pb = T.space(96),
					ui.column {
						id = "voice_words",
						w = ui.raw(M.WORDS, "the transcript's column (STAGE_TRANSCRIPT_WIDTH)"),
						max_w = "100%",
						grow = 1,
						min_h = 0,
						justify = "center",
						kit.scroll {
							id = "voice_transcript",
							label = "Call transcript",
							w_full = true,
							max_h = "100%",
							follow = true,
							fade = 32,
							ui.each(M.lines, turn, {
								key = function(l: Line): string
									return l.id
								end,
							}),
						},
					},
				},
			},
			ui.row {
				id = "voice_bar_row",
				absolute = true,
				left = 0,
				right = 0,
				bottom = T.space(M.BAR_BOTTOM),
				justify = "center",
				on_mount = function(el: Element)
					anime.animate(el, { y = { 12, 0 }, duration = motion.d(M.ENTER), ease = motion.EASE_OUT_EXPO })
				end,
				bar(),
			},
			-- The stage covers the conversation's titlebar: its band still
			-- moves the window and a double click zooms it.
			ui.div {
				id = "voice_stage_titlebar",
				absolute = true,
				top = 0,
				left = 0,
				right = 0,
				h = tb.HEIGHT,
				window_drag = true,
			},
		}
	end, {
		absolute = true,
		top = props.top,
		bottom = 0,
		right = 0,
		left = function(): number
			-- The sidebar stays usable beside the stage; collapsed, the
			-- stage spans the window.
			local shell = state.shell()
			return if ps.shown(shell, "sidebar") then ps.sidebar_width(shell) else 0
		end,
		enter = { opacity = { 0, 1 }, duration = motion.d(M.ENTER), ease = motion.EASE_OUT_EXPO },
		exit = { opacity = 0, duration = motion.d(M.EXIT), ease = motion.EASE },
	})
end

-- What the stage covers starts so (a column built while it is up).
function M.under_opacity(): number
	return if M.stage:peek() and not opaque() then 0 else 1
end

-- What the stage covers, faded as it arrives on frosted surfaces: a column
-- filling its place, or `fill = false` its content's size.
function M.under(node: Node, fill: boolean?): Node
	local full = fill ~= false
	return ui.column {
		class = M.UNDER,
		w_full = true,
		h_full = full,
		opacity = M.under_opacity(),
		items = "stretch",
		node,
	}
end

-- ---- the way back ------------------------------------------------------------

-- The footer's voice button (kit/session_sidebar): the call's beam in
-- miniature while one is live.
M.call = {
	offered = M.offered,
	live = M.live,
	stage = function(): boolean
		return M.stage:get()
	end,
	failure = function(): string
		return M.reason:get()
	end,
	glyph = function(): Node
		return glyph.mini { id = "voice_footer_glyph", mode = M.mode, speaking = M.voice }
	end,
	toggle = function()
		M.set_stage(not M.stage:peek())
	end,
	dismiss = M.dismiss,
}

-- The call tray over a conversation's composer while a call is live
-- (render_voice_composer_orb), on the queue's surface tucked under the
-- composer's top edge and as wide as its straight top: the call's beam,
-- pressing which returns to the stage, then mute and hang-up. `name`
-- gives its ids (two panes, two trays).
function M.tray(name: (id: string) -> string): Node
	-- Built only while a call is live.
	return ui.presence(live_key, function(): Node
		return ui.column {
			w_full = true,
			px = ui.raw(26, "the composer's radius: the tray spans its straight top"),
			mb = T.pull(tray.OVERLAP),
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(motion.FAST), ease = motion.EASE })
			end,
			tray.surface {
				id = name("voice_tray"),
				w = "100%",
				-- The beam spans what the controls leave (a tooltip's anchor
				-- keeps its own box: placed, not grown).
				ui.row {
					w_full = true,
					relative = true,
					h = T.space(M.TRAY_BEAM),
					gap = "$zeron.space.4",
					items = "center",
					justify = "end",
					ui.button {
						id = name("voice_tray_open"),
						label = "Open voice",
						tooltip = "Open voice",
						absolute = true,
						top = 0,
						bottom = 0,
						left = 0,
						right = T.space(2 * M.TRAY_CONTROL + 2 * 4),
						p = 0,
						bg = T.clear,
						hover = { bg = T.clear },
						rounded = T.radius_full,
						cursor = "pointer",
						focus = { border = 2, border_over = true, border_color = T.accent },
						on_click = function()
							M.set_stage(true)
						end,
						glyph.beam {
							id = name("voice_tray_beam"),
							mode = M.mode,
							speaking = M.voice,
							outline = "square",
							w = "100%",
							h = "100%",
							fade_right = M.TRAY_FADE,
						},
					},
					mute(name("voice_tray_mic"), M.TRAY_CONTROL, false),
					hang_up(name("voice_tray_end"), false),
				},
			},
		}
	end)
end

-- The voice chat's transcript: built again as a call ends (its turns join
-- the history); while one is on, its turns follow, word by word.
function M.transcript(session: string, build: () -> Node): Node
	if session ~= M.CHAT then
		return build()
	end
	return ui.presence(M.calls, function(): Node
		return build()
	end, { w_full = true, h_full = true })
end

-- The call's turns in its conversation, after what earlier calls said:
-- each as the conversation's own, its words arriving as they are said.
function M.live_turns(session: string?, name: (id: string) -> string): Node?
	if session ~= M.CHAT then
		return nil
	end
	return ui.each(M.lines, function(line: Line, _: number, row: State<Line>): Node
		return ui.presence(function(): string?
			local s = row:get().speaker
			return if s == "" then nil else s
		end, function(speaker: string): Node
			local text = function(): string
				return row:get().text
			end
			if speaker == "user" then
				return ui.column {
					w_full = true,
					pt = "$zeron.space.16",
					kit.transcript.user_bubble { id = name(`voice_{line.id}`), text = text, meta = false },
				}
			end
			return ui.column {
				w_full = true,
				pt = "$zeron.space.8",
				kit.transcript.turn {
					id = name(`voice_{line.id}`),
					kit.markdown.view { text = text, key = `voice:{line.id}`, veil = true },
				},
			}
		end, { w_full = true })
	end, {
		key = function(l: Line): string
			return l.id
		end,
	})
end

return M
