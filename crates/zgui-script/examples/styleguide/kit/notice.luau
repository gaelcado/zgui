-- A notice: a warning or error line in a tinted chip, with a copy button.
-- Zeron's `notice.rs`: accent at 5% over a 1-point accent border at 16%,
-- the message wrapping rather than truncating.
local T = require("../theme")
local icon = require("./icon")
local txt = require("./text")
local icon_button = require("./icon_button")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	message: string,
	tone: VariantOption<typeof(recipes.notice), "tone">?,
	-- A 20-point tile holds the icon, as the transcript draws it.
	tile: boolean?,
	on_copy: Handler?,
	w: Length?,
	w_full: boolean?,
}

return ui.component(function(props: Props): Node
	local tone = if props.tone == "danger" then "danger" else "warning"
	local tile = props.tile == true
	return ui.row {
		id = props.id,
		variants = recipes.notice { tone = tone, tile = tile },
		w = props.w,
		w_full = props.w_full,
		-- The icon takes the tone's colour; the message the text's.
		if tile
			then ui.row {
				variants = recipes.notice_tile { tone = tone },
				icon { name = "danger-triangle", size = 12, color = "currentColor" },
			}
			else icon { name = "danger-triangle", size = 14, color = "currentColor" },
		txt.text { props.message, size = "sm", wrap = true, grow = 1, shrink = 1, min_w = 0, color = T.text },
		icon_button {
			icon = "copy",
			size = 20,
			icon_size = 12,
			on_click = props.on_copy,
			label = "Copy",
			no_ring = true,
		},
	}
end)
