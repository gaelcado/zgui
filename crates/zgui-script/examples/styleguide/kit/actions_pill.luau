-- The project actions pill (shell/actions_ui.rs): a frosted split pill in
-- the titlebar, 24 high at radius 7; the run segment (13 icon, 11.5
-- medium label) then a 1×14 seam and a 22-wide chevron that opens the
-- menu of actions. Loading, unavailable and empty read in the segment.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")
local loaders = require("./loaders")

export type Kind = "play" | "test" | "lint" | "configure" | "build" | "debug"
export type State = "ready" | "loading" | "unavailable" | "empty"
export type Props = {
	id: string?,
	label: string?,
	kind: Kind?,
	state: State?,
	-- Hide the label (the titlebar is narrower than 420).
	compact: boolean?,
	on_run: (Handler | Action)?,
	on_menu: (Handler | Action)?,
}

local ICON: { [Kind]: icon_mod.Name } = {
	play = "action-play",
	test = "action-test",
	lint = "action-lint",
	configure = "action-configure",
	build = "action-build",
	debug = "action-debug",
}

local function segment(props: {
	[number]: Child,
	id: string?,
	kind: "run" | "chevron",
	w: number?,
	on_click: (Handler | Action)?,
	disabled: boolean?,
}): Node
	return ui.button {
		id = props.id,
		variants = recipes.actions_segment { kind = props.kind },
		w = props.w,
		disabled = props.disabled,
		on_click = props.on_click,
		{ table.unpack(props) },
	}
end

return ui.component(function(props: Props): Node
	local state = props.state or "ready"
	local lead: Node
	local label: string
	if state == "loading" then
		lead = loaders.mini_spinner { cell = 2 }
		label = "Loading…"
	elseif state == "unavailable" then
		lead = icon { name = "danger-triangle", size = 13, color = T.danger }
		label = "Actions unavailable"
	elseif state == "empty" then
		lead = icon { name = "plus", size = 13, color = T.secondary }
		label = "Add action"
	else
		lead = icon { name = ICON[(props.kind or "play") :: Kind], size = 13, color = T.text }
		label = props.label or "Run"
	end
	return ui.row {
		id = props.id,
		variants = recipes.actions_pill,
		segment {
			id = props.id and `{props.id}_run`,
			kind = "run",
			on_click = props.on_run,
			disabled = state == "unavailable",
			lead,
			not props.compact and txt.text {
				label,
				size = "xs",
				weight = "medium",
				line = false,
				truncate = true,
				max_w = 150,
				opacity = if state == "loading" then 0.45 else 1,
			},
		},
		ui.div { w = 1, h = 14, self = "center", bg = T.text, opacity = 0.14 },
		segment {
			id = props.id and `{props.id}_menu`,
			kind = "chevron",
			w = 22,
			on_click = props.on_menu,
			icon { name = "alt-arrow-down", size = 11, color = T.secondary },
		},
	}
end)
