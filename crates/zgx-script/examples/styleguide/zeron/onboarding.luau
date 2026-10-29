-- Onboarding (onboarding.rs, shell.rs v0.2.129). A fresh install opens on
-- first-run setup, a page at a time in the window's place, on its glass:
-- Welcome; Make it yours (the colour scheme, the accent, the new-chat
-- wallpaper and its effect, behind the page as soon as it is chosen);
-- Sync your work (why, then Log in or Skip for now: logging in runs
-- zeron/sync's steps in the same frame); Connect GitHub (signed in and
-- offered Cloud: Settings → Cloud's block); Your agents (Settings →
-- Providers' rows: Continue waits until one is installed); You're all set
-- (what was chosen, then Start using Zeron, or Add a project and I'll do
-- this later). The numbered steps share one frame, the progress over them
-- and Back and the way on under them, still while the step between them
-- fades. Signing out leads to Zeron's gates instead (render_gate_card,
-- render_org_gate, the no-projects canvas): over a 44-point grid fading
-- toward the window's edges, a card at a time entering over 500 ms, "Log
-- in to Zeron", "Create your workspace", then "Add a project to get
-- started". Each step waits on what it asks; nothing runs while it rests.
local T = require("../theme")
local kit = require("@kit")
local look_mod = require("@kit/look")
local appearance = require("@kit/appearance")
local select = require("@kit/select")
local settings_page = require("@kit/settings_page")
local agents = require("@kit/settings_agents")
local projects = require("./projects")
local account = require("./account")
local sync = require("./sync")
local cloud = require("./cloud")
local state = require("./state")

local M = {}

export type Step =
	""
	| "signin"
	| "signing"
	| "workspace"
	| "project"
	| "welcome"
	| "appearance"
	| "sync"
	| "github"
	| "providers"
	| "done"

-- The step shown; "" once done.
M.step = ui.state("onboarding_step", "" :: Step)
-- First-run setup finished on this device (onboardingCompleted).
M.completed = ui.persist("onboarding_completed", false)
local workspace = ui.state("onboarding_workspace", "")
local creating = ui.state("onboarding_creating", false)
-- Log in was pressed: signing in moves setup on.
local awaiting = ui.state("onboarding_awaiting", false)
-- Whether the device has a project yet (a fresh install has none).
local has_projects = ui.state("onboarding_has_projects", true)

local SETUP: { [string]: boolean } =
	{ welcome = true, appearance = true, sync = true, github = true, providers = true, done = true }

-- A project added ends the last gate.
projects.on_added = function()
	if M.step:peek() == "project" then
		M.step:set("")
	end
end

-- The gates from their start, as after signing out.
function M.start()
	workspace:set("")
	creating:set(false)
	M.step:set("signin")
end

-- First-run setup from its start: signed out, on this device alone.
-- `fresh`: no project yet either.
function M.begin(fresh: boolean?)
	awaiting:set(false)
	has_projects:set(not fresh)
	account.account:set { scope = "local" }
	-- An account new to Zeron: Cloud not set up, GitHub not connected.
	if fresh then
		cloud.account:set("off")
		cloud.github:set { link = "none", account = "" }
	end
	M.step:set("welcome")
end

-- Whether setup (not a gate) shows.
function M.setting_up(): boolean
	return SETUP[M.step:get()] == true
end
-- Whether it covers the window (the app beneath stops painting).
function M.covering(): boolean
	return M.step:get() ~= ""
end

local function signed_in(): boolean
	return account.account:get().email ~= nil
end
-- The GitHub step is in the flow: signed in, and Cloud offered.
local function github_in_flow(): boolean
	return signed_in() and cloud.offered:get()
end

local function next_of(step: string): Step
	if step == "welcome" then
		return "appearance"
	elseif step == "appearance" then
		return "sync"
	elseif step == "sync" and github_in_flow() then
		return "github"
	elseif step == "sync" or step == "github" then
		return "providers"
	end
	return "done"
end
local function previous_of(step: string): Step
	if step == "welcome" or step == "appearance" then
		return "welcome"
	elseif step == "sync" then
		return "appearance"
	elseif step == "github" then
		return "sync"
	elseif step == "providers" then
		return if github_in_flow() then "github" else "sync"
	end
	return "providers"
end
-- Place among the numbered steps (the welcome and the ending aren't).
local function number_of(step: string): number?
	if step == "appearance" then
		return 1
	elseif step == "sync" then
		return 2
	elseif step == "github" then
		return 3
	elseif step == "providers" then
		return if github_in_flow() then 4 else 3
	end
	return nil
end
local function total(): number
	return if github_in_flow() then 4 else 3
end

-- zeron/sync's step while it shows inside setup, in the sync step's place.
local function sync_slot(): string?
	if not M.setting_up() then
		return nil
	end
	return sync.page_step()
end
sync.inside = M.setting_up

-- The step on show: zeron/sync's, or setup's own.
local function shown(): string
	local slot = sync_slot()
	return if slot then `sync:{slot}` else M.step:get()
end

-- Signed in after Log in: on to GitHub, or the agents. Setup's GitHub
-- step without the offer moves past it.
ui.effect(function()
	local step = M.step:get()
	if awaiting:get() and signed_in() then
		awaiting:set(false)
		M.step:set(if github_in_flow() then "github" else "providers")
	elseif step == "github" and not github_in_flow() then
		M.step:set("providers")
	end
end)

local function finish(add: boolean)
	M.completed:set(true)
	M.step:set("")
	if add then
		projects.start()
	end
end

-- The device's place, as the agents step says it (the sample's is a Mac
-- unless the host says otherwise).
local function this_device(): string
	local platform = ui.shared("platform", ""):peek()
	return if platform == "macos" or platform == "" then "this Mac" else "this computer"
end

-- The agents on the providers page's device, installed.
local function installed(): { string }
	local device = agents.device:get()
	local status = agents.status:get()
	local out: { string } = {}
	for _, h in agents.HARNESSES do
		local s = status[`{device}:{h.id}`]
		if s and s.installed then
			table.insert(out, h.name)
		end
	end
	return out
end
local function agents_place(): string
	local device = agents.device:get()
	for _, d in agents.devices:get() do
		if d.id == device then
			return if d.you then this_device() else d.name
		end
	end
	return "that device"
end
-- "Claude Code", "Claude Code and Codex", "Claude Code, Codex and Cursor".
local function join(names: { string }): string
	if #names <= 1 then
		return names[1] or ""
	end
	return `{table.concat(names, ", ", 1, #names - 1)} and {names[#names]}`
end
-- Past three, the first two and a count.
local function short_names(names: { string }): string
	if #names > 3 then
		return `{names[1]}, {names[2]} and {#names - 2} more`
	end
	return join(names)
end

-- The sample engine's (⌘K): no agents on this device yet.
function M.sample_no_agents()
	local device = agents.device:peek()
	local all = table.clone(agents.status:peek())
	for k, s in all do
		if string.sub(k, 1, #device + 1) == `{device}:` then
			local now = table.clone(s)
			now.installed = false
			now.enabled = false
			now.version = nil
			now.latest = nil
			now.phase = "current"
			all[k] = now
		end
	end
	agents.status:set(all)
end

-- ---- setup's pieces ----

-- A page's headline and the line under it (the Settings header).
local function heading(title: Text, line: Text): Node
	return ui.column {
		w_full = true,
		gap = "$zeron.space.4",
		kit.text.text { title, size = "xxl", weight = "medium", line = false },
		kit.text.text { line, size = "md", color = T.secondary, wrap = true },
	}
end
-- A row's title over its muted explainer.
local function row_text(title: Text, detail: Text): Node
	return ui.column {
		grow = 1,
		min_w = 0,
		gap = "$zeron.space.2",
		kit.text.text { title, size = "md", weight = "medium" },
		kit.text.text { detail, size = "sm", color = T.secondary, wrap = true },
	}
end
local function card_row(id: string?, ...: Node): Node
	return ui.row {
		id = id,
		w_full = true,
		min_h = 60,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		gap = "$zeron.space.12",
		items = "center",
		{ ... },
	}
end
local function tile(glyph: string): Node
	return ui.row {
		w = 36,
		h = 36,
		shrink = 0,
		rounded = "$zeron.radius.10",
		bg = T.ink2,
		items = "center",
		justify = "center",
		kit.icon { name = glyph :: any, size = 16, color = T.secondary },
	}
end
-- The wide button the welcome and the ending end on: 36 high, radius 6,
-- in the text colour.
local function wide(id: string, label: string, run: () -> ()): Node
	return ui.button {
		id = id,
		w_full = true,
		h = 36,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = T.text,
		hover = { opacity = 0.9 },
		focus = { border = 0 },
		cursor = "pointer",
		on_click = run,
		kit.text.text { label, size = "lg", weight = "medium", color = T.bg, line = false },
	}
end
local function ghost(id: string, label: string, run: () -> ()): Node
	return kit.button { id = id, label = label, size = "sm", variant = "ghost", on_click = run }
end
local function primary(id: string, label: string, run: () -> (), enabled: (() -> boolean)?): Node
	return kit.button {
		id = id,
		label = label,
		size = "sm",
		variant = "primary",
		disabled = if enabled
			then function()
				return not enabled()
			end
			else nil,
		on_click = run,
	}
end

-- One segment a step, done and current in the accent; "2 of 3".
local function progress(): Node
	local segments: { Node } = {}
	for i = 1, 4 do
		table.insert(
			segments,
			ui.div {
				w = 20,
				h = 3,
				rounded = "$zeron.radius.2",
				hidden = function()
					return i > total()
				end,
				bg = function(): Color
					local n = number_of(if sync_slot() then "sync" else M.step:get()) or 0
					return if i <= n then T.accent else T.ink4
				end,
			}
		)
	end
	return ui.row {
		id = "onboarding_progress",
		h = 20,
		mb = "$zeron.space.28",
		gap = "$zeron.space.10",
		items = "center",
		shrink = 0,
		ui.row { gap = "$zeron.space.4", items = "center", segments },
		kit.text.text {
			function()
				local n = number_of(if sync_slot() then "sync" else M.step:get()) or 0
				return `{n} of {total()}`
			end,
			id = "onboarding_progress_label",
			size = "xs",
			color = T.tertiary,
			line = false,
		},
	}
end

local function welcome(): Node
	return ui.column {
		id = "onboarding_welcome",
		w_full = true,
		items = "center",
		kit.icon { name = "zeron-logo", size = 42, color = T.text },
		ui.text {
			"Welcome to Zeron",
			mt = "$zeron.space.28",
			font = T.sans,
			text_size = "$zeron.font.size.hero",
			weight = "$font.weight.semibold",
			color = T.text,
		},
		kit.text.text {
			"Run your coding agents side by side — on this computer, your other devices, or in the cloud.",
			size = "lg",
			color = T.secondary,
			align = "center",
			wrap = true,
			max_w = 360,
			mt = "$zeron.space.10",
		},
		ui.column {
			w = 320,
			mt = "$zeron.space.32",
			wide("onboarding_start", "Get started", function()
				M.step:set("appearance")
			end),
		},
	}
end

-- The new-chat wallpaper: an image of your own, then its treatment.
local function wallpaper(): Node
	local pref = require("./settings").pref
	local effects: { select.Option } = {}
	for i, e in settings_page.EFFECTS do
		table.insert(effects, { value = e.label, label = e.label, id = `onboarding_effect_{i}` })
	end
	return ui.column {
		w_full = true,
		mt = "$zeron.space.28",
		gap = "$zeron.space.10",
		kit.text.text { "New chat wallpaper", size = "md", color = T.secondary },
		ui.presence(pref.canvas_background, function(src: string): Node
			local chosen = src ~= ""
			local rows: { Node } = {
				card_row(
					"onboarding_wallpaper_row",
					ui.row {
						w = 36,
						h = 36,
						shrink = 0,
						rounded = "$zeron.radius.8",
						overflow = "hidden",
						bg = T.ink2,
						items = "center",
						justify = "center",
						if chosen
							then ui.image { src = src, label = "", w_full = true, h_full = true, fit = "cover" }
							else kit.icon { name = "gallery", size = 16, color = T.tertiary },
					},
					row_text(
						if chosen then string.match(src, "[^/]+$") or src else "None",
						"Shows behind every new chat."
					),
					ui.row {
						gap = "$zeron.space.8",
						shrink = 0,
						chosen and ghost("onboarding_wallpaper_remove", "Remove", function()
							pref.canvas_background:set("")
						end) or nil,
						kit.button {
							id = "onboarding_wallpaper_choose",
							label = if chosen then "Change" else "Choose image",
							size = "sm",
							on_click = function()
								pref.canvas_background:set(settings_page.SAMPLE_BACKGROUND)
							end,
						},
					}
				),
			}
			if chosen then
				table.insert(
					rows,
					card_row(
						"onboarding_effect_row",
						row_text("Effect", function()
							for _, e in settings_page.EFFECTS do
								if e.label == pref.canvas_effect:get() then
									return e.detail or ""
								end
							end
							return ""
						end),
						select {
							id = "onboarding_effect",
							label = "Background effect",
							value = pref.canvas_effect,
							options = effects,
							w = 128,
							menu_w = 220,
						}
					)
				)
			end
			return kit.settings.card(rows :: any)
		end, { w_full = true }),
	}
end

local function make_it_yours(): Node
	local look = state.look
	local modes: { Node } = {}
	for _, m in { "system", "light", "dark" } :: { appearance.Mode } do
		table.insert(
			modes,
			appearance.card {
				id = `onboarding_mode_{m}`,
				mode = m,
				selected = function()
					return look.mode:get() == m
				end,
				on_click = ui.set(look.mode, m),
			}
		)
	end
	return kit.scroll {
		id = "onboarding_appearance",
		label = "Make it yours",
		grow = 1,
		w_full = true,
		fade = 16,
		ui.column {
			w_full = true,
			heading("Make it yours", "Pick a look. You can change it any time in Settings → Appearance."),
			ui.column {
				w_full = true,
				mt = "$zeron.space.24",
				gap = "$zeron.space.12",
				kit.text.text { "Color scheme", size = "md", color = T.secondary },
				ui.row { gap = "$zeron.space.12", modes },
			},
			ui.column {
				w_full = true,
				mt = "$zeron.space.16",
				kit.settings.card {
					card_row(
						nil,
						kit.text.text { "Accent", size = "md", weight = "medium", grow = 1 },
						look_mod.swatches(look, "onboarding_accent")
					),
				},
			},
			wallpaper(),
		},
	}
end

-- One reason to sync, as a settings row.
local function benefit(glyph: string, title: string, detail: string): Node
	return card_row(nil, tile(glyph), row_text(title, detail))
end
local function sync_your_work(): Node
	return ui.column {
		id = "onboarding_sync",
		w_full = true,
		heading("Sync your work", "Log in to keep your chats, projects and settings in step everywhere you use Zeron."),
		ui.column {
			w_full = true,
			mt = "$zeron.space.24",
			kit.settings.card {
				benefit(
					"smartphone",
					"On every device",
					"Pick up a chat on your phone or another computer, right where you left it."
				),
				benefit(
					"remote-server",
					"Run agents anywhere",
					"Start work on any of your machines from whichever one you're at."
				),
				benefit(
					"cloud",
					"Zeron Cloud",
					"Hand chats to cloud machines that keep going while your computer sleeps."
				),
			},
		},
		ui.column {
			w_full = true,
			mt = "$zeron.space.28",
			kit.settings.card {
				ui.row {
					id = "onboarding_sync_status",
					w_full = true,
					min_h = 44,
					px = "$zeron.space.16",
					py = "$zeron.space.10",
					gap = "$zeron.space.10",
					items = "center",
					ui.presence(signed_in, function(on: boolean): Node
						return kit.icon {
							name = if on then "check" else "laptop",
							size = 14,
							color = if on then T.accent else T.secondary,
						}
					end),
					kit.text.text {
						function()
							local email = account.account:get().email
							return if email
								then `Signed in as {email}`
								else `Not ready? Everything stays on {this_device()} until you log in.`
						end,
						size = "sm",
						color = function()
							return if signed_in() then T.text else T.secondary
						end,
						grow = 1,
						min_w = 0,
						wrap = true,
					},
				},
			},
		},
	}
end

local function connect_github(): Node
	return ui.column {
		id = "onboarding_github",
		w_full = true,
		heading(
			"Connect GitHub",
			"Cloud agents work in your repositories on machines of their own. Connect GitHub so they can clone and push — or skip and do it later in Settings → Cloud."
		),
		ui.column { w_full = true, mt = "$zeron.space.24", cloud.github_step() },
	}
end

local function your_agents(): Node
	local pref = require("./settings").pref
	return ui.column {
		id = "onboarding_providers",
		w_full = true,
		h_full = true,
		ui.row {
			w_full = true,
			gap = "$zeron.space.12",
			items = "start",
			ui.column {
				grow = 1,
				min_w = 0,
				heading(function()
					return if #installed() == 0 then "Install an agent" else "Your agents"
				end, function()
					local names = installed()
					local place = agents_place()
					if #names == 0 then
						return `Zeron runs the coding agents you already use, and none are on {place} yet. Install one to continue.`
					end
					local found = if #names > 3 then `{#names} agents` else join(names)
					return `Found {found} on {place}. Sign in to any you'd like to use.`
				end),
			},
			agents.toolbar(),
		},
		ui.column {
			grow = 1,
			min_h = 0,
			w_full = true,
			mt = "$zeron.space.24",
			kit.scroll {
				id = "onboarding_agents",
				label = "Your agents",
				grow = 1,
				w_full = true,
				fade = 16,
				agents.provider_list(pref),
			},
		},
	}
end

local function all_set(): Node
	local look = state.look
	local function line(id: string, label: string, value: () -> string): Node
		return ui.row {
			id = id,
			w_full = true,
			min_h = 44,
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			gap = "$zeron.space.12",
			items = "center",
			justify = "between",
			kit.text.text { label, size = "md", color = T.secondary, line = false, shrink = 0 },
			kit.text.text { value, size = "md", truncate = true, min_w = 0, line = false },
		}
	end
	local rows: { Node } = {
		line("onboarding_summary_look", "Appearance", function()
			local mode = look.mode:get()
			local accent = look.accent:get()
			local label = "Theme"
			for _, a in look_mod.ACCENTS do
				if a.id == accent then
					label = a.label
				end
			end
			return `{string.upper(string.sub(mode, 1, 1))}{string.sub(mode, 2)} · {label}`
		end),
		line("onboarding_summary_sync", "Sync", function()
			local email = account.account:get().email
			return if email then `Signed in as {email}` else `Only on {this_device()}`
		end),
	}
	if github_in_flow() then
		table.insert(
			rows,
			line("onboarding_summary_github", "GitHub", function()
				return if cloud.github_connected() then "Connected" else "Not yet · Settings → Cloud"
			end)
		)
	end
	table.insert(
		rows,
		line("onboarding_summary_agents", "Agents", function()
			local names = installed()
			return if #names == 0 then "None yet" else short_names(names)
		end)
	)
	local more = has_projects:peek()
	return ui.column {
		id = "onboarding_done",
		w_full = true,
		items = "center",
		ui.row {
			w = 48,
			h = 48,
			rounded = T.radius_full,
			bg = T.accent_wash,
			items = "center",
			justify = "center",
			kit.icon { name = "check", size = 22, color = T.accent },
		},
		ui.text {
			"You're all set",
			mt = "$zeron.space.20",
			font = T.sans,
			text_size = "$zeron.font.size.headline",
			weight = "$font.weight.semibold",
			color = T.text,
		},
		kit.text.text {
			if more
				then "Pick a project and start a chat."
				else "Add a project to start your first chat. A project is a folder on one of your devices.",
			size = "md",
			color = T.secondary,
			align = "center",
			wrap = true,
			max_w = 340,
			mt = "$zeron.space.8",
		},
		ui.column { w = 400, mt = "$zeron.space.28", kit.settings.card(rows :: any) },
		ui.column {
			w = 320,
			mt = "$zeron.space.28",
			gap = "$zeron.space.14",
			items = "center",
			if more
				then wide("onboarding_finish", "Start using Zeron", function()
					finish(false)
				end)
				else wide("onboarding_add", "Add a project", function()
					finish(true)
				end),
			not more and ui.button {
				id = "onboarding_later",
				variants = kit.recipes.text_button,
				on_click = function()
					finish(false)
				end,
				kit.text.text { "I'll do this later", size = "sm", color = "inherit", line = false },
			} or nil,
		},
	}
end

-- What the step on show is, as a page's body.
local function body(key: string): Node
	local slot = string.match(key, "^sync:(.+)$")
	if slot then
		local p = sync.parts(slot)
		return ui.column {
			id = p.id,
			w_full = true,
			heading(p.title, p.body),
			p.block and ui.column { w_full = true, pt = "$zeron.space.24", p.block } or nil,
		}
	end
	if key == "appearance" then
		return make_it_yours()
	elseif key == "sync" then
		return sync_your_work()
	elseif key == "github" then
		return connect_github()
	elseif key == "providers" then
		return your_agents()
	end
	return ui.div {}
end

-- Back on the left; the step's way on at the right.
local function footer(key: string): Node
	local back: Node?, forward: { Node } = nil, {}
	local slot = string.match(key, "^sync:([^|]+)$")
	if slot then
		local p = sync.parts(slot)
		back, forward = p.back, p.forward or {}
	else
		local step = string.match(key, "^([^|]+)") or key
		back = ghost("onboarding_back", "Back", function()
			M.step:set(previous_of(M.step:peek()))
		end)
		local function go_on()
			M.step:set(next_of(M.step:peek()))
		end
		if step == "sync" and not signed_in() then
			forward = {
				ghost("onboarding_skip_sync", "Skip for now", function()
					M.step:set("providers")
				end),
				primary("onboarding_log_in", "Log in", function()
					awaiting:set(true)
					sync.enable()
				end),
			}
		elseif step == "github" then
			forward = {
				ui.presence(cloud.github_connected, function(connected: boolean): Node
					if connected then
						return primary("onboarding_continue", "Continue", go_on)
					end
					return ghost("onboarding_skip_github", "Skip for now", go_on)
				end),
			}
		elseif step == "providers" then
			forward = {
				ui.show(function()
					return #installed() == 0
				end, ghost("onboarding_skip_agents", "Skip for now", go_on)),
				primary("onboarding_continue", "Continue", go_on, function()
					return #installed() > 0
				end),
			}
		else
			forward = { primary("onboarding_continue", "Continue", go_on) }
		end
	end
	return ui.row {
		w_full = true,
		pt = "$zeron.space.24",
		items = "center",
		shrink = 0,
		ui.row { ml = T.pull(12), back },
		ui.div { grow = 1 },
		ui.row { gap = "$zeron.space.8", items = "center", forward },
	}
end

-- The column's height, for the wallpaper's clearing around it.
local column_h = ui.state("onboarding_column_h", 0)

local function setup(): Node
	return ui.column {
		id = "onboarding",
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		bg = T.clear,
		-- The new-chat wallpaper, clearing around the column.
		require("./conversation").artwork_around("onboarding_wallpaper", column_h),
		ui.row {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			h = "$zeron.titlebar.height",
			window_drag = true,
		},
		ui.column {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			pt = "$zeron.titlebar.height",
			pb = "$zeron.space.32",
			items = "center",
			justify = "center",
			ui.presence(function(): string
				return if number_of(M.step:get()) or sync_slot() then "numbered" else M.step:get()
			end, function(kind: string): Node
				local column: Node
				if kind ~= "numbered" then
					column = ui.column {
						w_full = true,
						max_w = 640,
						px = "$zeron.space.40",
						on_resize = function(size: { w: number, h: number })
							column_h:set(size.h)
						end,
						on_mount = function(el: Element)
							anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) })
						end,
						if kind == "welcome" then welcome() else all_set(),
					}
				else
					-- One frame for the numbered steps, so Back and the way on
					-- never move.
					column = ui.column {
						w_full = true,
						max_w = 640,
						h_full = true,
						min_h = 420,
						max_h = 640,
						px = "$zeron.space.40",
						on_resize = function(size: { w: number, h: number })
							column_h:set(size.h)
						end,
						on_mount = function(el: Element)
							anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) })
						end,
						progress(),
						ui.presence(shown, function(key: string): Node
							return ui.column { w_full = true, h_full = true, body(key) }
						end, {
							grow = 1,
							min_h = 0,
							w_full = true,
							enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) },
						}),
						ui.presence(function(): string
							local key = shown()
							return if string.match(key, "^sync:")
								then key
								else `{key}|{if key == "sync" then tostring(signed_in()) else ""}`
						end, footer, { w_full = true }),
					}
				end
				return ui.column { w_full = true, h_full = true, items = "center", justify = "center", column }
			end, { w_full = true, h_full = true }),
		},
	}
end

-- ---- the gates ----

-- The background over the grid's ends, fading out (gradients take
-- colours: the theme's, read as it is).
local function fade(angle: number): () -> Gradient
	return function(): Gradient
		local bg = tostring(ui.theme.get("background") or "#000000")
		return { angle = angle, stops = { { 0, bg }, { 1, `alpha({bg}, 0)` } } }
	end
end

local STEP = 44
local SPAN = 2640
local function grid(): Node
	local lines: { Node } = {}
	for i = 1, SPAN // STEP - 1 do
		table.insert(lines, ui.div { absolute = true, left = i * STEP, top = 0, bottom = 0, w = 1, bg = T.ink1 })
	end
	for i = 1, (SPAN * 3 // 4) // STEP - 1 do
		table.insert(lines, ui.div { absolute = true, top = i * STEP, left = 0, right = 0, h = 1, bg = T.ink1 })
	end
	return ui.div {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		overflow = "hidden",
		pointer_events = "none",
		lines,
		-- The grid fades into the background toward the window's edges.
		ui.div {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			h = 120,
			gradient = fade(180),
		},
		ui.div {
			absolute = true,
			left = 0,
			right = 0,
			bottom = 0,
			h = 120,
			gradient = fade(0),
		},
	}
end

-- The solid button: 36 high, radius 6, the text colour, 14 medium.
local function solid(id: string, label: Text, on_click: Handler, w_full: boolean?): Node
	return ui.button {
		id = id,
		w_full = w_full,
		h = 36,
		px = "$zeron.space.16",
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = T.text,
		hover = { opacity = 0.9 },
		focus = { border = 0 },
		cursor = "pointer",
		shrink = 0,
		on_click = on_click,
		kit.text.text { label, size = "lg", weight = "medium", color = T.bg, line = false },
	}
end

local function card(id: string, w: number, ...: Node): Node
	return ui.column {
		id = id,
		w = w,
		px = "$zeron.space.32",
		py = "$zeron.space.40",
		rounded = T.radius_card,
		border = 1,
		border_color = T.border,
		bg = T.card,
		shadow = T.shadow_lg,
		items = "center",
		on_mount = function(el: Element)
			anime.animate(
				el,
				{ opacity = { 0, 1 }, y = { 6, 0 }, duration = kit.motion.d(500), ease = kit.motion.EASE }
			)
		end,
		{ ... },
	}
end

local function sign_in(): Node
	return card(
		"onboarding_signin",
		360,
		kit.icon { name = "zeron-logo", size = 36, color = T.text },
		kit.text.text { "Log in to Zeron", size = "xl", weight = "semibold", mt = "$zeron.space.24", line = false },
		kit.text.text {
			"This opens your browser to finish logging in — you'll come right back.",
			size = "md",
			color = T.secondary,
			align = "center",
			wrap = true,
			mt = "$zeron.space.6",
			mb = "$zeron.space.24",
		},
		solid("onboarding_login", function()
			return if M.step:get() == "signing" then "Waiting for the browser…" else "Log in"
		end, function()
			if M.step:peek() ~= "signin" then
				return
			end
			M.step:set("signing")
			-- The browser hands the sign-in back.
			ui.after(1200, function()
				if M.step:peek() == "signing" then
					M.step:set("workspace")
				end
			end)
		end, true)
	)
end

local MEMBERSHIPS = { "Zeron", "Grid" }
local function create_workspace(): Node
	local function create()
		if workspace:peek() == "" or creating:peek() then
			return
		end
		creating:set(true)
		ui.after(600, function()
			creating:set(false)
			M.step:set("project")
		end)
	end
	local rows: { Node } = {}
	for i, name in MEMBERSHIPS do
		table.insert(
			rows,
			ui.button {
				id = `onboarding_member_{i}`,
				variants = kit.recipes.wash { hover = "ink2" },
				w_full = true,
				h = 36,
				px = "$zeron.space.12",
				gap = "$zeron.space.10",
				items = "center",
				rounded = "$zeron.radius.8",
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					M.step:set("project")
				end,
				ui.row {
					w = 20,
					h = 20,
					rounded = "$zeron.radius.5",
					bg = T.ink3,
					items = "center",
					justify = "center",
					kit.text.text { string.sub(name, 1, 1), size = "xs", weight = "medium", line = false },
				},
				kit.text.text { name, size = "md", grow = 1, line = false },
				kit.icon { name = "arrow-right", size = 14, color = T.tertiary },
			}
		)
	end
	return card(
		"onboarding_workspace",
		400,
		kit.icon { name = "zeron-logo", size = 28, color = T.text },
		kit.text.text { "Create your workspace", size = "xl", weight = "semibold", mt = "$zeron.space.20", line = false },
		kit.text.text {
			"Zeron is organized around workspaces — create one for yourself or your team.",
			size = "md",
			color = T.secondary,
			align = "center",
			wrap = true,
			mt = "$zeron.space.6",
			mb = "$zeron.space.24",
		},
		ui.row {
			w_full = true,
			gap = "$zeron.space.8",
			ui.input {
				id = "onboarding_workspace_name",
				value = workspace,
				label = "Workspace name",
				placeholder = "Workspace name",
				placeholder_color = T.tertiary,
				grow = 1,
				min_w = 0,
				h = 36,
				px = "$zeron.space.12",
				rounded = "$zeron.radius.8",
				border = 1,
				border_color = T.border,
				bg = T.bg,
				font = T.sans,
				text_size = "$font.size.md",
				color = T.text,
				on_key = function(e: KeyEvent): boolean
					if e.key == "Enter" then
						create()
						return true
					end
					return false
				end,
			},
			ui.column {
				opacity = function()
					return if creating:get() or workspace:get() == "" then 0.5 else 1
				end,
				solid("onboarding_create", function()
					return if creating:get() then "Creating…" else "Create"
				end, create),
			},
		},
		kit.text.text {
			"Or continue in a workspace you belong to",
			size = "xs",
			color = T.tertiary,
			mt = "$zeron.space.24",
			mb = "$zeron.space.8",
			line = false,
		},
		ui.column { w_full = true, gap = "$zeron.space.2", rows },
		ui.button {
			id = "onboarding_other_account",
			variants = kit.recipes.text_button,
			mt = "$zeron.space.24",
			on_click = function()
				M.step:set("signin")
			end,
			kit.text.text { "Use a different account", size = "sm", color = "inherit", line = false },
		}
	)
end

local function add_project(): Node
	return ui.column {
		id = "onboarding_project",
		items = "center",
		on_mount = function(el: Element)
			anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(500), ease = kit.motion.EASE })
		end,
		kit.icon { name = "zeron-logo", size = 48, color = T.ink3 },
		kit.text.text {
			"Add a project to get started",
			size = "xl",
			weight = "medium",
			mt = "$zeron.space.24",
			line = false,
		},
		kit.text.text {
			"A project is a folder on one of your devices.",
			size = "md",
			color = T.tertiary,
			mt = "$zeron.space.6",
			line = false,
		},
		ui.column {
			mt = "$zeron.space.20",
			-- The project flow over this; adding one ends it.
			solid("onboarding_add_project", "Add a project", function()
				projects.start()
			end),
		},
	}
end

local function gate(step: string): Node
	return ui.column {
		id = "onboarding",
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		bg = T.bg,
		items = "center",
		justify = "center",
		grid(),
		if step == "signin" then sign_in() elseif step == "workspace" then create_workspace() else add_project(),
	}
end

-- Over the window while a step shows.
function M.view(): Node
	return ui.presence(function()
		-- Nothing over the window once done (nor in the pointer's way).
		-- Setup is one page throughout; waiting on the browser is still the
		-- sign-in card.
		local step = M.step:get()
		if step == "" then
			return nil
		elseif SETUP[step] then
			return "setup"
		end
		return if step == "signing" then "signin" else step
	end, function(step: string): Node
		return if step == "setup" then setup() else gate(step)
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.SLOW) },
	})
end

-- A fresh install starts setup (a host that keeps what was finished
-- says it may be one); ZERON_ONBOARDING opens it at a step even when
-- finished.
local asked = tostring(ui.shared("onboarding", ""):peek() or "")
-- Once a launch (a reload keeps the window as it was).
local launched = ui.state("onboarding_launched", false)
if not launched:peek() then
	launched:set(true)
	if asked ~= "" then
		M.begin(true)
		M.step:set(if SETUP[asked] then asked :: Step else "welcome")
	elseif ui.shared("first_run", false):peek() == true and not M.completed:peek() then
		M.begin(true)
	end
end

return M
