-- Glass: Rex's material in the layout Dia, zimmer, Rex and Tern share. A
-- sidebar straight on the window's blur (spaces of items, favourites, the
-- titlebar's controls beside the traffic lights) and the content in wells
-- inset into that glass, one or two side by side.
-- Run: cargo run -p zgui-run -- crates/zgui-script/examples/glass
require("./theme")
local state = require("./state")
local sidebar = require("@components/sidebar")
local card = require("@components/card")

ui.theme.strict("warn")

ui.command {
	id = "sidebar",
	title = "Toggle Sidebar",
	menu = "View",
	key = "cmd+\\",
	run = function()
		state.sidebar:toggle()
	end,
}
ui.command {
	id = "split",
	title = "Split",
	menu = "View",
	key = "cmd+d",
	run = state.split,
}
ui.command {
	id = "close_split",
	title = "Close Split",
	menu = "View",
	key = "cmd+w",
	run = function()
		if state.right:peek() then
			state.split()
		end
	end,
}
ui.command {
	id = "appearance",
	title = "Light or Dark",
	menu = "View",
	key = "cmd+shift+l",
	run = function()
		state.dark:toggle()
	end,
}

return ui.row {
	w_full = true,
	h_full = true,
	bg = "$glass.tint",
	color = "$text.primary",
	sidebar.view(),
	ui.row {
		id = "wells",
		grow = 1,
		min_w = 0,
		h_full = true,
		gap = "$shell.gap",
		pt = "$shell.gap",
		pr = "$shell.gap",
		pb = "$shell.gap",
		pl = ui.tween(state.sidebar, { from = 8, to = 2, duration = 220, ease = "outQuart" }),
		card.view(1, state.left),
		ui.show(function()
			return state.right:get() ~= nil
		end, card.view(2, state.right)),
	},
}
