-- Providers and Devices (settings/harnesses.rs, accounts.rs, devices.rs,
-- v0.2.129). Providers: the agents a device can run, chosen by the
-- header's device select (Cloud last), refreshed by its ↻ (a spinner while
-- it checks). A row: the 36 tile with the mark, the name over its version
-- ("v2.1.308 → v2.1.310" when an update can apply, the progress of one,
-- an install hint at 55% while it is not installed), Update or Install,
-- the chevron, the switch (none on Cloud). Opened: Completion, Delegation,
-- Updates (Notify, Auto when idle, Off) and the provider's accounts (the
-- avatar, the plan, "In use", two usage meters, ⋯ to switch or remove;
-- the add buttons, the sign-in dialog: the browser, a pasted code for
-- Claude, a failure to retry; an API key on Cloud). Devices: this one and
-- the others (Online, Asleep, Last seen), Copy ID and Rename. A check, an
-- install, an update or an accounts load can fail, and say so with a way
-- to retry; Auto when idle waits for the agent. Sample devices and flows
-- until the engine is wired.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local icon_button = require("./icon_button")
local button = require("./button")
local select = require("./select")
local settings = require("./settings")
local dialog = require("./dialog")
local menu = require("./menu")
local loaders = require("./loaders")
local account = require("./account")
local recipes = require("./recipes")
local tooltip = require("./tooltip")

local M = {}

-- The sample engine's next settings step fails (⌘K "Sample engine: Fail
-- the next settings step"): a load, a save, a check, an install, a
-- download. Whether this one does.
M.fail_next = ui.state("settings_fail_next", false)
function M.failing(): boolean
	if M.fail_next:peek() then
		M.fail_next:set(false)
		return true
	end
	return false
end

export type Device = {
	id: string,
	name: string,
	platform: string,
	version: string?,
	you: boolean?,
	-- How long since it was seen ("" online), or Cloud's presence.
	seen: string?,
	cloud: boolean?,
}
M.devices = ui.state(
	"settings_devices",
	{
		{
			id = "d7c1f0a2-41b9-4c55-9e3a-0f6b2c8d1e44",
			name = "MacBook Pro",
			platform = "macOS",
			version = "0.2.129",
			you = true,
		},
		{
			id = "4a90e2bb-7d13-4f0e-a1c6-92d5e8b37f10",
			name = "Mac mini",
			platform = "macOS",
			version = "0.2.126",
			seen = "2d ago",
		},
		{
			id = "b3f86c1d-0e27-49a8-bd54-6c1e7a9f2d03",
			name = "Build box",
			platform = "Linux",
			version = "0.2.129",
			seen = "",
		},
		{ id = "cloud", name = "Cloud", platform = "Cloud", cloud = true, seen = "Available" },
	} :: { Device }
)

export type Harness = {
	id: string,
	name: string,
	mark: string,
	tint: Color?,
	-- Its CLI as the hints name it.
	cli: string,
	-- How to install it by hand, when Zeron cannot.
	manual: string?,
	-- Whether it can hand work to native subagents.
	native: boolean?,
	-- The sign-ins it offers, if not one of its own.
	logins: { string }?,
}
M.HARNESSES = {
	{ id = "claude", name = "Claude Code", mark = "claude-mark", tint = T.claude, cli = "claude", native = true },
	{ id = "codex", name = "Codex", mark = "openai-mark", cli = "codex", native = true },
	{ id = "cursor", name = "Cursor", mark = "cursor-mark", cli = "cursor-agent" },
	{
		id = "opencode",
		name = "OpenCode",
		mark = "opencode-mark",
		cli = "opencode",
		logins = { "ChatGPT", "GitHub Copilot" },
	},
	{ id = "grok", name = "Grok", mark = "grok-mark", cli = "grok" },
	{
		id = "devin",
		name = "Devin",
		mark = "devin-mark",
		cli = "devin",
		manual = "curl -fsSL https://cli.devin.ai/install.sh | sh",
	},
} :: { Harness }

-- Where a provider stands on a device: installed and at what version,
-- an update's phase, on or off, its update policy.
export type Phase =
	"current"
	| "available"
	| "preparing"
	| "downloading"
	| "installing"
	| "verifying"
	| "updated"
	| "waiting"
	| "failed"
export type Status = {
	installed: boolean,
	version: string?,
	latest: string?,
	phase: Phase,
	enabled: boolean,
	installing: boolean?,
	policy: string,
	native: boolean?,
}
local function st(installed: boolean, version: string?, enabled: boolean, latest: string?): Status
	return {
		installed = installed,
		version = version,
		latest = latest,
		phase = if latest then "available" else "current",
		enabled = enabled,
		policy = "Notify",
		native = true,
	}
end
local MBP, MINI, BOX =
	"d7c1f0a2-41b9-4c55-9e3a-0f6b2c8d1e44",
	"4a90e2bb-7d13-4f0e-a1c6-92d5e8b37f10",
	"b3f86c1d-0e27-49a8-bd54-6c1e7a9f2d03"
M.status = ui.state(
	"settings_providers",
	{
		[`{MBP}:claude`] = st(true, "2.1.308", true, "2.1.310"),
		[`{MBP}:codex`] = st(true, "0.164.0", true),
		[`{MBP}:cursor`] = st(true, "1.7.2", false),
		[`{MBP}:opencode`] = st(false, nil, false),
		[`{MBP}:grok`] = st(false, nil, false),
		[`{MBP}:devin`] = st(false, nil, false),
		[`{MINI}:claude`] = st(true, "2.1.290", true),
		[`{MINI}:codex`] = st(false, nil, false),
		[`{BOX}:claude`] = st(true, "2.1.308", true),
		[`{BOX}:codex`] = st(true, "0.164.0", true),
		["cloud:claude"] = st(true, nil, true),
		["cloud:codex"] = st(true, nil, true),
	} :: { [string]: Status }
)

-- A provider's login: its plan, whether it is in use, its usage; why it has
-- none (the engine's `note`), or that its secret is out of reach.
export type Login = {
	email: string,
	plan: string,
	active: boolean?,
	session: number?,
	weekly: number?,
	note: string?,
	unswitchable: boolean?,
}
M.accounts = ui.state(
	"settings_accounts",
	{
		claude = {
			{ email = "cado.gael@gmail.com", plan = "Max 20x", active = true, session = 0.37, weekly = 0.84 },
			{ email = "work@zeron.sh", plan = "Pro", session = 0.12, weekly = 0.4 },
		},
		codex = { { email = "gael@zeron.dev", plan = "Plus", active = true, session = 0.62, weekly = 0.18 } },
		["cloud:claude"] = { { email = "Anthropic API key", plan = "API key …k3Qa", active = true } },
	} :: { [string]: { Login } }
)

M.device = ui.state("settings_providers_device", MBP)

local function key(device: string, harness: string): string
	return `{device}:{harness}`
end
-- Whether this device's Codex is installed and on: voice needs it
-- (VoiceController::offered).
function M.codex_ready(): boolean
	local s = M.status:get()[key(MBP, "codex")]
	return s ~= nil and s.installed and s.enabled
end
-- Accounts are the device's, Cloud's its own.
local function accounts_key(device: string, harness: string): string
	return if device == "cloud" then `cloud:{harness}` else harness
end

local function patch(k: string, change: (s: Status) -> ())
	local all = table.clone(M.status:peek())
	local s = all[k]
	if not s then
		return
	end
	local now = table.clone(s)
	change(now)
	all[k] = now
	M.status:set(all)
end

local function device_of(id: string): Device?
	for _, d in M.devices:peek() do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- An update, step by step (Preparing, Downloading, Installing, Verifying),
-- to Updated at the latest version.
local STEPS: { { phase: Phase, ms: number } } = {
	{ phase = "preparing", ms = 400 },
	{ phase = "downloading", ms = 900 },
	{ phase = "installing", ms = 600 },
	{ phase = "verifying", ms = 400 },
}
-- Refresh usage (accounts.rs load): the accounts and their usage asked
-- again; a login without usage says "Checking usage…" meanwhile. A failed
-- load says why, with Retry.
M.refreshing = ui.state("settings_accounts_refreshing", false)
M.accounts_error = ui.state("settings_accounts_error", "")
function M.refresh_accounts()
	if M.refreshing:peek() then
		return
	end
	M.refreshing:set(true)
	local fails = M.failing()
	ui.after(900, function()
		M.refreshing:set(false)
		M.accounts_error:set(if fails then "Couldn't load accounts: the device did not answer." else "")
	end)
end
-- The sample engine signs a login out: its usage gives way to why.
function M.sign_out_login()
	local all = table.clone(M.accounts:peek())
	local list: { Login } = {}
	for _, l in all.claude or {} do
		local now = table.clone(l)
		if not now.active then
			now.session, now.weekly = nil, nil
			now.note = "Signed out — sign in again"
		end
		table.insert(list, now)
	end
	all.claude = list
	M.accounts:set(all)
end

-- What went wrong on the page (an install, the update check), over its
-- rows; "" for nothing.
M.error = ui.state("settings_providers_error", "")
M.updates_error = ui.state("settings_providers_updates_error", "")

function M.update(k: string)
	local i = 0
	local fails = M.failing()
	local function next_step()
		i += 1
		local s = M.status:peek()[k]
		if not s or (i > 1 and s.phase ~= STEPS[i - 1].phase) then
			return
		end
		-- A failed download stops there (Update failed, Retry update).
		if fails and i == 3 then
			patch(k, function(x)
				x.phase = "failed"
			end)
			return
		end
		if i > #STEPS then
			patch(k, function(x)
				x.phase = "updated"
				x.version = x.latest or x.version
				x.latest = nil
			end)
			return
		end
		patch(k, function(x)
			x.phase = STEPS[i].phase
		end)
		ui.after(STEPS[i].ms, next_step)
	end
	next_step()
end
function M.cancel_update(k: string)
	patch(k, function(x)
		x.phase = "available"
	end)
end
-- With Auto when idle, an update waits for the agent's runs to end (the
-- sample's end a moment later), then installs itself.
function M.set_policy(k: string, policy: string)
	patch(k, function(x)
		x.policy = policy
		if policy == "Auto when idle" and x.phase == "available" then
			x.phase = "waiting"
		elseif policy ~= "Auto when idle" and x.phase == "waiting" then
			x.phase = "available"
		end
	end)
	local s = M.status:peek()[k]
	if s and s.phase == "waiting" then
		ui.after(1500, function()
			local now = M.status:peek()[k]
			if now and now.phase == "waiting" then
				M.update(k)
			end
		end)
	end
end

function M.install(k: string)
	M.error:set("")
	local fails = M.failing()
	patch(k, function(x)
		x.installing = true
	end)
	ui.after(1600, function()
		local s = M.status:peek()[k]
		if s and s.installing and fails then
			patch(k, function(x)
				x.installing = false
			end)
			M.error:set("Installation failed — npm exited with code 1")
		elseif s and s.installing then
			patch(k, function(x)
				x.installing = false
				x.installed = true
				x.enabled = true
				x.version = "1.0.4"
				x.phase = "current"
			end)
		end
	end)
end
function M.cancel_install(k: string)
	patch(k, function(x)
		x.installing = false
	end)
end

-- ↻: the device's agents found again and their updates checked; a newer
-- Codex turns up on this Mac.
M.checking = ui.state("settings_providers_checking", false)
function M.check()
	if M.checking:peek() then
		return
	end
	M.checking:set(true)
	M.updates_error:set("")
	local fails = M.failing()
	ui.after(900, function()
		M.checking:set(false)
		if fails then
			M.updates_error:set("Connection closed. Reconnecting to device…")
			return
		end
		local k = key(MBP, "codex")
		local s = M.status:peek()[k]
		if s and s.phase == "current" and s.version == "0.164.0" then
			patch(k, function(x)
				x.latest = "0.165.0"
				x.phase = "available"
			end)
		end
	end)
end

local UPDATING: { [string]: string } = {
	preparing = "Preparing update…",
	downloading = "Downloading…",
	installing = "Installing…",
	verifying = "Verifying…",
	waiting = "Waiting for agent to be idle",
	updated = "Updated",
}

-- The row's meta line (harnesses.rs status_text): the install's progress,
-- the hint while it is not installed, or the version and its update.
local function meta(h: Harness, device: string, s: Status): Node
	local function muted(text: string, color: Color?): Node
		return txt.text { text, literal = true, size = "sm", color = color or T.secondary, opacity = 0.75, line = false }
	end
	if s.installing then
		return ui.row {
			gap = "$zeron.space.6",
			items = "center",
			loaders.mini_spinner { color = T.secondary },
			muted(`Installing {h.name}…`),
		}
	end
	if device == "cloud" then
		local n = #(M.accounts:get()[accounts_key(device, h.id)] or {})
		return muted(if n == 0 then "No account" elseif n == 1 then "1 account" else `{n} accounts`)
	end
	if not s.installed then
		local hint = if s.enabled
			then `{h.cli} CLI not installed — turn it off or install it`
			else `Install the {h.cli} CLI to enable`
		if h.manual then
			hint = `{hint}. Install with {h.manual}`
		end
		return muted(hint)
	end
	local v = if s.version then `v{s.version}` else ""
	if s.phase == "available" and s.latest then
		return ui.row {
			gap = "$zeron.space.4",
			items = "center",
			muted(v),
			icon { name = "arrow-right", size = 11, color = T.tertiary },
			muted(`v{s.latest}`),
		}
	elseif s.phase == "failed" then
		return muted(`{v} · Update failed`, T.danger_muted)
	elseif UPDATING[s.phase] then
		return muted(`{v} · {UPDATING[s.phase]}`)
	end
	return muted(v)
end

-- What an update offers: Update, Retry update, or Cancel while it waits
-- or downloads.
local function update_action(k: string, s: Status, id: string): Node?
	local function small(id: string, label: string, primary: boolean, run: () -> ()): Node
		return ui.button {
			id = id,
			px = "$zeron.space.9",
			py = "$zeron.space.5",
			rounded = "$zeron.radius.6",
			bg = if primary then T.accent_wash else T.clear,
			hover = { bg = if primary then T.accent_lit else T.ink2 },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = run,
			txt.text {
				label,
				size = "xs",
				weight = if primary then "medium" else nil,
				color = if primary then T.accent else T.secondary,
				line = false,
			},
		}
	end
	if s.phase == "available" then
		return small(`{id}_update`, "Update", true, function()
			M.update(k)
		end)
	elseif s.phase == "failed" then
		return small(`{id}_update`, "Retry update", true, function()
			M.update(k)
		end)
	elseif s.phase == "preparing" or s.phase == "downloading" or s.phase == "waiting" then
		return small(`{id}_cancel_update`, "Cancel", false, function()
			M.cancel_update(k)
		end)
	end
	return nil
end

-- How many of the device's installed providers are on.
local function enabled_count(device: string): number
	local n = 0
	for k, s in M.status:get() do
		if string.sub(k, 1, #device + 1) == `{device}:` and s.installed and s.enabled then
			n += 1
		end
	end
	return n
end

local POLICIES: { select.Option } = {
	{ value = "Notify", label = "Notify", detail = nil },
	{ value = "Auto when idle", label = "Auto when idle" },
	{ value = "Off", label = "Off" },
}
local POLICY_NOTE: { [string]: string } = {
	Notify = "Install only when you choose Update.",
	["Auto when idle"] = "Install automatically after active runs finish.",
	Off = "Don't check for new versions.",
}

export type Completion = { dollar_skills: State<boolean>, separate_commands: State<boolean> }

-- A detail's row: 52 at least, its switch or select at the end.
-- Each detail's name for settings search.
local DETAIL_ANCHOR: { [string]: string } = {
	["Use $ for skills"] = "skill_dollar",
	["Separate / commands"] = "skill_slash",
	["Native subagents"] = "native_subagents",
	["Update policy"] = "update_policy",
}
local function detail_row(title: string, note: Text, control: Node): Node
	local anchor = DETAIL_ANCHOR[title]
	return ui.row {
		on_mount = if anchor then settings.anchor(anchor) else nil,
		w_full = true,
		min_h = 52,
		py = "$zeron.space.10",
		gap = "$zeron.space.16",
		items = "center",
		ui.column {
			grow = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { title, size = "md", weight = "medium" },
			txt.text { note, size = "sm", color = T.secondary, wrap = true },
		},
		control,
	}
end
local function label(text: string): Node
	return txt.text { text, size = "sm", weight = "medium", color = T.secondary, line = false }
end

-- The sign-in under way, if any: which provider, which of its sign-ins,
-- and its step.
export type Flow = {
	provider: string,
	option: string?,
	device: string,
	step: "starting" | "browser" | "code" | "verifying" | "failed",
	error: string?,
	-- Which attempt it is: a step answers only its own.
	attempt: number,
}
M.flow = ui.state("settings_sign_in", nil :: Flow?)
local flow_open = ui.state("settings_sign_in_open", false)

local function harness_of(id: string): Harness
	for _, h in M.HARNESSES do
		if h.id == id then
			return h
		end
	end
	return M.HARNESSES[1]
end

-- The browser's step, as each provider words it (accounts.rs
-- browser_copy; Cloud's own).
local function browser_copy(f: Flow): string
	local tail = "The new login is saved next to your current one — nothing changes until you switch."
	if f.device == "cloud" then
		local who = if f.provider == "codex" then "ChatGPT" else "Claude"
		return `Finish signing in to {who} in your browser. The login is stored for Cloud and becomes the account every Cloud machine uses; this computer's login is untouched.`
	elseif f.option == "GitHub Copilot" then
		return `Finish signing in to GitHub in your browser — enter the code shown below. {tail}`
	elseif f.option == "ChatGPT" then
		return "Finish signing in to ChatGPT in your browser. The agent gets its own login, saved next to any current one — nothing changes until you switch."
	elseif f.provider == "claude" then
		return `Finish signing in to Claude in your browser. {tail}`
	elseif f.provider == "codex" then
		return `Finish signing in to ChatGPT in your browser. {tail}`
	elseif f.provider == "devin" then
		return `Finish signing in to Devin in your browser. {tail}`
	elseif f.provider == "grok" then
		return `Finish signing in to Grok in your browser — approve the code shown below. {tail}`
	elseif f.provider == "cursor" then
		return "Finish signing in to Cursor in your browser. This mints a zeron-named API key you can revoke any time from Cursor's dashboard."
	end
	return "Finish signing in in your browser."
end

local function add_login(k: string, login: Login)
	local all = table.clone(M.accounts:peek())
	local list = table.clone(all[k] or {})
	table.insert(list, login)
	all[k] = list
	M.accounts:set(all)
end

local NEW_LOGIN: { [string]: Login } = {
	claude = { email = "gael@zeron.dev", plan = "Pro", session = 0.04, weekly = 0.02 },
	codex = { email = "cado.gael@gmail.com", plan = "Pro", session = 0.0, weekly = 0.11 },
	cursor = { email = "gael@zeron.dev", plan = "Pro" },
	opencode = { email = "gael@zeron.dev", plan = "ChatGPT Plus" },
	devin = { email = "gael@zeron.dev", plan = "Core" },
}

local function finish(f: Flow)
	local base: Login = NEW_LOGIN[f.provider] or { email = "gael@zeron.dev", plan = "Pro" }
	local login = table.clone(base)
	if f.option == "GitHub Copilot" then
		login.plan = "GitHub Copilot"
	end
	add_login(accounts_key(f.device, f.provider), login)
	flow_open:set(false)
	M.flow:set(nil)
end

-- Start a sign-in: the browser opens; Claude's hands back a code to paste,
-- Cursor's agent does not answer the first time (the failure to retry),
-- the rest come back signed in.
local failed_once: { [string]: boolean } = {}
local attempts = 0
local function current(attempt: number): boolean
	local f = M.flow:peek()
	return f ~= nil and f.attempt == attempt
end
function M.sign_in(device: string, provider: string, option: string?)
	attempts += 1
	local f: Flow = { provider = provider, option = option, device = device, step = "starting", attempt = attempts }
	M.flow:set(f)
	flow_open:set(true)
	ui.after(400, function()
		if not current(f.attempt) then
			return
		end
		local now = table.clone(f)
		now.step = "browser"
		M.flow:set(now)
		ui.after(1400, function()
			if not current(now.attempt) or (M.flow:peek() :: Flow).step ~= "browser" then
				return
			end
			if provider == "claude" and device ~= "cloud" then
				local code = table.clone(now)
				code.step = "code"
				M.flow:set(code)
			elseif provider == "cursor" and not failed_once.cursor then
				failed_once.cursor = true
				local failed = table.clone(now)
				failed.step = "failed"
				failed.error = "Couldn't start the sign-in: cursor-agent did not answer"
				M.flow:set(failed)
			else
				finish(now)
			end
		end)
	end)
end

local function sign_in_dialog(): Node
	return ui.presence(function(): string?
		local f = M.flow:get()
		return if flow_open:get() and f then `{f.provider}:{f.option or ""}:{f.device}` else nil
	end, function(): Node
		local code = ui.use_state("")
		local function step(): string
			local f = M.flow:get()
			return if f then f.step else ""
		end
		local f0 = M.flow:peek() :: Flow
		local h = harness_of(f0.provider)
		local title = if f0.option then `Sign in to {f0.option} for {h.name}` else `Sign in to {h.name}`
		local function cancel()
			flow_open:set(false)
			M.flow:set(nil)
		end
		local function submit()
			local f = M.flow:peek()
			if not f or code:peek() == "" or f.step == "verifying" then
				return
			end
			local verifying = table.clone(f)
			verifying.step = "verifying"
			verifying.error = nil
			M.flow:set(verifying)
			ui.after(700, function()
				if not current(verifying.attempt) or (M.flow:peek() :: Flow).step ~= "verifying" then
					return
				end
				if #code:peek() < 12 then
					local back = table.clone(verifying)
					back.step = "code"
					back.error = "That code didn't work. Copy it again from your browser and paste it here."
					M.flow:set(back)
				else
					finish(verifying)
				end
			end)
		end
		return dialog {
			id = "sign_in_dialog",
			open = flow_open,
			title = title,
			w = 420,
			on_enter = submit,
			ui.column {
				w = 378,
				gap = "$zeron.space.6",
				mt = T.pull(10),
				txt.text {
					function()
						local f = M.flow:get()
						if f and (f.step == "code" or f.step == "verifying") then
							return "Your browser opened Claude's sign-in page. Approve access, then paste the code Anthropic shows you below. Your current login is untouched until you switch."
						end
						return if f then browser_copy(f) else ""
					end,
					size = "md",
					color = T.secondary,
					wrap = true,
				},
				ui.show(
					function()
						return step() ~= "starting" and step() ~= "failed"
					end,
					ui.button {
						id = "sign_in_reopen",
						variants = recipes.text_button,
						self = "start",
						txt.text { "Reopen the sign-in page", size = "sm", color = "inherit", line = false },
					}
				),
			},
			ui.presence(function(): string
				local s = step()
				return if s == "verifying" then "code" else s
			end, function(s: string): Node
				if s == "code" then
					return ui.column {
						w_full = true,
						gap = "$zeron.space.6",
						ui.input {
							id = "sign_in_code",
							value = code,
							label = "Authorization code",
							placeholder = "Paste the authorization code",
							placeholder_color = T.tertiary,
							w_full = true,
							h = 36,
							px = "$zeron.space.12",
							rounded = "$zeron.radius.8",
							border = 1,
							border_color = T.border,
							bg = T.ink1,
							font = T.mono,
							text_size = "$font.size.md",
							color = T.text,
							on_mount = function(el: Element)
								el:focus()
							end,
						},
						ui.show(
							function()
								local f = M.flow:get()
								return f ~= nil and f.error ~= nil
							end,
							txt.text {
								function()
									local f = M.flow:get()
									return if f then f.error or "" else ""
								end,
								id = "sign_in_error",
								size = "sm",
								color = T.danger,
								wrap = true,
							}
						),
					}
				elseif s == "failed" then
					return txt.text {
						function()
							local f = M.flow:get()
							return if f then f.error or "The sign-in failed." else ""
						end,
						id = "sign_in_error",
						size = "sm",
						color = T.danger,
						wrap = true,
					}
				end
				return ui.row {
					gap = "$zeron.space.10",
					items = "center",
					mt = "$zeron.space.6",
					loaders.gradient_spinner {},
					txt.text {
						if s == "starting"
							then "Starting sign-in…"
							else "Waiting for you to finish in the browser…",
						id = "sign_in_status",
						size = "md",
						color = T.secondary,
						line = false,
					},
				}
			end, { w_full = true }),
			ui.presence(function(): string
				local s = step()
				return if s == "failed" then "failed" elseif s == "code" or s == "verifying" then "code" else "wait"
			end, function(s: string): Node
				local buttons: { Node } = {}
				if s == "failed" then
					table.insert(
						buttons,
						button {
							id = "sign_in_close",
							label = "Close",
							size = "sm",
							variant = "ghost",
							on_click = cancel,
						}
					)
					table.insert(
						buttons,
						button {
							id = "sign_in_retry",
							label = "Retry",
							size = "sm",
							variant = "primary",
							on_click = function()
								M.sign_in(f0.device, f0.provider, f0.option)
							end,
						}
					)
				else
					table.insert(
						buttons,
						button {
							id = "sign_in_cancel",
							label = "Cancel",
							size = "sm",
							variant = "ghost",
							on_click = cancel,
						}
					)
					if s == "code" then
						table.insert(
							buttons,
							ui.column {
								opacity = function()
									return if step() == "verifying" then 0.5 else 1
								end,
								button {
									id = "sign_in_submit",
									label = function()
										return if step() == "verifying" then "Verifying…" else "Add account"
									end,
									size = "sm",
									variant = "primary",
									on_click = submit,
								},
							}
						)
					end
				end
				return ui.row { w_full = true, mt = "$zeron.space.6", gap = "$zeron.space.8", justify = "end", buttons }
			end, { w_full = true }),
		}
	end)
end

-- An account's row (accounts.rs render_account_row): the avatar ringed in
-- the accent while it is the one in use, its address over its plan and
-- "In use", two usage meters, ⋯ to switch to it or remove it; a click on
-- another switches to it.
local function account_row(id: string, list_key: string, index: number, login: Login): Node
	local open = ui.use_state(false)
	local function switch()
		local all = table.clone(M.accounts:peek())
		local list: { Login } = {}
		for i, l in all[list_key] or {} do
			local now = table.clone(l)
			now.active = i == index
			table.insert(list, now)
		end
		all[list_key] = list
		M.accounts:set(all)
	end
	local function remove()
		local all = table.clone(M.accounts:peek())
		local list: { Login } = {}
		for i, l in all[list_key] or {} do
			if i ~= index then
				table.insert(list, l)
			end
		end
		all[list_key] = list
		M.accounts:set(all)
	end
	local active = login.active == true
	local items: { menu.Entry } = {}
	if not active then
		local to: menu.Item = { id = `{id}_switch`, label = "Switch to this account", on_click = switch }
		table.insert(items, to)
	end
	local gone: menu.Item = { id = `{id}_remove`, label = "Remove account", danger = true, on_click = remove }
	table.insert(items, gone)
	local metas: { Node } = { txt.text { login.plan, literal = true, size = "sm", color = T.secondary, line = false } }
	if active then
		table.insert(metas, txt.text { "·", size = "sm", color = T.tertiary, opacity = 0.6, line = false })
		table.insert(metas, txt.text { "In use", size = "sm", color = T.accent, line = false })
	end
	-- No meters: why (render_usage_missing): a login whose secret is gone,
	-- the engine's reason, a refresh under way, or nothing known.
	if login.session == nil then
		table.insert(metas, txt.text { "·", size = "sm", color = T.tertiary, opacity = 0.6, line = false })
		table.insert(
			metas,
			txt.text {
				function()
					if login.unswitchable then
						return if string.sub(list_key, -6) == "claude"
							then "Credentials unavailable"
							else "Couldn't identify this login"
					elseif login.note then
						return login.note
					end
					return if M.refreshing:get() then "Checking usage…" else "Usage unavailable"
				end,
				size = "sm",
				color = T.secondary,
				line = false,
			}
		)
	end
	return ui.row {
		id = id,
		w_full = true,
		min_h = 56,
		p = "$zeron.space.10",
		gap = "$zeron.space.14",
		items = "center",
		rounded = "$zeron.radius.10",
		bg = T.clear,
		hover = if active then nil else { bg = T.ink1 },
		cursor = if active then nil else "pointer",
		on_click = if active then nil else switch,
		ui.row {
			w = 32,
			h = 32,
			shrink = 0,
			border = 1.5,
			variants = recipes.account_ring { active = active },
			ui.row {
				w = 25,
				h = 25,
				rounded = T.radius_full,
				bg = T.ink3,
				items = "center",
				justify = "center",
				txt.text {
					string.upper(string.sub(login.email, 1, 1)),
					literal = true,
					size = "xs",
					weight = "medium",
					color = "inherit",
					line = false,
				},
			},
		},
		ui.column {
			grow = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { login.email, literal = true, size = "md", weight = "medium", truncate = true, line = false },
			ui.row { gap = "$zeron.space.6", items = "center", metas },
		},
		login.session ~= nil and ui.column {
			w = 190,
			shrink = 0,
			gap = "$zeron.space.2",
			account.meter { label = "Session", level = login.session or 0 },
			account.meter { label = "Week", level = login.weekly or 0 },
		} or nil,
		menu.menu {
			id = `{id}_menu`,
			open = open,
			w = 208,
			placement = { side = "bottom", align = "end", offset = 4 },
			rows = "popover",
			anchor = icon_button {
				id = `{id}_more`,
				icon = "more-horizontal",
				size = 28,
				icon_size = 16,
				label = `Actions for {login.email}`,
				no_ring = true,
				on_click = ui.toggle(open),
			},
			items = items,
		},
	}
end

-- A provider's accounts, opened under its row (accounts.rs
-- render_embedded_accounts): its logins, then its add buttons (and on
-- Cloud, an API key typed in).
local function accounts_of(h: Harness, device: string): Node
	local k = accounts_key(device, h.id)
	local adding_key = ui.use_state(false)
	local api_key = ui.use_state("")
	local key_error = ui.use_state("")
	local saving = ui.use_state(false)
	local id = `provider_{h.id}_accounts`
	local function save_key()
		local typed = api_key:peek()
		if typed == "" then
			key_error:set("Paste a key first.")
			return
		end
		saving:set(true)
		ui.after(600, function()
			saving:set(false)
			adding_key:set(false)
			add_login(k, {
				email = if h.id == "codex" then "OpenAI API key" else "Anthropic API key",
				plan = `API key …{string.sub(typed, -4)}`,
			})
			api_key:set("")
		end)
	end
	return ui.column {
		w_full = true,
		gap = "$zeron.space.4",
		ui.row {
			w_full = true,
			items = "center",
			label("Accounts"),
			ui.show(
				M.refreshing,
				ui.row {
					id = `{id}_refreshing`,
					ml = "$zeron.space.6",
					loaders.mini_spinner { color = T.secondary },
				}
			),
			ui.div { grow = 1 },
			ui.column {
				opacity = function()
					return if M.refreshing:get() then 0.5 else 1
				end,
				tooltip {
					label = "Refresh usage",
					icon_button {
						id = `{id}_refresh`,
						icon = "refresh",
						size = 28,
						icon_size = 14,
						label = "Refresh accounts",
						no_ring = true,
						on_click = M.refresh_accounts,
					},
				},
			},
		},
		ui.presence(function(): string
			if M.accounts_error:get() ~= "" then
				return "error"
			end
			local list = M.accounts:get()[k] or {}
			local parts = {}
			for _, l in list do
				table.insert(parts, `{l.email}:{l.plan}:{if l.active then 1 else 0}:{l.note or ""}:{l.session or ""}`)
			end
			return table.concat(parts, "|")
		end, function(state: string): Node
			if state == "error" then
				return ui.button {
					id = `{id}_retry`,
					label = "Retry loading accounts",
					w_full = true,
					mt = "$zeron.space.4",
					px = "$zeron.space.12",
					py = "$zeron.space.8",
					gap = "$zeron.space.8",
					items = "center",
					rounded = T.radius_button,
					bg = T.danger_wash,
					focus = { border = 0 },
					cursor = "pointer",
					on_click = M.refresh_accounts,
					txt.text {
						M.accounts_error:peek(),
						literal = true,
						size = "sm",
						color = T.danger,
						grow = 1,
						wrap = true,
					},
					txt.text { "Retry", size = "sm", color = T.secondary, line = false },
				}
			end
			local rows: { Node } = {}
			for i, l in M.accounts:peek()[k] or {} do
				table.insert(rows, account_row(`{id}_{i}`, k, i, l))
			end
			return ui.column { w_full = true, gap = "$zeron.space.2", rows }
		end, { w_full = true }),
		ui.presence(function(): number
			return #(M.accounts:get()[k] or {})
		end, function(n: number): Node
			local buttons: { Node } = {}
			local logins = h.logins or { "" }
			for i, option in logins do
				local text = if option == ""
					then (if n == 0 then `Connect a {h.name} account` else "Add account")
					else (if n == 0 then `Connect {option}` else `Add {option} account`)
				table.insert(
					buttons,
					button {
						id = `{id}_add_{i}`,
						label = text,
						size = "sm",
						variant = "ghost",
						icon = { name = "plus", size = 14 },
						on_click = function()
							M.sign_in(device, h.id, if option == "" then nil else option)
						end,
					}
				)
			end
			if device == "cloud" and (h.id == "claude" or h.id == "codex") then
				table.insert(
					buttons,
					ui.show(
						function()
							return not adding_key:get()
						end,
						button {
							id = `{id}_add_key`,
							label = if h.id == "codex" then "Add OpenAI API key" else "Add Anthropic API key",
							size = "sm",
							variant = "ghost",
							icon = { name = "plus", size = 14 },
							on_click = function()
								adding_key:set(true)
							end,
						}
					)
				)
			end
			return ui.row { w_full = true, py = "$zeron.space.8", gap = "$zeron.space.4", flex_wrap = true, buttons }
		end, { w_full = true }),
		ui.show(
			adding_key,
			ui.column {
				w_full = true,
				gap = "$zeron.space.6",
				ui.row {
					w_full = true,
					gap = "$zeron.space.8",
					ui.input {
						id = `{id}_key`,
						value = api_key,
						label = if h.id == "codex" then "OpenAI API key" else "Anthropic API key",
						placeholder = if h.id == "codex" then "OpenAI API key" else "Anthropic API key",
						placeholder_color = T.tertiary,
						secure = true,
						grow = 1,
						h = 32,
						px = "$zeron.space.10",
						rounded = "$zeron.radius.8",
						border = 1,
						border_color = T.border,
						bg = T.ink1,
						text_size = "$font.size.md",
						color = T.text,
						on_mount = function(el: Element)
							el:focus()
						end,
						on_key = function(e: KeyEvent): boolean
							if e.key == "Enter" then
								save_key()
								return true
							elseif e.key == "Escape" then
								adding_key:set(false)
								return true
							end
							return false
						end,
					},
					button {
						id = `{id}_key_cancel`,
						label = "Cancel",
						size = "sm",
						variant = "ghost",
						on_click = function()
							adding_key:set(false)
						end,
					},
					button {
						id = `{id}_key_save`,
						label = function()
							return if saving:get() then "Saving…" else "Save key"
						end,
						size = "sm",
						variant = "primary",
						on_click = save_key,
					},
				},
				txt.text {
					function()
						local e = key_error:get()
						return if e ~= ""
							then e
							else "Stored encrypted in your account for Cloud. It becomes the account Cloud machines use."
					end,
					size = "sm",
					color = function(): Color
						return if key_error:get() ~= "" then T.danger else T.secondary
					end,
					wrap = true,
				},
			}
		),
	}
end

-- A provider's row and, opened, its details.
local function provider_row(h: Harness, device: string, completion: Completion): Node
	local k = key(device, h.id)
	local id = `provider_{h.id}`
	local open = ui.use_state(false)
	local cloud = device == "cloud"
	local function s(): Status
		return M.status:get()[k]
	end
	local function can_open(): boolean
		return cloud or s().enabled
	end
	-- The last installed one on stays on; one not installed cannot come on.
	local enabled = ui.use_state(M.status:peek()[k].enabled)
	ui.effect(function()
		local now = enabled:get()
		local was = M.status:peek()[k]
		if was.enabled ~= now then
			patch(k, function(x)
				x.enabled = now
			end)
			if not now then
				open:set(false)
			end
		end
	end)
	ui.effect(function()
		local now = s().enabled
		if enabled:peek() ~= now then
			enabled:set(now)
		end
	end)
	local function locked(): boolean
		local x = s()
		return (x.enabled and x.installed and enabled_count(device) <= 1) or (not x.enabled and not x.installed)
	end
	local policy = ui.use_state(M.status:peek()[k].policy)
	ui.effect(function()
		local p = policy:get()
		if M.status:peek()[k].policy ~= p then
			M.set_policy(k, p)
		end
	end)
	local native = ui.use_state(M.status:peek()[k].native ~= false)
	ui.effect(function()
		local n = native:get()
		if (M.status:peek()[k].native ~= false) ~= n then
			patch(k, function(x)
				x.native = n
			end)
		end
	end)
	local function details(): Node
		local sections: { Node } = {
			ui.column {
				w_full = true,
				label("Completion"),
				detail_row(
					"Use $ for skills",
					"Type $ in the composer to pick a skill.",
					settings.switch { id = `{id}_dollar_skills`, value = completion.dollar_skills }
				),
				detail_row(
					"Separate / commands",
					"Keep skills out of the / menu.",
					settings.switch { id = `{id}_separate_commands`, value = completion.separate_commands }
				),
			},
		}
		if h.native and not cloud then
			table.insert(
				sections,
				ui.column {
					w_full = true,
					label("Delegation"),
					detail_row(
						"Native subagents",
						"Off: delegate through side chats, from each chat's next turn.",
						settings.switch { id = `{id}_native`, value = native }
					),
				}
			)
		end
		if not cloud then
			local options: { select.Option } = {}
			for i, p in POLICIES do
				table.insert(options, { value = p.value, label = p.label, id = `{id}_policy_{i}` })
			end
			table.insert(
				sections,
				ui.column {
					w_full = true,
					label("Updates"),
					detail_row(
						"Update policy",
						function()
							return POLICY_NOTE[policy:get()] or POLICY_NOTE.Notify
						end,
						select { id = `{id}_policy`, label = "Update policy", value = policy, options = options, w = 136 }
					),
				}
			)
		end
		table.insert(sections, accounts_of(h, device))
		return ui.column {
			id = `{id}_details`,
			w_full = true,
			pl = 68,
			pr = "$zeron.space.16",
			pb = "$zeron.space.16",
			gap = "$zeron.space.20",
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, y = { -4, 0 }, duration = 140 })
			end,
			sections,
		}
	end
	return ui.column {
		id = id,
		w_full = true,
		ui.row {
			id = `{id}_row`,
			w_full = true,
			min_h = 60,
			px = "$zeron.space.12",
			py = "$zeron.space.8",
			gap = "$zeron.space.16",
			items = "center",
			opacity = function()
				local x = s()
				return if not x.installed and not x.installing then 0.55 else 1
			end,
			ui.button {
				id = `{id}_trigger`,
				label = `{h.name} preferences`,
				grow = 1,
				min_w = 180,
				min_h = 44,
				px = "$zeron.space.4",
				gap = "$zeron.space.12",
				items = "center",
				rounded = "$zeron.radius.8",
				bg = T.clear,
				focus = { border = 0 },
				cursor = function()
					return if can_open() then "pointer" else "default"
				end,
				expanded = open,
				on_click = function()
					if can_open() then
						open:set(not open:peek())
					end
				end,
				ui.row {
					w = 36,
					h = 36,
					shrink = 0,
					rounded = "$zeron.radius.10",
					bg = T.ink2,
					items = "center",
					justify = "center",
					icon { name = h.mark :: any, size = 16, color = h.tint or T.secondary },
				},
				ui.column {
					grow = 1,
					min_w = 0,
					gap = "$zeron.space.2",
					txt.text { h.name, size = "md", weight = "medium", line = false },
					ui.presence(function(): string
						local x = s()
						local n = #(M.accounts:get()[accounts_key(device, h.id)] or {})
						return `{x.installed}:{x.installing}:{x.enabled}:{x.version}:{x.latest}:{x.phase}:{n}`
					end, function(): Node
						return meta(h, device, s())
					end),
				},
				ui.presence(function(): string
					local x = s()
					return `{x.phase}:{x.installed}:{x.installing}`
				end, function(): Node
					local x = M.status:peek()[k]
					local parts: { Node } = {}
					local action = if x.installed then update_action(k, x, id) else nil
					if action then
						table.insert(parts, action)
					end
					if not x.installed and not cloud then
						if x.installing then
							table.insert(
								parts,
								button {
									id = `{id}_install_cancel`,
									label = "Cancel",
									size = "sm",
									variant = "ghost",
									on_click = function()
										M.cancel_install(k)
									end,
								}
							)
						elseif not h.manual then
							table.insert(
								parts,
								button {
									id = `{id}_install`,
									label = "Install",
									size = "sm",
									variant = "ghost",
									on_click = function()
										M.install(k)
									end,
								}
							)
						end
					end
					return ui.row { gap = "$zeron.space.6", items = "center", parts }
				end),
				icon {
					name = "alt-arrow-right",
					size = 14,
					color = T.tertiary,
					opacity = function()
						return if can_open() then 1 else 0.35
					end,
					rotate = function()
						return if open:get() then 90 else 0
					end,
				},
			},
			not cloud and settings.switch { id = `{id}_switch`, value = enabled, disabled = locked } or nil,
		},
		ui.show(
			open,
			ui.presence(function(): boolean?
				return if open:get() then true else nil
			end, details, { w_full = true })
		),
	}
end

-- The device select: each with its platform's glyph, this one "You",
-- Cloud last.
local function device_select(): Node
	return ui.presence(function(): string
		local names = {}
		for _, d in M.devices:get() do
			table.insert(names, `{d.id}={d.name}`)
		end
		return table.concat(names, "|")
	end, function(): Node
		local options: { select.Option } = {}
		for _, d in M.devices:peek() do
			table.insert(options, {
				value = d.id,
				label = d.name,
				id = `providers_device_{string.lower((string.gsub(d.name, "%W+", "_")))}`,
				icon = (if d.cloud then "cloud" elseif d.platform == "Linux" then "monitor" else "laptop") :: any,
				detail = if d.you then "You" else nil,
			})
		end
		return select {
			id = "providers_device",
			label = "Device",
			value = M.device,
			options = options,
			w = 168,
			menu_w = 260,
		}
	end)
end

-- The page's header controls: ↻ (a spinner while it checks) and the
-- device select.
function M.toolbar(): Node
	return ui.row {
		gap = "$zeron.space.6",
		items = "center",
		shrink = 0,
		ui.presence(M.checking, function(checking: boolean): Node
			if checking then
				return ui.row {
					id = "providers_checking",
					w = 28,
					h = 28,
					items = "center",
					justify = "center",
					loaders.mini_spinner { color = T.secondary },
				}
			end
			return icon_button {
				id = "providers_check",
				icon = "refresh",
				size = 28,
				icon_size = 16,
				label = "Check for agents and updates",
				no_ring = true,
				on_click = M.check,
			}
		end),
		device_select(),
	}
end

-- The chosen device's agents, a row each (first-run setup's agents step
-- shows them too).
function M.provider_list(completion: Completion): Node
	return ui.column {
		w_full = true,
		ui.presence(M.device, function(device: string): Node
			local rows: { Node } = {}
			local d = device_of(device)
			for _, h in M.HARNESSES do
				if M.status:peek()[key(device, h.id)] then
					table.insert(rows, provider_row(h, device, completion))
				end
			end
			if d == nil or #rows == 0 then
				return settings.card {
					ui.row {
						p = "$zeron.space.16",
						txt.text { "No agents found on this device.", size = "md", color = T.secondary },
					},
				}
			end
			return settings.card(rows :: any)
		end, { w_full = true }),
		sign_in_dialog(),
	}
end

-- The Providers page.
function M.providers(completion: Completion): Node
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.24",
		ui.row {
			w_full = true,
			items = "center",
			justify = "between",
			txt.text { "Providers", size = "xxl", weight = "medium", line = false },
			M.toolbar(),
		},
		ui.show(
			function()
				return M.error:get() ~= ""
			end,
			settings.error_strip(function()
				return M.error:get()
			end, "providers_error")
		),
		ui.show(
			function()
				return M.updates_error:get() ~= ""
			end,
			ui.column {
				w_full = true,
				gap = "$zeron.space.8",
				items = "start",
				settings.error_strip(function()
					return `Agent updates: {M.updates_error:get()}`
				end, "providers_updates_error"),
				button {
					id = "providers_updates_retry",
					label = "Retry updates",
					size = "sm",
					variant = "ghost",
					on_click = M.check,
				},
			}
		),
		M.provider_list(completion),
	}
end

-- Devices: this one and the others, each with its platform, version and
-- presence; Copy ID (the button says Copied for 1.5 s) and Rename.
local renaming = ui.state("settings_device_renaming", "")
local rename_open = ui.state("settings_device_rename_open", false)

local function rename_dialog(): Node
	return ui.presence(function(): string?
		return if rename_open:get() and renaming:get() ~= "" then renaming:get() else nil
	end, function(id: string): Node
		local d = device_of(id)
		local name = ui.use_state(if d then d.name else "")
		local function rename()
			local trimmed = string.match(name:peek(), "^%s*(.-)%s*$") or ""
			if trimmed ~= "" then
				local list: { Device } = {}
				for _, x in M.devices:peek() do
					local now = table.clone(x)
					if now.id == id then
						now.name = trimmed
					end
					table.insert(list, now)
				end
				M.devices:set(list)
			end
			rename_open:set(false)
		end
		return dialog {
			id = "device_rename",
			open = rename_open,
			title = "Rename device",
			w = 360,
			on_enter = rename,
			actions = {
				button {
					id = "device_rename_cancel",
					label = "Cancel",
					size = "sm",
					variant = "ghost",
					on_click = function()
						rename_open:set(false)
					end,
				},
				button {
					id = "device_rename_confirm",
					label = "Rename",
					size = "sm",
					variant = "primary",
					on_click = rename,
				},
			},
			ui.input {
				id = "device_rename_name",
				value = name,
				label = "Device name",
				placeholder = "Device name",
				placeholder_color = T.tertiary,
				select_on_focus = true,
				w = 318,
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
		}
	end)
end

local function device_row(d: Device): Node
	local copied = ui.use_state(false)
	local slug = string.lower((string.gsub(d.name, "%W+", "_")))
	local metas: { Text } = { d.platform }
	if d.version then
		table.insert(metas, `v{d.version}`)
	end
	local presence: Node? = nil
	if not d.you then
		local online = d.seen == "" or d.seen == "Available"
		presence = txt.text {
			if d.seen == "" then "Online" elseif online then d.seen or "" else `Last seen {d.seen or "never seen"}`,
			literal = true,
			size = "sm",
			color = if online then T.success_muted else T.secondary,
			line = false,
		}
	end
	return settings.row {
		id = `device_{slug}`,
		title = d.name,
		meta = metas,
		control = ui.row {
			gap = "$zeron.space.8",
			items = "center",
			presence,
			button {
				id = `device_{slug}_copy`,
				label = function()
					return if copied:get() then "Copied" else "Copy ID"
				end,
				size = "sm",
				variant = "ghost",
				on_click = function()
					ui.clipboard.write(d.id)
					copied:set(true)
					ui.after(1500, function()
						copied:set(false)
					end)
				end,
			},
			button {
				id = `device_{slug}_rename`,
				label = "Rename",
				size = "sm",
				variant = "secondary",
				on_click = function()
					renaming:set(d.id)
					rename_open:set(true)
				end,
			},
		},
	}
end

-- The Devices page.
function M.devices_page(scope: string?): Node
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.28",
		settings.header {
			title = "Devices",
			description = if scope == "local"
				then "Devices in this local workspace."
				elseif scope == "synced" or scope == nil then "Devices synced to this workspace."
				else "Devices in this workspace.",
		},
		ui.presence(function(): string
			local parts = {}
			for _, d in M.devices:get() do
				table.insert(parts, `{d.id}={d.name}`)
			end
			return table.concat(parts, "|")
		end, function(): Node
			local mine: { Node } = {}
			local others: { Node } = {}
			for _, d in M.devices:peek() do
				table.insert(if d.you then mine else others, device_row(d))
			end
			if #others == 0 then
				others = {
					ui.row {
						p = "$zeron.space.16",
						txt.text { "Sign in on another device to see it here.", size = "md", color = T.secondary },
					},
				}
			end
			return ui.column {
				w_full = true,
				gap = "$zeron.space.28",
				settings.section { title = "This device", table.unpack(mine) },
				scope ~= "local" and settings.section { title = "Other devices", table.unpack(others) } or nil,
			}
		end, { w_full = true }),
		rename_dialog(),
	}
end

return M
