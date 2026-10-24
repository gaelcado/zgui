-- Roll text (roll_text.rs, after Scritto): when a label changes, only the
-- glyphs that differ roll. The common prefix stays, the common suffix
-- keeps its glyphs; outgoing glyphs rise 0.35 em and shrink to 0.6 as
-- they fade, incoming ones arrive from below, each 550 ms on
-- ease-out-quint, staggered left to right over 30% of that. One presence
-- per glyph slot, keyed by the glyph's identity, in a plain row.
local T = require("../theme")
local txt = require("./text")
local motion = require("./motion")

export type Props = {
	id: string?,
	value: State<string>,
	size: txt.Size?,
	weight: txt.Weight?,
	color: Reactive<Color>?,
	mono: boolean?,
	tabular: boolean?,
}

type Glyph = { key: string, ch: string }

local M = {}

M.DURATION = motion.ROLL
M.STAGGER = 0.3
-- Slots laid out at most; a longer label shows its first glyphs rolling.
M.SLOTS = 48

local PX: { [txt.Size]: number } = { micro = 10, xs = 11, sm = 12, md = 13, lg = 14, xl = 16, xxl = 19 }

local function split(s: string): { string }
	local out: { string } = {}
	for _, code in utf8.codes(s) do
		table.insert(out, utf8.char(code))
	end
	return out
end

return ui.component(function(props: Props): Node
	local size: txt.Size = props.size or "md"
	local em = PX[size]
	local travel = em * 0.35
	local glyphs = ui.state(`roll_{props.id or tostring(math.random(1, 1e9))}`, {} :: { Glyph })
	local prev: { string } = {}
	local generation = 0
	local function apply(value: string)
		local next = split(value)
		local prefix = 0
		while prefix < #prev and prefix < #next and prev[prefix + 1] == next[prefix + 1] do
			prefix += 1
		end
		local suffix = 0
		while suffix < #prev - prefix and suffix < #next - prefix and prev[#prev - suffix] == next[#next - suffix] do
			suffix += 1
		end
		generation += 1
		local list: { Glyph } = {}
		for i, ch in next do
			local key: string
			if i <= prefix then
				key = `p{i}`
			elseif i > #next - suffix then
				key = `s{#next - i}`
			else
				key = `m{generation}_{i}`
			end
			table.insert(list, { key = key, ch = ch })
		end
		prev = next
		glyphs:set(list)
	end
	ui.effect(function()
		apply(props.value:get())
	end)
	local slots: { Node } = {}
	for i = 1, M.SLOTS do
		table.insert(
			slots,
			ui.presence(function()
				local g = glyphs:get()[i]
				return if g then g.key else nil
			end, function(): Node
				local g = glyphs:peek()[i]
				return txt.text {
					if g then g.ch else "",
					size = size,
					weight = props.weight,
					color = props.color or T.text,
					mono = props.mono,
					tabular = props.tabular,
					line = false,
				}
			end, {
				enter = {
					opacity = { 0, 1 },
					y = { travel, 0 },
					scale = { 0.6, 1 },
					duration = motion.d(M.DURATION),
					delay = (i - 1) * motion.d(M.DURATION) * M.STAGGER / 12,
					ease = motion.EASE_OUT_QUINT,
				},
				exit = {
					opacity = 0,
					y = -travel,
					scale = 0.6,
					duration = motion.d(M.DURATION),
					ease = motion.EASE_OUT_QUINT,
				},
			})
		)
	end
	return ui.row {
		id = props.id,
		items = "center",
		overflow = "hidden",
		py = ui.raw(travel, "the glyph's travel"),
		my = ui.raw(-travel, "the glyph's travel"),
		slots,
	}
end)
