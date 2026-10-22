-- What runs in the panes: terminals (Ghostty surfaces attached to the
-- host's session server) and web pages. The host keeps both across reloads;
-- this run asks for them by pane id.
local state = require("./state")
local names = require("@lib/names")

local M = {}

-- Where a new pane's shell starts, until it has.
local spawn_dir: { [string]: string } = {}
M.spawn_dir = spawn_dir
-- Terminal panes whose sessions this run has asked for.
local made: { [string]: boolean } = {}
M.made = made
-- What a terminal asking to close does. actions.luau, which needs these
-- sessions, sets it: a module cannot require one that requires it.
M.close_pane = function(_pane: string, _force: boolean?) end

function M.is_browser(pane: string?): boolean
	return pane ~= nil and (state.kinds:peek())[pane] == "browser"
end

-- A browser pane's page: the host keeps it across reloads, as it does
-- shells.
function M.page(pane: string): Web
	return ui.web("web:" .. pane, { profile = "default" })
end

local function quote(s: string): string
	return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

-- A terminal pane's session, made the first time; every call gives it this
-- run's handlers.
function M.session(pane: string): Term?
	if M.is_browser(pane) then
		return nil
	end
	M.made[pane] = true
	local cwd = M.spawn_dir[pane] or state.launch_dir
	local attach = state.attach
	return ui.term(pane, {
		cwd = cwd,
		command = if attach ~= "" then `{attach} --attach {quote(pane)} --cwd {quote(cwd)}` else nil,
		-- The process exited (no question), or a close binding asked.
		on_close = function(alive)
			M.close_pane(pane, not alive)
		end,
	})
end

function M.describe(pane: string?): names.Description
	if not pane then
		return { name = "", icon = "terminal", busy = false }
	end
	if (state.kinds:get())[pane] == "browser" then
		return names.describe_page(M.page(pane))
	end
	return names.describe(ui.term(pane), state.home)
end

-- Where a shell starts given a directory to start in: there, unless it is
-- none or the root (where an app opened from the Finder starts, not a place
-- anyone works), then where the app was launched (home from the Finder).
function M.start_dir(dir: string?): string
	return if dir and dir ~= "" and dir ~= "/" then dir else state.launch_dir
end

-- The directory a pane's shell is in, for what opens next to it.
function M.cwd_of(pane: string?): string
	local pwd = if pane and not M.is_browser(pane) then names.path_of(ui.term(pane).pwd) else nil
	return M.start_dir(pwd)
end

-- Keyboard focus to a pane's terminal or page.
function M.focus_view(pane: string)
	if M.is_browser(pane) then
		M.page(pane):focus()
	else
		ui.term(pane):focus()
	end
end

-- Whether closing the pane would end something running.
function M.needs_confirm(pane: string): boolean
	return not M.is_browser(pane) and ui.term(pane):needs_confirm()
end

return M
