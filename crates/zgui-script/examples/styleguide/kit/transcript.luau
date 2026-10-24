-- The transcript's pieces, as Zeron's `transcript.rs` and `markdown/render.rs`
-- draw them: the user's bubble, prose at 14/22, headings, a code block with
-- its header and copy button, inline code on the accent wash, a blockquote
-- rail, a tool call chip, and the message rail's ticks.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local icon_button = require("./icon_button")
local loaders = require("./loaders")
local motion = require("./motion")

local M = {}

-- The column prose sits in: 768 with 16 each side.
M.WIDTH = 736

-- The user's turn: a bubble on wash 8%, radius 16, padding 16×10, at most
-- 80% of the column, on the right.
export type BubbleProps = { id: string?, text: Text, time: string? }
M.user_bubble = ui.component(function(props: BubbleProps): Node
	return ui.row {
		id = props.id,
		w_full = true,
		justify = "end",
		ui.column {
			max_w = "80%",
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			rounded = T.radius_xl,
			bg = T.ink3,
			txt.text { props.text, size = "lg", wrap = true, literal = true },
		},
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

-- A code block: radius 10 on ink 3.5% with a hairline; a 28-high header
-- with the language at 11 and a copy button; code 12.5/18, padding 12×10.
export type CodeProps = { id: string?, language: string?, lines: { string }, on_copy: Handler? }
M.code_block = ui.component(function(props: CodeProps): Node
	local lines: { Node } = {}
	for _, line in props.lines do
		table.insert(lines, txt.text { line, size = "sm", mono = true, color = T.text })
	end
	return ui.column {
		id = props.id,
		w_full = true,
		rounded = T.radius_lg,
		bg = T.ink1,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		ui.row {
			h = 28,
			pl = "$zeron.space.12",
			pr = "$zeron.space.6",
			items = "center",
			bg = T.ink1,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			txt.text { props.language or "text", size = "xs", color = T.tertiary, grow = 1, line = false },
			ui.button {
				h = 22,
				px = "$zeron.space.6",
				gap = "$zeron.space.5",
				items = "center",
				rounded = "$zeron.radius.5",
				bg = T.clear,
				hover = { bg = T.ink3 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = props.on_copy,
				icon { name = "copy", size = 12, color = T.secondary },
				txt.text { "Copy", size = "micro", color = T.secondary, line = false },
			},
		},
		ui.column { px = "$zeron.space.12", py = "$zeron.space.10", gap = 0, lines },
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

-- The working trailer under an assistant turn: the gradient spinner and a
-- word.
export type WorkingProps = { id: string?, label: Text? }
M.working = ui.component(function(props: WorkingProps): Node
	return ui.row {
		id = props.id,
		h = 22,
		gap = "$zeron.space.10",
		items = "center",
		loaders.gradient_spinner {},
		txt.text { props.label or "Working", size = "sm", color = T.secondary, line = false },
	}
end)

-- The message rail: a tick per turn, 2 high at radius 1, 12 wide (20 under
-- the pointer), ink 16% or the text at 80% when active.
export type RailProps = { id: string?, count: number, active: State<number> }
M.rail = ui.component(function(props: RailProps): Node
	local ticks: { Node } = {}
	for i = 1, math.min(props.count, 12) do
		table.insert(
			ticks,
			ui.button {
				id = props.id and `{props.id}_{i}`,
				h = 10,
				w = 26,
				p = 0,
				items = "center",
				justify = "start",
				bg = T.clear,
				hover = { bg = T.clear },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = ui.set(props.active, i),
				ui.div {
					h = 2,
					rounded = "$zeron.radius.1",
					variants = recipes.turn_tick {
						active = function()
							return props.active:get() == i
						end,
					},
				},
			}
		)
	end
	return ui.column { id = props.id, w = 26, gap = "$zeron.space.3", ticks }
end)

-- An assistant turn: the content and the actions under it, 12 apart
-- (Zeron's markdown block gap); `who` names it over the content (Zeron's
-- transcript names no one: the app leaves it out).
export type TurnProps = { id: string?, who: string?, [number]: Child, time: string? }
M.turn = ui.component(function(props: TurnProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.12",
		props.who and ui.row {
			gap = "$zeron.space.8",
			items = "center",
			txt.text { props.who, size = "xs", color = T.tertiary },
			props.time and txt.text { props.time, size = "xs", color = T.tertiary, opacity = 0.7 },
		},
		{ table.unpack(props) },
	}
end)

-- The hover actions under a turn: copy, retry, more; 24-point ghosts.
function M.actions(): Node
	return ui.row {
		gap = "$zeron.space.2",
		items = "center",
		icon_button { icon = "copy", size = 24, icon_size = 13, label = "Copy", no_ring = true },
		icon_button { icon = "restart", size = 24, icon_size = 13, label = "Retry", no_ring = true },
		icon_button { icon = "more-horizontal", size = 24, icon_size = 13, label = "More", no_ring = true },
	}
end

return M
