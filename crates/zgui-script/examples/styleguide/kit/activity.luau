-- A turn's tool calls as Zeron groups them (transcript.rs): a 26-high
-- header ("Ran 2 commands · Read 3 files") with its chevron on the trunk
-- (the 14 glyph centred on x 12.5), then 32-high rows hung off a 1-point
-- trunk at x 12.5 in a 48 gutter; a branch leaves the trunk at the row's
-- middle less 6, bends with a 6 radius and runs to x 28; a 16 icon sits at
-- 32, the label and detail at 12 in the muted colour, failed rows in
-- danger. The header is no button: its label brightens under the pointer.
--
-- A live group (`items` a state) grows as calls arrive, as Zeron's does:
-- each new row opens its height over 360 ms (outExpo) while its connector
-- draws by length over 480 ms (outQuint): the row before it extends its
-- trunk to the boundary first, then this row's trunk comes down, rounds
-- the elbow and runs out to the tip, where the icon fades in and the label
-- rises 4 into place. A running call shows a spinner at the tip that gives
-- way to its icon, popping in, when it is done. The summary rolls as it
-- changes, and breathes while a call runs. `animate` replays the arrival
-- of every row, 65 ms apart (90 before the first). Folding eases the
-- height and the opacity over 140 ms. Everything moves in the engine:
-- no script runs per frame.
--
-- While the turn works on the group (`active`, or while a call runs), a
-- light sweeps the summary left to right (Zeron's shimmer: a bright copy
-- of it through a moving band, 1.7 s a peak), the engine moving the band
-- with no script.
--
-- A row with something to show (the call in full, its output, its diff,
-- its images) opens under itself as Zeron's chips do: the header is the
-- click, its label and detail brighten under the pointer and a chevron
-- shows after them; the body (mono 12 lines 18 high, 6 above and below,
-- in the faint colour) eases its height open over 140 ms while the trunk
-- runs on down beside it.
local T = require("../theme")
local disclosure = require("./disclosure")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")
local loaders = require("./loaders")
local diff = require("./diff")

export type Status = "running" | "done" | "failed"
-- A diff's counts for one file (a post-strip edit's record).
export type Stat = { path: string, added: number, removed: number }
-- An image the call read, wrote or printed; `w` and `h` its pixels.
export type Image = { src: string, name: string, w: number, h: number }
export type Activity = {
	id: string,
	-- An icon's name (kit/icon_names).
	icon: string,
	label: string,
	detail: string?,
	-- A file-path detail shows as a 22-high badge with its icon well.
	file: boolean?,
	failed: boolean?,
	-- A live call's status (done unless set).
	status: Status?,
	-- What the row opens on (transcript.rs ToolDetail), in this order: the
	-- call in full (the whole command, pattern or URL, wrapped at 80), its
	-- images, then what came back: its edit as hunks (the changes pane's),
	-- a diff's counts per file, or its output (24 lines, then "… N more
	-- lines").
	call: string?,
	images: { Image }?,
	hunks: { diff.HunkProps }?,
	stats: { Stat }?,
	output: string?,
}
export type Props = {
	id: string?,
	-- A state rolls as it changes.
	summary: string | State<string>,
	-- A state: a live group, whose new calls arrive drawn.
	items: { Activity } | State<{ Activity }>,
	open: State<boolean>,
	-- Every row arrives with the staggered reveal (a replay).
	animate: boolean?,
	-- Whether the turn is still working on it (Zeron's auto-open group): a
	-- light sweeps the summary meanwhile. Unset, while a call runs.
	active: (() -> boolean)?,
	-- A click on a row's image opens it (the image viewer).
	on_image: ((image: Image) -> ())?,
	w: Length?,
}

local M = {}

M.HEADER = 26
M.ROW = 32
M.GUTTER = 48
M.TRUNK_X = 12.5
M.BRANCH_END = 28
M.BEND = 6
M.ICON_LEFT = 32
M.ICON = 16
M.ROW_REVEAL = 360
M.CONNECTOR = 480
M.FIRST_DELAY = 90
M.STAGGER = 65
M.FOLD = 140
-- The body's lines and its bounds (OUTPUT_LINE_HEIGHT, OUTPUT_DETAIL_MAX_LINES,
-- CALL_WRAP_COLS), and the image strip's frames (TOOL_IMAGE_*).
M.LINE = 18
M.MAX_LINES = 24
M.WRAP = 80
M.IMAGE_H = 220
M.IMAGE_MAX_W = 560
M.IMAGE_PAD = 8
-- The shimmer: a peak every `SHIMMER_EVERY` points, passing in
-- `SHIMMER_PERIOD` ms, lit `SHIMMER_HALF` either side of it.
M.SHIMMER_EVERY = 480
M.SHIMMER_PERIOD = 1700
M.SHIMMER_HALF = 56

-- Where the connector's parts fall in its 480 ms, as Zeron splits its
-- eased progress (0–0.62 trunk and 0.58–1 branch for a first row, 0.45–0.72
-- and 0.68–1 after a row, whose trunk reaches down over 0–0.45), mapped
-- through the quint ease into time.
local function at(p: number): number
	return M.CONNECTOR * (1 - (1 - p) ^ 0.2)
end

-- The trunk's x as a 1-point line's left, the fork above the branch.
local LINE_X = M.TRUNK_X - 0.5
local FORK = M.ROW / 2 - M.BEND

-- A row's status, `failed` included.
function M.status(a: Activity): Status
	if a.failed then
		return "failed"
	end
	return a.status or "done"
end

-- What a group of calls did, as Zeron says it: "Read 2 files · Ran 1
-- command", in the order each verb first appears.
local NOUN: { [string]: string } = { Read = "file", Ran = "command", Edited = "file", Wrote = "file" }
function M.summary(items: { Activity }): string
	local counts: { [string]: number } = {}
	local order: { string } = {}
	local failed = 0
	for _, a in items do
		if not counts[a.label] then
			counts[a.label] = 0
			table.insert(order, a.label)
		end
		counts[a.label] += 1
		if a.failed then
			failed += 1
		end
	end
	local parts: { string } = {}
	for _, label in order do
		local n = counts[label]
		local noun = NOUN[label]
		if label == "Searched" then
			table.insert(parts, if n == 1 then "Searched once" else `Searched {n} times`)
		elseif noun then
			table.insert(parts, `{label} {n} {noun}{if n == 1 then "" else "s"}`)
		else
			table.insert(parts, if n == 1 then label else `{label} {n} times`)
		end
	end
	if failed > 0 then
		table.insert(parts, `{failed} failed`)
	end
	return table.concat(parts, " · ")
end

type RowContext = {
	-- The group's id, its rows' prefix.
	group: string?,
	-- A live group's rows follow their call; a settled one's are still
	-- (no effects, no bindings).
	live: boolean,
	-- The row's latest call, and whether a row follows it.
	latest: () -> Activity,
	follows: () -> boolean,
	-- Whether this row arrives drawn, after `delay`; and whether a row was
	-- there before it (whose trunk reaches down first).
	animated: boolean,
	delay: number,
	after_row: boolean,
	-- When the row after it arrives in the same batch (its trunk's cue).
	next_delay: number?,
	on_image: ((image: Image) -> ())?,
}

-- The connector: the trunk coming in from the top, the elbow and branch to
-- the tip, and the trunk going on down to the next row. Plain boxes the
-- engine clips open, so drawing them runs no script.
local function rail(ctx: RowContext): Node
	local animated = ctx.animated
	local after_row = ctx.after_row
	local line = T.ink4
	local trunk_in: Element? = nil
	local elbow: Element? = nil
	local trunk_out: Element? = nil
	local tip: Element? = nil
	local function draw_in()
		local in0, in1 = if after_row then at(0.45) else 0, if after_row then at(0.72) else at(0.62)
		local b0 = if after_row then at(0.68) else at(0.58)
		local d = ctx.delay
		if trunk_in then
			anime.animate(trunk_in, {
				clipBottom = { FORK, 0 },
				duration = motion.d(in1 - in0),
				delay = d + in0,
				ease = "linear",
			})
		end
		if elbow then
			-- Down the bend, then out along the branch.
			local span = M.CONNECTOR - b0
			anime.animate(elbow, {
				clipBottom = { M.BEND + 0.5, 0 },
				duration = motion.d(span * 0.2),
				delay = d + b0,
				ease = "linear",
			})
			anime.animate(elbow, {
				clipRight = { M.BRANCH_END - LINE_X - 1, 0 },
				duration = motion.d(span * 0.9),
				delay = d + b0 + span * 0.1,
				ease = motion.EASE_OUT_QUINT,
			})
		end
		if tip then
			anime.animate(tip, {
				opacity = { 0, 1 },
				duration = motion.d(M.CONNECTOR - b0),
				delay = d + b0,
				ease = motion.EASE_OUT_QUINT,
			})
		end
	end
	-- The trunk on down: drawn as the next row arrives, before its own.
	local function draw_out(delay: number)
		if trunk_out then
			anime.animate(trunk_out, {
				clipBottom = { M.ROW - FORK, 0 },
				duration = motion.d(at(0.45)),
				delay = delay,
				ease = "linear",
			})
		end
	end
	local followed = ctx.follows()
	if ctx.live then
		ui.effect(function()
			local now = ctx.follows()
			if now and not followed then
				draw_out(0)
			end
			followed = now
		end)
	end
	local function clip(sides: { number }): { number }?
		return if animated then sides else nil
	end
	-- As tall as the row: an open body's, the trunk running on beside it.
	return ui.div {
		w = M.GUTTER,
		self = "stretch",
		shrink = 0,
		relative = true,
		on_mount = function()
			if animated then
				draw_in()
			end
			if ctx.next_delay then
				draw_out(ctx.next_delay :: number)
			end
		end,
		ui.div {
			absolute = true,
			left = LINE_X,
			top = 0,
			w = 1,
			h = FORK,
			bg = line,
			clip_inset = clip { 0, 0, FORK, 0 },
			on_mount = function(el: Element)
				trunk_in = el
			end,
		},
		-- The elbow and branch: a box's left and bottom edges, its corner
		-- rounded by the bend, the bottom edge centred on the row's middle.
		ui.div {
			absolute = true,
			left = LINE_X,
			top = FORK,
			w = M.BRANCH_END - LINE_X,
			h = M.BEND + 0.5,
			border_sides = { 0, 0, 1, 1 },
			border_color = line,
			rounded_bl = T.radius(M.BEND),
			-- Its left edge alone shows while the bend comes down.
			clip_inset = clip { 0, M.BRANCH_END - LINE_X - 1, M.BEND + 0.5, 0 },
			on_mount = function(el: Element)
				elbow = el
			end,
		},
		ui.div {
			absolute = true,
			left = LINE_X,
			top = FORK,
			bottom = 0,
			w = 1,
			bg = line,
			hidden = if ctx.live
				then function()
					return not ctx.follows()
				end
				else not followed,
			clip_inset = if animated or ctx.next_delay then { 0, 0, M.ROW - FORK, 0 } else nil,
			on_mount = function(el: Element)
				trunk_out = el
			end,
		},
		-- The tip: a spinner while the call runs, its icon once it is done.
		ui.div {
			absolute = true,
			left = M.ICON_LEFT,
			top = (M.ROW - M.ICON) / 2,
			w = M.ICON,
			h = M.ICON,
			opacity = if animated then 0 else nil,
			on_mount = function(el: Element)
				tip = el
			end,
			if not ctx.live
				then icon {
					name = ctx.latest().icon :: any,
					size = M.ICON,
					color = if M.status(ctx.latest()) == "failed" then T.danger else T.secondary,
				}
				else ui.presence(function()
					return M.status(ctx.latest())
				end, function(status: Status): Node
					if status == "running" then
						return ui.row {
							w = M.ICON,
							h = M.ICON,
							items = "center",
							justify = "center",
							loaders.mini_spinner { cell = 2 },
						}
					end
					return icon {
						name = ctx.latest().icon :: any,
						size = M.ICON,
						color = if status == "failed" then T.danger else T.secondary,
					}
				end, {
					w = M.ICON,
					h = M.ICON,
					enter = { opacity = { 0, 1 }, scale = { 0.6, 1 }, duration = motion.d(220), ease = "outBack(1.6)" },
					exit = { opacity = 0, scale = 0.6, duration = motion.d(120), ease = "inQuad" },
				}),
		},
	}
end

-- Whether a row has something to open on.
function M.expands(a: Activity): boolean
	return (a.call or a.output or a.hunks or a.stats or a.images) ~= nil
end

-- Text as the body's lines (transcript.rs tool_detail, call_block): its
-- trailing blank lines dropped, each wrapped at `wrap` characters when
-- given, the first `MAX_LINES` kept; and how many more there were.
function M.lines(text: string, wrap: number?): ({ string }, number)
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local n = utf8.len(line)
		if wrap and n and n > wrap then
			local i = 1
			while i <= n do
				local s = utf8.offset(line, i) :: number
				local e = utf8.offset(line, math.min(i + wrap, n + 1)) :: number
				table.insert(out, string.sub(line, s, e - 1))
				i += wrap
			end
		else
			table.insert(out, line)
		end
	end
	while #out > 0 and string.match(out[#out], "^%s*$") do
		table.remove(out)
	end
	local cut = math.max(#out - M.MAX_LINES, 0)
	for _ = 1, cut do
		table.remove(out)
	end
	return out, cut
end

-- One line of the body: 18 high, clipped rather than wrapped.
local function line_row(content: Node?): Node
	return ui.row { w_full = true, h = M.LINE, min_w = 0, overflow = "hidden", items = "center", content }
end

-- Verbatim mono lines, indentation kept; "… N more lines" past the cap.
local function code_block(text: string, wrap: number?): Node?
	local lines, cut = M.lines(text, wrap)
	if #lines == 0 then
		return nil
	end
	local rows: { Node } = {}
	for _, l in lines do
		table.insert(
			rows,
			line_row(if l == ""
				then nil
				else txt.text {
					l,
					literal = true,
					size = "sm",
					mono = true,
					color = T.tertiary,
					line = false,
					shrink = 0,
				})
		)
	end
	if cut > 0 then
		table.insert(rows, line_row(txt.text { `… {cut} more lines`, size = "sm", color = T.tertiary, line = false }))
	end
	return ui.column { w_full = true, min_w = 0, py = "$zeron.space.6", items = "stretch", selectable = true, rows }
end

-- A diff's counts: each file's icon, its path, its additions and deletions.
local function stats_block(stats: { Stat }): Node
	local rows: { Node } = {}
	for _, s in stats do
		table.insert(
			rows,
			ui.row {
				w_full = true,
				h = M.LINE,
				min_w = 0,
				gap = "$zeron.space.8",
				items = "center",
				icon { name = "file-code", size = 14, color = T.tertiary },
				txt.text {
					s.path,
					literal = true,
					size = "sm",
					mono = true,
					color = T.tertiary,
					truncate = true,
					grow = 1,
					shrink = 1,
					min_w = 0,
					line = false,
				},
				txt.text { `+{s.added}`, size = "sm", mono = true, color = T.diff_add, line = false },
				txt.text { `−{s.removed}`, size = "sm", mono = true, color = T.diff_del, line = false },
			}
		)
	end
	return ui.column { w_full = true, py = "$zeron.space.6", items = "stretch", selectable = true, rows }
end

-- The images, 220 high at their own aspect (48 to 560 wide), 8 apart in a
-- strip that scrolls sideways; a click opens one in the viewer.
local function image_strip(a: Activity, id: string?, on_image: ((image: Image) -> ())?): Node
	local frames: { Node } = {}
	for i, image in a.images :: { Image } do
		local w = math.clamp(M.IMAGE_H * image.w / math.max(image.h, 1), 48, M.IMAGE_MAX_W)
		table.insert(
			frames,
			ui.button {
				id = id and `{id}_image_{i}`,
				label = image.name,
				w = w,
				h = M.IMAGE_H,
				p = 0,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.8",
				overflow = "hidden",
				border = 1,
				border_color = T.hairline,
				bg = T.ink1,
				cursor = if on_image then "zoom_in" else nil,
				focus = { border = 1 },
				on_click = if on_image
					then function()
						on_image(image)
					end
					else nil,
				ui.image {
					src = image.src,
					label = image.name,
					w = w - 2,
					h = M.IMAGE_H - 2,
					fit = "contain",
					rounded = "$zeron.radius.7",
				},
			}
		)
	end
	return ui.scroll_x {
		w_full = true,
		h = M.IMAGE_H + 2 * M.IMAGE_PAD,
		py = T.space(M.IMAGE_PAD),
		ui.row { gap = T.space(M.IMAGE_PAD), items = "start", frames },
	}
end

-- What a row opens on: the call, its images, then what came back, a
-- hairline's room between them; easing its height over 140 ms.
function M.body(a: Activity, open: State<boolean>, id: string?, on_image: ((image: Image) -> ())?): Node
	return ui.presence(function()
		return if open:get() then "body" else nil
	end, function(): Node
		local parts: { Node } = {}
		local function add(part: Node?)
			if part then
				table.insert(parts, ui.div { w_full = true, h = 1, shrink = 0 })
				table.insert(parts, part)
			end
		end
		add(if a.call then code_block(a.call, M.WRAP) else nil)
		add(if a.images and #a.images > 0 then image_strip(a, id, on_image) else nil)
		if a.hunks then
			local hunks: { Node } = {}
			for _, h in a.hunks do
				-- A fresh props table: a state's is read-only.
				table.insert(hunks, diff.hunk { header = h.header, lines = h.lines })
			end
			add(ui.column { w_full = true, items = "stretch", rounded = "$zeron.radius.6", overflow = "hidden", hunks })
		elseif a.stats then
			add(stats_block(a.stats))
		elseif a.output then
			add(code_block(a.output))
		end
		return ui.column {
			id = id and `{id}_body`,
			w_full = true,
			min_w = 0,
			pl = "$zeron.space.8",
			items = "stretch",
			parts,
		}
	end, {
		w_full = true,
		layout = "height",
		layout_clip = true,
		-- Built as the row first opens: it opens from nothing then too.
		layout_enter = true,
		initial = true,
		layout_duration = motion.d(M.FOLD),
		layout_ease = motion.EASE_OUT,
		enter = { opacity = { 0, 1 }, duration = motion.d(M.FOLD), ease = motion.EASE_OUT },
		exit = { opacity = 0, duration = motion.d(M.FOLD), ease = motion.EASE_OUT },
	})
end

local function row(ctx: RowContext): Node
	local a = ctx.latest()
	local animated = ctx.animated
	local tone: Color | () -> Color = if M.status(a) == "failed" then T.danger else T.secondary
	if ctx.live then
		tone = function(): Color
			return if M.status(ctx.latest()) == "failed" then T.danger else T.secondary
		end
	end
	-- An opening row's words brighten under the pointer; a failed one's
	-- stay in danger.
	local brighten: Styles? = if M.expands(a) and M.status(a) ~= "failed" then { color = T.text } else nil
	local detail: Node? = nil
	if a.detail and a.file then
		detail = ui.row {
			h = 22,
			pl = "$zeron.space.1",
			pr = "$zeron.space.6",
			gap = "$zeron.space.6",
			items = "center",
			rounded = "$zeron.radius.5",
			bg = T.ink2,
			shrink = 1,
			min_w = 0,
			ui.row {
				w = 20,
				h = 20,
				rounded = "$zeron.radius.4",
				bg = T.ink3,
				items = "center",
				justify = "center",
				icon { name = "file-code", size = 14, color = T.secondary },
			},
			txt.text { a.detail, size = "sm", color = tone, truncate = true, line = false, group_hover = brighten },
		}
	elseif a.detail then
		detail = txt.text {
			a.detail,
			size = "sm",
			color = tone,
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
			group_hover = brighten,
		}
	end
	local b0 = if ctx.after_row then at(0.68) else at(0.58)
	local id = ctx.group and `{ctx.group}_{a.id}`
	-- Whether it opens: settled, a row is its call's; live, its latest.
	local opens = M.expands(a)
	local open = if opens then ui.use_state(false) else nil
	-- Whether it has opened yet: its body's box (and its easing) is built
	-- the first time, so a shut row costs no box.
	local opened = if opens then ui.use_state(false) else nil
	return ui.row {
		id = id,
		w_full = true,
		overflow = "hidden",
		items = "stretch",
		shrink = 0,
		rail(ctx),
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			items = "stretch",
			ui.row {
				id = id and `{id}_head`,
				w_full = true,
				h = if animated then 0 else M.ROW,
				overflow = if animated then "hidden" else nil,
				shrink = 0,
				items = "center",
				hover_group = opens or nil,
				cursor = if opens then "pointer" else nil,
				on_click = if open
					then function()
						(opened :: State<boolean>):set(true)
						open:set(not open:peek())
					end
					else nil,
				on_mount = function(el: Element)
					if animated then
						anime.animate(el, {
							height = { 0, M.ROW },
							duration = motion.d(M.ROW_REVEAL),
							delay = ctx.delay,
							ease = motion.EASE_OUT_EXPO,
						})
					end
				end,
				ui.row {
					grow = 1,
					shrink = 1,
					min_w = 0,
					h = M.ROW,
					-- The label 8 past the tip's icon.
					pl = "$zeron.space.8",
					pr = "$zeron.space.8",
					gap = "$zeron.space.8",
					items = "center",
					opacity = if animated then 0 else nil,
					on_mount = function(el: Element)
						if animated then
							anime.animate(el, {
								opacity = { 0, 1 },
								y = { 4, 0 },
								duration = motion.d(M.CONNECTOR - b0),
								delay = ctx.delay + b0,
								ease = motion.EASE_OUT_QUINT,
							})
						end
					end,
					txt.text { a.label, size = "sm", color = tone, line = false, shrink = 0, group_hover = brighten },
					detail,
					-- The chevron after them, shown under the pointer.
					-- Right while shut, down while open (chip_header_row's
					-- tile: the glyph swaps, no turn).
					open and ui.row {
						id = id and `{id}_chevron`,
						w = 18,
						h = 18,
						shrink = 0,
						items = "center",
						justify = "center",
						opacity = 0,
						group_hover = { opacity = 1 },
						rotate = function()
							return if open:get() then 90 else 0
						end,
						icon { name = "alt-arrow-right", size = 12, color = T.tertiary },
					} or nil,
				},
			},
			open and ui.show(opened :: State<boolean>, M.body(a, open, id, ctx.on_image)) or nil,
		},
	}
end

local function index_in(list: State<{ Activity }>, id: string): number?
	for i, a in list:get() do
		if a.id == id then
			return i
		end
	end
	return nil
end

local function batch_delay(i: number): number
	return M.FIRST_DELAY + (i - 1) * M.STAGGER
end

-- The rows of one opening: those in `seen` sit still (drawn in turn when
-- `batch`), arrivals after it are drawn in on their own.
local function rows_of(
	group: string?,
	list: State<{ Activity }>,
	seen: { [string]: number },
	batch: boolean,
	live: boolean,
	on_image: ((image: Image) -> ())?
): Node
	if not live and not batch then
		-- Settled: the rows as they are, built once.
		local items = list:peek()
		local out: { Node } = {}
		for i, a in items do
			table.insert(
				out,
				row {
					group = group,
					live = false,
					latest = function(): Activity
						return a
					end,
					follows = function(): boolean
						return i < #items
					end,
					animated = false,
					delay = 0,
					after_row = i > 1,
					next_delay = nil,
					on_image = on_image,
				}
			)
		end
		return ui.column { w_full = true, items = "stretch", out }
	end
	return ui.each(list, function(a: Activity): Node
		local first_at: number? = seen[a.id]
		local replay = batch and first_at ~= nil
		local n = #list:peek()
		local ctx: RowContext = {
			group = group,
			live = true,
			latest = function(): Activity
				local i = index_in(list, a.id)
				return if i then list:get()[i] else a
			end,
			follows = function(): boolean
				local i = index_in(list, a.id)
				return i ~= nil and i < #list:get()
			end,
			animated = replay or first_at == nil,
			delay = if replay and first_at then batch_delay(first_at) else 0,
			after_row = (index_in(list, a.id) or 1) > 1,
			next_delay = if replay and first_at and first_at < n then batch_delay(first_at + 1) else nil,
			on_image = on_image,
		}
		return row(ctx)
	end, {
		key = function(a: Activity)
			return a.id
		end,
		direction = "column",
	})
end

-- A summary that changes rolls by its parts ("Read 1 file" → "Read 2
-- files"), each part whole so its letters keep their spacing: a part that
-- changes rises out as the new one rises in (550 ms, outQuint), the parts
-- that stay keep still.
local PARTS = 6
local function rolling(summary: State<string>): Node
	local parts = ui.computed(function(): { string }
		local out: { string } = {}
		for part in string.gmatch(summary:get(), "[^·]+") do
			local trimmed = string.match(part, "^%s*(.-)%s*$") or part
			table.insert(out, trimmed)
		end
		return out
	end)
	local slots: { Node } = {}
	local travel = 6
	for i = 1, PARTS do
		table.insert(
			slots,
			ui.presence(function()
				local part = parts:get()[i]
				return if part then `{i}:{part}` else nil
			end, function(): Node
				local part = parts:peek()[i] or ""
				return ui.row {
					gap = "$zeron.space.4",
					items = "center",
					i > 1 and txt.text { "·", size = "sm", color = "inherit", line = false } or nil,
					txt.text { part, size = "sm", color = "inherit", line = false },
				}
			end, {
				enter = {
					opacity = { 0, 1 },
					y = { travel, 0 },
					duration = motion.d(motion.ROLL),
					ease = motion.EASE_OUT_QUINT,
				},
				exit = { opacity = 0, y = -travel, duration = motion.d(motion.ROLL), ease = motion.EASE_OUT_QUINT },
			})
		)
	end
	return ui.row { items = "center", gap = "$zeron.space.4", min_w = 0, overflow = "hidden", slots }
end

-- The shimmer's band (tool_title_shimmer_amount): a peak every
-- `SHIMMER_EVERY` points, falling off linearly over `SHIMMER_HALF` either
-- side; twice the spacing wide, so sliding it one spacing a period covers
-- a title that long at every step, seamlessly.
local band: Bitmap? = nil
local function shimmer_band(): Bitmap
	if not band then
		local every, half = M.SHIMMER_EVERY, M.SHIMMER_HALF
		band = ui.bitmap(every * 2, M.HEADER, function(x: number): number
			local d = math.abs((x + 0.5) % every - every / 2)
			return math.max(0, 1 - d / half)
		end)
	end
	return band :: Bitmap
end

-- The summary's label: still, or rolling as a state changes; a light
-- sweeping it while a call runs, a bright copy of it showing through the
-- band the engine slides (no script per frame).
local function summary_label(props: Props, running: State<boolean>?): Node
	local function label(): Node
		return if type(props.summary) == "string"
			then txt.text { props.summary, size = "sm", color = "inherit", line = false, truncate = true }
			else rolling(props.summary :: State<string>)
	end
	local live = running
	return ui.row {
		h = 18,
		min_w = 0,
		shrink = 1,
		items = "center",
		overflow = "hidden",
		relative = true,
		label(),
		live and ui.show(
			function()
				return live:get() and motion.loops()
			end,
			ui.row {
				id = props.id and `{props.id}_shimmer`,
				absolute = true,
				left = 0,
				top = 0,
				right = 0,
				bottom = 0,
				items = "center",
				overflow = "hidden",
				pointer_events = "none",
				color = T.text,
				mask = {
					shimmer_band(),
					w = M.SHIMMER_EVERY * 2,
					h = M.HEADER,
					x = -M.SHIMMER_EVERY,
					y = (18 - M.HEADER) / 2,
					sweep = { x = M.SHIMMER_EVERY, duration = motion.d(M.SHIMMER_PERIOD), frame_rate = 30 },
				},
				label(),
			}
		) or nil,
	}
end

local function header(props: Props, running: State<boolean>?): Node
	return ui.row {
		id = props.id and `{props.id}_header`,
		w_full = true,
		-- Arriving with its first call, it opens as a row does.
		h = if props.animate then 0 else M.HEADER,
		overflow = if props.animate then "hidden" else nil,
		on_mount = function(el: Element)
			if props.animate then
				anime.animate(el, {
					height = { 0, M.HEADER },
					duration = motion.d(M.ROW_REVEAL),
					ease = motion.EASE_OUT_EXPO,
				})
			end
		end,
		pr = "$zeron.space.4",
		gap = "$zeron.space.6",
		items = "center",
		variants = recipes.disclosure { tone = "plain" },
		on_click = ui.toggle(props.open),
		-- The chevron on the trunk: a 22×18 slot, the 14 glyph centred on
		-- the trunk's x, 2 down.
		ui.div {
			w = 22,
			h = 18,
			shrink = 0,
			relative = true,
			ui.div {
				absolute = true,
				left = M.TRUNK_X - 7,
				top = 2,
				disclosure.chevron {
					id = props.id and `{props.id}_chevron`,
					open = props.open,
					size = 14,
					color = T.secondary,
				},
			},
		},
		summary_label(props, running),
	}
end

M.group = ui.component(function(props: Props): Node
	local items: any = props.items
	local live = type(items) ~= "table"
	local list: State<{ Activity }> = if live
		then items
		else ui.computed(function(): { Activity }
			return items
		end)
	-- Whether the turn works on (a live group's summary shimmers).
	local running: State<boolean>? = if props.active
		then ui.computed(props.active)
		elseif live then ui.computed(function(): boolean
			for _, a in list:get() do
				if M.status(a) == "running" then
					return true
				end
			end
			return false
		end)
		else nil
	-- Replayed, the rows are drawn in turn the first time the group opens.
	local replaying = props.animate == true
	return ui.column {
		id = props.id,
		w = props.w,
		w_full = props.w == nil,
		items = "stretch",
		header(props, running),
		ui.presence(function()
			return if props.open:get() then "rows" else nil
		end, function(): Node
			local seen: { [string]: number } = {}
			for i, a in list:peek() do
				seen[a.id] = i
			end
			local batch = replaying
			replaying = false
			return ui.column {
				w_full = true,
				pt = "$zeron.space.2",
				items = "stretch",
				rows_of(props.id, list, seen, batch, live, props.on_image),
			}
		end, {
			w_full = true,
			layout = "height",
			layout_clip = true,
			layout_duration = motion.d(M.FOLD),
			layout_ease = motion.EASE_OUT,
			enter = { opacity = { 0, 1 }, duration = motion.d(M.FOLD), ease = motion.EASE_OUT },
			exit = { opacity = 0, duration = motion.d(M.FOLD), ease = motion.EASE_OUT },
		}),
	}
end)

return M
