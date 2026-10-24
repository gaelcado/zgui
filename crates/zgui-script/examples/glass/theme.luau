-- Glass's tokens, each with a default in standard ones so any theme styles
-- the app; glass-dark.json and glass-light.json are its own look.
ui.theme.tokens {
	shell = {
		-- The content's inset well, its two edges (a dark hairline outside, a
		-- light one inside) and its lift.
		well = "{surface.sunken}",
		edge = "{border.strong}",
		shadow = "{shadow.md}",
		-- The light hairline inside the dark one: an inset ring two points
		-- wide, the outer point under the border. Dimmer on a well that has
		-- lost the focus to the one beside it.
		inner = "0 0 0 2 #ffffff14",
		inner_dim = "0 0 0 2 #ffffff0a",
		-- A sidebar row: chosen, under the pointer; an icon's tile.
		selected = "{pressed}",
		selected_line = "{border.subtle}",
		hover = "{hover}",
		tile = "{hover}",
		-- The composer's field, a sent message's bubble, the send button.
		field = "{hover}",
		field_line = "{border.subtle}",
		bubble = "{hover}",
		send = "{text.primary}",
		on_send = "{surface.base}",
		-- From the window's edge to the well, the sidebar's width, the well's
		-- corners.
		gap = 8,
		sidebar = 236,
		radius = 11,
		-- The app's own steps between the standard scale's: a hairline, a
		-- tight gap, and the spacings the sidebar and the page use.
		hair = 1,
		tight = 2,
		xs = 6,
		sm = 10,
		md = 14,
		lg = 18,
		page = 28,
		-- The titlebar's controls start past the traffic lights.
		lights = 68,
		bubble_radius = 18,
	},
}

local M = {}
M.dark = ui.theme.load("glass-dark.json")
M.light = ui.theme.load("glass-light.json")
ui.theme.default(M.dark)
return M
