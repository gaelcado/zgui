-- Zeron's right pane's content (shell.rs, tabs.rs): a strip of 112×24 tab
-- chips (zgx's tabs) that rides in the titlebar over the pane, the active surface (file,
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
local types = require("./types")
local menus = require("./menu")

export type Tab = {
	id: string,
	-- A function follows what it reads (a page's title).
	title: Text,
	icon: icon_mod.Name?,
	-- A file's path: its own icon.
	file: string?,
	-- A page's favicon, "" while it has none.
	favicon: (() -> string)?,
	letter: string?,
	tint: Color?,
	loading: types.Cond?,
	dot: boolean?,
}
export type Props = {
	id: string?,
	-- The open tabs (each with its `id`), and how each shows.
	items: State<{ any }>,
	look: (item: any) -> Tab,
	active: State<string>,
	-- A tab closed: the app's to remove, choosing the next.
	on_close_tab: ((id: string) -> ())?,
	on_add: (Handler | Action)?,
	-- A tab's secondary click: its menu's items.
	menu: ((id: string) -> { Node })?,
	-- Tabs drag along the strip (a copy following the pointer).
	reorderable: boolean?,
}
export type SurfaceProps = {
	id: string?,
	active: State<string>,
	-- What the active tab shows.
	render: (id: string) -> Node,
}

local M = {}

-- A title as it reads now (a function's, what it returns).
local function said(title: Text): string
	if type(title) == "function" then
		return tostring((title :: () -> any)() or "")
	end
	return tostring(title)
end

-- A tab lifted off the strip (SurfaceTabGhost): its title on a raised
-- chip as wide as a tab, slightly see-through.
local function ghost(title: string): Node
	return ui.row {
		w = browser.TAB_W,
		h = browser.TAB_H,
		px = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.6",
		bg = T.raised,
		border = 1,
		border_color = T.strong,
		opacity = 0.85,
		txt.text { title, literal = true, size = "xs", line = false, truncate = true, min_w = 0 },
	}
end

-- The tab strip for the titlebar row, on zgx's tabs (`ui.tabs`: one Tab
-- stop, the arrows choose, Delete closes; too many scroll, with a menu of
-- them all): chips 4 apart, each washing under the pointer, a 24 + at the
-- end (with `on_add`).
M.strip = ui.component(function(props: Props): Node
	local group = wash.group("strip")
	local on_close = props.on_close_tab
	local dragging = ui.use_state("")
	local menu = props.menu
	return ui.row {
		gap = "$zeron.space.4",
		items = "center",
		min_w = 0,
		-- In a narrow pane the strip keeps one chip, scrolling to the chosen.
		wash.list {
			group = group,
			direction = "row",
			shrink = 1,
			min_w = browser.TAB_W,
			color = T.ink3,
			ui.tabs {
				id = props.id and `{props.id}_tabs`,
				label = "Open tabs",
				items = props.items,
				value = props.active,
				gap = "$zeron.space.4",
				shrink = 1,
				min_w = browser.TAB_W,
				closable = on_close ~= nil,
				reorderable = props.reorderable,
				dragging = dragging,
				preview = function(item: any): Node
					return ghost(said(props.look(item).title))
				end,
				on_close = if on_close
					then function(id: string): boolean
						on_close(id)
						return false
					end
					else nil,
				tab = function(item: any, close: () -> ()): Node
					local t = props.look(item)
					return browser.chip {
						group = group,
						id = props.id and `{props.id}_tab_{t.id}`,
						-- The tab's own title as the items change it.
						title = function(): string
							for _, it in props.items:get() do
								if it.id == t.id then
									return said(props.look(it).title)
								end
							end
							return said(t.title)
						end,
						icon = t.icon,
						file = t.file,
						favicon = t.favicon,
						letter = t.letter,
						tint = t.tint,
						loading = t.loading,
						dot = t.dot,
						selected = function()
							return props.active:get() == t.id
						end,
						on_close = close,
						menu = if menu
							then function(): { Node }?
								return (menu :: (string) -> { Node })(t.id)
							end
							else nil,
						menu_style = if menu then menus.CARD :: any else nil,
						lifted = function(): boolean
							return dragging:get() == t.id
						end,
					}
				end,
			},
		},
		props.on_add and ui.button {
			variants = recipes.wash { hover = "ink4" },
			id = props.id and `{props.id}_add`,
			w = 24,
			h = 24,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_add,
			icon { name = "plus", size = 13, color = T.secondary },
		} or nil,
	}
end)

-- The active surface, filling the pane, cross-fading as tabs change.
M.surface = ui.component(function(props: SurfaceProps): Node
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
