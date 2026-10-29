-- The chat's right pane: a strip of tabs (in Zeron's titlebar, or the
-- well's header), the active tab's surface (the changes, Wing's panes, a
-- browser, a terminal, notes), and the picker when no tab is open.
local kit = require("@kit")
local right_panel = require("@kit/right_panel")
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local data = require("./data")
local state = require("./state")
local comments = require("./comments")
local browser = require("./browser")
local terminal = require("./terminal")

local M = {}

-- The checkout's changes (kit/changes): the working tree (discarded once
-- asked: the tree's statuses go with it), the branch against a base, the
-- latest turn; or one commit's own (`sha`). Split view and wrapping are
-- the user's (ui-settings.json diffSplit, diffWrap): every changes tab
-- follows them. Comments on its lines are staged on the session's composer.
local diff_mode = ui.state("diff_mode", "unified" :: "unified" | "split")
local diff_wrap = ui.state("diff_wrap", false)
function M.changes(prefix: string, sha: string?): Node
	local function staged()
		return comments.staged(state.session:peek())
	end
	local found = if sha then data.commit(sha) else nil
	return kit.changes.view {
		id = prefix,
		patch = data.patch :: any,
		partial = data.partial :: any,
		branch = data.BRANCH,
		branches = data.BRANCHES,
		commit = if sha then { sha = sha, subject = if found then found.subject else "" } else nil,
		on_discard = if sha
			then nil
			else function()
				data.working:set("")
				require("./files").discard()
			end,
		-- The session card's branch row opens the branch's scope.
		scope = (if prefix == "zchange" then state.changes_scope else ui.state(`{prefix}:scope`, "working")) :: any,
		mode = diff_mode,
		wrap = diff_wrap,
		comments = function()
			return comments.staged(state.session:get()):get()
		end,
		on_comment = function(c)
			staged():push(c)
		end,
		on_edit_comment = function(id: string, body: string)
			for i, n in staged():peek() do
				if n.id == id then
					staged():set_key({ i, "body" }, body)
				end
			end
		end,
		on_remove_comment = function(id: string)
			local rest = {}
			for _, c in staged():peek() do
				if c.id ~= id then
					table.insert(rest, c)
				end
			end
			staged():set(rest)
		end,
	}
end

-- Wing's layout: the editor beside Hacker News, in one tab.
local hn_filter = ui.state("zhn_filter", "Top")
local workspace = kit.panes.new {
	id = "zws",
	root = kit.layout.split(kit.layout.pane("zws_a"), "zws_a", "row", "zws_b", "zws_s1"),
	name = function(pane: string)
		return if pane == "zws_b" then "Hacker News" else "Editor"
	end,
	render = function(pane: string): Node
		if pane == "zws_b" then
			return kit.wing_panes.hn { id = "zws_hn", stories = data.STORIES, filter = hn_filter }
		end
		return kit.wing_panes.editor {
			id = "zws_editor",
			name = "README.md",
			path = "~/Documents/GitHub/zgx",
			lines = data.README,
			first_line = 141,
			language = "Markdown",
			selection = { 3, 8 },
		}
	end,
}
workspace.ratios:set { zws_s1 = 0.6 }

local notes = ui.state("pane_notes", "")

-- A link a page opens in a new window: a browser tab of its own beside it.
local function new_window(url: string)
	local id = state.open_tab("preview")
	if id then
		browser.navigate(id, url)
	end
end

-- A surface of `kind`, its ids under `id`; `ref` what it shows (a commit's
-- SHA, a file's path), the tab's unless given. `bare`: a tabs layout's
-- pane, no session's (a browser there has no dev servers to offer).
function M.surface(kind: string, id: string, ref: string?, bare: boolean?): Node
	if kind == "panes" then
		return ui.column {
			w_full = true,
			h_full = true,
			p = "$zeron.space.6",
			items = "stretch",
			kit.panes.view(workspace, { grow = 1, w_full = true }),
		}
	elseif kind == "preview" then
		return browser.surface(id, new_window, not bare)
	elseif kind == "terminal" then
		return terminal.surface(id)
	elseif kind == "notes" then
		return kit.wing_panes.notes { id = `notes_{id}`, value = notes }
	elseif kind == "history" then
		return require("./history").view(`history_{id}`)
	elseif kind == "file" then
		return require("./files").surface(ref or state.ref_of(id) or "", `file_{id}`)
	elseif kind == "commit" then
		return M.changes(`{id}_change`, ref or state.ref_of(id) or "")
	elseif kind == "side" then
		-- A side chat: what it forked, then its own turns, under a drop
		-- zone of its own.
		local conversation = require("./conversation")
		local key = state.ref_of(id) or ""
		return require("./dropzone").wrap(key, conversation.view(key, id), id)
	elseif kind == "subagent" then
		return require("./turns").subagent(ref or state.ref_of(id) or "", id)
	elseif kind == "pr" then
		return require("./prs").view(ref or state.ref_of(id) or "")
	end
	return M.changes(if id == "changes" then "zchange" else `{id}_change`)
end

local function render(id: string): Node
	return M.surface(state.kind_of(id) or "changes", id)
end

-- How a tab of the strip shows, as right_panel takes it: a terminal by
-- what its program titles it, a page by its title or host (a spinner while
-- it loads).
local function look(t: state.Tab): right_panel.Tab
	local k = state.KINDS[t.kind]
	local title: Text = k.title
	if t.kind == "file" and t.ref then
		-- A file's tab is its name.
		title = string.match(t.ref, "([^/]+)$") or t.ref
	elseif (t.kind == "side" or t.kind == "subagent") and t.title then
		title = t.title
	elseif t.kind == "terminal" then
		-- A project action's runs under its name.
		title = if t.ref then t.ref else terminal.title(t.id)
	elseif t.kind == "preview" then
		title = browser.title(t.id)
	elseif t.kind == "pr" and t.ref then
		title = require("./prs").title(t.ref)
	elseif t.kind == "commit" and t.ref then
		-- A commit's, its subject (its short SHA without one).
		local c = data.commit(t.ref)
		title = if c and c.subject ~= "" then c.subject else string.sub(t.ref, 1, 7)
	end
	return {
		id = t.id,
		title = title,
		icon = k.icon :: any,
		file = if t.kind == "file" then t.ref else nil,
		favicon = if t.kind == "preview" then browser.favicon(t.id) else nil,
		letter = k.letter,
		loading = if t.kind == "preview"
			then browser.loading(t.id)
			elseif t.kind == "pr" and t.ref then function(): boolean
				return require("./prs").reading(t.ref :: string)
			end
			else nil,
		dot = t.kind == "changes",
	}
end

-- A tab closed: what it ran ends with it.
state.hooks.tab_closed = function(t: state.Tab)
	if t.kind == "terminal" then
		terminal.close(t.id)
	elseif t.kind == "preview" then
		browser.close(t.id)
	end
end

-- Next and previous session (⌃Tab, ⌃⇧Tab) while the pane has the focus
-- (shell/tabs.rs cycle_navigation): its tabs in turn, wrapping. The focus
-- is the pane's while a press there was the last (a press on its blank
-- leaves the window's root the focus), or while something in it or its
-- strip has the keyboard's.
M.pressed = false
local body: Element? = nil
function M.mounted(el: Element)
	body = el
end
function M.press(e: PointerEvent)
	local b = body
	M.pressed = b ~= nil
		and b.mounted
		and b.x ~= nil
		and e.x >= b.x
		and e.x < b.x + (b.width or 0)
		and e.y >= (b.y :: number)
		and e.y < (b.y :: number) + (b.height or 0)
end
function M.step(by: number)
	local list = state.tabs:peek()
	if #list > 1 then
		local at: number? = nil
		for i, t in list do
			if t.id == state.tab:peek() then
				at = i
			end
		end
		local next_at = if at then (at - 1 + by) % #list + 1 elseif by > 0 then 1 else #list
		state.tab:set(list[next_at].id)
	end
end
function M.on_key(e: KeyEvent): boolean
	local keys = require("./keys")
	local by = if keys.is("next_session", e) then 1 elseif keys.is("prev_session", e) then -1 else 0
	if by == 0 or state.route:peek() ~= "chat" then
		return false
	end
	M.step(by)
	return true
end

-- A tab's menu (shell.rs TabCloseAction): close it, the others, or those
-- to its left or right; a row with none to close is inert.
local CLOSES: { { state.CloseAction | string } } = {
	{ "this", "Close tab" },
	{ "others", "Close other tabs" },
	{ "left", "Close tabs to the left" },
	{ "right", "Close tabs to the right" },
}
local function tab_menu(prefix: string, id: string): { Node }
	local items: { Node } = {}
	for _, c in CLOSES do
		local action = c[1] :: state.CloseAction
		local closes = state.tabs_to_close(id, action)
		table.insert(
			items,
			kit.menu_item({
				id = `{prefix}_tab_menu_{action}`,
				label = c[2],
				disabled = #closes == 0,
				on_click = function()
					for _, tab in closes do
						state.close_tab(tab)
					end
				end,
			}, function() end, nil, nil, "popover")
		)
	end
	return items
end

-- The tab strip: the open tabs, as they open, close and move (the active
-- one glides on its own), dragged along it to reorder.
function M.strip(prefix: string): Node
	return right_panel.strip {
		id = prefix,
		items = state.tabs :: any,
		look = look :: any,
		active = state.tab,
		reorderable = true,
		menu = function(id: string): { Node }
			return tab_menu(prefix, id)
		end,
		on_close_tab = state.close_tab,
		on_add = function()
			state.palette:set(true)
		end,
	}
end

local PICK = {
	{ id = "changes", label = "Changes", icon = "git-branch" },
	{ id = "history", label = "History", icon = "clock-circle" },
	{ id = "terminal", label = "Terminal", icon = "terminal" },
	{ id = "preview", label = "Browser", icon = "globe" },
	{ id = "notes", label = "Notes", icon = "pen" },
	{ id = "side", label = "Side chat", icon = "chat-round-line" },
}

-- What the pane shows: the active tab's surface, or the picker.
function M.body(): Node
	return ui.presence(function()
		return if state.tab:get() == "" then "pick" else "tab"
	end, function(what: string): Node
		if what == "pick" then
			return ui.column {
				id = "zpane_picker",
				w_full = true,
				h_full = true,
				pt = "$zeron.space.24",
				items = "center",
				ui.column {
					w = 320,
					right_panel.picker {
						id = "zpick",
						items = PICK,
						on_pick = function(id: string)
							if id == "side" then
								state.fork_chat()
							else
								state.open_tab(id :: any)
							end
						end,
					},
				},
			}
		end
		return right_panel.surface { id = "zsurface", active = state.tab, render = render }
	end, { w_full = true, h_full = true })
end

-- Expand (the pane takes the conversation's room) and collapse.
function M.expand(prefix: string): Node
	return ui.show(
		function()
			return state.chat.expanded:get()
		end,
		tb.button {
			id = `{prefix}_collapse`,
			label = "Collapse panel",
			icon = "collapse-arrows",
			on_click = function()
				ps.toggle_expand(state.chat)
			end,
		},
		tb.button {
			id = `{prefix}_expand`,
			label = "Expand panel",
			icon = "expand-arrows",
			on_click = function()
				ps.toggle_expand(state.chat)
			end,
		}
	)
end

return M
