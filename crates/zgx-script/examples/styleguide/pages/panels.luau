-- Panels: the pieces of a multiplexer window, from Wing's zterm and the
-- lab's pickers: a glass tab strip, the agents sidebar, a command palette,
-- an empty pane, key hints.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local wash = require("@kit/wash")
local specimen = require("@shell/specimen")
local agent_row = require("@kit/agent_row")
local palette = require("@kit/palette")
local browser_kit = require("@kit/browser")
local look = require("@kit/look")
local columns = require("./panels_columns")
local dia = require("./panels_dia")

local tab = ui.state("panel_tab", "t2")
local address = ui.state("panel_address", "localhost:3000/preview")
local ftab = ui.state("panel_ftab", "summary")
local btab = ui.state("panel_btab", "b1")

local SERVICES: { browser_kit.Service } = {
	{ id = "docs", name = "vite · zgx-docs", port = 5173, url = "http://localhost:5173/" },
	{ id = "site", name = "next · zeron.sh", port = 3000, url = "http://localhost:3000/" },
}
local terms = ui.state("panel_terms", { "pt1", "pt2" })
local term_tab = ui.state("panel_term_tab", "pt1")
local TERM_TITLES = { pt1 = "~/zeron/zgx", pt2 = "cargo test" }

local function browser(): Node
	local function chip(id: string, title: string, extra: { [string]: any }): Node
		local props: browser_kit.TabProps = {
			group = "browser_tabs",
			id = `btab_{id}`,
			title = title,
			selected = function()
				return btab:get() == id
			end,
			on_click = ui.set(btab, id),
		}
		for k, v in extra do
			(props :: any)[k] = v
		end
		return kit.browser.tab(props)
	end
	return ui.column {
		gap = "$zeron.space.24",
		items = "start",
		specimen.cell {
			label = "toolbar 38 · controls 24 · address 24 on ink 3.5%, globe 12, text 11.5",
			specimen.frame {
				w = 560,
				p = 0,
				bg = T.glass,
				overflow = "hidden",
				kit.browser.toolbar { id = "browser_bar", value = address, can_back = true, can_forward = false },
			},
		},
		specimen.cell {
			label = "tab chips 112 × 24 · favicon slot 18 · dot swaps for × under the pointer",
			wash.list {
				group = "browser_tabs",
				direction = "row",
				gap = "$zeron.space.4",
				color = T.ink3,
				chip("b1", "Preview", { letter = "P", tint = T.info }),
				chip("b2", "Hacker News", { letter = "Y", tint = T.claude, dot = true }),
				chip("b3", "Loading…", { loading = true }),
				chip("b4", "Docs", {}),
			},
		},
		ui.row {
			gap = "$zeron.space.32",
			items = "start",
			flex_wrap = true,
			specimen.cell {
				label = "empty · tile 44 · title 14 · body 12/19",
				specimen.frame {
					w = 360,
					h = 260,
					items = "center",
					bg = T.glass,
					kit.browser.empty {
						title = "Preview your work",
						body = "Start a dev server and its address shows up here, or enter one.",
						action = "Enter an address",
						hint = "Ctrl L",
					},
				},
			},
			specimen.cell {
				label = "a new tab's dev servers · rows 56 · radius 10 · title 13, sub 11 · Open 28",
				specimen.frame {
					w = 320,
					h = 300,
					p = 0,
					bg = T.glass,
					kit.browser.previews { id = "panel_previews", services = SERVICES },
				},
			},
			specimen.cell {
				label = "invalid address",
				specimen.frame {
					w = 360,
					p = 0,
					bg = T.glass,
					overflow = "hidden",
					kit.browser.toolbar { value = address, invalid = true },
				},
			},
		},
		specimen.cell {
			label = "terminal bar 40 · tabs 118 × 28 at radius 8, glyph 16, text 12 · close 20 on the chosen · + and hide 28",
			specimen.frame {
				w = 560,
				p = 0,
				bg = T.sunken,
				overflow = "hidden",
				kit.terminal.bar {
					id = "panel_term_bar",
					ui.tabs {
						label = "Terminals",
						items = terms,
						value = term_tab,
						gap = "$zeron.space.4",
						reorderable = true,
						tab = function(id: string): Node
							return kit.terminal.chip {
								id = `panel_term_{id}`,
								title = TERM_TITLES[id] or id,
								exited = id == "pt2",
								selected = function()
									return term_tab:get() == id
								end,
							}
						end,
					},
				},
			},
		},
	}
end

local function pills(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "project actions · 24 at radius 7 · seam 1×14 · chevron 22",
			ui.row {
				gap = "$zeron.space.12",
				kit.actions_pill { id = "actions", label = "Run dev", kind = "play" },
				kit.actions_pill { label = "Test", kind = "test", compact = true },
				kit.actions_pill { state = "loading" },
				kit.actions_pill { state = "unavailable" },
				kit.actions_pill { state = "empty" },
			},
		},
		specimen.cell {
			label = "floating tabs · 46 at radius 23 · segments 36 · thumb slides 260 ms ease-out-soft",
			kit.floating_tabs {
				id = "ftabs",
				value = ftab,
				tabs = {
					{ id = "summary", label = "Summary", icon = "document" },
					{ id = "code", label = "Code", icon = "file-code", count = 12 },
					{ id = "activity", label = "Activity", icon = "chat-round-line", count = 3 },
				},
			},
		},
	}
end
local agent = ui.state("panel_agent", "a1")
local scope = ui.state("panel_scope", "All")
local choice = ui.state("panel_choice", "terminal")

local AGENTS: { agent_row.Agent } = {
	{
		id = "a1",
		name = "300-word story",
		where = "zgx",
		status = "working",
		icon = "claude-mark",
		tint = T.claude,
		ago = "5m",
	},
	{
		id = "a2",
		name = "",
		where = "~/zeron/zgx",
		status = "blocked",
		waits = "question",
		icon = "openai-mark",
		ago = "now",
	},
	{ id = "a3", name = "Codex", where = "zgx", status = "idle", icon = "terminal", ago = "1h" },
	{
		id = "a4",
		name = "Fix flaky test",
		where = "comet",
		status = "done",
		icon = "claude-mark",
		tint = T.claude,
		ago = "2h",
	},
	{ id = "a5", name = "Deploy preview", where = "grid-website", status = "error", icon = "cursor-mark", ago = "3h" },
}

local function strip(): Node
	return specimen.cell {
		label = "28 high · radius 8 · the active glass slides · a bell on a background tab",
		specimen.frame {
			w = 620,
			p = "$zeron.space.6",
			bg = T.glass,
			kit.tabstrip {
				id = "panel_tabs",
				value = tab,
				tabs = {
					{ id = "t1", label = "Editor", icon = "document" },
					{ id = "t2", label = "Plugins", icon = "widget" },
					{ id = "t3", label = "zgx", icon = "terminal", bell = true },
					{ id = "t4", label = "Hacker News", icon = "globe", closable = true },
				},
				on_add = function() end,
			},
		},
	}
end

local function agents(): Node
	local rows: { Node } = {}
	for _, a in AGENTS do
		local snapshot = a
		table.insert(
			rows,
			agent_row.row {
				id = "panel_" .. a.id,
				agent = function()
					return snapshot
				end,
				selected = function()
					return agent:get() == snapshot.id
				end,
				group = "panel-agents",
				on_click = ui.set(agent, a.id),
			}
		)
	end
	return specimen.cell {
		label = "glyph 16 · name 13 medium · ago 11 · a mark and the status · hover and active glass",
		specimen.frame {
			w = 272,
			p = 0,
			bg = T.glass,
			items = "stretch",
			ui.row {
				px = "$zeron.space.16",
				pt = "$zeron.space.10",
				pb = "$zeron.space.6",
				gap = "$zeron.space.6",
				items = "center",
				kit.text.text { "Agents", size = "sm", weight = "semibold", color = T.secondary },
				kit.text.text { tostring(#AGENTS), size = "sm", color = T.tertiary },
			},
			kit.scroll {
				h = 300,
				w_full = true,
				px = "$zeron.space.8",
				py = "$zeron.space.8",
				fade = 18,
				kit.list { group = "panel-agents", gap = "$zeron.space.1", color = T.glass_hover, rows },
			},
		},
	}
end

local function command_palette(): Node
	return specimen.cell {
		label = "search header · groups · title and description · key hints",
		palette {
			id = "panel_palette",
			placeholder = "Open a terminal, a browser or a panel…",
			query = "",
			count = nil,
			selected = choice,
			results = {
				{
					id = "terminal",
					title = "Terminal",
					description = "A shell where the focused one is",
					group = "Open",
					icon = "terminal",
					keys = { "↩" },
				},
				{
					id = "browser",
					title = "Browser",
					description = "A web page",
					group = "Open",
					icon = "globe",
					keys = { "⌘", "B" },
				},
				{ id = "editor", title = "Editor", description = "Edit a file", group = "Panels", icon = "document" },
				{
					id = "hn",
					title = "Hacker News",
					description = "Stories, discussions and articles",
					group = "Panels",
					icon = "globe",
				},
				{
					id = "notes",
					title = "Notes",
					description = "A notepad for this pane",
					group = "Panels",
					icon = "pen-new-square",
				},
				{
					id = "plugins",
					title = "Plugins",
					description = "What is installed, and what each may do",
					group = "Manage",
					icon = "widget",
				},
			},
			hints = {
				{ keys = { "↩" }, label = "Choose" },
				{ keys = { "⌘", "↩" }, label = "Open beside" },
				{ keys = { "⇧", "↩" }, label = "New tab" },
			},
		},
	}
end

local function reference_picker(): Node
	return specimen.cell {
		label = "the @ picker: the query, scopes, matches in bold, a footer of hints",
		palette {
			id = "panel_refs",
			icon = "command",
			placeholder = "Search tabs, files, history…",
			query = "ope",
			count = "7 results",
			scopes = { "All", "Tabs", "Clipboard", "History", "Files", "Bookmarks" },
			scope = scope,
			results = {
				{
					id = "r1",
					match = "Ope",
					title = "nTable · Le Bernardin",
					description = "opentable.com/r/le-bernardin",
					group = "Open tabs",
					letter = "O",
					tint = T.danger,
					meta = "Tab",
					keys = { "↩" },
				},
				{
					id = "r2",
					match = "Ope",
					title = "n Kitchen — Dinner menu",
					description = "openkitchen.co/menu",
					group = "Open tabs",
					letter = "K",
					meta = "Tab",
				},
				{
					id = "r3",
					match = "Ope",
					title = "ning hours.pdf",
					description = "Downloads · 240 KB",
					group = "Files & bookmarks",
					icon = "document",
					meta = "PDF",
				},
				{
					id = "r4",
					match = "Ope",
					title = "n data · NYC restaurant grades",
					description = "data.cityofnewyork.us",
					group = "Files & bookmarks",
					icon = "tag",
					meta = "Bookmark",
				},
			},
			hints = {
				{ keys = { "↑", "↓" }, label = "Navigate" },
				{ keys = { "↩" }, label = "Insert" },
				{ keys = { "⇥" }, label = "Scope" },
				{ keys = { "⌘", "↩" }, label = "Snapshot" },
			},
		},
	}
end

local function empty(): Node
	return specimen.cell {
		label = "an empty pane",
		specimen.frame {
			w = 420,
			h = 260,
			items = "center",
			bg = T.glass,
			ui.column {
				grow = 1,
				justify = "center",
				kit.empty {
					icon = "document",
					title = "Edit a file",
					description = "Open one, or start a new one and save it where you like.",
					actions = {
						{ label = "Open File…", icon = "folder", keys = { "⌘", "O" } },
						{ label = "New File", icon = "document-add" },
					},
					hint = "Last here: /Users/wing/Documents/GitHub/zgx/apps/copy/src/",
				},
			},
		},
	}
end

-- The surfaces as the look maps them, in its surface mode (here or in the
-- titlebar) and with the double border on or off.
local function surfaces(): Node
	local function body(title: string, sub: string): Node
		return ui.column {
			p = "$zeron.space.12",
			gap = "$zeron.space.4",
			kit.text.text { title, size = "md", weight = "medium", line = false },
			kit.text.text { sub, size = "xs", color = T.secondary, wrap = true },
		}
	end
	local function on_glass(label: string, child: Node): Node
		return specimen.cell {
			label = label,
			specimen.frame { w = 240, h = 150, p = "$zeron.space.12", bg = T.glass, items = "stretch", child },
		}
	end
	return ui.column {
		gap = "$zeron.space.20",
		items = "start",
		ui.row {
			gap = "$zeron.space.16",
			items = "center",
			kit.segmented {
				id = "surfaces_mode",
				size = "sm",
				value = state.look.surface :: any,
				options = look.SURFACES,
			},
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				kit.toggle { id = "surfaces_rim", value = state.look.rim },
				kit.text.text { "Double border", size = "sm", color = T.secondary, line = false },
			},
		},
		ui.row {
			gap = "$zeron.space.24",
			items = "start",
			flex_wrap = true,
			on_glass(
				"well · edge outside, lit rim inside",
				kit.well.well { id = "surfaces_well", body("A well", "Inset into the window's glass") }
			),
			on_glass(
				"well out of focus · the rim dims",
				kit.well.well { focused = false, body("Another well", "Beside the focused one") }
			),
			on_glass(
				"rim recipe · on a card",
				ui.column {
					id = "surfaces_card",
					h_full = true,
					rounded = T.radius_card,
					bg = T.pane,
					variants = kit.recipes.rim {},
					body("A pane", "recipes.rim: any surface with a hairline"),
				}
			),
			specimen.cell {
				label = "flush panel · its inner line beside the seam",
				ui.row {
					w = 240,
					h = 150,
					rounded = T.radius_card,
					bg = T.glass,
					border = 1,
					border_color = T.hairline,
					overflow = "hidden",
					items = "stretch",
					ui.div { w = 72, bg = T.sidebar_tone },
					ui.div { w = 1, bg = T.border },
					ui.column {
						grow = 1,
						variants = kit.recipes.panel_fill {},
						body("A panel", "The background at 40%, solid when opaque"),
					},
				},
			},
			on_glass(
				"frost · floating card",
				kit.frost.card { w_full = true, body("Frost", "Faint over a blur; solid with a shadow when opaque") }
			),
		},
	}
end

return function(): Node
	local p = state.page_by("panels")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "Columns",
			note = "Zeron's panel policy: the sidebar (256) and Files (286) keep their widths · the conversation and the pane split the rest equally (chat 300, pane 360 at least) · a dragged divider holds until the next toggle, a double-click on a seam resets · too narrow: the least recently opened column leaves; asking for it brings it back · columns ease on the dialog curve, 180 to 240 ms, content masked not reflowed · expand covers the conversation, which keeps its layout · drag the frame's right edge to narrow the window",
			columns.view(),
		},
		specimen.section {
			title = "Surfaces",
			note = "Each surface as old Zeron maps it: the window's glass (the shell at 80%, solid when opaque), panels (the background at 40%), wells, and floating frost (a faint tint over a blur with no shadow, or the overlay with the large shadow when opaque) · the theme's own surface is frosted for Zeron's themes and opaque for the rest · the double border: a hairline outside, a lit rim inside, top-weighted (theme `zeron.rim.*`, tuned per kind and surface in kit/look)",
			id = "surfaces",
			surfaces(),
		},
		specimen.section { title = "Tab strip", strip() },
		specimen.section { title = "Title-bar tabs (zimmer)", dia.bar() },
		specimen.section { title = "Agents", agents() },
		specimen.section {
			title = "Palette",
			ui.row { gap = "$zeron.space.32", items = "start", flex_wrap = true, command_palette(), reference_picker() },
		},
		specimen.section { title = "Empty state", empty() },
		specimen.section { title = "Browser", browser() },
		specimen.section { title = "Pills", pills() },
	}
end
