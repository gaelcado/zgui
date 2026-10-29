-- The Files column (files/mod.rs): under its toolbar (the search field,
-- and the eye showing hidden and ignored entries, as Settings → Files
-- does) the project's tree, folders folding under their chevron, each
-- entry's own icon, the name coloured by its git status (modified, added,
-- renamed, deleted; ignored dimmed). An open folder with nothing in it
-- says "Empty folder"; a big one lists a page at a time ("Load more…").
-- Typing searches the workspace's paths ("No files found.", "Showing the
-- first 200 matches"). When file updates stop, a band says so with
-- "Refresh now". A file opens in the right pane (files/preview.rs) under
-- its breadcrumb and toolbar (the Markdown toggle, the save's status,
-- Reveal file in tree, word wrap): the editor (line numbers, its syntax
-- coloured, the caret's line marked, Tab indenting, Save file (⌘S) and
-- autosave, a dot while edited), Markdown as its preview, an image fitted
-- and enlarged in the viewer; what it can't edit says why (binary, too
-- large, an encoding, a symlink, permission, mixed line endings, outside
-- the chat's folder, a large file cut short). A file changed outside
-- Zeron asks before its edits go; closing one with edits saves them
-- first, and asks when they can't be. A secondary click: Add to chat,
-- Copy path (the full one), Rename… (in place), Delete… (asked first). A
-- row dragged into the chat is a mention in its draft; onto a folder of
-- the tree, it moves there. The workspace is live: what a turn writes
-- recolours as it lands, a folder in the worst status under it.
local T = require("../theme")
local kit = require("@kit")
local file_tree = require("@kit/file_tree")
local file_icon = require("@kit/file_icon")
local menus = require("@kit/menu")
local data = require("./data")
local syntax = require("@lib/syntax")
local chrome = require("./chrome")
local state = require("./state")
local comments = require("./comments")
local markdown_kit = require("@kit/markdown")
local keys = require("./keys")
local cloud = require("./cloud")

local M = {}

-- The chat's folder, on this device.
M.ROOT = "/Users/gael/Developer/zgx"
-- How many entries a folder lists before "Load more…".
M.PAGE = 100
M.SEARCH_LIMIT = 200

-- The workspace: each entry's path (a moved one's old path too), and a
-- file's text (or an image's).
type Node_ = { path: string, folder: boolean?, git: file_tree.Git, from: string? }
local PATHS: { Node_ } = {
	{ path = ".github", folder = true },
	{ path = ".github/ci.yml" },
	{ path = "assets", folder = true },
	{ path = "assets/icons", folder = true },
	{ path = "assets/logo.icns" },
	{ path = "crates", folder = true },
	{ path = "crates/zgx", folder = true },
	{ path = "crates/zgx/compose.rs", git = "modified" },
	{ path = "crates/zgx/compose_scrollbar.rs" },
	{ path = "crates/zgx/layout_old.rs", git = "deleted" },
	{ path = "crates/zgx-desktop", folder = true },
	{ path = "crates/styleguide", folder = true },
	{ path = "crates/styleguide/canvas.luau", git = "added" },
	{ path = "crates/styleguide/shadow.jpg" },
	{ path = "data", folder = true },
	{ path = "data/telemetry.ndjson" },
	{ path = "docs", folder = true },
	{ path = "docs/legacy-latin1.txt" },
	{ path = "docs/release-notes.md" },
	{ path = "logs", folder = true },
	{ path = "logs/engine.log" },
	{ path = "scripts", folder = true },
	{ path = "scripts/build.bat" },
	{ path = "secrets", folder = true },
	{ path = "secrets/deploy.pem" },
	{ path = "target", folder = true, git = "ignored" },
	{ path = ".gitignore" },
	{ path = "Cargo.toml" },
	{ path = "README.md", git = "modified" },
	{ path = "latest" },
}
-- A big folder's 250 entries: kept apart from the tree's state (a read of
-- the state copies what it holds), changed in place as they are renamed,
-- moved or deleted, with `big_rev` saying so.
local BIG: { Node_ } = {}
for i = 1, 250 do
	table.insert(BIG, { path = string.format("assets/icons/glyph-%03d.svg", i) })
end
local ENGINE_LOG = {}
for i = 1, 400 do
	table.insert(
		ENGINE_LOG,
		string.format("2026-10-28T09:%02d:%02dZ engine: frame %d laid out in 0.%dms", i // 60, i % 60, i, i % 9 + 1)
	)
end
M.TEXT = {
	["crates/zgx/compose.rs"] = table.concat({
		"fn place(&mut self, node: NodeId) {",
		"    let parent = self.parent(node);",
		"    let centred = parent.items == Align::Center && self_align.is_none();",
		"    if centred {",
		"        offset = (room - size) / 2.;",
		"    }",
		"}",
	}, "\n"),
	["crates/zgx/compose_scrollbar.rs"] = "pub fn mount(ui: &mut Ui, root: NodeId) {\n    // The thumb follows the offset.\n}",
	["crates/styleguide/canvas.luau"] = "return ui.column {\n\tw_full = true,\n\tgap = 12,\n}",
	["Cargo.toml"] = '[workspace]\nmembers = ["crates/*"]\nresolver = "2"',
	["docs/release-notes.md"] = "# Release notes\n\nLead with the glass, then the panes.\n",
	[".github/ci.yml"] = "on: [push, pull_request]\njobs:\n  test:\n    runs-on: ubuntu-latest",
	[".gitignore"] = "/target\n",
	["README.md"] = table.concat(data.README, "\n"),
	["logs/engine.log"] = table.concat(ENGINE_LOG, "\n"),
	["scripts/build.bat"] = "@echo off\r\ncargo build --release\nif errorlevel 1 exit /b 1\r\n",
}
M.IMAGES = { ["crates/styleguide/shadow.jpg"] = { src = "images/shadow.jpg", w = 720, h = 480 } }

-- Why a file can't be edited (WorkspaceReadOnlyReason), and whether the
-- engine sent only its start (`truncated`).
export type Reason = "binary" | "large" | "encoding" | "symlink" | "permission" | "line_endings" | "outside"
M.READ_ONLY = {
	["assets/logo.icns"] = "binary",
	["data/telemetry.ndjson"] = "large",
	["docs/legacy-latin1.txt"] = "encoding",
	["latest"] = "symlink",
	["secrets/deploy.pem"] = "permission",
	["scripts/build.bat"] = "line_endings",
} :: { [string]: Reason }
M.TRUNCATED = { ["logs/engine.log"] = true } :: { [string]: boolean }

-- What each reason says (preview.rs read_only_message).
M.MESSAGES = {
	binary = "Binary files cannot be previewed.",
	encoding = "This file encoding is not supported.",
	symlink = "Symlink targets are read-only.",
	permission = "Permission denied.",
	large = "This file is too large to preview.",
	line_endings = "Files with mixed line endings are read-only.",
	outside = "Read-only: outside this chat's folder.",
} :: { [Reason]: string }

-- Files the agent changed on disk since they were opened: what is there now.
M.DISK = {
	["crates/zgx/compose_scrollbar.rs"] = "pub fn mount(ui: &mut Ui, root: NodeId) {\n    // The thumb follows the offset, eased.\n    ease(ui, root);\n}",
}
-- A file whose next save the disk refuses (once), and why.
M.BUSY = { ["crates/styleguide/canvas.luau"] = "Resource busy (os error 16)" } :: { [string]: string }

local function name_of(path: string): string
	return string.match(path, "([^/]+)$") or path
end
local function parent_of(path: string): string?
	return string.match(path, "^(.*)/[^/]+$")
end
-- Outside the chat's folder: an absolute path.
local function outside(path: string): boolean
	return string.sub(path, 1, 1) == "/" or string.sub(path, 1, 1) == "~"
end
-- Why `path` can't be edited, if it can't.
function M.reason(path: string): Reason?
	if outside(path) then
		return "outside"
	end
	return M.READ_ONLY[path]
end

-- The tree as it stands: renames and deletions applied, and the folders
-- open (all but the build's output).
M.paths = ui.state("files_paths", PATHS :: { Node_ })
M.expanded = ui.state("files_open", { ".github", "crates", "crates/zgx", "crates/styleguide", "docs" })
local big_rev = ui.state("files_big_rev", 0)
-- How many entries each big folder lists so far.
local loaded = ui.state("files_loaded", {} :: { [string]: number })
-- The sessions whose stopped file updates "Refresh now" picked up again.
local refreshed = ui.state("files_refreshed", {} :: { [string]: boolean })
local selected = ui.state("tree_sel", "crates/zgx/compose.rs")
-- The entries chosen together (⌘ or ⇧ and a click).
M.chosen = ui.state("tree_chosen", { "crates/zgx/compose.rs" })
local renaming = ui.state("files_renaming", "")
local query = ui.state("files_query", "")
-- The entries a Delete… asks about.
local deleting = ui.state("files_deleting_paths", {} :: { string })
local copied = ui.state("files_copied", "")
-- What the last change in the tree could not do (mod.rs mutation_error):
-- a line at the column's foot until the next.
local refused = ui.state("files_refused", "")

local function pref()
	return require("./settings").pref
end

-- Every entry, the tree's then the big folder's (its folder is above);
-- read, followed.
local function entries(read: boolean): { Node_ }
	local list = if read then M.paths:get() else M.paths:peek()
	if read then
		big_rev:get()
	end
	local out = table.clone(list)
	table.move(BIG, 1, #BIG, #out + 1, out)
	return out
end

-- Hidden and ignored entries (a dotted name, what .gitignore leaves out,
-- and what is under them) show only with Show hidden and ignored files.
local function hidden(n: Node_, ignored: { [string]: boolean }): boolean
	local up = parent_of(n.path)
	return string.sub(name_of(n.path), 1, 1) == "." or n.git == "ignored" or (up ~= nil and ignored[up] == true)
end
local function shown(list: { Node_ }): { Node_ }
	if pref().hidden_files:get() then
		return list
	end
	local out, gone = {}, {}
	for _, n in list do
		if hidden(n, gone) then
			gone[n.path] = true
		else
			table.insert(out, n)
		end
	end
	return out
end

-- How bad a status is (git_status.rs severity): a folder takes its worst.
local SEVERITY: { [string]: number } = { added = 1, modified = 2, renamed = 3, deleted = 4 }

-- The tree's order (files/model.rs): within a folder, folders first, then
-- by name, any case.
local function before(a: Node_, b: Node_): boolean
	local sa, sb = string.split(a.path, "/"), string.split(b.path, "/")
	for i = 1, math.min(#sa, #sb) do
		if sa[i] ~= sb[i] then
			local fa = i < #sa or a.folder == true
			local fb = i < #sb or b.folder == true
			if fa ~= fb then
				return fa
			end
			return string.lower(sa[i]) < string.lower(sb[i])
		end
	end
	return #sa < #sb
end

-- The tree's entries, each folder's under it, in its order; a folder
-- coloured by the worst status under it (a renamed file's old folders too).
local items = ui.computed(function(): { file_tree.Entry }
	local roots: { file_tree.Entry } = {}
	local folders: { [string]: file_tree.Entry } = {}
	local list = table.clone(shown(entries(true)))
	table.sort(list, before)
	local pages = loaded:get()
	local counts: { [string]: number } = {}
	local skipped: { [string]: boolean } = {}
	local worst: { [string]: string } = {}
	local function mark(path: string, git: string)
		local up = parent_of(path)
		while up do
			local was = worst[up]
			if not was or SEVERITY[was] < SEVERITY[git] then
				worst[up] = git
			end
			up = parent_of(up)
		end
	end
	for _, n in list do
		if n.git and SEVERITY[n.git] and not n.folder then
			mark(n.path, n.git)
			if n.from then
				mark(n.from, n.git)
			end
		end
	end
	for _, n in list do
		local up = parent_of(n.path)
		if up and skipped[up] then
			skipped[n.path] = true
			continue
		end
		local parent = up and folders[up]
		if parent and up then
			counts[up] = (counts[up] or 0) + 1
			if counts[up] > (pages[up] or M.PAGE) then
				skipped[n.path] = true
				continue
			end
		end
		local e: file_tree.Entry = {
			id = n.path,
			label = name_of(n.path),
			folder = n.folder,
			git = if n.folder then (worst[n.path] or n.git) :: file_tree.Git else n.git,
			children = if n.folder then {} else nil,
		}
		if n.folder then
			folders[n.path] = e
		end
		table.insert(if parent and parent.children then parent.children else roots, e)
	end
	-- What a folder can't list: nothing in it, or its next page.
	for path, f in folders do
		local children = f.children :: { file_tree.Entry }
		local n = counts[path] or 0
		if n == 0 then
			table.insert(
				children,
				{ id = `{path}/.empty`, label = "Empty folder", git = nil, status = "empty" :: "empty" }
			)
		elseif n > (pages[path] or M.PAGE) then
			table.insert(
				children,
				{ id = `{path}/.load-more`, label = "Load more…", git = nil, status = "more" :: "more" }
			)
		end
	end
	return roots
end)

-- A file's document: its text, what was last saved, whether its Markdown
-- shows rendered, and its lifecycle (changed on disk, a save that hit the
-- change, a save that failed and why, deleted while open, a close waiting
-- on a save).
type Doc = {
	text: State<string>,
	saved: State<string>,
	markdown: State<boolean>,
	external: State<boolean>,
	confirming: State<boolean>,
	conflict: State<boolean>,
	failed: State<string>,
	deleted: State<boolean>,
	closing: State<boolean>,
}
local function doc(path: string): Doc
	local text = M.TEXT[path] or ""
	return {
		text = ui.state(`file_text:{path}`, text),
		saved = ui.state(`file_saved:{path}`, text),
		markdown = ui.state(`file_markdown:{path}`, string.match(path, "%.md$") ~= nil),
		external = ui.state(`file_external:{path}`, M.DISK[path] ~= nil),
		confirming = ui.state(`file_confirming:{path}`, false),
		conflict = ui.state(`file_conflict:{path}`, false),
		failed = ui.state(`file_failed:{path}`, ""),
		deleted = ui.state(`file_deleted:{path}`, false),
		closing = ui.state(`file_closing:{path}`, false),
	}
end

-- Saves `path`'s edits; false when they can't be (the file changed or went
-- on disk and the user has not chosen to keep theirs, or the disk refused).
local function save(path: string): boolean
	local d = doc(path)
	if M.reason(path) or M.TRUNCATED[path] or d.deleted:peek() then
		return false
	end
	-- Whatever comes of it, a send waiting on this file goes on: saved, or
	-- refused (document_finishes_review_comment_flush).
	comments.saving(state.session:peek()):set_key(path, nil)
	if d.external:peek() then
		d.conflict:set(true)
		return false
	end
	local busy = M.BUSY[path]
	if busy then
		M.BUSY[path] = nil
		d.failed:set(busy)
		return false
	end
	d.saved:set(d.text:peek())
	d.conflict:set(false)
	d.failed:set("")
	return true
end

local function reload(path: string)
	local d = doc(path)
	local disk = M.DISK[path] or d.saved:peek()
	M.TEXT[path] = disk
	d.text:set(disk)
	d.saved:set(disk)
	d.external:set(false)
	d.confirming:set(false)
	d.conflict:set(false)
end

local function tab_of(path: string): string?
	for _, t in state.tabs:peek() do
		if t.kind == "file" and t.ref == path then
			return t.id
		end
	end
	return nil
end

-- Closing a file's tab (shell.rs close_right_surface, preview.rs
-- prepare_close): its edits are saved first; when they can't be, it stays
-- open and asks.
state.hooks.prepare_close = function(id: string): boolean
	for _, t in state.tabs:peek() do
		if t.id == id and t.kind == "file" and t.ref then
			local d = doc(t.ref)
			if d.text:peek() == d.saved:peek() or save(t.ref) then
				d.closing:set(false)
				return true
			end
			d.closing:set(true)
			state.tab:set(id)
			return false
		end
	end
	return true
end

local function close_now(path: string)
	local tab = tab_of(path)
	doc(path).closing:set(false)
	if tab then
		state.close_tab(tab)
	end
end

-- The files each session opened, the latest first (⌘K's Recent Files).
local opened = ui.state("files_recent", {} :: { [string]: { string } })
function M.recent(session: string): { string }
	return opened:get()[session] or {}
end

-- Opens `path` in the right pane: its tab, or a new one.
function M.open(path: string)
	local session = state.session:peek()
	local recent = table.clone(opened:peek()[session] or {})
	local at = table.find(recent, path)
	if at then
		table.remove(recent, at)
	end
	table.insert(recent, 1, path)
	opened:set_key(session, { table.unpack(recent, 1, math.min(#recent, 20)) })
	local tab = tab_of(path)
	if tab then
		state.tab:set(tab)
		return
	end
	local id = `file_{string.gsub(path, "[^%w]", "_")}`
	local list = table.clone(state.tabs:peek())
	table.insert(list, { id = id, kind = "file" :: state.Kind, ref = path })
	state.tabs:set(list)
	state.tab:set(id)
	require("@kit/panel_shell").set_open(state.chat, "right", true)
end

-- Shows `path` in the tree: the Files column open, its folders open, it
-- chosen (FilesEvent::RevealFile).
function M.reveal(path: string)
	local open = table.clone(M.expanded:peek())
	local up = parent_of(path)
	while up do
		if not table.find(open, up) then
			table.insert(open, up)
		end
		up = parent_of(up)
	end
	M.expanded:set(open)
	query:set("")
	selected:set(path)
	if state.tabbed_now() and state.hooks.open_surface then
		state.hooks.open_surface("files")
	else
		require("@kit/panel_shell").set_open(state.chat, "files", true)
	end
end

local function exists(path: string): boolean
	for _, n in entries(false) do
		if n.path == path then
			return true
		end
	end
	return false
end

local function folder_of(path: string): boolean
	for _, n in M.paths:peek() do
		if n.path == path then
			return n.folder == true
		end
	end
	return false
end

-- The workspace file at `path` (not a folder), as a link names it.
function M.file(path: string): boolean
	for _, n in M.paths:peek() do
		if n.path == path then
			return not n.folder
		end
	end
	return false
end

-- Moves `path`, and what is under it, to `to` (mutations.rs relocate): a
-- file is renamed from where it was (a new one stays new); open folders
-- stay open, open tabs follow it, and it is chosen where it went.
local function relocate(path: string, to: string)
	local function moved(p: string): string?
		if p == path or string.sub(p, 1, #path + 1) == path .. "/" then
			return to .. string.sub(p, #path + 1)
		end
		return nil
	end
	local out = {}
	for _, n in M.paths:peek() do
		local now = moved(n.path)
		if now then
			local m = table.clone(n)
			m.path = now
			if not n.folder and n.git ~= "added" then
				m.git = "renamed"
				m.from = n.from or n.path
			end
			table.insert(out, m)
			if M.TEXT[n.path] then
				M.TEXT[now] = M.TEXT[n.path]
			end
			if M.IMAGES[n.path] then
				M.IMAGES[now] = M.IMAGES[n.path]
			end
		else
			table.insert(out, n)
		end
	end
	M.paths:set(out)
	for _, n in BIG do
		local now = moved(n.path)
		if now then
			n.from = n.from or n.path
			n.path = now
			n.git = "renamed"
		end
	end
	big_rev:set(big_rev:peek() + 1)
	local open = {}
	for _, id in M.expanded:peek() do
		table.insert(open, moved(id) or id)
	end
	M.expanded:set(open)
	for i, t in state.tabs:peek() do
		local now = if t.kind == "file" and t.ref then moved(t.ref) else nil
		if now then
			state.tabs:set_key({ i, "ref" }, now)
		end
	end
	selected:set(to)
end

-- Renames `path` to `name`, its children with it: one name (rename.rs
-- renamed_path: no separator, colon or NUL, not "", ".", ".." or ".git"),
-- else the column says why.
function M.rename(path: string, name: string): boolean
	local lower = string.lower(name)
	if name == "" or name == "." or name == ".." or lower == ".git" or string.find(name, "[/\\:%z]") then
		refused:set("Enter a single file name without path separators")
		return false
	end
	local up = parent_of(path)
	local to = if up then `{up}/{name}` else name
	if exists(to) then
		return false
	end
	refused:set("")
	relocate(path, to)
	return true
end

-- Moves `path` into `folder` ("" the root), as a drop in the tree does
-- (drag.rs): never where it is, into itself or over another entry.
function M.move(path: string, folder: string): boolean
	if not file_tree.can_move(path, folder) then
		return false
	end
	local to = if folder == "" then name_of(path) else `{folder}/{name_of(path)}`
	if exists(to) then
		return false
	end
	relocate(path, to)
	return true
end

-- The workspace as a turn writes it (watch.rs): `path` changed (or new,
-- its folders with it), and what it leaves in the working tree's diff.
function M.write(path: string, patch: string?)
	local out = table.clone(M.paths:peek())
	local found = false
	for i, n in out do
		if n.path == path then
			found = true
			if n.git == nil or n.git == "ignored" then
				local m = table.clone(n)
				m.git = "modified"
				out[i] = m
			end
		end
	end
	if not found then
		local up = parent_of(path)
		while up and not exists(up) do
			table.insert(out, { path = up, folder = true })
			up = parent_of(up)
		end
		table.insert(out, { path = path, git = "added" :: file_tree.Git })
	end
	M.paths:set(out)
	local working = data.working:peek()
	if patch and not string.find(working, patch, 1, true) then
		data.working:set(working .. patch)
	end
end

-- The working tree discarded (DISCARD_WORKING_TREE): new files go, changed
-- and deleted ones are as they were.
function M.discard()
	local out = {}
	for _, n in M.paths:peek() do
		if n.git == "modified" or n.git == "deleted" then
			local m = table.clone(n)
			m.git = nil
			table.insert(out, m)
		elseif not (n.git == "added" and not n.folder) then
			table.insert(out, n)
		end
	end
	M.paths:set(out)
end

-- Deletes `path` and what is under it; a file open in a tab keeps its
-- buffer, deleted on disk (mutations.rs).
function M.delete(path: string)
	refused:set("")
	for _, t in state.tabs:peek() do
		local ref = t.ref
		if t.kind == "file" and ref and (ref == path or string.sub(ref, 1, #path + 1) == path .. "/") then
			doc(ref).deleted:set(true)
		end
	end
	local out = {}
	for _, n in M.paths:peek() do
		if n.path ~= path and string.sub(n.path, 1, #path + 1) ~= path .. "/" then
			table.insert(out, n)
		end
	end
	M.paths:set(out)
	for i = #BIG, 1, -1 do
		local p = BIG[i].path
		if p == path or string.sub(p, 1, #path + 1) == path .. "/" then
			table.remove(BIG, i)
		end
	end
	big_rev:set(big_rev:peek() + 1)
end

-- `path` from the chat's folder (context_menu.rs absolute_workspace_path).
function M.full_path(path: string): string
	return if outside(path) then path else `{M.ROOT}/{path}`
end

-- What a secondary click offers (context_menu.rs), on the entries it acts
-- on: several chosen copy their paths a line each and delete together;
-- only one renames.
local function menu(e: file_tree.Entry, paths: { string }): { Node }
	local function item(
		id: string,
		label: string,
		glyph: string,
		run: () -> (),
		danger: boolean?,
		tip: string?,
		inert: boolean?
	): Node
		return ui.menu_item {
			id = `files_menu_{id}`,
			label = label,
			on_click = run,
			tooltip = tip,
			disabled = inert,
			opacity = if inert then 0.38 else nil,
			ui.row {
				gap = "$zeron.space.10",
				items = "center",
				kit.icon { name = glyph :: any, size = 16, color = if danger then T.danger else T.secondary },
				kit.text.text { label, size = "md", color = if danger then T.danger else T.text, line = false },
			},
		}
	end
	if e.status then
		return {}
	end
	local many = #paths > 1
	return {
		item("chat", "Add to chat", "chat-round-line", function()
			-- As a drop on the chat is (the conversation holds the draft).
			if state.hooks.drop_into then
				for _, path in paths do
					state.hooks.drop_into(
						state.session:peek(),
						{ kind = "file", path = path, folder = folder_of(path) }
					)
				end
			end
		end),
		item("copy", if many then "Copy paths" else "Copy path", "copy", function()
			local full: { string } = {}
			for _, path in paths do
				table.insert(full, M.full_path(path))
			end
			local text = table.concat(full, "\n")
			copied:set(text)
			ui.clipboard.write(text)
		end, nil, if many then "Copy full paths, one per line" else "Copy full path"),
		menus.separator(),
		item("rename", "Rename…", "pen", function()
			refused:set("")
			renaming:set(e.id)
		end, nil, nil, many),
		item("delete", if many then `Delete {#paths} items…` else "Delete…", "trash-bin-minimalistic", function()
			deleting:set(paths)
		end, true),
	}
end

-- Paths holding the query (any case), files first; hidden ones only
-- while shown.
function M.search(q: string): { Node_ }
	local needle = string.lower(q)
	local files, folders = {}, {}
	for _, n in shown(entries(true)) do
		if string.find(string.lower(n.path), needle, 1, true) then
			table.insert(if n.folder then folders else files, n)
		end
	end
	table.move(folders, 1, #folders, #files + 1, files)
	return files
end

local function search_results(): Node
	return ui.presence(function()
		return `{query:get()}|{pref().hidden_files:get()}`
	end, function(): Node
		local found = M.search(query:peek())
		if #found == 0 then
			return ui.row {
				h = 27,
				px = "$zeron.space.12",
				items = "center",
				kit.text.text { "No files found.", size = "xs", color = T.tertiary, line = false },
			}
		end
		local shown = math.min(#found, M.SEARCH_LIMIT)
		return ui.column {
			w_full = true,
			grow = 1,
			min_h = 0,
			#found >= M.SEARCH_LIMIT and ui.row {
				id = "files_found_limit",
				h = 24,
				px = "$zeron.space.10",
				items = "center",
				shrink = 0,
				kit.text.text { "Showing the first 200 matches", size = "micro", color = T.tertiary, line = false },
			} or nil,
			ui.list {
				id = "files_found",
				label = "Fuzzy workspace file results",
				grow = 1,
				w_full = true,
				count = shown,
				height = 27,
				row = function(i: number): Node
					local n = found[i]
					return ui.button {
						id = `files_found_{i}`,
						variants = kit.recipes.wash { hover = "ink2" },
						w_full = true,
						h = 27,
						px = "$zeron.space.12",
						gap = "$zeron.space.6",
						items = "center",
						focus = { border = 0 },
						cursor = "pointer",
						on_click = function()
							selected:set(n.path)
							if not n.folder then
								M.open(n.path)
							end
						end,
						file_icon.icon { path = n.path, folder = n.folder, size = 14 },
						kit.text.text { name_of(n.path), literal = true, size = "xs", line = false, shrink = 0 },
						kit.text.text {
							parent_of(n.path) or "",
							literal = true,
							size = "xs",
							color = T.tertiary,
							truncate = true,
							line = false,
							shrink = 1,
							min_w = 0,
						},
					}
				end,
			},
		}
	end, { w_full = true, grow = 1, min_h = 0 })
end

-- The explorer's toolbar (render_explorer_header): the search field, and
-- the eye that shows hidden and ignored files.
local function toolbar(): Node
	return ui.row {
		h = 38,
		px = "$zeron.space.8",
		gap = "$zeron.space.4",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		ui.row {
			h = 24,
			grow = 1,
			min_w = 0,
			px = "$zeron.space.8",
			gap = "$zeron.space.6",
			items = "center",
			rounded = T.radius_md,
			bg = T.ink1,
			kit.icon { name = "magnifer", size = 12, color = T.tertiary },
			ui.input {
				id = "files_search",
				value = query,
				label = "Search files",
				placeholder = "Search files",
				placeholder_color = T.tertiary,
				grow = 1,
				shrink = 1,
				min_w = 0,
				h = "100%",
				px = 0,
				py = 0,
				bg = T.clear,
				border = 0,
				rounded = 0,
				font = T.sans,
				text_size = "$font.size.xs",
				color = T.text,
				focus = { border = 0 },
				on_key = function(k: KeyEvent): boolean
					if k.key == "Escape" then
						query:set("")
						return true
					end
					return false
				end,
			},
		},
		ui.presence(pref().hidden_files, function(on: boolean): Node
			local label = if on then "Hide hidden and ignored files" else "Show all files (even hidden)"
			return kit.tooltip {
				label = label,
				kit.icon_button {
					id = "files_hidden",
					icon = if on then "eye" else "eye-closed",
					size = 24,
					icon_size = 14,
					label = label,
					no_ring = true,
					selected = on,
					on_click = ui.toggle(pref().hidden_files),
				},
			}
		end),
	}
end

-- File updates stopped (files/watch.rs): a band over the tree until
-- "Refresh now" picks them up again.
local function watch_band(): Node
	return ui.show(
		function()
			local session = state.session:get()
			return data.watch_error(session) ~= nil and not refreshed:get()[session]
		end,
		ui.row {
			id = "files_watch_error",
			h = 27,
			px = "$zeron.space.10",
			gap = "$zeron.space.6",
			items = "center",
			shrink = 0,
			bg = T.warning_wash,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.warning_wash,
			kit.icon { name = "refresh", size = 10.5, color = T.warning },
			kit.text.text {
				function()
					return data.watch_error(state.session:get()) or ""
				end,
				size = "micro",
				color = T.warning,
				truncate = true,
				line = false,
				grow = 1,
				min_w = 0,
			},
			ui.button {
				id = "files_refresh_now",
				label = "Refresh workspace files now",
				h = 20,
				px = "$zeron.space.6",
				items = "center",
				rounded = "$zeron.radius.5",
				bg = T.clear,
				hover = { bg = T.ink2 },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					refreshed:set_key(state.session:peek(), true)
				end,
				kit.text.text { "Refresh now", size = "micro", color = T.secondary, line = false },
			},
		}
	)
end

-- What a delete names (rename.rs delete_subject): the entry, or how many
-- with the first two.
function M.delete_subject(paths: { string }): string
	local names: { string } = {}
	for _, path in paths do
		table.insert(names, name_of(path))
	end
	if #names == 1 then
		return names[1]
	elseif #names == 2 then
		return `2 items ({names[1]} and {names[2]})`
	elseif #names > 2 then
		return `{#names} items ({names[1]}, {names[2]} and {#names - 2} more)`
	end
	return ""
end

-- What the dialog says (render_tree_delete): a folder goes with what is in it.
function M.delete_words(paths: { string }): string
	local folders = 0
	for _, path in paths do
		if folder_of(path) then
			folders += 1
		end
	end
	local consequence = if folders == 0
		then "This cannot be undone. "
		elseif #paths == 1 then "All current folder contents will be deleted. "
		else "Folders are deleted with all their current contents. "
	return `Permanently delete {M.delete_subject(paths)}? {consequence}Open editor buffers will be kept for recovery.`
end

-- Asks before deleting (files/rename.rs).
local function delete_dialog(): Node
	local open = ui.state("files_delete_open", false)
	ui.effect(function()
		open:set(#deleting:get() > 0)
	end)
	ui.effect(function()
		if not open:get() then
			deleting:set {}
		end
	end)
	return kit.dialog {
		id = "files_delete",
		open = open,
		title = "Delete permanently?",
		description = function(): string
			return M.delete_words(deleting:get())
		end,
		w = 380,
		actions = {
			kit.button {
				id = "files_delete_cancel",
				label = "Cancel",
				variant = "ghost",
				size = "sm",
				on_click = function()
					deleting:set {}
				end,
			},
			kit.button {
				id = "files_delete_confirm",
				label = "Delete",
				variant = "danger",
				size = "sm",
				on_click = function()
					for _, path in deleting:peek() do
						M.delete(path)
					end
					deleting:set {}
				end,
			},
		},
	}
end

function M.view(): Node
	return ui.column {
		w_full = true,
		h_full = true,
		pt = chrome.top,
		variants = kit.recipes.panel_fill { glass = chrome.glass },
		ui.show(
			function()
				return not chrome.glass()
			end,
			ui.row {
				h = 32,
				px = "$zeron.space.12",
				items = "center",
				shrink = 0,
				kit.text.text { "Files", size = "sm", weight = "semibold", line = false },
			}
		),
		toolbar(),
		watch_band(),
		ui.presence(function()
			-- A Cloud session's machine asleep has no files to show.
			local m = cloud.machine(state.session:get())
			if m == "asleep" or m == "waking" or m == "new" or m == "starting" then
				return "asleep"
			end
			return if query:get() ~= "" then "search" else "tree"
		end, function(what: string): Node
			if what == "search" then
				return search_results()
			elseif what == "asleep" then
				return cloud.asleep_files(state.session:peek())
			end
			return file_tree.tree {
				id = "ztree",
				items = items,
				open = M.expanded,
				selected = selected,
				selection = M.chosen,
				on_open = function(e: file_tree.Entry)
					M.open(e.id)
				end,
				on_more = function(folder: string)
					loaded:set_key(folder, (loaded:peek()[folder] or M.PAGE) + M.PAGE)
				end,
				menu = menu,
				renaming = renaming,
				on_rename = function(id: string, name: string): boolean
					return M.rename(id, name)
				end,
				-- Into the chat (a mention), or onto a folder (a move).
				draggable = true,
				on_move = function(id: string, folder: string)
					M.move(id, folder)
				end,
			}
		end, { w_full = true, grow = 1, min_h = 0 }),
		-- What the last change could not do (popover.rs error_row).
		ui.show(
			function()
				return refused:get() ~= ""
			end,
			ui.row {
				id = "files_refused",
				w_full = true,
				p = "$zeron.space.8",
				shrink = 0,
				kit.text.text {
					function(): string
						return refused:get()
					end,
					size = "sm",
					color = T.danger,
					wrap = true,
				},
			}
		),
		delete_dialog(),
	}
end

-- A comment just posted on `path`'s line over edits not yet saved: the
-- session's next send waits for the save (require_review_comment_flush),
-- which autosave makes at once.
local function hold_for_save(path: string)
	local d = doc(path)
	if d.text:peek() == d.saved:peek() then
		return
	end
	comments.saving(state.session:peek()):set_key(path, true)
	if pref().autosave:peek() then
		save(path)
	end
end

-- Comments on a file's own lines (comments.rs ReviewComment::file), staged
-- on the session's composer as a diff's are and cited "path:line": in the
-- Markdown preview a block's "+" opens a draft under it ("Request a
-- change…"); posted, a card under it, its pen editing it in place.
local made = 0
local function line_comments(path: string, id: string): markdown_kit.Comments
	local draft = ui.state(`file_draft:{path}`, nil :: { line: number, editing: string? }?)
	local draft_text = ui.state(`file_draft_text:{path}`, "")
	local function staged(): State<{ comments.Comment }>
		return comments.staged(state.session:peek())
	end
	local function at(line: number): { comments.Comment }
		local out: { comments.Comment } = {}
		for _, c in comments.staged(state.session:get()):get() do
			if c.path == path and c.side == nil and c.line == line then
				table.insert(out, c)
			end
		end
		return out
	end
	local function post(line: number)
		local d = draft:peek()
		local body = draft_text:peek()
		draft:set(nil)
		if not string.match(body, "%S") then
			return
		end
		if d and d.editing then
			for i, c in staged():peek() do
				if c.id == d.editing then
					staged():set_key({ i, "body" }, body)
				end
			end
			return
		end
		made += 1
		staged():push { id = `file_{made}`, path = path, line = line, body = body }
		hold_for_save(path)
	end
	return {
		add = function(line: number)
			draft_text:set("")
			draft:set { line = line }
		end,
		under = function(line: number): Node
			return ui.presence(function()
				local keys = {}
				local d = draft:get()
				for _, c in at(line) do
					table.insert(keys, if d and d.editing == c.id then "edit" else `{c.id}:{c.body}`)
				end
				if d and d.line == line and not d.editing then
					table.insert(keys, "draft")
				end
				return if #keys > 0 then table.concat(keys, "|") else nil
			end, function(): Node
				local d = draft:peek()
				local function editor(editing: string?): Node
					return kit.comment.draft {
						id = `{id}_draft`,
						where = `{path}:{line}`,
						value = draft_text,
						autofocus = true,
						action = if editing then "Save" else "Comment",
						on_submit = function()
							post(line)
						end,
						on_cancel = function()
							draft:set(nil)
						end,
					}
				end
				local cards: { Node } = {}
				for _, c in at(line) do
					if d and d.editing == c.id then
						table.insert(cards, editor(c.id))
					else
						table.insert(
							cards,
							kit.comment.card {
								id = `{id}_comment_{c.id}`,
								where = `{path}:{line}`,
								body = c.body,
								on_edit = function()
									draft_text:set(c.body)
									draft:set { line = line, editing = c.id }
								end,
								on_remove = function()
									local rest = {}
									for _, n in staged():peek() do
										if n.id ~= c.id then
											table.insert(rest, n)
										end
									end
									staged():set(rest)
								end,
							}
						)
					end
				end
				if d and d.line == line and not d.editing then
					table.insert(cards, editor(nil))
				end
				return ui.column { w_full = true, pt = "$zeron.space.12", gap = "$zeron.space.6", cards }
			end, { w_full = true })
		end,
	}
end

-- Comments on a file's lines in its code editor (preview.rs
-- render_editor_comment_overlays): under the pointer a line's gutter cell
-- offers "+", which opens a draft card under the line ("Add a comment…");
-- a commented line's cell shows the comment's glyph in its number's place,
-- and a press shows or hides its card (its pen editing it, its remove).
-- The cards float under their line, kept inside the editor's view; a
-- comment follows its line as the text is edited. Posted over edits not
-- yet saved, the session's next send waits for the save (autosave saves at
-- once).
local function editor_comments(path: string): any
	local draft = ui.state(`file_draft:{path}`, nil :: { line: number, editing: string? }?)
	local draft_text = ui.state(`file_draft_text:{path}`, "")
	-- The posted comment whose card shows.
	local active = ui.state(`file_comment_shown:{path}`, nil :: string?)
	local function staged(): State<{ comments.Comment }>
		return comments.staged(state.session:peek())
	end
	local function find(id: string): (number?, comments.Comment?)
		for i, c in staged():peek() do
			if c.id == id then
				return i, c
			end
		end
		return nil, nil
	end
	local function post()
		local at = draft:peek()
		local body = string.match(draft_text:peek(), "^%s*(.-)%s*$") or ""
		draft:set(nil)
		if not at then
			return
		end
		if body == "" then
			active:set(at.editing)
			return
		end
		if at.editing then
			local i = find(at.editing)
			if i then
				staged():set_key({ i, "body" }, body)
			end
			active:set(at.editing)
			return
		end
		made += 1
		staged():push { id = `file_{made}`, path = path, line = at.line, body = body }
		active:set(nil)
		hold_for_save(path)
	end
	local function cancel()
		local at = draft:peek()
		draft:set(nil)
		active:set(if at then at.editing else nil)
	end
	local card = ui.presence(function(): string?
		local at = draft:get()
		if at then
			return if at.editing then `edit:{at.editing}:{at.line}` else `draft:{at.line}`
		end
		comments.staged(state.session:get()):get()
		local _, c = find(active:get() or "")
		return if c then `card:{c.id}:{c.line}:{c.body}` else nil
	end, function(key: string): Node
		local kind, which = string.match(key, "^(%a+):([^:]*)")
		if kind == "card" then
			local _, c = find(which :: string)
			local shown = c :: comments.Comment
			return kit.comment.card {
				id = "file_comment_card",
				floating = true,
				where = `{path}:{shown.line}`,
				body = shown.body,
				on_edit = function()
					draft_text:set(shown.body)
					draft:set { line = shown.line, editing = shown.id }
				end,
				on_remove = function()
					local rest = {}
					for _, n in staged():peek() do
						if n.id ~= shown.id then
							table.insert(rest, n)
						end
					end
					staged():set(rest)
					active:set(nil)
					local left = false
					for _, n in rest do
						left = left or (n.path == path and n.side == nil)
					end
					if not left then
						comments.saving(state.session:peek()):set_key(path, nil)
					end
				end,
			}
		end
		local at = draft:peek()
		return kit.comment.draft {
			id = "file_comment_draft",
			floating = true,
			where = `{path}:{if at then at.line else 0}`,
			value = draft_text,
			autofocus = true,
			placeholder = "Add a comment…",
			action = if kind == "edit" then "Save" else "Comment",
			on_submit = post,
			on_cancel = cancel,
		}
	end, { w_full = true })
	return {
		marks = function(): { GutterMark }
			local out: { GutterMark } = {}
			for _, c in comments.staged(state.session:get()):get() do
				if c.path == path and c.side == nil then
					table.insert(out, { id = c.id, line = c.line })
				end
			end
			return out
		end,
		mark = "icons/chat-round-line.svg",
		mark_color = T.secondary,
		mark_fill = T.card,
		add = "icons/plus.svg",
		add_color = T.on_solid,
		add_fill = T.solid,
		label = "Comment",
		on_press = function(line: number, id: string?)
			if id then
				-- Its card shown, or hidden again (toggle_editor_comment).
				draft:set(nil)
				active:set(if active:peek() == id then nil else id)
			else
				draft_text:set("")
				draft:set { line = line }
				active:set(nil)
			end
		end,
		-- The text was edited around them: each comment's line where its
		-- line went (update_review_comment_line).
		on_move = function(marks: { GutterMark })
			for _, m in marks do
				local i, c = find(m.id)
				if i and c and c.line ~= m.line then
					staged():set_key({ i, "line" }, m.line)
				end
				local at = draft:peek()
				if at and at.editing == m.id and at.line ~= m.line then
					draft:set { line = m.line, editing = m.id }
				end
			end
		end,
		card = ui.column { w_full = true, card },
		card_line = function(): number?
			local at = draft:get()
			if at then
				return at.line
			end
			comments.staged(state.session:get()):get()
			local _, c = find(active:get() or "")
			return if c then c.line else nil
		end,
	}
end

-- A toolbar button (files/mod.rs toolbar_button): 24 square, its 14 icon,
-- on the wash while `on`, named by its tooltip.
local function tool(id: string, glyph: string, label: string, run: () -> (), on: boolean?): Node
	return kit.tooltip {
		label = label,
		kit.icon_button {
			id = id,
			icon = glyph :: any,
			size = 24,
			icon_size = 14,
			label = label,
			no_ring = true,
			selected = on,
			on_click = run,
		},
	}
end

-- A band over the document (preview.rs): its words, then its actions as
-- text buttons, on the warning at 5.5%.
local function band(
	id: string,
	words: string,
	actions: { { id: string, label: string, run: () -> (), tone: string? } }
): Node
	local buttons: { Node } = {}
	for _, a in actions do
		table.insert(
			buttons,
			ui.button {
				id = `{id}_{a.id}`,
				label = a.label,
				px = "$zeron.space.2",
				bg = T.clear,
				border = 0,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = a.run,
				kit.text.text {
					a.label,
					size = "xs",
					color = if a.tone == "danger" then T.danger elseif a.tone == "muted" then T.secondary else T.text,
					line = false,
				},
			}
		)
	end
	return ui.row {
		id = id,
		w_full = true,
		min_h = 32,
		py = "$zeron.space.6",
		px = "$zeron.space.10",
		gap = "$zeron.space.8",
		items = "center",
		shrink = 0,
		bg = T.warning_wash,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.warning_wash,
		kit.text.text { words, size = "xs", color = T.warning, wrap = true, shrink = 1, min_w = 0 },
		ui.div { grow = 1 },
		buttons,
	}
end

-- A 28-high row over a read-only document's text (outside_read_only_row,
-- the truncated preview's).
local function note(id: string, words: string, warn: boolean): Node
	return ui.row {
		id = id,
		w_full = true,
		h = 28,
		px = "$zeron.space.10",
		items = "center",
		shrink = 0,
		bg = if warn then T.warning_wash else T.ink1,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.border,
		kit.text.text { words, size = "micro", color = if warn then T.warning else T.secondary, line = false },
	}
end

-- A file's own surface in the right pane (files/preview.rs): its toolbar
-- (the file's icon, its path as crumbs, the Markdown toggle, the save's
-- status, Reveal, Open in default editor, word wrap), the bands of its
-- lifecycle, then the editor, the Markdown preview, the image, or why it
-- can't be shown.
function M.surface(path: string, id: string): Node
	local image = M.IMAGES[path]
	local is_markdown = string.match(path, "%.md$") ~= nil
	local reason = M.reason(path)
	local truncated = M.TRUNCATED[path] == true
	local editable = reason == nil and not truncated
	local d = doc(path)

	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		table.insert(parts, part)
	end
	local crumbs: { Node } = {}
	for i, part in parts do
		if i > 1 then
			table.insert(
				crumbs,
				kit.text.text {
					"›",
					size = "xs",
					color = T.tertiary,
					opacity = 0.65,
					line = false,
					mx = "$zeron.space.4",
				}
			)
		end
		table.insert(
			crumbs,
			kit.text.text {
				part,
				literal = true,
				size = "xs",
				color = if i == #parts then T.secondary else T.tertiary,
				truncate = true,
				line = false,
				shrink = if i == #parts then 0 else 1,
				min_w = 0,
			}
		)
	end

	local head = ui.row {
		h = 38,
		pl = "$zeron.space.8",
		pr = "$zeron.space.4",
		gap = "$zeron.space.4",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		file_icon.icon { path = path, size = 14 },
		kit.tooltip {
			label = path,
			ui.row { id = `{id}_crumbs`, grow = 1, shrink = 1, min_w = 0, items = "center", overflow = "hidden", crumbs },
		},
		ui.show(function()
			return editable and d.text:get() ~= d.saved:get()
		end, ui.div { id = `{id}_edited`, w = 6, h = 6, rounded = T.radius_full, bg = T.secondary, shrink = 0 }),
		is_markdown and ui.presence(d.markdown, function(on: boolean): Node
			return tool(
				`{id}_markdown`,
				if on then "file-code" else "eye",
				if on then "Show Markdown code" else "Preview Markdown",
				function()
					d.markdown:set(not d.markdown:peek())
				end,
				on
			)
		end) or nil,
		-- The save's status (preview.rs save_status): a save the disk
		-- refused (a press saves again), one that hit a change on disk, the
		-- file gone or changed there; its tooltip says what it means.
		ui.presence(function(): string?
			if d.failed:get() ~= "" then
				return "failed"
			elseif d.conflict:get() then
				return "conflict"
			elseif d.deleted:get() then
				return "deleted"
			elseif d.external:get() then
				return "changed"
			end
			return nil
		end, function(what: string): Node
			local words: string, tip: string = "Changed on disk", "The file changed on disk. Review it before saving."
			if what == "failed" then
				words, tip = "Save failed", d.failed:peek() or ""
			elseif what == "conflict" then
				words, tip = "Save conflict", "The file changed on disk. Your editor buffer was preserved."
			elseif what == "deleted" then
				words, tip = "Deleted on disk", "The file was removed on disk. Your editor buffer was preserved."
			end
			local label = kit.text.text {
				words,
				size = "xs",
				color = if what == "failed" then T.danger else T.warning,
				line = false,
			}
			if what ~= "failed" then
				return kit.tooltip {
					label = tip,
					ui.row {
						id = `{id}_save_status`,
						h = 24,
						px = "$zeron.space.6",
						items = "center",
						shrink = 0,
						label,
					},
				}
			end
			return kit.tooltip {
				label = tip,
				ui.button {
					id = `{id}_save_status`,
					label = "Save file",
					h = 24,
					px = "$zeron.space.6",
					items = "center",
					shrink = 0,
					rounded = "$zeron.radius.6",
					bg = T.clear,
					hover = { bg = T.ink5 },
					border = 0,
					focus = { border = 0 },
					cursor = "pointer",
					on_click = function()
						save(path)
					end,
					label,
				},
			}
		end),
		tool(`{id}_reveal`, "folder", "Reveal file in tree", function()
			M.reveal(path)
		end),
		ui.presence(pref().word_wrap, function(on: boolean): Node
			return tool(`{id}_wrap`, "list", if on then "Disable word wrap" else "Enable word wrap", function()
				pref().word_wrap:set(not pref().word_wrap:peek())
			end, on)
		end),
	}

	-- The lifecycle's bands: a close waiting on edits that can't be saved;
	-- a file changed outside Zeron, or the reload asking first.
	local bands = ui.presence(function(): string
		if d.closing:get() then
			return "closing"
		elseif d.confirming:get() then
			return "confirming"
		elseif d.external:get() then
			return "external"
		end
		return ""
	end, function(what: string): Node
		if what == "closing" then
			return band(`{id}_closing`, "Changes could not be saved safely.", {
				{
					id = "retry",
					label = "Retry",
					run = function()
						if save(path) then
							close_now(path)
						end
					end,
				},
				{
					id = "keep",
					label = "Keep Open",
					tone = "muted",
					run = function()
						d.closing:set(false)
					end,
				},
				{
					id = "discard",
					label = "Discard Changes",
					tone = "danger",
					run = function()
						d.text:set(d.saved:peek())
						d.conflict:set(false)
						close_now(path)
					end,
				},
			})
		elseif what == "confirming" then
			return band(`{id}_reload`, "Discard unsaved changes?", {
				{
					id = "cancel",
					label = "Cancel",
					tone = "muted",
					run = function()
						d.confirming:set(false)
					end,
				},
				{
					id = "confirm",
					label = "Discard & Reload",
					run = function()
						reload(path)
					end,
				},
			})
		elseif what == "external" then
			return band(`{id}_external`, "This file changed outside Zeron.", {
				{
					id = "keep",
					label = "Keep Editing",
					tone = "muted",
					run = function()
						d.external:set(false)
						d.conflict:set(false)
					end,
				},
				{
					id = "reload",
					label = "Reload from Disk",
					run = function()
						if d.text:peek() ~= d.saved:peek() then
							d.confirming:set(true)
						else
							reload(path)
						end
					end,
				},
			})
		end
		return ui.div {}
	end, { w_full = true })

	local body: Node
	if image then
		body = ui.column {
			grow = 1,
			w_full = true,
			items = "center",
			justify = "center",
			p = "$zeron.space.16",
			ui.button {
				id = `{id}_image`,
				label = name_of(path),
				p = 0,
				bg = T.clear,
				border = 0,
				focus = { border = 0 },
				cursor = "zoom_in",
				max_w = "100%",
				on_click = function()
					kit.lightbox.open { src = image.src, name = name_of(path), w = image.w, h = image.h }
				end,
				ui.image { src = image.src, label = name_of(path), max_w = "100%", max_h = 480, fit = "contain" },
			},
		}
	elseif reason and M.TEXT[path] == nil then
		-- Nothing to show: why (centered_state).
		body = ui.column {
			id = `{id}_unavailable`,
			grow = 1,
			w_full = true,
			items = "center",
			justify = "center",
			px = "$zeron.space.24",
			kit.text.text { M.MESSAGES[reason], size = "sm", color = T.secondary, align = "center", wrap = true },
		}
	else
		-- zgx's code editor: the file's syntax coloured as its lines show,
		-- the caret's line marked, Tab indenting (Shift+Tab out); read-only
		-- where the file can't be saved.
		local editor = ui.textarea {
			id = `{id}_editor`,
			value = d.text,
			label = name_of(path),
			line_numbers = true,
			highlight = syntax.for_path(path),
			current_line = T.hover,
			tab = "    ",
			-- Long lines wrap at the editor's width (Settings → Files, or the
			-- toolbar's toggle).
			wrap = pref().word_wrap,
			read_only = not editable,
			gutter = if editable then editor_comments(path) else nil,
			grow = 1,
			w_full = true,
			p = "$zeron.space.8",
			bg = T.clear,
			border = 0,
			rounded = 0,
			font = T.mono,
			text_size = "$font.size.sm",
			line_height = 21,
			color = T.text,
			focus = { border = 0 },
			on_key = function(k: KeyEvent): boolean
				-- Save file (⌘S unless rebound).
				if keys.is("save_file", k) then
					save(path)
					return true
				end
				return false
			end,
		}
		-- Autosave: the edits are saved once they rest for the delay (not
		-- over a change on disk: that asks).
		local edits = 0
		ui.effect(function()
			local now = d.text:get()
			local p = pref()
			if
				not editable
				or not p.autosave:get()
				or now == d.saved:peek()
				or d.external:peek()
				or d.deleted:peek()
				or d.failed:peek() ~= ""
			then
				return
			end
			edits += 1
			local this = edits
			ui.after(require("@kit/settings_page").delay_ms(p.autosave_delay:get()), function()
				if this == edits and p.autosave:peek() then
					save(path)
				end
			end)
		end)
		local function notes(): { Node }
			local out: { Node } = {}
			if reason == "outside" then
				table.insert(out, note(`{id}_outside`, M.MESSAGES.outside, false))
			end
			if truncated then
				table.insert(out, note(`{id}_truncated`, "Large file preview is truncated and read-only.", true))
			end
			return out
		end
		local source = ui.column { grow = 1, w_full = true, min_h = 0, notes(), editor }
		body = if is_markdown
			then ui.presence(d.markdown, function(on: boolean): Node
				if not on then
					return source
				end
				return kit.scroll {
					grow = 1,
					w_full = true,
					label = name_of(path),
					ui.column {
						w_full = true,
						-- Room before the blocks for their "+".
						px = "$zeron.space.32",
						py = "$zeron.space.16",
						notes(),
						kit.markdown.view {
							text = function()
								return d.text:get()
							end,
							id = `{id}_preview`,
							key = `file:{path}`,
							comments = line_comments(path, id),
						},
					},
				}
			end, { grow = 1, w_full = true, min_h = 0 })
			else source
	end
	return ui.column { id = id, w_full = true, h_full = true, items = "stretch", head, bands, body }
end

return M
