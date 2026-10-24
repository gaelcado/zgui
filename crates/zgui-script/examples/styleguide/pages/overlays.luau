-- Overlays: each one open where it belongs, on a stage that is a corner of
-- Zeron's window (the glass, a sidebar, a thread, the composer), so the
-- frost, the shadow and the anchoring read as they will in the app. Under
-- each stage, its live triggers. Zeron's numbers (popover.rs): cards at
-- radius 12 with a 4 inset and rows at 7; dialogs 360 wide, padded 20, at
-- radius 16 over a light scrim; menus and tooltips on the menu surface.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local menu = require("@kit/menu")
local toast = require("@kit/toast")
local tr = require("@kit/transcript")

-- An item, typed (the entry union is too wide for Luau to pick from a
-- literal).
local function item(t: menu.Item): menu.Entry
	return t
end

local menu_open = ui.state("menu_open", false)
local popover_open = ui.state("popover_open", false)
local dialog_open = ui.state("dialog_open", false)
local danger_open = ui.state("danger_open", false)
local always = ui.state("always", false)
local pinned = ui.state("wrap", true)
local thinking = ui.state("thinking", true)
local chose = ui.state("chose", "nothing yet")
local model = ui.state("overlay_model", "opus")

local function items(prefix: string): { menu.Entry }
	return {
		{ heading = "Thread" },
		item {
			id = prefix .. "_rename",
			label = "Rename",
			icon = "pen",
			keys = { "⌘", "R" },
			on_click = function()
				chose:set("Rename")
			end,
		},
		item {
			label = "Duplicate",
			icon = "copy",
			on_click = function()
				chose:set("Duplicate")
			end,
		},
		item {
			label = "Pin to sidebar",
			icon = "pin",
			checked = pinned,
			on_click = function()
				pinned:toggle()
			end,
		},
		"-",
		item {
			label = "Open in terminal",
			icon = "terminal",
			detail = "zsh",
			on_click = function()
				chose:set("Open in terminal")
			end,
		},
		item { label = "Share link", icon = "arrow-up-right", disabled = true },
		"-",
		item {
			id = prefix .. "_delete",
			label = "Delete thread…",
			icon = "trash-bin-minimalistic",
			danger = true,
			keys = { "⌘", "⌫" },
			on_click = function()
				danger_open:set(true)
			end,
		},
	}
end

-- ---- the stage ----------------------------------------------------------

export type StageProps = { id: string?, h: number, [number]: Child }

-- A corner of the window: the glass, its hairline, what is drawn on it.
local function stage(props: StageProps): Node
	return ui.div {
		id = props.id,
		relative = true,
		w_full = true,
		h = props.h,
		rounded = T.radius_card,
		bg = T.glass,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		{ table.unpack(props) },
	}
end

-- Text lines standing in for a thread, so a frosted overlay has something
-- to blur.
local function lines(n: number, w: number): Node
	local bars: { Node } = {}
	for i = 1, n do
		table.insert(bars, ui.div { h = 8, w = w - ((i * 37) % 120), rounded = "$zeron.radius.4", bg = T.ink2 })
	end
	return ui.column { gap = "$zeron.space.12", bars }
end

-- The live triggers under a stage, and a line of state.
local function controls(children: { Child }): Node
	return ui.row {
		w_full = true,
		pt = "$zeron.space.12",
		gap = "$zeron.space.8",
		items = "center",
		flex_wrap = true,
		children,
	}
end

local function readout(id: string, text: () -> string): Node
	return kit.text.text { text, id = id, size = "xs", mono = true, color = T.tertiary, line = false }
end

-- ---- tooltip ------------------------------------------------------------

local function tooltips(): Node
	return ui.column {
		w_full = true,
		stage {
			id = "stage_tooltip",
			h = 150,
			-- A titlebar's trailing controls, the tooltip under one of them.
			-- Inset from the edge, so the shown tooltip has room to centre.
			ui.row {
				absolute = true,
				top = 12,
				right = 96,
				gap = "$zeron.space.4",
				items = "center",
				kit.tooltip {
					label = "Search",
					keys = { "⌘", "F" },
					id = "search",
					kit.icon_button { id = "tip_search", icon = "magnifer", no_ring = true },
				},
				kit.tooltip {
					label = "More actions",
					id = "more",
					kit.icon_button { icon = "more-horizontal", no_ring = true },
				},
				kit.tooltip {
					label = "Appearance",
					keys = { "⌘", "⇧", "A" },
					preview = true,
					kit.icon_button { icon = "palette", no_ring = true },
				},
			},
			ui.column { absolute = true, left = 24, top = 24, lines(4, 300) },
		},
		controls {
			kit.text.text {
				"Hover the search or the dots: 500 ms the first time, at once while another has just closed.",
				size = "xs",
				color = T.tertiary,
			},
		},
	}
end

-- ---- menu ---------------------------------------------------------------

local function thread_row(title: string, sub: string, selected: boolean): Node
	return ui.row {
		w_full = true,
		h = 44,
		px = "$zeron.space.10",
		gap = "$zeron.space.10",
		items = "center",
		rounded = T.radius_button,
		bg = if selected then T.selected else T.clear,
		kit.icon { name = "chat-round-line", size = 15, color = T.secondary },
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.1",
			kit.text.text { title, size = "sm", weight = "medium", truncate = true, line = false },
			kit.text.text { sub, size = "xs", color = T.tertiary, truncate = true, line = false },
		},
		selected and kit.icon { name = "more-horizontal", size = 15, color = T.secondary } or nil,
	}
end

local function menus(): Node
	return ui.column {
		w_full = true,
		stage {
			id = "stage_menu",
			h = 330,
			-- The sidebar, a thread's ··· pressed, its menu beside it.
			ui.column {
				absolute = true,
				left = 0,
				top = 0,
				bottom = 0,
				w = 260,
				p = "$zeron.space.8",
				gap = "$zeron.space.2",
				bg = T.sidebar_tone,
				border_sides = { 0, 1, 0, 0 },
				border_color = T.border,
				kit.text.eyebrow("Recent"),
				thread_row("Write the release notes", "zgui · 2m", true),
				thread_row("Refactor the layout engine", "zgui · 6m", false),
				thread_row("Fix flaky test", "comet · 1h", false),
			},
			ui.column { absolute = true, left = 300, top = 28, lines(6, 420) },
			ui.div {
				absolute = true,
				left = 236,
				top = 40,
				kit.menu {
					id = "menu_inline",
					open = menu_open,
					anchor = ui.div {},
					items = items("inline"),
					inline = true,
				},
			},
		},
		controls {
			kit.menu {
				id = "menu_live",
				open = menu_open,
				items = items("menu"),
				anchor = kit.button {
					id = "menu_trigger",
					label = "Thread",
					size = "sm",
					variant = "secondary",
					trailing = { name = "alt-arrow-down" },
					on_click = ui.toggle(menu_open),
				},
			},
			readout("menu_chose", function()
				return `chose: {chose:get()} · {if menu_open:get() then "open" else "closed"}`
			end),
		},
	}
end

-- ---- popover ------------------------------------------------------------

type Model = { id: string, label: string, detail: string?, icon: string }
local MODELS: { Model } = {
	{ id = "opus", label = "Claude Opus 5.5", detail = "default", icon = "claude-mark" },
	{ id = "sonnet", label = "Claude Sonnet 5.5", icon = "claude-mark" },
	{ id = "codex", label = "GPT-5.5 Codex", icon = "openai-mark" },
}

local function model_card(group: string): { Node }
	local rows: { Node } = {}
	for _, m in MODELS do
		table.insert(
			rows,
			kit.row {
				id = `{group}_{m.id}`,
				group = group,
				label = m.label,
				detail = m.detail,
				icon = m.icon :: any,
				selected = function()
					return model:get() == m.id
				end,
				on_click = ui.set(model, m.id),
			}
		)
	end
	return {
		ui.row { h = 26, px = "$zeron.space.8", items = "end", pb = "$zeron.space.4", kit.text.eyebrow("Model") },
		kit.list { group = group, gap = "$zeron.space.2", rows },
		kit.divider { my = "$zeron.space.2" },
		ui.row {
			px = "$zeron.space.8",
			py = "$zeron.space.6",
			kit.toggle { value = thinking, label = "Extended thinking", size = "sm" },
		},
	}
end

local function popovers(): Node
	return ui.column {
		w_full = true,
		stage {
			id = "stage_popover",
			h = 330,
			ui.column { absolute = true, left = 32, top = 28, lines(5, 460) },
			-- The composer at the bottom, its model chip's card above it.
			ui.row {
				absolute = true,
				left = 24,
				right = 24,
				bottom = 20,
				h = 52,
				px = "$zeron.space.14",
				gap = "$zeron.space.8",
				items = "center",
				rounded = "$zeron.radius.26",
				bg = T.frost,
				border = 1,
				border_color = T.input_border,
				kit.icon { name = "paperclip", size = 16, color = T.secondary },
				ui.row {
					h = 32,
					px = "$zeron.space.8",
					gap = "$zeron.space.6",
					items = "center",
					rounded = T.radius_button,
					bg = T.hover,
					kit.icon { name = "claude-mark", size = 16, color = T.claude },
					kit.text.text { "Claude Opus 5.5", size = "sm", weight = "medium", line = false },
				},
				ui.div { grow = 1 },
				kit.icon { name = "microphone", size = 16, color = T.secondary },
			},
			ui.column {
				absolute = true,
				left = 44,
				bottom = 80,
				w = 272,
				p = "$zeron.space.4",
				gap = "$zeron.space.2",
				rounded = T.radius_card,
				bg = T.frost,
				backdrop_blur = kit.frost.BLUR,
				border = 1,
				border_color = T.border,
				shadow = T.shadow_lg,
				model_card("popover_inline"),
			},
		},
		controls {
			kit.popover {
				id = "popover_live",
				open = popover_open,
				w = 272,
				p = "$zeron.space.4",
				gap = "$zeron.space.2",
				anchor = kit.button {
					id = "popover_trigger",
					label = "Claude Opus",
					size = "sm",
					variant = "secondary",
					icon = { name = "claude-mark" },
					trailing = { name = "sort-vertical" },
					on_click = ui.toggle(popover_open),
				},
				model_card("popover_live"),
			},
		},
	}
end

-- ---- dialog -------------------------------------------------------------

local function approval(inline: boolean?, open: State<boolean>, id: string): Node
	return kit.dialog {
		id = id,
		open = open,
		inline = inline,
		title = "Allow writing to src/?",
		description = "The agent wants to write three files under src/ in zeron/zgui. You can review the diff first.",
		actions = {
			kit.button { label = "Deny", variant = "ghost", size = "sm", on_click = ui.set(open, false) },
			kit.button { label = "Review", variant = "secondary", size = "sm", on_click = ui.set(open, false) },
			kit.button {
				id = id .. "_approve",
				label = "Approve",
				variant = "primary",
				size = "sm",
				on_click = ui.set(open, false),
			},
		},
		on_enter = function()
			open:set(false)
		end,
		kit.checkbox { value = always, label = "Always allow for this session" },
	}
end

local function destructive(inline: boolean?): Node
	return kit.dialog {
		id = if inline then "dialog_danger_inline" else "dialog_danger",
		open = danger_open,
		inline = inline,
		title = "Delete this thread?",
		description = "Its transcript and worktree go with it. This cannot be undone.",
		actions = {
			kit.button { label = "Cancel", variant = "ghost", size = "sm", on_click = ui.set(danger_open, false) },
			kit.button {
				id = if inline then "dialog_danger_inline_delete" else "dialog_danger_delete",
				label = "Delete",
				variant = "danger",
				size = "sm",
				on_click = ui.set(danger_open, false),
			},
		},
	}
end

-- A thread under the dialog's scrim.
local function scrimmed(child: Node): Node
	return stage {
		h = 300,
		ui.column {
			absolute = true,
			left = 28,
			top = 24,
			right = 28,
			gap = "$zeron.space.16",
			tr.user_bubble { text = "Can you make the panels follow Zeron's policy?" },
			lines(4, 360),
		},
		ui.column {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			items = "center",
			justify = "center",
			bg = "$zeron.scrim_preview",
			child,
		},
	}
end

local function dialogs(): Node
	return ui.column {
		w_full = true,
		gap = "$zeron.space.12",
		ui.row {
			w_full = true,
			gap = "$zeron.space.12",
			ui.column { grow = 1, basis = 0, min_w = 0, scrimmed(approval(true, dialog_open, "dialog_inline")) },
			ui.column { grow = 1, basis = 0, min_w = 0, scrimmed(destructive(true)) },
		},
		controls {
			kit.button {
				id = "dialog_trigger",
				label = "Open the approval",
				size = "sm",
				variant = "secondary",
				on_click = ui.set(dialog_open, true),
			},
			kit.button {
				id = "danger_trigger",
				label = "Delete thread…",
				size = "sm",
				variant = "danger",
				on_click = ui.set(danger_open, true),
			},
			readout("dialog_state", function()
				return if dialog_open:get() then "open" elseif danger_open:get() then "danger" else "closed"
			end),
			approval(false, dialog_open, "dialog_live"),
			destructive(false),
		},
	}
end

-- ---- toast --------------------------------------------------------------

local function toasts(): Node
	local function push(tone: toast.Tone, title: string, description: string?, action: string?)
		toast.push { tone = tone, title = title, description = description, action = action, duration = 6000 }
	end
	return ui.column {
		w_full = true,
		stage {
			id = "stage_toast",
			h = 300,
			ui.column { absolute = true, left = 28, top = 28, lines(7, 420) },
			-- The window's bottom right corner, the stack rising from it.
			ui.column {
				absolute = true,
				right = 16,
				bottom = 16,
				gap = "$zeron.space.8",
				items = "end",
				toast.card {
					id = "toast_a",
					title = "Changes applied",
					description = "3 files under src/ were written.",
					tone = "success",
				},
				toast.card {
					id = "toast_b",
					title = "Agent needs you",
					description = "It has a question about the database schema.",
					tone = "warning",
					action = "Open thread",
				},
				toast.card { id = "toast_c", title = "Connection lost", tone = "danger" },
			},
		},
		controls {
			kit.button {
				id = "toast_push",
				label = "Push a toast",
				size = "sm",
				variant = "secondary",
				on_click = function()
					push("neutral", "Copied to clipboard")
				end,
			},
			kit.button {
				label = "With an action",
				size = "sm",
				variant = "secondary",
				on_click = function()
					push("info", "Update ready", "Zeron 0.2.109 downloaded.", "Restart")
				end,
			},
			kit.button {
				label = "An error",
				size = "sm",
				variant = "secondary",
				on_click = function()
					push("danger", "Could not save", "The file is open elsewhere.")
				end,
			},
		},
	}
end

-- ⌘K, the app's own, over sample rows.
local function run() end
local command_palette = kit.command_palette.new("sg_palette", {
	query = ui.state("sg_palette_query", ""),
	autofocus = false,
	commands = {
		{
			id = "sg_new",
			section = "Commands",
			label = "New space",
			icon = "add-circle",
			keys = { "⌘", "T" },
			run = run,
		},
		{
			id = "sg_split",
			section = "Commands",
			label = "Split right",
			icon = "split-columns",
			keys = { "⌘", "D" },
			run = run,
		},
		{
			id = "sg_settings",
			section = "Commands",
			label = "Settings",
			icon = "settings",
			keys = { "⌘", "," },
			run = run,
		},
	},
	threads = {
		{
			id = "sg_t1",
			section = "Threads",
			label = "Fix the sidebar's glide",
			detail = "zgui · 2m",
			icon = "claude-mark",
			tint = T.claude,
			run = run,
		},
		{
			id = "sg_t2",
			section = "Threads",
			label = "Token audit",
			detail = "zeron · 1h",
			icon = "claude-mark",
			run = run,
		},
	},
	files = {
		{ id = "sg_f1", section = "Files", label = "theme.luau", detail = "styleguide", icon = "file-code", run = run },
	},
})

return function(): Node
	local page = state.page_by("overlays")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Tooltip",
			note = "the menu surface at radius 7 · text 12 · a key cap · 6 under the trigger · after 500 ms, at once while another just closed",
			tooltips(),
		},
		specimen.section {
			title = "Menu",
			note = "card at 12, inset 4, rows 30 at 7 · a heading, checks, details, keys, a separator, a disabled and a destructive item · ↑ ↓ Home End move, Enter chooses, Escape closes · the rows glide",
			menus(),
		},
		specimen.section {
			title = "Popover",
			note = "the same card, anchored to its trigger (here the composer's model chip) · opens over 140 ms, rising 4 · Escape and a click outside close it",
			popovers(),
		},
		specimen.section {
			title = "Dialog",
			note = "360 wide, padded 20, at radius 16 over a 35% scrim · title, what it asks, the choice, actions at the end, the primary last · Enter runs it, Escape closes · destructive on the danger plate",
			dialogs(),
		},
		specimen.section {
			title = "Command palette",
			note = "the app's ⌘K · 560 frosted at radius 16 · a 44 search row · tabs ⌘1 to ⌘4 · rows 30 in sections · ↑ ↓ move, ↵ opens, Esc closes",
			kit.command_palette.card(command_palette),
		},
		specimen.section {
			title = "Toast",
			note = "360 wide on the menu surface · a tone's glyph, title, detail, an action, dismiss · stacks bottom right, leaves after 6 s",
			toasts(),
		},
	}
end
