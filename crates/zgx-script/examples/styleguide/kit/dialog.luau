-- A dialog: a title, what it asks, the caller's content and its actions at
-- the end, centred over a scrim. Escape and a click outside close it; Enter
-- runs the primary action when the dialog asks for that.
local T = require("../theme")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	open: State<boolean>,
	title: string,
	-- Its words (a function of state: what it asks about now).
	description: Text?,
	[number]: Child,
	-- Buttons, laid out at the end; the last is the primary.
	actions: { Node }?,
	w: Length?,
	-- Shown in the flow instead of floating, for specimens.
	inline: boolean?,
	-- Enter runs this (a primary action's handler).
	on_enter: Handler?,
}

return ui.component(function(props: Props): Node
	local body: ContainerProps = {
		id = props.id,
		variants = recipes.dialog,
		w = props.w,
		on_key = function(e: KeyEvent): boolean
			if e.key == "Enter" and props.on_enter then
				props.on_enter()
				return true
			end
			return false
		end,
		txt.text { props.title, size = "xl", weight = "semibold" },
		props.description and txt.text { props.description, size = "md", color = T.secondary, wrap = true },
		#props > 0 and ui.column { mt = "$zeron.space.10", gap = "$zeron.space.10", { table.unpack(props) } },
		props.actions
			and ui.row { w_full = true, mt = "$zeron.space.16", gap = "$zeron.space.8", justify = "end", props.actions },
	}
	if props.inline then
		return ui.column(body)
	end
	return ui.modal {
		id = props.id,
		open = props.open,
		label = props.title,
		variants = recipes.dialog,
		w = props.w,
		on_key = body.on_key,
		-- Every opening plays the entrance (motion.rs dialog_in).
		enter = {
			opacity = { 0, 1 },
			y = { 6, 0 },
			scale = { 0.98, 1 },
			duration = motion.d(motion.DIALOG_IN),
			ease = motion.EASE,
		},
		txt.text { props.title, size = "xl", weight = "semibold" },
		props.description and txt.text { props.description, size = "md", color = T.secondary, wrap = true },
		#props > 0 and ui.column { mt = "$zeron.space.10", gap = "$zeron.space.10", { table.unpack(props) } },
		props.actions
			and ui.row { w_full = true, mt = "$zeron.space.16", gap = "$zeron.space.8", justify = "end", props.actions },
	}
end)
