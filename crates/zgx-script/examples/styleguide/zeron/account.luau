-- The account and the app's own update, as the sidebar's footer shows them
-- (shell.rs render_user_menu, render_update_strip, render_sync_overlay;
-- app_update.rs): who is signed in and how the workspace syncs, the
-- update found and where its download stands, and the dialogs they open.
-- Sample flows until the engine is wired: a download takes a moment, a
-- restart relaunches into the new version.
local kit = require("@kit")
local account = require("@kit/account")

local M = {}

M.VERSION = "0.2.116"
M.LATEST = "0.2.117"

M.account = ui.state(
	"z_account",
	{
		scope = "synced",
		name = "Gaël Cado",
		email = "gael@zeron.dev",
	} :: account.Account
)
-- The update the release checker found (strip_for): none once installed.
M.update = ui.state("z_update", { state = "available", version = `v{M.LATEST}` } :: account.Update?)
M.connection = ui.state("z_connection", "connected" :: account.Connection)
-- "Star on GitHub" until dismissed.
M.star = ui.state("z_star_banner", true)
-- The dialog up, if any ("sign_out", "update"),
-- and whether it is (Escape or a click outside writes it false).
M.dialog = ui.state("z_account_dialog", "")
M.open = ui.state("z_account_dialog_open", false)
-- The update dialog's step: "checking", or the result; a check that
-- failed says why ("" when none did).
M.checking = ui.state("z_update_checking", false)
M.check_failed = ui.state("z_update_check_failed", "")
-- How this copy was installed (zeron_update::InstallKind): the app
-- updates itself; a package manager's copy (`managed`) is updated by
-- `zeron update`; one set up by no installer (`source`: a source build)
-- can't update itself, and points at the releases.
export type Install = "desktop" | "managed" | "source"
M.install = ui.state("z_update_install", "desktop" :: Install)
local RELEASES = "https://github.com/zeronsh/zeron/releases"
local LATEST_RELEASE = "https://github.com/zeronsh/zeron/releases/latest"
-- The sample engine's next check fails (⌘K).
local fail_next_check = false

local DOWNLOAD_MS = 1600
local RESTART_MS = 900

-- The boot splash (shell.rs SplashPhase), shown while the engine connects
-- at launch (a host asks for it with `boot_splash`; a headless one does
-- not): the sample engine is ready after a moment, and the splash plays
-- its way out over the app.
local BOOT_MS = 1200
M.booting = ui.state("z_booting", ui.shared("boot_splash", false):peek() == true)
if M.booting:peek() then
	ui.after(BOOT_MS, function()
		M.booting:set(false)
	end)
end

local function set_flow(flow: account.SyncFlow)
	local a = table.clone(M.account:peek())
	a.flow = flow
	M.account:set(a)
end

local function show(kind: string)
	M.dialog:set(kind)
	M.open:set(true)
end
local function close()
	M.open:set(false)
end

-- Closing the sign-out question without signing out leaves things as
-- they were.
ui.effect(function()
	if not M.open:get() and M.account:peek().flow == "sign_out_confirm" then
		set_flow("idle")
	end
end)

-- Download, then "restart to apply"; a restart relaunches.
function M.download()
	local u = M.update:peek()
	if not u then
		return
	end
	M.update:set { state = "downloading", version = u.version }
	ui.after(DOWNLOAD_MS, function()
		local now = M.update:peek()
		if now and now.state == "downloading" then
			M.update:set { state = "ready", version = now.version }
		end
	end)
end
function M.restart()
	local u = M.update:peek()
	if not u then
		return
	end
	M.update:set { state = "restarting", version = u.version }
	ui.after(RESTART_MS, function()
		M.VERSION = M.LATEST
		M.update:set(nil)
	end)
end

-- The strip's click (on_update_strip_click): download, restart, or retry;
-- a copy that can't update itself is advised once (the releases opening
-- for a source build) and the strip goes.
function M.on_update(u: account.Update)
	local install = M.install:peek()
	if u.state == "available" and install ~= "desktop" then
		if install == "source" then
			ui.open_url(RELEASES)
		end
		M.update:set(nil)
	elseif u.state == "available" or u.state == "failed" then
		M.download()
	elseif u.state == "ready" then
		M.restart()
	end
end

-- "Check for Updates…": checking, then the outcome (or why it failed).
function M.check_for_updates()
	M.checking:set(true)
	M.check_failed:set("")
	show("update")
	local fail = fail_next_check
	fail_next_check = false
	ui.after(700, function()
		if fail then
			M.check_failed:set("The release server could not be reached.")
		end
		M.checking:set(false)
	end)
end

-- The sample engine's install, and its next check failing (⌘K): the
-- strip says what a copy that can't update itself should do.
function M.sample_install(kind: Install)
	M.install:set(kind)
	local u = M.update:peek()
	if u and u.state == "available" then
		M.update:set {
			state = "available",
			version = u.version,
			detail = if kind == "managed"
				then "run `zeron update`"
				elseif kind == "source" then "download from GitHub"
				else nil,
		}
	end
end
function M.sample_fail_check()
	fail_next_check = true
end

-- Whether a sidebar change can reach the engine (shell.rs mutate,
-- sidebar_sections.rs, sidebar_pins.rs); if not, a toast says why.
-- A failed save (storage_error) still takes changes: its pill says so.
function M.can_change(): boolean
	local c = M.connection:peek()
	if c == "connected" or c == "storage_error" then
		return true
	end
	kit.toast.push {
		title = if c == "syncing" then "Sidebar is still syncing. Try again shortly." else "Engine not connected",
		tone = "danger",
	}
	return false
end

-- The sample engine's posture, until one is wired: offline, syncing, or
-- reconnecting back to connected.
function M.sample_connection(c: account.Connection)
	if c == "connected" then
		M.connection:set("reconnecting")
		ui.after(RESTART_MS, function()
			if M.connection:peek() == "reconnecting" then
				M.connection:set("connected")
			end
		end)
	else
		M.connection:set(c)
	end
end

function M.request_sign_out()
	set_flow("sign_out_confirm")
	show("sign_out")
end
-- Enabling sync, finishing it and signing out: zeron/sync's steps.
M.sync = {} :: { enable: (() -> ())?, reopen: (() -> ())?, sign_out: (() -> ())? }
function M.start_sign_in()
	if M.sync.enable then
		M.sync.enable()
	end
end
function M.reopen_sync_notice()
	if M.sync.reopen then
		M.sync.reopen()
	end
end

local function button(id: string, label: string, variant: string, run: () -> ()): Node
	return kit.button { id = id, label = label, variant = variant :: any, size = "sm", on_click = run }
end

-- The dialog up (popover::dialog_card): its title, its body and its buttons.
local function dialog(kind: string): Node?
	local open = M.open
	if kind == "sign_out" then
		return kit.dialog {
			id = "signout_dialog",
			open = open,
			title = "Sign out?",
			description = "Zeron will remove your credentials, close the synced workspace, and continue in local mode.",
			actions = {
				button("signout-cancel", "Cancel", "ghost", close),
				button("signout-confirm", "Sign out", "danger", function()
					if M.sync.sign_out then
						M.sync.sign_out()
					end
					close()
				end),
			},
		}
	elseif kind == "update" then
		return ui.presence(function(): string
			if M.checking:get() then
				return "checking"
			elseif M.check_failed:get() ~= "" then
				return "check_failed"
			end
			local u = M.update:get()
			local install = M.install:get()
			return if not u then "none" elseif u.state == "available" and install ~= "desktop" then install else u.state
		end, function(step: string): Node
			local title, body, actions
			if step == "checking" then
				title = "Checking for updates…"
				body = `You're on Zeron {M.VERSION}.`
				actions = { button("update-prompt-close", "Cancel", "ghost", close) }
			elseif step == "check_failed" then
				title = "Couldn't check for updates"
				body = M.check_failed:peek()
				actions = {
					button("update-prompt-close", "Close", "ghost", close),
					button("update-prompt-check", "Try again", "primary", M.check_for_updates),
				}
			elseif step == "managed" then
				title = `Zeron {M.LATEST} is available`
				body = "Run `zeron update` in a terminal to install it."
				actions = { button("update-prompt-close", "OK", "ghost", close) }
			elseif step == "source" then
				title = `Zeron {M.LATEST} is available`
				body =
					"This copy of Zeron wasn't set up by an installer (for example, a source build), so it can't update itself."
				actions = {
					button("update-prompt-close", "Later", "ghost", close),
					button("update-prompt-downloads", "Open download page", "primary", function()
						ui.open_url(LATEST_RELEASE)
						close()
					end),
				}
			elseif step == "none" then
				title = "Zeron is up to date"
				body = `Version {M.VERSION} is the newest release.`
				actions = { button("update-prompt-close", "OK", "ghost", close) }
			elseif step == "downloading" or step == "restarting" then
				title = `Zeron {M.LATEST} is available`
				body = "Downloading the update in the background — you can keep working."
				actions = { button("update-prompt-close", "Hide", "ghost", close) }
			elseif step == "ready" then
				title = `Zeron {M.LATEST} is ready`
				body = "Restart to finish updating. If you don't, it installs the next time you quit Zeron."
				actions = {
					button("update-prompt-close", "Later", "ghost", close),
					button("update-prompt-restart", "Restart to update", "primary", function()
						close()
						M.restart()
					end),
				}
			else
				title = `Zeron {M.LATEST} is available`
				body = if step == "failed" then "The download failed: offline" else `You're on {M.VERSION}.`
				actions = {
					button("update-prompt-close", "Later", "ghost", close),
					button("update-prompt-download", "Download", "primary", M.download),
				}
			end
			return kit.dialog {
				id = "update_prompt_dialog",
				open = open,
				title = title,
				description = body,
				actions = actions,
			}
		end)
	end
	return nil
end

-- Mounted once in the app's root: the dialog up, built only while one is.
function M.dialogs(): Node
	return ui.presence(function(): string?
		return if M.open:get() and M.dialog:get() ~= "" then M.dialog:get() else nil
	end, function(kind: string): Node
		return dialog(kind) or ui.div {}
	end)
end

return M
