-- The pull requests route (PR #866, #914): the board is its content
-- column and pull requests open beside it in the route's own right pane,
-- as tabs, under the same panel policy as the chat's (equal split, held
-- divider, expand over the board), the pane covering the board where the
-- window cannot keep 360 of it beside the pane. From a chat, a pull request
-- opens as a tab in the session's right pane (chat_pull_requests.rs).
--
-- The pull request (pull_request_detail.rs): its bar (the title, refresh,
-- copy the link, the browser), then Summary, Code and Activity under the
-- floating section navigation. Summary: the header, the overview, the
-- assessment, the checks, the handoff and the description with its media;
-- Code: the changed files and the review stream (kit/pr_code); Activity:
-- the conversation and the inline review comments, the comment composer
-- docked under it. What GitHub would send is sample data (zeron/pr_data),
-- read with a little latency so each loads as Zeron's does: the board, the
-- detail and the diff stand in skeletons until they arrive.
local T = require("../theme")
local kit = require("@kit")
local pr = require("@kit/pr")
local pr_code = require("@kit/pr_code")
local markdown = require("@kit/markdown")
local completion = require("@kit/completion")
local lightbox = require("@kit/lightbox")
local syntax = require("@lib/syntax")
local data = require("./data")
local pr_data = require("./pr_data")
local handoff = require("./pr_handoff")
local board = require("./pr_board")
local state = require("./state")

local M = {}

-- How long GitHub takes to answer, through `gh` on the device.
M.LOAD = 450
M.DIFF_LOAD = 400
M.POST = 700
M.IMAGE = 300

-- ---- what has loaded ------------------------------------------------------

-- The pull requests read (when, `ui.now()`), the one being read, and the
-- patches read.
local loaded = ui.state("pr_loaded", {} :: { [string]: number })
local loading = ui.state("pr_loading", "")
local diffs = ui.state("pr_diffs", {} :: { [string]: boolean })
local diff_loading = ui.state("pr_diff_loading", "")
-- Why a pull request, or its patch, could not be read.
local read_errors = ui.state("pr_read_errors", {} :: { [string]: string })
local diff_errors = ui.state("pr_diff_errors", {} :: { [string]: string })
-- A pull request whose first read or first patch fails (`read_fails`,
-- `diff_fails`) fails once.
local failed_once: { [string]: boolean } = {}
local read_failed: { [string]: boolean } = {}
-- Stars are the user's (local preferences).
local stars = ui.state(
	"pr_stars",
	(function()
			local out: { [string]: boolean } = {}
			for _, r in data.PRS do
				if r.starred then
					out[r.id] = true
				end
			end
			return out
		end)() :: { [string]: boolean }
)

-- Pull requests the board does not list (a session's, a reply's link),
-- read as the board's are: by number, under `n<number>`.
local others: { [string]: { row: pr.Row, detail: pr_data.Detail } } = {}

local function listed(id: string): pr.Row?
	for _, list in { data.PRS, data.MORE_PRS } do
		for _, r in list do
			if r.id == id then
				return r
			end
		end
	end
	return nil
end
local function row_of(id: string): pr.Row
	local other = others[id]
	return listed(id) or (if other then other.row else data.PRS[1])
end
local function detail_of(id: string): pr_data.Detail
	local other = others[id]
	return pr_data.DETAILS[id] or (if other then other.detail else pr_data.DETAILS.p1)
end

-- The pull request numbered `number` in `repository` ("zeron/comet" unless
-- given): the board's, or one read on its own, titled `title`: what GitHub
-- says of it alone (its branch, no checks, nothing said yet), not the
-- board's.
function M.by_number(number: number, repository: string?, title: string?, status: pr.Status?, branch: string?): string
	for _, list in { data.PRS, data.MORE_PRS } do
		for _, r in list do
			if r.number == number then
				return r.id
			end
		end
	end
	local id = `n{number}`
	if not others[id] then
		local repo = repository or "zeron/comet"
		local draft = status == "draft"
		local row: pr.Row = {
			id = id,
			title = title or `Pull request #{number}`,
			number = number,
			author = pr_data.VIEWER,
			status = status or "open",
			date = "just now",
			added = 0,
			removed = 0,
		}
		local detail: pr_data.Detail = {
			repository = repo,
			url = `https://github.com/{repo}/pull/{number}`,
			head = branch or `pr-{number}`,
			base = "main",
			oid = "",
			state = if status == "merged" then "MERGED" else "OPEN",
			draft = draft,
			review = "",
			mergeable = "UNKNOWN",
			authored = true,
			requested = false,
			ci = "none",
			ci_total = 0,
			checks = {},
			body = "",
			patch = "",
			activity = {},
			threads = true,
			checkout = true,
		}
		others[id] = { row = row, detail = detail }
	end
	return id
end

-- The pull request a GitHub link names (pull_request_detail.rs
-- pull_request_link: https, github.com, `owner/repo/pull/N`, whatever
-- follows), or nil.
function M.link(url: string): string?
	local owner, repo, number, rest = string.match(url, "^https://github%.com/([^/?#]+)/([^/?#]+)/pull/(%d+)(.*)$")
	if not owner or not number or (rest ~= "" and not string.find(rest or "", "^[/?#]")) then
		return nil
	end
	local n = tonumber(number) :: number
	if n < 1 then
		return nil
	end
	return M.by_number(n, `{owner}/{repo}`)
end

-- Its address on GitHub, and its title (a tab's).
function M.url(id: string): string
	return detail_of(id).url
end
function M.title(id: string): string
	return row_of(id).title
end

local function load_diff(id: string)
	if diff_loading:peek() == id or diffs:peek()[id] then
		return
	end
	diff_loading:set(id)
	diff_errors:set_key(id, nil)
	ui.after(M.DIFF_LOAD, function()
		if diff_loading:peek() == id then
			diff_loading:set("")
		end
		if detail_of(id).diff_fails and not failed_once[id] then
			failed_once[id] = true
			diff_errors:set_key(id, "Couldn’t load the diff. GitHub didn’t respond in time. Try again.")
			return
		end
		diffs:set_key(id, true)
	end)
end

-- What each pull request's page keeps of its own (pull_request_detail.rs:
-- a page per tab), as tabs change and it is opened again: its section
-- (Summary, Code or Activity), where each scrolled, the checks folded
-- open, the changed files' search and picker.
type Page = {
	tab: State<string>,
	checks: State<boolean>,
	query: State<string>,
	picker: State<boolean>,
	summary: State<number>,
	activity: State<number>,
	code: State<number>,
}
local function page_of(id: string): Page
	return {
		tab = ui.state(`pr:{id}:tab`, "summary"),
		checks = ui.state(`pr:{id}:checks`, false),
		query = ui.state(`pr:{id}:file_query`, ""),
		picker = ui.state(`pr:{id}:file_picker`, false),
		summary = ui.state(`pr:{id}:summary_offset`, 0),
		activity = ui.state(`pr:{id}:activity_offset`, 0),
		code = ui.state(`pr:{id}:code_offset`, 0),
	}
end
-- The pull request a page shows now (beside the board, in a chat's pane,
-- or a pane's).
local showing = ui.state("pr_showing", "")

-- Reads pull request `id` (again, refreshing: its patch with it).
local function load(id: string)
	if loading:peek() == id then
		return
	end
	loading:set(id)
	read_errors:set_key(id, nil)
	ui.after(M.LOAD, function()
		if loading:peek() == id then
			loading:set("")
		end
		if detail_of(id).read_fails and not read_failed[id] then
			read_failed[id] = true
			read_errors:set_key(id, "Couldn’t load this pull request. GitHub didn’t respond in time. Try again.")
			return
		end
		loaded:set_key(id, ui.now())
		if page_of(id).tab:peek() == "code" and showing:peek() == id then
			load_diff(id)
		end
	end)
end
local function refresh(id: string)
	if loading:peek() == id then
		return
	end
	diffs:set_key(id, nil)
	diff_errors:set_key(id, nil)
	load(id)
end

-- The link was copied: its button says so for two seconds.
local copied = ui.state("pr_link_copied", false)
local function copy(text: string)
	ui.clipboard.write(text)
end

-- ---- the board ------------------------------------------------------------

-- The board (zeron/pr_board): a row opens its pull request where General
-- says (beside the board, or the browser); stars are the Summary's too.
function M.board(): Node
	return board.view { stars = stars, open = M.open }
end

-- ---- the bar ----------------------------------------------------------------

-- The pull request's actions: refresh (dim while it reads), copy the link
-- ("Link copied" for two seconds), open it in the browser: pull request
-- `which`, or the board's pane's.
function M.actions(prefix: string, which: string?): { Node }
	local function current(read: boolean): string
		return which or (if read then state.pr:get() else state.pr:peek())
	end
	return {
		pr.action {
			id = `{prefix}_refresh`,
			label = "Refresh pull request",
			icon = "refresh",
			dim = function()
				return loading:get() == current(true)
			end,
			on_click = function()
				refresh(current(false))
			end,
		},
		pr.action {
			id = `{prefix}_copy_link`,
			label = function()
				return if copied:get() then "Link copied" else "Copy link"
			end,
			icon = function()
				return if copied:get() then "check" else "copy"
			end,
			on_click = function()
				copy(detail_of(current(false)).url)
				copied:set(true)
				ui.after(2000, function()
					copied:set(false)
				end)
			end,
		},
		pr.action {
			id = `{prefix}_external`,
			label = "Open in default browser",
			icon = "arrow-up-right",
			on_click = function()
				ui.open_url(detail_of(current(false)).url)
			end,
		},
	}
end

-- The pull request's toolbar over its page (the pane's own row, under the
-- titlebar that holds its tabs): the glyph and the title, then the actions.
local function toolbar(id: string): Node
	local r = row_of(id)
	return ui.row {
		id = "zprs_bar",
		w_full = true,
		h = 38,
		pl = "$zeron.space.8",
		pr = "$zeron.space.4",
		gap = "$zeron.space.4",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		ui.row {
			id = "zprs_title",
			grow = 1,
			shrink = 1,
			min_w = 0,
			px = "$zeron.space.4",
			gap = "$zeron.space.6",
			items = "center",
			role = "heading",
			label = `Pull request {r.number}: {r.title}`,
			kit.icon { name = "pull-request", size = 14, color = T.secondary, shrink = 0 },
			kit.text.text {
				r.title,
				literal = true,
				size = "sm",
				weight = "medium",
				opacity = 0.85,
				truncate = true,
				shrink = 1,
				min_w = 0,
				line = false,
			},
		},
		M.actions("pr", id),
	}
end

-- ---- the detail ---------------------------------------------------------------

-- Split or unified: the reader's, for every pull request.
local split = ui.state("pr_split", false)
-- A handoff under way is the page it started on's: another pull request
-- starts afresh.
local shown_id = ""
local function arrive(id: string)
	showing:set(id)
	if shown_id == id then
		return
	end
	shown_id = id
	handoff.platform:set("relevant")
	handoff.finding:set(false)
	handoff.error:set(nil)
end

-- The Summary's cards stand 12 apart; the header 24 above the first.
local CARD_GAP = 12
-- The page column (page_column): 760 at most, 40 in at its sides.
local PAGE = 760

-- Description HTML as markdown (description_markdown): an <img> as an
-- image, a <details>, <summary>, <p>, <div> or <br> as a paragraph's
-- break; a script, a style or an iframe dropped whole. Code stays as it is.
function M.description(source: string): string
	local out: { string } = {}
	local fence = false
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		if string.match(line, "^%s*```") then
			fence = not fence
		elseif not fence then
			line = string.gsub(line, "<img%s[^>]*>", function(tag: string): string
				local src = string.match(tag, 'src="([^"]*)"') or ""
				local alt = string.match(tag, 'alt="([^"]*)"') or ""
				if src == "" then
					return ""
				end
				alt = string.gsub(alt, "[%[%]\\]", "\\%0")
				return `![{alt}](<{src}>)`
			end)
			for _, tag in { "script", "style", "iframe" } do
				line = string.gsub(line, `<{tag}[^>]*>.-</{tag}>`, "")
			end
			for _, tag in { "details", "summary", "p", "div", "br" } do
				line = string.gsub(line, `</?{tag}[^>]*>`, "\n\n")
			end
		end
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

-- ---- media ----------------------------------------------------------------------

-- An image's load (by address): the file it decoded to, or that it failed;
-- one hosted elsewhere waits for a click ("asked").
local media = ui.state("pr_media", {} :: { [string]: string })

local function placeholder(label: string, id: string?): Node
	return ui.row {
		id = id,
		w_full = true,
		min_h = 80,
		p = "$zeron.space.16",
		rounded = "$zeron.radius.8",
		bg = T.glass_hover,
		kit.text.text { label, literal = true, size = "sm", color = T.secondary, wrap = true },
	}
end

-- GitHub serves its own images; anything else is another party's server,
-- which would learn who opened the pull request and when.
local function github_hosted(host: string): boolean
	return host == "github.com"
		or string.sub(host, -#".githubusercontent.com") == ".githubusercontent.com"
		or string.sub(host, -#".githubassets.com") == ".githubassets.com"
end

local function fetch(src: string)
	media:set_key(src, "loading")
	ui.after(M.IMAGE, function()
		local m = pr_data.MEDIA[src]
		media:set_key(src, if m and not m.fails then "ready" else "failed")
	end)
end

-- An image enlarging: its full size loading (or failed) over the page,
-- then the viewer.
export type Full = { src: string, name: string, failed: boolean }
local full = ui.state("pr_full_image", nil :: Full?)
local function enlarge(src: string, name: string)
	full:set { src = src, name = name, failed = false }
	ui.after(M.IMAGE, function()
		local now = full:peek()
		if not now or now.src ~= src or now.failed then
			return
		end
		local m = pr_data.MEDIA[src]
		if m.full_fails then
			full:set { src = src, name = name, failed = true }
			return
		end
		full:set(nil)
		lightbox.open { src = m.src, name = name, w = m.w, h = m.h }
	end)
end
-- Over the page while it loads (pull_request_detail.rs pr-image-loading):
-- the scrim at 70% and what it is doing; a press or Escape cancels, and a
-- failed one's press opens it in the browser.
local function loading_image(): Node
	return ui.presence(full, function(f: Full): Node
		local function close()
			if f.failed then
				ui.open_url(f.src)
			end
			full:set(nil)
		end
		return ui.row {
			id = "pr_image_loading",
			absolute = true,
			left = 0,
			top = 0,
			right = 0,
			bottom = 0,
			p = "$zeron.space.24",
			items = "center",
			justify = "center",
			bg = T.image_scrim,
			focusable = true,
			label = f.name,
			on_mount = function(el: Element)
				el:focus()
			end,
			on_key = function(e: KeyEvent): boolean
				if e.key == "Escape" then
					full:set(nil)
					return true
				end
				return false
			end,
			on_click = close,
			kit.text.text {
				if f.failed
					then "Couldn’t load image. Click to open it in your browser · Escape to close"
					else "Loading image… · Escape to cancel",
				id = "pr_image_loading_label",
				size = "md",
				color = T.on_scrim,
				align = "center",
				wrap = true,
			},
		}
	end, { absolute = true, left = 0, top = 0, right = 0, bottom = 0, pointer_events = "none" })
end

-- An image of a description (pull_request_media.rs media): a GitHub one
-- loads where it is, at most as wide as the column and 420 high, never past
-- its size, a hairline round it; another host's loads only when asked. A
-- click enlarges it in the viewer, or opens a failed one in the browser.
local function image(src: string, alt: string, key: string): Node
	local host = string.match(src, "^https://([^/:]+)")
	if not host then
		return placeholder("Image unavailable here. Open the pull request in your browser to see it.")
	end
	local name = if alt ~= "" then alt else "Image"
	local inline = github_hosted(host)
	-- The room it has: the image is as wide as that, its height or 420,
	-- whichever is least, at its own aspect.
	local room = ui.ref()
	local function phase(): string
		return media:get()[src] or (if inline then "loading" else "asked")
	end
	return ui.button {
		id = `pr_image_{key}`,
		ref = room,
		label = function()
			return if phase() == "asked" then `Load image from {host}: {name}` else `Open image: {name}`
		end,
		w_full = true,
		min_w = 0,
		my = "$zeron.space.8",
		p = 0,
		rounded = "$zeron.radius.8",
		bg = T.clear,
		border = 0,
		focus = { border = 0 },
		justify = "center",
		overflow = "hidden",
		cursor = "pointer",
		on_mount = function()
			if inline and media:peek()[src] == nil then
				fetch(src)
			end
		end,
		on_click = function()
			local p = phase()
			if p == "asked" then
				fetch(src)
			elseif p == "failed" then
				ui.open_url(src)
			elseif p == "ready" then
				enlarge(src, name)
			end
		end,
		ui.presence(phase, function(p: string): Node
			if p == "asked" then
				return placeholder(`{name} · hosted on {host} · Click to load`)
			elseif p == "loading" then
				return placeholder("Loading image…")
			elseif p == "failed" then
				return placeholder(`{name} · Couldn’t load image. Open in browser ↗`, `pr_image_{key}_error`)
			end
			local m = pr_data.MEDIA[src]
			local function scale(): number
				return math.min((room.width or 0) / m.w, 420 / m.h, 1)
			end
			return ui.image {
				id = `pr_image_{key}_shown`,
				src = m.src,
				label = name,
				w = function()
					return m.w * scale()
				end,
				h = function()
					return m.h * scale()
				end,
				fit = "contain",
				rounded = "$zeron.radius.8",
				border = 1,
				border_color = T.hairline,
			}
		end, { w_full = true, items = "center" }),
	}
end

-- A description or a comment: markdown at 13, its images as above.
local function rich(id: string, text: string): Node
	return markdown.view { id = id, text = M.description(text), media = image, size = "md" }
end

-- ---- the header -------------------------------------------------------------

local function meta(glyph: string, text: string): Node
	return ui.row {
		gap = "$zeron.space.4",
		items = "center",
		kit.icon { name = glyph :: any, size = 13, color = T.secondary, shrink = 0 },
		kit.text.text { text, literal = true, size = "sm", color = T.secondary, line = false },
	}
end

-- The title (20 on 26, wrapping) and the meta line: the author, the
-- repository, the number, and when it was read.
local function header(r: pr.Row, d: pr_data.Detail, at: number?): Node
	local age: string? = nil
	if at then
		local minutes = math.floor((ui.now() - at) / 60000)
		age = if minutes < 1 then "Loaded just now" else `Loaded {minutes}m ago`
	end
	return ui.column {
		w_full = true,
		min_w = 0,
		kit.text.text {
			r.title,
			id = "pr_detail_title",
			literal = true,
			size = "xxl",
			weight = "medium",
			wrap = true,
			px = "$zeron.space.8",
		},
		ui.row {
			id = "pr_detail_meta",
			mt = "$zeron.space.12",
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			flex_wrap = true,
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				min_w = 0,
				kit.avatar { name = r.author, size = 20 },
				kit.text.text {
					if r.author == "" then "Deleted account" else r.author,
					literal = true,
					size = "sm",
					color = T.secondary,
					line = false,
				},
			},
			meta("folder-with-files", d.repository),
			meta("pull-request", tostring(r.number)),
			age and meta("clock-circle", age) or nil,
		},
	}
end

-- ---- Summary --------------------------------------------------------------

-- "3 files · +12 −4", the counts in their colours.
local function changes(files: number, added: number, removed: number): Node
	return ui.row {
		gap = "$zeron.space.6",
		flex_wrap = true,
		kit.text.text {
			`{files} {if files == 1 then "file" else "files"} ·`,
			size = "md",
			color = T.secondary,
			line = false,
		},
		kit.text.text { `+{added}`, size = "md", color = T.success_muted, line = false },
		kit.text.text { `−{removed}`, size = "md", color = T.danger_muted, line = false },
	}
end

local function checks_card(id: string, d: pr_data.Detail): Node
	local checks_open = page_of(id).checks
	local total = math.max(d.ci_total, #d.checks)
	local status = handoff.ci_status(d)
	local _, words = pr.status(status)
	local rows: { Node } = {}
	for i, c in d.checks do
		-- Status integrations set these links: only web pages open.
		local link = if c.link and string.match(c.link, "^https://") then c.link else nil
		table.insert(
			rows,
			ui.button {
				id = `pr_check_{i}`,
				role = if link then "link" else "row",
				label = if link then `Open {c.name}` else c.name,
				w_full = true,
				min_h = 36,
				px = "$zeron.space.16",
				py = "$zeron.space.4",
				gap = "$zeron.space.16",
				items = "center",
				bg = T.clear,
				border = 0,
				rounded = 0,
				focus = { border = 0 },
				border_sides = { 1, 0, 0, 0 },
				border_color = T.hairline,
				focusable = link ~= nil,
				cursor = if link then "pointer" else "default",
				variants = if link then kit.recipes.wash { hover = "glass" } else nil,
				on_click = if link
					then function()
						ui.open_url(link :: string)
					end
					else nil,
				kit.text.text {
					c.name,
					id = `pr_check_name_{i}`,
					literal = true,
					size = "md",
					grow = 1,
					shrink = 1,
					min_w = 0,
					wrap = true,
				},
				pr.status_chip { raw = c.status },
			}
		)
	end
	return pr.card {
		id = "pr_checks_card",
		mt = T.space(CARD_GAP),
		ui.button {
			id = "pr_checks_toggle",
			label = `Checks, {total}, {words}`,
			w_full = true,
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			gap = "$zeron.space.8",
			items = "center",
			flex_wrap = true,
			bg = T.clear,
			border = 0,
			rounded = 0,
			focus = { border = 0 },
			cursor = "pointer",
			variants = kit.recipes.wash { hover = "glass" },
			on_click = ui.toggle(checks_open),
			ui.presence(checks_open, function(open: boolean): Node
				return kit.icon {
					name = if open then "alt-arrow-down" else "alt-arrow-right",
					size = 14,
					color = T.secondary,
				}
			end),
			kit.text.text { `Checks · {total}`, size = "md", grow = 1, line = false },
			pr.status_chip { raw = status },
		},
		ui.presence(function()
			return if checks_open:get() then "open" else nil
		end, function(): Node
			if #d.checks == 0 then
				return ui.row {
					id = "pr_checks_empty",
					w_full = true,
					p = "$zeron.space.16",
					kit.text.text { handoff.ci_empty(d), size = "md", color = T.secondary, wrap = true },
				}
			end
			return ui.column { w_full = true, rows }
		end, { w_full = true }),
	}
end

local function summary(id: string, r: pr.Row, d: pr_data.Detail): Node
	local a = handoff.assess(d)
	local blockers = if #a.blockers > 0
		then table.concat(a.blockers, " · ")
		elseif #a.missing > 0 then "Assessment incomplete"
		else "No blockers reported"
	local missing: { Node } = {}
	for _, m in a.missing do
		table.insert(missing, kit.text.text { m, size = "xs", color = T.secondary, wrap = true })
	end
	local next_action = a.actions[1]
	local files = #pr_code.files(d.patch)
	return ui.column {
		w_full = true,
		pr.card {
			id = "pr_overview",
			mt = "$zeron.space.24",
			pr.field {
				id = "pr_field_status",
				label = "Status",
				first = true,
				pr.status_chip { raw = if d.draft then "DRAFT" else d.state },
			},
			pr.field {
				id = "pr_field_review",
				label = "Review",
				pr.status_chip { raw = if d.review == "" then "No review decision" else d.review },
			},
			pr.field {
				id = "pr_field_branch",
				label = "Branch",
				kit.text.text { `{d.head} → {d.base}`, literal = true, size = "sm", mono = true, wrap = true },
			},
			pr.field {
				id = "pr_field_changes",
				label = "Changes",
				changes(files, r.added, r.removed),
			},
		},
		pr.card {
			id = "pr_assessment",
			mt = T.space(CARD_GAP),
			pr.card_row {
				first = true,
				ui.column {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.6",
					pr.row_title("Current assessment"),
					kit.text.text { blockers, id = "pr_blockers", size = "sm", color = T.secondary, wrap = true },
					next_action and kit.text.text {
						`Next: {handoff.ACTION_LABEL[next_action]}`,
						id = "pr_next_action",
						size = "sm",
						wrap = true,
					} or nil,
					missing,
					ui.row {
						id = "pr_head_commit",
						min_w = 0,
						tooltip = pr.tip(if d.oid == "" then "Current commit unavailable" else d.oid),
						kit.text.text {
							if d.oid == "" then "Commit unavailable" else `Commit {string.sub(d.oid, 1, 7)}`,
							size = "xs",
							mono = true,
							color = T.secondary,
							truncate = true,
							line = false,
						},
					},
				},
				pr.star {
					id = "pr_star",
					starred = function()
						return stars:get()[id] == true
					end,
					on_click = function()
						stars:set_key(id, if stars:peek()[id] then nil else true)
					end,
				},
			},
		},
		checks_card(id, d),
		handoff.card(r.number, r.title, d, copy),
		pr.card {
			id = "pr_description",
			mt = T.space(CARD_GAP),
			ui.column {
				w_full = true,
				min_h = 60,
				p = "$zeron.space.16",
				if d.body == ""
					then kit.text.text { "No description provided.", size = "md", color = T.secondary }
					else rich("pr_body", d.body),
			},
		},
	}
end

-- ---- Activity --------------------------------------------------------------------

-- Comments posted from here, by pull request, after what GitHub sent.
local posted = ui.state("pr_posted", {} :: { [string]: { pr_data.Message } })
-- The comment on its way (the body sent), and why the last one failed.
local posting = ui.state("pr_posting", nil :: { id: string, body: string }?)
local comment_errors = ui.state("pr_comment_errors", {} :: { [string]: string })
-- A pull request whose first post fails (`diff_fails` stands for a flaky
-- device: its first post times out too).
local post_failed: { [string]: boolean } = {}

local function messages(id: string): { pr_data.Message }
	local out = table.clone(detail_of(id).activity)
	ui.sort(out, function(m: pr_data.Message): number
		return m.order
	end)
	for _, m in posted:get()[id] or {} do
		table.insert(out, m)
	end
	return out
end

local function draft_of(id: string): State<string>
	return ui.state(`pr:{id}:draft`, "")
end

local function location(i: number, m: pr_data.Message): Node?
	local t = m.thread
	if not t then
		return nil
	end
	local where = if t.line then `{t.path}:{t.line}` else t.path
	local details = { if t.resolved then "Resolved" else "Unresolved" }
	if t.outdated then
		table.insert(details, "Outdated")
	end
	if t.reply then
		table.insert(details, "Reply")
	end
	local link = if t.url and string.match(t.url, "^https://github%.com/") then t.url else nil
	-- One quiet line: where the comment sits (a link to it on GitHub), then
	-- its state.
	return ui.row {
		id = `pr_inline_thread_{i}`,
		min_w = 0,
		gap = "$zeron.space.8",
		items = "center",
		ui.button {
			id = `pr_inline_location_{i}`,
			role = if link then "link" else "group",
			label = if link then "Open review comment on GitHub" else where,
			min_w = 0,
			shrink = 1,
			h = 22,
			px = "$zeron.space.6",
			gap = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.6",
			border = 0,
			focus = { border = 0 },
			focusable = link ~= nil,
			cursor = if link then "pointer" else "default",
			variants = kit.recipes.pr_location { link = link ~= nil },
			tooltip = pr.tip(where),
			on_click = if link
				then function()
					ui.open_url(link :: string)
				end
				else nil,
			kit.text.text {
				where,
				literal = true,
				size = "xs",
				mono = true,
				color = "inherit",
				truncate = true,
				shrink = 1,
				min_w = 0,
				line = false,
			},
			link and kit.icon { name = "arrow-up-right", size = 11, color = T.secondary, shrink = 0 } or nil,
		},
		kit.text.text { table.concat(details, " · "), size = "sm", color = T.secondary, shrink = 0, line = false },
	}
end

local function message(i: number, m: pr_data.Message): Node
	local own = string.lower(m.author) == string.lower(pr_data.VIEWER)
	return ui.row {
		w_full = true,
		mb = "$zeron.space.24",
		justify = if own then "end" else "start",
		ui.column {
			id = `pr_message_{i}`,
			role = "article",
			w = "90%",
			max_w = if own then "80%" else nil,
			min_w = 0,
			px = if own then "$zeron.space.16" else nil,
			py = if own then "$zeron.space.10" else nil,
			rounded = if own then T.radius_xl else nil,
			bg = if own then T.ink3 else nil,
			gap = "$zeron.space.8",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				flex_wrap = true,
				kit.avatar { name = m.author, size = 24 },
				kit.text.text {
					if m.author == "" then "Deleted account" else m.author,
					literal = true,
					size = "md",
					weight = "medium",
					line = false,
				},
				m.state and pr.status_chip { raw = m.state } or nil,
				kit.text.text { m.at, size = "xs", color = T.secondary, line = false },
			},
			location(i, m),
			rich(`pr_message_{i}_body`, m.body),
		},
	}
end

local function activity(id: string, d: pr_data.Detail): Node
	return ui.presence(function()
		return #messages(id)
	end, function(): Node
		local list = messages(id)
		if #list == 0 then
			return ui.column {
				id = "pr_activity_thread",
				w_full = true,
				grow = 1,
				min_h = 160,
				mt = "$zeron.space.24",
				items = "center",
				justify = "center",
				ui.column {
					id = "pr_activity_empty",
					w_full = true,
					max_w = 320,
					items = "center",
					kit.icon { name = "chat-round-line", size = 24, color = T.secondary, mb = "$zeron.space.16" },
					kit.text.text {
						if d.threads then "No activity yet" else "No conversation yet",
						size = "xl",
						weight = "semibold",
						align = "center",
					},
					kit.text.text {
						if d.threads
							then "Comments and reviews will appear here. Start the conversation below."
							else "Inline review threads are unavailable. Refresh or open this pull request on GitHub to read them.",
						size = "md",
						color = T.secondary,
						align = "center",
						wrap = true,
						mt = "$zeron.space.6",
					},
				},
			}
		end
		local nodes: { Node } = {}
		for i, m in list do
			table.insert(nodes, message(i, m))
		end
		return ui.column {
			id = "pr_activity_thread",
			w_full = true,
			mt = "$zeron.space.24",
			pl = "$zeron.space.8",
			if d.threads
				then nil
				else kit.text.text {
					"Inline review threads are unavailable. Refresh or open this pull request on GitHub to read them.",
					id = "pr_threads_unavailable",
					size = "md",
					color = T.secondary,
					wrap = true,
					mb = "$zeron.space.16",
				},
			nodes,
		}
	end, { w_full = true, grow = 1 })
end

-- The people to mention: the author, then everyone in the activity, at
-- most eight, by name.
local function participants(id: string, query: string): { completion.Item }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	local function add(login: string)
		if login ~= "" and not seen[login] and string.find(string.lower(login), string.lower(query), 1, true) then
			seen[login] = true
			table.insert(names, login)
		end
	end
	add(row_of(id).author)
	for _, m in messages(id) do
		add(m.author)
	end
	table.sort(names)
	local out: { completion.Item } = {}
	for i, login in names do
		if i > 8 then
			break
		end
		local item: completion.Item =
			{ id = login, label = `@{login}`, icon = "chat-round-line", avatar = login, insert = `@{login}` }
		table.insert(out, item)
	end
	return out
end

local function send(id: string)
	local draft = draft_of(id)
	local body = draft:peek()
	if posting:peek() or not string.match(body, "%S") then
		return
	end
	if #body > 60000 then
		comment_errors:set_key(id, "Comment is too long (maximum 60,000 bytes).")
		return
	end
	comment_errors:set_key(id, nil)
	posting:set { id = id, body = body }
	ui.after(M.POST, function()
		posting:set(nil)
		if detail_of(id).diff_fails and not post_failed[id] then
			post_failed[id] = true
			comment_errors:set_key(
				id,
				"Couldn’t confirm your comment was posted. GitHub didn’t respond in time. Try again. Your draft is kept; check GitHub before sending again."
			)
			return
		end
		local list = table.clone(posted:peek()[id] or {})
		table.insert(list, {
			id = `posted_{#list + 1}`,
			author = pr_data.VIEWER,
			at = "just now",
			order = 1000 + #list,
			body = body,
		})
		posted:set_key(id, list)
		-- Only the text that was sent leaves the draft.
		if draft:peek() == body then
			draft:set("")
		end
	end)
end

-- The comment composer (comment_composer): docked in the flow under the
-- thread, the chat composer's compact pill (49 high, radius 26, the
-- composer's material), the send circle on its last line; @ mentions the
-- people here. Posting, a quiet line over it says so with its first words.
local function composer(id: string): Node
	local draft = draft_of(id)
	local input = ui.ref()
	local menu = completion.menu({
		token = function()
			local text = draft:get()
			local before, query = string.match(text, "^(.-)@([%w%-_]*)$")
			if not query then
				return nil
			end
			local last = string.sub(before :: string, -1)
			if last ~= "" and not string.find(last, "[%s%(%[{>]") then
				return nil
			end
			return { trigger = "@", query = query :: string }
		end,
		results = function(token: completion.Token): { completion.Item }
			return participants(id, token.query)
		end,
		on_pick = function(item: completion.Item, token: completion.Token)
			local text = draft:peek()
			draft:set(`{string.sub(text, 1, #text - #token.trigger - #token.query)}{item.insert} `)
		end,
		empty = function(): string
			return "No matching participants. You can type any @username."
		end,
	}, {
		id = "pr_mention",
		on_accept = function()
			local el = input:peek()
			if el then
				el:focus()
			end
		end,
	})
	local function sending(): boolean
		local p = posting:get()
		return p ~= nil and p.id == id
	end
	local function idle(): boolean
		return sending() or not string.match(draft:get(), "%S")
	end
	return ui.column {
		id = "pr_comment_dock",
		w_full = true,
		shrink = 0,
		pb = ui.raw(pr.NAV_CLEARANCE, "the floating navigation's room"),
		ui.column {
			w_full = true,
			max_w = PAGE,
			self = "center",
			px = "$zeron.space.40",
			gap = "$zeron.space.8",
			ui.presence(function()
				local p = posting:get()
				return if p and p.id == id then p.body else nil
			end, function(body: string): Node
				local first = string.match(body, "^[^\n]*") or ""
				return ui.row {
					id = "pr_comment_pending",
					px = "$zeron.space.16",
					min_w = 0,
					gap = "$zeron.space.8",
					items = "center",
					kit.loaders.mini_spinner { cell = 1.5 },
					kit.text.text { "Posting comment", size = "sm", color = T.secondary, shrink = 0, line = false },
					kit.text.text {
						string.sub(first, 1, 160),
						literal = true,
						size = "sm",
						color = T.secondary,
						opacity = 0.7,
						truncate = true,
						shrink = 1,
						min_w = 0,
						line = false,
					},
				}
			end),
			ui.column {
				id = "pr_comment_surface",
				relative = true,
				w_full = true,
				min_h = 49,
				rounded = T.radius_composer,
				variants = kit.recipes.composer { edge = "pill" },
				menu.view,
				ui.presence(function()
					return comment_errors:get()[id]
				end, function(message: string): Node
					return kit.text.text {
						message,
						id = "pr_comment_error",
						size = "sm",
						color = T.danger,
						wrap = true,
						px = "$zeron.space.16",
						mt = "$zeron.space.12",
					}
				end),
				ui.row {
					w_full = true,
					pl = "$zeron.space.16",
					pr = "$zeron.space.8",
					gap = "$zeron.space.8",
					items = "end",
					ui.textarea {
						id = "pr_comment_input",
						ref = input,
						value = draft,
						label = "Comment",
						placeholder = "Write a comment… Type @ to mention someone",
						placeholder_color = T.tertiary,
						grow = 1,
						shrink = 1,
						min_w = 0,
						auto_height = true,
						min_h = 47,
						max_h = 140,
						px = 0,
						py = "$zeron.space.12",
						bg = T.clear,
						border = 0,
						rounded = 0,
						font = T.sans,
						text_size = "$font.size.lg",
						line_height = 22.75,
						color = T.text,
						focus = { border = 0 },
						wrap = true,
						chips = "@",
						chip_color = T.ink3,
						on_key = function(e: KeyEvent): boolean
							if menu.on_key(e) then
								return true
							end
							if e.key == "Enter" and not e.shift then
								send(id)
								return true
							end
							return false
						end,
					},
					ui.row {
						h = 47,
						shrink = 0,
						items = "center",
						ui.presence(function()
							return if sending() then "sending" else "send"
						end, function(phase: string): Node
							if phase == "sending" then
								return ui.row {
									id = "pr_send_comment",
									role = "button",
									label = "Sending comment",
									w = 28,
									h = 28,
									items = "center",
									justify = "center",
									kit.loaders.mini_spinner { cell = 1.5 },
								}
							end
							return ui.button {
								id = "pr_send_comment",
								label = "Send comment",
								w = 28,
								h = 28,
								p = 0,
								items = "center",
								justify = "center",
								rounded = T.radius_full,
								focus = { border = 0 },
								variants = kit.recipes.send_button { idle = idle },
								on_click = function()
									send(id)
								end,
								kit.icon { name = "arrow-up", size = 14, color = "currentColor" },
							}
						end),
					},
				},
			},
		},
	}
end

-- ---- the page ----------------------------------------------------------------------

local function page(id: string): Node
	local r = row_of(id)
	local d = detail_of(id)
	local view = page_of(id)
	-- The Code column, whose width decides where the file tree goes.
	local workspace = ui.ref()
	local function ready(): boolean
		return loaded:get()[id] ~= nil
	end
	-- Why the last read failed, and Try again (error_strip, pr-retry): over
	-- what was read before, or in its place.
	local function failure(): Node
		return ui.presence(function()
			return read_errors:get()[id]
		end, function(message: string): Node
			return ui.column {
				w_full = true,
				gap = "$zeron.space.8",
				items = "start",
				kit.notice { id = "pr_read_error", message = message, tone = "danger", w_full = true },
				kit.button {
					id = "pr_retry",
					label = "Try again",
					variant = "ghost",
					on_click = function()
						refresh(id)
					end,
				},
			}
		end, { w_full = true })
	end
	-- The reading area: selectable, so a press and a drag select its text
	-- and ⌘C copies it; each section keeps where it was scrolled.
	local function scrolled(tab: string, body: Node): Node
		return kit.scroll {
			id = "pr_detail_scroll",
			grow = 1,
			w_full = true,
			fade = 24,
			offset = if tab == "activity" then view.activity else view.summary,
			ui.column {
				id = "pr_content_column",
				w_full = true,
				max_w = PAGE,
				self = "center",
				min_h = if tab == "activity" then "100%" else nil,
				px = "$zeron.space.40",
				pt = "$zeron.space.24",
				pb = if tab == "activity" then "$zeron.space.32" else ui.raw(76, "the floating navigation's room"),
				selectable = true,
				failure(),
				body,
			},
		}
	end
	local content = ui.presence(function()
		local phase = if ready() then "ready" elseif read_errors:get()[id] then "failed" else "loading"
		return `{view.tab:get()}|{phase}`
	end, function(key: string): Node
		local tab, phase = string.match(key, "^(%w+)|(%w+)$")
		if phase == "failed" then
			return scrolled(tab :: string, ui.div {})
		end
		if tab == "code" then
			return ui.column {
				id = "pr_content_column",
				ref = workspace,
				grow = 1,
				w_full = true,
				min_h = 0,
				px = "$zeron.space.24",
				pt = "$zeron.space.24",
				ui.presence(function()
					return diff_errors:get()[id]
				end, function(message: string): Node
					return ui.column {
						w_full = true,
						gap = "$zeron.space.8",
						items = "start",
						kit.notice { id = "pr_diff_error", message = message, tone = "danger", w_full = true },
						kit.button {
							id = "pr_retry_diff",
							label = "Retry diff",
							icon = { name = "refresh" },
							variant = "ghost",
							on_click = function()
								load_diff(id)
							end,
						},
					}
				end, { w_full = true }),
				ui.show(
					function()
						return diff_errors:get()[id] == nil
					end,
					pr_code.view {
						id = "pr_code",
						patch = function()
							return if diffs:get()[id] then d.patch else nil
						end,
						totals = function()
							return { files = #pr_code.files(d.patch), added = r.added, removed = r.removed }
						end,
						wide = function()
							-- Its content box: the column less its 24 a side.
							return (workspace.width or 0) - 48 >= pr_code.WIDE
						end,
						split = split,
						query = view.query,
						picker = view.picker,
						offset = view.code,
						highlight = syntax.for_path,
						on_copy = copy,
					}
				),
			}
		end
		local at = loaded:peek()[id]
		if phase == "loading" then
			-- The loaded layout with placeholders: the board's row gives
			-- the header, so nothing moves when the pull request arrives.
			return scrolled(
				tab :: string,
				ui.column {
					w_full = true,
					header(r, d, nil),
					pr.summary_skeleton { id = "pr_detail_skeleton", gap = CARD_GAP },
				}
			)
		elseif tab == "activity" then
			return scrolled("activity", ui.column { w_full = true, grow = 1, header(r, d, at), activity(id, d) })
		end
		return scrolled("summary", ui.column { w_full = true, header(r, d, at), summary(id, r, d) })
	end, { grow = 1, w_full = true, min_h = 0 })
	return ui.column {
		id = "pr_detail",
		relative = true,
		w_full = true,
		h_full = true,
		on_mount = function()
			arrive(id)
			if loaded:peek()[id] == nil then
				load(id)
			end
		end,
		content,
		ui.show(function()
			return view.tab:get() == "activity" and ready()
		end, composer(id)),
		pr.nav {
			id = "pr_nav",
			value = view.tab,
			tabs = {
				{ id = "summary", label = "Summary", icon = "document" },
				{
					id = "code",
					label = "Code",
					icon = "file-code",
					count = function()
						return if ready() then #pr_code.files(d.patch) else nil
					end,
				},
				{
					id = "activity",
					label = "Activity",
					icon = "chat-round-line",
					count = function()
						return if ready() then #messages(id) else nil
					end,
				},
			},
		},
		loading_image(),
	}
end
-- A pull request's view (render_chat_pull_request): its toolbar, then its
-- page.
function M.view(id: string): Node
	return ui.column {
		w_full = true,
		h_full = true,
		items = "stretch",
		toolbar(id),
		ui.column { w_full = true, grow = 1, min_h = 0, items = "stretch", page(id) },
	}
end

-- The pull request beside the board (its pane's active tab), built (and
-- read) only while the pane is open; a pane of its own (`alone`, whose
-- header holds the actions) always shows it.
function M.detail(alone: boolean?): Node
	if alone then
		return ui.presence(state.pr, page, { w_full = true, h_full = true })
	end
	return ui.presence(function(): string?
		return if state.prs.open.right:get() then state.pr:get() else nil
	end, M.view, { w_full = true, h_full = true })
end

-- The diff loads on the first visit to Code, once the pull request has.
ui.effect(function()
	local id = showing:get()
	if id ~= "" and page_of(id).tab:get() == "code" and loaded:get()[id] ~= nil then
		load_diff(id)
	end
end)

-- Whether pull request `id` is being read (its tab spins).
function M.reading(id: string): boolean
	return loading:get() == id
end

-- ---- the board's pane's tabs ---------------------------------------------------

-- A tab's menu (TabCloseAction): close it, the others, or those to its
-- left or right; a row with none to close is inert.
local CLOSES: { { string } } = {
	{ "this", "Close tab" },
	{ "others", "Close other tabs" },
	{ "left", "Close tabs to the left" },
	{ "right", "Close tabs to the right" },
}
local function tab_menu(prefix: string, id: string): { Node }
	local items: { Node } = {}
	for _, c in CLOSES do
		local action = c[1] :: state.CloseAction
		local closes = state.pr_tabs_to_close(id, action)
		table.insert(
			items,
			kit.menu_item({
				id = `{prefix}_prs_tab_{id}_menu_{action}`,
				label = c[2],
				disabled = #closes == 0,
				on_click = function()
					for _, tab in closes do
						state.close_pr_tab(tab)
					end
				end,
			}, function() end, nil, nil, "popover")
		)
	end
	return items
end

-- The pane's tabs (render_pull_request_tab_strip), in the titlebar over it
-- as the chat's are: each the pull request's title (spinning while it
-- reads), closed by its ×, its menu or ⌘W, dragged along the strip to
-- reorder. Choosing one is a place of its own (Back returns to the one
-- viewed before): the strip chooses into its own state, which follows the
-- pane's and opens what it is given.
function M.strip(prefix: string): Node
	local chosen = ui.state(`{prefix}_prs_chosen`, state.pr:peek())
	ui.effect(function()
		chosen:set(state.pr:get())
	end)
	ui.effect(function()
		local id = chosen:get()
		if id ~= state.pr:peek() then
			state.open_pr(id)
		end
	end)
	return require("@kit/right_panel").strip {
		id = `{prefix}_prs`,
		items = state.pr_tabs :: any,
		look = function(t: { id: string }): any
			return {
				id = t.id,
				title = row_of(t.id).title,
				icon = "pull-request",
				loading = function(): boolean
					return M.reading(t.id)
				end,
			}
		end,
		active = chosen,
		reorderable = true,
		menu = function(id: string): { Node }
			return tab_menu(prefix, id)
		end,
		on_close_tab = state.close_pr_tab,
	}
end

-- ---- where a pull request opens --------------------------------------------------

-- Pull request `id` where Settings → General sends it ("Open pull requests
-- in"; pull_request_detail.rs open_on_device, chat_pull_requests.rs): the
-- pull request view (a tab in the session's right pane while a session is
-- on screen, beside the board otherwise), a browser tab in that pane (the
-- default browser without one), or the default browser.
function M.open(id: string)
	local to = require("./settings").pref.open_prs:peek()
	local url = detail_of(id).url
	local beside_chat = not state.tabbed_now() and state.route:peek() == "chat" and state.session:peek() ~= "new"
	if to == "Default browser" or (to == "In-app browser" and not beside_chat) then
		ui.open_url(url)
	elseif to == "In-app browser" then
		local tab = state.open_tab("preview")
		if tab then
			require("./browser").navigate(tab, url)
		end
	elseif beside_chat then
		state.open_pr_tab(id)
	else
		state.open_pr(id, true)
	end
end

-- Session `key`'s pull request (its sidebar badge, its composer's).
function M.open_session(key: string)
	local s = data.session(key)
	local p = s and s.pr
	if s and p then
		local status: pr.Status = if p.state == "draft" then "draft" elseif p.state == "merged" then "merged" else "open"
		M.open(M.by_number(p.number, `zeron/{s.project}`, s.title, status, s.branch))
	end
end

state.hooks.pr_link = M.link
state.hooks.show_pr = M.open
state.hooks.open_session_pr = M.open_session

return M
