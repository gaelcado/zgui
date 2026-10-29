-- Appearance (settings/appearance.rs): the System / Light / Dark cards at
-- 148 with their miniature of the shell (a 44 sidebar of bars, a pane of
-- bars), the border and caption fading to the accent over 150 ms; the
-- accent swatches at 30 with a 2-point bar under the chosen one.
local T = require("../theme")
local recipes = require("./recipes")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")

export type Mode = "system" | "light" | "dark"
export type CardProps = { id: string?, mode: Mode, selected: types.Cond?, on_click: (Handler | Action)? }
export type Swatch = { id: string, color: Color?, label: string }
export type SwatchesProps = { id: string?, swatches: { Swatch }, value: State<string> }

local M = {}

type Palette = { surface: Color, bg: Color, ink: Color, border: Color }
-- Each card shows its mode in its own colours, whatever the theme.
local function palette(mode: string): Palette
	local p = `$zeron.preview.{mode}`
	return { surface = `{p}.surface`, bg = `{p}.bg`, ink = `{p}.ink`, border = `{p}.border` }
end
local LIGHT = palette("light")
local DARK = palette("dark")

local ICON: { [Mode]: icon_mod.Name } = { system = "monitor", light = "sun", dark = "moon" }
local LABEL: { [Mode]: string } = { system = "System", light = "Light", dark = "Dark" }

-- The card's inner width, and what the miniature divides it into.
local INNER = 146
local SIDEBAR = 44
local PANE = INNER - SIDEBAR - 16
local PANE_INNER = PANE - 20

local function bars(ink: Color, widths: { number }, span: number, strong: number?): { Node }
	local out: { Node } = {}
	for i, w in widths do
		table.insert(
			out,
			ui.div {
				w = math.floor(span * w / 100),
				h = 5,
				rounded = "$zeron.radius.3",
				bg = ink,
				opacity = if i == (strong or 1) then 0.34 else 0.22,
			}
		)
	end
	return out
end

-- The miniature: a 44 sidebar (bars 5 at a 7 gap) and a pane with a
-- border and bars inside, all at fixed widths so halves can be clipped.
local function miniature(p: Palette): Node
	return ui.row {
		w = INNER,
		h_full = true,
		shrink = 0,
		bg = p.surface,
		overflow = "hidden",
		ui.column {
			w = SIDEBAR,
			shrink = 0,
			px = "$zeron.space.8",
			pt = "$zeron.space.14",
			gap = "$zeron.space.7",
			bars(p.ink, { 70, 100, 85, 100 }, SIDEBAR - 16),
		},
		ui.column {
			w = PANE,
			shrink = 0,
			m = "$zeron.space.8",
			ml = 0,
			p = "$zeron.space.10",
			gap = "$zeron.space.7",
			rounded = "$zeron.radius.6",
			bg = p.bg,
			border = 1,
			border_color = p.border,
			bars(p.ink, { 62, 88, 76, 52 }, PANE_INNER),
		},
	}
end

-- System: light on the left half, dark on the right, split down the middle.
local function split(): Node
	return ui.div {
		relative = true,
		w = INNER,
		h_full = true,
		miniature(LIGHT),
		ui.div {
			absolute = true,
			top = 0,
			bottom = 0,
			left = INNER / 2,
			w = INNER / 2,
			overflow = "hidden",
			ui.div { absolute = true, top = 0, bottom = 0, left = -INNER / 2, w = INNER, miniature(DARK) },
		},
	}
end

M.card = ui.component(function(props: CardProps): Node
	local function on(): boolean
		return types.on(props.selected)
	end
	local preview: Node
	if props.mode == "system" then
		preview = split()
	else
		preview = miniature(if props.mode == "light" then LIGHT else DARK)
	end
	return ui.button {
		id = props.id,
		w = 148,
		p = 0,
		direction = "column",
		items = "stretch",
		gap = "$zeron.space.8",
		bg = T.clear,
		hover = { bg = T.clear },
		focus = { border = 0 },
		cursor = "pointer",
		variants = recipes.mode_card { selected = on },
		on_click = props.on_click,
		ui.column {
			h = 108,
			rounded = T.radius_md,
			border = 1,
			variants = recipes.mode_frame { selected = on },
			overflow = "hidden",
			preview,
		},
		ui.row {
			gap = "$zeron.space.6",
			items = "center",
			justify = "center",
			icon { name = ICON[props.mode], size = 16, color = "currentColor" },
			ui.text {
				LABEL[props.mode],
				font = T.sans,
				text_size = "$font.size.md",
				variants = recipes.mode_caption { selected = on },
			},
		},
	}
end)

-- Swatches: 30×34 cells with a 2-point accent bar under the chosen one;
-- the swatch at 30, padded 2, radius 8, on raised 42%; the theme's own
-- accent shows three bars on the wash.
M.swatches = ui.component(function(props: SwatchesProps): Node
	local cells: { Node } = {}
	for _, s in props.swatches do
		local function on(): boolean
			return props.value:get() == s.id
		end
		table.insert(
			cells,
			ui.button {
				id = props.id and `{props.id}_{s.id}`,
				w = 30,
				h = 34,
				p = 0,
				pb = "$zeron.space.4",
				direction = "column",
				items = "center",
				bg = T.clear,
				hover = { bg = T.clear },
				focus = { border = 0 },
				cursor = "pointer",
				border_sides = { 0, 0, 2, 0 },
				variants = recipes.swatch_cell { selected = on },
				on_click = ui.set(props.value, s.id),
				ui.row {
					w = 30,
					h = 30,
					p = "$zeron.space.2",
					rounded = "$zeron.radius.8",
					bg = T.ink2,
					border = 1,
					items = "center",
					justify = "center",
					variants = recipes.swatch_well { selected = on },
					if s.color
						then ui.div { w_full = true, h_full = true, rounded = "$zeron.radius.6", bg = s.color }
						else ui.row {
							w_full = true,
							h_full = true,
							rounded = "$zeron.radius.6",
							bg = T.accent_wash,
							gap = "$zeron.space.2",
							items = "center",
							justify = "center",
							ui.div { w = 4, h = 13, rounded = "$zeron.radius.2", bg = T.accent },
							ui.div { w = 4, h = 16, rounded = "$zeron.radius.2", bg = T.accent },
							ui.div { w = 4, h = 11, rounded = "$zeron.radius.2", bg = T.accent },
						},
				},
			}
		)
	end
	return ui.row { id = props.id, gap = "$zeron.space.6", items = "end", cells }
end)

return M
