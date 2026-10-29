-- History as a right-pane surface (history.rs): the branch's commits with
-- their graph. A 40-high header holds the branch's name, "{n} commits" and
-- how far it is ahead of and behind its base, then the search (24×196),
-- "Fetch all", the branch tips' toggle (Show branch tips: a commit per
-- branch; Show all commits) and Refresh. A failed fetch says so in a band
-- over the rows; the search finding none says "No matching commits", the
-- tips none "No branch tips found"; "Load more" ends the list. A click
-- opens the commit's own diff in a tab of its own; a tip's fold hides its
-- branch's plain commits. The rows are built once per change of what
-- shows, not per key.
local T = require("../theme")
local kit = require("@kit")
local history = require("@kit/history")
local data = require("./data")
local state = require("./state")

local M = {}

-- Commits whose subject, author or SHA hold `query` (any case).
function M.matching(query: string, commits: { history.Commit }?): { history.Commit }
	local q = string.lower(query)
	local out: { history.Commit } = {}
	for _, c in commits or data.COMMITS do
		if
			q == ""
			or string.find(string.lower(c.subject), q, 1, true)
			or string.find(string.lower(c.author), q, 1, true)
			or string.find(c.sha, q, 1, true)
		then
			table.insert(out, c)
		end
	end
	return out
end

-- Each branch's tip alone, unlinked (its parents are seldom tips).
function M.tips(commits: { history.Commit }): { history.Commit }
	local out: { history.Commit } = {}
	for _, c in commits do
		if c.refs and #c.refs > 0 then
			local tip = table.clone(c)
			tip.parents = {}
			table.insert(out, tip)
		end
	end
	return out
end

-- The commits with each folded branch's plain run hidden (history.rs
-- collapse_branch_runs): in the lane of its tip, those with no ref that
-- neither merge nor branch off; and how many each branch hides.
function M.fold(commits: { history.Commit }, folded: { [string]: boolean }): ({ history.Commit }, { [string]: number })
	local lanes: { [number]: string } = {}
	for _, c in commits do
		for _, r in c.refs or {} do
			local b = history.branch(r)
			if b and folded[b] then
				lanes[c.lane] = b
			end
		end
	end
	local out: { history.Commit } = {}
	local hidden: { [string]: number } = {}
	for b in folded do
		hidden[b] = 0
	end
	for _, c in commits do
		local b = lanes[c.lane]
		local plain = (c.refs == nil or #c.refs == 0) and #c.parents == 1 and c.parents[1] == c.lane
		if b and plain then
			hidden[b] += 1
		else
			table.insert(out, c)
		end
	end
	return out, hidden
end

function M.view(id: string): Node
	local query = ui.state(`{id}_query`, "")
	local fetching = ui.state(`{id}_fetching`, false)
	local fetches = ui.state(`{id}_fetches`, 0)
	local failed = ui.state(`{id}_failed`, "")
	local tips = ui.state(`{id}_tips`, false)
	local folded = ui.state(`{id}_folded`, {} :: { [string]: boolean })
	-- The user's columns, every history's (ui-settings.json).
	local columns = ui.state("history_columns", history.default_columns())

	local function shown(): ({ history.Commit }, { [string]: number })
		local list = if tips:get() then M.tips(data.COMMITS) else data.COMMITS
		local hidden = {}
		if not tips:get() then
			list, hidden = M.fold(list, folded:get())
		end
		return M.matching(query:get(), list), hidden
	end
	local key = ui.computed(function(): string
		local list, hidden = shown()
		local parts = {}
		for _, c in list do
			table.insert(parts, c.sha)
		end
		for b, n in hidden do
			table.insert(parts, `{b}={n}`)
		end
		return `{tips:get()}|{table.concat(parts, ",")}`
	end)

	local function fetch()
		if fetching:peek() then
			return
		end
		fetching:set(true)
		ui.after(900, function()
			fetching:set(false)
			fetches:set(fetches:peek() + 1)
			failed:set(data.fetch(fetches:peek()) or "")
		end)
	end

	local function control(button: Node, label: string): Node
		return kit.tooltip { label = label, button }
	end

	local count = kit.text.text {
		function()
			local n = #data.COMMITS
			return `{n} {if n == 1 then "commit" else "commits"}`
		end,
		size = "xs",
		color = T.secondary,
		line = false,
		shrink = 0,
	}
	local c = data.COMPARISON
	local comparison = kit.tooltip {
		label = `Compared with {c.base}: {c.ahead} ahead, {c.behind} behind`,
		ui.row {
			id = `{id}_comparison`,
			gap = "$zeron.space.4",
			items = "center",
			shrink = 0,
			c.ahead > 0 and kit.text.text {
				`{c.ahead} ahead`,
				size = "micro",
				color = T.accent,
				opacity = 0.88,
				line = false,
			} or nil,
			c.ahead > 0 and c.behind > 0 and kit.text.text { "·", size = "micro", color = T.tertiary, line = false }
				or nil,
			c.behind > 0 and kit.text.text {
				`{c.behind} behind`,
				size = "micro",
				color = T.warning,
				opacity = 0.82,
				line = false,
			} or nil,
		},
	}

	local head = ui.row {
		w_full = true,
		h = 40,
		px = "$zeron.space.8",
		gap = "$zeron.space.4",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		kit.text.text {
			data.BRANCH,
			literal = true,
			size = "sm",
			mono = true,
			color = T.secondary,
			truncate = true,
			line = false,
			max_w = 160,
			shrink = 1,
			min_w = 0,
			px = "$zeron.space.8",
		},
		ui.row {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.10",
			items = "center",
			overflow = "hidden",
			count,
			(c.ahead > 0 or c.behind > 0) and comparison or nil,
		},
		history.search { id = `{id}_search`, value = query },
		ui.button {
			id = `{id}_fetch`,
			variants = kit.recipes.wash { hover = "ink3" },
			h = 24,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			items = "center",
			rounded = T.radius_md,
			focus = { border = 0 },
			cursor = "pointer",
			on_click = fetch,
			kit.icon { name = "cloud", size = 14, color = T.secondary },
			kit.text.text {
				function()
					return if fetching:get() then "Fetching…" else "Fetch all"
				end,
				size = "xs",
				color = T.secondary,
				line = false,
			},
		},
		ui.presence(tips, function(on: boolean): Node
			local label = if on then "Show all commits" else "Show branch tips"
			return control(
				kit.icon_button {
					id = `{id}_view`,
					icon = "fold-vertical",
					size = 24,
					icon_size = 14,
					label = label,
					no_ring = true,
					color = if on then T.accent else nil,
					selected = on,
					on_click = ui.toggle(tips),
				},
				label
			)
		end),
		control(
			kit.icon_button {
				id = `{id}_refresh`,
				icon = "refresh",
				size = 24,
				icon_size = 14,
				label = "Refresh",
				no_ring = true,
				on_click = function()
					folded:set {}
					query:set("")
				end,
			},
			"Refresh"
		),
	}

	-- A failed fetch (history.rs fetch_error): 28 high on danger at 5%.
	local band = ui.show(
		function()
			return failed:get() ~= ""
		end,
		ui.row {
			id = `{id}_fetch_failed`,
			w_full = true,
			h = 28,
			px = "$zeron.space.8",
			items = "center",
			shrink = 0,
			bg = T.danger_wash,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.danger_wash,
			kit.text.text {
				function()
					return `Fetch failed: {failed:get()}`
				end,
				size = "xs",
				color = T.danger,
				truncate = true,
				line = false,
			},
		}
	)

	return ui.column {
		id = id,
		w_full = true,
		h_full = true,
		items = "stretch",
		head,
		band,
		ui.presence(key, function(): Node
			local list, hidden = shown()
			if #list == 0 then
				return ui.column {
					grow = 1,
					w_full = true,
					items = "center",
					justify = "center",
					kit.text.text {
						if query:peek() ~= ""
							then "No matching commits"
							elseif tips:peek() then "No branch tips found"
							else "No commits found",
						size = "sm",
						color = T.tertiary,
						line = false,
					},
				}
			end
			local shut: { [string]: number } = {}
			for b in folded:peek() do
				shut[b] = hidden[b] or 0
			end
			return kit.scroll {
				grow = 1,
				w_full = true,
				label = "History",
				ui.column {
					w_full = true,
					gap = "$zeron.space.12",
					pb = "$zeron.space.16",
					items = "stretch",
					history.table {
						id = `{id}_commits`,
						commits = list,
						on_open = function(c: history.Commit)
							state.open_commit(c.sha)
						end,
						columns = columns,
						folded = shut,
						on_fold = if tips:peek()
							then nil
							else function(b: string)
								folded:set_key(b, if folded:peek()[b] then nil else true)
							end,
					},
					ui.row { px = "$zeron.space.12", history.more { id = `{id}_more` } },
				},
			}
		end, { grow = 1, w_full = true, min_h = 0 }),
	}
end

return M
