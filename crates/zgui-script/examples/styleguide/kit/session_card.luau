-- The session card (Zeron's shell/session_info.rs): where the chat runs
-- (the device, the project, the branch with its working-tree diff, its pull
-- request) and the project's run actions; under it, the lanes card (its
-- side chats and subagents). 272 wide, 12 in from the column's top right,
-- over the transcript.
local T = require("../theme")
local recipes = require("./recipes")
local txt = require("./text")
local glyph = require("./icon")
local loaders = require("./loaders")
local frost = require("./frost")

export type Info = {
	title: string,
	harness: { icon: string, tint: Color? },
	device: string,
	project: string,
	branch: string?,
	pr: { number: number, state: string }?,
}

local M = {}

M.WIDTH = 272
M.INSET = 12

-- A row: the icon in a 16 slot, the label at 13, a detail trailing.
local function row(icon: string, label: string, detail: Node?, tint: Color?): Node
	return ui.row {
		w_full = true,
		min_h = 30,
		px = "$zeron.space.9",
		gap = "$zeron.space.8",
		items = "center",
		ui.row {
			w = 16,
			h = 16,
			shrink = 0,
			items = "center",
			justify = "center",
			glyph { name = icon :: any, size = 15, color = tint or T.secondary },
		},
		txt.text {
			label,
			size = "md",
			line = false,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
			literal = true,
		},
		detail,
	}
end

local function action(id: string, icon: string, label: string): Node
	return ui.button {
		id = id,
		w_full = true,
		h = 30,
		px = "$zeron.space.9",
		py = 0,
		gap = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.8",
		variants = recipes.wash { hover = "ink2" },
		focus = { border = 0 },
		cursor = "pointer",
		ui.row {
			w = 16,
			h = 16,
			shrink = 0,
			items = "center",
			justify = "center",
			glyph { name = icon :: any, size = 15, color = T.secondary },
		},
		txt.text { label, size = "md", line = false, grow = 1 },
	}
end

local function rule(): Node
	return ui.div { variants = recipes.divider, my = "$zeron.space.4" }
end

local function heading(text: string): Node
	return ui.row {
		px = "$zeron.space.9",
		pt = "$zeron.space.4",
		pb = "$zeron.space.2",
		txt.text { text, size = "xs", color = T.tertiary, line = false },
	}
end

-- The card for a session (`info`), its ids under `prefix`.
function M.card(info: Info, prefix: string): Node
	local harness = info.harness
	local branch = info.branch or "main"
	local pr = info.pr
	return ui.column {
		id = `{prefix}_session_card`,
		absolute = true,
		top = M.INSET,
		right = M.INSET,
		w = M.WIDTH,
		gap = "$zeron.space.8",
		on_click = function() end,
		frost.card {
			w_full = true,
			shrink = 0,
			row(harness.icon, info.title, nil, harness.tint),
			rule(),
			row("monitor", info.device),
			row("folder", info.project),
			row(
				"git-branch",
				branch,
				ui.row {
					gap = "$zeron.space.4",
					shrink = 0,
					txt.text { "+12", size = "xs", mono = true, color = T.success, line = false },
					txt.text { "−3", size = "xs", mono = true, color = T.danger, line = false },
				}
			),
			pr and row("pull-request", `#{pr.number} · {pr.state}`) or nil,
			rule(),
			heading("Run"),
			action(`{prefix}_card_dev`, "action-play", "Run dev"),
			action(`{prefix}_card_test`, "action-test", "Test"),
			action(`{prefix}_card_lint`, "action-lint", "Lint"),
		},
		-- No shadow of its own: a later card's shadow would paint over the
		-- card above it; the first card's falls under this one.
		frost.card {
			w_full = true,
			shrink = 0,
			shadow = false,
			heading("Lanes"),
			row("chat-round-line", "Side chat: check the release links"),
			row("bot", "Subagent: run the suite", ui.row { shrink = 0, loaders.mini_spinner { color = T.secondary } }),
		},
	}
end

return M
