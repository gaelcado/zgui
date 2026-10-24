-- What a pane shows in the tabs layouts: a surface (a session's chat, a
-- terminal, the changes, a browser, the files, the board of pull requests
-- or one of them, notes), or, in a new pane, the picker that chooses one.
-- Each pane is a card with a header (what it shows; split, zoom, close).
local T = require("../theme")
local kit = require("@kit")
local wash = require("@kit/wash")
local data = require("./data")
local state = require("./state")
local conversation = require("./conversation")
local pane = require("./pane")
local files = require("./files")
local prs = require("./prs")
local chrome = require("./chrome")

export type Kind = "new" | "chat" | "terminal" | "changes" | "history" | "preview" | "files" | "prs" | "pr" | "notes"
export type Surface = { kind: Kind, ref: string? }

local M = {}

-- A pane's header row.
M.HEADER = 36

type Look = { icon: string, tint: Color?, title: string }

-- The session a `chat` surface shows, as the sidebar names it.
local function session_look(session: string): Look
	local s = data.session(session)
	if s then
		local h = data.HARNESS[s.harness]
		return { icon = h.icon, tint = h.tint, title = s.title }
	end
	return { icon = "claude-mark", tint = T.claude, title = "New session" }
end

function M.look(s: Surface): Look
	if s.kind == "chat" then
		return session_look(s.ref or "")
	elseif s.kind == "terminal" then
		return { icon = "terminal", title = "zsh ~" }
	elseif s.kind == "changes" then
		return { icon = "git-branch", title = "Changes" }
	elseif s.kind == "history" then
		return { icon = "clock-circle", title = "History" }
	elseif s.kind == "preview" then
		return { icon = "globe", title = "localhost:5173" }
	elseif s.kind == "files" then
		return { icon = "folder-tree", title = "Files" }
	elseif s.kind == "prs" then
		return { icon = "pull-request", title = "Pull requests" }
	elseif s.kind == "pr" then
		for _, r in data.PRS do
			if r.id == s.ref then
				return { icon = "pull-request", title = `#{r.number} {r.title}` }
			end
		end
		return { icon = "pull-request", title = "Pull request" }
	elseif s.kind == "notes" then
		return { icon = "pen", title = "Notes" }
	end
	return { icon = "add-circle", title = "New pane" }
end

-- What a new pane can become.
type Choice = { id: string, label: string, detail: string, icon: string, surface: Surface }
local CHOICES: { Choice } = {
	{
		id = "chat",
		label = "New chat",
		detail = "Claude Code in ~/zeron/zgui",
		icon = "chat-round-line",
		surface = { kind = "chat", ref = "new" },
	},
	{ id = "terminal", label = "Terminal", detail = "zsh", icon = "terminal", surface = { kind = "terminal" } },
	{
		id = "changes",
		label = "Changes",
		detail = "What the branch changes",
		icon = "git-branch",
		surface = { kind = "changes" },
	},
	{
		id = "history",
		label = "History",
		detail = "The branch's commits",
		icon = "clock-circle",
		surface = { kind = "history" },
	},
	{ id = "preview", label = "Browser", detail = "A web page", icon = "globe", surface = { kind = "preview" } },
	{
		id = "files",
		label = "Files",
		detail = "The project's tree",
		icon = "folder-tree",
		surface = { kind = "files" },
	},
	{
		id = "prs",
		label = "Pull requests",
		detail = "The board",
		icon = "pull-request",
		surface = { kind = "prs" },
	},
	{ id = "notes", label = "Notes", detail = "A notepad", icon = "pen", surface = { kind = "notes" } },
}

-- The new pane's picker: what it can become, then the recent sessions.
local function picker(id: string, choose: (Surface) -> ()): Node
	local group = wash.group("zpick")
	local function row(key: string, label: string, detail: string, icon: Node, s: Surface): Node
		return ui.button(wash.item(group, {
			id = `{id}_{key}`,
			w_full = true,
			h = 40,
			px = "$zeron.space.10",
			gap = "$zeron.space.10",
			items = "center",
			rounded = T.radius_lg,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = function()
				choose(s)
			end,
			icon,
			kit.text.text { label, size = "md", line = false },
			kit.text.text { detail, size = "sm", color = T.tertiary, line = false, truncate = true, shrink = 1 },
		}))
	end
	local rows: { Node } = {}
	for _, c in CHOICES do
		table.insert(
			rows,
			row(c.id, c.label, c.detail, kit.icon { name = c.icon :: any, size = 16, color = T.secondary }, c.surface)
		)
	end
	local recent: { Node } = {}
	for i, s in data.SESSIONS do
		if i > 6 then
			break
		end
		local h = data.HARNESS[s.harness]
		table.insert(
			recent,
			row(
				s.row,
				s.title,
				s.project,
				kit.icon { name = h.icon :: any, size = 16, color = h.tint or T.secondary },
				{ kind = "chat", ref = s.key }
			)
		)
	end
	return kit.scroll {
		id = `{id}_picker`,
		grow = 1,
		w_full = true,
		fade = 16,
		ui.column {
			w_full = true,
			max_w = 420,
			self = "center",
			px = "$zeron.space.12",
			py = "$zeron.space.24",
			gap = "$zeron.space.12",
			kit.text.text { "Open in this pane", size = "lg", weight = "semibold", px = "$zeron.space.10" },
			wash.list {
				group = group,
				gap = "$zeron.space.2",
				rows,
				ui.row { h = 24, px = "$zeron.space.10", items = "end", kit.text.eyebrow("Sessions") },
				recent,
			},
		},
	}
end

export type Actions = {
	choose: (Surface) -> (),
	split: (axis: "row" | "column") -> (),
	zoom: () -> (),
	close: () -> (),
	zoomed: () -> boolean,
	focused: () -> boolean,
}

local function header(id: string, s: Surface, a: Actions): Node
	local look = M.look(s)
	local function button(key: string, label: string, icon: string | Node, run: () -> ()): Node
		return ui.button {
			id = `{id}_{key}`,
			w = 24,
			h = 24,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.6",
			bg = T.clear,
			hover = { bg = T.ink4 },
			focus = { border = 0 },
			cursor = "pointer",
			tooltip = label,
			on_click = run,
			if type(icon) == "string" then kit.icon { name = icon :: any, size = 14, color = T.tertiary } else icon,
		}
	end
	return ui.row {
		id = `{id}_head`,
		h = M.HEADER,
		w_full = true,
		shrink = 0,
		pl = "$zeron.space.12",
		pr = "$zeron.space.6",
		gap = "$zeron.space.8",
		items = "center",
		kit.icon { name = look.icon :: any, size = 15, color = look.tint or T.secondary },
		kit.text.text {
			look.title,
			size = "md",
			weight = "medium",
			line = false,
			truncate = true,
			shrink = 1,
			color = "inherit",
			variants = kit.recipes.strip_tab { selected = a.focused },
		},
		ui.div { grow = 1 },
		button("split_right", "Split right (⌘D)", chrome.split_glyph("row"), function()
			a.split("row")
		end),
		button("split_down", "Split down (⌘⇧D)", chrome.split_glyph("column"), function()
			a.split("column")
		end),
		button("zoom", "Zoom (⌘⇧↩)", "expand-arrows", a.zoom),
		button("close", "Close (⌘W)", "close", a.close),
	}
end

-- The body for a surface, its ids under `id`.
local function body(id: string, s: Surface, a: Actions): Node
	if s.kind == "chat" and s.ref == "new" then
		return conversation.canvas(id, function(key: string)
			state.sessions_version:set(state.sessions_version:peek() + 1)
			a.choose { kind = "chat", ref = key }
		end)
	elseif s.kind == "chat" then
		return conversation.view(s.ref, id)
	elseif s.kind == "files" then
		return files.view()
	elseif s.kind == "prs" then
		return prs.board()
	elseif s.kind == "pr" then
		return prs.detail()
	elseif s.kind == "new" then
		return picker(id, a.choose)
	end
	return pane.surface(s.kind, id)
end

-- A pane: its header over its body, built again when its surface changes.
function M.view(id: string, surface: () -> Surface, a: Actions): Node
	return ui.presence(function()
		local s = surface()
		return `{s.kind}:{s.ref or ""}`
	end, function(key: string): Node
		local kind, ref = string.match(key, "^(%w+):(.*)$")
		local s: Surface = { kind = (kind or "new") :: any, ref = if ref and ref ~= "" then ref else nil }
		return ui.column {
			id = id,
			w_full = true,
			h_full = true,
			items = "stretch",
			header(id, s, a),
			ui.column { grow = 1, min_h = 0, w_full = true, items = "stretch", body(id, s, a) },
		}
	end, { w_full = true, h_full = true })
end

return M
