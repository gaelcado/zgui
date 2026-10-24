-- The chat's right pane: a strip of tabs (in Zeron's titlebar, or the
-- well's header), the active tab's surface (the changes, Wing's panes, a
-- preview, a terminal, notes), and the picker when no tab is open.
local T = require("../theme")
local kit = require("@kit")
local right_panel = require("@kit/right_panel")
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local data = require("./data")
local state = require("./state")
local comments = require("./comments")

local M = {}

-- The checkout's changes (kit/changes): the working tree, the branch
-- against a base, the latest turn.
-- Comments on its lines are staged on the session's composer.
local function changes(prefix: string): Node
	local function staged()
		return comments.staged(state.session:peek())
	end
	return kit.changes.view {
		id = prefix,
		patch = data.patch :: any,
		branches = data.BRANCHES,
		comments = function()
			return comments.staged(state.session:get()):get()
		end,
		on_comment = function(c)
			staged():push(c)
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
			path = "~/Documents/GitHub/zgui",
			lines = data.README,
			first_line = 141,
			language = "Markdown",
			selection = { 3, 8 },
		}
	end,
}
workspace.ratios:set { zws_s1 = 0.6 }

local preview_address = ui.state("preview_address", "localhost:5173")
local notes = ui.state("pane_notes", "")

-- A surface of `kind`, its ids under `id`.
function M.surface(kind: string, id: string): Node
	if kind == "panes" then
		return ui.column {
			w_full = true,
			h_full = true,
			p = "$zeron.space.6",
			items = "stretch",
			kit.panes.view(workspace, { grow = 1, w_full = true }),
		}
	elseif kind == "preview" then
		return ui.column {
			id = `preview_{id}`,
			w_full = true,
			h_full = true,
			items = "stretch",
			kit.browser.toolbar { value = preview_address },
			ui.column {
				grow = 1,
				items = "center",
				justify = "center",
				kit.browser.empty {
					title = "Preview your work",
					body = "Start a dev server and its address shows up here.",
				},
			},
		}
	elseif kind == "terminal" then
		return kit.wing_panes.claude { id = `term_{id}`, cwd = "~/zeron/zgui" }
	elseif kind == "notes" then
		return kit.wing_panes.notes { id = `notes_{id}`, value = notes }
	elseif kind == "history" then
		return require("./history").view(`history_{id}`)
	elseif kind == "file" then
		return require("./files").surface(state.ref_of(id) or "", `file_{id}`)
	elseif kind == "side" then
		-- A side chat: the conversation it forked, then its own turns.
		local conversation = require("./conversation")
		local source = state.ref_of(id) or ""
		return conversation.view(`{id}:{source}`, id, source)
	end
	return changes(if id == "changes" then "zchange" else `{id}_change`)
end

local function render(id: string): Node
	return M.surface(state.kind_of(id) or "changes", id)
end

-- The strip's tabs, as right_panel takes them.
local function strip_tabs(): { right_panel.Tab }
	local out: { right_panel.Tab } = {}
	for _, t in state.tabs:peek() do
		local k = state.KINDS[t.kind]
		table.insert(out, {
			id = t.id,
			-- A file's tab is its name.
			title = if t.kind == "file" and t.ref then string.match(t.ref, "([^/]+)$") or t.ref else k.title,
			icon = k.icon :: any,
			letter = k.letter,
			tint = if t.kind == "preview" then T.info else nil,
			dot = t.kind == "changes",
		})
	end
	return out
end

-- The tab strip: built again as tabs open and close (the active one
-- glides on its own).
function M.strip(prefix: string): Node
	local function signature(): string
		local ids = {}
		for _, t in state.tabs:get() do
			table.insert(ids, t.id)
		end
		return table.concat(ids, ",")
	end
	return ui.presence(signature, function(): Node
		return right_panel.strip {
			id = prefix,
			tabs = strip_tabs(),
			active = state.tab,
			on_close_tab = state.close_tab,
			on_add = function()
				state.palette:set(true)
			end,
			render = render,
		}
	end, { min_w = 0 })
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
								state.open_side_chat()
							else
								state.open_tab(id :: any)
							end
						end,
					},
				},
			}
		end
		return right_panel.surface { id = "zsurface", tabs = {}, active = state.tab, render = render }
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
