-- How the window looks, as Zeron's appearance settings choose it: a theme
-- (a family and its dark or light variant, or the system's), an accent (the
-- theme's, or one of Zeron's presets with a dark and a light colour), and
-- the surface (the theme's own, Frosted or Opaque: theme/src/lib.rs
-- SurfacePreference), and whether surfaces wear the double border. The app
-- puts `M.scope(look)` on its root: the accent's derived tokens and the
-- surface's are token expressions the engine resolves (and follows through
-- theme changes), not colours worked out here.
local appearance = require("./appearance")
local segmented = require("./segmented")
local THEMES = require("./theme_list")

export type Mode = "system" | "light" | "dark"
export type Surface = "theme" | "frosted" | "opaque"
export type Accent = { id: string, label: string, dark: string?, light: string? }
export type Look = {
	family: State<string>,
	mode: State<Mode>,
	accent: State<string>,
	surface: State<Surface>,
	-- The double border on panels, panes and wells (recipes `rim`).
	rim: State<boolean>,
}

local M = {}

M.THEMES = THEMES

-- Zeron's presets (theme/src/lib.rs), and the theme's own.
M.ACCENTS = {
	{ id = "theme", label = "Theme" },
	{ id = "zeron", label = "Zeron", dark = "#8b7cf6", light = "#5b43e8" },
	{ id = "orange", label = "Orange", dark = "#fb923c", light = "#c2410c" },
	{ id = "amber", label = "Amber", dark = "#fbbf24", light = "#a16207" },
	{ id = "green", label = "Green", dark = "#4ade80", light = "#15803d" },
	{ id = "cyan", label = "Cyan", dark = "#22d3ee", light = "#0e7490" },
	{ id = "blue", label = "Blue", dark = "#60a5fa", light = "#2563eb" },
	{ id = "pink", label = "Pink", dark = "#f472b6", light = "#be185d" },
} :: { Accent }

M.SURFACES = {
	{ id = "theme", label = "Theme" },
	{ id = "frosted", label = "Frosted" },
	{ id = "opaque", label = "Opaque" },
} :: { segmented.Option }

local function entry(id: string): typeof(THEMES[1])
	for _, t in THEMES do
		if t.id == id then
			return t
		end
	end
	return THEMES[1]
end

-- The family's variant of `kind`, else Zeron's.
local function variant(family: string, kind: "dark" | "light"): string
	for _, t in THEMES do
		if t.family == family and t.kind == kind then
			return t.id
		end
	end
	return if kind == "dark" then "zeron-dark" else "zeron-light"
end

-- Whether the window shows a dark theme now.
function M.is_dark(): boolean
	return entry(ui.theme.current:get()).kind == "dark"
end

-- A look named under `prefix` (it lasts across reloads), and the theme it
-- picks, applied to the window as it changes (unless `apply` is false: a
-- specimen of the settings that must not restyle the window).
function M.new(prefix: string, family: string?, mode: Mode?, apply: boolean?): Look
	local look: Look = {
		family = ui.state(`{prefix}_family`, family or "zeron"),
		mode = ui.state(`{prefix}_mode`, mode or "dark" :: Mode),
		accent = ui.state(`{prefix}_accent`, "theme"),
		surface = ui.state(`{prefix}_surface`, "theme" :: Surface),
		rim = ui.state(`{prefix}_rim`, true),
	}
	if apply == false then
		return look
	end
	ui.effect(function()
		local f, m = look.family:get(), look.mode:get()
		if m == "system" then
			ui.theme.follow_system { dark = variant(f, "dark"), light = variant(f, "light") }
		else
			ui.theme.follow_system(false)
			ui.theme.set(variant(f, m))
		end
	end)
	return look
end

-- Show theme `id`: its family, in its own kind.
function M.choose(look: Look, id: string)
	local t = entry(id)
	look.family:set(t.family)
	look.mode:set(t.kind)
end

-- Whether theme `id` is the one showing.
function M.showing(id: string): boolean
	return ui.theme.current:get() == id
end

local function luminance(hex: string): number
	local function lin(v: number): number
		v = v / 255
		return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	local r = tonumber(string.sub(hex, 2, 3), 16) or 0
	local g = tonumber(string.sub(hex, 4, 5), 16) or 0
	local b = tonumber(string.sub(hex, 6, 7), 16) or 0
	return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

-- The label for a fill: black or white, whichever reads better on it.
function M.label_on(fill: string): string
	return if luminance(fill) > 0.179 then "#000000" else "#ffffff"
end

-- The accent's colour now: the preset's for this kind, or nil (the theme's).
function M.preset(look: Look): string?
	local id = look.accent:get()
	local dark = M.is_dark()
	for _, a in M.ACCENTS do
		if a.id == id and a.dark and a.light then
			return if dark then a.dark else a.light
		end
	end
	return nil
end

-- Whether surfaces are frosted now: the surface chosen, or the theme's own
-- (SurfacePreference::resolve; Zeron's themes are frosted, the rest opaque).
function M.frosted(look: Look): boolean
	local s = look.surface:get()
	if s == "theme" then
		return entry(ui.theme.current:get()).frosted == true
	end
	return s == "frosted"
end

-- The surfaces' tokens in each mode, as theme.rs maps them: the window's
-- glass (`glass`: the shell at 80% frosted, the shell itself opaque), the
-- panels (`panel_bg`: the background at 40%, or solid), the floating cards
-- (`popover::surface_bg`: a faint tint over a blur and no shadow frosted,
-- the overlay with the large shadow opaque), the composer's edge
-- (`composer_surface_border`). theme.luau's defaults are dark frost's.
local FROSTED_LIGHT: { [string]: any } = {
	["zeron.frost"] = "alpha({surface.overlay}, 0.45)",
	["zeron.input.border"] = "alpha(#43515e, 0.10)",
}
local OPAQUE: { [string]: any } = {
	["glass.tint"] = "{surface.base}",
	["zeron.frost"] = "{surface.overlay}",
	["zeron.blur"] = 0,
	["zeron.float_shadow"] = "{shadow.lg}",
	["zeron.panel"] = "{background}",
	["zeron.pane"] = "{surface.sunken}",
	["zeron.well.bg"] = "{background}",
	["zeron.grip"] = "{surface.raised}",
	["zeron.input.border"] = "{border}",
}
-- Opaque inputs are the theme's input flattened on the page
-- (input_glass_bg): dark themes' raised at 72%, light themes' card as is.
local OPAQUE_DARK_INPUT = "mix({background}, {surface.raised}, 0.72)"
-- The double border in each kind and mode: the hairline outside, the lit
-- rim inside (ring and top band), dimmer out of focus, a flush panel's
-- inner line. Dark glass lights it faintly; daylight with white.
type Rim = { edge: string, light: string, light_dim: string, side: string }
local RIM: { [string]: Rim } = {
	dark_frosted = {
		edge = "alpha(#000000, 0.32)",
		light = "0 0 0 2 alpha(#ffffff, 0.07), 0 2 0 0 alpha(#ffffff, 0.1)",
		light_dim = "0 0 0 2 alpha(#ffffff, 0.035), 0 2 0 0 alpha(#ffffff, 0.05)",
		side = "2 0 0 0 alpha(#ffffff, 0.04)",
	},
	dark_opaque = {
		edge = "alpha(#000000, 0.45)",
		light = "0 0 0 2 alpha(#ffffff, 0.045), 0 2 0 0 alpha(#ffffff, 0.05)",
		light_dim = "0 0 0 2 alpha(#ffffff, 0.025), 0 2 0 0 alpha(#ffffff, 0.025)",
		side = "2 0 0 0 alpha(#ffffff, 0.03)",
	},
	light_frosted = {
		edge = "alpha(#000000, 0.11)",
		light = "0 0 0 2 alpha(#ffffff, 0.75), 0 2 0 0 alpha(#ffffff, 0.6)",
		light_dim = "0 0 0 2 alpha(#ffffff, 0.4), 0 2 0 0 alpha(#ffffff, 0.3)",
		side = "2 0 0 0 alpha(#ffffff, 0.6)",
	},
	light_opaque = {
		edge = "alpha(#000000, 0.12)",
		light = "0 0 0 2 alpha(#ffffff, 0.9), 0 2 0 0 alpha(#ffffff, 0.8)",
		light_dim = "0 0 0 2 alpha(#ffffff, 0.5), 0 2 0 0 alpha(#ffffff, 0.4)",
		side = "2 0 0 0 alpha(#ffffff, 0.8)",
	},
}
M.RIM = RIM

-- The root's theme scope: the surface's fills and the double border, the
-- accent preset and what derives from it (AccentRoles::derive).
function M.scope(look: Look): () -> { [string]: any }
	return function()
		local out: { [string]: any } = { theme = ui.theme.current:get() }
		local dark = M.is_dark()
		local frosted = M.frosted(look)
		if not frosted then
			for k, v in OPAQUE do
				out[k] = v
			end
			if dark then
				out["input.bg"] = OPAQUE_DARK_INPUT
			end
		elseif not dark then
			for k, v in FROSTED_LIGHT do
				out[k] = v
			end
		end
		local rim = RIM[`{if dark then "dark" else "light"}_{if frosted then "frosted" else "opaque"}`]
		out["zeron.rim.edge"] = rim.edge
		if look.rim:get() then
			out["zeron.rim.light"] = rim.light
			out["zeron.rim.light_dim"] = rim.light_dim
			out["zeron.rim.side"] = rim.side
		else
			out["zeron.rim.light"] = "none"
			out["zeron.rim.light_dim"] = "none"
			out["zeron.rim.side"] = "none"
		end
		-- The accent's roles derive from the accent, the theme's own or a
		-- preset (AccentRoles::derive), as Zeron does for every theme: an
		-- imported theme's selection and menu colours are not used.
		local function a(d: number, l: number): string
			return `alpha(\{accent}, {if dark then d else l})`
		end
		local primary = M.preset(look)
		if primary then
			out.accent = primary
			out["accent.text"] = M.label_on(primary)
			out["accent.hover"] = if dark then "mix({accent}, #ffffff, 0.28)" else "mix({accent}, {background}, 0.18)"
		end
		out.selection = a(0.35, 0.24)
		-- What is pressed or active (a button held, the chosen row or tab)
		-- is a UI wash, the text colour faintly, never the accent's.
		out.pressed = "{zeron.glass.active}"
		out["zeron.accent.wash"] = a(0.22, 0.12)
		out["zeron.accent.selection"] = a(0.35, 0.24)
		out["zeron.code.wash"] = a(0.22, 0.12)
		out["zeron.diff.hunk"] = a(0.08, 0.07)
		out["zeron.accent_faint"] = a(0.05, 0.05)
		out["zeron.accent.light"] = "mix({accent}, #ffffff, 0.18)"
		return out
	end
end

-- The accent presets as swatches, each in its colour for the theme's kind.
function M.swatches(look: Look, id: string): Node
	return ui.presence(function()
		return if M.is_dark() then "dark" else "light"
	end, function(): Node
		local dark = M.is_dark()
		local list: { appearance.Swatch } = {}
		for _, a in M.ACCENTS do
			table.insert(list, {
				id = a.id,
				label = a.label,
				color = if a.dark and a.light
					then ui.raw(if dark then a.dark else a.light, "an accent preset, shown as itself")
					else nil,
			})
		end
		return appearance.swatches { id = id, value = look.accent, swatches = list }
	end)
end

return M
