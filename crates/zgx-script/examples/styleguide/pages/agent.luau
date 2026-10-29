-- Agent surfaces: what gathers around the composer while an agent works.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local tray = require("@kit/tray")
local dictation = require("@kit/dictation")
local message_badge = require("@kit/message_badge")

local dict = ui.state("dict_state", "idle" :: dictation.Phase)
local dict_live = ui.state("dict_live", "listening" :: dictation.Phase)
local dict_busy = ui.state("dict_busy", "processing" :: dictation.Phase)
local usage = ui.state("usage", 0.42 :: number?)
local usage_warn = ui.state("usage_warn", 0.81 :: number?)
local usage_hot = ui.state("usage_hot", 0.94 :: number?)
local usage_none = ui.state("usage_none", nil :: number?)
local todo_open = ui.state("todo_open", true)
local todo_closed = ui.state("todo_closed", false)
local roll_value = ui.state("roll_value", "Working · 12 files")
local roll_count = ui.state("roll_count", "1,284")
local ROLLS = { "Working · 12 files", "Working · 13 files", "Done · 13 files", "Working · 12 files" }
local roll_i = 1

local queued = ui.state(
	"queued",
	{
		{ id = "q1", text = "Then run the tests and fix what fails" },
		{ id = "q2", text = "Add the release notes to CHANGELOG.md", attachments = 2 },
		{ id = "q3", text = "Open a PR against main" },
	} :: { tray.Queued }
)

-- A well the trays rise in: the tray's bottom tucks under its edge.
local function well(w: number, child: Node): Node
	return ui.column {
		w = w,
		pt = "$zeron.space.16",
		px = "$zeron.space.16",
		items = "center",
		rounded = T.radius_card,
		bg = T.glass,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		child,
	}
end

local function cycle()
	local s = dict:peek()
	dict:set(
		if s == "idle"
			then "requesting"
			elseif s == "requesting" then "listening"
			elseif s == "listening" then "processing"
			else "idle"
	)
end

local function dictation_cells(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "click to step idle → requesting → listening → processing",
			kit.dictation.row { id = "dict", state = dict, clock = "0:07", on_click = cycle },
		},
		specimen.cell { label = "listening", kit.dictation.row { state = dict_live, clock = "0:07" } },
		specimen.cell { label = "processing", kit.dictation.row { state = dict_busy, clock = "0:52" } },
		specimen.cell {
			label = "status line · no speech / failed",
			ui.column {
				w = 360,
				gap = "$zeron.space.4",
				kit.dictation.status { title = "No speech detected", detail = "Try again closer to the mic" },
				kit.dictation.status {
					title = "Dictation failed",
					detail = "Microphone access was denied",
					failed = true,
				},
			},
		},
	}
end

local function usage_chips(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell { label = "42%", kit.context_usage.chip { id = "usage", used = usage } },
		specimen.cell { label = "81% · warning", kit.context_usage.chip { used = usage_warn } },
		specimen.cell { label = "94% · danger", kit.context_usage.chip { used = usage_hot } },
		specimen.cell { label = "unknown", kit.context_usage.chip { used = usage_none } },
	}
end

local function usage_cells(): Node
	return ui.column {
		gap = "$zeron.space.24",
		items = "start",
		usage_chips(),
		specimen.cell { label = "card", kit.context_usage.card { used = 0.42, total = 200000 } },
	}
end

local TODOS: { tray.Todo } = {
	{ id = "t1", text = "Read the failing test", state = "done" },
	{ id = "t2", text = "Trace the layout pass that drops the click", state = "done" },
	{ id = "t3", text = "Fix the recentre on blur", state = "active" },
	{ id = "t4", text = "Run the suite", state = "pending" },
	{ id = "t5", text = "Write the release note", state = "pending" },
}

local function trays(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "todo · open · the turn is live",
			well(420, tray.todo { id = "todo", items = TODOS, live = true, open = todo_open, w = 388 }),
		},
		specimen.cell {
			label = "todo · collapsed",
			well(420, tray.todo { items = TODOS, open = todo_closed, w = 388 }),
		},
		specimen.cell {
			label = "queue · rows slide on 150 ms ease-out",
			ui.column {
				gap = "$zeron.space.12",
				items = "start",
				well(
					520,
					tray.queue {
						id = "queue",
						items = queued,
						w = 488,
						on_remove = function(id: string)
							for i, q in queued:peek() do
								if q.id == id then
									queued:remove(i)
								end
							end
						end,
					}
				),
				kit.button {
					id = "queue_reset",
					label = "Reset",
					size = "sm",
					variant = "ghost",
					on_click = function()
						queued:set {
							{ id = "q1", text = "Then run the tests and fix what fails" },
							{ id = "q2", text = "Add the release notes to CHANGELOG.md", attachments = 2 },
							{ id = "q3", text = "Open a PR against main" },
						}
					end,
				},
			},
		},
	}
end

local function rolls(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "center",
		flex_wrap = true,
		specimen.cell {
			label = "only the changed glyphs roll · 550 ms, staggered 30%",
			ui.row {
				gap = "$zeron.space.16",
				items = "center",
				kit.roll { id = "roll", value = roll_value, size = "md" },
				kit.button {
					id = "roll_next",
					label = "Next",
					size = "sm",
					variant = "secondary",
					on_click = function()
						roll_i = roll_i % #ROLLS + 1
						roll_value:set(ROLLS[roll_i])
					end,
				},
			},
		},
		specimen.cell {
			label = "a count, tabular",
			ui.row {
				gap = "$zeron.space.16",
				items = "center",
				kit.roll { value = roll_count, size = "xl", weight = "semibold", tabular = true },
				kit.button {
					label = "+1",
					size = "sm",
					variant = "secondary",
					on_click = function()
						local n = tonumber((roll_count:peek():gsub(",", ""))) or 0
						local s = tostring(n + 1)
						roll_count:set((s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")))
					end,
				},
			},
		},
	}
end

local function badges(): Node
	local items: { message_badge.Item } = {
		{
			where = "src/layout/compose.rs:412",
			tag = "selection",
			body = "let centred = parent.items == Align::Center && self_align.is_none();",
		},
		{
			where = "crates/ui/src/shell.rs",
			tag = "comment",
			body = "This recentres the page when its height changes mid-press, which drops the click.",
		},
	}
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "hover 280 ms for the card",
			kit.message_badge { id = "badge", label = "2 references", icon = "file-code", items = items },
		},
		specimen.cell {
			label = "preview",
			-- Room under the badge for the card it holds open.
			ui.column {
				h = 260,
				kit.message_badge { label = "2 references", icon = "file-code", items = items, preview = true },
			},
		},
		specimen.cell { label = "a file", kit.message_badge { label = "release-notes.md", icon = "file-markdown" } },
	}
end

return function(): Node
	local p = state.page_by("agent")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "Dictation",
			note = "mic 28 → accent plate, 420 ms ease-out-soft · track 32, bars 3 at a 6 pitch, mono clock",
			dictation_cells(),
		},
		specimen.section {
			title = "Context usage",
			note = "ring 16, stroke 1.8, clockwise from 12 · muted / warning at 75% / danger at 90%",
			usage_cells(),
		},
		specimen.section {
			title = "Trays",
			note = "frost, top corners 16, rows at 11 · 18 tucked under the composer",
			trays(),
		},
		specimen.section { title = "Roll text", rolls() },
		specimen.section {
			title = "Message badges",
			note = "24 high on ink 6% · card 320 on frost, rows on ink 5% with a 2-point rail",
			badges(),
		},
	}
end
