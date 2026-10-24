-- Pull requests (pull_requests.rs): groups as one card on wash 4.5% at
-- radius 12; rows of at least 64 with a title line (14-point glyph, 13
-- text), a meta line at 11 (avatar 16, login, badges 16 high, checks,
-- status), a 112 column of date and diff stats, and a 28 star. The
-- skeleton row breathes on the 2.4 s pulse.
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
local icon_button = require("./icon_button")

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
	id: string?,
	-- The group's list (`GroupProps.list`): the row washes as its rows do.
	group: string?,
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
	return ui.button(wash.maybe(props.group, {
		variants = recipes.wash { hover = "glass" },
		id = props.id,
		w_full = true,
		min_h = M.MIN_ROW,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		gap = "$zeron.space.16",
		items = "start",
		cursor = "pointer",
		focus = { border = 0 },
		border_sides = if props.first == false then { 1, 0, 0, 0 } else nil,
		border_color = T.hairline,
		on_click = props.on_click,
		ui.column {
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
		},
		ui.column {
			w = M.SIDE,
			shrink = 0,
			gap = "$zeron.space.4",
			items = "end",
			txt.text { r.date, size = "xs", color = T.secondary, line = false },
			ui.row {
				gap = "$zeron.space.8",
				txt.text { `+{r.added}`, size = "xs", mono = true, color = T.success_muted, line = false },
				txt.text { `−{r.removed}`, size = "xs", mono = true, color = T.danger_muted, line = false },
			},
		},
		icon_button {
			icon = if r.starred then "star-bold" else "star",
			size = 28,
			icon_size = 14,
			label = "Star",
			no_ring = true,
			color = if r.starred then T.warning else nil,
		},
	}))
end)

-- A group: its header (chevron turning 280 ms, label 13 muted, count 11)
-- and the card of rows under it.
M.group = ui.component(function(props: GroupProps): Node
	return ui.column {
		id = props.id,
		w = props.w,
		w_full = props.w == nil,
		gap = "$zeron.space.8",
		ui.button {
			variants = recipes.wash { hover = "ink1" },
			id = props.id and `{props.id}_header`,
			min_h = 24,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			self = "start",
			rounded = T.radius_md,
			cursor = "pointer",
			focus = { border = 0 },
			on_click = ui.toggle(props.open),
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

-- A skeleton row: bars on ink 7% at 0.45 ± 0.4 on the pulse, phases
-- 0.08 apart.
local WIDTHS = { 0.62, 0.48, 0.71, 0.55, 0.39, 0.66 }
export type SkeletonProps = { id: string?, rows: number?, w: Length? }
M.skeleton = ui.component(function(props: SkeletonProps): Node
	local p: SkeletonProps = props or {}
	local id = p.id or `prsk{math.random(1, 1e9)}`
	local function bar(w: Length, h: number, i: number): Node
		return ui.div { w = w, h = h, rounded = T.radius_full, bg = T.ink3, opacity = 0.45, class = `{id}_{i}` }
	end
	local rows: { Node } = {}
	for i = 1, p.rows or 3 do
		table.insert(
			rows,
			ui.row {
				w_full = true,
				min_h = M.MIN_ROW,
				px = "$zeron.space.16",
				py = "$zeron.space.12",
				gap = "$zeron.space.16",
				items = "start",
				border_sides = if i > 1 then { 1, 0, 0, 0 } else nil,
				border_color = T.hairline,
				ui.column {
					grow = 1,
					gap = "$zeron.space.6",
					ui.row {
						h = 20,
						gap = "$zeron.space.8",
						items = "center",
						bar(14, 14, i),
						bar(`{WIDTHS[(i - 1) % #WIDTHS + 1] * 100}%`, 10, i),
					},
					ui.row {
						pl = T.space(M.META_INDENT),
						h = 16,
						gap = "$zeron.space.8",
						items = "center",
						bar(16, 16, i),
						bar(72, 10, i),
						bar(52, 16, i),
						bar(120, 12, i),
					},
				},
				ui.column { w = M.SIDE, items = "end", gap = "$zeron.space.4", bar(56, 10, i), bar(48, 10, i) },
				ui.div { w = 28, h = 28 },
			}
		)
	end
	return ui.column {
		id = p.id,
		w = p.w,
		w_full = p.w == nil,
		rounded = T.radius_card,
		bg = T.card,
		overflow = "hidden",
		on_mount = function()
			if not motion.loops() then
				return
			end
			for i = 1, p.rows or 3 do
				anime.animate(`.{id}_{i}`, {
					opacity = { 0.45, 0.85, 0.45 },
					duration = 2400,
					delay = (i - 1) * 0.08 * 2400,
					ease = motion.EASE,
					loop = true,
					frameRate = 30,
				})
			end
		end,
		rows,
	}
end)

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

export type ChipProps = { id: string?, tone: Tone, label: string? }
M.status_chip = ui.component(function(props: ChipProps): Node
	local t = TONE[props.tone]
	return ui.row {
		id = props.id,
		px = "$zeron.space.8",
		py = "$zeron.space.3",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = t.wash,
		icon { name = t.icon, size = 14, color = t.color },
		txt.text { props.label or t.label, size = "sm", line = false },
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
