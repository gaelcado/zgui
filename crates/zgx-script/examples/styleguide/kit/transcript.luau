-- The transcript's pieces, as Zeron's `transcript.rs` and `markdown/render.rs`
-- draw them: the user's bubble, prose at 14/22, headings, a code block with
-- its header and copy button, inline code on the accent wash, a blockquote
-- rail, a tool call chip, and the message rail's ticks.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local loaders = require("./loaders")
local motion = require("./motion")
local attachments_mod = require("./attachments")
local kit_scroll = require("./scroll")

local M = {}

-- The column prose sits in: 768 with 16 each side.
M.WIDTH = 736

-- A long prompt folds (USER_COLLAPSED_LINES, USER_COLLAPSE_CHARS): past 5
-- lines or 400 characters it shows its first 5 lines (22 each), the last
-- line and a half fading out, and "Show more" under them.
M.FOLD_LINES = 5
M.FOLD_CHARS = 400
M.LINE = 22

-- Whether a prompt folds.
function M.folds(text: string): boolean
	local _, breaks = string.gsub(text, "\n", "")
	return breaks + 1 > M.FOLD_LINES or (utf8.len(text) or #text) > M.FOLD_CHARS
end

-- A sent reference's chip (composer/chip.rs paint_chip, as the composer
-- draws it): `@path ` or a session's `@Its\u{a0}title ` on ink 8% at radius
-- 5, its glyph before its name.
local function chips(text: string): { [any]: any }?
	if not string.find(text, "@[^%s]") then
		return nil
	end
	local runs: { [any]: any } = {}
	local at = 1
	local from = 1
	while true do
		local s, e = string.find(text, "@[^%s]+", from)
		if not s or not e then
			break
		end
		from = e + 1
		if s == 1 or string.match(string.sub(text, s - 1, s - 1), "%s") then
			if s > at then
				table.insert(runs, ui.span { string.sub(text, at, s - 1), literal = true })
			end
			local token = string.sub(text, s + 1, e)
			local label = string.gsub(token, "\u{a0}", " ")
			local session = string.find(token, "\u{a0}", 1, true) ~= nil or not string.find(token, "[%./]")
			local src = if session
				then "icons/chat-round-line.svg"
				else `icons/file-icons/{require("./file_icon").asset(token)}.svg`
			table.insert(
				runs,
				ui.span {
					label,
					literal = true,
					bg = T.ink3,
					padding = { 4, 1 },
					radius = 5,
					-- A file's own icon; a session's glyph in the muted colour.
					icon = { src = src, size = 12, gap = 4, tint = if session then T.secondary else nil },
				}
			)
			at = e + 1
		end
	end
	if at <= #text then
		table.insert(runs, ui.span { string.sub(text, at), literal = true })
	end
	return runs
end

-- Draws a prompt's Markdown as a reply's, at the bubble's size (set by
-- kit/markdown, which needs this module): its id and links.
M.markdown = nil :: ((text: string, id: string?, links: any) -> Node)?

-- Whether a message's Markdown says nothing plain text does not
-- (transcript.rs plain_markdown): paragraphs of unstyled runs.
local function plain(text: string): boolean
	for _, b in ui.markdown(text, { breaks = true }) do
		if b.t ~= "p" then
			return false
		end
		for _, r in b.s do
			if r.b or r.i or r.c or r.s or r.a or r.f or r.img then
				return false
			end
		end
	end
	return true
end

-- The prompt's text: its references as chips; else its Markdown, drawn as
-- a reply's (code fences, links), unless it is plain
-- (transcript.rs render_user_markdown).
local function prompt_text(text: string | () -> string, id: string?, links: any): Node
	local runs = if type(text) == "string" then chips(text) else nil
	if runs then
		runs.wrap = true
		runs.text_size = "$font.size.lg"
		runs.line_height = "$font.line.lg"
		runs.color = T.text
		return ui.rich(runs :: any)
	end
	local draw = M.markdown
	if draw and type(text) == "string" and not plain(text) then
		return draw(text, id and `{id}_md`, links)
	end
	return txt.text { text, size = "lg", wrap = true, literal = true }
end

-- A prompt past the fold (render_user_body, render_user_expander): its
-- first lines, the rest under a fade, and the plain link under them ("Show
-- more" and a chevron, 14 in the muted colour, the text's under the
-- pointer), 8 below; opening and closing ease its height over 200 ms.
local function folded(id: string?, text: string, links: any): Node
	local open = ui.use_state(false)
	return ui.column {
		min_w = 0,
		items = "start",
		ui.column {
			id = id and `{id}_body`,
			w_full = true,
			max_h = function(): number
				return if open:get() then 1e6 else M.FOLD_LINES * M.LINE
			end,
			overflow = "hidden",
			fade = { 0, M.LINE * 1.5 },
			layout = "height",
			layout_clip = true,
			layout_duration = motion.d(motion.RESIZE),
			layout_ease = motion.EASE_OUT,
			prompt_text(text, id, links),
		},
		ui.button {
			id = id and `{id}_expander`,
			label = function(): string
				return if open:get() then "Collapse message" else "Expand message"
			end,
			mt = "$zeron.space.8",
			p = 0,
			gap = "$zeron.space.5",
			items = "center",
			bg = T.clear,
			color = T.secondary,
			hover = { bg = T.clear, color = T.text },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ui.toggle(open),
			txt.text {
				function(): string
					return if open:get() then "Show less" else "Show more"
				end,
				size = "lg",
				color = "inherit",
				line = false,
			},
			icon {
				name = "alt-arrow-down",
				size = 12,
				color = "currentColor",
				hidden = function()
					return open:get()
				end,
			},
			icon {
				name = "alt-arrow-up",
				size = 12,
				color = "currentColor",
				hidden = function()
					return not open:get()
				end,
			},
		},
	}
end

-- The chat that sent a message through Zeron's send_message: "Message from
-- [mark] Chat" over its bubble (render_agent_sender, user_caption): 13 in
-- the muted colour, the mark 14 and the title medium, 6 above it; a click
-- opens that chat.
export type Sender = { title: string, icon: string?, tint: Color?, on_open: Handler? }

-- `[mark] Name` in a caption (caption_label): the mark 14, 5 before the
-- name in medium.
local function caption_label(from: Sender): Node
	return ui.row {
		min_w = 0,
		gap = "$zeron.space.5",
		items = "center",
		from.icon and icon { name = from.icon :: any, size = 14, color = from.tint or "currentColor" } or nil,
		txt.text {
			from.title,
			literal = true,
			size = "md",
			weight = "medium",
			color = "inherit",
			truncate = true,
			line = false,
			min_w = 0,
			shrink = 1,
		},
	}
end

-- "`lead` [mark] Chat" (render_chat_caption): 13 in the muted colour, 6
-- apart; a chat the workspace lists opens on a click.
local function chat_caption(id: string?, lead: string, chat: Sender): Node
	local body = {
		id = id,
		max_w = "80%",
		min_w = 0,
		gap = "$zeron.space.6",
		items = "center",
		overflow = "hidden",
		color = T.secondary,
		txt.text { lead, size = "md", color = "inherit", line = false, shrink = 0 },
		caption_label(chat),
	} :: { [any]: any }
	if not chat.on_open then
		return ui.row(body)
	end
	body.p = 0
	body.bg = T.clear
	body.hover = { bg = T.clear, color = T.text }
	body.focus = { border = 0 }
	body.cursor = "pointer"
	body.label = `{lead} {chat.title}`
	body.on_click = chat.on_open
	return ui.button(body)
end

function M.sender(id: string?, from: Sender): Node
	return ui.row { w_full = true, justify = "end", pb = "$zeron.space.6", chat_caption(id, "Message from", from) }
end

-- A message this chat's agent sent another through Zeron's send_message
-- (RowKind::SentMessage): "Message to [mark] Chat" on the left, "Couldn't
-- message" once the call failed, at 65% while it has not returned.
export type SentProps = { id: string?, to: Sender, failed: boolean?, pending: boolean? }
function M.sent_message(props: SentProps): Node
	return ui.row {
		w_full = true,
		opacity = if props.pending then 0.65 else nil,
		chat_caption(props.id, if props.failed then "Couldn't message" else "Message to", props.to),
	}
end

-- The provider-switch seam (switch_marker): "[mark] Claude Code → [mark]
-- Codex" right-aligned over the message that switched, the arrow 12 at
-- 70%, 6 above the bubble.
function M.switch_marker(id: string?, from: Sender, to: Sender): Node
	return ui.row {
		id = id,
		w_full = true,
		justify = "end",
		pb = "$zeron.space.6",
		ui.row {
			max_w = "100%",
			min_w = 0,
			gap = "$zeron.space.6",
			items = "center",
			overflow = "hidden",
			color = T.secondary,
			caption_label(from),
			icon { name = "arrow-right", size = 12, color = "currentColor", opacity = 0.7 },
			caption_label(to),
		},
	}
end

-- The user's turn: a bubble on wash 8%, radius 16, padding 16×10, its text
-- 14 on 22, at most 80% of the column, on the right; under it the
-- message's strip (`meta`: its time and copy under the pointer), unless
-- `meta` is false. Over it, the chat that sent it (`from`) and what it
-- carried (`attachments`: thumbnails, which open with `on_attachment`,
-- and file pills, right-aligned and wrapping 8 apart).
export type BubbleProps = {
	id: string?,
	text: string | () -> string,
	time: string?,
	meta: boolean?,
	from: Sender?,
	-- The provider the chat switched from and to, at this message.
	switched: { from: Sender, to: Sender }?,
	-- Its Markdown's links as a reply's (kit/markdown's `Links`).
	links: any,
	-- A state: a message on its way, its uploads moving on.
	attachments: ({ attachments_mod.Sent } | State<{ attachments_mod.Sent }>)?,
	on_attachment: ((a: attachments_mod.Sent) -> ())?,
	-- Whether any of it shows in the transcript's view (the rail's light).
	on_visible: ((visible: boolean, el: Element) -> ())?,
}
M.user_bubble = ui.component(function(props: BubbleProps): Node
	local text = props.text
	local strip: Node? = nil
	local function item(a: attachments_mod.Sent): Node
		if a.kind ~= "image" then
			return attachments_mod.pill(a)
		end
		local open = props.on_attachment
		return attachments_mod.sent(
			a,
			if open and a.status ~= "uploading"
				then function()
					open(a)
				end
				else nil
		)
	end
	local given: any = props.attachments
	local box = {
		id = props.id and `{props.id}_attachments`,
		w_full = true,
		flex_wrap = true,
		justify = "end",
		items = "start",
		gap = "$zeron.space.8",
		px = "$zeron.space.4",
		pt = "$zeron.space.4",
		pb = "$zeron.space.6",
	} :: { [any]: any }
	if type(given) == "table" and #given > 0 then
		local items: { Node } = {}
		for _, a in given :: { attachments_mod.Sent } do
			table.insert(items, item(a))
		end
		table.insert(box, items)
		strip = ui.row(box)
	elseif given ~= nil and type(given) ~= "table" then
		local list = given :: State<{ attachments_mod.Sent }>
		box.direction = "row"
		box.key = function(a: attachments_mod.Sent)
			return a.id
		end
		strip = ui.show(function()
			return #list:get() > 0
		end, ui.each(list, item, box))
	end
	local long = type(text) == "string" and M.folds(text)
	return ui.column {
		id = props.id,
		w_full = true,
		hover_group = true,
		on_visible = props.on_visible,
		props.switched and M.switch_marker(props.id and `{props.id}_switch`, props.switched.from, props.switched.to)
			or nil,
		props.from and M.sender(props.id and `{props.id}_from`, props.from) or nil,
		strip,
		ui.row {
			w_full = true,
			justify = "end",
			ui.column {
				max_w = "80%",
				min_w = 0,
				px = "$zeron.space.16",
				py = "$zeron.space.10",
				rounded = T.radius_xl,
				bg = T.ink3,
				if long
					then folded(props.id, text :: string, props.links)
					else prompt_text(text, props.id, props.links),
			},
		},
		props.meta ~= false and M.meta {
			id = props.id and `{props.id}_meta`,
			time = props.time,
			copy = text,
			align = "end",
		} or nil,
	}
end)

-- Prose: 14/22, blocks 12 apart.
export type ProseProps = { id: string?, [number]: Child }
M.prose = ui.component(function(props: ProseProps): Node
	return ui.column { id = props.id, w_full = true, gap = "$zeron.space.12", { table.unpack(props) } }
end)
function M.paragraph(text: string): Node
	return txt.text { text, size = "lg", wrap = true }
end
-- Headings: h1 19/27, h2 16/24, h3 15/22, the rest 14/22, all semibold.
function M.heading(level: number, text: string): Node
	local size: txt.Size = if level == 1 then "xxl" elseif level == 2 then "xl" else "lg"
	return txt.text {
		text,
		size = size,
		weight = "semibold",
		wrap = true,
		mt = if level <= 2 then "$zeron.space.8" else "$zeron.space.4",
	}
end

-- A code block (render.rs render_code_block): radius 10 on ink 3.5% with a
-- hairline; a 28-high header with the language at 11 and its actions, 22
-- high and 2 apart: Fit content (long lines wrap) or horizontal scrolling,
-- what the block adds (a diagram's Show source), and Copy, whose check and
-- "Copied" hold for 1.2 s. The code is mono 12/18, padding 12×10, its
-- syntax coloured by its language in the engine, line by line, so a block
-- streaming in colours only its new lines; with `veil`, what streams in
-- fades in.
export type CodeProps = {
	id: string?,
	language: string?,
	-- The code, or its lines.
	text: string?,
	lines: { string }?,
	-- Colours its lines: lib/syntax's highlighter for its language.
	highlight: ((line: string, state: number) -> ({ { number | string } }, number))?,
	-- A key: what streams in fades in, kept as the block is built again.
	veil: string?,
	-- Long lines wrap rather than scroll; a state, the header toggles it.
	fit: (boolean | State<boolean>)?,
	-- Header actions before Copy (a diagram's Show source).
	actions: { Node }?,
	-- In place of the code (a diagram).
	body: Node?,
	-- Copy does this instead of writing the code to the clipboard.
	on_copy: Handler?,
}

-- A header action: a 22 square at radius 6, its icon at 13; `on` keeps
-- ink 8% under it (11% under the pointer).
function M.code_action(props: {
	id: string?,
	label: string,
	icon: icon_mod.Name,
	on_click: Handler,
	on: boolean?,
}): Node
	return ui.button {
		id = props.id,
		label = props.label,
		tooltip = props.label,
		w = 22,
		h = 22,
		p = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = if props.on then T.ink3 else T.clear,
		hover = { bg = if props.on then T.ink4 else T.ink3 },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = props.on_click,
		icon { name = props.icon, size = 13, color = T.secondary },
	}
end

M.COPIED_CODE = 1200

M.code_block = ui.component(function(props: CodeProps): Node
	local code = props.text or table.concat(props.lines or {}, "\n")
	local copied = ui.use_state(false)
	local fit = props.fit
	local fitting: State<boolean>? = if fit ~= nil and type(fit) ~= "boolean" then fit :: any else nil
	local function wraps(): boolean
		return if fitting then fitting:get() else fit == true
	end
	local actions: { Node } = {}
	if fitting then
		local f = fitting
		table.insert(
			actions,
			ui.presence(f, function(on: boolean): Node
				return M.code_action {
					id = props.id and `{props.id}_fit`,
					label = if on then "Use horizontal scrolling" else "Fit content",
					icon = "wrap-text",
					on = on,
					on_click = function()
						f:set(not f:peek())
					end,
				}
			end)
		)
	end
	for _, a in props.actions or {} do
		table.insert(actions, a)
	end
	table.insert(
		actions,
		ui.button {
			id = props.id and `{props.id}_copy`,
			label = "Copy code",
			tooltip = "Copy code",
			h = 22,
			px = "$zeron.space.6",
			gap = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.5",
			bg = T.clear,
			hover = { bg = T.ink3 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = props.on_copy or function()
				ui.clipboard.write(code)
				copied:set(true)
				ui.after(M.COPIED_CODE, function()
					copied:set(false)
				end)
			end,
			icon {
				name = "copy",
				size = 12,
				color = T.secondary,
				hidden = function()
					return copied:get()
				end,
			},
			icon {
				name = "check",
				size = 12,
				color = T.secondary,
				hidden = function()
					return not copied:get()
				end,
			},
			ui.show(copied, txt.text { "Copied", size = "micro", color = T.secondary, line = false }),
		}
	)
	local function lines(wrap: boolean): Node
		return ui.rich {
			id = props.id and `{props.id}_code`,
			wrap = wrap,
			w_full = wrap,
			min_w = if wrap then 0 else nil,
			shrink = if wrap then 1 else 0,
			text_size = "$font.size.sm",
			line_height = "$font.line.md",
			font = T.mono,
			color = T.text,
			veil = props.veil,
			ui.span { code, literal = true, highlight = props.highlight },
		}
	end
	local body = props.body
		or ui.presence(wraps, function(wrap: boolean): Node
			if wrap then
				return ui.column { w_full = true, min_w = 0, px = "$zeron.space.12", py = "$zeron.space.10", lines(true) }
			end
			return ui.scroll_x {
				id = props.id and `{props.id}_scroll`,
				w_full = true,
				px = "$zeron.space.12",
				py = "$zeron.space.10",
				lines(false),
			}
		end, { w_full = true })
	return ui.column {
		id = props.id,
		w_full = true,
		min_w = 0,
		rounded = T.radius_lg,
		bg = T.ink1,
		border = 1,
		border_color = T.border,
		overflow = "hidden",
		ui.row {
			h = 28,
			pl = "$zeron.space.12",
			pr = "$zeron.space.5",
			items = "center",
			bg = T.ink1,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.border,
			txt.text { props.language or "text", size = "xs", color = T.tertiary, grow = 1, line = false },
			ui.row { gap = "$zeron.space.2", items = "center", actions },
		},
		body,
	}
end)

-- Inline code, as a span on the accent wash at radius 4.5.
function M.code(text: string): Span
	return ui.span { text, font = "mono", bg = T.code_wash }
end

-- A blockquote: a 2-point accent rail at 60%, the accent at 5% behind.
function M.quote(text: string): Node
	return ui.row {
		w_full = true,
		items = "stretch",
		ui.div { w = 2, bg = T.accent, opacity = 0.6, shrink = 0 },
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			px = "$zeron.space.12",
			py = "$zeron.space.8",
			rounded_tr = "$zeron.radius.6",
			rounded_br = "$zeron.radius.6",
			bg = T.accent_faint,
			txt.text { text, size = "lg", color = T.secondary, wrap = true },
		},
	}
end

-- A tool call: a chip card at radius 9 on ink 3% with a 7% hairline; the
-- tool's icon, what it did, and a running or done mark.
export type ToolState = "running" | "done" | "failed"
export type ToolProps = {
	id: string?,
	icon: icon_mod.Name?,
	title: string,
	detail: string?,
	-- A state or a function: a change cross-fades the mark.
	state: (ToolState | State<ToolState> | () -> ToolState)?,
	on_click: (Handler | Action)?,
}
M.tool = ui.component(function(props: ToolProps): Node
	local given: any = props.state
	local function state(): ToolState
		if type(given) == "function" then
			return (given :: () -> ToolState)()
		elseif type(given) == "string" then
			return given
		elseif given ~= nil then
			return given:get()
		end
		return "done"
	end
	return ui.button {
		id = props.id,
		h = 30,
		pl = "$zeron.space.8",
		pr = "$zeron.space.10",
		gap = "$zeron.space.8",
		items = "center",
		self = "start",
		max_w = "100%",
		rounded = "$zeron.radius.9",
		bg = T.ink1,
		border = 1,
		border_color = T.hairline,
		hover = { bg = T.ink2 },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = props.on_click,
		-- Running, a spinner; done, the tool's icon pops in where it was.
		ui.presence(function()
			return state()
		end, function(now: string): Node
			if now == "running" then
				return ui.row { w = 14, h = 14, items = "center", justify = "center", loaders.mini_spinner { cell = 2 } }
			end
			return icon {
				name = if now == "failed" then "danger-triangle" else props.icon or "terminal",
				size = 14,
				color = if now == "failed" then T.danger else T.secondary,
			}
		end, {
			w = 14,
			h = 14,
			shrink = 0,
			enter = { opacity = { 0, 1 }, scale = { 0.6, 1 }, duration = motion.d(220), ease = "outBack(1.6)" },
			exit = { opacity = 0, scale = 0.6, duration = motion.d(120), ease = "inQuad" },
		}),
		txt.text { props.title, size = "sm", weight = "medium", line = false, shrink = 0 },
		props.detail and txt.text {
			props.detail,
			size = "sm",
			mono = true,
			color = T.tertiary,
			line = false,
			truncate = true,
			shrink = 1,
			min_w = 0,
		},
	}
end)

-- The working trailer under an assistant turn (render_working_trailer): 16
-- under the turn, the gradient spinner and 8 after it the turn's word and
-- an ellipsis at 12 in the muted colour, then how long it has worked at 11
-- in the faint colour ("Pondering… 1m 32s"). The word is one of Zeron's 21,
-- a step every 7 s from where the chat's seed puts it; the engine moves
-- the word and the timer on (`ui.clock`), so no script runs as they tick.
-- `label` says what the turn waits on instead ("Sending"), with no timer;
-- `queued` (delivery degraded) says "Queued — will send automatically" in
-- the warning colour. A change of what it says rolls, the old words rising
-- out as the new rise in (550 ms, outQuint).
M.WORDS = {
	"Zeroning",
	"Thinking",
	"Pondering",
	"Scheming",
	"Brewing",
	"Weaving",
	"Tinkering",
	"Musing",
	"Composing",
	"Sifting",
	"Untangling",
	"Distilling",
	"Sketching",
	"Plotting",
	"Riffing",
	"Combobulating",
	"Percolating",
	"Marinating",
	"Noodling",
	"Puzzling",
	"Conjuring",
}
M.ROTATE = 7000
M.QUEUED = "Queued — will send automatically"
local WORDS_ON: { string } = {}
for i, w in M.WORDS do
	WORDS_ON[i] = `{w}…`
end
-- A chat's place in the words (flavour_seed): the same chat starts on the
-- same word, others elsewhere.
function M.seed(chat: string): number
	local h = 5381
	for i = 1, #chat do
		h = (h * 33 + string.byte(chat, i)) % 2147483647
	end
	return h % #M.WORDS
end
export type WorkingProps = {
	id: string?,
	label: (string | State<string> | () -> string?)?,
	-- When the turn began (ms since the epoch; now unless given), and the
	-- chat whose seed picks the words.
	since: number?,
	seed: string?,
	queued: (() -> boolean)?,
}
M.working = ui.component(function(props: WorkingProps): Node
	local given: any = props.label
	local function label(): string?
		if type(given) == "function" then
			return (given :: () -> string?)()
		elseif type(given) == "string" then
			return given
		elseif given ~= nil then
			return given:get()
		end
		return nil
	end
	local since = props.since or ui.now()
	local word = ui.clock {
		since = since,
		every = M.ROTATE,
		cycle = WORDS_ON,
		offset = M.seed(props.seed or props.id or ""),
	}
	local elapsed = ui.clock { since = since }
	local queued = props.queued
	local function phase(): string
		if queued and queued() then
			return "queued"
		end
		local l = label()
		return if l then `:{l}` else "word"
	end
	local travel = 6
	return ui.row {
		id = props.id,
		pt = "$zeron.space.16",
		gap = "$zeron.space.8",
		items = "center",
		loaders.gradient_spinner {},
		ui.presence(phase, function(now: string): Node
			if now == "queued" then
				return txt.text { M.QUEUED, size = "sm", color = T.warning, line = false }
			elseif now == "word" then
				return txt.text { word, size = "sm", color = T.secondary, line = false }
			end
			local l = string.sub(now, 2)
			return txt.text {
				if string.sub(l, -3) == "…" then l else `{l}…`,
				literal = true,
				size = "sm",
				color = T.secondary,
				line = false,
			}
		end, {
			enter = {
				opacity = { 0, 1 },
				y = { travel, 0 },
				duration = motion.d(motion.ROLL),
				ease = motion.EASE_OUT_QUINT,
			},
			exit = { opacity = 0, y = -travel, duration = motion.d(motion.ROLL), ease = motion.EASE_OUT_QUINT },
		}),
		txt.text {
			elapsed,
			id = props.id and `{props.id}_timer`,
			size = "xs",
			color = T.tertiary,
			line = false,
			mt = "$zeron.space.1",
			hidden = function()
				return phase() ~= "word"
			end,
		},
	}
end)

-- A send that failed (the trailer's retry): "Not delivered — click to
-- retry" at 12 in the danger colour, 16 under the prompt.
-- The transcript loader (render_loader), centred over the blank list
-- while a chat on another device has nothing to show yet: the ring
-- spinner 20 in the muted colour over what it waits on, 8 apart, 12 in
-- the faint colour; hard offline waits on nothing the app does, so the
-- warning's 5 dot stands for the spinner, 6 before the words. It fades in
-- rising 4 over 500 ms (motion::fade_in).
export type Loading = "opening" | "syncing" | "reconnecting" | "offline"
M.LOADING = {
	opening = "Opening…",
	syncing = "Syncing…",
	reconnecting = "Reconnecting…",
	offline = "Offline — this chat loads when you're back online",
} :: { [Loading]: string }
M.LOADER_DELAY = 300
function M.loader(id: string?, loading: () -> Loading?): Node
	return ui.column {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		items = "center",
		justify = "center",
		pointer_events = "none",
		-- Its words change in place; it fades in once.
		ui.presence(function(): string?
			return if loading() then "on" else nil
		end, function(): Node
			local function offline(): boolean
				return loading() == "offline"
			end
			return ui.column {
				id = id,
				items = "center",
				gap = "$zeron.space.8",
				on_mount = function(el: Element)
					anime.animate(el, {
						opacity = { 0, 1 },
						y = { 4, 0 },
						duration = motion.d(500),
						ease = motion.EASE_OUT_EXPO,
					})
				end,
				ui.show(function()
					return not offline()
				end, loaders.ring { size = 20 }),
				ui.row {
					gap = "$zeron.space.6",
					items = "center",
					ui.show(offline, ui.div { w = 5, h = 5, rounded = T.radius_full, bg = T.warning, shrink = 0 }),
					txt.text {
						function(): string
							local now = loading()
							return if now then M.LOADING[now] else ""
						end,
						id = id and `{id}_caption`,
						size = "sm",
						color = T.tertiary,
						line = false,
					},
				},
			}
		end),
	}
end

export type UndeliveredProps = { id: string?, on_retry: Handler? }
function M.undelivered(props: UndeliveredProps): Node
	return ui.row {
		pt = "$zeron.space.16",
		ui.button {
			id = props.id,
			p = 0,
			bg = T.clear,
			hover = { bg = T.clear },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = props.on_retry,
			txt.text { "Not delivered — click to retry", size = "sm", color = T.danger, line = false },
		},
	}
end

-- The transcript's error (error_chip, notice_chip_with_action as a tile):
-- 4 above and below, a block on the danger at 10% at radius 10, 10 by 8 in,
-- 6 between its lines; its header the 20 tile (radius 6, the danger at
-- 12%, the triangle 12) and "Error" medium, both in the muted danger at
-- 80%, the copy button at its end; the message under it, wrapped (an
-- agent's exit status and its stderr), in the muted danger. A refusal
-- signing in fixes says so ("Signed out", "Limit reached") and offers its
-- `action` under the message: 12 medium in the muted danger on the
-- danger at 14% (22% under the pointer), 10 by 4 in at radius 6.
export type ErrorProps = {
	id: string?,
	message: string,
	label: string?,
	action: { label: string, on_click: Handler }?,
}
function M.error_chip(props: ErrorProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		py = "$zeron.space.4",
		ui.column {
			w_full = true,
			px = "$zeron.space.10",
			py = "$zeron.space.8",
			gap = "$zeron.space.6",
			rounded = "$zeron.radius.10",
			bg = T.danger_alert,
			ui.row {
				w_full = true,
				gap = "$zeron.space.8",
				items = "center",
				ui.row {
					w = 20,
					h = 20,
					shrink = 0,
					rounded = "$zeron.radius.6",
					bg = T.danger_tile,
					items = "center",
					justify = "center",
					icon { name = "danger-triangle", size = 12, color = T.danger_muted, opacity = 0.8 },
				},
				txt.text {
					props.label or "Error",
					size = "sm",
					weight = "medium",
					color = T.danger_muted,
					opacity = 0.8,
					line = false,
				},
				ui.div { grow = 1 },
				ui.button {
					id = props.id and `{props.id}_copy`,
					label = "Copy message",
					tooltip = "Copy message",
					w = 20,
					h = 20,
					p = 0,
					items = "center",
					justify = "center",
					rounded = "$zeron.radius.6",
					bg = T.clear,
					hover = { bg = T.danger_tile },
					focus = { border = 0 },
					cursor = "pointer",
					on_click = function()
						ui.clipboard.write(props.message)
					end,
					icon { name = "copy", size = 12, color = T.danger_muted, opacity = 0.8 },
				},
			},
			txt.text {
				props.message,
				literal = true,
				size = "sm",
				color = T.danger_muted,
				wrap = true,
			},
			props.action and ui.row {
				pt = "$zeron.space.2",
				ui.button {
					id = props.id and `{props.id}_action`,
					px = "$zeron.space.10",
					py = "$zeron.space.4",
					rounded = "$zeron.radius.6",
					bg = T.danger_wash,
					hover = { bg = T.danger_lit },
					focus = { border = 0 },
					cursor = "pointer",
					on_click = props.action.on_click,
					txt.text {
						props.action.label,
						size = "sm",
						weight = "medium",
						color = T.danger_muted,
						line = false,
					},
				},
			} or nil,
		},
	}
end

-- A question the agent asked (input_chip), its controls the composer's: 4
-- above and below, a 34 row at radius 10 with a hairline at 8% on ink 4.5%,
-- 8 in, at 12: the 20 tile (radius 6, ink 9%, the speech glyph 12), the
-- medium "Question", then "Awaiting your answer…" while it waits, or
-- `label → answer` once answered.
export type QuestionProps = { id: string?, label: string?, answer: string? }
function M.question(props: QuestionProps): Node
	local value: Node
	if props.answer then
		value = ui.row {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.6",
			items = "center",
			overflow = "hidden",
			txt.text {
				props.label or "",
				literal = true,
				size = "sm",
				color = T.secondary,
				truncate = true,
				line = false,
				max_w = "50%",
				shrink = 0,
			},
			icon { name = "arrow-right", size = 11, color = T.secondary, opacity = 0.7 },
			txt.text {
				props.answer,
				literal = true,
				size = "sm",
				color = T.text,
				opacity = 0.9,
				truncate = true,
				line = false,
				shrink = 1,
				min_w = 0,
			},
		}
	else
		value = txt.text {
			"Awaiting your answer…",
			size = "sm",
			color = T.text,
			opacity = 0.9,
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
		}
	end
	return ui.column {
		id = props.id,
		w_full = true,
		py = "$zeron.space.4",
		ui.row {
			w_full = true,
			h = 34,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			overflow = "hidden",
			rounded = "$zeron.radius.10",
			border = 1,
			border_color = T.ink3,
			bg = T.ink1,
			ui.row {
				w = 20,
				h = 20,
				shrink = 0,
				rounded = "$zeron.radius.6",
				bg = T.ink3,
				items = "center",
				justify = "center",
				icon { name = "chat-round-line", size = 12, color = T.secondary },
			},
			txt.text { "Question", size = "sm", weight = "medium", line = false, shrink = 0 },
			value,
		},
	}
end

-- A visual's status line (visuals.rs status_line): 12 on 18.
local function visual_status(id: string?, text: string | () -> string, color: string): Node
	return txt.text { text, id = id, literal = true, size = "sm", color = color, wrap = true, line_height = 18 }
end

-- An agent's visual (show_visual, visuals.rs VisualFrame): its Luau script
-- run as a sandboxed plugin of the app's (`ui.sandbox`: no grants, the
-- plugins' memory and time limits), what it returns drawn on the chat in
-- the theme's tokens, its controls calling its own handlers. "Loading
-- visual…" in the faint text while the script is read, "Visual
-- unavailable" or "Visual failed: …" in the muted text, and under a visual
-- that broke as it ran (a handler's error) "Visual error: …" in the danger
-- colour, the last of it staying. `status`: "loading", "loaded" or
-- "unavailable".
export type VisualProps = {
	id: string,
	-- Its plugin's name: its state and grants go by it.
	name: string,
	title: string,
	script: string?,
	status: () -> string,
}
M.visual = ui.component(function(props: VisualProps): Node
	local broke = ui.use_state("")
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.8",
		label = props.title,
		ui.presence(props.status, function(now: string): Node
			if now == "loading" then
				return visual_status(`{props.id}_status`, "Loading visual…", T.tertiary)
			elseif now ~= "loaded" or not props.script then
				return visual_status(`{props.id}_status`, "Visual unavailable", T.secondary)
			end
			return ui.sandbox(props.script :: string, {
				name = props.name,
				w_full = true,
				fallback = function(why: string): Node
					return visual_status(`{props.id}_status`, `Visual failed: {why}`, T.secondary)
				end,
				on_error = function(why: string)
					broke:set(why)
				end,
			})
		end, { w_full = true }),
		ui.show(
			function()
				return broke:get() ~= ""
			end,
			visual_status(`{props.id}_error`, function()
				return `Visual error: {broke:get()}`
			end, T.danger)
		),
	}
end)

-- An image the agent made (render_generated_image, reply_images frame):
-- 512 wide at most, 320 high, radius 12 with a hairline at 7% on ink 4.5%,
-- "Loading image…" or "Image unavailable" in its middle; once loaded, sized
-- to the picture (512 by 420 at most, keeping its aspect), and a click
-- opens it.
export type GeneratedProps = {
	id: string?,
	src: string?,
	name: string?,
	w: number?,
	h: number?,
	status: (() -> string)?,
	on_open: Handler?,
}
function M.generated_image(props: GeneratedProps): Node
	local function frame(text: string): Node
		return ui.row {
			id = props.id,
			w = 512,
			max_w = "100%",
			h = 320,
			rounded = "$zeron.radius.card",
			border = 1,
			border_color = T.hairline,
			bg = T.ink1,
			items = "center",
			justify = "center",
			txt.text { text, size = "sm", color = T.secondary, line = false },
		}
	end
	local status = props.status or function(): string
		return if props.src then "loaded" else "failed"
	end
	return ui.presence(status, function(now: string): Node
		if now == "loading" then
			return frame("Loading image…")
		elseif now ~= "loaded" or not props.src then
			return frame("Image unavailable")
		end
		local pw, ph = props.w or 512, props.h or 320
		local scale = math.min(512 / pw, 420 / ph, 1)
		local w, h = pw * scale + 2, ph * scale + 2
		return ui.button {
			id = props.id,
			label = "Preview image",
			w = w,
			max_w = "100%",
			aspect = w / h,
			p = 1,
			rounded = "$zeron.radius.card",
			border = 1,
			border_color = T.hairline,
			bg = T.ink1,
			overflow = "hidden",
			focus = { border = 0 },
			cursor = "pointer",
			on_click = props.on_open,
			ui.image {
				src = props.src :: string,
				label = props.name or "",
				w_full = true,
				h_full = true,
				rounded = "$zeron.radius.11",
				fit = "contain",
			},
		}
	end, { w_full = true, items = "start" })
end

-- A subagent the agent spawned (subagent_chip, chip_header_row): its own
-- 38 row, a card 30 high at radius 9 with a hairline at 7% on ink 3% (5%
-- under the pointer) whose whole face opens the subagent's transcript; in
-- it, 8 in at 12: the 18 tile (radius 5, ink 8%, the bot 12), "Agent"
-- medium, what it was asked in the text at 85%, the model it runs on at 11
-- in the faint colour, the mini spinner while it runs, and the open arrow
-- on its 18 tile (ink 6%). A failed one takes the danger colour.
export type SpawnStatus = "running" | "done" | "failed"
export type SpawnProps = {
	id: string?,
	detail: string,
	model: string?,
	status: (SpawnStatus | () -> SpawnStatus)?,
	on_open: Handler?,
}
function M.spawn(props: SpawnProps): Node
	local given: any = props.status
	local function status(): string
		if type(given) == "function" then
			return (given :: () -> string)()
		end
		return given or "done"
	end
	return ui.row {
		w_full = true,
		h = 38,
		items = "center",
		shrink = 0,
		ui.button {
			id = props.id,
			label = `Open subagent: {props.detail}`,
			h = 30,
			grow = 1,
			min_w = 0,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			overflow = "hidden",
			rounded = "$zeron.radius.9",
			border = 1,
			border_color = T.hairline,
			bg = T.ink1,
			hover = { bg = T.ink2 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = props.on_open,
			ui.row {
				w = 18,
				h = 18,
				shrink = 0,
				rounded = "$zeron.radius.5",
				bg = T.ink3,
				items = "center",
				justify = "center",
				icon { name = "bot", size = 12, color = T.secondary },
			},
			txt.text {
				"Agent",
				size = "sm",
				weight = "medium",
				color = function(): Color
					return if status() == "failed" then T.danger else T.secondary
				end,
				line = false,
				shrink = 0,
			},
			txt.text {
				props.detail,
				literal = true,
				size = "sm",
				color = function(): Color
					return if status() == "failed" then T.danger else T.activity_badge
				end,
				truncate = true,
				line = false,
				grow = 1,
				shrink = 1,
				min_w = 0,
			},
			props.model and txt.text {
				props.model,
				literal = true,
				size = "xs",
				color = T.tertiary,
				line = false,
				shrink = 0,
			} or nil,
			ui.show(function()
				return status() == "running"
			end, loaders.mini_spinner { id = props.id and `{props.id}_spinner`, cell = 2 }),
			ui.row {
				w = 18,
				h = 18,
				shrink = 0,
				rounded = "$zeron.radius.5",
				bg = T.ink2,
				items = "center",
				justify = "center",
				icon { name = "arrow-up-right", size = 11, color = T.secondary, opacity = 0.8 },
			},
		},
	}
end

-- The strip under a message (render_row's metadata): a 32 lane, 8 above a
-- 24 row, always there so nothing moves when it shows; under the pointer
-- anywhere on the message (its `hover_group`), its time at 12 in the muted
-- colour at 55% and a 24 copy button (radius 6, ink 8% under the pointer,
-- its 14 glyph muted) that copies the message and shows a check for 1.2 s.
-- A user's sits under the bubble's end, a reply's at its start.
export type MetaProps = {
	id: string?,
	time: string?,
	-- What the copy button copies (the message's text); none, no button.
	copy: (string | () -> string)?,
	align: ("start" | "end")?,
}
M.META = 32
M.COPIED = 1200
M.meta = ui.component(function(props: MetaProps): Node
	local copied = ui.use_state(false)
	local copy = props.copy
	local function text(): string
		return if type(copy) == "function" then copy() else copy or ""
	end
	return ui.row {
		id = props.id,
		w_full = true,
		h = M.META,
		pt = "$zeron.space.8",
		shrink = 0,
		items = "center",
		justify = if props.align == "end" then "end" else "start",
		ui.row {
			id = props.id and `{props.id}_strip`,
			gap = "$zeron.space.8",
			items = "center",
			opacity = 0,
			group_hover = { opacity = 1 },
			props.time and txt.text { props.time, literal = true, size = "sm", color = T.meta, line = false },
			copy and ui.button {
				id = props.id and `{props.id}_copy`,
				label = "Copy message",
				tooltip = "Copy message",
				w = 24,
				h = 24,
				p = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.6",
				bg = T.clear,
				hover = { bg = T.ink3 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					ui.clipboard.write(text())
					copied:set(true)
					ui.after(M.COPIED, function()
						copied:set(false)
					end)
				end,
				icon {
					name = "copy",
					size = 14,
					color = T.secondary,
					hidden = function()
						return copied:get()
					end,
				},
				icon {
					name = "check",
					size = 14,
					color = T.secondary,
					hidden = function()
						return not copied:get()
					end,
				},
			} or nil,
		},
	}
end)

-- A preview's Markdown as one run of prose (rail.rs preview_runs): its
-- paragraphs, headings and list items, markers dropped and blocks joined
-- by spaces; fences, quotes and tables left out, unless the message has
-- nothing else (then its first fence's opening line).
function M.preview(source: string): string
	local prose: { string } = {}
	local fence: string? = nil
	local first_code: string? = nil
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		if string.match(line, "^%s*```") then
			fence = if fence then nil else "open"
		elseif fence then
			if not first_code and string.match(line, "%S") then
				first_code = line
			end
		elseif not (string.match(line, "^%s*>") or string.match(line, "^%s*|")) then
			local text = string.gsub(line, "^%s*#+%s*", "")
			text = string.gsub(text, "^%s*[-*+]%s+%[[ xX]%]%s+", "")
			text = string.gsub(text, "^%s*[-*+]%s+", "")
			text = string.gsub(text, "^%s*%d+[.)]%s+", "")
			text = string.gsub(text, "!?%[([^%]]*)%]%([^)]*%)", "%1")
			text = string.gsub(text, "[*_`~]", "")
			text = string.match(text, "^%s*(.-)%s*$") or text
			if text ~= "" then
				table.insert(prose, text)
			end
		end
	end
	if #prose == 0 then
		return first_code or ""
	end
	return table.concat(prose, " ")
end

-- The message rail (rail.rs): a tick per prompt down the transcript's left,
-- 16 in, in the middle of its height, 8 apart in 32-wide rows. A tick is
-- 2 high at radius 1, 8 wide in ink 16%, the text at 80% while its prompt
-- shows (`lit`); under the pointer 24 wide and lit, its card beside it
-- (280 wide on the frost, 8 in: who sent it, the prompt at 12 for three
-- lines, the reply's opening at 11 in the muted colour for four), and a
-- click takes the transcript there (`on_pick`). A long conversation's
-- ticks scroll in a window 70% of its height, their ends fading over 24.
export type RailTick = { id: string, prompt: string, reply: string?, from: Sender? }
export type RailProps = {
	id: string?,
	ticks: { RailTick } | State<{ RailTick }>,
	lit: (id: string) -> boolean,
	on_pick: (id: string) -> (),
}
M.RAIL_W = 32
M.TICK = 8
local function rail_card(t: RailTick): Node
	local reply = if t.reply then M.preview(t.reply) else ""
	return ui.column {
		w = 280,
		p = "$zeron.space.8",
		gap = "$zeron.space.6",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		t.from and ui.row {
			min_w = 0,
			gap = "$zeron.space.5",
			items = "center",
			txt.text { "Message from", size = "xs", color = T.secondary, line = false, shrink = 0 },
			t.from.icon and icon { name = t.from.icon :: any, size = 14, color = t.from.tint or T.secondary } or nil,
			txt.text {
				t.from.title,
				literal = true,
				size = "xs",
				weight = "medium",
				color = T.secondary,
				truncate = true,
				line = false,
				min_w = 0,
				shrink = 1,
			},
		} or nil,
		txt.text { M.preview(t.prompt), literal = true, size = "sm", color = T.text, wrap = true, lines = 3 },
		reply ~= "" and txt.text {
			reply,
			literal = true,
			size = "xs",
			color = T.secondary,
			wrap = true,
			lines = 4,
		} or nil,
	}
end
M.rail = ui.component(function(props: RailProps): Node
	local given: any = props.ticks
	local list: State<{ RailTick }> = if type(given) == "table"
		then ui.computed(function(): { RailTick }
			return given
		end)
		else given
	local function tick(t: RailTick): Node
		return ui.button {
			id = props.id and `{props.id}_{t.id}`,
			label = `Go to: {M.preview(t.prompt)}`,
			w = M.RAIL_W,
			h = M.TICK,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "start",
			bg = T.clear,
			hover = { bg = T.clear },
			focus = { border = 0 },
			cursor = "pointer",
			hover_group = true,
			on_click = function()
				props.on_pick(t.id)
			end,
			tooltip = function(): Node
				return rail_card(t)
			end,
			tooltip_delay = 0,
			tooltip_placement = { side = "right", align = "center", offset = 4 },
			ui.div {
				id = props.id and `{props.id}_{t.id}_bar`,
				h = 2,
				rounded = "$zeron.radius.1",
				variants = recipes.turn_tick {
					active = function()
						return props.lit(t.id)
					end,
				},
				group_hover = { w = 24, bg = T.text, opacity = 0.8 },
			},
		}
	end
	return ui.show(
		function()
			return #list:get() >= 2
		end,
		kit_scroll {
			id = props.id,
			label = "Prompts",
			w = M.RAIL_W,
			max_h = "70%",
			fade = 24,
			ui.column {
				w_full = true,
				py = "$zeron.space.1",
				ui.each(list, tick, {
					key = function(t: RailTick)
						return t.id
					end,
					direction = "column",
				}),
			},
		}
	)
end)

-- An assistant turn: the content 12 apart (Zeron's tool group and block
-- gaps), then right under it its strip (`meta`, shown while the pointer is
-- on the turn) and the working trailer while it works; `who` names it over
-- the content (Zeron's transcript names no one: the app leaves it out).
export type TurnProps = {
	id: string?,
	who: string?,
	[number]: Child,
	time: string?,
	meta: Child?,
	working: Child?,
}
M.turn = ui.component(function(props: TurnProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		hover_group = true,
		ui.column {
			w_full = true,
			gap = "$zeron.space.12",
			props.who and ui.row {
				gap = "$zeron.space.8",
				items = "center",
				txt.text { props.who, size = "xs", color = T.tertiary },
				props.time and txt.text { props.time, size = "xs", color = T.tertiary, opacity = 0.7 },
			},
			{ table.unpack(props) },
		},
		props.meta,
		props.working,
	}
end)

return M
