-- Git history (history.rs): a table of commits at 36 a row with the graph
-- drawn down its left on a canvas (lanes 12 apart, nodes of radius 3, the
-- HEAD ring 2 out, strokes 1.5), then the subject at 12 with ref badges 16
-- high in the lane's colour at 7%, and the columns: the author's 20 circle
-- with 9-point initials, the date at 10.5, the SHA in mono 10.5 on a 24 hit
-- area that copies it ("Copied" for 1.2 s). The 24-high header at 9.5 names
-- them; under its pointer a 20 button opens the Columns menu (each shown or
-- hidden, Reset), a column drags to another place, and the edge before it
-- resizes it (a double click puts the widths back). Under the pointer a
-- branch's tip shows a 16 button by its node that folds the branch's lane
-- (its plain commits hidden, "N hidden"). A 24×196 search field and a 28
-- load-more pill belong to the panel's chrome.
local T = require("../theme")
local wash = require("./wash")
local txt = require("./text")
local icon = require("./icon")
local tooltip = require("./tooltip")
local frost = require("./frost")
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
export type Column = "author" | "date" | "sha"
-- Which columns show, in what order (hidden ones keep their place) and
-- how wide (settings.rs GitHistoryColumns, GitHistoryColumnOrder,
-- GitHistoryColumnWidths).
export type Columns = {
	shown: { [string]: boolean },
	order: { Column },
	widths: { [string]: number },
}
export type Props = {
	id: string?,
	commits: { Commit },
	selected: State<string>?,
	-- A click opens the commit (its own diff, history.rs OpenCommit)
	-- rather than marking it.
	on_open: ((c: Commit) -> ())?,
	lanes: number?,
	w: Length?,
	columns: State<Columns>?,
	-- The branches folded shut, each with how many commits it hides, and
	-- what folding or opening one does; without `on_fold`, none fold.
	folded: { [string]: number }?,
	on_fold: ((ref: string) -> ())?,
}

local M = {}

M.ROW = 36
M.LANE = 12
M.NODE = 3
M.STROKE = 1.5
M.HEADER = 24

M.LABELS = { author = "Author", date = "Date", sha = "SHA" }
M.LIMITS = { author = { 44, 220 }, date = { 68, 180 }, sha = { 58, 140 } }

function M.default_columns(): Columns
	return {
		shown = { author = true, date = true, sha = true },
		order = { "author", "date", "sha" },
		widths = { author = 88, date = 88, sha = 74 },
	}
end

-- Whether `c` is as it starts (Reset has nothing to do).
function M.is_default(c: Columns): boolean
	local d = M.default_columns()
	for _, k in d.order do
		if c.shown[k] ~= d.shown[k] or c.widths[k] ~= d.widths[k] then
			return false
		end
	end
	return table.concat(c.order, ",") == table.concat(d.order, ",")
end

-- The columns shown, in order.
function M.visible(c: Columns): { Column }
	local out: { Column } = {}
	for _, k in c.order do
		if c.shown[k] then
			table.insert(out, k)
		end
	end
	return out
end

-- `c` with `column` moved to where `over` is among the columns.
function M.reorder(c: Columns, column: Column, over: Column): Columns
	local order = table.clone(c.order)
	local from, to = table.find(order, column), table.find(order, over)
	if not from or not to or from == to then
		return c
	end
	table.remove(order, from)
	table.insert(order, to, column)
	return { shown = c.shown, order = order, widths = c.widths }
end

-- A branch's name in a ref (remote branches and tags fold nothing).
function M.branch(ref: string): string?
	if string.match(ref, "^origin/") or string.match(ref, "^tag:") then
		return nil
	end
	return ref
end

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

local function node_x(lane: number): number
	return 6 + lane * M.LANE + M.LANE / 2
end

-- The graph: one canvas spanning every row. Each lane runs as one line
-- from a commit down to the next commit in that lane; a parent in another
-- lane curves over within the first row, then runs straight.
local function graph(commits: { Commit }, lanes: number): Node
	local width = lanes * M.LANE + 12
	local merges = 0
	for _, c in commits do
		if #c.parents > 1 then
			merges += 1
		end
	end
	return ui.canvas {
		-- The graph as a screen reader reads it (a chart, not decoration).
		label = `Commit graph: {#commits} commits in {lanes} {if lanes == 1 then "lane" else "lanes"}, {merges} {if merges
				== 1
			then "merge"
			else "merges"}`,
		absolute = true,
		top = 0,
		left = 0,
		w = width,
		h = #commits * M.ROW,
		pointer_events = "none",
		draw = function(cv: Canvas, _w: number, _h: number)
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
					local path = ui.path():move(node_x(c.lane), y(i))
					if p ~= c.lane then
						local midy = y(i) + M.ROW / 2
						path = path:cubic(node_x(c.lane), midy, node_x(p), midy, node_x(p), y(i + 1))
					end
					path = path:line(node_x(p), to_y)
					cv.stroke(cv, path, lane_color(p), M.STROKE, { cap = "round", join = "round" })
				end
			end
			for i, c in commits do
				local color = lane_color(c.lane)
				cv.circle(
					cv,
					node_x(c.lane),
					y(i),
					M.NODE + (if c.head then 2 else 0) + 1.5,
					tostring(ui.theme.get("zeron.card"))
				)
				if c.head then
					cv.stroke(cv, ui.path():arc(node_x(c.lane), y(i), M.NODE + 2, 0, 360), color, 1)
				end
				cv.circle(cv, node_x(c.lane), y(i), M.NODE, color)
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
		icon {
			name = if string.match(label, "^origin/") then "cloud" else "git-branch",
			size = 10,
			color = color,
			opacity = 0.78,
		},
		txt.text { label, size = "micro", color = color, opacity = 0.9, truncate = true, line = false },
	}
end

-- The fold by a tip's node: shown under the row's pointer, or while shut.
local function fold(c: Commit, ref: string, props: Props): Node
	local hidden = props.folded and props.folded[ref]
	local shut = hidden ~= nil
	local color = `$zeron.lane.{(c.lane % 6) + 1}`
	local label = if shut
		then `Expand {ref}{if hidden and hidden > 0 then ` ({hidden} hidden)` else ""}`
		else `Collapse {ref}`
	return ui.div {
		absolute = true,
		top = (M.ROW - 16) / 2,
		left = node_x(c.lane) + M.NODE + 3,
		tooltip {
			label = label,
			ui.button {
				id = props.id and `{props.id}_fold_{c.sha}`,
				label = label,
				w = 16,
				h = 16,
				p = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_full,
				border = 1,
				border_color = color,
				bg = T.card,
				focus = { border = 1 },
				cursor = "pointer",
				opacity = if shut then 1 else 0,
				group_hover = { opacity = 1 },
				on_click = function()
					(props.on_fold :: (string) -> ())(ref)
				end,
				icon { name = if shut then "expand-arrows" else "fold-vertical", size = 9, color = color },
			},
		},
	}
end

local function sha_cell(c: Commit, props: Props, width: () -> number, copied: State<string>, on: () -> boolean): Node
	return ui.row {
		w = width,
		h_full = true,
		pr = "$zeron.space.6",
		shrink = 1,
		items = "center",
		ui.button {
			id = props.id and `{props.id}_{c.sha}_sha`,
			label = `Copy {c.sha}`,
			w_full = true,
			h = 24,
			px = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.4",
			bg = T.clear,
			hover = { bg = T.ink3 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = function()
				ui.clipboard.write(c.sha)
				copied:set(c.sha)
				ui.after(1200, function()
					if copied:peek() == c.sha then
						copied:set("")
					end
				end)
			end,
			txt.text {
				function()
					return if copied:get() == c.sha then "Copied" else string.sub(c.sha, 1, 7)
				end,
				size = "micro",
				mono = true,
				line = false,
				color = "inherit",
				variants = recipes.sha {
					selected = function()
						return copied:get() == c.sha or on()
					end,
				},
			},
		},
	}
end

local function row(
	c: Commit,
	props: Props,
	group: string,
	gw: number,
	columns: State<Columns>,
	copied: State<string>
): Node
	local function on(): boolean
		return props.selected ~= nil and props.selected:get() == c.sha
	end
	local refs: { Node } = {}
	local tip: string? = nil
	for _, r in c.refs or {} do
		table.insert(refs, badge(r, `$zeron.lane.{(c.lane % 6) + 1}`))
		tip = tip or M.branch(r)
	end
	local cells: { Node } = {}
	for _, k in M.visible(columns:peek()) do
		-- Followed as a column is resized, without building the row again.
		local function width(): number
			return columns:get().widths[k]
		end
		if k == "author" then
			table.insert(
				cells,
				ui.row {
					w = width,
					h_full = true,
					shrink = 1,
					items = "center",
					justify = "center",
					tooltip {
						label = c.author,
						ui.row {
							w = 20,
							h = 20,
							items = "center",
							justify = "center",
							rounded = "$zeron.radius.10",
							bg = T.ink3,
							border = 1,
							border_color = T.ink4,
							txt.text { initials(c.author), size = "micro", color = T.tertiary, line = false },
						},
					},
				}
			)
		elseif k == "date" then
			table.insert(
				cells,
				txt.text {
					c.date,
					literal = true,
					size = "micro",
					color = T.secondary,
					truncate = true,
					line = false,
					w = width,
					shrink = 1,
				}
			)
		else
			table.insert(cells, sha_cell(c, props, width, copied, on))
		end
	end
	return ui.button(wash.item(group, {
		id = props.id and `{props.id}_{c.sha}`,
		w_full = true,
		h = M.ROW,
		pl = ui.raw(gw, "the graph's width"),
		items = "center",
		cursor = "pointer",
		focus = { border = 0 },
		on_click = if props.on_open
			then function()
				(props.on_open :: (Commit) -> ())(c)
			end
			elseif props.selected then ui.set(props.selected, c.sha)
			else nil,
		ui.row {
			grow = 1,
			shrink = 1,
			min_w = 80,
			gap = "$zeron.space.5",
			pr = "$zeron.space.8",
			items = "center",
			txt.text { c.subject, size = "sm", truncate = true, line = false, shrink = 1, min_w = 0 },
			refs,
		},
		cells,
		if tip and props.on_fold then fold(c, tip, props) else nil,
	}))
end

-- The Columns menu: a 132 card, each column with its check, Reset under a
-- hairline while anything differs from the start.
local function columns_menu(id: string, open: State<boolean>, columns: State<Columns>, anchor: Node): Node
	local function option(k: Column): Node
		return ui.button {
			id = `{id}_{k}`,
			w_full = true,
			px = "$zeron.space.7",
			py = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.6",
			variants = recipes.picker_choice {},
			color = T.text,
			focus = { border = 0 },
			cursor = "pointer",
			on_click = function()
				local c = columns:peek()
				local shown = table.clone(c.shown)
				shown[k] = not shown[k]
				columns:set { shown = shown, order = c.order, widths = c.widths }
			end,
			txt.text { M.LABELS[k], size = "sm", color = "inherit", line = false, grow = 1 },
			ui.row {
				w = 12,
				justify = "end",
				icon {
					name = "check",
					size = 10,
					color = T.secondary,
					hidden = function()
						return not columns:get().shown[k]
					end,
				},
			},
		}
	end
	return ui.popover {
		id = id,
		open = open,
		label = "Columns",
		anchor = anchor,
		w = 132,
		p = T.space(frost.INSET),
		gap = "$zeron.space.2",
		rounded = "$zeron.radius.9",
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		placement = { side = "bottom", align = "end", offset = 4 },
		option("author"),
		option("date"),
		option("sha"),
		ui.show(
			function()
				return not M.is_default(columns:get())
			end,
			ui.column {
				w_full = true,
				gap = "$zeron.space.2",
				ui.div { h = 1, mx = "$zeron.space.5", my = "$zeron.space.2", bg = T.hairline },
				ui.button {
					id = `{id}_reset`,
					w_full = true,
					px = "$zeron.space.7",
					py = "$zeron.space.4",
					items = "center",
					rounded = "$zeron.radius.6",
					variants = recipes.picker_choice {},
					color = T.secondary,
					focus = { border = 0 },
					cursor = "pointer",
					on_click = function()
						columns:set(M.default_columns())
						open:set(false)
					end,
					txt.text { "Reset", size = "sm", color = "inherit", line = false },
				},
			}
		),
	}
end

local function header(id: string?, gw: number, columns: State<Columns>): Node
	local menu_open = ui.use_state(false)
	local function cell(k: Column, index: number, left: Column?): Node
		-- The edge before a column resizes it: against the subject (it
		-- alone), or against the column before it (the two trade width).
		local start: { x: number, w: number, lw: number }? = nil
		local function resize(e: PointerEvent)
			local s = start
			if not s then
				return
			end
			local c = columns:peek()
			local widths = table.clone(c.widths)
			local dx = e.x - s.x
			local lo, hi = M.LIMITS[k][1], M.LIMITS[k][2]
			if left then
				local llo, lhi = M.LIMITS[left][1], M.LIMITS[left][2]
				dx = math.clamp(dx, math.max(llo - s.lw, s.w - hi), math.min(lhi - s.lw, s.w - lo))
				widths[left] = s.lw + dx
				widths[k] = s.w - dx
			else
				widths[k] = math.clamp(s.w - dx, lo, hi)
			end
			columns:set { shown = c.shown, order = c.order, widths = widths }
		end
		return ui.row {
			id = id and `{id}_col_{k}`,
			relative = true,
			w = function(): number
				return columns:get().widths[k]
			end,
			h_full = true,
			shrink = 1,
			items = "center",
			justify = if k == "author" then "center" else "start",
			cursor = "pointer",
			on_drag = function()
				return { history_column = k }
			end,
			drag_preview = function(): Node
				return ui.row {
					h = 22,
					px = "$zeron.space.8",
					items = "center",
					rounded = "$zeron.radius.5",
					bg = T.frost,
					border = 1,
					border_color = T.border,
					txt.text { M.LABELS[k], size = "micro", color = T.text, line = false },
				}
			end,
			drop_when = function(payload: any): boolean
				return type(payload) == "table" and payload.history_column ~= nil and payload.history_column ~= k
			end,
			on_drop = function(payload: any)
				columns:set(M.reorder(columns:peek(), payload.history_column, k))
			end,
			txt.text { M.LABELS[k], size = "micro", color = T.tertiary, line = false },
			ui.div {
				id = id and `{id}_resize_{k}`,
				absolute = true,
				top = 0,
				bottom = 0,
				left = -3,
				w = 6,
				cursor = "col_resize",
				bg = T.clear,
				hover = { bg = T.border },
				on_press = function(e: PointerEvent)
					local c = columns:peek()
					if (e :: any).clicks == 2 then
						local widths = M.default_columns().widths
						columns:set { shown = c.shown, order = c.order, widths = widths }
						start = nil
						return
					end
					start = { x = e.x, w = c.widths[k], lw = if left then c.widths[left] else 0 }
				end,
				on_press_move = resize,
				on_release = function()
					start = nil
				end,
			},
		}
	end
	local menu_button = ui.button {
		id = id and `{id}_columns`,
		label = "Columns",
		w = 20,
		h = 20,
		p = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.5",
		bg = T.clear,
		hover = { bg = T.ink3 },
		focus = { border = 0 },
		cursor = "pointer",
		opacity = function()
			return if menu_open:get() then 1 else 0
		end,
		group_hover = { opacity = 1 },
		on_click = ui.toggle(menu_open),
		icon { name = "checklist", size = 12, color = T.secondary },
	}
	return ui.row {
		w_full = true,
		h = M.HEADER,
		relative = true,
		hover_group = true,
		pl = ui.raw(gw, "the graph's width"),
		items = "center",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		-- As wide as a row's subject (its 80 and its 8 after), so the columns line up.
		ui.row {
			grow = 1,
			shrink = 1,
			min_w = 80,
			pr = "$zeron.space.8",
			txt.text { "Commit", size = "micro", color = T.tertiary, line = false },
		},
		ui.presence(function(): string
			return table.concat(M.visible(columns:get()), ",")
		end, function(): Node
			local cells: { Node } = {}
			local shown = M.visible(columns:peek())
			for i, k in shown do
				table.insert(cells, cell(k, i, shown[i - 1]))
			end
			return ui.row { h_full = true, shrink = 1, cells }
		end, { h_full = true, shrink = 1 }),
		ui.div {
			absolute = true,
			right = 3,
			top = 2,
			tooltip {
				label = "Columns",
				columns_menu(id and `{id}_columns_menu` or "history_columns_menu", menu_open, columns, menu_button),
			},
		},
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
	local columns = props.columns or ui.use_state(M.default_columns())
	local copied = ui.use_state("")
	local group = wash.group("history")
	local gw = lanes * M.LANE + 12
	return ui.column {
		id = props.id,
		w = props.w,
		w_full = props.w == nil,
		header(props.id, gw, columns),
		ui.presence(function(): string
			-- Built again as columns show, hide or move.
			return table.concat(M.visible(columns:get()), ",")
		end, function(): Node
			local rows: { Node } = {}
			for _, c in props.commits do
				table.insert(rows, row(c, props, group, gw, columns, copied))
			end
			return ui.column {
				w_full = true,
				relative = true,
				graph(props.commits, lanes),
				wash.list { group = group, w_full = true, color = T.ink1, rows },
			}
		end, { w_full = true }),
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
