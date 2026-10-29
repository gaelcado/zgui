-- Zeron's settings page (settings/*.rs, shell.rs render_settings_page;
-- v0.2.129): Back, the search field and the sections down the left, in a
-- column as wide as the app's sidebar and toned as it is, the sections
-- grouped by spacing alone (preferences, agents and devices, then the
-- workspace's data); the search's hits in their place while it holds a
-- query. Each section a column of cards 760 wide at most, on the window's
-- glass. The app gives it its preferences and what the pages show of it
-- (the layout, the archived sessions, the sidebar's width); the workbench
-- shows the same page.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local wash = require("./wash")
local scroll = require("./scroll")
local settings = require("./settings")
local appearance = require("./appearance")
local look_mod = require("./look")
local select = require("./select")
local segmented = require("./segmented")
local keymap = require("./keymap")
local shortcuts_page = require("./shortcuts_page")
local recipes = require("./recipes")
local L = require("./panel_layout")
local appearance_more = require("./settings_appearance")
local theme_library = require("./theme_library")
local agents = require("./settings_agents")
local sections = require("./settings_sections")
local capture = require("./settings_capture")
local git = require("./settings_git")
local search = require("./settings_search")

-- The preferences the pages hold.
export type Prefs = {
	sounds: State<boolean>,
	naming: State<string>,
	send: State<string>,
	-- Escape stops the running agent when nothing else takes it.
	escape_stops: State<boolean>,
	dictation: State<boolean>,
	-- The composer's model chip (no setting of Zeron's shows it: on).
	model_chip: State<boolean>,
	compact_picker: State<boolean>,
	notify_done: State<boolean>,
	notify_input: State<boolean>,
	notify_failed: State<boolean>,
	-- Voice (dictation/model.rs): the microphone, where Codex's voice runs
	-- ("" this device) and its style ("" Codex's default).
	microphone: State<string>,
	voice_host: State<string>,
	voice_style: State<string>,
	-- Files (settings/files.rs).
	autosave: State<boolean>,
	autosave_delay: State<string>,
	word_wrap: State<boolean>,
	hidden_files: State<boolean>,
	-- Appshots (settings/appshots.rs).
	appshots: State<boolean>,
	appshot_sound: State<boolean>,
	appshot_destination: State<string>,
	-- Completion, per provider (settings/completion.rs): `$` for skills,
	-- and skills kept out of the `/` menu.
	dollar_skills: State<boolean>,
	separate_commands: State<boolean>,
	-- The wallpaper folder (settings/wallpaper.rs) ⌘U picks from.
	wallpaper: State<string>,
	-- The new-session canvas's artwork (an image's path; "" for none), and
	-- its effect (settings.rs NewThreadBackgroundEffect).
	canvas_background: State<string>,
	canvas_effect: State<string>,
	-- The transcript's compact mode (transcript_compact_mode): each turn's
	-- thinking and tools under one folded "Worked for" header.
	compact_mode: State<boolean>,
	-- Zeron's own (v0.2.129): the fonts and the reading width
	-- (settings/appearance.rs), the artwork's tint and placement, motion;
	-- desktop notifications (notifications.rs: the sounds are `sounds` and
	-- `notify_*`); where pull requests open; `naming` is thread_naming.rs's
	-- `agent/model`, "" for the session's agent.
	font_ui: State<string>,
	font_ui_size: State<string>,
	font_terminal: State<string>,
	font_terminal_size: State<string>,
	font_code: State<string>,
	font_code_size: State<string>,
	conversation_width: State<number>,
	render_math: State<boolean>,
	math_font: State<string>,
	math_size: State<string>,
	wallpaper_colors: State<boolean>,
	canvas_placement: State<appearance_more.Placement>,
	reduce_motion: State<string>,
	pause_background: State<boolean>,
	smooth_scrolling: State<boolean>,
	desktop: State<boolean>,
	agent_updates: State<boolean>,
	background_only: State<boolean>,
	open_prs: State<string>,
}
export type Archived = sections.Archived
export type Context = {
	-- The section shown.
	section: State<string>,
	prefs: Prefs,
	-- The theme, its mode, the accent and the surface (kit/look).
	look: look_mod.Look,
	-- The window's layouts, when the app has several.
	layouts: { { id: string, label: string } }?,
	layout: State<string>?,
	archived: { Archived }?,
	archived_total: number?,
	-- The rebindable shortcuts (Zeron's, at their defaults, unless given).
	keymap: keymap.Keymap?,
	-- The archived sessions as they change, putting one back, removing all.
	archived_list: State<{ Archived }>?,
	on_unarchive: ((s: Archived) -> ())?,
	on_delete_all: (() -> ())?,
	-- Where the workspace lives ("local", "synced"), as Devices says.
	scope: (() -> string)?,
	on_back: (Handler | Action)?,
	-- Whether a voice call is on (Codex's voice keeps its device).
	voice_live: (() -> boolean)?,
	-- A random picture from the wallpaper folder (Shuffle, ⌘U).
	on_shuffle: (() -> ())?,
	-- The new-thread background's file gone (the sample engine's).
	background_missing: State<boolean>?,
	-- Whether a section shows (Cloud and Billing follow the account).
	shown: ((id: string) -> boolean)?,
	-- The app's sidebar width, which the sections' column takes (Zeron's
	-- settings.sidebar_width, shared by both); the default sidebar's else.
	sidebar_width: (() -> number)?,
}

local M = {}

M.WIDTH = settings.WIDTH
-- Files' autosave delays (settings/files.rs DELAY_OPTIONS), and each in
-- milliseconds.
type Choice = { label: string, detail: string? }
local AUTOSAVE_DELAYS: { Choice } = {
	{ label = "300 ms" },
	{ label = "600 ms" },
	{ label = "900 ms" },
	{ label = "1.5 s" },
	{ label = "3 s" },
}
M.AUTOSAVE_DELAYS = AUTOSAVE_DELAYS
function M.delay_ms(label: string): number
	local n, unit = string.match(label, "^([%d%.]+) (m?s)$")
	local value = tonumber(n) or 0.9
	return if unit == "ms" then value else value * 1000
end
-- What "Choose image" picks for the new-session background until the
-- host's file dialog is wired, and "Choose folder" for the wallpapers.
M.SAMPLE_BACKGROUND = "images/shadow.jpg"
M.SAMPLE_FOLDER = "~/Pictures/Wallpapers"

-- The sections (SettingsSection::ALL), each with its glyph; a group starts
-- with `gap` above it.
type Section = { id: string, title: string, icon: string, gap: boolean? }
M.SECTIONS = {
	{ id = "general", title = "General", icon = "settings" },
	{ id = "appearance", title = "Appearance", icon = "tuning" },
	{ id = "notifications", title = "Notifications", icon = "bell" },
	{ id = "voice", title = "Voice", icon = "microphone" },
	{ id = "shortcuts", title = "Shortcuts", icon = "keyboard" },
	{ id = "harnesses", title = "Providers", icon = "widget", gap = true },
	{ id = "devices", title = "Devices", icon = "monitor" },
	{ id = "cloud", title = "Cloud", icon = "cloud" },
	{ id = "billing", title = "Billing", icon = "wallet" },
	{ id = "files", title = "Files", icon = "folder", gap = true },
	{ id = "appshots", title = "Appshots", icon = "monitor" },
	{ id = "archived", title = "Archived sessions", icon = "archive-minimalistic" },
} :: { Section }

-- A set of preferences at their defaults, named under `prefix` (they last
-- across reloads; `persist`, across runs).
function M.prefs(prefix: string, persist: boolean?): Prefs
	local function s<T>(name: string, value: T): State<T>
		return if persist then ui.persist(`{prefix}_{name}`, value) else ui.state(`{prefix}_{name}`, value)
	end
	return {
		sounds = s("sounds", true),
		naming = s("naming", ""),
		send = s("send", "enter"),
		escape_stops = s("escape_stops", false),
		dictation = s("dictation", true),
		model_chip = s("model_chip", true),
		compact_picker = s("compact_picker", true),
		notify_done = s("notify_done", true),
		notify_input = s("notify_input", true),
		notify_failed = s("notify_failed", true),
		microphone = s("microphone", "System default"),
		voice_host = s("voice_host", ""),
		voice_style = s("voice_style", ""),
		autosave = s("autosave", false),
		autosave_delay = s("autosave_delay", "900 ms"),
		word_wrap = s("word_wrap", false),
		hidden_files = s("hidden_files", false),
		appshots = s("appshots", true),
		appshot_sound = s("appshot_sound", true),
		appshot_destination = s("appshot_destination", "Automatic"),
		dollar_skills = s("dollar_skills", true),
		separate_commands = s("separate_commands", true),
		wallpaper = s("wallpaper", ""),
		canvas_background = s("canvas_background", ""),
		canvas_effect = s("canvas_effect", "None"),
		compact_mode = s("compact_mode", false),
		font_ui = s("font_ui", appearance_more.FONT_DEFAULTS.font_ui),
		font_ui_size = s("font_ui_size", appearance_more.FONT_DEFAULTS.font_ui_size),
		font_terminal = s("font_terminal", appearance_more.FONT_DEFAULTS.font_terminal),
		font_terminal_size = s("font_terminal_size", appearance_more.FONT_DEFAULTS.font_terminal_size),
		font_code = s("font_code", appearance_more.FONT_DEFAULTS.font_code),
		font_code_size = s("font_code_size", appearance_more.FONT_DEFAULTS.font_code_size),
		conversation_width = s("conversation_width", appearance_more.WIDTH_DEFAULT),
		render_math = s("render_math", true),
		math_font = s("math_font", "fira"),
		math_size = s("math_size", "100"),
		wallpaper_colors = s("wallpaper_colors", false),
		canvas_placement = s("canvas_placement", appearance_more.PLACEMENT),
		reduce_motion = s("reduce_motion", "System"),
		pause_background = s("pause_background", false),
		smooth_scrolling = s("smooth_scrolling", true),
		desktop = s("desktop", true),
		agent_updates = s("agent_updates", true),
		background_only = s("background_only", true),
		open_prs = s("open_prs", "Pull request view"),
	}
end

-- Zeron's keymap at its defaults, for a page given none (the workbench).
local fallback: keymap.Keymap? = nil
local function keys_of(ctx: Context): keymap.Keymap
	if ctx.keymap then
		return ctx.keymap
	end
	if not fallback then
		fallback = keymap.new("settings_keys", keymap.ZERON, ui.state("settings_keys_custom", {}))
	end
	return fallback :: keymap.Keymap
end

-- The sections shown now.
local function shown_sections(ctx: Context): { search.Section }
	local out: { search.Section } = {}
	for _, s in M.SECTIONS do
		if not ctx.shown or ctx.shown(s.id) then
			table.insert(out, { id = s.id, title = s.title, icon = s.icon })
		end
	end
	return out
end

local function page(title: string, ...: Node): Node
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.32",
		settings.header { title = title },
		{ ... },
	}
end

-- A select of named choices (widgets::select): the value in a 32-high
-- field, its menu under it, checked at the chosen one; a choice's detail
-- muted after it.
local function choose(id: string, value: State<string>, choices: { Choice }, w: number?): Node
	local options: { select.Option } = {}
	for i, c in choices do
		table.insert(options, { value = c.label, label = c.label, id = `{id}_{i}`, detail = c.detail })
	end
	return select { id = id, value = value, options = options, w = w or 180, menu_w = math.max(w or 180, 220) }
end

-- The device General's Git card edits: this one unless chosen.
local git_device = ui.state("settings_git_device", "d7c1f0a2-41b9-4c55-9e3a-0f6b2c8d1e44")

-- General (settings/shortcuts.rs general_page): how messages send, compact
-- mode and the compact picker, Escape; Links; Thread naming; Git.
local function general(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"General",
		settings.card {
			settings.row {
				anchor = "send_messages_with",
				title = "Send messages with",
				control = select {
					id = "pref_send",
					label = "Send messages with",
					value = pref.send,
					options = {
						{ value = "enter", label = "Enter" },
						{ value = "cmd_enter", label = if keymap.MAC then "⌘ Enter" else "Ctrl Enter" },
					},
					w = 128,
				},
			},
			settings.row {
				anchor = "compact_mode",
				title = "Compact mode",
				meta = { "Collapse thinking and tools." },
				control = settings.switch { id = "pref_compact_mode", value = pref.compact_mode },
			},
			settings.row {
				anchor = "compact_model_picker",
				title = "Compact model picker",
				meta = { "Adjust effort with a slider, then open the model list when needed." },
				control = settings.switch { id = "pref_compact_picker", value = pref.compact_picker },
			},
			settings.row {
				anchor = "escape_stops",
				title = "Stop agent with Escape",
				meta = { "When no dialog or menu is open." },
				control = settings.switch { id = "settings_escape_stops", value = pref.escape_stops },
			},
		},
		sections.links(pref.open_prs),
		sections.thread_naming(pref.naming),
		git.card(git_device)
	)
end

-- The new-thread background's effects (settings.rs NewThreadBackgroundEffect).
local EFFECTS: { Choice } = {
	{ label = "None", detail = "Shows the original artwork." },
	{ label = "Dither", detail = "Rebuilds the artwork with a dithered color palette." },
	{ label = "ASCII", detail = "Recreates the artwork with colored characters on black." },
	{ label = "Halftone", detail = "Recreates the artwork with colored print dots on black." },
	{ label = "Scanlines", detail = "Adds a pronounced horizontal display-line texture." },
}
M.EFFECTS = EFFECTS

-- Adjust background's dialog, while it is up; the background's file gone,
-- for a page given no state of the app's.
local adjusting = ui.state("settings_background_adjust", false)
local missing_sample = ui.state("settings_background_missing", false)

-- Appearance (settings/appearance.rs): the color scheme; the light and
-- dark themes, the accent and wallpaper colors; material and background;
-- motion; the theme library; fonts and layout.
local function appearance_page(ctx: Context): Node
	local pref = ctx.prefs
	local km = keys_of(ctx)
	local missing = ctx.background_missing or missing_sample
	local modes: { Node } = {}
	for _, m in { "system", "light", "dark" } :: { appearance.Mode } do
		table.insert(
			modes,
			appearance.card {
				id = `settings_mode_{m}`,
				mode = m,
				selected = function()
					return ctx.look.mode:get() == m
				end,
				on_click = ui.set(ctx.look.mode, m),
			}
		)
	end
	local function accent_note(): string
		if pref.wallpaper_colors:get() and pref.canvas_background:get() ~= "" then
			return "Wallpaper colors are enabled; this accent is used when they are off."
		end
		local id = ctx.look.accent:get()
		for _, a in look_mod.ACCENTS do
			if a.id == id and id ~= "theme" then
				return a.label
			end
		end
		return "Theme default"
	end
	local function surface_note(): string
		local s = ctx.look.surface:get()
		if s == "frosted" then
			return "Translucent surfaces"
		elseif s == "opaque" then
			return "Solid surfaces"
		end
		return `Theme default: {if look_mod.frosted(ctx.look) then "frosted" else "opaque"}`
	end
	local background = appearance_more.background_rows {
		image = pref.canvas_background,
		missing = missing,
		folder = pref.wallpaper,
		random_keys = function()
			local combo = keymap.combo(km, "random_wallpaper")
			return if keymap.MAC then table.concat(keymap.caps(combo)) else keymap.display(combo)
		end,
		on_choose = function()
			pref.canvas_background:set(M.SAMPLE_BACKGROUND)
			missing:set(false)
		end,
		on_adjust = function()
			adjusting:set(true)
		end,
		on_choose_folder = function()
			pref.wallpaper:set(M.SAMPLE_FOLDER)
		end,
		on_shuffle = ctx.on_shuffle or function() end,
	}
	local material: { Node } = {
		settings.row {
			anchor = "glass",
			title = "Glass",
			meta = { surface_note },
			control = segmented {
				id = "settings_surface",
				size = "sm",
				value = ctx.look.surface :: any,
				options = look_mod.SURFACES,
			},
		},
		settings.row {
			anchor = "double_border",
			title = "Double border",
			meta = { "A lit rim inside the hairline of panels, panes and wells" },
			control = settings.switch { id = "settings_rim", value = ctx.look.rim },
		},
		background[1],
		background[2],
		-- While there is artwork: its effect.
		ui.show(
			function()
				return pref.canvas_background:get() ~= "" and not missing:get()
			end,
			settings.row {
				anchor = "background_effect",
				title = "Background effect",
				meta = {
					function()
						for _, e in EFFECTS do
							if e.label == pref.canvas_effect:get() then
								return e.detail or ""
							end
						end
						return ""
					end,
				},
				control = choose("settings_canvas_effect", pref.canvas_effect, EFFECTS, 128),
			}
		),
	}
	-- The window's layouts are this app's own.
	if ctx.layouts and ctx.layout then
		table.insert(
			material,
			settings.row {
				anchor = "layout",
				title = "Layout",
				meta = { "How the window is drawn around its content" },
				control = segmented {
					id = "layout_choice",
					options = ctx.layouts :: any,
					value = ctx.layout :: any,
					size = "sm",
				},
			}
		)
	end
	return page(
		"Appearance",
		ui.column {
			w_full = true,
			gap = "$zeron.space.12",
			txt.text { "Color scheme", size = "md", color = T.secondary, px = "$zeron.space.8" },
			ui.row {
				gap = "$zeron.space.16",
				on_mount = settings.anchor("color_scheme"),
				modes,
			},
		},
		settings.card {
			settings.row {
				anchor = "light_theme",
				title = "Light theme",
				control = appearance_more.theme_select("light", ctx.look.light),
			},
			settings.row {
				anchor = "dark_theme",
				title = "Dark theme",
				control = appearance_more.theme_select("dark", ctx.look.dark),
			},
			settings.row {
				anchor = "accent_color",
				title = "Accent color",
				meta = { accent_note },
				control = look_mod.swatches(ctx.look, "settings_accent"),
			},
			appearance_more.wallpaper_colors_row(pref.wallpaper_colors),
		},
		settings.section { title = "Material and background", table.unpack(material) },
		appearance_more.motion(pref),
		theme_library.card(),
		appearance_more.fonts(pref, pref.conversation_width),
		appearance_more.adjust_dialog(adjusting, pref.canvas_background, pref.canvas_placement)
	)
end

-- Notifications (settings/notifications.rs): Desktop, then Sounds.
local function notifications(ctx: Context): Node
	return sections.notifications(ctx.prefs)
end

local function shortcuts(ctx: Context): Node
	local pref = ctx.prefs
	return shortcuts_page.view {
		keymap = keys_of(ctx),
		customised = function()
			return pref.send:get() ~= "enter" or pref.escape_stops:get()
		end,
		on_restore = function()
			pref.send:set("enter")
			pref.escape_stops:set(false)
		end,
	}
end

-- Providers (settings/harnesses.rs): each agent on the device chosen, its
-- completion, delegation, updates and accounts under it. Accounts live
-- under their providers (v0.2.129: "Accounts" opens Providers).
local function harnesses(ctx: Context): Node
	return agents.providers(ctx.prefs)
end

local function devices(ctx: Context): Node
	return agents.devices_page(if ctx.scope then ctx.scope() else nil)
end

local function voice(ctx: Context): Node
	return capture.voice(ctx.prefs, keys_of(ctx), ctx.voice_live)
end

-- Files (settings/files.rs): autosave and its delay, word wrap, what the
-- tree shows.
local function files(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"Files",
		settings.card {
			settings.row {
				anchor = "autosave",
				title = "Autosave",
				control = settings.switch { id = "settings_autosave", value = pref.autosave },
			},
			ui.show(
				function()
					return pref.autosave:get()
				end,
				settings.row {
					anchor = "autosave_delay",
					title = "Autosave delay",
					control = choose("settings_autosave_delay", pref.autosave_delay, AUTOSAVE_DELAYS, 148),
				}
			),
			settings.row {
				anchor = "word_wrap",
				title = "Word wrap",
				control = settings.switch { id = "settings_word_wrap", value = pref.word_wrap },
			},
			settings.row {
				anchor = "show_all_files",
				title = "Show hidden and ignored files",
				control = settings.switch { id = "settings_hidden_files", value = pref.hidden_files },
			},
		}
	)
end

local function appshots(ctx: Context): Node
	return capture.appshots(ctx.prefs, keys_of(ctx))
end

-- Archived sessions (settings/archived.rs): 40 a page.
local archived_sample: State<{ Archived }>? = nil
local function archived(ctx: Context): Node
	local list = ctx.archived_list
	if not list then
		archived_sample = archived_sample or ui.state("settings_archived_sample", ctx.archived or {})
		list = archived_sample
	end
	return sections.archived(list :: State<{ Archived }>, ctx.on_unarchive, ctx.on_delete_all)
end

local PAGES: { [string]: (ctx: Context) -> Node } = {
	general = general,
	appearance = appearance_page,
	notifications = notifications,
	voice = voice,
	shortcuts = shortcuts,
	accounts = harnesses,
	harnesses = harnesses,
	files = files,
	appshots = appshots,
	devices = devices,
	archived = archived,
}
-- Other pages an app adds (Cloud, Billing), by section.
M.PAGES = PAGES

-- The sections, grouped by spacing alone (render_settings_nav).
local function nav_list(ctx: Context): Node
	local rows: { Node } = {}
	for _, s in M.SECTIONS do
		local function chosen(): boolean
			return ctx.section:get() == s.id
		end
		local tab = ui.button(wash.item("settings_nav", {
			id = `settings_nav_{s.id}`,
			label = s.title,
			role = "tab",
			w_full = true,
			min_h = 32,
			mt = if s.gap then "$zeron.space.16" else nil,
			px = "$zeron.space.8",
			py = "$zeron.space.6",
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.8",
			cursor = "pointer",
			focus = { border = 0 },
			variants = recipes.active_glass { selected = chosen },
			on_click = ui.set(ctx.section, s.id),
			icon { name = s.icon :: any, size = 16, color = T.secondary },
			txt.text { s.title, size = "md", line = false },
		}, chosen))
		table.insert(
			rows,
			if ctx.shown
				then ui.show(function()
					return (ctx.shown :: (string) -> boolean)(s.id)
				end, tab)
				else tab
		)
	end
	return scroll {
		id = "settings_nav_scroll",
		label = "Settings sections",
		grow = 1,
		w_full = true,
		fade = 16,
		wash.list {
			group = "settings_nav",
			id = "settings_nav",
			w_full = true,
			gap = "$zeron.space.2",
			py = "$zeron.space.12",
			rows,
		},
	}
end

local function nav(ctx: Context): Node
	local props: search.Props = {
		sections = function()
			return shown_sections(ctx)
		end,
		section = ctx.section,
		keymap = keys_of(ctx),
	}
	return ui.column {
		id = "settings_sections",
		w = ctx.sidebar_width or L.SIDEBAR_DEFAULT,
		h_full = true,
		shrink = 0,
		px = "$zeron.space.8",
		-- The sidebar's tone and its seam (shell.rs sidebar_tone).
		bg = T.sidebar_tone,
		border_sides = { 0, 1, 0, 0 },
		border_color = T.border,
		ui.row {
			h = "$zeron.titlebar.height",
			w_full = true,
			shrink = 0,
			pl = "$zeron.lights_inset",
			items = "center",
			window_drag = true,
		},
		ctx.on_back and ui.button {
			id = "settings_back",
			label = "Back",
			h = 32,
			shrink = 0,
			px = "$zeron.space.8",
			py = 0,
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.8",
			bg = T.clear,
			color = T.secondary,
			hover = { bg = T.glass_hover, color = T.text },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ctx.on_back,
			icon { name = "arrow-left", size = 16, color = "currentColor" },
			txt.text { "Back", size = "md", color = "inherit", line = false },
		},
		ui.row { w_full = true, pt = "$zeron.space.8", shrink = 0, search.field(props) },
		ui.presence(function(): boolean
			return search.searching()
		end, function(searching: boolean): Node
			return if searching then search.results(props) else nav_list(ctx)
		end, { w_full = true, grow = 1, min_h = 0 }),
	}
end

-- ⌘F in Settings: the search field.
M.focus_search = search.focus
-- Settings opened: the sections, no query.
M.reset_search = search.reset

-- The page: the sections and the chosen one's cards, filling its box.
function M.view(ctx: Context): Node
	return ui.row {
		w_full = true,
		h_full = true,
		nav(ctx),
		ui.column {
			grow = 1,
			h_full = true,
			min_w = 0,
			on_mount = search.mount("frame"),
			ui.row {
				h = "$zeron.titlebar.height",
				w_full = true,
				shrink = 0,
				window_drag = true,
				on_mount = search.mount("top"),
			},
			ui.presence(ctx.section, function(id: string): Node
				local offset = ui.use_state(0)
				search.page_offset(offset)
				return scroll {
					id = `settings_page_{id}`,
					label = "Settings",
					grow = 1,
					w_full = true,
					px = "$zeron.space.32",
					fade = 24,
					offset = offset,
					ui.column {
						w_full = true,
						relative = true,
						pb = "$zeron.space.48",
						on_mount = search.mount("content"),
						search.glow(),
						(PAGES[id] or general)(ctx),
					},
				}
			end, { grow = 1, w_full = true, min_h = 0 }),
		},
	}
end

return M
