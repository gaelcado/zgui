-- What resizes two columns or two panes: the room between them takes the
-- pointer (its whole length, the gap's width or more), and under the
-- pointer a slim line shows down its middle, 2 wide, rounded, in the text
-- colour faintly (`zeron.resize.line`), stopping 10 short of each end.
-- Nothing at rest, and no script as the pointer passes: the line is the
-- room's group hover. A press and drag is the caller's (`on_press`,
-- `on_press_move`, `on_release`), as the cursor is.
local T = require("../theme")

export type Axis = "row" | "column"

local M = {}

M.LINE = 2
M.INSET = 10

-- The line inside a room laid out along `axis` ("row": side by side, so
-- the line runs down), centred, `offset` from the centre if given (a seam
-- over a hairline at its edge).
function M.line(axis: Axis, offset: number?): Node
	local down = axis == "row"
	local half = ui.raw((offset or 0) - M.LINE / 2, "half the line, to centre it")
	return ui.div {
		absolute = true,
		top = if down then M.INSET else "50%",
		bottom = if down then M.INSET else nil,
		left = if down then "50%" else M.INSET,
		right = if down then nil else M.INSET,
		w = if down then M.LINE else nil,
		h = if down then nil else M.LINE,
		ml = if down then half else nil,
		mt = if down then nil else half,
		rounded = T.radius_full,
		bg = T.clear,
		pointer_events = "none",
		group_hover = { bg = T.resize_line },
	}
end

return M
