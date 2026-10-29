-- The sidebar toggle's glyph (icons.rs:271–305, zterm's sidebar.luau): a
-- rounded frame with an inner panel at its left whose width narrows from
-- 5.5 to 1.75 units of 24 as the sidebar closes, over 280 ms on
-- ease-out-quint.
local T = require("../theme")
local motion = require("./motion")

export type Props = { open: State<boolean>, size: number?, color: Color? }

return ui.component(function(props: Props): Node
	local k = (props.size or 16) / 24
	local color = props.color or T.secondary
	return ui.div {
		relative = true,
		w = 24 * k,
		h = 24 * k,
		ui.div {
			absolute = true,
			left = 2.125 * k,
			top = 3.125 * k,
			w = 19.75 * k,
			h = 17.75 * k,
			rounded = ui.raw(4.875 * k, "a drawn glyph's corner, scaled with it"),
			border = 1.75 * k,
			border_color = color,
		},
		ui.div {
			absolute = true,
			left = 6.5 * k,
			top = 7.5 * k,
			h = 9 * k,
			rounded = ui.raw(0.875 * k, "a drawn glyph's corner, scaled with it"),
			bg = color,
			w = ui.tween(
				ui.computed(function()
					return if props.open:get() then 5.5 * k else 1.75 * k
				end),
				{ duration = motion.d(280), ease = motion.EASE_OUT_QUINT }
			),
		},
	}
end)
