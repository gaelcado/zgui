-- Cloud (settings/cloud.rs, cloud.rs; v0.2.129): the user's Cloud, where
-- every session runs on a machine of its own that sleeps when idle.
-- Settings → Cloud: Cloud's own row only when there is something to say
-- (turning on or off, a failure and Retry, its status out of reach); the
-- credits used over a chosen range, a bar a day; GitHub, for the
-- repositories Cloud sessions clone and push: connected by device code
-- ("Enter this code on GitHub", the code copied by a click or by Open
-- GitHub), Disconnect, Reconnect, and the repositories it reaches ("Choose
-- on GitHub", Private). Cloud turns itself on for an account offered it
-- as the page opens. Elsewhere: a Cloud session's machine asleep (the
-- session card, Files' Wake up), waking or starting as a message goes (the
-- working line), and the composer out of credits. The sample engine's;
-- its states on ⌘K.
local T = require("../theme")
local kit = require("@kit")
local select = require("@kit/select")
local button_kit = require("@kit/button")
local icon_kit = require("@kit/icon")
local billing = require("./billing")

local M = {}

-- Whether the account is offered Cloud (state.rs cloud_offered): Cloud
-- and Billing show in Settings only then.
M.offered = ui.state("cloud_offered", true)

-- The account: on ("ready"), off, being turned off, failed, or its status
-- out of reach ("unreachable", "loading" while Retry asks again).
export type Account = "ready" | "off" | "deleting" | "error" | "unreachable" | "loading"
M.account = ui.state("cloud_account", "ready" :: Account)
-- The call in flight ("enable", "delete"), and what failed last.
M.busy = ui.state("cloud_busy", "")
M.failure = ui.state("cloud_failure", { action = "enable", error = "" })

local STEP_MS = 1200
local SETTLE_MS = 1500

-- A step's timer, dropped when another starts.
local function after(ms: number, run: () -> ()): () -> boolean
	local live = true
	ui.after(ms, function()
		if live then
			run()
		end
	end)
	return function()
		local was = live
		live = false
		return was
	end
end

-- Cloud is on: there is a Cloud device for GitHub to be allowed on.
local function enabled(a: Account): boolean
	return a == "ready" or a == "error"
end
function M.enabled(): boolean
	return enabled(M.account:get())
end

-- GitHub for Cloud: connected, refused ("reconnect"), stored for other
-- devices only, or none; and the device flow under way.
export type Link = "connected" | "reconnect" | "other_devices" | "none"
M.github = ui.state("cloud_github", { link = "connected" :: Link, account = "gaelcado" })
export type Flow = { step: "idle" | "starting" | "waiting" | "failed", code: string, copied: boolean, error: string }
local IDLE: Flow = { step = "idle", code = "", copied = false, error = "" }
M.flow = ui.state("cloud_github_flow", IDLE)
-- A Disconnect or Connect (allowing a stored grant) in flight.
M.github_busy = ui.state("cloud_github_busy", false)

export type Repo = { name: string, private: boolean? }
local REPOS: { Repo } = {
	{ name = "gaelcado/zeron", private = true },
	{ name = "gaelcado/zgx" },
	{ name = "gaelcado/comet", private = true },
	{ name = "zeron-dev/website" },
	{ name = "zeron-dev/docs" },
	{ name = "gaelcado/rex", private = true },
	{ name = "gaelcado/tern" },
	{ name = "gaelcado/dotfiles" },
}
M.repos = ui.state("cloud_repos", REPOS)
M.refreshing = ui.state("cloud_repos_refreshing", false)
local SHOWN = 6

-- Usage: the range shown (UsageRange).
M.RANGES = { "Last 7 days", "Last 30 days", "This month", "Last month", "Last 90 days" }
M.range = ui.state("cloud_usage_range", "Last 30 days")

-- Each Cloud session's machine: asleep, waking, starting (a new one), or
-- ready. The sample's Cloud session is asleep.
export type Machine = "asleep" | "waking" | "new" | "starting" | "ready"
M.machines = ui.state("cloud_machines", { ["thread:h3"] = "asleep" } :: { [string]: Machine })
local WAKE_MS = 1800

-- Whether Settings → Cloud shows (it turns Cloud on as it opens).
local viewing = false

-- "enable" or "delete".
function M.run(action: string)
	if M.busy:peek() ~= "" then
		return
	end
	M.busy:set(action)
	after(STEP_MS, function()
		M.busy:set("")
		if billing.failing() then
			M.account:set("error")
			M.failure:set {
				action = action,
				error = if action == "enable" then "Sandbox failed to start" else "A session's machine didn't stop",
			}
			return
		end
		if action == "enable" then
			M.account:set("ready")
			return
		end
		-- Every session's machine stops, is metered and goes; the grant
		-- stays stored, no longer allowed on the next Cloud device.
		M.account:set("deleting")
		M.flow:set(IDLE)
		after(SETTLE_MS, function()
			M.account:set("off")
			local g = M.github:peek()
			if g.link ~= "none" then
				M.github:set { link = "other_devices", account = g.account }
			end
			if viewing then
				M.run("enable")
			end
		end)
	end)
end

-- The page opens: an account offered Cloud and not set up is set up now.
function M.visit()
	viewing = true
	if M.account:peek() == "off" then
		M.run("enable")
	end
end
function M.leave()
	viewing = false
end

-- Retry: the status asked again, or the action that failed repeated.
function M.retry()
	local a = M.account:peek()
	if a == "unreachable" then
		M.account:set("loading")
		after(700, function()
			M.account:set(if billing.failing() then "unreachable" else "ready")
		end)
	elseif a == "error" then
		M.account:set("ready")
		M.run(M.failure:peek().action)
	end
end

-- The sample engine's (⌘K).
function M.sample(kind: string)
	if kind == "off" then
		M.run("delete")
	elseif kind == "unreachable" then
		M.account:set("unreachable")
	elseif kind == "reconnect" then
		M.flow:set(IDLE)
		M.github:set { link = "reconnect", account = M.github:peek().account }
	elseif kind == "offer" then
		M.offered:set(not M.offered:peek())
	elseif kind == "asleep" then
		M.machines:set_key("thread:h3", "asleep")
	elseif kind == "new" then
		M.machines:set_key("thread:h3", "new")
	end
end

-- GitHub's device flow: a code to enter on GitHub, approved there (the
-- sample approves once GitHub opens).
local cancel_flow: (() -> boolean)? = nil
function M.start_github()
	if not M.enabled() then
		return
	end
	M.flow:set { step = "starting", code = "", copied = false, error = "" }
	cancel_flow = after(700, function()
		M.flow:set { step = "waiting", code = "WDJB-MJHT", copied = false, error = "" }
	end)
end
function M.cancel_github()
	if cancel_flow then
		cancel_flow()
	end
	M.flow:set(IDLE)
end
local uncopy: (() -> boolean)? = nil
function M.copy_code()
	local f = M.flow:peek()
	if f.code == "" then
		return
	end
	ui.clipboard.write(f.code)
	M.flow:set_key("copied", true)
	if uncopy then
		uncopy()
	end
	uncopy = after(1500, function()
		M.flow:set_key("copied", false)
	end)
end
-- Open GitHub copies the code too; the sample approves a moment later.
function M.open_github()
	M.copy_code()
	if cancel_flow then
		cancel_flow()
	end
	cancel_flow = after(1500, function()
		if M.flow:peek().step ~= "waiting" then
			return
		end
		if billing.failing() then
			M.flow:set { step = "failed", code = "", copied = false, error = "GitHub didn't approve the connection." }
			return
		end
		M.flow:set(IDLE)
		M.github:set { link = "connected", account = "gaelcado" }
		M.refresh_repos()
	end)
end
function M.disconnect()
	if M.github_busy:peek() then
		return
	end
	M.github_busy:set(true)
	after(700, function()
		M.github_busy:set(false)
		M.github:set { link = "none", account = "" }
	end)
end
-- A grant stored for other devices, allowed on Cloud too.
function M.authorize()
	if M.github_busy:peek() then
		return
	end
	M.github_busy:set(true)
	after(700, function()
		M.github_busy:set(false)
		M.github:set { link = "connected", account = M.github:peek().account }
	end)
end
function M.refresh_repos()
	if M.refreshing:peek() then
		return
	end
	M.refreshing:set(true)
	after(800, function()
		M.refreshing:set(false)
		M.repos:set(REPOS)
	end)
end
function M.github_connected(): boolean
	return M.enabled() and M.github:get().link == "connected"
end

-- ---- elsewhere ----

-- Whether `session` runs on Cloud.
function M.on_cloud(session: string): boolean
	return M.machines:peek()[session] ~= nil
end
-- `session`'s Cloud machine, if it runs on one.
function M.machine(session: string): Machine?
	return M.machines:get()[session]
end
function M.wake(session: string)
	local m = M.machines:peek()[session]
	if m ~= "asleep" and m ~= "new" then
		return
	end
	M.machines:set_key(session, if m == "new" then "starting" else "waking")
	after(WAKE_MS, function()
		M.machines:set_key(session, "ready")
	end)
end
-- A message to `session`: its machine wakes (or starts) first; how long
-- the reply waits on it.
function M.wake_for_send(session: string): number
	local m = M.machines:peek()[session]
	if m == "asleep" or m == "new" then
		M.wake(session)
		return WAKE_MS
	end
	return if m == "waking" or m == "starting" then WAKE_MS else 0
end
-- The working line while the send waits on the machine.
function M.working_label(session: string): string?
	local m = M.machines:get()[session]
	if m == "starting" then
		return "Starting a Cloud machine"
	elseif m == "waking" then
		return "Waking the Cloud machine"
	end
	return nil
end
-- Settings → Billing (zeron/settings opens it).
M.open_billing = nil :: (() -> ())?
-- Out of credits, a send to a Cloud session can't start or wake its
-- machine: a toast says so, with the way to Billing.
function M.blocks_send(session: string): boolean
	if M.machines:peek()[session] == nil or billing.total() > 0 then
		return false
	end
	kit.toast.push {
		title = "You're out of Cloud credits. Add credits to send.",
		tone = "danger",
		action = "Add credits",
		on_action = function()
			if M.open_billing then
				M.open_billing()
			end
		end,
	}
	return true
end

-- Files' place while the Cloud agent sleeps: why, and Wake up.
function M.asleep_files(session: string): Node
	local function waking(): boolean
		local m = M.machines:get()[session]
		return m == "waking" or m == "starting"
	end
	return ui.column {
		id = "files_cloud_asleep",
		grow = 1,
		w_full = true,
		px = "$zeron.space.28",
		gap = "$zeron.space.10",
		items = "center",
		justify = "center",
		kit.icon { name = "cloud", size = 20, color = T.tertiary },
		kit.text.text {
			function()
				return if waking() then "Waking up the Cloud agent…" else "Cloud agent is asleep"
			end,
			size = "sm",
			weight = "medium",
			align = "center",
		},
		kit.text.text {
			function()
				return if waking()
					then "Its files show as soon as it's up."
					else "Wake it to browse its files. Sending a message wakes it too."
			end,
			size = "sm",
			color = T.secondary,
			align = "center",
			wrap = true,
		},
		ui.presence(waking, function(now: boolean): Node
			if now then
				return ui.row { h = 28, items = "center", kit.loaders.mini_spinner { color = T.secondary } }
			end
			return kit.button {
				id = "files_cloud_wake",
				label = "Wake up",
				size = "sm",
				variant = "outlined",
				on_click = function()
					M.wake(session)
				end,
			}
		end),
	}
end

-- ---- the page ----

-- The 36 tile a row leads with.
local function tile(glyph: icon_kit.Name): Node
	return ui.row {
		w = 36,
		h = 36,
		shrink = 0,
		rounded = "$zeron.radius.10",
		bg = T.ink2,
		items = "center",
		justify = "center",
		kit.icon { name = glyph, size = 16, color = T.secondary },
	}
end
local function words(text: Text, color: Color?): Node
	return kit.text.text { text, size = "sm", color = color or T.secondary, wrap = true }
end
local function busy(text: string): Node
	return ui.row {
		gap = "$zeron.space.6",
		items = "center",
		kit.loaders.mini_spinner { color = T.secondary },
		kit.text.text { text, size = "sm", color = T.secondary, wrap = true, min_w = 0 },
	}
end
-- A row: the tile, its title over what it says, its actions at the end.
local function row(id: string, glyph: icon_kit.Name, title: string, meta: { Node }, actions: { Node }?): Node
	return ui.row {
		id = id,
		w_full = true,
		min_h = 60,
		px = "$zeron.space.16",
		py = "$zeron.space.12",
		gap = "$zeron.space.12",
		items = "center",
		tile(glyph),
		ui.column {
			grow = 1,
			min_w = 160,
			gap = "$zeron.space.2",
			kit.text.text { title, size = "md", weight = "medium" },
			#meta > 0 and ui.row { gap = "$zeron.space.6", items = "center", flex_wrap = true, meta } or nil,
		},
		actions and ui.row { gap = "$zeron.space.4", items = "center", shrink = 0, actions } or nil,
	}
end
local function action(
	id: string,
	label: Text,
	variant: button_kit.Variant,
	run: () -> (),
	enabled: (() -> boolean)?
): Node
	return kit.button {
		id = id,
		label = label,
		size = "sm",
		variant = variant,
		disabled = if enabled
			then function()
				return not enabled()
			end
			else nil,
		on_click = run,
	}
end
-- An action that leaves the app: its label, then the way-out glyph.
local function external(id: string, label: string, run: () -> ()): Node
	return kit.button {
		id = id,
		label = label,
		size = "sm",
		variant = "secondary",
		trailing = { name = "arrow-up-right", size = 12 },
		on_click = run,
	}
end

-- Cloud's own row, only when there is something to say.
-- `apart`: its space from what is above it (the page) or below (setup).
local function status(apart: "above" | "below"): Node
	return ui.presence(function(): string?
		local a = M.account:get()
		local b = M.busy:get()
		if a == "unreachable" then
			return "unreachable"
		elseif b ~= "" then
			return `busy:{b}`
		elseif a == "deleting" or a == "error" then
			return a
		end
		return nil
	end, function(phase: string): Node
		local meta: { Node }, actions: { Node } = {}, {}
		if phase == "unreachable" then
			meta = { words("Couldn't check Cloud: Engine not connected", T.danger_muted) }
			actions = { action("cloud_status_retry", "Retry", "secondary", M.retry) }
		elseif phase == "busy:enable" then
			meta = { busy("Turning on…") }
		elseif phase == "busy:delete" then
			meta = { busy("Turning off…") }
		elseif phase == "deleting" then
			meta = { busy("Turning off Cloud…") }
		else
			meta = {
				words(function()
					local e = M.failure:get().error
					return if e ~= "" then e else "Something went wrong with Cloud."
				end, T.danger_muted),
			}
			actions = { action("cloud_retry", "Retry", "ghost", M.retry) }
		end
		return ui.column {
			w_full = true,
			pt = if apart == "above" then "$zeron.space.28" else nil,
			pb = if apart == "below" then "$zeron.space.16" else nil,
			kit.settings.card { id = "cloud_status", row("cloud_status_row", "cloud", "Cloud", meta, actions) },
		}
	end, { w_full = true })
end

-- "Oct 5".
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function short_day(t: { month: number, day: number }): string
	return `{MONTHS[t.month]} {t.day}`
end
-- The range's days (inclusive, ending today) and what each used: the
-- sample's, the same for a day whatever the range.
type Day = { label: string, credits: number }
local function days_of(range: string): { Day }
	local DAY = 86400
	local today = os.time()
	local t = os.date("*t", today)
	local from: number, to: number = today, today
	if range == "Last 7 days" then
		from = today - 6 * DAY
	elseif range == "Last 30 days" then
		from = today - 29 * DAY
	elseif range == "Last 90 days" then
		from = today - 89 * DAY
	elseif range == "This month" then
		from = today - (t.day - 1) * DAY
	else
		to = today - t.day * DAY
		local last = os.date("*t", to)
		from = to - (last.day - 1) * DAY
	end
	local out: { Day } = {}
	local at = from
	while at <= to + 1 do
		local n = at // DAY
		local h = (n * 2654435761) % 4294967296
		h = (bit32.bxor(h, bit32.rshift(h, 13)) * 1274126177) % 4294967296
		local credits = if h % 5 == 0 then 0 else (h // 7) % 900 + 40
		local d = os.date("*t", at)
		table.insert(out, { label = short_day(d), credits = credits })
		at += DAY
	end
	return out
end

-- Credits over the chosen range against what's left, a bar a day.
local CHART_H = 88
local function usage(): Node
	local options: { select.Option } = {}
	for i, r in M.RANGES do
		table.insert(options, { value = r, label = r, id = `cloud_usage_range_{i}` })
	end
	return kit.settings.section {
		title = "Usage",
		id = "cloud_usage",
		ui.presence(M.range, function(range: string): Node
			local days = days_of(range)
			local used, peak = 0, 0
			for _, d in days do
				used += d.credits
				peak = math.max(peak, d.credits)
			end
			local bars: { Node } = {}
			for i, d in days do
				local ran = d.credits > 0
				table.insert(
					bars,
					ui.column {
						id = `cloud_usage_bar_{i}`,
						grow = 1,
						min_w = 1,
						h_full = true,
						justify = "end",
						ui.div {
							w_full = true,
							tooltip = `{d.label} · {billing.credits(d.credits)}`,
							-- A day that ran stays visible beside a busy one.
							h = if ran then math.max(d.credits / peak, 0.04) * CHART_H else 2,
							rounded = "$zeron.radius.2",
							bg = if ran then "$zeron.credits.used" else T.ink2,
						},
					}
				)
			end
			return ui.column {
				w_full = true,
				ui.row {
					w_full = true,
					min_h = 52,
					px = "$zeron.space.16",
					py = "$zeron.space.10",
					gap = "$zeron.space.16",
					items = "center",
					ui.column {
						grow = 1,
						min_w = 160,
						gap = "$zeron.space.2",
						kit.text.text {
							`{billing.credits(used)} used`,
							id = "cloud_usage_used",
							size = "md",
							weight = "medium",
						},
						kit.text.text {
							function()
								local left = billing.total()
								return if left <= 0 then "Out of credits" else `{billing.credits(left)} left`
							end,
							id = "cloud_usage_left",
							size = "sm",
							color = function()
								return if billing.total() <= 0 then T.warning_muted else T.secondary
							end,
						},
					},
					select {
						id = "cloud_usage_range",
						label = "Usage range",
						value = M.range,
						options = options,
						w = 128,
					},
				},
				ui.column {
					w_full = true,
					px = "$zeron.space.16",
					pb = "$zeron.space.12",
					gap = "$zeron.space.6",
					ui.row {
						id = "cloud_usage_chart",
						w_full = true,
						h = CHART_H,
						items = "end",
						gap = if #days > 45 then "$zeron.space.1" else "$zeron.space.3",
						bars,
					},
					ui.row {
						w_full = true,
						justify = "between",
						kit.text.text { days[1].label, size = "xs", color = T.tertiary, line = false },
						kit.text.text { days[#days].label, size = "xs", color = T.tertiary, line = false },
					},
				},
			}
		end, { w_full = true }),
	}
end

-- The device flow's row: what to do, the code (a click copies it), the
-- way to GitHub (which copies it too).
local function code_row(): Node
	return row("cloud_github_code_row", "key-minimalistic", "Enter this code on GitHub", {
		words("Approve Zeron there; this page moves on by itself."),
	}, {
		ui.button {
			id = "cloud_github_code",
			label = function()
				return `Copy GitHub code {M.flow:get().code}`
			end,
			tooltip = "Copy code",
			h = 32,
			px = "$zeron.space.12",
			gap = "$zeron.space.10",
			items = "center",
			rounded = "$zeron.radius.8",
			variants = kit.recipes.wash { rest = "ink2", hover = "ink4" },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = M.copy_code,
			kit.text.text {
				function()
					return M.flow:get().code
				end,
				mono = true,
				size = "lg",
				weight = "medium",
				line = false,
			},
			ui.presence(function(): string
				return if M.flow:get().copied then "check" else "copy"
			end, function(glyph: string): Node
				return kit.icon {
					name = glyph :: any,
					size = 14,
					color = if glyph == "check" then T.text else T.secondary,
				}
			end),
		},
		external("cloud_github_open", "Open GitHub", M.open_github),
	})
end

-- The repositories Cloud sessions can open, newest push first.
local function repositories(): Node
	return ui.column {
		id = "cloud_repos",
		w_full = true,
		row("cloud_repos_row", "git-branch", "Repositories", {
			words(function()
				local n = #M.repos:get()
				return if n == 0
					then "None yet: choose the repositories Cloud sessions can open."
					elseif n == 1 then "Cloud sessions can open 1 repository."
					else `Cloud sessions can open {n} repositories.`
			end),
		}, {
			ui.presence(M.refreshing, function(now: boolean): Node
				if now then
					return ui.row {
						w = 28,
						h = 28,
						items = "center",
						justify = "center",
						kit.loaders.mini_spinner { color = T.secondary },
					}
				end
				return kit.icon_button {
					id = "cloud_repos_refresh",
					icon = "refresh",
					size = 28,
					icon_size = 16,
					label = "Check repositories again",
					no_ring = true,
					on_click = M.refresh_repos,
				}
			end),
			external("cloud_github_install", "Choose on GitHub", function() end),
		}),
		ui.presence(function(): number
			return #M.repos:get()
		end, function(n: number): Node
			local rows: { Node } = {}
			for i, r in M.repos:peek() do
				if i > SHOWN then
					break
				end
				local owner = string.match(r.name, "^([^/]+)") or r.name
				table.insert(
					rows,
					ui.row {
						id = `cloud_repo_{i}`,
						w_full = true,
						min_h = 40,
						py = "$zeron.space.8",
						pl = "$zeron.space.24",
						pr = "$zeron.space.16",
						gap = "$zeron.space.12",
						items = "center",
						kit.avatar { name = owner, size = 20 },
						kit.text.text {
							r.name,
							literal = true,
							size = "md",
							truncate = true,
							grow = 1,
							min_w = 0,
							line = false,
						},
						r.private and kit.settings.badge("Private") or nil,
					}
				)
			end
			if n > SHOWN then
				table.insert(
					rows,
					ui.row {
						id = "cloud_repos_more",
						min_h = 36,
						py = "$zeron.space.8",
						pl = "$zeron.space.24",
						items = "center",
						words(`and {n - SHOWN} more`),
					}
				)
			end
			return ui.column { w_full = true, pb = "$zeron.space.4", rows }
		end, { w_full = true }),
	}
end

-- GitHub's block: where it stands and its way on, the code while one is
-- asked for, the repositories once connected. With Cloud off it is dimmed
-- and says why.
function M.github_block(): Node
	return ui.presence(function(): string?
		local a = M.account:get()
		if a == "unreachable" or a == "loading" then
			return nil
		end
		local f = M.flow:get()
		local g = M.github:get()
		if not enabled(a) then
			return "off"
		end
		if f.step ~= "idle" then
			return f.step
		end
		return g.link
	end, function(phase: string): Node
		local meta: { Node }, actions: { Node } = {}, {}
		local function connect(label: string, on: boolean): Node
			return action("cloud_github_connect", label, "secondary", M.start_github, function()
				return on
			end)
		end
		local g = M.github:peek()
		if phase == "off" then
			meta = { words("Turn on Cloud to connect GitHub.") }
			actions = { connect("Connect", false) }
		elseif phase == "starting" then
			meta = { busy("Contacting GitHub…") }
		elseif phase == "waiting" then
			meta = { busy("Waiting for you to approve on GitHub…") }
			actions = { action("cloud_github_cancel", "Cancel", "ghost", M.cancel_github) }
		elseif phase == "failed" then
			meta = { words(M.flow:peek().error, T.danger_muted) }
			actions = { connect("Try again", true) }
		elseif phase == "connected" then
			meta = { words(g.account, nil) }
			actions = {
				action(
					"cloud_github_disconnect",
					function()
						return if M.github_busy:get() then "Removing…" else "Disconnect"
					end,
					"ghost",
					M.disconnect,
					function()
						return not M.github_busy:get()
					end
				),
			}
		elseif phase == "reconnect" then
			meta = { words("Needs reconnect", T.warning_muted), words(g.account) }
			actions = { connect("Reconnect", true) }
		elseif phase == "other_devices" then
			meta = { words(g.account) }
			actions = {
				action(
					"cloud_github_authorize",
					function()
						return if M.github_busy:get() then "Connecting…" else "Connect"
					end,
					"secondary",
					M.authorize,
					function()
						return not M.github_busy:get()
					end
				),
			}
		else
			meta = { words("Not connected") }
			actions = { connect("Connect", true) }
		end
		return kit.settings.card {
			id = "cloud_github",
			ui.column {
				w_full = true,
				opacity = if phase == "off" then 0.6 else 1,
				row("cloud_github_row", "github-mark", "GitHub", meta, actions),
			},
			phase == "waiting" and code_row() or nil,
			phase == "connected" and repositories() or nil,
		}
	end, { w_full = true })
end

-- Cloud's status row and GitHub's block, for setup's GitHub step.
function M.github_step(): Node
	ui.on_cleanup(M.leave)
	return ui.column {
		w_full = true,
		on_mount = function()
			M.visit()
		end,
		status("below"),
		M.github_block(),
	}
end

-- The page, built while it shows.
function M.page(): Node
	ui.on_cleanup(M.leave)
	return ui.column {
		id = "cloud_page",
		w_full = true,
		max_w = kit.settings.WIDTH,
		self = "center",
		gap = "$zeron.space.32",
		on_mount = function()
			M.visit()
		end,
		ui.column {
			w_full = true,
			kit.settings.header { title = "Cloud", description = "Run your agents in cloud sandboxes." },
			status("above"),
		},
		ui.show(function()
			local a = M.account:get()
			return a ~= "unreachable" and a ~= "loading"
		end, ui.column { w_full = true, on_mount = kit.settings.anchor("cloud_usage"), usage() }),
		ui.show(
			function()
				local a = M.account:get()
				return a ~= "unreachable" and a ~= "loading"
			end,
			ui.column {
				w_full = true,
				gap = "$zeron.space.10",
				on_mount = kit.settings.anchor("cloud_github"),
				kit.text.text { "GitHub", size = "md", color = T.secondary },
				M.github_block(),
			}
		),
	}
end

return M
