-- The panel shell: Zeron's columns under its layout policy (see
-- panel_layout.luau). Up to four columns in a row: the sidebar (a tool),
-- the conversation and the right pane (content), Files (a tool). Make one
-- with `new`, show it with `view`, change it with `toggle`, `set_open`,
-- `toggle_expand` and the seams.
--
-- What it does, as Zeron does it:
--   * Opening or closing a column re-splits the content columns equally; a
--     dragged divider holds until then; double-clicking a seam resets it
--     (the sidebar's and Files' to their default widths) and re-splits.
--   * A window too narrow for every open column's minimum hides the least
--     recently opened; toggling a hidden column brings it back (it ranks
--     most recent) and closes it only when it still cannot return.
--   * Columns ease on the panel curve from what they paint, so a reversal
--     mid-flight never jumps; content lays out at its destination when a
--     column opens and keeps its layout while it closes; the right pane and
--     Files are anchored to their right edge, so the mask reveals them.
--   * Expand gives the right pane the conversation's room; the
--     conversation keeps its layout beneath instead of squeezing.
--   * Resizing the window, or dragging a seam, applies at once: nothing
--     lags the edge or the pointer.
local T = require("../theme")
local motion = require("./motion")
local L = require("./panel_layout")

export type Column = L.Column
export type Seam = "sidebar" | "right" | "files"
export type Options = {
	id: string,
	-- Which columns exist besides the conversation, and which start open.
	sidebar: boolean?,
	right: boolean?,
	files: boolean?,
	sidebar_open: boolean?,
	right_open: boolean?,
	files_open: boolean?,
	-- The tools' preferred widths.
	sidebar_width: number?,
	files_width: number?,
	-- The conversation's floor beside the right pane; where the window
	-- cannot give it that and the pane its minimum, the pane covers it
	-- (the pull requests' board, 360).
	cover: number?,
	-- Open flags the caller already owns (they change only through the
	-- shell's functions, which keep the policy).
	states: { sidebar: State<boolean>?, right: State<boolean>?, files: State<boolean>? }?,
}
type Columns<V> = { [string]: V }
export type Shell = {
	id: string,
	has: Columns<boolean>,
	open: Columns<State<boolean>>,
	expanded: State<boolean>,
	-- What each column paints, eased.
	w: Columns<State<number>>,
	-- The width each column's content lays out at (0: the column's own).
	content: Columns<State<number>>,
	conversation_content: State<number>,
	viewport: State<number>,
	-- The right seam was dragged; it holds until the next toggle.
	held: State<boolean>,
	-- Bumps with every arrangement (readouts follow it).
	version: State<number>,
	prefs: Columns<number>,
	at: Columns<number>,
	seq: number,
	anims: { [string]: Animation? },
	root: Ref,
	-- A seam's double-click window: the press that opened it.
	armed: { [string]: number? },
	dragging: Seam?,
	measured: boolean,
	cover: number?,
}

local M = {}

M.SEAM_HIT = 20
M.DOUBLE_CLICK = 350
local COLUMNS: { Column } = { "sidebar", "right", "files" }
M.COLUMNS = COLUMNS

function M.new(o: Options): Shell
	local id = o.id
	local has: Columns<boolean> = { sidebar = o.sidebar == true, right = o.right == true, files = o.files == true }
	local function st(name: string, v: any): State<any>
		return ui.state(`{id}_{name}`, v)
	end
	local s: Shell = {
		id = id,
		has = has,
		open = {
			sidebar = (o.states and o.states.sidebar) or st("sidebar_open", has.sidebar and o.sidebar_open ~= false),
			right = (o.states and o.states.right) or st("right_open", has.right and o.right_open == true),
			files = (o.states and o.states.files) or st("files_open", has.files and o.files_open == true),
		},
		expanded = st("expanded", false),
		w = { sidebar = st("w_sidebar", 0), right = st("w_right", 0), files = st("w_files", 0) },
		content = { sidebar = st("c_sidebar", 0), right = st("c_right", 0), files = st("c_files", 0) },
		conversation_content = st("c_conversation", 0),
		viewport = st("viewport", 0),
		held = st("held", false),
		version = st("version", 0),
		prefs = {
			sidebar = o.sidebar_width or L.SIDEBAR_DEFAULT,
			files = o.files_width or L.FILES_DEFAULT,
			right = L.RIGHT_DEFAULT,
		},
		at = { sidebar = 1, right = 2, files = 3 },
		seq = 3,
		anims = {},
		root = ui.ref(),
		armed = {},
		dragging = nil,
		measured = false,
		cover = o.cover,
	}
	return s
end

-- ---- the policy, read ---------------------------------------------------

local function slot(s: Shell, col: Column): L.Slot
	return { open = s.has[col] and s.open[col]:peek(), at = s.at[col] }
end

-- Which columns the window has room for, once every move has landed.
function M.fit(s: Shell): L.Fit
	return L.fit(
		s.viewport:peek(),
		s.prefs.sidebar,
		slot(s, "sidebar"),
		slot(s, "right"),
		slot(s, "files"),
		s.expanded:peek(),
		s.cover
	)
end

function M.targets(s: Shell): L.Widths
	return L.settled(s.viewport:peek(), M.fit(s), s.prefs.files, s.prefs.right, s.expanded:peek(), s.cover)
end

-- Whether a column is open and the window shows it.
function M.shown(s: Shell, col: Column): boolean
	s.version:get()
	return (M.fit(s) :: any)[col] == true
end

-- Whether the open pane covers the conversation (`cover`).
function M.covered(s: Shell): boolean
	if s.cover == nil then
		return false
	end
	s.version:get()
	return M.fit(s).covered == true
end

-- The sidebar's width as the user left it (dragged, or the default), open
-- or not: what Settings' sections take beside the page (settings.sidebar_width).
function M.sidebar_width(s: Shell): number
	s.version:get()
	return s.prefs.sidebar
end

-- What the conversation paints now.
function M.conversation_width(s: Shell): number
	return math.max(s.viewport:get() - s.w.sidebar:get() - s.w.right:get() - s.w.files:get(), 0)
end

-- ---- motion -------------------------------------------------------------

local function bump(s: Shell)
	s.version:set(s.version:peek() + 1)
end

local function stop(s: Shell, col: string)
	local a = s.anims[col]
	if a then
		a:cancel()
		s.anims[col] = nil
	end
end

local function content_now(s: Shell, col: Column): number
	local c = s.content[col]:peek()
	return if c > 0 then c else s.w[col]:peek()
end

local function landed(s: Shell, col: Column, to: number)
	s.w[col]:set(to)
	s.content[col]:set(0)
	if col == "right" and not s.expanded:peek() then
		-- The conversation's return rides the pane: it follows again.
		s.conversation_content:set(0)
	end
end

-- Ease a column from what it paints to `to` on the panel curve, or set it
-- at once (`direct`: a window resize or a drag).
local function move(s: Shell, col: Column, to: number, direct: boolean)
	local from = s.w[col]:peek()
	stop(s, col)
	if direct or math.abs(to - from) < 0.5 or motion.reduced:peek() then
		landed(s, col, to)
		return
	end
	if from < 0.5 or to < 0.5 then
		-- Opening lays out at the destination; closing keeps the layout.
		local c = L.content_tween(content_now(s, col), from, to)
		s.content[col]:set(c)
	else
		-- Between two open widths the content follows the column.
		s.content[col]:set(0)
	end
	-- anime writes the width itself, without a script call per frame.
	s.anims[col] = (anime.animate :: any)(s.w[col], {
		value = to,
		duration = motion.d(L.duration(from, to)),
		ease = L.EASE,
		onComplete = function()
			s.anims[col] = nil
			landed(s, col, to)
		end,
	}) :: Animation
end

-- Every column toward where the policy rests it.
local function settle(s: Shell, direct: boolean)
	local t = M.targets(s)
	for _, col in COLUMNS do
		if s.has[col] then
			move(s, col, (t :: any)[col], direct)
		end
	end
	bump(s)
end

-- The content columns split what the tools leave equally (a dragged
-- divider gives way). Only a shown pane outside takeover takes a share.
local function resplit(s: Shell)
	local fit = M.fit(s)
	if not (fit.right and not s.expanded:peek()) then
		return
	end
	local t = M.targets(s)
	s.prefs.right = L.content_split(math.max(s.viewport:peek() - t.sidebar - t.files, 0), s.cover)
	s.held:set(false)
end

local function record(s: Shell, col: Column)
	s.seq += 1
	s.at[col] = s.seq
end

-- An open column the fit hides: asking for it ranks it most recent; true
-- when that brings it back.
local function promote(s: Shell, col: Column): boolean
	if (M.fit(s) :: any)[col] then
		return false
	end
	local seq, at = s.seq, s.at[col]
	record(s, col)
	if not (M.fit(s) :: any)[col] then
		s.seq, s.at[col] = seq, at
		return false
	end
	resplit(s)
	settle(s, false)
	return true
end

-- ---- what the user does -------------------------------------------------

function M.toggle(s: Shell, col: Column)
	if not s.has[col] then
		return
	end
	local open = s.open[col]:peek()
	if open and promote(s, col) then
		return
	end
	local was_expanded = s.expanded:peek()
	if col == "right" and open and was_expanded then
		-- Closing always leaves takeover: reopening at full bleed with the
		-- conversation gone reads as a broken chat.
		s.expanded:set(false)
	end
	s.open[col]:set(not open)
	if not open then
		record(s, col)
	end
	resplit(s)
	if col == "right" and open and was_expanded then
		local t = M.targets(s)
		s.conversation_content:set(math.max(s.viewport:peek() - t.sidebar - t.right - t.files, 0))
	end
	settle(s, false)
end

-- Open or close; asking to open an open column the fit hides promotes it.
function M.set_open(s: Shell, col: Column, open: boolean)
	if s.open[col]:peek() == open then
		if open then
			promote(s, col)
		end
		return
	end
	M.toggle(s, col)
end

function M.toggle_expand(s: Shell)
	if not (s.has.right and s.open.right:peek() and (M.fit(s) :: any).right) then
		return
	end
	local before = M.conversation_width(s)
	s.expanded:set(not s.expanded:peek())
	if s.expanded:peek() then
		-- The conversation keeps its layout beneath the pane.
		s.conversation_content:set(before)
	else
		-- It returns laid out where it will rest.
		local t = M.targets(s)
		s.conversation_content:set(math.max(s.viewport:peek() - t.sidebar - t.right - t.files, 0))
	end
	settle(s, false)
end

-- A seam dragged to `x` (from the shell's left edge).
function M.drag(s: Shell, seam: Seam, x: number)
	local vp = s.viewport:peek()
	local t = M.targets(s)
	if seam == "sidebar" then
		s.prefs.sidebar = math.clamp(x, L.SIDEBAR_MIN, L.SIDEBAR_MAX)
	elseif seam == "files" then
		s.prefs.files = math.clamp(vp - x, L.FILES_MIN, L.FILES_MAX)
	else
		local most = math.max(vp - t.files - t.sidebar - (s.cover or L.CHAT_MIN), L.RIGHT_MIN)
		s.prefs.right = math.clamp(vp - t.files - x, L.RIGHT_MIN, most)
		s.held:set(true)
	end
	settle(s, true)
end

-- Double-clicking a seam: the sidebar's or Files' back to its default
-- width, and the content columns equal again, eased from what shows.
function M.reset(s: Shell, seam: Seam)
	if seam == "sidebar" then
		s.prefs.sidebar = L.SIDEBAR_DEFAULT
	elseif seam == "files" then
		s.prefs.files = L.FILES_DEFAULT
	end
	resplit(s)
	settle(s, false)
end

-- The window (the shell's box) is `w` wide: applied at once, the content
-- columns kept equal.
function M.observe(s: Shell, w: number)
	if s.measured and math.abs(w - s.viewport:peek()) <= 0.5 then
		return
	end
	s.measured = true
	s.viewport:set(w)
	for _, col in COLUMNS do
		stop(s, col)
	end
	resplit(s)
	if s.expanded:peek() then
		local t = M.targets(s)
		s.conversation_content:set(math.max(w - t.sidebar - t.files - s.prefs.right, 0))
	else
		s.conversation_content:set(0)
	end
	settle(s, true)
end

-- Every column straight to where the policy rests it, with no motion: a
-- route arriving lays out at rest (its columns may have changed while it
-- was away, through a state it shares, such as the sidebar's).
function M.rest(s: Shell)
	for _, col in COLUMNS do
		stop(s, col)
	end
	resplit(s)
	settle(s, true)
end

-- One line on the arrangement, for readouts and tests.
function M.describe(s: Shell): string
	s.version:get()
	local fit = M.fit(s)
	local parts: { string } = {}
	local function col(name: string, c: Column)
		if not s.has[c] then
			return
		end
		if not s.open[c]:peek() then
			table.insert(parts, `{name} closed`)
		elseif not (fit :: any)[c] then
			table.insert(parts, `{name} hidden`)
		else
			table.insert(parts, `{name} {math.floor(s.w[c]:get() + 0.5)}`)
		end
	end
	col("sidebar", "sidebar")
	table.insert(parts, `conversation {math.floor(M.conversation_width(s) + 0.5)}`)
	col("pane", "right")
	col("files", "files")
	if s.expanded:get() then
		table.insert(parts, "expanded")
	end
	if s.held:get() then
		table.insert(parts, "divider held")
	end
	return table.concat(parts, " · ")
end

-- ---- the view -----------------------------------------------------------

export type Parts = {
	sidebar: Node?,
	conversation: Node,
	right: Node?,
	files: Node?,
	w_full: boolean?,
	h_full: boolean?,
	grow: number?,
	h: Length?,
	-- Draw the seams' hairlines (true unless set).
	hairlines: boolean?,
	-- Wash the sidebar column with Zeron's sidebar tone (true unless set);
	-- a layout whose sidebar is the window's glass itself turns it off.
	tone: boolean?,
}

-- A column: a clipping box at the painted width over its content, laid out
-- at the content width and anchored to one edge.
local function column(s: Shell, col: Column, node: Node, right_edge: boolean, tone: boolean): Node
	return ui.div {
		id = `{s.id}_{col}`,
		relative = true,
		h_full = true,
		shrink = 0,
		overflow = "hidden",
		-- Zeron's sidebar tone: the column's own 5% wash over the window glass,
		-- the full window height. The chat paints nothing; the right panel
		-- and Files paint the panel fill themselves.
		bg = if col == "sidebar" and tone then T.sidebar_tone else nil,
		w = function()
			return s.w[col]:get()
		end,
		ui.div {
			absolute = true,
			top = 0,
			bottom = 0,
			left = if right_edge then nil else 0,
			right = if right_edge then 0 else nil,
			w = function()
				local c = s.content[col]:get()
				return if c > 0 then c else s.w[col]:get()
			end,
			node,
		},
	}
end

local function seam(s: Shell, which: Seam, hairline: boolean): Node
	local function x(): number
		if which == "sidebar" then
			return s.w.sidebar:get()
		elseif which == "files" then
			return s.viewport:get() - s.w.files:get()
		end
		return s.viewport:get() - s.w.files:get() - s.w.right:get()
	end
	local function gone(): boolean
		local col: Column = if which == "sidebar" then "sidebar" elseif which == "files" then "files" else "right"
		return s.w[col]:get() < 0.5
	end
	local function local_x(e: PointerEvent): number
		local el = s.root:peek()
		return e.x - (if el then el.x or 0 else 0)
	end
	return ui.div {
		id = `{s.id}_seam_{which}`,
		absolute = true,
		top = 0,
		bottom = 0,
		w = M.SEAM_HIT,
		left = function()
			return x() - M.SEAM_HIT / 2
		end,
		-- In takeover, or covering the conversation, the pane has no seam.
		hidden = function()
			return gone() or (which == "right" and (s.expanded:get() or M.covered(s)))
		end,
		cursor = "col_resize",
		on_press = function()
			if s.armed[which] then
				s.armed[which] = nil
				s.dragging = nil
				M.reset(s, which)
				return
			end
			-- Each press arms its own window; a late timer from an older
			-- press must not disarm a newer one.
			s.seq += 1
			local token = s.seq
			s.armed[which] = token
			ui.after(M.DOUBLE_CLICK, function()
				if s.armed[which] == token then
					s.armed[which] = nil
				end
			end)
			s.dragging = which
		end,
		-- Only while pressed: the pointer passing over runs nothing.
		on_press_move = function(e: PointerEvent)
			if s.dragging == which then
				s.armed[which] = nil
				M.drag(s, which, local_x(e))
			end
		end,
		on_release = function()
			s.dragging = nil
		end,
		-- Under the pointer, a slim line down it (kit/resize), over the
		-- hairline where there is one.
		hover_group = true,
		require("./resize").line("row", if hairline and which == "sidebar" then -0.5 else 0),
		hairline and ui.div {
			absolute = true,
			top = 0,
			bottom = 0,
			left = M.SEAM_HIT / 2 - (if which == "sidebar" then 1 else 0),
			w = 1,
			-- Zeron's seams are the theme border, not the subtle hairline.
			bg = T.border,
			pointer_events = "none",
		} or nil,
	}
end

-- How far a card's shadow reaches past it (a well's: 24 of blur, 8 down):
-- the shell's clips reach that far past their edges where nothing of the
-- shell lies beyond, so a shadow falls on the sidebar and under the
-- topbar as it does below, rather than stopping in a hard line.
local REACH = 32

function M.view(s: Shell, parts: Parts): Node
	local hair = parts.hairlines ~= false
	local tone = parts.tone ~= false
	local conversation = ui.div {
		id = `{s.id}_conversation`,
		relative = true,
		h_full = true,
		shrink = 0,
		min_w = 0,
		-- Its content clipped at its end (wider as a column slides), and
		-- its cards' shadows reaching past its other edges.
		clip_inset = { -REACH, 0, -REACH, -REACH },
		w = function()
			return M.conversation_width(s)
		end,
		ui.div {
			id = `{s.id}_conversation_content`,
			absolute = true,
			top = 0,
			bottom = 0,
			left = 0,
			w = function()
				local c = s.conversation_content:get()
				return if c > 0 then c else M.conversation_width(s)
			end,
			parts.conversation,
		},
	}
	return ui.row {
		id = s.id,
		ref = s.root,
		relative = true,
		-- The columns clipped at the shell's ends; above it, shadows show.
		clip_inset = { -REACH, 0, 0, 0 },
		items = "stretch",
		w_full = parts.w_full,
		h_full = parts.h_full,
		h = parts.h,
		grow = parts.grow,
		min_w = 0,
		min_h = 0,
		on_resize = function(size: Size)
			M.observe(s, size.w)
		end,
		s.has.sidebar and column(s, "sidebar", parts.sidebar or ui.div {}, false, tone) or nil,
		conversation,
		s.has.right and column(s, "right", parts.right or ui.div {}, true, tone) or nil,
		s.has.files and column(s, "files", parts.files or ui.div {}, true, tone) or nil,
		s.has.sidebar and seam(s, "sidebar", hair) or nil,
		s.has.right and seam(s, "right", hair) or nil,
		s.has.files and seam(s, "files", hair) or nil,
	}
end

return M
