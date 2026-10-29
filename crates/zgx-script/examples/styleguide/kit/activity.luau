-- A turn's tool calls as Zeron groups them (transcript.rs): a 26-high
-- header ("Ran 1 command · read 1 file") with its chevron on the trunk
-- (the 14 glyph centred on x 12.5), then 32-high rows hung off the tree in
-- a 48 gutter. The tree is Zeron's activity_rail: one 1-point path at
-- x 12.5 down to the row's middle less 6, a quadratic elbow (its control
-- point on the trunk at the middle) out to x 18.5, then the branch to
-- x 28, in the line colour (hairline at 12%), stroked as one so the fork
-- carries one coat; a 16 icon sits at 32, the label and detail 8 past the
-- gutter at 12 in the muted colour, failed rows in danger. The header is
-- no button: its label brightens under the pointer.
--
-- A live group (`items` a state) grows as calls arrive, as Zeron's does:
-- each new row opens its height over 360 ms (outExpo) while its connector
-- draws over 480 ms (outQuint): the row before it extends its trunk to the
-- boundary first, then this row's trunk comes down, rounds the elbow and
-- runs out to the tip, where the icon fades in and the label rises 4 into
-- place. A running call shows a spinner at the tip that gives way to its
-- icon, popping in, when it is done. The summary rolls as it changes, and
-- breathes while a call runs. `animate` replays the arrival of every row,
-- 65 ms apart (90 before the first). Folding eases the height and the
-- opacity over 140 ms. Everything moves in the engine: no script runs per
-- frame.
--
-- While the turn works on the group (`active`, or while a call runs), a
-- light sweeps the summary left to right (Zeron's shimmer: a bright copy
-- of it through a moving band, 1.7 s a peak), the engine moving the band
-- with no script.
--
-- A row with something to show (the call in full, its output, its diff,
-- its images) opens under itself as Zeron's chips do: the header is the
-- click, its label and detail brighten under the pointer and a chevron
-- shows after them (right while shut, down while open); the body (mono 12
-- lines 18 high, 6 above and below, in the faint colour) eases its height
-- open over 140 ms while the trunk runs on down beside it.
local T = require("../theme")
local disclosure = require("./disclosure")
local icon = require("./icon")
local file_icon = require("./file_icon")
local txt = require("./text")
local motion = require("./motion")
local recipes = require("./recipes")
local loaders = require("./loaders")
local diff = require("./diff")
local menu = require("./menu")
local patch = require("./patch")

export type Status = "running" | "done" | "failed"
-- A diff's counts for one file (a post-strip edit's record).
export type Stat = { path: string, added: number, removed: number }
-- An image the call read, wrote or printed; `w` and `h` its pixels,
-- `path` where it is (its `src` unless set).
export type Image = { src: string, name: string, w: number, h: number, path: string? }
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
	-- Its full output, kept apart from the transcript (its sidecar, by
	-- this key: `M.fetch` brings it), and how big it is.
	output_ref: string?,
	output_bytes: number?,
	-- A reasoning part riding the group ("Thought process"): its text,
	-- what the row opens on; open while it streams (running).
	thought: string?,
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
	-- A click on a row's file badge opens the file (in Files): the badge
	-- is its own target, the row's fold left alone.
	on_file: ((path: string) -> ())?,
	-- Compact mode: nothing in it opens by itself.
	compact: boolean?,
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

-- The trunk's x as a 1-point line's left, and the fork: where the elbow
-- leaves the trunk, its radius above the row's middle.
local LINE_X = M.TRUNK_X - 0.5
local FORK = M.ROW / 2 - M.BEND
-- The connector's box, to just past the branch's end, and its clip while
-- shut (its trunk's column alone, none of its height).
local RAIL_W = M.BRANCH_END + 1
local SHUT = { 0, RAIL_W - LINE_X - 1, M.ROW, 0 }
-- Where the trunk on down to the next row leaves the drawn path for a
-- plain line: past the elbow's reach (its stroke has left the trunk's
-- column by 14.3), so the two never overlap and the fork takes one coat.
M.STUB = FORK + M.BEND - 1
local STUB = M.STUB

-- The connector (activity_rail, activity_branch_points): the trunk in
-- from the top to the fork, the elbow (a quadratic curve whose control
-- point is on the trunk at the row's middle) and the branch out to its
-- end; `on`, the trunk on down to `STUB` too. One path stroked 1 wide, so
-- its parts are one shape and where they meet is painted once (Zeron
-- unions its ribbons for the same reason). The renderer rasterizes it at
-- the display's scale, smooth, once for every row.
local function connector(on: boolean): string
	local x, mid, r = M.TRUNK_X, M.ROW / 2, M.BEND
	local d = `M{x} 0V{FORK}Q{x} {mid} {x + r} {mid}H{M.BRANCH_END}`
	if on then
		d ..= `M{x} {FORK}V{STUB}`
	end
	return `<svg xmlns="http://www.w3.org/2000/svg" width="{RAIL_W}" height="{M.ROW}" viewBox="0 0 {RAIL_W} {M.ROW}">`
		.. `<path d="{d}" fill="none" stroke="#ffffff" stroke-width="1"/></svg>`
end
local CONNECTOR = connector(false)
local CONNECTOR_ON = connector(true)

-- A row's status, `failed` included.
function M.status(a: Activity): Status
	if a.failed then
		return "failed"
	end
	return a.status or "done"
end

-- What a group of calls did, as Zeron says it (zeron_proto view.rs
-- tool_group_summary): "Ran 2 commands · edited 1 file · read 3 files", by
-- kind in that order whatever the calls' (commands, edited files counted
-- once a path, reads, searches, fetches, todos, other tools), then how many
-- failed; only its first letter lifts. A row's label is Zeron's chip label
-- (tool_chip_content): Run, Read, Edit, Write, Patch, Search, Glob, Web,
-- Fetch, Todo; any other is a tool.
local KIND: { [string]: string } = {
	Run = "ran",
	Edit = "edited",
	Write = "edited",
	Patch = "edited",
	Read = "read",
	Search = "searched",
	Glob = "searched",
	Web = "searched",
	Fetch = "fetched",
	Todo = "todos",
}
local SEGMENTS: { { string } } = {
	{ "ran", "command" },
	{ "edited", "file" },
	{ "read", "file" },
	{ "searched", "time" },
	{ "fetched", "page" },
	{ "todos" },
	{ "called", "tool" },
}
function M.summary(items: { Activity }): string
	local counts: { [string]: number } = {}
	local edited: { [string]: boolean } = {}
	local failed = 0
	-- Thoughts ride the group and lead its summary ("Thought 2 times · ran
	-- 1 command"), as transcript.rs tool_group_summary names them.
	local thoughts = 0
	local calls = 0
	for _, a in items do
		if a.thought then
			thoughts += 1
			continue
		end
		calls += 1
		local kind = KIND[a.label] or "called"
		if kind == "edited" then
			local path = a.detail or "patch"
			if not edited[path] then
				edited[path] = true
				counts.edited = (counts.edited or 0) + 1
			end
		else
			counts[kind] = (counts[kind] or 0) + 1
		end
		if a.failed then
			failed += 1
		end
	end
	local parts: { string } = {}
	if thoughts == 1 then
		table.insert(parts, "thought process")
	elseif thoughts > 1 then
		table.insert(parts, `thought {thoughts} times`)
	end
	for _, segment in SEGMENTS do
		local kind, noun = segment[1], segment[2]
		local n = counts[kind]
		if n and noun then
			table.insert(parts, `{kind} {n} {noun}{if n == 1 then "" else "s"}`)
		elseif n then
			table.insert(parts, "updated todos")
		end
	end
	if #parts == 0 then
		table.insert(parts, `{calls} tool{if calls == 1 then "" else "s"}`)
	end
	if failed > 0 then
		table.insert(parts, `{failed} failed`)
	end
	local summary = table.concat(parts, " · ")
	return string.upper(string.sub(summary, 1, 1)) .. string.sub(summary, 2)
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
	on_file: ((path: string) -> ())?,
	compact: boolean,
}

-- The connector: the path down the trunk, round the elbow and out to the
-- tip, and the trunk going on down to the next row. Drawing them in runs
-- no script: the engine clips them open.
local function rail(ctx: RowContext): Node
	local animated = ctx.animated
	local after_row = ctx.after_row
	local paths: { Element } = {}
	local trunk_out: Element? = nil
	local tip: Element? = nil
	local function draw_in()
		local in0, in1 = if after_row then at(0.45) else 0, if after_row then at(0.72) else at(0.62)
		local b0 = if after_row then at(0.68) else at(0.58)
		local d = ctx.delay
		local span = M.CONNECTOR - b0
		for _, path in paths do
			-- Down the trunk to the fork, then on down the bend,
			anime.animate(path, {
				clipBottom = {
					{
						from = M.ROW,
						to = M.ROW - FORK,
						duration = motion.d(in1 - in0),
						delay = d + in0,
						ease = "linear",
					},
					{ to = 0, duration = motion.d(span * 0.2), ease = "linear" },
				},
			})
			-- and out along the branch, easing into its tip.
			anime.animate(path, {
				clipRight = { SHUT[2], 0 },
				duration = motion.d(span * 0.9),
				delay = d + b0 + span * 0.1,
				ease = motion.EASE_OUT_QUINT,
			})
		end
		if tip then
			anime.animate(tip, {
				opacity = { 0, 1 },
				duration = motion.d(span),
				delay = d + b0,
				ease = motion.EASE_OUT_QUINT,
			})
		end
	end
	-- The trunk on down: drawn as the next row arrives, before its own.
	local function draw_out(delay: number)
		if trunk_out then
			anime.animate(trunk_out, {
				clipBottom = { M.ROW - STUB, 0 },
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
	-- The path, with its trunk on down (`on`) or without. A live row has
	-- both, the one that applies shown, so the row after it arriving draws
	-- nothing new in script.
	local function path(on: boolean): Node
		return ui.svg {
			code = if on then CONNECTOR_ON else CONNECTOR,
			absolute = true,
			left = 0,
			top = 0,
			w = RAIL_W,
			h = M.ROW,
			tint = T.activity_line,
			hidden = if ctx.live
				then function()
					return ctx.follows() ~= on
				end
				else nil,
			clip_inset = if animated then SHUT else nil,
			on_mount = function(el: Element)
				table.insert(paths, el)
			end,
		}
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
		if ctx.live then { path(false), path(true) } else path(followed),
		ui.div {
			absolute = true,
			left = LINE_X,
			top = STUB,
			bottom = 0,
			w = 1,
			bg = T.activity_line,
			hidden = if ctx.live
				then function()
					return not ctx.follows()
				end
				else not followed,
			clip_inset = if animated or ctx.next_delay then { 0, 0, M.ROW - STUB, 0 } else nil,
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

-- A path's last component, its badge's name (file_badge_name: either
-- separator, a trailing one skipped).
function M.file_name(path: string): string
	return string.match(path, "([^/\\]+)[/\\]*$") or path
end

-- Whether a row has something to open on.
function M.expands(a: Activity): boolean
	return (a.call or a.output or a.output_ref or a.hunks or a.stats or a.images or a.thought) ~= nil
end

-- Where a call's full output comes from (FETCH_TOOL_BLOB): the app's, given
-- its key, answering with the text (nil or "" when it could not).
M.fetch = nil :: ((ref: string, done: (text: string?) -> ()) -> ())?
-- A fetched output's lines at most (FULL_OUTPUT_MAX_LINES), and the
-- affordance's row (BLOB_AFFORDANCE_HEIGHT).
M.FULL_LINES = 400
M.BLOB = 24

-- "812 B", "12 KB" (format_kb).
function M.size(bytes: number): string
	return if bytes < 1024 then `{bytes} B` else `{math.ceil(bytes / 1024)} KB`
end

-- A sidecar's fetch, by key, for the window's life (as Zeron's cache): idle
-- until asked, loading, then ready (its text, shown) or failed.
type Blob = { status: "idle" | "loading" | "ready" | "failed", text: string? }
local function blob(ref: string): State<Blob>
	return ui.state(`tool_blob:{ref}`, { status = "idle" } :: Blob)
end
function M.fetch_blob(ref: string)
	local b = blob(ref)
	local now = b:peek().status
	if now == "loading" or now == "ready" or not M.fetch then
		return
	end
	b:set { status = "loading" }
	M.fetch(ref, function(text: string?)
		if text and text ~= "" then
			b:set { status = "ready", text = text }
		else
			b:set { status = "failed" }
		end
	end)
end

-- Text as the body's lines (transcript.rs tool_detail, call_block): its
-- trailing blank lines dropped, each wrapped at `wrap` characters when
-- given, the first `most` (`MAX_LINES`) kept; and how many more there were.
function M.lines(text: string, wrap: number?, most: number?): ({ string }, number)
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
	local cut = math.max(#out - (most or M.MAX_LINES), 0)
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
local function code_block(text: string, wrap: number?, most: number?): Node?
	local lines, cut = M.lines(text, wrap, most)
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

-- A thought's Markdown as the body's lines (thought_lines, THOUGHT_WRAP_COLS):
-- its markers dropped, wrapped at 96 at a word, 18 high in the faint
-- colour; past 24 lines a live one keeps its tail (the fresh thinking), a
-- settled one its head, and "… N more lines".
M.THOUGHT_WRAP = 96
function M.thought_lines(text: string, live: boolean?): ({ string }, number)
	local out: { string } = {}
	local fence = false
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		local line = raw
		if string.match(line, "^%s*```") then
			fence = not fence
			continue
		end
		if not fence then
			line = string.gsub(line, "^(%s*)#+%s*", "%1")
			line = string.gsub(line, "^(%s*)[-*+]%s+", "%1• ")
			line = string.gsub(line, "!?%[([^%]]*)%]%([^)]*%)", "%1")
			line = string.gsub(line, "[*_`]", "")
		end
		-- Wrapped at a word, the indent kept on what follows.
		local indent = string.match(line, "^(%s*)") or ""
		while (utf8.len(line) or #line) > M.THOUGHT_WRAP do
			local cut = utf8.offset(line, M.THOUGHT_WRAP + 1) or #line + 1
			local head = string.sub(line, 1, cut - 1)
			local at = string.match(head, "^.*()%s") or cut
			if at <= #indent + 1 then
				at = cut
			end
			table.insert(out, string.sub(line, 1, at - 1))
			line = indent .. (string.match(string.sub(line, at), "^%s*(.*)$") or "")
		end
		table.insert(out, line)
	end
	while #out > 0 and string.match(out[#out], "^%s*$") do
		table.remove(out)
	end
	local cut = math.max(#out - M.MAX_LINES, 0)
	for _ = 1, cut do
		table.remove(out, if live then 1 else #out)
	end
	while live and #out > 0 and string.match(out[1], "^%s*$") do
		table.remove(out, 1)
	end
	return out, cut
end
local function thought_block(text: string, live: boolean?): Node?
	local lines, cut = M.thought_lines(text, live)
	if #lines == 0 then
		return nil
	end
	local rows: { Node } = {}
	for _, l in lines do
		table.insert(
			rows,
			line_row(
				if string.match(l, "^%s*$")
					then nil
					else txt.text { l, literal = true, size = "sm", color = T.tertiary, line = false, shrink = 0 }
			)
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
				file_icon.icon { path = s.path, size = 14 },
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

-- An image's menu (transcript.rs image_context_menu): Zeron's card at 190
-- with popover rows, Copy path and Copy image (its pixels, from the file).
local IMAGE_MENU = (function()
	local style = table.clone(menu.CARD) :: { [string]: any }
	style.w = 190
	return style
end)()
function M.image_menu(image: Image, id: string?): { Node }
	local function item(key: string, label: string, glyph: icon.Name, run: () -> ()): Node
		return menu.item({
			id = id and `{id}_{key}`,
			label = label,
			icon = glyph,
			on_click = run,
		}, function() end, nil, nil, "popover")
	end
	return {
		item("copy_path", "Copy path", "copy", function()
			ui.clipboard.write(image.path or image.src)
		end),
		item("copy_image", "Copy image", "file-image", function()
			ui.clipboard.write_image(image.src)
		end),
	}
end

-- The images, 220 high at their own aspect (48 to 560 wide), 8 apart in a
-- strip that scrolls sideways; a click opens one in the viewer, a
-- secondary click its menu.
local function image_strip(a: Activity, id: string?, on_image: ((image: Image) -> ())?): Node
	local frames: { Node } = {}
	for i, image in a.images :: { Image } do
		local w = math.clamp(M.IMAGE_H * image.w / math.max(image.h, 1), 48, M.IMAGE_MAX_W)
		local frame = id and `{id}_image_{i}`
		table.insert(
			frames,
			ui.button {
				id = frame,
				context_menu_style = IMAGE_MENU,
				context_menu = function(): { Node }
					return M.image_menu(image, frame and `{frame}_menu`)
				end,
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

-- An output kept apart (transcript.rs blob affordance): what the
-- transcript holds of it, and under it a 24-high line at 12 in the faint
-- colour (the muted under the pointer): "Show full output (12 KB)", which
-- fetches it in place ("Loading full output…", inert; "Couldn't load full
-- output — tap to retry"); fetched, its first 400 lines take the place of
-- the summary.
local function sidecar(a: Activity, ref: string, id: string?): Node
	local b = blob(ref)
	return ui.presence(function()
		return b:get().status
	end, function(status: string): Node
		if status == "ready" then
			return code_block(b:peek().text or "", nil, M.FULL_LINES) or ui.div {}
		end
		local label = if status == "loading"
			then "Loading full output…"
			elseif status == "failed" then "Couldn't load full output — tap to retry"
			elseif a.output_bytes then `Show full output ({M.size(a.output_bytes)})`
			else "Show full output"
		return ui.column {
			w_full = true,
			min_w = 0,
			items = "stretch",
			a.output and code_block(a.output) or nil,
			ui.button {
				id = id and `{id}_blob`,
				h = M.BLOB,
				px = 0,
				items = "center",
				bg = T.clear,
				border = 0,
				focus = { border = 0 },
				color = T.tertiary,
				hover = if status == "loading" then nil else { color = T.secondary },
				cursor = if status == "loading" then nil else "pointer",
				disabled = status == "loading",
				on_click = function()
					M.fetch_blob(ref)
				end,
				txt.text { label, size = "sm", color = "inherit", line = false },
			},
		}
	end, { w_full = true, min_w = 0 })
end

-- The most lines a row's diff shows (transcript.rs DIFF_DETAIL_MAX_LINES).
M.DIFF_MAX = 600

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
		add(if a.thought then thought_block(a.thought, M.status(a) == "running") else nil)
		add(if a.call then code_block(a.call, M.WRAP) else nil)
		add(if a.images and #a.images > 0 then image_strip(a, id, on_image) else nil)
		if a.hunks then
			-- Built whole, so cut at `DIFF_MAX` lines, saying so.
			local kept, cut = patch.truncate(a.hunks :: any, M.DIFF_MAX)
			local hunks: { Node } = {}
			for _, h in kept do
				-- A fresh props table: a state's is read-only.
				table.insert(hunks, diff.hunk { header = h.header, lines = h.lines })
			end
			if cut then
				table.insert(hunks, diff.notice(cut))
			end
			add(ui.column { w_full = true, items = "stretch", rounded = "$zeron.radius.6", overflow = "hidden", hunks })
		elseif a.stats then
			add(stats_block(a.stats))
		elseif a.output_ref then
			add(sidecar(a, a.output_ref, id))
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
		-- A file's badge (chip_header_row): 22 high at radius 5 on ink 6%,
		-- the file's glyph on its well (20, radius 4), then its name alone
		-- (file_badge_name) in the text at 85%. With somewhere to open it,
		-- the badge is its own target (ink 10% under the pointer): a click
		-- opens the file, the row's fold left alone.
		local failed = M.status(a) == "failed"
		local on_file = ctx.on_file
		local path = a.detail
		local make: (props: any) -> Node = if on_file then ui.button else ui.row
		detail = make {
			id = if on_file and ctx.group then `{ctx.group}_{a.id}_file` else nil,
			label = if on_file then `Open {path}` else nil,
			on_click = if on_file
				then function()
					on_file(path)
				end
				else nil,
			cursor = if on_file then "pointer" else nil,
			hover = if on_file then { bg = T.ink4 } else nil,
			focus = if on_file then { border = 0 } else nil,
			py = 0,
			h = 22,
			pl = "$zeron.space.1",
			pr = "$zeron.space.6",
			gap = "$zeron.space.6",
			items = "center",
			rounded = "$zeron.radius.5",
			bg = T.ink2,
			shrink = 1,
			min_w = 0,
			overflow = "hidden",
			ui.row {
				w = 20,
				h = 20,
				shrink = 0,
				rounded = "$zeron.radius.4",
				bg = T.activity_well,
				items = "center",
				justify = "center",
				file_icon.icon { path = a.detail, size = 14 },
			},
			txt.text {
				M.file_name(a.detail),
				literal = true,
				size = "sm",
				color = if failed then T.danger else T.activity_badge,
				truncate = true,
				line = false,
				shrink = 1,
				min_w = 0,
				group_hover = brighten,
			},
		}
	elseif a.detail then
		detail = txt.text {
			a.detail,
			literal = true,
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
	-- A thought opens while it streams (the live thinking is the point),
	-- folding as it settles unless it was toggled; compact mode opens
	-- nothing by itself.
	local streaming = a.thought ~= nil and M.status(a) == "running" and not ctx.compact
	local open = if opens then ui.use_state(streaming) else nil
	-- Whether it has opened yet: its body's box (and its easing) is built
	-- the first time, so a shut row costs no box.
	local opened = if opens then ui.use_state(streaming) else nil
	local toggled = false
	if streaming and open and ctx.live then
		ui.effect(function()
			if M.status(ctx.latest()) ~= "running" and not toggled then
				open:set(false)
			end
		end)
	end
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
						toggled = true
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
					-- The label 8 past the gutter, the chevron right after
					-- the detail.
					pl = "$zeron.space.8",
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
					-- The chevron after them, shown under the pointer, in
					-- the faint colour, the text's (danger's) there; right
					-- while shut, down while open (chip_header_row's tile:
					-- the glyph swaps, no turn).
					open and ui.row {
						id = id and `{id}_chevron`,
						w = 18,
						h = 18,
						shrink = 0,
						items = "center",
						justify = "center",
						opacity = 0,
						color = T.tertiary,
						group_hover = {
							opacity = 1,
							color = if M.status(a) == "failed" then T.danger else T.text,
						},
						icon {
							name = "alt-arrow-right",
							size = 12,
							color = "currentColor",
							hidden = function()
								return open:get()
							end,
						},
						icon {
							name = "alt-arrow-down",
							size = 12,
							color = "currentColor",
							hidden = function()
								return not open:get()
							end,
						},
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
	props: Props
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
					on_image = props.on_image,
					on_file = props.on_file,
					compact = props.compact == true,
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
			on_image = props.on_image,
			on_file = props.on_file,
			compact = props.compact == true,
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
-- that stay keep still. Each kind has its slot, in the summary's order, so
-- a kind arriving before others opens its own place and leaves theirs be
-- (their dots stay put; a part that loses its capital rolls).
local SLOTS = { "thought", "ran", "edited", "read", "searched", "fetched", "updated", "called", "failed" }
local function kind_of(part: string): string
	if string.match(part, "^%d+ failed$") then
		return "failed"
	elseif string.match(part, "^%d+ tools?$") then
		return "called"
	end
	return string.lower(string.match(part, "^(%a+)") or "")
end
local function rolling(summary: State<string>): Node
	local parts = ui.computed(function(): { [string]: string }
		local out: { [string]: string } = {}
		for part in string.gmatch(summary:get(), "[^·]+") do
			local trimmed = string.match(part, "^%s*(.-)%s*$") or part
			out[kind_of(trimmed)] = trimmed
		end
		return out
	end)
	-- The first kind shown: no dot before it.
	local first = ui.computed(function(): string?
		for _, kind in SLOTS do
			if parts:get()[kind] then
				return kind
			end
		end
		return nil
	end)
	local slots: { Node } = {}
	local travel = 6
	for _, kind in SLOTS do
		table.insert(
			slots,
			ui.row {
				items = "center",
				txt.text {
					"·",
					size = "sm",
					color = "inherit",
					line = false,
					mx = "$zeron.space.4",
					hidden = function()
						return parts:get()[kind] == nil or first:get() == kind
					end,
				},
				ui.presence(function()
					return parts:get()[kind]
				end, function(part: string): Node
					return txt.text { part, literal = true, size = "sm", color = "inherit", line = false }
				end, {
					enter = {
						opacity = { 0, 1 },
						y = { travel, 0 },
						duration = motion.d(motion.ROLL),
						ease = motion.EASE_OUT_QUINT,
					},
					exit = { opacity = 0, y = -travel, duration = motion.d(motion.ROLL), ease = motion.EASE_OUT_QUINT },
				}),
			}
		)
	end
	return ui.row { items = "center", min_w = 0, overflow = "hidden", slots }
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

local function header(props: Props, running: State<boolean>?, label: Node?): Node
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
					-- Muted whatever the pointer (its own colour, not the
					-- label's), turning over the fold's 140 ms.
					color = T.secondary,
					duration = M.FOLD,
				},
			},
		},
		label or summary_label(props, running),
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
	-- zgx's disclosure: the header is its summary button (expanded to
	-- assistive technology; a click, Enter or Space folds it), the rows
	-- its content, folding over 140 ms.
	return ui.disclosure {
		id = props.id,
		open = props.open,
		bare = true,
		w = props.w,
		w_full = props.w == nil,
		items = "stretch",
		summary = header(props, running),
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
				rows_of(props.id, list, seen, batch, live, props),
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

-- Compact mode's turn (transcript.rs compact_shell): the turn's thinking,
-- tools and narration under one header, folded; open, they show as they
-- would without it (the children). While the turn works the header is
-- their summary, shimmering; settled it says how long the turn worked
-- ("Worked for 5m 10s", format_elapsed), crossfading from the summary
-- over 500 ms (outExpo, rising 4) when it settles in view, at once for a
-- turn that settled before.
M.WORKED = 500
export type WorkProps = {
	id: string?,
	summary: string | State<string>,
	worked: () -> string?,
	open: State<boolean>,
	active: (() -> boolean)?,
	[number]: Child,
}
-- "Worked for 1m 32s": two units at most, as the working line's timer.
function M.worked(secs: number): string
	local s = math.max(math.floor(secs), 0)
	local d = if s < 60
		then `{s}s`
		elseif s < 3600 then `{s // 60}m {s % 60}s`
		elseif s < 86400 then `{s // 3600}h {s % 3600 // 60}m`
		else `{s // 86400}d {s % 86400 // 3600}h`
	return `Worked for {d}`
end
M.work = ui.component(function(props: WorkProps): Node
	local running: State<boolean>? = if props.active then ui.computed(props.active) else nil
	local group: Props = { id = props.id, summary = props.summary, items = {}, open = props.open }
	local label = ui.presence(function(): string
		return props.worked() or ""
	end, function(now: string): Node
		if now == "" then
			return summary_label(group, running)
		end
		return txt.text { now, literal = true, size = "sm", color = "inherit", line = false, truncate = true }
	end, {
		min_w = 0,
		shrink = 1,
		enter = {
			opacity = { 0, 1 },
			y = { 4, 0 },
			duration = motion.d(M.WORKED),
			ease = motion.EASE_OUT_EXPO,
		},
		exit = { opacity = 0, duration = motion.d(M.WORKED), ease = motion.EASE_OUT_EXPO },
	})
	return ui.disclosure {
		id = props.id,
		open = props.open,
		bare = true,
		w_full = true,
		items = "stretch",
		summary = header(group, running, label),
		ui.presence(function()
			return if props.open:get() then "body" else nil
		end, function(): Node
			return ui.column {
				w_full = true,
				pt = "$zeron.space.2",
				gap = "$zeron.space.12",
				items = "stretch",
				{ table.unpack(props) },
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
