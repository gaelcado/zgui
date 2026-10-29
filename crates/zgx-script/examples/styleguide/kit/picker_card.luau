-- The new-session canvas's pickers (pickers.rs: the project, device, ref
-- and checkout popovers): a frosted card under its chip, a search row
-- ("Search projects…", "Search devices…", "Search refs…") over rows 32 at
-- radius 7 (the chosen one on the selected wash with its ring), a muted tag
-- at a row's end ("current", "worktree"), Zeron's empty words, a pinned row
-- above the list ("Don't work in a project") and one under a hairline (New
-- project), a capped list's "Showing X of Y refs". Up and Down move
-- through the rows, Enter takes one, Escape closes.
local T = require("../theme")
local txt = require("./text")
local icon_mod = require("./icon")
local icon = require("./icon")
local frost = require("./frost")
local popover = require("./popover")
local recipes = require("./recipes")
local project_picker = require("./project_picker")

export type Row = {
	-- What a pick sets, and the row's id (`<rows>_<key>`, made safe).
	key: string,
	label: string,
	icon: icon_mod.Name?,
	-- A project's art in the icon's slot.
	project: string?,
	-- Muted at the row's end.
	tag: string?,
}
export type Props = {
	id: string,
	open: State<boolean>,
	anchor: Node,
	-- No search row: a short fixed list (the checkout's two).
	search: string?,
	rows: () -> { Row },
	value: () -> string,
	on_pick: (key: string) -> (),
	-- Above the list, and under it past a hairline.
	top: Row?,
	bottom: Row?,
	-- What an empty list says, given the query.
	empty: ((query: string) -> string)?,
	-- At most this many rows, then the footer says how many there are.
	cap: number?,
	noun: string?,
	w: number?,
}

local M = {}

M.ROW = 32
M.LIST_MAX = 224

local function safe(key: string): string
	return (string.gsub(string.lower(key), "[^%w]+", "_"))
end

M.card = ui.component(function(props: Props): Node
	local id = props.id
	local function content(): Node
		local query = ui.use_state("")
		local active = ui.use_state(1)
		ui.effect(function()
			query:get()
			active:set(1)
		end)
		local function close()
			props.open:set(false)
		end
		-- What the list holds now, its total before the cap.
		local function rows(): ({ Row }, number)
			local q = query:get()
			local out: { Row } = {}
			local total = 0
			for _, r in props.rows() do
				if project_picker.matches(r.label, q) then
					total += 1
					if #out < (props.cap or math.huge) then
						table.insert(out, r)
					end
				end
			end
			return out, total
		end
		-- Every row the keys move through, in order.
		local function all(): { Row }
			local list = table.clone((rows()))
			if props.top then
				table.insert(list, 1, props.top)
			end
			if props.bottom then
				table.insert(list, props.bottom)
			end
			return list
		end
		local function choose(r: Row)
			close()
			props.on_pick(r.key)
		end
		local function row(r: Row, index: number): Node
			local function selected(): boolean
				return props.value() == r.key
			end
			return ui.button {
				id = `{id}_{safe(r.key)}`,
				label = r.label,
				w_full = true,
				min_h = M.ROW,
				shrink = 0,
				px = "$zeron.space.8",
				py = 0,
				gap = "$zeron.space.8",
				items = "center",
				rounded = T.radius_item,
				variants = recipes.picker_choice {
					selected = selected,
					-- The last row (index 0) is wherever the list ends.
					keyed = function()
						return active:get() == (if index == 0 then #all() else index)
					end,
				},
				color = T.text,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					choose(r)
				end,
				ui.row {
					w = 16,
					h = 16,
					shrink = 0,
					items = "center",
					justify = "center",
					if r.project
						then require("./project_icon").icon { name = r.project, size = 16, lit = selected }
						else icon { name = r.icon or "folder", size = 12, color = T.secondary },
				},
				txt.text {
					r.label,
					literal = true,
					size = "md",
					color = "inherit",
					line = false,
					truncate = true,
					grow = 1,
					shrink = 1,
					min_w = 0,
				},
				r.tag and txt.text { r.tag, size = "micro", color = T.tertiary, opacity = 0.6, line = false },
			}
		end
		local function on_key(e: KeyEvent): boolean
			local list = all()
			if e.key == "ArrowDown" or e.key == "ArrowUp" then
				local by = if e.key == "ArrowDown" then 1 else -1
				active:set((active:peek() - 1 + by) % math.max(#list, 1) + 1)
				return true
			elseif e.key == "Enter" then
				local r = list[active:peek()]
				if r then
					choose(r)
				end
				return true
			elseif e.key == "Escape" then
				close()
				return true
			end
			return false
		end
		local offset = if props.top then 1 else 0
		return ui.column {
			w_full = true,
			gap = "$zeron.space.2",
			on_key = on_key,
			props.search and ui.row {
				h = 40,
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
					placeholder = props.search,
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
			props.top and row(props.top, 1),
			ui.presence(function(): string
				local list, total = rows()
				local keys = { tostring(total) }
				for _, r in list do
					table.insert(keys, r.key)
				end
				return table.concat(keys, "\n")
			end, function(): Node
				local list, total = rows()
				if #list == 0 then
					return ui.row {
						w_full = true,
						p = "$zeron.space.8",
						txt.text {
							if props.empty then props.empty(query:peek()) else "Nothing matches.",
							id = `{id}_empty`,
							size = "sm",
							color = T.tertiary,
						},
					}
				end
				local built: { Node } = {}
				for i, r in list do
					table.insert(built, row(r, i + offset))
				end
				return ui.column {
					w_full = true,
					gap = "$zeron.space.2",
					ui.scroll {
						w_full = true,
						max_h = M.LIST_MAX,
						gap = "$zeron.space.2",
						fade = { 12, 12 },
						fade_overflow = true,
						built,
					},
					total > #list and ui.column {
						w_full = true,
						pt = "$zeron.space.2",
						ui.div { h = 1, w_full = true, mx = T.pull(4), bg = T.hairline },
						ui.row {
							px = "$zeron.space.8",
							pt = "$zeron.space.4",
							txt.text {
								`Showing {#list} of {total} {props.noun or "rows"}`,
								id = `{id}_capped`,
								size = "xs",
								color = T.tertiary,
							},
						},
					},
				}
			end, { w_full = true }),
			props.bottom and ui.div { h = 1, shrink = 0, my = "$zeron.space.2", mx = T.pull(4), bg = T.hairline },
			props.bottom and row(props.bottom, 0),
		}
	end
	return ui.popover {
		id = id,
		open = props.open,
		anchor = props.anchor,
		w = props.w or 260,
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
		enter = popover.enter(nil, 4),
		exit = popover.exit(nil, 4),
		ui.presence(function(): boolean?
			return if props.open:get() then true else nil
		end, content, { w_full = true }),
	}
end)

return M
