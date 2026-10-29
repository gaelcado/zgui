-- A conversation's turns as Zeron's transcript draws them (transcript.rs
-- rows_for_entry): the prompt (who sent it, what it carried, folded when
-- long), then the reply: the tool calls and thoughts in their group, the
-- subagents it spawned in rows of their own, the images it made, its prose,
-- how it ended in error, a question it asks; the working line while it
-- works, the retry under a send that never arrived. In compact mode the
-- turn's work folds under one header that says how long it worked. And the
-- message rail beside them, and a subagent's own transcript.
local kit = require("@kit")
local activity = require("@kit/activity")
local lightbox = require("@kit/lightbox")
local data = require("./data")
local state = require("./state")
local links = require("./links")

local tr = require("@kit/transcript")
local attachments = require("@kit/attachments")

local M = {}

-- Compact mode (Settings → General), as the transcript follows it.
function M.compact(): State<boolean>
	return require("./settings").pref.compact_mode
end

-- The rail's view of a conversation: which prompts show, and what a click
-- on a tick does.
export type Rail = {
	-- Its ticks, oldest first.
	ticks: State<{ tr.RailTick }>,
	-- The bubble of prompt `id` coming into view or leaving it.
	visible: (id: string) -> (visible: boolean, el: Element) -> (),
	lit: (id: string) -> boolean,
	pick: (id: string) -> (),
	-- The band the rail sits in (the transcript's view).
	band: Ref,
	node: (id: string) -> Node,
}

-- A conversation's rail (rail.rs): a prompt's tick is lit while its bubble
-- shows between the titlebar and the composer; with none showing (a long
-- reply), the prompt being read stays lit, the last one above the view. A
-- click glides the transcript (`offset`) to put that prompt 10 under the
-- view's top over 500 ms (SCROLL_GLIDE), the content's top found from
-- `content`.
function M.rail(key: string, ticks: State<{ tr.RailTick }>, offset: State<number>, content: Ref, column: Ref): Rail
	local seen = ui.state(`{key}:rail_seen`, {} :: { [string]: boolean })
	local above: { [string]: boolean } = {}
	local elements: { [string]: Element } = {}
	local band = ui.ref()
	local function lit(id: string): boolean
		local shown = seen:get()
		if shown[id] then
			return true
		end
		for _, v in shown do
			if v then
				return false
			end
		end
		-- Nothing shows: the last prompt above the view (the first if none).
		local last: string? = nil
		for i, t in ticks:get() do
			if above[t.id] or (i == 1 and last == nil) then
				last = t.id
			end
		end
		return last == id
	end
	local function visible(id: string): (boolean, Element) -> ()
		return function(on: boolean, el: Element)
			elements[id] = el
			local b = band:peek()
			above[id] = not on and b ~= nil and (el.y or 0) + (el.height or 0) <= (b.y or 0) + (b.height or 0) / 2
			if (seen:peek()[id] == true) ~= on then
				seen:set_key({ id }, on)
			end
		end
	end
	local function pick(id: string)
		local el, top, b = elements[id], content:peek(), band:peek()
		if not (el and el.mounted and top and b) then
			return
		end
		-- The scroll's padding (8) over the content, and the bubble 10 under
		-- the view's top (kit/own_turn's INSET).
		local now = (b.y or 0) + 8 - (top.y or 0)
		local target = math.max((el.y or 0) - (top.y or 0) + 8 - kit.own_turn.INSET, 0)
		offset:set(now);
		(anime.animate :: any)(offset, {
			value = target,
			duration = kit.motion.d(kit.motion.SCROLL_GLIDE),
			ease = kit.motion.EASE_IN_OUT,
		})
	end
	return {
		ticks = ticks,
		visible = visible,
		lit = lit,
		pick = pick,
		band = band,
		-- Down the view's left, 16 in, in the middle of its height; hidden
		-- below a 48rem (768) column.
		node = function(id: string): Node
			return ui.column {
				ref = band,
				absolute = true,
				left = 16,
				top = 0,
				bottom = 0,
				w = tr.RAIL_W,
				justify = "center",
				pointer_events = "none",
				ui.show(function()
					local c = column:get()
					return c ~= nil and (column.width or 0) >= 768
				end, tr.rail { id = id, ticks = ticks, lit = lit, on_pick = pick }),
			}
		end,
	}
end

-- What the transcript needs of the conversation around a turn.
export type Ctx = {
	session: string?,
	name: (id: string) -> string,
	key: (name: string) -> string,
	rail: Rail?,
}

-- A prompt's carried files as the bubble shows them.
local function carried(t: data.Turn, nth: number): { attachments.Sent }
	local out: { attachments.Sent } = {}
	for k, a in t.attachments or {} do
		table.insert(out, {
			id = `turn_{nth}_attachment_{k}`,
			name = a.name,
			kind = a.kind,
			src = if a.failed then nil else a.src,
			w = a.w,
			h = a.h,
			status = (if a.kind == "image" and (a.failed or not a.src) then "failed" else nil) :: any,
		})
	end
	return out
end

-- Opens what a bubble carried in the viewer.
function M.open_attachment(a: attachments.Sent)
	if a.src then
		lightbox.open { src = a.src, name = a.name, w = a.w or 720, h = a.h or 480 }
	end
end

-- The chat that sent a prompt, as its caption names it (a click opens it).
local function sender(key: string?): tr.Sender?
	local s = key and data.session(key)
	if not s then
		return nil
	end
	local h = data.HARNESS[s.harness]
	return {
		title = s.title,
		icon = h.icon,
		tint = h.tint,
		on_open = function()
			state.open_session(s.key)
		end,
	}
end

-- A provider as the switch seam names it: its mark and name.
local function provider(h: data.Harness): tr.Sender
	local it = data.HARNESS[h]
	return { title = it.name, icon = it.icon, tint = it.tint }
end

-- The chat a message went to (chat_identity): a session the workspace
-- lists, by key or title, opening on a click; else the name the call
-- gave, with the chat glyph.
local function recipient(to: string): tr.Sender
	local s = data.session(to)
	if not s then
		for _, other in data.SESSIONS do
			if other.title == to then
				s = other
				break
			end
		end
	end
	if not s then
		return { title = to, icon = "chat-round-line" }
	end
	local found = s :: data.Session
	local h = data.HARNESS[found.harness]
	return {
		title = found.title,
		icon = h.icon,
		tint = h.tint,
		on_open = function()
			state.open_session(found.key)
		end,
	}
end

-- What a refusal says signing in fixes (run_errors.rs provider_problem):
-- signed out, or out of usage; Cloud credits are Zeron's, not the
-- provider's.
local SIGNED_OUT = {
	"isn't signed in",
	"is not signed in",
	"not signed in",
	"not logged in",
	"please run /login",
	"run `claude login`",
	"run codex login",
	"authentication failed",
	"authentication_error",
	"sign in to claude again",
	"sign in again",
	"log in again",
	"invalid api key",
	"invalid x-api-key",
	"oauth token has expired",
	"token has expired",
	"token expired",
	"refresh token",
	"unauthorized",
	"http 401",
	"status 401",
	"(401)",
	"401 ",
	"logged out",
}
local LIMIT_REACHED = {
	"usage limit",
	"limit reached",
	"rate limit",
	"rate-limit",
	"you've hit your",
	"you have hit your",
	"hit your limit",
	"quota",
	"http 429",
	"status 429",
	"(429)",
	"too many requests",
}
function M.problem(message: string): ("Signed out" | "Limit reached")?
	local text = string.lower(message)
	local function says(list: { string }): boolean
		for _, needle in list do
			if string.find(text, needle, 1, true) then
				return true
			end
		end
		return false
	end
	if says { "out of credits", "cloud credits" } then
		return nil
	end
	if says(SIGNED_OUT) then
		return "Signed out"
	elseif says(LIMIT_REACHED) then
		return "Limit reached"
	end
	return nil
end

-- "Log in": Settings → Providers, the chat's provider's sign-in on the
-- device the chat runs on (shell.rs sign_in_for_chat).
function M.sign_in(session: string)
	local s = data.session(session)
	if not s then
		return
	end
	local agents = require("@kit/settings_agents")
	local where = data.ELSEWHERE[session]
	local device = agents.device:peek()
	for _, d in agents.devices:peek() do
		if if where then d.name == where else d.you == true then
			device = d.id
		end
	end
	require("./settings").section:set("harnesses")
	state.settings:set(true)
	agents.device:set(device)
	agents.sign_in(device, s.harness)
end

-- History turn `t`'s prompt (the `nth` of the conversation).
function M.prompt(ctx: Ctx, t: data.Turn, nth: number): Node
	local tick = `turn_{nth}`
	return tr.user_bubble {
		id = ctx.name(`turn_{nth}_prompt`),
		text = t.user,
		time = t.asked,
		from = sender(t.from),
		switched = if t.switched then { from = provider(t.switched.from), to = provider(t.switched.to) } else nil,
		links = links.links,
		attachments = carried(t, nth),
		on_attachment = M.open_attachment,
		on_visible = if ctx.rail then ctx.rail.visible(tick) else nil,
	}
end

-- The rail's tick for history turn `t`.
function M.tick(t: data.Turn, nth: number): tr.RailTick
	-- Data alone (a state holds no functions): the card names the sender.
	local from = sender(t.from)
	return {
		id = `turn_{nth}`,
		prompt = t.user,
		reply = t.reply,
		from = if from then { title = from.title, icon = from.icon, tint = from.tint } else nil,
	}
end

-- An image the agent made; the first time the window shows it, it loads a
-- moment (the sample's read of the file) before it shows.
local loaded: { [string]: boolean } = {}
local Generated = ui.component(function(props: { id: string, image: data.Generated }): Node
	local image = props.image
	local key = image.src or image.name
	local status = ui.use_state(if loaded[key] then (if image.src then "loaded" else "failed") else "loading")
	if not loaded[key] then
		ui.after(700, function()
			loaded[key] = true
			status:set(if image.src then "loaded" else "failed")
		end)
	end
	return tr.generated_image {
		id = props.id,
		src = image.src,
		name = image.name,
		w = image.w,
		h = image.h,
		status = function(): string
			return status:get()
		end,
		on_open = function()
			if image.src then
				lightbox.open { src = image.src, name = image.name, w = image.w or 720, h = image.h or 480 }
			end
		end,
	}
end)

-- A visual the agent showed (show_visual): "Loading visual…" a moment (the
-- sample's read of its script), then the script run as a sandboxed plugin
-- named for the visual (its state and grants go by it), or "Visual
-- unavailable" when there is none.
local read: { [string]: boolean } = {}
local Visual = ui.component(function(props: { id: string, name: string, visual: data.Visual }): Node
	local status = ui.use_state(if read[props.name] then "loaded" else "loading")
	if not read[props.name] then
		ui.after(600, function()
			read[props.name] = true
			status:set("loaded")
		end)
	end
	return tr.visual {
		id = props.id,
		name = props.name,
		title = props.visual.title,
		script = props.visual.script,
		status = function(): string
			return if status:get() == "loaded" and not props.visual.script then "unavailable" else status:get()
		end,
	}
end)

-- A turn's tool calls as the group takes them.
local function items_of(t: data.Turn, nth: number): { activity.Activity }
	local items: { activity.Activity } = {}
	for k, tool in t.tools or {} do
		table.insert(items, {
			id = `t{nth}_{k}`,
			icon = tool.icon,
			label = tool.label,
			detail = if tool.detail ~= "" then tool.detail else nil,
			file = tool.file,
			failed = tool.failed,
			status = tool.status,
			call = tool.call,
			output = tool.output,
			output_ref = tool.output_ref,
			output_bytes = tool.output_bytes,
			hunks = tool.hunks,
			images = tool.images,
			thought = tool.thought,
		})
	end
	return items
end

-- Opens a tool's file in Files: the files pane, the file's tab.
function M.open_file(path: string)
	require("./files").open(path)
end

-- The rows a spawn makes (subagent_chip): each its own row, opening the
-- subagent's transcript.
local function spawn_rows(ctx: Ctx, t: data.Turn, nth: number): { Node }
	local rows: { Node } = {}
	for _, sp in t.spawns or {} do
		table.insert(
			rows,
			tr.spawn {
				id = ctx.name(`turn_{nth}_spawn_{sp.id}`),
				detail = sp.detail,
				model = sp.model,
				status = function(): tr.SpawnStatus
					local s = data.subagent(sp.id)
					return if s then s.status else "done"
				end,
				on_open = function()
					state.open_subagent(sp.id)
				end,
			}
		)
	end
	return rows
end

export type ReplyOpts = {
	-- The conversation's last turn (its working line, its retry).
	last: boolean,
	-- Whether its group starts open.
	open: State<boolean>?,
	-- No working line (a side chat's copy of its source).
	quiet: boolean?,
}

-- History turn `t`'s reply.
function M.reply(ctx: Ctx, t: data.Turn, nth: number, opts: ReplyOpts): Node
	local name, key = ctx.name, ctx.key
	local items = items_of(t, nth)
	local working = t.working ~= nil and opts.last and not opts.quiet
	-- A send that never arrived: nothing under it but the retry, until a
	-- retry delivers it ("sending", then "working", then "done").
	local retry = if t.undelivered then ui.state(key(`turn_{nth}_retry`), "") else nil
	local function delivered(): boolean
		return retry == nil or retry:get() == "done"
	end
	local function work(compact: boolean): { Node }
		local nodes: { Node } = {}
		if #items > 0 then
			table.insert(
				nodes,
				activity.group {
					id = name(`turn_{nth}_tools`),
					-- What the tools did, counted as Zeron says it: "Read 2
					-- files · Ran 1 command".
					summary = activity.summary(items),
					open = if compact
						then ui.state(key(`turn_open_compact_{nth}`), false)
						else opts.open or ui.state(key(`turn_open_{nth}`), false),
					items = items,
					on_image = lightbox.open,
					on_file = M.open_file,
					compact = compact,
				}
			)
		end
		for _, row in spawn_rows(ctx, t, nth) do
			table.insert(nodes, row)
		end
		return nodes
	end
	local has_work = #items > 0 or (t.spawns ~= nil and #t.spawns > 0)
	local content: { Node } = {}
	if has_work then
		-- Compact mode folds the work under one header; its summary counts
		-- the spawns as the tools they are.
		table.insert(
			content,
			ui.presence(function()
				return if M.compact():get() then "compact" else "full"
			end, function(mode: string): Node
				if mode == "full" then
					return ui.column { w_full = true, gap = "$zeron.space.12", work(false) }
				end
				local all = table.clone(items)
				for _, sp in t.spawns or {} do
					table.insert(all, { id = sp.id, icon = "bot", label = "Agent", detail = sp.detail })
				end
				local props: activity.WorkProps = {
					id = name(`turn_{nth}_work`),
					summary = activity.summary(all),
					worked = function(): string?
						return if working or not t.worked then nil else activity.worked(t.worked)
					end,
					open = ui.state(key(`turn_work_{nth}`), false),
					active = if working
						then function()
							return true
						end
						else nil,
				}
				for _, n in work(true) do
					table.insert(props, n)
				end
				return activity.work(props)
			end, { w_full = true })
		)
	end
	-- A message to another chat reads as one line naming it, out of the
	-- tool fold (compact mode folds it with the rest of the work).
	for k, m in t.messages or {} do
		table.insert(
			content,
			ui.show(
				function()
					return not M.compact():get()
				end,
				tr.sent_message {
					id = name(`turn_{nth}_message_{k}`),
					to = recipient(m.to),
					failed = m.failed,
					pending = m.pending,
				}
			)
		)
	end
	-- Visuals sit above the reply they lead into.
	for k, visual in t.visuals or {} do
		table.insert(
			content,
			Visual { id = name(`turn_{nth}_visual_{k}`), name = ctx.key(`visual_{nth}_{k}`), visual = visual }
		)
	end
	for k, image in t.images or {} do
		table.insert(content, Generated { id = name(`turn_{nth}_image_{k}`), image = image })
	end
	if t.reply ~= "" then
		local prose = kit.markdown.view { id = name(`reply_{nth}`), text = t.reply, links = links.links }
		table.insert(content, if retry then ui.show(delivered, prose) else prose)
	end
	if t.error then
		-- A refusal signing in fixes says so and offers "Log in".
		local problem = M.problem(t.error)
		local session = ctx.session
		table.insert(
			content,
			tr.error_chip {
				id = name(`turn_{nth}_error`),
				message = t.error,
				label = problem,
				action = if problem and session
					then {
						label = "Log in",
						on_click = function()
							M.sign_in(session)
						end,
					}
					else nil,
			}
		)
	end
	if t.question then
		table.insert(
			content,
			tr.question { id = name(`turn_{nth}_question`), label = t.question.label, answer = t.question.answer }
		)
	end
	local trailer: Node? = nil
	if working then
		trailer = tr.working {
			id = name(`turn_{nth}_working`),
			since = ui.now() - (t.working :: number) * 1000,
			seed = ctx.session,
		}
	elseif retry then
		local r = retry
		-- Zeron's retry re-kicks delivery: "Sending…", then the turn's
		-- word and timer, then the reply.
		trailer = ui.presence(function()
			return if r:get() == "done" then nil else (if r:get() == "" then "failed" else "on")
		end, function(now: string): Node
			if now == "failed" then
				return tr.undelivered {
					id = name(`turn_{nth}_retry`),
					on_retry = function()
						r:set("sending")
						ui.after(250, function()
							r:set("working")
						end)
						ui.after(1500, function()
							r:set("done")
						end)
					end,
				}
			end
			return tr.working {
				id = name(`turn_{nth}_working`),
				seed = ctx.session,
				label = function(): string?
					return if r:get() == "sending" then "Sending" else nil
				end,
			}
		end, { w_full = true })
	end
	return tr.turn {
		content,
		meta = if retry
			then ui.show(delivered, tr.meta { time = t.answered, copy = t.reply })
			else tr.meta { time = t.answered, copy = t.reply },
		working = trailer,
	}
end

-- Whether a turn's reply opens on its work (12 off the prompt; prose, 8).
function M.opens_on_work(t: data.Turn): boolean
	return (t.tools ~= nil and #t.tools > 0) or (t.spawns ~= nil and #t.spawns > 0)
end

-- Subagent `id`'s own transcript in a tab (doc_override): what it was asked
-- and what it did, its working line while it runs; no composer.
function M.subagent(id: string, prefix: string): Node
	local function name(n: string): string
		return `{prefix}_{n}`
	end
	local ctx: Ctx = {
		session = `subagent:{id}`,
		name = name,
		key = function(n: string): string
			return `subagent:{id}:{n}`
		end,
	}
	local turns = data.turns(`subagent:{id}`)
	local rows: { Node } = {}
	for nth, t in turns do
		table.insert(
			rows,
			ui.column { w_full = true, pt = if nth == 1 then 0 else "$zeron.space.16", M.prompt(ctx, t, nth) }
		)
		local s = data.subagent(id)
		local live = s ~= nil and s.status == "running"
		table.insert(
			rows,
			ui.column {
				w_full = true,
				pt = if M.opens_on_work(t) then "$zeron.space.12" else "$zeron.space.8",
				M.reply(ctx, t, nth, { last = nth == #turns, quiet = not live }),
			}
		)
	end
	return ui.column {
		id = name("subagent"),
		w_full = true,
		h_full = true,
		pt = require("./chrome").top,
		items = "stretch",
		kit.scroll {
			grow = 1,
			w_full = true,
			label = "Subagent transcript",
			fade = 24,
			py = "$zeron.space.8",
			ui.column {
				w_full = true,
				max_w = 768,
				self = "center",
				px = "$zeron.space.16",
				py = "$zeron.space.12",
				rows,
			},
		},
	}
end

return M
