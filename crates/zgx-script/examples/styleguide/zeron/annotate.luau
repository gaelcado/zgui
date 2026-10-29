-- Browser annotations (browser/mod.rs, composer.rs, proto annotation.rs):
-- an element picked on a page lands in the session's draft as a chip,
-- "Annotation N", numbered after the draft's others; its hover shows the
-- element (its tag, classes and size) over the opening of its code. The
-- chip's reference is `@annotation:N:K` (K tells picks apart); what was
-- picked stays here, bounded as Zeron bounds page data.
local T = require("../theme")
local kit = require("@kit")

local M = {}

-- The picker the page runs (zeron/annotate_js).
M.SCRIPT = require("./annotate_js")
-- Picks a session takes (a page's script answers, so it could stream
-- chips into the draft without a click).
M.MAX_PICKS = 24
-- Code lines a chip's card shows.
M.SNIPPET_LINES = 4

export type Annotation = {
	index: number,
	url: string,
	title: string,
	element: string,
	selector: string,
	path: { string },
	role: string,
	name: string,
	text: string,
	html: string,
	rect: { number },
	viewport: { number },
	styles: { { string } },
}

-- Each chip's element, by its reference.
local picked: { [string]: Annotation } = {}
local made = 0

local function clip(value: any, max: number): string
	local s = if type(value) == "string" then value else ""
	return if #s > max then string.sub(s, 1, max) else s
end
local function numbers(value: any, n: number): { number }
	local out: { number } = {}
	for i = 1, n do
		local v = if type(value) == "table" then value[i] else nil
		table.insert(out, if type(v) == "number" then math.floor(v) else 0)
	end
	return out
end

-- A pick as the page sent it, within Zeron's limits (annotation.rs bounded).
function M.bounded(pick: any): Annotation
	local p = if type(pick) == "table" then pick else {}
	local path: { string } = {}
	if type(p.path) == "table" then
		for i = 1, math.min(#p.path, 8) do
			table.insert(path, clip(p.path[i], 240))
		end
	end
	local styles: { { string } } = {}
	if type(p.styles) == "table" then
		for i = 1, math.min(#p.styles, 24) do
			local pair = p.styles[i]
			if type(pair) == "table" then
				table.insert(styles, { clip(pair[1], 64), clip(pair[2], 240) })
			end
		end
	end
	return {
		index = 0,
		url = clip(p.url, 2048),
		title = clip(p.title, 240),
		element = clip(p.element, 240),
		selector = clip(p.selector, 480),
		path = path,
		role = clip(p.role, 240),
		name = clip(p.name, 240),
		text = clip(p.text, 240),
		html = clip(p.html, 2400),
		rect = numbers(p.rect, 4),
		viewport = numbers(p.viewport, 2),
		styles = styles,
	}
end

-- The opening of its code: its first non-blank lines, "…" when there are more.
function M.snippet(html: string, max: number): { string }
	local lines: { string } = {}
	local more = false
	for line in string.gmatch(html .. "\n", "([^\n]*)\n") do
		if string.match(line, "%S") then
			if #lines == max then
				more = true
				break
			end
			table.insert(lines, line)
		end
	end
	if more then
		table.insert(lines, "…")
	end
	return lines
end

-- A chip's reference, and the number it shows.
function M.is(token: string): boolean
	return string.match(token, "^@annotation:%d+:%d+$") ~= nil
end
function M.number(token: string): number?
	return tonumber(string.match(token, "^@annotation:(%d+):"))
end

-- The numbers of the annotations `text` holds.
function M.numbers(text: string): { number }
	local out: { number } = {}
	for n in string.gmatch(text, "@annotation:(%d+):%d+") do
		table.insert(out, tonumber(n) :: number)
	end
	return out
end

-- Adds `a` to `draft` as a chip numbered after its others; the number.
function M.add(draft: State<string>, a: Annotation): number
	local text = draft:peek()
	local n = 0
	for _, k in M.numbers(text) do
		n = math.max(n, k)
	end
	n += 1
	made += 1
	local token = `@annotation:{n}:{made}`
	a.index = n
	picked[token] = a
	local gap = if text == "" or string.find(string.sub(text, -1), "%s") then "" else " "
	draft:set(`{text}{gap}{token} `)
	return n
end

function M.label(token: string): string
	return `Annotation {M.number(token) or 0}`
end

M.ICON = "icons/cursor-square.svg"

-- The chip's card (MentionPathTooltip::annotation_card): 360 wide, the
-- element (its tag, then its id and classes muted, its size faint at the
-- end) over up to four lines of its code in mono, under a hairline.
function M.card(token: string): Node?
	local a = picked[token]
	if not a then
		return nil
	end
	local at = string.find(a.element, "[#.]")
	local tag = if at then string.sub(a.element, 1, at - 1) else a.element
	local rest = if at then string.sub(a.element, at) else ""
	local w, h = a.rect[3], a.rect[4]
	local lines: { Node } = {}
	for _, line in M.snippet(a.html, M.SNIPPET_LINES) do
		table.insert(
			lines,
			kit.text.text {
				line,
				literal = true,
				mono = true,
				size = "xs",
				color = T.secondary,
				line_height = 16,
				truncate = true,
				line = false,
			}
		)
	end
	return kit.frost.card {
		id = "annotation_card",
		w = 360,
		p = 0,
		gap = 0,
		ui.row {
			h = 28,
			px = "$zeron.space.10",
			gap = "$zeron.space.6",
			items = "center",
			ui.row {
				grow = 1,
				shrink = 1,
				min_w = 0,
				overflow = "hidden",
				kit.text.text { tag, literal = true, size = "sm", weight = "semibold", line = false, shrink = 0 },
				kit.text.text {
					rest,
					literal = true,
					size = "sm",
					color = T.secondary,
					truncate = true,
					line = false,
					shrink = 1,
					min_w = 0,
				},
			},
			(w > 0 or h > 0) and kit.text.text {
				`{w} × {h}`,
				size = "sm",
				color = T.tertiary,
				line = false,
				shrink = 0,
				ml = "$zeron.space.8",
			} or nil,
		},
		#lines > 0 and ui.column {
			w_full = true,
			px = "$zeron.space.10",
			py = "$zeron.space.7",
			border_sides = { 1, 0, 0, 0 },
			border_color = T.border,
			lines,
		} or nil,
	}
end

return M
