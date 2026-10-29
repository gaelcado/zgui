-- A badge: a count or a status word at the smallest size, never
-- interactive. A number alone is a round count.
local chip = require("./chip")

export type Props = {
	id: string?,
	label: Text,
	tone: chip.Tone?,
	variant: chip.Variant?,
	dot: boolean?,
	mono: boolean?,
}

return ui.component(function(props: Props): Node
	return chip {
		id = props.id,
		label = props.label,
		tone = props.tone,
		variant = props.variant,
		dot = props.dot,
		mono = props.mono,
		size = "xs",
	}
end)
