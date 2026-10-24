-- Surface chrome: the toolbar strip of Zeron's panes (files, browser,
-- history, PRs) and what sits in it: 38 high with hairlines above and
-- below, 24-point controls and tabs at radius 6, 14-point icons, a 24-high
-- field.
local T = require("../theme")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")

export type ToolbarProps = { id: string?, [number]: Child, gap: number?, px: number? }
export type TabProps = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	selected: types.Cond?,
	on_click: (Handler | Action)?,
}
export type ControlProps = {
	id: string?,
	icon: icon_mod.Name,
	label: string?,
	selected: types.Cond?,
	disabled: types.Cond?,
	on_click: (Handler | Action)?,
}
export type FieldProps = { id: string?, value: State<string>, placeholder: string?, icon: icon_mod.Name?, w: Length? }

local M = {}

M.HEIGHT = 38
M.CONTROL = 24
M.ICON = 14
M.GAP = 4
M.EDGE = 8

M.toolbar = ui.component(function(props: ToolbarProps): Node
	return ui.row {
		id = props.id,
		w_full = true,
		h = M.HEIGHT,
		px = props.px or T.space(M.EDGE),
		gap = props.gap or T.space(M.GAP),
		items = "center",
		shrink = 0,
		bg = T.chrome,
		border_sides = { 1, 0, 1, 0 },
		border_color = T.hairline,
		{ table.unpack(props) },
	}
end)

-- A 24-square icon control, the hover wash blended in.
M.control = ui.component(function(props: ControlProps): Node
	return ui.button {
		variants = recipes.chrome_control { selected = props.selected or false, dim = props.disabled or false },
		id = props.id,
		w = M.CONTROL,
		h = M.CONTROL,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_md,
		cursor = "pointer",
		focus = { border = 0 },
		disabled = props.disabled,
		on_click = props.on_click,
		icon { name = props.icon, size = M.ICON, color = "currentColor" },
	}
end)

-- A 24-high tab: wash 10% selected, 6% hovered, text 12.
M.tab = ui.component(function(props: TabProps): Node
	return ui.button {
		id = props.id,
		h = M.CONTROL,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		cursor = "pointer",
		variants = recipes.chrome_tab { selected = props.selected or false },
		focus = { border = 0 },
		on_click = props.on_click,
		props.icon and icon { name = props.icon, size = M.ICON, color = "currentColor" },
		txt.text { props.label, size = "sm", weight = "medium", line = false, color = "inherit" },
	}
end)

-- A 24-high field on ink 3.5%, text 11.5.
M.field = ui.component(function(props: FieldProps): Node
	return ui.row {
		id = props.id and props.id .. "_frame",
		h = M.CONTROL,
		w = props.w or 200,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = T.ink1,
		border = 1,
		border_color = T.hairline,
		props.icon and icon { name = props.icon, size = 12, color = T.tertiary },
		ui.input {
			id = props.id,
			value = props.value,
			label = props.placeholder or "",
			placeholder = props.placeholder,
			placeholder_color = T.tertiary,
			grow = 1,
			shrink = 1,
			min_w = 0,
			h = "100%",
			px = 0,
			py = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			font = T.sans,
			text_size = "$font.size.xs",
			color = T.text,
			focus = { border = 0 },
		},
	}
end)

return M
