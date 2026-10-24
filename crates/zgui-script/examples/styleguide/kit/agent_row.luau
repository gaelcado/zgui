-- An agent in the sidebar (zterm's agents list): its program's glyph, what
-- it works on, how long ago, and its status as a mark before its words: an
-- arc turning while it works, a dot when it needs you (amber) or failed
-- (red), a check when it finished unseen, a hollow ring at rest.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local glass = require("./glass")
local wash = require("./wash")
local motion = require("./motion")

export type Status = "working" | "blocked" | "error" | "done" | "idle"
export type Agent = {
	id: string,
	name: string,
	-- "zgui @ MacBook Pro"
	where: string,
	status: Status,
	-- What a blocked agent waits for.
	waits: ("permission" | "question" | "auth")?,
	icon: icon_mod.Name?,
	tint: Color?,
	ago: string,
}
export type Props = {
	id: string?,
	agent: () -> Agent,
	selected: () -> boolean,
	group: string?,
	on_click: (Handler | Action)?,
}

local SAYS: { [Status]: string } =
	{ working = "Working", blocked = "Needs you", error = "Failed", done = "Done", idle = "Idle" }
local WAITS = { permission = "Needs permission", question = "Has a question", auth = "Needs a login" }

local M = {}

-- The status mark, cross-fading as the status changes.
function M.mark(status: () -> Status): Node
	local function arc(): Node
		return ui.div {
			w = 10,
			h = 10,
			relative = true,
			rounded = "$zeron.radius.5",
			border = 1.5,
			border_color = T.ink5,
			ui.div {
				absolute = true,
				left = -1.5,
				top = -1.5,
				w = 10,
				h = 10,
				rounded = "$zeron.radius.5",
				border_over = true,
				border = 1.5,
				border_color = T.accent,
				clip_inset = { 0, 0, 5, 5 },
				on_mount = function(el: Element)
					if not motion.loops() then
						return
					end
					anime.animate(el, { rotate = 360, duration = 900, ease = "linear", loop = true, frameRate = 30 })
				end,
			},
		}
	end
	local function dot(color: Color): Node
		return ui.div { w = 6, h = 6, rounded = "$zeron.radius.3", bg = color }
	end
	return ui.presence(status, function(s: Status): Node
		return ui.overlay {
			w = 10,
			h = 10,
			items = "center",
			justify = "center",
			if s == "working"
				then arc()
				elseif s == "blocked" then dot(T.warning)
				elseif s == "error" then dot(T.danger)
				elseif s == "done" then icon { name = "check", size = 11, color = T.secondary }
				else ui.div { w = 6, h = 6, rounded = "$zeron.radius.3", border = 1.25, border_color = T.tertiary },
		}
	end, {
		w = 10,
		h = 10,
		shrink = 0,
		enter = { opacity = { 0, 1 }, scale = { 0.6, 1 }, duration = motion.d(220), ease = "outBack(1.6)" },
		exit = { opacity = 0, scale = 0.6, duration = motion.d(120), ease = "inQuad" },
	})
end

M.row = ui.component(function(props: Props): Node
	local ref = ui.ref()
	-- The wash under the pointer (instant, kit/wash), the selection's fill.
	local hover_layer = wash.layer(props.selected, T.radius(8))
	local active = if props.group
		then wash.selection(props.selected, T.radius(8), T.glass_active)
		else glass.active("agent-active", props.selected, 8)
	local press, release = glass.press(ref)
	local function status(): Status
		return props.agent().status
	end
	return ui.button {
		id = props.id,
		ref = ref,
		relative = true,
		w_full = true,
		px = "$zeron.space.10",
		py = "$zeron.space.7",
		gap = "$zeron.space.10",
		rounded = T.radius_button,
		items = "center",
		shrink = 0,
		bg = T.clear,
		hover = { bg = T.clear },
		active = { bg = T.clear },
		focus = { border = 0 },
		cursor = "pointer",
		hover_group = true,
		on_press = press,
		on_release = release,
		on_click = props.on_click,
		hover_layer,
		active,
		ui.overlay {
			w = 18,
			h = 18,
			shrink = 0,
			items = "center",
			justify = "center",
			icon {
				name = props.agent().icon or "bot",
				size = 16,
				color = props.agent().tint or T.secondary,
			},
		},
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.3",
			items = "stretch",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				txt.text {
					function()
						local a = props.agent()
						return if a.name ~= "" then a.name else a.where
					end,
					size = "md",
					weight = "medium",
					truncate = true,
					grow = 1,
					shrink = 1,
					min_w = 0,
					line = false,
				},
				txt.text {
					function()
						return props.agent().ago
					end,
					size = "xs",
					color = T.tertiary,
					tabular = true,
					shrink = 0,
					line = false,
				},
			},
			ui.row {
				gap = "$zeron.space.6",
				items = "center",
				M.mark(status),
				txt.text {
					function()
						local a = props.agent()
						local says = if a.status == "blocked"
							then WAITS[a.waits or ""] or SAYS.blocked
							else SAYS[a.status]
						return if a.where ~= "" then `{says} · {a.where}` else says
					end,
					size = "xs",
					color = "inherit",
					variants = recipes.agent_status {
						blocked = function()
							return status() == "blocked"
						end,
					},
					truncate = true,
					shrink = 1,
					min_w = 0,
					line = false,
				},
			},
		},
	}
end)

return M
