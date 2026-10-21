-- Coding agents running in panes, and what each is doing: what the sidebar
-- lists. A program that reports its own status (the Program Status Protocol,
-- OSC 7501) is taken at its word. For agents that do not (Claude Code and
-- Codex today), it is worked out from what they do show: a progress report
-- (OSC 9;4), Claude Code's title spinner, and their notifications and bell
-- (attention.luau).
local state = require("./state")
local sessions = require("./sessions")
local actions = require("./actions")
local attention = require("./attention")
local icons = require("./icons")
local names = require("@lib/names")
local layout = require("@lib/layout")

local M = {}

-- What an agent is doing, in the protocol's words: it needs the user
-- (blocked), failed (error), finished and unseen (done), runs (working), or
-- waits for its next instruction (idle).
export type Status = "blocked" | "error" | "done" | "working" | "idle"

export type Agent = {
	pane: string,
	tab: string,
	status: Status,
	-- With "blocked": what for ("permission", "question", "auth").
	kind: string?,
	-- What it works on (its title), and where (its directory).
	name: string,
	where: string,
	icon: icons.Name,
	tint: string?,
	-- When its status began (Unix seconds).
	since: number,
}

-- The sidebar's order: what needs the user first, what rests last.
M.ORDER = { blocked = 1, error = 2, done = 3, working = 4, idle = 5 } :: { [Status]: number }

-- Per pane, what the sidebar remembers between changes: whether its agent
-- was working, since when, whether it finished while the user looked away,
-- and when the user last looked (gave the pane focus).
type Memory = { working: boolean, since: number, done: boolean, seen: number }
local memory = ui.state("memory", {} :: { [string]: Memory })

-- Every terminal pane, with its tab.
local function panes(): { { pane: string, tab: string } }
	local out = {}
	for _, tab in state.tabs:get() do
		for _, pane in layout.leaves(tab.root) do
			if not sessions.is_browser(pane) then
				table.insert(out, { pane = pane, tab = tab.id })
			end
		end
	end
	return out
end

-- Whether what runs in `t` is an agent the sidebar lists.
local function is_agent(t: Term): boolean
	return t.status ~= nil or names.agent(t.process) ~= nil
end

-- Whether the agent shows it is working (without reporting it).
local function shows_work(t: Term): boolean
	if t.progress ~= nil and not t.progress_error then
		return true
	end
	return names.title_working(t.title) == true
end

-- Remember transitions as they happen: finishing while the user looks away
-- makes "done" until they look; looking clears that and any notification.
ui.effect(function()
	local now = os.time()
	for _, p in panes() do
		local t = ui.term(p.pane)
		if is_agent(t) then
			local working = shows_work(t)
			local focused = t.focused
			local m = (memory:peek())[p.pane]
			local next: Memory = if m
				then table.clone(m)
				else { working = working, since = now, done = false, seen = 0 }
			if m and m.working ~= working then
				next.working, next.since = working, now
				next.done = not working and not focused
				if working then
					attention.clear(p.pane)
				end
			end
			if focused then
				next.seen, next.done = now, false
				attention.clear(p.pane)
			end
			if not m or next.working ~= m.working or next.done ~= m.done or next.seen ~= m.seen then
				memory:set_key(p.pane, next)
			end
		end
	end
end)

-- A pane's agent's status, and since when.
local function status_of(t: Term, m: Memory?, note: attention.Note?): (Status, string?, number)
	local mem = m or { working = false, since = os.time(), done = false, seen = 0 }
	local reported = t.status
	if reported then
		if reported.child_blocked and reported.state ~= "error" then
			return "blocked", reported.kind, reported.since
		end
		-- "done" means unseen: once the user has looked, it rests.
		if reported.state == "done" and mem.seen >= reported.since then
			return "idle", nil, reported.since
		end
		return reported.state, reported.kind, reported.since
	end
	if t.progress_error then
		return "error", nil, mem.since
	end
	if note and note.kind == "permission" then
		return "blocked", "permission", note.at
	end
	if mem.working then
		return "working", nil, mem.since
	end
	if mem.done or note then
		return "done", nil, if note then note.at else mem.since
	end
	return "idle", nil, mem.since
end

-- Every agent, sorted: by status, then the most recent change first.
M.list = ui.computed(function(): { Agent }
	local out: { Agent } = {}
	local remembered = memory:get()
	local notes = attention.notes:get()
	for _, p in panes() do
		local t = ui.term(p.pane)
		if is_agent(t) then
			local status, kind, since = status_of(t, remembered[p.pane], notes[p.pane])
			local desc = names.describe(t, state.home)
			local dir = names.path_of(t.pwd)
			local where = if dir ~= "" then names.short(dir, state.home) else ""
			-- A title that only repeats the directory or the command line
			-- ("claude --resume") says less than the agent's name.
			local name = desc.name
			local command = name:sub(1, #t.process + 1)
			local base = dir:match("([^/]+)/*$")
			if name == where or name == dir or name == base or command == t.process or command == t.process .. " " then
				name = names.label(t.process)
			end
			table.insert(out, {
				pane = p.pane,
				tab = p.tab,
				status = status,
				kind = kind,
				name = name,
				where = where,
				icon = desc.icon,
				tint = desc.tint,
				since = since,
			})
		end
	end
	table.sort(out, function(a: Agent, b: Agent)
		if a.status ~= b.status then
			return M.ORDER[a.status] < M.ORDER[b.status]
		end
		return a.since > b.since
	end)
	return out
end)

-- Show `agent`'s tab and give its pane focus (out of a zoom on another).
function M.open(agent: Agent)
	local zoomed = (state.zoom:peek())[agent.tab]
	if zoomed and zoomed ~= agent.pane then
		state.zoom:set_key(agent.tab, nil)
	end
	actions.focus_pane(agent.tab, agent.pane)
	actions.activate(agent.tab)
end

return M
