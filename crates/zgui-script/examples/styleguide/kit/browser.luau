-- The browser pane's chrome (browser/view.rs, shell.rs): the 38 toolbar
-- with back, forward, reload, the address field (a 12 globe, the text at
-- 11.5, a Go button when edited) and open-in-browser; 112-wide tab chips
-- of 24 with a favicon slot and a close slot whose dot swaps for an ×
-- under the pointer; the empty state with its 44 tile.
local T = require("../theme")
local wash = require("./wash")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")
local chrome = require("./chrome")
local loaders = require("./loaders")
local motion = require("./motion")
local button = require("./button")

export type AddressProps = { id: string?, value: State<string>, editing: types.Cond?, invalid: boolean?, w: Length? }
export type ToolbarProps = {
	id: string?,
	value: State<string>,
	can_back: boolean?,
	can_forward: boolean?,
	invalid: boolean?,
}
export type TabProps = {
	id: string?,
	title: string,
	icon: icon_mod.Name?,
	-- A favicon stands in as a tinted letter tile.
	letter: string?,
	tint: Color?,
	loading: boolean?,
	selected: types.Cond?,
	-- A dot instead of the × until hovered (a background tab with news).
	dot: boolean?,
	on_click: (Handler | Action)?,
	on_close: Handler?,
	-- The strip's glide group: its one wash comes to the tab under the
	-- pointer.
	group: string?,
}
export type EmptyProps = {
	id: string?,
	icon: icon_mod.Name?,
	title: string,
	body: string,
	action: string?,
	hint: string?,
}

local M = {}

M.TAB_W = 112
M.TAB_H = 24

M.address = ui.component(function(props: AddressProps): Node
	return ui.row {
		id = props.id and `{props.id}_frame`,
		h = chrome.CONTROL,
		w = props.w,
		grow = if props.w then nil else 1,
		shrink = 1,
		min_w = 80,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = T.ink1,
		border = 1,
		border_color = if props.invalid then T.danger else T.clear,
		icon { name = "global", size = 12, color = T.tertiary },
		ui.input {
			id = props.id,
			value = props.value,
			label = "Address",
			placeholder = "Enter an address",
			placeholder_color = T.tertiary,
			grow = 1,
			shrink = 1,
			min_w = 0,
			h = 16,
			px = 0,
			py = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			font = T.sans,
			text_size = "$font.size.xs",
			color = T.text,
			focus = { border = 0 },
		},
		ui.presence(function()
			return if types.on(props.editing) then "go" else nil
		end, function(): Node
			return ui.button {
				w = 18,
				h = 18,
				p = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.4",
				bg = T.clear,
				hover = { bg = T.ink4 },
				focus = { border = 0 },
				cursor = "pointer",
				icon { name = "return", size = 12, color = T.secondary },
			}
		end, {
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
			exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
		}),
	}
end)

M.toolbar = ui.component(function(props: ToolbarProps): Node
	return chrome.toolbar {
		id = props.id,
		chrome.control { icon = "arrow-left", disabled = props.can_back == false },
		chrome.control { icon = "arrow-right", disabled = props.can_forward == false },
		chrome.control { icon = "refresh" },
		M.address { id = props.id and `{props.id}_address`, value = props.value, invalid = props.invalid },
		chrome.control { icon = "arrow-up-right" },
	}
end)

-- A tab chip: 112×24, the 18 leading slot, the title at 11.5, the 18
-- close slot.
M.tab = ui.component(function(props: TabProps): Node
	local function on(): boolean
		return types.on(props.selected)
	end
	local lead: Node
	if props.loading then
		lead = loaders.mini_spinner { cell = 2 }
	elseif props.letter then
		lead = ui.row {
			w = 12,
			h = 12,
			rounded = "$zeron.radius.3",
			bg = props.tint or T.ink4,
			items = "center",
			justify = "center",
			txt.text { props.letter, size = "micro", weight = "semibold", color = T.on_solid, line = false },
		}
	else
		lead = icon {
			name = props.icon or "globe",
			size = 12,
			color = T.secondary,
			variants = recipes.browser_tab_icon { selected = on },
		}
	end
	-- In a strip's group the strip's wash is the hover.
	local function chip(node: ContainerProps): ContainerProps
		if props.group then
			return wash.item(props.group, node, on)
		end
		return node
	end
	return ui.button(chip {
		variants = recipes.browser_tab { selected = on, listed = props.group ~= nil },
		-- The close button shows while the pointer is over the tab.
		hover_group = true,
		id = props.id,
		w = M.TAB_W,
		h = M.TAB_H,
		pl = "$zeron.space.3",
		pr = "$zeron.space.3",
		gap = "$zeron.space.4",
		items = "center",
		rounded = T.radius_md,
		cursor = "pointer",
		focus = { border = 0 },
		on_click = props.on_click,
		ui.row { w = 18, h = 18, items = "center", justify = "center", shrink = 0, lead },
		txt.text {
			props.title,
			size = "xs",
			truncate = true,
			line = false,
			grow = 1,
			shrink = 1,
			min_w = 0,
			color = "inherit",
		},
		ui.button {
			w = 18,
			h = 18,
			p = 0,
			relative = true,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.4",
			shrink = 0,
			bg = T.clear,
			hover = { bg = T.ink4 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = props.on_close,
			ui.div {
				absolute = true,
				w = 6,
				h = 6,
				rounded = "$zeron.radius.3",
				bg = T.secondary,
				opacity = if props.dot then 1 else 0,
				group_hover = { opacity = 0 },
			},
			ui.div {
				opacity = 0,
				group_hover = { opacity = 1 },
				icon { name = "close", size = 12, color = T.secondary },
			},
		},
	})
end)

M.empty = ui.component(function(props: EmptyProps): Node
	return ui.column {
		id = props.id,
		p = "$zeron.space.24",
		max_w = 300,
		gap = "$zeron.space.12",
		items = "center",
		ui.row {
			w = 44,
			h = 44,
			items = "center",
			justify = "center",
			rounded = T.radius_card,
			border = 1,
			border_color = T.border,
			bg = T.ink2,
			icon { name = props.icon or "globe", size = 22, color = T.secondary },
		},
		txt.text { props.title, size = "lg", align = "center" },
		txt.text { props.body, size = "sm", color = T.secondary, wrap = true, align = "center" },
		props.action and button { label = props.action, size = "sm", variant = "secondary" },
		props.hint and txt.text { props.hint, size = "micro", color = T.tertiary },
	}
end)

return M
