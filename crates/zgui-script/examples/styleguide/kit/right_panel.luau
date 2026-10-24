-- Zeron's right pane's content (shell.rs, tabs.rs): a strip of 112×24 tab
-- chips that rides in the titlebar over the pane, the active surface (file,
-- browser, diff, terminal, subagent, side chat) cross-fading as tabs
-- change, and the picker shown when no tab is open. The pane's column (its
-- width, its seam, how it opens, splits and takes over) is the panel
-- shell's, under Zeron's panel policy: see panel_shell.luau.
local T = require("../theme")
local wash = require("./wash")
local motion = require("./motion")
local browser = require("./browser")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")

export type Tab = {
	id: string,
	title: string,
	icon: icon_mod.Name?,
	letter: string?,
	tint: Color?,
	loading: boolean?,
	dot: boolean?,
}
export type Props = {
	id: string?,
	tabs: { Tab },
	active: State<string>,
	on_close_tab: ((id: string) -> ())?,
	on_add: (Handler | Action)?,
	-- What the active tab shows.
	render: (id: string) -> Node,
}

local M = {}

-- The tab strip for the titlebar row: chips 4 apart, a 24 + at the end.
M.strip = ui.component(function(props: Props): Node
	local chips: { Node } = {}
	local group = wash.group("strip")
	for _, t in props.tabs do
		table.insert(
			chips,
			browser.tab {
				group = group,
				id = props.id and `{props.id}_tab_{t.id}`,
				title = t.title,
				icon = t.icon,
				letter = t.letter,
				tint = t.tint,
				loading = t.loading,
				dot = t.dot,
				selected = function()
					return props.active:get() == t.id
				end,
				on_click = ui.set(props.active, t.id),
				on_close = if props.on_close_tab
					then function()
						(props.on_close_tab :: (string) -> ())(t.id)
					end
					else nil,
			}
		)
	end
	return ui.row {
		gap = "$zeron.space.4",
		items = "center",
		wash.list { group = group, direction = "row", gap = "$zeron.space.4", color = T.ink3, chips },
		ui.button {
			variants = recipes.wash { hover = "ink4" },
			id = props.id and `{props.id}_add`,
			w = 24,
			h = 24,
			p = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_add,
			icon { name = "plus", size = 13, color = T.secondary },
		},
	}
end)

-- The active surface, filling the pane, cross-fading as tabs change.
M.surface = ui.component(function(props: Props): Node
	return ui.presence(props.active, function(id: string): Node
		return props.render(id)
	end, {
		id = props.id,
		w_full = true,
		h_full = true,
		items = "stretch",
		enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
		exit = { opacity = 0, duration = motion.d(80) },
	})
end)

-- With no tab open: a picker of 44-high rows.
export type PickProps = {
	id: string?,
	items: { { id: string, label: string, icon: icon_mod.Name } },
	on_pick: ((id: string) -> ())?,
}
M.picker = ui.component(function(props: PickProps): Node
	local group = wash.group("picker")
	local rows: { Node } = {}
	for _, it in props.items do
		table.insert(
			rows,
			ui.button(wash.item(group, {
				id = props.id and `{props.id}_{it.id}`,
				w_full = true,
				h = 44,
				px = "$zeron.space.12",
				gap = "$zeron.space.10",
				items = "center",
				rounded = T.radius_lg,
				cursor = "pointer",
				focus = { border = 0 },
				on_click = if props.on_pick
					then function()
						(props.on_pick :: (string) -> ())(it.id)
					end
					else nil,
				icon { name = it.icon, size = 16, color = T.secondary },
				txt.text { it.label, size = "md", line = false },
			}))
		)
	end
	return wash.list { group = group, p = "$zeron.space.8", gap = "$zeron.space.2", rows }
end)

return M
