-- The conversation: the transcript (the sent-turn hold gliding a prompt
-- to the top, the reply streaming into the runway under it), the todo tray
-- and the composer docked under it with its model picker.
local T = require("../theme")
local kit = require("@kit")
local tray = require("@kit/tray")
local activity = require("@kit/activity")
local lightbox = require("@kit/lightbox")
local composer = require("@kit/composer")
local data = require("./data")
local references = require("./references")
local session_card = require("./session_card")
local chrome = require("./chrome")
local state = require("./state")
local comments = require("./comments")
local message_badge = require("@kit/message_badge")
local ps = require("@kit/panel_shell")

local MODELS = data.MODELS
local REPLY = data.REPLY
local TODOS = data.TODOS
-- What a sent turn's agent does before it answers.
local LIVE_TOOLS: { data.Tool } = {
	{
		icon = "magnifer",
		label = "Searched",
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
		icon = "terminal",
		label = "Ran",
		detail = "cargo test -p zgui-script --test zeron_app",
		call = "cargo test -p zgui-script --test zeron_app",
		output = "running 24 tests\ntest result: ok. 24 passed; 0 failed\n",
	},
}
local tr = kit.transcript

local M = {}

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

-- A conversation. `session` keys its states (two panes showing one
-- session share its draft and its turns) and, with `prefix`, its ids (two
-- panes never share an id); without them, the classic layout's one. A side
-- chat (`fork`: the session it forked) shows that session's turns, then
-- where it forked, then its own.
function M.view(session: string?, prefix: string?, fork: string?): Node
	local function key(name: string): string
		return if session then `{session}:{name}` else name
	end
	local function name(id: string): string
		return if prefix then `{prefix}_{id}` else id
	end
	-- A session started in this window has only what was sent to it.
	local record = if session then data.session(session) else nil
	local fresh = record ~= nil and record.fresh == true
	local draft = ui.state(key("draft"), "")
	local working = ui.state(key("working"), false)
	local todo_open = ui.state(key("todo_open"), false)
	local model = ui.state(key("model"), "opus")
	local effort = ui.state(key("effort"), 3)
	local fast = ui.state(key("fast"), false)
	local favorites = ui.state(key("favorites"), {} :: { string })
	local picker_open = ui.state(key("picker_open"), false)
	local turn_open = ui.state(key("turn_open"), true)
	-- How full the context window is (the footer's ring): each turn adds.
	local context = ui.state(key("context"), (if fresh then 0.02 else 0.34) :: number?)

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
	local stream_run = 0
	local queued_made = 0
	local send_text: (text: string) -> ()
	local function send_next()
		local list = queue:peek()
		if #list > 0 then
			local rest = table.clone(list)
			local first = table.remove(rest, 1) :: tray.Queued
			queue:set(rest)
			send_text(first.text)
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
		stream_run += 1
		working:set(false)
	end
	send_text = function(text: string)
		if text == "" or sent_n:peek() >= #sent_text then
			return
		end
		attachments:set {}
		stream_run += 1
		local this = stream_run
		hold.send()
		local n = sent_n:peek() + 1
		sent_text[n]:set(text)
		sent_n:set(n)
		streamed:set(0)
		working:set(true)
		local tools = sent_tools[n]
		tools:set {}
		sent_open[n]:set(true)
		-- The calls arrive one after another, each running a moment before
		-- it is done; the reply streams once they are.
		for k, call in LIVE_TOOLS do
			local arrive = 300 + (k - 1) * 600
			ui.after(arrive, function()
				if stream_run == this then
					tools:push {
						id = `live{n}_{k}`,
						icon = call.icon,
						label = call.label,
						detail = call.detail,
						file = call.file,
						call = call.call,
						output = call.output,
						status = "running",
					}
				end
			end)
			ui.after(arrive + 400, function()
				if stream_run == this then
					tools:set_key({ k, "status" }, "done")
				end
			end)
		end
		local reply_at = 300 + #LIVE_TOOLS * 600
		for i = 1, #REPLY do
			ui.after(reply_at + (i - 1) * 400, function()
				if stream_run == this then
					streamed:set(i)
					if i == #REPLY then
						working:set(false)
						context:set(math.min((context:peek() or 0) + 0.06, 1))
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
		table.insert(list, { id = `q{queued_made}`, text = text, attachments = #attachments:peek() })
		queue:set(list)
		draft:set("")
		attachments:set {}
	end
	local attached = 0
	local function attach()
		attached += 1
		local list = table.clone(attachments:peek())
		local image = attached % 2 == 1
		table.insert(list, {
			id = `a{attached}`,
			name = if image then `Screenshot {attached}.png` else "panel_layout.rs",
			kind = (if image then "image" else "file") :: "image" | "file",
		})
		attachments:set(list)
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
		for _, m in MODELS do
			if m.id == model:get() then
				return (m.levels or {})[effort:get()] or "Default"
			end
		end
		return ""
	end

	-- Turns space themselves (24 above each) instead of a column gap: a hidden
	-- slot must take no room, and the engine keeps a gap around hidden children.
	-- Zeron's row gaps (transcript.rs top_gap_for): 16 where a turn starts,
	-- 8 from a prompt to its reply.
	local function spaced(node: Node, first: boolean?, gap: Length?): Node
		return ui.column { w_full = true, pt = if first then 0 else gap or "$zeron.space.16", node }
	end

	local function transcript(): Node
		local turns: { Node } = {}
		local history = if fork then data.turns(fork) elseif fresh then {} else data.turns(session)
		for i, t in history do
			table.insert(turns, spaced(tr.user_bubble { text = t.user }, i == 1))
			local tools: { Node } = {}
			if t.tools then
				local items: { activity.Activity } = {}
				for k, tool in t.tools do
					table.insert(items, {
						id = `t{i}_{k}`,
						icon = tool.icon,
						label = tool.label,
						detail = tool.detail,
						file = tool.file,
						call = tool.call,
						output = tool.output,
						hunks = tool.hunks,
						images = tool.images,
					})
				end
				table.insert(
					tools,
					activity.group {
						id = name(`turn_{i}_tools`),
						-- What the tools did, counted as Zeron says it: "Read 2 files
						-- · Ran 1 command".
						summary = activity.summary(items),
						open = if i == 1 then turn_open else ui.state(key(`turn_open_{i}`), false),
						items = items,
						on_image = lightbox.open,
					}
				)
			end
			table.insert(
				turns,
				spaced(
					tr.turn {
						tools[1],
						kit.markdown.view { text = t.reply },
						if t.working
								and i == #history
								and not fork
							then tr.working { label = t.working }
							else tr.actions(),
					},
					false,
					-- A reply that opens on its tool calls stands 12 off the
					-- prompt; prose, 8.
					if tools[1] then "$zeron.space.12" else "$zeron.space.8"
				)
			)
		end
		if fork then
			local source = data.session(fork)
			table.insert(turns, fork_marker(name("fork"), if source then source.title else "the conversation"))
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
						tr.user_bubble {
							id = name(`sent_turn_{i}`),
							-- The prompt without its comments, which show as a
							-- badge under it (comments.rs extract_badge).
							text = function()
								return (comments.read(text:get()))
							end,
						},
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
							ui.show(
								function()
									return #sent_tools[i]:get() > 0
								end,
								activity.group {
									id = name(`sent_tools_{i}`),
									summary = ui.computed(function(): string
										return activity.summary(sent_tools[i]:get())
									end),
									items = sent_tools[i],
									open = sent_open[i],
									animate = true,
									-- Until the reply is done, the turn works on it.
									active = function()
										return sent_n:get() == i and streamed:get() < #REPLY and working:get()
									end,
								}
							),
							kit.markdown.view { text = reply, key = key(`reply_{i}`) },
							ui.show(
								function()
									return sent_n:get() == i and streamed:get() < #REPLY
								end,
								tr.working {
									label = function()
										return if streamed:get() == 0 then "Working" else "Writing"
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
			-- tool row opened after extends below, the view staying put.
			follow = working,
			offset = hold_offset,
			at_end = at_end,
			runway = hold.runway,
			on_measure = hold.measure,
			over = {
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
			},
			ui.column {
				w_full = true,
				max_w = 768,
				px = "$zeron.space.16",
				py = "$zeron.space.12",
				self = "center",
				turns,
			},
		}
	end

	-- The conversation: the transcript, the todo tray and the docked
	-- composer, under the titlebar's band. The composer takes the
	-- transcript's reading width (736, Zeron's default), the tray 16 in from
	-- each of its sides; both narrow with the column, in layout.
	return ui.column {
		id = name("conversation"),
		relative = true,
		w_full = true,
		h_full = true,
		pt = chrome.top,
		items = "stretch",
		transcript(),
		ui.column {
			w_full = true,
			max_w = 768,
			self = "center",
			px = "$zeron.space.16",
			pb = "$zeron.space.12",
			shrink = 0,
			items = "stretch",
			ui.column {
				px = "$zeron.space.16",
				mb = T.pull(kit.tray.OVERLAP),
				items = "stretch",
				kit.tray.todo {
					id = name("todo_tray"),
					items = TODOS,
					live = true,
					open = todo_open,
					w = "100%",
				},
			},
			ui.column {
				shrink = 0,
				items = "stretch",
				kit.composer {
					id = name("composer"),
					w = "100%",
					docked = true,
					-- One row while the draft fits it, opening out as it grows.
					compact = "auto",
					branch = "main",
					checkout = "~/zeron/zgui",
					context = context,
					context_total = 200000,
					value = draft,
					working = working,
					model = model_label,
					effort = effort_label,
					on_model = ui.toggle(picker_open),
					model_picker = function(chip: Node): Node
						return kit.compact_picker {
							id = name("zeron_picker"),
							open = picker_open,
							anchor = chip,
							models = MODELS,
							model = model,
							effort = effort,
							fast = fast,
							favorites = favorites,
						}
					end,
					references = references.for_draft(draft, attachments, actions),
					on_send = send_draft,
					comments = function()
						return #staged:get()
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
		},
		-- Over the transcript and the composer.
		session_card.view(session, prefix),
	}
end

-- Session `session`'s draft (Files' "Add to chat" writes into it).
function M.draft(session: string): State<string>
	return ui.state(`{session}:draft`, "")
end

-- The new-session canvas's artwork (shell.rs new_thread_background): the
-- user's image across the canvas's top, 72% of the window's height at most
-- 760, cropped to cover it, fading out from its top to its bottom so the
-- composer sits on the canvas; at 84% while the surfaces are frosted. A
-- mask the engine draws: nothing runs while it rests.
local HERO = 576
local FADE_STEPS = 128
local fade: Bitmap? = nil
local function background(id: string): Node
	local look = state.look
	local pref = require("./settings").pref.canvas_background
	if not fade then
		fade = ui.bitmap(1, FADE_STEPS, function(_x: number, y: number): number
			return 1 - (y + 0.5) / FADE_STEPS
		end)
	end
	return ui.presence(pref, function(src: string): Node
		if src == "" then
			return ui.div {}
		end
		return ui.div {
			id = id,
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			h = HERO,
			overflow = "hidden",
			pointer_events = "none",
			opacity = function()
				return if look.surface:get() == "opaque" then 1 else 0.84
			end,
			mask = { fade :: Bitmap, w = 4096, h = HERO },
			ui.image { src = src, label = "", w_full = true, h_full = true, fit = "cover" },
		}
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) },
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.SLOW) },
	})
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
	local project = ui.state("new:project", "zgui")
	local device = ui.state("new:device", "MacBook Pro")
	local checkout = ui.state("new:checkout", "Local checkout")
	local branch = ui.state("new:branch", "main")
	local model = ui.state("new:model", "opus")
	local picker_open = ui.state("new:picker_open", false)
	local effort = ui.state("new:effort", 3)
	local fast = ui.state("new:fast", false)
	local favorites = ui.state("new:favorites", {} :: { string })

	-- A chip: 12 medium, quiet, its icon 12; a menu of choices under it.
	local function chip(id: string, icon: string, value: State<string>, choices: { string }): Node
		local open_menu = ui.state(`new:{id}_open`, false)
		local items: { any } = {}
		for _, c in choices do
			table.insert(items, {
				id = name(`new_{id}_{string.lower((string.gsub(c, "[^%w]+", "_")))}`),
				label = c,
				checked = function()
					return value:get() == c
				end,
				on_click = function()
					value:set(c)
				end,
			})
		end
		return kit.menu {
			id = name(`new_{id}_menu`),
			open = open_menu,
			items = items,
			w = 220,
			anchor = ui.button {
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
				kit.text.text {
					function()
						return value:get()
					end,
					size = "sm",
					weight = "medium",
					color = T.tertiary,
					line = false,
				},
			},
		}
	end

	local function send()
		local text = draft:peek()
		if text == "" then
			return
		end
		local title = if #text > 48 then string.sub(text, 1, 47) .. "…" else text
		local s = data.add_session(title, project:peek())
		ui.state(`{s.key}:autosend`, ""):set(text)
		draft:set("")
		open(s.key)
	end

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
		background(name("canvas_background")),
		-- Zeron's new-chat composer: 768 outside (`max-w-3xl`), its pill 16 in
		-- from each side, as the thread's composer is.
		ui.column {
			w_full = true,
			max_w = 736,
			gap = "$zeron.space.6",
			ui.row {
				w_full = true,
				justify = "end",
				gap = "$zeron.space.4",
				chip("project", "folder", project, data.PROJECTS),
				chip("device", "monitor", device, { "MacBook Pro", "Cloud" }),
			},
			kit.composer {
				id = name("new_composer"),
				w = "100%",
				value = draft,
				placeholder = "What should we work on?",
				model = label,
				effort = "High",
				on_model = ui.toggle(picker_open),
				model_picker = function(c: Node): Node
					return kit.compact_picker {
						id = name("new_picker"),
						open = picker_open,
						anchor = c,
						models = MODELS,
						model = model,
						effort = effort,
						fast = fast,
						favorites = favorites,
					}
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
			ui.row {
				w_full = true,
				gap = "$zeron.space.4",
				chip("checkout", "worktree", checkout, { "Local checkout", "New worktree" }),
				chip("branch", "git-branch", branch, { "main", "layout-root", "release/0.2.117" }),
			},
		},
	}
end

return M
