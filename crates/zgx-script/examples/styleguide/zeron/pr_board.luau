-- The pull requests' board (pull_requests.rs): one repository's open pull
-- requests on one desktop device. Its header: the title and count, refresh
-- (its freshness in the tooltip), the repository (the projects' checkouts,
-- recent ones, or one typed) and the device; the filters (Authored,
-- Reviewing, All), the search and the sort; Needs you and Starred. Then
-- Zeron's groups (Needs attention, Awaiting review, Approved, Drafts) in
-- one virtual list, "Load more" at its foot; the skeleton while the first
-- page reads; what an empty or failed board says. Authored is the board's
-- own choice until the user picks: empty, it falls back to All. A failed
-- refresh keeps what showed and says so once. GitHub's answers are sample
-- data (zeron/pr_data), read with a little latency.
local T = require("../theme")
local kit = require("@kit")
local pr = require("@kit/pr")
local data = require("./data")
local pr_data = require("./pr_data")
local handoff = require("./pr_handoff")
local state = require("./state")
local chrome = require("./chrome")

local M = {}

-- How long GitHub takes to answer, through `gh` on the device.
M.LOAD = 400

export type Filter = "authored" | "reviewing" | "all"
export type View = "everything" | "needs_you" | "starred"
export type Sort = "updated_desc" | "updated_asc" | "opened_desc" | "opened_asc" | "changes_desc" | "changes_asc"
export type Group = "attention" | "review" | "approved" | "drafts"
-- PullRequestsPageError.
export type Failure = "cli" | "auth" | "rate" | "network" | "offline" | "update"
export type Props = {
	-- Stars (local preferences), by pull request.
	stars: State<{ [string]: boolean }>,
	-- A row's click: beside the board, or where General says.
	open: (id: string) -> (),
}

local GROUPS: { { id: Group, label: string } } = {
	{ id = "attention", label = "Needs attention" },
	{ id = "review", label = "Awaiting review" },
	{ id = "approved", label = "Approved" },
	{ id = "drafts", label = "Drafts" },
}
local SORTS: { { id: Sort, label: string } } = {
	{ id = "updated_desc", label = "Recently updated" },
	{ id = "updated_asc", label = "Least recently updated" },
	{ id = "opened_desc", label = "Newest first" },
	{ id = "opened_asc", label = "Oldest first" },
	{ id = "changes_desc", label = "Largest changes" },
	{ id = "changes_asc", label = "Smallest changes" },
}

-- ---- what GitHub answers --------------------------------------------------

local function row_of(id: string): pr.Row?
	for _, list in { data.PRS, data.MORE_PRS } do
		for _, r in list do
			if r.id == id then
				return r
			end
		end
	end
	return nil
end
local function detail_of(id: string): pr_data.Detail
	return pr_data.DETAILS[id] or pr_data.DETAILS.p1
end

-- What the board's rows say of it (status_description): open or draft,
-- its blockers, approved, what asks for the viewer.
local function attention(d: pr_data.Detail): { string }
	local out: { string } = {}
	if d.state ~= "OPEN" then
		return out
	end
	if d.requested and not d.draft then
		table.insert(out, "Your review requested")
	end
	if d.review == "CHANGES_REQUESTED" and d.authored then
		table.insert(out, "Your PR needs changes")
	end
	if d.ci == "failed" and (d.authored or d.requested) then
		table.insert(out, "Your CI needs attention")
	end
	return out
end
function M.description(id: string): string
	local d = detail_of(id)
	local labels = { if d.draft then "Draft" else "Open" }
	for _, b in handoff.assess(d).blockers do
		table.insert(labels, b)
	end
	if d.review == "APPROVED" then
		table.insert(labels, "Approved")
	end
	for _, a in attention(d) do
		if a ~= "Your CI needs attention" then
			table.insert(labels, a)
		end
	end
	return table.concat(labels, " · ")
end

-- Its group (request_group): drafts apart; anything blocked or asking for
-- the viewer needs attention; then approved, or awaiting review.
function M.group_of(id: string): Group
	local d = detail_of(id)
	if d.draft then
		return "drafts"
	elseif #handoff.assess(d).blockers > 0 or #attention(d) > 0 then
		return "attention"
	elseif d.review == "APPROVED" then
		return "approved"
	end
	return "review"
end

type Page = { items: { string }, next: number?, total: number }
-- Page `page` of `repo`'s pull requests on `device` under `filter`, or
-- why GitHub would not say.
local function answer(repo: string, filter: Filter, device: string, page: number): (Page?, Failure?)
	if not data.ONLINE[device] then
		return nil, "offline"
	end
	local fails = pr_data.FAILS[repo]
	if fails then
		return nil, fails :: Failure
	end
	local all = pr_data.BOARD[repo]
	if not all then
		return nil, "network"
	end
	local matching: { string } = {}
	for _, id in all do
		local d = detail_of(id)
		if filter == "all" or (filter == "authored" and d.authored) or (filter == "reviewing" and d.requested) then
			table.insert(matching, id)
		end
	end
	local items = {}
	for i = (page - 1) * pr_data.PAGE + 1, math.min(page * pr_data.PAGE, #matching) do
		table.insert(items, matching[i])
	end
	return {
		items = items,
		next = if page * pr_data.PAGE < #matching then page + 1 else nil,
		total = #matching,
	},
		nil
end

-- `minutes` ago, as a row says it (compact_relative_time).
function M.ago(minutes: number): string
	if minutes < 1 then
		return "now"
	elseif minutes < 60 then
		return `{math.floor(minutes)}m ago`
	elseif minutes < 1440 then
		return `{math.floor(minutes / 60)}h ago`
	elseif minutes < 10080 then
		return `{math.floor(minutes / 1440)}d ago`
	elseif minutes < 43200 then
		return `{math.floor(minutes / 10080)}w ago`
	end
	return `{math.floor(minutes / 43200)}mo ago`
end

-- What a failure says (error_copy): its title and what to do.
function M.error_copy(failure: Failure, device: string): (string, string)
	if failure == "cli" then
		return "GitHub CLI isn’t available on this device", "Install gh and sign in to view your pull requests."
	elseif failure == "auth" then
		return "Sign in to GitHub on this device", "Run gh auth login, then refresh this page."
	elseif failure == "rate" then
		return "GitHub’s rate limit was reached",
			"Requests are paused for 15 minutes. Your loaded results stay available."
	elseif failure == "offline" then
		return `{device} is offline`, "Reconnect the device and try again."
	elseif failure == "update" then
		return `Update Zeron on {device}`, "This device doesn’t support pull requests yet."
	end
	return "Couldn’t load pull requests", "Check the repository name and your connection, then try again."
end

-- ---- what has loaded --------------------------------------------------------

M.repository = ui.state("prs_repository", "zeron/comet")
M.device = ui.state("prs_device", data.THIS)
M.filter = ui.state("prs_filter", "authored" :: Filter)
M.query = ui.state("prs_query", "")
M.sort = ui.state("prs_sort", "updated_desc" :: Sort)
M.view_mode = ui.state("prs_view", "everything" :: View)
local collapsed = ui.state("prs_collapsed", {} :: { [string]: boolean })
-- The pull requests read, in GitHub's order; how the read stands; why it
-- failed; when it was read; the next page, and how many there are.
local items = ui.state("prs_items", {} :: { string })
local phase = ui.state("prs_phase", "idle" :: "idle" | "loading" | "ready" | "failed")
local failure = ui.state("prs_failure", nil :: Failure?)
local refreshing = ui.state("prs_refreshing", false)
local loaded_at = ui.state("prs_loaded_at", nil :: number?)
local next_page = ui.state("prs_next", nil :: number?)
local total = ui.state("prs_total", 0)
local more = ui.state("prs_more", "" :: "" | "loading" | "failed")
-- Authored until the user picks: an empty one falls back to All. The
-- filter each repository was last read under, on each device, comes back
-- with it (scope_filters).
local automatic = true
local remembered: { [string]: Filter } = {}
local function scope(): string
	return `{M.device:peek()}|{M.repository:peek()}`
end
-- Bumps as what the board reads changes: a reply for what it has left is
-- dropped.
local generation = 0
-- Repositories whose next refresh times out (`pr_data.FLAKY`), once.
local flaked: { [string]: boolean } = {}
-- Repositories opened here, most recent first (the menu's recent ones).
local recent = ui.state("prs_recent", { "zeron/comet" } :: { string })

local function load(refresh: boolean)
	generation += 1
	local this = generation
	local repo, device = M.repository:peek(), M.device:peek()
	local filter: Filter = M.filter:peek()
	local had = #items:peek() > 0
	if had then
		refreshing:set(true)
	else
		phase:set("loading")
	end
	more:set("")
	ui.after(M.LOAD, function()
		if this ~= generation then
			return
		end
		refreshing:set(false)
		local page, why = answer(repo, filter, device, 1)
		if refresh and pr_data.FLAKY[repo] and not flaked[repo] then
			flaked[repo] = true
			page, why = nil, "network"
		end
		if page and #page.items == 0 and not refresh and automatic and filter == "authored" then
			M.filter:set("all")
			filter = "all"
			page, why = answer(repo, filter, device, 1)
		end
		if not page then
			if had then
				-- What showed stays, and says so once.
				local title = M.error_copy(why :: Failure, device)
				kit.toast.push { title = title, description = "Showing the last loaded results.", tone = "danger" }
				return
			end
			failure:set(why)
			phase:set("failed")
			return
		end
		automatic = false
		remembered[`{device}|{repo}`] = filter
		items:set(page.items)
		next_page:set(page.next)
		total:set(page.total)
		failure:set(nil)
		loaded_at:set(ui.now())
		phase:set("ready")
	end)
end

-- Another repository, device or filter: the board starts over. Another
-- repository or device comes back under its own filter (Authored, the
-- board's own choice, if it has none).
local function reset(rescope: boolean?)
	if rescope then
		local known = remembered[scope()]
		automatic = known == nil
		M.filter:set(known or "authored")
	end
	items:set {}
	next_page:set(nil)
	total:set(0)
	loaded_at:set(nil)
	failure:set(nil)
	load(false)
end

function M.refresh()
	if phase:peek() == "loading" or refreshing:peek() then
		return
	end
	load(true)
end

local function load_more()
	local page = next_page:peek()
	if not page or more:peek() == "loading" or phase:peek() == "loading" then
		return
	end
	local this = generation
	local repo, filter, device = M.repository:peek(), M.filter:peek(), M.device:peek()
	more:set("loading")
	ui.after(M.LOAD, function()
		if this ~= generation then
			return
		end
		local next, why = answer(repo, filter, device, page)
		if not next then
			more:set("failed")
			kit.toast.push { title = (M.error_copy(why :: Failure, device)), tone = "danger" }
			return
		end
		local list = table.clone(items:peek())
		for _, id in next.items do
			if not table.find(list, id) then
				table.insert(list, id)
			end
		end
		items:set(list)
		next_page:set(next.next)
		total:set(next.total)
		more:set("")
	end)
end

function M.select_filter(f: Filter)
	automatic = false
	if M.filter:peek() == f then
		return
	end
	M.filter:set(f)
	reset()
end

-- Owner/name, as GitHub spells them (valid_repository_filter).
function M.valid(repo: string): boolean
	local owner, name = string.match(repo, "^([%w%-_%.]+)/([%w%-_%.]+)$")
	return owner ~= nil and owner ~= "." and owner ~= ".." and name ~= "." and name ~= ".."
end

function M.select_repository(repo: string): boolean
	repo = string.lower(string.match(repo, "^%s*(.-)%s*$") or "")
	if not M.valid(repo) then
		kit.toast.push { title = "Enter a repository as owner/name.", tone = "danger" }
		return false
	end
	local list = { repo }
	for _, r in recent:peek() do
		if r ~= repo and #list < 5 then
			table.insert(list, r)
		end
	end
	recent:set(list)
	if M.repository:peek() ~= repo then
		M.repository:set(repo)
		reset(true)
	elseif loaded_at:peek() == nil then
		load(false)
	end
	return true
end

function M.select_device(name: string)
	if M.device:peek() ~= name then
		M.device:set(name)
		reset(true)
	end
end

-- ---- what shows ---------------------------------------------------------------

local function matches(id: string, query: string): boolean
	local r = row_of(id)
	if not r then
		return false
	end
	local d = detail_of(id)
	local text = string.lower(`{r.title} {d.repository} #{r.number} {M.description(id)} {r.author}`)
	for word in string.gmatch(string.lower(query), "%S+") do
		if not string.find(text, word, 1, true) then
			return false
		end
	end
	return true
end

-- The read pull requests the search keeps, sorted (sort_pull_requests:
-- ties by repository, then number).
local function sorted(): { string }
	local query = M.query:get()
	local out: { string } = {}
	for _, id in items:get() do
		if matches(id, query) then
			table.insert(out, id)
		end
	end
	local how = M.sort:get()
	local function value(id: string): number
		local r = row_of(id) :: pr.Row
		if string.match(how, "^changes") then
			return r.added + r.removed
		elseif string.match(how, "^opened") then
			-- Minutes since: the newest is the smallest.
			return -(r.opened or 0)
		end
		return -(r.updated or 0)
	end
	local descending = string.match(how, "_desc$") ~= nil
	table.sort(out, function(a: string, b: string): boolean
		local va, vb = value(a), value(b)
		if va ~= vb then
			return if descending then va > vb else va < vb
		end
		local ra, rb = row_of(a) :: pr.Row, row_of(b) :: pr.Row
		local da, db = detail_of(a).repository, detail_of(b).repository
		if da ~= db then
			return da < db
		end
		return if descending then ra.number > rb.number else ra.number < rb.number
	end)
	return out
end

-- Those the personal view keeps (Needs you, Starred).
local function shown(stars: State<{ [string]: boolean }>): { string }
	local view = M.view_mode:get()
	local out: { string } = {}
	for _, id in sorted() do
		if
			view == "everything"
			or (view == "needs_you" and #attention(detail_of(id)) > 0)
			or (view == "starred" and stars:get()[id] == true)
		then
			table.insert(out, id)
		end
	end
	return out
end

type BoardRow = {
	key: string,
	-- "group", "item" or "footer".
	kind: string,
	group: Group?,
	label: string?,
	count: number?,
	closed: boolean?,
	first: boolean?,
	last: boolean?,
	id: string?,
}

-- ---- the header ----------------------------------------------------------------

-- A header button (HEADER_CONTROL_HEIGHT 32, radius 6, the ink wash under
-- the pointer).
local function control(props: {
	id: string,
	label: string | () -> string,
	tip: string | () -> string,
	w: number?,
	dim: (() -> boolean)?,
	on_click: Handler | Action,
	[number]: Child,
}): Node
	return ui.button {
		id = props.id,
		label = props.label,
		tooltip = pr.tip(props.tip),
		h = 32,
		w = props.w,
		min_w = 32,
		px = if props.w then 0 else "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		justify = "center",
		shrink = 0,
		rounded = "$zeron.radius.6",
		focus = { border = 0 },
		cursor = "pointer",
		variants = kit.recipes.wash { hover = "ink2" },
		opacity = if props.dim
			then function()
				return if (props.dim :: () -> boolean)() then 0.5 else 1
			end
			else nil,
		on_click = props.on_click,
		{ table.unpack(props) },
	}
end

local function refresh_button(): Node
	return control {
		id = "prs_refresh",
		label = "Refresh pull requests",
		tip = function()
			local at = loaded_at:get()
			if not at then
				return "Refresh pull requests"
			end
			local minutes = math.floor((ui.now() - at) / 60000)
			return if minutes < 1
				then "Loaded just now · Refresh pull requests"
				else `Loaded {minutes}m ago · Refresh pull requests`
		end,
		w = 32,
		dim = function()
			return phase:get() == "loading" or refreshing:get()
		end,
		on_click = M.refresh,
		ui.presence(function()
			return if refreshing:get() then "spinning" else "still"
		end, function(how: string): Node
			if how == "spinning" then
				return kit.loaders.ring { id = "prs_refresh_spinner", size = 13 }
			end
			return kit.icon { name = "refresh", size = 16, color = T.secondary }
		end),
	}
end

-- The repository's menu (render_repository_menu): a field for owner/name
-- with Open, the projects' checkouts, then the repositories opened here.
local function repository_menu(): Node
	local open = ui.state("prs_repository_open", false)
	local typed = ui.state("prs_repository_typed", "")
	local function choose(repo: string)
		if M.select_repository(repo) then
			open:set(false)
		end
	end
	local function option(id: string, label: string, art: Node, selected: () -> boolean, repo: string): Node
		return ui.button {
			id = id,
			label = `Open {repo}`,
			w_full = true,
			h = 32,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			rounded = T.radius_item,
			variants = kit.recipes.picker_choice { selected = selected },
			color = T.text,
			focus = { border = 0 },
			cursor = "pointer",
			on_click = function()
				choose(repo)
			end,
			ui.row { w = 16, h = 16, shrink = 0, items = "center", justify = "center", art },
			kit.text.text {
				label,
				literal = true,
				size = "md",
				color = "inherit",
				truncate = true,
				grow = 1,
				min_w = 0,
				line = false,
			},
		}
	end
	local function heading(label: string): Node
		return ui.row {
			px = "$zeron.space.8",
			pt = "$zeron.space.6",
			pb = "$zeron.space.4",
			kit.text.text { label, size = "xs", weight = "medium", color = T.tertiary, line = false },
		}
	end
	local function content(): Node
		local rows: { Node } = { heading("Projects") }
		for _, p in pr_data.PROJECTS do
			table.insert(
				rows,
				option(`prs_project_{p.name}`, p.name, kit.project_icon.icon { name = p.name, size = 14 }, function()
					return M.repository:get() == p.repository
				end, p.repository)
			)
		end
		local others: { string } = {}
		for _, r in recent:peek() do
			local project = false
			for _, p in pr_data.PROJECTS do
				project = project or p.repository == r
			end
			if not project then
				table.insert(others, r)
			end
		end
		if #others > 0 then
			table.insert(rows, heading("Recent repositories"))
			for _, r in others do
				table.insert(
					rows,
					option(
						`prs_recent_{string.gsub(r, "[^%w]", "_")}`,
						r,
						kit.icon { name = "folder", size = 14, color = T.secondary },
						function()
							return M.repository:get() == r
						end,
						r
					)
				)
			end
		end
		return ui.column {
			w_full = true,
			gap = "$zeron.space.2",
			ui.row {
				h = 40,
				w_full = true,
				shrink = 0,
				mx = T.pull(4),
				mt = T.pull(4),
				mb = "$zeron.space.4",
				pl = "$zeron.space.10",
				pr = "$zeron.space.6",
				gap = "$zeron.space.8",
				items = "center",
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				kit.icon { name = "magnifer", size = 14, color = T.secondary },
				ui.input {
					id = "prs_repository_input",
					value = typed,
					label = "Repository",
					placeholder = "owner/repository",
					placeholder_color = T.tertiary,
					grow = 1,
					min_w = 0,
					p = 0,
					border = 0,
					rounded = 0,
					bg = T.clear,
					focus = { border = 0, bg = T.clear },
					text_size = "$font.size.md",
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = function(e: KeyEvent): boolean
						if e.key == "Enter" then
							choose(typed:peek())
							return true
						elseif e.key == "Escape" then
							open:set(false)
							return true
						end
						return false
					end,
				},
				ui.button {
					id = "prs_repository_load",
					label = "Open repository",
					h = 28,
					px = "$zeron.space.10",
					shrink = 0,
					items = "center",
					rounded = "$zeron.radius.6",
					variants = kit.recipes.wash { hover = "ink3" },
					focus = { border = 0 },
					cursor = "pointer",
					on_click = function()
						choose(typed:peek())
					end,
					kit.text.text { "Open", size = "sm", line = false },
				},
			},
			ui.scroll { w_full = true, max_h = 360, fade = { 12, 12 }, fade_overflow = true, rows },
		}
	end
	return kit.popover {
		id = "prs_repository_card",
		open = open,
		label = "Repository",
		w = 320,
		p = "$zeron.space.4",
		placement = { side = "bottom", align = "end", offset = 6 },
		anchor = control {
			id = "prs_repository",
			label = function()
				return `Repository: {M.repository:get()}`
			end,
			tip = function()
				return M.repository:get()
			end,
			on_click = function()
				typed:set(M.repository:peek())
				open:set(not open:peek())
			end,
			ui.presence(function()
				for _, p in pr_data.PROJECTS do
					if p.repository == M.repository:get() then
						return p.name
					end
				end
				return ""
			end, function(name: string): Node
				if name ~= "" then
					return kit.project_icon.icon { name = name, size = 14 }
				end
				return kit.icon { name = "folder-with-files", size = 14, color = T.secondary }
			end),
			kit.text.text {
				function()
					return M.repository:get()
				end,
				id = "prs_repository_label",
				size = "sm",
				truncate = true,
				max_w = 180,
				min_w = 0,
				line = false,
			},
			kit.icon { name = "alt-arrow-down", size = 12, color = T.secondary },
		},
		ui.presence(function()
			return if open:get() then true else nil
		end, content, { w_full = true }),
	}
end

-- The desktop device the board reads from (render_device_switcher): a
-- menu of them, this one and the offline ones said so.
local function device_menu(): Node
	local open = ui.state("prs_device_open", false)
	local items: { any } = { { heading = "Desktop devices" } }
	for i, name in pr_data.DEVICES do
		local details: { string } = {}
		if name == data.THIS then
			table.insert(details, "This device")
		end
		if not data.ONLINE[name] then
			table.insert(details, "Offline")
		end
		table.insert(items, {
			id = `prs_device_{i}`,
			label = name,
			icon = if name == "Cloud" then "monitor" else "laptop",
			detail = if #details > 0 then table.concat(details, " · ") else nil,
			checked = function()
				return M.device:get() == name
			end,
			on_click = function()
				M.select_device(name)
			end,
		})
	end
	return kit.menu {
		id = "prs_device_menu",
		open = open,
		label = "Desktop devices",
		items = items,
		w = 240,
		rows = "popover",
		placement = { side = "bottom", align = "end", offset = 6 },
		anchor = control {
			id = "prs_device",
			label = function()
				return `Desktop device: {M.device:get()}`
			end,
			tip = function()
				return M.device:get()
			end,
			on_click = ui.toggle(open),
			ui.presence(function()
				return if M.device:get() == "Cloud" then "monitor" else "laptop"
			end, function(glyph: string): Node
				return kit.icon { name = glyph :: any, size = 16, color = T.secondary }
			end),
			kit.text.text {
				function()
					return M.device:get()
				end,
				size = "sm",
				weight = "medium",
				truncate = true,
				max_w = 130,
				min_w = 0,
				line = false,
			},
			kit.icon { name = "alt-arrow-down", size = 14, color = T.tertiary },
		},
	}
end

-- The sort (render_sort_menu): its direction's arrow, the six orders.
local function sort_menu(): Node
	local open = ui.state("prs_sort_open", false)
	local items: { any } = {}
	for _, s in SORTS do
		table.insert(items, {
			id = `prs_sort_{s.id}`,
			label = s.label,
			checked = function()
				return M.sort:get() == s.id
			end,
			on_click = function()
				M.sort:set(s.id)
			end,
		})
	end
	local function label(): string
		for _, s in SORTS do
			if s.id == M.sort:get() then
				return s.label
			end
		end
		return ""
	end
	return kit.menu {
		id = "prs_sort_menu",
		open = open,
		label = "Sort pull requests",
		items = items,
		w = 220,
		rows = "popover",
		placement = { side = "bottom", align = "end", offset = 6 },
		anchor = control {
			id = "prs_sort",
			label = function()
				return `Sort pull requests: {label()}`
			end,
			tip = label,
			w = 32,
			on_click = ui.toggle(open),
			ui.presence(function()
				return if string.match(M.sort:get(), "_asc$") then "up" else "down"
			end, function(way: string): Node
				return kit.icon {
					name = if way == "up" then "arrow-up" else "arrow-down",
					size = 14,
					color = T.secondary,
				}
			end),
		},
	}
end

-- The search (32, radius 8, the input's frame): its glass, the field, and
-- a clear button once something is typed.
local function search(): Node
	return ui.row {
		grow = 1,
		min_w = 160,
		h = 32,
		pl = "$zeron.space.10",
		pr = "$zeron.space.4",
		gap = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.8",
		bg = T.ink2,
		kit.icon { name = "magnifer", size = 14, color = T.secondary },
		ui.input {
			id = "prs_search",
			value = M.query,
			label = "Search pull requests",
			placeholder = "Search pull requests",
			placeholder_color = T.tertiary,
			grow = 1,
			shrink = 1,
			min_w = 0,
			p = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			focus = { border = 0, bg = T.clear },
			text_size = "$font.size.sm",
		},
		ui.show(
			function()
				return M.query:get() ~= ""
			end,
			ui.button {
				id = "prs_clear_search",
				label = "Clear search",
				tooltip = pr.tip("Clear search"),
				w = 24,
				h = 24,
				p = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.4",
				variants = kit.recipes.wash { hover = "ink3" },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					M.query:set("")
				end,
				kit.icon { name = "close", size = 12, color = T.secondary },
			}
		),
	}
end

-- Needs you and Starred: pills in the tray's material, filled while on;
-- turning one on shows All.
local function view_pill(id: string, view: View, label: string, glyph: string, on_glyph: string): Node
	local function on(): boolean
		return M.view_mode:get() == view
	end
	return ui.button {
		id = id,
		label = label,
		selected = on,
		h = 28,
		pl = "$zeron.space.10",
		pr = "$zeron.space.12",
		gap = "$zeron.space.6",
		items = "center",
		shrink = 0,
		rounded = T.radius_full,
		focus = { border = 0 },
		cursor = "pointer",
		variants = kit.recipes.pr_view_pill { on = on },
		on_click = function()
			if on() then
				M.view_mode:set("everything")
			else
				M.view_mode:set(view)
				M.select_filter("all")
			end
		end,
		ui.presence(function()
			return if on() then "on" else "off"
		end, function(s: string): Node
			return kit.icon { name = (if s == "on" then on_glyph else glyph) :: any, size = 13, color = "currentColor" }
		end),
		kit.text.text { label, size = "sm", color = "inherit", line = false },
	}
end

local function header(rows: () -> { BoardRow }, count: () -> string?): Node
	return ui.column {
		id = "prs_header",
		w_full = true,
		max_w = 760,
		self = "center",
		px = "$zeron.space.40",
		pb = "$zeron.space.16",
		shrink = 0,
		ui.row {
			w_full = true,
			gap = "$zeron.space.12",
			items = "center",
			flex_wrap = true,
			ui.row {
				px = "$zeron.space.4",
				gap = "$zeron.space.10",
				items = "baseline",
				role = "heading",
				kit.text.text { "Pull requests", id = "prs_title", size = "xxl", weight = "medium", line = false },
				ui.presence(count, function(n: string): Node
					return kit.text.text { n, id = "prs_count", size = "md", color = T.secondary, line = false }
				end),
			},
			ui.div { grow = 1 },
			ui.row {
				gap = "$zeron.space.4",
				items = "center",
				flex_wrap = true,
				refresh_button(),
				repository_menu(),
				device_menu(),
			},
		},
		ui.row {
			w_full = true,
			mt = "$zeron.space.12",
			gap = "$zeron.space.12",
			items = "center",
			flex_wrap = true,
			kit.segmented {
				id = "prs_filter",
				label = "Pull requests to show",
				value = M.filter :: any,
				options = {
					{ id = "authored", label = "Authored" },
					{ id = "reviewing", label = "Reviewing" },
					{ id = "all", label = "All" },
				},
				on_change = function(id: string)
					M.select_filter(id :: Filter)
				end,
			},
			ui.row {
				grow = 1,
				min_w = 180,
				gap = "$zeron.space.8",
				items = "center",
				search(),
				sort_menu(),
			},
		},
		ui.row {
			mt = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			flex_wrap = true,
			view_pill("prs_view_needs_you", "needs_you", "Needs you", "bell", "bell"),
			view_pill("prs_view_starred", "starred", "Starred", "star", "star-bold"),
		},
		ui.presence(function()
			if M.query:get() == "" then
				return nil
			end
			local n = 0
			for _, r in rows() do
				if r.kind == "item" then
					n += 1
				end
			end
			return `{n} of {#items:get()} pull requests`
		end, function(words: string): Node
			return kit.text.text { words, id = "prs_matches", size = "xs", color = T.secondary, mt = "$zeron.space.8" }
		end),
	}
end

-- ---- the states ------------------------------------------------------------------

-- A quiet text action (empty_action): 28, its label at 12.
local function action(id: string, label: string, run: () -> ()): Node
	return ui.button {
		id = id,
		label = label,
		mt = "$zeron.space.16",
		h = 28,
		px = "$zeron.space.12",
		items = "center",
		rounded = "$zeron.radius.6",
		variants = kit.recipes.wash { rest = "ink2", hover = "ink3" },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = run,
		kit.text.text { label, size = "sm", weight = "medium", line = false },
	}
end

-- What an empty or failed board says (render_empty_or_error), with what
-- to do about it.
local function empty_or_error(): Node
	return ui.presence(function()
		local why = failure:get()
		return if phase:get() == "failed" and why then `failed:{why}` else `empty:{M.filter:get()}`
	end, function(key: string): Node
		local kind, which = string.match(key, "^(%a+):(%a+)$")
		local glyph, title, body = "pull-request", "", ""
		local actions: { Node } = {}
		if kind == "failed" then
			title, body = M.error_copy(which :: Failure, M.device:peek())
			glyph = if which == "auth"
				then "key-minimalistic"
				elseif which == "offline" then "wifi-off"
				else "info-circle"
			if which ~= "rate" then
				table.insert(actions, action("prs_retry", "Try again", M.refresh))
			end
		elseif which == "authored" then
			title, body =
				"No pull requests authored by you", "Your open pull requests in this repository will appear here."
		elseif which == "reviewing" then
			title, body = "No reviews requested", "Pull requests waiting for your review will appear here."
		else
			title, body =
				"No open pull requests", "This repository has no open pull requests. New ones will appear here."
		end
		if kind == "empty" and which ~= "all" then
			table.insert(
				actions,
				action("prs_empty_show_all", "Show all pull requests", function()
					M.select_filter("all")
				end)
			)
		end
		return ui.column {
			id = "prs_empty",
			w_full = true,
			mt = "$zeron.space.64",
			items = "center",
			kit.icon { name = glyph :: any, size = 24, color = T.secondary, mb = "$zeron.space.16" },
			kit.text.text {
				title,
				id = "prs_empty_title",
				size = "lg",
				weight = "semibold",
				align = "center",
				wrap = true,
				w = 420,
				max_w = "100%",
			},
			kit.text.text {
				body,
				id = "prs_empty_description",
				size = "md",
				color = T.secondary,
				align = "center",
				wrap = true,
				w = 420,
				max_w = "100%",
				mt = "$zeron.space.6",
			},
			actions,
		}
	end, { w_full = true })
end

-- What a search or a personal view that keeps nothing says.
local function no_results(): Node
	return ui.column {
		id = "prs_no_results",
		w_full = true,
		py = "$zeron.space.48",
		items = "center",
		kit.text.text {
			function()
				local view = M.view_mode:get()
				return if view == "needs_you"
					then "Nothing needs your attention"
					elseif view == "starred" then "No starred pull requests"
					else "No matching pull requests"
			end,
			size = "md",
			color = T.secondary,
			line = false,
		},
		action("prs_empty_clear_search", "Show all pull requests", function()
			M.query:set("")
			M.view_mode:set("everything")
		end),
	}
end

-- "Load more" (render_load_more): how many remain, at most a page; while
-- it reads, "Loading more…"; failed, "Try again".
local function footer(): Node
	return ui.row {
		w_full = true,
		pt = "$zeron.space.16",
		justify = "center",
		ui.button {
			id = "prs_load_more",
			label = function()
				return if more:get() == "loading" then "Loading more…" else "Load more pull requests"
			end,
			h = 32,
			px = "$zeron.space.14",
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.8",
			variants = kit.recipes.wash { rest = "ink2", hover = "ink3" },
			focus = { border = 0 },
			cursor = "pointer",
			opacity = function()
				return if more:get() == "loading" then 0.7 else 1
			end,
			on_click = load_more,
			ui.presence(function()
				return if more:get() == "loading" then true else nil
			end, function(): Node
				return kit.loaders.ring { size = 12 }
			end),
			kit.text.text {
				function()
					local m = more:get()
					if m == "loading" then
						return "Loading more…"
					elseif m == "failed" then
						return "Try again"
					end
					local left = total:get() - #items:get()
					return if left > 0 then `Load {math.min(left, 50)} more` else "Load more"
				end,
				id = "prs_load_more_label",
				size = "sm",
				weight = "medium",
				line = false,
			},
		},
	}
end

-- ---- the board ---------------------------------------------------------------

function M.view(props: Props): Node
	-- The list's width: under 640 of content (beside a pull request), rows
	-- put their counts and date under their identity.
	local host = ui.ref()
	local narrow = ui.computed(function(): boolean
		return math.min(host.width or 1000, 760) - 80 < 640
	end)
	local rows = ui.computed(function(): { BoardRow }
		local list = shown(props.stars)
		local shut = collapsed:get()
		local out: { BoardRow } = {}
		for _, g in GROUPS do
			local members: { string } = {}
			for _, id in list do
				if M.group_of(id) == g.id then
					table.insert(members, id)
				end
			end
			if #members > 0 then
				local closed = shut[g.id] == true
				table.insert(out, {
					key = `g:{g.id}:{#members}:{closed}:{#out == 0}`,
					kind = "group",
					group = g.id,
					label = g.label,
					count = #members,
					closed = closed,
					first = #out == 0,
				})
				if not closed then
					for i, id in members do
						table.insert(out, {
							key = `i:{id}:{i == 1}:{i == #members}`,
							kind = "item",
							id = id,
							first = i == 1,
							last = i == #members,
						})
					end
				end
			end
		end
		if next_page:get() ~= nil and #out > 0 then
			table.insert(out, { key = "footer", kind = "footer" })
		end
		return out
	end)
	local function count(): string?
		local p = phase:get()
		if p == "ready" or #items:get() > 0 then
			return tostring(math.max(total:get(), #items:get()))
		end
		return nil
	end
	local function build(r: BoardRow): Node
		if r.kind == "footer" then
			return footer()
		elseif r.kind == "group" then
			local g = r.group :: Group
			return ui.row {
				w_full = true,
				pt = if r.first then nil else "$zeron.space.32",
				pb = "$zeron.space.8",
				ui.button {
					id = `prs_group_{g}`,
					label = `{r.label}, {r.count} pull requests`,
					expanded = not r.closed,
					min_h = 24,
					px = "$zeron.space.8",
					gap = "$zeron.space.8",
					items = "center",
					rounded = "$zeron.radius.6",
					variants = kit.recipes.wash { hover = "ink1" },
					focus = { border = 0 },
					cursor = "pointer",
					on_click = function()
						collapsed:set_key(g, if collapsed:peek()[g] then nil else true)
					end,
					kit.disclosure.chevron {
						open = function()
							return not r.closed
						end,
						size = 14,
					},
					kit.text.text { r.label :: string, size = "md", color = T.secondary, line = false },
					kit.text.text { tostring(r.count), size = "xs", color = T.secondary, line = false },
				},
			}
		end
		local id = r.id :: string
		local row = row_of(id) :: pr.Row
		local opened = string.match(M.sort:peek(), "^opened") ~= nil
		local radius = T.radius_card
		return ui.column {
			w_full = true,
			bg = T.card,
			overflow = "hidden",
			rounded_tl = if r.first then radius else 0,
			rounded_tr = if r.first then radius else 0,
			rounded_bl = if r.last then radius else 0,
			rounded_br = if r.last then radius else 0,
			pr.row {
				id = `pr_{id}`,
				row = row,
				first = r.first,
				group = "zprs_rows",
				date = if opened and row.opened
					then `Opened {M.ago(row.opened)}`
					elseif row.updated then M.ago(row.updated)
					else nil,
				selected = function()
					return state.pr:get() == id and state.prs.open.right:get()
				end,
				starred = function()
					return props.stars:get()[id] == true
				end,
				on_star = function()
					props.stars:set_key(id, if props.stars:peek()[id] then nil else true)
				end,
				on_click = function()
					props.open(id)
				end,
				narrow = narrow,
			},
		}
	end
	local body = ui.presence(function(): string
		local p = phase:get()
		if p == "idle" or (p == "loading" and #items:get() == 0) then
			return "loading"
		elseif #items:get() == 0 then
			return "empty"
		end
		-- The sort reads into the rows' dates: they are built again for it.
		return if #rows:get() == 0 then "none" else `list:{string.match(M.sort:get(), "^%a+")}`
	end, function(what: string): Node
		local function page(child: Node): Node
			return kit.scroll {
				grow = 1,
				w_full = true,
				fade = 24,
				ui.column {
					w_full = true,
					max_w = 760,
					self = "center",
					px = "$zeron.space.40",
					pt = "$zeron.space.8",
					pb = "$zeron.space.32",
					child,
				},
			}
		end
		if what == "loading" then
			return page(pr.skeleton { id = "prs_skeleton", narrow = narrow })
		elseif what == "empty" then
			return page(empty_or_error())
		elseif what == "none" then
			return page(no_results())
		end
		local function at(key: string): BoardRow?
			for _, r in rows:peek() do
				if r.key == key then
					return r
				end
			end
			return nil
		end
		return kit.wash.list {
			group = "zprs_rows",
			color = T.glass_hover,
			grow = 1,
			w_full = true,
			ui.list {
				id = "prs_list",
				label = "Pull requests",
				w_full = true,
				grow = 1,
				measured = true,
				height = 64,
				count = function()
					return #rows:get()
				end,
				key = function(i: number): string
					return rows:get()[i].key
				end,
				row = function(key: string): Node
					local r = at(key)
					if not r then
						return ui.div {}
					end
					return ui.row {
						w_full = true,
						justify = "center",
						ui.column {
							w_full = true,
							max_w = 760,
							px = "$zeron.space.40",
							pt = if r.first and r.kind == "group" then "$zeron.space.8" else nil,
							pb = if r.kind == "footer" or (r.last and r.key == rows:peek()[#rows:peek()].key)
								then "$zeron.space.32"
								else nil,
							build(r),
						},
					}
				end,
			},
		}
	end, { grow = 1, w_full = true, min_h = 0 })
	return ui.column {
		id = "prs_board",
		ref = host,
		w_full = true,
		h_full = true,
		pt = chrome.top,
		on_mount = function()
			if phase:peek() == "idle" then
				load(false)
			end
		end,
		ui.column {
			w_full = true,
			pt = "$zeron.space.16",
			shrink = 0,
			header(function()
				return rows:get()
			end, count),
		},
		body,
	}
end

return M
