-- Transcript: a conversation as Zeron lays it out, and each of its pieces
-- on its own.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local tr = require("@kit/transcript")
local activity = require("@kit/activity")
local own_turn = require("@kit/own_turn")

-- The sent-turn hold: a prompt is sent into a short frame; its runway and
-- the reply that streams into it.
local hold_offset = ui.state("hold_offset", 0)
local hold = own_turn.new { offset = hold_offset, inset = own_turn.INSET, pb = 20, gap = 24 }
local sent = ui.state("hold_sent", 0)
local streamed = ui.state("hold_streamed", 0)
local run = 0
local PROMPTS =
	{ "Shorter, and lead with the glass.", "Now a version for the changelog.", "And one line for the release tweet." }
local REPLY = {
	"Zeron's windows are glass: one tint over the desktop's blur, and the chat sits straight on it.",
	"Every list fades at its edges instead of ending at a line, and the composer floats as a pill under the thread.",
	"The release moves the transcript, the composer and the settings onto the new engine without changing how they read.",
	"Tool calls fold into a tree that draws itself as the turn runs; the history table draws its lanes on one canvas.",
	"Themes come from the same seeds as before, with an accent and a material (glass or opaque) chosen on top.",
	"Nothing bounces at the end of a scroll; a sent prompt glides to the top and the reply fills the room beneath it.",
}
local function send_prompt()
	if sent:peek() >= #PROMPTS then
		return
	end
	run += 1
	local this = run
	hold.send()
	streamed:set(0)
	sent:set(sent:peek() + 1)
	for i = 1, #REPLY do
		ui.after(600 + (i - 1) * 420, function()
			if run == this then
				streamed:set(i)
			end
		end)
	end
end
local function reset_prompts()
	run += 1
	hold.release()
	streamed:set(0)
	sent:set(0)
	hold_offset:set(0)
end

-- Turns space themselves (24 above each) instead of a column gap: a hidden
-- slot must take no room, and the engine keeps a gap around hidden children.
local function spaced(node: Node): Node
	return ui.column { w_full = true, pt = "$zeron.space.24", node }
end

local function hold_demo(): Node
	local turns: { Node } = {
		tr.user_bubble { id = "hold_first", text = "Can you draft the release notes for 0.2.109?" },
		spaced(tr.turn {
			tr.prose {
				tr.paragraph("Here is a first pass at the notes, grouped by area, with the breaking change first."),
				tr.paragraph(
					"The composer's docks now share one radius token with the bubbles, so they meet concentrically."
				),
			},
			meta = tr.meta {
				copy = "Here is a first pass at the notes, grouped by area, with the breaking change first.",
			},
		}),
	}
	for i, prompt in PROMPTS do
		local paragraphs: { Child } = {}
		for k, text in REPLY do
			table.insert(
				paragraphs,
				ui.show(
					function()
						return sent:get() > i or streamed:get() >= k
					end,
					ui.column {
						id = `hold_reply_{i}_{k}`,
						w_full = true,
						pt = if k == 1 then 0 else "$zeron.space.12",
						tr.paragraph(text),
					}
				)
			)
		end
		table.insert(
			turns,
			ui.show(
				function()
					return sent:get() >= i
				end,
				ui.column {
					w_full = true,
					pt = "$zeron.space.24",
					gap = "$zeron.space.24",
					tr.user_bubble { id = `hold_turn_{i}`, text = prompt },
					tr.turn {
						ui.column { w_full = true, { table.unpack(paragraphs) } },
						working = ui.show(function()
							return sent:get() == i and streamed:get() < #REPLY
						end, tr.working { label = "Writing" }),
					},
				}
			)
		)
	end
	return ui.column {
		w_full = true,
		gap = "$zeron.space.12",
		items = "start",
		ui.column {
			w = 560,
			h = 380,
			rounded = T.radius_card,
			bg = T.glass,
			border = 1,
			border_color = T.hairline,
			overflow = "hidden",
			items = "stretch",
			kit.scroll {
				id = "hold_scroll",
				grow = 1,
				w_full = true,
				offset = hold_offset,
				runway = hold.runway,
				on_measure = hold.measure,
				follow = hold.follow(),
				fade = 24,
				px = "$zeron.space.16",
				py = "$zeron.space.20",
				turns,
			},
		},
		ui.row {
			gap = "$zeron.space.8",
			items = "center",
			kit.button {
				id = "hold_send",
				label = "Send",
				size = "sm",
				icon = { name = "arrow-up" },
				on_click = send_prompt,
			},
			kit.button { id = "hold_reset", label = "Reset", size = "sm", variant = "ghost", on_click = reset_prompts },
			kit.text.text {
				function()
					return `held: {if hold.held:get() then "yes" else "no"} · runway: {math.floor(hold.runway:get())} · offset: {math.floor(
						hold_offset:get()
					)}`
				end,
				id = "hold_state",
				size = "xs",
				mono = true,
				color = T.tertiary,
			},
		},
	}
end

local active_tick = ui.state("tick", "p2")
-- The rail's specimen: five prompts, the second lit; a click lights another.
local RAIL_TICKS: { tr.RailTick } = {
	{
		id = "p1",
		prompt = "Can you draft the release notes for 0.2.109?",
		reply = "Here is a first pass at the notes, grouped by area.",
	},
	{
		id = "p2",
		prompt = "Shorter, and lead with the glass.",
		reply = "One tint over the desktop's blur, the chat straight on it.",
	},
	{ id = "p3", prompt = "Add the **panes** after it.", reply = "Done: the panes follow the glass." },
	{ id = "p4", prompt = "Check the links." },
	{ id = "p5", prompt = "Ship it." },
}
local group_open = ui.state("group_open", true)
local live_open = ui.state("live_open", true)
local replay = ui.state("replay", 0)

local ACTIVITIES: { activity.Activity } = {
	{ id = "a1", icon = "terminal", label = "Run", detail = "cargo test -p zgx-script --test styleguide" },
	{ id = "a2", icon = "document", label = "Read", detail = "kit/scroll.luau", file = true },
	{ id = "a3", icon = "document", label = "Read", detail = "shell/canvas.luau", file = true },
	{ id = "a4", icon = "pen", label = "Edit", detail = "kit/scroll.luau", file = true },
	{ id = "a5", icon = "terminal", label = "Run", detail = "cargo test -p zgx-script", failed = true },
}

-- A live group: the calls arrive one by one, each running a moment (a
-- spinner at its tip) before its icon pops in; the summary rolls.
local live_calls = ui.state("live_calls", {} :: { activity.Activity })
local stream_open = ui.state("stream_open", true)
local live_run = 0
local function run_live()
	live_run += 1
	local this = live_run
	live_calls:set {}
	stream_open:set(true)
	for k, a in ACTIVITIES do
		ui.after(150 + (k - 1) * 700, function()
			if live_run == this then
				local call = table.clone(a)
				call.id = `s{k}`
				call.failed = nil
				call.status = "running"
				live_calls:push(call)
			end
		end)
		ui.after(150 + (k - 1) * 700 + 500, function()
			if live_run == this then
				live_calls:set_key({ k, "status" }, if a.failed then "failed" else "done")
			end
		end)
	end
end
local live_summary = ui.computed(function(): string
	return activity.summary(live_calls:get())
end)

local function conversation(): Node
	return specimen.frame {
		w = 800,
		p = 0,
		bg = T.glass,
		ui.row {
			w_full = true,
			items = "start",
			ui.column {
				pl = "$zeron.space.16",
				pt = "$zeron.space.28",
				tr.rail {
					id = "rail",
					ticks = RAIL_TICKS,
					lit = function(id: string): boolean
						return active_tick:get() == id
					end,
					on_pick = function(id: string)
						active_tick:set(id)
					end,
				},
			},
			ui.column {
				grow = 1,
				shrink = 1,
				min_w = 0,
				max_w = tr.WIDTH,
				px = "$zeron.space.16",
				py = "$zeron.space.20",
				gap = "$zeron.space.24",
				tr.user_bubble { text = "Can you draft the release notes for 0.2.109?" },
				tr.turn {
					time = "10:08",
					activity.group {
						id = "turn_group",
						summary = "Ran 2 commands · edited 1 file · read 2 files · 1 failed",
						items = ACTIVITIES,
						open = group_open,
					},
					tr.prose {
						tr.paragraph(
							"Here is a first pass at the notes, grouped by area, with the breaking change first."
						),
						tr.heading(2, "Breaking"),
						ui.rich {
							wrap = true,
							text_size = "$font.size.lg",
							line_height = "$font.line.lg",
							color = T.text,
							"The ",
							tr.code("ui.theme.tokens"),
							" call now takes nested groups; dotted names still work, so most scripts need no change.",
						},
						tr.code_block {
							language = "luau",
							lines = {
								'ui.theme.tokens { zeron = { card = "{surface.sunken}" } }',
								'ui.theme.default(ui.theme.load("zeron-dark.json"))',
							},
						},
						tr.quote(
							"The composer's docks now share one radius token with the bubbles, so they meet concentrically."
						),
					},
					meta = tr.meta {
						time = "Oct 24, 10:08 AM",
						copy = "Here is a first pass at the notes, grouped by area, with the breaking change first.",
					},
				},
				tr.user_bubble { text = "Shorter, and lead with the glass." },
				tr.turn {
					tr.tool { icon = "pen", title = "Writing", detail = "release-notes.md", state = "running" },
					working = tr.working { label = "Rewriting the opening" },
				},
			},
		},
	}
end

return function(): Node
	local p = state.page_by("transcript")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "A conversation",
			note = "bubble on wash 8% at radius 16 · prose 14/22, blocks 12 apart · rail at left 16",
			conversation(),
		},
		specimen.section {
			title = "Tool calls",
			note = "header 26 with the chevron centred on the trunk · rows 32 off a 1-point trunk at 12.5, the branch bending at 6 to x 28 · icon 16 at 32 · 12 muted, failed in danger · rows reveal 360 ms outExpo, 65 apart, the connector drawn by length over 480 ms quint (the trunk, the bend, the branch, then the icon and the label rising 4) · a running call's spinner pops into its icon · the summary rolls · fold 140 ms on height and opacity",
			ui.row {
				gap = "$zeron.space.32",
				items = "start",
				flex_wrap = true,
				specimen.cell {
					label = "arriving (click Replay)",
					ui.column {
						gap = "$zeron.space.12",
						items = "start",
						ui.presence(function()
							return `live{replay:get()}`
						end, function(): Node
							return activity.group {
								id = "live_group",
								summary = "Ran 2 commands · Read 2 files · Edited 1 file · 1 failed",
								items = ACTIVITIES,
								open = live_open,
								animate = true,
								w = 420,
							}
						end),
						kit.button {
							id = "replay",
							label = "Replay",
							size = "sm",
							variant = "secondary",
							icon = { name = "restart" },
							on_click = ui.add(replay),
						},
					},
				},
				specimen.cell {
					label = "streaming (click Run)",
					ui.column {
						gap = "$zeron.space.12",
						items = "start",
						w = 420,
						ui.show(
							function()
								return #live_calls:get() > 0
							end,
							activity.group {
								id = "stream_group",
								summary = live_summary,
								items = live_calls,
								open = stream_open,
								animate = true,
								w = 420,
							}
						),
						kit.button {
							id = "run_live",
							label = "Run",
							size = "sm",
							variant = "secondary",
							icon = { name = "action-play" },
							on_click = run_live,
						},
					},
				},
				specimen.cell {
					label = "settled · folds on the header",
					activity.group {
						id = "settled_group",
						summary = "Read 3 files",
						items = { ACTIVITIES[2], ACTIVITIES[3], ACTIVITIES[4] },
						open = group_open,
						w = 420,
					},
				},
			},
		},
		specimen.section {
			title = "Sent-turn hold (overscroll)",
			note = "send: a runway is reserved under the prompt so the view scrolls past its content and the prompt glides to 10 under the top over ~230 ms · the reply streams into the room below and uses the runway up · then the bottom pin takes over · nothing bounces (Zeron tried 24 of scroll room and removed it)",
			hold_demo(),
		},
		specimen.section {
			title = "Pieces",
			ui.row {
				gap = "$zeron.space.32",
				items = "start",
				flex_wrap = true,
				specimen.cell {
					label = "tool call · running / done / failed",
					ui.column {
						gap = "$zeron.space.8",
						tr.tool { title = "Bash", detail = "cargo test", state = "running" },
						tr.tool { icon = "terminal", title = "Bash", detail = "cargo test -p zgx-script" },
						tr.tool { title = "Bash", detail = "exit 101", state = "failed" },
					},
				},
				specimen.cell { label = "working trailer", tr.working {} },
				specimen.cell {
					label = "headings",
					ui.column {
						w = 300,
						tr.heading(1, "Heading one 19/27"),
						tr.heading(2, "Heading two 16/24"),
						tr.heading(3, "Heading three 15/22"),
					},
				},
			},
		},
	}
end
