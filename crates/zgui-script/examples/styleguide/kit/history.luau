-- Git history (history.rs): a table of commits at 36 a row with the graph
-- drawn down its left on a canvas (lanes 12 apart, nodes of radius 3, the
-- HEAD ring 2 out, strokes 1.5), then the subject at 12 with ref badges 16
-- high in the lane's colour at 7%, a 20 author circle with 9-point
-- initials, the date at 10.5 and the SHA in mono 10.5 on a 24 hit area.
-- A 24-high column header at 9.5 sits above; a 24×196 search field and a
-- 28 load-more pill belong to the panel's chrome.
local T = require("../theme")
local wash = require("./wash")
local txt = require("./text")
local icon = require("./icon")
local recipes = require("./recipes")

export type Commit = {
	sha: string,
	subject: string,
	author: string,
	date: string,
	-- The lane the node sits in (from 0) and the lanes its parents continue in.
	lane: number,
	parents: { number },
	refs: { string }?,
	head: boolean?,
}
export type Props = {
	id: string?,
	commits: { Commit },
	selected: State<string>?,
	lanes: number?,
	w: Length?,
}

local M = {}

M.ROW = 36
M.LANE = 12
M.NODE = 3
M.STROKE = 1.5
M.HEADER = 24

local function lane_color(i: number): string
	return tostring(ui.theme.get(`zeron.lane.{(i % 6) + 1}`) or ui.theme.get("accent"))
end

local function initials(name: string): string
	local out = ""
	for word in string.gmatch(name, "%S+") do
		out ..= string.upper(string.sub(word, 1, 1))
		if #out >= 2 then
			break
		end
	end
	return out
end

-- The graph: one canvas spanning every row. Each lane runs as one line
-- from a commit down to the next commit in that lane; a parent in another
-- lane curves over within the first row, then runs straight.
local function graph(commits: { Commit }, lanes: number): Node
	local width = lanes * M.LANE + 12
	return ui.canvas {
		w = width,
		h = #commits * M.ROW,
		shrink = 0,
		draw = function(cv: Canvas, _w: number, _h: number)
			local function x(lane: number): number
				return 6 + lane * M.LANE + M.LANE / 2
			end
			local function y(row: number): number
				return (row - 0.5) * M.ROW
			end
			local function next_in(lane: number, after: number): number?
				for j = after + 1, #commits do
					if commits[j].lane == lane then
						return j
					end
				end
				return nil
			end
			for i, c in commits do
				for _, p in c.parents do
					local j = next_in(p, i)
					local to_y = if j then y(j) else y(#commits) + M.ROW / 2
					local path = ui.path():move(x(c.lane), y(i))
					if p ~= c.lane then
						local midy = y(i) + M.ROW / 2
						path = path:cubic(x(c.lane), midy, x(p), midy, x(p), y(i + 1))
					end
					path = path:line(x(p), to_y)
					cv.stroke(cv, path, lane_color(p), M.STROKE, { cap = "round", join = "round" })
				end
			end
			for i, c in commits do
				local color = lane_color(c.lane)
				cv.circle(
					cv,
					x(c.lane),
					y(i),
					M.NODE + (if c.head then 2 else 0) + 1.5,
					tostring(ui.theme.get("zeron.card"))
				)
				if c.head then
					cv.stroke(cv, ui.path():arc(x(c.lane), y(i), M.NODE + 2, 0, 360), color, 1)
				end
				cv.circle(cv, x(c.lane), y(i), M.NODE, color)
			end
		end,
	}
end

local function badge(label: string, color: string): Node
	return ui.row {
		h = 16,
		max_w = 112,
		px = "$zeron.space.5",
		gap = "$zeron.space.2",
		items = "center",
		rounded = "$zeron.radius.4",
		bg = T.ink2,
		icon { name = "git-branch", size = 10, color = color, opacity = 0.78 },
		txt.text { label, size = "micro", color = color, opacity = 0.9, truncate = true, line = false },
	}
end

local function row(c: Commit, props: Props, group: string): Node
	local function on(): boolean
		return props.selected ~= nil and props.selected:get() == c.sha
	end
	local refs: { Node } = {}
	for _, r in c.refs or {} do
		table.insert(refs, badge(r, `$zeron.lane.{(c.lane % 6) + 1}`))
	end
	return ui.button(wash.item(group, {
		id = props.id and `{props.id}_{c.sha}`,
		w_full = true,
		h = M.ROW,
		pr = "$zeron.space.8",
		gap = "$zeron.space.10",
		items = "center",
		cursor = "pointer",
		focus = { border = 0 },
		on_click = if props.selected then ui.set(props.selected, c.sha) else nil,
		ui.row {
			grow = 1,
			shrink = 1,
			min_w = 80,
			gap = "$zeron.space.5",
			items = "center",
			txt.text { c.subject, size = "sm", truncate = true, line = false, shrink = 1, min_w = 0 },
			refs,
		},
		ui.row {
			w = 20,
			h = 20,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.10",
			bg = T.ink3,
			border = 1,
			border_color = T.ink4,
			txt.text { initials(c.author), size = "micro", color = T.tertiary, line = false },
		},
		txt.text { c.date, size = "micro", color = T.secondary, line = false, w = 64, shrink = 0 },
		ui.row {
			h = 24,
			px = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.4",
			shrink = 0,
			hover = { bg = T.ink3 },
			txt.text {
				string.sub(c.sha, 1, 7),
				size = "micro",
				mono = true,
				line = false,
				color = "inherit",
				variants = recipes.sha { selected = on },
			},
		},
	}))
end

local function header(): Node
	local function cell(label: string, w: Length?, grow: number?): Node
		return txt.text {
			label,
			size = "micro",
			color = T.tertiary,
			line = false,
			w = w,
			grow = grow,
			letter_spacing = 0.3,
		}
	end
	return ui.row {
		w_full = true,
		h = M.HEADER,
		pr = "$zeron.space.8",
		gap = "$zeron.space.10",
		items = "center",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		cell("SUBJECT", nil, 1),
		cell("", 20),
		cell("DATE", 64),
		cell("SHA", 60),
	}
end

M.table = ui.component(function(props: Props): Node
	local lanes = props.lanes or 1
	for _, c in props.commits do
		lanes = math.max(lanes, c.lane + 1)
		for _, p in c.parents do
			lanes = math.max(lanes, p + 1)
		end
	end
	local group = wash.group("history")
	local rows: { Node } = {}
	for _, c in props.commits do
		table.insert(rows, row(c, props, group))
	end
	local gw = lanes * M.LANE + 12
	return ui.column {
		id = props.id,
		w = props.w,
		w_full = props.w == nil,
		ui.row { w_full = true, pl = ui.raw(gw, "the graph's width"), header() },
		ui.row {
			w_full = true,
			items = "start",
			graph(props.commits, lanes),
			wash.list { group = group, grow = 1, shrink = 1, min_w = 0, w_full = false, color = T.ink1, rows },
		},
	}
end)

-- The search field: 24×196 on ink 3.5% at radius 6, an 11 magnifier.
export type SearchProps = { id: string?, value: State<string>, w: Length? }
M.search = ui.component(function(props: SearchProps): Node
	return ui.row {
		id = props.id and `{props.id}_frame`,
		h = 24,
		w = props.w or 196,
		min_w = 80,
		pl = "$zeron.space.8",
		pr = "$zeron.space.2",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = T.ink1,
		icon { name = "magnifer", size = 11, color = T.tertiary },
		ui.input {
			id = props.id,
			value = props.value,
			label = "Search commits",
			placeholder = "Search commits",
			placeholder_color = T.tertiary,
			grow = 1,
			shrink = 1,
			min_w = 0,
			h = "100%",
			px = 0,
			py = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			font = T.sans,
			text_size = "$font.size.xs",
			color = T.text,
			focus = { border = 0 },
		},
		ui.button {
			w = 16,
			h = 16,
			p = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.3_5",
			bg = T.clear,
			hover = { bg = T.ink3 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ui.set(props.value, ""),
			icon { name = "close", size = 9, color = T.tertiary },
		},
	}
end)

-- The load-more pill: 28 high, text 11, on raised 72% with a border.
export type MoreProps = { id: string?, label: string?, on_click: (Handler | Action)? }
M.more = ui.component(function(props: MoreProps): Node
	return ui.button {
		variants = recipes.wash { rest = "raised", hover = "hover" },
		id = props.id,
		h = 28,
		px = "$zeron.space.11",
		items = "center",
		self = "start",
		rounded = "$zeron.radius.7",
		border = 1,
		border_color = T.border,
		cursor = "pointer",
		focus = { border = 0 },
		on_click = props.on_click,
		txt.text { props.label or "Load more", size = "xs", color = T.secondary, line = false },
	}
end)

return M
