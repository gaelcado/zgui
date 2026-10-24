-- Settings widgets, as Zeron's `settings/widgets.rs` lays a preferences
-- page out: a 760-wide column, a 20/26 header, sections 32 apart with a
-- 13-point label, cards at radius 12 on wash 4.5%, rows 60 high with a
-- title, a meta line and a control at the end.
local T = require("../theme")
local types = require("./types")
local toggle = require("./toggle")
local txt = require("./text")
local icon = require("./icon")
local recipes = require("./recipes")

local M = {}

M.WIDTH = 760

export type HeaderProps = { title: string, description: string? }
M.header = ui.component(function(props: HeaderProps): Node
	return ui.column {
		gap = "$zeron.space.4",
		txt.text { props.title, size = "xxl", weight = "medium" },
		props.description and txt.text { props.description, size = "md", color = T.secondary, wrap = true },
	}
end)

export type SectionProps = { title: string, [number]: Child, id: string? }
M.section = ui.component(function(props: SectionProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.10",
		txt.text { props.title, size = "md", color = T.secondary },
		M.card { table.unpack(props) },
	}
end)

export type CardProps = { [number]: Child, id: string? }
M.card = ui.component(function(props: CardProps): Node
	local rows: { Node } = {}
	for i, child in ipairs(props) do
		if i > 1 then
			table.insert(rows, ui.div { h = 1, mx = "$zeron.space.16", bg = T.hairline })
		end
		table.insert(rows, child :: Node)
	end
	return ui.column { id = props.id, w_full = true, rounded = T.radius_card, bg = T.ink1, rows }
end)

-- A row: title 13 medium, meta 12 muted (parts joined by dots), a control.
-- `meta`: what the row says under its title, its parts dotted apart; one
-- part wraps (a sentence), several stay on their line.
export type RowProps = { id: string?, title: string, meta: { Text }?, control: Node?, on_click: (Handler | Action)? }
M.row = ui.component(function(props: RowProps): Node
	local meta: { Node } = {}
	for i, part in props.meta or {} do
		if i > 1 then
			table.insert(meta, txt.text { "·", size = "sm", color = T.tertiary, opacity = 0.6 })
		end
		table.insert(meta, txt.text { part, size = "sm", color = T.secondary, wrap = #(props.meta or {}) == 1 })
	end
	return ui.row {
		id = props.id,
		w_full = true,
		min_h = 60,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		gap = "$zeron.space.16",
		items = "center",
		cursor = if props.on_click then "pointer" else nil,
		on_click = props.on_click,
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { props.title, size = "md", weight = "medium" },
			#meta > 0 and ui.row { gap = "$zeron.space.6", items = "center", flex_wrap = true, meta },
		},
		props.control,
	}
end)

-- Zeron's larger switch is the kit's toggle at its large size.
export type SwitchProps = { id: string?, value: State<boolean>, disabled: types.Cond? }
M.switch = ui.component(function(props: SwitchProps): Node
	return toggle { id = props.id, value = props.value, disabled = props.disabled, size = "lg" }
end)

-- A select: 32 high, radius 8, wash 6% to 10%, a chevron.
export type SelectProps = { id: string?, value: Text, on_click: (Handler | Action)?, w: Length? }
M.select = ui.component(function(props: SelectProps): Node
	return ui.button {
		variants = recipes.wash { rest = "ink2", hover = "ink4" },
		id = props.id,
		h = 32,
		w = props.w,
		px = "$zeron.space.10",
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.radius_button,
		focus = { border = 0 },
		cursor = "pointer",
		on_click = props.on_click,
		txt.text { props.value, size = "md", line = false, grow = 1 },
		icon { name = "alt-arrow-down", size = 12, color = T.tertiary },
	}
end)

-- An option card: 148 high, radius 6, the border taking the accent when
-- chosen (appearance's theme pickers).
export type OptionProps = {
	id: string?,
	label: string,
	selected: types.Cond?,
	on_click: (Handler | Action)?,
	preview: Node?,
	w: Length?,
}
M.option = ui.component(function(props: OptionProps): Node
	return ui.button {
		id = props.id,
		w = props.w or 148,
		h = 148,
		p = 0,
		direction = "column",
		items = "stretch",
		rounded = T.radius_md,
		bg = T.ink1,
		border = 1,
		variants = recipes.picked_rim { selected = props.selected or false },
		hover = { bg = T.ink2 },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = props.on_click,
		ui.column {
			grow = 1,
			overflow = "hidden",
			rounded_tl = "$zeron.radius.5",
			rounded_tr = "$zeron.radius.5",
			props.preview,
		},
		ui.row {
			h = 32,
			px = "$zeron.space.10",
			items = "center",
			border_sides = { 1, 0, 0, 0 },
			border_color = T.hairline,
			txt.text { props.label, size = "sm", weight = "medium", line = false },
		},
	}
end)

-- A settings badge: wash 8%, text 10.5, fully rounded.
function M.badge(label: string): Node
	return ui.row {
		h = 18,
		px = "$zeron.space.8",
		items = "center",
		rounded = T.radius_full,
		bg = T.ink3,
		txt.text { label, size = "micro", weight = "medium", color = T.secondary, line = false },
	}
end

return M
