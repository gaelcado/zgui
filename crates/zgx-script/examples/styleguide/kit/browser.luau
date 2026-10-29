-- The browser pane's chrome (browser/view.rs, shell.rs): the 38 toolbar
-- with back, forward, reload, the address field (a 12 globe, the text at
-- 11.5, a Go button while edited) and open-in-browser; 112-wide tab chips
-- of 24 with a favicon slot and a close slot whose dot swaps for an ×
-- under the pointer; the dev servers a new tab offers (rows 56); the empty
-- and error states with their 44 tile.
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

export type AddressProps = {
	id: string?,
	value: State<string>,
	editing: types.Cond?,
	invalid: types.Cond?,
	w: Length?,
	ref: Ref?,
	-- Enter and Escape in the field (true: handled).
	on_key: ((e: KeyEvent) -> boolean?)?,
	on_focus: Handler?,
	on_blur: Handler?,
	-- Focused as it mounts (a new tab).
	autofocus: boolean?,
	on_go: Handler?,
}
export type ToolbarProps = {
	id: string?,
	value: State<string>,
	can_back: types.Cond?,
	can_forward: types.Cond?,
	-- A page is open: reload and open-in-browser act.
	has_page: types.Cond?,
	invalid: types.Cond?,
	editing: types.Cond?,
	-- No embedded pages here: an address opens in the system's browser, so
	-- there is no back, forward or reload.
	external: boolean?,
	address_ref: Ref?,
	autofocus: boolean?,
	on_key: ((e: KeyEvent) -> boolean?)?,
	on_focus: Handler?,
	on_blur: Handler?,
	on_go: Handler?,
	on_back: Handler?,
	on_forward: Handler?,
	on_reload: Handler?,
	on_open: Handler?,
	-- Annotate an element (embedded pages only): picking while
	-- `annotating`, inert without a loaded page.
	annotating: types.Cond?,
	can_annotate: types.Cond?,
	on_annotate: Handler?,
}
export type TabProps = {
	id: string?,
	-- It may follow what the tab shows (a side chat titling itself).
	title: Text,
	icon: icon_mod.Name?,
	-- A file's tab: its own icon (kit/file_icon) for `icon`.
	file: string?,
	-- The page's favicon ("" while it has none: the icon stands in).
	favicon: (() -> string)?,
	-- A favicon stands in as a tinted letter tile.
	letter: string?,
	tint: Color?,
	loading: types.Cond?,
	selected: types.Cond?,
	-- A dot instead of the × until hovered (a background tab with news).
	dot: boolean?,
	on_click: (Handler | Action)?,
	on_close: Handler?,
	-- The strip's glide group: its one wash comes to the tab under the
	-- pointer.
	group: string?,
	-- Its secondary click's menu, in `menu_style`.
	menu: ((e: PointerEvent) -> { Node }?)?,
	menu_style: Styles?,
	-- Dragged away: its place stays, empty (the pointer carries a copy).
	lifted: (() -> boolean)?,
}
export type EmptyProps = {
	id: string?,
	icon: icon_mod.Name?,
	title: Text,
	body: Text,
	action: string?,
	action_id: string?,
	-- The action's keys, faint after its label ("⌘L").
	hint: string?,
	on_action: Handler?,
}
export type Service = { id: string, name: string, port: number, url: string, device: string? }
export type PreviewsProps = {
	id: string?,
	services: { Service },
	-- On another device: the rows say which, and so does the heading.
	remote: boolean?,
	loading: boolean?,
	on_open: ((url: string) -> ())?,
	on_address: Handler?,
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
		border_color = function()
			return if types.on(props.invalid) then T.danger else T.clear
		end,
		icon { name = "global", size = 12, color = T.tertiary },
		ui.input {
			id = props.id,
			ref = props.ref,
			value = props.value,
			label = "Address",
			placeholder = "Website or localhost:3000",
			placeholder_color = T.tertiary,
			select_on_focus = true,
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
			on_key = props.on_key,
			on_focus = props.on_focus,
			on_blur = props.on_blur,
			on_mount = if props.autofocus
				then function(el: Element)
					el:focus()
				end
				else nil,
		},
		ui.presence(function()
			return if types.on(props.editing) then "go" else nil
		end, function(): Node
			return ui.button {
				id = props.id and `{props.id}_go`,
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
				label = "Go to address",
				tooltip = "Go to address",
				on_click = props.on_go,
				icon { name = "return", size = 12, color = T.secondary },
			}
		end, {
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.FAST) },
			exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
		}),
	}
end)

-- A control that acts while `enabled` (always, unless given).
local function dim(enabled: types.Cond?): types.Cond
	if enabled == nil then
		return false
	end
	return types.unless(enabled)
end

M.toolbar = ui.component(function(props: ToolbarProps): Node
	local id = props.id
	local function control(key: string, name: icon_mod.Name, label: string, enabled: types.Cond?, run: Handler?): Node
		return chrome.control {
			id = id and `{id}_{key}`,
			icon = name,
			label = label,
			disabled = dim(enabled),
			on_click = run,
		}
	end
	local inside = not props.external
	return chrome.toolbar {
		id = id,
		inside and control("back", "arrow-left", "Back", props.can_back, props.on_back) or nil,
		inside and control("forward", "arrow-right", "Forward", props.can_forward, props.on_forward) or nil,
		inside and control("reload", "refresh", "Reload page", props.has_page, props.on_reload) or nil,
		M.address {
			id = id and `{id}_address`,
			ref = props.address_ref,
			autofocus = props.autofocus,
			value = props.value,
			invalid = props.invalid,
			editing = props.editing,
			on_key = props.on_key,
			on_focus = props.on_focus,
			on_blur = props.on_blur,
			on_go = props.on_go,
		},
		inside and props.on_annotate and M.annotate(id, props.annotating, props.can_annotate, props.on_annotate) or nil,
		control("open", "arrow-up-right", "Open in default browser", props.has_page, props.on_open),
	}
end)

-- The toolbar's Annotate toggle (browser/view.rs): "Annotate an element",
-- "Stop annotating" while it picks.
function M.annotate(id: string?, on: types.Cond?, can: types.Cond?, run: Handler): Node
	return ui.presence(function()
		return if types.on(on) then "on" else "off"
	end, function(state: string): Node
		local picking = state == "on"
		local label = if picking then "Stop annotating" else "Annotate an element"
		return ui.button {
			id = id and `{id}_annotate`,
			variants = recipes.browser_annotate { on = picking, inert = dim(can) },
			w = chrome.CONTROL,
			h = chrome.CONTROL,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			disabled = dim(can),
			label = label,
			tooltip = label,
			on_click = run,
			icon { name = "cursor-square", size = chrome.ICON, color = "currentColor" },
		}
	end, { shrink = 0 })
end

-- A tab chip: 112×24, the 18 leading slot, the title at 11.5, the 18
-- close slot. `chip` is the node (a strip's tab dresses itself with it),
-- `tab` the component.
function M.chip(props: TabProps): Node
	local function on(): boolean
		return types.on(props.selected)
	end
	local idle: Node
	if props.file then
		idle = require("./file_icon").icon { path = props.file, size = 12 }
	elseif props.letter then
		idle = ui.row {
			w = 12,
			h = 12,
			rounded = "$zeron.radius.3",
			bg = props.tint or T.ink4,
			items = "center",
			justify = "center",
			txt.text { props.letter, size = "micro", weight = "semibold", color = T.on_solid, line = false },
		}
	else
		local function glyph(): Node
			return icon {
				name = props.icon or "globe",
				size = 12,
				color = T.secondary,
				variants = recipes.browser_tab_icon { selected = on },
			}
		end
		idle = glyph()
		-- The page's own icon once it has one; the glyph while it loads, or
		-- if it fails.
		local favicon = props.favicon
		if favicon then
			idle = ui.show(
				function()
					return favicon() ~= ""
				end,
				ui.image {
					id = props.id and `{props.id}_favicon`,
					src = favicon,
					w = 12,
					h = 12,
					rounded = "$zeron.radius.3",
					fallback = glyph(),
				},
				idle
			)
		end
	end
	-- Loading: the mono mini spinner centred in the favicon's 12.
	local lead = if props.loading == nil or props.loading == false
		then idle
		else ui.show(
			function()
				return types.on(props.loading)
			end,
			ui.row {
				w = 12,
				h = 12,
				shrink = 0,
				items = "center",
				justify = "center",
				loaders.mini_spinner { color = T.secondary },
			},
			idle
		)
	-- In a strip's group the strip's wash is the hover.
	local function chip(node: ContainerProps): ContainerProps
		if props.group then
			return wash.item(props.group, node, on)
		end
		return node
	end
	local lifted = props.lifted
	return ui.button(chip {
		variants = recipes.browser_tab { selected = on, listed = props.group ~= nil },
		-- The close button shows while the pointer is over the tab.
		hover_group = true,
		id = props.id,
		context_menu = props.menu,
		context_menu_style = props.menu_style,
		opacity = if lifted
			then function(): number
				return if lifted() then 0 else 1
			end
			else nil,
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
			-- Not a stop of its own: a strip's arrows go tab to tab.
			focusable = false,
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
end
M.tab = ui.component(M.chip)

-- The 28-high quiet buttons of the empty state and the dev servers.
local SMALL = chrome.HEIGHT - 10

M.empty = ui.component(function(props: EmptyProps): Node
	return ui.column {
		id = props.id,
		p = "$zeron.space.24",
		w_full = true,
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
		txt.text { props.title, size = "lg", weight = "medium", align = "center", mt = "$zeron.space.4" },
		txt.text { props.body, size = "sm", color = T.secondary, wrap = true, align = "center", line_height = 19 },
		props.action and ui.button {
			variants = recipes.wash { rest = "raised", hover = "ink4" },
			id = props.action_id,
			mt = "$zeron.space.6",
			h = SMALL,
			px = "$zeron.space.10",
			gap = "$zeron.space.8",
			items = "center",
			rounded = T.radius_md,
			border = 1,
			border_color = T.border,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = props.on_action,
			txt.text { props.action, size = "sm", line = false },
			props.hint and txt.text { props.hint, size = "micro", color = T.tertiary, line = false } or nil,
		} or nil,
	}
end)

-- A dev server a new tab offers (browser/view.rs preview_body): 56 high
-- at radius 10, its name over its address, Open at its end.
local function service(id: string?, s: Service, remote: boolean, open: ((url: string) -> ())?): Node
	local function go()
		if open then
			open(s.url)
		end
	end
	local where = if remote and s.device then `{s.device} · localhost:{s.port}` else `localhost:{s.port}`
	return ui.button {
		id = id and `{id}_{s.id}`,
		w_full = true,
		h = 56,
		px = "$zeron.space.14",
		gap = "$zeron.space.10",
		items = "center",
		rounded = "$zeron.radius.10",
		border = 1,
		border_color = T.border,
		bg = T.clear,
		hover = { bg = T.ink1, border_color = T.strong },
		cursor = "pointer",
		focus = { border = 0 },
		label = s.name,
		on_click = go,
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { s.name, literal = true, size = "md", weight = "medium", truncate = true, line = false },
			txt.text { where, literal = true, size = "xs", color = T.secondary, truncate = true, line = false },
		},
		ui.button {
			id = id and `{id}_{s.id}_open`,
			h = SMALL,
			px = "$zeron.space.6",
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = T.radius_md,
			bg = T.clear,
			hover = { bg = T.ink1 },
			focus = { border = 0 },
			cursor = "pointer",
			label = `Open {s.name} preview`,
			on_click = go,
			txt.text { "Open", size = "sm", color = T.secondary, line = false },
		},
	}
end

-- A new tab: the dev servers running for the project, or how to start
-- one, then a way to type an address instead.
M.previews = ui.component(function(props: PreviewsProps): Node
	local rows: { Node } = {}
	for _, s in props.services do
		table.insert(rows, service(props.id, s, props.remote == true, props.on_open))
	end
	local empty: Node? = nil
	if #props.services == 0 then
		local say = "Start a dev server in this project. It will appear here automatically, ready to open."
		if props.loading then
			say = "Looking for dev servers…"
		elseif props.remote then
			say =
				"Start a dev server in this project on your other device. Its preview will appear here when that device is online."
		end
		empty = ui.div {
			p = "$zeron.space.16",
			rounded = "$zeron.radius.8",
			border = 1,
			border_color = T.border,
			txt.text { say, literal = true, size = "sm", color = T.secondary, wrap = true, line_height = 19 },
		}
	end
	-- Centred while it fits, scrolling once it does not.
	return ui.column {
		id = props.id,
		grow = 1,
		min_h = 0,
		w_full = true,
		justify = "center",
		ui.scroll {
			w_full = true,
			shrink = 1,
			min_h = 0,
			p = "$zeron.space.16",
			items = "center",
			ui.column {
				w_full = true,
				max_w = 280,
				gap = "$zeron.space.8",
				txt.text {
					if props.remote then "Running on your device" else "Running locally",
					size = "sm",
					color = T.secondary,
					mb = "$zeron.space.4",
				},
				rows,
				empty,
				ui.button {
					id = props.id and `{props.id}_address`,
					mt = "$zeron.space.8",
					self = "start",
					p = 0,
					bg = T.clear,
					focus = { border = 0 },
					cursor = "pointer",
					label = "Enter a website address",
					on_click = props.on_address,
					txt.text { "Or enter a website address", size = "xs", color = T.secondary, line = false },
				},
			},
		},
	}
end)

return M
