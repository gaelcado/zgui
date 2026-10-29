-- Markdown, as Zeron's `markdown/render.rs` draws a reply: the blocks
-- `ui.markdown` parses, in the transcript's styles. Prose at 14/22 with
-- bold, italics, struck text, inline code on the accent wash and links in
-- the accent; headings; bullet and numbered lists (nested, a task's box);
-- code blocks with their header, their syntax coloured; Mermaid diagrams
-- drawn; quotes on the accent rail; rules; tables of hairline rules that
-- scroll once their columns reach 96. The whole is selectable, as a reply
-- is. A view given `media` draws its images that way (a pull request's
-- description: what it may load, and how), and lays a paragraph of images
-- or a table of screenshots out as wrapping cards
-- (pull_request_media.rs render_description).
--
-- A view given `links` treats its links as Zeron's: one naming a
-- workspace file (or a code span that is a file's path) opens it, shown
-- with an open glyph after it (a code span under the file's name); a web
-- link opens where `links` says; each tells where it goes under the
-- pointer, and a secondary click has its menu (link_interaction.rs). A
-- streaming view (`key`) fades in what arrives (veil.rs).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local tr = require("./transcript")
local lightbox = require("./lightbox")
local comment = require("./comment")
local menus = require("./menu")
local motion = require("./motion")
local syntax = require("../lib/syntax")

local M = {}

type Run = { x: string, b: boolean?, i: boolean?, c: boolean?, s: boolean?, a: string?, f: boolean?, m: boolean? }

-- What a link's click or menu row asks: a click (`open`, the web link's
-- destination by the preference), Zeron's own surface (`zeron`: the file in
-- Files, the page in a browser tab), the system's browser (`external`), a
-- file's default app (`default_app`) or its folder (`reveal`).
export type LinkAction = "open" | "zeron" | "external" | "default_app" | "reveal"
export type Links = {
	-- The workspace file a link's target or a code span names (its path in
	-- the workspace), or nil.
	file: (target: string) -> string?,
	-- Runs a link's action: `target` the file's path or the web address.
	open: (target: string, action: LinkAction) -> (),
	-- Whether a web link's click opens it in Zeron (the menu's check).
	in_zeron: State<boolean>?,
}

-- Code fences wrap their long lines (Fit content) or scroll them, one
-- choice for every fence (settings.rs code_fences_fit_content).
M.fit = ui.state("markdown_fit", false)

-- How TeX is set (Settings → Appearance: Render math, Math font, Math
-- size; markdown/math.rs MathStyle): typeset by `ui.math` in the face, at
-- the size (percent) of the text around it; off, `$…$` shows its source
-- as code and `$$…$$` as a `math` code block, as source zatex can't set.
export type MathStyle = { on: State<boolean>, face: State<string>, size: State<string> }
M.math = {
	on = ui.state("markdown_math_on", true),
	face = ui.state("markdown_math_face", "fira"),
	size = ui.state("markdown_math_size", "100"),
} :: MathStyle

-- What sets a formula now: the face and size, or "off".
local function math_key(): string
	local m = M.math
	return if m.on:get() then `{m.face:get()}:{m.size:get()}` else "off"
end
-- A text size's points.
local function points(size: txt.Size): number
	return tonumber(ui.theme.get(`font.size.{size}`)) or 14
end
-- `tex` laid out in the style `key` names for text of `size`, or nil.
local function formula(tex: string, display: boolean, key: string, size: txt.Size): (MathFormula?, number)
	if key == "off" then
		return nil, 0
	end
	local face, percent = string.match(key, "^(.-):(.*)$")
	local f = ui.math(tex, { display = display, face = face :: any })
	return f, points(size) * (tonumber(percent) or 100) / 100
end

-- The prose's size in the view being built (`Props.size`).
local prose: txt.Size = "lg"
-- The view being built's links, and its veil's key and the paragraphs
-- keyed under it so far.
local links: Links? = nil
local veil: string? = nil
local veiled = 0
-- The block being built's id, and the texts and code blocks in it so far.
local block_id: string? = nil
local texts = 0
local coded = 0

-- Link menus (popover_card, 260 wide), rows popover.rs menu_row's.
local LINK_MENU = (function()
	local style = table.clone(menus.CARD) :: { [string]: any }
	style.w = 260
	return style
end)()

local function row(id: string, label: string, glyph: string, run: () -> (), checked: State<boolean>?): Node
	return menus.item({
		id = id,
		label = label,
		icon = if checked then nil else glyph :: any,
		checked = checked,
		on_click = run,
	}, function() end, nil, nil, "popover")
end

-- A link's menu: a file's (Open in Zeron, Open with default app, Show in
-- folder, Copy file path) or a web link's (Open in Zeron, Open in
-- external browser, Copy link address, and the "Open links in Zeron"
-- check under a separator).
local function link_menu(l: Links, target: string, file: string?): (PointerEvent) -> { Node }
	return function(_: PointerEvent): { Node }
		local function open(action: LinkAction): () -> ()
			return function()
				l.open(file or target, action)
			end
		end
		if file then
			local path: string = file
			return {
				row("link_menu_open_zeron", "Open in Zeron", "document", open("zeron")),
				row("link_menu_open_default", "Open with default app", "arrow-up-right", open("default_app")),
				row("link_menu_show_in_folder", "Show in folder", "folder", open("reveal")),
				row("link_menu_copy_path", "Copy file path", "copy", function()
					ui.clipboard.write(path)
				end),
			}
		end
		local items = {
			row("link_menu_open_zeron", "Open in Zeron", "globe", open("zeron")),
			row("link_menu_open_external", "Open in external browser", "arrow-up-right", open("external")),
			row("link_menu_copy_address", "Copy link address", "copy", function()
				ui.clipboard.write(target)
			end),
		}
		local pref = l.in_zeron
		if pref then
			table.insert(items, menus.separator())
			table.insert(
				items,
				row("link_menu_default_destination", "Open links in Zeron", "check", function()
					pref:set(not pref:peek())
				end, pref)
			)
		end
		return items
	end
end

-- A path's last `n` components (all of it with fewer), its `:line` kept.
local function trailing(path: string, n: number): string
	local parts = string.split(path, "/")
	if #parts <= n then
		return path
	end
	return table.concat(parts, "/", #parts - n + 1)
end
-- Labels for code spans naming files: each its file's name, or as many of
-- its last components as tell it from another path ending the same way
-- (inline_code_links.rs span_labels).
local function file_labels(spans: { string }): { [string]: string }
	local out: { [string]: string } = {}
	for _, span in spans do
		local n = 1
		while true do
			local tail = trailing(span, n)
			local shared = false
			for _, other in spans do
				if other ~= span and (other == tail or string.sub(other, -#tail - 1) == "/" .. tail) then
					shared = true
				end
			end
			if not shared or tail == span then
				out[span] = tail
				break
			end
			n += 1
		end
	end
	return out
end

-- A paragraph's runs, as one rich text.
local function runs(list: { Run }?, size: txt.Size?, color: Color?, weight: string?): Node
	local s = size or prose
	local props: RichProps = {
		wrap = true,
		text_size = `$font.size.{s}`,
		line_height = `$font.line.{s}`,
		color = color or T.text,
		weight = weight,
	}
	if veil then
		veiled += 1
		props.veil = `{veil}.{veiled}`
	end
	-- Named for the block: its first text the block's id.
	if block_id then
		texts += 1
		props.id = if texts == 1 then block_id else `{block_id}_text{texts}`
	end
	-- Code spans that name workspace files, and their labels.
	local files: { [number]: string } = {}
	local named: { string } = {}
	local l = links
	if l then
		for i, r in list or {} do
			local path = if r.c and not r.a then l.file(r.x) else nil
			if path then
				files[i] = path
				table.insert(named, r.x)
			end
		end
	end
	local labels = file_labels(named)
	local formulas = false
	for _, r in list or {} do
		formulas = formulas or r.m == true
	end
	-- The runs as spans; formulas as the math style `key` sets them.
	local function fill(key: string): Node
		local spans = table.clone(props)
		for i, r in list or {} do
			local file = files[i]
			local span: SpanProps = { if file then labels[r.x] or r.x else r.x, literal = true }
			-- A formula on the text's baseline (math.rs MathGlyphs), copying
			-- as its source; one that can't be set, or with math off, its
			-- source as code.
			local f: MathFormula?, px = nil, 0
			if r.m then
				f, px = formula(r.x, false, key, s)
			end
			if f then
				span[1] = ""
				span.icon = {
					code = f.svg,
					w = f.w * px,
					h = f.h * px,
					descent = f.descent * px,
					gap = 0,
					tint = "currentColor",
				}
				span.copy = `${r.x}$`
			elseif r.m then
				span[1] = `${r.x}$`
			end
			if r.b then
				span.weight = 600
			end
			if r.i then
				span.italic = true
			end
			if r.s then
				span.strike = true
			end
			if (r.c or (r.m and not f)) and not file then
				span.font = "mono"
				span.bg = T.code_wash
				span.padding = { 3, 1 }
				span.radius = 4
			end
			local target = r.a or (if file then r.x else nil)
			if target and target ~= "zgx:pending-link" then
				span.color = T.accent
				span.hover = { underline = true }
				local lk = l
				if lk then
					file = file or lk.file(target)
					local to, at = target, file
					span.tooltip = at or to
					span.on_click = function()
						lk.open(at or to, if at then "zeron" else "open")
					end
					span.context_menu = link_menu(lk, to, at)
					span.context_menu_style = LINK_MENU
					-- Zeron's open glyph after a file (link_presentation.rs): 12, 4
					-- from its text, in the faint text colour.
					if at then
						span.icon =
							{ src = "icons/arrow-up-right.svg", size = 12, gap = 4, tint = T.tertiary, after = true }
					end
				else
					span.href = target
					span.tooltip = target
				end
			elseif target then
				span.color = T.accent
			end
			table.insert(spans, ui.span(span))
		end
		return ui.rich(spans)
	end
	if not formulas then
		return fill("off")
	end
	-- Set again as the style changes, and only then.
	return ui.presence(math_key, fill, { w_full = true })
end

-- Blocks hold blocks (a list's items, a quote's), so the renderer calls
-- itself through this table.
local R = {}

-- How the view being built draws an image (`Props.media`), and how many it
-- has drawn: each its own key.
export type Media = (src: string, alt: string, key: string) -> Node
local media: Media? = nil
local media_key = ""
local images = 0

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

-- A table (render.rs render_table, mugen's TableBlock): no box, a hairline
-- under each row but the last; cells 14/22 padded 12, the header's bold.
-- Columns share the width by their content, none under 96 (or its content,
-- if less); past that the table scrolls sideways rather than crushing
-- them.
local TABLE_MIN_COLUMN = 96
local function table_block(b: any): Node
	local all: { { any } } = {}
	if #b.head > 0 then
		table.insert(all, b.head)
	end
	for _, r in b.rows do
		table.insert(all, r)
	end
	-- Each column's content, as its longest cell's characters: its share.
	local columns = 0
	for _, r in all do
		columns = math.max(columns, #r)
	end
	local naturals: { number } = {}
	for c = 1, columns do
		local longest = 0
		for _, r in all do
			local n = 0
			for _, run in r[c] or {} do
				n += utf8.len(run.x) or #run.x
			end
			longest = math.max(longest, n)
		end
		-- 7 a character at 14, at least 48, and the padding.
		naturals[c] = math.max(longest * 7, 48) + 24
	end
	local floor = 0
	for _, n in naturals do
		floor += math.min(n, TABLE_MIN_COLUMN)
	end
	local rows: { Node } = {}
	for ri, r in all do
		local head = ri == 1 and #b.head > 0
		local cells: { Node } = {}
		for c = 1, columns do
			table.insert(
				cells,
				ui.column {
					grow = naturals[c],
					shrink = naturals[c],
					basis = 0,
					min_w = math.min(naturals[c], TABLE_MIN_COLUMN),
					p = "$zeron.space.12",
					runs(r[c] or {}, prose, T.text, if head then "$font.weight.bold" else nil),
				}
			)
		end
		table.insert(
			rows,
			ui.row {
				w_full = true,
				border_sides = if ri < #all then { 0, 0, 1, 0 } else nil,
				border_color = T.border,
				cells,
			}
		)
	end
	return ui.scroll_x {
		id = if block_id then `{block_id}_table` else nil,
		w_full = true,
		ui.column { grow = 1, min_w = floor, shrink = 0, rows },
	}
end

-- Mermaid's colours: the theme's roles (mermaid.rs Palette::from_theme).
local function diagram_colours(): MermaidColours
	return {
		dark = ui.theme.kind() == "dark" or ui.theme.kind() == "high-contrast",
		font = ui.theme.get("font.sans"),
		bg = ui.theme.get("background"),
		text = ui.theme.get("text.primary"),
		muted = ui.theme.get("text.secondary"),
		faint = ui.theme.get("text.tertiary"),
		border = ui.theme.get("border"),
		strong = ui.theme.get("border.strong"),
		accent = ui.theme.get("accent"),
	}
end

-- A code fence: its syntax coloured, streaming in through the veil.
local function code(b: any, id: string?, actions: { Node }?, fit: State<boolean>?): Node
	return tr.code_block {
		id = id,
		language = if b.lang ~= "" then b.lang else nil,
		text = b.text or "",
		highlight = syntax.for_language(b.lang),
		veil = if veil
			then (function()
				veiled += 1
				return `{veil}.{veiled}`
			end)()
			else nil,
		fit = fit or M.fit,
		actions = actions,
	}
end

-- A Mermaid fence drawn (render.rs:2076, transcript.rs's diagram worker):
-- its source while the fence streams or the diagram renders (off the main
-- thread), then the diagram, fitted to the column, with Show source / Show
-- diagram and Copy; one that can't be drawn stays source, a warning saying
-- why.
local Diagram = ui.component(function(props: { block: any, id: string? }): Node
	local b = props.block
	local source = ui.use_state(false)
	local drawn = ui.resource(function(): MermaidDiagram?
		return ui.mermaid(b.text or "", diagram_colours()):await()
	end)
	local function toggle(shown: boolean): Node
		return tr.code_action {
			id = props.id and `{props.id}_source`,
			label = if shown then "Show diagram" else "Show source",
			icon = if shown then "eye" else "file-code",
			on_click = function()
				source:set(not source:peek())
			end,
		}
	end
	return ui.switch(drawn.status, {
		loading = code(b, props.id),
		failed = ui.presence(drawn.error, function(why: string?): Node
			local reason = why or "Diagram could not be rendered"
			return code(b, props.id, {
				ui.row {
					id = props.id and `{props.id}_failed`,
					w = 22,
					h = 22,
					items = "center",
					justify = "center",
					label = reason,
					tooltip = reason,
					icon { name = "danger-triangle", size = 13, color = T.warning_muted },
				},
			})
		end, { w_full = true }),
		ready = ui.presence(source, function(shown: boolean): Node
			local d = drawn.data:peek()
			if shown or not d then
				return code(b, props.id, { toggle(true) })
			end
			return tr.code_block {
				id = props.id,
				language = b.lang,
				text = b.text or "",
				actions = { toggle(false) },
				body = ui.column {
					w_full = true,
					items = "center",
					p = "$zeron.space.12",
					ui.svg {
						id = props.id and `{props.id}_diagram`,
						label = "Diagram",
						code = d.svg,
						w = d.w,
						h = d.h,
						aspect = if d.h > 0 then d.w / d.h else 1,
						max_w = "100%",
						fit = "contain",
					},
				},
			}
		end, { w_full = true }),
	})
end)

-- An image alone in its paragraph (image_media.rs preview_element): as
-- wide as the column, never past its own size or 480 high, centred; a
-- click enlarges it in the image viewer.
local function image(src: string, alt: string): Node
	if media then
		images += 1
		return media(src, alt, `{media_key}_{images}`)
	end
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

-- Cards of images (render_description): a paragraph of nothing but
-- images, or a table with an image in a cell (its header's words over each
-- cell's), as cards 240 wide at least that share the row, 12 apart, each
-- its label at 12 in the muted text over its images.
local function only_images(runs_: { MarkdownRun }): boolean
	local any = false
	for _, r in runs_ do
		if r.img then
			any = true
		elseif string.match(r.x, "%S") then
			return false
		end
	end
	return any
end
local function gallery(cells: { { MarkdownRun } }): Node
	local cards: { Node } = {}
	for _, cell in cells do
		local label: { string } = {}
		local shots: { Node } = {}
		for _, r in cell do
			if r.img then
				table.insert(shots, image(r.img, r.x))
			else
				table.insert(label, r.x)
			end
		end
		local words = table.concat(label)
		table.insert(
			cards,
			ui.column {
				grow = 1,
				basis = 240,
				min_w = 0,
				max_w = "100%",
				if string.match(words, "%S")
					then txt.text { words, literal = true, size = "sm", color = T.secondary, wrap = true }
					else nil,
				shots,
			}
		)
	end
	return ui.row { w_full = true, flex_wrap = true, gap = "$zeron.space.12", cards }
end

-- A display formula (`$$…$$`): centred on a line of its own as tall as it
-- with its clear space, scrolling sideways past the column, copying as its
-- source; as a `math` code block while it can't be set.
local function math_block(tex: string): Node
	local size, id = prose, block_id
	local function build(key: string): Node
		local f, px = formula(tex, true, key, size)
		if not f then
			return code({ lang = "math", text = tex }, if id then `{id}_math` else nil)
		end
		return ui.scroll_x {
			id = if id then `{id}_math` else nil,
			w_full = true,
			ui.row {
				grow = 1,
				shrink = 0,
				justify = "center",
				-- Clear space above and below it (DISPLAY_PAD_Y).
				py = "$zeron.space.6",
				ui.rich {
					text_size = `$font.size.{size}`,
					color = T.text,
					ui.span {
						"",
						literal = true,
						icon = { code = f.svg, w = f.w * px, h = f.h * px, gap = 0, tint = "currentColor" },
						copy = `$${tex}$$`,
					},
				},
			},
		}
	end
	return ui.presence(math_key, build, { w_full = true })
end

function R.block(b: MarkdownBlock, depth: number): Node
	local any_b = b :: any
	if media and b.t == "p" and only_images(b.s) then
		local cells: { { MarkdownRun } } = {}
		for _, r in b.s do
			if r.img then
				table.insert(cells, { r })
			end
		end
		return gallery(cells)
	elseif media and b.t == "table" then
		local cells: { { MarkdownRun } } = {}
		local shots = false
		for _, row in b.rows do
			for column, cell in row do
				local runs_: { MarkdownRun } = table.clone(b.head[column] or {})
				for _, r in cell do
					shots = shots or r.img ~= nil
					table.insert(runs_, r)
				end
				table.insert(cells, runs_)
			end
		end
		if shots then
			return gallery(cells)
		end
	end
	if b.t == "h" then
		local size: txt.Size = if any_b.l == 1 then "xxl" elseif any_b.l == 2 then "xl" else "lg"
		return ui.column {
			w_full = true,
			pt = if any_b.l <= 2 then "$zeron.space.8" else 4,
			runs(any_b.s, size, T.text, "$font.weight.semibold"),
		}
	elseif b.t == "code" then
		coded += 1
		local id = if block_id then `{block_id}_code{if coded > 1 then coded else ""}` else nil
		-- A diagram once its fence has closed.
		if string.lower(any_b.lang or "") == "mermaid" and not any_b.open then
			return Diagram { block = any_b, id = id }
		end
		return code(any_b, id)
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
	elseif b.t == "math" then
		return math_block(any_b.tex)
	end
	return runs(any_b.s)
end

export type Props = {
	id: string?,
	-- The markdown, or a function of it (a reply streaming in).
	text: string | (() -> string),
	-- Names a text that grows, so each change parses only its new end.
	key: string?,
	-- Draws each image instead (given its source, alt text and a key of
	-- its own), and lays images out as cards.
	media: Media?,
	-- The prose's size (the transcript's 14, "lg", unless set).
	size: txt.Size?,
	-- Its links as Zeron's: files open in Files, web links where the
	-- preference says, each with its menu.
	links: Links?,
	-- What streams in fades in (a reply's, with `key`).
	veil: boolean?,
	-- Single newlines break lines, as people's messages show them.
	breaks: boolean?,
	-- Review comments on its blocks (markdown_preview.rs): under the pointer
	-- a block shows the 16 "+" 20 before it, which comments on the line it
	-- starts on (`add`); under each block, what `under` gives for its line
	-- (its comments, a draft, with their own room above them).
	comments: Comments?,
}
export type Comments = { add: (line: number) -> (), under: (line: number) -> Node }

-- A block with its "+" and what is under it.
local function commented(b: MarkdownBlock, c: Comments, id: string?): Node
	local line = b.line or 1
	return ui.column {
		w_full = true,
		ui.div {
			w_full = true,
			relative = true,
			hover_group = true,
			R.block(b, 0),
			ui.div {
				absolute = true,
				top = 3,
				left = -20,
				opacity = 0,
				group_hover = { opacity = 1 },
				selectable = false,
				comment.add(function()
					c.add(line)
				end, id and `{id}_add_{line}`),
			},
		},
		c.under(line),
	}
end

-- Builds `b`, the `i`th block, with `props`' media (a streamed block's
-- images keyed on), links and veil (keyed on the block, so a block built
-- again as it grows fades only what it gained).
local function built(props: Props, b: MarkdownBlock, i: number): Node
	local media_, key_, prose_, links_ = media, media_key, prose, links
	local veil_, veiled_, block_, coded_, texts_ = veil, veiled, block_id, coded, texts
	media, media_key, prose = props.media, props.id or "md", props.size or "lg"
	links = props.links
	veil = if props.veil and props.key and not motion.reduced:peek() then `{props.key}:{i}` else nil
	veiled, coded, texts = 0, 0, 0
	block_id = if props.id then `{props.id}_{i}` else nil
	local node = R.block(b, 0)
	media, media_key, prose, links = media_, key_, prose_, links_
	veil, veiled, block_id, coded, texts = veil_, veiled_, block_, coded_, texts_
	return node
end

-- A reply's blocks, 12 apart, selectable.
M.view = ui.component(function(props: Props): Node
	local text = props.text
	local notes = props.comments
	if notes then
		local blocks = ui.computed(function()
			local source = if type(text) == "string" then text else text()
			return ui.markdown(source, { key = props.key, lines = true, math = true })
		end)
		return ui.column {
			id = props.id,
			w_full = true,
			gap = "$zeron.space.12",
			selectable = true,
			ui.each(blocks, function(b: MarkdownBlock, i: number): Node
				local links_, block_, coded_, texts_ = links, block_id, coded, texts
				links, block_id, coded, texts = props.links, if props.id then `{props.id}_{i}` else nil, 0, 0
				local node = commented(b, notes, props.id)
				links, block_id, coded, texts = links_, block_, coded_, texts_
				return node
			end),
		}
	end
	if type(text) == "string" then
		local parts: { Node } = {}
		local count = images
		images = 0
		local still: Props = { id = props.id, text = text, media = props.media, size = props.size, links = props.links }
		for i, b in ui.markdown(text, { breaks = props.breaks, math = true }) do
			table.insert(parts, built(still, b, i))
		end
		images = count
		return ui.column { id = props.id, w_full = true, gap = "$zeron.space.12", selectable = true, parts }
	end
	local blocks = ui.computed(function()
		return ui.markdown(text(), { key = props.key, math = true })
	end)
	return ui.column {
		id = props.id,
		w_full = true,
		gap = "$zeron.space.12",
		selectable = true,
		ui.each(blocks, function(b: MarkdownBlock, i: number): Node
			return built(props, b, i)
		end),
	}
end)

-- A prompt's Markdown in its bubble, as a reply's at the bubble's size.
tr.markdown = function(text: string, id: string?, links: any): Node
	return M.view { id = id, text = text, links = links, breaks = true }
end

return M
