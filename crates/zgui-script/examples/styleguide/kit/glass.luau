-- Wing's glass (zterm): a clear tint over the window's blur under what is
-- active, one piece per id that slides between rows or tabs. Under the
-- pointer, a glass row washes as every list row does (kit/wash).
local T = require("../theme")
local motion = require("./motion")

local M = {}

M.EASE = "cubicBezier(.22, 1, .36, 1)"
M.DURATION = 320

-- The active glass: `shown()` says whether this row holds it; the one node
-- with `id` slides to whichever row does. The row must be `relative`.
function M.active(id: string, shown: () -> boolean, radius: Num): Node
	return ui.presence(function()
		return if shown() then "on" else nil
	end, function(): Node
		return ui.div {
			layout_id = id,
			layout_duration = motion.d(M.DURATION),
			layout_ease = M.EASE,
			w_full = true,
			h_full = true,
			rounded = radius,
			bg = T.glass_active,
		}
	end, {
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		bottom = 0,
		enter = { opacity = { 0, 1 }, duration = motion.d(160) },
	})
end

-- Press feedback as glass gives: a slight give, then a spring back.
function M.press(ref: Ref): ((e: PointerEvent) -> (), (e: PointerEvent) -> ())
	local function to(params: ElementParams)
		local el = ref:peek()
		if el then
			anime.animate(el, params)
		end
	end
	return function()
		to { scale = 0.985, duration = motion.d(90), ease = "outQuad" }
	end, function()
		to { scale = 1, duration = motion.d(260), ease = "outBack(2)" }
	end
end

return M
