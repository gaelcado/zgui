-- Settings, as Zeron's: the kit's settings page in place of the whole
-- window, on its glass (the app beneath stops painting while it shows). ⌘,
-- opens it from any layout; Esc or Back returns to where the window was.
local T = require("../theme")
local kit = require("@kit")
local page = require("@kit/settings_page")
local appearance = require("@kit/settings_appearance")
local agents = require("@kit/settings_agents")
local capture = require("@kit/settings_capture")
local ps = require("@kit/panel_shell")
local session_sidebar = require("@kit/session_sidebar")
local data = require("./data")
local state = require("./state")
local keys = require("./keys")
local account = require("./account")
local cloud = require("./cloud")
local billing = require("./billing")

local M = {}

M.section = ui.state("settings_section", "general")

-- The preferences the pages hold, kept across runs.
local pref = page.prefs("pref", true)
M.pref = pref
-- Replies and prompts set TeX as Appearance says.
require("@kit/markdown").math = { on = pref.render_math, face = pref.math_font, size = pref.math_size }

-- The archived sessions, newest first: the sample's own, then as many
-- older ones as the shelf counts.
local OLDER = {
	"Profile the text shaper",
	"Draft the 0.2 changelog",
	"Port the menu bar to AppKit",
	"Investigate the flaky drag test",
	"Rename the theme tokens",
	"Sketch the voice stage",
	"Bisect the scroll jank",
	"Review the sync protocol",
}
local archived: { page.Archived } = {}
for _, s in data.SESSIONS do
	if s.archived then
		table.insert(archived, { key = s.key, title = s.title, project = s.project, ago = s.ago })
	end
end
for i = #archived + 1, data.ARCHIVED_TOTAL do
	table.insert(archived, {
		title = OLDER[(i - 1) % #OLDER + 1],
		project = data.PROJECTS[(i - 1) % #data.PROJECTS + 1],
		ago = `{1 + i // 9}mo`,
		device = if i % 5 == 0 then "Mac mini" else nil,
	})
end
M.archived = ui.state("settings_archived", archived)

-- As Settings opens: the sample sessions archived now (the sidebar's menu
-- archives and unarchives them too), then the older ones still listed.
local function refresh()
	local now: { page.Archived } = {}
	for _, s in data.SESSIONS do
		if session_sidebar.archived(s.key, s.archived == true) then
			table.insert(now, { key = s.key, title = s.title, project = s.project, ago = s.ago })
		end
	end
	for _, a in M.archived:peek() do
		if not a.key then
			table.insert(now, a)
		end
	end
	M.archived:set(now)
end

-- Unarchived, a sample session comes back to the sidebar.
local function unarchive(s: page.Archived)
	if s.key then
		session_sidebar.set_archived(s.key, false)
	end
end

-- The pictures the sample's wallpaper folder holds.
local PICTURES = { "images/shadow.jpg", "images/screenshot-tall.jpg" }
-- The new-thread background's file gone (the sample engine loses it).
M.background_missing = ui.state("settings_background_missing_app", false)
-- The voice call's phase (zeron/voice's, which needs this module).
local voice_phase = ui.state("voice_phase", "closed")

-- ⌘U and Shuffle (wallpaper.rs randomize): another picture from the folder
-- behind the new-session canvas. Without a folder, Appearance, to choose
-- one, and why.
function M.random_wallpaper()
	if pref.wallpaper:peek() == "" then
		M.section:set("appearance")
		state.settings:set(true)
		kit.toast.push { title = "Choose a wallpaper folder in Appearance first.", tone = "danger" }
		return
	end
	local now = pref.canvas_background:peek()
	local others = {}
	for _, p in PICTURES do
		if p ~= now then
			table.insert(others, p)
		end
	end
	pref.canvas_background:set(others[math.random(#others)])
	M.background_missing:set(false)
end

-- The sample engine's settings states (⌘K): the next step failing, the
-- USB microphone and the Build box gone, a login signed out, the capture
-- permissions taken back, the background's file lost.
M.sample = {
	fail_next = function()
		agents.fail_next:set(true)
	end,
	unplug = function()
		capture.usb:set(false)
		capture.build_box:set(false)
	end,
	sign_out_login = agents.sign_out_login,
	revoke = capture.revoke,
	lose_background = function()
		if pref.canvas_background:peek() ~= "" then
			M.background_missing:set(true)
		end
	end,
}

local context: page.Context = {
	section = M.section,
	prefs = pref,
	look = state.look,
	layouts = state.LAYOUTS :: any,
	layout = state.layout :: any,
	archived = archived,
	archived_total = data.ARCHIVED_TOTAL,
	keymap = keys.map,
	archived_list = M.archived,
	on_unarchive = unarchive,
	scope = function(): string
		return account.account:peek().scope or "synced"
	end,
	on_back = ui.set(state.settings, false),
	voice_live = function(): boolean
		return voice_phase:get() ~= "closed"
	end,
	on_shuffle = M.random_wallpaper,
	background_missing = M.background_missing,
	-- The sections take the sidebar's width.
	sidebar_width = function(): number
		return ps.sidebar_width(state.shell())
	end,
	-- Cloud and Billing while the account is offered Cloud.
	shown = function(id: string): boolean
		return (id ~= "cloud" and id ~= "billing") or cloud.offered:get()
	end,
}
page.PAGES.cloud = function(): Node
	return cloud.page()
end
page.PAGES.billing = function(): Node
	return billing.page()
end

-- "Add credits" (out of Cloud credits): Billing.
cloud.open_billing = function()
	M.section:set("billing")
	state.settings:set(true)
end

-- Cloud and Billing go once the offer does: General instead.
ui.effect(function()
	local section = M.section:get()
	if (section == "cloud" or section == "billing") and not cloud.offered:get() then
		M.section:set("general")
	end
end)

-- The artwork's colour, where the sample knows it (wallpaper_colors.rs
-- takes it from a 64 thumbnail, favouring saturated pixels).
local ART_COLOUR: { [string]: string } = { ["images/shadow.jpg"] = "#6fae98" }
state.look.tint = ui.state("zeron_look_tint", "")
state.look.fonts = { sans = pref.font_ui, mono = pref.font_code }
ui.effect(function()
	local art = pref.canvas_background:get()
	local tint = if pref.wallpaper_colors:get() then ART_COLOUR[art] or "" else ""
	local now = state.look.tint :: State<string>
	if now:peek() ~= tint then
		now:set(tint)
	end
end)

-- Reduce motion: On, or the system's while System; animations held while
-- the window is at the back, when asked.
ui.effect(function()
	local reduce = appearance.reduces(pref)
	if kit.motion.reduced:peek() ~= reduce then
		kit.motion.reduced:set(reduce)
	end
end)
ui.effect(function()
	if pref.pause_background:get() and not ui.window.active:get() then
		anime.engine.pause()
	else
		anime.engine.resume()
	end
end)

-- ⌘F: the search field.
M.focus_search = page.focus_search

-- However Settings is left, the next visit starts from the sections.
ui.effect(function()
	if not state.settings:get() then
		page.reset_search()
	end
end)

-- The page over the window.
function M.view(): Node
	return ui.presence(function()
		return if state.settings:get() then "on" else nil
	end, function(): Node
		refresh()
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
