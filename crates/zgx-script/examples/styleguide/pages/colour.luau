-- Colour: every token in the context it is for, with its value and the
-- contrast it makes against the surface it sits on. Values and ratios are
-- read from the theme, so they follow a theme switch.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local colour = require("@lib/colour")
local labels = require("./colour_labels")

type Entry = { token: string, role: string, note: string? }

-- The surfaces, from the window out.
local SURFACES: { Entry } = {
	{ token = "background", role = "background", note = "the window" },
	{ token = "surface.sunken", role = "terminal.background", note = "wells, code, terminals" },
	{ token = "surface.base", role = "shell", note = "sidebars and panels" },
	{ token = "zeron.card", role = "card", note = "cards in the transcript" },
	{ token = "zeron.dialog", role = "dialog" },
	{ token = "surface.overlay", role = "overlay", note = "menus and popovers" },
	{ token = "surface.raised", role = "raised", note = "controls" },
}
local TEXTS: { Entry } = {
	{ token = "text.primary", role = "text" },
	{ token = "text.secondary", role = "text_muted" },
	{ token = "text.tertiary", role = "text_faint" },
	{ token = "text.disabled", role = "(text at 38%)" },
}
local ACCENTS: { Entry } = {
	{ token = "accent", role = "accent.primary" },
	{ token = "accent.hover", role = "glyph light" },
	{ token = "danger", role = "danger" },
	{ token = "warning", role = "warning" },
	{ token = "success", role = "success" },
	{ token = "info", role = "(ANSI blue)" },
}
local MUTED: { Entry } = {
	{ token = "zeron.danger.muted", role = "danger_muted" },
	{ token = "zeron.warning.muted", role = "warning_muted" },
	{ token = "zeron.success.muted", role = "success_muted" },
	{ token = "zeron.claude", role = "Claude" },
}
local WASHES: { Entry } = {
	{ token = "hover", role = "hover" },
	{ token = "pressed", role = "active" },
	{ token = "selection.item", role = "card_selected_bg" },
	{ token = "selection", role = "accent.selection" },
	{ token = "zeron.accent.wash", role = "accent.wash" },
	{ token = "zeron.danger.wash", role = "danger at 14%" },
	{ token = "zeron.warning.wash", role = "warning at 14%" },
	{ token = "zeron.success.wash", role = "success at 14%" },
	{ token = "zeron.accent_faint", role = "blockquote, accent at 5%" },
	{ token = "zeron.code.wash", role = "inline code, accent at 22%" },
	{ token = "zeron.diff.add_wash", role = "diff line added, 5.5%" },
	{ token = "zeron.diff.delete_wash", role = "diff line deleted, 5.5%" },
	{ token = "zeron.diff.hunk", role = "hunk header, accent at 8%" },
}
local LANES = { "zeron.lane.1", "zeron.lane.2", "zeron.lane.3", "zeron.lane.4", "zeron.lane.5", "zeron.lane.6" }
local LINES: { Entry } = {
	{ token = "border.subtle", role = "hairline(.06)" },
	{ token = "border", role = "border" },
	{ token = "border.strong", role = "border_strong" },
	{ token = "zeron.input.border", role = "composer_surface_border" },
	{ token = "focus.ring", role = "(accent)" },
}
local INKS = { "zeron.ink.1", "zeron.ink.2", "zeron.ink.3", "zeron.ink.4", "zeron.ink.5", "zeron.ink.6" }

-- A contrast badge: the ratio of `fg` over `bg`, green from 4.5, amber from
-- 3, red under.
local function contrast(fg: string, bg: string, large: boolean?): Node
	local function ratio(): number
		local f, b = colour.token(fg), colour.token(bg)
		if not f or not b then
			return 0
		end
		return colour.contrast(f, b)
	end
	local function tone(): Color
		local r = ratio()
		local pass = if large then 3 else 4.5
		return if r >= pass then T.success elseif r >= 3 then T.warning else T.danger
	end
	return ui.row {
		h = 18,
		px = "$zeron.space.6",
		gap = "$zeron.space.4",
		items = "center",
		rounded = T.radius_sm,
		bg = T.ink2,
		ui.div { w = 6, h = 6, rounded = "$zeron.radius.3", bg = tone },
		kit.text.text {
			function()
				return colour.ratio(ratio())
			end,
			size = "micro",
			mono = true,
			color = T.secondary,
			tabular = true,
			line = false,
		},
	}
end

local function value(token: string): Node
	return kit.text.text {
		function()
			return colour.label(ui.theme.get(token))
		end,
		size = "xs",
		mono = true,
		color = T.tertiary,
	}
end

-- A surface card: the surface itself, text on it, and what it is.
local function surface_card(entry: Entry): Node
	return ui.column {
		w = 196,
		h = 128,
		p = "$zeron.space.14",
		gap = "$zeron.space.4",
		rounded = T.radius_card,
		bg = "$" .. entry.token,
		border = 1,
		border_color = T.hairline,
		kit.text.text { entry.token, size = "sm", mono = true, weight = "medium" },
		kit.text.text { entry.role, size = "xs", color = T.secondary },
		entry.note and kit.text.text { entry.note, size = "xs", color = T.tertiary },
		ui.div { grow = 1 },
		ui.row {
			items = "center",
			gap = "$zeron.space.8",
			value(entry.token),
			ui.div { grow = 1 },
			contrast("text.primary", entry.token),
		},
	}
end

-- Text roles on one surface, each with its contrast.
local function text_on(surface: string): Node
	local rows: { Node } = {}
	for _, entry in TEXTS do
		table.insert(
			rows,
			ui.row {
				items = "center",
				gap = "$zeron.space.10",
				h = 26,
				kit.text.text { "The quick brown fox", size = "md", color = "$" .. entry.token, w = 150 },
				kit.text.text { entry.token, size = "xs", mono = true, color = T.tertiary, w = 112 },
				contrast(entry.token, surface),
			}
		)
	end
	return ui.column {
		w = 360,
		p = "$zeron.space.14",
		gap = "$zeron.space.2",
		rounded = T.radius_card,
		bg = "$" .. surface,
		border = 1,
		border_color = T.hairline,
		kit.text.text { "on " .. surface, size = "xs", mono = true, color = T.tertiary, mb = "$zeron.space.6" } :: Node,
		rows,
	}
end

-- A swatch tile: the colour as a fill, with a sample of it as text and as
-- a fill under on-colour text.
local function tile(entry: Entry): Node
	return ui.column {
		w = 148,
		gap = "$zeron.space.6",
		ui.column {
			h = 64,
			rounded = T.radius_lg,
			bg = "$" .. entry.token,
			p = "$zeron.space.10",
			justify = "end",
			ui.row {
				items = "center",
				gap = "$zeron.space.6",
				contrast(entry.token, "background", true),
			},
		},
		kit.text.text { entry.token, size = "xs", mono = true, color = T.text, truncate = true },
		kit.text.text { entry.role, size = "xs", color = T.tertiary, truncate = true },
		value(entry.token),
	}
end

-- A wash over the base surface, around a row of text, as it is used.
local function wash(entry: Entry): Node
	return ui.column {
		w = 164,
		gap = "$zeron.space.6",
		ui.column {
			p = "$zeron.space.6",
			rounded = T.radius_lg,
			bg = T.base,
			border = 1,
			border_color = T.hairline,
			ui.row {
				h = 30,
				px = "$zeron.space.10",
				items = "center",
				rounded = T.radius_item,
				bg = "$" .. entry.token,
				kit.text.text { "Row under the wash", size = "sm", line = false },
			},
		},
		kit.text.text { entry.token, size = "xs", mono = true, truncate = true },
		kit.text.text { entry.role, size = "xs", color = T.tertiary, truncate = true },
		value(entry.token),
	}
end

local function line(entry: Entry): Node
	return ui.column {
		w = 164,
		gap = "$zeron.space.6",
		ui.column {
			h = 56,
			rounded = T.radius_lg,
			bg = T.base,
			border = 1,
			border_color = "$" .. entry.token,
			p = "$zeron.space.10",
			w_full = true,
			justify = "center",
			ui.div { h = 1, w_full = true, bg = "$" .. entry.token },
		},
		kit.text.text { entry.token, size = "xs", mono = true, truncate = true },
		kit.text.text { entry.role, size = "xs", color = T.tertiary, truncate = true },
		value(entry.token),
	}
end

local function lanes(): Node
	local tiles: { Node } = {}
	for i, token in LANES do
		table.insert(
			tiles,
			ui.column {
				gap = "$zeron.space.6",
				items = "center",
				ui.div { w = 56, h = 56, rounded = T.radius_lg, bg = "$" .. token },
				kit.text.text { `lane.{i}`, size = "xs", mono = true, color = T.secondary },
				value(token),
			}
		)
	end
	return ui.row { gap = "$zeron.space.16", tiles }
end

local function inks(): Node
	local tiles: { Node } = {}
	for i, token in INKS do
		table.insert(
			tiles,
			ui.column {
				gap = "$zeron.space.6",
				items = "center",
				ui.div { w = 56, h = 56, rounded = T.radius_lg, bg = "$" .. token },
				kit.text.text { `ink.{i}`, size = "xs", mono = true, color = T.secondary },
				value(token),
			}
		)
	end
	return ui.row {
		gap = "$zeron.space.10",
		p = "$zeron.space.14",
		rounded = T.radius_card,
		bg = T.base,
		border = 1,
		border_color = T.hairline,
		tiles,
	}
end

local function diff(): Node
	local function row(sign: string, text: string, fg: Color, bg: Color): Node
		return ui.row {
			h = 22,
			px = "$zeron.space.10",
			gap = "$zeron.space.10",
			items = "center",
			bg = bg,
			kit.text.text { sign, size = "sm", mono = true, color = fg, w = 10 },
			kit.text.text { text, size = "sm", mono = true, color = fg },
		}
	end
	return ui.column {
		w = 420,
		py = "$zeron.space.6",
		rounded = T.radius_lg,
		bg = T.sunken,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		row("@", "@@ -12,6 +12,7 @@ fn render(cx: &mut Context)", T.tertiary, "$zeron.diff.hunk"),
		row(" ", "    let theme = cx.theme();", T.secondary, T.clear),
		row("-", "    let bg = Color(6, 6, 6, 255);", "$zeron.diff.delete", T.danger_wash),
		row("+", "    let bg = theme.background();", "$zeron.diff.add", T.success_wash),
		row(" ", "    column().bg(bg)", T.secondary, T.clear),
	}
end

local function grid(nodes: { Node }): Node
	return ui.row { flex_wrap = true, gap_x = "$zeron.space.14", gap_y = "$zeron.space.18", nodes }
end
local function map(entries: { Entry }, f: (Entry) -> Node): { Node }
	local out: { Node } = {}
	for i, e in entries do
		out[i] = f(e)
	end
	return out
end

return function(): Node
	local page = state.page_by("colour")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Surfaces",
			note = "From the window outward; each card shows the primary text's contrast on it.",
			grid(map(SURFACES, surface_card)),
		},
		specimen.section {
			title = "Text",
			note = "4.5:1 passes AA for body text, 3:1 for large text and icons.",
			grid { text_on("background"), text_on("surface.base"), text_on("surface.raised") },
		},
		specimen.section {
			title = "Accent and status",
			note = "Contrast as text on the background. Below: the muted variants for text on washes.",
			grid(map(ACCENTS, tile)),
			grid(map(MUTED, tile)),
		},
		specimen.section {
			title = "Labels on fills",
			note = "Every label the kit sets on a fill, in each state, translucent fills over the background: 4.5:1 at least, in every theme and accent (the suite checks).",
			labels.view(),
		},
		specimen.section {
			title = "Washes",
			note = "Translucent, so one token serves hover on glass, cards and menus.",
			grid(map(WASHES, wash)),
		},
		specimen.section {
			title = "Lines",
			grid(map(LINES, line)),
		},
		specimen.section {
			title = "Ink",
			note = "ink(a): the text colour at 4, 6, 8, 11, 16 and 22%.",
			inks(),
		},
		specimen.section {
			title = "Lanes",
			note = "The history graph's lane colours, a palette at 72% saturation.",
			lanes(),
		},
		specimen.section {
			title = "Diff",
			diff(),
		},
	}
end
