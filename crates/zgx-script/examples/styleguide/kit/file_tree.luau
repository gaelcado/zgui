-- The files tree (files/tree.rs), on zgx's tree (`ui.tree`: one Tab stop,
-- Up and Down move, Right opens then enters, Left closes then goes up,
-- typing finds, Enter opens; the rows are virtual): rows 27 high, 14 of
-- indent per level from 8, 1-point guides at each level, an 11-point
-- chevron in a 14 slot for folders, the entry's own 14 icon (kit/
-- file_icon) and the name at 11.5. An open folder with nothing in it says
-- "Empty folder"; one with more than it lists ends in "Load more…". Git
-- status colours the name; selection is wash 12% (8% unfocused), hover
-- 5.5%. A press on a folder folds it, on a file opens it. A secondary
-- click shows the entry's menu (`menu`); an entry being renamed shows its
-- name in a field in place (files/rename.rs): Enter keeps it, Escape or
-- leaving it drops it.
--
-- Dragged (files/drag.rs), a row is a chip under the pointer (24 high,
-- radius 6, the raised surface in a strong hairline at 85%, its icon and
-- name) carrying `{ kind = "file", path, name, folder }`: into the chat, a
-- mention. With `on_move`, onto a folder (a file's own folder, or the
-- workspace root over the tree's top row and its empty end) it moves
-- there: the folder's row washes at 16% while it would take it (never its
-- own folder, itself or a folder inside it), and a folder rested on opens
-- (spring loading).
--
-- With `selection` it chooses several (files/tree.rs, zgx's tree): ⌘ and
-- a click adds or takes away, Shift a range, Shift and an arrow extends,
-- Escape keeps the current one, a press below the rows chooses none. The
-- chosen wash at 12% (8% unfocused); the keyboard's own row, once it is
-- not the whole choice, at 16% chosen and 4% not. A chosen row dragged
-- carries every chosen entry ("N items"), the menu acts on them all.
local T = require("../theme")
local recipes = require("./recipes")
local wash = require("./wash")
local types = require("./types")
local icon = require("./icon")
local file_icon = require("./file_icon")
local txt = require("./text")

export type Git = "added" | "modified" | "renamed" | "deleted" | "ignored" | nil
-- An entry, in `ui.tree`'s shape (its `label` the name; a folder's
-- entries under it), with what the explorer shows of it. A `status` row
-- stands in a folder for what it can't list: "empty", or "more" (a click
-- loads the next page, `on_more`).
export type Entry = {
	id: string,
	label: string,
	folder: boolean?,
	git: Git,
	children: { Entry }?,
	status: ("empty" | "more")?,
}
-- An entry of a flat list: its depth from 0, and whether it shows open.
export type Flat = {
	id: string,
	name: string,
	level: number,
	folder: boolean?,
	open: boolean?,
	git: Git,
}
export type Props = {
	id: string?,
	items: State<{ Entry }>,
	-- The open folders' ids, both ways.
	open: State<{ string }>,
	selected: State<string>,
	-- The chosen entries' ids, both ways, choosing several.
	selection: State<{ string }>?,
	focused: types.Cond?,
	-- A file chosen (a press on it, or Enter).
	on_open: ((e: Entry) -> ())?,
	-- A folder's "Load more…" pressed: the folder's id.
	on_more: ((folder: string) -> ())?,
	-- The entry's context menu: its `ui.menu_item`s, and what they act on
	-- (the chosen entries with it, else it alone).
	menu: ((e: Entry, paths: { string }) -> { Node })?,
	-- The entry being renamed (its id; "" for none), and what renaming it
	-- to a name does (false: refused, the field stays).
	renaming: State<string>?,
	on_rename: ((id: string, name: string) -> boolean?)?,
	-- Rows drag out (into the chat); with `on_move`, within the tree: an
	-- entry onto a folder ("" the workspace root). Ids are paths.
	draggable: boolean?,
	on_move: ((id: string, folder: string) -> ())?,
	w: Length?,
	-- The rows are virtual: the tree takes the room it is given, unless it
	-- `fit`s the rows it shows (a short tree in a card).
	h: Length?,
	fit: boolean?,
}

local M = {}

M.ROW = 27
M.INDENT = 14
M.BASE = 8

local GIT: { [string]: Color } = {
	added = T.success,
	modified = T.warning,
	renamed = T.accent,
	deleted = T.danger,
}

-- What a drag carries: the entry pressed, and with several chosen, each
-- of them (`items`, in the tree's order, none under another).
export type Item = { path: string, folder: boolean }
export type Payload = { kind: "file", path: string, name: string, folder: boolean, items: { Item }? }

-- What a drop holds: its entries.
function M.items(payload: Payload): { Item }
	return payload.items or { { path = payload.path, folder = payload.folder } }
end

local function parent_of(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or ""
end

-- Whether `path` can move into `folder` ("" the root; drag.rs
-- destination_path): not where it is, not into itself or below it.
function M.can_move(path: string, folder: string): boolean
	if folder == parent_of(path) or folder == path then
		return false
	end
	return string.sub(folder, 1, #path + 1) ~= path .. "/"
end

-- The chip a dragged entry is (WorkspacePathDragGhost): the first one's
-- icon, its name or "N items".
function M.ghost(name: string, folder: boolean?, count: number?): Node
	return ui.row {
		id = "tree_drag_ghost",
		h = 24,
		max_w = 220,
		px = "$zeron.space.8",
		gap = "$zeron.space.5",
		items = "center",
		rounded = "$zeron.radius.6",
		bg = T.raised,
		border = 1,
		border_color = T.strong,
		opacity = 0.85,
		file_icon.icon { path = name, folder = folder, size = 14 },
		txt.text {
			if count and count > 1 then `{count} items` else name,
			literal = true,
			size = "xs",
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
		},
	}
end

-- A drag over the tree: whether one is under way, and the folder that
-- would take it (nil where it would not).
type Drag = { on: State<boolean>, target: State<string?> }

-- What makes a node a drop target for folder `folder`: it takes files,
-- says where they would go, moves them there.
type Drop = {
	drop_when: ((payload: any) -> boolean)?,
	on_drag_over: ((payload: any, e: DragPoint) -> ())?,
	on_drag_leave: ((payload: any) -> ())?,
	on_drop: ((payload: any, e: DragPoint) -> ())?,
}
local function drop(props: Props, drag: Drag, folder: string): Drop
	-- The folder, while it takes one of the entries and none is a folder
	-- above it (drag.rs destination_paths: those already there are skipped).
	local function into(payload: any): string?
		if type(payload) ~= "table" or payload.kind ~= "file" then
			return nil
		end
		local any = false
		for _, it in M.items(payload) do
			if it.folder and (folder == it.path or string.sub(folder, 1, #it.path + 1) == it.path .. "/") then
				return nil
			end
			any = any or M.can_move(it.path, folder)
		end
		return if any then folder else nil
	end
	return {
		drop_when = function(payload: any): boolean
			return type(payload) == "table" and payload.kind == "file"
		end,
		on_drag_over = function(payload: any, _e: DragPoint)
			local to = into(payload)
			if drag.target:peek() ~= to then
				drag.target:set(to)
			end
		end,
		on_drag_leave = function(_payload: any)
			if drag.target:peek() ~= nil then
				drag.target:set(nil)
			end
		end,
		on_drop = function(payload: any, _e: DragPoint)
			drag.target:set(nil)
			local to = into(payload)
			if to and props.on_move then
				for _, it in M.items(payload) do
					if M.can_move(it.path, to) then
						props.on_move(it.path, to)
					end
				end
			end
		end,
	}
end

-- The chosen entries showing, in the tree's order, those under a chosen
-- folder left to it (model.rs selection_roots).
function M.roots(items: { Entry }, open: { string }, chosen: { string }): { Entry }
	local set: { [string]: boolean } = {}
	for _, id in chosen do
		set[id] = true
	end
	local out: { Entry } = {}
	local function walk(list: { Entry }, under: boolean)
		for _, e in list do
			local on = set[e.id] == true and e.status == nil
			if on and not under then
				table.insert(out, e)
			end
			if e.children and table.find(open, e.id) then
				walk(e.children, under or on)
			end
		end
	end
	walk(items, false)
	return out
end

-- What a press on `e` acts on (context_menu.rs tree_action_paths): the
-- chosen entries when it is one of them, else it alone.
local function acted(props: Props, e: Entry): { Entry }
	local selection = props.selection
	if selection and table.find(selection:peek(), e.id) then
		local roots = M.roots(props.items:peek(), props.open:peek(), selection:peek())
		if #roots > 0 then
			return roots
		end
	end
	return { e }
end

-- A flat list's entries nested, and the folders it shows open.
function M.nest(flat: { Flat }): ({ Entry }, { string })
	local roots: { Entry } = {}
	local open: { string } = {}
	-- The folder each depth's entries go in.
	local within: { { Entry } } = { roots }
	for _, f in flat do
		local entry: Entry = { id = f.id, label = f.name, folder = f.folder, git = f.git }
		local list = within[f.level + 1] or roots
		table.insert(list, entry)
		if f.folder then
			entry.children = {}
			within[f.level + 2] = entry.children
			if f.open then
				table.insert(open, f.id)
			end
		end
	end
	return roots, open
end

-- The entry's name, or the field renaming it.
local function name(e: Entry, props: Props, color: Color): Node
	local label = txt.text {
		e.label,
		literal = true,
		size = "xs",
		truncate = true,
		line = false,
		grow = 1,
		shrink = 1,
		min_w = 0,
		color = color,
	}
	local renaming = props.renaming
	if not renaming then
		return label
	end
	return ui.presence(function()
		return if renaming:get() == e.id then "field" else "label"
	end, function(what: string): Node
		if what == "label" then
			return label
		end
		local draft = ui.use_state(e.label)
		local done = false
		local function finish(keep: boolean)
			if done then
				return
			end
			local to = draft:peek()
			-- A name refused keeps the field, to be put right.
			if keep and props.on_rename and to ~= e.label and props.on_rename(e.id, to) == false then
				return
			end
			done = true
			renaming:set("")
		end
		return ui.input {
			id = props.id and `{props.id}_{e.id}_rename`,
			value = draft,
			label = `Rename {e.label}`,
			grow = 1,
			shrink = 1,
			min_w = 0,
			h = 20,
			px = "$zeron.space.4",
			py = 0,
			rounded = "$zeron.radius.4",
			bg = T.input,
			border = 1,
			border_color = T.accent,
			font = T.sans,
			text_size = "$font.size.xs",
			color = T.text,
			focus = { border = 1 },
			select_on_focus = true,
			on_mount = function(el: Element)
				el:focus()
			end,
			on_key = function(k: KeyEvent): boolean
				if k.key == "Enter" then
					finish(true)
					return true
				elseif k.key == "Escape" then
					finish(false)
					return true
				end
				return false
			end,
			on_blur = function()
				finish(false)
			end,
		}
	end, { grow = 1, shrink = 1, min_w = 0 })
end

-- A folder's status row, one level in (tree.rs status_row): "Empty
-- folder" faint, or "Load more…" at 10.5, washing under the pointer.
local function status(e: Entry, level: number, props: Props): Node
	local more = e.status == "more"
	local folder = string.match(e.id, "^(.*)/[^/]*$") or ""
	return ui.row {
		id = props.id and `{props.id}_{e.id}`,
		w_full = true,
		h = M.ROW,
		pl = ui.raw(M.BASE + (level - 1) * M.INDENT + 14 + 4, "past the entry's chevron"),
		pr = "$zeron.space.8",
		items = "center",
		cursor = if more then "pointer" else nil,
		bg = T.clear,
		hover = if more then { bg = T.ink1 } else nil,
		on_click = if more and props.on_more
			then function()
				(props.on_more :: (string) -> ())(folder)
			end
			else nil,
		txt.text {
			e.label,
			size = "xs",
			color = if more then T.secondary else T.tertiary,
			opacity = if more then 1 else 0.7,
			line = false,
		},
	}
end

-- A row of the tree: its guides, chevron, icon and name. `level` is 1 at
-- the roots.
local function row(e: Entry, level: number, props: Props, drag: Drag): Node
	if e.status then
		return status(e, level, props)
	end
	local selection = props.selection
	local function on(): boolean
		if selection then
			return table.find(selection:get(), e.id) ~= nil
		end
		return props.selected:get() == e.id
	end
	-- The keyboard's row once it is not the whole choice (tree.rs
	-- distinct_cursor; the focus is the variants').
	local function cursor(): boolean
		if not selection or props.selected:get() ~= e.id then
			return false
		end
		local chosen = selection:get()
		return #chosen > 1 or table.find(chosen, e.id) == nil
	end
	local depth = level - 1
	local guides: { Node } = {}
	for l = 1, depth do
		table.insert(
			guides,
			ui.div { absolute = true, top = 0, bottom = 0, left = 15 + (l - 1) * M.INDENT, w = 1, bg = T.border }
		)
	end
	local color: Color = GIT[e.git or ""] or T.secondary
	local on_open = props.on_open
	local chevron: Node? = nil
	if e.folder then
		local function shown(): boolean
			return table.find(props.open:get(), e.id) ~= nil
		end
		chevron = ui.show(
			shown,
			icon { name = "alt-arrow-down", size = 11, color = T.tertiary },
			icon { name = "alt-arrow-right", size = 11, color = T.tertiary }
		)
	end
	local moves = props.on_move ~= nil
	-- A folder's row takes what is dropped on it, a file's row for its
	-- folder (whose row washes).
	local target = if moves then drop(props, drag, if e.folder then e.id else parent_of(e.id)) else {} :: Drop
	local function landing(): boolean
		return drag.target:get() == e.id
	end
	return ui.row(wash.item("tree", {
		id = props.id and `{props.id}_{e.id}`,
		on_drag = if props.draggable or moves
			then function(): Payload
				drag.on:set(true)
				local items: { Item } = {}
				for _, a in acted(props, e) do
					table.insert(items, { path = a.id, folder = a.folder == true })
				end
				return {
					kind = "file",
					path = e.id,
					name = e.label,
					folder = e.folder == true,
					items = if #items > 1 then items else nil,
				}
			end
			else nil,
		drag_preview = function(): Node
			local all = acted(props, e)
			return M.ghost(all[1].label, all[1].folder, #all)
		end,
		on_drag_end = function()
			drag.on:set(false)
			drag.target:set(nil)
		end,
		drop_when = target.drop_when,
		on_drag_over = target.on_drag_over,
		on_drag_leave = target.on_drag_leave,
		on_drop = target.on_drop,
		-- A folder rested on opens.
		on_drag_spring = if moves and e.folder
			then function(): boolean
				if not table.find(props.open:peek(), e.id) then
					props.open:push(e.id)
				end
				return true
			end
			else nil,
		relative = true,
		w_full = true,
		h = M.ROW,
		pl = ui.raw(M.BASE + depth * M.INDENT, "the entry's depth"),
		pr = "$zeron.space.8",
		gap = "$zeron.space.4",
		items = "center",
		cursor = "pointer",
		variants = recipes.tree_row { selected = on },
		opacity = if e.git == "ignored" then 0.52 else 1,
		-- The tree chooses it and folds a folder as it is pressed.
		on_click = if not e.folder and on_open
			then function(keys: ClickEvent?)
				-- ⌘ or ⇧ chooses (several), it doesn't open.
				if keys and (keys.cmd or keys.shift) and selection then
					return
				end
				on_open(e)
			end
			else nil,
		context_menu = if props.menu
			then function()
				-- One of several chosen keeps them; another is chosen alone.
				local all = acted(props, e)
				if #all == 1 then
					props.selected:set(e.id)
				end
				local paths: { string } = {}
				for _, a in all do
					table.insert(paths, a.id)
				end
				return (props.menu :: (Entry, { string }) -> { Node })(e, paths)
			end
			else nil,
		guides,
		ui.div {
			absolute = true,
			top = 0,
			left = 0,
			right = 0,
			bottom = 0,
			-- Deeper while the tree has the focus.
			variants = recipes.tree_selection {
				selected = on,
				cursor = cursor,
				focused = if props.focused == nil then true else props.focused,
			},
		},
		-- Where a drag would land (built while one is under way).
		e.folder and moves and ui.show(
			drag.on,
			ui.div {
				absolute = true,
				top = 0,
				left = 0,
				right = 0,
				bottom = 0,
				bg = T.ink5,
				opacity = function(): number
					return if landing() then 1 else 0
				end,
			}
		) or nil,
		ui.row {
			w = 14,
			h = 14,
			items = "center",
			justify = "center",
			shrink = 0,
			chevron,
		},
		file_icon.icon { path = e.label, folder = e.folder, size = 14 },
		name(e, props, if e.git and GIT[e.git :: string] then color else "inherit"),
	}, on))
end

-- How many rows show: the roots, and what each open folder holds.
function M.shown(items: { Entry }, open: { string }): number
	local n = 0
	for _, e in items do
		n += 1
		if e.children and table.find(open, e.id) then
			n += M.shown(e.children, open)
		end
	end
	return n
end

-- The entry `id` among `items`, at any depth.
local function find(items: { Entry }, id: string): Entry?
	for _, e in items do
		if e.id == id then
			return e
		end
		local found = e.children and find(e.children, id)
		if found then
			return found
		end
	end
	return nil
end

M.tree = ui.component(function(props: Props): Node
	local on_open = props.on_open
	local drag: Drag = { on = ui.use_state(false), target = ui.use_state(nil :: string?) }
	local moves = props.on_move ~= nil
	local root = if moves then drop(props, drag, "") else {} :: Drop
	return wash.list {
		group = "tree",
		id = props.id,
		w = props.w,
		w_full = props.w == nil,
		h = if props.fit
			then function(): number
				return M.ROW * M.shown(props.items:get(), props.open:get()) + (if moves then 24 else 0)
			end
			else props.h,
		grow = if props.h == nil and not props.fit then 1 else nil,
		color = T.ink2,
		ui.column {
			grow = 1,
			w_full = true,
			min_h = 0,
			items = "stretch",
			-- Below the rows, the workspace root takes it.
			drop_when = root.drop_when,
			on_drag_over = root.on_drag_over,
			on_drag_leave = root.on_drag_leave,
			on_drop = root.on_drop,
			-- The root's own row (render_tree_root_target): 24 high, its
			-- words at 10.5 in the muted text, washed while a drag would
			-- land there.
			moves and ui.row {
				id = props.id and `{props.id}_root`,
				relative = true,
				w_full = true,
				h = 24,
				px = "$zeron.space.8",
				items = "center",
				shrink = 0,
				ui.show(
					drag.on,
					ui.div {
						absolute = true,
						top = 0,
						left = 0,
						right = 0,
						bottom = 0,
						bg = T.ink5,
						opacity = function(): number
							return if drag.target:get() == "" then 1 else 0
						end,
					}
				),
				ui.show(
					drag.on,
					txt.text { "Move to workspace root", size = "micro", color = T.secondary, line = false },
					txt.text { "Workspace root", size = "micro", color = T.secondary, line = false }
				),
			} or nil,
			ui.tree {
				label = "Files",
				grow = 1,
				w_full = true,
				min_h = 0,
				items = props.items,
				open = props.open,
				value = props.selected :: any,
				selection = props.selection,
				row_height = M.ROW,
				open_on_click = true,
				on_activate = if on_open
					then function(id: string)
						local e = find(props.items:peek(), id)
						if e and e.status == "more" and props.on_more then
							props.on_more(string.match(e.id, "^(.*)/[^/]*$") or "")
						elseif e and not e.folder and not e.status then
							on_open(e)
						end
					end
					else nil,
				row = function(e: Entry, level: number): Node
					return row(e, level, props, drag)
				end,
			},
		},
	}
end)

return M
