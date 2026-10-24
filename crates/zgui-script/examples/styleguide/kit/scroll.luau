-- A scroll area with Zeron's edge fades and, when asked, zgui's overlay
-- scrollbar (shown while scrolling). Nothing runs in script as it scrolls:
-- sizes are measured only for a caller that passes `on_measure`.

export type Props = {
	id: string?,
	-- What a screen reader calls the scroll area ("Transcript", "Sessions").
	label: string?,
	[number]: Child,
	w: Length?,
	h: Length?,
	w_full: boolean?,
	h_full: boolean?,
	grow: number?,
	p: Length?,
	px: Length?,
	py: Length?,
	gap: Num?,
	-- The scroll position, if the caller wants it.
	offset: State<number>?,
	-- Keep the view at the end as content grows (a transcript); a state:
	-- only while it holds (while a reply streams).
	follow: (boolean | Readable<boolean>)?,
	-- Written by the scroll: whether it shows its end (for a jump pill).
	at_end: State<boolean>?,
	-- The scrollbar on, for specimens.
	preview: boolean?,
	-- Zeron shows no scrollbar; `thumb = true` turns on zgui's overlay one.
	thumb: boolean?,
	-- Nodes laid over the view (a jump pill), absolutely positioned in it.
	over: { Node }?,
	-- Edge fade band at the top and bottom (24 unless set; 0 for none), only as far as content runs
	-- past the edge (Zeron: 24 for lists, 12 for menus, 16 for settings).
	fade: number?,
	-- Space reserved after the content (the sent-turn hold's runway, see
	-- own_turn): the view can scroll that far past what is there.
	runway: (State<number> | (() -> number))?,
	-- The view's and the content's sizes as layout reports them (the
	-- content without the runway).
	on_measure: ((view: Size, content: Size) -> ())?,
}

return ui.component(function(props: Props): Node
	local fade = if props.fade == nil then 24 else props.fade
	-- Sizes are measured only for a caller that asks (the sent-turn hold):
	-- otherwise nothing runs as the view or its content resizes.
	local measure = props.on_measure
	local view: State<Size>? = if measure then ui.use_state { w = 0, h = 0 } else nil
	local content: State<Size>? = if measure then ui.use_state { w = 0, h = 0 } else nil
	local function report()
		if measure and view and content then
			measure(view:peek(), content:peek())
		end
	end
	-- `relative`: `over` positions against this box, not the nearest
	-- relative ancestor up the tree.
	return ui.overlay {
		id = props.id,
		relative = true,
		w = props.w,
		h = props.h,
		w_full = props.w_full,
		h_full = props.h_full,
		grow = props.grow,
		-- In a column it must be allowed to shrink to the space left.
		min_h = if props.grow or props.h_full then 0 else nil,
		min_w = 0,
		shrink = 1,
		overflow = "hidden",
		items = "stretch",
		justify = "stretch",
		-- The overlay stretches it; percentages here would feed its size back
		-- into the overlay's.
		ui.scroll {
			label = props.label,
			offset = props.offset,
			follow = props.follow,
			at_end = props.at_end,
			-- zgui's overlay scrollbar, hidden until scrolling (Zeron shows none
			-- unless asked).
			scrollbar = props.thumb == true or props.preview == true,
			fade = if fade > 0 then { fade, fade } else nil,
			fade_overflow = fade > 0,
			on_resize = if view
				then function(size: Size)
					(view :: State<Size>):set { w = size.w, h = size.h }
					report()
				end
				else nil,
			ui.column {
				w_full = true,
				p = props.p,
				px = props.px,
				py = props.py,
				gap = props.gap,
				on_resize = if content
					then function(size: Size)
						(content :: State<Size>):set { w = size.w, h = size.h }
						report()
					end
					else nil,
				{ table.unpack(props) },
			},
			props.runway and ui.div { w_full = true, shrink = 0, h = props.runway },
		},
		props.over,
	}
end)
