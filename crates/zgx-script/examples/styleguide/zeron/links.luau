-- Links in replies, as Zeron's (workspace_links.rs, link_interaction.rs):
-- a link or a code span naming a workspace file opens it in the right pane
-- (a `#L12` fragment or a `:12` suffix still names the file); a web link
-- opens in a browser tab, or the system's browser once "Open links in
-- Zeron" is off. The workspace here is the Files column's, on this device:
-- Open with default app and Show in folder show the file in Files.
local files = require("./files")
local state = require("./state")
local browser = require("./browser")
local markdown = require("@kit/markdown")

local M = {}

-- Whether a web link's click opens it in Zeron (open_web_links_in_zeron).
M.in_zeron = ui.state("open_links_in_zeron", true)

-- `target`'s path in the workspace, if it names a file there: relative to
-- its root (`./` and a `file://` scheme aside), its location dropped.
function M.file(target: string): string?
	if string.find(target, "^%a[%w+.-]*://") and not string.find(target, "^file://") then
		return nil
	end
	local path = string.gsub(target, "^file://", "")
	path = string.gsub(path, "#.*$", "")
	path = string.gsub(path, ":%d+[:%-]?%d*$", "")
	path = string.gsub(path, "^%./", "")
	if path == "" or string.find(path, "%s") then
		return nil
	end
	if files.file(path) then
		return path
	end
	return nil
end

-- A browser tab at `url`, beside the conversation.
local function browse(url: string)
	local id = state.open_tab("preview")
	if id then
		browser.navigate(id, url)
	end
end

function M.open(target: string, action: markdown.LinkAction)
	if action == "zeron" or action == "default_app" then
		if M.file(target) then
			files.open(target)
		else
			browse(target)
		end
		return
	elseif action == "reveal" then
		files.reveal(target)
		return
	elseif action == "external" then
		ui.open_url(target)
		return
	end
	-- A pull request's link (shell.rs resolve_link_activation) leaves Zeron
	-- when General sends pull requests to the default browser; staying, it
	-- opens where General says (the pull request view beside the session).
	local hooks = state.hooks
	local pr = if hooks.pr_link then hooks.pr_link(target) else nil
	local to = require("./settings").pref.open_prs:peek()
	if not M.in_zeron:peek() or (pr and to == "Default browser") then
		ui.open_url(target)
	elseif pr and to == "Pull request view" and hooks.show_pr then
		hooks.show_pr(pr)
	else
		browse(target)
	end
end

M.links = { file = M.file, open = M.open, in_zeron = M.in_zeron } :: markdown.Links

return M
