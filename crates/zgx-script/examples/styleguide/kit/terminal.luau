-- Zeron's terminal panel (terminal/panel.rs, view.rs): the 40 bar of
-- 118×28 tabs (the terminal glyph, the program's title, a close on the
-- chosen one; a middle click closes any), a 28 + and the hide chevron at
-- its end; the grid 12 in from its edges at 13 points in the theme's
-- terminal colours, on the terminal background (40% on glass), its
-- scrollback's rail over its right edge; "[process exited N]" once its
-- process ends. The terminal is Ghostty's (`ui.terminal`), where the host
-- has it; elsewhere a stand-in says so.
local T = require("../theme")
local types = require("./types")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")
local browser = require("./browser")

export type TabProps = {
	id: string?,
	title: Text,
	selected: types.Cond?,
	-- Its process ended: the tab dims.
	exited: types.Cond?,
	on_click: (Handler | Action)?,
	on_close: Handler?,
}
export type BarProps = {
	id: string?,
	[number]: Child,
	on_add: (Handler | Action)?,
	on_hide: (Handler | Action)?,
}
export type ViewProps = {
	id: string?,
	term: Term,
	-- Whether the host shows terminals (`ui.native`'s `terminals`).
	native: () -> boolean,
	-- Its panel (the terminal background unless given: a dock draws its
	-- own under its bar).
	bg: Color?,
}

local M = {}

M.TAB_W = 118
M.TAB_H = 28
M.BAR_H = 40
M.FONT = 13

-- Ghostty's configuration for Zeron's terminal (view.rs's palette and
-- font): the theme's terminal colours (`zeron.terminal`), the font and
-- size Appearance chose, and ⌘K the app's (Zeron's terminal hands every ⌘
-- key to the app; Ghostty binds ⌘K to clear the screen). Read in a
-- computed, it follows the theme.
function M.config(font: string, size: number): string
	local function hex(token: string): string
		return string.sub(tostring(ui.theme.get(token)), 1, 7)
	end
	local lines = {
		`background = {hex("surface.sunken")}`,
		`foreground = {hex("zeron.terminal.fg")}`,
		`selection-background = {hex("zeron.terminal.selection")}`,
		`selection-foreground = {hex("zeron.terminal.fg")}`,
		`font-family = {font}`,
		`font-size = {size}`,
		"keybind = super+k=unbind",
	}
	for i = 0, 15 do
		local colour = hex("zeron.terminal.ansi." .. tostring(i))
		table.insert(lines, `palette = {i}={colour}`)
	end
	return table.concat(lines, "\n")
end
-- The grid's inset is 12; Ghostty pads 10 across and 6 down itself.
M.PAD_X = 2
M.PAD_Y = 6

local function square(id: string?, label: string, name: icon.Name, size: number, run: (Handler | Action)?): Node
	return ui.button {
		variants = recipes.wash { hover = "ink1" },
		id = id,
		w = M.TAB_H,
		h = M.TAB_H,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.8",
		cursor = "pointer",
		focus = { border = 0 },
		tooltip = label,
		on_click = run,
		icon { name = name, size = size, color = T.tertiary },
	}
end

-- A tab: `chip` is the node (a strip's tab dresses itself with it), `tab`
-- the component.
function M.chip(props: TabProps): Node
	local function on(): boolean
		return types.on(props.selected)
	end
	return ui.button {
		variants = recipes.terminal_tab { selected = on, exited = props.exited or false },
		id = props.id,
		w = M.TAB_W,
		h = M.TAB_H,
		shrink = 0,
		pl = "$zeron.space.8",
		pr = "$zeron.space.4",
		gap = "$zeron.space.6",
		items = "center",
		rounded = "$zeron.radius.8",
		cursor = "pointer",
		focus = { border = 0 },
		on_click = props.on_click,
		on_aux_click = function(e: AuxClickEvent)
			if e.button == "middle" and props.on_close then
				props.on_close()
			end
		end,
		icon {
			name = "terminal",
			size = 16,
			color = "currentColor",
			variants = recipes.terminal_tab_icon { selected = on },
		},
		txt.text {
			props.title,
			size = "sm",
			line = false,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
			color = "inherit",
		},
		ui.button {
			id = props.id and `{props.id}_close`,
			w = 20,
			h = 20,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			bg = T.clear,
			hover = { bg = T.ink3 },
			focus = { border = 0 },
			cursor = "pointer",
			-- Only the chosen tab's.
			invisible = function()
				return not on()
			end,
			tooltip = "Close terminal",
			on_click = props.on_close,
			icon { name = "close", size = 12, color = T.secondary },
		},
	}
end
M.tab = ui.component(M.chip)

M.bar = ui.component(function(props: BarProps): Node
	return ui.row {
		id = props.id,
		w_full = true,
		h = M.BAR_H,
		shrink = 0,
		pl = "$zeron.space.8",
		pr = "$zeron.space.6",
		gap = "$zeron.space.4",
		items = "center",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		{ table.unpack(props) },
		square(props.id and `{props.id}_add`, "New terminal", "plus", 16, props.on_add),
		ui.div { grow = 1 },
		square(props.id and `{props.id}_hide`, "Hide terminal", "alt-arrow-down", 13, props.on_hide),
	}
end)

-- The session, or the stand-in where the host has no terminals.
M.view = ui.component(function(props: ViewProps): Node
	local term = props.term
	return ui.presence(function()
		return if props.native() then "term" else "none"
	end, function(what: string): Node
		if what == "none" then
			return ui.column {
				id = props.id,
				grow = 1,
				w_full = true,
				items = "center",
				justify = "center",
				browser.empty {
					icon = "terminal",
					title = "No terminal in this build",
					body = "Terminals run on Ghostty: build with zgx-desktop's ghostty feature (macOS).",
				},
			}
		end
		return ui.column {
			id = props.id,
			grow = 1,
			w_full = true,
			min_h = 0,
			px = T.space(M.PAD_X),
			py = T.space(M.PAD_Y),
			items = "stretch",
			bg = props.bg or T.terminal,
			ui.terminal { term = term, scrollbar = true, grow = 1, min_h = 0, w_full = true },
			ui.show(
				function()
					return term.exited ~= nil
				end,
				txt.text {
					function()
						return `[process exited {term.exited or 0}]`
					end,
					mono = true,
					size = "md",
					color = T.tertiary,
					px = "$zeron.space.10",
					py = "$zeron.space.6",
				}
			),
		}
	end, { grow = 1, w_full = true, min_h = 0, items = "stretch" })
end)

return M
