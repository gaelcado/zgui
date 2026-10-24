-- Zeron's composer as it ships (composer.rs): a frosted pill at radius 26
-- (22 once docked in a thread) on the input glass with the composer
-- border; the text at 14/22.75 ("Do anything…" in the faint colour) over
-- a 42-high action row (add · then, right, model chip · mic · send), or one 47-high
-- compact row; attachments in a strip inside the pill; the queue tray and
-- an error notice above; the question panel in the pill's place; the
-- 24-high session footer below. The completion menus (kit/completion: @
-- files, / commands, $ skills) open over it as the draft asks.
local T = require("../theme")
local wash = require("./wash")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local button = require("./button")
local motion = require("./motion")
local recipes = require("./recipes")
local frost = require("./frost")
local tray = require("./tray")
local notice = require("./notice")
local attachments_kit = require("./attachments")
local loaders = require("./loaders")
local completion = require("./completion")
local dictation = require("./dictation")
local context_usage = require("./context_usage")
local message_badge = require("./message_badge")

export type Attachment = {
	id: string,
	name: string,
	kind: "file" | "image" | "link",
	detail: string?,
	badge: string?,
	-- Upload progress, 0 to 1, while it uploads.
	progress: number?,
	error: string?,
}
export type QueueItem = { id: string, text: string }
export type Choice = { id: string, title: string, description: string? }
export type Dock = {
	kind: "queue" | "question" | "error",
	-- queue
	items: { QueueItem }?,
	timing: string?,
	-- question
	prompt: string?,
	choices: { Choice }?,
	selected: State<string>?,
	count: string?,
	-- error
	body: string?,
	tone: ("warning" | "danger")?,
	on_dismiss: (Handler | Action)?,
}
-- The completions that follow the draft (kit/completion's source).
export type References = completion.Source
export type CompletionItem = completion.Item
-- A completion menu held open over the pill, for specimens.
export type Picker = { token: completion.Token, items: { completion.Item } }
export type Props = {
	id: string?,
	value: State<string>,
	placeholder: string?,
	attachments: State<{ Attachment }>?,
	on_remove_attachment: ((id: string) -> ())?,
	-- How many review comments are staged for the next message (read where
	-- it changes): a "2 comments" badge over the draft, 16 in and 12 down.
	comments: (() -> number)?,
	docks: { Dock }?,
	-- A live queue: what was typed while a run was live, shown in the queue
	-- tray over the pill while it holds anything.
	queue: State<{ tray.Queued }>?,
	on_send_queued: ((id: string) -> ())?,
	-- A run is live: the send button queues typed text, or stops when empty.
	working: types.Cond?,
	model: Text?,
	effort: Text?,
	harness: icon_mod.Name?,
	-- Wraps the model chip in its picker (a popover anchored on it), and
	-- what a click on the chip does (opens it).
	model_picker: ((chip: Node) -> Node)?,
	on_model: (Handler | Action)?,
	-- One 47-high row (a short message in a thread) instead of the
	-- expanded 120; `"auto"`, the row while the draft fits it, opening
	-- out as it grows past it, a line break or an attachment (composer.rs
	-- composer_flip): the engine measures, no script a key.
	compact: (boolean | "auto")?,
	-- Docked at the bottom of a thread: radius 22 instead of 26.
	docked: boolean?,
	-- The session footer: a branch, a checkout, a PR number, and how full
	-- the context window is (0 to 1, of `context_total` tokens).
	context: State<number?>?,
	context_total: number?,
	branch: string?,
	checkout: string?,
	pr: number?,
	-- A completion menu held open over the composer (a specimen).
	picker: Picker?,
	-- Or live ones, following the draft: @, / and $ as `references` reads
	-- them.
	references: References?,
	-- The pill's width (768 at most in Zeron; the column adds 16 a side);
	-- a function follows the column.
	w: Reactive<Length>?,
	on_send: Handler?,
	on_stop: Handler?,
	on_queue: Handler?,
	on_add: Handler?,
	-- The mic: the app's own handler, or else dictation in the composer
	-- (its phase in `dictation` when the app follows it).
	on_voice: Handler?,
	dictation: State<dictation.Phase>?,
	on_remove_queued: ((id: string) -> ())?,
	-- Shown focused, for specimens.
	preview: "focus"?,
}

local M = {}

M.RADIUS = 26
M.RADIUS_DOCKED = 22
M.MAX_WIDTH = 768
M.CONTROL = 28
M.ACTIONS = 42
M.COMPACT = 47
M.TEXT_MIN = 76
M.TEXT_MAX = 260

-- A tooltip above a control, as the kit's bubble (`kit/tooltip`), on the
-- control itself: no wrapper to lay out.
local ABOVE: Placement = { side = "top", offset = 6 }
local function tip_bubble(label: Text): Node
	return ui.row { variants = recipes.tooltip { keys = false }, txt.text { label, size = "sm", line = false } }
end

-- A 28-point round control: the attach and mic buttons, ink 10% under the
-- pointer over 150 ms, named by a tooltip above.
local function round(name: icon_mod.Name, on_click: (Handler | Action)?, id: string?, tip: string?): Node
	return ui.button {
		variants = recipes.wash { hover = "ink4" },
		id = id,
		w = M.CONTROL,
		h = M.CONTROL,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		cursor = "pointer",
		focus = { border = 1, border_color = T.accent },
		on_click = on_click,
		tooltip = if tip then tip_bubble(tip) else nil,
		tooltip_placement = if tip then ABOVE else nil,
		icon { name = name, size = 18, color = T.secondary },
	}
end

-- Send, queue or stop: a 28 circle in the text colour; the arrow 14, the
-- stop square 11 at radius 3, in the background colour. Hover 0.85; with
-- nothing to send, 35% and inert (Zeron's send_circle).
local function send(props: Props): Node
	-- Staged comments alone are something to send (composer_has_content).
	local function typed(): boolean
		return props.value:get() ~= "" or (props.comments ~= nil and props.comments() > 0)
	end
	local function mode(): "send" | "queue" | "stop"
		if not types.on(props.working) then
			return "send"
		end
		return if typed() then "queue" else "stop"
	end
	return ui.button {
		id = props.id and props.id .. "_send",
		tooltip = tip_bubble(function()
			local m = mode()
			return if m == "stop" then "Stop" elseif m == "queue" then "Queue message" else "Send message"
		end),
		tooltip_placement = ABOVE,
		w = M.CONTROL,
		h = M.CONTROL,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		variants = recipes.send_button {
			idle = function()
				return mode() == "send" and not typed()
			end,
		},
		focus = { border = 0 },
		on_click = function()
			local m = mode()
			if m == "stop" then
				if props.on_stop then
					props.on_stop()
				end
			elseif m == "queue" then
				if props.on_queue then
					props.on_queue()
				end
			elseif props.on_send and typed() then
				props.on_send()
			end
		end,
		ui.presence(mode, function(m: string): Node
			if m == "stop" then
				return ui.div { w = 11, h = 11, rounded = "$zeron.radius.3", bg = T.bg }
			end
			return icon { name = "arrow-up", size = 14, color = "currentColor" }
		end, {
			w = M.CONTROL,
			h = M.CONTROL,
			items = "center",
			justify = "center",
			enter = { opacity = { 0, 1 }, scale = { 0.6, 1 }, duration = motion.d(motion.FAST) },
			exit = { opacity = 0, duration = motion.d(80) },
		}),
	}
end

-- The model chip: 32 high, radius 8, px 6, gap 6; the harness mark at 16,
-- the model at 12 medium (text at 0.9), the effort as a muted suffix.
local function model_chip(props: Props): Node
	local chip = ui.button {
		variants = recipes.wash { hover = "hover" },
		id = props.id and props.id .. "_model",
		h = 32,
		px = "$zeron.space.6",
		gap = "$zeron.space.6",
		items = "center",
		shrink = 1,
		min_w = 0,
		max_w = 248,
		rounded = T.radius_button,
		cursor = "pointer",
		focus = { border = 0 },
		on_click = props.on_model,
		icon { name = props.harness or "claude-mark", size = 16, color = T.claude },
		txt.text {
			props.model or "Claude Opus",
			size = "sm",
			weight = "medium",
			opacity = 0.9,
			truncate = true,
			line = false,
		},
		props.effort and txt.text {
			props.effort,
			size = "sm",
			weight = "medium",
			color = T.secondary,
			opacity = 0.7,
			line = false,
		},
	}
	return if props.model_picker then props.model_picker(chip) else chip
end

-- What the compact row's controls take from the expanded draft's width
-- (`fits_inset`): the row's insets, the paperclip, the mic and send and
-- their gaps (104 past the expanded draft's own 32), and the model chip,
-- as wide as its words (at most its 248). It must not fall short of the
-- row's (an expanded draft that "fits" would fold into a row it does not
-- fit, and back): the words are counted generously.
local function fold_inset(props: Props): number
	local function len(t: Text?): number
		if t == nil then
			return 0
		end
		local s = if type(t) == "function" then (t :: any)() else t
		return utf8.len(tostring(s)) or 0
	end
	local words = len(props.model or "Claude Opus") + (if props.effort then len(props.effort) + 1 else 0)
	return 104 + math.min(44 + words * 7.5, 248)
end

-- Whether the draft has the focus, and whether a flip (a new editor)
-- hands it on.
type Carry = { focused: boolean, refocus: boolean }

local function text_input(
	props: Props,
	compact: boolean,
	menu: completion.Menu?,
	ref: Ref,
	fits: State<boolean>?,
	carry: Carry?
): Node
	return ui.textarea {
		id = props.id and props.id .. "_input",
		ref = ref,
		-- Folding: whether the draft fits the one row (the engine writes it).
		fits = fits,
		fits_inset = if fits and not compact
			then function()
				return fold_inset(props)
			end
			else nil,
		on_focus = if carry
			then function()
				carry.focused = true
			end
			else nil,
		on_blur = if carry
			then function()
				carry.focused = false
			end
			else nil,
		on_mount = if carry
			then function(el: Element)
				-- A flip builds the other editor: it takes the focus and the
				-- caret where the draft had them.
				if carry.refocus then
					carry.refocus = false
					el:focus()
					el:set_selection(utf8.len(props.value:peek()) or 0)
				end
			end
			else nil,
		value = props.value,
		label = "Message",
		placeholder = props.placeholder or "Do anything…",
		placeholder_color = T.tertiary,
		grow = 1,
		shrink = 1,
		min_w = 0,
		w_full = not compact,
		-- Long lines wrap, as Zeron's do (the one-line compact row scrolls).
		wrap = not compact,
		-- Zeron's input fade (INPUT_FADE_BAND): 12 where the draft runs past.
		fade = { 12, 12 },
		fade_overflow = true,
		-- Expanded, it is as tall as its wrapped lines (`auto_height`), 56 (76 − 20)
		-- to 240, past which it scrolls: Rust measures, no script a key.
		h = if compact then 22.75 else nil,
		auto_height = not compact,
		min_h = if compact then nil else M.TEXT_MIN - 20,
		max_h = if compact then nil else M.TEXT_MAX - 20,
		px = if compact then "$zeron.space.8" else 0,
		py = 0,
		bg = T.clear,
		border = 0,
		rounded = 0,
		font = T.sans,
		text_size = "$font.size.lg",
		line_height = 22.75,
		color = T.text,
		focus = { border = 0 },
		-- A reference a completion wrote (`@path `) shows as a chip on the
		-- ink at 8% (composer/chip.rs paint_chip) and deletes whole.
		chips = if props.references then "@" else nil,
		chip_color = T.ink3,
		on_key = function(e: KeyEvent): boolean
			-- An open menu takes its keys first (Enter and Tab pick).
			if menu and menu.on_key(e) then
				return true
			end
			-- ⌘⏎ (Ctrl⏎) on an empty draft sends the latest queued message
			-- now (composer.rs on_modified_submit); with a draft, as ⏎.
			if e.key == "Enter" and (e.meta or e.ctrl) and props.value:peek() == "" then
				local queued = if props.queue then props.queue:peek() else {}
				local latest = queued[#queued]
				if latest and props.on_send_queued then
					props.on_send_queued(latest.id)
				end
				return true
			end
			if e.key == "Enter" and not e.shift then
				if types.on(props.working) then
					if props.on_queue then
						props.on_queue()
					end
				elseif props.on_send then
					props.on_send()
				end
				return true
			end
			return false
		end,
	}
end

-- The attachment strip inside the pill: 56 tiles, 8 apart, 16 in, 12 down.
local function strip(props: Props): Node?
	local list = props.attachments
	if not list then
		return nil
	end
	-- Only while it holds something: its 12 down would otherwise sit over
	-- the text as an empty band.
	return ui.show(
		function()
			return #(list :: State<{ Attachment }>):get() > 0
		end,
		ui.each(list, function(a: Attachment)
			return ui.column {
				relative = true,
				attachments_kit.tile {
					id = props.id and `{props.id}_att_{a.id}`,
					name = a.name,
					image = if a.kind == "image" then T.ink5 else nil,
					icon = if a.kind == "link" then "global" elseif a.kind == "file" then "document" else nil,
					on_remove = function()
						if props.on_remove_attachment then
							props.on_remove_attachment(a.id)
						end
					end,
				},
				a.progress and a.progress < 1 and ui.div {
					absolute = true,
					left = 4,
					right = 4,
					bottom = 4,
					h = 3,
					rounded = "$zeron.radius.1_5",
					bg = T.ink5,
					ui.div { w = `{a.progress * 100}%`, h_full = true, rounded = "$zeron.radius.1_5", bg = T.text },
				},
				a.error and ui.row {
					absolute = true,
					top = 0,
					left = 0,
					right = 0,
					bottom = 0,
					rounded = "$zeron.radius.8",
					bg = T.danger_wash,
					border = 1,
					border_color = T.danger,
					items = "center",
					justify = "center",
					icon { name = "danger-triangle", size = 16, color = T.danger },
				},
			}
		end, {
			id = props.id and props.id .. "_strip",
			key = function(a: Attachment)
				return a.id
			end,
			direction = "row",
			flex_wrap = true,
			gap = "$zeron.space.8",
			px = "$zeron.space.16",
			pt = "$zeron.space.12",
			animate = true,
			exit = { opacity = 0, scale = 0.9, duration = motion.d(motion.FAST) },
		})
	)
end

-- The staged comments' badge (render_comments_chip): "1 comment" on the
-- chat glyph, while any are staged.
local function comments_chip(props: Props): Node?
	local count = props.comments
	if not count then
		return nil
	end
	return ui.show(
		function()
			return count() > 0
		end,
		ui.row {
			px = "$zeron.space.16",
			pt = "$zeron.space.12",
			ui.presence(count, function(n: number): Node
				return message_badge {
					id = props.id and `{props.id}_comments`,
					icon = "chat-round-line",
					label = if n == 1 then "1 comment" else `{n} comments`,
				}
			end),
		}
	)
end

-- The question panel (render_wizard): in the pill's place at radius 26;
-- a 10.5 tracked header, the question at 15/20 medium, options at radius
-- 12 with a 22 number badge, a free-text line, Back and Next.
local function question(dock: Dock, props: Props): Node
	local choices: { Node } = {}
	local choice_group = wash.group("choices")
	for i, c in dock.choices or {} do
		local function on(): boolean
			return dock.selected ~= nil and dock.selected:get() == c.id
		end
		table.insert(
			choices,
			ui.button(wash.item(choice_group, {
				id = `choice_{c.id}`,
				w_full = true,
				px = "$zeron.space.14",
				py = "$zeron.space.10",
				gap = "$zeron.space.12",
				items = "center",
				-- Concentric with the pill: 16 in, inside its border.
				rounded = T.concentric(M.RADIUS, 16, 1),
				border = 1,
				variants = recipes.choice_card { selected = on },
				-- Keep the border's width on focus: a width change relays out
				-- mid-press and the next click is lost.
				focus = { border = 1, border_color = T.ink6 },
				cursor = "pointer",
				on_click = function()
					if dock.selected then
						dock.selected:set(c.id)
					end
				end,
				ui.row {
					w = 22,
					h = 22,
					items = "center",
					justify = "center",
					rounded = T.radius_md,
					bg = T.ink3,
					shrink = 0,
					txt.text { tostring(i), size = "xs", weight = "medium", line = false },
				},
				ui.column {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.2",
					txt.text { c.title, size = "md", weight = "medium", truncate = true },
					c.description and txt.text { c.description, size = "sm", color = T.secondary, truncate = true },
				},
			}, on))
		)
	end
	return ui.column {
		id = "question_dock",
		w_full = true,
		rounded = T.radius(M.RADIUS),
		bg = T.input,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		ui.column {
			w_full = true,
			p = "$zeron.space.16",
			gap = "$zeron.space.12",
			ui.row {
				items = "center",
				gap = "$zeron.space.8",
				txt.text {
					"QUESTION",
					size = "micro",
					color = T.secondary,
					opacity = 0.6,
					letter_spacing = 0.8,
					grow = 1,
				},
				dock.count and ui.row {
					h = 20,
					px = "$zeron.space.6",
					items = "center",
					rounded = T.radius_md,
					bg = T.ink2,
					txt.text { dock.count, size = "micro", color = T.secondary, line = false },
				},
			},
			txt.text { dock.prompt or "", size = "xl", weight = "medium", wrap = true },
			wash.list { group = choice_group, gap = "$zeron.space.4", color = T.ink2, choices },
			ui.column {
				w_full = true,
				pt = "$zeron.space.4",
				ui.textarea {
					id = props.id and props.id .. "_input",
					value = props.value,
					label = "Your own answer",
					placeholder = "Type your own answer, or pick an option above",
					placeholder_color = T.tertiary,
					w_full = true,
					h = 34.75,
					px = 0,
					py = "$zeron.space.6",
					fade = { 12, 12 },
					fade_overflow = true,
					bg = T.clear,
					border = 0,
					rounded = 0,
					font = T.sans,
					text_size = "$font.size.lg",
					line_height = 22.75,
					color = T.text,
					focus = { border = 0 },
				},
			},
		},
		ui.div { h = 1, w_full = true, bg = T.hairline },
		ui.row {
			w_full = true,
			px = "$zeron.space.16",
			pt = "$zeron.space.4",
			pb = "$zeron.space.16",
			gap = "$zeron.space.8",
			items = "center",
			button { label = "Back", variant = "ghost", size = "sm", disabled = true },
			ui.div { grow = 1 },
			button {
				id = "question_next",
				label = "Submit",
				variant = "primary",
				size = "sm",
				on_click = props.on_send,
			},
		},
	}
end

-- Dictation in the composer (composer.rs): the mic starts it, the track
-- unrolls beside the mic with its clock while the model chip steps aside,
-- the paperclip turns into a cancel ✕; the stop plate ends it, and after
-- a moment of processing the words join the draft.
type Voice = { phase: State<dictation.Phase>, clock: State<string>, toggle: () -> (), cancel: () -> () }
local SAID = "and lead with what changed for Windows"
local function voice_state(props: Props): Voice?
	if props.on_voice then
		return nil
	end
	local phase = props.dictation or ui.use_state("idle" :: dictation.Phase)
	local clock = ui.use_state("0:00")
	local stop: (() -> ())? = nil
	local function halt()
		if stop then
			stop()
			stop = nil
		end
	end
	local function toggle()
		local p = phase:peek()
		if p == "idle" then
			local seconds = 0
			clock:set("0:00")
			phase:set("listening")
			-- The clock ticks once a second while it listens: no more.
			stop = ui.every(1000, function()
				seconds += 1
				clock:set(`{seconds // 60}:{string.format("%02d", seconds % 60)}`)
				return true
			end)
		elseif p == "listening" or p == "requesting" then
			halt()
			phase:set("processing")
			ui.after(900, function()
				if phase:peek() ~= "processing" then
					return
				end
				local draft = props.value:peek()
				props.value:set(
					if draft == "" then SAID elseif string.sub(draft, -1) == " " then draft .. SAID else `{draft} {SAID}`
				)
				phase:set("idle")
			end)
		end
	end
	local function cancel()
		halt()
		phase:set("idle")
	end
	return { phase = phase, clock = clock, toggle = toggle, cancel = cancel }
end

-- The attach button, or the cancel ✕ while dictating (each scaling in).
local function attach(props: Props, voice: Voice?): Node
	local id = props.id and props.id .. "_add"
	if not voice then
		return round("paperclip", props.on_add, id, "Attach images")
	end
	local v = voice :: Voice
	return ui.presence(function()
		return if v.phase:get() == "idle" then "attach" else "cancel"
	end, function(k: string): Node
		return if k == "attach"
			then round("paperclip", props.on_add, id, "Attach images")
			else round("close", v.cancel, props.id and props.id .. "_cancel", "Cancel dictation")
	end, {
		enter = { opacity = { 0, 1 }, scale = { 0.25, 1 }, duration = motion.d(motion.FAST), ease = motion.EASE_OUT },
	})
end

-- The mic: the app's round button, or dictation's mic and track.
local function mic(props: Props, voice: Voice?): Node
	if not voice then
		return round("microphone", props.on_voice, props.id and props.id .. "_mic", "Dictate")
	end
	local v = voice :: Voice
	return dictation.row {
		id = props.id,
		state = v.phase,
		clock = function()
			return v.clock:get()
		end,
		on_click = v.toggle,
	}
end

-- The model chip, out of the way while dictating.
local function chip(props: Props, voice: Voice?): Node
	if not voice then
		return model_chip(props)
	end
	local v = voice :: Voice
	return ui.show(function()
		return v.phase:get() == "idle"
	end, model_chip(props))
end

-- The session footer: 24 high, the checkout and branch at 12 (muted 60%),
-- the PR badge at the end.
local function footer(props: Props): Node
	local pr = require("./pr")
	return ui.row {
		w_full = true,
		h = 24,
		px = "$zeron.space.4",
		gap = "$zeron.space.4",
		items = "center",
		props.checkout and ui.row {
			h = 20,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			items = "center",
			rounded = T.radius_md,
			max_w = 160,
			icon { name = "folder", size = 12, color = T.secondary, opacity = 0.6 },
			txt.text { props.checkout, size = "sm", color = T.secondary, opacity = 0.6, truncate = true, line = false },
		},
		props.branch and ui.row {
			h = 20,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			items = "center",
			rounded = T.radius_md,
			max_w = 160,
			icon { name = "git-branch", size = 12, color = T.secondary, opacity = 0.6 },
			txt.text { props.branch, size = "sm", color = T.secondary, opacity = 0.6, truncate = true, line = false },
		},
		ui.div { grow = 1 },
		props.pr and pr.badge { tone = "open", number = props.pr, size = "md" },
		props.context and context_usage.usage {
			id = props.id and props.id .. "_context",
			used = props.context,
			total = props.context_total or 200000,
		},
	}
end

M.composer = ui.component(function(props: Props): Node
	local compact = props.compact == true
	-- Folding by width: the row while the draft fits it.
	local folds = props.compact == "auto"
	local fits = if folds then ui.use_state(true) else nil
	local carry: Carry? = if folds then { focused = false, refocus = false } else nil
	local input = ui.ref()
	local voice = voice_state(props)
	-- A pick hands the keyboard back to the draft, the caret at its end.
	local menu = if props.references
		then completion.menu(props.references, {
			id = props.id,
			on_accept = function()
				local el = input:peek()
				if el then
					el:focus()
					el:set_selection(utf8.len(props.value:peek()) or 0)
				end
			end,
		})
		else nil
	local above: { Node } = {}
	local live = props.queue
	if live then
		table.insert(
			above,
			ui.show(
				function()
					return #live:get() > 0
				end,
				ui.column {
					w_full = true,
					px = "$zeron.space.16",
					-- The pill below tucks under it by the overlap.
					mb = T.pull(tray.OVERLAP),
					tray.queue {
						id = props.id and `{props.id}_queue`,
						items = live,
						action = "Send now",
						on_remove = props.on_remove_queued,
						on_send = props.on_send_queued,
					},
				}
			)
		)
	end
	local question_dock: Dock? = nil
	for _, dock in props.docks or {} do
		if dock.kind == "queue" then
			local items = ui.state(`{props.id or "composer"}_queue`, {} :: { tray.Queued })
			local list: { tray.Queued } = {}
			for _, q in dock.items or {} do
				table.insert(list, { id = q.id, text = q.text })
			end
			items:set(list)
			table.insert(
				above,
				ui.column {
					w_full = true,
					px = "$zeron.space.16",
					-- The pill below tucks under it by the overlap.
					mb = T.pull(tray.OVERLAP),
					tray.queue {
						id = "queue_dock",
						items = items,
						action = "Send next",
						on_remove = props.on_remove_queued,
					},
				}
			)
		elseif dock.kind == "question" then
			question_dock = dock
		else
			table.insert(
				above,
				ui.column {
					w_full = true,
					px = "$zeron.space.4",
					pb = "$zeron.space.8",
					notice {
						id = "error_dock",
						message = dock.body or "Something went wrong.",
						tone = dock.tone or "danger",
						w_full = true,
					},
				}
			)
		end
	end
	local pill: Node
	if question_dock then
		pill = question(question_dock, props)
	else
		local function actions(): Node
			return ui.row {
				w_full = true,
				h = M.ACTIONS,
				pt = "$zeron.space.2",
				pb = "$zeron.space.8",
				px = "$zeron.space.12",
				gap = "$zeron.space.8",
				items = "center",
				ui.row {
					gap = "$zeron.space.2",
					items = "center",
					attach(props, voice),
				},
				ui.div { grow = 1 },
				chip(props, voice),
				mic(props, voice),
				send(props),
			}
		end
		local function compact_body(): Node
			return ui.row {
				w_full = true,
				h = M.COMPACT,
				pl = "$zeron.space.8",
				pr = "$zeron.space.8",
				gap = "$zeron.space.2",
				items = "center",
				attach(props, voice),
				text_input(props, true, menu, input, fits, carry),
				chip(props, voice),
				ui.row {
					gap = "$zeron.space.8",
					items = "center",
					pl = "$zeron.space.6",
					mic(props, voice),
					send(props),
				},
			}
		end
		local function expanded_body(): Node
			return ui.column {
				w_full = true,
				strip(props),
				comments_chip(props),
				ui.column {
					w_full = true,
					px = "$zeron.space.16",
					pt = "$zeron.space.16",
					pb = "$zeron.space.4",
					-- A new line grows the pill over 180 ms ease-out (COLLAPSE),
					-- its top rising while the action row stays put.
					layout = "height",
					layout_duration = motion.d(motion.COLLAPSE),
					layout_ease = motion.EASE_OUT,
					layout_clip = true,
					text_input(props, false, menu, input, fits, carry),
				},
				actions(),
			}
		end
		local body: Node
		if folds then
			-- The row while the draft fits it and nothing is attached. The
			-- flip snaps, as Zeron's first did (its morph ○: an eased box
			-- here costs every layout change).
			local attached = props.attachments
			local shown: string? = nil
			body = ui.presence(function()
				local one_row = (fits :: State<boolean>):get()
					and (attached == nil or #(attached :: State<{ Attachment }>):get() == 0)
					and (props.comments == nil or props.comments() == 0)
				local mode = if one_row then "row" else "open"
				if shown and mode ~= shown and carry then
					-- Before the editor goes (and blurs): the next one takes it.
					carry.refocus = carry.focused
				end
				shown = mode
				return mode
			end, function(mode: string): Node
				return if mode == "row" then compact_body() else expanded_body()
			end, {
				w_full = true,
				mode = "wait",
			})
		elseif compact then
			body = compact_body()
		else
			body = expanded_body()
		end
		pill = ui.column {
			id = props.id and props.id .. "_box",
			relative = true,
			w_full = true,
			rounded = T.radius(if props.docked then M.RADIUS_DOCKED else M.RADIUS),
			bg = T.input,
			backdrop_blur = frost.BLUR,
			border = 1,
			border_color = if props.preview == "focus" then T.strong else T.input_border,
			overflow = "visible",
			props.picker and completion.preview {
				token = props.picker.token,
				items = props.picker.items,
			},
			menu and menu.view,
			body,
		}
	end
	local has_footer = props.branch ~= nil or props.checkout ~= nil or props.pr ~= nil or props.context ~= nil
	return ui.column {
		id = props.id,
		w = props.w or M.MAX_WIDTH - 32,
		max_w = "100%",
		items = "stretch",
		above,
		-- A tray above tucks 18 under the pill (its own bottom margin, so a
		-- hidden one pulls nothing).
		pill,
		has_footer and ui.column { w_full = true, pt = "$zeron.space.8", footer(props) },
	}
end)

local _ = loaders
return M
