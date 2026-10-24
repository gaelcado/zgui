-- The palette as a mini app: a frameless frosted window holding the @
-- reference picker. Escape closes the window.
local T = require("./theme")
local kit = require("@kit")

local scope = ui.state("scope", "All")
local chosen = ui.state("chosen", "r1")

return ui.column {
	id = "palette_app",
	w_full = true,
	h_full = true,
	color = T.text,
	font = T.sans,
	text_size = "$font.size.md",
	focusable = true,
	on_mount = function(el: Element)
		el:focus()
	end,
	on_key = function(e: KeyEvent): boolean
		if e.key == "Escape" then
			ui.invoke("close_window")
			return true
		end
		return false
	end,
	kit.palette {
		id = "picker",
		icon = "command",
		placeholder = "Search tabs, files, history…",
		query = "ope",
		count = "7 results",
		scopes = { "All", "Tabs", "Clipboard", "History", "Files", "Bookmarks" },
		scope = scope,
		selected = chosen,
		w = "100%",
		results = {
			{
				id = "r1",
				match = "Ope",
				title = "nTable · Le Bernardin",
				description = "opentable.com/r/le-bernardin",
				group = "Open tabs",
				letter = "O",
				tint = T.danger,
				meta = "Tab",
				keys = { "↩" },
			},
			{
				id = "r2",
				match = "Ope",
				title = "n Kitchen — Dinner menu",
				description = "openkitchen.co/menu",
				group = "Open tabs",
				letter = "K",
				meta = "Tab",
			},
			{
				id = "r3",
				match = "Ope",
				title = "ning hours.pdf",
				description = "Downloads · 240 KB",
				group = "Files & bookmarks",
				icon = "document",
				meta = "PDF",
			},
			{
				id = "r4",
				match = "Ope",
				title = "n data · NYC restaurant grades",
				description = "data.cityofnewyork.us",
				group = "Files & bookmarks",
				icon = "tag",
				meta = "Bookmark",
			},
			{
				id = "r5",
				match = "ope",
				title = "ntable confirmation",
				description = "Clipboard · 2m ago",
				group = "Clipboard",
				letter = "C",
			},
		},
		hints = {
			{ keys = { "↑", "↓" }, label = "Navigate" },
			{ keys = { "↩" }, label = "Insert" },
			{ keys = { "⇥" }, label = "Scope" },
			{ keys = { "⌘", "↩" }, label = "Snapshot" },
		},
		on_choose = function()
			ui.invoke("close_window")
		end,
	},
}
