-- Zeron's roles on zgui's tokens. The kit styles itself only from the
-- standard tokens and the app's own below, whose defaults are written in
-- standard tokens, so any theme styles it; zeron-dark.json and
-- zeron-light.json set every one to Zeron's resolved values (source.json
-- says where from), and `ui.theme.set("zgui-dark")` restyles the kit whole.
local ZERON = {
	-- Zeron's card and dialog surfaces (between the shell and overlays).
	card = "{surface.sunken}",
	dialog = "{surface.overlay}",
	-- The composer's and inputs' hairline (composer_surface_border).
	input = { border = "{border}" },
	-- solid / on_solid: the send button and other filled neutrals.
	solid = "{text.primary}",
	["solid.hover"] = "mix({text.primary}, {background}, 0.12)",
	["solid.pressed"] = "mix({text.primary}, {background}, 0.2)",
	on_solid = "{background}",
	-- Status colours muted toward the text, for text on dark washes.
	-- Plates: each status colour as a fill under a label (`strong`, with
	-- `hover` and `pressed`) and the label (`text`), 4.5:1 or more in every
	-- theme. The themes compute them (themes/generate.py: the colour moved
	-- away from its label, hue kept, just far enough); these defaults only
	-- stand for a theme without them.
	danger = {
		muted = "mix({danger}, {text.primary}, 0.28)",
		wash = "alpha({danger}, 0.14)",
		lit = "alpha({danger}, 0.22)",
		strong = "mix({danger}, #000000, 0.3)",
		hover = "mix({danger}, #000000, 0.36)",
		pressed = "mix({danger}, #000000, 0.42)",
		text = "#ffffff",
	},
	warning = {
		muted = "mix({warning}, {text.primary}, 0.25)",
		wash = "alpha({warning}, 0.14)",
		strong = "{warning}",
		hover = "mix({warning}, #ffffff, 0.08)",
		pressed = "mix({warning}, #ffffff, 0.16)",
		text = "#000000",
	},
	success = {
		muted = "mix({success}, {text.primary}, 0.25)",
		wash = "alpha({success}, 0.14)",
		strong = "{success}",
		hover = "mix({success}, #ffffff, 0.08)",
		pressed = "mix({success}, #ffffff, 0.16)",
		text = "#000000",
	},
	info = {
		wash = "alpha({info}, 0.14)",
		strong = "mix({info}, #000000, 0.3)",
		hover = "mix({info}, #000000, 0.36)",
		pressed = "mix({info}, #000000, 0.42)",
		text = "#ffffff",
	},
	accent = {
		wash = "alpha({accent}, 0.22)",
		-- The update strip under the pointer.
		lit = "alpha({accent}, 0.16)",
		selection = "alpha({accent}, 0.35)",
		-- The dictation plate's top: the accent toward white.
		light = "mix({accent}, #ffffff, 0.18)",
	},
	-- ink(a): the text colour at 4, 6, 8, 11, 16 and 22%, for washes and
	-- hairlines that take the colour of what is under the glass.
	ink = {
		["1"] = "alpha({text.primary}, 0.04)",
		["2"] = "alpha({text.primary}, 0.06)",
		["3"] = "alpha({text.primary}, 0.08)",
		["4"] = "alpha({text.primary}, 0.11)",
		["5"] = "alpha({text.primary}, 0.16)",
		["6"] = "alpha({text.primary}, 0.22)",
	},
	diff = {
		add = "{success}",
		delete = "{danger}",
		hunk = "alpha({accent}, 0.08)",
		add_wash = "alpha({success}, 0.055)",
		delete_wash = "alpha({danger}, 0.055)",
		-- The rail beside a changed line, a context line's dot and the
		-- code itself.
		add_rail = "alpha({success}, 0.55)",
		delete_rail = "alpha({danger}, 0.55)",
		dot = "alpha({text.tertiary}, 0.5)",
		code = "alpha({text.primary}, 0.92)",
	},
	cursor = "alpha({text.primary}, 0.4)",
	-- A list row's label at rest: the text colour at 80%, full under the
	-- pointer or chosen.
	row = { label = "alpha({text.primary}, 0.8)" },
	-- Zeron's unified titlebar (shell/titlebar.rs): 38 high, 4 down from
	-- the top; the window controls 88 in beside macOS's traffic lights,
	-- 12 elsewhere; 2 between controls, 8 between groups, 4 between
	-- anchors, 6 from the window's right edge.
	titlebar = {
		height = 38,
		top = 4,
		inset = 12,
		inset_mac = 88,
		control_gap = 2,
		group_gap = 8,
		anchor_gap = 4,
		edge = 6,
	},
	-- From the window's left edge past macOS's traffic lights, where a
	-- layout without the titlebar puts its controls.
	lights = 78,
	-- The same inside a column that pads 8.
	lights_inset = 70,
	-- The same, less a header's own 6.
	lights_header = 72,
	-- Pulls: a negative margin by which a control reaches past its box
	-- (a hit area wider than its glyph, a strip overlapping the pane).
	pull = { ["1"] = -1, ["2"] = -2, ["4"] = -4, ["16"] = -16, ["18"] = -18 },
	-- Zeron's sidebar lists: one 8 inset for every icon column; a row's
	-- second line starts under its title (the 13 glyph and its 8).
	list = {
		inset = 8,
		meta_indent = 21,
		-- The hover wash of a list's rows (kit/wash): a list scopes it to its
		-- own colour (the glass hover in the sidebar, the menu hover in a menu).
		wash = "{hover}",
	},
	-- A menu's item under the pointer: the theme's hover over the menu, as
	-- Zeron's (an imported theme's menu selection is not used).
	menu = { hover = "over({menu.bg}, {hover})" },
	-- The sidebar's session rows (shell.rs, spaces.rs): status tones held
	-- below full strength but Done's; a pull request's badge in its state's
	-- tone at 8% (16% under the pointer); a project's monogram (project_icon.rs),
	-- its letter in one of eight tones, toward the text so it reads in either
	-- appearance, on its tone at 8%; lit on its row's hover (and selection),
	-- its tone at 24% and its letter nearer the text.
	side = {
		status = {
			working = "alpha({text.secondary}, 0.9)",
			input = "alpha({accent}, 0.6)",
			failed = "alpha({danger}, 0.65)",
			done = "alpha({success}, 0.9)",
			idle = "alpha({text.primary}, 0.14)",
		},
		pr = {
			open = { fg = "alpha({success}, 0.85)", wash = "alpha({success}, 0.08)", lit = "alpha({success}, 0.16)" },
			merged = { fg = "alpha({accent}, 0.85)", wash = "alpha({accent}, 0.08)", lit = "alpha({accent}, 0.16)" },
			closed = { fg = "alpha({danger}, 0.85)", wash = "alpha({danger}, 0.08)", lit = "alpha({danger}, 0.16)" },
			draft = {
				fg = "alpha({text.secondary}, 0.85)",
				wash = "alpha({text.primary}, 0.06)",
				lit = "alpha({text.primary}, 0.12)",
			},
		},
		project = {
			["1"] = {
				fg = "mix(#64748b, {text.primary}, 0.3)",
				wash = "alpha(#64748b, 0.08)",
				lit = "alpha(#64748b, 0.24)",
				glow = "mix(#64748b, {text.primary}, 0.55)",
			},
			["2"] = {
				fg = "mix(#3b82f6, {text.primary}, 0.3)",
				wash = "alpha(#3b82f6, 0.08)",
				lit = "alpha(#3b82f6, 0.24)",
				glow = "mix(#3b82f6, {text.primary}, 0.55)",
			},
			["3"] = {
				fg = "mix(#8b5cf6, {text.primary}, 0.3)",
				wash = "alpha(#8b5cf6, 0.08)",
				lit = "alpha(#8b5cf6, 0.24)",
				glow = "mix(#8b5cf6, {text.primary}, 0.55)",
			},
			["4"] = {
				fg = "mix(#f43f5e, {text.primary}, 0.3)",
				wash = "alpha(#f43f5e, 0.08)",
				lit = "alpha(#f43f5e, 0.24)",
				glow = "mix(#f43f5e, {text.primary}, 0.55)",
			},
			["5"] = {
				fg = "mix(#f59e0b, {text.primary}, 0.3)",
				wash = "alpha(#f59e0b, 0.08)",
				lit = "alpha(#f59e0b, 0.24)",
				glow = "mix(#f59e0b, {text.primary}, 0.55)",
			},
			["6"] = {
				fg = "mix(#10b981, {text.primary}, 0.3)",
				wash = "alpha(#10b981, 0.08)",
				lit = "alpha(#10b981, 0.24)",
				glow = "mix(#10b981, {text.primary}, 0.55)",
			},
			["7"] = {
				fg = "mix(#14b8a6, {text.primary}, 0.3)",
				wash = "alpha(#14b8a6, 0.08)",
				lit = "alpha(#14b8a6, 0.24)",
				glow = "mix(#14b8a6, {text.primary}, 0.55)",
			},
			["8"] = {
				fg = "mix(#f97316, {text.primary}, 0.3)",
				wash = "alpha(#f97316, 0.08)",
				lit = "alpha(#f97316, 0.24)",
				glow = "mix(#f97316, {text.primary}, 0.55)",
			},
		},
	},
	-- Behind dialogs.
	scrim = "#00000099",
	-- Under the command palette: the window stays legible behind it.
	scrim_soft = "alpha(#000000, 0.16)",
	-- A dialog's scrim drawn inside a specimen.
	scrim_preview = "alpha(#000000, 0.35)",
	-- Appearance's cards: each mode's miniature in its own colours, the same
	-- in every theme.
	preview = {
		light = { surface = "#f4f4f5", bg = "#ffffff", ink = "#18181b", border = "#e4e4e7" },
		dark = { surface = "#121214", bg = "#060606", ink = "#e8e8ea", border = "#2a2a2e" },
	},
	-- macOS's traffic lights, where a page draws them.
	traffic = { close = "#ff5f57", minimize = "#febc2e", zoom = "#28c840" },
	code = { wash = "alpha({accent}, 0.22)" },
	-- A blockquote's wash.
	accent_faint = "alpha({accent}, 0.05)",
	-- Claude's brand colour, whatever the theme.
	claude = "#d97757",
	-- Frost: the floating cards' tint (popover::surface_bg), over a blur of
	-- `blur` and casting `float_shadow`. These defaults are dark frost's;
	-- kit/look sets each surface mode's and the light ones: light frost is
	-- the overlay at 45%, opaque the overlay itself with no blur and the
	-- large shadow (a shadow under frost would show through it).
	frost = "alpha({background}, 0.15)",
	blur = 16,
	float_shadow = "none",
	-- The double border (recipes `rim`): a hairline outside (`edge`) and a
	-- lit rim inside (`light`: an inset ring two points wide, its outer
	-- point under the border, and a top-weighted band; `light_dim` on a
	-- surface that has lost the focus; `side`, the inner line a flush
	-- panel shows beside its seam). Glass with a touch of bevel; kit/look
	-- tunes it per mode and turns it off.
	rim = {
		edge = "alpha(#000000, 0.32)",
		light = "0 0 0 2 alpha(#ffffff, 0.07), 0 2 0 0 alpha(#ffffff, 0.1)",
		light_dim = "0 0 0 2 alpha(#ffffff, 0.035), 0 2 0 0 alpha(#ffffff, 0.05)",
		side = "2 0 0 0 alpha(#ffffff, 0.04)",
	},
	-- panel_bg: the editor host, the files column and the right panel sit on
	-- the background at 40% over the window's glass; the chat sits on the
	-- glass itself.
	panel = "alpha({background}, 0.4)",
	-- The sidebar's tone (shell.rs sidebar_tone): a 5% wash over the window
	-- glass, its own surface between the glass of the chat and the panel.
	sidebar = "alpha({text.primary}, 0.05)",
	-- The glass layout's well (Rex's): the content inset into the window's
	-- glass, darker than it and translucent, edged with a dark hairline
	-- outside (`edge`) and a light one inside (`inner`, an inset ring two
	-- points wide whose outer point the border covers; `inner_dim` on a
	-- well that has lost the focus to the one beside it).
	well = {
		-- From the window's edges to a well, and between two wells.
		gap = 6,
		-- Frosted, the background at 40% over the window's glass, as
		-- Zeron's panels (panel_bg); opaque, the background (kit/look).
		bg = "alpha({background}, 0.4)",
		-- Its lines are the double border's.
		edge = "{zeron.rim.edge}",
		inner = "{zeron.rim.light}",
		inner_dim = "{zeron.rim.light_dim}",
		shadow = "0 8 24 0 alpha(#000000, 0.22)",
	},
	-- Wing's pane card (zterm): the sunken surface at 30%, its border while
	-- a pane is moved, the grip's frosted fill.
	pane = "alpha({surface.sunken}, 0.3)",
	["pane.moving"] = "alpha({text.primary}, 0.35)",
	grip = "alpha({surface.raised}, 0.25)",
	-- Wing's glass: under the active row or tab, and under the pointer.
	glass = {
		active = "alpha({text.primary}, 0.11)",
		hover = "{hover}",
		-- The account pill's hover (user-menu.tsx: white/[0.04] against the
		-- buttons' 0.05): the glass hover at 80%.
		soft = "alpha({zeron.glass.hover}, 0.8)",
		light = { top = "alpha({text.primary}, 0.09)", bottom = "alpha({text.primary}, 0.04)" },
	},
	-- The chat's drop zone's scrim (chat_dropzone.rs: the scrim at 40%).
	drop_scrim = "alpha(#000000, 0.4)",
	-- A chosen card's ring (card_selected_shadows): a hairline inside its
	-- edge, painted over its fill.
	selected_ring = "0 0 0 1 alpha({text.primary}, 0.09)",
	-- A notice's fill: the accent at 5%.
	-- The reasoning slider: the halo and band of light fast mode brings,
	-- the stops over and past the fill.
	effort = {
		halo = "alpha({accent}, 0.35)",
		band = "alpha(mix({accent}, #ffffff, 0.45), 0.55)",
		stop = { filled = "alpha(#ffffff, 0.4)", open = "alpha({text.secondary}, 0.28)" },
		-- The fill's top gloss, and the handle: its glow in fast mode, its
		-- rim and its shadow at rest and while dragged.
		gloss = "alpha(#ffffff, 0.08)",
		glow = "0 1 10 0 {zeron.effort.halo}",
		thumb = {
			border = "alpha(#000000, 0.12)",
			rest = "0 1 2 0 alpha(#000000, 0.22)",
			lifted = "0 2 8 0 alpha(#000000, 0.12)",
		},
	},
	notice = "alpha({warning}, 0.05)",
	chrome = "alpha({surface.base}, 0.26)",
	-- The history graph's lane colours (a palette at 72% saturation).
	lane = {
		["1"] = "#7c9ee6",
		["2"] = "#d99a5b",
		["3"] = "#5fbf8f",
		["4"] = "#c67ad6",
		["5"] = "#e07b7b",
		["6"] = "#6cc0c9",
	},
	-- The gradient spinner's row tints (Zeron's GSPIN_ROW_TINTS).
	loader = { ["1"] = "#b6d3ef", ["2"] = "#edb185", ["3"] = "#f888a0" },
	-- The switch (settings/widgets.rs toggle_switch): a near-white thumb in
	-- both states, the track the accent when on and an ink wash when off,
	-- a white rim on the accent.
	switch = {
		-- The on mark under Zeron's large switch: near white.
		mark = "#fffffff5",
		thumb = "mix(#ffffff, {background}, 0.05)",
		["thumb.border"] = "alpha(#000000, 0.1)",
		off = "alpha({text.primary}, 0.2)",
		rim = "alpha(#ffffff, 0.14)",
	},
	-- The focus ring on a solid button, and a checkbox's 2-point halo.
	focus = { on_solid = "alpha({background}, 0.5)", halo = "0 0 0 2 {focus.ring}" },
	-- The composer's send button with nothing to send: Zeron draws the solid
	-- at 35% as a group (its arrow stays the surface's colour), here as the
	-- colours that makes.
	send = { idle = "mix({text.primary}, {input.bg}, 0.65)", glyph = "{input.bg}" },
	-- Popover card, menu item and composer radii.
	-- Small and large controls around `control.height`.
	control = { sm = 26, lg = 38 },
	-- `tile`: a project monogram's letter (project_icon.rs).
	font = { size = { micro = 10, tile = 9 } },
	-- motion.rs specs, in ms.
	motion = {
		hover = 150,
		menu_in = 140,
		menu_out = 100,
		dialog_in = 180,
		collapse = 180,
		resize = 200,
		glyph = 280,
		resort = 260,
		fade_in = 500,
		tab_slide = 150,
		scroll_glide = 500,
		morph = 420,
		roll = 550,
	},
	-- The spacing scale, in points: every padding, margin and gap the kit
	-- and the app set is one of these (Zeron's metrics sit on a 1-point
	-- grid up to 14, then 16 to 96). A density could scale them here.
	-- `5_5` is 5.5.
	space = {
		["1"] = 1,
		["2"] = 2,
		["3"] = 3,
		["4"] = 4,
		["5"] = 5,
		["5_5"] = 5.5,
		["6"] = 6,
		["7"] = 7,
		["8"] = 8,
		["9"] = 9,
		["10"] = 10,
		["11"] = 11,
		["12"] = 12,
		["13"] = 13,
		["14"] = 14,
		["16"] = 16,
		["18"] = 18,
		["20"] = 20,
		["22"] = 22,
		["24"] = 24,
		["28"] = 28,
		["32"] = 32,
		["40"] = 40,
		["48"] = 48,
		["56"] = 56,
		["64"] = 64,
		["96"] = 96,
	},
	-- The corner radii, in points (`1_5`, `2_5`… are fractions). Components name theirs through their
	-- recipes; the standard `radius.*` scale stays for the rest.
	radius = {
		-- Named roles: the popover card, a menu item, the composer, a button.
		card = 12,
		item = 7,
		composer = 26,
		button = 8,
		["0"] = 0,
		["1"] = 1,
		["1_5"] = 1.5,
		["2"] = 2,
		["2_5"] = 2.5,
		["3"] = 3,
		["3_5"] = 3.5,
		["4"] = 4,
		["5"] = 5,
		["6"] = 6,
		["7"] = 7,
		["8"] = 8,
		["9"] = 9,
		["10"] = 10,
		["11"] = 11,
		["13"] = 13,
		["14"] = 14,
		["16"] = 16,
		["22"] = 22,
		["26"] = 26,
	},
}
ui.theme.tokens { zeron = ZERON }
ui.theme.load("zeron-light.json")
-- Zeron's other built-in themes, generated from comet's seeds (themes/).
for _, entry in require("@kit/theme_list") :: { { id: string } } do
	if entry.id ~= "zeron-dark" and entry.id ~= "zeron-light" then
		ui.theme.load(`themes/{entry.id}.json`)
	end
end
ui.theme.default(ui.theme.load("zeron-dark.json"))

-- A metric the kit keeps as a number (for arithmetic) named as its token,
-- so a style stays on the scale: `p = T.space(M.INSET)`. A value off the
-- scale is an error here, not a silent literal.
local function scale(group: string, table_: { [string]: number }, n: number): string
	local key = string.gsub(tostring(n), "%.", "_")
	assert(table_[key] ~= nil, `{n} is not on the zeron.{group} scale`)
	return `$zeron.{group}.{key}`
end

-- Token references, as the kit names them.
return {
	space = function(n: number): string
		return scale("space", ZERON.space :: any, n)
	end,
	radius = function(n: number): string
		return scale("radius", ZERON.radius :: any, n)
	end,
	-- Concentric corners ("radius in radius"): a box inset `inset` inside a
	-- corner of radius `outer`, and inside its `border`, rounds at what is
	-- left, so both curves share one centre and the gap between them stays
	-- even. `T.inset_radius(12, 4, 1)` is a menu row's 7 in the 12 card;
	-- `T.concentric` gives it as a token (on the scale, or an error).
	inset_radius = function(outer: number, inset: number, border: number?): number
		return math.max(outer - inset - (border or 0), 0)
	end,
	concentric = function(outer: number, inset: number, border: number?): string
		return scale("radius", ZERON.radius :: any, math.max(outer - inset - (border or 0), 0))
	end,
	-- A negative margin: `T.pull(18)` is -18.
	pull = function(n: number): string
		return scale("pull", ZERON.pull :: any, n)
	end,
	-- Surfaces.
	bg = "$background",
	sunken = "$surface.sunken",
	base = "$surface.base",
	raised = "$surface.raised",
	overlay = "$surface.overlay",
	card = "$zeron.card",
	dialog = "$zeron.dialog",
	glass = "$glass.tint",
	-- Text.
	text = "$text.primary",
	secondary = "$text.secondary",
	tertiary = "$text.tertiary",
	disabled = "$text.disabled",
	-- Lines.
	border = "$border",
	hairline = "$border.subtle",
	strong = "$border.strong",
	input_border = "$zeron.input.border",
	-- Accent and status.
	accent = "$accent",
	accent_hover = "$accent.hover",
	on_accent = "$accent.text",
	accent_wash = "$zeron.accent.wash",
	accent_lit = "$zeron.accent.lit",
	accent_faint = "$zeron.accent_faint",
	code_wash = "$zeron.code.wash",
	diff_add = "$zeron.diff.add",
	diff_del = "$zeron.diff.delete",
	diff_hunk = "$zeron.diff.hunk",
	diff_add_wash = "$zeron.diff.add_wash",
	diff_del_wash = "$zeron.diff.delete_wash",
	diff_add_rail = "$zeron.diff.add_rail",
	diff_del_rail = "$zeron.diff.delete_rail",
	diff_dot = "$zeron.diff.dot",
	diff_code = "$zeron.diff.code",
	danger = "$danger",
	danger_muted = "$zeron.danger.muted",
	danger_wash = "$zeron.danger.wash",
	danger_lit = "$zeron.danger.lit",
	danger_hover = "$zeron.danger.hover",
	danger_pressed = "$zeron.danger.pressed",
	on_danger = "$zeron.danger.text",
	danger_strong = "$zeron.danger.strong",
	warning_strong = "$zeron.warning.strong",
	on_warning = "$zeron.warning.text",
	success_strong = "$zeron.success.strong",
	on_success = "$zeron.success.text",
	info_strong = "$zeron.info.strong",
	on_info = "$zeron.info.text",
	warning = "$warning",
	warning_muted = "$zeron.warning.muted",
	warning_wash = "$zeron.warning.wash",
	success = "$success",
	success_muted = "$zeron.success.muted",
	success_wash = "$zeron.success.wash",
	info = "$info",
	info_wash = "$zeron.info.wash",
	solid = "$zeron.solid",
	solid_hover = "$zeron.solid.hover",
	solid_pressed = "$zeron.solid.pressed",
	on_solid = "$zeron.on_solid",
	claude = "$zeron.claude",
	frost = "$zeron.frost",
	frost_blur = "$zeron.blur",
	float_shadow = "$zeron.float_shadow",
	rim_edge = "$zeron.rim.edge",
	rim_light = "$zeron.rim.light",
	rim_light_dim = "$zeron.rim.light_dim",
	rim_side = "$zeron.rim.side",
	panel = "$zeron.panel",
	sidebar_tone = "$zeron.sidebar",
	well = "$zeron.well.bg",
	well_edge = "$zeron.well.edge",
	well_inner = "$zeron.well.inner",
	well_inner_dim = "$zeron.well.inner_dim",
	well_shadow = "$zeron.well.shadow",
	glass_active = "$zeron.glass.active",
	pane = "$zeron.pane",
	pane_moving = "$zeron.pane.moving",
	grip = "$zeron.grip",
	glass_hover = "$zeron.glass.hover",
	glass_soft = "$zeron.glass.soft",
	glass_light_top = "$zeron.glass.light.top",
	glass_light_bottom = "$zeron.glass.light.bottom",
	effort_halo = "$zeron.effort.halo",
	effort_band = "$zeron.effort.band",
	notice = "$zeron.notice",
	chrome = "$zeron.chrome",
	loader1 = "$zeron.loader.1",
	loader2 = "$zeron.loader.2",
	loader3 = "$zeron.loader.3",
	-- States.
	hover = "$hover",
	pressed = "$pressed",
	selected = "$selection.item",
	selected_ring = "$zeron.selected_ring",
	drop_scrim = "$zeron.drop_scrim",
	selection = "$selection",
	ring = "$focus.ring",
	ring_on_solid = "$zeron.focus.on_solid",
	scrim = "$zeron.scrim",
	scrim_soft = "$zeron.scrim_soft",
	checkbox_ring = "$zeron.focus.halo",
	switch_mark = "$zeron.switch.mark",
	row_label = "$zeron.row.label",
	ink1 = "$zeron.ink.1",
	ink2 = "$zeron.ink.2",
	ink3 = "$zeron.ink.3",
	ink4 = "$zeron.ink.4",
	ink5 = "$zeron.ink.5",
	ink6 = "$zeron.ink.6",
	-- Widgets.
	button = "$button.bg",
	button_hover = "$button.hover",
	button_pressed = "$button.pressed",
	input = "$input.bg",
	menu = "$menu.bg",
	menu_hover = "$zeron.menu.hover",
	thumb = "$scrollbar.thumb",
	thumb_active = "$scrollbar.thumb.active",
	-- Type.
	sans = "$font.sans",
	mono = "$font.mono",
	-- Metrics.
	radius_sm = "$radius.sm",
	radius_md = "$radius.md",
	radius_lg = "$radius.lg",
	radius_xl = "$radius.xl",
	radius_full = "$radius.full",
	radius_card = "$zeron.radius.card",
	radius_item = "$zeron.radius.item",
	radius_composer = "$zeron.radius.composer",
	radius_button = "$zeron.radius.button",
	control = "$control.height",
	control_sm = "$zeron.control.sm",
	control_lg = "$zeron.control.lg",
	space1 = "$space.1",
	space2 = "$space.2",
	space3 = "$space.3",
	space4 = "$space.4",
	space5 = "$space.5",
	space6 = "$space.6",
	space7 = "$space.7",
	space8 = "$space.8",
	shadow_sm = "$shadow.sm",
	switch_thumb = "$zeron.switch.thumb",
	switch_thumb_border = "$zeron.switch.thumb.border",
	switch_off = "$zeron.switch.off",
	switch_rim = "$zeron.switch.rim",
	shadow_md = "$shadow.md",
	shadow_lg = "$shadow.lg",
	clear = "#00000000",
}
