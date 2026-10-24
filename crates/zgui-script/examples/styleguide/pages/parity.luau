-- Parity: each pattern as Zeron draws it today (the numbers, from its
-- source) next to the kit's version. The spec is the reference until a
-- crop of the real app sits beside it.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local agent_row = require("@kit/agent_row")
local tray = require("@kit/tray")
local dictation = require("@kit/dictation")
local file_tree = require("@kit/file_tree")
local pr = require("@kit/pr")
local history = require("@kit/history")
local browser_kit = require("@kit/browser")

type Entry = { id: string, title: string, source: string, spec: { string }, render: () -> Node }

local sel = ui.state("parity_sel", "b")
local open = ui.state("parity_open", false)

local tab = ui.state("parity_tab", "b")
local pal_query = ui.state("parity_pal_query", "term")
local pal_sel = ui.state("parity_pal_sel", "t1")
local par_dict = ui.state("parity_dict", "listening" :: dictation.Phase)
local par_usage = ui.state("parity_usage", 0.81 :: number?)
local par_todo = ui.state("parity_todo", true)
local par_tree = ui.state("parity_tree", "b")
local par_commit = ui.state("parity_commit", "")
local par_ftab = ui.state("parity_ftab", "code")
local par_rec = ui.state("parity_rec", true)
local par_queue = ui.state(
	"parity_queue",
	{
		{ id = "pq1", text = "Then run the tests and fix what fails" },
		{ id = "pq2", text = "Open a PR against main", attachments = 1 },
	} :: { tray.Queued }
)
local ENTRIES: { Entry } = {
	{
		id = "tabstrip",
		title = "Tab strip (zterm)",
		source = "zgui-desktop/examples/terminal/components/tabs.luau:153–351",
		spec = {
			"tab 28 · pl 3 pr 10 · gap 7 · radius 8 · max 210 · text 12.5",
			"icon tile as far in from the edge as from the top",
			"active glass slides between tabs (320 ms, .22 1 .36 1) over a hover glass (140 in, 220 out)",
			"a 6 px bell dot on a background tab",
		},
		render = function()
			return specimen.frame {
				w = 420,
				p = "$zeron.space.6",
				bg = T.glass,
				kit.tabstrip {
					id = "parity_tabs",
					value = tab,
					tabs = {
						{ id = "a", label = "Editor", icon = "document" },
						{ id = "b", label = "zgui", icon = "terminal", bell = true },
						{ id = "c", label = "Hacker News", icon = "globe" },
					},
				},
			}
		end,
	},
	{
		id = "agent",
		title = "Agent row (zterm sidebar)",
		source = "zgui-desktop/examples/terminal/components/sidebar.luau:116–288",
		spec = {
			"px 10 · py 7 · gap 10 · radius 8 · glyph 16",
			"name 13/500 · ago 11 tabular · status 11.5 (amber when blocked)",
			"mark 10: a turning arc (900 ms) · a 6 px dot · an 11 px check · a hollow ring",
			"press gives to 0.985 and springs back (outBack 2)",
		},
		render = function()
			local a: agent_row.Agent = {
				id = "p1",
				name = "300-word story",
				where = "zgui",
				status = "working",
				icon = "claude-mark",
				tint = T.claude,
				ago = "5m",
			}
			local b: agent_row.Agent = {
				id = "p2",
				name = "",
				where = "~/zeron/zgui",
				status = "blocked",
				waits = "question",
				icon = "openai-mark",
				ago = "now",
			}
			return specimen.frame {
				w = 272,
				p = "$zeron.space.8",
				gap = "$zeron.space.1",
				items = "stretch",
				bg = T.glass,
				agent_row.row {
					agent = function()
						return a
					end,
					selected = function()
						return true
					end,
					group = "parity-agents",
				},
				agent_row.row {
					agent = function()
						return b
					end,
					selected = function()
						return false
					end,
					group = "parity-agents",
				},
			}
		end,
	},
	{
		id = "palette",
		title = "Palette (zterm)",
		source = "zgui-desktop/examples/terminal/components/palette.luau",
		spec = {
			"frost · radius 14 · 560 wide · header 44 with the query and its count",
			"group title 11 caps · row 36 radius 10 · title 13, match semibold · meta 11 at the end",
			"footer of key hints 11 on a hairline · ↑↓ move · ↩ open · esc close",
		},
		render = function()
			return kit.palette {
				id = "parity_palette",
				placeholder = "Open a terminal, a browser or a panel",
				query = pal_query,
				count = "3 results",
				selected = pal_sel,
				w = 480,
				results = {
					{
						id = "t1",
						match = "Term",
						title = "inal",
						description = "a shell in this project",
						group = "Open",
						icon = "terminal",
						keys = { "↩" },
					},
					{
						id = "t2",
						match = "Term",
						title = "inal in ~/zeron/zgui",
						group = "Open",
						icon = "terminal",
						meta = "⌘ ⇧ T",
					},
					{ id = "t3", title = "Browser", description = "a new tab", group = "Open", icon = "globe" },
				},
				hints = {
					{ keys = { "↑", "↓" }, label = "move" },
					{ keys = { "↩" }, label = "open" },
					{ keys = { "esc" }, label = "close" },
				},
			}
		end,
	},
	{
		id = "popover",
		title = "Popover card and menu row",
		source = "ui/src/popover.rs:307–315, 329, 910",
		spec = {
			"card radius 12 · inset 4 · gap 2 · hairline · text 13",
			"row radius 7 (12 − 1 − 4) · padding 8×6 · gap 10",
			"rest text 0.9 → 1 · fill wash 0 → selected, 150 ms",
			"frost blur 16 · in 140 ms (0.3 → 1, −2 px) · out 100 ms",
		},
		render = function()
			return kit.frost.card {
				w = 240,
				kit.menu_item({ label = "Rename", icon = "pen", keys = { "⌘", "R" } }, function() end),
				kit.menu_item({ label = "Duplicate", icon = "copy" }, function() end),
				kit.menu_item({ label = "Pin to sidebar", icon = "pin", checked = true }, function() end),
				ui.div { h = 1, my = "$zeron.space.4", mx = "$zeron.space.6", bg = T.hairline },
				kit.menu_item(
					{ label = "Delete thread…", icon = "trash-bin-minimalistic", danger = true },
					function() end
				),
			}
		end,
	},
	{
		id = "sidebar_row",
		title = "Sidebar chat row",
		source = "ui/src/shell.rs:7718–8307, 943–962",
		spec = {
			"height 29 compact · 45 regular · 47 + 14 with metadata",
			"radius 8 · padding 8×6 · gap 2",
			"title 13/17 · subline 11/14 muted 0.5 · status 10 medium + 6 px dot",
			"rest text 0.8 → 1 over 150 ms · selected = card_selected_bg, no ring",
		},
		render = function()
			local function on(id: string): () -> boolean
				return function()
					return sel:get() == id
				end
			end
			return specimen.frame {
				w = 260,
				p = "$zeron.space.6",
				gap = "$zeron.space.1",
				items = "stretch",
				bg = T.glass,
				kit.row {
					label = "Refactor the layout engine",
					description = "zgui @ MacBook Pro",
					dot = T.accent,
					group = "parity",
					selected = on("a"),
					on_click = ui.set(sel, "a"),
				},
				kit.row {
					label = "Write the release notes",
					description = "comet @ MacBook Pro",
					dot = T.warning,
					group = "parity",
					selected = on("b"),
					on_click = ui.set(sel, "b"),
				},
				kit.row {
					label = "Fix flaky test",
					description = "zgui @ MacBook Pro",
					dot = T.success,
					group = "parity",
					selected = on("c"),
					on_click = ui.set(sel, "c"),
				},
			}
		end,
	},
	{
		id = "edge_fade",
		title = "Edge fade",
		source = "ui/src/edge_fade.rs:51, shell.rs:1050, popover.rs:398",
		spec = {
			"band: sidebar 24 · menus 12 · transcript 24 (inset 38) · tab strips 36 · settings 16",
			"only where content runs past the edge",
			"label truncation: right fade 20, eased in over one band",
		},
		render = function()
			local rows: { Node } = {}
			for i = 1, 12 do
				table.insert(rows, kit.row { label = `Row {i}`, size = "sm", icon = "document" })
			end
			return specimen.frame {
				w = 240,
				h = 180,
				p = 0,
				bg = T.glass,
				kit.scroll {
					h_full = true,
					w_full = true,
					p = "$zeron.space.6",
					gap = "$zeron.space.1",
					fade = 24,
					rows,
				},
			}
		end,
	},
	{
		id = "chrome",
		title = "Surface chrome",
		source = "ui/src/surface_chrome.rs:7–84",
		spec = {
			"toolbar 38 · top and bottom hairline · surface at 26% on glass",
			"controls 24 square · radius 6 · icon 14 · gap 4 · edge inset 8",
			"tab 24 · radius 6 · text 12 · selected wash 10% · hover 6%",
			"field 24 · padding 8 · ink 3.5% · text 11.5",
		},
		render = function()
			return specimen.frame {
				w = 420,
				p = 0,
				items = "stretch",
				kit.chrome.toolbar {
					kit.chrome.tab { label = "Files", selected = true },
					kit.chrome.tab { label = "Changes" },
					ui.div { grow = 1 },
					kit.chrome.control { icon = "sort" },
					kit.chrome.control { icon = "refresh" },
				},
			}
		end,
	},
	{
		id = "buttons",
		title = "Text buttons",
		source = "ui/src/popover.rs:1325–1361, settings/widgets.rs:1514",
		spec = {
			"btn_ghost · btn_primary · btn_danger: padding 12×6 · radius 8 · text 13",
			"ghost wash 0 → ink 6%, muted → full · primary = text fill, on_solid label, hover 0.9",
			"settings action_button min height 32 · text 12.5",
			"spread today: 15 heights, 13 radii, ~20 hover fills",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.8",
				kit.button { label = "Cancel", variant = "ghost" },
				kit.button { label = "Review" },
				kit.button { label = "Approve", variant = "primary" },
				kit.button { label = "Delete", variant = "danger" },
			}
		end,
	},
	{
		id = "icon_buttons",
		title = "Icon buttons",
		source = "ui/src/shell.rs:12785, 12971, files/mod.rs:59",
		spec = {
			"window control 24 · header 28 · toolbar 24 · all radius 6",
			"icon 14–16 · hover wash 11–14% blended",
			"spread today: 11 square sizes",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.8",
				items = "center",
				kit.icon_button { icon = "settings", size = 28 },
				kit.icon_button { icon = "pen", size = 24 },
				kit.icon_button { icon = "close", size = 24, icon_size = 14 },
			}
		end,
	},
	{
		id = "pill",
		title = "Running pill",
		source = "ui/src/running_pill.rs:18–26, 175, 222",
		spec = {
			"16 high · 5 px dot · padding 6 · gap 4 · fully rounded",
			"busy at 16% · Geist Mono 10 medium · dot 0.4 → 1 on the 2.4 s clock · caps at 99+",
		},
		render = function()
			return ui.row { gap = "$zeron.space.12", kit.pill { count = 3 }, kit.pill { count = 120 } }
		end,
	},
	{
		id = "spinner",
		title = "Loaders",
		source = "ui/src/loaders.rs:117, 154, popover.rs:1377–1447",
		spec = {
			"gradient spinner 3×3 · cell 2.5 · 750 ms upward wave · row tints",
			"mini spinner 2×3 · perimeter chase · sidebar cell 2",
			"skeleton bars ink 4–8% · opacity 0.35 + 0.4·wave · rows 28 radius 6",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.24",
				items = "center",
				kit.loaders.gradient_spinner {},
				kit.loaders.mini_spinner {},
				kit.loaders.skeleton { rows = 2, w = 160 },
			}
		end,
	},
	{
		id = "dictation",
		title = "Dictation",
		source = "ui/src/composer.rs:10150–10530, dictation/waveform.rs, dictation/glass.rs",
		spec = {
			"mic 28 · icon 18 muted · hover ink 10% · morph 420 ms (.2 0 0 1)",
			"stop plate: accent glass, square 9 radius 2.5 on_accent · spinner while opening",
			"track 32, fully rounded, light glass · padding 12 gap 10 · bars 3 at a 6 pitch, min 3, radius 1.5 · leftmost 28 fade",
			"clock mono 11 · muted live, warning in the last 10 s of 60",
		},
		render = function()
			return dictation.row { state = par_dict, clock = "0:07" }
		end,
	},
	{
		id = "context_usage",
		title = "Context usage",
		source = "ui/src/context_usage.rs",
		spec = {
			"chip 24 · px 6 · gap 5 · radius 6 · text 11 · ink 5% hovered or open",
			"ring 16 · stroke 1.8 · track faint 25% · arc clockwise from 12",
			"muted · warning ≥ 75% · danger ≥ 90% · unknown: faint and —",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.16",
				items = "start",
				kit.context_usage.chip { used = par_usage },
				kit.context_usage.card { used = 0.81, total = 200000 },
			}
		end,
	},
	{
		id = "todo",
		title = "Todo tray",
		source = "ui/src/todo_panel.rs",
		spec = {
			"surface: top corners 16 · hairline · frost 16 · inset 4, bottom +18 under the composer",
			"header 32 · px 8 · radius 11 · gap 8 · icon 14 · 'Todo' 12.5 medium · count faint",
			"rows min 26 · px 8 py 4 · glyph 14×17 · text 12.5/17 · done faint + check success · active medium + spinner or ring 10 with a 4 dot",
		},
		render = function()
			return tray.todo {
				items = {
					{ id = "a", text = "Read the failing test", state = "done" },
					{ id = "b", text = "Fix the recentre on blur", state = "active" },
					{ id = "c", text = "Run the suite", state = "pending" },
				},
				live = true,
				open = par_todo,
				w = 360,
			}
		end,
	},
	{
		id = "queue",
		title = "Queue tray",
		source = "ui/src/queue.rs",
		spec = {
			"row 32 · gap 4 · px 4 · radius 11 (16 − 1 − 4) · hover ink 4%",
			"handle 14×22 radius 4 icon 13 muted 50% · text 12.5 at 90% · overflow chip 24 radius 7 ink 6%",
			"actions 24 radius 7 at 0.72 → 1 on ink 7% · primary 72×24 text 11.5 · rows slide 150 ms ease-out",
		},
		render = function()
			return tray.queue { items = par_queue, w = 420 }
		end,
	},
	{
		id = "tree",
		title = "Files tree row",
		source = "ui/src/files/tree.rs",
		spec = {
			"row 27 · pl 8 + 14 per level · pr 8 · gap 4 · guides 1 at 15 + 14·level",
			"chevron 11 in a 14 slot · icon 14 · name 11.5 · selected wash 12% (8% unfocused) · hover 5.5%",
			"git: added success · modified warning · renamed accent · deleted danger · ignored at 0.52",
		},
		render = function()
			return specimen.frame {
				w = 240,
				p = 0,
				bg = T.glass,
				overflow = "hidden",
				file_tree.tree {
					selected = par_tree,
					entries = {
						{ id = "a", name = "kit", level = 0, folder = true, open = true },
						{ id = "b", name = "row.luau", level = 1, icon = "file-code" :: any },
						{
							id = "c",
							name = "glass.luau",
							level = 1,
							icon = "file-code" :: any,
							git = "modified" :: any,
						},
						{ id = "d", name = "old.luau", level = 1, icon = "file-code" :: any, git = "deleted" :: any },
					},
				},
			}
		end,
	},
	{
		id = "pr",
		title = "Pull request row",
		source = "ui/src/pull_requests.rs",
		spec = {
			"group card wash 4.5% radius 12 · row ≥ 64 · px 16 py 12 · gap 16 · divider border 60%",
			"title 13 after a 14 glyph (draft muted · conflicting danger · changes warning · else success)",
			"meta 11 indented 22: avatar 16, login ≤ 150, badges 16 radius 4 at 8%, checks, status · side 112 · star 28",
		},
		render = function()
			return ui.column {
				w = 560,
				rounded = T.radius_card,
				bg = T.card,
				overflow = "hidden",
				pr.row {
					row = {
						id = "x",
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
				},
			}
		end,
	},
	{
		id = "history",
		title = "History row",
		source = "ui/src/history.rs",
		spec = {
			"row 36 · hover ink 2.5% · lanes 12 · node r3 · HEAD ring +2 · stroke 1.5",
			"subject 12 · ref badges 16, max 112, px 5, lane colour at 7%, text 10 at 0.9",
			"author 20 circle, initials 9 · date 10.5 muted · sha mono 10.5 on a 24 hit area, accent when active",
		},
		render = function()
			return specimen.frame {
				w = 560,
				p = 0,
				bg = T.card,
				overflow = "hidden",
				history.table {
					selected = par_commit,
					commits = {
						{
							sha = "bd62d21a",
							subject = "⌘K jumps to a page",
							author = "Gaël Cado",
							date = "2m ago",
							lane = 0,
							parents = { 0, 1 },
							refs = { "main" },
							head = true,
						},
						{
							sha = "a1c2e3f4",
							subject = "glass: the hover layer",
							author = "Wing",
							date = "3h ago",
							lane = 1,
							parents = { 0 },
						},
						{
							sha = "51f122b0",
							subject = "the transcript from the kit",
							author = "Gaël Cado",
							date = "7h ago",
							lane = 0,
							parents = {},
						},
					},
				},
			}
		end,
	},
	{
		id = "attachments",
		title = "Attachments",
		source = "ui/src/composer.rs, composer/chip.rs, transcript.rs",
		spec = {
			"composer tile 56 radius 8, hairline 10%, image 54 at 7 · remove 18 at −6/−6 on hover",
			"chip radius 5 on ink 9% · icon well inset 1, radius 4 · icon 14",
			"transcript thumb 112×80 radius 8 · loaded hairline 11% on ink 3.5% · loading ink 5.5% pulsing · error dashed 14%",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.16",
				items = "center",
				kit.attachments.tile { name = "screen.png", image = ui.raw("#3b4a6b", "a stand-in image") },
				kit.attachments.chip { label = "row.luau", icon = "file-code" },
				kit.attachments.thumb { image = ui.raw("#3b4a6b", "a stand-in image") },
			}
		end,
	},
	{
		id = "floating_tabs",
		title = "Floating tab nav",
		source = "ui/src/pull_request_detail.rs",
		spec = {
			"pill 46 · radius 23 (18 + 2 + 2 + 1) · padding 2 · composer border and fill · frost 16",
			"segment 36 · px 14 · gap 6 · 12 medium / 16 · icon 14 · count 11 muted",
			"thumb glass_hover + card_selected shadows · slides 260 ms (.2 0 0 1), retargets mid-flight · ←→ Home End",
		},
		render = function()
			return kit.floating_tabs {
				id = "parity_ftabs",
				value = par_ftab,
				tabs = {
					{ id = "summary", label = "Summary", icon = "document" },
					{ id = "code", label = "Code", icon = "file-code", count = 12 },
					{ id = "activity", label = "Activity", icon = "chat-round-line", count = 3 },
				},
			}
		end,
	},
	{
		id = "status_chip",
		title = "PR status chip and badge",
		source = "ui/src/pull_request_detail.rs, change_requests.rs",
		spec = {
			"chip: px 8 py 3 · radius 6 · gap 6 · text 12 · icon 14 in the tone · tone at 8% behind",
			"tones: open/approved/passed success · merged code_text · closed/failure danger · changes/awaiting/pending warning · draft muted",
			"badge: sidebar 16 px 4 radius 4 text 10 · composer 20 px 7 radius 6 text 11 · tone 8% → 16% hovered · number mono",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.10",
				items = "center",
				flex_wrap = true,
				pr.status_chip { tone = "open" },
				pr.status_chip { tone = "changes" },
				pr.status_chip { tone = "draft" },
				pr.badge { tone = "open", number = 412 },
				pr.badge { tone = "merged", number = 398, size = "md" },
			}
		end,
	},
	{
		id = "browser_tab",
		title = "Browser tab chip and address",
		source = "ui/src/shell.rs:11738–12150, browser/view.rs",
		spec = {
			"chip 112 × 24 · 4 apart · reorder slides 150 ms ease-out · lead slot 18 (favicon 12 / spinner / icon 12 at 0.7 inactive)",
			"title 11.5 · close slot 18 radius 4, wash 12% hovered · 6 dot ↔ 12 × by opacity",
			"address 24 · radius 6 · ink 3.5% · px 8 gap 6 · globe 12 faint · Go 18 radius 4 when edited · invalid: 1 danger border",
		},
		render = function()
			local q = ui.state("parity_addr", "localhost:3000")
			return ui.column {
				gap = "$zeron.space.10",
				items = "start",
				ui.row {
					gap = "$zeron.space.4",
					browser_kit.tab { title = "Preview", letter = "P", tint = T.info, selected = true },
					browser_kit.tab { title = "Hacker News", letter = "Y", tint = T.claude, dot = true },
				},
				browser_kit.address { value = q, w = 240, editing = true },
			}
		end,
	},
	{
		id = "actions_pill",
		title = "Project actions pill",
		source = "ui/src/shell/actions_ui.rs",
		spec = {
			"24 high · radius 7 · frost 16 · composer border and fill · shadow-sm off frost",
			"segment px 8 gap 5 · 11.5 medium · icon 13 · hover wash 4% · label hidden under 420 · run label ≤ 150",
			"seam 1×14 text 14% · chevron 22 with an 11 arrow · loading / unavailable / + Add action",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.10",
				kit.actions_pill { label = "Run dev", kind = "play" },
				kit.actions_pill { state = "empty" },
			}
		end,
	},
	{
		id = "shortcut",
		title = "Shortcut key chip",
		source = "ui/src/settings/shortcuts.rs",
		spec = {
			"min 96 × 32 · px 12 · radius 8 · mono 12 centred · wash 6% → 10% hovered · transparent 1 border",
			"recording: 'Press keys…' · accent 16% fill · accent 55% border · Escape cancels",
			"Reset link 11 muted → text · 20 before the chip · only when customised",
		},
		render = function()
			return ui.row {
				gap = "$zeron.space.12",
				kit.shortcut.chip { keys = "Cmd+Shift+K" },
				kit.shortcut.chip { keys = "Cmd+N", recording = par_rec },
			}
		end,
	},
	{
		id = "dialog",
		title = "Dialog",
		source = "ui/src/popover.rs:1022, 1275–1292",
		spec = {
			"360 wide · padding 20 · radius 16 · hairline 10%",
			"title 15 semibold · body 13/19 muted · field radius 8 ink 4% text 14",
			"in 180 ms, 2 px rise · scrim 0.35",
		},
		render = function()
			return kit.dialog {
				open = open,
				inline = true,
				w = 360,
				title = "Allow writing to src/?",
				description = "The agent wants to write three files under src/.",
				actions = {
					kit.button { label = "Deny", variant = "ghost" },
					kit.button { label = "Approve", variant = "primary" },
				},
			}
		end,
	},
}

local function entry(e: Entry): Node
	local spec: { Node } = {}
	for _, line in e.spec do
		table.insert(spec, kit.text.text { line, size = "xs", mono = true, color = T.secondary, wrap = true })
	end
	return ui.row {
		id = "parity_" .. e.id,
		w_full = true,
		gap = "$zeron.space.24",
		items = "start",
		pb = "$zeron.space.24",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		ui.column {
			w = 360,
			shrink = 0,
			gap = "$zeron.space.8",
			kit.text.text { e.title, size = "md", weight = "semibold" },
			kit.text.text { e.source, size = "xs", mono = true, color = T.tertiary },
			ui.column { gap = "$zeron.space.3", mt = "$zeron.space.4", spec },
		},
		ui.column { grow = 1, shrink = 1, min_w = 0, items = "start", e.render() },
	}
end

return function(): Node
	local page = state.page_by("parity")
	local rows: { Node } = {}
	for _, e in ENTRIES do
		table.insert(rows, entry(e))
	end
	return ui.column {
		gap = "$zeron.space.24",
		w_full = true,
		specimen.header(page.title, page.blurb),
		rows,
	}
end
