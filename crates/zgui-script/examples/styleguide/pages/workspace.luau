-- Workspace: the files tree, pull requests, comments and attachments.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local file_tree = require("@kit/file_tree")
local pr = require("@kit/pr")
local history = require("@kit/history")

local tree_sel = ui.state("tree_sel", "f3")
local tree_open = ui.state("tree_open", { src = true, kit = true, shell = false })
local prs_open = ui.state("prs_open", true)
local prs_done = ui.state("prs_done", false)
local draft = ui.state("comment_draft", "")
local commit_sel = ui.state("commit_sel", "bd62d21a")
local commit_query = ui.state("commit_query", "")

local COMMITS: { history.Commit } = {
	{
		sha = "bd62d21a",
		subject = "styleguide: ⌘K jumps to a page through the kit's palette",
		author = "Gaël Cado",
		date = "2m ago",
		lane = 0,
		parents = { 0 },
		refs = { "main", "origin/main" },
		head = true,
	},
	{
		sha = "3b87140c",
		subject = "styleguide: the Zeron app's todo tray, usage chip and update strip",
		author = "Gaël Cado",
		date = "1h ago",
		lane = 0,
		parents = { 0, 1 },
	},
	{
		sha = "efad969d",
		subject = "styleguide: files tree, pull requests, comments, attachments",
		author = "Gaël Cado",
		date = "2h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "a1c2e3f4",
		subject = "glass: the hover layer under the active one",
		author = "Wing",
		date = "3h ago",
		lane = 1,
		parents = { 1 },
		refs = { "wing/glass" },
	},
	{
		sha = "9c245b6e",
		subject = "styleguide: parity for dictation, context usage and the trays",
		author = "Gaël Cado",
		date = "3h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "7f8e9d0c",
		subject = "glass: press gives to 0.985",
		author = "Wing",
		date = "5h ago",
		lane = 1,
		parents = { 0 },
	},
	{
		sha = "2537d86b",
		subject = "styleguide: motion tokens for the morph, roll, tab slide and glide",
		author = "Gaël Cado",
		date = "6h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "51f122b0",
		subject = "styleguide: the Zeron app's transcript from the kit",
		author = "Gaël Cado",
		date = "7h ago",
		lane = 0,
		parents = {},
	},
}

local function commits(): Node
	return ui.column {
		gap = "$zeron.space.16",
		items = "start",
		ui.row {
			gap = "$zeron.space.12",
			items = "center",
			history.search { id = "commit_search", value = commit_query },
		},
		specimen.cell {
			label = "rows 36 · lanes 12 · nodes 3, HEAD ring +2 · strokes 1.5 · subject 12 · refs 16 · author 20 · date and sha 10.5",
			specimen.frame {
				w = 760,
				p = 0,
				bg = T.card,
				overflow = "hidden",
				history.table { id = "commits", commits = COMMITS, selected = commit_sel },
			},
		},
		history.more { id = "commits_more" },
	}
end

local function entries(): { file_tree.Entry }
	local o = tree_open:get()
	local list: { file_tree.Entry } = {
		{ id = "src", name = "src", level = 0, folder = true, open = o.src },
	}
	if o.src then
		table.insert(
			list,
			{ id = "kit", name = "kit", level = 1, folder = true, open = o.kit, icon = "folder-with-files" } :: file_tree.Entry
		)
		if o.kit then
			table.insert(
				list,
				{ id = "f1", name = "button.luau", level = 2, icon = "file-code", git = "modified" } :: file_tree.Entry
			)
			table.insert(
				list,
				{ id = "f2", name = "dictation.luau", level = 2, icon = "file-code", git = "added" } :: file_tree.Entry
			)
			table.insert(list, { id = "f3", name = "row.luau", level = 2, icon = "file-code" } :: file_tree.Entry)
		end
		table.insert(
			list,
			{ id = "shell", name = "shell", level = 1, folder = true, open = o.shell } :: file_tree.Entry
		)
		table.insert(
			list,
			{ id = "f4", name = "theme.luau", level = 1, icon = "file-code", git = "renamed" } :: file_tree.Entry
		)
		table.insert(list, { id = "f5", name = "zeron-dark.json", level = 1, icon = "file-data" } :: file_tree.Entry)
	end
	table.insert(list, { id = "f6", name = "README.md", level = 0, icon = "file-markdown" } :: file_tree.Entry)
	table.insert(
		list,
		{ id = "f7", name = "notes.old", level = 0, icon = "document", git = "ignored" } :: file_tree.Entry
	)
	table.insert(
		list,
		{ id = "f8", name = "legacy.rs", level = 0, icon = "file-code", git = "deleted" } :: file_tree.Entry
	)
	return list
end

local function tree(): Node
	return specimen.cell {
		label = "rows 27 · indent 14 · guides 1 · chevron 11 · icon 14 · name 11.5 · git colours",
		specimen.frame {
			w = 260,
			p = 0,
			bg = T.glass,
			overflow = "hidden",
			ui.presence(function()
				local o = tree_open:get()
				return `{o.src}{o.kit}{o.shell}`
			end, function(): Node
				return file_tree.tree {
					id = "tree",
					entries = entries(),
					selected = tree_sel,
					on_toggle = function(id: string)
						local o = table.clone(tree_open:peek())
						o[id] = not o[id]
						tree_open:set(o)
					end,
				}
			end, { w_full = true, py = "$zeron.space.6" }),
		},
	}
end

local ROWS: { pr.Row } = {
	{
		id = "p1",
		title = "Scroll fade on the transcript's bottom edge",
		number = 412,
		author = "Gaël Cado",
		status = "open",
		checks = "passed",
		sha = "9c245b6",
		date = "2h ago",
		added = 128,
		removed = 41,
		labels = { "ui" },
	},
	{
		id = "p2",
		title = "Dictation: the stop plate on the accent glass",
		number = 409,
		author = "Wing",
		status = "changes",
		checks = "failed",
		sha = "51f122b",
		date = "yesterday",
		added = 302,
		removed = 17,
		starred = true,
	},
	{
		id = "p3",
		title = "WIP: queue tray drag",
		number = 401,
		author = "Gaël Cado",
		status = "draft",
		date = "3d ago",
		added = 44,
		removed = 9,
	},
	{
		id = "p4",
		title = "Rebase onto the new layout root",
		number = 398,
		author = "Wing",
		status = "conflicting",
		checks = "pending",
		sha = "2cec833",
		date = "4d ago",
		added = 12,
		removed = 230,
		labels = { "layout", "breaking" },
	},
}

local function prs(): Node
	local rows: { Node } = {}
	for i, r in ROWS do
		table.insert(rows, pr.row { id = `pr_{r.id}`, row = r, first = i == 1, group = "prs_open" })
	end
	return ui.column {
		gap = "$zeron.space.24",
		items = "start",
		specimen.cell {
			label = "group card on wash 4.5% at 12 · rows ≥ 64 · title 13 · meta 11 · side 112 · star 28",
			pr.group { id = "prs", label = "Open", count = #ROWS, open = prs_open, w = 760, list = "prs_open", rows },
		},
		specimen.cell {
			label = "skeleton · bars ink 7% at 0.45 ± 0.4 on the 2.4 s pulse",
			ui.column {
				gap = "$zeron.space.8",
				w = 760,
				pr.group { label = "Merged", count = 3, open = prs_done, w = 760 },
				pr.skeleton { rows = 2 },
			},
		},
	}
end

local checks_open = ui.state("checks_open", true)
local verify = ui.state("verify", "relevant")

local function detail(): Node
	local function check(name: string, tone: pr.Tone, last: boolean?): Node
		return ui.row {
			w_full = true,
			min_h = 36,
			px = "$zeron.space.16",
			py = "$zeron.space.4",
			items = "center",
			gap = "$zeron.space.12",
			kit.text.text { name, size = "md", grow = 1, truncate = true, line = false },
			pr.status_chip { tone = tone },
		}
	end
	return ui.column {
		gap = "$zeron.space.24",
		items = "start",
		specimen.cell {
			label = "header · title 20/26 · meta 12 with 13 icons · status chips px 8 py 3 radius 6",
			ui.column {
				w = 760,
				gap = "$zeron.space.12",
				kit.text.text {
					"Scroll fade on the transcript's bottom edge",
					size = "xxl",
					weight = "medium",
					wrap = true,
				},
				ui.row {
					gap = "$zeron.space.8",
					items = "center",
					flex_wrap = true,
					ui.row {
						gap = "$zeron.space.8",
						items = "center",
						kit.avatar { name = "Gaël Cado", size = 20 },
						kit.text.text { "Gaël Cado", size = "sm", line = false },
					},
					ui.row {
						gap = "$zeron.space.4",
						items = "center",
						kit.icon { name = "folder", size = 13, color = T.secondary },
						kit.text.text { "zeronsh/zgui", size = "sm", color = T.secondary, line = false },
					},
					ui.row {
						gap = "$zeron.space.4",
						items = "center",
						kit.icon { name = "pull-request", size = 13, color = T.secondary },
						kit.text.text { "#412", size = "sm", color = T.secondary, line = false },
					},
					ui.row {
						gap = "$zeron.space.4",
						items = "center",
						kit.icon { name = "clock-circle", size = 13, color = T.secondary },
						kit.text.text { "Loaded 2m ago", size = "sm", color = T.secondary, line = false },
					},
				},
				ui.row {
					gap = "$zeron.space.8",
					flex_wrap = true,
					pr.status_chip { tone = "open" },
					pr.status_chip { tone = "approved" },
					pr.status_chip { tone = "passed" },
					pr.status_chip { tone = "merged" },
					pr.status_chip { tone = "closed" },
					pr.status_chip { tone = "failed" },
					pr.status_chip { tone = "changes" },
					pr.status_chip { tone = "awaiting" },
					pr.status_chip { tone = "draft" },
				},
			},
		},
		specimen.cell {
			label = "checks card · header 16×10 · rows ≥ 36",
			ui.column {
				w = 560,
				rounded = T.radius_card,
				bg = T.card,
				overflow = "hidden",
				ui.button {
					id = "checks_header",
					w_full = true,
					px = "$zeron.space.16",
					py = "$zeron.space.10",
					gap = "$zeron.space.8",
					items = "center",
					bg = T.clear,
					hover = { bg = T.glass_hover },
					focus = { border = 0 },
					cursor = "pointer",
					on_click = ui.toggle(checks_open),
					kit.disclosure.chevron { open = checks_open, size = 14, color = T.secondary },
					kit.text.text { "Checks · 2 of 3 passed", size = "md", grow = 1, line = false },
					pr.status_chip { tone = "pending" },
				},
				ui.presence(function()
					return if checks_open:get() then "rows" else nil
				end, function(): Node
					return ui.column {
						w_full = true,
						pb = "$zeron.space.4",
						check("build · macOS", "passed"),
						check("build · Linux", "passed"),
						check("test · styleguide", "pending", true),
					}
				end, {
					w_full = true,
					layout = "height",
					enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.COLLAPSE) },
					exit = { opacity = 0, duration = kit.motion.d(kit.motion.COLLAPSE) },
				}),
			},
		},
		specimen.cell {
			label = "handoff card · filled buttons · verification segments · checkout row with an 80 label",
			ui.column {
				w = 760,
				rounded = T.radius_card,
				bg = T.card,
				overflow = "hidden",
				ui.row {
					px = "$zeron.space.16",
					py = "$zeron.space.12",
					min_h = 60,
					gap = "$zeron.space.16",
					items = "center",
					flex_wrap = true,
					ui.column {
						min_w = 220,
						gap = "$zeron.space.2",
						kit.text.text { "Hand off to an agent", size = "md", weight = "medium" },
						kit.text.text {
							"Opens a new session with the prompt ready to send.",
							size = "sm",
							color = T.secondary,
						},
					},
					ui.div { grow = 1 },
					ui.row {
						gap = "$zeron.space.8",
						flex_wrap = true,
						kit.button { label = "Review", icon = { name = "eye" }, size = "sm", variant = "secondary" },
						kit.button {
							label = "Address feedback",
							icon = { name = "chat-round-line" },
							size = "sm",
							variant = "secondary",
						},
						kit.button {
							label = "Fix failing checks",
							icon = { name = "danger-triangle" },
							size = "sm",
							variant = "secondary",
						},
						kit.button {
							label = "Resolve conflicts",
							icon = { name = "pull-request" },
							size = "sm",
							variant = "secondary",
						},
					},
				},
				ui.row {
					px = "$zeron.space.16",
					py = "$zeron.space.12",
					min_h = 44,
					gap = "$zeron.space.16",
					items = "center",
					border_sides = { 1, 0, 0, 0 },
					border_color = T.hairline,
					kit.text.text { "Verification", size = "md", weight = "medium", w = 80 },
					kit.segmented {
						id = "verify",
						value = verify,
						size = "sm",
						options = {
							{ id = "relevant", label = "Relevant platforms" },
							{ id = "macos", label = "macOS" },
							{ id = "linux", label = "Linux" },
							{ id = "windows", label = "Windows" },
						},
					},
				},
				ui.row {
					px = "$zeron.space.16",
					py = "$zeron.space.12",
					min_h = 44,
					gap = "$zeron.space.16",
					items = "center",
					border_sides = { 1, 0, 0, 0 },
					border_color = T.hairline,
					kit.text.text { "Checkout", size = "md", weight = "medium", w = 80 },
					kit.text.text {
						"gh pr checkout 412 && cargo test -p zgui-script",
						size = "sm",
						mono = true,
						color = T.secondary,
						truncate = true,
						grow = 1,
						shrink = 1,
						min_w = 0,
					},
					kit.icon_button { icon = "copy", size = 24, icon_size = 14, label = "Copy", no_ring = true },
				},
			},
		},
		specimen.cell {
			label = "PR badges · sidebar 16 · composer 20 · the tone at 8%, text at 85%",
			ui.row {
				gap = "$zeron.space.12",
				items = "center",
				pr.badge { tone = "open", number = 412 },
				pr.badge { tone = "merged", number = 398 },
				pr.badge { tone = "closed", number = 377 },
				pr.badge { tone = "open", number = 412, size = "md" },
				pr.badge { tone = "merged", number = 398, size = "md" },
			},
		},
	}
end

local function comments(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell { label = "add button 16 on the solid", kit.comment.add() },
		specimen.cell {
			label = "comment card · ink 5% · rail 3 at 35% · header 22 · body 12/18",
			kit.comment.card {
				id = "comment",
				where = "crates/zgui/src/compose.rs:412",
				body = "This recentres the page when its height changes mid-press, which drops the click. Centre from the parent instead.",
				w = 420,
			},
		},
		specimen.cell {
			label = "draft · ink 8% · rail at 70% · input 46 · actions 22",
			kit.comment.draft { id = "draft", where = "kit/row.luau:98", value = draft, w = 420 },
		},
	}
end

local function attachments(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "composer tiles 56 · radius 8 · remove 18 at −6,−6 on hover",
			ui.row {
				gap = "$zeron.space.8",
				pt = "$zeron.space.8",
				kit.attachments.tile {
					id = "tile_img",
					name = "screen.png",
					image = ui.raw("#3b4a6b", "a stand-in image"),
				},
				kit.attachments.tile { name = "sunset.jpg", image = ui.raw("#8a4b3a", "a stand-in image") },
				kit.attachments.tile { name = "notes.md", icon = "file-markdown" },
				kit.attachments.tile { name = "data.csv", icon = "file-data" },
			},
		},
		specimen.cell {
			label = "inline chips · radius 5 on ink 9% · icon well inset 1",
			ui.row {
				gap = "$zeron.space.6",
				kit.attachments.chip { label = "row.luau", icon = "file-code" },
				kit.attachments.chip { label = "kit/", icon = "folder" },
				kit.attachments.chip { label = "screen.png", icon = "gallery" },
				kit.attachments.chip { label = "/commit", icon = "command" },
			},
		},
		specimen.cell {
			label = "transcript thumbnails 112×80 · loaded / loading / failed",
			ui.row {
				gap = "$zeron.space.8",
				kit.attachments.thumb { image = ui.raw("#3b4a6b", "a stand-in image") },
				kit.attachments.thumb { state = "loading" },
				kit.attachments.thumb { state = "error" },
			},
		},
	}
end

return function(): Node
	local p = state.page_by("workspace")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section { title = "Files", tree() },
		specimen.section { title = "Pull requests", prs() },
		specimen.section { title = "History", commits() },
		specimen.section { title = "Pull request detail", detail() },
		specimen.section { title = "Comments", comments() },
		specimen.section { title = "Attachments", attachments() },
	}
end
