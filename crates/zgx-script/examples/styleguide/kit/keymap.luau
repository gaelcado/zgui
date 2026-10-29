-- Rebindable shortcuts (settings.rs KeymapConfig, settings/shortcuts.rs):
-- each binding's combo stored as Zeron stores it, platform-neutral
-- ("mod-shift-a": Command on macOS, Control elsewhere), the defaults
-- unless changed; a key event matched against them; recording a new
-- combo, refused while another binding has it.
local M = {}

export type Binding = {
	id: string,
	label: string,
	-- The section its row shows under.
	group: string,
	default: string,
	-- A line under its label.
	meta: string?,
}
export type Keymap = {
	bindings: { Binding },
	by_id: { [string]: Binding },
	-- The combos changed from their defaults, by binding (kept across runs
	-- when the app gives a `ui.persist`).
	custom: State<{ [string]: string }>,
	-- The binding being recorded ("" for none), and why the last combo
	-- recorded was refused.
	recording: State<string>,
	notice: State<string>,
}

-- macOS keeps Control apart from Command; elsewhere Control is the
-- primary modifier ("mod").
local platform = ui.shared("platform", ""):peek()
M.MAC = platform ~= "linux" and platform ~= "windows"

-- A keymap over `bindings`, its changes in `custom`; `name` names its
-- recording's state.
function M.new(name: string, bindings: { Binding }, custom: State<{ [string]: string }>): Keymap
	local by_id = {}
	for _, b in bindings do
		by_id[b.id] = b
	end
	return {
		bindings = bindings,
		by_id = by_id,
		custom = custom,
		recording = ui.state(`{name}_recording`, ""),
		notice = ui.state(`{name}_notice`, ""),
	}
end

-- Zeron's bindings (ShortcutId::ALL: its labels, sections and defaults).
M.ZERON = {
	{ id = "toggle_dictation", label = "Hold to dictate", group = "Voice", default = "mod-d" },
	{
		id = "capture_appshot",
		label = "Capture Appshot",
		group = "Appshots",
		default = if M.MAC then "ctrl-alt-space" else "mod-alt-space",
	},
	{ id = "random_wallpaper", label = "Random wallpaper", group = "Appearance", default = "mod-u" },
	{ id = "save_file", label = "Save file", group = "Files", default = "mod-s" },
	{ id = "browser_reload", label = "Reload browser page", group = "Browser", default = "mod-shift-r" },
	{ id = "toggle_sidebar", label = "Toggle left sidebar", group = "Panels", default = "mod-b" },
	{ id = "toggle_changes", label = "Toggle right sidebar", group = "Panels", default = "mod-r" },
	{ id = "toggle_files", label = "Toggle files panel", group = "Panels", default = "mod-e" },
	{ id = "toggle_terminal", label = "Toggle terminal", group = "Panels", default = "mod-j" },
	{ id = "new_session", label = "New session", group = "Sessions", default = "mod-n" },
	{ id = "new_project", label = "New project", group = "Projects", default = "mod-shift-n" },
	{ id = "open_model_picker", label = "Open model picker", group = "Sessions", default = "mod-/" },
	{
		id = "next_session",
		label = "Next session or right pane tab",
		group = "Sessions",
		-- Control-Tab everywhere (Command-Tab is the system's on macOS).
		default = if M.MAC then "ctrl-tab" else "mod-tab",
		meta = "Navigate within the focused pane.",
	},
	{
		id = "prev_session",
		label = "Previous session or right pane tab",
		group = "Sessions",
		default = if M.MAC then "ctrl-shift-tab" else "mod-shift-tab",
		meta = "Navigate within the focused pane.",
	},
	-- ⌘A is the composer's Select all.
	{ id = "archive_session", label = "Archive session", group = "Sessions", default = "mod-shift-a" },
} :: { Binding }
for n = 1, 9 do
	table.insert(
		M.ZERON,
		{ id = `jump_{n}`, label = `Jump to session {n}`, group = "Jump to session", default = `mod-{n}` }
	)
end
-- The Shortcuts page's sections, in order (GROUP_ORDER; Appshots and
-- Voice keep theirs on their own pages).
M.GROUPS = { "Appearance", "Files", "Browser", "Panels", "Sessions", "Projects", "Jump to session" }

-- Binding `id`'s combo (read where it changes).
function M.combo(km: Keymap, id: string): string
	local b = km.by_id[id]
	return km.custom:get()[id] or (b and b.default) or ""
end
function M.combo_now(km: Keymap, id: string): string
	local b = km.by_id[id]
	return km.custom:peek()[id] or (b and b.default) or ""
end

local KEYS: { [string]: string } = {
	ArrowLeft = "left",
	ArrowRight = "right",
	ArrowUp = "up",
	ArrowDown = "down",
	[" "] = "space",
	Spacebar = "space",
}
local MODIFIERS: { [string]: boolean } = {
	shift = true,
	control = true,
	ctrl = true,
	alt = true,
	option = true,
	meta = true,
	super = true,
	hyper = true,
	os = true,
	fn = true,
	capslock = true,
}

-- A key event as a combo (combo_from_keystroke): nil for a modifier alone.
function M.of_event(e: KeyEvent): string?
	local key = KEYS[e.key] or string.lower(e.key)
	if key == "" or MODIFIERS[key] then
		return nil
	end
	local parts: { string } = {}
	local primary = if M.MAC then e.meta else (e.ctrl or e.meta)
	if primary then
		table.insert(parts, "mod")
	end
	if M.MAC and e.ctrl then
		table.insert(parts, "ctrl")
	end
	if e.alt then
		table.insert(parts, "alt")
	end
	if e.shift then
		table.insert(parts, "shift")
	end
	table.insert(parts, key)
	return table.concat(parts, "-")
end

-- A combo's modifiers and its key ("mod-shift--" is Shift and the minus).
local function split(combo: string): ({ [string]: boolean }, string)
	local mods: { [string]: boolean } = {}
	local rest = combo
	while true do
		local m, tail = string.match(rest, "^(%a+)%-(.+)$")
		if m and (m == "mod" or m == "ctrl" or m == "alt" or m == "shift") then
			mods[m] = true
			rest = tail :: string
		else
			break
		end
	end
	return mods, rest
end

local function key_name(key: string): string
	return string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
end

-- As the settings show a combo (display_combo): "Cmd+Shift+A".
function M.display(combo: string): string
	if combo == "" then
		return "None"
	end
	local mods, key = split(combo)
	local parts: { string } = {}
	if mods.mod then
		table.insert(parts, if M.MAC then "Cmd" else "Ctrl")
	end
	if mods.ctrl then
		table.insert(parts, "Ctrl")
	end
	if mods.alt then
		table.insert(parts, if M.MAC then "Opt" else "Alt")
	end
	if mods.shift then
		table.insert(parts, "Shift")
	end
	table.insert(parts, key_name(key))
	return table.concat(parts, "+")
end

-- As key caps (badge_combo): macOS's glyphs in ⌃⌥⇧⌘ order, then the key.
function M.caps(combo: string): { string }
	local mods, key = split(combo)
	local out: { string } = {}
	if not M.MAC then
		for part in string.gmatch(M.display(combo), "[^+]+") do
			table.insert(out, part)
		end
		return out
	end
	for _, m in { { "ctrl", "⌃" }, { "alt", "⌥" }, { "shift", "⇧" }, { "mod", "⌘" } } do
		if mods[m[1]] then
			table.insert(out, m[2])
		end
	end
	table.insert(out, key_name(key))
	return out
end

-- The binding `e` presses, if any.
function M.bound(km: Keymap, e: KeyEvent): string?
	local combo = M.of_event(e)
	if not combo then
		return nil
	end
	local custom = km.custom:peek()
	for _, b in km.bindings do
		if (custom[b.id] or b.default) == combo then
			return b.id
		end
	end
	return nil
end
function M.is(km: Keymap, id: string, e: KeyEvent): boolean
	local combo = M.of_event(e)
	return combo ~= nil and combo ~= "" and combo == M.combo_now(km, id)
end

-- The keys a global shortcut can end in (appshots/shortcut.rs Shortcut::parse).
local GLOBAL_KEYS: { [string]: boolean } = {}
for _, k in
	{
		"space",
		"tab",
		"enter",
		"backspace",
		"delete",
		"insert",
		"up",
		"down",
		"left",
		"right",
		"home",
		"end",
		"pageup",
		"pagedown",
	}
do
	GLOBAL_KEYS[k] = true
end
-- Whether `combo` can be registered system-wide: Control, Option or
-- Command (Control or Alt elsewhere) with a letter, a digit, F1 to F20 or a
-- navigation key.
function M.global(combo: string): boolean
	local mods, key = split(combo)
	local f = tonumber(string.match(key, "^f(%d+)$"))
	local supported = string.match(key, "^%w$") ~= nil or GLOBAL_KEYS[key] == true or (f ~= nil and f >= 1 and f <= 20)
	return supported and (mods.mod or mods.ctrl or mods.alt) == true
end

-- Why `combo` cannot be bound to `id`, if it cannot (refusal): Appshots'
-- shortcut must work system-wide; the composer keeps ⌘↩; another binding
-- that has it is named.
function M.refusal(km: Keymap, id: string, combo: string): string?
	if id == "capture_appshot" and not M.global(combo) then
		return `Use {if M.MAC then "Control, Option or Command" else "Control or Alt"} with a letter, number, function key or navigation key.`
	end
	if combo == "mod-enter" then
		return `{M.display(combo)} is reserved for the composer.`
	end
	for _, b in km.bindings do
		if b.id ~= id and M.combo_now(km, b.id) == combo then
			local page = if b.group == "Voice" or b.group == "Appshots" then ` in Settings → {b.group}` else ""
			return `{M.display(combo)} is already assigned to {b.label}{page}.`
		end
	end
	return nil
end

-- Binding `id` at `combo`; at its default, it keeps no combo of its own.
function M.set(km: Keymap, id: string, combo: string)
	local b = km.by_id[id]
	local custom = table.clone(km.custom:peek())
	custom[id] = if b and combo == b.default then nil else combo
	km.custom:set(custom)
end
function M.reset(km: Keymap, id: string)
	km.recording:set("")
	local b = km.by_id[id]
	M.set(km, id, if b then b.default else "")
end
function M.restore(km: Keymap)
	km.recording:set("")
	km.notice:set("")
	km.custom:set {}
end
-- Whether any binding has a combo of its own (read where it changes).
function M.customised(km: Keymap): boolean
	return next(km.custom:get()) ~= nil
end

function M.start(km: Keymap, id: string)
	km.notice:set("")
	km.recording:set(id)
end
function M.stop(km: Keymap, id: string)
	if km.recording:peek() == id then
		km.recording:set("")
	end
end

-- A key while `id` records (record_key): Escape cancels, a modifier alone
-- waits, a combo lands unless another binding has it.
function M.record(km: Keymap, id: string, e: KeyEvent): boolean
	if km.recording:peek() ~= id then
		return false
	end
	if e.key == "Escape" and not (e.meta or e.ctrl or e.alt or e.shift) then
		km.recording:set("")
		return true
	end
	local combo = M.of_event(e)
	if not combo then
		return true
	end
	km.recording:set("")
	local refused = M.refusal(km, id, combo)
	if refused then
		km.notice:set(refused)
	else
		km.notice:set("")
		M.set(km, id, combo)
	end
	return true
end

return M
