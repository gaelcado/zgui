-- Key caps, as tooltips, menus and hints show a shortcut: `kbd { "⌘", "K" }`.
local txt = require("./text")
local recipes = require("./recipes")

export type Props = {
	[number]: string,
	-- On a surface that is already raised (a tooltip, a menu).
	flat: boolean?,
	size: VariantOption<typeof(recipes.kbd), "size">?,
}

local function cap(key: string, flat: boolean, small: boolean): Node
	return ui.row {
		variants = recipes.kbd { size = if small then "sm" else "md", flat = flat },
		txt.text { key, size = if small then "micro" else "xs", mono = true, color = "inherit", line = false },
	}
end

return ui.component(function(props: Props): Node
	local caps: { Node } = {}
	for i, key in ipairs(props) do
		caps[i] = cap(key, props.flat == true, props.size == "sm")
	end
	return ui.row { gap = "$zeron.space.2", items = "center", shrink = 0, caps }
end)
