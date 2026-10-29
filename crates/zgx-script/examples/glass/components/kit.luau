-- Glass's design system: its pieces as ui.variants recipes over the
-- shell.* tokens (theme.luau), so a theme restyles every one of them.
local M = {}

-- An icon from icons/ (Solar, CC BY 4.0), tinted.
function M.icon(name: string, size: number?, color: Color?): Node
	return ui.svg {
		src = `icons/{name}.svg`,
		w = size or 16,
		h = size or 16,
		shrink = 0,
		tint = color or "$text.secondary",
	}
end

-- A square button around one icon: on the glass (`chrome`) or in the well.
M.icon_button = ui.variants {
	base = {
		items = "center",
		justify = "center",
		shrink = 0,
		rounded = "$radius.md",
		cursor = "pointer",
		bg = "#00000000",
		focus = { border = 0 },
		active = { bg = "$pressed" },
	},
	variants = {
		size = { sm = { w = 24, h = 24 }, md = { w = 28, h = 28 } },
		on = { [true] = { bg = "$shell.selected" }, [false] = { hover = { bg = "$hover" } } },
	},
	defaults = { size = "md", on = false },
}

-- A sidebar row: an item (a chat, a page, a session) or a section's title.
-- The chosen one is a lighter pane of glass with a hairline of its own.
M.row = ui.variants {
	base = {
		items = "center",
		w_full = true,
		shrink = 0,
		rounded = "$radius.lg",
		bg = "#00000000",
		focus = { border = 0 },
	},
	variants = {
		kind = {
			item = { h = 32, px = "$shell.xs", gap = "$space.2", cursor = "pointer", active = { bg = "$pressed" } },
			section = { h = 28, px = "$space.2", gap = "$shell.xs" },
		},
		selected = {
			[true] = {
				bg = "$shell.selected",
				border = 1,
				border_color = "$shell.selected_line",
			},
			[false] = { border = 1, border_color = "#00000000", hover = { bg = "$shell.hover" } },
		},
	},
	compound = { { kind = "section", hover = { bg = "#00000000" } } },
	defaults = { kind = "item", selected = false },
}

-- A pinned favourite: a tile in the row above the spaces (Dia's, Arc's).
M.pin = ui.variants {
	base = {
		h = 40,
		w_full = true,
		items = "center",
		justify = "center",
		rounded = "$radius.lg",
		bg = "$shell.tile",
		border = 1,
		border_color = "$shell.selected_line",
		cursor = "pointer",
		hover = { bg = "$shell.selected" },
		active = { bg = "$pressed" },
		focus = { border = 0 },
	},
}

-- The small tile an item's icon sits on.
M.tile = ui.variants {
	base = { w = 20, h = 20, items = "center", justify = "center", shrink = 0, rounded = "$radius.sm" },
	variants = {
		tone = { plain = { bg = "$shell.tile" }, clear = {} },
	},
	defaults = { tone = "plain" },
}

-- The content's well: inset from the window's edges, a dark hairline
-- outside and a light one inside (the inset shadow, under the border), a
-- soft lift. A focused well, beside another, keeps a brighter inner edge.
M.well = ui.variants {
	base = {
		grow = 1,
		basis = 0,
		min_w = 0,
		h_full = true,
		overflow = "hidden",
		rounded = "$shell.radius",
		bg = "$shell.well",
		border = 1,
		border_color = "$shell.edge",
		shadow = "$shell.shadow",
	},
	variants = {
		focused = {
			[true] = { inset_shadow = "$shell.inner" },
			[false] = { inset_shadow = "$shell.inner_dim" },
		},
	},
	defaults = { focused = true },
}

-- A field on the glass or in the well: the sidebar's search, the composer.
M.field = ui.variants {
	base = {
		w_full = true,
		items = "center",
		rounded = "$radius.lg",
		bg = "$shell.field",
		border = 1,
		border_color = "$shell.field_line",
	},
	variants = {
		kind = {
			search = { h = 32, px = "$shell.sm", gap = "$space.2", cursor = "text" },
			composer = {
				direction = "column",
				p = "$shell.sm",
				gap = "$space.2",
				rounded = "$radius.xl",
				items = "stretch",
			},
		},
	},
	defaults = { kind = "search" },
}

-- A key's chip in a hint (⌘K).
M.key = ui.variants {
	base = {
		h = 18,
		min_w = 18,
		px = "$space.1",
		items = "center",
		justify = "center",
		rounded = "$radius.sm",
		bg = "$shell.tile",
		text_size = "$font.size.xs",
		color = "$text.tertiary",
	},
}

return M
