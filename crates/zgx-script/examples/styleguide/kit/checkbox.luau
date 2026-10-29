-- A checkbox: a 16-point box that fills with the accent when checked, with
-- a label beside it; the whole row is the hit area. Space and Enter toggle
-- it. `indeterminate` shows a dash for a group partly checked. Focus rings
-- the box, not the row (a dialog focuses its first control on opening).
local T = require("../theme")
local types = require("./types")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	value: State<boolean>,
	label: Text?,
	description: Text?,
	indeterminate: types.Cond?,
	disabled: types.Cond?,
	on_change: ((checked: boolean) -> ())?,
}

return ui.component(function(props: Props): Node
	local focused = ui.use_state(false)
	local function on(): boolean
		return props.value:get() or types.on(props.indeterminate)
	end
	local box = ui.overlay {
		variants = recipes.checkbox_box {
			on = on,
			-- The row's focus rings the box, not the row.
			focused = function()
				return focused:get()
			end,
			lines = if props.description then "two" else "one",
		},
		ui.presence(function()
			return if types.on(props.indeterminate) then "dash" elseif props.value:get() then "check" else nil
		end, function(kind: string): Node
			return icon { name = if kind == "dash" then "stop" else "check", size = 12, color = T.on_solid }
		end, {
			w = 12,
			h = 12,
			enter = { scale = { 0.5, 1 }, opacity = { 0, 1 }, duration = motion.d(motion.FAST), ease = "outBack(1.5)" },
			exit = { scale = 0.5, opacity = 0, duration = motion.d(motion.MENU_OUT) },
		}),
	}
	return ui.button {
		id = props.id,
		-- Heard as a checkbox, checked or not.
		role = "checkbox",
		checked = props.value,
		variants = recipes.checkbox_row { lines = if props.description then "two" else "one" },
		on_focus = function()
			focused:set(true)
		end,
		on_blur = function()
			focused:set(false)
		end,
		disabled = props.disabled,
		on_click = function()
			local next = not props.value:peek()
			props.value:set(next)
			if props.on_change then
				props.on_change(next)
			end
		end,
		box,
		props.label and ui.column {
			gap = "$zeron.space.1",
			txt.text { props.label, size = "md", line = props.description == nil },
			props.description and txt.text { props.description, size = "sm", color = T.secondary },
		},
	}
end)
