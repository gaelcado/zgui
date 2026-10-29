-- A tooltip around any node: its label (and a shortcut) over or under the
-- node. zgx shows it (`tooltip`): after the pointer rests, at once while
-- another has just been showing, gone as the pointer leaves or a key is
-- pressed, placed where it fits. The kit gives it Zeron's look, a frosted
-- bubble (`recipes.tooltip`). `preview` draws one held open in place, for
-- specimens.
local txt = require("./text")
local kbd = require("./kbd")
local recipes = require("./recipes")

export type Props = {
	[number]: Child,
	label: Text,
	keys: { string }?,
	above: boolean?,
	id: string?,
	-- Shown open in place, for specimens.
	preview: boolean?,
}

local function bubble(props: Props): Node
	return ui.row {
		id = props.id and "tooltip_" .. props.id,
		variants = recipes.tooltip { keys = props.keys ~= nil },
		txt.text { props.label, size = "sm", line = false },
		props.keys and kbd(table.clone(props.keys) :: kbd.Props),
	}
end

return ui.component(function(props: Props): Node
	if props.preview then
		-- Held open: centred over or under the trigger, in its box.
		return ui.column {
			relative = true,
			items = "center",
			{ table.unpack(props) },
			ui.row {
				absolute = true,
				top = if props.above then nil else "100%",
				bottom = if props.above then "100%" else nil,
				mt = if props.above then nil else "$zeron.space.6",
				mb = if props.above then "$zeron.space.6" else nil,
				pointer_events = "none",
				bubble(props),
			},
		}
	end
	return ui.column {
		tooltip = bubble(props),
		tooltip_placement = { side = if props.above then "top" else "bottom", offset = 6 },
		{ table.unpack(props) },
	}
end)
