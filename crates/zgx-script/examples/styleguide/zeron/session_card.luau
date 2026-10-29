-- The session card (shell/session_info.rs, kit/session_card), behind the
-- header's toggle. While the chat's column has room, it shows at its right
-- on its own (until hidden), the transcript and the composer moving left
-- just enough to clear it; once clearing it would narrow the transcript,
-- it hides, and opening it floats it over the transcript, a press
-- elsewhere (or choosing one of its rows) dismissing it. Docked it slides
-- in 12 from the right, floating it drops 6 from above, fading over the
-- resize's 200 ms.
local kit = require("@kit")
local card = require("@kit/session_card")
local data = require("./data")
local state = require("./state")
local chrome = require("./chrome")
local actions = require("./actions")
local cloud = require("./cloud")

local M = {}

-- The main conversation's column: its width says whether the card fits.
M.column = ui.ref()
-- The card, for a press outside it.
local shown_card = ui.ref()

-- Zeron's reading width (the transcript's 736 by default) and the
-- gutters its rows keep (48 each side).
local READING = 736
local GUTTER = 48
-- The least column the card fits beside: a gutter, the reading column,
-- the gap, the card, its inset.
M.FIT = GUTTER + READING + card.GAP + card.WIDTH + card.INSET
-- How far from the column's right the reading column (with its own 16
-- each side) keeps while the card shows beside it.
M.ROOM = card.GAP + card.WIDTH + card.INSET - 16

M.fits = ui.computed(function(): boolean
	return (M.column.width or 0) >= M.FIT
end)

local function chat_open(): boolean
	return state.route:get() == "chat" and state.session:get() ~= "new" and not state.tabbed()
end

-- Beside the transcript it shows unless hidden; over it, only while opened.
function M.shown(): boolean
	if not chat_open() then
		return false
	end
	if M.fits:get() then
		return not state.card_hidden:get()
	end
	return state.card_overlay:get()
end
local function shown_now(): boolean
	if state.route:peek() ~= "chat" or state.session:peek() == "new" or state.tabbed_now() then
		return false
	end
	return if M.fits:peek() then not state.card_hidden:peek() else state.card_overlay:peek()
end

-- The room the transcript keeps free for it, eased as it shows and hides.
M.room = ui.computed(function(): number
	return if M.shown() and M.fits:get() then M.ROOM else 0
end)

-- An overlay opened on a tighter column ends once the card fits.
ui.effect(function()
	if M.fits:get() and state.card_overlay:peek() then
		state.card_overlay:set(false)
	end
end)

-- The toggle's press notes whether the card showed, so the click after it
-- (a press outside having closed it meanwhile) closes it, not reopens it.
local pressed_open: boolean? = nil
function M.note_press()
	pressed_open = shown_now()
end
function M.toggle()
	local was = if pressed_open == nil then shown_now() else pressed_open
	pressed_open = nil
	if M.fits:peek() then
		state.card_hidden:set(was)
	else
		state.card_overlay:set(not was)
	end
end

-- Dismiss the card floating over the transcript; one beside it stays.
function M.close_overlay()
	if state.card_overlay:peek() then
		state.card_overlay:set(false)
	end
end

-- A press anywhere (the window's): outside the floating card, it goes.
function M.press(e: PointerEvent)
	if not state.card_overlay:peek() or M.fits:peek() then
		return
	end
	for _, el in shown_card:elements() do
		if el.x and el.y and el.width and el.height then
			if e.x >= el.x and e.x <= el.x + el.width and e.y >= el.y and e.y <= el.y + el.height then
				return
			end
		end
	end
	state.card_overlay:set(false)
end

-- What runs beside it: its working side chats and subagents (counted on
-- the toggle).
function M.running(): number
	if not chat_open() then
		return 0
	end
	state.sides_version:get()
	local session = state.session:get()
	local n = 0
	for _, s in data.side_chats(session) do
		if s.status == "working" then
			n += 1
		end
	end
	for _, s in data.SUBAGENTS[session] or {} do
		if s.status == "running" then
			n += 1
		end
	end
	return n
end

local function lane(s: data.Session): card.SideChat
	local h = data.HARNESS[s.harness]
	return {
		key = s.key,
		row = s.row,
		title = s.title,
		status = s.status,
		harness = h,
		pr = s.pr :: any,
		ago = s.ago,
	}
end

-- The card for `session`, floating or beside the transcript.
local function view(session: string, floating: boolean): Node
	local s = data.session(session)
	local project = s and s.project
	local p = "z"
	local function chosen(run: () -> ())
		return function()
			M.close_overlay()
			run()
		end
	end
	return kit.session_card.card {
		prefix = p,
		ref = shown_card,
		floating = floating,
		h = "100%",
		info = {
			-- A Cloud session's machine, asleep until a send wakes it.
			device = if cloud.on_cloud(session) then "Cloud" else data.DEVICE,
			device_icon = if cloud.on_cloud(session) then "cloud" else "laptop",
			asleep = if cloud.on_cloud(session)
				then function(): boolean
					return cloud.machine(session) == "asleep"
				end
				else nil,
			project = project,
			project_path = project and data.PROJECT_PATHS[project],
			branch = s and s.branch,
			diff = s and s.diff,
		},
		actions = if project
			then ui.computed(function(): { card.Action }
				return (actions.lists:get()[project] or {}) :: any
			end)
			else nil,
		imports = if project
			then ui.computed(function(): { card.Action }
				return (actions.imports:get()[project] or {}) :: any
			end)
			else nil,
		ports = (function(): { card.Port }
			local out: { card.Port } = {}
			for _, port in data.PORTS[session] or {} do
				table.insert(out, {
					id = port.id,
					name = port.name,
					port = port.port,
					url = `http://localhost:{port.port}`,
				})
			end
			return out
		end)(),
		side_chats = ui.computed(function(): { card.SideChat }
			state.sides_version:get()
			local out: { card.SideChat } = {}
			for _, side in data.side_chats(session) do
				table.insert(out, lane(side))
			end
			return out
		end),
		subagents = data.SUBAGENTS[session],
		harness = s and data.HARNESS[s.harness],
		on_diff = chosen(function()
			state.open_changes("branch")
		end),
		on_run = function(a: card.Action)
			M.close_overlay()
			if project then
				actions.run(project, a :: any)
			end
		end,
		on_edit = function(a: card.Action)
			M.close_overlay()
			if project then
				actions.edit(project, a :: any)
			end
		end,
		on_import = function(a: card.Action)
			M.close_overlay()
			if project then
				actions.edit(project, nil, a :: any)
			end
		end,
		on_add_action = chosen(function()
			if project then
				actions.edit(project)
			end
		end),
		on_port = function(port: card.Port)
			M.close_overlay()
			state.open_preview(`localhost:{port.port}`)
		end,
		on_side_chat = function(key: string)
			M.close_overlay()
			state.open_side_chat(key)
		end,
		on_subagent = function(id: string)
			M.close_overlay()
			state.open_subagent(id)
		end,
		on_new_side_chat = chosen(function()
			state.new_side_chat(session)
		end),
		on_fork = chosen(function()
			state.fork_chat(session)
		end),
	}
end

-- The card over the main conversation of `session`.
function M.view(session: string): Node
	local function placed(mode: string): any
		local docked = mode == "docked"
		local d = kit.motion.d(kit.motion.RESIZE)
		return {
			absolute = true,
			top = function(): number
				return chrome.top_px() + card.INSET
			end,
			right = card.INSET,
			-- The composer's stack stays clear under it (Zeron's bottom
			-- stack and 24).
			bottom = ui.raw(132, "the docked composer's stack, measured, and 24"),
			pointer_events = "none",
			enter = if docked
				then { opacity = { 0, 1 }, x = { 12, 0 }, duration = d, ease = kit.motion.EASE_OUT }
				else { opacity = { 0, 1 }, y = { -6, 0 }, duration = d, ease = kit.motion.EASE_OUT },
			exit = if docked
				then { opacity = 0, x = 12, duration = d, ease = kit.motion.EASE_OUT }
				else { opacity = 0, y = -6, duration = d, ease = kit.motion.EASE_OUT },
		} :: any
	end
	local function card_in(mode: string): Node
		return ui.presence(function()
			if not M.shown() then
				return nil
			end
			return if (M.fits:get() and "docked" or "floating") == mode then mode else nil
		end, function(): Node
			return view(session, mode == "floating")
		end, placed(mode))
	end
	return ui.div {
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		bottom = 0,
		pointer_events = "none",
		card_in("docked"),
		card_in("floating"),
	}
end

return M
