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
-- The dialog up, if any ("sign_out", "enabling", "restart", "update"),
-- and whether it is (Escape or a click outside writes it false).
M.dialog = ui.state("z_account_dialog", "")
M.open = ui.state("z_account_dialog_open", false)
-- The update dialog's step: "checking", or the result.
M.checking = ui.state("z_update_checking", false)

local DOWNLOAD_MS = 1600
local RESTART_MS = 900

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

-- The strip's click (on_update_strip_click): download, restart, or retry.
function M.on_update(u: account.Update)
	if u.state == "available" or u.state == "failed" then
		M.download()
	elseif u.state == "ready" then
		M.restart()
	end
end

-- "Check for Updates…": checking, then the outcome.
function M.check_for_updates()
	M.checking:set(true)
	show("update")
	ui.after(700, function()
		M.checking:set(false)
	end)
end

function M.request_sign_out()
	set_flow("sign_out_confirm")
	show("sign_out")
end
function M.start_sign_in()
	set_flow("enabling")
	show("enabling")
end
function M.reopen_sync_notice()
	show("restart")
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
					M.account:set { scope = "local", flow = "idle" }
					close()
				end),
			},
		}
	elseif kind == "enabling" then
		return kit.dialog {
			id = "sync_enable_dialog",
			open = open,
			title = "Enable sync",
			description = "Finish signing in in your browser. Zeron will keep using this local workspace until you quit and reopen.",
			actions = {
				button("sync-enable-cancel", "Cancel", "ghost", function()
					set_flow("idle")
					close()
				end),
				button("sync-enable-open-browser", "Open browser again", "primary", function()
					-- The browser comes back signed in: sync is ready after a restart.
					set_flow("restart_pending")
					show("restart")
				end),
			},
		}
	elseif kind == "restart" then
		return kit.dialog {
			id = "sync_restart_dialog",
			open = open,
			title = "Sync needs a restart",
			description = "Quit and reopen Zeron to start the synced workspace. Existing local sessions stay on this device and will not be uploaded.",
			actions = {
				button("sync-restart-later", "Later", "ghost", close),
				button("sync-restart-quit", "Quit Zeron", "primary", close),
			},
		}
	elseif kind == "update" then
		return ui.presence(function(): string
			if M.checking:get() then
				return "checking"
			end
			local u = M.update:get()
			return if u then u.state else "none"
		end, function(step: string): Node
			local title, body, actions
			if step == "checking" then
				title = "Checking for updates…"
				body = `You're on Zeron {M.VERSION}.`
				actions = { button("update-prompt-close", "Cancel", "ghost", close) }
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
