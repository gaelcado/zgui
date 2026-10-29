-- An empty state (Wing's editor pane before a file): an icon on a tile, a
-- title, a line of help, the actions that start something, and a quiet
-- hint about where you were.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local button = require("./button")
local kbd = require("./kbd")
local recipes = require("./recipes")

export type Action = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	keys: { string }?,
	primary: boolean?,
	on_click: (Handler | Action)?,
}
export type Props = {
	id: string?,
	icon: icon_mod.Name,
	title: string,
	description: string?,
	actions: { Action }?,
	hint: string?,
}

return ui.component(function(props: Props): Node
	local actions: { Node } = {}
	for _, a in props.actions or {} do
		table.insert(
			actions,
			ui.row {
				gap = 0,
				items = "center",
				button {
					id = a.id,
					label = a.label,
					icon = if a.icon then { name = a.icon :: icon_mod.Name } else nil,
					size = "sm",
					variant = if a.primary then "primary" else "secondary",
					on_click = a.on_click,
				},
				a.keys and ui.div { ml = "$zeron.pull.2", kbd(table.clone(a.keys) :: kbd.Props) },
			}
		)
	end
	return ui.column {
		id = props.id,
		items = "center",
		gap = "$zeron.space.6",
		p = "$zeron.space.24",
		ui.row { variants = recipes.empty_tile, icon { name = props.icon, size = 18, color = "currentColor" } },
		txt.text { props.title, size = "md", weight = "medium" },
		props.description and txt.text {
			props.description,
			size = "xs",
			color = T.secondary,
			align = "center",
			wrap = true,
			max_w = 280,
		},
		#actions > 0 and ui.row { mt = "$zeron.space.10", gap = "$zeron.space.8", items = "center", actions },
		props.hint and txt.text {
			props.hint,
			size = "micro",
			mono = true,
			color = T.tertiary,
			mt = "$zeron.space.14",
			truncate = true,
			max_w = 320,
		},
	}
end)
