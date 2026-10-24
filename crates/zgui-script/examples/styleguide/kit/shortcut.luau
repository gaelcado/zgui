-- Keyboard shortcuts (settings/shortcuts): a card row with the action's
-- name, a "Reset" link when customised, and the key chip: at least 96
-- wide, 32 high, radius 8, mono 12, wash 6% (10% hovered); recording
-- shows "Press keys…" on the accent at 16% with a 55% accent border.
local types = require("./types")
local txt = require("./text")
local recipes = require("./recipes")
local settings = require("./settings")

export type ChipProps = { id: string?, keys: string, recording: types.Cond?, on_click: (Handler | Action)? }
export type RowProps = {
	id: string?,
	title: string,
	meta: { Text }?,
	keys: string,
	customised: boolean?,
	recording: types.Cond?,
	on_click: (Handler | Action)?,
	on_reset: Handler?,
}

local M = {}

M.chip = ui.component(function(props: ChipProps): Node
	local function rec(): boolean
		return types.on(props.recording)
	end
	return ui.button {
		id = props.id,
		variants = recipes.shortcut { recording = rec },
		on_click = props.on_click,
		txt.text {
			function()
				return if rec() then "Press keys…" else props.keys
			end,
			size = "sm",
			mono = true,
			line = false,
			color = "inherit",
		},
	}
end)

M.row = ui.component(function(props: RowProps): Node
	return settings.row {
		id = props.id,
		title = props.title,
		meta = props.meta,
		control = ui.row {
			gap = "$zeron.space.20",
			items = "center",
			props.customised and ui.button {
				variants = recipes.text_button,
				on_click = props.on_reset,
				txt.text { "Reset", size = "xs", color = "inherit", line = false },
			},
			M.chip {
				id = props.id and `{props.id}_chip`,
				keys = props.keys,
				recording = props.recording,
				on_click = props.on_click,
			},
		},
	}
end)

return M
