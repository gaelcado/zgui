-- A hairline between things, across or down, optionally with a label.
local txt = require("./text")
local recipes = require("./recipes")

export type Props = {
	vertical: boolean?,
	-- Space kept clear at each end.
	inset: Num?,
	label: string?,
	-- Space around it along the flow.
	my: Length?,
	mx: Length?,
	strong: boolean?,
}

return ui.component(function(props: Props): Node
	local strong = props.strong == true
	if props.vertical then
		return ui.div {
			variants = recipes.divider { axis = "down", strong = strong },
			my = props.inset,
			mx = props.mx,
		}
	end
	if props.label then
		return ui.row {
			w_full = true,
			my = props.my,
			px = props.inset,
			gap = "$zeron.space.10",
			items = "center",
			ui.div { variants = recipes.divider { strong = strong }, grow = 1, w_full = false },
			txt.eyebrow(props.label),
			ui.div { variants = recipes.divider { strong = strong }, grow = 1, w_full = false },
		}
	end
	return ui.div { variants = recipes.divider { strong = strong }, my = props.my, mx = props.inset }
end)
