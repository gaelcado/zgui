-- The app's state: the layout it is drawn in, the route, each route's
-- columns under Zeron's panel policy, where it has been (back and
-- forward), the right pane's tabs, and what is open over it.
local ps = require("@kit/panel_shell")
local data = require("./data")

export type Layout = "zeron" | "glass" | "tabs" | "tabs_sidebar"
export type Route = "chat" | "prs"
export type Kind = "changes" | "history" | "file" | "panes" | "preview" | "terminal" | "notes" | "side"
-- A side chat's tab holds the session it forked (`ref`).
export type Tab = { id: string, kind: Kind, ref: string? }
export type Place = { route: Route, session: string }

local look = require("@kit/look")

local M = {}

-- How the window is drawn. Classic: Zeron's unified titlebar over flush
-- columns, the right pane beside the chat. Glass: the same columns, the
-- sidebar on the window's blur and every content column a well inset into
-- it (Rex's). Tabs: no sidebar and no right pane; tabs in the topbar beside
-- the traffic lights, each a tree of panes showing any surface (Tern's,
-- Rex's). Tabs and sidebar: the same with the sessions beside them.
M.layout = ui.state("layout", "zeron" :: Layout)
M.LAYOUTS = {
	{ id = "zeron", label = "Classic" },
	{ id = "glass", label = "Glass" },
	{ id = "tabs", label = "Tabs" },
	{ id = "tabs_sidebar", label = "Tabs + sidebar" },
}
-- How the window looks: the theme and its mode, the accent, the surface
-- (kit/look; the root wears its scope).
M.look = look.new("zeron")

-- The tabs layouts (topbar tabs over trees of panes).
function M.tabbed(): boolean
	local l = M.layout:get()
	return l == "tabs" or l == "tabs_sidebar"
end
function M.tabbed_now(): boolean
	local l = M.layout:peek()
	return l == "tabs" or l == "tabs_sidebar"
end
-- Where the tabs layouts handle what the classic ones route (set by
-- tabs.luau, which this module cannot require).
M.hooks = {} :: {
	open_session: ((session: string) -> ())?,
	open_pr: ((id: string) -> ())?,
	open_surface: ((kind: string) -> ())?,
	open_in_tab: ((session: string) -> ())?,
	-- A drop on a session's chat (zeron/dropzone): a session to mention
	-- (`{ kind = "session", key, title }`), a file to attach (`{ kind =
	-- "file", name, path }`). The conversation, which holds the draft and
	-- the attachments, takes it.
	drop_into: ((session: string, payload: any) -> ())?,
}

-- The chat, or the pull requests' board with a pull request beside it.
M.route = ui.state("route", "chat" :: Route)
-- The sidebar is the window's, shared by both routes; each route keeps its
-- own right pane and divider (PR #914), and the chat its Files.
M.sidebar = ui.state("sidebar_open", true)
M.chat = ps.new {
	id = "zcols",
	sidebar = true,
	right = true,
	files = true,
	sidebar_open = true,
	states = { sidebar = M.sidebar },
}
M.prs = ps.new { id = "zprs", sidebar = true, right = true, states = { sidebar = M.sidebar } }
-- The tabs and sidebar layout: the sidebar beside the tabs' panes.
M.tabs_shell = ps.new { id = "ztabsh", sidebar = true, states = { sidebar = M.sidebar } }

-- The shell the route shows.
function M.shell(): ps.Shell
	if M.layout:get() == "tabs_sidebar" then
		return M.tabs_shell
	end
	return if M.route:get() == "prs" then M.prs else M.chat
end
function M.shell_now(): ps.Shell
	if M.layout:peek() == "tabs_sidebar" then
		return M.tabs_shell
	end
	return if M.route:peek() == "prs" then M.prs else M.chat
end

-- The session the chat shows: `agent:<id>` or `thread:<id>`.
M.session = ui.state("session", "agent:a1")
-- The pull request the board's pane shows.
M.pr = ui.state("pr", "p1")
-- In the tabs layouts: the session the focused pane shows (the sidebar
-- marks it).
M.pane_session = ui.state("pane_session", "")
-- Bumps as sessions are started (the sidebar lists them again).
M.sessions_version = ui.state("sessions_version", 0)

-- ---- where the window has been -------------------------------------------

local back: { Place } = {}
local forward: { Place } = {}
-- Bumps as the history changes, for what reads can_back and can_forward.
local moved = ui.state("moved", 0)

local function here(): Place
	return { route = M.route:peek(), session = M.session:peek() }
end
local function arrive(p: Place)
	local shell = if p.route == "prs" then M.prs else M.chat
	if p.route ~= M.route:peek() then
		-- The arriving route lays out at rest: the sidebar may have moved
		-- while it was away.
		ps.rest(shell)
	end
	M.route:set(p.route)
	M.session:set(p.session)
	moved:set(moved:peek() + 1)
end

-- Go somewhere, as a click does: where the window was goes back.
function M.go(route: Route, session: string?)
	local to = { route = route, session = session or M.session:peek() }
	local from = here()
	if to.route == from.route and to.session == from.session then
		return
	end
	table.insert(back, from)
	table.clear(forward)
	arrive(to)
end
function M.back()
	local p = table.remove(back)
	if p then
		table.insert(forward, here())
		arrive(p)
	end
end
function M.forward()
	local p = table.remove(forward)
	if p then
		table.insert(back, here())
		arrive(p)
	end
end
function M.can_back(): boolean
	moved:get()
	return #back > 0
end
function M.can_forward(): boolean
	moved:get()
	return #forward > 0
end

-- The title the window shows for where it is.
function M.title(): string
	if M.route:get() == "prs" then
		return "Pull requests"
	end
	local s = data.session(M.session:get())
	return if s then s.title else "New session"
end

-- ---- the right pane's tabs -------------------------------------------------

export type KindInfo = { title: string, icon: string?, letter: string? }
M.KINDS = (
	{
		changes = { title = "Changes", icon = "git-branch" },
		history = { title = "History", icon = "clock-circle" },
		file = { title = "File", icon = "document" },
		panes = { title = "zgui", icon = "terminal" },
		preview = { title = "Preview", letter = "P" },
		terminal = { title = "Terminal", icon = "terminal" },
		notes = { title = "Notes", icon = "pen" },
		side = { title = "Side chat", icon = "chat-round-line" },
	}
) :: { [Kind]: KindInfo }
M.tabs = ui.state(
	"tabs",
	{
		{ id = "changes", kind = "changes" },
		{ id = "zgui", kind = "panes" },
		{ id = "preview", kind = "preview" },
	} :: { Tab }
)
-- The active tab ("" with none: the pane shows its picker).
M.tab = ui.state("tab", "changes")
local made = 0

function M.kind_of(id: string): Kind?
	for _, t in M.tabs:peek() do
		if t.id == id then
			return t.kind
		end
	end
	return nil
end

-- A session, from the sidebar: the chat's in the classic layouts, a
-- pane's in the tabs layouts.
function M.open_session(session: string)
	if M.tabbed_now() and M.hooks.open_session then
		M.hooks.open_session(session)
		return
	end
	if session == "prs" then
		M.go("prs")
	else
		M.go("chat", session)
	end
end

-- Opens a tab of `kind` in the chat's pane, and the pane with it (in the
-- tabs layouts, a surface in a pane).
function M.open_tab(kind: Kind)
	if M.tabbed_now() and M.hooks.open_surface then
		M.hooks.open_surface(kind)
		return
	end
	made += 1
	local id = `{kind}_{made}`
	local list = table.clone(M.tabs:peek())
	table.insert(list, { id = id, kind = kind })
	M.tabs:set(list)
	M.tab:set(id)
	if M.route:peek() ~= "chat" then
		M.go("chat")
	end
	ps.set_open(M.chat, "right", true)
end

-- The session a tab forked (a side chat's).
function M.ref_of(id: string): string?
	for _, t in M.tabs:peek() do
		if t.id == id then
			return t.ref
		end
	end
	return nil
end

-- A side chat (shell/side_chats.rs): the conversation forked through its
-- latest reply, as a tab of the right pane beside it, its own composer
-- under it. Nothing to fork on the new-session canvas, nor in the tabs
-- layouts (whose panes have no right pane).
function M.open_side_chat(): boolean
	local source = M.session:peek()
	if M.tabbed_now() or M.route:peek() ~= "chat" or source == "new" or data.session(source) == nil then
		return false
	end
	made += 1
	local id = `side_{made}`
	local list = table.clone(M.tabs:peek())
	local tab: Tab = { id = id, kind = "side", ref = source }
	table.insert(list, tab)
	M.tabs:set(list)
	M.tab:set(id)
	ps.set_open(M.chat, "right", true)
	return true
end

-- Closes tab `id`; the active one hands over to its right-hand neighbour,
-- or the left-hand one at the end. The last leaves the picker.
function M.close_tab(id: string)
	local list = M.tabs:peek()
	local at = 0
	for i, t in list do
		if t.id == id then
			at = i
		end
	end
	if at == 0 then
		return
	end
	local rest = table.clone(list)
	table.remove(rest, at)
	if M.tab:peek() == id then
		local next_tab = rest[at] or rest[at - 1]
		M.tab:set(if next_tab then next_tab.id else "")
	end
	M.tabs:set(rest)
end

-- ⌘W: the active tab closes only while its pane is on screen (not while
-- the window's fit hides it); on the board, the pull request's pane.
function M.close_active(): boolean
	if M.route:peek() == "prs" then
		if ps.shown(M.prs, "right") then
			ps.toggle(M.prs, "right")
			return true
		end
		return false
	end
	if ps.shown(M.chat, "right") and M.tab:peek() ~= "" then
		M.close_tab(M.tab:peek())
		return true
	end
	return false
end

-- Opens pull request `id` beside the board.
function M.open_pr(id: string)
	M.pr:set(id)
	if M.tabbed_now() and M.hooks.open_pr then
		M.hooks.open_pr(id)
		return
	end
	ps.set_open(M.prs, "right", true)
end

-- ---- what opens over the window --------------------------------------------

M.palette = ui.state("palette", false)
M.query = ui.state("query", "")
M.settings = ui.state("settings", false)
M.card = ui.state("card", false)
-- The glass layout's focused well: the column last pressed.
M.focus = ui.state("focus", "conversation")

return M
