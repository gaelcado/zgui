-- The running pill (running_pill.rs): how many agents are busy. 16 high, a
-- 5-point dot breathing 0.4 to 1 on the 2.4 s pulse (a cosine: inOutSine
-- out and back, 15 frames a second as Zeron's), mono 10 medium digits, all
-- in the activity tone (the accent) on its 16%; counts cap at 99+. Still
-- under reduced motion, the dot full.
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
	return ui.row {
		id = props.id,
		variants = recipes.running_pill,
		color = props.tone,
		ui.div {
			w = 5,
			h = 5,
			shrink = 0,
			rounded = T.radius_full,
			bg = props.tone or T.accent,
			opacity = if motion.loops()
				then ui.loop { from = 0.4, to = 1, duration = 2400, ease = "inOutSine", fps = 15 }
				else 1,
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
