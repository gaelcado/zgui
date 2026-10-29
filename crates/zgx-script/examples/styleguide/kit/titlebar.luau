-- Zeron's unified titlebar (shell.rs `render_titlebar_cluster`, tabs.rs
-- `render_session_title_bar`): one 38-high band across the whole window,
-- on the glass, over the columns (they run beneath it, their seams
-- through it); no bottom border. Content sits 4 lower than centre, on the
-- traffic lights' line. The whole band moves the window and a double
-- click zooms it; only its buttons take clicks.
--
--   * The window controls: one cluster pinned at 88 (beside macOS's
--     traffic lights; 12 without them): the 24 sidebar toggle with its
--     morphing glyph, 8, then Back and Forward 2 apart, then an optional
--     new-session +, 8 further.
--   * The identity (a brand mark and a title at 12 medium, 85%) starts 16
--     past the sidebar while it shows, else 12 past the cluster, and
--     glides with the sidebar.
--   * The actions that end the content's stretch (the session card toggle,
--     28 buttons), then the right pane's header strip, as wide as the pane
--     beneath it, then the fixed right-edge anchors (28 each, 4 apart, 6
--     from the edge) in a slot as wide as the tool column under them.
local T = require("../theme")
local recipes = require("./recipes")
local motion = require("./motion")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local sidebar_glyph = require("./sidebar_glyph")

export type Props = {
	id: string?,
	-- Where the window controls start (88 beside macOS's traffic lights).
	inset: number?,
	-- The sidebar toggle, its glyph following `sidebar`.
	sidebar: State<boolean>?,
	on_sidebar: Handler?,
	on_back: Handler?,
	on_forward: Handler?,
	can_back: (() -> boolean)?,
	can_forward: (() -> boolean)?,
	on_new: Handler?,
	-- What the sidebar paints now (the identity glides with it).
	sidebar_w: (() -> number)?,
	title: Text?,
	title_icon: icon_mod.Name?,
	title_tint: Color?,
	-- The right pane has taken over: its strip owns the band, the title and
	-- the actions hide, and the row pulls back to the sidebar's seam.
	takeover: (() -> boolean)?,
	actions: { Node }?,
	-- The right pane's header strip, revealed as the pane opens.
	pane: Node?,
	pane_w: (() -> number)?,
	-- The width the pane's header lays out at (the pane's destination).
	pane_content_w: (() -> number)?,
	-- The right-edge anchors, over the tool column `files_w` wide.
	anchors: { Node }?,
	files_w: (() -> number)?,
	-- The band moves the window (true unless set; a specimen turns it off).
	window_drag: boolean?,
}

local M = {}

M.HEIGHT = 38
M.TOP_PAD = 4
M.CONTROL = 24
M.BUTTON = 28
M.CONTROL_GAP = 2
M.GROUP_GAP = 8
M.IDENTITY_GAP = 12
M.EDGE = 6
M.ANCHOR_GAP = 4
M.CLUSTER_PAD = 10
M.CLUSTER = 24 * 3 + 8 + 2
M.PANE_CONTROLS_MIN = 8 + 4 + 4 + 28

-- The host says which platform the window is on (macOS keeps its traffic
-- lights at the top left).
local platform = ui.shared("platform", "")
function M.inset(): number
	local p = platform:peek()
	return if p == "" or p == "macos" then 88 else 12
end

-- A window control: 24 square at radius 6, the glass wash fading in under
-- the pointer.
export type ControlProps = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	glyph: Node?,
	on_click: (Handler | Action)?,
	disabled: (() -> boolean)?,
}
M.control = ui.component(function(p: ControlProps): Node
	local function off(): boolean
		return p.disabled ~= nil and p.disabled()
	end
	return ui.button {
		id = p.id,
		w = M.CONTROL,
		h = M.CONTROL,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = T.clear,
		hover = { bg = T.glass_hover },
		focus = { border = 0 },
		cursor = "pointer",
		disabled = if p.disabled then p.disabled else nil,
		on_click = p.on_click,
		p.glyph or icon {
			name = p.icon or "arrow-left",
			size = 16,
			color = T.secondary,
			variants = recipes.faded { faded = off },
		},
	}
end)

-- A header button: 28 square at radius 6, the wash at 11% under the
-- pointer, 9% while what it toggles is on.
export type ButtonProps = {
	id: string?,
	-- What it says to assistive technology (it may follow what it toggles).
	label: string | (() -> string),
	icon: icon_mod.Name?,
	glyph: Node?,
	on: (() -> boolean)?,
	on_click: (Handler | Action)?,
	color: Color?,
}
M.button = ui.component(function(p: ButtonProps): Node
	return ui.button {
		id = p.id,
		label = p.label,
		w = M.BUTTON,
		h = M.BUTTON,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		variants = recipes.toggle_wash { on = p.on or false },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = p.on_click,
		p.glyph or icon { name = p.icon or "palette", size = 16, color = p.color or T.secondary },
	}
end)

-- A header button's count while work runs behind it (running_pill.rs
-- mark_titlebar_button): a 13 pill in the activity tone on its corner, 3
-- past it, mono 9 semibold; it holds still, the count the signal.
function M.count_badge(count: () -> number, id: string?): Node
	return ui.show(
		function()
			return count() > 0
		end,
		ui.row {
			id = id,
			absolute = true,
			top = -3,
			right = -3,
			h = 13,
			min_w = 13,
			px = "$zeron.space.3",
			items = "center",
			justify = "center",
			rounded = T.radius_full,
			bg = T.accent,
			pointer_events = "none",
			ui.text {
				function()
					local n = count()
					return if n > 99 then "99+" else tostring(n)
				end,
				literal = true,
				text_size = "$zeron.font.size.tile",
				line_height = 13,
				weight = "$font.weight.semibold",
				font = T.mono,
				color = T.on_accent,
			},
		}
	)
end

-- The anchors' slot keeps room for its buttons even when the column under
-- it is closed.
local function anchors_slot(count: number): number
	return count * M.BUTTON + math.max(count - 1, 0) * M.ANCHOR_GAP
end

M.titlebar = ui.component(function(p: Props): Node
	local inset = p.inset or M.inset()
	local cluster_end = inset + M.CLUSTER + (if p.on_new then M.GROUP_GAP + M.CONTROL else 0)
	local function sidebar_w(): number
		return if p.sidebar_w then p.sidebar_w() else 0
	end
	-- Where the identity starts: past the sidebar while it shows, else past
	-- the cluster.
	local function content_left(): number
		return math.max(sidebar_w() + 16, cluster_end + M.IDENTITY_GAP)
	end
	local function taken(): boolean
		return p.takeover ~= nil and p.takeover()
	end
	-- The band's width, for capping the pane's strip.
	local band = ui.state(`{p.id or "titlebar"}_band`, 0)
	-- In takeover the strip starts 8 before the sidebar's seam (its own 8
	-- lands the first chip on the pane's gutter), still clearing the
	-- window controls.
	local function row_left(): number
		if taken() then
			return math.max(sidebar_w() - 8, cluster_end - 14)
		end
		return content_left()
	end
	local n_anchors = if p.anchors then #p.anchors else 0
	local function files_controls(): number
		local files = if p.files_w then p.files_w() else 0
		return math.max(files - M.EDGE, anchors_slot(n_anchors))
	end
	-- The pane's strip ends where the anchors' slot begins and starts over
	-- the pane's seam.
	local function reveal_for(pane: number): number
		local files = if p.files_w then p.files_w() else 0
		local controls = files_controls()
		-- Never more than the row has between its start and the anchors.
		local gaps = if taken() then M.GROUP_GAP else M.GROUP_GAP * 3
		local room = band:get() - row_left() - M.EDGE - gaps - controls
		return math.max(math.min(pane + files - M.EDGE - controls, room), 0)
	end

	local cluster = ui.row {
		absolute = true,
		top = 0,
		left = 0,
		h = M.HEIGHT,
		pt = "$zeron.titlebar.top",
		pl = if p.inset
			then ui.raw(p.inset, "the caller's own inset")
			elseif inset == 88 then "$zeron.titlebar.inset_mac"
			else "$zeron.titlebar.inset",
		items = "center",
		-- No input of its own: the gaps between its buttons move the window.
		p.sidebar and M.control {
			id = p.id and `{p.id}_sidebar`,
			label = "Toggle sidebar",
			glyph = sidebar_glyph { open = p.sidebar, size = 16, color = T.secondary },
			on_click = p.on_sidebar,
		} or nil,
		(p.on_back or p.on_forward) and ui.row {
			ml = "$zeron.titlebar.group_gap",
			gap = "$zeron.titlebar.control_gap",
			items = "center",
			M.control {
				id = p.id and `{p.id}_back`,
				label = "Back",
				icon = "arrow-left",
				on_click = p.on_back,
				disabled = if p.can_back
					then function()
						return not (p.can_back :: () -> boolean)()
					end
					else nil,
			},
			M.control {
				id = p.id and `{p.id}_forward`,
				label = "Forward",
				icon = "arrow-right",
				on_click = p.on_forward,
				disabled = if p.can_forward
					then function()
						return not (p.can_forward :: () -> boolean)()
					end
					else nil,
			},
		} or nil,
		p.on_new and ui.div {
			ml = "$zeron.titlebar.group_gap",
			M.control { id = p.id and `{p.id}_new`, label = "New session", icon = "plus", on_click = p.on_new },
		} or nil,
	}

	local identity = (p.title or p.title_icon)
			and ui.row {
				min_w = 0,
				shrink = 1,
				gap = "$zeron.space.6",
				items = "center",
				overflow = "hidden",
				hidden = taken,
				p.title_icon and icon { name = p.title_icon, size = 14, color = p.title_tint or T.secondary } or nil,
				p.title and txt.text {
					p.title,
					id = p.id and `{p.id}_title`,
					size = "sm",
					weight = "medium",
					opacity = 0.85,
					truncate = true,
					line = false,
					shrink = 1,
					min_w = 0,
				} or nil,
			}
		or nil

	local pane = p.pane
		and ui.div {
			id = p.id and `{p.id}_pane`,
			relative = true,
			h_full = true,
			shrink = 0,
			overflow = "hidden",
			w = function()
				return reveal_for(if p.pane_w then p.pane_w() else 0)
			end,
			ui.row {
				absolute = true,
				top = 0,
				bottom = 0,
				right = 0,
				-- Laid out at the pane's destination, so the strip never
				-- reflows while the pane's edge moves.
				w = function()
					local now = reveal_for(if p.pane_w then p.pane_w() else 0)
					local rest = if p.pane_content_w then reveal_for(p.pane_content_w()) else now
					return math.max(now, rest)
				end,
				pl = "$zeron.space.8",
				pr = "$zeron.titlebar.anchor_gap",
				items = "center",
				-- Zeron shows the pane's header controls once there is room for
				-- them (8 + 4 + 4 + 28); below that the strip stays empty.
				hidden = function()
					return reveal_for(if p.pane_w then p.pane_w() else 0) < M.PANE_CONTROLS_MIN
				end,
				p.pane,
			},
		}
	local anchors = n_anchors > 0
		and ui.row {
			h_full = true,
			shrink = 0,
			w = files_controls,
			gap = "$zeron.titlebar.anchor_gap",
			items = "center",
			justify = "end",
			{ table.unpack(p.anchors :: { Node }) },
		}

	return ui.div {
		id = p.id,
		relative = true,
		w_full = true,
		h = M.HEIGHT,
		shrink = 0,
		window_drag = p.window_drag ~= false,
		on_resize = function(size: Size)
			band:set(size.w)
		end,
		ui.row {
			w_full = true,
			h_full = true,
			pt = "$zeron.titlebar.top",
			-- Past the sidebar's painted width, or the window controls: a
			-- position the columns decide, not a step of the scale.
			pl = function()
				return ui.raw(row_left(), "the identity starts past the sidebar's live width")
			end,
			pr = "$zeron.titlebar.edge",
			gap = "$zeron.titlebar.group_gap",
			items = "center",
			identity,
			ui.div { grow = 1, h_full = true },
			p.actions and ui.row {
				gap = "$zeron.titlebar.anchor_gap",
				items = "center",
				shrink = 0,
				hidden = taken,
				{ table.unpack(p.actions) },
			} or nil,
			pane or nil,
			anchors or nil,
		},
		cluster,
	}
end)

-- The pane toggle's glyph: the sidebar glyph mirrored, its panel at right.
export type GlyphProps = { open: State<boolean> | (() -> boolean), size: number?, color: Color? }
M.pane_glyph = ui.component(function(p: GlyphProps): Node
	local k = (p.size or 16) / 24
	local color = p.color or T.secondary
	local function on(): boolean
		local o: any = p.open
		if type(o) == "function" then
			return (o :: () -> boolean)()
		end
		return (o :: State<boolean>):get()
	end
	return ui.div {
		relative = true,
		w = 24 * k,
		h = 24 * k,
		ui.div {
			absolute = true,
			left = 2.125 * k,
			top = 3.125 * k,
			w = 19.75 * k,
			h = 17.75 * k,
			rounded = ui.raw(4.875 * k, "a drawn glyph's corner, scaled with it"),
			border = 1.75 * k,
			border_color = color,
		},
		ui.div {
			absolute = true,
			right = 6.5 * k,
			top = 7.5 * k,
			h = 9 * k,
			rounded = ui.raw(0.875 * k, "a drawn glyph's corner, scaled with it"),
			bg = color,
			w = ui.tween(
				ui.computed(function()
					return if on() then 5.5 * k else 1.75 * k
				end),
				{ duration = motion.d(280), ease = motion.EASE_OUT_QUINT }
			),
		},
	}
end)

-- The session card toggle's glyph: the frame with the panel's footprint
-- at its top right, cut to its top half.
function M.card_glyph(size: number?, color: Color?): Node
	local k = (size or 16) / 24
	local c = color or T.secondary
	return ui.div {
		relative = true,
		w = 24 * k,
		h = 24 * k,
		ui.div {
			absolute = true,
			left = 2.125 * k,
			top = 3.125 * k,
			w = 19.75 * k,
			h = 17.75 * k,
			rounded = ui.raw(4.875 * k, "a drawn glyph's corner, scaled with it"),
			border = 1.75 * k,
			border_color = c,
		},
		ui.div {
			absolute = true,
			right = 6.5 * k,
			top = 7.5 * k,
			w = 5.5 * k,
			h = 4.5 * k,
			rounded = ui.raw(0.875 * k, "a drawn glyph's corner, scaled with it"),
			bg = c,
		},
	}
end

return M
