-- A switch, after Zeron's settings switch (settings/widgets.rs
-- toggle_switch): a pill track, a near-white thumb that slides across, the
-- track the accent when on. `lg` is Zeron's own (44.8 × 28.8: a 20.8 track
-- under a 24 × 17.6 thumb, the on and off marks beneath it); `md` and `sm`
-- are the compact ones, a round thumb filling the track less 2. The thumb
-- is the track's sibling, not its child, so a border never moves it off
-- centre. Colour and place are bindings: no script runs per frame. Its
-- look is `recipes.switch_*`.
local T = require("../theme")
local types = require("./types")
local txt = require("./text")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	value: State<boolean>,
	label: Text?,
	description: Text?,
	disabled: types.Cond?,
	-- sm 26×16 · md 32×18 · lg Zeron's settings switch.
	size: ("sm" | "md" | "lg")?,
	on_change: ((on: boolean) -> ())?,
}

type Metrics = { w: number, h: number, track: number, thumb_w: number, thumb_h: number, inset: number }
local METRICS: { [string]: Metrics } = {
	sm = { w = 26, h = 16, track = 16, thumb_w = 12, thumb_h = 12, inset = 2 },
	md = { w = 32, h = 18, track = 18, thumb_w = 14, thumb_h = 14, inset = 2 },
	lg = { w = 44.8, h = 28.8, track = 20.8, thumb_w = 24, thumb_h = 17.6, inset = 1.6 },
}

return ui.component(function(props: Props): Node
	local size = props.size or "md"
	local m = METRICS[size]
	local large = size == "lg"
	local on = function(): boolean
		return props.value:get()
	end
	local travel = m.w - m.thumb_w - 2 * m.inset
	local thumb_x = ui.spring(
		ui.computed(function()
			return if props.value:get() then travel else 0
		end),
		{ stiffness = 700, damping = 40 }
	)
	-- Zeron's marks: a bar where the thumb leaves when on, a ring when off.
	local marks: Node? = if large
		then ui.row {
			absolute = true,
			top = 0,
			left = 0,
			w = m.w,
			h = m.h,
			-- The marks centre in the room the thumb leaves: a drawing's
			-- geometry, from the switch's size.
			px = ui.raw((m.w - m.thumb_w - m.inset - 7.2) / 2, "a drawn switch's mark, centred in its room"),
			items = "center",
			justify = "between",
			pointer_events = "none",
			ui.div {
				w = 7.2,
				h = 7.2,
				items = "center",
				justify = "center",
				opacity = ui.tween(props.value, { from = 0, to = 1, duration = 180 }),
				ui.div { w = 1.2, h = 7.2, rounded = T.radius_full, bg = T.switch_mark },
			},
			ui.div {
				w = 7.2,
				h = 7.2,
				items = "center",
				justify = "center",
				opacity = ui.tween(props.value, { from = 1, to = 0, duration = 180 }),
				ui.div { w = 6.4, h = 6.4, rounded = T.radius_full, border = 1, border_color = T.secondary },
			},
		}
		else nil
	local switch = ui.overlay {
		w = m.w,
		h = m.h,
		relative = true,
		shrink = 0,
		ui.div {
			absolute = true,
			top = (m.h - m.track) / 2,
			left = 0,
			w = m.w,
			h = m.track,
			variants = recipes.switch_track { on = on },
		},
		marks,
		ui.div {
			absolute = true,
			top = (m.h - m.thumb_h) / 2,
			left = m.inset,
			x = thumb_x,
			w = m.thumb_w,
			h = m.thumb_h,
			variants = recipes.switch_thumb,
		},
	}
	return ui.button {
		id = props.id,
		variants = recipes.switch_row { lines = if props.description then "two" else "one" },
		disabled = props.disabled,
		on_click = function()
			local next = not props.value:peek()
			props.value:set(next)
			if props.on_change then
				props.on_change(next)
			end
		end,
		switch,
		props.label and ui.column {
			gap = "$zeron.space.1",
			txt.text { props.label, size = "md", line = props.description == nil },
			props.description and txt.text { props.description, size = "sm", color = T.secondary },
		},
	}
end)
