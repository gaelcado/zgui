-- The full model picker (pickers.rs render_harness_model_popover), behind
-- Settings' Compact model picker turned off: the providers' strip (40: a
-- 32 tab for Starred, then each harness's mark, the chosen one with the
-- accent's bar under it), the search row, the chosen tab's models (rows 32:
-- the mark, the name, the star), and under a hairline the model's
-- settings (rows 30, the value muted at the end; a click opens its
-- choices beside it): Reasoning, Context window, Service tier. Up from the
-- chip, its right edge on the chip's, rising 4.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local frost = require("./frost")
local popover = require("./popover")
local recipes = require("./recipes")
local motion = require("./motion")
local menu = require("./menu")
local compact_picker = require("./compact_picker")

type Model = compact_picker.Model
export type Props = {
	id: string,
	open: State<boolean>,
	anchor: Node,
	models: { Model },
	model: State<string>,
	effort: State<number>,
	fast: State<boolean>,
	-- "Standard" or "1M tokens", for the models that offer the long one.
	context: State<string>,
	favorites: State<{ string }>,
}

local M = {}

M.WIDTH = 300
M.ROW = 32
M.LIST_MAX = 224

-- Which models take a 1M context window (the Claude models here).
function M.long_context(m: Model): boolean
	return m.harness == "Claude Code"
end

-- The chip's suffix: the effort, then what differs from the defaults
-- ("High · 1M · Fast").
function M.traits(m: Model?, effort: number, context: string, fast: boolean): string
	if not m then
		return ""
	end
	local parts = { (m.levels or {})[effort] or "Default" }
	if context == "1M tokens" and M.long_context(m) then
		table.insert(parts, "1M")
	end
	if fast and m.fast then
		table.insert(parts, "Fast")
	end
	return table.concat(parts, " · ")
end

local function safe(text: string): string
	return (string.gsub(string.lower(text), "[^%w]+", "_"))
end

M.picker = ui.component(function(props: Props): Node
	local id = props.id
	local function current(): Model?
		for _, m in props.models do
			if m.id == props.model:get() then
				return m
			end
		end
		return nil
	end
	local function content(): Node
		local start = current()
		-- The strip's tab: "starred", or a harness's name.
		local tab = ui.use_state(if start then start.harness else "starred")
		local query = ui.use_state("")
		local harnesses: { Model } = {}
		local seen: { [string]: boolean } = {}
		for _, m in props.models do
			if not seen[m.harness] then
				seen[m.harness] = true
				table.insert(harnesses, m)
			end
		end
		local function shown(): { Model }
			local q = query:get()
			local favs = props.favorites:get()
			local out: { Model } = {}
			for _, m in props.models do
				local in_tab = if tab:get() == "starred" then table.find(favs, m.id) ~= nil else m.harness == tab:get()
				local matches = q == "" or string.find(string.lower(m.label), string.lower(q), 1, true) ~= nil
				-- A search looks through every provider.
				if (q ~= "" and matches) or (q == "" and in_tab) then
					table.insert(out, m)
				end
			end
			return out
		end
		local function strip_tab(key: string, label: string, glyph: string, tint: Color?): Node
			local function on(): boolean
				return tab:get() == key and query:get() == ""
			end
			return ui.button {
				variants = recipes.wash { hover = "ink2" },
				id = `{id}_tab_{safe(key)}`,
				label = label,
				tooltip = label,
				relative = true,
				w = 32,
				h = 32,
				p = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_item,
				cursor = "pointer",
				focus = { border = 0 },
				on_click = function()
					query:set("")
					tab:set(key)
				end,
				icon {
					name = glyph :: any,
					size = if key == "starred" then 15 else 16,
					color = tint or function()
						return if on() then T.text else T.secondary
					end,
				},
				ui.show(
					on,
					ui.div { absolute = true, left = 8, right = 8, bottom = 0, h = 2, rounded = 1, bg = T.accent }
				),
			}
		end
		local tabs: { Node } = { strip_tab("starred", "Starred", "star-bold") }
		for _, m in harnesses do
			table.insert(tabs, strip_tab(m.harness, m.harness, m.mark, m.tint))
		end
		local function row(m: Model): Node
			local function selected(): boolean
				return props.model:get() == m.id
			end
			local function starred(): boolean
				return table.find(props.favorites:get(), m.id) ~= nil
			end
			return ui.button {
				id = `{id}_model_{m.id}`,
				label = m.label,
				w_full = true,
				h = M.ROW,
				shrink = 0,
				px = "$zeron.space.8",
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius_item,
				variants = recipes.picker_choice { selected = selected },
				color = T.text,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					props.model:set(m.id)
					local levels = m.levels or {}
					props.effort:set(if #levels == 0 then 1 else math.clamp(props.effort:peek(), 1, #levels))
				end,
				icon { name = m.mark, size = 16, color = m.tint or T.secondary },
				txt.text { m.label, size = "md", color = "inherit", line = false, truncate = true, grow = 1, min_w = 0 },
				ui.button {
					variants = recipes.wash { hover = "ink3" },
					id = `{id}_star_{m.id}`,
					label = function()
						return if starred() then "Unstar" else "Star"
					end,
					w = 24,
					h = 24,
					p = 0,
					items = "center",
					justify = "center",
					rounded = "$zeron.radius.3",
					cursor = "pointer",
					focus = { border = 0 },
					on_click = function()
						local favs = table.clone(props.favorites:peek())
						local at = table.find(favs, m.id)
						if at then
							table.remove(favs, at)
						else
							table.insert(favs, m.id)
						end
						props.favorites:set(favs)
					end,
					ui.presence(function()
						return if starred() then "star-bold" else "star"
					end, function(name: string): Node
						return icon {
							name = name :: any,
							size = 13,
							color = if name == "star-bold" then T.warning else T.tertiary,
						}
					end),
				},
			}
		end
		-- A setting's row: its label, its value muted; its choices open
		-- beside it.
		local function setting(
			key: string,
			label: string,
			value: () -> string,
			choices: () -> { string },
			set: (choice: string) -> ()
		): Node
			local open = ui.use_state(false)
			local items: { any } = {}
			for _, c in choices() do
				table.insert(items, {
					id = `{id}_{key}_{safe(c)}`,
					label = c,
					checked = function()
						return value() == c
					end,
					on_click = function()
						set(c)
					end,
				})
			end
			return menu.menu {
				id = `{id}_{key}_menu`,
				open = open,
				items = items,
				w = 180,
				placement = { side = "right", align = "start", offset = 6 },
				anchor = ui.button {
					variants = recipes.wash { hover = "ink2" },
					id = `{id}_{key}`,
					label = label,
					w_full = true,
					h = 30,
					px = "$zeron.space.8",
					gap = "$zeron.space.8",
					items = "center",
					rounded = T.radius_item,
					cursor = "pointer",
					focus = { border = 0 },
					on_click = ui.toggle(open),
					txt.text { label, size = "md", line = false, grow = 1 },
					txt.text { value, size = "sm", color = T.secondary, line = false, truncate = true, max_w = 100 },
					icon { name = "alt-arrow-right", size = 12, color = T.tertiary },
				},
			}
		end
		local function settings_of(): { Node }
			local m = current()
			local settings: { Node } = {}
			if m and m.levels and #m.levels > 0 then
				table.insert(
					settings,
					setting("reasoning", "Reasoning", function()
						local now = current()
						return if now then (now.levels or {})[props.effort:get()] or "Default" else ""
					end, function()
						return (m :: Model).levels or {}
					end, function(c: string)
						local now = current()
						local at = now and table.find(now.levels or {}, c)
						if at then
							props.effort:set(at)
						end
					end)
				)
			end
			if m and M.long_context(m) then
				table.insert(
					settings,
					setting("context", "Context window", function()
						return props.context:get()
					end, function()
						return { "Standard", "1M tokens" }
					end, function(c: string)
						props.context:set(c)
					end)
				)
			end
			if m and m.fast then
				table.insert(
					settings,
					setting("tier", "Service tier", function()
						return if props.fast:get() then "Fast" else "Standard"
					end, function()
						return { "Standard", "Fast" }
					end, function(c: string)
						props.fast:set(c == "Fast")
					end)
				)
			end
			return settings
		end
		return ui.column {
			w_full = true,
			ui.row {
				h = 40,
				w_full = true,
				px = T.space(frost.INSET),
				gap = "$zeron.space.2",
				items = "center",
				border = 1,
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				tabs,
			},
			ui.row {
				h = 40,
				w_full = true,
				px = "$zeron.space.10",
				gap = "$zeron.space.8",
				items = "center",
				border = 1,
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				icon { name = "magnifer", size = 14, color = T.secondary },
				ui.input {
					id = `{id}_search`,
					value = query,
					placeholder = "Search models…",
					grow = 1,
					min_w = 0,
					p = 0,
					border = 0,
					rounded = 0,
					bg = T.clear,
					focus = { border = 0, bg = T.clear },
					text_size = "$font.size.md",
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = function(e: KeyEvent): boolean
						if e.key == "Escape" then
							props.open:set(false)
							return true
						end
						return false
					end,
				},
			},
			ui.presence(function(): string
				local keys = { tab:get() }
				for _, s in shown() do
					table.insert(keys, s.id)
				end
				return table.concat(keys, "\n")
			end, function(): Node
				local list = shown()
				if #list == 0 then
					return ui.row {
						w_full = true,
						p = "$zeron.space.12",
						txt.text {
							if query:peek() ~= ""
								then "No models found"
								elseif tab:peek() == "starred" then "No starred models yet — hit a row's star"
								else "No models",
							id = `{id}_empty`,
							size = "sm",
							color = T.tertiary,
						},
					}
				end
				local rows: { Node } = {}
				for _, model in list do
					table.insert(rows, row(model))
				end
				return ui.scroll {
					w_full = true,
					max_h = M.LIST_MAX,
					p = T.space(frost.INSET),
					gap = "$zeron.space.2",
					bg = T.ink1,
					fade = { 12, 12 },
					fade_overflow = true,
					rows,
				}
			end, { w_full = true }),
			-- The chosen model's settings, under a hairline.
			ui.presence(function(): string
				return props.model:get()
			end, function(): Node
				local settings = settings_of()
				if #settings == 0 then
					return ui.div {}
				end
				return ui.column {
					w_full = true,
					p = T.space(frost.INSET),
					gap = "$zeron.space.2",
					border = 1,
					border_sides = { 1, 0, 0, 0 },
					border_color = T.hairline,
					settings,
				}
			end, { w_full = true }),
		}
	end
	return ui.popover {
		id = id,
		open = props.open,
		anchor = props.anchor,
		label = "Model",
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
		enter = { opacity = { 0, 1 }, y = { 4, 0 }, duration = motion.d(motion.MENU_IN), ease = motion.EASE_OUT_QUINT },
		exit = popover.exit(popover.ABOVE_END, 4),
		ui.presence(function(): boolean?
			return if props.open:get() then true else nil
		end, content, { w_full = true }),
	}
end)

return M
