-- What the two layouts draw around the same columns. Zeron's: a unified
-- titlebar over flush columns, so content starts under its band. Glass
-- (Rex's): no band; the sidebar sits on the window's blur and every
-- content column is a well inset into it, with a header of its own.
local tb = require("@kit/titlebar")
local ps = require("@kit/panel_shell")
local well = require("@kit/well")
local state = require("./state")

local M = {}

-- The glass layout's gap: from the window's edges to the wells, and
-- between two wells.
M.GAP = 6
-- From the window's left edge past the traffic lights (an inset titlebar).
M.LIGHTS = 78
-- The traffic lights' centre line, from the window's top: every layout's
-- window controls sit on it, as the unified titlebar's do (4 down, 38 high).
M.LIGHTS_LINE = 21

-- Content sits in wells (every layout but the classic one).
function M.glass(): boolean
	return state.layout:get() ~= "zeron"
end

-- Where a column's content starts: under Zeron's band, or at the top of
-- its well or pane.
function M.top(): Length
	return if M.glass() then 0 else "$zeron.titlebar.height"
end
-- The same in points, for a position (`top`), which takes no token.
function M.top_px(): number
	return if M.glass() then 0 else tb.HEIGHT
end

export type WellProps = {
	id: string,
	header: (() -> Node)?,
	-- Built again when the layout changes (one layout's tree leaves before
	-- the other's mounts, so their ids never meet).
	body: () -> Node,
	-- The first content column starts at the sidebar: with the sidebar
	-- shut it keeps the gap from the window's edge too.
	first: boolean?,
	-- Which column it is, for the focus.
	column: string,
	-- A class and opacity of its box (what the voice stage fades).
	class: string?,
	opacity: number?,
}

-- A column's content in the glass layout: a well inset by the gap from
-- the window's top, right and bottom (the next well's gap is its own), with
-- its header over its body. In Zeron's layout, the body alone.
function M.column(p: WellProps): Node
	-- The right pane and Files are built the first time they show (shut,
	-- a column costs nothing), then kept, shut or open, so what they hold
	-- stays as it was.
	local built = p.column ~= "right" and p.column ~= "files"
	local function layout(): string?
		if not built then
			built = ps.shown(state.shell(), p.column :: any)
		end
		return if built then state.layout:get() else nil
	end
	return ui.presence(layout, function(layout: string): Node
		if layout ~= "glass" then
			return p.body()
		end
		return ui.div {
			w_full = true,
			h_full = true,
			pt = "$zeron.well.gap",
			pb = "$zeron.well.gap",
			pr = "$zeron.well.gap",
			pl = if p.first
				then function()
					return if state.shell().w.sidebar:get() < 0.5 then "$zeron.well.gap" else 0
				end
				else 0,
			well.well {
				id = p.id,
				focused = function()
					local f = state.focus:get()
					if f == p.column then
						return true
					end
					-- A focused column that has closed hands it back to
					-- the conversation.
					return p.column == "conversation" and not ps.shown(state.shell(), f :: any)
				end,
				on_press = function()
					state.focus:set(p.column)
				end,
				header = p.header and p.header(),
				p.body(),
			},
		}
	end, { w_full = true, h_full = true, class = p.class, opacity = p.opacity })
end

M.split_glyph = well.split_glyph
M.header = well.header
M.HEADER = well.HEADER

return M
