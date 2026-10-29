-- The chat's drop zone (shell/chat_dropzone.rs): over a conversation, a
-- session dragged from the sidebar says "Drop to mention", a workspace file
-- or files from another app "Drop to attach", on a scrim at 40%, the words
-- at 13 in the middle; no icon, no border, no fade. A session lands in the
-- draft as a mention, a file as a reference there, other apps' files among
-- the attachments (the conversation's, by `state.hooks.drop_into`). Built
-- only while something is over it.
local T = require("../theme")
local kit = require("@kit")
local state = require("./state")

local M = {}

-- What a drag over it would do: "mention", "attach", or nil.
local function what(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	if payload.kind == "session" then
		return "mention"
	elseif payload.kind == "file" or type(payload.files) == "table" then
		return "attach"
	end
	return nil
end

-- `content` (the conversation of `session`) under the zone, taking what
-- its column leaves (the terminals' dock under it), its ids under
-- `prefix` (each zone its own: a side chat's beside the chat's).
function M.wrap(session: string, content: Node, prefix: string?): Node
	local p = prefix or "chat"
	local over = ui.state(`{p}:drop_over`, nil :: string?)
	return ui.overlay {
		id = `{p}_dropzone`,
		w_full = true,
		grow = 1,
		min_h = 0,
		drop_when = function(payload: any): boolean
			return what(payload) ~= nil
		end,
		on_drag_over = function(payload: any)
			local now = what(payload)
			if over:peek() ~= now then
				over:set(now)
			end
		end,
		on_drag_leave = function()
			over:set(nil)
		end,
		on_drop = function(payload: any)
			over:set(nil)
			-- The conversation holds the draft and the attachments.
			if state.hooks.drop_into then
				state.hooks.drop_into(session, payload)
			end
		end,
		content,
		ui.presence(over, function(said: string): Node
			return ui.row {
				id = `{p}_dropzone_overlay`,
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
					if said == "mention" then "Drop to mention" else "Drop to attach",
					size = "md",
					line = false,
				},
			}
		end, { absolute = true, top = 0, left = 0, right = 0, bottom = 0, pointer_events = "none" }),
	}
end

return M
