-- A footer of key hints under a palette or a panel: key caps and what they
-- do, on a hairline.
local T = require("../theme")
local txt = require("./text")
local kbd = require("./kbd")
local recipes = require("./recipes")

export type Hint = { keys: { string }, label: string }
export type Props = { items: { Hint }, id: string?, px: Num? }

return ui.component(function(props: Props): Node
	local parts: { Node } = {}
	for _, h in props.items do
		table.insert(
			parts,
			ui.row {
				gap = "$zeron.space.5",
				items = "center",
				kbd(table.clone(h.keys) :: kbd.Props),
				txt.text { h.label, size = "micro", color = T.tertiary, line = false },
			}
		)
	end
	return ui.row {
		id = props.id,
		variants = recipes.hints,
		px = props.px,
		parts,
	}
end)
