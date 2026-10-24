-- Zeron's settings page (settings/*.rs): its sections down the left under
-- their groups, Back above them, in a column as wide as the app's sidebar
-- and toned as it is; each section a column of cards 760 wide at most, on
-- the window's glass. The app gives it its preferences and what the pages
-- show of it (the layout, the archived sessions, the sidebar's width); the
-- workbench shows the same page.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local button = require("./button")
local wash = require("./wash")
local scroll = require("./scroll")
local settings = require("./settings")
local appearance = require("./appearance")
local look_mod = require("./look")
local menu = require("./menu")
local segmented = require("./segmented")
local shortcut = require("./shortcut")
local account = require("./account")
local recipes = require("./recipes")
local L = require("./panel_layout")

-- The preferences the pages hold.
export type Prefs = {
	sounds: State<boolean>,
	confirm_quit: State<boolean>,
	naming: State<string>,
	send: State<string>,
	dictation: State<boolean>,
	model_chip: State<boolean>,
	notify_done: State<boolean>,
	notify_input: State<boolean>,
	notify_failed: State<boolean>,
	notify_focus: State<boolean>,
	density: State<string>,
	worktrees: State<boolean>,
	-- Voice (dictation/model.rs).
	microphone: State<string>,
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
	-- The window's wallpaper (settings/wallpaper.rs): a folder, an effect.
	wallpaper: State<string>,
	wallpaper_effect: State<string>,
	-- The new-session canvas's artwork (an image's path; "" for none).
	canvas_background: State<string>,
}
export type Archived = { title: string, project: string, ago: string }
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
	on_back: (Handler | Action)?,
	-- Signing out (the app's onboarding from its start).
	on_sign_out: Handler?,
	-- The app's sidebar width, which the sections' column takes (Zeron's
	-- settings.sidebar_width, shared by both); the default sidebar's else.
	sidebar_width: (() -> number)?,
}

local M = {}

M.WIDTH = settings.WIDTH
-- What "Choose…" picks for the new-session background until the host's
-- file dialog is wired.
M.SAMPLE_BACKGROUND = "images/shadow.jpg"

type Section = { id: string, title: string, icon: string, group: string }
M.SECTIONS = {
	{ id = "general", title = "General", icon = "settings-minimalistic", group = "App" },
	{ id = "appearance", title = "Appearance", icon = "palette", group = "App" },
	{ id = "composer", title = "Composer", icon = "pen-new-square", group = "App" },
	{ id = "notifications", title = "Notifications", icon = "bell", group = "App" },
	{ id = "voice", title = "Voice", icon = "microphone", group = "App" },
	{ id = "shortcuts", title = "Shortcuts", icon = "keyboard", group = "App" },
	{ id = "accounts", title = "Accounts", icon = "key-minimalistic", group = "Agents" },
	{ id = "harnesses", title = "Harnesses", icon = "bot", group = "Agents" },
	{ id = "devices", title = "Devices", icon = "laptop", group = "Agents" },
	{ id = "worktrees", title = "Worktrees", icon = "worktree", group = "Agents" },
	{ id = "files", title = "Files", icon = "folder-with-files", group = "Data" },
	{ id = "appshots", title = "Appshots", icon = "gallery", group = "Data" },
	{ id = "archived", title = "Archived", icon = "archive-minimalistic", group = "Data" },
} :: { Section }

-- A set of preferences at their defaults, named under `prefix` (they last
-- across reloads).
function M.prefs(prefix: string): Prefs
	local function s<T>(name: string, value: T): State<T>
		return ui.state(`{prefix}_{name}`, value)
	end
	return {
		sounds = s("sounds", true),
		confirm_quit = s("confirm_quit", true),
		naming = s("naming", "auto"),
		send = s("send", "enter"),
		dictation = s("dictation", true),
		model_chip = s("model_chip", true),
		notify_done = s("notify_done", true),
		notify_input = s("notify_input", true),
		notify_failed = s("notify_failed", true),
		notify_focus = s("notify_focus", false),
		density = s("density", "comfortable"),
		worktrees = s("worktrees", true),
		microphone = s("microphone", "System default"),
		autosave = s("autosave", true),
		autosave_delay = s("autosave_delay", "1 second"),
		word_wrap = s("word_wrap", false),
		hidden_files = s("hidden_files", false),
		appshots = s("appshots", true),
		appshot_sound = s("appshot_sound", true),
		appshot_destination = s("appshot_destination", "Automatic"),
		dollar_skills = s("dollar_skills", true),
		separate_commands = s("separate_commands", false),
		wallpaper = s("wallpaper", ""),
		wallpaper_effect = s("wallpaper_effect", "None"),
		canvas_background = s("canvas_background", ""),
	}
end

local function page(title: string, description: string, ...: Node): Node
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.32",
		settings.header { title = title, description = description },
		{ ... },
	}
end

-- A select of named choices (widgets::select): the value in a 32-high
-- field, its menu under it, checked at the chosen one; a choice's detail
-- muted after it.
type Choice = { label: string, detail: string? }
local function choose(id: string, value: State<string>, choices: { Choice }, w: number?): Node
	local open = ui.state(`{id}_open`, false)
	local items: { any } = {}
	for i, c in choices do
		table.insert(items, {
			id = `{id}_{i}`,
			label = c.label,
			detail = c.detail,
			checked = function()
				return value:get() == c.label
			end,
			on_click = function()
				value:set(c.label)
			end,
		})
	end
	return menu.menu {
		id = `{id}_menu`,
		open = open,
		w = math.max(w or 180, 220),
		items = items,
		anchor = settings.select {
			id = id,
			value = function()
				return value:get()
			end,
			w = w or 180,
			on_click = ui.toggle(open),
		},
	}
end

local function general(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"General",
		"How Zeron behaves on this device.",
		settings.section {
			title = "Sessions",
			settings.row {
				title = "Name new threads",
				meta = { "From the first message, or as you type them" },
				control = segmented {
					id = "pref_naming",
					size = "sm",
					value = pref.naming,
					options = { { id = "auto", label = "Automatically" }, { id = "manual", label = "Myself" } },
				},
			},
			settings.row {
				title = "Sounds",
				meta = { "A chime when an agent needs you" },
				control = settings.switch { value = pref.sounds },
			},
			settings.row {
				title = "Confirm before quitting",
				meta = { "While an agent is working" },
				control = settings.switch { value = pref.confirm_quit },
			},
		},
		(
				ctx.on_sign_out
					and settings.section {
						title = "Account",
						settings.row {
							title = "Sign out",
							meta = { "Back to the sign-in, as on a new device" },
							control = button {
								id = "settings_sign_out",
								label = "Sign out",
								size = "sm",
								variant = "secondary",
								on_click = ctx.on_sign_out,
							},
						},
					}
				or nil
			) :: any,
		settings.section {
			title = "Updates",
			settings.row {
				title = "Zeron v0.2.117",
				meta = { "An update is ready; it applies on restart" },
				control = button { label = "Restart", size = "sm", variant = "secondary" },
			},
		}
	)
end

-- The wallpaper's effects (settings.rs WallpaperEffect).
local WALLPAPER_EFFECTS: { Choice } = {
	{ label = "None", detail = "Shows the original artwork." },
	{ label = "Dither", detail = "Rebuilds the artwork with a dithered color palette." },
	{ label = "ASCII", detail = "Recreates the artwork with colored characters on black." },
	{ label = "Halftone", detail = "Recreates the artwork with colored print dots on black." },
	{ label = "Scanlines", detail = "Adds a pronounced horizontal display-line texture." },
}

local function appearance_page(ctx: Context): Node
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
	-- The theme families, each in the mode chosen.
	local families: { any } = {}
	local seen: { [string]: boolean } = {}
	for _, t in look_mod.THEMES do
		if not seen[t.family] then
			seen[t.family] = true
			table.insert(families, {
				id = `settings_theme_{t.family}`,
				label = t.family_name,
				checked = function()
					return ctx.look.family:get() == t.family
				end,
				on_click = function()
					ctx.look.family:set(t.family)
				end,
			})
		end
	end
	local function family_name(): string
		local f = ctx.look.family:get()
		for _, t in look_mod.THEMES do
			if t.family == f then
				return t.family_name
			end
		end
		return f
	end
	local themes_open = ui.state("settings_themes_open", false)
	local window: { Node } = {}
	if ctx.layouts and ctx.layout then
		table.insert(
			window,
			settings.row {
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
	table.insert(
		window,
		settings.row {
			title = "Density",
			meta = { "The space between rows and controls" },
			control = segmented {
				id = "pref_density",
				size = "sm",
				value = ctx.prefs.density,
				options = { { id = "compact", label = "Compact" }, { id = "comfortable", label = "Comfortable" } },
			},
		}
	)
	return page(
		"Appearance",
		"How Zeron looks on this device.",
		ui.column {
			gap = "$zeron.space.10",
			txt.text { "Theme", size = "md", color = T.secondary },
			ui.row { gap = "$zeron.space.16", modes },
		},
		ui.column {
			gap = "$zeron.space.10",
			txt.text { "Accent", size = "md", color = T.secondary },
			look_mod.swatches(ctx.look, "settings_accent"),
		},
		settings.section {
			title = "Colours and surfaces",
			settings.row {
				title = "Theme",
				meta = { "Each has a dark and a light variant" },
				control = menu.menu {
					id = "settings_themes",
					open = themes_open,
					w = 220,
					max_h = 320,
					items = families,
					anchor = settings.select {
						id = "settings_theme",
						value = family_name,
						w = 180,
						on_click = ui.toggle(themes_open),
					},
				},
			},
			settings.row {
				title = "Surfaces",
				meta = { "Frosted lets the window's blur show through; Opaque never" },
				control = segmented {
					id = "settings_surface",
					size = "sm",
					value = ctx.look.surface :: any,
					options = look_mod.SURFACES,
				},
			},
			settings.row {
				title = "Double border",
				meta = { "A lit rim inside the hairline of panels, panes and wells" },
				control = settings.switch { id = "settings_rim", value = ctx.look.rim },
			},
		},
		settings.section {
			title = "Wallpaper",
			settings.row {
				title = "Folder",
				meta = {
					function()
						local f = ctx.prefs.wallpaper:get()
						return if f == "" then "Pictures from a folder of your own, behind the window" else f
					end,
				},
				control = button {
					id = "settings_wallpaper_folder",
					label = "Choose…",
					size = "sm",
					variant = "secondary",
					on_click = function()
						ctx.prefs.wallpaper:set("~/Pictures/Wallpapers")
					end,
				},
			},
			settings.row {
				title = "Effect",
				meta = {
					function()
						for _, e in WALLPAPER_EFFECTS do
							if e.label == ctx.prefs.wallpaper_effect:get() then
								return e.detail or ""
							end
						end
						return ""
					end,
				},
				control = choose("settings_wallpaper_effect", ctx.prefs.wallpaper_effect, WALLPAPER_EFFECTS, 148),
			},
			settings.row {
				title = "New session background",
				meta = { "Artwork over the new-session canvas, fading toward the composer" },
				control = ui.row {
					gap = "$zeron.space.6",
					items = "center",
					ui.show(
						function()
							return ctx.prefs.canvas_background:get() ~= ""
						end,
						button {
							id = "settings_canvas_background_remove",
							label = "Remove",
							size = "sm",
							variant = "ghost",
							on_click = function()
								ctx.prefs.canvas_background:set("")
							end,
						}
					),
					button {
						id = "settings_canvas_background",
						label = "Choose…",
						size = "sm",
						variant = "secondary",
						on_click = function()
							ctx.prefs.canvas_background:set(M.SAMPLE_BACKGROUND)
						end,
					},
				},
			},
			settings.row {
				title = "Random wallpaper",
				meta = { "Another picture from the folder" },
				control = shortcut.chip { keys = "Cmd+U" },
			},
		},
		settings.section { title = "Window", window }
	)
end

local function composer(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"Composer",
		"How you write to agents.",
		settings.section {
			title = "Sending",
			settings.row {
				title = "Send with",
				meta = { "The other key adds a line" },
				control = segmented {
					id = "pref_send",
					size = "sm",
					value = pref.send,
					options = { { id = "enter", label = "↩" }, { id = "cmd_enter", label = "⌘↩" } },
				},
			},
			settings.row {
				title = "Dictation",
				meta = { "⌘D records until you stop it; audio never leaves the device" },
				control = settings.switch { value = pref.dictation },
			},
			settings.row {
				title = "Model chip",
				meta = { "Show the model and its effort in the composer" },
				control = settings.switch { value = pref.model_chip },
			},
		}
	)
end

local function notifications(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"Notifications",
		"When Zeron tells you about an agent.",
		settings.section {
			title = "Notify me when",
			settings.row { title = "An agent finishes", control = settings.switch { value = pref.notify_done } },
			settings.row { title = "An agent needs input", control = settings.switch { value = pref.notify_input } },
			settings.row { title = "A run fails", control = settings.switch { value = pref.notify_failed } },
			settings.row {
				title = "Even while Zeron is focused",
				control = settings.switch { value = pref.notify_focus },
			},
		}
	)
end

local SHORTCUTS = {
	{ "Open the palette", "Panels", "Cmd+K" },
	{ "New session or tab", "Sessions", "Cmd+T" },
	{ "Toggle the sidebar", "Window", "Cmd+\\" },
	{ "Toggle Files", "Window", "Cmd+Shift+E" },
	{ "Split right", "Panes", "Cmd+D" },
	{ "Split down", "Panes", "Cmd+Shift+D" },
	{ "Close the pane or tab", "Panes", "Cmd+W" },
	{ "Zoom the pane", "Panes", "Cmd+Shift+Enter" },
	{ "Change the layout", "Window", "Cmd+Shift+L" },
	{ "Settings", "App", "Cmd+," },
}
local function shortcuts(): Node
	local rows: { Node } = {}
	for i, s in SHORTCUTS do
		table.insert(rows, shortcut.row { id = `settings_shortcut_{i}`, title = s[1], meta = { s[2] }, keys = s[3] })
	end
	return page(
		"Shortcuts",
		"Click a shortcut to record another.",
		ui.column { w_full = true, rounded = T.radius_card, bg = T.card, overflow = "hidden", rows }
	)
end

local function accounts(): Node
	return page(
		"Accounts",
		"The plans your agents run on, and what is left of them.",
		wash.list {
			group = "settings_accounts",
			w_full = true,
			gap = "$zeron.space.4",
			account.row {
				group = "settings_accounts",
				email = "cado.gael@gmail.com",
				initial = "G",
				active = true,
				session = 0.37,
				weekly = 0.84,
			},
			account.row {
				group = "settings_accounts",
				email = "work@zeron.sh",
				initial = "Z",
				session = 0.12,
				weekly = 0.4,
			},
		},
		ui.row { button { label = "Add an account", size = "sm", variant = "secondary", icon = { name = "plus" } } }
	)
end

local function harnesses(ctx: Context): Node
	local rows: { Node } = {}
	type Harness = { name: string, version: string, connected: boolean }
	local list: { Harness } = {
		{ name = "Claude Code", version = "v2.1.308", connected = true },
		{ name = "Codex", version = "v0.164.0", connected = true },
		{ name = "Cursor", version = "v1.7.2", connected = false },
		{ name = "OpenCode", version = "not installed", connected = false },
	}
	for _, h in list do
		table.insert(
			rows,
			settings.row {
				title = h.name,
				meta = { h.version },
				control = if h.connected
					then settings.badge("Connected")
					else button { label = "Connect", size = "sm", variant = "secondary" },
			}
		)
	end
	return page(
		"Harnesses",
		"The agents Zeron can run, on this device.",
		settings.card(rows :: any),
		-- Completion (settings/completion.rs): how skills are offered.
		settings.section {
			title = "Completion",
			settings.row {
				title = "Use $ for skills",
				meta = { "Type $ in the composer to pick a skill." },
				control = settings.switch { id = "settings_dollar_skills", value = ctx.prefs.dollar_skills },
			},
			settings.row {
				title = "Separate / commands",
				meta = { "Keep skills out of the / menu." },
				control = settings.switch { id = "settings_separate_commands", value = ctx.prefs.separate_commands },
			},
		}
	)
end

local function devices(): Node
	return page(
		"Devices",
		"Where your sessions run.",
		settings.card {
			settings.row {
				title = "MacBook Pro",
				meta = { "This Mac", "online" },
				control = settings.badge("This device"),
			},
			settings.row { title = "Cloud", meta = { "xlarge", "starts on wake" }, control = settings.badge("Online") },
			settings.row {
				title = "Mac mini",
				meta = { "last seen 2 days ago" },
				control = button { label = "Remove", size = "sm", variant = "ghost" },
			},
		}
	)
end

-- Voice (dictation/model.rs): dictation, the microphone, the shortcut and
-- the on-device speech model.
local function voice(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"Voice",
		"Dictation runs on this device; audio never leaves it.",
		settings.section {
			title = "Dictation",
			settings.row {
				title = "Dictation",
				meta = { "Speak into the composer" },
				control = settings.switch { id = "settings_dictation", value = pref.dictation },
			},
			settings.row {
				title = "Microphone",
				control = choose("settings_microphone", pref.microphone, {
					{ label = "System default", detail = "MacBook Pro Microphone" },
					{ label = "MacBook Pro Microphone" },
					{ label = "USB Microphone" },
				}, 200),
			},
			settings.row {
				title = "Shortcut",
				meta = { "Hold to talk, release to transcribe" },
				control = shortcut.chip { keys = "Cmd+D" },
			},
			settings.row {
				title = "Speech model",
				meta = { "Parakeet v3", "640 MB" },
				control = button { id = "settings_speech_remove", label = "Remove", size = "sm", variant = "ghost" },
			},
		}
	)
end

-- Files (settings/files.rs): saving, wrapping, what the tree shows.
local function files(ctx: Context): Node
	local pref = ctx.prefs
	return page(
		"Files",
		"How the files panel edits and lists.",
		settings.section {
			title = "Editing",
			settings.row {
				title = "Autosave",
				meta = { "Save edits as you pause" },
				control = settings.switch { id = "settings_autosave", value = pref.autosave },
			},
			ui.show(
				function()
					return pref.autosave:get()
				end,
				settings.row {
					title = "Autosave delay",
					control = choose("settings_autosave_delay", pref.autosave_delay, {
						{ label = "Immediately" },
						{ label = "1 second" },
						{ label = "5 seconds" },
						{ label = "30 seconds" },
					}, 148),
				}
			),
			settings.row {
				title = "Word wrap",
				meta = { "Long lines wrap at the editor's width" },
				control = settings.switch { id = "settings_word_wrap", value = pref.word_wrap },
			},
		},
		settings.section {
			title = "Tree",
			settings.row {
				title = "Show hidden and ignored files",
				meta = { "Dotfiles and what .gitignore leaves out" },
				control = settings.switch { id = "settings_hidden_files", value = pref.hidden_files },
			},
		}
	)
end

-- Appshots (settings/appshots.rs): a window and its text, captured into a
-- composer for review, never sent on their own.
local APPSHOT_DESTINATIONS: { Choice } = {
	{
		label = "Automatic",
		detail = "Use the open session, or the new-session composer when no session is open.",
	},
	{
		label = "Last session",
		detail = "Use the open session, or return to the last session used for an Appshot.",
	},
	{
		label = "New session",
		detail = "Stage captures in a new-session composer, keeping existing drafts intact.",
	},
}
local function appshots(ctx: Context): Node
	local pref = ctx.prefs
	local function detail(): string
		for _, d in APPSHOT_DESTINATIONS do
			if d.label == pref.appshot_destination:get() then
				return d.detail or ""
			end
		end
		return ""
	end
	return page(
		"Appshots",
		"Capture a window and its text into the composer.",
		settings.section {
			title = "Capture",
			settings.row {
				title = "Capture Appshots",
				meta = { "Captures are staged for review and never sent automatically." },
				control = settings.switch { id = "settings_appshots", value = pref.appshots },
			},
			settings.row {
				title = "Capture sound",
				meta = { "Play a sound when an Appshot is ready." },
				control = settings.switch { id = "settings_appshot_sound", value = pref.appshot_sound },
			},
			settings.row {
				title = "Global shortcut",
				meta = { "Press Escape to cancel." },
				control = shortcut.chip { keys = "Ctrl+Alt+Space" },
			},
			settings.row {
				title = "Destination",
				meta = { detail },
				control = choose("settings_appshot_destination", pref.appshot_destination, APPSHOT_DESTINATIONS, 148),
			},
		},
		settings.section {
			title = "Permissions",
			settings.row {
				title = "Window capture",
				meta = { "Screen Recording, in System Settings" },
				control = settings.badge("Allowed"),
			},
			settings.row {
				title = "Application text",
				meta = { "Accessibility, in System Settings" },
				control = button {
					id = "settings_appshot_text",
					label = "Open System Settings",
					size = "sm",
					variant = "secondary",
				},
			},
		}
	)
end

local function worktrees(ctx: Context): Node
	return page(
		"Worktrees",
		"Agents can work in a checkout of their own.",
		settings.section {
			title = "New sessions",
			settings.row {
				title = "Start in a new worktree",
				meta = { "Beside the project, on a branch named for the session" },
				control = settings.switch { value = ctx.prefs.worktrees },
			},
		}
	)
end

local function archived(ctx: Context): Node
	local rows: { Node } = {}
	for _, s in ctx.archived or {} do
		table.insert(
			rows,
			settings.row {
				title = s.title,
				meta = { s.project, s.ago },
				control = button { label = "Unarchive", size = "sm", variant = "ghost" },
			}
		)
	end
	return page(
		"Archived",
		`{ctx.archived_total or #rows} archived sessions. Unarchiving puts one back in the sidebar.`,
		settings.card(rows :: any)
	)
end

local PAGES: { [string]: (ctx: Context) -> Node } = {
	general = general,
	appearance = appearance_page,
	composer = composer,
	notifications = notifications,
	voice = voice,
	shortcuts = shortcuts,
	accounts = accounts,
	harnesses = harnesses,
	files = files,
	appshots = appshots,
	devices = devices,
	worktrees = worktrees,
	archived = archived,
}

local function nav(ctx: Context): Node
	local rows: { Node } = {}
	local group = ""
	for _, s in M.SECTIONS do
		if s.group ~= group then
			group = s.group
			table.insert(
				rows,
				ui.row { h = 28, px = "$zeron.space.8", pt = "$zeron.space.8", items = "end", txt.eyebrow(s.group) }
			)
		end
		local function chosen(): boolean
			return ctx.section:get() == s.id
		end
		table.insert(
			rows,
			ui.button(wash.item("settings_nav", {
				id = `settings_nav_{s.id}`,
				w_full = true,
				h = 30,
				px = "$zeron.space.8",
				py = 0,
				gap = "$zeron.space.8",
				items = "center",
				rounded = "$zeron.radius.8",
				cursor = "pointer",
				focus = { border = 0 },
				variants = recipes.active_glass { selected = chosen },
				on_click = ui.set(ctx.section, s.id),
				icon { name = s.icon :: any, size = 14, color = T.secondary },
				txt.text { s.title, size = "md", line = false },
			}, chosen))
		)
	end
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
			pl = "$zeron.lights_inset",
			items = "center",
			window_drag = true,
		},
		ctx.on_back and ui.button {
			id = "settings_back",
			h = 30,
			px = "$zeron.space.8",
			py = 0,
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.8",
			bg = T.clear,
			hover = { bg = T.glass_hover },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ctx.on_back,
			icon { name = "arrow-left", size = 14, color = T.secondary },
			txt.text { "Back to the app", size = "md", color = T.secondary, line = false },
		},
		wash.list { group = "settings_nav", w_full = true, gap = "$zeron.space.2", rows },
	}
end

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
			ui.row { h = "$zeron.titlebar.height", w_full = true, shrink = 0, window_drag = true },
			ui.presence(ctx.section, function(id: string): Node
				return scroll {
					id = `settings_page_{id}`,
					label = "Settings",
					grow = 1,
					w_full = true,
					px = "$zeron.space.32",
					fade = 24,
					ui.column { w_full = true, pb = "$zeron.space.48", (PAGES[id] or general)(ctx) },
				}
			end, { grow = 1, w_full = true, min_h = 0 }),
		},
	}
end

return M
