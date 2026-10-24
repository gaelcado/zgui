-- An avatar: a picture, or initials on a wash, with a status dot at its
-- corner ringed by the surface it sits on. `status_dot` alone marks an
-- agent's state in rows and tabs.
local T = require("../theme")
local motion = require("./motion")
local txt = require("./text")
local icon_mod = require("./icon")
local icon = require("./icon")
local recipes = require("./recipes")

export type Status = "working" | "blocked" | "error" | "done" | "idle" | "online" | "offline"
export type Props = {
	id: string?,
	name: string,
	src: string?,
	-- A mark instead of initials (a harness's icon).
	icon: icon_mod.Name?,
	size: number?,
	status: Reactive<Status>?,
	-- The surface the avatar sits on, for the dot's ring.
	surface: Color?,
	square: boolean?,
}

local STATUS_COLOR: { [Status]: Color } = {
	working = T.accent,
	blocked = T.warning,
	error = T.danger,
	done = T.success,
	idle = T.tertiary,
	online = T.success,
	offline = T.tertiary,
}

local M = {}

local function status_of(s: Reactive<Status>?): Status
	if type(s) == "string" then
		return s
	elseif type(s) == "function" then
		return s()
	elseif type(s) == "table" then
		return (s :: any):get()
	end
	return "idle"
end

-- A status dot: solid for most states, a ring at rest, and a slow pulse
-- while working.
function M.status_dot(status: Reactive<Status>?, size: number?): Node
	local d = size or 8
	return ui.presence(function()
		return status_of(status)
	end, function(s: Status): Node
		local rest = s == "idle" or s == "offline"
		return ui.div {
			w = d,
			h = d,
			rounded = T.radius_full,
			bg = if rest then T.clear else STATUS_COLOR[s],
			border = if rest then math.max(1, d / 6) else 0,
			border_color = T.tertiary,
			-- Only a working dot asks for frames.
			opacity = if s == "working" and motion.loops()
				then ui.loop { from = 0.5, to = 1, duration = 1200, fps = 30 }
				else 1,
		}
	end, {
		w = d,
		h = d,
		shrink = 0,
		enter = { scale = { 0.6, 1 }, opacity = { 0, 1 }, duration = 180, ease = "outBack(1.6)" },
		exit = { scale = 0.6, opacity = 0, duration = 100 },
	})
end

local function initials(name: string): string
	local out = ""
	for word in name:gmatch("%S+") do
		out ..= word:sub(1, 1):upper()
		if #out == 2 then
			break
		end
	end
	return out
end

M.avatar = ui.component(function(props: Props): Node
	local size = props.size or 28
	-- A squared face's corner scales with it.
	local radius: Num? = if props.square
		then ui.raw(math.floor(size * 0.3), "a squared avatar's corner, scaled with it")
		else nil
	local face: Node
	if props.src then
		face = ui.image { src = props.src, w = size, h = size, rounded = radius or T.radius_full, fit = "cover" }
	elseif props.icon then
		face = ui.row {
			variants = recipes.avatar,
			w = size,
			h = size,
			rounded = radius,
			icon { name = props.icon, size = math.floor(size * 0.55), color = "currentColor" },
		}
	else
		face = ui.row {
			variants = recipes.avatar,
			w = size,
			h = size,
			rounded = radius,
			txt.text {
				initials(props.name),
				size = if size <= 20 then "micro" elseif size <= 28 then "xs" elseif size <= 36 then "sm" else "md",
				weight = "semibold",
				color = "inherit",
				line = false,
			},
		}
	end
	if props.status == nil then
		return face
	end
	local dot = math.max(8, math.floor(size * 0.32))
	return ui.overlay {
		id = props.id,
		w = size,
		h = size,
		shrink = 0,
		items = "end",
		justify = "end",
		face,
		ui.div {
			variants = recipes.avatar_ring,
			w = dot,
			h = dot,
			bg = props.surface,
			M.status_dot(props.status, dot - 4),
		},
	}
end)

return M
