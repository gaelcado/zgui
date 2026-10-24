-- The chat's drop zone (shell/chat_dropzone.rs): over the conversation, a
-- session dragged from the sidebar says "Drop to mention" and a file
-- "Drop to attach", on a scrim at 40%, the words at 13 in the middle; no
-- icon, no border, no fade. A session lands in the draft as a mention, a
-- file among the attachments (the conversation's, by `state.hooks.
-- drop_into`). Built only while something is over it.
local T = require("../theme")
local kit = require("@kit")
local state = require("./state")

local M = {}

-- What a drag over it would do: "mention", "attach", or nil.
M.over = ui.state("z_drop_over", nil :: string?)

local function what(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.kind == "session" then
		return "mention"
	elseif payload.kind == "file" then
		return "attach"
	end
	return nil
end

-- `content` (the conversation of `session`) under the zone.
function M.wrap(session: string, content: Node): Node
	return ui.overlay {
		id = "chat_dropzone",
		w_full = true,
		h_full = true,
		drop_when = function(payload: any): boolean
			return what(payload) ~= nil
		end,
		on_drag_over = function(payload: any)
			local now = what(payload)
			if M.over:peek() ~= now then
				M.over:set(now)
			end
		end,
		on_drag_leave = function()
			M.over:set(nil)
		end,
		on_drop = function(payload: any)
			M.over:set(nil)
			-- The conversation holds the draft and the attachments.
			if state.hooks.drop_into then
				state.hooks.drop_into(session, payload)
			end
		end,
		content,
		ui.presence(M.over, function(over: string): Node
			return ui.row {
				id = "chat_dropzone_overlay",
				absolute = true,
				top = 0,
				left = 0,
				right = 0,
				bottom = 0,
				items = "center",
				justify = "center",
				bg = T.drop_scrim,
				pointer_events = "none",
				kit.text.text {
					if over == "mention" then "Drop to mention" else "Drop to attach",
					size = "md",
					line = false,
				},
			}
		end, { absolute = true, top = 0, left = 0, right = 0, bottom = 0, pointer_events = "none" }),
	}
end

return M
