-- Zeron's settings as a mini app: the kit's settings page, a window of its
-- own.
local T = require("./theme")
local page = require("@kit/settings_page")
local look = require("@kit/look")

-- Its own look, worn by the window.
local shown = look.new("settings_app", "zeron", "system")

return ui.row {
	id = "settings_app",
	w_full = true,
	h_full = true,
	items = "stretch",
	bg = T.glass,
	color = T.text,
	font = T.sans,
	text_size = "$font.size.md",
	theme = look.scope(shown),
	page.view {
		section = ui.state("section", "appearance"),
		prefs = page.prefs("app"),
		look = shown,
	},
}
