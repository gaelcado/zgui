-- What the composer's completion menus offer as the draft is typed
-- (composer.rs mention_token, invocation_token): after an @ that starts a
-- word, the project's files and folders; after a / or a $ that starts one,
-- the commands and the skills (a $ only the skills). An @ inside a word (an
-- address) is not one, nor a $ before a digit (an amount), nor a / inside
-- a path. A pick writes the reference in the token's place, then a space.
local completion = require("@kit/completion")
local icon_mod = require("@kit/icon")
local data = require("./data")

local M = {}

type Item = completion.Item
type Token = completion.Token

-- The harness's own commands: a pick writes them into the draft.
local COMMANDS = {
	{ "compact", "Summarise the conversation so far" },
	{ "clear", "Start over in this session" },
	{ "review", "Review the branch's changes" },
	{ "init", "Write the project's AGENTS.md" },
	{ "cost", "What the session has used" },
}

-- Zeron's own (composer.rs WorkspaceCommand): a pick runs them at once,
-- taking only the token out of the draft; sending one alone runs it too.
-- Those that need a conversation show only in one.
local WORKSPACE: { { name: string, detail: string, chat: boolean } } = {
	{ name = "model", detail = "Zeron: choose agent, model, and reasoning", chat = false },
	{ name = "new", detail = "Zeron: start a new conversation", chat = false },
	{ name = "resume", detail = "Zeron: search and open conversations", chat = false },
	{ name = "settings", detail = "Zeron: open settings", chat = false },
	{ name = "diff", detail = "Zeron: open changes", chat = true },
	{ name = "files", detail = "Zeron: open project files", chat = true },
	{ name = "terminal", detail = "Zeron: open a terminal", chat = true },
	{ name = "rename", detail = "Zeron: rename this conversation", chat = true },
	{ name = "stop", detail = "Zeron: stop the active run", chat = true },
}
M.WORKSPACE = WORKSPACE

-- What runs each of Zeron's commands, by name; one missing is not offered.
export type Actions = { [string]: () -> () }
-- A staged attachment, as the composer holds it.
export type Staged = { id: string, name: string, kind: string }

local SKILLS = {
	{ "frontend-design", "Distinctive interfaces, not generic ones" },
	{ "release-notes", "Write the notes for the next release" },
	{ "code-review", "Review a diff for correctness" },
	{ "pdf", "Read, fill and make PDF files" },
	{ "webapp-testing", "Drive a local web app in a browser" },
}

-- Each extension's file glyph (file_icons.rs, in the kit's icons).
local GLYPH: { [string]: icon_mod.Name } = {
	rs = "file-code",
	luau = "file-code",
	lua = "file-code",
	ts = "file-code",
	tsx = "file-code",
	py = "file-code",
	md = "file-markdown",
	toml = "file-data",
	json = "file-data",
	yml = "file-data",
	yaml = "file-data",
	lock = "file-data",
	css = "file-style",
	png = "file-image",
	svg = "file-image",
	jpg = "file-image",
}

-- The workspace as paths, the sample tree's first: enough to scroll.
local PATHS = {
	"crates/zgui/src/layout.rs",
	"crates/zgui/src/scene.rs",
	"crates/zgui/src/widgets.rs",
	"crates/zgui/src/text_edit.rs",
	"crates/zgui/src/platform.rs",
	"crates/zgui/Cargo.toml",
	"crates/zgui-script/src/node.rs",
	"crates/zgui-script/src/lower.rs",
	"crates/zgui-script/src/io.rs",
	"crates/zgui-script/types/zgui.d.luau",
	"crates/zgui-script/examples/styleguide/kit/composer.luau",
	"crates/zgui-script/examples/styleguide/kit/completion.luau",
	"crates/zgui-script/examples/styleguide/theme.luau",
	"crates/zgui-desktop/src/platform.rs",
	"crates/zgui-desktop/src/application.rs",
	"crates/zgui-gpu/src/renderer.rs",
	"docs/scripting.md",
	"docs/reference/controls.md",
	"docs/ROADMAP.md",
	"assets/logo.svg",
	"Cargo.lock",
	"AGENTS.md",
}

local function name_of(path: string): string
	return string.match(path, "([^/]+)$") or path
end
local function dir_of(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

local FILES: { Item } = {}
do
	-- The sample tree's files keep their ids (`file_{n}`), as the tree has them.
	local path: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(full: string, folder: boolean, id: string)
		seen[full] = true
		local name = name_of(full)
		local ext = string.match(name, "%.(%w+)$") or ""
		table.insert(FILES, {
			id = id,
			label = name,
			detail = dir_of(full),
			icon = if folder then "folder" :: icon_mod.Name else GLYPH[ext] or "document" :: icon_mod.Name,
			insert = `@{full}`,
			kind = if folder then "folder" else "file",
		})
	end
	local n = 0
	for _, f in data.FILES do
		path[f.level + 1] = f.name
		for i = f.level + 2, #path do
			path[i] = nil
		end
		if not f.folder then
			n += 1
			add(table.concat(path, "/", 1, f.level + 1), false, `file_{n}`)
		end
	end
	local folders: { [string]: boolean } = {}
	for i, full in PATHS do
		if not seen[full] then
			add(full, false, `path_{i}`)
		end
		local dir = dir_of(full)
		while dir ~= "" and not folders[dir] do
			folders[dir] = true
			dir = dir_of(dir)
		end
	end
	local dirs: { string } = {}
	for dir in folders do
		table.insert(dirs, dir)
	end
	table.sort(dirs)
	for i, dir in dirs do
		add(dir, true, `dir_{i}`)
	end
end

-- Title Case for a skill's name: "frontend-design" is "Frontend Design".
local function display(name: string): string
	return (
		string.gsub(string.gsub(name, "[-_]", " "), "%a[%w]*", function(word: string): string
			return string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2)
		end)
	)
end

local INVOCATIONS: { Item } = {}
local SKILL_ITEMS: { Item } = {}
for _, c in COMMANDS do
	local item: Item = {
		id = `cmd_{c[1]}`,
		label = `/{c[1]}`,
		detail = c[2],
		icon = "command",
		insert = `/{c[1]}`,
		kind = "command",
	}
	table.insert(INVOCATIONS, item)
end
for _, k in SKILLS do
	local item: Item = {
		id = `skill_{k[1]}`,
		label = display(k[1]),
		detail = k[2],
		icon = "magic-stick-3",
		insert = `${k[1]}`,
		kind = "skill",
	}
	table.insert(INVOCATIONS, item)
	table.insert(SKILL_ITEMS, item)
end

-- The token at the draft's end, if a word starts with a trigger there.
function M.token(text: string): Token?
	-- A word starts at the start, after a space or an opening bracket.
	local before, trigger, query = string.match(text, "^(.-)([@/$])([^%s]*)$")
	if not trigger then
		return nil
	end
	local last = string.sub(before :: string, -1)
	if last ~= "" and not string.find(last, "[%s%(%[{>]") then
		return nil
	end
	if trigger == "@" then
		if string.find(query :: string, "@", 1, true) then
			return nil
		end
	elseif not string.match(query :: string, "^[%w%-_:%.]*$") then
		return nil
	elseif trigger == "$" and string.match(query :: string, "^%d") then
		return nil
	end
	return { trigger = trigger :: string, query = query :: string }
end

-- The staged attachments as @ rows (mention_attachment_matches): images
-- read "Image 1", "Image 2"…, files their name; those whose label holds
-- the query (spaces and case aside), in the order they were staged.
local function attached(staged: { Staged }, query: string): { Item }
	local function normal(text: string): string
		return string.lower((string.gsub(text, "%s+", "")))
	end
	local wanted = normal(query)
	local out: { Item } = {}
	local images = 0
	for _, a in staged do
		local label = a.name
		if a.kind == "image" then
			images += 1
			label = `Image {images}`
		end
		if string.find(normal(label), wanted, 1, true) then
			table.insert(out, {
				id = `attached_{a.id}`,
				label = label,
				detail = if a.kind == "image" then "Attached image" else "Attached file",
				icon = (if a.kind == "image" then "file-image" else "document") :: icon_mod.Name,
				insert = `@{label}`,
				kind = "attachment",
			})
		end
	end
	return out
end

-- Zeron's commands the actions run.
local function workspace_items(actions: Actions?): { Item }
	local out: { Item } = {}
	for _, w in WORKSPACE do
		if actions and actions[w.name] then
			local item: Item = {
				id = `cmd_{w.name}`,
				label = `/{w.name}`,
				detail = w.detail,
				icon = "command",
				insert = `/{w.name}`,
				kind = "workspace",
			}
			table.insert(out, item)
		end
	end
	return out
end

-- Files match on their name, then on their folder (the staged
-- attachments pinned above them); commands on their name without the
-- slash ("/re" finds "/review"), skills on theirs.
local function results(token: Token, staged: { Staged }?, actions: Actions?): { Item }
	if token.trigger == "@" then
		local files = completion.filter(FILES, token.query, function(item: Item): string
			return item.detail or ""
		end)
		if not staged or #staged == 0 then
			return files
		end
		local out = attached(staged, token.query)
		table.move(files, 1, #files, #out + 1, out)
		return out
	end
	local list = if token.trigger == "$" then SKILL_ITEMS else INVOCATIONS
	if token.trigger == "/" and actions then
		list = table.clone(list)
		for _, item in workspace_items(actions) do
			table.insert(list, item)
		end
	end
	local named: { Item } = {}
	for _, item in list do
		local copy = table.clone(item)
		if item.kind == "command" or item.kind == "workspace" then
			copy.label = string.sub(item.label, 2)
		end
		table.insert(named, copy)
	end
	local out = completion.filter(named, token.query)
	for _, item in out do
		if item.kind == "command" or item.kind == "workspace" then
			item.label = `/{item.label}`
			if item.match then
				item.match = { item.match[1] + 1, item.match[2] + 1 }
			end
		end
	end
	return out
end

-- The Zeron command a draft is, alone (`/diff`, spaces around it): run
-- on sending instead of sent.
function M.command_of(text: string, actions: Actions?): (() -> ())?
	local name = string.match(text, "^%s*/([%w%-_:]+)%s*$")
	return if name and actions then actions[name] else nil
end

-- The completions for a composer writing into `draft`; its staged
-- attachments pinned first under @, and Zeron's commands that `actions`
-- runs under /.
function M.for_draft(draft: State<string>, staged: State<{ Staged }>?, actions: Actions?): completion.Source
	return {
		token = function()
			return M.token(draft:get())
		end,
		results = function(token: Token): { Item }
			return results(token, if staged then staged:get() else nil, actions)
		end,
		on_pick = function(item: Item, token: Token)
			local text = draft:peek()
			local head = string.sub(text, 1, #text - #token.trigger - #token.query)
			if item.kind == "workspace" and actions then
				-- Only the token leaves the draft; the command runs.
				draft:set(head)
				local run = actions[string.sub(item.label, 2)]
				if run then
					run()
				end
				return
			end
			draft:set(`{head}{item.insert or item.label} `)
		end,
	}
end

return M
