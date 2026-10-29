-- Notifications, Archived sessions and General's Links and thread naming
-- (settings/notifications.rs, archived.rs, thread_naming.rs, shortcuts.rs
-- general_page; v0.2.129). Notifications: Desktop, then Sounds, a parent's
-- rows at 55% and inert while it is off (keeping their own values).
-- Archived: 40 a page, Previous and Next with "1–40 of N", each row's
-- Unarchive (Unarchiving… while it goes), Delete all asking first, and
-- "Nothing archived". Thread naming: the session's own agent, or a small
-- model chosen from the agents' (Reset goes back).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local button = require("./button")
local select = require("./select")
local settings = require("./settings")
local dialog = require("./dialog")
local menu = require("./menu")
local recipes = require("./recipes")

local M = {}

export type NotificationPrefs = {
	desktop: State<boolean>,
	agent_updates: State<boolean>,
	background_only: State<boolean>,
	sounds: State<boolean>,
	notify_done: State<boolean>,
	notify_input: State<boolean>,
	notify_failed: State<boolean>,
}

-- Each child row's name for settings search.
local ANCHOR: { [string]: string } = {
	settings_agent_updates = "agent_updates",
	settings_background_only = "background_only",
	settings_sound_done = "task_completed",
	settings_sound_input = "input_required",
	settings_sound_failed = "error_sound",
}

-- A row under a parent switch: at 55% and its switch inert while the
-- parent is off (still showing its own value).
local function child(
	id: string,
	title: string,
	meta: string?,
	value: State<boolean>,
	parent: State<boolean>,
	glyph: string?
): Node
	return ui.row {
		id = `{id}_row`,
		on_mount = settings.anchor(ANCHOR[id]),
		w_full = true,
		opacity = function()
			return if parent:get() then 1 else 0.55
		end,
		glyph and ui.row {
			pl = "$zeron.space.16",
			items = "center",
			icon { name = glyph :: any, size = 16, color = T.secondary },
		} or nil,
		ui.column {
			grow = 1,
			min_w = 0,
			settings.row {
				title = title,
				meta = if meta then { meta } else nil,
				control = settings.switch {
					id = id,
					value = value,
					disabled = function()
						return not parent:get()
					end,
				},
			},
		},
	}
end

function M.notifications(prefs: NotificationPrefs): Node
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.24",
		settings.header { title = "Notifications" },
		settings.section {
			title = "Desktop",
			settings.row {
				anchor = "desktop_notifications",
				title = "Desktop notifications",
				control = settings.switch { id = "settings_desktop_notifications", value = prefs.desktop },
			},
			child(
				"settings_agent_updates",
				"Agent updates",
				"Show a banner when monitored agent CLIs have updates.",
				prefs.agent_updates,
				prefs.desktop,
				"refresh"
			),
			child("settings_background_only", "Only when in the background", nil, prefs.background_only, prefs.desktop),
		},
		settings.section {
			title = "Sounds",
			settings.row {
				anchor = "session_sounds",
				title = "Session sounds",
				control = settings.switch { id = "settings_session_sounds", value = prefs.sounds },
			},
			child("settings_sound_done", "Task completed", nil, prefs.notify_done, prefs.sounds),
			child("settings_sound_input", "Input required", nil, prefs.notify_input, prefs.sounds),
			child("settings_sound_failed", "Errors and disconnections", nil, prefs.notify_failed, prefs.sounds),
		},
	}
end

-- Open pull requests in (settings.rs PullRequestDestination): the app's
-- own view, a Browser tab, or the default browser; each saying what it
-- does.
M.PR_TARGETS = { "Pull request view", "In-app browser", "Default browser" }
local PR_TARGET_NOTES: { [string]: string } = {
	["Pull request view"] = "Inspect them in Zeron, beside the conversation or the Pull requests board.",
	["In-app browser"] = "Open them in a Browser tab beside the conversation, or in the default browser when none is shown.",
	["Default browser"] = "Open them in the default browser.",
}
function M.links(value: State<string>): Node
	local options: { select.Option } = {}
	for i, t in M.PR_TARGETS do
		table.insert(options, { value = t, label = t, id = `settings_open_prs_{i}` })
	end
	return settings.section {
		title = "Links",
		settings.row {
			anchor = "open_prs",
			title = "Open pull requests in",
			meta = {
				function()
					return PR_TARGET_NOTES[value:get()] or ""
				end,
			},
			control = select {
				id = "settings_open_prs",
				label = "Open pull requests in",
				value = value,
				options = options,
				w = 160,
			},
		},
	}
end

-- The agents that can name threads and their models; "" is Automatic (the
-- cheapest).
export type Namer = { id: string, name: string, mark: string, tint: Color?, models: { string } }
M.NAMERS = {
	{
		id = "claude",
		name = "Claude Code",
		mark = "claude-mark",
		tint = T.claude,
		models = { "Haiku 4.5", "Sonnet 4.5" },
	},
	{ id = "codex", name = "Codex", mark = "openai-mark", models = { "GPT-5 mini", "GPT-5" } },
	{ id = "cursor", name = "Cursor", mark = "cursor-mark", models = { "Composer 1" } },
} :: { Namer }

-- Thread naming (thread_naming.rs): "" follows the session's agent, else
-- `agent/model` (the model "" for Automatic).
function M.thread_naming(value: State<string>): Node
	local open = ui.state("settings_thread_naming_open", false)
	local function parts(): (string?, string?)
		local v = value:get()
		if v == "" then
			return nil, nil
		end
		local agent, model = string.match(v, "^([^/]*)/(.*)$")
		return agent, model
	end
	local items: { menu.Entry } = {}
	for _, n in M.NAMERS do
		table.insert(items, { heading = n.name })
		local choices = { "" }
		for _, m in n.models do
			table.insert(choices, m)
		end
		for i, m in choices do
			local v = `{n.id}/{m}`
			local item: menu.Item = {
				id = `settings_thread_naming_{n.id}_{i}`,
				label = if m == "" then "Automatic" else m,
				icon = n.mark :: any,
				checked = function()
					return value:get() == v
				end,
				on_click = function()
					value:set(v)
				end,
			}
			table.insert(items, item)
		end
	end
	local chip = ui.button {
		id = "settings_thread_naming",
		label = "Thread naming model",
		h = 28,
		px = "$zeron.space.10",
		gap = "$zeron.space.6",
		items = "center",
		rounded = "$zeron.radius.8",
		variants = recipes.wash { rest = "ink2", hover = "ink4" },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = ui.toggle(open),
		ui.presence(value, function(v: string): Node
			local agent, _ = parts()
			local mark = "chat-round-line"
			local tint: Color? = nil
			for _, n in M.NAMERS do
				if n.id == agent then
					mark, tint = n.mark, n.tint
				end
			end
			return icon { name = mark :: any, size = 14, color = tint or T.secondary }
		end),
		txt.text {
			function()
				local agent, model = parts()
				if not agent then
					return "Session agent"
				end
				return if model == "" or model == nil then "Automatic" else model
			end,
			size = "md",
			line = false,
		},
		icon { name = "alt-arrow-down", size = 12, color = T.tertiary },
	}
	return settings.card {
		settings.row {
			id = "settings_thread_naming_row",
			anchor = "thread_naming",
			title = "Thread naming",
			meta = {
				function()
					return if value:get() == ""
						then "Each thread is named by its own agent."
						else "A small model keeps titles fast and cheap."
				end,
			},
			control = ui.row {
				gap = "$zeron.space.6",
				items = "center",
				ui.show(
					function()
						return value:get() ~= ""
					end,
					button {
						id = "settings_thread_naming_reset",
						label = "Reset",
						size = "sm",
						variant = "ghost",
						on_click = function()
							value:set("")
						end,
					}
				),
				menu.menu {
					id = "settings_thread_naming_menu",
					open = open,
					anchor = chip,
					label = "Name threads with",
					w = 232,
					max_h = 320,
					placement = { side = "bottom", align = "end", offset = 4 },
					items = items,
				},
			},
		},
	}
end

export type Archived = { key: string?, title: string, project: string, ago: string, device: string? }
M.PAGE = 40

-- The Archived sessions page: `list` the archived sessions, newest first;
-- `on_unarchive` puts one back in the sidebar, `on_delete_all` removes
-- them all.
function M.archived(list: State<{ Archived }>, on_unarchive: ((s: Archived) -> ())?, on_delete_all: (() -> ())?): Node
	local page = ui.state("settings_archived_page", 1)
	local unarchiving = ui.state("settings_archived_unarchiving", "")
	local deleting = ui.state("settings_archived_deleting", false)
	local confirm = ui.state("settings_archived_confirm", false)
	local function pages(): number
		return math.max(1, math.ceil(#list:get() / M.PAGE))
	end
	-- A page emptied by unarchiving goes back to the one before it.
	ui.effect(function()
		local n = pages()
		if page:peek() > n then
			page:set(n)
		end
	end)
	local function unarchive(s: Archived, id: string, at: number)
		unarchiving:set(id)
		ui.after(600, function()
			if unarchiving:peek() ~= id then
				return
			end
			unarchiving:set("")
			local out: { Archived } = {}
			for i, x in list:peek() do
				if i ~= at then
					table.insert(out, x)
				end
			end
			list:set(out)
			if on_unarchive then
				on_unarchive(s)
			end
		end)
	end
	local function delete_all()
		confirm:set(false)
		deleting:set(true)
		ui.after(700, function()
			deleting:set(false)
			list:set {}
			if on_delete_all then
				on_delete_all()
			end
		end)
	end
	local function row(s: Archived, at: number): Node
		local id = `archived_{at}`
		local second = s.project
		if s.device then
			second = `{s.device} · {s.project}`
		end
		return ui.row {
			id = id,
			w_full = true,
			min_h = 56,
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			gap = "$zeron.space.12",
			items = "center",
			hover = { bg = T.ink1 },
			ui.row {
				w = 32,
				h = 32,
				shrink = 0,
				rounded = "$zeron.radius.8",
				border = 1,
				border_color = T.border,
				items = "center",
				justify = "center",
				icon { name = "archive-minimalistic", size = 16, color = T.secondary },
			},
			ui.column {
				grow = 1,
				min_w = 0,
				gap = "$zeron.space.2",
				ui.row {
					gap = "$zeron.space.8",
					items = "center",
					txt.text {
						if s.title == "" then "Untitled session" else s.title,
						literal = true,
						size = "md",
						weight = "medium",
						truncate = true,
						shrink = 1,
						line = false,
					},
					txt.text { s.ago, literal = true, size = "xs", color = T.tertiary, line = false },
				},
				txt.text { second, literal = true, size = "xs", color = T.tertiary, truncate = true, line = false },
			},
			ui.button {
				id = `{id}_unarchive`,
				h = 28,
				px = "$zeron.space.10",
				gap = "$zeron.space.6",
				items = "center",
				rounded = "$zeron.radius.8",
				border = 1,
				border_color = T.border,
				bg = T.clear,
				hover = { bg = T.glass_hover },
				focus = { border = 0 },
				cursor = "pointer",
				opacity = function()
					return if unarchiving:get() == id then 0.4 else 0.8
				end,
				on_click = function()
					unarchive(s, id, at)
				end,
				icon { name = "archive-up-minimalistic", size = 14, color = T.secondary },
				txt.text {
					function()
						return if unarchiving:get() == id then "Unarchiving…" else "Unarchive"
					end,
					size = "sm",
					line = false,
				},
			},
		}
	end
	local function pager(): Node
		local function nav(id: string, label: string, by: number): Node
			return ui.button {
				id = id,
				variants = recipes.text_button,
				opacity = function()
					local p = page:get() + by
					return if p < 1 or p > pages() then 0.4 else 1
				end,
				on_click = function()
					page:set(math.clamp(page:peek() + by, 1, pages()))
				end,
				txt.text { label, size = "sm", color = "inherit", line = false },
			}
		end
		return ui.show(
			function()
				return #list:get() > M.PAGE
			end,
			ui.row {
				w_full = true,
				justify = "between",
				items = "center",
				nav("archived_previous", "Previous", -1),
				txt.text {
					function()
						local n = #list:get()
						local first = (page:get() - 1) * M.PAGE + 1
						return `{first}–{math.min(n, first + M.PAGE - 1)} of {n}`
					end,
					id = "archived_range",
					size = "sm",
					color = T.secondary,
					tabular = true,
					line = false,
				},
				nav("archived_next", "Next", 1),
			}
		)
	end
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.24",
		ui.row {
			w_full = true,
			items = "end",
			gap = "$zeron.space.16",
			ui.column {
				grow = 1,
				gap = "$zeron.space.4",
				ui.row {
					gap = "$zeron.space.8",
					items = "baseline",
					txt.text { "Archived sessions", size = "xxl", weight = "medium", line = false },
					txt.text {
						function()
							local n = #list:get()
							return if n > 0 then tostring(n) else ""
						end,
						id = "archived_count",
						size = "md",
						color = T.secondary,
						line = false,
					},
				},
				txt.text { "Hidden from the sidebar until restored.", size = "md", color = T.secondary },
			},
			ui.show(
				function()
					return #list:get() > 0
				end,
				ui.column {
					opacity = function()
						return if deleting:get() then 0.5 else 1
					end,
					button {
						id = "archived_delete_all",
						label = function()
							return if deleting:get() then "Deleting…" else "Delete all"
						end,
						icon = { name = "trash-bin-minimalistic", size = 16 },
						size = "sm",
						variant = "danger",
						on_click = function()
							if not deleting:peek() then
								confirm:set(true)
							end
						end,
					},
				}
			),
		},
		ui.presence(function(): string
			local n = #list:get()
			return if n == 0 then "empty" else `{page:get()}:{n}`
		end, function(k: string): Node
			if k == "empty" then
				return ui.column {
					id = "archived_empty",
					w_full = true,
					pt = "$zeron.space.96",
					gap = "$zeron.space.6",
					items = "center",
					icon { name = "archive-minimalistic", size = 28, color = T.text, opacity = 0.2 },
					txt.text { "Nothing archived", size = "lg", mt = "$zeron.space.6", line = false },
					txt.text {
						"Right-click a session in the sidebar to archive it.",
						size = "sm",
						color = T.secondary,
						line = false,
					},
				}
			end
			local all = list:peek()
			local first = (page:peek() - 1) * M.PAGE + 1
			local rows: { Node } = {}
			for i = first, math.min(#all, first + M.PAGE - 1) do
				table.insert(rows, row(all[i], i))
			end
			return ui.column { w_full = true, gap = "$zeron.space.16", settings.card(rows :: any), pager() }
		end, { w_full = true }),
		ui.presence(function(): boolean?
			return if confirm:get() then true else nil
		end, function(): Node
			local n = #list:peek()
			return dialog {
				id = "archived_delete_dialog",
				open = confirm,
				title = "Delete all archived sessions?",
				description = if n == 1
					then "1 archived session will be permanently deleted. This can’t be undone."
					else `{n} archived sessions will be permanently deleted. This can’t be undone.`,
				w = 360,
				actions = {
					button {
						id = "archived_delete_cancel",
						label = "Cancel",
						size = "sm",
						variant = "ghost",
						on_click = function()
							confirm:set(false)
						end,
					},
					button {
						id = "archived_delete_confirm",
						label = "Delete all",
						size = "sm",
						variant = "danger",
						on_click = delete_all,
					},
				},
			}
		end),
	}
end

return M
