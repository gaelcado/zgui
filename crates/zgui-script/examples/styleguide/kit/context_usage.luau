-- Context usage (context_usage.rs): a 16-point ring with a 1.8 stroke
-- that fills clockwise from 12 o'clock, its percentage beside it in a
-- 24-high chip; muted until 75%, warning to 90%, danger past it. The card
-- under it says the numbers.
local T = require("../theme")
local txt = require("./text")
local recipes = require("./recipes")
local frost = require("./frost")
local popover = require("./popover")

export type Props = {
	id: string?,
	-- 0–1, or nil when unknown.
	used: State<number?>,
	-- Tokens, for the card.
	total: number?,
	on_click: (Handler | Action)?,
}
export type CardProps = { id: string?, used: number, total: number }
export type UsageProps = { id: string?, used: State<number?>, total: number }

local M = {}

M.RING = 16
M.STROKE = 1.8

local function tone(used: number?): Color
	if used == nil then
		return T.tertiary
	elseif used >= 0.9 then
		return T.danger
	elseif used >= 0.75 then
		return T.warning
	end
	return T.secondary
end

function M.ring(used: State<number?>): Node
	return ui.canvas {
		w = M.RING,
		h = M.RING,
		shrink = 0,
		draw = function(cv: Canvas, w: number, h: number)
			local u = used:get()
			local r = (w - M.STROKE) / 2
			local track = ui.theme.get("zeron.ink.4") :: string
			cv.circle(cv, w / 2, h / 2, r, T.clear)
			cv.stroke(cv, ui.path():arc(w / 2, h / 2, r, 0, 360), track, M.STROKE)
			if u and u > 0 then
				cv.stroke(
					cv,
					ui.path():arc(w / 2, h / 2, r, -90, 360 * math.min(1, u)),
					tostring(ui.theme.get(string.sub(tone(u) :: string, 2))),
					M.STROKE,
					{ cap = "butt" }
				)
			end
		end,
	}
end

M.chip = ui.component(function(props: Props): Node
	return ui.button {
		id = props.id,
		variants = recipes.context_chip {
			level = function()
				local u = props.used:get()
				return if u == nil then "none" elseif u >= 0.9 then "full" elseif u >= 0.75 then "high" else "low"
			end,
		},
		on_click = props.on_click,
		M.ring(props.used),
		txt.text {
			function()
				local u = props.used:get()
				return if u == nil then "—" else `{math.floor(u * 100 + 0.5)}%`
			end,
			size = "xs",
			tabular = true,
			-- Room for "100%" in tabular figures: the measured run comes up
			-- short of the painted one and would clip the percent sign.
			wrap = false,
			min_w = 26,
			line = false,
			color = "inherit",
		},
	}
end)

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function numbers(used_fraction: number, total: number): { Node }
	local used = math.floor(used_fraction * total)
	return {
		txt.text { "Context window", size = "xs", color = T.tertiary, px = "$zeron.space.8", py = "$zeron.space.4" },
		ui.column {
			px = "$zeron.space.8",
			pb = "$zeron.space.6",
			txt.text { `{thousands(used)} / {thousands(total)} tokens`, size = "sm", color = T.secondary },
			txt.text { `{thousands(total - used)} tokens remaining`, size = "sm", color = T.secondary },
		},
	}
end

M.card = ui.component(function(props: CardProps): Node
	return frost.card {
		id = props.id,
		w = 220,
		numbers(props.used, props.total),
	}
end)

-- The chip in the session footer, its card opening above it, end-aligned
-- 6 away (account_usage.rs anchored_menu_above_end); the numbers are
-- read as it opens.
M.usage = ui.component(function(props: UsageProps): Node
	local open = ui.use_state(false)
	return popover.popover {
		id = props.id and `{props.id}_card`,
		open = open,
		label = "Context window",
		placement = popover.ABOVE_END,
		w = 220,
		p = T.space(frost.INSET),
		anchor = M.chip { id = props.id, used = props.used, on_click = ui.toggle(open) },
		ui.presence(function()
			return if open:get() then tostring(props.used:get() or 0) else nil
		end, function(): Node
			return ui.column { numbers(props.used:peek() or 0, props.total) }
		end),
	}
end)

return M
