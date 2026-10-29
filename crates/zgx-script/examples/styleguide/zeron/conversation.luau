-- The conversation: the transcript (the sent-turn hold gliding a prompt
-- to the top, the reply streaming into the runway under it), the todo tray
-- and the composer docked under it with its model picker.
local T = require("../theme")
local kit = require("@kit")
local kit_access = require("@kit/access")
local picker_card = require("@kit/picker_card")
local model_picker_kit = require("@kit/model_picker")
local tray = require("@kit/tray")
local activity = require("@kit/activity")
local lightbox = require("@kit/lightbox")
local composer = require("@kit/composer")
local carry = require("@kit/attachments")
local dictation = require("@kit/dictation")
local data = require("./data")
local references = require("./references")
local session_card = require("./session_card")
local chrome = require("./chrome")
local state = require("./state")
local comments = require("./comments")
local message_badge = require("@kit/message_badge")
local ps = require("@kit/panel_shell")
local voice = require("./voice")
local usage = require("./usage")
local keys = require("./keys")
local notify = require("./notify")
local turns_mod = require("./turns")
local links = require("./links")
local cloud = require("./cloud")

local MODELS = data.MODELS
local REPLY = data.REPLY
-- What a sent turn's agent does before it answers.
local LIVE_TOOLS: { data.Tool } = {
	{
		icon = "magnifer",
		label = "Search",
		detail = "lead with the glass",
		call = "lead with the glass in docs",
		output = "docs/release-notes.md:3: lead with the glass, then the panes\n",
	},
	{
		icon = "document",
		label = "Read",
		detail = "docs/release-notes.md",
		file = true,
		call = "docs/release-notes.md",
		output = "# Release notes\n\nLead with the glass, then the panes.\n",
	},
	{
		icon = "pen",
		label = "Edit",
		detail = "docs/release-notes.md",
		file = true,
		hunks = {
			{
				header = "@@ -1,3 +1,3 @@",
				lines = {
					{ kind = "ctx", old = 1, new = 1, text = "# Release notes" },
					{ kind = "ctx", old = 2, new = 2, text = "" },
					{ kind = "del", old = 3, text = "Lead with the glass, then the panes." },
					{ kind = "add", new = 3, text = "One tint over the desktop's blur, the chat straight on it." },
				},
			},
		},
		writes = "docs/release-notes.md",
		patch = [[
diff --git a/docs/release-notes.md b/docs/release-notes.md
index 5e1c309..8d2a4f1 100644
--- a/docs/release-notes.md
+++ b/docs/release-notes.md
@@ -1,3 +1,3 @@
 # Release notes

-Lead with the glass, then the panes.
+One tint over the desktop's blur, the chat straight on it.
]],
	},
	{
		icon = "terminal",
		label = "Run",
		detail = "cargo test -p zgx-script --test zeron_app",
		call = "cargo test -p zgx-script --test zeron_app",
		output = "running 24 tests\ntest result: ok. 24 passed; 0 failed\n",
	},
	{
		icon = "chat-round-line",
		label = "Thought process",
		detail = "",
		thought = "The tests pass with the new opening. Say what changed in one line, and keep **the panes** for the second.",
	},
}
local tr = require("@kit/transcript")

local M = {}

-- The reading column's width: Appearance's Conversation width and 16 on
-- each side, one state every conversation binds (the engine reads it, no
-- script runs per column).
local reading: State<number>? = nil
local function reading_column(): State<number>
	if not reading then
		local width = require("./settings").pref.conversation_width
		reading = ui.computed(function(): number
			return width:get() + 32
		end)
	end
	return reading :: State<number>
end

-- Where a side chat forked (transcript.rs fork_marker): "Forked from"
-- between two strong rules, the source's title under it, 14 above and
-- below.
local function fork_marker(id: string, title: string): Node
	local function rule(): Node
		return ui.div { grow = 1, min_w = 0, h = 1, bg = T.strong }
	end
	return ui.column {
		id = id,
		w_full = true,
		pt = "$zeron.space.28",
		pb = "$zeron.space.14",
		gap = "$zeron.space.6",
		items = "stretch",
		ui.row {
			w_full = true,
			gap = "$zeron.space.10",
			items = "center",
			rule(),
			kit.text.text { "Forked from", size = "sm", color = T.tertiary, line = false, shrink = 0 },
			rule(),
		},
		kit.text.text {
			title,
			size = "md",
			weight = "medium",
			color = T.secondary,
			align = "center",
			truncate = true,
			line = false,
		},
	}
end

-- What a drop on a session's chat lands in (zeron/dropzone, by
-- `state.hooks.drop_into`): its conversation, the last one built.
local receivers: { [string]: (payload: any) -> () } = {}
state.hooks.drop_into = function(session: string, payload: any)
	local receive = receivers[session]
	if receive then
		receive(payload)
	end
end

-- The sample session's pace (tests may play it slower): `ms` of it, in
-- real time.
local stream_pace = ui.shared("stream_pace", 1)
local function paced(ms: number): number
	return ms / math.max(stream_pace:peek(), 0.01)
end

local IMAGE = { png = true, jpg = true, jpeg = true, gif = true, webp = true, heic = true }

-- How long another device's chat takes to replay its history once the
-- connection is there.
local LOAD_MS = 700

-- Each session's run, as its conversation last showed it: what Escape
-- stops (Settings → General).
local runs: { [string]: { working: State<boolean>, sending: State<boolean>, stop: () -> () } } = {}
function M.stop(session: string): boolean
	local run = runs[session]
	if run and run.working:peek() then
		run.stop()
		return true
	end
	return false
end

-- Whether a run of `harness` is under way now (its update waits for it).
function M.busy(harness: string): boolean
	for session, run in runs do
		local s = data.session(session)
		if (run.working:peek() or run.sending:peek()) and s and s.harness == harness then
			return true
		end
	end
	return false
end

-- The sample engine's next failure (⌘K "Sample engine: Fail …"): the next
-- send, stop or upload fails, as Zeron's composer says it.
local failing: { send: boolean?, stop: boolean?, upload: boolean?, dictation: dictation.Outcome? } = {}
function M.fail_next(what: "send" | "stop" | "upload")
	(failing :: any)[what] = true
end
-- The next dictation's outcome (⌘K "Sample engine: …"): no speech heard,
-- the microphone refused, or the transcription stopped.
local DICTATION: { [string]: dictation.Outcome } = {
	no_speech = dictation.NO_SPEECH,
	denied = {
		title = "Dictation unavailable",
		detail = "Allow Microphone access for Zeron in System Settings → Privacy & Security, then retry.",
		failed = true,
		at = "start",
	},
	failed = {
		title = "Dictation stopped",
		detail = "Dictation took too long. Your draft is safe. Wait a moment, then try a shorter recording.",
		failed = true,
	},
}
function M.fail_dictation(what: "no_speech" | "denied" | "failed")
	failing.dictation = DICTATION[what]
end
local function dictation_outcome(at: "start" | "end"): dictation.Outcome?
	local queued = failing.dictation
	if queued and (queued.at or "end") == at then
		failing.dictation = nil
		return queued
	end
	return nil
end

-- ⌘/ opens the model picker of `session`'s composer (the canvas's for
-- "new"), while its chip shows.
function M.open_model_picker(session: string): boolean
	if not require("./settings").pref.model_chip:peek() then
		return false
	end
	ui.state(`{session}:picker_open`, false):set(true)
	return true
end

-- What the composers take from Settings: the send key, the model chip,
-- dictation and its shortcut.
local function composer_prefs(): any
	local pref = require("./settings").pref
	return {
		send_with = pref.send,
		show_model = pref.model_chip,
		voice = pref.dictation,
		dictation_key = function(e: KeyEvent): boolean
			return keys.is("toggle_dictation", e)
		end,
	}
end

-- The model chip's picker: the compact one, or the full one with every
-- provider's models and their settings (Settings: Compact model picker
-- off).
type PickerStates = {
	open: State<boolean>,
	model: State<string>,
	effort: State<number>,
	fast: State<boolean>,
	context: State<string>,
	favorites: State<{ string }>,
}
local function model_picker(compact_id: string, full_id: string, chip: Node, s: PickerStates): Node
	return ui.presence(function(): string
		return if require("./settings").pref.compact_picker:get() then "compact" else "full"
	end, function(mode: string): Node
		if mode == "compact" then
			return kit.compact_picker {
				id = compact_id,
				open = s.open,
				anchor = chip,
				models = MODELS,
				model = s.model,
				effort = s.effort,
				fast = s.fast,
				favorites = s.favorites,
			}
		end
		return model_picker_kit.picker {
			id = full_id,
			open = s.open,
			anchor = chip,
			models = MODELS,
			model = s.model,
			effort = s.effort,
			fast = s.fast,
			context = s.context,
			favorites = s.favorites,
		}
	end, { shrink = 1, min_w = 0 })
end

-- The chip's suffix: the effort, then a long context and fast mode.
local function traits(model: State<string>, effort: State<number>, context: State<string>, fast: State<boolean>): string
	for _, m in MODELS do
		if m.id == model:get() then
			return model_picker_kit.traits(m, effort:get(), context:get(), fast:get())
		end
	end
	return ""
end

-- A conversation. `session` keys its states (two panes showing one
-- session share its draft and its turns) and, with `prefix`, its ids (two
-- panes never share an id); without them, the classic layout's one, with
-- the session card. A side chat shows what it forked (that chat's turns,
-- then where it forked), then its own.
function M.view(session: string?, prefix: string?): Node
	local function key(name: string): string
		return if session then `{session}:{name}` else name
	end
	local function name(id: string): string
		return if prefix then `{prefix}_{id}` else id
	end
	-- A session started in this window has only what was sent to it.
	local record = if session then data.session(session) else nil
	local fresh = record ~= nil and record.fresh == true
	local side = record ~= nil and record.parent ~= nil
	local main = prefix == nil
	local draft = ui.state(key("draft"), "")
	local working = ui.state(key("working"), false)
	-- A message on its way that the session has not taken up yet: the
	-- composer's strip says "Sending…" until it does, then the transcript's
	-- working line takes over (Zeron's status strip and trailer).
	local sending = ui.state(key("sending"), false)
	local todo_open = ui.state(key("todo_open"), false)
	local model = ui.state(key("model"), "opus")
	local effort = ui.state(key("effort"), 3)
	local fast = ui.state(key("fast"), false)
	local context_window = ui.state(key("context_window"), "Standard")
	local favorites = ui.state(key("favorites"), {} :: { string })
	local picker_open = ui.state(key("picker_open"), false)
	local turn_open = ui.state(key("turn_open"), true)
	-- How full the context window is (the footer's ring): each turn adds.
	-- Cursor reports none (context_usage.rs: "not reported").
	local reported = not (record and record.harness == "cursor")
	local context = ui.state(key("context"), (if not reported then nil elseif fresh then 0.02 else 0.34) :: number?)

	-- The sent-turn hold: sent prompts glide to the top of the thread with
	-- the reply streaming into the runway under them. Four slots take what
	-- the composer sends.
	-- A session opens at its end (the newest turn in view).
	local hold_offset = ui.state(key("hold_offset"), math.huge)
	-- Whether the transcript shows its end: "Scroll to bottom" shows while
	-- it does not.
	local at_end = ui.state(key("at_end"), true)
	local hold = kit.own_turn.new {
		offset = hold_offset,
		inset = kit.own_turn.INSET,
		pb = 20,
		gap = 24,
	}
	local sent_n = ui.state(key("sent_n"), 0)
	local sent_text: { State<string> } = {}
	for i = 1, 4 do
		table.insert(sent_text, ui.state(key(`sent_{i}`), ""))
	end
	local streamed = ui.state(key("streamed"), 0)
	-- Each sent turn's tool calls as they arrive, and whether its group is
	-- open: open while the calls run, folding when the reply is done.
	local sent_tools: { State<{ activity.Activity }> } = {}
	local sent_open: { State<boolean> } = {}
	for i = 1, 4 do
		table.insert(sent_tools, ui.state(key(`sent_tools_{i}`), {} :: { activity.Activity }))
		table.insert(sent_open, ui.state(key(`sent_open_{i}`), true))
	end
	-- What was typed while the agent worked, sent in turn as each run ends;
	-- and what is attached to the next message.
	local queue = ui.state(key("queue"), {} :: { tray.Queued })
	local attachments = ui.state(key("attachments"), {} :: { composer.Attachment })
	-- What each sent turn carried (its images uploading, then loaded), how
	-- long it worked once done (compact mode's "Worked for"), and whether
	-- it waits on a device that is away (delivery degraded: it queues).
	local sent_carried: { State<{ carry.Sent }> } = {}
	local sent_worked: { State<number> } = {}
	for i = 1, 4 do
		table.insert(sent_carried, ui.state(key(`sent_carried_{i}`), {} :: { carry.Sent }))
		table.insert(sent_worked, ui.state(key(`sent_worked_{i}`), 0))
	end
	local away = record ~= nil and data.project_offline(record.project)
	local queued = ui.state(key("queued_send"), false)
	-- Why the last send, stop or upload failed (the composer's notice).
	local failure = ui.state(key("failure"), nil :: string?)
	-- The queued message being edited in the composer, and the draft set
	-- aside for it (queue.rs swap_in_queued_draft).
	local editing = ui.state(key("editing"), nil :: string?)
	local set_aside = ui.state(key("set_aside"), nil :: { text: string, attachments: { composer.Attachment } }?)
	local stream_run = 0
	local queued_made = 0
	local send_text: (text: string) -> ()
	-- The run is over: the first queued message goes (the one being edited
	-- keeps its place).
	local function send_next()
		local list = queue:peek()
		for i, q in list do
			if q.id ~= editing:peek() then
				local rest = table.clone(list)
				table.remove(rest, i)
				queue:set(rest)
				send_text(q.text)
				return
			end
		end
	end
	local stop_run: () -> ()
	-- Zeron's own / commands (composer.rs WorkspaceCommand): a pick in the
	-- menu, or one sent alone, runs at once.
	local actions: references.Actions = {
		model = function()
			picker_open:set(true)
		end,
		new = function()
			state.go("chat", "new")
		end,
		resume = function()
			state.palette:set(true)
		end,
		settings = function()
			state.settings:set(true)
		end,
		diff = function()
			-- The changes tab the pane has, or a new one.
			if not state.tabbed_now() then
				for _, t in state.tabs:peek() do
					if t.kind == "changes" then
						state.tab:set(t.id)
						ps.set_open(state.chat, "right", true)
						return
					end
				end
			end
			state.open_tab("changes")
		end,
		files = function()
			ps.set_open(state.chat, "files", true)
		end,
		terminal = function()
			state.open_tab("terminal")
		end,
		stop = function()
			stop_run()
		end,
	}
	-- Review comments staged from the changes, folded into the next prompt.
	local staged = comments.staged(session or "chat")
	local function send_draft()
		local text = draft:peek()
		-- Out of Cloud credits, a send to a Cloud session goes nowhere.
		if session and cloud.blocks_send(session) then
			return
		end
		-- A file comment's line must be in the file the agent reads.
		if comments.held(session or "chat") then
			return
		end
		local command = references.command_of(text, actions)
		draft:set("")
		if command then
			command()
			return
		end
		local notes = staged:peek()
		if #notes > 0 then
			staged:set {}
			text = comments.fold(text, notes)
		end
		send_text(text)
	end
	stop_run = function()
		if failing.stop then
			failing.stop = nil
			failure:set("Stop failed: the engine did not answer")
			return
		end
		stream_run += 1
		working:set(false)
		sending:set(false)
		queued:set(false)
	end
	if session then
		runs[session] = { working = working, sending = sending, stop = stop_run }
	end
	send_text = function(text: string)
		if text == "" or sent_n:peek() >= #sent_text then
			return
		end
		-- A send that fails keeps the message in the draft.
		if failing.send then
			failing.send = nil
			failure:set("Send failed: the engine did not answer")
			if draft:peek() == "" then
				draft:set(text)
			end
			return
		end
		failure:set(nil)
		-- A side chat is minted (and titled) by its first message.
		if side and session then
			data.side_chat_sent(session, text)
			state.sides_changed()
		end
		local n = sent_n:peek() + 1
		-- What it carries goes with it: its images upload (the percent on
		-- each), then show.
		local carried: { carry.Sent } = {}
		for _, a in attachments:peek() do
			if a.kind ~= "link" then
				table.insert(carried, {
					id = `sent_{n}_{a.id}`,
					name = a.name,
					kind = (if a.kind == "image" then "image" else "file") :: "image" | "file",
					src = if a.kind == "image" then "images/shadow.jpg" else nil,
					w = 720,
					h = 480,
					status = (if a.kind == "image" then "uploading" else nil) :: any,
					progress = if a.kind == "image" then 0 else nil,
				})
			end
		end
		sent_carried[n]:set(carried)
		for k, a in carried do
			if a.kind == "image" then
				for step = 1, 4 do
					ui.after(step * 200, function()
						sent_carried[n]:set_key({ k, "progress" }, step * 25)
						if step == 4 then
							sent_carried[n]:set_key({ k, "status" }, "loaded")
						end
					end)
				end
			end
		end
		attachments:set {}
		stream_run += 1
		local this = stream_run
		hold.send()
		sent_text[n]:set(text)
		sent_n:set(n)
		streamed:set(0)
		working:set(true)
		local began = ui.now()
		-- A device that is away holds the send: it waits, queued, and goes
		-- once the device is back (not while this sample's is asleep).
		if away then
			queued:set(true)
			return
		end
		-- A Cloud session's machine wakes (or starts) first.
		local lead = if session then cloud.wake_for_send(session) else 0
		local function at(ms: number): number
			return lead + paced(ms)
		end
		-- The session takes it up a moment later.
		sending:set(true)
		ui.after(paced(250), function()
			if stream_run == this then
				sending:set(false)
			end
		end)
		local tools = sent_tools[n]
		tools:set {}
		sent_open[n]:set(true)
		-- The calls arrive one after another, each running a moment before
		-- it is done; the reply streams once they are.
		for k, call in LIVE_TOOLS do
			local arrive = 300 + (k - 1) * 600
			ui.after(at(arrive), function()
				if stream_run == this then
					tools:push {
						id = `live{n}_{k}`,
						icon = call.icon,
						label = call.label,
						detail = call.detail,
						file = call.file,
						call = call.call,
						output = call.output,
						hunks = call.hunks,
						thought = call.thought,
						status = "running",
					}
				end
			end)
			ui.after(at(arrive + 400), function()
				if stream_run == this then
					tools:set_key({ k, "status" }, "done")
					-- What it wrote shows in the workspace as it lands.
					if call.writes then
						require("./files").write(call.writes, call.patch)
					end
				end
			end)
		end
		local reply_at = 300 + #LIVE_TOOLS * 600
		for i = 1, #REPLY do
			ui.after(at(reply_at + (i - 1) * 400), function()
				if stream_run == this then
					streamed:set(i)
					if i == #REPLY then
						working:set(false)
						sent_worked[n]:set(math.max((ui.now() - began) / 1000, 1))
						if side and record then
							record.status = "done"
							state.sides_changed()
						end
						notify.event("done", if record then record.title else nil, nil, session)
						if reported then
							context:set(math.min((context:peek() or 0) + 0.06, 1))
						end
						-- Done: the calls fold away under their summary.
						sent_open[n]:set(false)
						-- The run is over: the next queued message goes.
						ui.after(300, send_next)
					end
				end
			end)
		end
	end
	local function queue_draft()
		local text = draft:peek()
		if text == "" then
			return
		end
		queued_made += 1
		local list = table.clone(queue:peek())
		local files: { tray.QueuedFile } = {}
		for _, a in attachments:peek() do
			table.insert(files, { name = a.name, src = a.src })
		end
		table.insert(list, { id = `q{queued_made}`, text = text, attachments = #files, files = files })
		queue:set(list)
		draft:set("")
		attachments:set {}
	end
	-- Editing a queued message (queue.rs): the draft is set aside and the
	-- message fills the composer while its row keeps its place; Save to
	-- queue writes it back (an empty one leaves the queue), Cancel leaves
	-- the row as it was; either way the draft comes back.
	local function restore()
		local aside = set_aside:peek()
		editing:set(nil)
		set_aside:set(nil)
		draft:set(if aside then aside.text else "")
		attachments:set(if aside then aside.attachments else {})
	end
	local function edit_queued(id: string)
		if editing:peek() then
			restore()
		end
		for _, q in queue:peek() do
			if q.id == id then
				set_aside:set { text = draft:peek(), attachments = attachments:peek() }
				local staged: { composer.Attachment } = {}
				for i, f in q.files or {} do
					table.insert(staged, {
						id = `{id}_{i}`,
						name = f.name,
						src = f.src,
						kind = (if f.src then "image" else "file") :: "image" | "file",
					})
				end
				editing:set(id)
				draft:set(q.text)
				attachments:set(staged)
				return
			end
		end
	end
	local function save_edit()
		local id = editing:peek()
		if not id then
			return
		end
		local text = draft:peek()
		local files: { tray.QueuedFile } = {}
		for _, a in attachments:peek() do
			table.insert(files, { name = a.name, src = a.src })
		end
		local list: { tray.Queued } = {}
		for _, q in queue:peek() do
			if q.id ~= id then
				table.insert(list, q)
			elseif text ~= "" or #files > 0 then
				table.insert(list, { id = q.id, text = text, attachments = #files, files = files })
			end
		end
		queue:set(list)
		restore()
	end
	local function move_queued(id: string, index: number)
		local list = table.clone(queue:peek())
		for i, q in list do
			if q.id == id then
				table.remove(list, i)
				table.insert(list, math.clamp(index, 1, #list + 1), q)
				queue:set(list)
				return
			end
		end
	end
	-- An image opens in the viewer.
	local function open_image(name: string, src: string?)
		if src then
			lightbox.open { src = src, name = name, w = 480, h = 720 }
		end
	end
	-- A drop: a session mentioned in the draft (one chip, its title's words
	-- joined by no-break spaces), a workspace file referenced there, files
	-- from other apps attached (chat_dropzone.rs).
	local function mention(token: string)
		local text = draft:peek()
		local gap = if text == "" or string.find(string.sub(text, -1), "%s") then "" else " "
		draft:set(`{text}{gap}@{token} `)
	end
	local dropped = 0
	receivers[session or "chat"] = function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "session" and payload.title then
			mention((string.gsub(payload.title, " ", "\u{a0}")))
		elseif payload.kind == "file" and payload.path then
			-- A folder's with its slash; several chosen, each of them.
			for _, it in payload.items or { payload } do
				mention(if it.folder then `{it.path}/` else it.path)
			end
		elseif type(payload.files) == "table" then
			local list = table.clone(attachments:peek())
			for _, path in payload.files do
				dropped += 1
				local file = string.match(path, "([^/\\]+)$") or path
				local ext = string.lower(string.match(file, "%.(%w+)$") or "")
				table.insert(list, {
					id = `d{dropped}`,
					name = file,
					kind = (if IMAGE[ext] then "image" else "file") :: "image" | "file",
				})
			end
			attachments:set(list)
		end
	end
	local attached = 0
	local function attach()
		attached += 1
		local list = table.clone(attachments:peek())
		local image = attached % 2 == 1
		local failed = failing.upload == true
		failing.upload = nil
		table.insert(list, {
			id = `a{attached}`,
			name = if image then `Screenshot {attached}.png` else "panel_layout.rs",
			kind = (if image then "image" else "file") :: "image" | "file",
			src = if image then "images/screenshot-tall.jpg" else nil,
			error = if failed then "Upload failed" else nil,
		})
		attachments:set(list)
		if failed then
			failure:set("Couldn't upload the attachment — the device may be offline.")
		end
	end

	-- The canvas hands its first message over: it sends as the view opens.
	local autosend = ui.state(key("autosend"), "")
	if autosend:peek() ~= "" then
		draft:set(autosend:peek())
		autosend:set("")
		ui.after(0, send_draft)
	end

	local function model_label(): string
		for _, m in MODELS do
			if m.id == model:get() then
				return m.label
			end
		end
		return ""
	end
	local function effort_label(): string
		return traits(model, effort, context_window, fast)
	end

	-- Turns space themselves (24 above each) instead of a column gap: a hidden
	-- slot must take no room, and the engine keeps a gap around hidden children.
	-- Zeron's row gaps (transcript.rs top_gap_for): 16 where a turn starts,
	-- 8 from a prompt to its reply.
	local function spaced(node: Node, first: boolean?, gap: Length?): Node
		return ui.column { w_full = true, pt = if first then 0 else gap or "$zeron.space.16", node }
	end

	-- The reading column, centred; in the chat's own column it keeps the
	-- session card's room on its right while the card shows beside it.
	local room = if main
		then ui.tween(session_card.room, { duration = kit.motion.d(kit.motion.RESIZE), ease = kit.motion.EASE_OUT })
		else nil
	-- Its width is Appearance's Conversation width, 16 in on each side.
	local column_w = reading_column()
	local function centred(column: { [any]: any }, shrink: number?): Node
		if not room then
			column.w_full = true
			column.max_w = column_w
			column.self = "center"
			column.shrink = shrink
			return ui.column(column :: any)
		end
		column.w = column_w
		column.shrink = 1
		column.min_w = 0
		return ui.row {
			w_full = true,
			shrink = shrink,
			ui.div { grow = 1 },
			ui.column(column :: any),
			ui.div { grow = 1, min_w = room },
		}
	end

	-- The message rail's ticks: the history's prompts, then those sent here.
	local content_ref = ui.ref()
	local column_ref = if main then session_card.column else ui.ref()
	local entries = if fresh then {} else data.history(session or "")
	-- A chat on another device (transcript_loading): until its history has
	-- arrived the list is blank, and the loader says what it waits on once
	-- that takes 300 ms: the replay ("Opening…"), the sync, the reconnect,
	-- or the connection itself. The sample replays a moment after the
	-- connection is back; a chat once shown stays loaded for the window's
	-- life.
	local ready: () -> boolean = function()
		return true
	end
	local loading: (() -> tr.Loading?)? = nil
	if session and data.ELSEWHERE[session] and not fresh then
		local connection = require("./account").connection
		local function live(): boolean
			local c = connection:peek()
			return c == "connected" or c == "storage_error"
		end
		local arrived = ui.state(key("arrived"), live())
		local waited = ui.state(key("loader_shown"), false)
		ready = function()
			return arrived:get()
		end
		local replaying = false
		ui.effect(function()
			local c = connection:get()
			if arrived:peek() or replaying or (c ~= "connected" and c ~= "storage_error") then
				return
			end
			replaying = true
			ui.after(paced(LOAD_MS), function()
				arrived:set(true)
			end)
		end)
		if not arrived:peek() then
			ui.after(tr.LOADER_DELAY, function()
				waited:set(true)
			end)
		end
		loading = function(): tr.Loading?
			if arrived:get() or not waited:get() then
				return nil
			end
			local c = connection:get()
			if c == "offline" then
				return "offline"
			elseif c == "reconnecting" then
				return "reconnecting"
			elseif c == "syncing" then
				return "syncing"
			end
			return "opening"
		end
	end
	local history_ticks: { tr.RailTick } = {}
	do
		local nth = 0
		for _, entry in entries do
			if entry.turn then
				nth += 1
				table.insert(history_ticks, turns_mod.tick(entry.turn, nth))
			end
		end
	end
	local rail = turns_mod.rail(
		key("rail"),
		ui.computed(function(): { tr.RailTick }
			local out = table.clone(history_ticks)
			for i = 1, sent_n:get() do
				table.insert(out, {
					id = `sent_{i}`,
					prompt = (comments.read(sent_text[i]:get())),
					reply = table.concat(REPLY, ""),
				})
			end
			return out
		end),
		hold_offset,
		content_ref,
		column_ref
	)
	local ctx: turns_mod.Ctx = { session = session, name = name, key = key, rail = rail }

	-- A sent turn's calls as they arrive: their live group, or in compact
	-- mode under the turn's one header, its summary turning to "Worked for"
	-- as the turn settles.
	local function sent_work(i: number): Node
		local replayed = false
		local function active(): boolean
			-- Until the reply is done, the turn works on it.
			return sent_n:get() == i and streamed:get() < #REPLY and working:get()
		end
		local function summary(): State<string>
			return ui.computed(function(): string
				return activity.summary(sent_tools[i]:get())
			end)
		end
		local function group(compact: boolean): Node
			local animate = not replayed
			replayed = true
			return activity.group {
				id = name(`sent_tools_{i}`),
				summary = summary(),
				items = sent_tools[i],
				open = sent_open[i],
				animate = animate,
				active = active,
				on_image = lightbox.open,
				on_file = turns_mod.open_file,
				compact = compact,
			}
		end
		return ui.presence(function()
			return if turns_mod.compact():get() then "compact" else "full"
		end, function(mode: string): Node
			if mode == "full" then
				return group(false)
			end
			return activity.work {
				id = name(`sent_work_{i}`),
				summary = summary(),
				worked = function(): string?
					local secs = sent_worked[i]:get()
					return if secs > 0 then activity.worked(secs) else nil
				end,
				open = ui.state(key(`sent_work_open_{i}`), false),
				active = active,
				group(true),
			}
		end, { w_full = true })
	end

	local function transcript(): Node
		local turns: { Node } = {}
		local nth = 0
		local forks = 0
		for at, entry in entries do
			if entry.fork then
				forks += 1
				table.insert(turns, fork_marker(name(if forks == 1 then "fork" else `fork_{forks}`), entry.fork))
				continue
			end
			local t = entry.turn :: data.Turn
			nth += 1
			table.insert(turns, spaced(turns_mod.prompt(ctx, t, nth), at == 1))
			table.insert(
				turns,
				spaced(
					turns_mod.reply(ctx, t, nth, {
						last = at == #entries,
						open = if nth == 1 then turn_open else nil,
						quiet = side,
					}),
					false,
					-- A reply that opens on its tool calls stands 12 off the
					-- prompt's strip; prose, 8 (top_gap_for).
					if turns_mod.opens_on_work(t) then "$zeron.space.12" else "$zeron.space.8"
				)
			)
		end
		-- A chat on another device shows its history once it has arrived.
		if loading then
			turns = { ui.show(ready, ui.column { w_full = true, turns }) }
		end
		-- The voice chat: the call on now, as it is said.
		local call = voice.live_turns(session, name)
		if call then
			table.insert(turns, call)
		end
		for i, text in sent_text do
			-- The reply as it streams: the chunks that have arrived, joined.
			local function reply(): string
				local upto = if sent_n:get() > i then #REPLY else streamed:get()
				return table.concat(REPLY, "", 1, math.min(upto, #REPLY))
			end
			table.insert(
				turns,
				ui.show(
					function()
						return sent_n:get() >= i
					end,
					ui.column {
						w_full = true,
						pt = "$zeron.space.16",
						gap = "$zeron.space.8",
						-- The prompt without its comments, which show as a badge
						-- under it (comments.rs extract_badge); what it carried
						-- over it; folded when long, its references as chips.
						ui.presence(function()
							return text:get()
						end, function(sent: string): Node
							return tr.user_bubble {
								id = name(`sent_turn_{i}`),
								text = (comments.read(sent)),
								attachments = sent_carried[i],
								on_attachment = turns_mod.open_attachment,
								on_visible = rail.visible(`sent_{i}`),
							}
						end, { w_full = true }),
						ui.presence(function()
							local _, notes = comments.read(text:get())
							return if notes then text:get() else nil
						end, function(): Node
							local _, notes = comments.read(text:peek())
							local items: { message_badge.Item } = {}
							for _, n in notes or {} do
								table.insert(items, { where = n.where, tag = n.tag, body = n.body })
							end
							return ui.row {
								w_full = true,
								justify = "end",
								kit.message_badge {
									id = name(`sent_comments_{i}`),
									icon = "chat-round-line",
									label = comments.label(#items),
									items = items,
								},
							}
						end, { w_full = true }),
						tr.turn {
							ui.show(function()
								return #sent_tools[i]:get() > 0
							end, sent_work(i)),
							kit.markdown.view { text = reply, key = key(`reply_{i}`), links = links.links, veil = true },
							meta = tr.meta { copy = reply },
							working = ui.show(
								function()
									return sent_n:get() == i
										and streamed:get() < #REPLY
										and working:get()
										and not sending:get()
								end,
								tr.working {
									id = name(`sent_working_{i}`),
									seed = session or "chat",
									queued = function()
										return queued:get()
									end,
									-- Waiting on a Cloud machine.
									label = function(): string?
										return if session then cloud.working_label(session) else nil
									end,
								}
							),
						},
					}
				)
			)
		end
		return kit.scroll {
			grow = 1,
			w_full = true,
			label = "Transcript",
			fade = 24,
			py = "$zeron.space.8",
			-- At the end while a reply streams (should_anchor_live_stream); a
			-- tool row opened after extends below, the view staying put. Not
			-- while a sent prompt is held: the glide moves the view then, and
			-- the pin takes over once the reply has used the runway up.
			follow = hold.follow(working),
			offset = hold_offset,
			at_end = at_end,
			runway = hold.runway,
			on_measure = hold.measure,
			over = {
				rail.node(name("rail")),
				ui.row {
					absolute = true,
					left = 0,
					right = 0,
					bottom = 12,
					justify = "center",
					pointer_events = "none",
					ui.show(
						function()
							return not at_end:get()
						end,
						kit.jump {
							id = name("jump"),
							on_click = function()
								hold_offset:set(math.huge)
							end,
						}
					),
				},
				(loading and tr.loader(name("transcript_loader"), loading) or nil) :: Node,
			},
			centred {
				ref = content_ref,
				px = "$zeron.space.16",
				py = "$zeron.space.12",
				turns,
			},
		}
	end

	local settings_of = composer_prefs()
	local todo_dismissed = ui.state(key("todo_dismissed"), false)
	local offline = function()
		return require("./account").connection:get() == "offline"
	end
	-- A session waiting on input asks its questions in the composer's
	-- place until they are answered or closed; the answers go as its next
	-- message, the draft is as it was.
	local questions = if session and record and record.status == "input" then data.QUESTIONS[session] else nil
	local asks = ui.state(key("asks"), questions ~= nil)
	local asked: composer.Ask? = if questions
		then {
			id = session or "ask",
			questions = questions :: any,
			on_answer = function(answers: { { string } })
				asks:set(false)
				local lines: { string } = {}
				for i, q in questions :: { any } do
					table.insert(lines, `{q.header}: {table.concat(answers[i] or {}, ", ")}`)
				end
				send_text(table.concat(lines, "\n"))
			end,
			on_dismiss = function()
				asks:set(false)
			end,
		}
		else nil
	local function asking(): composer.Ask?
		return if asks:get() then asked else nil
	end
	-- The conversation: the transcript, the todo tray and the docked
	-- composer, under the titlebar's band. The composer takes the
	-- transcript's reading width (Appearance's Conversation width, 736 by default), the tray 16 in from
	-- each of its sides; both narrow with the column, in layout.
	local harness = if record then record.harness else "claude"
	return ui.column {
		id = name("conversation"),
		ref = column_ref,
		relative = true,
		w_full = true,
		h_full = true,
		pt = chrome.top,
		items = "stretch",
		transcript(),
		centred({
			px = "$zeron.space.16",
			pb = "$zeron.space.12",
			items = "stretch",
			-- A live call's tray, over every conversation's composer.
			voice.tray(name),
			ui.column {
				shrink = 0,
				items = "stretch",
				kit.composer {
					id = name("composer"),
					input_ref = if main and session then state.composer_field(session) else nil,
					w = "100%",
					docked = true,
					-- What failed, or that it waits offline, then the todo tray
					-- (dismissed while the turn rests, until the agent writes
					-- another), over the queue.
					error = failure,
					offline = offline,
					todo = ui.show(
						function()
							return not todo_dismissed:get()
						end,
						ui.column {
							px = "$zeron.space.16",
							mb = T.pull(kit.tray.OVERLAP),
							items = "stretch",
							kit.tray.todo {
								id = name("todo_tray"),
								items = data.todos(session),
								live = working,
								open = todo_open,
								on_dismiss = function()
									todo_dismissed:set(true)
								end,
								w = "100%",
							},
						}
					),
					send_with = settings_of.send_with,
					show_model = settings_of.show_model,
					voice = settings_of.voice,
					dictation_key = settings_of.dictation_key,
					dictation_outcome = dictation_outcome,
					-- One row while the draft fits it, opening out as it grows.
					compact = "auto",
					branch = "main",
					checkout = "~/zeron/zgx",
					-- The session's pull request, opening beside it.
					pr = record and record.pr and record.pr.number,
					pr_tone = record and record.pr and record.pr.state,
					on_pr = record and record.pr and function()
						if state.hooks.open_session_pr then
							state.hooks.open_session_pr(record.key)
						end
					end,
					context = context,
					context_total = 200000,
					usage = usage.chip(harness, name("usage")),
					-- What the agent may do unasked, and plan mode where it has
					-- one (Cursor runs with full access alone).
					access = kit.access.chip {
						id = name("access"),
						mode = ui.state(key("access"), "full_access" :: kit_access.Mode),
						modes = if harness == "cursor" then { "full_access" } else nil,
						plan = if harness == "cursor" then nil else ui.state(key("plan"), false),
						agent = if harness == "cursor" then "Cursor" else nil,
					},
					value = draft,
					working = working,
					sending = sending,
					model = model_label,
					effort = effort_label,
					on_model = ui.toggle(picker_open),
					model_picker = function(chip: Node): Node
						return model_picker(name("zeron_picker"), name("zeron_models"), chip, {
							open = picker_open,
							model = model,
							effort = effort,
							fast = fast,
							context = context_window,
							favorites = favorites,
						})
					end,
					references = references.for_draft(draft, attachments, actions),
					markdown = true,
					chips = "@/$",
					chip_label = references.chip_label,
					chip_icon = references.chip_icon,
					chip_tooltip = references.chip_tooltip,
					on_paste = references.resolve_paste,
					-- A thread the canvas started: its composer glides down from there
					-- (one the sidebar opens shows its own at once).
					layout_id = if main and fresh then "zeron_composer" else nil,
					ask = if questions then asking else nil,
					on_open_attachment = function(a: composer.Attachment)
						open_image(a.name, a.src)
					end,
					-- Claude Code takes a message mid-turn; the others at the
					-- next turn.
					steers = harness == "claude",
					editing = editing,
					on_edit_queued = edit_queued,
					on_save_edit = save_edit,
					on_cancel_edit = restore,
					on_move_queued = move_queued,
					on_open_queued = function(f: tray.QueuedFile)
						open_image(f.name, f.src)
					end,
					on_send = send_draft,
					comments = function()
						return #staged:get()
					end,
					-- A comment on a file's line waits for its file's save.
					held = function()
						return comments.held(session or "chat")
					end,
					on_stop = function()
						stop_run()
					end,
					on_queue = queue_draft,
					queue = queue,
					on_remove_queued = function(id: string)
						local rest = {}
						for _, q in queue:peek() do
							if q.id ~= id then
								table.insert(rest, q)
							end
						end
						queue:set(rest)
					end,
					on_send_queued = function(id: string)
						for i, q in queue:peek() do
							if q.id == id then
								local rest = table.clone(queue:peek())
								table.remove(rest, i)
								queue:set(rest)
								stream_run += 1
								working:set(false)
								send_text(q.text)
								return
							end
						end
					end,
					attachments = attachments,
					on_add = attach,
					on_remove_attachment = function(id: string)
						local rest = {}
						for _, a in attachments:peek() do
							if a.id ~= id then
								table.insert(rest, a)
							end
						end
						attachments:set(rest)
					end,
				},
			},
		}, 0),
		-- Over the transcript and the composer.
		if main and session then session_card.view(session) else nil,
	}
end

-- Session `session`'s draft (Files' "Add to chat" writes into it).
function M.draft(session: string): State<string>
	return ui.state(`{session}:draft`, "")
end
state.hooks.draft = M.draft

-- A call's full output (FETCH_TOOL_BLOB): the sample's sidecars, a moment
-- after it is asked for.
activity.fetch = function(ref: string, done: (text: string?) -> ())
	ui.after(600, function()
		done(data.blob(ref))
	end)
end

-- Stages `text` on the new-session canvas, in `project`, under a draft
-- already there (a pull request's handoff: shell.rs StartPullRequestSession).
function M.stage(text: string, project: string)
	local draft = ui.state("new:draft", "")
	local before = string.gsub(draft:peek(), "%s+$", "")
	draft:set(if before == "" then text else `{before}\n\n{text}`)
	ui.state("new:project", "zgx"):set(project)
end

-- The new-session canvas's project from now (a project group's +, a
-- project just added), and its device (a No project group's +).
function M.start_in(project: string, device: string?)
	ui.state("new:project", "zgx"):set(project)
	if device then
		ui.state("new:device", "MacBook Pro"):set(device)
	end
end
state.hooks.canvas_project = M.start_in

-- The new-session canvas's artwork (shell.rs new_thread_background,
-- new_thread_background_mask.rs, new_thread_background_effects.rs): the
-- user's image across the canvas's top, 72% of its height at most 760,
-- cropped to cover it; at 84% while the surfaces are frosted. One layer
-- shader draws the rest as it composites (the engine's: nothing runs as
-- it rests or as the window resizes):
-- - its effect, in the image's own pixels: Dither (2×2 cells quantized on
--   a 4×4 Bayer), ASCII (5×7 glyphs in 6×8 cells by ink density, coloured,
--   40% over the image at 60%), Halftone (4×4 dots by luminance, the same
--   mix), Scanlines (every third line to 52%, lifted instead in daylight);
-- - its fade from its top to its foot (a smoothstep over its height);
-- - the composer's feathered cutout: around the composer, from its top
--   to the artwork's foot, the artwork clears (radius 26, 8 clear of it,
--   feathered over 52% of the height within 120 to 280), and shows there
--   at half strength (the reveal pass), so the composer sits on the
--   canvas.
-- The composer's place is the canvas's centring of it, from the composer's
-- height (`params[0]`: the top inset, that height, its width at most and
-- the canvas's side inset).
local ART = 0.72
local ART_MAX = 760
local EFFECTS = { None = 0, Dither = 1, ASCII = 2, Halftone = 3, Scanlines = 4 }
-- The sample artwork's size in pixels (the effects' cells are its own).
local ART_SIZE: { [string]: { number } } = { ["images/shadow.jpg"] = { 720, 480 } }
local artwork: LayerShader? = nil
local ARTWORK_WGSL = [[
fn art_luma(c: vec3<f32>) -> f32 {
	return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}
// Source pixel `q`'s colour: the layer at its centre, kept in the art.
fn art_at(q: vec2<f32>, o: vec2<f32>, k: f32, box: vec2<f32>) -> vec4<f32> {
	return zgx_sample(clamp(o + (q + 0.5) * k, vec2<f32>(0.5), box - 0.5));
}
fn art_glyph(i: u32) -> u32 {
	var g = array<u32, 70>(
		0u, 0u, 0u, 0u, 0u, 0u, 0u,
		0u, 0u, 0u, 0u, 0u, 4u, 0u,
		0u, 4u, 0u, 0u, 4u, 0u, 0u,
		0u, 0u, 0u, 14u, 0u, 0u, 0u,
		0u, 0u, 14u, 0u, 14u, 0u, 0u,
		0u, 4u, 4u, 31u, 4u, 4u, 0u,
		0u, 21u, 14u, 31u, 14u, 21u, 0u,
		10u, 10u, 31u, 10u, 31u, 10u, 10u,
		17u, 2u, 4u, 4u, 8u, 16u, 17u,
		14u, 17u, 23u, 21u, 23u, 16u, 14u
	);
	return g[min(i, 69u)];
}
fn layer(input: LayerInput) -> vec4<f32> {
	let p = input.p;
	let size = input.size;
	let at = input.params[0];
	let fx = input.params[1];
	let art = min(size.y * 0.72, 760.0);
	var c = input.color;
	let effect = u32(fx.x + 0.5);
	if (effect > 0u && fx.z > 0.0 && fx.w > 0.0 && p.y < art) {
		let box = vec2<f32>(size.x, art);
		let k = max(size.x / fx.z, art / fx.w);
		let o = (box - vec2<f32>(fx.z, fx.w) * k) * 0.5;
		let s = max(floor((p - o) / k), vec2<f32>(0.0));
		let light = fx.y > 0.5;
		let paper = select(0.0, 1.0, light);
		if (effect == 1u) {
			var bayer = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			let cell = floor(s / 2.0);
			let col = art_at(cell * 2.0 + 1.0, o, k, box);
			let b = bayer[(u32(cell.y) % 4u) * 4u + u32(cell.x) % 4u];
			let peak = max(col.r, max(col.g, col.b));
			let gain = select(0.08, 1.0 / max(peak, 0.004), peak > (b + 0.5) / 16.0);
			c = vec4<f32>(col.rgb * gain, col.a);
		} else if (effect == 2u) {
			let centre = vec2<f32>(floor(s.x / 6.0) * 6.0 + 3.0, floor(s.y / 8.0) * 8.0 + 4.0);
			let glyph = art_at(centre, o, k, box);
			var ink = art_luma(glyph.rgb);
			if (light) { ink = 1.0 - ink; }
			let index = min(u32(sqrt(max(ink, 0.0)) * 9.0), 9u);
			let x = u32(s.x) % 6u;
			let y = u32(s.y) % 8u;
			var on = false;
			if (x < 5u && y < 7u) {
				on = (art_glyph(index * 7u + y) & (1u << (4u - x))) != 0u;
			}
			let mark = select(vec3<f32>(paper), glyph.rgb, on);
			c = vec4<f32>(c.rgb * 0.6 + mark * 0.4, c.a);
		} else if (effect == 3u) {
			let cell = floor(s / 4.0) * 4.0;
			var l = art_luma(art_at(cell, o, k, box).rgb);
			if (light) { l = 1.0 - l; }
			let radius = 2.0 * (0.3 + 0.7 * sqrt(max(l, 0.0)));
			let dot_colour = art_at(cell + 2.0, o, k, box);
			let cover = clamp(radius + 0.5 - length(s - cell - 1.5), 0.0, 1.0) * dot_colour.a;
			let mark = dot_colour.rgb * cover + vec3<f32>(paper) * (1.0 - cover);
			c = vec4<f32>(c.rgb * 0.6 + mark * 0.4, c.a);
		} else {
			let gain = select(1.0, 0.52, u32(s.y) % 3u == 0u);
			c = vec4<f32>(select(c.rgb * gain, c.rgb + (1.0 - c.rgb) * (1.0 - gain), light), c.a);
		}
	}
	let fade = smoothstep(0.0, art, art - p.y);
	var cut = 1.0;
	if (at.y > 0.0) {
		let w = min(at.z, size.x - 2.0 * at.w);
		let column = at.y + 60.0;
		let top = at.x + (size.y - at.x - column) * 0.5 + 30.0;
		let bottom = max(top + at.y, art);
		let half = vec2<f32>(w, bottom - top) * 0.5;
		let centre = vec2<f32>(size.x * 0.5, top + half.y);
		let radius = min(26.0, min(half.x, half.y));
		let q = abs(p - centre) - half + radius;
		let d = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - radius;
		cut = smoothstep(0.0, clamp(art * 0.52, 120.0, 280.0), d - 8.0);
	}
	let shown = min(cut, fade);
	return vec4<f32>(c.rgb, c.a * (shown + 0.5 * fade * (1.0 - shown)));
}
]]
local function background(id: string, composer_h: State<number>): Node
	local look = state.look
	local prefs = require("./settings").pref
	local pref = prefs.canvas_background
	if not artwork then
		artwork = ui.layer_shader(ARTWORK_WGSL)
	end
	return ui.presence(pref, function(src: string): Node
		if src == "" then
			return ui.div {}
		end
		local size = ART_SIZE[src] or { 2048, 1365 }
		-- Its parameters follow the composer's height, the layout's top
		-- inset, the effect and the appearance: set as they change.
		local hero = ui.ref()
		ui.effect(function()
			local el = hero:get()
			local effect = EFFECTS[prefs.canvas_effect:get()] or 0
			local light = effect ~= EFFECTS.Dither and not require("@kit/look").is_dark()
			local values = {
				layerParam0 = chrome.top_px(),
				layerParam1 = composer_h:get(),
				layerParam2 = prefs.conversation_width:get(),
				layerParam3 = 16,
				layerParam4 = effect,
				layerParam5 = if light then 1 else 0,
				layerParam6 = size[1],
				layerParam7 = size[2],
			}
			if el and el.mounted then
				anime.utils.set(el, values)
			end
		end)
		return ui.div {
			id = id,
			ref = hero,
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			overflow = "hidden",
			pointer_events = "none",
			opacity = function()
				return if look.surface:get() == "opaque" then 1 else 0.84
			end,
			layer_shader = artwork,
			-- Placed as Adjust background left it: zoomed, and moved within
			-- the room the zoom leaves.
			ui.div {
				id = `{id}_image`,
				relative = true,
				w_full = true,
				h = `{ART * 100}%`,
				max_h = ART_MAX,
				overflow = "hidden",
				ui.image {
					id = `{id}_art`,
					src = src,
					label = "",
					absolute = true,
					fit = "cover",
					w = function(): string
						return `{prefs.canvas_placement:get().zoom * 100}%`
					end,
					h = function(): string
						return `{prefs.canvas_placement:get().zoom * 100}%`
					end,
					left = function(): string
						local p = prefs.canvas_placement:get()
						return `{(p.x - 1) * (p.zoom - 1) * 50}%`
					end,
					top = function(): string
						local p = prefs.canvas_placement:get()
						return `{(p.y - 1) * (p.zoom - 1) * 50}%`
					end,
				},
			},
		}
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		pointer_events = "none",
		enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) },
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.SLOW) },
	})
end

-- The voice stage shows the same artwork, without the canvas's cutout (no
-- composer under it: a height of 0).
function M.artwork(id: string): Node
	return background(id, ui.state("voice_artwork_composer_h", 0))
end
-- First-run setup shows it too, cleared around its column (`height`).
function M.artwork_around(id: string, height: State<number>): Node
	return background(id, height)
end

-- The new-session canvas (Zeron's): the composer in the middle of the
-- column; above its trailing edge, where the session will run (the project,
-- the device); under its leading edge, its checkout and branch. Sending
-- starts the session with that message and hands it to `open`.
function M.canvas(prefix: string?, open: (session: string) -> ()): Node
	local function name(id: string): string
		return if prefix then `{prefix}_{id}` else id
	end
	local draft = ui.state("new:draft", "")
	local project = ui.state("new:project", "zgx")
	local device = ui.state("new:device", "MacBook Pro")
	-- "local" (the ref's own worktree, or this checkout) or "worktree" (a
	-- new one from the ref).
	local checkout = ui.state("new:checkout", "local")
	local branch = ui.state("new:branch", "main")
	local model = ui.state("new:model", "opus")
	local picker_open = ui.state("new:picker_open", false)
	local effort = ui.state("new:effort", 3)
	local fast = ui.state("new:fast", false)
	local context_window = ui.state("new:context_window", "Standard")
	local favorites = ui.state("new:favorites", {} :: { string })
	local composer_h = ui.state(name("new_composer_h"), 0)

	-- A chip: 12 medium, quiet, its icon 12; its picker under it
	-- (pickers.rs: searchable where the list is long).
	local function chip(id: string, icon: string, label: () -> string, card: { [string]: any }): Node
		local open_menu = ui.state(`new:{id}_open`, false)
		card.id = name(`new_{id}_menu`)
		card.open = open_menu
		card.anchor = ui.button {
			id = name(`new_{id}`),
			h = 24,
			px = "$zeron.space.8",
			py = 0,
			gap = "$zeron.space.6",
			items = "center",
			rounded = "$zeron.radius.6",
			bg = T.clear,
			hover = { bg = T.glass_hover },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ui.toggle(open_menu),
			kit.icon { name = icon :: any, size = 12, color = T.tertiary },
			kit.text.text { label, size = "sm", weight = "medium", color = T.tertiary, line = false },
		}
		return picker_card.card(card :: any)
	end
	local function rows_of(list: { string }, icon: string?): { picker_card.Row }
		local out: { picker_card.Row } = {}
		for _, c in list do
			table.insert(out, { key = c, label = c, icon = icon :: any })
		end
		return out
	end
	-- The project: any of them, or none ("Don't work in a project").
	local project_chip = chip("project", "folder", function()
		local p = project:get()
		return if p == "" then "No project" else p
	end, {
		search = "Search projects…",
		w = 240,
		rows = function(): { picker_card.Row }
			local out: { picker_card.Row } = {}
			for _, p in data.PROJECTS do
				table.insert(out, { key = p, label = p, project = p })
			end
			return out
		end,
		top = { key = "", label = "Don't work in a project", icon = "close" },
		value = function()
			return project:get()
		end,
		on_pick = function(key: string)
			project:set(key)
		end,
		empty = function(query: string): string
			return if query == "" then "No projects yet." else "No projects match."
		end,
	})
	local device_chip = chip("device", "monitor", function()
		return device:get()
	end, {
		search = "Search devices…",
		rows = function()
			return rows_of(data.DEVICES, "monitor")
		end,
		value = function()
			return device:get()
		end,
		on_pick = function(key: string)
			device:set(key)
		end,
		empty = function(): string
			return "No devices match."
		end,
	})
	-- The checkout: the ref's worktree (or this checkout) or a new one.
	local function ref_worktree(): boolean
		for _, r in data.REFS do
			if r.name == branch:get() then
				return r.worktree == true
			end
		end
		return false
	end
	local function local_label(): string
		return if ref_worktree() then "Current worktree" else "Current checkout"
	end
	local checkout_chip = chip("checkout", "worktree", function()
		return if checkout:get() == "worktree" then "New worktree" else local_label()
	end, {
		w = 220,
		rows = function(): { picker_card.Row }
			return {
				{ key = "local", label = local_label(), icon = if ref_worktree() then "worktree" else "folder" },
				{ key = "worktree", label = "New worktree", icon = "worktree" },
			}
		end,
		value = function()
			return checkout:get()
		end,
		on_pick = function(key: string)
			checkout:set(key)
		end,
	})
	-- The ref: "From <ref>" when a new worktree comes off it.
	local branch_chip = chip("branch", "git-branch", function()
		local b = branch:get()
		return if checkout:get() == "worktree" then `From {b}` else b
	end, {
		search = "Search refs…",
		w = 280,
		cap = 300,
		noun = "refs",
		rows = function(): { picker_card.Row }
			local out: { picker_card.Row } = {}
			for _, r in data.REFS do
				table.insert(out, {
					key = r.name,
					label = r.name,
					icon = (if r.tag then "tag" else "git-branch") :: any,
					tag = if r.current then "current" elseif r.worktree then "worktree" else nil,
				})
			end
			return out
		end,
		value = function()
			return branch:get()
		end,
		on_pick = function(key: string)
			branch:set(key)
		end,
		empty = function(): string
			return "No refs found."
		end,
	})

	local function send()
		local text = draft:peek()
		if text == "" then
			return
		end
		-- Named from its first message (the sample's stand-in for General's
		-- Thread naming: the session's agent or the model chosen).
		local title = if #text > 48 then string.sub(text, 1, 47) .. "…" else text
		local s = data.add_session(title, project:peek(), device:peek())
		ui.state(`{s.key}:autosend`, ""):set(text)
		draft:set("")
		open(s.key)
	end

	local settings_of = composer_prefs()
	local function label(): string
		for _, m in MODELS do
			if m.id == model:get() then
				return m.label
			end
		end
		return ""
	end

	return ui.column {
		id = name("canvas"),
		relative = true,
		w_full = true,
		h_full = true,
		pt = chrome.top,
		items = "center",
		justify = "center",
		px = "$zeron.space.16",
		background(name("canvas_background"), composer_h),
		-- Zeron's new-chat composer: 768 outside (`max-w-3xl`), its pill 16 in
		-- from each side, as the thread's composer is.
		ui.column {
			w_full = true,
			max_w = require("./settings").pref.conversation_width,
			gap = "$zeron.space.6",
			ui.row {
				w_full = true,
				justify = "end",
				gap = "$zeron.space.4",
				project_chip,
				device_chip,
			},
			-- Its height places the artwork's cutout around it: a sliver
			-- beside it as tall, which no width change resizes.
			ui.row {
				w_full = true,
				items = "stretch",
				ui.div {
					w = 0,
					shrink = 0,
					on_resize = function(size: Size)
						composer_h:set(size.h)
					end,
				},
				kit.composer {
					id = name("new_composer"),
					input_ref = if prefix == nil then state.composer_field("new") else nil,
					w = "100%",
					value = draft,
					send_with = settings_of.send_with,
					show_model = settings_of.show_model,
					voice = settings_of.voice,
					dictation_key = settings_of.dictation_key,
					dictation_outcome = dictation_outcome,
					placeholder = "What should we work on?",
					markdown = true,
					chips = "@/$",
					chip_label = references.chip_label,
					chip_icon = references.chip_icon,
					chip_tooltip = references.chip_tooltip,
					on_paste = references.resolve_paste,
					-- It glides down into the thread it starts.
					layout_id = if prefix == nil then "zeron_composer" else nil,
					model = label,
					effort = function()
						return traits(model, effort, context_window, fast)
					end,
					on_model = ui.toggle(picker_open),
					model_picker = function(c: Node): Node
						return model_picker(name("new_picker"), name("new_models"), c, {
							open = picker_open,
							model = model,
							effort = effort,
							fast = fast,
							context = context_window,
							favorites = favorites,
						})
					end,
					on_send = send,
					-- Before a conversation: only the commands that need none.
					references = references.for_draft(draft, nil, {
						model = function()
							picker_open:set(true)
						end,
						resume = function()
							state.palette:set(true)
						end,
						settings = function()
							state.settings:set(true)
						end,
					}),
				},
			},
			ui.row {
				w_full = true,
				gap = "$zeron.space.4",
				checkout_chip,
				branch_chip,
			},
		},
	}
end

-- The fade-through when navigation moves the conversation's column
-- (composer_dock/panel_handoff.rs): from the canvas to a chat whose
-- session card stands beside it, or back, the conversation fades out by
-- 18% of 320 ms, its column switches unseen, and the next fades in from
-- 26%, rather than sliding sideways. A thread the canvas starts glides
-- down instead; chats in the same column swap at once. `handoff` counts
-- such navigations: a view keyed on it fades (`HANDOFF_OUT`, `_IN`).
M.HANDOFF = 320
M.HANDOFF_OUT = {
	opacity = 0,
	duration = kit.motion.d(M.HANDOFF * 0.18),
	ease = kit.motion.EASE_IN_OUT,
} :: ElementParams
M.HANDOFF_IN = {
	opacity = { 0, 1 },
	delay = kit.motion.d(M.HANDOFF * 0.08),
	duration = kit.motion.d(M.HANDOFF * 0.74),
	ease = kit.motion.EASE_IN_OUT,
} :: ElementParams
local function column_of(session: string): string
	-- The canvas keeps no room for the card; a chat does where the column
	-- fits it (the columns as they are now, not followed).
	local s = state.chat
	local column = s.viewport:peek() - s.w.sidebar:peek() - s.w.right:peek() - s.w.files:peek()
	local docked = session ~= "new" and column >= session_card.FIT and not state.card_hidden:peek()
	return if docked then "beside the card" else "centred"
end
local handoffs = 0
local handed: string? = nil
M.handoff = ui.computed(function(): number
	local now = state.session:get()
	local was = handed
	handed = now
	local record = data.session(now)
	if was and was ~= now and column_of(was) ~= column_of(now) and not (record and record.fresh) then
		handoffs += 1
	end
	return handoffs
end)

return M
