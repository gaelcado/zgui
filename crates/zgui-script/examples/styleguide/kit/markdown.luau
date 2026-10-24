-- Markdown, as Zeron's `markdown/render.rs` draws a reply: the blocks
-- `ui.markdown` parses, in the transcript's styles. Prose at 14/22 with
-- bold, italics, struck text, inline code on the accent wash and links in
-- the accent; headings; bullet and numbered lists (nested, a task's box);
-- code blocks with their header; quotes on the accent rail; rules; tables
-- in a card. The whole is selectable, as a reply is.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local tr = require("./transcript")
local lightbox = require("./lightbox")

local M = {}

type Run = { x: string, b: boolean?, i: boolean?, c: boolean?, s: boolean?, a: string?, f: boolean? }

-- A paragraph's runs, as one rich text.
local function runs(list: { Run }?, size: txt.Size?, color: Color?, weight: string?): Node
	local s = size or "lg"
	local props: RichProps = {
		wrap = true,
		text_size = `$font.size.{s}`,
		line_height = `$font.line.{s}`,
		color = color or T.text,
		weight = weight,
	}
	for _, r in list or {} do
		local span: SpanProps = { r.x, literal = true }
		if r.b then
			span.weight = 600
		end
		if r.i then
			span.italic = true
		end
		if r.s then
			span.strike = true
		end
		if r.c then
			span.font = "mono"
			span.bg = T.code_wash
			span.padding = { 3, 1 }
			span.radius = 4
		end
		if r.a then
			span.color = T.accent
			span.hover = { underline = true }
			span.href = r.a
		end
		table.insert(props, ui.span(span))
	end
	return ui.rich(props)
end

-- Blocks hold blocks (a list's items, a quote's), so the renderer calls
-- itself through this table.
local R = {}

local function list(b: any, depth: number): Node
	local items: { Node } = {}
	for i, item in b.items do
		local marker: Node
		local first = item[1]
		if first and first.task ~= nil then
			marker = ui.row {
				w = 14,
				h = 14,
				mt = "$zeron.space.4",
				rounded = "$zeron.radius.4",
				border = 1.5,
				border_color = if first.task then T.accent else T.strong,
				bg = if first.task then T.accent else T.clear,
				items = "center",
				justify = "center",
				first.task and icon { name = "check", size = 10, color = T.on_accent } or nil,
			}
		elseif b.t == "ol" then
			marker = txt.text { `{(b.start or 1) + i - 1}.`, size = "lg", color = T.tertiary, line = false }
		else
			marker = ui.div { w = 5, h = 5, mt = "$zeron.space.9", rounded = "$zeron.radius.3", bg = T.tertiary }
		end
		local parts: { Node } = {}
		for _, sub in item do
			table.insert(parts, R.block(sub, depth + 1))
		end
		table.insert(
			items,
			ui.row {
				w_full = true,
				gap = "$zeron.space.8",
				items = "start",
				ui.row { w = 18, shrink = 0, justify = "end", marker },
				ui.column { grow = 1, shrink = 1, min_w = 0, gap = "$zeron.space.4", items = "stretch", parts },
			}
		)
	end
	return ui.column { w_full = true, gap = "$zeron.space.4", items }
end

local function table_block(b: any): Node
	local function cells(row: { any }, head: boolean): Node
		local out: { Node } = {}
		for _, cell in row do
			table.insert(
				out,
				ui.column {
					grow = 1,
					basis = 0,
					min_w = 0,
					px = "$zeron.space.12",
					py = "$zeron.space.7",
					runs(cell, "sm", if head then T.secondary else T.text),
				}
			)
		end
		return ui.row {
			w_full = true,
			bg = if head then T.ink1 else T.clear,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			out,
		}
	end
	local rows: { Node } = { cells(b.head, true) }
	for _, r in b.rows do
		table.insert(rows, cells(r, false))
	end
	return ui.column {
		w_full = true,
		rounded = T.radius_lg,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		rows,
	}
end

-- An image alone in its paragraph (image_media.rs preview_element): as
-- wide as the column, never past its own size or 480 high, centred; a
-- click enlarges it in the image viewer.
local function image(src: string, alt: string): Node
	-- Its laid-out size is the viewer's: read on the click, not followed.
	local shown = ui.ref()
	return ui.button {
		label = if alt ~= "" then alt else "Enlarge image",
		self = "center",
		max_w = "100%",
		p = 0,
		bg = T.clear,
		border = 0,
		focus = { border = 0 },
		rounded = "$zeron.radius.8",
		overflow = "hidden",
		cursor = "zoom_in",
		on_click = function()
			local w, h = shown:peek() and shown.width, shown.height
			if w and h and w > 0 then
				lightbox.open { src = src, name = if alt ~= "" then alt else src, w = w, h = h }
			end
		end,
		ui.image {
			src = src,
			label = alt,
			max_w = "100%",
			max_h = 480,
			fit = "contain",
			ref = shown,
		},
	}
end

function R.block(b: MarkdownBlock, depth: number): Node
	local any_b = b :: any
	if b.t == "h" then
		local size: txt.Size = if any_b.l == 1 then "xxl" elseif any_b.l == 2 then "xl" else "lg"
		return ui.column {
			w_full = true,
			pt = if any_b.l <= 2 then "$zeron.space.8" else 4,
			runs(any_b.s, size, T.text, "$font.weight.semibold"),
		}
	elseif b.t == "code" then
		local lines: { string } = {}
		for line in string.gmatch((any_b.text or "") :: string, "([^\n]*)\n?") do
			table.insert(lines, line)
		end
		if #lines > 0 and lines[#lines] == "" then
			table.remove(lines)
		end
		return tr.code_block { language = any_b.lang, lines = lines }
	elseif b.t == "ul" or b.t == "ol" then
		return list(any_b, depth)
	elseif b.t == "quote" then
		local parts: { Node } = {}
		for _, sub in any_b.b or {} do
			table.insert(parts, R.block(sub, depth + 1))
		end
		return ui.row {
			w_full = true,
			items = "stretch",
			ui.div { w = 2, bg = T.accent, opacity = 0.6, shrink = 0 },
			ui.column {
				grow = 1,
				shrink = 1,
				min_w = 0,
				px = "$zeron.space.12",
				py = "$zeron.space.8",
				gap = "$zeron.space.8",
				bg = T.accent_faint,
				parts,
			},
		}
	elseif b.t == "hr" then
		return ui.div { w_full = true, h = 1, my = "$zeron.space.4", bg = T.hairline }
	elseif b.t == "table" then
		return table_block(any_b)
	elseif b.t == "img" then
		return image(any_b.src or "", any_b.alt or "")
	end
	return runs(any_b.s)
end

export type Props = {
	id: string?,
	-- The markdown, or a function of it (a reply streaming in).
	text: string | (() -> string),
	-- Names a text that grows, so each change parses only its new end.
	key: string?,
}

-- A reply's blocks, 12 apart, selectable.
M.view = ui.component(function(props: Props): Node
	local text = props.text
	if type(text) == "string" then
		local parts: { Node } = {}
		for _, b in ui.markdown(text) do
			table.insert(parts, R.block(b, 0))
		end
		return ui.column { id = props.id, w_full = true, gap = "$zeron.space.12", selectable = true, parts }
	end
	local blocks = ui.computed(function()
		return ui.markdown(text(), { key = props.key })
	end)
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.12",
		selectable = true,
		ui.each(blocks, function(b: MarkdownBlock): Node
			return R.block(b, 0)
		end),
	}
end)

return M
