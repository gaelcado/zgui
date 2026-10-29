-- The window's state: the sidebar, which item each card shows, the focused
-- card, what was sent, the theme.
local sample = require("@lib/sample")

local M = {}

M.sidebar = ui.state("sidebar", true)
-- The cards side by side: the first always, the second when split.
M.left = ui.state("left", "plan")
M.right = ui.state("right", nil :: string?)
-- Which card a sidebar click opens in: 1 or 2.
M.focus = ui.state("focus", 1)
M.dark = ui.state("dark", true)
-- What each chat's composer holds, and the messages sent there.
M.drafts = {} :: { [string]: State<string> }
M.sent = ui.state("sent", {} :: { [string]: { sample.Message } })

function M.draft(id: string): State<string>
	local d = M.drafts[id]
	if not d then
		d = ui.state(`draft_{id}`, "")
		M.drafts[id] = d
	end
	return d
end

-- The item the focused card shows.
function M.current(): string
	if M.focus:get() == 2 then
		return M.right:get() or M.left:get()
	end
	return M.left:get()
end

function M.open(id: string)
	if M.focus:peek() == 2 and M.right:peek() then
		M.right:set(id)
	else
		M.left:set(id)
	end
end

-- Split: a second card beside the first, on the next item of its space.
function M.split()
	if M.right:peek() then
		M.right:set(nil)
		M.focus:set(1)
		return
	end
	local left = M.left:peek()
	local next_id = "story"
	for _, space in sample.spaces do
		for i, id in space.items do
			if id == left then
				next_id = space.items[i % #space.items + 1]
			end
		end
	end
	M.right:set(next_id)
	M.focus:set(2)
end

function M.send(id: string)
	local d = M.draft(id)
	local text = d:peek()
	if text:match("^%s*$") then
		return
	end
	local all = table.clone(M.sent:peek())
	local list = table.clone(all[id] or {})
	table.insert(list, { from = "me", text = text } :: sample.Message)
	all[id] = list
	M.sent:set(all)
	d:set("")
end

return M
