-- Settings widgets, as Zeron's `settings/widgets.rs` lays a preferences
-- page out: a 760-wide column, a 20/26 header, sections 32 apart with a
-- 13-point label, cards at radius 12 on wash 4.5%, rows 60 high with a
-- title, a meta line and a control at the end.
local T = require("../theme")
local types = require("./types")
local toggle = require("./toggle")
local txt = require("./text")
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

-- Where settings search lands (search/reveal.rs SearchAnchor): each
-- anchored row's element by its name, noted as it mounts.
M.anchors = {} :: { [string]: Element }
function M.anchor(name: string): (el: Element) -> ()
	return function(el: Element)
		M.anchors[name] = el
	end
end

-- A row: title 13 medium, meta 12 muted (parts joined by dots), a control.
-- `meta`: what the row says under its title, its parts dotted apart; one
-- part wraps (a sentence), several stay on their line. `anchor`: its name
-- for settings search. `lead`: a tile before the title.
export type RowProps = {
	id: string?,
	title: Text,
	meta: { Text }?,
	control: Node?,
	on_click: (Handler | Action)?,
	anchor: string?,
	lead: Node?,
}
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
		on_mount = if props.anchor then M.anchor(props.anchor) else nil,
		props.lead,
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
export type SwitchProps = {
	id: string?,
	value: State<boolean>,
	disabled: types.Cond?,
	-- After a click has set `value`.
	on_change: ((on: boolean) -> ())?,
}
M.switch = ui.component(function(props: SwitchProps): Node
	return toggle {
		id = props.id,
		value = props.value,
		disabled = props.disabled,
		size = "lg",
		on_change = props.on_change,
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

-- What failed, in the danger's colour on its wash (widgets::error_strip).
function M.error_strip(text: Text, id: string?): Node
	return ui.row {
		id = id,
		w_full = true,
		px = "$zeron.space.12",
		py = "$zeron.space.8",
		rounded = T.radius_button,
		bg = T.danger_wash,
		txt.text { text, literal = true, size = "sm", color = T.danger, wrap = true },
	}
end

-- A settings badge: wash 8%, text 10.5, fully rounded.
function M.badge(label: Text, id: string?): Node
	return ui.row {
		id = id,
		h = 18,
		px = "$zeron.space.8",
		items = "center",
		rounded = T.radius_full,
		bg = T.ink3,
		txt.text { label, size = "micro", weight = "medium", color = T.secondary, line = false },
	}
end

return M
