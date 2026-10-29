-- Zeron's composer as it ships (composer.rs): a pill at radius 26 (22 once
-- docked in a thread) in the composer's material (recipes.composer: dark
-- frost's faint tint over the blur, light frost's input at 35%, opaque's
-- input under the large shadow) edged with the composer's hairline; the text at 14/22.75 ("Do anything…" in the faint colour) over
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
	-- An image's picture: a click on its tile opens it.
	src: string?,
}
export type QueueItem = { id: string, text: string }
-- A question the agent asks (UserInputQuestion): its header, the question,
-- the options by their labels; several may be picked (`multi`), or it
-- takes typed text only (`multiline`).
export type Question = {
	id: string,
	header: string,
	question: string,
	options: { string },
	multi: boolean?,
	multiline: boolean?,
	prefill: string?,
}
-- What a session waiting on input asks: its questions, paged; answered
-- with each one's labels (a typed answer over the picked ones), or closed
-- unanswered.
export type Ask = {
	id: string,
	questions: { Question },
	on_answer: (answers: { { string } }) -> (),
	on_dismiss: (() -> ())?,
}
export type Dock = {
	kind: "queue" | "question" | "error",
	-- queue
	items: { QueueItem }?,
	timing: string?,
	-- question
	ask: Ask?,
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
	-- The draft's field, for a caller that hands it the keyboard.
	input_ref: Ref?,
	attachments: State<{ Attachment }>?,
	on_remove_attachment: ((id: string) -> ())?,
	-- A staged image's click: its preview.
	on_open_attachment: ((a: Attachment) -> ())?,
	-- A question the session waits on: its panel in the pill's place, the
	-- draft kept for after.
	ask: (() -> Ask?)?,
	-- Why the last send, stop or upload failed: a notice over the pill,
	-- dismissed by a click.
	error: State<string?>?,
	-- Offline with something to send: the caption over the pill says it
	-- waits.
	offline: types.Cond?,
	-- The todo tray, under the notices and over the queue (it tucks under
	-- what follows it by its own margin).
	todo: Node?,
	-- The draft is Markdown (composer_markdown.rs): faces as it is typed,
	-- markers hidden off the caret's lines, lists going on; code fences
	-- coloured by their language.
	markdown: boolean?,
	-- References as chips (`@` by default with `references`): their label
	-- and icon, `false` for a word that is none; a paste resolving
	-- references into them.
	chips: string?,
	chip_label: ((token: string) -> (string | false)?)?,
	chip_icon: ((token: string) -> string?)?,
	-- A chip's card under the pointer (a browser annotation's code).
	chip_tooltip: ((token: string) -> Node?)?,
	on_paste: ((text: string) -> string?)?,
	-- The queue: whether the harness steers mid-turn (a row's Steer, else
	-- Send next), the row being edited in the composer and its Save and
	-- Cancel, rows dragged, a row's image opened.
	steers: types.Cond?,
	editing: State<string?>?,
	on_edit_queued: ((id: string) -> ())?,
	on_save_edit: Handler?,
	on_cancel_edit: Handler?,
	on_move_queued: ((id: string, index: number) -> ())?,
	on_open_queued: ((file: tray.QueuedFile) -> ())?,
	-- Shared with the composer it hands over to (the new-session canvas's
	-- and the thread's): it glides from one place to the other.
	layout_id: string?,
	-- How many review comments are staged for the next message (read where
	-- it changes): a "2 comments" badge over the draft, 16 in and 12 down.
	comments: (() -> number)?,
	-- The send waits (read where it changes): a file comment's file is
	-- saving. The send button rests at 35% and Enter sends nothing.
	held: (() -> boolean)?,
	docks: { Dock }?,
	-- A live queue: what was typed while a run was live, shown in the queue
	-- tray over the pill while it holds anything.
	queue: State<{ tray.Queued }>?,
	on_send_queued: ((id: string) -> ())?,
	-- A run is live: the send button queues typed text, or stops when empty.
	working: types.Cond?,
	-- A message is on its way and the session has not started working on
	-- it: the 24-high strip above the pill says so (the gradient spinner
	-- and "Sending…", shell.rs status strip).
	sending: types.Cond?,
	model: Text?,
	effort: Text?,
	harness: icon_mod.Name?,
	-- Wraps the model chip in its picker (a popover anchored on it), and
	-- what a click on the chip does (opens it).
	model_picker: ((chip: Node) -> Node)?,
	on_model: (Handler | Action)?,
	-- The access chip before the model chip (kit/access), out of the way
	-- as the model chip is.
	access: Node?,
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
	-- The account's plan usage, before the context's ring
	-- (account_usage.rs).
	usage: Node?,
	branch: string?,
	checkout: string?,
	pr: number?,
	-- The pull request's state (its badge's tone; open unless given), and
	-- what a click on its badge does.
	pr_tone: string?,
	on_pr: (() -> ())?,
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
	-- Whether dictation is on (Settings → Voice): off, no mic, and what was
	-- being dictated is dropped.
	voice: types.Cond?,
	-- Whether a key is the dictation shortcut (held to talk, while the draft
	-- has the focus).
	dictation_key: ((e: KeyEvent) -> boolean)?,
	-- How the engine answers a dictation as it starts and as it
	-- transcribes: nothing (it goes on), or what it ended in.
	dictation_outcome: ((at: "start" | "end") -> dictation.Outcome?)?,
	-- What sends: Enter (⌘↩ too), or ⌘↩ alone with Enter adding a line.
	send_with: Reactive<"enter" | "cmd_enter">?,
	-- Whether the model chip shows.
	show_model: types.Cond?,
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
-- The glide between the canvas and the thread (composer_dock.rs duration):
-- docking, and back.
M.DOCK = 420
M.UNDOCK = 470

-- A Markdown draft's code fences in their language's colours
-- (composer_markdown.rs syntax_spans), a line at a time for the editor's
-- `highlight`: prose has none (its faces are the engine's). The state a
-- line leaves: 0 in prose; in a fence, 2 + its language × 4 + its marker
-- (backticks 0, tildes 2) + what its code leaves open (0 or 1).
local syntax = require("../lib/syntax")
local LANGUAGES = { "rs", "luau", "toml" }
local BY_TAG: { [string]: number } = { rust = 1, rs = 1, luau = 2, lua = 2, toml = 3 }
function M.fences(line: string, state: number): ({ { number | string } }, number)
	local marker, tag = string.match(line, "^%s*([`~][`~][`~]+)%s*([%w_+%-]*)")
	if state == 0 then
		if marker and (string.match(marker, "^`+$") or string.match(marker, "^~+$")) then
			local language = BY_TAG[string.lower(tag or "")] or 0
			return {}, 2 + language * 4 + (if string.sub(marker, 1, 1) == "~" then 2 else 0)
		end
		return {}, 0
	end
	local fence = state - 2
	local language, tilde, open = fence // 4, (fence // 2) % 2 == 1, fence % 2
	local close = if tilde then "^%s*~~~+%s*$" else "^%s*```+%s*$"
	if string.match(line, close) then
		return {}, 0
	end
	local highlight = if language > 0 then syntax.for_path(`code.{LANGUAGES[language]}`) else nil
	if not highlight then
		return {}, state
	end
	local spans, leaves = highlight(line, open)
	return spans, 2 + language * 4 + (if tilde then 2 else 0) + (if leaves ~= 0 then 1 else 0)
end

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
		if props.held and props.held() then
			return false
		end
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
-- fit, and back): the words are counted generously, the access chip at
-- its widest ("Auto-accept edits", "Plan").
local ACCESS_W = 190
local function fold_inset(props: Props): number
	local function len(t: Text?): number
		if t == nil then
			return 0
		end
		local s = if type(t) == "function" then (t :: any)() else t
		return utf8.len(tostring(s)) or 0
	end
	local words = len(props.model or "Claude Opus") + (if props.effort then len(props.effort) + 1 else 0)
	return 104 + math.min(44 + words * 7.5, 248) + (if props.access then ACCESS_W else 0)
end

-- Whether the draft has the focus, and whether a flip (a new editor)
-- hands it on.
type Carry = { focused: boolean, refocus: boolean }

-- What sends (Enter unless the app says ⌘↩).
local function send_with(props: Props): string
	local w = props.send_with
	if w == nil then
		return "enter"
	end
	local t = type(w)
	if t == "function" then
		return (w :: any)()
	elseif t == "string" then
		return w :: any
	end
	return (w :: any):peek()
end

local function text_input(
	props: Props,
	compact: boolean,
	menu: completion.Menu?,
	ref: Ref,
	fits: State<boolean>?,
	carry: Carry?,
	voice: Voice?
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
		-- ink at 8% (composer/chip.rs paint_chip): its label after its icon's
		-- well; it deletes whole.
		chips = props.chips or if props.references then "@" else nil,
		chip_color = T.ink3,
		chip_label = props.chip_label,
		chip_icon = props.chip_icon,
		chip_tooltip = props.chip_tooltip,
		on_paste = props.on_paste,
		-- Several lines: a Markdown draft, its fences in their language's
		-- colours (only the lines that change are asked again).
		markdown = props.markdown == true,
		highlight = if props.markdown then M.fences else nil,
		on_key_up = if voice and props.dictation_key
			then function()
				(voice :: Voice).release()
			end
			else nil,
		on_key = function(e: KeyEvent): boolean
			-- An open menu takes its keys first (Enter and Tab pick).
			if menu and menu.on_key(e) then
				return true
			end
			-- The dictation shortcut, while dictation is on.
			if
				voice
				and props.dictation_key
				and (props.voice == nil or types.on(props.voice))
				and not e["repeat"]
				and props.dictation_key(e)
			then
				voice.press()
				return true
			end
			-- Editing a queued message: Enter saves it to the queue, Escape
			-- leaves the row as it was.
			local editing = props.editing and props.editing:peek()
			if editing and e.key == "Enter" and not e.shift then
				if props.on_save_edit then
					props.on_save_edit()
				end
				return true
			elseif editing and e.key == "Escape" then
				if props.on_cancel_edit then
					props.on_cancel_edit()
				end
				return true
			end
			-- ⌘⏎ (Ctrl⏎) on an empty draft sends the latest queued message
			-- now (composer.rs on_modified_submit); with a draft, as ⏎.
			local modified = e.meta or e.ctrl
			if e.key == "Enter" and modified and props.value:peek() == "" then
				local queued = if props.queue then props.queue:peek() else {}
				local latest = queued[#queued]
				if latest and props.on_send_queued then
					props.on_send_queued(latest.id)
				end
				return true
			end
			-- Sending with ⌘↩: Enter adds a line (message_enter_bindings).
			if e.key == "Enter" and not modified and send_with(props) == "cmd_enter" then
				return false
			end
			if e.key == "Enter" and not e.shift then
				if types.on(props.working) then
					if props.on_queue then
						props.on_queue()
					end
				elseif props.on_send and not (props.held and props.held()) then
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
					src = a.src,
					icon = if a.kind == "link" then "global" elseif a.kind == "file" then "document" else nil,
					-- An image opens in the viewer (composer.rs staged preview).
					on_open = if a.kind == "image" and props.on_open_attachment
						then function()
							(props.on_open_attachment :: (a: Attachment) -> ())(a)
						end
						else nil,
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

-- The question panel (composer.rs render_wizard, the Wizard reducer): in
-- the pill's place at radius 26, in its material. A tracked header and,
-- paged, its "1/3"; the question at 15/20 medium ("Select one or more
-- options." under a multiple choice); options at radius 12, their number
-- 22 at the end; a typed answer over a hairline, which wins over what is
-- picked; Back and Next (Submit on the last), and the corner's close. A
-- single choice goes on by itself after 220 ms; 1 to 9 pick while the
-- answer is empty; Escape goes back, or closes an untouched first page.
M.AUTO_ADVANCE = 220
export type QuestionPanelProps = { id: string?, ask: Ask }
M.question_panel = ui.component(function(props: QuestionPanelProps): Node
	local ask = props.ask
	local questions = ask.questions
	local id = props.id or "question"
	local page = ui.use_state(1)
	local picked = ui.use_state({} :: { { number } })
	local typed: { State<string> } = {}
	for i, q in questions do
		typed[i] = ui.use_state(q.prefill or "")
	end
	local answer = ui.use_state("")
	local input = ui.ref()
	local function question(): Question
		return questions[page:get()]
	end
	local function picks(n: number): { number }
		return picked:get()[n] or {}
	end
	local function has_pick(): boolean
		return #picks(page:get()) > 0
	end
	local function is_picked(i: number): boolean
		return table.find(picks(page:get()), i) ~= nil and answer:get() == ""
	end
	-- Each page's typed answer lives in its own state; the field shows the
	-- page's.
	local function show_page(n: number)
		typed[page:peek()]:set(answer:peek())
		page:set(n)
		answer:set(typed[n]:peek())
		local el = input:peek()
		if el then
			el:focus()
		end
	end
	local function answers(): { { string } }
		typed[page:peek()]:set(answer:peek())
		local out: { { string } } = {}
		for n, q in questions do
			local text = typed[n]:peek()
			if not q.multiline then
				text = string.match(text, "^%s*(.-)%s*$") or ""
			end
			if text ~= "" or q.multiline then
				out[n] = { text }
			else
				local labels = {}
				for _, i in picked:peek()[n] or {} do
					table.insert(labels, q.options[i])
				end
				out[n] = labels
			end
		end
		return out
	end
	local function advance()
		local n = page:peek()
		if n < #questions then
			show_page(n + 1)
		else
			ask.on_answer(answers())
		end
	end
	local function back(): boolean
		local n = page:peek()
		if n > 1 then
			show_page(n - 1)
			return true
		end
		return false
	end
	local function dismiss()
		if ask.on_dismiss then
			ask.on_dismiss()
		end
	end
	local waiting = 0
	local function pick(i: number)
		local n = page:peek()
		local q = questions[n]
		if i < 1 or i > #q.options then
			return
		end
		local all = table.clone(picked:peek())
		local mine = table.clone(all[n] or {})
		if q.multi then
			local at = table.find(mine, i)
			if at then
				table.remove(mine, at)
			else
				table.insert(mine, i)
			end
			all[n] = mine
			picked:set(all)
		else
			all[n] = { i }
			picked:set(all)
			waiting += 1
			local this = waiting
			ui.after(M.AUTO_ADVANCE, function()
				if this == waiting and page:peek() == n then
					advance()
				end
			end)
		end
	end
	local function on_key(e: KeyEvent): boolean
		local empty = answer:peek() == ""
		local digit = tonumber(e.key)
		if digit and digit >= 1 and digit <= 9 and not (e.meta or e.ctrl or e.alt) then
			if empty then
				pick(digit)
				return true
			end
			return false
		elseif e.key == "Enter" and not e.shift then
			advance()
			return true
		elseif e.key == "Escape" then
			if empty then
				if page:peek() == 1 and #picks(1) == 0 then
					dismiss()
				else
					back()
				end
			end
			return true
		end
		return false
	end
	local function closes(): boolean
		return page:get() == 1 and not has_pick() and answer:get() == ""
	end
	local option_group = wash.group("question_options")
	return ui.column {
		id = id,
		relative = true,
		w_full = true,
		rounded = T.radius(M.RADIUS),
		-- Stands in for the pill: the same material, edged with the border.
		variants = recipes.composer { edge = "panel" },
		on_key = on_key,
		ui.column {
			w_full = true,
			px = "$zeron.space.16",
			pt = "$zeron.space.16",
			ui.row {
				items = "center",
				gap = "$zeron.space.10",
				pr = "$zeron.space.32",
				txt.text {
					function()
						return string.upper(question().header)
					end,
					size = "micro",
					weight = "medium",
					color = T.secondary,
					opacity = 0.6,
					letter_spacing = 0.8,
					line = false,
				},
				#questions > 1 and ui.row {
					id = `{id}_counter`,
					h = 20,
					px = "$zeron.space.6",
					items = "center",
					rounded = "$zeron.radius.6",
					bg = T.ink2,
					txt.text {
						function()
							return `{page:get()}/{#questions}`
						end,
						size = "micro",
						weight = "medium",
						color = T.secondary,
						opacity = 0.6,
						line = false,
					},
				},
			},
			-- Wrapping clear of the corner's close.
			ui.column {
				w_full = true,
				pt = "$zeron.space.6",
				pr = "$zeron.space.32",
				txt.text {
					function()
						return question().question
					end,
					id = `{id}_prompt`,
					size = "xl",
					weight = "medium",
					wrap = true,
				},
			},
			ui.show(
				function()
					return question().multi == true
				end,
				txt.text {
					"Select one or more options.",
					size = "sm",
					color = T.secondary,
					opacity = 0.65,
					mt = "$zeron.space.4",
				}
			),
			ui.presence(page, function(n: number): Node
				local rows: { Node } = {}
				for i, label in questions[n].options do
					local function on(): boolean
						return is_picked(i)
					end
					table.insert(
						rows,
						ui.button(wash.item(option_group, {
							id = `{id}_option_{i}`,
							label = label,
							w_full = true,
							px = "$zeron.space.14",
							py = "$zeron.space.10",
							gap = "$zeron.space.12",
							items = "center",
							-- Concentric with the pill: 16 in, inside its border.
							rounded = T.concentric(M.RADIUS, 16, 1),
							border = 1,
							variants = recipes.choice_card { selected = on },
							-- Keep the border's width on focus: a width change
							-- relays out mid-press and the next click is lost.
							focus = { border = 1, border_color = T.ink6 },
							cursor = "pointer",
							on_click = function()
								pick(i)
							end,
							txt.text {
								label,
								size = "md",
								weight = "medium",
								grow = 1,
								shrink = 1,
								min_w = 0,
								wrap = true,
							},
							i <= 9 and ui.row {
								w = 22,
								h = 22,
								items = "center",
								justify = "center",
								rounded = "$zeron.radius.6",
								bg = function()
									return if on() then T.ink5 else T.ink1
								end,
								shrink = 0,
								txt.text {
									tostring(i),
									size = "xs",
									color = function()
										return if on() then T.text else T.secondary
									end,
									line = false,
								},
							},
						}, on))
					)
				end
				return wash.list { group = option_group, gap = "$zeron.space.4", color = T.ink2, rows }
			end, { w_full = true, mt = "$zeron.space.12" }),
			-- The typed answer, over a hairline.
			ui.div { w_full = true, h = 1, mt = "$zeron.space.12", bg = T.hairline },
			ui.column {
				w_full = true,
				pt = "$zeron.space.12",
				pb = "$zeron.space.4",
				px = "$zeron.space.4",
				ui.textarea {
					id = `{id}_answer`,
					ref = input,
					value = answer,
					label = "Your own answer",
					placeholder = function()
						return if has_pick()
							then "Type your own answer, or leave this blank to use the selected option"
							else "Type your own answer, or pick an option above"
					end,
					placeholder_color = T.tertiary,
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = on_key,
					w_full = true,
					auto_height = true,
					min_h = 22.75,
					max_h = M.TEXT_MAX - 20,
					wrap = true,
					p = 0,
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
		ui.row {
			w_full = true,
			px = "$zeron.space.16",
			pt = "$zeron.space.4",
			pb = "$zeron.space.16",
			gap = "$zeron.space.8",
			items = "center",
			ui.show(function()
				return page:get() > 1
			end, button { id = `{id}_back`, label = "Back", variant = "ghost", size = "sm", on_click = back }),
			ui.div { grow = 1 },
			ui.row {
				opacity = function()
					return if has_pick() or answer:get() ~= "" or question().multiline then 1 else 0.4
				end,
				button {
					id = `{id}_next`,
					label = function()
						return if page:get() == #questions then "Submit" else "Next"
					end,
					variant = "primary",
					size = "sm",
					on_click = advance,
				},
			},
		},
		-- Closes it unanswered: the composer's own close, 12 in from the
		-- corner, concentric with the 26.
		ui.button {
			variants = recipes.wash { hover = "ink4" },
			id = `{id}_dismiss`,
			label = "Close without answering",
			tooltip = tip_bubble(function()
				return if closes() then "Close without answering · Esc" else "Close without answering"
			end),
			tooltip_placement = ABOVE,
			absolute = true,
			top = 12,
			right = 12,
			w = M.CONTROL,
			h = M.CONTROL,
			p = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_full,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = dismiss,
			icon { name = "close", size = 16, color = T.secondary },
		},
	}
end)

-- Dictation in the composer (composer.rs): the mic starts it, the track
-- unrolls beside the mic with its clock while the model chip steps aside,
-- the paperclip turns into a cancel ✕; the stop plate ends it, and after
-- a moment of processing the words join the draft.
type Voice = {
	phase: State<dictation.Phase>,
	clock: State<string>,
	toggle: () -> (),
	cancel: () -> (),
	-- The shortcut down and up: held, it talks until let go; tapped, it
	-- explains that it is held (dictation is hold to talk).
	press: () -> (),
	release: () -> (),
	-- What the last one ended in, under the composer until dismissed or
	-- another starts.
	outcome: State<dictation.Outcome?>,
}
local HOLD_MS = 300
local SAID = "and lead with what changed for Windows"
local function voice_state(props: Props): Voice?
	if props.on_voice then
		return nil
	end
	local phase = props.dictation or ui.use_state("idle" :: dictation.Phase)
	local clock = ui.use_state("0:00")
	local outcome = ui.use_state(nil :: dictation.Outcome?)
	local stop: (() -> ())? = nil
	local function halt()
		if stop then
			stop()
			stop = nil
		end
	end
	local function answer(at: "start" | "end"): dictation.Outcome?
		local ask = props.dictation_outcome
		return if ask then ask(at) else nil
	end
	local function toggle()
		local p = phase:peek()
		if p == "idle" then
			outcome:set(nil)
			local refused = answer("start")
			if refused then
				outcome:set(refused)
				return
			end
			local seconds = 0
			clock:set("0:00")
			phase:set("listening")
			dictation.started(phase)
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
				local ended = answer("end")
				if ended then
					phase:set("idle")
					outcome:set(ended)
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
	local held_at: number? = nil
	local function press()
		local p = phase:peek()
		if p == "idle" then
			toggle()
			held_at = ui.now()
		elseif p == "listening" or p == "requesting" then
			held_at = nil
			toggle()
		end
	end
	local function release()
		local at = held_at
		held_at = nil
		if not at or phase:peek() ~= "listening" then
			return
		end
		if ui.now() - at >= HOLD_MS then
			toggle()
		else
			-- A tap: nothing heard, and a word on holding.
			cancel()
			outcome:set(dictation.TAPPED)
		end
	end
	-- Dictation turned off drops what was being said.
	if props.voice ~= nil then
		ui.effect(function()
			if not types.on(props.voice) and phase:peek() ~= "idle" then
				cancel()
			end
		end)
	end
	return {
		phase = phase,
		clock = clock,
		toggle = toggle,
		cancel = cancel,
		press = press,
		release = release,
		outcome = outcome,
	}
end

-- What the last dictation ended in, under the pill, 8 below it.
local function dictation_status(props: Props, voice: Voice?): Node?
	if not voice then
		return nil
	end
	local outcome = (voice :: Voice).outcome
	return ui.presence(outcome, function(o: dictation.Outcome): Node
		return ui.column {
			w_full = true,
			pt = "$zeron.space.8",
			dictation.status {
				id = props.id and `{props.id}_dictation_status`,
				title = o.title,
				detail = o.detail,
				failed = o.failed,
				on_dismiss = function()
					outcome:set(nil)
				end,
			},
		}
	end, { w_full = true })
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

-- The mic: the app's round button, or dictation's mic and track; none
-- while dictation is off.
local function mic(props: Props, voice: Voice?): Node
	local node: Node
	if not voice then
		node = round("microphone", props.on_voice, props.id and props.id .. "_mic", "Dictate")
	else
		local v = voice :: Voice
		node = dictation.row {
			id = props.id,
			state = v.phase,
			clock = function()
				return v.clock:get()
			end,
			on_click = v.toggle,
		}
	end
	if props.voice == nil then
		return node
	end
	return ui.show(function()
		return types.on(props.voice)
	end, node)
end

-- The access and model chips, out of the way while dictating (and while
-- the model's is off).
local function chip(props: Props, voice: Voice?): Node
	local shown = props.show_model
	local chips = if props.access
		then ui.row { gap = "$zeron.space.4", items = "center", shrink = 1, min_w = 0, props.access, model_chip(props) }
		else model_chip(props)
	if not voice and shown == nil then
		return chips
	end
	return ui.show(function()
		return (shown == nil or types.on(shown)) and (voice == nil or (voice :: Voice).phase:get() == "idle")
	end, chips)
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
		props.pr and (if props.on_pr
			then ui.button {
				id = props.id and `{props.id}_pr`,
				label = `Pull request #{props.pr}`,
				role = "link",
				p = 0,
				bg = T.clear,
				border = 0,
				rounded = "$zeron.radius.6",
				focus = { border = 0 },
				cursor = "pointer",
				on_click = props.on_pr,
				pr.badge { tone = (props.pr_tone or "open") :: any, number = props.pr, size = "md" },
			}
			else pr.badge { tone = (props.pr_tone or "open") :: any, number = props.pr, size = "md" }),
		props.usage,
		props.context and context_usage.usage {
			id = props.id and props.id .. "_context",
			used = props.context,
			total = props.context_total or 200000,
		},
	}
end

-- What the composer says over itself (composer.rs): why the last send,
-- stop or upload failed (a notice a click dismisses), and, offline with
-- something to send (`intent`), that it waits; over the todo tray (`todo`)
-- and the queue.
export type NoticeProps = {
	id: string?,
	error: State<string?>?,
	offline: types.Cond?,
	intent: () -> boolean,
}
function M.notices(props: NoticeProps): { Node }
	local out: { Node } = {}
	-- Why a send, stop or upload failed (composer.rs failure notice): a
	-- click on it dismisses it.
	local failure = props.error
	if failure then
		table.insert(
			out,
			ui.presence(failure, function(message: string): Node
				return ui.button {
					id = props.id and `{props.id}_failure`,
					label = message,
					w_full = true,
					p = 0,
					mx = "$zeron.space.4",
					mt = "$zeron.space.6",
					mb = "$zeron.space.8",
					bg = T.clear,
					cursor = "pointer",
					focus = { border = 0 },
					on_click = function()
						failure:set(nil)
					end,
					notice { message = message, tone = "danger", w_full = true },
				}
			end, {
				w_full = true,
				enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
				exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
			})
		)
	end
	-- Offline with a draft or queued messages: one quiet caption (11, the
	-- faint text, the warning's dot), gone as the connection heals.
	local offline = props.offline
	if offline ~= nil then
		table.insert(
			out,
			ui.show(
				function()
					return types.on(offline) and props.intent()
				end,
				ui.row {
					id = props.id and `{props.id}_offline`,
					mx = "$zeron.space.8",
					mb = "$zeron.space.8",
					gap = "$zeron.space.6",
					items = "center",
					ui.div { w = 6, h = 6, rounded = T.radius_full, bg = T.warning, shrink = 0 },
					txt.text {
						"Offline — messages will send when you're back online.",
						size = "xs",
						color = T.tertiary,
						truncate = true,
						line = false,
					},
				}
			)
		)
	end
	return out
end

M.composer = ui.component(function(props: Props): Node
	local compact = props.compact == true
	-- Folding by width: the row while the draft fits it.
	local folds = props.compact == "auto"
	local fits = if folds then ui.use_state(true) else nil
	local carry: Carry? = if folds then { focused = false, refocus = false } else nil
	local input = props.input_ref or ui.ref()
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
	local queue = props.queue
	local notices = M.notices {
		id = props.id,
		error = props.error,
		offline = props.offline,
		intent = function(): boolean
			return props.value:get() ~= "" or (queue ~= nil and #queue:get() > 0)
		end,
	}
	for _, n in notices do
		table.insert(above, n)
	end
	-- The checklist tray stacks over the queue (todo_panel.rs).
	if props.todo then
		table.insert(above, props.todo)
	end
	local sending = props.sending
	if sending ~= nil then
		-- The status strip: 24 high, 24 in, the spinner 8 before the word.
		table.insert(
			above,
			ui.show(
				function()
					return types.on(sending)
				end,
				ui.row {
					id = props.id and `{props.id}_sending`,
					w_full = true,
					h = 24,
					px = "$zeron.space.24",
					gap = "$zeron.space.8",
					items = "center",
					loaders.gradient_spinner {},
					txt.text { "Sending…", size = "sm", color = T.secondary, line = false },
				}
			)
		)
	end
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
						steers = props.steers,
						on_remove = props.on_remove_queued,
						on_send = props.on_send_queued,
						on_edit = props.on_edit_queued,
						editing = props.editing,
						on_save = props.on_save_edit,
						on_cancel = props.on_cancel_edit,
						on_move = props.on_move_queued,
						on_open = props.on_open_queued,
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
			text_input(props, true, menu, input, fits, carry, voice),
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
				text_input(props, false, menu, input, fits, carry, voice),
			},
			actions(),
		}
	end
	local function the_pill(): Node
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
		return ui.column {
			id = props.id and props.id .. "_box",
			relative = true,
			w_full = true,
			rounded = T.radius(if props.docked then M.RADIUS_DOCKED else M.RADIUS),
			variants = recipes.composer,
			border_color = if props.preview == "focus" then T.strong else nil,
			overflow = "visible",
			props.picker and completion.preview {
				token = props.picker.token,
				items = props.picker.items,
			},
			menu and menu.view,
			body,
		}
	end
	local pill: Node
	local asking = props.ask
	if question_dock and question_dock.ask then
		pill = M.question_panel { id = "question_dock", ask = question_dock.ask }
	elseif asking then
		-- A question in the pill's place while one waits (fading in over
		-- the quick fade); the draft waits under it, as it was.
		local current: Ask? = nil
		pill = ui.presence(function()
			current = asking()
			return if current then `ask:{current.id}` else "pill"
		end, function(mode: string): Node
			local a = current
			if mode ~= "pill" and a then
				return M.question_panel { id = props.id and `{props.id}_question`, ask = a }
			end
			return the_pill()
		end, {
			w_full = true,
			mode = "wait",
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
		})
	else
		pill = the_pill()
	end
	local has_footer = props.branch ~= nil
		or props.checkout ~= nil
		or props.pr ~= nil
		or props.context ~= nil
		or props.usage ~= nil
	return ui.column {
		id = props.id,
		w = props.w or M.MAX_WIDTH - 32,
		max_w = "100%",
		items = "stretch",
		-- Handed between the canvas's composer and the thread's: it glides
		-- from one place to the other on one critically damped clock
		-- (composer_dock.rs Glide).
		layout_id = props.layout_id,
		layout_duration = if props.layout_id then motion.d(if props.docked then M.DOCK else M.UNDOCK) else nil,
		layout_ease = if props.layout_id then "critical" else nil,
		above,
		-- A tray above tucks 18 under the pill (its own bottom margin, so a
		-- hidden one pulls nothing).
		pill,
		dictation_status(props, voice),
		has_footer and ui.column { w_full = true, pt = "$zeron.space.8", footer(props) },
	}
end)

return M
