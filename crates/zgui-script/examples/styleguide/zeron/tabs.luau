-- The tabs layouts' model and views. Tabs sit in the topbar beside the
-- traffic lights (Tern's, Rex's); each is a tree of panes (kit/panes: equal
-- shares, held dividers, double-click to equalize, drag a pane by its grip
-- onto another's edge, zoom, the least recently focused hidden when the
-- area is too small), every pane a card showing one surface. Nothing sits
-- beside them: no right pane, since any pane can be one.
local T = require("../theme")
local panes = require("@kit/panes")
local layout = require("@kit/layout")
local space_tabs = require("@kit/space_tabs")
local ps = require("@kit/panel_shell")
local state = require("./state")
local surfaces = require("./surfaces")

type Surface = surfaces.Surface

local M = {}

-- The topbar's height, and the gap around and between cards.
M.HEIGHT = 44
M.GAP = 6

-- The cards are wells: the theme's well fill, its dark edge, its inner
-- ring dimmer on a card that is not focused.
local CARD: panes.Card = {
	bg = T.well,
	line = T.well_edge,
	shadow = T.well_shadow,
	inner = T.well_inner,
	inner_dim = T.well_inner_dim,
}

M.ids = ui.state("ztab_ids", {} :: { string })
M.active = ui.state("ztab_active", "")
M.surfaces = ui.state("zsurfaces", {} :: { [string]: Surface })
local workspaces: { [string]: panes.Workspace } = {}
local made = 0

local function surface_of(pane: string): Surface
	return M.surfaces:get()[pane] or { kind = "new" }
end
local function set_surface(pane: string, s: Surface?)
	local all = table.clone(M.surfaces:peek())
	all[pane] = s
	M.surfaces:set(all)
end

function M.workspace(tab: string): panes.Workspace?
	return workspaces[tab]
end
local function active(): panes.Workspace?
	return workspaces[M.active:peek()]
end

-- ---- what changes them ------------------------------------------------------

function M.activate(tab: string)
	if workspaces[tab] then
		M.active:set(tab)
	end
end

local close_pane: (tab: string, pane: string) -> ()

local function actions(tab: string, pane: string): surfaces.Actions
	local function ws(): panes.Workspace
		return workspaces[tab]
	end
	return {
		choose = function(s: Surface)
			set_surface(pane, s)
			panes.focus(ws(), pane)
		end,
		split = function(axis)
			panes.focus(ws(), pane)
			M.split(axis)
		end,
		zoom = function()
			panes.focus(ws(), pane)
			panes.toggle_zoom(ws())
		end,
		close = function()
			close_pane(tab, pane)
		end,
		zoomed = function()
			return ws().zoom:get() == pane
		end,
		focused = function()
			return ws().focus:get() == pane
		end,
	}
end

-- A tab with `tree`, each pane showing what `shows` gives it.
-- Each space's name (a tab in the topbar is a space: a named group of
-- panes; the sidebar lists the sessions, so the tabs never repeat them).
M.names = ui.state("zspace_names", {} :: { [string]: string })
-- The space being renamed in place ("" for none).
M.renaming = ui.state("zspace_renaming", "")

local function make(tree: layout.Tree, shows: { [string]: Surface }, name: string?): string
	made += 1
	local tab = `t{made}`
	M.names:set_key(tab, name or `Space {made}`)
	local ws = panes.new {
		id = `z{tab}`,
		root = tree,
		gap = M.GAP,
		radius = 11,
		card = CARD,
		render = function(pane: string): Node
			return surfaces.view(pane, function()
				return surface_of(pane)
			end, actions(tab, pane))
		end,
		name = function(pane: string): string
			return surfaces.look(surface_of(pane)).title
		end,
		look = function(pane: string): panes.Look
			local l = surfaces.look(M.surfaces:peek()[pane] or { kind = "new" })
			return { icon = l.icon, tint = l.tint }
		end,
		-- A lone pane can still go to another space.
		movable = function(): boolean
			return #M.ids:get() > 1
		end,
	}
	workspaces[tab] = ws
	local all = table.clone(M.surfaces:peek())
	for pane, s in shows do
		all[pane] = s
	end
	M.surfaces:set(all)
	local ids = table.clone(M.ids:peek())
	table.insert(ids, tab)
	M.ids:set(ids)
	M.active:set(tab)
	return tab
end

-- A new tab of one pane: `surface`, or the picker.
function M.new_tab(surface: Surface?, name: string?): string
	local pane = `zt{made + 1}_a`
	return make(layout.pane(pane), { [pane] = surface or { kind = "new" } }, name)
end

function M.rename(tab: string, name: string)
	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	if trimmed ~= "" then
		M.names:set_key(tab, trimmed)
	end
	M.renaming:set("")
end

-- Moves `tab` next to `other`: before it, else after (a drag in the
-- topbar). Nothing changes while it is already there.
function M.move(tab: string, other: string, before: boolean)
	local ids = table.clone(M.ids:peek())
	local from = table.find(ids, tab)
	if not from or tab == other then
		return
	end
	table.remove(ids, from)
	local at = table.find(ids, other)
	if not at then
		return
	end
	table.insert(ids, if before then at else at + 1, tab)
	local same = true
	for i, id in ids do
		if M.ids:peek()[i] ~= id then
			same = false
		end
	end
	if not same then
		M.ids:set(ids)
	end
end

-- Closes every space but `tab`.
function M.close_others(tab: string)
	for _, other in table.clone(M.ids:peek()) do
		if other ~= tab then
			M.close_tab(other)
		end
	end
	M.active:set(tab)
end

function M.close_tab(tab: string)
	local ids = table.clone(M.ids:peek())
	local at = table.find(ids, tab)
	if not at then
		return
	end
	table.remove(ids, at)
	local ws = workspaces[tab]
	workspaces[tab] = nil
	if ws then
		local all = table.clone(M.surfaces:peek())
		for _, pane in panes.panes(ws) do
			all[pane] = nil
		end
		M.surfaces:set(all)
	end
	M.ids:set(ids)
	if M.active:peek() == tab then
		M.active:set(ids[at] or ids[at - 1] or "")
	end
	if #ids == 0 then
		M.new_tab()
	end
end

close_pane = function(tab: string, pane: string)
	local ws = workspaces[tab]
	if not ws then
		return
	end
	panes.close(ws, pane)
	set_surface(pane, nil)
	if #panes.panes(ws) == 0 then
		M.close_tab(tab)
	end
end

-- The space holding `pane`.
local function space_of(pane: string): string?
	for tab, ws in workspaces do
		if table.find(panes.panes(ws), pane) then
			return tab
		end
	end
	return nil
end

-- A pane dragged onto another space moves in beside its focused pane,
-- what it shows kept; the space it left goes with its last pane.
function M.move_pane(pane: string, to: string)
	local from = space_of(pane)
	local target = workspaces[to]
	if not from or not target then
		return
	end
	if from ~= to then
		panes.close(workspaces[from], pane)
		panes.insert(target, pane, "row")
		if #panes.panes(workspaces[from]) == 0 then
			M.close_tab(from)
		end
	end
	M.active:set(to)
end

-- A pane dropped on the topbar's empty end: a space of its own, named for
-- what it shows.
function M.pane_to_space(pane: string)
	local from = space_of(pane)
	if not from then
		return
	end
	local ws = workspaces[from]
	if #panes.panes(ws) == 1 then
		-- Alone already: its space comes forward.
		M.active:set(from)
		return
	end
	panes.close(ws, pane)
	make(layout.pane(pane), {}, surfaces.look(surface_of(pane)).title)
end

-- Split the focused pane of the active tab; the new pane shows `surface`,
-- or the picker.
function M.split(axis: layout.Axis, surface: Surface?): string?
	local ws = active()
	if not ws then
		return nil
	end
	local pane = panes.split(ws, axis)
	if pane then
		set_surface(pane, surface or { kind = "new" })
	end
	return pane
end

-- ⌘W: the focused pane closes, and with the last pane its tab.
function M.close_focused(): boolean
	local ws = active()
	local pane = ws and ws.focus:peek()
	if not pane then
		return false
	end
	close_pane(M.active:peek(), pane)
	return true
end

function M.zoom()
	local ws = active()
	if ws then
		panes.toggle_zoom(ws)
	end
end

function M.go(direction: layout.Direction)
	local ws = active()
	if ws then
		panes.go(ws, direction)
	end
end

-- The tab `step` along from the active one, wrapping.
function M.cycle(step: number)
	local ids = M.ids:peek()
	local at = table.find(ids, M.active:peek()) or 1
	local n = #ids
	if n > 0 then
		M.active:set(ids[((at - 1 + step) % n) + 1])
	end
end

function M.select(index: number)
	local id = M.ids:peek()[index]
	if id then
		M.active:set(id)
	end
end

-- Shows `s` where it belongs: a pane already showing it comes forward;
-- else the focused pane takes it if it is a picker; else it opens beside
-- the focused pane (a pull request beside the board) or in a new tab.
local function show(s: Surface, beside: boolean)
	for tab, ws in workspaces do
		for _, pane in panes.panes(ws) do
			local here = M.surfaces:peek()[pane]
			if here and here.kind == s.kind and here.ref == s.ref then
				M.active:set(tab)
				panes.focus(ws, pane)
				return
			end
		end
	end
	local ws = active()
	local focus = ws and ws.focus:peek()
	local current = focus and M.surfaces:peek()[focus]
	if focus and (current == nil or current.kind == "new") then
		set_surface(focus, s)
	elseif beside and ws then
		M.split("row", s)
	else
		M.new_tab(s)
	end
end

function M.open_session(session: string)
	if session == "prs" then
		show({ kind = "prs" }, false)
	else
		show({ kind = "chat", ref = session }, false)
	end
end

function M.open_surface(kind: string)
	show({ kind = (if kind == "panes" then "terminal" else kind) :: any }, true)
end

-- A pull request beside the board: the tab's pull request pane follows it.
function M.open_pr(id: string)
	local ws = active()
	if ws then
		for _, pane in panes.panes(ws) do
			local here = M.surfaces:peek()[pane]
			if here and here.kind == "pr" then
				set_surface(pane, { kind = "pr", ref = id })
				panes.focus(ws, pane)
				return
			end
		end
	end
	show({ kind = "pr", ref = id }, true)
end

-- The sidebar marks the focused pane's session.
ui.effect(function()
	local ws = workspaces[M.active:get()]
	local focus = ws and ws.focus:get()
	local s = focus and M.surfaces:get()[focus]
	local session = if s and s.kind == "chat" then s.ref or "" elseif s and s.kind == "prs" then "prs" else ""
	if state.pane_session:peek() ~= session then
		state.pane_session:set(session)
	end
end)

state.hooks.open_session = M.open_session
state.hooks.open_pr = M.open_pr
state.hooks.open_surface = M.open_surface
state.hooks.open_in_tab = function(session: string)
	local s = require("./data").session(session)
	M.new_tab({ kind = "chat", ref = session }, if s then s.title else nil)
end

-- The first tabs: the release notes with a terminal and the changes beside
-- them, the layout refactor, a shell.
do
	-- The spaces' panes live in this module, not in state: a reload builds
	-- them again, so the lists that name them start again too (else every
	-- save would add the first spaces once more).
	M.ids:set {}
	M.names:set {}
	M.surfaces:set {}
	M.renaming:set("")
	local a, b, c = "zt1_a", "zt1_b", "zt1_c"
	local tree = layout.split(layout.pane(a), a, "row", b, "zt1_first")
	tree = layout.split(tree, b, "column", c, "zt1_second")
	make(tree, {
		[a] = { kind = "chat", ref = "agent:a1" },
		[b] = { kind = "terminal" },
		[c] = { kind = "changes" },
	}, "Release 0.2.117")
	M.new_tab({ kind = "chat", ref = "agent:a2" }, "Layout engine")
	M.new_tab({ kind = "terminal" }, "Shell")
	M.active:set("t1")
end

-- ---- the views --------------------------------------------------------------

local topbar_context: space_tabs.Context = {
	ids = M.ids,
	active = M.active,
	names = M.names,
	renaming = M.renaming,
	panes = function(tab: string): { string }
		-- A space closing fades out after its panes are gone.
		local ws = workspaces[tab]
		if not ws then
			return {}
		end
		ws.root:get()
		return panes.panes(ws)
	end,
	look = function(pane: string): space_tabs.Look
		return surfaces.look(M.surfaces:peek()[pane] or { kind = "new" }) :: any
	end,
	look_key = function(pane: string): string
		local s = surface_of(pane)
		return `{s.kind}:{s.ref or ""}`
	end,
	activate = M.activate,
	rename = M.rename,
	new = function()
		M.new_tab()
	end,
	close = M.close_tab,
	close_others = M.close_others,
	move = M.move,
	take_pane = function(tab: string, pane: string)
		M.move_pane(pane, tab)
	end,
	pane_to_new = M.pane_to_space,
	project = "zgui",
	on_search = function()
		state.palette:set(true)
	end,
	on_settings = function()
		state.settings:set(true)
	end,
}

-- The topbar: the kit's (kit/space_tabs) over the spaces, with the sidebar
-- toggle when the layout has the sidebar.
function M.topbar(with_sidebar: boolean): Node
	local ctx = table.clone(topbar_context)
	if with_sidebar then
		ctx.sidebar = state.sidebar
		ctx.on_sidebar = function()
			ps.toggle(state.tabs_shell, "sidebar")
		end
	end
	return space_tabs.topbar(ctx)
end

-- The active tab's panes, inset by the gap from the window's edges; beside
-- the sidebar, from its edge alone (its rows keep their own inset), as the
-- glass layout's wells sit.
function M.body(): Node
	return ui.column {
		id = "ztabs_body",
		grow = 1,
		w_full = true,
		min_h = 0,
		pl = function(): Length
			local beside = state.layout:get() == "tabs_sidebar" and state.tabs_shell.w.sidebar:get() > 0.5
			return if beside then 0 else "$zeron.well.gap"
		end,
		pr = "$zeron.well.gap",
		pb = "$zeron.well.gap",
		ui.presence(M.active, function(tab: string): Node
			local ws = workspaces[tab]
			if not ws then
				return ui.div {}
			end
			return panes.view(ws, { w_full = true, h_full = true })
		end, { grow = 1, w_full = true, min_h = 0 }),
	}
end

return M
