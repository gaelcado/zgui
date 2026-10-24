-- A well of content: its header (what it shows, split and close) and its
-- body, by kind: a chat with its composer, a document, a terminal, a page.
local kit = require("./kit")
local sidebar = require("./sidebar")
local state = require("../state")
local sample = require("@lib/sample")

local M = {}

local MEASURE = 680

local function header(slot: number, id: string): Node
	local it = sample.items[id]
	local first = slot == 1
	return ui.row {
		h = 40,
		w_full = true,
		shrink = 0,
		pr = "$space.2",
		-- With the sidebar shut, the first well's header makes room for the
		-- traffic lights and takes the sidebar's toggle.
		pl = if first
			then ui.tween(state.sidebar, { from = sidebar.LIGHTS - 6, to = 14, duration = 220, ease = "outQuart" })
			else "$shell.md",
		gap = "$space.2",
		items = "center",
		window_drag = true,
		first and ui.show(function()
			return not state.sidebar:get()
		end, sidebar.toggle("well_sidebar_toggle")),
		ui.div { variants = kit.tile { tone = "clear" }, kit.icon(sample.icons[it.kind], 15) },
		ui.text {
			it.title,
			min_w = 0,
			shrink = 1,
			truncate = true,
			text_size = "$font.size.sm",
			weight = "$font.weight.medium",
		},
		ui.text { it.meta, shrink = 0, text_size = "$font.size.xs", color = "$text.tertiary" },
		ui.div { grow = 1 },
		first and ui.button {
			id = "split",
			variants = kit.icon_button {
				size = "sm",
				on = function()
					return state.right:get() ~= nil
				end,
			},
			tooltip = "Split (⌘D)",
			on_click = state.split,
			kit.icon("split-columns", 15),
		},
		(not first) and ui.button {
			id = "close_split",
			variants = kit.icon_button { size = "sm" },
			tooltip = "Close (⌘W)",
			on_click = state.split,
			kit.icon("close", 14),
		},
		ui.button { variants = kit.icon_button { size = "sm" }, tooltip = "More", kit.icon("more-horizontal", 15) },
	}
end

local function bubble(m: sample.Message): Node
	if m.from == "me" then
		return ui.row {
			w_full = true,
			justify = "end",
			ui.div {
				max_w = 460,
				px = "$shell.md",
				py = "$space.2",
				rounded = "$shell.bubble_radius",
				bg = "$shell.bubble",
				ui.text { m.text, text_size = "$font.size.md", wrap = true, line_height = 20 },
			},
		}
	end
	return ui.text {
		m.text,
		w_full = true,
		text_size = "$font.size.md",
		wrap = true,
		line_height = 21,
		color = "$text.primary",
	}
end

local function composer(id: string): Node
	local draft = state.draft(id)
	return ui.column {
		w_full = true,
		max_w = MEASURE,
		px = "$space.5",
		pb = "$space.4",
		mx = "auto",
		ui.column {
			variants = kit.field { kind = "composer" },
			ui.textarea {
				id = `composer_{id}`,
				value = draft,
				multiline = true,
				w_full = true,
				-- No auto-grow in zgui's textarea: the height follows the
				-- draft's lines, one to seven.
				h = function()
					local v = draft:get()
					local _, newlines = string.gsub(v, "\n", "")
					return math.clamp((newlines + 1 + math.floor(#v / 80)) * 22, 22, 154)
				end,
				wrap = true,
				line_height = 22,
				p = 0,
				border = 0,
				rounded = 0,
				placeholder = "Ask anything",
				placeholder_color = "$text.tertiary",
				text_size = "$font.size.md",
				bg = "#00000000",
				on_key = function(e: KeyEvent): boolean?
					if e.key == "Enter" and not e.shift then
						state.send(id)
						return true
					end
					return nil
				end,
			},
			ui.row {
				w_full = true,
				gap = "$space.1",
				items = "center",
				ui.button {
					variants = kit.icon_button { size = "sm" },
					tooltip = "Attach",
					kit.icon("paperclip", 15),
				},
				ui.button {
					variants = kit.icon_button { size = "sm" },
					tooltip = "Dictate",
					kit.icon("microphone", 15),
				},
				ui.div { grow = 1 },
				ui.text { "Opus 5.5", text_size = "$font.size.xs", color = "$text.tertiary", pr = "$shell.xs" },
				ui.button {
					id = `send_{id}`,
					w = 26,
					h = 26,
					rounded = "$radius.full",
					items = "center",
					justify = "center",
					bg = "$shell.send",
					cursor = "pointer",
					focus = { border = 0 },
					opacity = function()
						return if draft:get():match("^%s*$") then 0.35 else 1
					end,
					on_click = function()
						state.send(id)
					end,
					kit.icon("arrow-up", 15, "$shell.on_send"),
				},
			},
		},
	}
end

local function chat(it: sample.Item): Node
	local rows: { Node } = {}
	for _, m in it.messages or {} do
		table.insert(rows, bubble(m))
	end
	local sent = ui.computed(function()
		return state.sent:get()[it.id] or {}
	end)
	return ui.column {
		grow = 1,
		w_full = true,
		min_h = 0,
		ui.scroll {
			grow = 1,
			w_full = true,
			follow = true,
			fade = { 12, 12 },
			fade_overflow = true,
			ui.column {
				w_full = true,
				max_w = MEASURE,
				mx = "auto",
				px = "$shell.page",
				py = "$shell.lg",
				gap = "$shell.lg",
				rows,
				ui.each(sent :: any, function(m: sample.Message): Node
					return bubble(m)
				end),
			},
		},
		composer(it.id),
	}
end

local function doc(it: sample.Item): Node
	local paragraphs: { Node } = {}
	for _, p in it.paragraphs or {} do
		table.insert(
			paragraphs,
			ui.text { p, w_full = true, text_size = "$font.size.md", wrap = true, line_height = 22 }
		)
	end
	return ui.scroll {
		grow = 1,
		w_full = true,
		fade = { 12, 12 },
		fade_overflow = true,
		ui.column {
			w_full = true,
			max_w = 640,
			mx = "auto",
			px = "$space.6",
			pt = "$space.5",
			pb = "$space.7",
			gap = "$shell.md",
			ui.text { it.title, text_size = "$font.size.xl", weight = "$font.weight.semibold", pb = "$space.1" },
			paragraphs,
		},
	}
end

local function terminal(it: sample.Item): Node
	local lines: { Node } = {}
	for _, line in it.lines or {} do
		table.insert(
			lines,
			ui.text {
				line,
				font = "$font.mono",
				text_size = "$font.size.sm",
				line_height = 19,
				color = if line:sub(1, 1) == "$" then "$text.primary" else "$text.secondary",
			}
		)
	end
	return ui.scroll {
		grow = 1,
		w_full = true,
		ui.column {
			w_full = true,
			px = "$space.4",
			py = "$space.3",
			lines,
			ui.row {
				gap = "$shell.xs",
				pt = "$space.1",
				items = "center",
				ui.text { "❯", font = "$font.mono", text_size = "$font.size.sm", color = "$accent" },
				ui.div { w = 7, h = 15, bg = "$accent", opacity = ui.loop { duration = 600, from = 1, to = 0.15 } },
			},
		},
	}
end

local function web(it: sample.Item): Node
	local paragraphs: { Node } = {}
	for _, p in it.paragraphs or {} do
		table.insert(
			paragraphs,
			ui.text { p, w_full = true, text_size = "$font.size.lg", wrap = true, line_height = 24 }
		)
	end
	return ui.column {
		grow = 1,
		w_full = true,
		items = "center",
		justify = "center",
		gap = "$space.4",
		px = "$space.7",
		ui.div {
			w = 52,
			h = 52,
			rounded = "$radius.xl",
			bg = "$shell.tile",
			items = "center",
			justify = "center",
			kit.icon("globe", 26, "$text.primary"),
		},
		ui.text { it.title, text_size = "$font.size.xxl", weight = "$font.weight.semibold" },
		ui.column { max_w = 460, gap = "$shell.sm", items = "center", paragraphs },
		ui.text { it.url or "", text_size = "$font.size.xs", color = "$text.tertiary" },
	}
end

local BODY = { chat = chat, doc = doc, terminal = terminal, web = web }

-- The well for card `slot` (1 or 2), showing the item `shown` names.
function M.view(slot: number, shown: State<any>): Node
	return ui.column {
		id = `well_{slot}`,
		variants = kit.well {
			focused = function()
				return state.right:get() == nil or state.focus:get() == slot
			end,
		},
		on_press = function()
			state.focus:set(slot)
		end,
		ui.presence(function()
			return shown:get()
		end, function(id: string): Node
			local it = sample.items[id]
			return ui.column {
				w_full = true,
				h_full = true,
				header(slot, id),
				BODY[it.kind](it),
			}
		end),
	}
end

return M
