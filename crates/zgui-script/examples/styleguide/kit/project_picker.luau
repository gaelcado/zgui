-- The sidebar's space switcher (shell/spaces.rs render_spaces_trigger,
-- render_spaces_menu): the trigger filling the sidebar's top row (29, 8 in,
-- the project's 16 art then its name at 13 medium fading at its end), and
-- under it a picker card as wide: a search row (40, the magnifier 14, a
-- hairline under it), "All projects" (while nothing is typed) and the
-- projects the query matches (rows 32, 8 in, radius 7; the chosen one on
-- the selected wash with its ring, no check), at most 224 before they
-- scroll; a full-bleed hairline, then "New project" pinned under them. Up
-- and Down move through every row (the footer last), Enter takes one,
-- Escape closes. A project's secondary click renames or removes it.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local frost = require("./frost")
local popover = require("./popover")
local recipes = require("./recipes")
local project_icon = require("./project_icon")

export type Props = {
	id: string?,
	open: State<boolean>,
	-- What opens it (`M.trigger`): the card opens under it, from its start.
	anchor: Node,
	-- Its rows' ids: `<rows>_<project>`, `<rows>_all`, `<rows>_new` (the
	-- picker's id unless set).
	rows: string?,
	-- The projects, in order, and the one the sidebar keeps ("" for all).
	projects: () -> { string },
	value: State<string>,
	-- The card's width (the sidebar's less its gutters).
	w: (() -> number)?,
	-- A project's name as shown.
	label: ((name: string) -> string)?,
	on_new: (() -> ())?,
	-- A project's secondary click: Rename…, Remove….
	on_rename: ((name: string) -> ())?,
	on_remove: ((name: string) -> ())?,
}

local M = {}

M.ROW = 32
M.SEARCH = 40
M.LIST_MAX = 224

-- Whether `query`'s letters come in `name` in order (a fuzzy match).
function M.matches(name: string, query: string): boolean
	local at = 1
	local hay = string.lower(name)
	for c in string.gmatch(string.lower(query), "[^%s]") do
		local found = string.find(hay, c, at, true)
		if not found then
			return false
		end
		at = found + 1
	end
	return true
end

-- The trigger: what the sidebar keeps, its art in a 16 slot.
function M.trigger(
	props: { id: string?, value: State<string>, open: State<boolean>, label: ((name: string) -> string)? }
): Node
	local function label(name: string): string
		return if props.label then props.label(name) else name
	end
	return ui.button {
		id = props.id,
		w_full = true,
		h = 29,
		px = "$zeron.space.8",
		gap = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.8",
		variants = recipes.side_control { on = props.open },
		cursor = "pointer",
		focus = { border = 0 },
		on_click = ui.toggle(props.open),
		ui.presence(props.value, function(f: string): Node
			if f == "" then
				return icon { name = "folder", size = 16, color = T.secondary }
			end
			return project_icon.icon { name = f, size = 16 }
		end, { w = 16, h = 16, shrink = 0, items = "center", justify = "center" }),
		-- The name fades over its last 20 as it runs long.
		ui.row {
			grow = 1,
			shrink = 1,
			min_w = 0,
			overflow = "hidden",
			fade_x = { 0, 20 },
			fade_overflow = true,
			txt.text {
				function()
					local f = props.value:get()
					return if f == "" then "All projects" else label(f)
				end,
				size = "md",
				weight = "medium",
				color = "inherit",
				line = false,
				shrink = 0,
			},
		},
	}
end

M.picker = ui.component(function(props: Props): Node
	local id = props.id or "projects"
	local rows_id = props.rows or id
	-- What it shows, built as it opens (and its search afresh).
	local function content(): Node
		local query = ui.use_state("")
		-- The keyboard's row, from 1 (the footer is the last): back to the
		-- first as the query changes.
		local active = ui.use_state(1)
		ui.effect(function()
			query:get()
			active:set(1)
		end)
		local function label(name: string): string
			return if props.label then props.label(name) else name
		end
		local function close()
			props.open:set(false)
		end
		-- What the list holds now: "" for All projects, then the projects.
		local function rows(): { string }
			local q = query:get()
			local out: { string } = {}
			if q == "" then
				table.insert(out, "")
			end
			for _, p in props.projects() do
				if M.matches(label(p), q) then
					table.insert(out, p)
				end
			end
			return out
		end
		local function choose(name: string)
			props.value:set(name)
			close()
		end
		local function new()
			close()
			if props.on_new then
				props.on_new()
			end
		end
		local function row(name: string, index: number): Node
			local function selected(): boolean
				return props.value:get() == name
			end
			return ui.button {
				id = `{rows_id}_{if name == "" then "all" else name}`,
				w_full = true,
				min_h = M.ROW,
				px = "$zeron.space.8",
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius_item,
				variants = recipes.picker_choice {
					selected = selected,
					keyed = function()
						return active:get() == index
					end,
				},
				color = T.text,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					choose(name)
				end,
				context_menu = if name ~= "" and (props.on_rename or props.on_remove)
					then function()
						return {
							ui.menu_item {
								id = `{rows_id}_{name}_rename`,
								label = "Rename…",
								ui.row {
									gap = "$zeron.space.10",
									items = "center",
									icon { name = "pen", size = 16, color = T.secondary },
									txt.text { "Rename…", size = "md", color = "inherit", line = false },
								},
								on_click = function()
									close()
									if props.on_rename then
										props.on_rename(name)
									end
								end,
							},
							ui.div { h = 1, my = "$zeron.space.4", bg = T.hairline },
							ui.menu_item {
								id = `{rows_id}_{name}_remove`,
								label = "Remove…",
								ui.row {
									gap = "$zeron.space.10",
									items = "center",
									icon { name = "trash-bin-minimalistic", size = 16, color = T.danger },
									txt.text { "Remove…", size = "md", color = T.danger, line = false },
								},
								on_click = function()
									close()
									if props.on_remove then
										props.on_remove(name)
									end
								end,
							},
						}
					end
					else nil,
				ui.row {
					w = 16,
					h = 16,
					shrink = 0,
					items = "center",
					justify = "center",
					if name == ""
						then icon { name = "folder", size = 14, color = T.secondary }
						else project_icon.icon { name = name, size = 16, lit = selected },
				},
				txt.text {
					if name == "" then "All projects" else label(name),
					literal = true,
					size = "md",
					color = "inherit",
					line = false,
					truncate = true,
					grow = 1,
					shrink = 1,
					min_w = 0,
				},
			}
		end
		local function on_key(e: KeyEvent): boolean
			local list = rows()
			local n = #list + 1
			if e.key == "ArrowDown" or e.key == "ArrowUp" then
				local by = if e.key == "ArrowDown" then 1 else -1
				active:set((active:peek() - 1 + by) % n + 1)
				return true
			elseif e.key == "Enter" then
				local at = active:peek()
				if at > #list then
					new()
				else
					choose(list[at])
				end
				return true
			elseif e.key == "Escape" then
				close()
				return true
			end
			return false
		end
		return ui.column {
			w_full = true,
			gap = "$zeron.space.2",
			-- The search row, bleeding to the card's edges.
			ui.row {
				h = M.SEARCH,
				w_full = true,
				shrink = 0,
				mx = T.pull(4),
				mt = T.pull(4),
				mb = T.space(frost.INSET),
				px = "$zeron.space.10",
				gap = "$zeron.space.8",
				items = "center",
				border = 1,
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				icon { name = "magnifer", size = 14, color = T.secondary },
				ui.input {
					id = `{id}_search`,
					value = query,
					placeholder = "Search projects…",
					grow = 1,
					min_w = 0,
					p = 0,
					border = 0,
					rounded = 0,
					bg = T.clear,
					focus = { border = 0, bg = T.clear },
					text_size = "$font.size.md",
					on_mount = function(el: Element)
						el:focus()
					end,
					on_key = on_key,
				},
			},
			ui.scroll {
				w_full = true,
				max_h = M.LIST_MAX,
				gap = "$zeron.space.2",
				fade = { 12, 12 },
				fade_overflow = true,
				ui.presence(function(): string
					return table.concat(rows(), "\n")
				end, function(): Node
					local list = rows()
					local built: { Node } = {}
					for i, name in list do
						table.insert(built, row(name, i))
					end
					return ui.column { w_full = true, gap = "$zeron.space.2", built }
				end, { w_full = true }),
			},
			-- A full-bleed hairline, then New project, pinned.
			ui.div { h = 1, shrink = 0, my = "$zeron.space.2", mx = T.pull(4), bg = T.hairline },
			ui.button {
				id = `{rows_id}_new`,
				w_full = true,
				min_h = M.ROW,
				px = "$zeron.space.8",
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius_item,
				variants = recipes.picker_choice {
					keyed = function()
						return active:get() == #rows() + 1
					end,
				},
				color = T.text,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = new,
				ui.row {
					w = 16,
					h = 16,
					shrink = 0,
					items = "center",
					justify = "center",
					icon { name = "plus", size = 12, color = T.secondary },
				},
				txt.text { "New project", size = "md", color = "inherit", line = false, grow = 1 },
			},
		}
	end
	return ui.popover {
		id = id,
		open = props.open,
		label = "Projects",
		anchor = props.anchor,
		w = function(): number
			return if props.w then props.w() else 240
		end :: any,
		p = T.space(frost.INSET),
		gap = "$zeron.space.2",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		placement = { side = "bottom", align = "start", offset = 6 },
		-- Each opening drops in 2 (anchored_menu_below), leaving by 1.
		enter = popover.enter(nil, 2),
		exit = popover.exit(nil, 2),
		ui.presence(function(): boolean?
			return if props.open:get() then true else nil
		end, content, { w_full = true }),
	}
end)

return M
