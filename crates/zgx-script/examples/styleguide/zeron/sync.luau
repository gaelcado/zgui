-- Enabling sync, and the engine out of reach (shell.rs v0.2.129:
-- render_setup_page's sync steps, render_signed_out_restart,
-- render_gate_card). Each step is a page in place of the window, as
-- Settings is: a 560 column under the titlebar, its heading and line, a
-- card saying where it stands (a spinner, or the account signed in), then
-- the way back on the left and on on the right. "Finish logging in" waits
-- for the browser; "Sync is ready" asks to bring this device's work or
-- start fresh; "Setting up sync", "Bringing your work over" (session N of
-- total, on a bar), "Your work is synced"; "Import didn't finish" retries
-- what is missing; "Restart to finish" when the switch cannot happen in
-- place. Signing out asks first, then says it is under way; if the
-- synced workspace will not close, "Signed out" offers Retry local mode.
-- Unreachable, the engine's error and Retry are all the window shows.
-- The sample engine's: each step takes a moment, and ⌘K's "Sample
-- engine" commands fail the next step or the connection.
local T = require("../theme")
local kit = require("@kit")
local data = require("./data")
local account = require("./account")

local M = {}

-- Whether a postponed step ("Later") shows again.
M.notice = ui.state("sync_notice_open", false)
M.import = ui.state("sync_import", { done = 0, total = 0, title = "" })
M.result = ui.state("sync_import_result", { imported = 0, skipped = 0, error = "" })
-- The next step fails (the switch, an import, closing the workspace).
M.fail_next = ui.state("sync_fail_next", false)
-- "Stopping engine…" while a restart or local mode is under way.
M.stopping = ui.state("sync_stopping", false)
-- The engine: "" connected, "failed" out of reach, "loading" retrying.
M.gate = ui.state("engine_gate", "")
M.GATE_ERROR = "Could not reach the zeron engine on port 27901"

local STEP_MS = 1200
local IMPORT_MS = 160

local function flow(): string
	return account.account:get().flow or "idle"
end
local function set(changes: { [string]: any })
	local a = table.clone(account.account:peek())
	for k, v in changes do
		(a :: any)[k] = v
	end
	account.account:set(a)
end
local function failing(): boolean
	if M.fail_next:peek() then
		M.fail_next:set(false)
		return true
	end
	return false
end

-- This device's work: its sessions and projects.
local function local_work(): (number, number)
	local n = 0
	for _, s in data.SESSIONS do
		if not s.archived and not s.parent then
			n += 1
		end
	end
	return n, #data.PROJECTS
end
local function plural(n: number, one: string): string
	return `{n} {one}{if n == 1 then "" else "s"}`
end
local function work_phrase(): string
	local sessions, projects = local_work()
	return `the {plural(sessions, "session")} and {plural(projects, "project")}`
end

-- A step's timer, dropped when another step starts.
local token = 0
local function after(ms: number, run: () -> ())
	token += 1
	local mine = token
	ui.after(ms, function()
		if token == mine then
			run()
		end
	end)
end

-- Enable sync: the browser signs in, then the offer.
function M.enable()
	set { flow = "enabling" }
	M.notice:set(true)
	after(STEP_MS + 400, function()
		set { flow = "switch_offer", name = "Gaël Cado", email = "gael@zeron.dev" }
	end)
end
function M.cancel()
	set { flow = "canceling" }
	after(STEP_MS, function()
		set { flow = "idle", scope = "local", email = nil, name = nil }
	end)
end
function M.later()
	M.notice:set(false)
end
function M.reopen()
	M.notice:set(true)
end

local function import(total: number, skipped: number)
	set { flow = "importing", scope = "synced" }
	M.import:set { done = 0, total = 0, title = "" }
	local titles: { string } = {}
	for _, s in data.SESSIONS do
		if not s.archived and not s.parent then
			table.insert(titles, s.title)
		end
	end
	local fails = failing()
	local at = 0
	local function step()
		at += 1
		-- What it came to first: the page reads it as it is built.
		if fails and at == total then
			M.notice:set(true)
			M.result:set {
				imported = total - 1,
				skipped = skipped,
				error = `{total - 1} imported, 1 failure: {titles[at] or "a session"}: its transcript is too large`,
			}
			set { flow = "import_failed" }
			return
		end
		if at > total then
			M.result:set { imported = total, skipped = skipped, error = "" }
			set { flow = "import_done", scope = "synced" }
			return
		end
		M.import:set { done = at - 1, total = total, title = titles[(at - 1) % math.max(#titles, 1) + 1] or "" }
		after(IMPORT_MS, step)
	end
	-- Looking for local sessions first.
	after(500, step)
end

-- Bring this device's work over, or start fresh: the engine hands over to
-- the account, then the sessions come along.
function M.switch(bring: boolean)
	set { flow = "switching" }
	M.import:set { done = 0, total = 0, title = "" }
	after(STEP_MS, function()
		local sessions = local_work()
		if bring and sessions > 0 then
			import(sessions, 0)
		elseif failing() then
			M.notice:set(true)
			M.result:set {
				imported = 0,
				skipped = 0,
				error = "The synced workspace did not come up — restart to finish.",
			}
			set { flow = "restart_pending" }
		else
			set { flow = "idle", scope = "synced" }
		end
	end)
end
-- Retry: only what is missing comes over.
function M.retry_import()
	local r = M.result:peek()
	import(1, r.imported + r.skipped)
end
function M.done()
	set { flow = "idle", scope = "synced" }
end
-- "Quit Zeron": the sample relaunches into the synced workspace.
function M.restart()
	M.stopping:set(true)
	after(STEP_MS, function()
		M.stopping:set(false)
		set { flow = "idle", scope = "synced" }
	end)
end

-- Sign out: confirmed, the credentials go and the workspace closes.
function M.sign_out()
	set { flow = "signing_out" }
	after(STEP_MS, function()
		if failing() then
			set { flow = "signed_out_restart", scope = "local", email = nil, name = nil }
		else
			set { flow = "idle", scope = "local", email = nil, name = nil }
		end
	end)
end
function M.retry_local()
	M.stopping:set(true)
	after(STEP_MS, function()
		M.stopping:set(false)
		set { flow = "idle", scope = "local" }
	end)
end

account.sync.enable = M.enable
account.sync.reopen = M.reopen
account.sync.sign_out = M.sign_out

-- The engine out of reach, and Retry: nothing shows until it answers.
function M.fail_connection()
	M.gate:set("failed")
end
function M.retry_engine()
	M.gate:set("loading")
	after(900, function()
		M.gate:set(if failing() then "failed" else "")
	end)
end

local PAGED: { [string]: boolean } = {
	enabling = true,
	canceling = true,
	switching = true,
	importing = true,
	import_done = true,
}
local POSTPONED: { [string]: boolean } = { switch_offer = true, import_failed = true, restart_pending = true }

-- The step's page now, if one shows.
function M.page_step(): string?
	local f = flow()
	return if PAGED[f] or (POSTPONED[f] and M.notice:get()) then f else nil
end
-- Whether first-run setup shows the steps' pages in its own frame.
M.inside = nil :: (() -> boolean)?

-- What covers the window now: a step's page, the signed-out card, the gate.
local function showing(): string?
	if M.gate:get() ~= "" then
		return `gate:{M.gate:get()}`
	end
	if flow() == "signed_out_restart" then
		return "signed_out"
	end
	if M.inside and M.inside() then
		return nil
	end
	return M.page_step()
end
-- Whether the app beneath stops painting.
function M.covering(): boolean
	return showing() ~= nil
end

local function ghost(id: string, label: Text, run: () -> ()): Node
	return kit.button { id = id, label = label, size = "sm", variant = "ghost", on_click = run }
end
local function primary(id: string, label: Text, run: () -> ()): Node
	return kit.button { id = id, label = label, size = "sm", variant = "primary", on_click = run }
end

-- The status card: one row, a spinner (or a glyph) and what is happening.
local function status(id: string, text: Text, glyph: Node?, strong: boolean?): Node
	return kit.settings.card {
		id = id,
		ui.row {
			w_full = true,
			min_h = 44,
			px = "$zeron.space.16",
			py = "$zeron.space.10",
			gap = "$zeron.space.10",
			items = "center",
			glyph or kit.loaders.mini_spinner { color = T.secondary },
			kit.text.text { text, size = "sm", color = if strong then T.text else T.secondary, line = false },
		},
	}
end

type Page = {
	id: string,
	title: string,
	body: Text,
	block: Node?,
	back: Node?,
	forward: { Node }?,
}

-- A setup page (onboarding.rs render_page): the heading and its line, the
-- block 28 under them, the footer 24 under that.
local function setup_page(p: Page): Node
	return ui.column {
		id = p.id,
		w_full = true,
		max_w = 640,
		px = "$zeron.space.40",
		gap = "$zeron.space.4",
		on_mount = function(el: Element)
			anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW), ease = kit.motion.EASE })
		end,
		kit.text.text { p.title, size = "xxl", weight = "medium", line = false },
		kit.text.text { p.body, size = "md", color = T.secondary, wrap = true },
		p.block and ui.column { w_full = true, pt = "$zeron.space.24", p.block } or nil,
		ui.row {
			w_full = true,
			pt = "$zeron.space.24",
			items = "center",
			ui.row { ml = T.pull(12), p.back },
			ui.div { grow = 1 },
			ui.row { gap = "$zeron.space.8", items = "center", p.forward or {} },
		},
	}
end

local function error_line(): Node
	return ui.show(
		function()
			return M.result:get().error ~= ""
		end,
		kit.text.text {
			function()
				return M.result:get().error
			end,
			id = "sync_error",
			size = "sm",
			color = T.danger,
			wrap = true,
			mt = "$zeron.space.12",
		}
	)
end

-- A step's page as its parts: its heading and line, its block, the way
-- back and on (first-run setup lays them in its own frame).
function M.parts(step: string): Page
	if step == "enabling" then
		return {
			id = "sync_enabling",
			title = "Finish logging in",
			body = "We opened your browser to log in to Zeron. Come back when you're done — this page moves on by itself.",
			block = status("sync_status", "Waiting for your browser…"),
			back = ghost("sync_cancel", "Cancel", M.cancel),
			forward = { primary("sync_open_browser", "Open browser again", M.enable) },
		}
	elseif step == "canceling" then
		return {
			id = "sync_canceling",
			title = "Canceling sign-in",
			body = "Removing the partial sign-in before going back.",
			block = status("sync_status", "Canceling…"),
		}
	elseif step == "switch_offer" then
		local sessions = local_work()
		local email = account.account:peek().email
		local forward = if sessions > 0
			then {
				ghost("sync_start_fresh", "Start fresh", function()
					M.switch(false)
				end),
				primary("sync_bring_work", "Bring my work", function()
					M.switch(true)
				end),
			}
			else {
				primary("sync_switch_now", "Switch now", function()
					M.switch(false)
				end),
			}
		return {
			id = "sync_offer",
			title = "Sync is ready",
			body = if sessions > 0
				then `Bring {work_phrase()} from this device into your synced workspace, or start it fresh.`
				else "Zeron can switch to your synced workspace now.",
			block = status(
				"sync_status",
				if email then `Signed in as {email}` else "You're signed in",
				kit.icon { name = "check", size = 14, color = T.accent },
				true
			),
			back = ghost("sync_later", "Later", M.later),
			forward = forward,
		}
	elseif step == "switching" then
		return {
			id = "sync_switching",
			title = "Setting up sync",
			body = "Handing the engine over to your account. Your local sessions come along next.",
			block = status("sync_status", "Switching to your synced workspace…"),
		}
	elseif step == "importing" then
		return {
			id = "sync_importing",
			title = "Bringing your work over",
			body = function()
				local i = M.import:get()
				if i.total == 0 then
					return "Looking for local sessions…"
				end
				return `Importing session {math.min(i.done + 1, i.total)} of {i.total}`
			end,
			block = kit.settings.card {
				ui.column {
					w_full = true,
					min_h = 44,
					px = "$zeron.space.16",
					py = "$zeron.space.12",
					gap = "$zeron.space.10",
					kit.text.text {
						function()
							return M.import:get().title
						end,
						id = "sync_import_title",
						literal = true,
						size = "sm",
						color = T.secondary,
						truncate = true,
						line = false,
					},
					ui.div {
						w_full = true,
						h = 4,
						rounded = "$zeron.radius.2",
						bg = T.ink4,
						overflow = "hidden",
						ui.div {
							id = "sync_import_bar",
							h_full = true,
							rounded = "$zeron.radius.2",
							bg = T.accent,
							w = function(): string
								local i = M.import:get()
								local f = if i.total > 0 then i.done / i.total else 0
								return `{math.max(4, f * 100)}%`
							end,
						},
					},
				},
			},
		}
	elseif step == "import_done" then
		local r = M.result:peek()
		return {
			id = "sync_done",
			title = "Your work is synced",
			body = if r.imported == 0 and r.skipped == 0
				then "Your synced workspace is ready."
				elseif r.skipped == 0 then `{plural(r.imported, "session")} moved into your synced workspace.`
				else `{plural(r.imported, "session")} imported, {r.skipped} already present.`,
			forward = { primary("sync_continue", "Continue", M.done) },
		}
	elseif step == "import_failed" then
		return {
			id = "sync_import_failed",
			title = "Import didn't finish",
			body = "Anything already imported is kept; retrying only copies what's missing.",
			block = error_line(),
			back = ghost("sync_later", "Later", M.later),
			forward = { primary("sync_retry_import", "Retry import", M.retry_import) },
		}
	end
	return {
		id = "sync_restart",
		title = "Restart to finish",
		body = "Quit and reopen Zeron to start the synced workspace. Existing local sessions stay on this device and will not be uploaded.",
		block = error_line(),
		back = ghost("sync_later", "Later", M.later),
		forward = {
			ui.column {
				opacity = function()
					return if M.stopping:get() then 0.6 else 1
				end,
				primary("sync_quit", function()
					return if M.stopping:get() then "Stopping engine…" else "Quit Zeron"
				end, function()
					if not M.stopping:peek() then
						M.restart()
					end
				end),
			},
		},
	}
end

local function page_for(step: string): Node
	if PAGED[step] or POSTPONED[step] then
		return setup_page(M.parts(step))
	elseif step == "signed_out" then
		return ui.column {
			id = "sync_signed_out",
			w = 380,
			px = "$zeron.space.32",
			py = "$zeron.space.40",
			rounded = T.radius_card,
			border = 1,
			border_color = T.border,
			bg = T.card,
			shadow = T.shadow_lg,
			items = "center",
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) })
			end,
			kit.icon { name = "zeron-logo", size = 36, color = T.text },
			kit.text.text { "Signed out", size = "xl", weight = "semibold", mt = "$zeron.space.24", line = false },
			kit.text.text {
				"Zeron removed your credentials but could not finish closing the previous synced workspace. Retry before continuing in local mode.",
				size = "md",
				color = T.secondary,
				align = "center",
				wrap = true,
				mt = "$zeron.space.6",
				mb = "$zeron.space.24",
			},
			ui.column {
				opacity = function()
					return if M.stopping:get() then 0.6 else 1
				end,
				primary("sync_retry_local", function()
					return if M.stopping:get() then "Stopping engine…" else "Retry local mode"
				end, function()
					if not M.stopping:peek() then
						M.retry_local()
					end
				end),
			},
		}
	elseif step == "gate:failed" then
		return ui.column {
			id = "engine_gate",
			gap = "$zeron.space.12",
			items = "center",
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.SLOW) })
			end,
			kit.text.text { M.GATE_ERROR, size = "lg", color = T.secondary, align = "center", line = false },
			ghost("engine_retry", "Retry", M.retry_engine),
		}
	end
	-- Retrying: nothing until the engine answers.
	return ui.div { id = "engine_loading" }
end

-- Over the window while a step, the card or the gate shows.
function M.view(): Node
	return ui.presence(showing, function(step: string): Node
		local signed_out = step == "signed_out"
		return ui.column {
			id = "sync",
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			-- Signed out blocks the window on its background; the rest sit
			-- on its glass, as Settings does.
			bg = if signed_out then T.bg else T.clear,
			items = "center",
			justify = "center",
			ui.row {
				absolute = true,
				left = 0,
				right = 0,
				top = 0,
				h = "$zeron.titlebar.height",
				window_drag = true,
			},
			page_for(step),
		}
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.MENU_OUT) },
	})
end

-- Signing out, under way (shell.rs render_sync_overlay's SigningOut).
function M.dialogs(): Node
	local open = ui.state("sync_signing_out_open", false)
	ui.effect(function()
		local now = flow() == "signing_out"
		if open:peek() ~= now then
			open:set(now)
		end
	end)
	return ui.presence(function(): boolean?
		return if open:get() then true else nil
	end, function(): Node
		return kit.dialog {
			id = "signing_out_dialog",
			open = open,
			title = "Signing out…",
			description = "Removing account credentials and closing the synced workspace.",
		}
	end)
end

return M
