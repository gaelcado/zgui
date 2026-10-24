-- The files tree (files/tree.rs): rows 27 high, 14 of indent per level
-- from 8, 1-point guides at each level, an 11-point chevron in a 14 slot
-- for folders, a 14 icon and the name at 11.5. Git status colours the
-- name; selection is wash 12% (8% unfocused), hover 5.5%. A secondary
-- click shows the entry's menu (`menu`); an entry being renamed shows its
-- name in a field in place (files/rename.rs): Enter keeps it, Escape or
-- leaving it drops it.
local T = require("../theme")
local recipes = require("./recipes")
local wash = require("./wash")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")

export type Git = "added" | "modified" | "renamed" | "deleted" | "ignored" | nil
export type Entry = {
	id: string,
	name: string,
	level: number,
	folder: boolean?,
	open: boolean?,
	icon: icon_mod.Name?,
	git: Git,
}
export type Props = {
	id: string?,
	entries: { Entry },
	selected: State<string>,
	focused: types.Cond?,
	on_toggle: ((id: string) -> ())?,
	-- A file chosen (a click on it).
	on_open: ((e: Entry) -> ())?,
	-- The entry's context menu: its `ui.menu_item`s.
	menu: ((e: Entry) -> { Node })?,
	-- The entry being renamed (its id; "" for none), and what renaming it
	-- to a name does.
	renaming: State<string>?,
	on_rename: ((id: string, name: string) -> ())?,
	w: Length?,
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

-- The entry's name, or the field renaming it.
local function name(e: Entry, props: Props, color: Color): Node
	local label = txt.text {
		e.name,
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
		local draft = ui.use_state(e.name)
		local done = false
		local function finish(keep: boolean)
			if done then
				return
			end
			done = true
			local to = draft:peek()
			if keep and props.on_rename and to ~= "" and to ~= e.name then
				props.on_rename(e.id, to)
			end
			renaming:set("")
		end
		return ui.input {
			id = props.id and `{props.id}_{e.id}_rename`,
			value = draft,
			label = `Rename {e.name}`,
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

local function row(e: Entry, props: Props, group: string): Node
	local function on(): boolean
		return props.selected:get() == e.id
	end
	local guides: { Node } = {}
	for level = 1, e.level do
		table.insert(
			guides,
			ui.div { absolute = true, top = 0, bottom = 0, left = 15 + (level - 1) * M.INDENT, w = 1, bg = T.border }
		)
	end
	local color: Color = GIT[e.git or ""] or T.secondary
	return ui.button(wash.item(group, {
		id = props.id and `{props.id}_{e.id}`,
		relative = true,
		w_full = true,
		h = M.ROW,
		pl = ui.raw(M.BASE + e.level * M.INDENT, "the entry's depth"),
		pr = "$zeron.space.8",
		gap = "$zeron.space.4",
		items = "center",
		cursor = "pointer",
		focus = { border = 0 },
		variants = recipes.tree_row { selected = on },
		opacity = if e.git == "ignored" then 0.52 else 1,
		on_click = function()
			props.selected:set(e.id)
			if e.folder and props.on_toggle then
				props.on_toggle(e.id)
			elseif not e.folder and props.on_open then
				props.on_open(e)
			end
		end,
		context_menu = if props.menu
			then function()
				props.selected:set(e.id)
				return (props.menu :: (Entry) -> { Node })(e)
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
				focused = if props.focused == nil then true else props.focused,
			},
		},
		ui.row {
			w = 14,
			h = 14,
			items = "center",
			justify = "center",
			shrink = 0,
			e.folder and icon {
				name = if e.open then "alt-arrow-down" else "alt-arrow-right",
				size = 11,
				color = T.tertiary,
			},
		},
		icon {
			name = e.icon or (if e.folder then "folder" else "document"),
			size = 14,
			color = if e.folder then T.secondary else color,
		},
		name(e, props, if e.git and GIT[e.git :: string] then color else "inherit"),
	}, on))
end

M.tree = ui.component(function(props: Props): Node
	local group = wash.group("tree")
	local rows: { Node } = {}
	for _, e in props.entries do
		table.insert(rows, row(e, props, group))
	end
	return wash.list { group = group, id = props.id, w = props.w, w_full = props.w == nil, color = T.ink2, rows }
end)

return M
