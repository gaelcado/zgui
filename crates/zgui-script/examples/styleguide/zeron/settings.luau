-- Settings, as Zeron's: the kit's settings page in place of the whole
-- window, on its glass (the app beneath stops painting while it shows). ⌘,
-- opens it from any layout; Esc or Back returns to where the window was.
local T = require("../theme")
local kit = require("@kit")
local page = require("@kit/settings_page")
local ps = require("@kit/panel_shell")
local data = require("./data")
local state = require("./state")

local M = {}

M.section = ui.state("settings_section", "general")

-- The preferences the pages hold (the engine will keep them).
local pref = page.prefs("pref")
M.pref = pref

local archived: { page.Archived } = {}
for _, s in data.SESSIONS do
	if s.archived then
		table.insert(archived, { title = s.title, project = s.project, ago = s.ago })
	end
end

local context: page.Context = {
	section = M.section,
	prefs = pref,
	look = state.look,
	layouts = state.LAYOUTS :: any,
	layout = state.layout :: any,
	archived = archived,
	archived_total = data.ARCHIVED_TOTAL,
	on_back = ui.set(state.settings, false),
	on_sign_out = function()
		state.settings:set(false)
		require("./onboarding").start()
	end,
	-- The sections take the sidebar's width.
	sidebar_width = function(): number
		return ps.sidebar_width(state.shell())
	end,
}

-- The page over the window.
function M.view(): Node
	return ui.presence(function()
		return if state.settings:get() then "on" else nil
	end, function(): Node
		return ui.row {
			id = "settings",
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			bg = T.clear,
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.FAST) })
			end,
			page.view(context),
		}
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		exit = {
			opacity = 0,
			duration = kit.motion.d(kit.motion.MENU_OUT),
		},
	})
end

return M
