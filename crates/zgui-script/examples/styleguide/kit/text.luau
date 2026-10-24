-- Text in the type scale: a size name picks the token for its size and line
-- height, so a theme's scale restyles every label.
local T = require("../theme")

export type Size = "micro" | "xs" | "sm" | "md" | "lg" | "xl" | "xxl"
export type Weight = "regular" | "medium" | "semibold" | "bold"
export type Props = {
	-- Text the script did not write (a message, a name): no `{state}`
	-- templates in it.
	literal: boolean?,
	[number]: Text,
	size: Size?,
	weight: Weight?,
	-- "inherit": the parent's colour (a control's, as it changes with
	-- hover and selection); unset, the text colour.
	color: Reactive<Color>?,
	mono: boolean?,
	italic: boolean?,
	wrap: boolean?,
	truncate: boolean?,
	lines: number?,
	align: ("start" | "center" | "end")?,
	tabular: boolean?,
	letter_spacing: number?,
	id: string?,
	class: string?,
	grow: number?,
	shrink: number?,
	min_w: Length?,
	w: Reactive<Length>?,
	max_w: Length?,
	opacity: Reactive<number>?,
	hidden: Reactive<boolean>?,
	-- Its look while the pointer is over the row it sits in (`hover_group`).
	group_hover: Styles?,
	mt: Length?,
	mb: Length?,
	ml: Length?,
	mr: Length?,
	px: Length?,
	py: Length?,
	-- The line height is the size's unless the text is a single line in a
	-- control, where the font's own keeps it centred.
	line: boolean?,
	-- A line height of its own, over the size's (a label on gpui's 1.618
	-- line, as Zeron sets it).
	line_height: Length?,
	-- A recipe's choice (its colour, chosen by a state), over the size's.
	variants: Variants?,
}

local SIZE: { [Size]: string } = {
	micro = "$zeron.font.size.micro",
	xs = "$font.size.xs",
	sm = "$font.size.sm",
	md = "$font.size.md",
	lg = "$font.size.lg",
	xl = "$font.size.xl",
	xxl = "$font.size.xxl",
}
local LINE: { [Size]: string } = {
	micro = "$font.line.xs",
	xs = "$font.line.xs",
	sm = "$font.line.sm",
	md = "$font.line.md",
	lg = "$font.line.lg",
	xl = "$font.line.xl",
	xxl = "$font.line.xxl",
}
local WEIGHT: { [Weight]: string } = {
	regular = "$font.weight.regular",
	medium = "$font.weight.medium",
	semibold = "$font.weight.semibold",
	bold = "$font.weight.bold",
}

local M = {}

function M.text(props: Props): Node
	local size: Size = props.size or "md"
	local weight: Weight = props.weight or "regular"
	local align: ("start" | "center" | "right")? = if props.align == "end" then "right" else props.align
	return ui.text {
		props[1],
		id = props.id,
		class = props.class,
		font = if props.mono then T.mono else T.sans,
		text_size = SIZE[size],
		line_height = props.line_height or (if props.line == false then nil else LINE[size]),
		weight = WEIGHT[weight],
		color = if props.color == "inherit" then nil else props.color or T.text,
		italic = props.italic,
		literal = props.literal,
		wrap = props.wrap,
		truncate = props.truncate,
		lines = props.lines,
		align = align,
		tabular = props.tabular,
		letter_spacing = props.letter_spacing,
		grow = props.grow,
		shrink = props.shrink,
		min_w = props.min_w,
		w = props.w,
		max_w = props.max_w,
		opacity = props.opacity,
		hidden = props.hidden,
		group_hover = props.group_hover,
		mt = props.mt,
		mb = props.mb,
		ml = props.ml,
		mr = props.mr,
		px = props.px,
		py = props.py,
		variants = props.variants,
	}
end

-- Shorthands: a label in the secondary colour, a mono value, a heading.
function M.label(content: Text, size: Size?): Node
	return M.text { content, size = size or "sm", color = T.secondary }
end
function M.mono(content: Text, size: Size?, color: Reactive<Color>?): Node
	return M.text { content, size = size or "sm", mono = true, color = color or T.secondary }
end
function M.heading(content: Text, size: Size?): Node
	return M.text { content, size = size or "xl", weight = "semibold" }
end
-- An uppercase section label, tracked out.
function M.eyebrow(content: string): Node
	return M.text { content, size = "xs", weight = "medium", color = T.tertiary }
end

return M
