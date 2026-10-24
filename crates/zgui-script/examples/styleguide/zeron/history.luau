-- History as a right-pane surface (history.rs): the branch's commits with
-- their graph, a 40-high header holding the search (24×196) and "Fetch
-- all", "No matching commits" when the search finds none, and "Load more"
-- at the end. A click picks a commit. The rows are built once per search,
-- not per key: the table is built again only as the matches change.
local T = require("../theme")
local kit = require("@kit")
local history = require("@kit/history")
local data = require("./data")

local M = {}

-- Commits whose subject, author or SHA hold `query` (any case).
function M.matching(query: string): { history.Commit }
	local q = string.lower(query)
	local out: { history.Commit } = {}
	for _, c in data.COMMITS do
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

function M.view(id: string): Node
	local query = ui.state(`{id}_query`, "")
	local selected = ui.state(`{id}_selected`, "")
	local fetching = ui.state(`{id}_fetching`, false)
	local matches = ui.computed(function(): string
		local shas = {}
		for _, c in M.matching(query:get()) do
			table.insert(shas, c.sha)
		end
		return table.concat(shas, ",")
	end)
	return ui.column {
		id = id,
		w_full = true,
		h_full = true,
		items = "stretch",
		ui.row {
			w_full = true,
			h = 40,
			px = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			shrink = 0,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			history.search { id = `{id}_search`, value = query },
			ui.div { grow = 1 },
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
				on_click = function()
					if fetching:peek() then
						return
					end
					fetching:set(true)
					ui.after(900, function()
						fetching:set(false)
					end)
				end,
				kit.icon { name = "refresh", size = 12, color = T.secondary },
				kit.text.text {
					function()
						return if fetching:get() then "Fetching…" else "Fetch all"
					end,
					size = "xs",
					color = T.secondary,
					line = false,
				},
			},
		},
		ui.presence(matches, function(): Node
			local list = M.matching(query:peek())
			if #list == 0 then
				return ui.column {
					grow = 1,
					w_full = true,
					items = "center",
					justify = "center",
					kit.text.text { "No matching commits", size = "sm", color = T.tertiary, line = false },
				}
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
					history.table { id = `{id}_commits`, commits = list, selected = selected },
					ui.row { px = "$zeron.space.12", history.more { id = `{id}_more` } },
				},
			}
		end, { grow = 1, w_full = true, min_h = 0 }),
	}
end

return M
