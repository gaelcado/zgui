-- The "Scroll to bottom" pill: 30 high, radius 15, frosted over the popup
-- tint with a hairline, text 13; it rises 2 points in over 180 ms and
-- leaves at once.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local motion = require("./motion")
local recipes = require("./recipes")

export type Props = { id: string?, label: string?, on_click: (Handler | Action)? }

return ui.component(function(props: Props): Node
	return ui.button {
		id = props.id,
		variants = recipes.jump,
		on_click = props.on_click,
		on_mount = function(el: Element)
			anime.animate(
				el,
				{ opacity = { 0, 1 }, y = { 2, 0 }, duration = motion.d(motion.DIALOG_IN), ease = motion.EASE }
			)
		end,
		icon { name = "arrow-down", size = 13, color = T.secondary },
		txt.text { props.label or "Scroll to bottom", size = "md", line = false, color = "inherit" },
	}
end)
