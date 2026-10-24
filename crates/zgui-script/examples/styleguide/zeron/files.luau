-- The Files column (files/mod.rs): the project's tree, folders folding
-- under their chevron, the name coloured by its git status (modified,
-- added, renamed, deleted; ignored dimmed). The magnifier searches the
-- workspace's paths ("No files found."); a file opens in the right pane,
-- in the editor (line numbers, ⌘S saves, a dot while edited) or, for
-- Markdown, a preview with its source a click away, an image fitted and
-- enlarged in the viewer. A secondary click: Add to chat, Copy path,
-- Rename… (in place), Delete… (asked first).
local T = require("../theme")
local kit = require("@kit")
local file_tree = require("@kit/file_tree")
local data = require("./data")
local chrome = require("./chrome")
local state = require("./state")

local M = {}

-- The workspace: each entry's path, and a file's text (or an image's).
type Node_ = { path: string, folder: boolean?, git: file_tree.Git, icon: string? }
local PATHS: { Node_ } = {
	{ path = "crates", folder = true },
	{ path = "crates/zgui", folder = true, icon = "folder-with-files" },
	{ path = "crates/zgui/compose.rs", git = "modified", icon = "file-code" },
	{ path = "crates/zgui/compose_scrollbar.rs", icon = "file-code" },
	{ path = "crates/zgui/layout_old.rs", git = "deleted", icon = "file-code" },
	{ path = "crates/styleguide", folder = true },
	{ path = "crates/styleguide/canvas.luau", git = "added", icon = "file-code" },
	{ path = "crates/styleguide/shadow.jpg", icon = "file-image" },
	{ path = "target", folder = true, git = "ignored" },
	{ path = "Cargo.toml", icon = "file-data" },
	{ path = "README.md", git = "modified", icon = "file-markdown" },
}
M.TEXT = {
	["crates/zgui/compose.rs"] = table.concat({
		"fn place(&mut self, node: NodeId) {",
		"    let parent = self.parent(node);",
		"    let centred = parent.items == Align::Center && self_align.is_none();",
		"    if centred {",
		"        offset = (room - size) / 2.;",
		"    }",
		"}",
	}, "\n"),
	["crates/zgui/compose_scrollbar.rs"] = "pub fn mount(ui: &mut Ui, root: NodeId) {\n    // The thumb follows the offset.\n}",
	["crates/styleguide/canvas.luau"] = "return ui.column {\n\tw_full = true,\n\tgap = 12,\n}",
	["Cargo.toml"] = '[workspace]\nmembers = ["crates/*"]\nresolver = "2"',
	["README.md"] = table.concat(data.README, "\n"),
}
M.IMAGES = { ["crates/styleguide/shadow.jpg"] = { src = "images/shadow.jpg", w = 720, h = 480 } }

local function name_of(path: string): string
	return string.match(path, "([^/]+)$") or path
end
local function depth_of(path: string): number
	return select(2, string.gsub(path, "/", ""))
end
local function parent_of(path: string): string?
	return string.match(path, "^(.*)/[^/]+$")
end

-- The tree as it stands: renames and deletions applied, folders' open.
M.paths = ui.state("files_paths", PATHS :: { Node_ })
M.shut = ui.state("files_shut", { target = true } :: { [string]: boolean })
local selected = ui.state("tree_sel", "crates/zgui/compose.rs")
local renaming = ui.state("files_renaming", "")
local searching = ui.state("files_searching", false)
local query = ui.state("files_query", "")
local deleting = ui.state("files_deleting", "")
local copied = ui.state("files_copied", "")

-- The rows that show: an entry under a shut folder does not.
local function entries(): { file_tree.Entry }
	local out: { file_tree.Entry } = {}
	local shut = M.shut:get()
	for _, n in M.paths:get() do
		local hidden = false
		local up = parent_of(n.path)
		while up do
			if shut[up] then
				hidden = true
				break
			end
			up = parent_of(up)
		end
		if not hidden then
			table.insert(out, {
				id = n.path,
				name = name_of(n.path),
				level = depth_of(n.path),
				folder = n.folder,
				open = n.folder and not shut[n.path] or nil,
				icon = n.icon :: any,
				git = n.git,
			})
		end
	end
	return out
end

-- Opens `path` in the right pane: its tab, or a new one.
function M.open(path: string)
	for _, t in state.tabs:peek() do
		if t.kind == "file" and t.ref == path then
			state.tab:set(t.id)
			return
		end
	end
	local id = `file_{string.gsub(path, "[^%w]", "_")}`
	local list = table.clone(state.tabs:peek())
	table.insert(list, { id = id, kind = "file" :: state.Kind, ref = path })
	state.tabs:set(list)
	state.tab:set(id)
	require("@kit/panel_shell").set_open(state.chat, "right", true)
end

-- Renames `path` to `name` (one name: no separators), its children with it.
function M.rename(path: string, name: string): boolean
	if string.find(name, "/", 1, true) or string.find(name, "\\", 1, true) then
		return false
	end
	local up = parent_of(path)
	local to = if up then `{up}/{name}` else name
	local out = {}
	for _, n in M.paths:peek() do
		local p = n.path
		if p == path or string.sub(p, 1, #path + 1) == path .. "/" then
			local moved = table.clone(n)
			moved.path = to .. string.sub(p, #path + 1)
			moved.git = "renamed"
			table.insert(out, moved)
		else
			table.insert(out, n)
		end
	end
	M.paths:set(out)
	if M.TEXT[path] then
		M.TEXT[to] = M.TEXT[path]
	end
	selected:set(to)
	return true
end

function M.delete(path: string)
	local out = {}
	for _, n in M.paths:peek() do
		if n.path ~= path and string.sub(n.path, 1, #path + 1) ~= path .. "/" then
			table.insert(out, n)
		end
	end
	M.paths:set(out)
end

local function menu(e: file_tree.Entry): { Node }
	local function item(id: string, label: string, glyph: string, run: () -> (), danger: boolean?): Node
		return ui.menu_item {
			id = `files_menu_{id}`,
			label = label,
			on_click = run,
			ui.row {
				gap = "$zeron.space.10",
				items = "center",
				kit.icon { name = glyph :: any, size = 16, color = if danger then T.danger else T.secondary },
				kit.text.text { label, size = "md", color = if danger then T.danger else T.text, line = false },
			},
		}
	end
	return {
		item("chat", "Add to chat", "chat-round-line", function()
			local draft = require("./conversation").draft(state.session:peek())
			local text = draft:peek()
			draft:set(`{text}{if text == "" or string.sub(text, -1) == " " then "" else " "}@{e.id} `)
		end),
		item("copy", "Copy path", "copy", function()
			copied:set(e.id)
			ui.clipboard.write(e.id)
		end),
		item("rename", "Rename…", "pen", function()
			renaming:set(e.id)
		end),
		item("delete", "Delete…", "trash-bin-minimalistic", function()
			deleting:set(e.id)
		end, true),
	}
end

-- Paths holding the query (any case), files first, at most 200.
function M.search(q: string): { Node_ }
	local needle = string.lower(q)
	local files, folders = {}, {}
	for _, n in M.paths:get() do
		if string.find(string.lower(n.path), needle, 1, true) then
			table.insert(if n.folder then folders else files, n)
		end
	end
	table.move(folders, 1, #folders, #files + 1, files)
	return files
end

local function search_results(): Node
	return ui.presence(function()
		return query:get()
	end, function(q: string): Node
		local found = M.search(q)
		if #found == 0 then
			return ui.row {
				h = 27,
				px = "$zeron.space.12",
				items = "center",
				kit.text.text { "No files found.", size = "xs", color = T.tertiary, line = false },
			}
		end
		local rows: { Node } = {}
		for i, n in found do
			if i > 200 then
				break
			end
			table.insert(
				rows,
				ui.button {
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
					kit.icon {
						name = (n.icon or (if n.folder then "folder" else "document")) :: any,
						size = 14,
						color = T.secondary,
					},
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
			)
		end
		return ui.column { w_full = true, items = "stretch", rows }
	end, { w_full = true })
end

local function header(): Node
	return ui.row {
		h = 32,
		px = "$zeron.space.12",
		gap = "$zeron.space.6",
		items = "center",
		shrink = 0,
		ui.show(function()
			return not chrome.glass()
		end, kit.text.text { "Files", size = "sm", weight = "semibold", line = false }),
		ui.div { grow = 1 },
		kit.icon_button {
			id = "files_search",
			icon = "magnifer",
			size = 24,
			icon_size = 14,
			label = "Search files",
			on_click = function()
				searching:set(not searching:peek())
				query:set("")
			end,
		},
	}
end

local function search_field(): Node
	return ui.row {
		mx = "$zeron.space.8",
		mb = "$zeron.space.6",
		h = 26,
		px = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		bg = T.ink1,
		shrink = 0,
		kit.icon { name = "magnifer", size = 12, color = T.tertiary },
		ui.input {
			id = "files_query",
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
			on_mount = function(el: Element)
				el:focus()
			end,
			on_key = function(k: KeyEvent): boolean
				if k.key == "Escape" then
					searching:set(false)
					return true
				end
				return false
			end,
		},
	}
end

-- Asks before deleting (files/rename.rs).
local function delete_dialog(): Node
	local open = ui.state("files_delete_open", false)
	ui.effect(function()
		open:set(deleting:get() ~= "")
	end)
	ui.effect(function()
		if not open:get() then
			deleting:set("")
		end
	end)
	return kit.dialog {
		id = "files_delete",
		open = open,
		title = "Delete permanently?",
		description = "This cannot be undone.",
		actions = {
			kit.button {
				id = "files_delete_cancel",
				label = "Cancel",
				variant = "ghost",
				size = "sm",
				on_click = function()
					deleting:set("")
				end,
			},
			kit.button {
				id = "files_delete_confirm",
				label = "Delete",
				variant = "danger",
				size = "sm",
				on_click = function()
					M.delete(deleting:peek())
					deleting:set("")
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
		header(),
		ui.show(searching, search_field()),
		ui.presence(function()
			if searching:get() and query:get() ~= "" then
				return "search"
			end
			-- Built again as folders fold and entries change (a small tree).
			local keys = {}
			for _, e in entries() do
				table.insert(keys, `{e.id}:{e.open and 1 or 0}:{e.git or ""}`)
			end
			return table.concat(keys, ",")
		end, function(key: string): Node
			if key == "search" then
				return search_results()
			end
			return file_tree.tree {
				id = "ztree",
				entries = (function()
					local list: { file_tree.Entry } = {}
					for _, e in entries() do
						table.insert(list, e)
					end
					return list
				end)(),
				selected = selected,
				on_toggle = function(id: string)
					M.shut:set_key(id, if M.shut:peek()[id] then nil else true)
				end,
				on_open = function(e: file_tree.Entry)
					M.open(e.id)
				end,
				menu = menu,
				renaming = renaming,
				on_rename = function(id: string, name: string)
					M.rename(id, name)
				end,
			}
		end, { w_full = true }),
		delete_dialog(),
	}
end

-- A file's own surface in the right pane (files/preview.rs): its header
-- (icon, name, folder, Edited's dot), then the editor, the Markdown
-- preview or the image.
function M.surface(path: string, id: string): Node
	local image = M.IMAGES[path]
	local markdown = string.match(path, "%.md$") ~= nil
	local text = ui.state(`file_text:{path}`, M.TEXT[path] or "")
	local saved = ui.state(`file_saved:{path}`, M.TEXT[path] or "")
	local mode = ui.state(`file_mode:{path}`, if markdown then "preview" else "source")
	local head = ui.row {
		h = 40,
		px = "$zeron.space.14",
		gap = "$zeron.space.8",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		kit.icon { name = if image then "file-image" else "document", size = 16, color = T.secondary },
		kit.text.text { name_of(path), size = "md", weight = "semibold", shrink = 0 },
		ui.show(function()
			return text:get() ~= saved:get()
		end, ui.div { id = `{id}_edited`, w = 6, h = 6, rounded = T.radius_full, bg = T.secondary }),
		kit.text.text {
			parent_of(path) or "",
			literal = true,
			size = "sm",
			color = T.tertiary,
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
		},
		ui.div { grow = 1 },
		markdown and kit.segmented {
			id = `{id}_mode`,
			size = "sm",
			value = mode :: any,
			options = { { id = "preview", label = "Preview" }, { id = "source", label = "Source" } },
		} or nil,
	}
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
	else
		local editor = ui.textarea {
			id = `{id}_editor`,
			value = text,
			label = name_of(path),
			line_numbers = true,
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
				-- ⌘S saves.
				if k.key == "s" and (k.meta or k.ctrl) then
					saved:set(text:peek())
					return true
				end
				return false
			end,
		}
		body = if markdown
			then ui.presence(mode, function(m: string): Node
				if m == "source" then
					return editor
				end
				return kit.scroll {
					grow = 1,
					w_full = true,
					label = name_of(path),
					ui.column {
						w_full = true,
						p = "$zeron.space.16",
						kit.markdown.view {
							text = function()
								return text:get()
							end,
							key = `file:{path}`,
						},
					},
				}
			end, { grow = 1, w_full = true, min_h = 0 })
			else editor
	end
	return ui.column { id = id, w_full = true, h_full = true, items = "stretch", head, body }
end

return M
