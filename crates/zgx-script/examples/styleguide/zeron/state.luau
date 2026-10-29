-- The app's state: the layout it is drawn in, the route, each route's
-- columns under Zeron's panel policy, where it has been (back and
-- forward), the right pane's tabs, and what is open over it.
local ps = require("@kit/panel_shell")
local data = require("./data")

export type Layout = "zeron" | "glass" | "tabs" | "tabs_sidebar"
export type Route = "chat" | "prs"
export type Kind =
	"changes"
	| "commit"
	| "history"
	| "file"
	| "panes"
	| "preview"
	| "terminal"
	| "notes"
	| "side"
	| "subagent"
	| "pr"
-- A side chat's tab holds the side chat (`ref`), a commit's its SHA, a
-- file's its path, a terminal's the action it runs, a subagent's its id,
-- a pull request's its id.
export type Tab = { id: string, kind: Kind, ref: string?, title: string? }
-- On the board, the pull request beside it (none: the board alone).
export type Place = { route: Route, session: string, pr: string? }

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
-- Each session's draft field, by session ("new" for the canvas's): what
-- takes the keyboard when the terminal dock shuts.
local composer_fields: { [string]: Ref } = {}
function M.composer_field(session: string): Ref
	local field = composer_fields[session]
	if not field then
		field = ui.ref()
		composer_fields[session] = field
	end
	return field
end

M.hooks = {} :: {
	open_session: ((session: string) -> ())?,
	open_pr: ((id: string) -> ())?,
	open_surface: ((kind: string) -> ())?,
	open_in_tab: ((session: string) -> ())?,
	open_commit: ((sha: string) -> ())?,
	-- A side chat beside the focused pane (the tabs layouts').
	open_side_chat: ((key: string) -> ())?,
	-- A subagent's transcript beside the focused pane.
	open_subagent: ((id: string) -> ())?,
	-- What a tabs layout forks: its focused pane's chat.
	fork_source: (() -> string?)?,
	-- A drop on a session's chat (zeron/dropzone): a session to mention
	-- (`{ kind = "session", key, title }`), a file to attach (`{ kind =
	-- "file", name, path }`). The conversation, which holds the draft and
	-- the attachments, takes it.
	drop_into: ((session: string, payload: any) -> ())?,
	-- A session's draft (zeron/conversation): a browser's annotations go in.
	draft: ((session: string) -> State<string>)?,
	-- A right-pane tab closed (zeron/pane: its terminal or page ends).
	tab_closed: ((tab: Tab) -> ())?,
	-- The new-session canvas's project from now (zeron/conversation).
	canvas_project: ((project: string, device: string?) -> ())?,
	-- Whether tab `id` may close now (zeron/files: a file's edits are
	-- saved first, and it stays open when they can't be).
	prepare_close: ((id: string) -> boolean)?,
	-- Pull requests (zeron/prs): the one a link names, if any; one opened
	-- where General says; session `key`'s, opened there.
	pr_link: ((url: string) -> string?)?,
	show_pr: ((id: string) -> ())?,
	open_session_pr: ((key: string) -> ())?,
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
-- The board keeps 360 beside its pane; narrower, the pane covers it
-- (shell/pull_request_pane.rs PULL_REQUEST_BOARD_MIN).
M.prs = ps.new { id = "zprs", sidebar = true, right = true, cover = 360, states = { sidebar = M.sidebar } }
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

-- Defined with the board's tabs, below.
local show_pr: (id: string) -> ()

local function here(): Place
	local route = M.route:peek()
	local beside = route == "prs" and not M.tabbed_now() and M.prs.open.right:peek()
	return { route = route, session = M.session:peek(), pr = if beside then M.pr:peek() else nil }
end
local function same(a: Place, b: Place): boolean
	return a.route == b.route and a.session == b.session and a.pr == b.pr
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
	-- A pull request's entry shows it beside the board (its tab again if
	-- it was closed); the board's alone, the board without its pane.
	if p.route == "prs" and not M.tabbed_now() then
		if p.pr then
			show_pr(p.pr)
		else
			ps.set_open(M.prs, "right", false)
		end
	end
	moved:set(moved:peek() + 1)
end
-- Records where the window was before `change` moved it.
local function record(change: () -> ())
	local from = here()
	change()
	if not same(from, here()) then
		table.insert(back, from)
		table.clear(forward)
		moved:set(moved:peek() + 1)
	end
end

-- Go somewhere, as a click does: where the window was goes back.
function M.go(route: Route, session: string?)
	-- The board comes back as it was left, its pull request included.
	local beside = route == "prs" and not M.tabbed_now() and M.prs.open.right:peek()
	local to = { route = route, session = session or M.session:peek(), pr = if beside then M.pr:peek() else nil }
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
		commit = { title = "Commit", icon = "git-branch" },
		history = { title = "History", icon = "clock-circle" },
		file = { title = "File", icon = "document" },
		panes = { title = "zgx", icon = "terminal" },
		preview = { title = "Browser", icon = "globe" },
		terminal = { title = "Terminal", icon = "terminal" },
		notes = { title = "Notes", icon = "pen" },
		side = { title = "Side chat", icon = "chat-round-line" },
		subagent = { title = "Subagent", icon = "bot" },
		pr = { title = "Pull request", icon = "pull-request" },
	}
) :: { [Kind]: KindInfo }
M.tabs = ui.state(
	"tabs",
	{
		{ id = "changes", kind = "changes" },
		{ id = "zgx", kind = "panes" },
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
-- tabs layouts, a surface in a pane); the tab's id, in the pane.
function M.open_tab(kind: Kind): string?
	if M.tabbed_now() and M.hooks.open_surface then
		M.hooks.open_surface(kind)
		return nil
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
	return id
end

-- A commit's own diff (History's click, shell.rs add_commit_diff_surface):
-- a tab of its own each time, beside History (in the tabs layouts, a
-- pane beside the focused one).
function M.open_commit(sha: string)
	if M.tabbed_now() and M.hooks.open_commit then
		M.hooks.open_commit(sha)
		return
	end
	made += 1
	local id = `commit_{made}`
	local list = table.clone(M.tabs:peek())
	table.insert(list, { id = id, kind = "commit" :: Kind, ref = sha })
	M.tabs:set(list)
	M.tab:set(id)
	ps.set_open(M.chat, "right", true)
end

-- What a tab holds (a side chat's, a commit's SHA, a file's path, a
-- terminal's action).
function M.ref_of(id: string): string?
	for _, t in M.tabs:peek() do
		if t.id == id then
			return t.ref
		end
	end
	return nil
end

-- Opens a tab of `kind` holding `ref` in the chat's pane, or brings
-- forward the one that holds it.
local function open_ref(kind: Kind, ref: string)
	for _, t in M.tabs:peek() do
		if t.kind == kind and t.ref == ref then
			M.tab:set(t.id)
			ps.set_open(M.chat, "right", true)
			return
		end
	end
	made += 1
	local id = `{kind}_{made}`
	local list = table.clone(M.tabs:peek())
	local s = kind == "side" and data.session(ref)
	local agent = kind == "subagent" and data.subagent(ref)
	local tab: Tab = {
		id = id,
		kind = kind,
		ref = ref,
		title = if s and s.title ~= "New side chat" then s.title elseif agent then agent.title else nil,
	}
	table.insert(list, tab)
	M.tabs:set(list)
	M.tab:set(id)
	ps.set_open(M.chat, "right", true)
end

-- ---- side chats (shell/side_chats.rs) ---------------------------------------

-- Bumps as side chats come and change (the lanes list them again); a
-- side chat's tab takes the title its first message gives it.
M.sides_version = ui.state("sides_version", 0)
function M.sides_changed()
	M.sides_version:set(M.sides_version:peek() + 1)
	local list = M.tabs:peek()
	for i, t in list do
		local s = t.kind == "side" and t.ref and data.session(t.ref)
		if s and s.title ~= "New side chat" and t.title ~= s.title then
			M.tabs:set_key({ i, "title" }, s.title)
		end
	end
end

-- Side chat `key` in the right pane (a pane beside the focused one in the
-- tabs layouts), the tab already showing it brought forward.
function M.open_side_chat(key: string)
	if M.tabbed_now() and M.hooks.open_side_chat then
		M.hooks.open_side_chat(key)
		return
	end
	open_ref("side", key)
end

-- Subagent `id`'s transcript (a spawn row's link, TranscriptEvent::
-- OpenSubagent): a right-pane tab of its own named by its task, the one
-- showing it brought forward (in the tabs layouts, a pane beside the
-- focused one).
function M.open_subagent(id: string)
	if M.tabbed_now() and M.hooks.open_subagent then
		M.hooks.open_subagent(id)
		return
	end
	open_ref("subagent", id)
end

-- The chat a side chat would start from: the tabs layouts' focused pane's,
-- else the chat's; nil on the canvas or the board.
local function source(): string?
	local key = if M.tabbed_now()
		then (if M.hooks.fork_source then M.hooks.fork_source() else nil)
		elseif M.route:peek() == "chat" then M.session:peek()
		else nil
	if key == nil or key == "new" or data.session(key) == nil then
		return nil
	end
	return key
end

-- Forks `from` (the chat's own unless given) through its latest reply
-- into a side chat, its key; forking a side chat lists the copy as its
-- sibling.
function M.fork_side(from: string?): string?
	local key = from or source()
	local s = key and data.session(key)
	if not key or not s then
		return nil
	end
	local side = data.add_side_chat(s.parent or key, key)
	M.sides_changed()
	return side.key
end
-- The same, opened beside the chat.
function M.fork_chat(from: string?): boolean
	local key = M.fork_side(from)
	if key then
		M.open_side_chat(key)
	end
	return key ~= nil
end

-- A fresh side chat of `parent` (the chat's own unless given), written
-- by its first message: closed before it, it leaves nothing behind.
function M.new_side_chat(parent: string?): boolean
	local key = parent or source()
	local s = key and data.session(key)
	if not key or not s then
		-- Nothing to fork yet (side_chats.rs create_side_chat).
		require("@kit/toast").push { title = "Start a conversation before creating a side chat.", tone = "danger" }
		return false
	end
	local side = data.add_side_chat(s.parent or key, nil)
	M.open_side_chat(side.key)
	return true
end

-- The pane's changes' scope, and the browser's address.
M.changes_scope = ui.state("changes_scope", "working")
M.preview_address = ui.state("preview_address", "localhost:5173")

-- The changes tab showing `scope` (the branch row's "Branch changes").
function M.open_changes(scope: string)
	M.changes_scope:set(scope)
	if M.tabbed_now() and M.hooks.open_surface then
		M.hooks.open_surface("changes")
		return
	end
	for _, t in M.tabs:peek() do
		if t.kind == "changes" then
			M.tab:set(t.id)
			ps.set_open(M.chat, "right", true)
			return
		end
	end
	M.open_tab("changes")
end

-- A terminal running `title` (a project action) in the pane.
function M.open_terminal(title: string)
	if M.tabbed_now() and M.hooks.open_surface then
		M.hooks.open_surface("terminal")
		return
	end
	open_ref("terminal", title)
end

-- The browser at `address` (a port the session serves).
function M.open_preview(address: string)
	M.preview_address:set(address)
	if M.tabbed_now() and M.hooks.open_surface then
		M.hooks.open_surface("preview")
		return
	end
	for _, t in M.tabs:peek() do
		if t.kind == "preview" then
			M.tab:set(t.id)
			ps.set_open(M.chat, "right", true)
			return
		end
	end
	M.open_tab("preview")
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
	if at == 0 or (M.hooks.prepare_close and not M.hooks.prepare_close(id)) then
		return
	end
	local rest = table.clone(list)
	local gone = table.remove(rest, at) :: Tab
	if M.tab:peek() == id then
		local next_tab = rest[at] or rest[at - 1]
		M.tab:set(if next_tab then next_tab.id else "")
	end
	M.tabs:set(rest)
	if M.hooks.tab_closed then
		M.hooks.tab_closed(gone)
	end
end

-- The tabs a tab's menu closes (tabs_to_close): itself, the others, or
-- those to its left or right.
export type CloseAction = "this" | "others" | "left" | "right"
local function to_close(list: { any }, id: string, action: CloseAction): { string }
	local at = 0
	for i, t in list do
		if t.id == id then
			at = i
		end
	end
	local out: { string } = {}
	if at == 0 then
		return out
	end
	for i, t in list do
		if
			(action == "this" and i == at)
			or (action == "others" and i ~= at)
			or (action == "left" and i < at)
			or (action == "right" and i > at)
		then
			table.insert(out, t.id)
		end
	end
	return out
end
function M.tabs_to_close(id: string, action: CloseAction): { string }
	return to_close(M.tabs:peek(), id, action)
end

-- ---- pull requests (shell/pull_request_pane.rs, chat_pull_requests.rs) ------

-- The board's pane: the pull requests opened beside it, as tabs (`pr` the
-- active one). At most eight: opening another closes the least recently
-- viewed, never the active one (tests may lower the cap).
local pr_tabs_max = ui.shared("pr_tabs_max", 8)
M.pr_tabs = ui.state("pr_tabs", {} :: { { id: string } })
local viewed: { [string]: number } = {}
local views = 0
ui.effect(function()
	views += 1
	viewed[M.pr:get()] = views
end)

-- Pull request `id` beside the board, its tab opened or brought forward,
-- recording nothing.
function show_pr(id: string)
	M.pr:set(id)
	local list = table.clone(M.pr_tabs:peek())
	local there = false
	for _, t in list do
		there = there or t.id == id
	end
	if not there then
		table.insert(list, { id = id })
	end
	while #list > pr_tabs_max:peek() do
		local oldest: number? = nil
		for i, t in list do
			if t.id ~= id and (oldest == nil or (viewed[t.id] or 0) < (viewed[list[oldest].id] or 0)) then
				oldest = i
			end
		end
		table.remove(list, oldest)
	end
	M.pr_tabs:set(list)
	ps.set_open(M.prs, "right", true)
end

-- Opens pull request `id` beside the board (in the tabs layouts, the
-- focused tab's pull request pane), or brings its tab forward: a place of
-- its own, so Back returns to the one viewed before (pull_request_pane.rs
-- activate_pull_request_tab). `board`: from another route, the board's.
function M.open_pr(id: string, board: boolean?)
	if M.tabbed_now() and M.hooks.open_pr then
		M.pr:set(id)
		M.hooks.open_pr(id)
		return
	end
	record(function()
		if board and M.route:peek() ~= "prs" then
			ps.rest(M.prs)
			M.route:set("prs")
		end
		show_pr(id)
	end)
end

-- Closes the board's tab `id`: the active one hands over to the tab taking
-- its place, or the one before it; the last closes the pane.
function M.close_pr_tab(id: string)
	local rest = table.clone(M.pr_tabs:peek())
	local at = 0
	for i, t in rest do
		if t.id == id then
			at = i
		end
	end
	if at == 0 then
		return
	end
	table.remove(rest, at)
	if #rest == 0 then
		ps.set_open(M.prs, "right", false)
	elseif M.pr:peek() == id then
		M.pr:set((rest[at] or rest[at - 1]).id)
	end
	M.pr_tabs:set(rest)
end
function M.pr_tabs_to_close(id: string, action: CloseAction): { string }
	return to_close(M.pr_tabs:peek(), id, action)
end

-- The route's pane shown or hidden (⌘R, the titlebar's toggle); the
-- board's opens only with a pull request to show.
function M.toggle_right()
	local shell = M.shell_now()
	if shell == M.prs and not M.prs.open.right:peek() and #M.pr_tabs:peek() == 0 then
		return
	end
	ps.toggle(shell, "right")
end

-- Pull request `id` as a tab in the session's right pane, or its tab
-- brought forward (open_chat_pull_request).
function M.open_pr_tab(id: string)
	open_ref("pr", id)
end

-- ⌘W: the active tab closes only while its pane is on screen (not while
-- the window's fit hides it); on the board, the pull request's tab.
function M.close_active(): boolean
	if M.route:peek() == "prs" then
		if ps.shown(M.prs, "right") then
			M.close_pr_tab(M.pr:peek())
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

-- ---- what opens over the window --------------------------------------------

M.palette = ui.state("palette", false)
M.query = ui.state("query", "")
M.settings = ui.state("settings", false)
-- The session card (session_info.rs): beside the transcript it shows
-- unless hidden (a setting, kept); over a column too tight for it, only
-- while opened.
M.card_hidden = ui.state("card_hidden", false)
M.card_overlay = ui.state("card_overlay", false)
-- The glass layout's focused well: the column last pressed.
M.focus = ui.state("focus", "conversation")

return M
