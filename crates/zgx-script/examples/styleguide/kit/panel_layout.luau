-- Zeron's panel layout policy (shell/panel_layout.rs, PRs 677 and 914),
-- pure: which columns fit the window, how the open ones share its width,
-- and how a column moves between arrangements.
--
-- The sidebar and Files are tools: they keep their own widths, like a
-- navigator and an inspector. The conversation and the right pane are
-- content: they share what the tools leave equally, and absorb every
-- change. A dragged divider holds until the next panel toggle; a seam's
-- reset restores the split. A window too narrow for every open column's
-- minimum hides the least recently opened one (in takeover the right pane
-- goes last); asking for a hidden column ranks it most recent, and it
-- returns when space permits. Columns move on the dialog entrance's curve,
-- 180 ms up to the sidebar's width and up to 240 ms for wider moves. A
-- column's content lays out at its destination when it opens and keeps its
-- layout while it closes: the column masks it, never reflows it.
local M = {}

M.SIDEBAR_MIN = 242
M.SIDEBAR_MAX = 400
M.SIDEBAR_DEFAULT = 256
M.FILES_MIN = 220
M.FILES_MAX = 440
M.FILES_DEFAULT = 286
M.RIGHT_MIN = 360
M.RIGHT_DEFAULT = 520
M.CHAT_MIN = 300

-- PANEL_RESIZE = DIALOG_IN: 180 ms on `ease`.
M.BASE = 180
M.EASE = "cubicBezier(0.25, 0.1, 0.25, 1)"

export type Column = "sidebar" | "right" | "files"
-- An open flag and when it was opened (a rising sequence).
export type Slot = { open: boolean, at: number }
-- `covered`: the right pane takes the conversation's room (`cover`).
export type Fit = { sidebar: boolean, right: boolean, files: boolean, sidebar_limit: number, covered: boolean? }
export type Widths = { sidebar: number, right: number, files: number }

-- How long a column takes from `from` to `to`: twice the distance in the
-- same time up to the sidebar's width, growing with the square root of the
-- distance to at most 4/3 of the base.
function M.duration(from: number, to: number): number
	local scale = math.clamp(math.sqrt(math.abs(to - from) / M.SIDEBAR_DEFAULT), 1, 4 / 3)
	return M.BASE * scale
end

-- The right pane's half of `available` (what the tools leave). When halves
-- would break a minimum, the pane keeps its own and the conversation as
-- much of its own as fits (`chat_min`, CHAT_MIN unless given).
function M.content_split(available: number, chat_min: number?): number
	local floor = chat_min or M.CHAT_MIN
	return math.min(math.max(available / 2, M.RIGHT_MIN), math.max(available - floor, M.RIGHT_MIN))
end

-- The width a column's content lays out at while its mask runs `from → to`
-- (`current` is what it lays out at now): opening from closed lays out at
-- the destination, closing keeps the current layout; between two open
-- widths it starts from the wider and eases to the destination.
function M.content_tween(current: number, from: number, to: number): (number, number)
	if from < 0.5 then
		return to, to
	elseif to < 0.5 then
		local w = math.max(current, from)
		return w, w
	end
	return math.max(current, from), to
end

-- Which columns the window has room for. `sidebar_width` is the sidebar's
-- preferred width; the fit may squeeze it (`sidebar_limit`). With `cover`
-- (the pull requests' board: shell/pull_request_pane.rs), the conversation
-- keeps that much beside the open pane, and where the window cannot give
-- it that and the pane its minimum, the pane covers it rather than going.
function M.fit(
	viewport: number,
	sidebar_width: number,
	sidebar: Slot,
	right: Slot,
	files: Slot,
	expanded: boolean,
	cover: number?
): Fit
	local open = { sidebar.open, right.open, files.open }
	local at = { sidebar.at, right.at, files.at }
	local mins = { M.SIDEBAR_MIN, M.RIGHT_MIN, M.FILES_MIN }
	viewport = math.max(viewport, 0)
	-- Takeover spends only the conversation's width on the right pane;
	-- below the chat and pane minima the pane alone may still take over.
	local narrow_takeover = expanded and right.open and viewport < M.CHAT_MIN + M.RIGHT_MIN
	if narrow_takeover then
		open[1] = false
		open[3] = false
	end
	local covered = false
	while true do
		local chat_floor = if open[2] and (narrow_takeover or covered)
			then 0
			elseif open[2] and cover then cover
			else M.CHAT_MIN
		local minimum = chat_floor
		for i = 1, 3 do
			if open[i] then
				minimum += mins[i]
			end
		end
		if minimum <= viewport then
			local limit = 0
			if open[1] then
				limit = viewport
					- chat_floor
					- (if open[2] then M.RIGHT_MIN else 0)
					- (if open[3] then M.FILES_MIN else 0)
				limit = math.min(limit, sidebar_width)
			end
			return {
				sidebar = open[1],
				right = open[2],
				files = open[3],
				sidebar_limit = limit,
				covered = open[2] and covered,
			}
		end
		if cover and open[2] and not covered then
			covered = true
			continue
		end
		-- The least recently opened goes; takeover is the user's choice to
		-- give the pane the conversation's room, so the others go first.
		local victim: number? = nil
		local best_kept, best_at = 0, 0
		for i = 1, 3 do
			if open[i] then
				local kept = if expanded and i == 2 then 1 else 0
				if victim == nil or kept < best_kept or (kept == best_kept and at[i] < best_at) then
					victim, best_kept, best_at = i, kept, at[i]
				end
			end
		end
		if victim == nil then
			return { sidebar = false, right = false, files = false, sidebar_limit = 0 }
		end
		open[victim] = false
	end
end

-- Where each column rests for a fit: the sidebar at its allowance; Files at
-- its own width as far as the conversation's and the pane's minimums leave
-- room; the pane at its share (`right_width`), or everything the tools
-- leave in takeover or covering. `chat_min` is the conversation's floor
-- beside the pane (CHAT_MIN unless given).
function M.settled(
	viewport: number,
	fit: Fit,
	files_width: number,
	right_width: number,
	expanded: boolean,
	chat_min: number?
): Widths
	local floor = chat_min or M.CHAT_MIN
	local sidebar = if fit.sidebar then fit.sidebar_limit else 0
	local files = 0
	if fit.files then
		local room = viewport - sidebar - M.CHAT_MIN - (if fit.right then M.RIGHT_MIN else 0)
		files = math.min(files_width, math.max(room, 0))
	end
	local right = 0
	if fit.right then
		if expanded or fit.covered then
			right = math.max(viewport - sidebar - files, 0)
		else
			right = math.min(right_width, math.max(viewport - sidebar - files - floor, 0))
		end
	end
	return { sidebar = sidebar, right = right, files = files }
end

return M
