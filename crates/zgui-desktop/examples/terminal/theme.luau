-- The terminal's colours are theme tokens, so any theme styles it: the
-- standard ones, and the app's own below, whose defaults are written in
-- terms of the standard ones. Its own look is glass.json, a theme that sets
-- both; `ui.theme.set("zgui-light")` (or any other theme) restyles it live.
ui.theme.tokens {
	terminal = {
		-- Each terminal's card.
		pane = "{surface.sunken}",
		-- A selected tab, a dialog's button.
		wash = "{pressed}",
		-- Frosted glass under what is active (the tab, the agent); a fainter
		-- one under the pointer.
		glass = "{pressed}",
		glass_hover = "{hover}",
		-- The focused pane's border, when there are several.
		ring = "{border.strong}",
		-- Claude's colour, whatever the theme.
		claude = "#d97757",
	},
}
ui.theme.default(ui.theme.load("glass.json"))

return {
	tint = "$glass.tint",
	pane = "$terminal.pane",
	wash = "$terminal.wash",
	glass = "$terminal.glass",
	glass_hover = "$terminal.glass_hover",
	hover = "$hover",
	line = "$border.subtle",
	ring = "$terminal.ring",
	text = "$text.primary",
	secondary = "$text.secondary",
	tertiary = "$text.tertiary",
	quaternary = "$text.disabled",
	accent = "$accent",
	bell = "$warning",
	claude = "$terminal.claude",
	danger = "$danger",
	clear = "#00000000",
	font = "$font.sans",

	-- Space between the window's edge and the panes, and between panes
	-- (less: two borders meet there, which reads as more space).
	inset = 6,
	gap = 4,
	titlebar = 40,
}
