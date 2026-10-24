-- The workbench's state: which page shows and how the canvas shows it.
local panel_shell = require("@kit/panel_shell")

local look = require("@kit/look")

local M = {}

export type Page = { id: string, title: string, group: string, icon: string, blurb: string }

-- The sidebar's tree, in order: Foundations (tokens), Components (the
-- generic kit and its patterns), Zeron (its screens' surfaces), Windows
-- (the shell and the mini apps), Reference (parity with Zeron's numbers).
local PAGES: { Page } = {
	{
		id = "colour",
		title = "Colour",
		group = "Foundations",
		icon = "palette",
		blurb = "Every token in context, with its contrast.",
	},
	{
		id = "typography",
		title = "Typography",
		group = "Foundations",
		icon = "wrap-text",
		blurb = "Scale, weights, line heights, mono.",
	},
	{
		id = "icons",
		title = "Icons",
		group = "Foundations",
		icon = "widget",
		blurb = "Solar Linear and Zeron Icons, with the harness marks; 16 and 20.",
	},
	{
		id = "metrics",
		title = "Space, radius, shadow",
		group = "Foundations",
		icon = "tuning",
		blurb = "Spacing, radii, shadows, control heights.",
	},
	{
		id = "motion",
		title = "Motion",
		group = "Foundations",
		icon = "restart",
		blurb = "Curves, durations, the spring, fades.",
	},
	{
		id = "patterns",
		title = "Patterns",
		group = "Components",
		icon = "widget",
		blurb = "Edge fade, frost, the hover wash, chrome, loaders, the running pill.",
	},
	{
		id = "buttons",
		title = "Buttons",
		group = "Components",
		icon = "widget",
		blurb = "Button, icon button, segmented control.",
	},
	{
		id = "inputs",
		title = "Inputs",
		group = "Components",
		icon = "pen-new-square",
		blurb = "Input, textarea, checkbox and toggle.",
	},
	{
		id = "chips",
		title = "Chips and badges",
		group = "Components",
		icon = "tag",
		blurb = "Chips, badges, avatars, status dots.",
	},
	{
		id = "overlays",
		title = "Overlays",
		group = "Components",
		icon = "window-restore",
		blurb = "Tooltip, menu, popover, dialog, toast.",
	},
	{
		id = "lists",
		title = "Lists and navigation",
		group = "Components",
		icon = "list",
		blurb = "Rows, sidebar, tabs, scroll area, dividers, key caps.",
	},
	{
		id = "transcript",
		title = "Transcript",
		group = "Zeron",
		icon = "chat-round-line",
		blurb = "Bubbles, prose, code, quotes, tool calls, the rail.",
	},
	{
		id = "composer",
		title = "Composer",
		group = "Zeron",
		icon = "chat-round-line",
		blurb = "The composer and its states.",
	},
	{
		id = "pickers",
		title = "Pickers",
		group = "Zeron",
		icon = "tuning",
		blurb = "The compact model picker and the reasoning slider.",
	},
	{
		id = "agent",
		title = "Agent surfaces",
		group = "Zeron",
		icon = "bot",
		blurb = "Dictation, context usage, the todo and queue trays, roll text, message badges.",
	},
	{
		id = "changes",
		title = "Changes",
		group = "Zeron",
		icon = "git-branch",
		blurb = "File rows and the diff beneath them.",
	},
	{
		id = "workspace",
		title = "Workspace",
		group = "Zeron",
		icon = "file-tree",
		blurb = "The files tree, pull requests, comments, attachments.",
	},
	{
		id = "panes",
		title = "Panes",
		group = "Zeron",
		icon = "split-columns",
		blurb = "Wing's split workspace (zterm): a tree of cards with dividers and drops; what a multiplexer does. Zeron itself keeps one right panel: see Panels.",
	},
	{
		id = "panels",
		title = "Panels",
		group = "Zeron",
		icon = "split-columns",
		blurb = "Zeron's columns under its panel policy, the titlebar over them; the tab strip, agents, palettes, browser chrome, an empty pane.",
	},
	{
		id = "settings",
		title = "Settings",
		group = "Zeron",
		icon = "settings-minimalistic",
		blurb = "The preferences page's widgets, and notices.",
	},
	{
		id = "shell",
		title = "Shell",
		group = "Windows",
		icon = "window-restore",
		blurb = "Titlebar, sidebar, pane chrome, the transcript's edge and jump pill.",
	},
	{
		id = "apps",
		title = "Apps",
		group = "Windows",
		icon = "window-restore",
		blurb = "The kit as whole windows, opened on their own.",
	},
	{
		id = "parity",
		title = "Parity",
		group = "Reference",
		icon = "split-columns",
		blurb = "Zeron's numbers next to the kit.",
	},
}
M.PAGES = PAGES

function M.page_by(id: string): Page
	for _, page in M.PAGES do
		if page.id == id then
			return page
		end
	end
	return M.PAGES[1]
end

M.page = ui.state("page", "colour")
-- The theme the whole window shows: the shell proves it is theme-agnostic
-- along with the kit.
M.theme = ui.theme.current

-- How the window looks: the theme and its mode, the accent, the surface
-- (kit/look, as the Zeron app's; the root wears its scope).
M.look = look.new("sg", "zeron", "dark")
M.THEMES = look.THEMES
M.is_dark = look.is_dark

-- The accent and its label as the window shows them: the chosen preset's,
-- or the theme's own.
function M.accent_pair(): (string, string)
	local primary = look.preset(M.look)
	if primary then
		return primary, look.label_on(primary)
	end
	return tostring(ui.theme.get("accent")), tostring(ui.theme.get("accent.text"))
end
M.density = ui.state("density", "comfortable")
M.zoom = ui.state("zoom", "1")
M.inspector = ui.state("inspector", false)
M.sidebar = ui.state("sidebar", true)

-- The workbench's columns under Zeron's panel policy: the pages tree is the
-- sidebar, the canvas the conversation, the inspector a tool in Files'
-- place (it keeps its own width; the canvas absorbs every change).
M.layout = panel_shell.new {
	id = "wb",
	sidebar = true,
	files = true,
	files_width = 300,
	states = { sidebar = M.sidebar, files = M.inspector },
}

-- The pages visited, for Back and Forward (⌘[ and ⌘]).
local history = { list = { M.page:peek() }, at = 1, moving = false }
M.can_back = ui.state("can_back", false)
M.can_forward = ui.state("can_forward", false)
local function sync_history()
	M.can_back:set(history.at > 1)
	M.can_forward:set(history.at < #history.list)
end
ui.effect(function()
	local page = M.page:get()
	if history.moving then
		history.moving = false
		return
	end
	if history.list[history.at] == page then
		return
	end
	for i = #history.list, history.at + 1, -1 do
		table.remove(history.list, i)
	end
	table.insert(history.list, page)
	history.at = #history.list
	sync_history()
end)
local function go(step: number)
	local at = history.at + step
	if at < 1 or at > #history.list then
		return
	end
	history.at = at
	history.moving = true
	M.page:set(history.list[at])
	sync_history()
end
function M.back()
	go(-1)
end
function M.forward()
	go(1)
end

-- Every metric token, so zoom scales them all; density shrinks a few.
local METRICS = {
	"font.size.xs",
	"font.size.sm",
	"font.size.md",
	"font.size.lg",
	"font.size.xl",
	"font.size.xxl",
	"font.line.xs",
	"font.line.sm",
	"font.line.md",
	"font.line.lg",
	"font.line.xl",
	"font.line.xxl",
	"zeron.font.size.micro",
	"radius.sm",
	"radius.md",
	"radius.lg",
	"radius.xl",
	"zeron.radius.card",
	"zeron.radius.item",
	"zeron.radius.composer",
	"space.1",
	"space.2",
	"space.3",
	"space.4",
	"space.5",
	"space.6",
	"space.7",
	"space.8",
	"control.height",
	"zeron.control.sm",
	"zeron.control.lg",
}
local COMPACT: { [string]: number } = {
	["control.height"] = 28,
	["zeron.control.sm"] = 24,
	["zeron.control.lg"] = 34,
	["space.2"] = 6,
	["space.3"] = 10,
	["space.4"] = 12,
	["space.5"] = 20,
	["font.size.md"] = 12.5,
	["font.line.md"] = 17,
}

-- The page's token overrides for the current density and zoom, tracked,
-- over the look's (a scope naming the window's theme starts from it, so it
-- carries the look's accent and surface again).
local look_scope = look.scope(M.look)
function M.overrides(): { [string]: string | number | { [string]: any } }
	local zoom = tonumber(M.zoom:get()) or 1
	local compact = M.density:get() == "compact"
	local out: { [string]: any } = look_scope()
	if zoom == 1 and not compact then
		return out
	end
	for _, name in METRICS do
		local base = if compact then COMPACT[name] else nil
		local v = base or ui.theme.get(name)
		if type(v) == "number" then
			out[name] = v * zoom
		end
	end
	return out
end

return M
