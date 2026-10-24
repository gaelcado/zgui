-- A popover: Zeron's card (12-point radius, a hairline, the overlay
-- surface, the large shadow) anchored to a trigger, over everything,
-- closing on Escape or a click outside. The content is the caller's. It
-- opens under its trigger unless placed (`placement`: Zeron's composer
-- pickers open above, end-aligned, `M.ABOVE_END`), entering from that side
-- and leaving toward it.
local motion = require("./motion")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	open: State<boolean>,
	anchor: Node,
	label: string?,
	w: Length?,
	p: Length?,
	gap: Num?,
	placement: Placement?,
	[number]: Child,
}

local M = {}

-- Zeron's composer pickers (popover.rs anchored_menu_above_end): up from
-- the trigger, its right edge on the trigger's, 6 away.
local ABOVE_END: Placement = { side = "top", align = "end", offset = 6 }
M.ABOVE_END = ABOVE_END

-- Zeron's popover motion (motion.rs menu_in_from, menu_out_toward): in
-- from `travel` toward the trigger's side at 30%, over MENU_IN; out
-- toward it by half the travel, over MENU_OUT. Every opening plays it.
function M.enter(placement: Placement?, travel: number): ElementParams
	local above = placement ~= nil and placement.side == "top"
	return {
		opacity = { 0.3, 1 },
		y = { if above then travel else -travel, 0 },
		duration = motion.d(motion.MENU_IN),
		ease = motion.EASE,
	}
end
function M.exit(placement: Placement?, travel: number): ElementParams
	local above = placement ~= nil and placement.side == "top"
	return {
		opacity = 0,
		y = (if above then travel else -travel) / 2,
		duration = motion.d(motion.MENU_OUT),
		ease = motion.EASE,
	}
end

M.popover = ui.component(function(props: Props): Node
	return ui.popover {
		id = props.id,
		open = props.open,
		anchor = props.anchor,
		label = props.label or "",
		variants = recipes.popover,
		w = props.w,
		p = props.p,
		gap = props.gap,
		placement = props.placement,
		-- It enters from its trigger's side (motion.rs MENU_IN): from 30%
		-- and 4 toward the trigger, over 140 ms on the plain ease; it leaves
		-- toward it by half that, fading out over 100 ms (menu_out_toward).
		enter = M.enter(props.placement, 4),
		exit = M.exit(props.placement, 4),
		{ table.unpack(props) },
	}
end)

return M
