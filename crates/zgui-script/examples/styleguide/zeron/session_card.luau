-- The session card over a conversation (kit/session_card), behind the
-- header's card toggle.
local kit = require("@kit")
local session_card = require("@kit/session_card")
local data = require("./data")
local state = require("./state")
local chrome = require("./chrome")

local M = {}

local function info(session: string): session_card.Info
	local s = data.session(session)
	local harness = if s then data.HARNESS[s.harness] else data.HARNESS.claude
	return {
		title = if s then s.title else "New session",
		harness = harness :: any,
		device = "MacBook Pro",
		project = if s then s.project else "zgui",
		branch = s and s.branch,
		pr = s and s.pr :: any,
	}
end

-- The card over a conversation, while the header's toggle has it open.
function M.view(session: string?, prefix: string?): Node
	local p = prefix or "z"
	return ui.presence(function()
		-- The toggle is the classic layouts' header's.
		return if state.card:get() and not state.tabbed() then "on" else nil
	end, function(): Node
		return session_card.card(info(session or state.session:peek()), p)
	end, {
		absolute = true,
		top = chrome.top_px,
		right = 0,
		enter = { opacity = { 0, 1 }, y = { -4, 0 }, duration = kit.motion.d(kit.motion.FAST) },
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.MENU_OUT) },
	})
end

return M
