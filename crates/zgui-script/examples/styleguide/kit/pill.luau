-- The running pill: how many agents are busy. 16 high, a 5-point dot
-- pulsing on the 2.4 s clock, mono digits, the accent at 16%; counts cap at
-- 99+.
local T = require("../theme")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Props = { id: string?, count: Reactive<number>, tone: Color? }

local function label(count: Reactive<number>): () -> string
	return function()
		local n: number
		if type(count) == "number" then
			n = count
		elseif type(count) == "function" then
			n = count()
		else
			n = (count :: any):get()
		end
		return if n > 99 then "99+" else tostring(n)
	end
end

return ui.component(function(props: Props): Node
	local tone = props.tone or T.accent
	return ui.row {
		id = props.id,
		variants = recipes.running_pill,
		ui.div {
			w = 5,
			h = 5,
			rounded = "$zeron.radius.2_5",
			bg = tone,
			opacity = if motion.loops() then ui.loop { from = 0.4, to = 1, duration = 2400, fps = 30 } else 1,
		},
		txt.text {
			label(props.count),
			size = "micro",
			mono = true,
			weight = "medium",
			color = "inherit",
			line = false,
			tabular = true,
		},
	}
end)
