-- A palette: a search header with the query and its count, scope chips,
-- grouped results with a title, a description and a key hint, and a
-- footer of hints (Wing's "Open a terminal, a browser or a panel" and the
-- @ reference picker). On frost, radius 14.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local chip = require("./chip")
local kbd = require("./kbd")
local hints = require("./hints")
local frost = require("./frost")
local motion = require("./motion")
local wash = require("./wash")
local glass = require("./glass")

export type Result = {
	id: string,
	title: string,
	-- The part of the title that matched the query, shown bold.
	match: string?,
	description: string?,
	group: string,
	icon: icon_mod.Name?,
	-- A letter on a tile instead of an icon (a site's initial).
	letter: string?,
	tint: Color?,
	-- Shown at the end: "Tab", "⌘ 1".
	meta: string?,
	keys: { string }?,
}
export type Props = {
	id: string?,
	placeholder: string,
	query: Reactive<string>,
	-- The header's icon: a magnifier unless told otherwise.
	icon: icon_mod.Name?,
	count: Text?,
	scopes: { string }?,
	scope: State<string>?,
	results: { Result },
	selected: State<string>?,
	hints: { hints.Hint }?,
	w: Length?,
	-- The results' height before they scroll (360).
	max_h: number?,
	on_choose: ((id: string) -> ())?,
}

local function tile(r: Result): Node
	if r.letter then
		return ui.row {
			w = 18,
			h = 18,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.5",
			bg = r.tint or T.ink4,
			txt.text {
				r.letter,
				size = "micro",
				weight = "semibold",
				line = false,
				color = if r.tint then T.bg else T.text,
			},
		}
	end
	return ui.row {
		w = 22,
		h = 22,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = T.ink2,
		icon { name = r.icon or "widget", size = 14, color = r.tint or T.secondary },
	}
end

-- A row: the selection sliding behind it (zimmer's palette highlight
-- follows ↑↓), the wash under the pointer (kit/wash).
local function row(props: Props, r: Result): Node
	local function on(): boolean
		return props.selected ~= nil and props.selected:get() == r.id
	end
	return ui.button {
		id = props.id and `{props.id}_{r.id}`,
		relative = true,
		hover_group = true,
		w_full = true,
		h = 40,
		px = "$zeron.space.8",
		gap = "$zeron.space.10",
		items = "center",
		justify = "start",
		rounded = T.radius_button,
		bg = T.clear,
		hover = { bg = T.clear },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = function()
			if props.selected then
				props.selected:set(r.id)
			end
			if props.on_choose then
				props.on_choose(r.id)
			end
		end,
		-- The selection: one piece sliding between rows (320 ms quint), as
		-- zimmer's palette highlight follows ↑↓.
		glass.active(`{props.id or "palette"}_sel`, on, T.radius_button),
		wash.layer(on, T.radius_button),
		tile(r),
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.1",
			if r.match
				then ui.rich {
					text_size = "$font.size.sm",
					color = T.text,
					truncate = true,
					ui.span { r.match, bold = true },
					ui.span { r.title },
				}
				else txt.text { r.title, size = "sm", weight = "medium", truncate = true, line = false },
			r.description
				and txt.text { r.description, size = "micro", mono = true, color = T.tertiary, truncate = true },
		},
		r.meta and txt.text { r.meta, size = "micro", color = T.tertiary, line = false },
		r.keys and kbd(table.clone(r.keys) :: kbd.Props),
	}
end

return ui.component(function(props: Props): Node
	local scopes: { Node } = {}
	for _, s in props.scopes or {} do
		table.insert(
			scopes,
			chip {
				label = s,
				size = "sm",
				selected = function()
					return props.scope ~= nil and props.scope:get() == s
				end,
				on_click = function()
					if props.scope then
						props.scope:set(s)
					end
				end,
			}
		)
	end
	local rows: { Node } = {}
	local last = ""
	for _, r in props.results do
		if r.group ~= last then
			table.insert(
				rows,
				ui.row {
					h = 24,
					px = "$zeron.space.8",
					items = "end",
					pb = "$zeron.space.5",
					txt.text { r.group, size = "micro", mono = true, color = T.tertiary },
				}
			)
			last = r.group
		end
		table.insert(rows, row(props, r))
	end
	local function query(): string
		local q = props.query
		return if type(q) == "string" then q elseif type(q) == "function" then q() else (q :: any):get()
	end
	return ui.column {
		id = props.id,
		w = props.w or 396,
		rounded = "$zeron.radius.14",
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		overflow = "hidden",
		on_mount = function(el: Element)
			anime.animate(
				el,
				{ opacity = { 0, 1 }, y = { 6, 0 }, duration = motion.d(motion.MENU_IN), ease = motion.EASE_OUT_QUINT }
			)
		end,
		ui.row {
			h = 36,
			px = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			icon { name = props.icon or "magnifer", size = 14, color = T.secondary },
			txt.text {
				function()
					local text = query()
					return if text == "" then props.placeholder else text
				end,
				size = "md",
				line = false,
				color = "inherit",
				variants = recipes.query_text {
					empty = function()
						return query() == ""
					end,
				},
			},
			ui.div {
				w = 1.5,
				h = 15,
				bg = T.text,
				opacity = if motion.loops() then ui.loop { from = 1, to = 0, duration = 1000, fps = 20 } else 1,
			},
			ui.div { grow = 1 },
			props.count and txt.text { props.count, size = "micro", mono = true, color = T.tertiary, line = false },
			kbd { "esc", flat = true, size = "sm" },
		},
		#scopes > 0 and ui.row { px = "$zeron.space.10", pb = "$zeron.space.8", gap = "$zeron.space.4", scopes },
		ui.div { h = 1, w_full = true, bg = T.hairline },
		-- The results scroll past `max_h`, faded where they run past (24).
		ui.scroll {
			w_full = true,
			max_h = props.max_h or 360,
			fade = { 24, 24 },
			fade_overflow = true,
			ui.column {
				p = "$zeron.space.6",
				gap = "$zeron.space.1",
				w_full = true,
				rows,
			},
		},
		props.hints and hints { items = props.hints },
	}
end)
