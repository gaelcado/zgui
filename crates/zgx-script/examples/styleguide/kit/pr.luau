-- Pull requests (pull_requests.rs): groups as one card on wash 4.5% at
-- radius 12; rows of at least 64 with a title line (14-point glyph, 13
-- text), a meta line at 11 (avatar 16, login, badges 16 high, checks,
-- status), a 112 column of date and diff stats, and a 28 star. Skeletons
-- (pull_request_skeleton.rs) stand in for the board, the detail's Summary,
-- its diff and its file tree while they load, their bars breathing on the
-- 2.4 s pulse. The detail's pieces: the status chip, its field rows, its
-- icon actions and the floating section navigation.
local T = require("../theme")
local disclosure = require("./disclosure")
local wash = require("./wash")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")
local avatar = require("./avatar")
local loaders = require("./loaders")

export type Status = "open" | "draft" | "conflicting" | "changes" | "merged"
export type Checks = "passed" | "failed" | "pending" | nil
export type Row = {
	id: string,
	title: string,
	number: number,
	author: string,
	status: Status,
	checks: Checks,
	sha: string?,
	date: string,
	-- Minutes since it was last updated and since it was opened (sorting).
	updated: number?,
	opened: number?,
	added: number,
	removed: number,
	labels: { string }?,
	starred: boolean?,
}
export type RowProps = {
	row: Row,
	first: boolean?,
	selected: types.Cond?,
	on_click: (Handler | Action)?,
	-- Starred (a local preference, read where it changes), and its toggle.
	starred: (() -> boolean)?,
	on_star: Handler?,
	id: string?,
	-- The group's list (`GroupProps.list`): the row washes as its rows do.
	group: string?,
	-- Narrow (a board under 640): the counts, the date and the star in a
	-- line under the identity, rather than a column beside it.
	narrow: types.Cond?,
	-- The date as the board's sort reads it ("Opened 3d ago"), over `row.date`.
	date: string?,
}
export type GroupProps = {
	id: string?,
	label: string,
	count: number?,
	open: State<boolean>,
	[number]: Child,
	w: Length?,
	-- The rows' list group: each washes under the pointer (kit/wash).
	list: string?,
}

local M = {}

M.MIN_ROW = 64
M.META_INDENT = 22
M.SIDE = 112

local function glyph_color(s: Status): Color
	return if s == "draft"
		then T.secondary
		elseif s == "conflicting" then T.danger
		elseif s == "changes" then T.warning
		else T.success
end

local function badge(label: string, color: Color): Node
	return ui.row {
		h = 16,
		px = "$zeron.space.4",
		items = "center",
		rounded = "$zeron.radius.4",
		bg = T.ink2,
		txt.text { label, size = "micro", weight = "medium", color = color, line = false, opacity = 0.85 },
	}
end

M.row = ui.component(function(props: RowProps): Node
	local r = props.row
	local checks = if r.checks == "failed"
		then T.danger_muted
		elseif r.checks == "passed" then T.success_muted
		else T.secondary
	local labels: { Node } = {}
	for _, l in r.labels or {} do
		table.insert(labels, badge(l, T.secondary))
	end
	local function identity(): Node
		return ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.6",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				icon {
					name = if r.status == "draft" then "pull-request-draft" else "pull-request",
					size = 14,
					color = glyph_color(r.status),
				},
				txt.text { r.title, size = "md", truncate = true, line = false, shrink = 1, min_w = 0 },
				txt.text { `#{r.number}`, size = "md", color = T.tertiary, line = false, shrink = 0 },
			},
			ui.row {
				pl = T.space(M.META_INDENT),
				gap = "$zeron.space.8",
				items = "center",
				flex_wrap = true,
				ui.row {
					gap = "$zeron.space.5",
					items = "center",
					avatar.avatar { name = r.author, size = 16 },
					txt.text {
						r.author,
						size = "xs",
						color = T.secondary,
						line = false,
						truncate = true,
						max_w = 150,
					},
				},
				labels,
				r.checks
					and txt.text {
						`{if r.checks == "failed" then "Failed" elseif r.checks == "passed" then "Passed" else "Pending"} · {r.sha or "—"}`,
						size = "xs",
						color = checks,
						line = false,
					},
				txt.text {
					if r.status == "conflicting"
						then "Conflicts"
						elseif r.status == "changes" then "Changes requested"
						elseif r.status == "draft" then "Draft"
						elseif r.status == "merged" then "Merged"
						else "Open",
					size = "xs",
					line = false,
					color = if r.status == "conflicting"
						then T.danger_muted
						elseif r.status == "changes" then T.warning
						else T.secondary,
				},
			},
		}
	end
	local function stats(): Node
		return ui.row {
			gap = "$zeron.space.8",
			txt.text { `+{r.added}`, size = "xs", mono = true, color = T.success_muted, line = false },
			txt.text { `−{r.removed}`, size = "xs", mono = true, color = T.danger_muted, line = false },
		}
	end
	local function date(): Node
		return txt.text { props.date or r.date, size = "xs", color = T.secondary, line = false }
	end
	local function star(): Node
		return M.star { id = props.id and `{props.id}_star`, starred = props.starred, on_click = props.on_star }
	end
	local function narrow(): boolean
		return props.narrow ~= nil and types.on(props.narrow)
	end
	return ui.button(wash.maybe(props.group, {
		variants = recipes.wash { hover = "glass" },
		id = props.id,
		w_full = true,
		min_h = M.MIN_ROW,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		items = "start",
		cursor = "pointer",
		focus = { border = 0 },
		border_sides = if props.first == false then { 1, 0, 0, 0 } else nil,
		border_color = T.hairline,
		on_click = props.on_click,
		ui.presence(function()
			return if narrow() then "narrow" else "wide"
		end, function(layout: string): Node
			if layout == "narrow" then
				return ui.column {
					w_full = true,
					gap = "$zeron.space.8",
					identity(),
					ui.row {
						pl = T.space(M.META_INDENT),
						gap = "$zeron.space.8",
						items = "center",
						stats(),
						ui.div { grow = 1 },
						date(),
						star(),
					},
				}
			end
			return ui.row {
				w_full = true,
				gap = "$zeron.space.16",
				items = "start",
				identity(),
				ui.column {
					w = M.SIDE,
					shrink = 0,
					gap = "$zeron.space.4",
					items = "end",
					date(),
					stats(),
				},
				star(),
			}
		end, { w_full = true }),
	}))
end)

-- A tooltip's bubble on the control itself.
local function tip(label: Text): Node
	return ui.row { variants = recipes.tooltip { keys = false }, txt.text { label, size = "sm", line = false } }
end
M.tip = tip

-- The star (star_button): 28, radius 6, the glass wash under the pointer;
-- the bold star in the warning tone while starred.
export type StarProps = { id: string?, starred: (() -> boolean)?, on_click: Handler? }
function M.star(props: StarProps): Node
	local function on(): boolean
		return props.starred ~= nil and props.starred()
	end
	return ui.button {
		id = props.id,
		w = 28,
		h = 28,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		variants = recipes.wash { hover = "glass" },
		focus = { border = 0 },
		cursor = "pointer",
		label = function()
			return if on() then "Unstar pull request" else "Star pull request"
		end,
		tooltip = tip(function()
			return if on() then "Unstar pull request" else "Star pull request"
		end),
		on_click = props.on_click,
		ui.presence(function()
			return if on() then "on" else "off"
		end, function(state: string): Node
			return icon {
				name = if state == "on" then "star-bold" else "star",
				size = 14,
				color = if state == "on" then T.warning else T.secondary,
			}
		end),
	}
end

-- A group: its header (chevron turning 280 ms, label 13 muted, count 11)
-- and the card of rows under it.
M.group = ui.component(function(props: GroupProps): Node
	-- zgx's disclosure: the header its summary button.
	return ui.disclosure {
		id = props.id,
		open = props.open,
		bare = true,
		w = props.w,
		w_full = props.w == nil,
		gap = "$zeron.space.8",
		summary = ui.button {
			variants = recipes.wash { hover = "ink1" },
			id = props.id and `{props.id}_header`,
			min_h = 24,
			px = "$zeron.space.8",
			py = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			self = "start",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			txt.text { props.label, size = "md", color = "inherit", line = false },
			props.count and txt.text { tostring(props.count), size = "xs", color = T.tertiary, line = false },
			disclosure.chevron { open = props.open, size = 14 },
		},
		ui.presence(function()
			return if props.open:get() then "rows" else nil
		end, function(): Node
			local rows = { table.unpack(props) }
			return ui.column {
				w_full = true,
				rounded = T.radius_card,
				bg = T.card,
				overflow = "hidden",
				if props.list then wash.list { group = props.list, color = T.glass_hover, rows } else rows,
			}
		end, {
			w_full = true,
			layout = "height",
			enter = { opacity = { 0, 1 }, duration = motion.d(motion.COLLAPSE), ease = motion.EASE_OUT },
			exit = { opacity = 0, duration = motion.d(motion.COLLAPSE), ease = motion.EASE_OUT },
		}),
	}
end)

-- Skeletons (pull_request_skeleton.rs): shaped like what they stand in
-- for, so nothing moves when it arrives. A bar is ink 7% at a radius of
-- half its height, breathing 0.45 to 0.85 on the loaders' pulse, `index`
-- staggering it 8% of the cycle a step down a column (still under reduced
-- motion).
function M.bar(w: Length, h: number, index: number?): Node
	return ui.div {
		w = w,
		h = h,
		shrink = 0,
		rounded = T.radius_full,
		bg = T.skeleton_board,
		opacity = 0.45,
		on_mount = function(el: Element)
			loaders.breathe(el, 0.45, 0.85, (index or 0) * loaders.PULSE_STAGGER)
		end,
	}
end
local bar = M.bar

local WIDTHS = { 0.62, 0.48, 0.71, 0.55, 0.39, 0.66 }
local function pct(f: number): string
	return `{math.floor(f * 1000 + 0.5) / 10}%`
end

-- The board's (board): a group label's bar over a card of six rows, each
-- the row's shape; narrow, the date and counts under the identity.
export type SkeletonProps = { id: string?, rows: number?, w: Length?, narrow: types.Cond? }
M.skeleton = ui.component(function(props: SkeletonProps): Node
	local p: SkeletonProps = props or {}
	local count = p.rows or 6
	local function narrow(): boolean
		return types.on(p.narrow)
	end
	local function row(i: number, layout: string): Node
		local index = i - 1
		local identity = ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.4",
			ui.row {
				h = 20,
				gap = "$zeron.space.8",
				items = "center",
				bar(14, 14, index),
				bar(pct(WIDTHS[(i - 1) % #WIDTHS + 1]), 12, index),
			},
			ui.row {
				pl = T.space(M.META_INDENT),
				gap = "$zeron.space.8",
				items = "center",
				flex_wrap = true,
				bar(16, 16, index),
				bar(72, 10, index),
				bar(52, 16, index),
				bar(120, 12, index),
			},
		}
		local tail: { Node } = if layout == "narrow"
			then {
				ui.row {
					pl = T.space(M.META_INDENT),
					h = 28,
					gap = "$zeron.space.8",
					items = "center",
					bar(72, 10, index),
					ui.div { grow = 1 },
					bar(44, 10, index),
					ui.row { w = 28, h = 28, items = "center", justify = "center", bar(14, 14, index) },
				},
			}
			else {
				ui.column {
					w = M.SIDE,
					shrink = 0,
					items = "end",
					gap = "$zeron.space.4",
					ui.row { h = 16, items = "center", bar(44, 10, index) },
					ui.row { h = 16, items = "center", bar(72, 10, index) },
				},
				ui.row { w = 28, h = 28, shrink = 0, items = "center", justify = "center", bar(14, 14, index) },
			}
		local props: ContainerProps = {
			w_full = true,
			min_h = M.MIN_ROW,
			px = "$zeron.space.16",
			py = "$zeron.space.12",
			gap = if layout == "narrow" then "$zeron.space.8" else "$zeron.space.16",
			items = if layout == "narrow" then "stretch" else "center",
			border_sides = if i > 1 then { 1, 0, 0, 0 } else nil,
			border_color = T.hairline,
			identity,
			tail,
		}
		return if layout == "narrow" then ui.column(props) else ui.row(props)
	end
	local card = ui.presence(function()
		return if narrow() then "narrow" else "wide"
	end, function(layout: string): Node
		local rows: { Node } = {}
		for i = 1, count do
			table.insert(rows, row(i, layout))
		end
		return ui.column { w_full = true, rounded = T.radius_card, bg = T.card, overflow = "hidden", rows }
	end, { w_full = true })
	return ui.column {
		id = p.id,
		w = p.w,
		w_full = p.w == nil,
		gap = "$zeron.space.8",
		role = "status",
		label = "Loading pull requests",
		ui.row { min_h = 24, px = "$zeron.space.8", items = "center", bar(120, 10, 0) },
		card,
	}
end)

-- A card of rows (section_card): radius 12 on wash 4.5%.
export type CardProps = { id: string?, [number]: Child, mt: Length? }
function M.card(props: CardProps): Node
	return ui.column {
		id = props.id,
		w_full = true,
		mt = props.mt,
		rounded = T.radius_card,
		bg = T.ink1,
		overflow = "hidden",
		{ table.unpack(props) },
	}
end

-- A card's row (card_row): 16 in at its sides, 12 over and under, at
-- least 60 high, a hairline above all but the first, inset to the text;
-- its parts wrap.
export type CardRowProps = {
	id: string?,
	first: boolean?,
	min_h: number?,
	py: Length?,
	wrap: boolean?,
	[number]: Child,
}
function M.card_row(props: CardRowProps): Node
	return ui.row {
		id = props.id,
		mx = "$zeron.space.16",
		py = props.py or "$zeron.space.12",
		min_h = props.min_h or 60,
		gap = "$zeron.space.16",
		items = "center",
		flex_wrap = props.wrap ~= false,
		border_sides = if props.first then nil else { 1, 0, 0, 0 },
		border_color = T.hairline,
		{ table.unpack(props) },
	}
end

-- A row's title: 13 medium.
function M.row_title(label: Text): Node
	return txt.text { label, size = "md", weight = "medium", line = false }
end

-- A field (field_row): its label in an 80 column, its value beside it;
-- at least 44 high, 8 over and under.
export type FieldProps = { id: string?, label: string, first: boolean?, [number]: Child }
function M.field(props: FieldProps): Node
	return M.card_row {
		id = props.id,
		first = props.first,
		min_h = 44,
		py = "$zeron.space.8",
		ui.row { w = 80, shrink = 0, items = "center", M.row_title(props.label) },
		ui.row { grow = 1, basis = 0, min_w = 120, items = "center", { table.unpack(props) } },
	}
end

-- The Summary's (summary): its cards in their places under the header.
local function skeleton_field(label: string, w: Length, h: number, index: number, first: boolean): Node
	return M.field { label = label, first = first, bar(w, h, index) }
end
function M.summary_skeleton(props: { id: string?, gap: number }): Node
	local lines: { Node } = {}
	for i = 0, 4 do
		table.insert(lines, bar(if i == 4 then "40%" else "92%", 10, i))
	end
	return ui.column {
		id = props.id,
		w_full = true,
		mt = "$zeron.space.24",
		gap = T.space(props.gap),
		role = "status",
		label = "Loading pull request",
		M.card {
			skeleton_field("Status", 96, 22, 0, true),
			skeleton_field("Review", 96, 22, 1, false),
			skeleton_field("Branch", 220, 12, 2, false),
			skeleton_field("Changes", 96, 12, 3, false),
		},
		M.card {
			M.card_row {
				first = true,
				ui.column {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.6",
					M.row_title("Current assessment"),
					bar("60%", 14, 4),
					bar("40%", 14, 4),
					bar(100, 13, 4),
				},
				ui.row { w = 28, h = 28, shrink = 0, items = "center", justify = "center", bar(14, 14, 4) },
			},
		},
		M.card {
			ui.row {
				px = "$zeron.space.16",
				py = "$zeron.space.10",
				gap = "$zeron.space.8",
				items = "center",
				bar(14, 14, 4),
				txt.text { "Checks", size = "md", grow = 1, line = false },
				bar(72, 22, 4),
			},
		},
		M.card {
			M.card_row {
				first = true,
				ui.column {
					grow = 1,
					basis = 0,
					min_w = 220,
					gap = "$zeron.space.2",
					M.row_title("Hand off to an agent"),
					txt.text { "Opens a new session with the prompt ready to send.", size = "sm", color = T.secondary },
				},
				bar(180, 28, 5),
			},
			M.card_row {
				ui.row { grow = 1, basis = 0, min_w = 120, M.row_title("Verification") },
				ui.row { grow = 1, basis = 0, min_w = 0, bar("80%", 28, 6) },
			},
			skeleton_field("Checkout", "70%", 12, 6, false),
		},
		M.card { ui.column { w_full = true, p = "$zeron.space.16", gap = "$zeron.space.12", lines } },
	}
end

-- The diff's (diff): a file header, a hunk header and fourteen lines,
-- unified or split, in the stream's card.
M.FILE_HEADER = 38
local function code_cell(index: number, split: boolean): Node
	local function gutter(): Node
		return ui.row { w = 36, shrink = 0, pr = "$zeron.space.8", justify = "end", bar(12, 8, index) }
	end
	return ui.row {
		h = 21,
		grow = 1,
		basis = 0,
		min_w = 0,
		items = "center",
		overflow = "hidden",
		ui.div { w = 3, shrink = 0 },
		gutter(),
		if split then nil else gutter(),
		ui.div { w = if split then 18 else 28, shrink = 0 },
		ui.row {
			grow = 1,
			min_w = 0,
			pl = if split then "$zeron.space.6" else "$zeron.space.12",
			bar(pct(WIDTHS[index % #WIDTHS + 1]), 8, index),
		},
	}
end
function M.diff_skeleton(props: { id: string?, split: boolean? }): Node
	local split = props.split == true
	local lines: { Node } = {}
	for i = 0, 13 do
		table.insert(
			lines,
			ui.row {
				h = 21,
				w_full = true,
				code_cell(i, split),
				if split then ui.div { w = 1, h_full = true, shrink = 0, bg = T.border } else nil,
				if split then code_cell(i, split) else nil,
			}
		)
	end
	return ui.column {
		id = props.id,
		w_full = true,
		h_full = true,
		role = "status",
		label = "Loading diff",
		ui.row {
			h = M.FILE_HEADER,
			w_full = true,
			shrink = 0,
			px = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			bg = T.ink1,
			bar(13, 13, 0),
			bar(14, 14, 0),
			ui.row { grow = 1, min_w = 0, bar("55%", 10, 0) },
			bar(64, 10, 0),
			bar(24, 24, 0),
		},
		ui.row { h = 28, shrink = 0, px = "$zeron.space.12", items = "center", bar(180, 10, 0) },
		lines,
	}
end

-- The file tree's (tree): twelve rows, three of each four nested.
function M.tree_skeleton(props: { id: string? }): Node
	local rows: { Node } = {}
	for i = 0, 11 do
		local nested = i % 4 ~= 0
		table.insert(
			rows,
			ui.row {
				h = 28,
				shrink = 0,
				pl = if nested then "$zeron.space.22" else "$zeron.space.8",
				pr = "$zeron.space.8",
				gap = "$zeron.space.6",
				items = "center",
				bar(14, 14, i),
				bar(pct(WIDTHS[i % #WIDTHS + 1] * 0.7), 10, i),
			}
		)
	end
	return ui.column { id = props.id, w_full = true, gap = "$zeron.space.1", rows }
end

-- The status chip (pull_request_detail.rs): padding 8×3, radius 6, a 14
-- icon in the tone, the tone at 8% behind; and the PR badge
-- (change_requests.rs): 16 high in the sidebar, 20 in the composer, the
-- tone at 8% (16% hovered), its text at 85%, the number in mono.
export type Tone =
	"open"
	| "approved"
	| "passed"
	| "merged"
	| "closed"
	| "failed"
	| "changes"
	| "awaiting"
	| "pending"
	| "draft"
local TONE: { [Tone]: { color: Color, wash: Color, icon: icon_mod.Name, label: string } } = {
	open = { color = T.success, wash = T.success_wash, icon = "pull-request", label = "Open" },
	approved = { color = T.success, wash = T.success_wash, icon = "check", label = "Approved" },
	passed = { color = T.success, wash = T.success_wash, icon = "check", label = "Passed" },
	merged = { color = T.accent, wash = T.accent_wash, icon = "pull-request", label = "Merged" },
	closed = { color = T.danger, wash = T.danger_wash, icon = "close-circle", label = "Closed" },
	failed = { color = T.danger, wash = T.danger_wash, icon = "danger-triangle", label = "Failure" },
	changes = { color = T.warning, wash = T.warning_wash, icon = "danger-triangle", label = "Changes requested" },
	awaiting = { color = T.warning, wash = T.warning_wash, icon = "clock-circle", label = "Awaiting review" },
	pending = { color = T.warning, wash = T.warning_wash, icon = "clock-circle", label = "Pending" },
	draft = { color = T.secondary, wash = T.ink2, icon = "document", label = "Draft" },
}
M.TONE = TONE

-- `raw`: a status as GitHub reports it (OPEN, CHANGES_REQUESTED, FAILURE,
-- in_progress…), read as status_style reads it; else `tone` and `label`.
export type ChipProps = { id: string?, tone: Tone?, label: string?, raw: string? }
M.status_chip = ui.component(function(props: ChipProps): Node
	local tone: Tone = props.tone or "draft"
	local label: string? = props.label
	local glyph: icon_mod.Name? = nil
	if props.raw then
		tone, label, glyph = M.status(props.raw)
	end
	local t = TONE[tone]
	return ui.row {
		id = props.id,
		shrink = 0,
		px = "$zeron.space.8",
		py = "$zeron.space.3",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = t.wash,
		icon { name = glyph or t.icon, size = 14, color = t.color },
		txt.text { label or t.label, size = "sm", line = false },
	}
end)

-- "CHANGES_REQUESTED" as words: "Changes requested".
function M.humanize(raw: string): string
	local text = string.lower((string.gsub(raw, "_", " ")))
	if text == "" then
		return "Not reported"
	end
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- A raw status's tone, words and glyph (status_style).
function M.status(raw: string): (Tone, string, icon_mod.Name)
	local key = string.upper((string.gsub(raw, " ", "_")))
	if key == "OPEN" then
		return "open", "Open", "pull-request"
	elseif key == "MERGED" then
		return "merged", "Merged", "pull-request"
	elseif key == "CLOSED" then
		return "closed", "Closed", "close-circle"
	elseif key == "DRAFT" then
		return "draft", "Draft", "document"
	elseif key == "APPROVED" then
		return "approved", "Approved", "check"
	elseif key == "SUCCESS" then
		return "passed", "Passed", "check"
	elseif key == "FAILURE" or key == "ERROR" or key == "TIMED_OUT" or key == "ACTION_REQUIRED" then
		return "failed", M.humanize(raw), "close-circle"
	elseif key == "CHANGES_REQUESTED" then
		return "changes", "Changes requested", "danger-triangle"
	elseif key == "REVIEW_REQUIRED" then
		return "awaiting", "Awaiting review", "clock-circle"
	elseif key == "IN_PROGRESS" or key == "PENDING" or key == "QUEUED" or key == "WAITING" then
		return "pending", M.humanize(raw), "clock-circle"
	end
	return "draft", M.humanize(raw), "document"
end

-- An icon action (pull_request_detail.rs action): 24 at radius 6, its
-- glyph 14 in the muted text, the glass wash under the pointer, named by
-- its tooltip; `dim` at 40% (nothing to step to, a load running).
export type ActionProps = {
	id: string,
	label: string | () -> string,
	icon: Reactive<icon_mod.Name>,
	on_click: (Handler | Action)?,
	dim: types.Cond?,
	selected: types.Cond?,
}
function M.action(props: ActionProps): Node
	local glyph = props.icon
	return ui.button {
		id = props.id,
		w = 24,
		h = 24,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		variants = recipes.pr_action {
			on = if props.selected ~= nil
				then function()
					return types.on(props.selected)
				end
				else false,
		},
		focus = { border = 0 },
		cursor = "pointer",
		label = props.label,
		tooltip = tip(props.label),
		opacity = if props.dim ~= nil
			then function()
				return if types.on(props.dim) then 0.4 else 1
			end
			else nil,
		on_click = props.on_click,
		if type(glyph) == "function"
			then ui.presence(glyph, function(name: icon_mod.Name): Node
				return icon { name = name, size = 14, color = T.secondary }
			end)
			else icon { name = glyph :: icon_mod.Name, size = 14, color = T.secondary },
	}
end

-- The detail's sections (navigation): a floating pill in the composer's
-- material, 16 over the column's foot, three equal segments 36 high, each
-- 2 inside its slot, its glyph 14 and its label 12 medium with a count at
-- 11; a raised thumb (the glass wash, the selected shadow) glides under the
-- chosen one over 150 ms, in the engine. The arrows, Home and End move the
-- choice. The pill's corners are its segments' plus their insets.
export type NavTab = { id: string, label: string, icon: icon_mod.Name, count: (() -> number?)? }
export type NavProps = { id: string, value: State<string>, tabs: { NavTab } }
M.NAV_SEGMENT = 36
M.NAV_INSET = 2
M.NAV_PADDING = 2
M.NAV_HEIGHT = M.NAV_SEGMENT + 2 * (M.NAV_INSET + M.NAV_PADDING) + 2
-- The room the floating pill takes at a column's foot: its 16 inset, its
-- height and 16 of air.
M.NAV_CLEARANCE = 16 + M.NAV_HEIGHT + 16
M.nav = ui.component(function(props: NavProps): Node
	local n = #props.tabs
	local track = ui.ref()
	local function slot(): number
		local v = props.value:get()
		for i, t in props.tabs do
			if t.id == v then
				return i - 1
			end
		end
		return 0
	end
	local x = ui.computed(function(): number
		return slot() * (track.width or 0) / n
	end)
	local position = ui.computed(slot)
	local glide = { duration = motion.d(motion.TAB_SLIDE), ease = motion.EASE_OUT }
	local options: { any } = {}
	for i, t in props.tabs do
		local function on(): boolean
			return props.value:get() == t.id
		end
		local function face(lit: boolean): { Node }
			local out: { Node } = {
				icon { name = t.icon, size = 14, color = if lit then T.text else "currentColor", shrink = 0 },
				txt.text {
					t.label,
					size = "sm",
					weight = "medium",
					color = if lit then T.text else "inherit",
					line = false,
				},
			}
			local count = t.count
			if count then
				table.insert(
					out,
					ui.presence(function()
						local c = count()
						return if c and c > 0 then tostring(c) else nil
					end, function(n: string): Node
						return txt.text { n, size = "xs", color = T.secondary, line = false }
					end)
				)
			end
			return out
		end
		-- The label in the text over its muted copy, as much as the thumb
		-- covers its slot (1 − |thumb − slot|, nothing a slot away): two
		-- ramps on the gliding position, clamped by opacity and multiplied
		-- down the tree, in the engine.
		local at = i - 1
		options[i] = {
			value = t.id,
			label = t.label,
			id = `{props.id}_{t.id}`,
			p = T.space(M.NAV_INSET),
			min_w = 0,
			bg = T.clear,
			border = 0,
			focus = { border = 0 },
			cursor = "pointer",
			ui.row {
				relative = true,
				h = M.NAV_SEGMENT,
				w_full = true,
				px = "$zeron.space.14",
				gap = "$zeron.space.6",
				items = "center",
				justify = "center",
				rounded = T.radius_full,
				variants = recipes.pr_nav_segment { on = on },
				face(false),
				ui.div {
					id = `{props.id}_{t.id}_cover`,
					absolute = true,
					left = 0,
					top = 0,
					right = 0,
					bottom = 0,
					pointer_events = "none",
					opacity = ui.tween(
						position,
						{ from = 1 - at, to = 2 - at, duration = glide.duration, ease = glide.ease }
					),
					ui.row {
						id = `{props.id}_{t.id}_lit`,
						w_full = true,
						h_full = true,
						px = "$zeron.space.14",
						gap = "$zeron.space.6",
						items = "center",
						justify = "center",
						opacity = ui.tween(
							position,
							{ from = 1 + at, to = at, duration = glide.duration, ease = glide.ease }
						),
						face(true),
					},
				},
			},
		}
	end
	local radius = M.NAV_SEGMENT / 2 + M.NAV_INSET + M.NAV_PADDING + 1
	return ui.row {
		absolute = true,
		left = 0,
		right = 0,
		bottom = 16,
		px = "$zeron.space.16",
		justify = "center",
		pointer_events = "none",
		ui.row {
			id = props.id,
			max_w = "100%",
			p = T.space(M.NAV_PADDING),
			rounded = ui.raw(radius, "concentric: the segments' and their insets"),
			variants = recipes.composer { edge = "pill" },
			ui.row {
				relative = true,
				ref = track,
				ui.div {
					id = `{props.id}_thumb`,
					absolute = true,
					top = 0,
					bottom = 0,
					left = 0,
					w = `{100 / n}%`,
					p = T.space(M.NAV_INSET),
					pointer_events = "none",
					x = ui.tween(x, { duration = motion.d(motion.TAB_SLIDE), ease = motion.EASE_OUT }),
					ui.div {
						w_full = true,
						h_full = true,
						rounded = T.radius_full,
						bg = T.glass_hover,
						inset_shadow = T.selected_ring,
					},
				},
				ui.segmented {
					id = `{props.id}_tabs`,
					label = "Pull request sections",
					value = props.value,
					options = options,
					grid = true,
					cols = n,
					p = 0,
					gap = 0,
					bg = T.clear,
					border = 0,
				},
			},
		},
	}
end)

export type BadgeProps = { id: string?, tone: Tone, number: number, title: string?, size: ("sm" | "md")? }
M.badge = ui.component(function(props: BadgeProps): Node
	local t = TONE[props.tone]
	local small = props.size ~= "md"
	return ui.row {
		id = props.id,
		h = if small then 16 else 20,
		px = if small then "$zeron.space.4" else "$zeron.space.7",
		gap = if small then "$zeron.space.3" else "$zeron.space.5",
		items = "center",
		rounded = if small then "$zeron.radius.4" else "$zeron.radius.6",
		bg = t.wash,
		hover = { bg = t.wash },
		icon { name = t.icon, size = if small then 10 else 11, color = t.color, opacity = 0.85 },
		txt.text {
			`#{props.number}`,
			size = if small then "micro" else "xs",
			mono = true,
			weight = "medium",
			color = t.color,
			opacity = 0.85,
			line = false,
		},
	}
end)

return M
