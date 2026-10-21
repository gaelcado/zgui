-- What programs in panes said to get the user's attention: their last
-- desktop notification (OSC 9 and 777) or bell, by pane. Agents that do not
-- report their status (OSC 7501) say this way that they need the user or
-- have finished; agents.luau reads it, and a pane taking focus clears it.
local M = {}

export type Note = {
	-- Unix seconds.
	at: number,
	-- "permission" (it asks to do something), else "finished".
	kind: "permission" | "finished",
	text: string,
}

M.notes = ui.state("notes", {} :: { [string]: Note })

-- What a notification asks for, from its words.
local function kind_of(text: string): "permission" | "finished"
	local lower = text:lower()
	for _, word in { "permission", "approv", "allow", "confirm", "needs your" } do
		if lower:find(word, 1, true) then
			return "permission"
		end
	end
	return "finished"
end

function M.note(pane: string, text: string)
	M.notes:set_key(pane, { at = os.time(), kind = kind_of(text), text = text })
end

function M.clear(pane: string)
	if (M.notes:peek())[pane] then
		M.notes:set_key(pane, nil)
	end
end

return M
