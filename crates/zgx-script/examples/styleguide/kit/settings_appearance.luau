-- Appearance's rows past the theme (settings/appearance.rs, v0.2.129): the
-- font pickers (a 220 pill opening a 220 card: "Search fonts" over the
-- catalog, prefixes before inner matches, a missing font at 45% and
-- skipped), the size beside each; Conversation width (560 to 1200 by 16,
-- 736 by default; its value, Reset and the ends under the pointer); Motion
-- (Reduce motion, Pause animations in background, Smooth scrolling); Match
-- wallpaper colors; and Adjust background (drag the artwork, zoom 100% to
-- 400%, Apply). The theme library is `kit/theme_library`.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local button = require("./button")
local select = require("./select")
local settings = require("./settings")
local frost = require("./frost")
local popover = require("./popover")
local recipes = require("./recipes")
local dialog = require("./dialog")
local look_mod = require("./look")

local M = {}

export type Font = { name: string, mono: boolean?, missing: boolean? }
-- The catalog: the bundled fonts first, then the installed families (a
-- sample until the host lists the system's).
M.FONTS = {
	{ name = "Geist" },
	{ name = "Geist Mono", mono = true },
	{ name = "System UI" },
	{ name = "Avenir Next" },
	{ name = "Berkeley Mono", mono = true, missing = true },
	{ name = "Courier New", mono = true },
	{ name = "Fira Code", mono = true },
	{ name = "Georgia" },
	{ name = "Helvetica Neue" },
	{ name = "IBM Plex Mono", mono = true },
	{ name = "IBM Plex Sans" },
	{ name = "Inter" },
	{ name = "Iosevka", mono = true },
	{ name = "JetBrains Mono", mono = true },
	{ name = "Menlo", mono = true },
	{ name = "SF Mono", mono = true },
	{ name = "SF Pro" },
} :: { Font }

-- What `query` finds: names starting with it, then names holding it, each
-- in the catalog's order, regardless of case.
function M.matching(fonts: { Font }, query: string): { Font }
	local q = string.lower(query)
	if q == "" then
		return fonts
	end
	local starts, inner = {}, {}
	for _, f in fonts do
		local at = string.find(string.lower(f.name), q, 1, true)
		if at == 1 then
			table.insert(starts, f)
		elseif at then
			table.insert(inner, f)
		end
	end
	for _, f in inner do
		table.insert(starts, f)
	end
	return starts
end

M.PICKER_W = 220
M.ROW = 30
M.LIST_MAX = 280

export type FontPickerProps = {
	id: string,
	-- The row's title, its accessible name's start ("Interface font: Geist").
	label: string,
	value: State<string>,
	-- Fixed-width families only (the terminal's).
	mono: boolean?,
}
M.font_picker = ui.component(function(props: FontPickerProps): Node
	local open = ui.use_state(false)
	local fonts: { Font } = {}
	for _, f in M.FONTS do
		if not props.mono or f.mono then
			table.insert(fonts, f)
		end
	end
	-- Built as it opens: the search empty and focused, the list at its top.
	local function content(): Node
		local query = ui.use_state("")
		local active = ui.use_state(props.value:peek())
		local function shown(): { Font }
			return M.matching(fonts, query:get())
		end
		-- The highlight goes to the first font left when a query hides it.
		ui.effect(function()
			local list = shown()
			for _, f in list do
				if f.name == active:peek() and not f.missing then
					return
				end
			end
			for _, f in list do
				if not f.missing then
					active:set(f.name)
					return
				end
			end
		end)
		local function choose(name: string)
			props.value:set(name)
			open:set(false)
		end
		local function step(by: number, to_end: boolean?)
			local list: { Font } = {}
			for _, f in shown() do
				if not f.missing then
					table.insert(list, f)
				end
			end
			if #list == 0 then
				return
			end
			local at = 0
			for i, f in list do
				if f.name == active:peek() then
					at = i
				end
			end
			local i = if to_end then (if by > 0 then #list else 1) else math.clamp(at + by, 1, #list)
			active:set(list[i].name)
		end
		local function on_key(e: KeyEvent): boolean
			if e.key == "ArrowDown" or e.key == "ArrowUp" then
				step(if e.key == "ArrowDown" then 1 else -1)
			elseif e.key == "Home" or e.key == "End" then
				step(if e.key == "End" then 1 else -1, true)
			elseif e.key == "Enter" then
				choose(active:peek())
			elseif e.key == "Escape" then
				open:set(false)
			else
				return false
			end
			return true
		end
		local function row(f: Font): Node
			local id = `{props.id}_{string.lower((string.gsub(f.name, "%W+", "_")))}`
			return ui.button {
				id = id,
				role = "radio",
				checked = function()
					return props.value:get() == f.name
				end,
				label = f.name,
				w_full = true,
				h = M.ROW,
				px = "$zeron.space.8",
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius_item,
				opacity = if f.missing then 0.45 else nil,
				disabled = f.missing == true,
				variants = recipes.picker_choice {
					selected = function()
						return props.value:get() == f.name
					end,
					keyed = function()
						return active:get() == f.name
					end,
				},
				color = T.text,
				focus = { border = 0 },
				cursor = if f.missing then "default" else "pointer",
				on_click = if f.missing
					then nil
					else function()
						choose(f.name)
					end,
				txt.text {
					f.name,
					literal = true,
					size = "md",
					color = "inherit",
					line = false,
					grow = 1,
					truncate = true,
				},
			}
		end
		return ui.column {
			w_full = true,
			gap = "$zeron.space.2",
			ui.row {
				h = 36,
				w_full = true,
				shrink = 0,
				mx = T.pull(4),
				mt = T.pull(4),
				mb = T.space(frost.INSET),
				px = "$zeron.space.10",
				gap = "$zeron.space.8",
				items = "center",
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				icon { name = "magnifer", size = 14, color = T.secondary },
				ui.input {
					id = `{props.id}_search`,
					value = query,
					label = "Search fonts",
					placeholder = "Search fonts",
					grow = 1,
					min_w = 0,
					p = 0,
					border = 0,
					rounded = 0,
					bg = T.clear,
					focus = { border = 0, bg = T.clear },
					text_size = "$font.size.md",
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = on_key,
				},
			},
			ui.scroll {
				w_full = true,
				max_h = M.LIST_MAX,
				fade = { 12, 12 },
				fade_overflow = true,
				ui.presence(function(): string
					local names = {}
					for _, f in shown() do
						table.insert(names, f.name)
					end
					return table.concat(names, "\n")
				end, function(): Node
					local list = shown()
					if #list == 0 then
						return ui.row {
							h = M.ROW,
							px = "$zeron.space.8",
							items = "center",
							txt.text {
								if query:peek() == "" then "No fonts" else "No matching fonts",
								size = "sm",
								color = T.tertiary,
								line = false,
							},
						}
					end
					local rows: { Node } = {}
					for _, f in list do
						table.insert(rows, row(f))
					end
					return ui.column { w_full = true, gap = "$zeron.space.2", role = "radiogroup", rows }
				end, { w_full = true }),
			},
		}
	end
	local trigger = ui.button {
		id = props.id,
		label = function()
			return `{props.label}: {props.value:get()}`
		end,
		w = M.PICKER_W,
		h = 32,
		px = "$zeron.space.10",
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.radius_button,
		variants = recipes.wash { rest = "ink2", hover = "ink4" },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = ui.toggle(open),
		on_key = function(e: KeyEvent): boolean
			if e.key == "ArrowDown" or e.key == "ArrowUp" or e.key == "Home" or e.key == "End" then
				open:set(true)
				return true
			end
			return false
		end,
		txt.text {
			function()
				return props.value:get()
			end,
			size = "md",
			line = false,
			grow = 1,
			truncate = true,
		},
		icon { name = "alt-arrow-down", size = 14, color = T.tertiary },
	}
	return popover.popover {
		id = `{props.id}_menu`,
		open = open,
		anchor = trigger,
		label = props.label,
		w = M.PICKER_W,
		p = T.space(frost.INSET),
		placement = { side = "bottom", align = "start", offset = 4 },
		ui.presence(function(): boolean?
			return if open:get() then true else nil
		end, content, { w_full = true }),
	}
end)

-- The sizes each font row offers (settings.rs font size choices).
local UI_SIZES = { "12 px", "13 px", "14 px", "15 px", "16 px", "18 px", "20 px" }
local CODE_SIZES = { "10 px", "11 px", "12 px", "12.5 px", "13 px", "14 px", "15 px", "16 px", "18 px", "20 px" }

local function size_select(id: string, label: string, value: State<string>, sizes: { string }): Node
	local options: { select.Option } = {}
	for i, s in sizes do
		table.insert(options, { value = s, label = s, id = `{id}_{i}` })
	end
	return select { id = id, label = `{label} size`, value = value, options = options, w = 128, max_h = 280 }
end

export type FontPrefs = {
	font_ui: State<string>,
	font_ui_size: State<string>,
	font_terminal: State<string>,
	font_terminal_size: State<string>,
	font_code: State<string>,
	font_code_size: State<string>,
	render_math: State<boolean>,
	math_font: State<string>,
	math_size: State<string>,
}

-- The math faces (settings.rs MathFont), each bundled: its menu label,
-- the note beside it, and what the row says of it.
M.MATH_FONTS = {
	{
		value = "fira",
		label = "Fira Math",
		detail = "Sans",
		about = "A sans face that sits beside the interface font.",
	},
	{ value = "stix", label = "STIX Two", detail = "Serif", about = "A Times-like serif face with the TeX look." },
	{
		value = "computer_modern",
		label = "Computer Modern",
		detail = "LaTeX",
		about = "A serif face with the classic LaTeX look.",
	},
	{ value = "libertinus", label = "Libertinus", detail = "Serif", about = "A warm serif book face." },
	{
		value = "pagella",
		label = "Palatino",
		detail = "Serif",
		about = "A Palatino serif face, from TeX Gyre Pagella.",
	},
	{ value = "euler", label = "Euler", detail = "Upright", about = "Zapf's upright, hand-drawn math." },
}
-- Math sizes, percent of the text around it (appearance.rs MATH_SIZES).
M.MATH_SIZES = { "90", "100", "110", "120", "135", "150" }

-- Render math, Math font and Math size (appearance.rs render_math_rows).
local function math_rows(prefs: FontPrefs): { Node }
	local on, face, size = prefs.render_math, prefs.math_font, prefs.math_size
	local faces: { select.Option } = {}
	for _, f in M.MATH_FONTS do
		table.insert(
			faces,
			{ value = f.value, label = f.label, detail = f.detail, id = `settings_math_font_{f.value}` }
		)
	end
	local sizes: { select.Option } = {}
	for _, v in M.MATH_SIZES do
		table.insert(sizes, {
			value = v,
			label = `{v}%`,
			detail = if v == "100" then "Default" else nil,
			id = `settings_math_size_{v}`,
		})
	end
	return {
		settings.row {
			id = "settings_render_math_row",
			anchor = "render_math",
			title = "Render math",
			meta = { "Typeset LaTeX in messages. Off shows the source as code." },
			control = settings.switch { id = "settings_render_math", value = on },
		},
		settings.row {
			id = "settings_math_font_row",
			anchor = "math_font",
			title = "Math font",
			meta = {
				function()
					local v = face:get()
					for _, f in M.MATH_FONTS do
						if f.value == v then
							return f.about
						end
					end
					return M.MATH_FONTS[1].about
				end,
			},
			control = select {
				id = "settings_math_font",
				label = "Math font",
				value = face,
				options = faces,
				w = 160,
				menu_w = 220,
			},
		},
		settings.row {
			id = "settings_math_size_row",
			anchor = "math_size",
			title = "Math size",
			meta = { "Relative to the text around it." },
			control = select { id = "settings_math_size", label = "Math size", value = size, options = sizes, w = 160 },
		},
	}
end
M.FONT_DEFAULTS = {
	font_ui = "Geist",
	font_ui_size = "16 px",
	font_terminal = "Geist Mono",
	font_terminal_size = "13 px",
	font_code = "Geist Mono",
	font_code_size = "12.5 px",
}

-- Conversation width (settings.rs transcript width): the reading column's
-- widest, the composer under it as wide.
M.WIDTH_MIN = 560
M.WIDTH_MAX = 1200
M.WIDTH_STEP = 16
M.WIDTH_DEFAULT = 736
local SLIDER_W = 240
-- zgx's slider keeps 8 at each end and its thumb 10 wide: the knob is
-- centred where its thumb would be.
local RAIL_INSET = 8
local THUMB = 10
local KNOB = 14

-- The width slider: zgx's (the keys, the drag, its step, a slider to
-- assistive technology) in Zeron's look, a 4 rail with the accent's fill
-- and a 14 knob; over it, the width and Reset, under it the range's ends,
-- shown while the pointer is on it.
function M.width_slider(id: string, value: State<number>): Node
	local function knob_left(): number
		local f = (value:get() - M.WIDTH_MIN) / (M.WIDTH_MAX - M.WIDTH_MIN)
		return RAIL_INSET + f * (SLIDER_W - 2 * RAIL_INSET - THUMB) + THUMB / 2 - KNOB / 2
	end
	local function detail(...: Node): Node
		return ui.row {
			w = SLIDER_W,
			h = 16,
			justify = "between",
			items = "center",
			opacity = 0,
			group_hover = { opacity = 1 },
			{ ... },
		}
	end
	return ui.column {
		id = id,
		hover_group = true,
		gap = "$zeron.space.2",
		detail(
			txt.text {
				function()
					return `{math.floor(value:get())} px`
				end,
				size = "xs",
				color = T.secondary,
				tabular = true,
				line = false,
			},
			ui.button {
				id = `{id}_reset`,
				variants = recipes.text_button,
				min_h = 16,
				on_click = function()
					value:set(M.WIDTH_DEFAULT)
				end,
				txt.text { "Reset", size = "xs", color = "inherit", line = false },
			}
		),
		ui.div {
			relative = true,
			w = SLIDER_W,
			h = 28,
			ui.div {
				absolute = true,
				left = RAIL_INSET,
				right = RAIL_INSET,
				top = 12,
				h = 4,
				rounded = T.radius_full,
				bg = T.ink3,
				pointer_events = "none",
			},
			ui.slider {
				id = `{id}_input`,
				label = "Conversation width",
				value = value,
				min = M.WIDTH_MIN,
				max = M.WIDTH_MAX,
				step = M.WIDTH_STEP,
				w = SLIDER_W,
				h = 28,
				px = 0,
				py = 0,
				bg = T.clear,
				color = T.clear,
				rounded = T.radius_full,
				cursor = "pointer",
			},
			ui.div {
				id = `{id}_knob`,
				absolute = true,
				top = 7,
				left = knob_left,
				w = KNOB,
				h = KNOB,
				rounded = T.radius_full,
				bg = T.accent,
				shadow = T.shadow_sm,
				pointer_events = "none",
			},
		},
		detail(
			txt.text { "560 px", size = "micro", color = T.tertiary, line = false },
			txt.text { "1,200 px", size = "micro", color = T.tertiary, line = false }
		),
	}
end

-- Each font row's name for settings search.
local ANCHORS: { [string]: string } =
	{ font_ui = "interface_font", font_terminal = "terminal_font", font_code = "code_font" }

-- Fonts and layout: a row per font (its family and size), then the width.
function M.fonts(prefs: FontPrefs, width: State<number>): Node
	local function row(
		id: string,
		title: string,
		meta: string,
		family: State<string>,
		size: State<string>,
		sizes: { string },
		mono: boolean?
	): Node
		return settings.row {
			id = `settings_{id}_row`,
			anchor = ANCHORS[id],
			title = title,
			meta = { meta },
			control = ui.row {
				gap = "$zeron.space.8",
				items = "center",
				M.font_picker { id = `settings_{id}`, label = title, value = family, mono = mono },
				size_select(`settings_{id}_size`, title, size, sizes),
			},
		}
	end
	local missing: { Node } = {}
	for _, f in M.FONTS do
		if f.missing then
			for _, kind in
				{
					{ "Interface font", prefs.font_ui },
					{ "Terminal font", prefs.font_terminal },
					{ "Code & diff font", prefs.font_code },
				} :: { { any } }
			do
				local label, value = kind[1] :: string, kind[2] :: State<string>
				table.insert(
					missing,
					ui.show(
						function()
							return value:get() == f.name
						end,
						ui.row {
							w_full = true,
							px = "$zeron.space.12",
							py = "$zeron.space.8",
							rounded = T.radius_button,
							bg = T.danger_wash,
							txt.text {
								`{label} "{f.name}" isn't available on this device. Using {if label
										== "Interface font"
									then "Geist"
									else "Geist Mono"}.`,
								literal = true,
								size = "sm",
								color = T.danger,
								wrap = true,
							},
						}
					)
				)
			end
		end
	end
	return ui.column {
		w_full = true,
		gap = "$zeron.space.10",
		settings.section {
			id = "settings_fonts",
			title = "Fonts and layout",
			row("font_ui", "Interface font", "Menus and conversations", prefs.font_ui, prefs.font_ui_size, UI_SIZES),
			row(
				"font_terminal",
				"Terminal font",
				"Terminal output · monospace only",
				prefs.font_terminal,
				prefs.font_terminal_size,
				CODE_SIZES,
				true
			),
			row(
				"font_code",
				"Code & diff font",
				"Code, diffs, and files",
				prefs.font_code,
				prefs.font_code_size,
				CODE_SIZES
			),
			settings.row {
				anchor = "conversation_width",
				title = "Conversation width",
				meta = { "Maximum width for messages and the composer." },
				control = M.width_slider("settings_conversation_width", width),
			},
			math_rows(prefs),
		},
		missing,
	}
end

export type MotionPrefs = {
	reduce_motion: State<string>,
	pause_background: State<boolean>,
	smooth_scrolling: State<boolean>,
}

-- Motion (motion.rs ReduceMotion): System, On or Off, each saying what it
-- does; the system's own setting decides System.
function M.motion(prefs: MotionPrefs): Node
	local options: { select.Option } = {
		{ value = "System", label = "System", id = "settings_reduce_motion_1" },
		{ value = "On", label = "On", id = "settings_reduce_motion_2" },
		{ value = "Off", label = "Off", id = "settings_reduce_motion_3" },
	}
	local function system_reduces(): boolean
		return ui.prefers.reduced_motion:get()
	end
	return settings.section {
		title = "Motion",
		settings.row {
			anchor = "reduce_motion",
			title = "Reduce motion",
			meta = {
				function()
					local v = prefs.reduce_motion:get()
					if v == "On" then
						return "Animations skip straight to their final state."
					elseif v == "Off" then
						return "Animations play even if the system asks for less motion."
					elseif system_reduces() then
						return "Following reduced system motion. Activity indicators use a gentle brightness pulse."
					end
					return "Following the system, which currently allows motion."
				end,
			},
			control = select {
				id = "settings_reduce_motion",
				label = "Reduce motion",
				value = prefs.reduce_motion,
				options = options,
				w = 128,
			},
		},
		settings.row {
			anchor = "pause_animations",
			title = "Pause animations in background",
			meta = { "Hold animations still while Zeron isn't the focused window." },
			control = settings.switch { id = "settings_pause_background", value = prefs.pause_background },
		},
		settings.row {
			anchor = "smooth_scrolling",
			title = "Smooth scrolling",
			meta = {
				function()
					if prefs.smooth_scrolling:get() and M.reduces(prefs) then
						return "Mouse wheels step instantly while motion is reduced."
					end
					return "Mouse wheels glide instead of jumping. Trackpads are unaffected."
				end,
			},
			control = settings.switch { id = "settings_smooth_scrolling", value = prefs.smooth_scrolling },
		},
	}
end

-- Whether motion is reduced now: On, or System while the system asks.
function M.reduces(prefs: MotionPrefs): boolean
	local v = prefs.reduce_motion:get()
	return v == "On" or (v == "System" and ui.prefers.reduced_motion:get())
end

-- A theme's palette (palette_preview): its surface, background and accent
-- side by side, 30 by 18.
function M.palette(swatch: { string }): Node
	local parts: { Node } = {}
	for _, c in swatch do
		table.insert(parts, ui.div { grow = 1, h_full = true, bg = ui.raw(c, "a theme's own colour, shown as itself") })
	end
	return ui.row {
		w = 30,
		h = 18,
		shrink = 0,
		rounded = "$zeron.radius.5",
		overflow = "hidden",
		border = 1,
		border_color = T.border,
		parts,
	}
end

-- The Light theme or Dark theme select (render_theme_selector): each theme
-- of its kind with its palette, the chosen one's in the field.
function M.theme_select(kind: "light" | "dark", value: State<string>): Node
	local themes = look_mod.themes_of(kind)
	local options: { select.Option } = {}
	local swatches: { [string]: { string } } = {}
	for _, t in themes do
		swatches[t.id] = t.swatch
		table.insert(
			options,
			{ value = t.id, label = t.name, id = `settings_{kind}_theme_{t.id}`, leading = M.palette(t.swatch) }
		)
	end
	return select {
		id = `settings_{kind}_theme`,
		label = if kind == "light" then "Light theme" else "Dark theme",
		value = value,
		options = options,
		w = 218,
		menu_w = 260,
		max_h = 320,
		face = {
			ui.presence(value, function(id: string): Node
				return M.palette(swatches[id] or themes[1].swatch)
			end),
			txt.text {
				function()
					for _, t in themes do
						if t.id == value:get() then
							return t.name
						end
					end
					return value:get()
				end,
				size = "md",
				line = false,
				grow = 1,
				truncate = true,
			},
			icon { name = "alt-arrow-down", size = 12, color = T.tertiary },
		},
	}
end

-- The new-thread background and the wallpaper folder (appearance.rs
-- 3733-3905): the image's tile and name ("No image selected"; "Image
-- unavailable" once its file is gone), Adjust, Replace image, Remove; or
-- Choose image. The folder, what ⌘U does, Choose folder and Shuffle.
export type BackgroundProps = {
	image: State<string>,
	-- Its file gone (the sample engine can lose it).
	missing: State<boolean>,
	folder: State<string>,
	-- ⌘U's combo, as the keys show it.
	random_keys: () -> string,
	on_choose: () -> (),
	on_adjust: () -> (),
	on_choose_folder: () -> (),
	on_shuffle: () -> (),
}
function M.background_rows(props: BackgroundProps): { Node }
	local function chosen(): boolean
		return props.image:get() ~= ""
	end
	local function available(): boolean
		return chosen() and not props.missing:get()
	end
	local function name(): string
		local path = props.image:get()
		local file = string.match(path, "([^/]+)$") or path
		return (string.gsub(file, "%.[^.]+$", ""))
	end
	local tile = ui.show(
		available,
		ui.row {
			id = "settings_canvas_background_tile",
			w = 36,
			h = 36,
			shrink = 0,
			rounded = "$zeron.radius.10",
			overflow = "hidden",
			border = 1,
			border_color = T.hairline,
			items = "center",
			justify = "center",
			ui.image { src = props.image, fit = "cover", w = 34, h = 34, rounded = "$zeron.radius.9" },
		}
	)
	local image = settings.row {
		id = "settings_canvas_background_row",
		anchor = "new_thread_background",
		lead = tile,
		title = "New thread background",
		meta = {
			function()
				if not chosen() then
					return "No image selected"
				end
				return if props.missing:get() then "Image unavailable" else name()
			end,
			function()
				return if chosen() and props.missing:get() then "Choose a replacement or remove it." else ""
			end,
		},
		control = ui.row {
			gap = "$zeron.space.8",
			items = "center",
			flex_wrap = true,
			ui.show(
				available,
				button {
					id = "settings_canvas_background_adjust",
					label = "Adjust",
					size = "sm",
					variant = "secondary",
					on_click = props.on_adjust,
				}
			),
			button {
				id = "settings_canvas_background",
				label = function()
					return if chosen() then "Replace image" else "Choose image"
				end,
				size = "sm",
				variant = "secondary",
				on_click = props.on_choose,
			},
			ui.show(
				chosen,
				button {
					id = "settings_canvas_background_remove",
					label = "Remove",
					size = "sm",
					variant = "secondary_danger",
					on_click = function()
						props.image:set("")
						props.missing:set(false)
					end,
				}
			),
		},
	}
	local folder = settings.row {
		id = "settings_wallpaper_folder_row",
		anchor = "wallpaper_folder",
		title = "Wallpaper folder",
		meta = {
			function()
				local f = props.folder:get()
				local shown = if f == "" then "Choose a folder of wallpaper images." else f
				return `{shown} · {props.random_keys()} picks a random image`
			end,
		},
		control = ui.row {
			gap = "$zeron.space.8",
			items = "center",
			button {
				id = "settings_wallpaper_folder",
				label = "Choose folder",
				size = "sm",
				variant = "secondary",
				on_click = props.on_choose_folder,
			},
			ui.show(
				function()
					return props.folder:get() ~= ""
				end,
				button {
					id = "settings_wallpaper_shuffle",
					label = "Shuffle",
					size = "sm",
					variant = "secondary",
					on_click = props.on_shuffle,
				}
			),
		},
	}
	return { image, folder }
end

-- Match wallpaper colors (settings/wallpaper_colors.rs): the artwork's
-- dominant colour tints the accent and the surfaces while there is one.
function M.wallpaper_colors_row(value: State<boolean>): Node
	return settings.row {
		anchor = "wallpaper_colors",
		title = "Match wallpaper colors",
		meta = { "Use wallpaper colors for accents, highlights, and subtle surface tints." },
		control = settings.switch { id = "settings_wallpaper_colors", value = value },
	}
end

-- Where the artwork sits: its zoom (1 to 4) and its offset, a fraction of
-- the room the zoom leaves on each axis (-1 to 1, 0 centred).
export type Placement = { zoom: number, x: number, y: number }
M.PLACEMENT = { zoom = 1, x = 0, y = 0 } :: Placement

-- The preview: the dialog's width inside its padding by 258, about the
-- new-session header's shape.
local PREVIEW_W = 558
local PREVIEW_H = 258

-- Adjust background (appearance.rs render_background_adjustment): the
-- artwork in a preview of the header it fills; dragging moves it (thirds
-- show while it does), the zoom slider, − and + and the wheel scale it;
-- Reset, Cancel, Apply (only Apply keeps it).
function M.adjust_dialog(open: State<boolean>, image: State<string>, placement: State<Placement>): Node
	return ui.presence(function(): boolean?
		return if open:get() then true else nil
	end, function(): Node
		local draft = ui.use_state(table.clone(placement:peek()))
		local zoom = ui.use_state(draft:peek().zoom)
		local dragging = ui.use_state(false)
		local from: { number } = { 0, 0, 0, 0 }
		ui.effect(function()
			local z = zoom:get()
			local d = table.clone(draft:peek())
			if d.zoom ~= z then
				d.zoom = z
				draft:set(d)
			end
		end)
		local function set_zoom(z: number)
			zoom:set(math.clamp(math.floor(z * 10 + 0.5) / 10, 1, 4))
		end
		local function close()
			open:set(false)
		end
		local function apply()
			placement:set(table.clone(draft:peek()))
			close()
		end
		-- The artwork covering the preview at the draft's zoom and offset.
		local function art(): Node
			return ui.image {
				id = "background_adjust_image",
				src = image,
				fit = "cover",
				absolute = true,
				w = function()
					return PREVIEW_W * draft:get().zoom
				end,
				h = function()
					return PREVIEW_H * draft:get().zoom
				end,
				left = function()
					local d = draft:get()
					local room = PREVIEW_W * (d.zoom - 1) / 2
					return -room + d.x * room
				end,
				top = function()
					local d = draft:get()
					local room = PREVIEW_H * (d.zoom - 1) / 2
					return -room + d.y * room
				end,
				pointer_events = "none",
			}
		end
		local thirds: { Node } = {}
		for i = 1, 2 do
			table.insert(
				thirds,
				ui.div { absolute = true, top = 0, bottom = 0, left = `{i * 100 / 3}%`, w = 1, bg = T.strong }
			)
			table.insert(
				thirds,
				ui.div { absolute = true, left = 0, right = 0, top = `{i * 100 / 3}%`, h = 1, bg = T.strong }
			)
		end
		return dialog {
			id = "background_adjust",
			open = open,
			title = "Adjust background",
			description = "Drag to reposition. Scroll or pinch to zoom.",
			w = 600,
			on_enter = apply,
			actions = {
				button {
					id = "background_adjust_cancel",
					label = "Cancel",
					size = "sm",
					variant = "ghost",
					on_click = close,
				},
				button {
					id = "background_adjust_apply",
					label = "Apply",
					size = "sm",
					variant = "primary",
					on_click = apply,
				},
			},
			ui.div {
				id = "background_adjust_preview",
				relative = true,
				w = 558,
				h = PREVIEW_H,
				self = "center",
				rounded = T.radius_card,
				overflow = "hidden",
				bg = T.ink2,
				cursor = function()
					return if dragging:get() then "grabbing" else "grab"
				end,
				on_press = function(e: PointerEvent)
					local d = draft:peek()
					from = { e.x, e.y, d.x, d.y }
					dragging:set(true)
				end,
				on_press_move = function(e: PointerEvent)
					local d = table.clone(draft:peek())
					local rx, ry = PREVIEW_W * (d.zoom - 1) / 2, PREVIEW_H * (d.zoom - 1) / 2
					d.x = if rx > 0 then math.clamp(from[3] + (e.x - from[1]) / rx, -1, 1) else 0
					d.y = if ry > 0 then math.clamp(from[4] + (e.y - from[2]) / ry, -1, 1) else 0
					draft:set(d)
				end,
				on_release = function()
					dragging:set(false)
				end,
				on_wheel = function(e: WheelEvent): boolean?
					set_zoom(zoom:peek() - e.dy / 200)
					return true
				end,
				on_pinch = function(e: PinchEvent): boolean?
					set_zoom(zoom:peek() * (1 + e.scale))
					return true
				end,
				art(),
				ui.show(
					dragging,
					ui.div { absolute = true, left = 0, right = 0, top = 0, bottom = 0, pointer_events = "none", thirds }
				),
			},
			ui.row {
				w = 558,
				items = "center",
				gap = "$zeron.space.6",
				button {
					id = "background_adjust_reset",
					label = "Reset",
					size = "sm",
					variant = "ghost",
					on_click = function()
						draft:set(table.clone(M.PLACEMENT))
						zoom:set(1)
					end,
				},
				ui.div { grow = 1 },
				button {
					id = "background_adjust_out",
					label = "−",
					size = "sm",
					variant = "ghost",
					on_click = function()
						set_zoom(zoom:peek() - 0.1)
					end,
				},
				ui.slider {
					id = "background_adjust_zoom",
					label = "Background zoom",
					value = zoom,
					min = 1,
					max = 4,
					step = 0.1,
					w = 168,
					h = 28,
				},
				txt.text {
					function()
						return `{math.floor(zoom:get() * 100 + 0.5)}%`
					end,
					id = "background_adjust_value",
					size = "sm",
					color = T.secondary,
					tabular = true,
					w = 52,
					align = "center",
					line = false,
				},
				button {
					id = "background_adjust_in",
					label = "+",
					size = "sm",
					variant = "ghost",
					on_click = function()
						set_zoom(zoom:peek() + 0.1)
					end,
				},
			},
		}
	end)
end

return M
