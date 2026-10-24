-- The pull requests route (PR #866, #914): the board is its content
-- column and a pull request opens beside it in the route's own right pane,
-- under the same panel policy as the chat's (equal split, held divider,
-- least recently opened hidden on a narrow window, expand over the board).
local T = require("../theme")
local kit = require("@kit")
local pr = require("@kit/pr")
local diff = require("@kit/diff")
local data = require("./data")
local state = require("./state")
local chrome = require("./chrome")

local M = {}

local open_group = ui.state("prs_open", true)
local done_group = ui.state("prs_done", false)

function M.board(): Node
	local rows: { Node } = {}
	for i, r in data.PRS do
		table.insert(
			rows,
			pr.row {
				id = `pr_{r.id}`,
				row = r,
				first = i == 1,
				group = "zprs_rows",
				selected = function()
					return state.pr:get() == r.id and state.prs.open.right:get()
				end,
				on_click = function()
					state.open_pr(r.id)
				end,
			}
		)
	end
	return ui.column {
		id = "prs_board",
		w_full = true,
		h_full = true,
		pt = chrome.top,
		kit.scroll {
			grow = 1,
			w_full = true,
			fade = 24,
			ui.column {
				w_full = true,
				max_w = 820,
				self = "center",
				px = "$zeron.space.16",
				py = "$zeron.space.16",
				gap = "$zeron.space.16",
				pr.group {
					id = "prs",
					label = "Open",
					count = #data.PRS,
					open = open_group,
					list = "zprs_rows",
					rows,
				},
				pr.group { label = "Merged", count = 3, open = done_group },
			},
		},
	}
end

local TONE: { [pr.Status]: pr.Tone } =
	{ open = "open", draft = "draft", conflicting = "failed", changes = "changes", merged = "merged" }

local function current(): pr.Row
	for _, r in data.PRS do
		if r.id == state.pr:peek() then
			return r
		end
	end
	return data.PRS[1]
end

local detail_files = ui.state("pr_files_open", true)

-- The pull request beside the board: its title, state, summary and diff.
function M.detail(): Node
	return ui.presence(state.pr, function(): Node
		local r = current()
		return kit.scroll {
			grow = 1,
			w_full = true,
			h_full = true,
			fade = 24,
			ui.column {
				id = "pr_detail",
				w_full = true,
				px = "$zeron.space.20",
				py = "$zeron.space.16",
				gap = "$zeron.space.12",
				ui.row {
					gap = "$zeron.space.8",
					items = "center",
					pr.badge { tone = TONE[r.status], number = r.number },
					pr.status_chip { tone = TONE[r.status] },
				},
				kit.text.text { r.title, size = "xl", weight = "semibold" },
				kit.text.text {
					`{r.author} · {r.date} · +{r.added} −{r.removed}`,
					size = "sm",
					color = T.tertiary,
				},
				kit.text.text {
					"The board and the pane split what the sidebar leaves equally; a dragged divider holds until the next toggle.",
					size = "md",
					color = T.secondary,
				},
				ui.column {
					w_full = true,
					rounded = T.radius_card,
					bg = T.card,
					overflow = "hidden",
					diff.change {
						file = {
							id = "pr_change",
							path = "crates/ui/src/shell/panel_layout.rs",
							icon = "file-code",
							added = r.added,
							removed = r.removed,
							open = detail_files,
						},
						hunks = { data.HUNK },
					},
				},
			},
		}
	end, { w_full = true, h_full = true })
end

-- The pane's header strip: the open pull request as a tab.
function M.tab(): Node
	return ui.presence(state.pr, function(): Node
		return kit.browser.tab {
			id = "zprs_tab",
			title = `#{current().number}`,
			icon = "pull-request",
			selected = true,
			on_close = function()
				state.close_active()
			end,
		}
	end)
end

return M
