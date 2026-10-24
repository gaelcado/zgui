-- Patterns: what Zeron's components are made of. Edge fades, frost, the
-- the hover wash, surface chrome, loaders, the running pill.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")

local chrome_tab = ui.state("chrome_tab", "files")
local chrome_query = ui.state("chrome_query", "")
local busy = ui.state("busy", 3)
local glass_sel = ui.state("glass_sel", 2)

local function lines(n: number): { Node }
	local out: { Node } = {}
	for i = 1, n do
		table.insert(
			out,
			kit.row {
				label = `Thread {i}`,
				description = if i % 3 == 0 then "Needs you" else "Working · 2m",
				dot = if i % 3 == 0 then T.warning else T.accent,
				size = "sm",
			}
		)
	end
	return out
end

local function fades(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "list, band 24, only where content runs past",
			specimen.frame {
				w = 260,
				h = 240,
				p = 0,
				bg = T.glass,
				kit.scroll {
					h_full = true,
					w_full = true,
					p = "$zeron.space.6",
					gap = "$zeron.space.1",
					fade = 24,
					lines(14),
				},
			},
		},
		specimen.cell {
			label = "menu, band 12",
			specimen.frame {
				w = 240,
				h = 200,
				p = 0,
				bg = T.frost,
				kit.scroll {
					h_full = true,
					w_full = true,
					p = "$zeron.space.4",
					gap = "$zeron.space.1",
					fade = 12,
					lines(10),
				},
			},
		},
		specimen.cell {
			label = "a label fading at its end, band 20",
			ui.scroll_x {
				w = 180,
				h = 20,
				fade_x = { 0, 20 },
				fade_overflow = true,
				kit.text.text { "Refactor the layout engine for the transcript", size = "md", shrink = 0 },
			},
		},
	}
end

local function frost(): Node
	local backdrop = ui.overlay {
		w = 420,
		h = 220,
		rounded = T.radius_card,
		overflow = "hidden",
		items = "center",
		justify = "center",
		ui.div {
			w_full = true,
			h_full = true, -- (`gradient` stops take literal colours, not tokens.)
			gradient = {
				angle = 135,
				stops = {
					ui.theme.get("zeron.loader.1"),
					ui.theme.get("zeron.loader.2"),
					ui.theme.get("zeron.loader.3"),
				},
			},
		},
		ui.row {
			gap = "$zeron.space.24",
			items = "center",
			kit.frost.card {
				w = 200,
				kit.menu_item({ label = "Rename", icon = "pen", keys = { "⌘", "R" } }, function() end),
				kit.menu_item({ label = "Duplicate", icon = "copy" }, function() end),
				kit.menu_item({ label = "Delete…", icon = "trash-bin-minimalistic", danger = true }, function() end),
			},
			ui.column {
				gap = "$zeron.space.10",
				kit.tooltip {
					label = "Search",
					keys = { "⌘", "F" },
					preview = true,
					kit.icon_button { icon = "magnifer", variant = "secondary" },
				},
			},
		},
	}
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell { label = "blur 16 under the overlay surface at 75%, hairline, radius 12, rows at 7", backdrop },
	}
end

local function blend(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "the wash: the engine's hover style, a token over the rest fill (Zeron eases it over 150 ms; zgui switches it)",
			specimen.frame {
				w = 260,
				p = "$zeron.space.6",
				gap = "$zeron.space.1",
				items = "stretch",
				bg = T.glass,
				lines(3),
			},
		},
		specimen.cell {
			label = "the same in a menu: text 90% → 100%, radius 7",
			kit.frost.card {
				w = 220,
				kit.menu_item({ label = "Open in terminal", icon = "terminal", detail = "zsh" }, function() end),
				kit.menu_item({ label = "Share link", icon = "arrow-up-right" }, function() end),
			},
		},
	}
end

local function chrome(): Node
	return specimen.cell {
		label = "toolbar 38, controls 24, tabs 24, field 24, icons 14",
		specimen.frame {
			w = 560,
			p = 0,
			items = "stretch",
			kit.chrome.toolbar {
				kit.chrome.tab {
					label = "Files",
					icon = "folder",
					selected = function()
						return chrome_tab:get() == "files"
					end,
					on_click = ui.set(chrome_tab, "files"),
				},
				kit.chrome.tab {
					label = "Changes",
					icon = "git-branch",
					selected = function()
						return chrome_tab:get() == "changes"
					end,
					on_click = ui.set(chrome_tab, "changes"),
				},
				ui.div { grow = 1 },
				kit.chrome.field { value = chrome_query, placeholder = "Filter", icon = "magnifer", w = 160 },
				kit.chrome.control { icon = "sort", label = "Sort" },
				kit.chrome.control { icon = "refresh", label = "Refresh" },
				kit.chrome.control { icon = "split-columns", label = "Split", selected = true },
			},
			ui.column {
				h = 80,
				p = "$zeron.space.12",
				kit.text.text { "pane content", size = "sm", color = T.tertiary },
			},
		},
	}
end

local function loaders(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "end",
		specimen.cell { label = "gradient spinner, cell 2.5", kit.loaders.gradient_spinner {} },
		specimen.cell { label = "cell 4", kit.loaders.gradient_spinner { cell = 4 } },
		specimen.cell { label = "mini spinner, cell 2", kit.loaders.mini_spinner {} },
		specimen.cell { label = "in a button", kit.button { label = "Saving", loading = true } },
		specimen.cell { label = "skeleton rows", kit.loaders.skeleton { rows = 3 } },
		specimen.cell { label = "menu skeleton", kit.loaders.skeleton { rows = 4, kind = "menu", w = 180 } },
	}
end

local function glass(): Node
	local rows: { Node } = {}
	for i, name in { "Inbox", "Working tree", "Hacker News", "zgui" } do
		table.insert(
			rows,
			kit.row {
				id = `glass_{i}`,
				label = name,
				icon = if i == 3 then "globe" else "folder",
				glass = true,
				group = "patterns-glass",
				selected = function()
					return glass_sel:get() == i
				end,
				on_click = ui.set(glass_sel, i),
			}
		)
	end
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "active glass slides between rows (320 ms, .22 1 .36 1) · hover glass 140 in, 220 out",
			specimen.frame {
				w = 260,
				p = "$zeron.space.6",
				gap = "$zeron.space.1",
				items = "stretch",
				bg = T.glass,
				rows,
			},
		},
		specimen.cell {
			label = "the two tints",
			ui.row {
				gap = "$zeron.space.12",
				ui.div { w = 72, h = 40, rounded = "$zeron.radius.8", bg = T.glass_active },
				ui.div {
					w = 72,
					h = 40,
					rounded = "$zeron.radius.8",
					bg = T.glass_hover,
					border = 1,
					border_color = T.glass_hover,
				},
			},
		},
	}
end

local function pill(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "center",
		specimen.cell { label = "1", kit.pill { count = 1 } },
		specimen.cell { label = "12", kit.pill { count = 12 } },
		specimen.cell { label = "caps at 99+", kit.pill { count = 120 } },
		specimen.cell {
			label = "in a row",
			specimen.frame {
				w = 240,
				p = "$zeron.space.6",
				bg = T.glass,
				kit.row { label = "zgui", icon = "folder", trailing = kit.pill { count = busy } },
			},
		},
		kit.button { label = "+1", size = "sm", on_click = ui.add(busy) },
	}
end

return function(): Node
	local page = state.page_by("patterns")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Edge fade",
			note = "Content fades toward a clipping edge, only as far as it runs past it.",
			fades(),
		},
		specimen.section { title = "Frost", frost() },
		specimen.section { title = "Glass", note = "Wing's tint over the window's blur, in place of a wash.", glass() },
		specimen.section { title = "Hover wash", blend() },
		specimen.section { title = "Surface chrome", chrome() },
		specimen.section { title = "Loaders", loaders() },
		specimen.section { title = "Running pill", pill() },
	}
end
