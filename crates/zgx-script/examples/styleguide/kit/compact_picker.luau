-- The compact model picker (pickers/compact.rs): a 256 card with two
-- pages. The panel: a 48 header (the effort as the title, rolling as the
-- slider drags, over the model's name with a chevron that leans toward
-- the list on hover; a 32 fast-mode button whose bolt fills in accent),
-- the reasoning slider, then the model's other settings as 26 rows that
-- open their choices beside them. The models page: a back button with the
-- providers as a tab strip (starred first), a search row, and 32 rows (the
-- brand mark, the name at 12 medium, a star that shows on hover) of which
-- seven fit before the list scrolls. Pages swap with the card resizing
-- over 200 ms as the new page fades in; nothing slides sideways.
local T = require("../theme")
local wash = require("./wash")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")
local popover = require("./popover")
local frost = require("./frost")
local roll = require("./roll")
local menu = require("./menu")
local scroll = require("./scroll")
local effort_slider = require("./effort_slider")

export type Option = { id: string, label: string, choices: { string }, value: State<string> }
export type Model = {
	id: string,
	label: string,
	-- The provider's name and brand mark.
	harness: string,
	mark: icon_mod.Name,
	tint: Color?,
	-- The reasoning ladder, when the model has one.
	levels: { string }?,
	-- Whether the model offers fast mode.
	fast: boolean?,
	options: { Option }?,
}
export type Props = {
	id: string?,
	open: State<boolean>,
	anchor: Node?,
	-- Laid out where it is written, open, for specimens.
	inline: boolean?,
	models: { Model },
	-- The chosen model's id, its effort (1-based into its levels) and fast mode.
	model: State<string>,
	effort: State<number>,
	fast: State<boolean>,
	favorites: State<{ string }>,
	-- "panel" or "models"; the panel unless set.
	page: State<string>?,
	query: State<string>?,
	on_pick: ((model: Model) -> ())?,
}

local M = {}

M.WIDTH = 256
M.INSET = 4
-- Concentric corners: the card's 12, its rows 4 in (and inside its
-- hairline) at 7, a row's 24 star 4 in from the row's edge at 3.
M.RADIUS = 12
M.ROW_RADIUS = T.inset_radius(M.RADIUS, M.INSET, 1)
M.STAR_RADIUS = T.inset_radius(M.ROW_RADIUS, (32 - 24) / 2)
M.ROW = 32
M.GAP = 2
M.LIST_ROWS = 7
M.HEADER = 48
M.HEADER_SINGLE = 36
M.FAST_W = 32
M.OPTION_ROW = 26
M.OPTIONS_MAX = 6
M.PITCH = M.ROW + M.GAP

local function has(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

local function find_model(props: Props, id: string): Model?
	for _, m in props.models do
		if m.id == id then
			return m
		end
	end
	return nil
end

local function current(props: Props): Model
	return find_model(props, props.model:get()) or props.models[1]
end

-- The list's order: starred models first, then one run per provider in
-- the order providers appear.
local function ordered(props: Props): { Model }
	local favs = props.favorites:get()
	local out: { Model } = {}
	for _, m in props.models do
		if has(favs, m.id) then
			table.insert(out, m)
		end
	end
	for _, m in props.models do
		if not has(favs, m.id) then
			table.insert(out, m)
		end
	end
	return out
end

type Group = { key: string, label: string, mark: icon_mod.Name, tint: Color?, start: number }

-- Where each group starts in the ordered list (1-based).
local function groups(props: Props): { Group }
	local favs = props.favorites:get()
	local out: { Group } = {}
	for i, m in ordered(props) do
		local key = if has(favs, m.id) then "*" else m.harness
		local last = out[#out]
		if not last or last.key ~= key then
			table.insert(
				out,
				{
					key = key,
					label = if key == "*" then "Starred" else m.harness,
					mark = if key == "*" then "star-bold" else m.mark,
					tint = if key == "*" then nil else m.tint,
					start = i,
				} :: Group
			)
		end
	end
	return out
end

local function matches(m: Model, q: string): boolean
	if q == "" then
		return true
	end
	local needle = string.lower(q)
	return string.find(string.lower(m.label), needle, 1, true) ~= nil
		or string.find(string.lower(m.harness), needle, 1, true) ~= nil
end

M.picker = ui.component(function(props: Props): Node
	local id = props.id or "picker"
	local page = props.page or ui.state(`{id}_page`, "panel")
	local query = props.query or ui.state(`{id}_query`, "")
	local list_offset = ui.state(`{id}_list_offset`, 0)
	local active = ui.state(`{id}_active`, 0)
	local keyboard = ui.state(`{id}_keyboard`, false)
	local dragging = ui.state(`{id}_dragging`, false)
	local effort_label = ui.state(`{id}_effort_label`, "")
	local option_open: { [string]: State<boolean> } = {}
	-- Each list glides: one wash slides to the row under the pointer.
	local model_group = wash.group("models")
	local option_group = wash.group("options")
	local strip_group = wash.group("providers")
	-- The model whose star was just pressed, until its row's click lands.
	local starring: string? = nil

	local function levels(): { string }
		return current(props).levels or {}
	end
	ui.effect(function()
		local l = levels()
		local i = props.effort:get()
		effort_label:set(l[i] or "Default")
	end)

	local function close()
		props.open:set(false)
	end

	local function pick_model(m: Model)
		if m.id ~= props.model:peek() then
			props.model:set(m.id)
			local l = m.levels or {}
			if #l == 0 then
				props.effort:set(1)
			else
				props.effort:set(math.clamp(props.effort:peek(), 1, #l))
			end
			if props.on_pick then
				props.on_pick(m)
			end
		end
		page:set("panel")
	end

	local function toggle_favorite(m: Model)
		local favs = table.clone(props.favorites:peek())
		local at = table.find(favs, m.id)
		if at then
			table.remove(favs, at)
		else
			table.insert(favs, m.id)
		end
		props.favorites:set(favs)
	end

	local function show_models(delta: number?)
		local list = ordered(props)
		local sel = 1
		for i, m in list do
			if m.id == props.model:peek() then
				sel = i
			end
		end
		local next = math.clamp(sel + (delta or 0), 1, math.max(#list, 1))
		active:set(next)
		query:set("")
		-- Open on the current model's group at the top, one row of the
		-- previous group under the fade when the model sits near its start.
		local start = 1
		for _, g in groups(props) do
			if g.start <= sel then
				start = g.start
			end
		end
		if sel - start < M.LIST_ROWS - 2 then
			list_offset:set(math.max(start - 1 - (if start > 1 then 1 else 0), 0) * M.PITCH)
		else
			list_offset:set(math.max((sel - 1) * M.PITCH - (M.LIST_ROWS / 2 - 0.5) * M.PITCH, 0))
		end
		page:set("models")
	end

	local function set_effort(i: number)
		local l = levels()
		if #l == 0 then
			return
		end
		local to = math.clamp(i, 1, #l)
		-- One tap a step, as the drag's; none at an end it stays on.
		if to ~= props.effort:peek() then
			props.effort:set(to)
			ui.haptic("level")
		end
	end

	local function cycle_provider(delta: number)
		local order: { string } = {}
		for _, m in props.models do
			if not table.find(order, m.harness) then
				table.insert(order, m.harness)
			end
		end
		local cur = current(props).harness
		local at = table.find(order, cur) or 1
		local next = order[((at - 1 + delta) % #order) + 1]
		for _, m in props.models do
			if m.harness == next then
				pick_model(m)
				return
			end
		end
	end

	local function on_key(e: KeyEvent): boolean?
		keyboard:set(true)
		local k = e.key
		if k == "Escape" then
			close()
			return true
		end
		if page:peek() == "panel" then
			if k == "f" and not (e.meta or e.ctrl or e.alt) then
				if current(props).fast then
					props.fast:set(not props.fast:peek())
				end
				return true
			elseif k == "ArrowUp" or k == "ArrowDown" then
				show_models(if k == "ArrowUp" then -1 else 1)
				return true
			elseif k == "Enter" or k == " " or k == "Space" then
				show_models(0)
				return true
			elseif k == "Tab" then
				cycle_provider(if e.shift then -1 else 1)
				return true
			elseif k == "ArrowLeft" then
				set_effort(props.effort:peek() - 1)
				return true
			elseif k == "ArrowRight" then
				set_effort(props.effort:peek() + 1)
				return true
			elseif k == "Home" then
				set_effort(1)
				return true
			elseif k == "End" then
				set_effort(#levels())
				return true
			end
			return nil
		end
		-- The models page.
		local list = ordered(props)
		local visible: { number } = {}
		for i, m in list do
			if matches(m, query:peek()) then
				table.insert(visible, i)
			end
		end
		if k == "ArrowUp" or k == "ArrowDown" then
			local at = table.find(visible, active:peek()) or 0
			local next = visible[math.clamp(at + (if k == "ArrowUp" then -1 else 1), 1, math.max(#visible, 1))]
			if next then
				active:set(next)
				local top = (next - 1) * M.PITCH
				local off = list_offset:peek()
				local h = math.min(#visible, M.LIST_ROWS) * M.PITCH
				if top < off then
					list_offset:set(top)
				elseif top + M.PITCH > off + h then
					list_offset:set(top + M.PITCH - h)
				end
			end
			return true
		elseif k == "Enter" then
			local m = list[active:peek()]
			if m then
				pick_model(m)
			end
			return true
		elseif k == "f" and e.meta and e.shift then
			local m = list[active:peek()]
			if m then
				toggle_favorite(m)
			end
			return true
		end
		return nil
	end

	-- ---- the panel page -------------------------------------------------

	local function title(): Node
		local m = current(props)
		local l = m.levels or {}
		local effort_title = if #l > 0
			then roll {
				id = `{id}_effort_title`,
				value = effort_label,
				size = "lg",
				weight = "semibold",
			}
			else nil
		return ui.button {
			variants = recipes.picker_control,
			-- The chevron leans toward the list under the pointer.
			hover_group = true,
			id = `{id}_title`,
			grow = 1,
			shrink = 1,
			min_w = 0,
			h_full = true,
			px = "$zeron.space.8",
			rounded = T.radius(M.ROW_RADIUS),
			items = "start",
			justify = "center",
			direction = "column",
			cursor = "pointer",
			focus = { border = 0 },
			on_click = function()
				keyboard:set(false)
				show_models(0)
			end,
			effort_title,
			ui.row {
				max_w = "100%",
				min_w = 0,
				gap = "$zeron.space.3",
				items = "center",
				txt.text {
					m.label,
					id = `{id}_model_name`,
					size = if #l > 0 then "sm" else "lg",
					weight = if #l > 0 then "regular" else "semibold",
					color = if #l > 0 then "inherit" else T.text,
					truncate = true,
					line = false,
					shrink = 1,
					min_w = 0,
				},
				-- Leans 3 toward the list and firms up on hover.
				ui.div {
					shrink = 0,
					opacity = 0.55,
					group_hover = { x = 3, opacity = 1 },
					icon { name = "alt-arrow-right", size = 10, color = "currentColor" },
				},
			},
		}
	end

	local function fast_button(): Node?
		if not current(props).fast then
			return nil
		end
		return ui.button {
			variants = recipes.picker_control { on = props.fast },
			id = `{id}_fast`,
			w = M.FAST_W,
			h_full = true,
			shrink = 0,
			p = 0,
			items = "center",
			justify = "center",
			rounded = T.radius(M.ROW_RADIUS),
			cursor = "pointer",
			focus = { border = 0 },
			on_click = function()
				keyboard:set(false)
				props.fast:set(not props.fast:peek())
			end,
			-- On fills the bolt: the solid twin fades in over the outline.
			ui.div {
				relative = true,
				w = 15,
				h = 15,
				icon { name = "fast-tier", size = 15, color = "currentColor" },
				ui.presence(function()
					return if props.fast:get() then "on" else nil
				end, function(): Node
					return icon { name = "fast-tier-bold", size = 15, color = T.accent }
				end, {
					id = `{id}_fast_on`,
					absolute = true,
					top = 0,
					left = 0,
					enter = { opacity = { 0, 1 }, duration = motion.d(motion.RESIZE) },
					exit = { opacity = 0, duration = motion.d(motion.RESIZE) },
				}),
			},
		}
	end

	local function option_row(o: Option, i: number): Node
		local open = option_open[o.id]
		if not open then
			open = ui.state(`{id}_opt_{o.id}_open`, false)
			option_open[o.id] = open
		end
		local items: { menu.Entry } = {}
		for _, c in o.choices do
			table.insert(
				items,
				{
					id = `{id}_opt_{o.id}_{c}`,
					label = c,
					checked = function()
						return o.value:get() == c
					end,
					on_click = function()
						o.value:set(c)
					end,
				} :: menu.Item
			)
		end
		return menu.menu {
			id = `{id}_opt_{o.id}_menu`,
			open = open,
			w = 232,
			items = items,
			anchor = ui.button(wash.item(option_group, {
				id = `{id}_opt_{i}`,
				w_full = true,
				h = M.OPTION_ROW,
				px = "$zeron.space.8",
				gap = "$zeron.space.6",
				items = "center",
				rounded = T.radius(M.ROW_RADIUS),
				cursor = "pointer",
				focus = { border = 0 },
				on_click = ui.toggle(open),
				txt.text { o.label, size = "sm", truncate = true, line = false, grow = 1, shrink = 1, min_w = 0 },
				txt.text {
					function()
						return o.value:get()
					end,
					size = "sm",
					color = T.secondary,
					truncate = true,
					line = false,
					max_w = 100,
				},
				icon { name = "alt-arrow-right", size = 12, color = T.secondary },
			})),
		}
	end

	local function panel(): Node
		local m = current(props)
		local l = m.levels or {}
		local rows: { Node } = {}
		for i, o in m.options or {} do
			table.insert(rows, option_row(o, i))
		end
		return ui.column {
			id = `{id}_panel`,
			w_full = true,
			p = T.space(M.INSET),
			items = "stretch",
			ui.row {
				w_full = true,
				h = if #l > 0 then M.HEADER else M.HEADER_SINGLE,
				gap = T.space(M.INSET),
				items = "stretch",
				title(),
				fast_button(),
			},
			if #l > 0
				then ui.div {
					w_full = true,
					px = "$zeron.space.8",
					pt = "$zeron.space.2",
					pb = "$zeron.space.4",
					effort_slider {
						id = `{id}_slider`,
						levels = l,
						selected = props.effort,
						fast = if m.fast then props.fast else nil,
						dragging = dragging,
					},
				}
				else nil,
			if #rows > 0
				then ui.column {
					w_full = true,
					mt = "$zeron.space.4",
					pt = "$zeron.space.2",
					gap = T.space(M.GAP),
					items = "stretch",
					if #rows > M.OPTIONS_MAX
						then scroll {
							w_full = true,
							h = M.OPTIONS_MAX * (M.OPTION_ROW + M.GAP),
							fade = 12,
							wash.list { group = option_group, gap = T.space(M.GAP), color = T.ink1, rows },
						}
						else wash.list { group = option_group, gap = T.space(M.GAP), color = T.ink1, rows },
				}
				else nil,
		}
	end

	-- ---- the models page ------------------------------------------------

	local function model_row(m: Model, i: number): Node
		local function selected(): boolean
			return props.model:get() == m.id
		end
		local function starred(): boolean
			return has(props.favorites:get(), m.id)
		end
		-- The keyboard's row: lit as the pointer's is.
		local function keyed(): boolean
			return keyboard:get() and active:get() == i
		end
		return ui.show(
			function()
				return matches(m, query:get())
			end,
			ui.button(wash.item(model_group, {
				id = `{id}_m_{m.id}`,
				w_full = true,
				h = M.ROW,
				pl = "$zeron.space.8",
				pr = "$zeron.space.4",
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius(M.ROW_RADIUS),
				cursor = "pointer",
				focus = { border = 0 },
				variants = recipes.picker_row { selected = selected, keyed = keyed },
				-- Its star shows under the pointer.
				hover_group = true,
				-- The pointer takes the keyboard's place.
				on_hover = function(inside: boolean)
					if inside then
						keyboard:set(false)
						active:set(i)
					end
				end,
				-- A click on the star reaches the row too (no stop-propagation
				-- here): the star's press marks it, and the row's click keeps or
				-- drops the favourite instead of picking.
				on_click = function()
					if starring == m.id then
						starring = nil
						toggle_favorite(m)
					else
						pick_model(m)
					end
				end,
				icon { name = m.mark, size = 14, color = m.tint or T.secondary },
				txt.text {
					m.label,
					size = "sm",
					weight = "medium",
					truncate = true,
					line = false,
					grow = 1,
					shrink = 1,
					min_w = 0,
				},
				ui.button {
					id = `{id}_star_{m.id}`,
					w = 24,
					h = 24,
					p = 0,
					shrink = 0,
					items = "center",
					justify = "center",
					rounded = T.radius(M.STAR_RADIUS),
					bg = T.clear,
					hover = { bg = T.ink3 },
					focus = { border = 0 },
					cursor = "pointer",
					variants = recipes.picker_star {
						shown = function()
							return starred() or keyed()
						end,
					},
					on_press = function()
						starring = m.id
					end,
					ui.show(starred, icon { name = "star-bold", size = 13, color = T.accent }),
					ui.show(function()
						return not starred()
					end, icon { name = "star", size = 13, color = T.secondary }),
				},
			}, selected))
		)
	end

	local function strip(): Node
		local tabs: { Node } = {}
		local gs = groups(props)
		local function viewed_key(): string?
			local top = math.floor(list_offset:get() / M.PITCH + 0.5) + 1
			local key: string? = nil
			for _, g in gs do
				if g.start <= top then
					key = g.key
				end
			end
			return key
		end
		for _, g in gs do
			local function viewed(): boolean
				return viewed_key() == g.key
			end
			table.insert(
				tabs,
				ui.button(wash.item(strip_group, {
					id = `{id}_group_{g.start}`,
					w = M.ROW,
					h = M.ROW,
					p = 0,
					shrink = 0,
					items = "center",
					justify = "center",
					rounded = T.radius(M.ROW_RADIUS),
					cursor = "pointer",
					focus = { border = 0 },
					variants = recipes.picker_group { viewed = viewed },
					on_click = function()
						keyboard:set(false)
						active:set(g.start)
						list_offset:set((g.start - 1) * M.PITCH)
					end,
					icon {
						name = g.mark,
						size = 14,
						color = g.tint or function()
							return if viewed() then T.text else T.secondary
						end,
					},
				}, viewed))
			)
		end
		return ui.show(
			function()
				return query:get() == ""
			end,
			ui.scroll {
				grow = 1,
				shrink = 1,
				min_w = 0,
				h = M.ROW,
				direction = "row",
				fade_x = { M.PITCH, M.PITCH },
				fade_overflow = true,
				wash.list {
					group = strip_group,
					direction = "row",
					h = M.ROW,
					gap = T.space(M.GAP),
					color = T.ink1,
					tabs,
				},
			}
		)
	end

	local function models(): Node
		local list = ordered(props)
		local rows: { Node } = {}
		for i, m in list do
			table.insert(rows, model_row(m, i))
		end
		local function count(): number
			local n = 0
			for _, m in list do
				if matches(m, query:get()) then
					n += 1
				end
			end
			return n
		end
		local function list_h(): number
			local n = count()
			return (if n == 0 then 4 else math.min(n, M.LIST_ROWS)) * M.PITCH + 2 * M.INSET
		end
		return ui.column {
			id = `{id}_models`,
			w_full = true,
			items = "stretch",
			-- The back button and the provider strip, one row inside the
			-- card's inset.
			ui.row {
				w_full = true,
				h = M.ROW + 2 * M.INSET,
				px = T.space(M.INSET),
				gap = T.space(M.GAP),
				items = "center",
				ui.button {
					variants = recipes.wash { hover = "ink1" },
					id = `{id}_back`,
					w = M.ROW,
					h = M.ROW,
					p = 0,
					shrink = 0,
					items = "center",
					justify = "center",
					rounded = T.radius(M.ROW_RADIUS),
					cursor = "pointer",
					focus = { border = 0 },
					on_click = function()
						page:set("panel")
					end,
					icon { name = "alt-arrow-left", size = 14, color = T.secondary },
				},
				strip(),
			},
			-- The search row.
			ui.row {
				w_full = true,
				h = 40,
				px = "$zeron.space.12",
				gap = "$zeron.space.8",
				items = "center",
				icon { name = "magnifer", size = 12, color = T.tertiary },
				ui.input {
					id = `{id}_search`,
					value = query,
					label = "Search models",
					placeholder = "Search models…",
					placeholder_color = T.tertiary,
					grow = 1,
					shrink = 1,
					min_w = 0,
					h = 24,
					px = 0,
					py = 0,
					bg = T.clear,
					border = 0,
					rounded = 0,
					font = T.sans,
					text_size = "$font.size.sm",
					color = T.text,
					focus = { border = 0 },
					on_key = function(e: KeyEvent): boolean?
						if e.key == "ArrowUp" or e.key == "ArrowDown" or e.key == "Enter" or e.key == "Escape" then
							return on_key(e)
						end
						return nil
					end,
				},
			},
			scroll {
				id = `{id}_list`,
				w_full = true,
				h = list_h :: any,
				offset = list_offset,
				fade = 12,
				px = T.space(M.INSET),
				py = T.space(M.INSET),
				gap = T.space(M.GAP),
				wash.list { group = model_group, gap = T.space(M.GAP), color = T.ink1, rows },
				ui.show(
					function()
						return count() == 0
					end,
					ui.column {
						w_full = true,
						h = 3 * M.PITCH,
						items = "center",
						justify = "center",
						txt.text { "No models match", size = "sm", color = T.tertiary, line = false },
					}
				),
			},
		}
	end

	-- ---- the card -------------------------------------------------------

	-- A page is built for the chosen model and the starred set, so a pick
	-- or a star rebuilds it, as Zeron's re-render would.
	local pages = ui.presence(function()
		return `{page:get()}:{props.model:get()}:{#props.favorites:get()}`
	end, function(): Node
		return if page:peek() == "models" then models() else panel()
	end, {
		w_full = true,
		layout = "height",
		layout_duration = motion.d(motion.RESIZE),
		layout_ease = motion.EASE_OUT,
		enter = { opacity = { 0, 1 }, duration = motion.d(motion.RESIZE), ease = motion.EASE_OUT },
		exit = { opacity = 0, duration = motion.d(60) },
	})

	local card: ContainerProps = {
		id = id,
		w = M.WIDTH,
		p = 0,
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		overflow = "hidden",
		focusable = true,
		focus = { border = 1 },
		on_key = on_key,
		pages,
	}
	if props.inline then
		return ui.column(card)
	end
	-- Opening shows the panel and takes the keyboard once the card is laid
	-- out (the popover mounts closed, so its on_mount is too early: a focus
	-- there stole the window's shortcuts).
	local ref = ui.ref()
	ui.effect(function()
		if props.open:get() then
			page:set("panel")
			keyboard:set(false)
			ui.after(16, function()
				local el = ref:peek()
				if el and props.open:peek() then
					el:focus()
				end
			end)
		end
	end)
	return ui.popover {
		id = id,
		ref = ref,
		open = props.open,
		anchor = props.anchor or ui.div {},
		label = "Model",
		-- Zeron's composer pickers: up from the chip, its right edge on the
		-- chip's, 6 away, rising 4.
		placement = popover.ABOVE_END,
		w = M.WIDTH,
		p = 0,
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		overflow = "hidden",
		focusable = true,
		focus = { border = 1 },
		on_key = on_key,
		-- Each opening rises 4 into place; closing sinks back half that and
		-- fades over 100 ms (menu_out_toward).
		enter = { opacity = { 0, 1 }, y = { 4, 0 }, duration = motion.d(motion.MENU_IN), ease = motion.EASE_OUT_QUINT },
		exit = popover.exit(popover.ABOVE_END, 4),
		pages,
	}
end)

return M
