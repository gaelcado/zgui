-- A pull request's Code (pull_request_code.rs): the changed files' tree
-- beside one review stream of every file. A file keeps its place in the
-- stream under a header that folds it (the changes pane's convention), the
-- current file's header sticks while its body scrolls, pushed up by the
-- next, and the tree follows the scroll. Under 760 the tree is a picker
-- under the toolbar's Files button. The toolbar steps through the files
-- and says where the reader is, folds them all, splits the diff and copies
-- it. The stream is one virtual list (`ui.list`): only what shows is built.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local file_icon = require("./file_icon")
local diff = require("./diff")
local patch_mod = require("./patch")
local frost = require("./frost")
local pr = require("./pr")
local recipes = require("./recipes")

export type Totals = { files: number, added: number, removed: number }
export type Props = {
	id: string,
	-- The patch; nil while it loads (the skeletons show).
	patch: () -> string?,
	-- What the pull request says it changes, while its patch loads.
	totals: () -> Totals,
	-- The tree beside the stream (760 and wider) or in the picker.
	wide: () -> boolean,
	split: State<boolean>,
	-- The tree's search, and the narrow picker.
	query: State<string>,
	picker: State<boolean>,
	-- A copy: its text and what it is ("diff", "path").
	on_copy: (text: string, what: string) -> (),
	-- Where the stream is scrolled, kept by the caller (a pull request's
	-- page keeps its own).
	offset: State<number>?,
	-- A file's syntax colours, by its path (lib/syntax's for_path).
	highlight: ((path: string) -> ((line: string, state: number) -> ({ { number | string } }, number))?)?,
}

local M = {}

M.FILES_WIDTH = 260
M.WIDE = 760
M.TREE_ROW = 28
M.TREE_INDENT = 14
M.PICKER_W = 320
M.PICKER_H = 360
M.HEADER = pr.FILE_HEADER
M.NOTICE = 24

-- `path`'s folder (with its slash) and name.
local function split_path(path: string): (string, string)
	local dir, name = string.match(path, "^(.*/)([^/]*)$")
	if dir then
		return dir, name :: string
	end
	return "", path
end

-- The files in directory order, so each folder appears once in the tree
-- and the stream reads as the tree does.
function M.files(text: string): { patch_mod.File }
	local files = patch_mod.parse(text)
	local function key(f: patch_mod.File): string
		local dir, name = split_path(f.path)
		return if dir == "" then `0\0\0{name}` else `1\0{dir}\0{name}`
	end
	table.sort(files, function(a, b)
		return key(a) < key(b)
	end)
	return files
end

-- What a file's header says before its hunks (file_notices).
local function notices(f: patch_mod.File): { string }
	local out: { string } = {}
	if f.status == "added" then
		table.insert(out, "New file")
	elseif f.status == "deleted" then
		table.insert(out, "Deleted file")
	elseif f.status == "renamed" then
		table.insert(out, `Renamed from {f.old_path or "?"}`)
	end
	if f.binary then
		table.insert(out, "Binary file — contents not shown")
	end
	return out
end

-- The tree's rows: a folder names its whole path (`crates/ui/src`), its
-- files under it; files at the root first. `query` keeps the paths that
-- hold it.
export type EntryKind = "dir" | "file"
export type Entry = { kind: EntryKind, path: string, name: string, depth: number, index: number? }
function M.tree(files: { patch_mod.File }, query: string): { Entry }
	local out: { Entry } = {}
	local current: string? = nil
	local q = string.lower(query)
	for i, f in files do
		if q == "" or string.find(string.lower(f.path), q, 1, true) then
			local dir, name = split_path(f.path)
			local folder = if dir == "" then nil else string.sub(dir, 1, -2)
			if folder ~= current then
				if folder then
					table.insert(out, { kind = "dir" :: EntryKind, path = folder, name = folder, depth = 0 })
				end
				current = folder
			end
			table.insert(
				out,
				{ kind = "file" :: EntryKind, path = f.path, name = name, depth = if folder then 1 else 0, index = i }
			)
		end
	end
	return out
end

-- Additions and deletions, mono, each only when there are some.
local function counts(added: number, removed: number, size: txt.Size): Node
	return ui.row {
		shrink = 0,
		gap = "$zeron.space.6",
		added > 0 and txt.text { `+{added}`, size = size, mono = true, color = T.diff_add, line = false } or nil,
		removed > 0 and txt.text { `−{removed}`, size = size, mono = true, color = T.diff_del, line = false } or nil,
	}
end

type RowKind = "file" | "notice" | "hunk" | "line" | "pair"
type Row = {
	kind: RowKind,
	file: number,
	text: string?,
	line: diff.Line?,
	pair: patch_mod.Pair?,
}

M.view = ui.component(function(props: Props): Node
	local id = props.id
	local files = ui.computed(function(): { patch_mod.File }?
		local text = props.patch()
		return if text then M.files(text) else nil
	end)
	-- Folded files, by their place.
	local folded = ui.use_state({} :: { [number]: boolean })
	local offset = props.offset or ui.use_state(0)
	-- One sideways scroll for every line, as wide as the longest; each
	-- file's lines in its syntax's colours.
	local sideways = ui.use_state(0)
	local width = ui.computed(function(): number
		local lines: { diff.Line } = {}
		for _, f in files:get() or {} do
			for _, h in f.hunks do
				table.move(h.lines, 1, #h.lines, #lines + 1, lines)
			end
		end
		return diff.code_width(lines)
	end)
	local codes: { [number]: diff.Code } = {}
	local function code(file: number): diff.Code
		local c = codes[file]
		if not c then
			local f = (files:peek() :: { patch_mod.File })[file]
			c = {
				highlight = if props.highlight then props.highlight(f.path) else nil,
				scroll = sideways,
				width = width:peek(),
			}
			codes[file] = c
		end
		return c
	end
	-- Built the first time with the place it was left at; again (a fold,
	-- the split), with the current file kept where it was.
	local rebuilt = false
	-- A file picked from the tree or the toolbar stays the current one
	-- until the reader scrolls (the last files cannot reach the top).
	local jumped = ui.use_state(nil :: { file: number, at: number }?)
	local list = ui.ref()

	local rows = ui.computed(function(): { Row }
		local out: { Row } = {}
		local split = props.split:get()
		local shut = folded:get()
		for fi, f in files:get() or {} do
			table.insert(out, { kind = "file" :: RowKind, file = fi })
			if not shut[fi] then
				for _, n in notices(f) do
					table.insert(out, { kind = "notice" :: RowKind, file = fi, text = n })
				end
				for _, h in f.hunks do
					table.insert(out, { kind = "hunk" :: RowKind, file = fi, text = h.header })
					if split then
						for _, p in patch_mod.pairs(h.lines) do
							table.insert(out, { kind = "pair" :: RowKind, file = fi, pair = p })
						end
					else
						for _, l in h.lines do
							table.insert(out, { kind = "line" :: RowKind, file = fi, line = l })
						end
					end
				end
			end
		end
		return out
	end)
	local function height(r: Row): number
		if r.kind == "file" then
			return M.HEADER
		elseif r.kind == "notice" then
			return M.NOTICE
		elseif r.kind == "hunk" then
			return diff.HUNK
		end
		return diff.LINE
	end
	-- Where each file's header starts in the stream, and its row.
	local layout = ui.computed(function(): { starts: { number }, heads: { number } }
		local starts, heads = {}, {}
		local y = 0
		for i, r in rows:get() do
			if r.kind == "file" then
				table.insert(starts, y)
				table.insert(heads, i)
			end
			y += height(r)
		end
		return { starts = starts, heads = heads }
	end)
	-- The file under the top of the stream, or the one just picked.
	local active = ui.computed(function(): number?
		local starts = layout:get().starts
		if #starts == 0 then
			return nil
		end
		local y = offset:get()
		local j = jumped:get()
		if j and math.abs(y - j.at) < 1 then
			return j.file
		end
		local at = 1
		for i, start in starts do
			if start <= y + 0.5 then
				at = i
			end
		end
		return at
	end)
	local function count(): number
		local fs = files:get()
		return if fs then #fs else 0
	end

	local function go(file: number)
		local heads = layout:peek().heads
		local el = list:peek()
		if not heads[file] or not el then
			return
		end
		el:scroll_to_row(heads[file], { align = "start" })
		-- The list lands where it can: that is where the pick holds.
		jumped:set { file = file, at = offset:peek() }
	end
	local function toggle(file: number)
		folded:set_key(file, if folded:peek()[file] then nil else true)
	end

	local function file_header(file: number): Node
		local f = (files:peek() :: { patch_mod.File })[file]
		local dir, name = split_path(f.path)
		local function shut(): boolean
			return folded:get()[file] == true
		end
		return ui.row {
			id = `{id}_file_{file}`,
			w_full = true,
			h = M.HEADER,
			px = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			cursor = "pointer",
			role = "button",
			label = function()
				return `{f.path}, {if shut() then "collapsed" else "expanded"}`
			end,
			variants = recipes.pr_file_header {},
			border_sides = if file > 1 then { 1, 0, 0, 0 } else nil,
			border_color = T.border,
			on_click = function()
				toggle(file)
			end,
			ui.presence(function()
				return if shut() then "shut" else "open"
			end, function(state: string): Node
				return icon {
					name = if state == "shut" then "alt-arrow-right" else "alt-arrow-down",
					size = 13,
					color = T.tertiary,
				}
			end),
			file_icon.icon { path = f.path, size = 14 },
			ui.row {
				grow = 1,
				shrink = 1,
				min_w = 0,
				overflow = "hidden",
				dir ~= "" and txt.text {
					dir,
					literal = true,
					size = "sm",
					mono = true,
					color = T.secondary,
					truncate = true,
					shrink = 1,
					min_w = 0,
					line = false,
				} or nil,
				txt.text { name, literal = true, size = "sm", mono = true, shrink = 0, line = false },
			},
			counts(f.added, f.removed, "xs"),
			pr.action {
				id = `{id}_copy_path_{file}`,
				label = "Copy path",
				icon = "copy",
				on_click = function()
					props.on_copy(f.path, "path")
				end,
			},
		}
	end

	local function build(r: Row?): Node
		if not r then
			return ui.div {}
		end
		if r.kind == "file" then
			return file_header(r.file)
		elseif r.kind == "notice" then
			return ui.row {
				w_full = true,
				h = M.NOTICE,
				px = "$zeron.space.16",
				items = "center",
				txt.text { r.text :: string, literal = true, size = "xs", color = T.tertiary, line = false },
			}
		elseif r.kind == "hunk" then
			return diff.hunk_header(r.text :: string)
		elseif r.kind == "pair" then
			local p = r.pair :: patch_mod.Pair
			return diff.split(p.left, p.right, nil, nil, code(r.file))
		end
		return diff.line(r.line :: diff.Line, nil, code(r.file))
	end

	local stream = ui.presence(function()
		local fs = files:get()
		if fs == nil then
			return "loading"
		end
		if #fs == 0 then
			return "empty"
		end
		-- Built again when the rows change (a fold, the split): the offset
		-- carries the place over.
		local shut = {}
		for k in folded:get() do
			table.insert(shut, tostring(k))
		end
		table.sort(shut)
		return `{props.split:get()}|{table.concat(shut, ",")}`
	end, function(state: string): Node
		if state == "loading" then
			return pr.diff_skeleton { id = `{id}_skeleton`, split = props.split:peek() }
		elseif state == "empty" then
			return ui.column {
				w_full = true,
				h_full = true,
				items = "center",
				justify = "center",
				txt.text { "No changed files", size = "sm", color = T.tertiary, line = false },
			}
		end
		local all = rows:peek()
		local heights: { number } = {}
		local sticky: { number } = {}
		for i, r in all do
			table.insert(heights, height(r))
			if r.kind == "file" then
				table.insert(sticky, i)
			end
		end
		-- The current file keeps its place as the stream is built again.
		local anchor = if rebuilt then active:peek() else nil
		rebuilt = true
		table.clear(codes)
		return ui.list {
			id = `{id}_stream`,
			ref = list,
			w_full = true,
			h_full = true,
			label = "Changes",
			scrollbar = true,
			offset = offset,
			heights = heights,
			sticky = sticky,
			on_mount = function(el: Element)
				local heads = layout:peek().heads
				if anchor and anchor > 1 and heads[anchor] then
					el:scroll_to_row(heads[anchor], { align = "start" })
				end
			end,
			row = function(index: number): Node
				return build(all[index])
			end,
		}
	end, { w_full = true, h_full = true })

	local function tree(in_picker: boolean): Node
		local function entries(): { Entry }
			local fs = files:get()
			return if fs then M.tree(fs, props.query:get()) else {}
		end
		local function step(key: string): boolean
			local ids: { number } = {}
			for _, e in entries() do
				if e.kind == "file" then
					table.insert(ids, e.index :: number)
				end
			end
			if #ids == 0 then
				return false
			end
			local at = table.find(ids, active:peek() or 0)
			local next_at: number
			if key == "ArrowDown" then
				next_at = if at then math.min(at + 1, #ids) else 1
			elseif key == "ArrowUp" then
				next_at = if at then math.max(at - 1, 1) else 1
			elseif key == "Home" then
				next_at = 1
			elseif key == "End" then
				next_at = #ids
			else
				return false
			end
			go(ids[next_at])
			return true
		end
		local function totals(): Totals
			local fs = files:get()
			if not fs then
				return props.totals()
			end
			local added, removed = 0, 0
			for _, f in fs do
				added += f.added
				removed += f.removed
			end
			return { files = #fs, added = added, removed = removed }
		end
		local rows_view = ui.presence(function()
			local fs = files:get()
			if not fs then
				return "loading"
			end
			local keys = {}
			for _, e in entries() do
				table.insert(keys, e.path)
			end
			return if #keys == 0 then "none" else table.concat(keys, "\n")
		end, function(state: string): Node
			if state == "loading" then
				return pr.tree_skeleton { id = `{id}_tree_skeleton` }
			elseif state == "none" then
				return ui.row {
					px = "$zeron.space.8",
					py = "$zeron.space.6",
					txt.text { "No matching files", size = "sm", color = T.secondary, line = false },
				}
			end
			local out: { Node } = {}
			local fs = files:peek() :: { patch_mod.File }
			for _, e in entries() do
				local pad = T.space(8 + e.depth * M.TREE_INDENT)
				if e.kind == "dir" then
					table.insert(
						out,
						ui.row {
							h = M.TREE_ROW,
							shrink = 0,
							pl = pad,
							pr = "$zeron.space.8",
							gap = "$zeron.space.6",
							items = "center",
							file_icon.icon { path = e.name, folder = true, size = 14 },
							txt.text {
								e.name,
								literal = true,
								size = "sm",
								color = T.secondary,
								truncate = true,
								shrink = 1,
								min_w = 0,
								line = false,
							},
						}
					)
				else
					local index = e.index :: number
					local f = fs[index]
					local function on(): boolean
						return active:get() == index
					end
					table.insert(
						out,
						ui.button {
							id = `{id}_tree_{index}`,
							role = "treeitem",
							label = `Open diff for {f.path}`,
							selected = on,
							h = M.TREE_ROW,
							w_full = true,
							shrink = 0,
							pl = pad,
							pr = "$zeron.space.8",
							gap = "$zeron.space.6",
							items = "center",
							rounded = "$zeron.radius.6",
							focusable = false,
							cursor = "pointer",
							variants = recipes.pr_tree_row { on = on },
							on_click = function()
								go(index)
								if in_picker then
									props.picker:set(false)
								end
							end,
							file_icon.icon { path = f.path, size = 14 },
							txt.text {
								e.name,
								literal = true,
								size = "sm",
								color = "inherit",
								truncate = true,
								grow = 1,
								shrink = 1,
								min_w = 0,
								line = false,
							},
							counts(f.added, f.removed, "micro"),
						}
					)
				end
			end
			return ui.column { w_full = true, gap = "$zeron.space.1", out }
		end, { w_full = true })
		return ui.column {
			id = if in_picker then `{id}_picker_tree` else `{id}_tree`,
			w_full = true,
			h_full = true,
			min_h = 0,
			gap = "$zeron.space.8",
			ui.row {
				h = 24,
				shrink = 0,
				px = "$zeron.space.8",
				gap = "$zeron.space.8",
				items = "center",
				txt.text { "Files", size = "sm", weight = "medium", line = false },
				txt.text {
					function()
						return tostring(totals().files)
					end,
					size = "sm",
					color = T.secondary,
					grow = 1,
					line = false,
				},
				ui.presence(function()
					local t = totals()
					return `{t.added}|{t.removed}`
				end, function(): Node
					local t = totals()
					return counts(t.added, t.removed, "xs")
				end),
			},
			ui.row {
				h = 24,
				shrink = 0,
				px = "$zeron.space.8",
				gap = "$zeron.space.6",
				items = "center",
				rounded = "$zeron.radius.6",
				bg = T.ink2,
				ui.input {
					id = `{id}_{if in_picker then "picker_" else ""}search`,
					value = props.query,
					label = "Find a changed file",
					placeholder = "Find a changed file…",
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
					on_mount = if in_picker
						then function(el: Element)
							el:focus()
						end
						else nil,
					on_key = function(k: KeyEvent): boolean
						if k.key == "Enter" then
							for _, e in entries() do
								if e.kind == "file" then
									go(e.index :: number)
									if in_picker then
										props.picker:set(false)
									end
									return true
								end
							end
							return true
						elseif k.key == "Escape" and in_picker then
							props.picker:set(false)
							return true
						end
						return false
					end,
				},
			},
			ui.scroll {
				id = `{id}_{if in_picker then "picker_" else ""}files`,
				grow = 1,
				min_h = 0,
				w_full = true,
				fade = { 16, 16 },
				fade_overflow = true,
				focusable = true,
				role = "tree",
				label = "Changed files",
				on_key = function(k: KeyEvent): boolean
					return step(k.key)
				end,
				ui.column {
					w_full = true,
					pt = "$zeron.space.4",
					pb = if in_picker
						then "$zeron.space.8"
						else ui.raw(pr.NAV_CLEARANCE, "the floating navigation's room"),
					rows_view,
				},
			},
		}
	end

	local function position(): string
		local n = count()
		if files:get() == nil then
			return "Loading changes…"
		elseif n == 0 then
			return "No changed files"
		end
		return `File {active:get() or 1} of {n}`
	end
	local function all_folded(): boolean
		local n = count()
		local shut = 0
		for _ in folded:get() do
			shut += 1
		end
		return n > 0 and shut == n
	end
	local toolbar = ui.row {
		id = `{id}_toolbar`,
		h = 24,
		shrink = 0,
		min_w = 0,
		gap = "$zeron.space.4",
		items = "center",
		ui.show(
			function()
				return not props.wide()
			end,
			pr.action {
				id = `{id}_files`,
				label = "Choose a changed file",
				icon = "file-tree",
				selected = props.picker,
				on_click = ui.toggle(props.picker),
			}
		),
		pr.action {
			id = `{id}_previous`,
			label = "Previous file",
			icon = "alt-arrow-up",
			dim = function()
				return (active:get() or 0) <= 1
			end,
			on_click = function()
				local at = active:peek()
				if at and at > 1 then
					go(at - 1)
				end
			end,
		},
		pr.action {
			id = `{id}_next`,
			label = "Next file",
			icon = "alt-arrow-down",
			dim = function()
				return (active:get() or 0) >= count()
			end,
			on_click = function()
				local at = active:peek() or 0
				if at < count() then
					go(at + 1)
				end
			end,
		},
		txt.text {
			position,
			id = `{id}_position`,
			size = "sm",
			color = T.secondary,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
			px = "$zeron.space.4",
			line = false,
		},
		pr.action {
			id = `{id}_fold_all`,
			label = function()
				return if all_folded() then "Expand all files" else "Collapse all files"
			end,
			icon = "fold-vertical",
			on_click = function()
				if all_folded() then
					folded:set {}
				else
					local shut: { [number]: boolean } = {}
					for i = 1, count() do
						shut[i] = true
					end
					folded:set(shut)
				end
				jumped:set(nil)
			end,
		},
		pr.action {
			id = `{id}_split`,
			label = function()
				return if props.split:get() then "Show unified diff" else "Show split diff"
			end,
			icon = "split-columns",
			selected = props.split,
			on_click = ui.toggle(props.split),
		},
		pr.action {
			id = `{id}_copy`,
			label = "Copy diff",
			icon = "copy",
			on_click = function()
				local text = props.patch()
				if text then
					props.on_copy(text, "diff")
				end
			end,
		},
	}

	local editor = ui.column {
		relative = true,
		grow = 1,
		shrink = 1,
		min_w = 0,
		h_full = true,
		gap = "$zeron.space.8",
		pb = ui.raw(pr.NAV_CLEARANCE, "the floating navigation's room"),
		toolbar,
		ui.column {
			id = `{id}_viewport`,
			grow = 1,
			min_h = 0,
			w_full = true,
			rounded = T.radius_card,
			border = 1,
			border_color = T.border,
			overflow = "hidden",
			stream,
		},
		-- Narrow: the tree in a picker under the toolbar, over a layer a
		-- press on which closes it.
		ui.presence(function()
			return if props.picker:get() and not props.wide() then "open" else nil
		end, function(): Node
			return ui.div {
				absolute = true,
				left = 0,
				top = 0,
				right = 0,
				bottom = 0,
				ui.div {
					id = `{id}_picker_dismiss`,
					absolute = true,
					left = 0,
					top = 0,
					right = 0,
					bottom = 0,
					on_press = function()
						props.picker:set(false)
					end,
				},
				ui.column {
					absolute = true,
					left = 0,
					top = 28,
					w = M.PICKER_W,
					max_w = "100%",
					h = M.PICKER_H,
					max_h = "90%",
					frost.card {
						id = `{id}_picker`,
						w_full = true,
						h = "100%",
						p = "$zeron.space.8",
						tree(true),
					},
				},
			}
		end, { absolute = true, left = 0, top = 0, right = 0, bottom = 0, pointer_events = "none" }),
	}

	return ui.row {
		id = id,
		w_full = true,
		h_full = true,
		min_h = 0,
		gap = "$zeron.space.16",
		ui.show(props.wide, ui.column { w = M.FILES_WIDTH, shrink = 0, h_full = true, min_h = 0, tree(false) }),
		editor,
	}
end)

return M
