-- Frost: Zeron's floating surface. One blur of 16 under a translucent tint,
-- a hairline, the popover radius of 12 and its concentric 4-point inset;
-- opaque surfaces drop the blur and cast the large shadow instead (kit/look).
-- Its look is `recipes.frost`.
local T = require("../theme")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	[number]: Child,
	-- 12 (card) unless told otherwise; rows inside take radius − inset.
	radius: Num?,
	p: Length?,
	gap: Num?,
	w: Length?,
	h: Length?,
	w_full: boolean?,
	grow: number?,
	shrink: number?,
	shadow: boolean?,
	absolute: boolean?,
	top: Length?,
	left: Length?,
	right: Length?,
	bottom: Length?,
	pointer_events: ("none" | "auto")?,
	on_mount: ((el: Element) -> ())?,
	ref: Ref?,
}

local M = {}

-- The blur (16, none when opaque) and the shadow (none under frost).
M.BLUR = T.frost_blur
M.SHADOW = T.float_shadow
M.INSET = 4

M.card = ui.component(function(props: Props): Node
	return ui.column {
		id = props.id,
		ref = props.ref,
		variants = recipes.frost { lifted = props.shadow ~= false },
		w = props.w,
		h = props.h,
		w_full = props.w_full,
		grow = props.grow,
		shrink = props.shrink,
		absolute = props.absolute,
		top = props.top,
		left = props.left,
		right = props.right,
		bottom = props.bottom,
		-- A caller's own padding, gap or radius wins over the recipe's.
		p = props.p,
		gap = props.gap,
		rounded = props.radius,
		pointer_events = props.pointer_events,
		on_mount = props.on_mount,
		{ table.unpack(props) },
	}
end)

return M
