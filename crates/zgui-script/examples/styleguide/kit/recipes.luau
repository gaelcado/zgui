-- The kit's design system: each component's look as a ui.variants recipe
-- over the theme's tokens (theme.luau). A component takes its look from
-- here rather than values of its own, so the same thing looks the same in
-- the workbench and the app, and a theme restyles all of it. Hover, press,
-- focus and disabled looks are the recipes' interaction styles; a state the
-- component holds (selected, open) chooses an axis. Icons and labels inside
-- take the control's colour (`currentColor`), so a hover that changes it
-- changes them, with no handler.
local T = require("../theme")

local M = {}

-- The focus ring: 1.5 over the edge, taking no room.
local RING = { border = 1.5, border_over = true, border_color = T.ring }
local NO_RING = { border = 0 }

-- A button (settings/widgets.rs action_button), with a press state Zeron
-- lacks. Every step stays in the tone's family: a solid dims toward the
-- background, a wash deepens; only the ghost's label comes up to the text
-- colour under the pointer.
M.button = ui.variants {
	base = {
		shrink = 0,
		py = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_button,
		cursor = "pointer",
		focus = RING,
	},
	variants = {
		tone = {
			primary = {
				bg = T.solid,
				color = T.on_solid,
				hover = { bg = T.solid_hover },
				active = { bg = T.solid_pressed },
				focus = { border = 1.5, border_over = true, border_color = T.ring_on_solid },
			},
			secondary = { bg = T.ink2, color = T.text, hover = { bg = T.ink4 }, active = { bg = T.ink5 } },
			outlined = {
				bg = T.input,
				color = T.text,
				border = 1,
				border_color = T.border,
				hover = { bg = T.glass_hover, border_color = T.strong },
				active = { bg = T.ink4 },
			},
			ghost = {
				bg = T.clear,
				color = T.secondary,
				hover = { bg = T.glass_hover, color = T.text },
				active = { bg = T.ink4 },
			},
			-- The danger plate: deep enough for its white label in every theme.
			danger = {
				bg = T.danger_strong,
				color = T.on_danger,
				hover = { bg = T.danger_hover },
				active = { bg = T.danger_pressed },
			},
		},
		size = {
			sm = { h = 28, px = "$zeron.space.10", gap = "$zeron.space.6" },
			md = { h = T.control, px = "$zeron.space.12", gap = "$zeron.space.7" },
			lg = { h = 36, px = "$zeron.space.14", gap = "$zeron.space.8" },
		},
		-- A label-less button is square.
		square = { [true] = {}, [false] = {} },
		pill = { [true] = { rounded = T.radius_full }, [false] = {} },
		-- Window chrome and the like: no focus ring.
		ring = { [true] = {}, [false] = {} },
		-- A toggle that is on keeps its selection under the pointer (a hover
		-- wash lighter than the selection would read as the chosen one).
		on = { [true] = {}, [false] = {} },
		-- Disabled (not busy): dimmed.
		dim = { [true] = { opacity = 0.45 }, [false] = {} },
	},
	compound = {
		{ square = true, px = 0 },
		{ ring = false, focus = NO_RING },
		{ on = true, bg = T.selected, color = T.text, hover = { bg = T.selected, color = T.text } },
	},
	defaults = { tone = "secondary", size = "md", square = false, pill = false, ring = true, on = false, dim = false },
}

-- A square button around one icon: toolbars, row actions, window chrome.
-- Its icon takes its colour, so a ghost's muted glyph comes up to the text
-- colour under the pointer. The size is the caller's (16 to 32).
M.icon_button = ui.variants {
	base = {
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_md,
		cursor = "pointer",
		focus = RING,
		disabled = { opacity = 0.45 },
	},
	variants = {
		tone = {
			ghost = {
				bg = T.clear,
				color = T.secondary,
				hover = { bg = T.glass_hover, color = T.text },
				active = { bg = T.ink4 },
			},
			secondary = { bg = T.ink2, color = T.secondary, hover = { bg = T.ink4 }, active = { bg = T.ink5 } },
			primary = {
				bg = T.solid,
				color = T.on_solid,
				hover = { bg = T.solid_hover },
				active = { bg = T.solid_pressed },
				focus = { border = 1.5, border_over = true, border_color = T.ring_on_solid },
			},
		},
		on = { [true] = {}, [false] = {} },
		ring = { [true] = {}, [false] = {} },
	},
	compound = {
		{ on = true, bg = T.selected, color = T.text, hover = { bg = T.selected, color = T.text } },
		{ ring = false, focus = NO_RING },
	},
	defaults = { tone = "ghost", on = false, ring = true },
}

-- A chip: a small rounded label in a tone (a tag, a filter, an attachment;
-- `badge` is the smallest). The tone and the variant together choose its
-- colours, in the compound rules; a selected filter takes the tone's solid.
-- A dot or a remove button tightens the side it sits on by its own inset.
export type ChipLook = { fg: Color, bg: Color, border: Color, solid_bg: Color, solid_fg: Color }
local CHIP_TONES: { [string]: ChipLook } = {
	neutral = { fg = T.secondary, bg = T.ink3, border = T.border, solid_bg = T.solid, solid_fg = T.on_solid },
	accent = { fg = T.accent, bg = T.accent_wash, border = T.accent, solid_bg = T.accent, solid_fg = T.on_accent },
	danger = {
		fg = T.danger_muted,
		bg = T.danger_wash,
		border = T.danger,
		solid_bg = T.danger_strong,
		solid_fg = T.on_danger,
	},
	warning = {
		fg = T.warning_muted,
		bg = T.warning_wash,
		border = T.warning,
		solid_bg = T.warning_strong,
		solid_fg = T.on_warning,
	},
	success = {
		fg = T.success_muted,
		bg = T.success_wash,
		border = T.success,
		solid_bg = T.success_strong,
		solid_fg = T.on_success,
	},
	info = { fg = T.info, bg = T.info_wash, border = T.info, solid_bg = T.info_strong, solid_fg = T.on_info },
}
M.CHIP_TONES = CHIP_TONES
local chip_rules: { any } = {
	-- The trigger (a picker's): its own metrics, square-ish, a plain wash
	-- under the pointer.
	{
		variant = "trigger",
		h = 20,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		rounded = T.radius_md,
		hover = { bg = T.hover },
	},
	-- A dot tightens the left by a point; a remove button the right by three.
	{ size = "xs", dot = true, pl = "$zeron.space.5" },
	{ size = "sm", dot = true, pl = "$zeron.space.7" },
	{ size = "md", dot = true, pl = "$zeron.space.9" },
	{ size = "xs", remove = true, pr = "$zeron.space.3" },
	{ size = "sm", remove = true, pr = "$zeron.space.5" },
	{ size = "md", remove = true, pr = "$zeron.space.7" },
	{ variant = "trigger", remove = true, pr = "$zeron.space.5" },
}
for tone, look in CHIP_TONES do
	table.insert(chip_rules, { tone = tone, variant = "soft", bg = look.bg, color = look.fg })
	table.insert(
		chip_rules,
		{ tone = tone, variant = { "outline", "trigger" }, color = look.fg, border_color = look.border }
	)
	table.insert(chip_rules, { tone = tone, variant = "solid", bg = look.solid_bg, color = look.solid_fg })
	table.insert(chip_rules, { tone = tone, on = true, bg = look.solid_bg, color = look.solid_fg })
end
M.chip = ui.variants {
	base = {
		items = "center",
		shrink = 0,
		rounded = T.radius_full,
		disabled = { opacity = 0.45 },
	},
	variants = {
		size = {
			xs = { h = 18, px = "$zeron.space.6", gap = "$zeron.space.4" },
			sm = { h = 22, px = "$zeron.space.8", gap = "$zeron.space.5" },
			md = { h = 26, px = "$zeron.space.10", gap = "$zeron.space.6" },
		},
		tone = {
			neutral = {},
			accent = {},
			danger = {},
			warning = {},
			success = {},
			info = {},
		},
		variant = {
			soft = { border = 0 },
			outline = { bg = T.clear, border = 1 },
			solid = { border = 0 },
			trigger = { bg = T.clear, border = 0 },
		},
		on = { [true] = {}, [false] = {} },
		dot = { [true] = {}, [false] = {} },
		remove = { [true] = {}, [false] = {} },
		-- A filter or a trigger: it clicks, brightens under the pointer and
		-- rings with the focus.
		interactive = { [true] = { cursor = "pointer", focus = RING, hover = { brightness = 1.15 } }, [false] = {} },
		pill = { [true] = {}, [false] = { rounded = T.radius_md } },
	},
	compound = chip_rules,
	defaults = {
		size = "sm",
		tone = "neutral",
		variant = "soft",
		on = false,
		dot = false,
		remove = false,
		interactive = false,
		pill = true,
	},
}
-- A chip's remove button: a round wash under the pointer.
M.chip_remove = ui.variants {
	base = {
		p = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		bg = T.clear,
		hover = { bg = T.ink4 },
		focus = RING,
		cursor = "pointer",
	},
}

-- A row in a list or a sidebar: an icon, a label, a detail, what sits at
-- its end. Its label is muted at rest and comes up to the text colour under
-- the pointer or chosen (the label takes the row's colour). On a plain
-- surface the row paints its own hover wash and selection; in a list
-- or on the glass, a layer under it does (kit/wash, `glass`).
M.row = ui.variants {
	base = {
		relative = true,
		w_full = true,
		pl = "$zeron.space.8",
		pr = "$zeron.space.8",
		gap = "$zeron.space.8",
		items = "center",
		justify = "start",
		rounded = T.radius_button,
		cursor = "pointer",
		bg = T.clear,
		color = T.row_label,
		hover = { color = T.text },
		focus = NO_RING,
		disabled = { opacity = 0.45 },
	},
	variants = {
		size = { sm = {}, md = {} },
		lines = { one = { py = 0 }, two = { py = "$zeron.space.6" } },
		indent = {
			["0"] = {},
			["1"] = { pl = "$zeron.space.24" },
			["2"] = { pl = "$zeron.space.40" },
			["3"] = { pl = "$zeron.space.56" },
		},
		-- `plain`: the row's own wash; `layered`: a layer under it paints
		-- the hover and the selection, the row only its press.
		surface = {
			plain = { hover = { bg = T.hover }, active = { bg = T.ink5 } },
			layered = { active = { bg = T.ink3 } },
		},
		on = { [true] = { color = T.text }, [false] = {} },
	},
	compound = {
		{ size = "sm", lines = "one", h = 28 },
		{ size = "md", lines = "one", h = 32 },
		{ surface = "plain", on = true, bg = T.selected, hover = { bg = T.selected } },
	},
	defaults = { size = "md", lines = "one", indent = "0", surface = "plain", on = false },
}
-- A row's icon: muted, the text colour when its row is chosen.
M.row_icon = ui.variants {
	base = { color = T.secondary },
	variants = { on = { [true] = { color = T.text }, [false] = {} } },
	defaults = { on = false },
}

-- A text field's frame: Zeron's input surface around the engine's editor.
-- `sm` is the pane chrome's field, `md` the control, `lg` Zeron's dialog
-- field. Its border strengthens under the pointer and while the editor in
-- it has the focus, and turns to the danger colour on an error.
M.field = ui.variants {
	base = {
		border = 1,
		border_color = T.input_border,
		gap = "$zeron.space.8",
		cursor = "text",
		hover = { border_color = T.strong },
		disabled = { opacity = 0.45 },
	},
	variants = {
		size = {
			sm = { h = 24, px = "$zeron.space.8", rounded = T.radius_md, bg = T.ink1 },
			md = { h = T.control, px = "$zeron.space.10", rounded = T.radius_md, bg = T.input },
			lg = { h = 36, px = "$zeron.space.12", rounded = T.radius_button, bg = T.ink1 },
		},
		lines = { one = { items = "center" }, many = { items = "start" } },
		focused = { [true] = {}, [false] = {} },
		invalid = { [true] = { border_color = T.danger, hover = { border_color = T.danger } }, [false] = {} },
	},
	-- An error's colour outlasts the focus.
	compound = { { focused = true, invalid = false, border_color = T.strong } },
	defaults = { size = "md", lines = "one", focused = false, invalid = false },
}
-- The field's icon: tertiary, secondary while the field has the focus.
M.field_icon = ui.variants {
	base = { color = T.tertiary },
	variants = { focused = { [true] = { color = T.secondary }, [false] = {} } },
	defaults = { focused = false },
}
-- The hint under a field, or its error.
M.field_hint = ui.variants {
	base = { color = T.tertiary },
	variants = { invalid = { [true] = { color = T.danger }, [false] = {} } },
	defaults = { invalid = false },
}

-- Frost: Zeron's floating surface (menus, popovers, cards over the
-- transcript): one blur under a translucent tint, a hairline, the popover
-- radius and its concentric 4-point inset.
M.frost = ui.variants {
	base = {
		p = "$zeron.space.4",
		gap = "$zeron.space.2",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
	},
	-- A card stacked under another casts none (it would paint over the
	-- one above).
	variants = { lifted = { [true] = {}, [false] = { shadow = false } } },
	defaults = { lifted = true },
}

-- A menu's item: 30 high, the item radius, the menu's wash under the
-- pointer (or the list's wash under it), a press a stronger wash; a danger
-- item in the danger colour on its wash. Its label takes its colour.
M.menu_item = ui.variants {
	base = {
		w_full = true,
		h = 30,
		pr = "$zeron.space.8",
		gap = "$zeron.space.9",
		items = "center",
		justify = "start",
		rounded = T.radius_item,
		bg = T.clear,
		cursor = "pointer",
		disabled = { opacity = 0.45 },
	},
	variants = {
		tone = {
			plain = {
				color = T.text,
				hover = { bg = T.menu_hover },
				active = { bg = T.ink5 },
				focus = { bg = T.menu_hover, border = 0 },
			},
			danger = {
				color = T.danger,
				hover = { bg = T.danger_wash },
				active = { bg = T.danger_wash },
				focus = { bg = T.danger_wash, border = 0 },
			},
		},
		-- With a column of checks, the row starts 2 closer to the edge.
		check = { [true] = { pl = "$zeron.space.8" }, [false] = { pl = "$zeron.space.10" } },
		-- In a list the wash layer is the hover (kit/wash): none of its own.
		listed = { [true] = {}, [false] = {} },
	},
	compound = { { listed = true, hover = { bg = T.clear } } },
	defaults = { tone = "plain", check = false, listed = false },
}
-- Its leading icon: secondary, the danger colour on a danger item.
M.menu_icon = ui.variants {
	variants = { tone = { plain = { color = T.secondary }, danger = { color = T.danger } } },
	defaults = { tone = "plain" },
}
-- Its check: there when the item is checked.
M.menu_check = ui.variants {
	base = { color = T.text },
	variants = { on = { [true] = { opacity = 1 }, [false] = { opacity = 0 } } },
	defaults = { on = false },
}

-- The project actions pill (shell/actions_ui.rs): a frosted split pill,
-- 24 high at radius 7, its segments washing faintly under the pointer.
M.actions_pill = ui.variants {
	base = {
		h = 24,
		items = "stretch",
		rounded = "$zeron.radius.7",
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.input_border,
		shadow = T.shadow_sm,
		overflow = "hidden",
	},
}
M.actions_segment = ui.variants {
	base = {
		h_full = true,
		gap = "$zeron.space.5",
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		cursor = "pointer",
		bg = T.clear,
		hover = { bg = T.ink1 },
		focus = NO_RING,
		disabled = { opacity = 0.45 },
	},
	variants = { kind = { run = { px = "$zeron.space.8" }, chevron = { px = 0 } } },
	defaults = { kind = "run" },
}

-- A segmented control: options in a well; the chosen one's pill sits under
-- it (a layer), each washes under the pointer. An option's icon and
-- label take its colour: secondary, the text colour when chosen.
M.segmented = ui.variants {
	base = {
		p = "$zeron.space.2",
		gap = "$zeron.space.2",
		items = "center",
		relative = true,
		rounded = T.radius_lg,
		bg = T.ink2,
		border = 1,
		border_color = T.hairline,
		disabled = { opacity = 0.45 },
	},
	variants = { size = { sm = { h = 28 }, md = { h = 32 } } },
	defaults = { size = "md" },
}
M.segment = ui.variants {
	base = {
		relative = true,
		gap = "$zeron.space.6",
		items = "center",
		justify = "center",
		rounded = T.radius_md,
		bg = T.clear,
		color = T.secondary,
		focus = NO_RING,
		cursor = "pointer",
	},
	variants = {
		size = { sm = { h = 24 }, md = { h = 28 } },
		-- With a label it pads its sides; an icon alone is square.
		labelled = { [true] = {}, [false] = { px = 0 } },
		even = { [true] = { grow = 1, basis = 0 }, [false] = {} },
		on = { [true] = { color = T.text }, [false] = {} },
	},
	compound = {
		{ size = "sm", labelled = true, px = "$zeron.space.8" },
		{ size = "md", labelled = true, px = "$zeron.space.10" },
	},
	defaults = { size = "md", labelled = true, even = false, on = false },
}

-- Tabs: a strip of labels with an underline under the chosen one, or
-- pills; the chosen tab's indicator is a layer under it, a hover wash
-- washes under the pointer. A tab's icon and label take its colour: secondary,
-- the text colour when chosen.
M.tabs = ui.variants {
	base = { relative = true, items = "center" },
	variants = {
		variant = {
			underline = { border_sides = { 0, 0, 1, 0 }, border_color = T.hairline },
			pills = { gap = "$zeron.space.2" },
		},
	},
	defaults = { variant = "underline" },
}
M.tab = ui.variants {
	base = {
		relative = true,
		gap = "$zeron.space.6",
		items = "center",
		justify = "center",
		bg = T.clear,
		color = T.secondary,
		focus = NO_RING,
		cursor = "pointer",
	},
	variants = {
		variant = {
			underline = { px = "$zeron.space.4", mx = "$zeron.space.6", rounded = T.radius_sm },
			pills = { px = "$zeron.space.10", rounded = T.radius_item },
		},
		size = { sm = {}, md = {} },
		on = { [true] = { color = T.text }, [false] = {} },
	},
	compound = {
		{ variant = "underline", size = "sm", h = 32 },
		{ variant = "underline", size = "md", h = 36 },
		{ variant = "pills", size = "sm", h = 26 },
		{ variant = "pills", size = "md", h = 30 },
	},
	defaults = { variant = "underline", size = "md", on = false },
}
-- A closable tab's ×, reaching 4 past the tab's padding.
M.tab_close = ui.variants {
	base = {
		w = 18,
		h = 18,
		p = 0,
		mr = "$zeron.pull.4",
		items = "center",
		justify = "center",
		rounded = T.radius_sm,
		bg = T.clear,
		color = T.tertiary,
		hover = { bg = T.ink4 },
		focus = NO_RING,
		cursor = "pointer",
	},
}

-- A switch (settings/widgets.rs toggle_switch): the row is the hit area,
-- reaching 2 past its box; the track turns the accent when on.
M.switch_row = ui.variants {
	base = {
		gap = "$zeron.space.10",
		p = "$zeron.space.2",
		mx = "$zeron.pull.2",
		rounded = T.radius_full,
		bg = T.clear,
		hover = { bg = T.clear },
		active = { bg = T.clear },
		focus = RING,
		cursor = "pointer",
		disabled = { opacity = 0.45 },
	},
	variants = { lines = { one = { items = "center" }, two = { items = "start" } } },
	defaults = { lines = "one" },
}
M.switch_track = ui.variants {
	base = { rounded = T.radius_full, border = 1 },
	variants = {
		on = {
			[true] = { bg = T.accent, border_color = T.switch_rim },
			[false] = { bg = T.switch_off, border_color = T.border },
		},
	},
	defaults = { on = false },
}
M.switch_thumb = ui.variants {
	base = {
		rounded = T.radius_full,
		bg = T.switch_thumb,
		border = 1,
		border_color = T.switch_thumb_border,
		shadow = T.shadow_sm,
	},
}

-- A checkbox: the row is the hit area (reaching 2 past its box); the box
-- fills with the solid when checked, and takes the focus ring as a 2-point
-- halo, so it keeps its size.
M.checkbox_row = ui.variants {
	base = {
		gap = "$zeron.space.10",
		px = "$zeron.space.2",
		py = "$zeron.space.2",
		mx = "$zeron.pull.2",
		rounded = T.radius_md,
		bg = T.clear,
		hover = { bg = T.clear },
		focus = NO_RING,
		cursor = "pointer",
		disabled = { opacity = 0.45 },
	},
	variants = { lines = { one = { items = "center" }, two = { items = "start" } } },
	defaults = { lines = "one" },
}
M.checkbox_box = ui.variants {
	base = {
		w = 16,
		h = 16,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_sm,
		border_color = T.strong,
	},
	variants = {
		on = { [true] = { bg = T.solid, border = 0 }, [false] = { bg = T.input, border = 1 } },
		focused = { [true] = { shadow = T.checkbox_ring }, [false] = { shadow = false } },
		lines = { one = {}, two = { mt = "$zeron.space.2" } },
	},
	defaults = { on = false, focused = false, lines = "one" },
}

-- A tooltip's bubble (Zeron's): 26 high at the item radius, frosted, its
-- label at 13 and a shortcut's caps tighter to the right edge.
M.tooltip = ui.variants {
	base = {
		h = 26,
		pl = "$zeron.space.9",
		pr = "$zeron.space.9",
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.radius_item,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.shadow_md,
		color = T.text,
	},
	variants = { keys = { [true] = { pr = "$zeron.space.5" }, [false] = {} } },
	defaults = { keys = false },
}

-- A key cap, as tooltips, menus and hints show a shortcut; flat on a
-- surface already raised (a tooltip, a menu).
M.kbd = ui.variants {
	base = { items = "center", justify = "center", rounded = T.radius_sm, color = T.secondary },
	variants = {
		size = {
			sm = { h = 16, min_w = 16, px = "$zeron.space.3" },
			md = { h = 18, min_w = 18, px = "$zeron.space.4" },
		},
		flat = { [true] = { bg = T.ink3, border = 0 }, [false] = { bg = T.ink2, border = 1, border_color = T.border } },
	},
	defaults = { size = "md", flat = false },
}

-- A row of key hints under a list (the palette's, a picker's): 30 high
-- over a hairline.
M.hints = ui.variants {
	base = {
		w_full = true,
		h = 30,
		px = "$zeron.space.12",
		gap = "$zeron.space.14",
		items = "center",
		border_sides = { 1, 0, 0, 0 },
		border_color = T.hairline,
	},
}

-- A hairline between things, across or down; a strong one on the border.
M.divider = ui.variants {
	base = { shrink = 0 },
	variants = {
		axis = { across = { w_full = true, h = 1 }, down = { w = 1, h_full = true } },
		strong = { [true] = { bg = T.border }, [false] = { bg = T.hairline } },
	},
	defaults = { axis = "across", strong = false },
}

-- An avatar's face: initials or an icon on a wash, round (or squared, its
-- corner scaling with it).
M.avatar = ui.variants {
	base = { items = "center", justify = "center", rounded = T.radius_full, bg = T.ink3, color = T.secondary },
}
-- The ring a status dot sits in, cut from the surface under the avatar,
-- reaching a point past its corner.
M.avatar_ring = ui.variants {
	base = {
		mr = "$zeron.pull.1",
		mb = "$zeron.pull.1",
		rounded = T.radius_full,
		bg = T.bg,
		items = "center",
		justify = "center",
	},
}

-- An empty state's tile: the icon on a quiet well.
M.empty_tile = ui.variants {
	base = {
		w = 40,
		h = 40,
		mb = "$zeron.space.6",
		items = "center",
		justify = "center",
		rounded = T.radius_lg,
		bg = T.ink2,
		border = 1,
		border_color = T.hairline,
		color = T.secondary,
	},
}

-- The running pill: how many agents are busy; 16 high on the accent's wash.
M.running_pill = ui.variants {
	base = {
		h = 16,
		px = "$zeron.space.6",
		gap = "$zeron.space.4",
		items = "center",
		shrink = 0,
		rounded = T.radius_full,
		bg = T.accent_wash,
		color = T.text,
	},
}

-- A popover's panel: frosted at the card radius, 280 wide, 12 in.
M.popover = ui.variants {
	base = {
		w = 280,
		p = "$zeron.space.12",
		gap = "$zeron.space.8",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
	},
}

-- A dialog: Zeron's card over a scrim, 360 wide, 20 in, at the large radius,
-- frosted as popovers are (popover::dialog_card in a modal's frost).
M.dialog = ui.variants {
	base = {
		w = 360,
		p = "$zeron.space.20",
		gap = "$zeron.space.6",
		rounded = T.radius_xl,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
	},
}

-- A toast (toast.rs): a frosted card, 356 wide, 14 by 13 inside; its icon
-- in its tone, 10 from the message.
M.toast = ui.variants {
	base = {
		w = 356,
		px = "$zeron.space.14",
		py = "$zeron.space.13",
		gap = "$zeron.space.10",
		items = "center",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
	},
}
M.toast_icon = ui.variants {
	variants = {
		tone = {
			neutral = { color = T.secondary },
			success = { color = T.success },
			danger = { color = T.danger },
			warning = { color = T.warning },
			info = { color = T.info },
		},
	},
	defaults = { tone = "neutral" },
}

-- A notice: a warning or an error on the faint notice fill, edged in its
-- tone's wash; as a tile, tighter, its icon on the wash.
M.notice = ui.variants {
	base = {
		py = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "start",
		bg = T.notice,
		border = 1,
	},
	variants = {
		tone = {
			warning = { border_color = T.warning_wash, color = T.warning },
			danger = { border_color = T.danger_wash, color = T.danger },
		},
		tile = {
			[true] = { px = "$zeron.space.10", rounded = T.radius_lg },
			[false] = { px = "$zeron.space.12", rounded = T.radius_card },
		},
	},
	defaults = { tone = "warning", tile = false },
}
M.notice_tile = ui.variants {
	base = { w = 20, h = 20, shrink = 0, items = "center", justify = "center", rounded = T.radius_md },
	variants = { tone = { warning = { bg = T.warning_wash }, danger = { bg = T.danger_wash } } },
	defaults = { tone = "warning" },
}

-- Scroll to bottom: a frosted pill over the transcript's end.
M.jump = ui.variants {
	base = {
		h = 30,
		pl = "$zeron.space.11",
		pr = "$zeron.space.13",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_full,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		color = T.text,
		hover = { bg = T.menu_hover },
		focus = NO_RING,
		cursor = "pointer",
	},
}

-- A shortcut's key chip (settings): mono on a wash; recording, the accent
-- edges it and colours its label.
M.shortcut = ui.variants {
	base = {
		min_w = 96,
		h = 32,
		px = "$zeron.space.12",
		items = "center",
		justify = "center",
		rounded = T.radius_button,
		bg = T.ink2,
		border = 1,
		border_color = T.clear,
		color = T.text,
		hover = { bg = T.ink3 },
		focus = { border = 1, border_color = T.accent },
		cursor = "pointer",
	},
	variants = { recording = { [true] = { border_color = T.accent, color = T.accent }, [false] = {} } },
	defaults = { recording = false },
}
-- Its Reset: quiet text.
M.text_button = ui.variants {
	base = {
		min_h = 24,
		px = "$zeron.space.2",
		items = "center",
		bg = T.clear,
		color = T.secondary,
		hover = { bg = T.clear, color = T.text },
		focus = NO_RING,
		cursor = "pointer",
	},
}

-- The context usage chip: its ring and percentage, coloured by how full
-- the window is (muted, then the warning colour at 75%, the danger's at 90).
M.context_chip = ui.variants {
	base = {
		h = 24,
		px = "$zeron.space.6",
		gap = "$zeron.space.5",
		items = "center",
		rounded = T.radius_md,
		bg = T.clear,
		hover = { bg = T.ink2 },
		focus = NO_RING,
		cursor = "pointer",
	},
	variants = {
		level = {
			none = { color = T.tertiary },
			low = { color = T.secondary },
			high = { color = T.warning },
			full = { color = T.danger },
		},
	},
	defaults = { level = "none" },
}

-- A wash: a surface's fill at rest and under the pointer, for the rows and
-- controls that carry no recipe of their own (Zeron eases it over 150 ms;
-- zgui switches it).
M.wash = ui.variants {
	variants = {
		rest = {
			clear = { bg = T.clear },
			ink1 = { bg = T.ink1 },
			ink2 = { bg = T.ink2 },
			raised = { bg = T.raised },
		},
		hover = {
			none = {},
			ink1 = { hover = { bg = T.ink1 } },
			ink2 = { hover = { bg = T.ink2 } },
			ink3 = { hover = { bg = T.ink3 } },
			ink4 = { hover = { bg = T.ink4 } },
			hover = { hover = { bg = T.hover } },
			glass = { hover = { bg = T.glass_hover } },
		},
	},
	defaults = { rest = "clear", hover = "none" },
}

-- A browser tab chip: the chosen one filled and in the primary text, the
-- others secondary under a wash on hover; its icon dims off the selection.
M.browser_tab = ui.variants {
	base = { bg = T.clear, color = T.secondary },
	variants = {
		selected = { [true] = { bg = T.ink4, color = T.text }, [false] = {} },
		-- In a strip's list the wash layer is the hover (kit/wash).
		listed = { [true] = {}, [false] = { hover = { bg = T.ink3 } } },
	},
	defaults = { selected = false, listed = false },
}
M.browser_tab_icon = ui.variants {
	base = { opacity = 0.7 },
	variants = { selected = { [true] = { opacity = 1 }, [false] = {} } },
	defaults = { selected = false },
}

-- A document tab (Dia's strip): the chosen one in the canvas colour, joined
-- to the page under it; the others secondary, primary under the pointer.
M.tabbar_tab = ui.variants {
	base = { bg = T.clear, color = T.secondary },
	variants = {
		selected = { [true] = { bg = T.bg, color = T.text }, [false] = { hover = { color = T.text } } },
	},
	defaults = { selected = false },
}
-- Its close button: on the chosen tab, and on another under the pointer.
M.tabbar_close = ui.variants {
	base = { opacity = 0, group_hover = { opacity = 1 } },
	variants = { selected = { [true] = { opacity = 1 }, [false] = {} } },
	defaults = { selected = false },
}

-- A session in the sidebar: the chosen one on the active glass in the
-- primary text, the others at 80% (an archived one tertiary); their titles
-- brighten under the pointer (`group_hover`) as the list's wash comes to them.
M.side_row = ui.variants {
	base = { bg = T.clear, color = T.row_label },
	variants = {
		selected = { [true] = { bg = T.glass_active }, [false] = {} },
		archived = { [true] = {}, [false] = {} },
		-- Dragged away, it dims where it was.
		dragged = { [true] = { opacity = 0.4 }, [false] = {} },
	},
	compound = {
		{ selected = true, color = T.text },
		{ selected = false, archived = true, color = T.tertiary },
	},
	defaults = { selected = false, archived = false, dragged = false },
}
-- The sidebar's controls (the project filter, the account pill, the footer's
-- buttons): the glass wash and the primary text under the pointer, and
-- while what they open is up (`on`); a label rests at 80%, a glyph secondary.
M.side_control = ui.variants {
	base = { bg = T.clear, hover = { bg = T.glass_hover, color = T.text } },
	variants = {
		tone = { label = { color = T.row_label }, glyph = { color = T.secondary } },
		on = { [true] = { bg = T.glass_hover }, [false] = {} },
	},
	compound = { { on = true, color = T.text } },
	defaults = { tone = "label", on = false },
}

-- A project's monogram tile: its tone's wash and letter, lit (24%, the
-- letter nearer the text) under its row's pointer and on the chosen row.
M.project_tile = ui.variants {
	variants = {
		tone = {
			["1"] = {
				bg = "$zeron.side.project.1.wash",
				color = "$zeron.side.project.1.fg",
				group_hover = { bg = "$zeron.side.project.1.lit", color = "$zeron.side.project.1.glow" },
			},
			["2"] = {
				bg = "$zeron.side.project.2.wash",
				color = "$zeron.side.project.2.fg",
				group_hover = { bg = "$zeron.side.project.2.lit", color = "$zeron.side.project.2.glow" },
			},
			["3"] = {
				bg = "$zeron.side.project.3.wash",
				color = "$zeron.side.project.3.fg",
				group_hover = { bg = "$zeron.side.project.3.lit", color = "$zeron.side.project.3.glow" },
			},
			["4"] = {
				bg = "$zeron.side.project.4.wash",
				color = "$zeron.side.project.4.fg",
				group_hover = { bg = "$zeron.side.project.4.lit", color = "$zeron.side.project.4.glow" },
			},
			["5"] = {
				bg = "$zeron.side.project.5.wash",
				color = "$zeron.side.project.5.fg",
				group_hover = { bg = "$zeron.side.project.5.lit", color = "$zeron.side.project.5.glow" },
			},
			["6"] = {
				bg = "$zeron.side.project.6.wash",
				color = "$zeron.side.project.6.fg",
				group_hover = { bg = "$zeron.side.project.6.lit", color = "$zeron.side.project.6.glow" },
			},
			["7"] = {
				bg = "$zeron.side.project.7.wash",
				color = "$zeron.side.project.7.fg",
				group_hover = { bg = "$zeron.side.project.7.lit", color = "$zeron.side.project.7.glow" },
			},
			["8"] = {
				bg = "$zeron.side.project.8.wash",
				color = "$zeron.side.project.8.fg",
				group_hover = { bg = "$zeron.side.project.8.lit", color = "$zeron.side.project.8.glow" },
			},
		},
		lit = { [true] = {}, [false] = {} },
	},
	compound = {
		{ tone = "1", lit = true, bg = "$zeron.side.project.1.lit", color = "$zeron.side.project.1.glow" },
		{ tone = "2", lit = true, bg = "$zeron.side.project.2.lit", color = "$zeron.side.project.2.glow" },
		{ tone = "3", lit = true, bg = "$zeron.side.project.3.lit", color = "$zeron.side.project.3.glow" },
		{ tone = "4", lit = true, bg = "$zeron.side.project.4.lit", color = "$zeron.side.project.4.glow" },
		{ tone = "5", lit = true, bg = "$zeron.side.project.5.lit", color = "$zeron.side.project.5.glow" },
		{ tone = "6", lit = true, bg = "$zeron.side.project.6.lit", color = "$zeron.side.project.6.glow" },
		{ tone = "7", lit = true, bg = "$zeron.side.project.7.lit", color = "$zeron.side.project.7.glow" },
		{ tone = "8", lit = true, bg = "$zeron.side.project.8.lit", color = "$zeron.side.project.8.glow" },
	},
	defaults = { tone = "1", lit = false },
}

-- A sidebar row's corner while ⌘ alone is held (shell.rs jump hints): the
-- time (or the subagents) and the hover's Archive give way to the hint.
-- The row's corner, Archive over it and the jump key over both: one slot,
-- the three swapped by opacity (the pointer or ⌘ changes no layout).
M.jump_corner = ui.variants {
	base = { group_hover = { opacity = 0 } },
	variants = { hint = { [true] = { opacity = 0 }, [false] = {} } },
	defaults = { hint = false },
}
M.jump_archive = ui.variants {
	base = { opacity = 0, group_hover = { opacity = 1 } },
	variants = { hint = { [true] = { group_hover = { opacity = 0 } }, [false] = {} } },
	defaults = { hint = false },
}
M.jump_hint = ui.variants {
	base = { opacity = 0 },
	variants = { hint = { [true] = { opacity = 1 }, [false] = {} } },
	defaults = { hint = false },
}

-- A searchable picker's row (popover.rs picker_row): the chosen one on
-- the selected wash with its hairline ring, no check; the keyboard's row
-- and the pointer's on ink at 4%.
M.picker_choice = ui.variants {
	base = { bg = T.clear, hover = { bg = T.ink1 } },
	variants = {
		selected = {
			[true] = { bg = T.selected, inset_shadow = T.selected_ring, hover = { bg = T.selected } },
			[false] = {},
		},
		keyed = { [true] = {}, [false] = {} },
	},
	compound = { { selected = false, keyed = true, bg = T.ink1 } },
	defaults = { selected = false, keyed = false },
}

-- The account pill: the side control's, but its hover wash at 80%
-- (user-menu.tsx), the full wash while its menu is up.
M.side_pill = ui.variants {
	base = { bg = T.clear, color = T.row_label, hover = { bg = T.glass_soft, color = T.text } },
	variants = {
		on = { [true] = { bg = T.glass_hover, color = T.text, hover = { bg = T.glass_hover } }, [false] = {} },
	},
	defaults = { on = false },
}

-- The update strip: the accent wash (danger's when it failed), lit under
-- the pointer while it has something to do.
M.update_strip = ui.variants {
	base = { bg = T.accent_wash, cursor = "default" },
	variants = {
		failed = { [true] = { bg = T.danger_wash }, [false] = {} },
		actionable = { [true] = { cursor = "pointer" }, [false] = {} },
	},
	compound = {
		{ failed = false, actionable = true, hover = { bg = T.accent_lit } },
		{ failed = true, actionable = true, hover = { bg = T.danger_lit } },
	},
	defaults = { failed = false, actionable = false },
}

-- A space in the topbar: the chosen one on the active glass with a
-- hairline; the strip's wash is the hover.
M.space_tab = ui.variants {
	base = { bg = T.clear, border = 1, border_color = T.clear },
	variants = { selected = { [true] = { bg = T.glass_active, border_color = T.hairline }, [false] = {} } },
	defaults = { selected = false },
}

-- The compact picker's header controls (the model title, the fast bolt):
-- secondary, primary under a wash on hover; a bolt that is on takes the
-- accent.
M.picker_control = ui.variants {
	base = { bg = T.clear, color = T.secondary, hover = { bg = T.ink1, color = T.text } },
	variants = { on = { [true] = { color = T.accent, hover = { color = T.accent } }, [false] = {} } },
	defaults = { on = false },
}

-- Pane chrome's 24-square icon control: secondary, primary when chosen,
-- under a wash on hover; dimmed while disabled.
M.chrome_control = ui.variants {
	base = { bg = T.clear, color = T.secondary, hover = { bg = T.ink4 } },
	variants = {
		selected = { [true] = { color = T.text }, [false] = {} },
		dim = { [true] = { opacity = 0.45 }, [false] = {} },
	},
	defaults = { selected = false, dim = false },
}
-- Its 24-high tab: a 10% wash when chosen, 6% under the pointer.
M.chrome_tab = ui.variants {
	base = { bg = T.clear, color = T.secondary, hover = { bg = T.ink2 } },
	variants = { selected = { [true] = { bg = T.ink4, color = T.text }, [false] = {} } },
	defaults = { selected = false },
}

-- Appearance's mode cards: the chosen one's frame and caption in the
-- accent, its caption medium.
M.mode_card = ui.variants {
	base = { color = T.secondary },
	variants = { selected = { [true] = { color = T.accent }, [false] = {} } },
	defaults = { selected = false },
}
M.mode_frame = ui.variants {
	base = { border_color = T.border },
	variants = { selected = { [true] = { border_color = T.accent }, [false] = {} } },
	defaults = { selected = false },
}
M.mode_caption = ui.variants {
	base = { weight = "$font.weight.regular" },
	variants = { selected = { [true] = { weight = "$font.weight.medium" }, [false] = {} } },
	defaults = { selected = false },
}
-- The accent swatches: a 2-point accent bar under the chosen cell, its well
-- rimmed strong.
M.swatch_cell = ui.variants {
	base = { border_color = T.clear },
	variants = { selected = { [true] = { border_color = T.accent }, [false] = {} } },
	defaults = { selected = false },
}
M.swatch_well = ui.variants {
	base = { border_color = T.border },
	variants = { selected = { [true] = { border_color = T.strong }, [false] = {} } },
	defaults = { selected = false },
}

-- The composer's send button (composer.rs send_circle): a 28 circle in the
-- text colour, its glyph in the background's; inert and faded to 35% (as
-- a group: the glyph keeps the surface's colour) while there is nothing to
-- send, 85% under the pointer otherwise.
M.send_button = ui.variants {
	base = { bg = T.text, color = T.bg, cursor = "pointer", hover = { opacity = 0.85 } },
	variants = {
		idle = {
			[true] = {
				bg = "$zeron.send.idle",
				color = "$zeron.send.glyph",
				cursor = "default",
				hover = { opacity = 1 },
			},
			[false] = {},
		},
	},
	defaults = { idle = false },
}

-- A question's answer card (the dock above the composer): ink 1, the
-- chosen one deeper with a rim; its list's wash is the hover.
M.choice_card = ui.variants {
	base = { bg = T.ink1, border_color = T.clear },
	variants = { selected = { [true] = { bg = T.ink3, border_color = T.ink5 }, [false] = {} } },
	defaults = { selected = false },
}
-- A chip chosen in a list (a scope filter): a 10% wash when chosen;
-- the list's wash is the hover.
M.listed_pick = ui.variants {
	base = { bg = T.clear, color = T.secondary },
	variants = { selected = { [true] = { bg = T.ink4, color = T.text }, [false] = {} } },
	defaults = { selected = false },
}

-- A completion row (popover.rs menu_row): the keyboard's row lit as the
-- pointer's wash lights the others (the list's wash), its text at full
-- strength; the rest at 90%.
M.completion_row = ui.variants {
	base = { bg = T.clear, color = T.text, opacity = 0.9 },
	variants = { selected = { [true] = { bg = T.menu_hover, opacity = 1 }, [false] = {} } },
	defaults = { selected = false },
}

-- The compact picker's model row: the chosen model selected, the
-- keyboard's row washed as the pointer's wash does; its star shows on
-- a favourite, on the keyboard's row and under the pointer.
M.picker_row = ui.variants {
	base = { bg = T.clear },
	variants = {
		selected = { [true] = {}, [false] = {} },
		keyed = { [true] = {}, [false] = {} },
	},
	compound = {
		{ selected = true, bg = T.selected },
		{ selected = false, keyed = true, bg = T.ink1 },
	},
	defaults = { selected = false, keyed = false },
}
M.picker_star = ui.variants {
	base = { opacity = 0, group_hover = { opacity = 1 } },
	variants = { shown = { [true] = { opacity = 1 }, [false] = {} } },
	defaults = { shown = false },
}
-- Its provider strip: the group in view washed and at full strength.
M.picker_group = ui.variants {
	base = { bg = T.clear, opacity = 0.7 },
	variants = { viewed = { [true] = { bg = T.ink3, opacity = 1 }, [false] = {} } },
	defaults = { viewed = false },
}

-- A file tree's row: secondary, primary when chosen; under it the
-- selection fill, deeper while the tree has the focus.
M.tree_row = ui.variants {
	base = { bg = T.clear, color = T.secondary },
	variants = { selected = { [true] = { color = T.text }, [false] = {} } },
	defaults = { selected = false },
}
M.tree_selection = ui.variants {
	base = { bg = T.ink3, opacity = 0 },
	variants = {
		selected = { [true] = { opacity = 1 }, [false] = {} },
		focused = { [true] = { bg = T.ink4 }, [false] = {} },
	},
	defaults = { selected = false, focused = true },
}
-- The transcript's turn ticks: the current one long and in the text colour.
M.turn_tick = ui.variants {
	base = { w = 12, bg = T.ink5 },
	variants = { active = { [true] = { w = 20, bg = T.text, opacity = 0.8 }, [false] = {} } },
	defaults = { active = false },
}

-- A glyph faded while what it does is unavailable (back with no history).
M.faded = ui.variants {
	variants = { faded = { [true] = { opacity = 0.35 }, [false] = {} } },
	defaults = { faded = false },
}
-- A header button's wash: 11% under the pointer, 9% while what it toggles
-- is on.
M.toggle_wash = ui.variants {
	base = { bg = T.clear, hover = { bg = T.ink4 } },
	variants = { on = { [true] = { bg = T.ink3 }, [false] = {} } },
	defaults = { on = false },
}
-- The tab strip's tab (a terminal's): its label primary when chosen, its
-- tile's glyph dimmer when not.
M.strip_tab = ui.variants {
	base = { color = T.secondary },
	variants = { selected = { [true] = { color = T.text }, [false] = {} } },
	defaults = { selected = false },
}
M.tile_icon = ui.variants {
	base = { color = T.secondary },
	variants = { dim = { [true] = { color = T.tertiary }, [false] = {} } },
	defaults = { dim = false },
}

-- A query field's text: the placeholder tertiary.
M.query_text = ui.variants {
	base = { color = T.text },
	variants = { empty = { [true] = { color = T.tertiary }, [false] = {} } },
	defaults = { empty = false },
}

-- Zeron's chosen row (sidebar, settings, palette): the active glass.
M.active_glass = ui.variants {
	base = { bg = T.clear },
	variants = { selected = { [true] = { bg = T.glass_active }, [false] = {} } },
	defaults = { selected = false },
}
-- ⌘K's scope tabs: a wash and the primary text when chosen.
M.palette_tab = ui.variants {
	base = { bg = T.clear, color = T.secondary, hover = { bg = T.ink2 } },
	variants = { selected = { [true] = { bg = T.ink3, color = T.text }, [false] = {} } },
	defaults = { selected = false },
}
-- A side panel's fill (panel_bg), the double border's inner line beside
-- its seam; none in a well, over the window's glass.
M.panel_fill = ui.variants {
	base = { bg = T.panel, inset_shadow = T.rim_side },
	variants = { glass = { [true] = { bg = T.clear, inset_shadow = false }, [false] = {} } },
	defaults = { glass = false },
}
-- The double border on a surface: a hairline outside and a lit rim inside,
-- top-weighted, dimmer out of focus (theme `rim`, tuned and switched off by
-- kit/look). Wells and panes wear the same through their own recipes.
M.rim = ui.variants {
	base = { border = 1, border_color = T.rim_edge, inset_shadow = T.rim_light },
	variants = { focused = { [true] = {}, [false] = { inset_shadow = T.rim_light_dim } } },
	defaults = { focused = true },
}
-- A choice card's rim (settings' option tiles): the text colour when chosen.
M.picked_rim = ui.variants {
	base = { border_color = T.border },
	variants = { selected = { [true] = { border_color = T.text }, [false] = {} } },
	defaults = { selected = false },
}
-- The effort slider's handle: its shadow lifts while dragged.
M.effort_thumb = ui.variants {
	base = { shadow = "$zeron.effort.thumb.rest" },
	variants = { lifted = { [true] = { shadow = "$zeron.effort.thumb.lifted" }, [false] = {} } },
	defaults = { lifted = false },
}
-- Dictation's clock: secondary while it listens.
M.dictation_clock = ui.variants {
	base = { color = T.tertiary },
	variants = { listening = { [true] = { color = T.secondary }, [false] = {} } },
	defaults = { listening = false },
}
-- An agent's status line: the warning colour while it waits on you.
M.agent_status = ui.variants {
	base = { color = T.tertiary },
	variants = { blocked = { [true] = { color = T.warning }, [false] = {} } },
	defaults = { blocked = false },
}
-- A commit's short hash: the accent on the chosen commit.
M.sha = ui.variants {
	base = { color = T.secondary },
	variants = { selected = { [true] = { color = T.accent }, [false] = {} } },
	defaults = { selected = false },
}

-- An account's avatar ring: the accent while it is in use, its initial
-- primary then.
M.account_ring = ui.variants {
	base = {
		rounded = T.radius_full,
		items = "center",
		justify = "center",
		border_color = T.clear,
		color = T.secondary,
	},
	variants = { active = { [true] = { border_color = T.accent, color = T.text }, [false] = {} } },
	defaults = { active = false },
}

-- A well's look: translucent and darker than the glass, a dark hairline
-- outside and a light one inside; a well that has lost the focus to the
-- one beside it dims its inner line.
M.well = ui.variants {
	base = {
		w_full = true,
		h_full = true,
		direction = "column",
		items = "stretch",
		overflow = "hidden",
		rounded = T.radius_card,
		bg = T.well,
		border = 1,
		border_color = T.well_edge,
		shadow = T.well_shadow,
	},
	variants = {
		focused = { [true] = { inset_shadow = T.well_inner }, [false] = { inset_shadow = T.well_inner_dim } },
	},
	defaults = { focused = true },
}

-- A message's badge (what a reply quotes): 24 high on ink 2, its label
-- secondary.
M.message_badge = ui.variants {
	base = {
		h = 24,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_button,
		bg = T.ink2,
	},
}
-- A quoted passage: on ink 1 at radius 6, a 2-point rail in the solid at
-- 35% down its left.
M.quote = ui.variants {
	base = { p = "$zeron.space.8", gap = "$zeron.space.8", rounded = "$zeron.radius.6", bg = T.ink1 },
}
M.quote_rail = ui.variants {
	base = { w = 2, rounded = "$zeron.radius.1", bg = T.solid, opacity = 0.35, shrink = 0, self = "stretch" },
}
-- A small mono tag on ink 3 (a quote's kind, a count).
M.tag = ui.variants {
	base = { px = "$zeron.space.4", rounded = "$zeron.radius.3", bg = T.ink3, items = "center" },
}

-- The frosted pill of equal segments (PR detail's Summary / Code /
-- Activity): the bar on frost with a rim and a deep shadow; its segments
-- secondary, primary when chosen (the sliding glass is the selection).
M.floating_tabs = ui.variants {
	base = {
		items = "stretch",
		rounded = T.radius_full,
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.input_border,
		shadow = T.shadow_lg,
	},
}
M.floating_tab = ui.variants {
	base = {
		rounded = T.radius_full,
		bg = T.clear,
		color = T.secondary,
		hover = { bg = T.clear },
		focus = { border = 0 },
		cursor = "pointer",
	},
	variants = { selected = { [true] = { color = T.text }, [false] = {} } },
	defaults = { selected = false },
}

-- Attachments: the composer's 56 tile (a hairline at radius 8, the fill
-- inset at 7, its remove button a white disc at its corner); the inline
-- chip at radius 5 on ink 9% with its icon well at 4; the transcript's
-- thumbnail, deeper while it loads and rimmed on an error. Inner corners
-- are concentric (`T.concentric`): the fill inside the tile's hairline,
-- the well 1 in from the chip's edge.
M.attachment = ui.variants {
	base = { rounded = T.radius(8), border = 1, border_color = T.hairline },
}
M.attachment_fill = ui.variants {
	base = { rounded = T.concentric(8, 0, 1), bg = T.ink1 },
}
M.attachment_remove = ui.variants {
	base = {
		p = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.9",
		bg = T.bg,
		shadow = T.shadow_sm,
		focus = { border = 0 },
		cursor = "pointer",
	},
}
M.attachment_chip = ui.variants {
	base = { items = "center", rounded = "$zeron.radius.5", bg = T.ink3 },
}
M.attachment_well = ui.variants {
	base = { items = "center", justify = "center", rounded = T.concentric(5, 1), bg = T.ink4 },
}
M.attachment_thumb = ui.variants {
	base = {
		rounded = "$zeron.radius.8",
		border = 1,
		border_color = T.ink4,
		bg = T.ink1,
		items = "center",
		justify = "center",
		overflow = "hidden",
	},
	variants = {
		state = {
			loaded = {},
			loading = { bg = T.ink2 },
			error = { border_color = T.ink5 },
		},
	},
	defaults = { state = "loaded" },
}

-- A collapsible's header: no button, so no wash under the pointer; its
-- label (and the chevron, in `currentColor`) brightens instead.
M.disclosure = ui.variants {
	base = {
		bg = T.clear,
		color = T.tertiary,
		cursor = "pointer",
		hover = { bg = T.clear, color = T.secondary },
		focus = { border = 0 },
	},
	variants = { tone = { quiet = {}, plain = { color = T.secondary, hover = { color = T.text } } } },
	defaults = { tone = "quiet" },
}

-- A list row's hover wash (kit/wash): the list's colour while the pointer
-- is over the row, none on the selected row.
M.list_wash = ui.variants {
	base = { bg = T.clear },
	variants = {
		selected = { [true] = {}, [false] = { group_hover = { bg = "$zeron.list.wash" } } },
	},
	defaults = { selected = false },
}

return M
