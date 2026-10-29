-- The composer's access chip (pickers.rs access_chip): beside the model
-- chip, the mode the agent runs with ("Supervised", "Auto-accept edits",
-- "Full access"), brighter while it is anything but full access, "Plan"
-- after it in the accent while plan mode is on. Its card opens above it,
-- end-aligned: the modes the harness honors, each with what it allows and
-- a check on the one in use; an agent with one mode says it can't ask
-- before acting; then, where the harness has one, the Plan mode switch.
local T = require("../theme")
local txt = require("./text")
local menu = require("./menu")
local recipes = require("./recipes")
local popover = require("./popover")

export type Mode = "supervised" | "auto_accept_edits" | "full_access"
export type Props = {
	id: string,
	mode: State<Mode>,
	-- What the harness honors, least to most trusting (all unless set).
	modes: { Mode }?,
	-- Plan mode, where the harness has it.
	plan: State<boolean>?,
	-- The agent's name, for a single mode's note ("Cursor can't ask…").
	agent: string?,
}

local M = {}

M.LABEL = {
	supervised = "Supervised",
	auto_accept_edits = "Auto-accept edits",
	full_access = "Full access",
} :: { [Mode]: string }
M.DESCRIPTION = {
	supervised = "Ask before commands and file changes.",
	auto_accept_edits = "Apply edits, ask before other actions.",
	full_access = "Run commands and edits without asking.",
} :: { [Mode]: string }
local ALL: { Mode } = { "supervised", "auto_accept_edits", "full_access" }

M.chip = ui.component(function(props: Props): Node
	local open = ui.use_state(false)
	local modes = props.modes or ALL
	local plan = props.plan
	local items: { menu.Entry } = {}
	for _, m in modes do
		table.insert(
			items,
			{
				id = `{props.id}_{m}`,
				label = M.LABEL[m],
				description = M.DESCRIPTION[m],
				h = 44,
				checked = function()
					return props.mode:get() == m
				end,
				on_click = function()
					props.mode:set(m)
				end,
			} :: menu.Item
		)
	end
	if #modes == 1 then
		local only = string.lower(M.LABEL[modes[1]])
		table.insert(
			items,
			{ note = `{props.agent or "This agent"} can't ask before acting, so it always runs with {only}.` }
		)
	end
	if plan then
		table.insert(items, "-" :: menu.Entry)
		table.insert(
			items,
			{
				id = `{props.id}_plan`,
				label = "Plan mode",
				description = "Explore and propose a plan before changing anything.",
				h = 44,
				toggle = plan,
				keep_open = true,
			} :: menu.Item
		)
	end
	return menu.menu {
		id = `{props.id}_menu`,
		open = open,
		label = "Access",
		w = 280,
		placement = popover.ABOVE_END,
		checks = "end",
		items = items,
		anchor = ui.button {
			id = props.id,
			label = "Access",
			h = 32,
			px = "$zeron.space.10",
			gap = "$zeron.space.6",
			items = "center",
			shrink = 0,
			rounded = T.radius_button,
			variants = recipes.wash { hover = "hover" },
			cursor = "pointer",
			focus = { border = 0 },
			on_click = ui.toggle(open),
			txt.text {
				function()
					return M.LABEL[props.mode:get()]
				end,
				size = "sm",
				weight = "medium",
				color = function(): Color
					return if props.mode:get() == "full_access" then T.secondary else T.text
				end,
				line = false,
			},
			plan and ui.show(plan, txt.text { "Plan", size = "sm", weight = "medium", color = T.accent, line = false })
				or nil,
		},
	}
end)

return M
