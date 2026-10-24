-- Labels on fills: every label the kit sets on a fill, against that fill in
-- each of its states, translucent fills composited over the window's
-- background. The floor is the lowest ratio among them; the suite walks
-- every theme and accent and holds it at 4.5:1 (AA for body text).
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local colour = require("@lib/colour")

local M = {}

M.FLOOR = 4.5

export type Pair = { name: string, label: string, fills: { string } }

-- Token names; "accent" pairs read the window's accent (a preset applies as
-- a scope the page cannot read through `ui.theme.get`).
local PAIRS: { Pair } = {
	{
		name = "Primary",
		label = "zeron.on_solid",
		fills = { "zeron.solid", "zeron.solid.hover", "zeron.solid.pressed" },
	},
	{
		name = "Danger",
		label = "zeron.danger.text",
		fills = { "zeron.danger.strong", "zeron.danger.hover", "zeron.danger.pressed" },
	},
	{
		name = "Warning",
		label = "zeron.warning.text",
		fills = { "zeron.warning.strong", "zeron.warning.hover", "zeron.warning.pressed" },
	},
	{
		name = "Success",
		label = "zeron.success.text",
		fills = { "zeron.success.strong", "zeron.success.hover", "zeron.success.pressed" },
	},
	{
		name = "Info",
		label = "zeron.info.text",
		fills = { "zeron.info.strong", "zeron.info.hover", "zeron.info.pressed" },
	},
	{ name = "Secondary", label = "text.primary", fills = { "zeron.ink.2", "zeron.ink.4", "zeron.ink.5" } },
	{ name = "Ghost", label = "text.primary", fills = { "background", "zeron.glass.hover", "zeron.ink.4" } },
	{ name = "Selected row", label = "text.primary", fills = { "selection.item", "button.hover", "button.pressed" } },
	{ name = "Accent", label = "accent", fills = { "accent" } },
}

M.PAIRS = PAIRS

local STATES = { "rest", "hover", "pressed" }

-- A fill as the eye sees it: composited over the window's background.
local function fill_of(name: string): colour.Rgba?
	local bg = colour.token("background")
	local f: colour.Rgba?
	if name == "accent" then
		f = colour.parse((state.accent_pair()))
	else
		f = colour.token(name)
	end
	if not f or not bg then
		return nil
	end
	return colour.over(f, bg)
end
local function label_of(pair: Pair): colour.Rgba?
	if pair.label == "accent" then
		local _, on = state.accent_pair()
		return colour.parse(on)
	end
	return colour.token(pair.label)
end

-- The ratio of a pair's label on one of its fills.
function M.ratio(pair: Pair, i: number): number
	ui.theme.current:get()
	local f, l = fill_of(pair.fills[i]), label_of(pair)
	if not f or not l then
		return 0
	end
	return colour.contrast(l, f)
end

-- The lowest ratio, and where.
function M.floor(): (number, string)
	local low, at = math.huge, ""
	for _, pair in PAIRS do
		for i = 1, #pair.fills do
			local r = M.ratio(pair, i)
			if r < low then
				low, at = r, `{pair.name} {STATES[i]}`
			end
		end
	end
	return low, at
end

local function hex(c: colour.Rgba?): string
	if not c then
		return "#00000000"
	end
	return string.format("#%02x%02x%02x", math.floor(c.r + 0.5), math.floor(c.g + 0.5), math.floor(c.b + 0.5))
end

local function sample(pair: Pair, i: number): Node
	return ui.column {
		gap = "$zeron.space.4",
		items = "start",
		ui.row {
			w = 72,
			h = 28,
			rounded = T.radius_button,
			items = "center",
			justify = "center",
			border = 1,
			border_color = T.hairline,
			-- The fill under test, as the contrast check composites it: data,
			-- not a style.
			bg = function()
				return ui.raw(hex(fill_of(pair.fills[i])), "the composited fill a contrast check measures")
			end,
			kit.text.text {
				"Label",
				size = "sm",
				weight = "medium",
				line = false,
				color = function()
					return ui.raw(hex(label_of(pair)), "the label colour the contrast check picked")
				end,
			},
		},
		kit.text.text {
			function()
				return `{STATES[i]} {colour.ratio(M.ratio(pair, i))}`
			end,
			size = "micro",
			mono = true,
			line = false,
			color = function()
				return if M.ratio(pair, i) >= M.FLOOR then T.tertiary else T.danger
			end,
		},
	}
end

function M.view(): Node
	local rows: { Node } = {}
	for _, pair in PAIRS do
		local samples: { Node } = {}
		for i = 1, #pair.fills do
			table.insert(samples, sample(pair, i))
		end
		table.insert(
			rows,
			ui.row {
				w_full = true,
				gap = "$zeron.space.16",
				items = "center",
				kit.text.text { pair.name, size = "sm", color = T.secondary, w = 112, line = false },
				samples,
			}
		)
	end
	return ui.column {
		w_full = true,
		gap = "$zeron.space.14",
		rows,
		kit.text.text {
			function()
				local low, at = M.floor()
				return `floor {colour.ratio(low)} · {at}`
			end,
			id = "contrast_floor",
			size = "xs",
			mono = true,
			color = T.tertiary,
		},
	}
end

return M
