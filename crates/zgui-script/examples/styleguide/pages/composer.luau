-- The composer: a state picker and the composer in that state, live.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local composer = require("@kit/composer")

type StateDef = { id: string, title: string, build: () -> composer.Props }

local current = ui.state("composer_state", "empty")
local draft = ui.state("draft", "")
local working = ui.state("working", false)
local context = ui.state("context", 0.78 :: number?)
local choice = ui.state("choice", "main")
local attachments = ui.state("attachments", {} :: { composer.Attachment })
local queued = ui.state("queued", {} :: { composer.QueueItem })

local ATTACHMENTS: { composer.Attachment } = {
	{ id = "a", name = "Lisboeta", kind = "link", detail = "opentable.com" },
	{ id = "b", name = "Dinner menu.pdf", kind = "file", badge = "PDF", detail = "6 pages · 2.4 MB" },
	{ id = "c", name = "photo.jpg", kind = "image" },
}
local UPLOADING: { composer.Attachment } = {
	{ id = "a", name = "Floor plan.pdf", kind = "file", badge = "PDF", progress = 0.62 },
	{ id = "b", name = "Trip budget.xlsx", kind = "file", error = "Too large (25 MB)" },
}
local QUEUE: { composer.QueueItem } = {
	{ id = "q1", text = "Find parking near the restaurant" },
	{ id = "q2", text = "Add the booking to my calendar" },
}
local RESULTS: { composer.CompletionItem } = {
	{ id = "1", label = "composer.luau", detail = "kit", icon = "file-code" },
	{ id = "2", label = "compact_picker.luau", detail = "kit", icon = "file-code" },
	{ id = "3", label = "completion.luau", detail = "kit", icon = "file-code" },
	{ id = "4", label = "compose.rs", detail = "crates/zgui/src", icon = "file-code" },
	{ id = "5", label = "components", detail = "crates/zgui/src", icon = "folder" },
	{ id = "6", label = "README.md", detail = "", icon = "file-markdown" },
}

local function base(extra: { [string]: any }?): composer.Props
	local props: composer.Props = {
		id = "composer",
		value = draft,
		working = working,
		on_send = function()
			if draft:peek() ~= "" then
				working:set(true)
				draft:set("")
			end
		end,
		on_stop = function()
			working:set(false)
		end,
		on_queue = function()
			queued:push { id = `q{queued:len() + 3}`, text = draft:peek() }
			draft:set("")
		end,
		on_remove_queued = function(id: string)
			for i, q in queued:peek() do
				if q.id == id then
					queued:remove(i)
				end
			end
		end,
		on_remove_attachment = function(id: string)
			for i, a in attachments:peek() do
				if a.id == id then
					attachments:remove(i)
				end
			end
		end,
	}
	for k, v in extra or {} do
		(props :: any)[k] = v
	end
	return props
end

local STATES: { StateDef } = {
	{
		id = "empty",
		title = "Empty",
		build = function()
			draft:set("")
			working:set(false)
			return base()
		end,
	},
	{
		id = "typing",
		title = "Typing",
		build = function()
			draft:set("Summarize this page")
			working:set(false)
			return base()
		end,
	},
	{
		id = "focus",
		title = "Focused",
		build = function()
			return base { preview = "focus" }
		end,
	},
	{
		id = "compact",
		title = "Compact (one line in a thread)",
		build = function()
			draft:set("")
			working:set(false)
			return base { compact = true, docked = true }
		end,
	},
	{
		id = "docked",
		title = "Docked with the session footer",
		build = function()
			draft:set("")
			working:set(false)
			return base {
				docked = true,
				branch = "main",
				checkout = "~/zeron/zgui",
				pr = 412,
				context = context,
				context_total = 200000,
			}
		end,
	},
	{
		id = "attachments",
		title = "Attachments",
		build = function()
			attachments:set(ATTACHMENTS)
			return base { attachments = attachments, placeholder = "Reply, @ for context" }
		end,
	},
	{
		id = "uploading",
		title = "Uploading and error",
		build = function()
			attachments:set(UPLOADING)
			return base { attachments = attachments }
		end,
	},
	{
		id = "working",
		title = "Working",
		build = function()
			draft:set("")
			working:set(true)
			return base { placeholder = "Reply, @ for context" }
		end,
	},
	{
		id = "steer",
		title = "Working · typed (send queues)",
		build = function()
			draft:set("Actually, make it 6 people.")
			working:set(true)
			return base()
		end,
	},
	{
		id = "queue",
		title = "Queue",
		build = function()
			queued:set(QUEUE)
			draft:set("")
			working:set(true)
			return base {
				docks = { { kind = "queue", items = queued:peek(), timing = "After this run" } },
			}
		end,
	},
	{
		id = "question",
		title = "Question",
		build = function()
			working:set(true)
			return base {
				placeholder = "Type another answer…",
				docks = {
					{
						kind = "question",
						prompt = "The window tables are full. Where would you like to sit?",
						choices = {
							{ id = "main", title = "Main dining room", description = "Quieter tables · Recommended" },
							{ id = "counter", title = "At the counter", description = "A view into the open kitchen" },
							{ id = "either", title = "Either is fine", description = "Book the first available table" },
						},
						selected = choice,
					},
				},
			}
		end,
	},
	{
		id = "error",
		title = "Error",
		build = function()
			working:set(false)
			return base {
				placeholder = "Reply with the code…",
				docks = {
					{
						kind = "error",
						label = "Stopped",
						site = "opentable.com",
						title = "OpenTable needs a verification code",
						body = "A 6-digit code went to the phone ending 4821. I can't read your messages, so I stopped before adding the seating note.",
						hint = "or reply with the code",
						on_dismiss = ui.set(current, "empty"),
						on_retry = ui.set(current, "working"),
					},
				},
			}
		end,
	},
	{
		id = "picker",
		title = "@ Reference picker",
		build = function()
			draft:set("Compare @comp")
			working:set(false)
			return base { picker = { token = { trigger = "@", query = "comp" }, items = RESULTS } }
		end,
	},
}

local function picker(): Node
	local rows: { Node } = {}
	for _, s in STATES do
		table.insert(
			rows,
			kit.row {
				id = "composer_" .. s.id,
				label = s.title,
				size = "sm",
				group = "composer_states",
				selected = function()
					return current:get() == s.id
				end,
				on_click = ui.set(current, s.id),
			}
		)
	end
	return ui.column {
		w = 200,
		gap = "$zeron.space.1",
		shrink = 0,
		rows,
		kit.text.text {
			function()
				return `state: {current:get()}`
			end,
			id = "composer_current",
			size = "xs",
			mono = true,
			color = T.tertiary,
			mt = "$zeron.space.8",
			px = "$zeron.space.8",
		},
	}
end

local function stage(): Node
	return ui.column {
		grow = 1,
		p = "$zeron.space.32",
		pt = "$zeron.space.48",
		items = "center",
		-- The composer sits at the stage's bottom, as in a thread; a centred
		-- stage moves on any height change, and a click mid-press is lost.
		justify = "end",
		rounded = T.radius_card,
		bg = T.bg,
		border = 1,
		border_color = T.hairline,
		ui.presence(current, function(id: string): Node
			for _, s in STATES do
				if s.id == id then
					return composer.composer(s.build())
				end
			end
			return composer.composer(base())
		end, {
			w = 396,
			layout = "height",
			enter = {
				opacity = { 0, 1 },
				y = { 8, 0 },
				duration = kit.motion.d(kit.motion.NORMAL),
				ease = kit.motion.EASE_OUT_EXPO,
			},
			exit = { opacity = 0, duration = kit.motion.d(kit.motion.FAST) },
			mode = "wait",
		}),
	}
end

return function(): Node
	local page = state.page_by("composer")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		ui.row {
			gap = "$zeron.space.24",
			items = "stretch",
			w_full = true,
			picker(),
			stage(),
		},
	}
end
