-- The sent-turn hold, Zeron's overscroll (transcript.rs): when the user
-- sends, the transcript reserves a runway under the new prompt so the view
-- can scroll past its content and the prompt glides to the top of the
-- viewport (10 under the chrome); the reply streams into the space below.
-- The runway shrinks as the reply grows and, once the reply has used it
-- up, the bottom pin takes over. The glide eases out over about 230 ms
-- (Zeron keeps 85% of the remaining distance per frame). Nothing bounces:
-- the runway ends at the view's bottom, with 2 points of slack. Zeron
-- tried 24 and it read as an overshoot-and-fight zone.
local motion = require("./motion")

export type Props = {
	-- Names the hold's states ("own_turn" unless set).
	id: string?,
	-- The scroll's offset (pass the same state to the scroll).
	offset: State<number>,
	-- The prompt's resting distance under the view's top (Zeron: the
	-- titlebar plus 10; 10 in a plain frame).
	inset: number?,
	-- The content column's bottom padding and the gap before the prompt,
	-- so the prompt's top can be placed from the content's height.
	pb: number?,
	gap: number?,
}
export type Hold = {
	-- Give the scroll these.
	runway: State<number>,
	measure: (view: Size, content: Size) -> (),
	-- Whether a prompt is held at the top.
	held: State<boolean>,
	-- Call just before the prompt is appended.
	send: () -> (),
	-- Drop the hold and its runway (a fold, explicit navigation).
	release: () -> (),
}

local M = {}

M.INSET = 10
M.SLACK = 2
M.GLIDE = 230
M.SNAP = 1

function M.new(props: Props): Hold
	local inset = props.inset or M.INSET
	local key = props.id or "own_turn"
	local runway = ui.state(`{key}_runway`, 0)
	local held = ui.state(`{key}_held`, false)
	local view: Size = { w = 0, h = 0 }
	local content: Size = { w = 0, h = 0 }
	-- The prompt's top within the content, while held.
	local anchor: number? = nil
	local glide_pending = false
	local glide: Animation? = nil

	local function target(): number
		return (anchor or 0) - inset
	end

	local function start_glide()
		if glide then
			glide:cancel()
		end
		local to = target()
		-- From the end asked for (math.huge) there is nothing to ease from.
		local from = props.offset:peek()
		if from ~= from or from == math.huge or math.abs(to - from) <= M.SNAP then
			props.offset:set(to)
			return
		end
		-- anime writes the offset itself, without a script call per frame.
		glide = (anime.animate :: any)(props.offset, {
			value = to,
			duration = motion.d(M.GLIDE),
			ease = motion.EASE_OUT_QUINT,
			onComplete = function()
				glide = nil
				props.offset:set(to)
			end,
		}) :: Animation
	end

	local function settle()
		if not anchor then
			return
		end
		-- The room the prompt and its reply have under the hold, less what
		-- the content already fills below the prompt.
		local need = (anchor :: number) - inset + view.h + M.SLACK - content.h
		if need <= 0 then
			anchor = nil
			runway:set(0)
			held:set(false)
			return
		end
		runway:set(need)
		if glide_pending and view.h > 0 then
			glide_pending = false
			start_glide()
		end
	end

	return {
		runway = runway,
		held = held,
		measure = function(v: Size, c: Size)
			view = v
			content = c
			settle()
		end,
		send = function()
			anchor = content.h - (props.pb or 0) + (props.gap or 0)
			held:set(true)
			glide_pending = true
			settle()
		end,
		release = function()
			anchor = nil
			glide_pending = false
			if glide then
				glide:cancel()
				glide = nil
			end
			runway:set(0)
			held:set(false)
		end,
	}
end

return M
