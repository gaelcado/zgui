-- The theme library (settings/appearance.rs render_library_rows,
-- theme_library.rs): a card with "Theme library" and Add theme, the
-- imported copies then the linked themes under their headings, each with
-- its source, its variants and its path, and its actions in a row
-- (Reload and Unlink for a linked one, Reveal, Review, Duplicate as
-- editable, Remove). "Add a theme" analyses a source into its variants
-- (Import a copy or Link to source, each variant checked), "Theme mapping"
-- reviews how one was mapped. Sample themes until the engine compiles
-- them: a source's variants come from its name.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local button = require("./button")
local settings = require("./settings")
local dialog = require("./dialog")
local checkbox = require("./checkbox")

local M = {}

export type Source = "copy" | "linked_file" | "linked_package" | "editable"
export type Variant = { name: string, kind: "dark" | "light", colours: { string } }
export type Theme = {
	id: string,
	name: string,
	source: Source,
	path: string?,
	variants: { Variant },
	-- The last reload's failure, the last good version kept.
	failure: string?,
}

M.SOURCE_LABEL = {
	copy = "Imported",
	linked_file = "Linked file",
	linked_package = "Linked package",
	editable = "Editable file",
} :: { [Source]: string }

local function v(name: string, kind: "dark" | "light", bg: string, fg: string, accent: string): Variant
	return { name = name, kind = kind, colours = { bg, fg, accent } }
end

M.SAMPLE = {
	{
		id = "tokyo_night",
		name = "Tokyo Night",
		source = "copy",
		path = "~/Downloads/tokyo-night-1.0.6.vsix",
		variants = {
			v("Tokyo Night", "dark", "#1a1b26", "#a9b1d6", "#7aa2f7"),
			v("Tokyo Night Day", "light", "#e1e2e7", "#3760bf", "#2e7de9"),
		},
	},
	{
		id = "rose_pine",
		name = "Rosé Pine",
		source = "linked_package",
		path = "~/.vscode/extensions/mvllow.rose-pine-2.13.0/package.json",
		variants = {
			v("Rosé Pine", "dark", "#191724", "#e0def4", "#c4a7e7"),
			v("Rosé Pine Moon", "dark", "#232136", "#e0def4", "#c4a7e7"),
			v("Rosé Pine Dawn", "light", "#faf4ed", "#575279", "#907aa9"),
		},
	},
	{
		id = "studio",
		name = "Studio",
		source = "editable",
		path = "~/Library/Application Support/Zeron/custom-themes/studio.zeron-theme.json",
		variants = { v("Studio", "dark", "#101214", "#d7dadc", "#e5a50a") },
	},
} :: { Theme }

M.library = ui.state("theme_library", M.SAMPLE)
-- What the last action could not do (the page's warning under the card).
M.warning = ui.state("theme_library_warning", "")

local function linked(t: Theme): boolean
	return t.source == "linked_file" or t.source == "linked_package" or t.source == "editable"
end

local function update(id: string, change: (t: Theme) -> Theme?)
	local out: { Theme } = {}
	for _, t in M.library:peek() do
		if t.id == id then
			local now = change(table.clone(t))
			if now then
				table.insert(out, now)
			end
		else
			table.insert(out, t)
		end
	end
	M.library:set(out)
end

-- Reload a linked theme from its source: the editable sample's file has a
-- mistake in it, so its last good version stays.
function M.reload(id: string)
	update(id, function(t: Theme): Theme?
		t.failure = if t.source == "editable" then "expected `,` at line 42, column 7" else nil
		return t
	end)
end
function M.unlink(id: string)
	update(id, function(t: Theme): Theme?
		t.source = "copy"
		t.failure = nil
		return t
	end)
end
function M.remove(id: string)
	update(id, function(_t: Theme): Theme?
		return nil
	end)
end
function M.duplicate(id: string)
	local list = table.clone(M.library:peek())
	for _, t in list do
		if t.id == id then
			table.insert(
				list,
				{
					id = `{t.id}_copy`,
					name = `{t.name} Copy`,
					source = "editable",
					path = `~/Library/Application Support/Zeron/custom-themes/{string.gsub(t.id, "_", "-")}-copy.zeron-theme.json`,
					variants = t.variants,
				} :: Theme
			)
			break
		end
	end
	M.library:set(list)
end

-- The swatch: its background, text and accent side by side.
local function swatch(colours: { string }, w: number?, h: number?): Node
	local parts: { Node } = {}
	for _, c in colours do
		table.insert(parts, ui.div { grow = 1, h_full = true, bg = ui.raw(c, "a theme's own colour, shown as itself") })
	end
	return ui.row {
		w = w or 30,
		h = h or 18,
		shrink = 0,
		rounded = "$zeron.radius.4",
		overflow = "hidden",
		border = 1,
		border_color = T.hairline,
		parts,
	}
end

-- How a variant was mapped (theme report): its counts, then each line.
local function report(name: string): Node
	local lines = {
		"42 mapped · 3 adjusted · 5 inferred/fallback · 1 unsupported · 0 warnings · 0 validation",
		"Adjusted · text.secondary #6e6a86 → #7f7b98 · contrast under 4.5:1 on the background",
		"Adjusted · border.subtle #26233a → #2a2740 · too close to the surface",
		"Fallback · surface.overlay ← editor.background, lightened",
		"Unsupported · terminal.ansiBrightBlack",
		"accent ← focusBorder",
		"background ← editor.background",
		"text.primary ← editor.foreground",
	}
	local rows: { Node } = {}
	for _, l in lines do
		table.insert(rows, txt.text { l, literal = true, size = "xs", color = T.secondary, wrap = true })
	end
	return ui.scroll {
		id = `theme_report_{string.lower((string.gsub(name, "%W+", "_")))}`,
		w_full = true,
		max_h = 168,
		p = "$zeron.space.10",
		gap = "$zeron.space.4",
		rounded = "$zeron.radius.8",
		bg = T.ink1,
		rows,
	}
end

-- A variant's scene: its colours on a miniature, a line of code, its accent.
local function scene(variant: Variant): Node
	local bg, fg, accent = variant.colours[1], variant.colours[2], variant.colours[3]
	local raw = function(c: string): Color
		return ui.raw(c, "a theme's own colour, shown as itself")
	end
	return ui.row {
		w_full = true,
		h = 86,
		rounded = "$zeron.radius.8",
		overflow = "hidden",
		bg = raw(bg),
		px = "$zeron.space.12",
		gap = "$zeron.space.12",
		items = "center",
		ui.column {
			grow = 1,
			gap = "$zeron.space.4",
			txt.text { "fn preview() {", mono = true, size = "xs", color = raw(fg), line = false },
			txt.text { '    "Theme mapping"', mono = true, size = "xs", color = raw(accent), line = false },
			txt.text { "}", mono = true, size = "xs", color = raw(fg), line = false },
		},
		ui.row {
			gap = "$zeron.space.4",
			ui.div { w = 28, h = 14, rounded = "$zeron.radius.4", bg = raw(accent) },
			ui.div { w = 28, h = 14, rounded = "$zeron.radius.4", bg = T.success },
			ui.div { w = 28, h = 14, rounded = "$zeron.radius.4", bg = T.danger },
		},
	}
end

-- "Theme mapping": each variant's scene and report.
local reviewing = ui.state("theme_library_review", "")
local review_open = ui.state("theme_library_review_open", false)
local function review_dialog(): Node
	return ui.presence(function(): string?
		return if review_open:get() and reviewing:get() ~= "" then reviewing:get() else nil
	end, function(id: string): Node
		local theme: Theme? = nil
		for _, t in M.library:peek() do
			if t.id == id then
				theme = t
			end
		end
		local body: { Node } = {}
		if theme then
			for _, variant in theme.variants do
				table.insert(body, txt.text { variant.name, literal = true, size = "md", weight = "medium" })
				table.insert(body, scene(variant))
				table.insert(body, report(variant.name))
			end
		end
		local function close()
			review_open:set(false)
		end
		return dialog {
			id = "theme_review",
			open = review_open,
			title = "Theme mapping",
			description = if theme then `{theme.name} · {M.SOURCE_LABEL[theme.source]}` else nil,
			w = 660,
			on_enter = close,
			actions = {
				button { id = "theme_review_done", label = "Done", size = "sm", variant = "primary", on_click = close },
			},
			ui.scroll { w = 618, max_h = 520, gap = "$zeron.space.10", body },
		}
	end)
end

-- What a source holds (a sample analysis): its family from the file's
-- name (a package.json its folder's), Catppuccin's four flavours.
function M.analyse(path: string): (string?, { Variant })
	local trimmed = string.match(path, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return "Choose a local theme file or extension folder.", {}
	end
	local file = string.match(trimmed, "([^/]+)/?$") or trimmed
	if file == "package.json" then
		file = string.match(trimmed, "([^/]+)/package%.json$") or "Custom theme"
	end
	local stem = string.match(file, "^([^%.]+)") or file
	stem = string.gsub(stem, "%-%d[%d%.%-]*$", "")
	stem = string.gsub(stem, "^[%w]+%.", "")
	if string.find(string.lower(trimmed), "catppuccin", 1, true) then
		return nil,
			{
				v("Catppuccin Mocha", "dark", "#1e1e2e", "#cdd6f4", "#cba6f7"),
				v("Catppuccin Macchiato", "dark", "#24273a", "#cad3f5", "#c6a0f6"),
				v("Catppuccin Frappé", "dark", "#303446", "#c6d0f5", "#ca9ee6"),
				v("Catppuccin Latte", "light", "#eff1f5", "#4c4f69", "#8839ef"),
			}
	end
	local name = string.gsub(stem, "[-_]+(%w)", function(c: string): string
		return " " .. string.upper(c)
	end)
	name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
	if name == "" then
		name = "Custom theme"
	end
	return nil,
		{
			v(`{name} Dark`, "dark", "#16181d", "#d4d7dd", "#5aa9e6"),
			v(`{name} Light`, "light", "#f7f7f5", "#2b2d31", "#2f6fbf"),
		}
end

M.SAMPLE_SOURCE = "~/.vscode/extensions/catppuccin.catppuccin-vsc-3.16.0/package.json"

local add_open = ui.state("theme_library_add_open", false)

-- "Add a theme" (appearance.rs render_add_theme_dialog).
local function add_dialog(): Node
	return ui.presence(function(): boolean?
		return if add_open:get() then true else nil
	end, function(): Node
		local path = ui.use_state("")
		local link = ui.use_state(false)
		local found = ui.use_state({} :: { Variant })
		local chosen = ui.use_state({} :: { [string]: boolean })
		local open_details = ui.use_state("")
		local err = ui.use_state("")
		local analysed = ui.use_state("")
		-- Editing the source drops what was found.
		ui.effect(function()
			if path:get() ~= analysed:peek() then
				found:set {}
				err:set("")
			end
		end)
		local function analyse()
			analysed:set(path:peek())
			local e, variants = M.analyse(path:peek())
			if e then
				err:set(e)
				return
			end
			local all: { [string]: boolean } = {}
			for _, x in variants do
				all[x.name] = true
			end
			chosen:set(all)
			found:set(variants)
			err:set("")
		end
		local function picked(): { Variant }
			local out: { Variant } = {}
			for _, x in found:get() do
				if chosen:get()[x.name] then
					table.insert(out, x)
				end
			end
			return out
		end
		local function import()
			local variants = picked()
			if #variants == 0 then
				err:set("Select at least one variant to import.")
				return
			end
			local p = path:peek()
			local family = string.gsub(variants[1].name, " %S+$", "")
			local source: Source = if not link:peek()
				then "copy"
				elseif string.find(p, "package%.json$") then "linked_package"
				else "linked_file"
			local list = table.clone(M.library:peek())
			table.insert(
				list,
				{
					id = `{string.lower((string.gsub(family, "%W+", "_")))}_{#list + 1}`,
					name = family,
					source = source,
					path = p,
					variants = variants,
				} :: Theme
			)
			M.library:set(list)
			add_open:set(false)
		end
		local function primary()
			if #found:peek() == 0 then
				analyse()
			else
				import()
			end
		end
		local function choice(id: string, linking: boolean, title: string, detail: string): Node
			local function on(): boolean
				return link:get() == linking
			end
			return ui.button {
				id = id,
				role = "radio",
				checked = on,
				grow = 1,
				basis = 0,
				p = "$zeron.space.10",
				gap = "$zeron.space.10",
				items = "start",
				rounded = "$zeron.radius.9",
				border = 1,
				border_color = function(): Color
					return if on() then T.accent else T.border
				end,
				bg = T.clear,
				hover = { bg = T.ink1 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					link:set(linking)
				end,
				ui.row {
					w = 16,
					h = 16,
					shrink = 0,
					mt = "$zeron.space.1",
					rounded = T.radius_full,
					border = function(): number
						return if on() then 5 else 1
					end,
					border_color = function(): Color
						return if on() then T.accent else T.strong
					end,
				},
				ui.column {
					grow = 1,
					min_w = 0,
					gap = "$zeron.space.2",
					txt.text { title, size = "md", weight = "medium", line = false },
					txt.text { detail, size = "sm", color = T.secondary, wrap = true },
				},
			}
		end
		local function variant_row(x: Variant): Node
			local key = string.lower((string.gsub(x.name, "%W+", "_")))
			local value = ui.use_state(chosen:peek()[x.name] == true)
			ui.effect(function()
				local now = value:get()
				local all = table.clone(chosen:peek())
				if all[x.name] ~= now then
					all[x.name] = now
					chosen:set(all)
				end
			end)
			return ui.column {
				w_full = true,
				p = "$zeron.space.10",
				gap = "$zeron.space.10",
				rounded = "$zeron.radius.10",
				bg = T.ink1,
				ui.row {
					w_full = true,
					gap = "$zeron.space.10",
					items = "center",
					checkbox { id = `theme_add_pick_{key}`, value = value },
					swatch(x.colours),
					txt.text {
						x.name,
						literal = true,
						size = "md",
						weight = "medium",
						grow = 1,
						truncate = true,
						line = false,
					},
					txt.text {
						if x.kind == "dark" then "Dark" else "Light",
						size = "sm",
						color = T.tertiary,
						line = false,
					},
					button {
						id = `theme_add_details_{key}`,
						label = function()
							return if open_details:get() == x.name then "Hide details" else "Details"
						end,
						size = "sm",
						variant = "ghost",
						on_click = function()
							open_details:set(if open_details:peek() == x.name then "" else x.name)
						end,
					},
				},
				ui.show(function()
					return open_details:get() == x.name
				end, ui.column { w_full = true, gap = "$zeron.space.8", scene(x), report(x.name) }),
			}
		end
		return dialog {
			id = "theme_add",
			open = add_open,
			title = "Add a theme",
			description = "Import a local theme into your library or keep it linked to its source.",
			w = 600,
			on_enter = primary,
			actions = {
				button {
					id = "theme_add_cancel",
					label = "Cancel",
					size = "sm",
					variant = "ghost",
					on_click = function()
						add_open:set(false)
					end,
				},
				ui.column {
					opacity = function()
						return if #found:get() > 0 and #picked() == 0 then 0.45 else 1
					end,
					button {
						id = "theme_add_primary",
						label = function()
							return if #found:get() == 0 then "Analyze theme" else "Import selected"
						end,
						size = "sm",
						variant = "primary",
						disabled = function()
							return #found:get() > 0 and #picked() == 0
						end,
						on_click = primary,
					},
				},
			},
			ui.scroll {
				w = 558,
				max_h = 520,
				gap = "$zeron.space.16",
				ui.column {
					w_full = true,
					gap = "$zeron.space.8",
					txt.text { "Source", size = "sm", weight = "medium", color = T.secondary },
					ui.row {
						w_full = true,
						gap = "$zeron.space.8",
						ui.input {
							id = "theme_add_source",
							value = path,
							label = "Theme source",
							placeholder = "Theme file, package.json, or extension folder",
							placeholder_color = T.tertiary,
							grow = 1,
							min_w = 0,
							h = 36,
							px = "$zeron.space.12",
							rounded = "$zeron.radius.8",
							border = 1,
							border_color = T.border,
							bg = T.ink1,
							text_size = "$font.size.md",
							color = T.text,
							on_mount = function(el: Element)
								el:focus()
							end,
						},
						button {
							id = "theme_add_browse",
							label = "Browse…",
							size = "lg",
							variant = "secondary",
							on_click = function()
								path:set(M.SAMPLE_SOURCE)
								analyse()
							end,
						},
					},
				},
				ui.column {
					w_full = true,
					gap = "$zeron.space.8",
					txt.text { "Keep it up to date", size = "sm", weight = "medium", color = T.secondary },
					ui.row {
						w_full = true,
						gap = "$zeron.space.8",
						role = "radiogroup",
						choice("theme_add_copy", false, "Import a copy", "Works independently from the original file."),
						choice("theme_add_link", true, "Link to source", "Reload changes from the file on disk."),
					},
				},
				ui.presence(function(): string
					local names = {}
					for _, x in found:get() do
						table.insert(names, x.name)
					end
					return table.concat(names, "\n")
				end, function(): Node
					local variants = found:peek()
					if #variants == 0 then
						return ui.row {
							gap = "$zeron.space.6",
							items = "center",
							icon { name = "info-circle", size = 14, color = T.tertiary },
							txt.text {
								"Zeron finds light and dark variants automatically.",
								size = "sm",
								color = T.tertiary,
							},
						}
					end
					local rows: { Node } = {}
					for _, x in variants do
						table.insert(rows, variant_row(x))
					end
					return ui.column {
						w_full = true,
						gap = "$zeron.space.8",
						pt = "$zeron.space.8",
						border_sides = { 1, 0, 0, 0 },
						border_color = T.hairline,
						ui.row {
							w_full = true,
							justify = "between",
							pt = "$zeron.space.8",
							txt.text {
								"Detected themes",
								size = "sm",
								weight = "medium",
								color = T.secondary,
								line = false,
							},
							txt.text {
								`{#variants} variant{if #variants == 1 then "" else "s"}`,
								size = "sm",
								color = T.tertiary,
								line = false,
							},
						},
						rows,
					}
				end, { w_full = true }),
				ui.show(
					function()
						return err:get() ~= ""
					end,
					ui.row {
						id = "theme_add_error",
						w_full = true,
						px = "$zeron.space.12",
						py = "$zeron.space.8",
						gap = "$zeron.space.8",
						items = "center",
						rounded = "$zeron.radius.8",
						bg = T.danger_wash,
						icon { name = "danger-triangle", size = 14, color = T.danger },
						txt.text {
							function()
								return err:get()
							end,
							literal = true,
							size = "sm",
							color = T.danger,
							truncate = true,
							grow = 1,
						},
					}
				),
			},
		}
	end)
end

local function action(id: string, label: string, run: () -> (), danger: boolean?): Node
	return button {
		id = id,
		label = label,
		size = "sm",
		variant = if danger then "ghost_danger" else "outlined",
		on_click = run,
	}
end

local function row(t: Theme): Node
	local key = t.id
	local count = #t.variants
	local meta: { Text } = if t.failure
		then { `Using last known good · {t.failure}` }
		else {
			M.SOURCE_LABEL[t.source],
			`{count} variant{if count == 1 then "" else "s"}`,
			t.path or "Self-contained snapshot",
		}
	local actions: { Node } = {}
	if linked(t) then
		table.insert(
			actions,
			action(`theme_{key}_reload`, "Reload", function()
				M.reload(key)
			end)
		)
	end
	table.insert(
		actions,
		action(`theme_{key}_reveal`, "Reveal", function()
			if not t.path then
				M.warning:set("theme source has no location to reveal")
			end
		end)
	)
	table.insert(
		actions,
		action(`theme_{key}_review`, "Review", function()
			reviewing:set(key)
			review_open:set(true)
		end)
	)
	table.insert(
		actions,
		action(`theme_{key}_duplicate`, "Duplicate as editable", function()
			M.duplicate(key)
		end)
	)
	if linked(t) then
		table.insert(
			actions,
			action(`theme_{key}_unlink`, "Unlink", function()
				M.unlink(key)
			end)
		)
	end
	table.insert(
		actions,
		action(`theme_{key}_remove`, "Remove", function()
			M.remove(key)
		end, true)
	)
	return ui.column {
		id = `theme_{key}`,
		w_full = true,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		gap = "$zeron.space.8",
		ui.row {
			w_full = true,
			gap = "$zeron.space.10",
			items = "center",
			swatch(t.variants[1].colours),
			ui.column {
				grow = 1,
				min_w = 0,
				gap = "$zeron.space.2",
				txt.text { t.name, literal = true, size = "md", weight = "medium", line = false },
				txt.text {
					table.concat(meta :: { any }, " · "),
					literal = true,
					size = "xs",
					color = if t.failure then T.warning else T.secondary,
					truncate = true,
					line = false,
				},
			},
		},
		ui.row { gap = "$zeron.space.2", flex_wrap = true, actions },
	}
end

local function heading(label: string): Node
	return ui.row {
		w_full = true,
		px = "$zeron.space.16",
		pt = "$zeron.space.8",
		txt.text { label, size = "sm", color = T.secondary, line = false },
	}
end

-- The library's card, its dialogs, and the warning under it.
function M.card(): Node
	return ui.column {
		w_full = true,
		gap = "$zeron.space.8",
		ui.presence(function(): string
			local keys = {}
			for _, t in M.library:get() do
				table.insert(keys, `{t.id}:{t.source}:{t.failure or ""}`)
			end
			return table.concat(keys, "|")
		end, function(): Node
			local imported: { Node }, linked_rows: { Node } = {}, {}
			for _, t in M.library:peek() do
				table.insert(if linked(t) then linked_rows else imported, row(t))
			end
			local rows: { Node } = {
				settings.row {
					anchor = "theme_library",
					title = "Theme library",
					control = button {
						id = "theme_library_add",
						label = "Add theme",
						size = "sm",
						variant = "primary",
						on_click = function()
							add_open:set(true)
						end,
					},
				},
			}
			if #imported > 0 then
				table.insert(rows, ui.column { w_full = true, heading("Imported"), imported })
			end
			if #linked_rows > 0 then
				table.insert(rows, ui.column { w_full = true, heading("Linked"), linked_rows })
			end
			return settings.card { id = "theme_library", table.unpack(rows) }
		end, { w_full = true }),
		ui.show(
			function()
				return M.warning:get() ~= ""
			end,
			txt.text {
				function()
					return M.warning:get()
				end,
				id = "theme_library_warning",
				literal = true,
				size = "xs",
				color = T.warning,
			}
		),
		add_dialog(),
		review_dialog(),
	}
end

return M
