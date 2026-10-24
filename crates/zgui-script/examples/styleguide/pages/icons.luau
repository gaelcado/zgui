-- Icons: Zeron's set (Solar Linear and Zeron Icons, with the harness
-- marks) by the groups icons.rs keeps them in, the sizes each role uses,
-- the ones that move, and where the most-used ones appear.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local wash = require("@kit/wash")
local specimen = require("@shell/specimen")
local icon_mod = require("@kit/icon")
local NAMES = require("@kit/icon_names")
local agent_row = require("@kit/agent_row")

local query = ui.state("icons_query", "")
local morph_open = ui.state("icons_morph", true)
local chevron_open = ui.state("icons_chevron", false)
local mic = ui.state("icons_mic", "idle" :: any)

type Group = { title: string, note: string?, names: { icon_mod.Name } }
local GROUPS: { Group } = {
	{
		title = "Navigation and chrome",
		note = "arrows, disclosure, window",
		names = {
			"alt-arrow-down",
			"alt-arrow-up",
			"alt-arrow-left",
			"alt-arrow-right",
			"arrow-up",
			"arrow-down",
			"arrow-left",
			"arrow-right",
			"arrow-up-right",
			"return",
			"expand-arrows",
			"collapse-arrows",
			"fold-vertical",
			"split-columns",
			"wrap-text",
			"sort",
			"sort-vertical",
			"more-horizontal",
			"drag-handle",
			"close",
			"close-circle",
			"window-minimize",
			"window-maximize",
			"window-restore",
			"home",
			"terminal",
			"stop",
			"check",
			"copy",
		},
	},
	{
		title = "Git and projects",
		note = "Zeron Icons, 1.75 strokes",
		names = {
			"folder",
			"folder-with-files",
			"fork",
			"git-branch",
			"pull-request",
			"pull-request-draft",
			"worktree",
			"project-default",
			"plus",
			"cloud",
			"tag",
			"key-minimalistic",
			"keyboard",
			"remote-server",
			"hard-drive",
			"laptop",
			"monitor",
			"smartphone",
		},
	},
	{
		title = "Documents and files",
		names = {
			"document",
			"document-add",
			"file-code",
			"file-style",
			"file-data",
			"file-markdown",
			"file-image",
			"file-tree",
			"gallery",
			"list",
			"floppy-disk",
			"paperclip",
			"archive-minimalistic",
			"archive-up-minimalistic",
		},
	},
	{
		title = "Actions",
		names = {
			"refresh",
			"restart",
			"add-circle",
			"tuning",
			"eye",
			"eye-closed",
			"pin",
			"pen",
			"pen-new-square",
			"trash-bin-minimalistic",
			"settings",
			"settings-minimalistic",
			"logout-2",
			"magnifer",
			"palette-search",
			"command",
			"calendar",
			"clock-circle",
			"star",
			"star-bold",
			"fast-tier",
			"fast-tier-bold",
		},
	},
	{
		title = "Project actions",
		note = "the titlebar pill",
		names = { "action-play", "action-test", "action-lint", "action-configure", "action-build", "action-debug" },
	},
	{
		title = "Status and agents",
		names = {
			"global",
			"globe",
			"checklist",
			"widget",
			"magic-stick-3",
			"wifi-off",
			"info-circle",
			"danger-triangle",
			"chat-round-line",
			"bot",
		},
	},
	{ title = "Voice", names = { "bell", "volume-loud", "microphone", "microphone-off", "phone-hang-up" } },
	{
		title = "Queue",
		note = "the queue tray's own family",
		names = { "queue-drag-handle", "queue-send", "queue-check", "queue-close", "queue-paperclip" },
	},
	{ title = "Appearance", names = { "sun", "moon" } },
	{
		title = "Harness marks",
		note = "the Claude mark is tinted #d97757",
		names = {
			"claude-mark",
			"openai-mark",
			"cursor-mark",
			"devin-mark",
			"grok-mark",
			"hermes-mark",
			"pi-mark",
			"opencode-mark",
			"antigravity-mark",
			"zeron-logo",
		},
	},
}

local SIZES = {
	{ size = 18, role = "composer mic and paperclip" },
	{ size = 16, role = "shell glyphs, transcript activity, sidebar rows, the toggle" },
	{ size = 14, role = "surface chrome on 24 controls, chevrons, chips, the todo glyph, file icons in tabs" },
	{ size = 13, role = "sidebar harness mark, the queue, the tab strip's +" },
	{ size = 12, role = "badges, inline file glyphs, tab chip icons and their ×" },
}

local USAGE = {
	{ name = "alt-arrow-down", count = 23, where = "disclosure everywhere" },
	{ name = "check", count = 22, where = "pickers, menus, todo, toast, copy-done, files, PR detail" },
	{ name = "plus", count = 17, where = "tab strip +, terminal, spaces, pickers, comments, accounts" },
	{ name = "chat-round-line", count = 17, where = "composer, transcript, comments, side chat, voice" },
	{ name = "folder", count = 16, where = "shell, pickers, PRs, palette, spaces, links" },
	{ name = "alt-arrow-right", count = 16, where = "tree and group disclosure" },
	{ name = "danger-triangle", count = 13, where = "notice, toast, transcript, PR detail, settings, voice" },
	{ name = "close", count = 13, where = "tab close, composer, todo, history, pickers, PRs" },
	{ name = "refresh", count = 11, where = "changes, history, PRs, browser, files" },
	{ name = "arrow-up-right", count = 10, where = "opens elsewhere: links, browser, preview" },
}

local function tile(name: icon_mod.Name, size: number, group: string): Node
	return ui.column(wash.item(group, {
		id = `icon_{name}`,
		w = 96,
		h = 72,
		gap = "$zeron.space.8",
		items = "center",
		justify = "center",
		rounded = T.radius_lg,
		hover = { bg = T.ink1 },
		kit.icon { name = name, size = size, color = if name == "claude-mark" then T.claude else T.text },
		kit.text.text { name, size = "micro", mono = true, color = T.tertiary, truncate = true, max_w = 88 },
	}))
end

local function groups(): Node
	return ui.presence(query, function(q: string): Node
		local sections: { Node } = {}
		local lq = string.lower(q)
		for _, g in GROUPS do
			local tiles: { Node } = {}
			local group = `icons_{g.title}`
			for _, name in g.names do
				if lq == "" or string.find(name, lq, 1, true) then
					table.insert(tiles, tile(name, 16, group))
				end
			end
			if #tiles > 0 then
				table.insert(
					sections,
					ui.column {
						w_full = true,
						gap = "$zeron.space.6",
						ui.row {
							gap = "$zeron.space.8",
							items = "baseline",
							kit.text.text { g.title, size = "md", weight = "medium" },
							g.note and kit.text.text { g.note, size = "xs", color = T.tertiary },
						},
						wash.list {
							group = group,
							direction = "row",
							flex_wrap = true,
							w_full = true,
							gap = "$zeron.space.2",
							color = T.ink2,
							tiles,
						},
					}
				)
			end
		end
		return ui.column { w_full = true, gap = "$zeron.space.24", sections }
	end, { w_full = true, enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.FAST) } })
end

local function sizes(): Node
	local rows: { Node } = {}
	for _, s in SIZES do
		table.insert(
			rows,
			ui.row {
				gap = "$zeron.space.16",
				items = "center",
				ui.row { w = 24, justify = "center", kit.icon { name = "folder", size = s.size } },
				kit.text.text { tostring(s.size), size = "sm", mono = true, w = 24 },
				kit.text.text { s.role, size = "sm", color = T.secondary },
			}
		)
	end
	return ui.column { gap = "$zeron.space.8", rows }
end

local function animated(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "gradient spinner · 3×3 · 750 ms wave · sending, working, boot",
			kit.loaders.gradient_spinner {},
		},
		specimen.cell {
			label = "mini glyph spinner · 2×3 · perimeter chase · sidebar rows, tabs, todos",
			kit.loaders.mini_spinner {},
		},
		specimen.cell { label = "pulse · 2.4 s · running pill, skeletons", kit.pill { count = 3 } },
		specimen.cell {
			label = "status mark · arc 900 ms · enter outBack(1.6)",
			agent_row.mark(function()
				return "working" :: any
			end),
		},
		specimen.cell {
			label = "chevron · right, down when open · 180 ms · click",
			ui.button {
				id = "icons_chevron_btn",
				w = 28,
				h = 28,
				p = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_md,
				bg = T.clear,
				hover = { bg = T.ink2 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = ui.toggle(chevron_open),
				kit.disclosure.chevron { open = chevron_open, size = 14, color = T.secondary },
			},
		},
		specimen.cell {
			label = "sidebar glyph · the panel narrows 5.5 → 1.75 · 280 ms quint · click",
			ui.button {
				id = "icons_morph_btn",
				w = 28,
				h = 28,
				p = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_md,
				bg = T.clear,
				hover = { bg = T.ink2 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = ui.toggle(morph_open),
				kit.sidebar_glyph { open = morph_open, size = 16 },
			},
		},
		specimen.cell {
			label = "mic → stop plate · 420 ms ease-out-soft · click",
			kit.dictation.mic {
				id = "icons_mic",
				state = mic,
				on_click = function()
					mic:set(if mic:peek() == "idle" then "listening" else "idle")
				end,
			},
		},
	}
end

local function usage(): Node
	local rows: { Node } = {}
	for _, u in USAGE do
		table.insert(
			rows,
			ui.row {
				w_full = true,
				h = 32,
				gap = "$zeron.space.12",
				items = "center",
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				kit.icon { name = u.name, size = 16 },
				kit.text.text { u.name, size = "sm", mono = true, w = 150, line = false },
				kit.text.text {
					tostring(u.count),
					size = "sm",
					mono = true,
					color = T.tertiary,
					w = 28,
					align = "end",
					line = false,
				},
				kit.text.text { u.where, size = "sm", color = T.secondary, truncate = true, line = false },
			}
		)
	end
	return ui.column { w_full = true, rows }
end

return function(): Node
	local p = state.page_by("icons")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		ui.row {
			gap = "$zeron.space.16",
			items = "center",
			kit.input {
				id = "icons_search",
				value = query,
				placeholder = "Filter icons",
				icon = "magnifer",
				size = "sm",
				w = 240,
			},
			kit.text.text {
				function()
					local q = string.lower(query:get())
					local n = 0
					for _, name in NAMES do
						if q == "" or string.find(name, q, 1, true) then
							n += 1
						end
					end
					return `{n} of {#NAMES}`
				end,
				size = "sm",
				color = T.tertiary,
			},
		},
		specimen.section {
			title = "By group",
			note = "as icons.rs keeps them; Solar Linear at 1.5, Zeron Icons at 1.75",
			groups(),
		},
		specimen.section { title = "Sizes by role", sizes() },
		specimen.section {
			title = "Icons that move",
			note = "loaders.rs and the glyph morphs; all hold still under reduced motion",
			animated(),
		},
		specimen.section { title = "Most used", note = "references in crates/ui, and where", usage() },
	}
end
