-- A collapsible's chevron: after its header's text (a transcript's tool
-- call group alone leads with it). Shut, it points right; open, it turns a
-- quarter toward where the content opened (`opens`: down under the header,
-- the default, or up when the content rises above it, as a tray docked
-- over the composer does), over the fold's duration. The header itself is
-- no button: no wash under the pointer, its label brightening instead
-- (`recipes.disclosure`).
local icon = require("./icon")
local motion = require("./motion")

export type Opens = "down" | "up"
export type Props = {
	id: string?,
	open: State<boolean> | (() -> boolean),
	-- Where the content opens from its header.
	opens: Opens?,
	size: number?,
	color: Color?,
}

local M = {}

M.FOLD = motion.COLLAPSE

-- The open chevron's turn from right, in degrees.
function M.turn(opens: Opens?): number
	return if opens == "up" then -90 else 90
end

M.chevron = ui.component(function(props: Props): Node
	local open = props.open
	local turned: State<boolean> = if type(open) == "function"
		then ui.computed(open :: () -> boolean) :: any
		else open :: State<boolean>
	local size = props.size or 12
	return ui.div {
		id = props.id,
		w = size,
		h = size,
		shrink = 0,
		items = "center",
		justify = "center",
		rotate = ui.tween(
			turned,
			{ from = 0, to = M.turn(props.opens), duration = motion.d(M.FOLD), ease = motion.EASE_OUT }
		),
		icon { name = "alt-arrow-right", size = size, color = props.color or "currentColor" },
	}
end)

return M
