-- The inspector: the page's tokens with their live values, the slow-motion
-- player, and the way into zgx's own layout inspector.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")

local M = {}

-- The tokens each page leans on, listed with their values.
local TOKENS: { [string]: { string } } = {
	colour = {
		"background",
		"surface.base",
		"surface.raised",
		"surface.overlay",
		"text.primary",
		"text.secondary",
		"accent",
		"hover",
		"pressed",
		"selection.item",
	},
	typography = { "font.sans", "font.mono", "font.size.md", "font.line.md", "font.weight.medium" },
	metrics = { "space.2", "space.3", "space.4", "radius.md", "radius.lg", "radius.xl", "control.height", "shadow.md" },
	motion = {
		"motion.duration.fast",
		"motion.duration.normal",
		"motion.duration.slow",
		"motion.ease.standard",
		"motion.ease.enter",
	},
	buttons = {
		"accent",
		"accent.text",
		"button.bg",
		"button.hover",
		"hover",
		"focus.ring",
		"control.height",
		"radius.md",
	},
	inputs = { "input.bg", "zeron.input.border", "border.strong", "text.tertiary", "accent", "selection" },
	chips = { "zeron.accent.wash", "zeron.danger.wash", "zeron.success.wash", "zeron.ink.3", "radius.full" },
	overlays = {
		"surface.overlay",
		"menu.bg",
		"menu.hover",
		"shadow.lg",
		"zeron.scrim",
		"zeron.radius.card",
		"zeron.radius.item",
	},
	lists = { "selection.item", "hover", "zeron.radius.item", "border.subtle", "scrollbar.thumb" },
	transcript = { "zeron.ink.3", "zeron.code.wash", "zeron.accent_faint", "radius.xl", "font.size.lg", "font.line.lg" },
	agent = {
		"accent",
		"zeron.accent.light",
		"zeron.glass.light.top",
		"zeron.frost",
		"warning",
		"danger",
		"zeron.motion.morph",
		"zeron.motion.roll",
	},
	changes = {
		"zeron.diff.add",
		"zeron.diff.delete",
		"zeron.diff.add_wash",
		"zeron.diff.delete_wash",
		"zeron.diff.hunk",
	},
	workspace = { "zeron.card", "zeron.ink.4", "success", "warning", "zeron.lane.1", "zeron.lane.2", "zeron.solid" },
	composer = {
		"zeron.input.border",
		"input.bg",
		"zeron.solid",
		"zeron.on_solid",
		"zeron.radius.composer",
		"text.tertiary",
	},
	pickers = {
		"accent",
		"zeron.effort.halo",
		"zeron.effort.band",
		"zeron.glass.light.top",
		"zeron.radius.card",
		"zeron.radius.item",
		"selection.item",
		"zeron.ink.1",
	},
}

local function value_of(name: string): string
	local v = ui.theme.get(name)
	if type(v) == "table" then
		-- A shadow: a list of { x, y, blur, spread, color }.
		local parts: { string } = {}
		for _, s in v do
			if type(s) == "table" then
				table.insert(parts, `{s.x} {s.y} {s.blur} {s.spread} {s.color}`)
			else
				table.insert(parts, tostring(s))
			end
		end
		return table.concat(parts, ", ")
	end
	return tostring(v)
end

local function swatch(name: string): Node
	return ui.div {
		w = 14,
		h = 14,
		rounded = "$zeron.radius.4",
		shrink = 0,
		border = 1,
		border_color = T.border,
		-- The token itself: it follows the theme with no function. A token
		-- that is not a colour shows an empty swatch.
		bg = (function(): Color
			local v = ui.theme.get(name)
			return if type(v) == "string" and string.sub(v, 1, 1) == "#" then `${name}` else T.clear
		end)(),
	}
end

local function token_rows(): Node
	return ui.presence(state.page, function(page: string): Node
		local rows: { Node } = {}
		for _, name in TOKENS[page] or {} do
			table.insert(
				rows,
				ui.row {
					w_full = true,
					h = 26,
					gap = "$zeron.space.8",
					items = "center",
					swatch(name),
					kit.text.text {
						name,
						size = "sm",
						mono = true,
						color = T.text,
						grow = 1,
						shrink = 1,
						min_w = 0,
						truncate = true,
					},
					kit.text.text {
						function()
							return value_of(name)
						end,
						size = "xs",
						mono = true,
						color = T.tertiary,
						shrink = 0,
					},
				}
			)
		end
		return ui.column { w_full = true, gap = 0, rows }
	end, {
		enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.FAST) },
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.MENU_OUT) },
		mode = "wait",
	})
end

function M.Inspector(): Node
	return ui.column {
		id = "inspector",
		w_full = true,
		h_full = true,
		-- A tool in Files' place: the panel fill runs the full height, the
		-- titlebar's band over its top, its seam drawn by the shell.
		bg = T.panel,
		pt = "$zeron.titlebar.height",
		ui.row {
			h = 36,
			px = "$zeron.space.16",
			items = "center",
			kit.text.text { "Inspector", size = "sm", weight = "semibold", line = false },
		},
		kit.scroll {
			grow = 1,
			w_full = true,
			px = "$zeron.space.16",
			py = "$zeron.space.8",
			gap = "$zeron.space.16",
			fade = 16,
			ui.column {
				w_full = true,
				gap = "$zeron.space.6",
				kit.text.eyebrow("Tokens on this page"),
				token_rows(),
			},
			kit.divider {},
			ui.column {
				w_full = true,
				gap = "$zeron.space.8",
				kit.text.eyebrow("Motion"),
				ui.row {
					items = "center",
					gap = "$zeron.space.8",
					kit.text.text { "Speed", size = "sm", color = T.secondary, grow = 1 },
					kit.segmented {
						id = "slow",
						size = "sm",
						value = ui.computed(function()
							return tostring(kit.motion.slow:get())
						end) :: State<string>,
						options = {
							{ id = "1", label = "1×" },
							{ id = "4", label = "¼" },
							{ id = "10", label = "⅒" },
						},
						on_change = function(id: string)
							kit.motion.slow:set(tonumber(id) or 1)
						end,
					},
				},
				ui.row {
					items = "center",
					gap = "$zeron.space.8",
					kit.text.text { "Reduced motion", size = "sm", color = T.secondary, grow = 1 },
					kit.text.text {
						function()
							return if kit.motion.reduced:get() then "on" else "off"
						end,
						size = "sm",
						mono = true,
						color = T.tertiary,
					},
				},
			},
			kit.divider {},
			ui.column {
				w_full = true,
				gap = "$zeron.space.8",
				items = "start",
				kit.text.eyebrow("Layout"),
				kit.text.text {
					"Outlines every box and names the script line that made the one under the pointer.",
					size = "sm",
					color = T.secondary,
					wrap = true,
				},
				kit.button {
					id = "layout_inspector",
					label = "Toggle layout inspector",
					icon = { name = "expand-arrows" },
					size = "sm",
					on_click = ui.action("inspect"),
				},
				ui.row {
					gap = "$zeron.space.8",
					items = "center",
					kit.text.text { "Shortcut", size = "sm", color = T.secondary },
					kit.kbd { "⌃", "⌥", "⌘", "I" },
				},
			},
		},
	}
end

return M
