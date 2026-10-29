-- Comments (comment_ui.rs): the 16-point add button on the solid; a
-- comment card on ink 5% with a 3-point solid rail at 35%, a 22 header
-- (chat glyph, mono location, edit and remove on hover) and a 12/18 body;
-- the draft card at 116 with its 46 input and 22-high actions, Enter
-- posting it (Shift+Enter a new line), Escape dropping it. Editing a
-- comment is its draft again, filled, its action "Save". Floating (the code
-- editor's, over its lines: preview.rs render_editor_comment_card), either
-- is a frosted card with no rail.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local recipes = require("./recipes")

export type CardProps = {
	id: string?,
	where: string,
	body: string,
	w: Length?,
	-- Its edit and remove buttons (shown under the pointer).
	on_edit: Handler?,
	on_remove: Handler?,
	floating: boolean?,
}
export type DraftProps = {
	id: string?,
	where: string,
	value: State<string>,
	w: Length?,
	on_submit: Handler?,
	on_cancel: Handler?,
	autofocus: boolean?,
	-- "Comment" (a new one) or "Save" (an edit).
	action: string?,
	-- "Request a change…" unless set.
	placeholder: string?,
	floating: boolean?,
}

local M = {}

function M.add(on_click: (Handler | Action)?, id: string?): Node
	return ui.button {
		id = id,
		label = "Comment",
		w = 16,
		h = 16,
		p = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.4",
		bg = T.solid,
		hover = { bg = T.solid_hover },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = on_click,
		icon { name = "plus", size = 11, color = T.on_solid },
	}
end

local function frame(
	id: string?,
	w: Length?,
	rail_opacity: number,
	bg: Color,
	children: { Node },
	-- Its actions show under the pointer (`group_hover` inside).
	group: boolean?,
	floating: boolean?
): Node
	if floating then
		return ui.column {
			id = id,
			w = w,
			w_full = w == nil,
			variants = recipes.frost {},
			px = "$zeron.space.16",
			py = "$zeron.space.8",
			gap = "$zeron.space.4",
			hover_group = group,
			children,
		}
	end
	return ui.row {
		id = id,
		w = w,
		w_full = w == nil,
		items = "stretch",
		bg = bg,
		hover_group = group,
		ui.div { w = 3, bg = T.solid, opacity = rail_opacity, shrink = 0 },
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			gap = "$zeron.space.4",
			children,
		},
	}
end

-- A card's 16 action (comment_ui.rs card_action): its glyph at 12 in the
-- muted text, radius 4, named and tipped by `label`.
local function action(id: string?, glyph: icon.Name, label: string, on_click: Handler?): Node
	return ui.button {
		id = id,
		variants = recipes.wash { hover = "ink3" },
		w = 16,
		h = 16,
		p = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.4",
		focus = { border = 0 },
		cursor = "pointer",
		label = label,
		tooltip = label,
		on_click = on_click,
		icon { name = glyph, size = 12, color = T.secondary },
	}
end

M.card = ui.component(function(props: CardProps): Node
	return frame(props.id, props.w, 0.35, T.ink1, {
		ui.row {
			h = 22,
			gap = "$zeron.space.6",
			items = "center",
			icon { name = "chat-round-line", size = 12, color = T.tertiary },
			txt.text {
				props.where,
				size = "xs",
				mono = true,
				color = T.tertiary,
				line = false,
				truncate = true,
				grow = 1,
				shrink = 1,
				min_w = 0,
			},
			ui.row {
				gap = "$zeron.space.2",
				opacity = 0,
				group_hover = { opacity = 1 },
				props.on_edit and action(props.id and `{props.id}_edit`, "pen", "Edit comment", props.on_edit) or nil,
				action(props.id and `{props.id}_remove`, "close-circle", "Remove comment", props.on_remove),
			},
		},
		txt.text { props.body, size = "sm", color = T.secondary, wrap = true },
	}, true, props.floating)
end)

M.draft = ui.component(function(props: DraftProps): Node
	return frame(props.id, props.w, 0.7, T.ink3, {
		ui.row {
			h = 22,
			gap = "$zeron.space.6",
			items = "center",
			icon { name = "chat-round-line", size = 12, color = T.tertiary },
			txt.text { props.where, size = "xs", mono = true, color = T.tertiary, line = false },
		},
		ui.textarea {
			id = props.id and `{props.id}_input`,
			value = props.value,
			label = "Comment",
			-- It takes the keyboard as it opens (`autofocus`); Enter posts it
			-- (⌘⏎ too), Shift+Enter breaks the line, Escape drops it.
			on_mount = if props.autofocus
				then function(el: Element)
					el:focus()
					-- Floating, it is placed under its line once the editor
					-- lays out: it takes the keyboard then.
					if props.floating then
						ui.after(0, function()
							el:focus()
						end)
					end
				end
				else nil,
			on_key = function(e: KeyEvent): boolean
				if e.key == "Enter" and not e.shift and props.on_submit then
					props.on_submit()
					return true
				elseif e.key == "Escape" and props.on_cancel then
					props.on_cancel()
					return true
				end
				return false
			end,
			placeholder = props.placeholder or "Request a change…",
			placeholder_color = T.tertiary,
			h = 46,
			w_full = true,
			p = 0,
			bg = T.clear,
			border = 0,
			rounded = 0,
			font = T.sans,
			text_size = "$font.size.sm",
			color = T.text,
			focus = { border = 0 },
		},
		ui.row {
			h = 28,
			gap = "$zeron.space.6",
			items = "center",
			justify = "end",
			ui.button {
				id = props.id and `{props.id}_cancel`,
				variants = recipes.wash { hover = "hover" },
				h = 22,
				px = "$zeron.space.10",
				items = "center",
				rounded = T.radius_md,
				cursor = "pointer",
				focus = { border = 0 },
				on_click = props.on_cancel,
				txt.text { "Cancel", size = "xs", weight = "medium", color = T.secondary, line = false },
			},
			ui.button {
				id = props.id and `{props.id}_submit`,
				h = 22,
				px = "$zeron.space.10",
				items = "center",
				rounded = T.radius_md,
				bg = T.solid,
				hover = { bg = T.solid_hover },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = props.on_submit,
				txt.text {
					props.action or "Comment",
					size = "xs",
					weight = "medium",
					color = T.on_solid,
					line = false,
				},
			},
		},
	}, nil, props.floating)
end)

return M
