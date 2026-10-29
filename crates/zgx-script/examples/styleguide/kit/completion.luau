-- The composer's completion menus (composer.rs mention and slash popups on
-- popover.rs completion_card): after an @, the files; after a / or a $,
-- the commands and skills. One card the pill's width just above it (6
-- away), radius 12 with its 4 inset, at most 320 high; its rows 30 high,
-- 2 apart, at the concentric 7: a 16 icon, the label at 13 medium (the
-- typed run at full strength, the rest secondary) and the detail at 12
-- muted. The keyboard's row is lit as the pointer's wash is (no script on
-- hover); Up and Down move and wrap, Enter or Tab take the row, Escape
-- dismisses the menu until the token changes. It rises in over 140 ms
-- from 30% and 2 below, and goes at once. A long list builds only the rows
-- in view (`ui.list`), its edges fading where it runs on.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local file_icon = require("./file_icon")
local txt = require("./text")
local wash = require("./wash")
local recipes = require("./recipes")
local motion = require("./motion")
local frost = require("./frost")
local avatar = require("./avatar")

-- A row: what it shows and what the pick writes in the token's place.
export type Item = {
	id: string,
	label: string,
	detail: string?,
	icon: icon_mod.Name,
	-- A file's or folder's path: its own icon (kit/file_icon) for `icon`.
	path: string?,
	folder: boolean?,
	-- The typed run in `label` (byte positions), lit.
	match: { number }?,
	-- What replaces the token (the trigger and query); `label` unless set.
	insert: string?,
	kind: string?,
	-- A person's avatar (their name) in the icon's place, at 20.
	avatar: string?,
}
-- The token being completed: its trigger ("@", "/", "$") and what follows.
export type Token = { trigger: string, query: string }
-- What feeds the menu: the token in the draft now (tracked; nil without
-- one), the rows for a token, what a pick does, and what an empty list
-- says.
export type Source = {
	token: () -> Token?,
	results: (token: Token) -> { Item },
	on_pick: (item: Item, token: Token) -> (),
	empty: ((token: Token) -> string)?,
}
export type Menu = {
	-- Shown, over the pill (absolute: its parent is `relative`).
	view: Node,
	-- The composer's keys, while it is open: true when one was taken.
	on_key: (e: KeyEvent) -> boolean,
	open: () -> boolean,
}
export type Options = {
	id: string?,
	-- After a pick: the input takes the focus back.
	on_accept: (() -> ())?,
}

local M = {}

M.RADIUS = 12
M.INSET = frost.INSET
M.ROW = 30
M.GAP = 2
M.PITCH = M.ROW + M.GAP
M.MAX_LIST = 310
M.OFFSET = 6
M.ICON = 16
M.TRAVEL = 2
-- Rows at the card's concentric radius: 12, 4 in, inside its hairline.
M.ROW_RADIUS = T.inset_radius(M.RADIUS, M.INSET, 1)

-- Where `query` falls in `text`, case aside: 0 for a prefix, 1 inside,
-- nil if nowhere; and the byte run it covers.
function M.rank(text: string, query: string): (number?, number, number)
	if query == "" then
		return 0, 0, -1
	end
	local at = string.find(string.lower(text), string.lower(query), 1, true)
	if not at then
		return nil, 0, -1
	end
	return if at == 1 then 0 else 1, at, at + #query - 1
end

-- `items` that match `query` on their label (or `also`, a second field
-- such as a path, ranked after), prefixes first, each rank in its order.
function M.filter(items: { Item }, query: string, also: ((item: Item) -> string)?): { Item }
	type Ranked = { rank: number, at: number, item: Item }
	local ranked: { Ranked } = {}
	for i, item in items do
		local rank, from, to = M.rank(item.label, query)
		local found = table.clone(item)
		if rank then
			found.match = if to >= from then { from, to } else nil
		elseif also then
			local r = M.rank(also(item), query)
			rank = if r then r + 2 else nil
		end
		if rank then
			table.insert(ranked, { rank = rank, at = i, item = found })
		end
	end
	-- Stable: each rank in its order.
	ui.sort(ranked, function(r: Ranked): number
		return r.rank
	end)
	local out: { Item } = {}
	for _, r in ranked do
		table.insert(out, r.item)
	end
	return out
end

-- The label with its typed run lit.
local function label(item: Item): Node
	local m = item.match
	if not m then
		return txt.text {
			item.label,
			size = "md",
			weight = "medium",
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
		}
	end
	return ui.rich {
		shrink = 1,
		min_w = 0,
		truncate = true,
		text_size = "$font.size.md",
		weight = "$font.weight.medium",
		color = T.secondary,
		string.sub(item.label, 1, m[1] - 1),
		ui.span { string.sub(item.label, m[1], m[2]), color = T.text },
		string.sub(item.label, m[2] + 1),
	}
end

local function row(item: Item, selected: () -> boolean, group: string, id: string?, on_click: () -> ()): Node
	return ui.row(wash.item(group, {
		id = id and `{id}_ref_{item.id}`,
		w_full = true,
		h = M.ROW,
		px = "$zeron.space.8",
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.radius(M.ROW_RADIUS),
		cursor = "pointer",
		variants = recipes.completion_row { selected = selected },
		on_click = on_click,
		if item.avatar
			then avatar.avatar { name = item.avatar, size = 20 }
			else ui.row {
				w = M.ICON,
				h = M.ICON,
				shrink = 0,
				items = "center",
				justify = "center",
				if item.path
					then file_icon.icon { path = item.path, folder = item.folder, size = M.ICON }
					else icon { name = item.icon, size = M.ICON, color = T.secondary },
			},
		label(item),
		item.detail and txt.text {
			item.detail,
			size = "sm",
			color = T.tertiary,
			truncate = true,
			line = false,
			grow = 1,
			shrink = 1,
			min_w = 0,
		},
	}, selected))
end

-- The card around rows `items` (or what an empty list says), the
-- keyboard's on `sel`.
local function card(
	items: { Item },
	sel: State<number>,
	offset: State<number>,
	empty: string,
	id: string?,
	pick: (i: number) -> ()
): Node
	local group = wash.group("completions")
	local content: Node
	if #items == 0 then
		content = ui.row {
			id = id and `{id}_ref_empty`,
			w_full = true,
			px = "$zeron.space.12",
			py = "$zeron.space.10",
			txt.text { empty, size = "sm", color = T.secondary, line = false },
		}
	else
		content = wash.list {
			group = group,
			color = T.menu_hover,
			ui.list {
				id = id and `{id}_ref_list`,
				label = "Suggestions",
				w_full = true,
				h = math.min(#items * M.PITCH - M.GAP, M.MAX_LIST),
				count = #items,
				height = M.PITCH,
				offset = offset,
				fade = { 12, 12 },
				fade_overflow = true,
				row = function(i: number): Node
					local item = items[i]
					return ui.column {
						w_full = true,
						h = M.PITCH,
						pb = T.space(M.GAP),
						row(
							item,
							function()
								return sel:get() == i
							end,
							group,
							id,
							function()
								pick(i)
							end
						),
					}
				end,
			},
		}
	end
	return ui.column {
		absolute = true,
		left = 0,
		right = 0,
		bottom = "100%",
		pb = T.space(M.OFFSET),
		frost.card {
			id = if id then `{id}_references` else "reference_picker",
			w_full = true,
			radius = T.radius_card,
			p = T.space(M.INSET),
			on_mount = function(el: Element)
				anime.animate(el, {
					opacity = { 0.3, 1 },
					y = { M.TRAVEL, 0 },
					duration = motion.d(motion.MENU_IN),
					ease = motion.EASE,
				})
			end,
			content,
		},
	}
end

-- What a token's empty list says (composer.rs).
local function says(token: Token): string
	if token.trigger == "@" then
		return if token.query == "" then "No files available" else "No matching files"
	elseif token.trigger == "$" then
		return if token.query == "" then "No skills available for this project" else "No matching skills"
	end
	return if token.query == "" then "No commands or skills available" else "No matching commands or skills"
end

local function key_of(token: Token?): string
	return if token then `{token.trigger}{token.query}` else ""
end

-- A live menu over a composer: it follows `source.token()` as the draft
-- changes, and takes the composer's keys while open.
function M.menu(source: Source, opts: Options?): Menu
	local o: Options = opts or {}
	local items = ui.use_state({} :: { Item })
	local sel = ui.use_state(1)
	local offset = ui.use_state(0)
	-- A new list each time the token changes: the rows are built for it.
	local generation = ui.use_state(0)
	local dismissed = ui.use_state("")
	local current = ui.computed(function()
		return key_of(source.token())
	end)
	local function shown(): boolean
		local k = current:get()
		return k ~= "" and k ~= dismissed:get()
	end
	ui.effect(function()
		local token = source.token()
		if token == nil then
			if #items:peek() > 0 then
				items:set {}
			end
			return
		end
		items:set(source.results(token))
		sel:set(1)
		offset:set(0)
		generation:set(generation:peek() + 1)
	end)
	local function pick(i: number)
		local token = source.token()
		local item = items:peek()[i]
		if token and item then
			source.on_pick(item, token)
			if o.on_accept then
				o.on_accept()
			end
		end
	end
	-- The keyboard's row stays in view as it moves.
	local function reveal(i: number)
		local top = (i - 1) * M.PITCH
		local view = math.min(#items:peek() * M.PITCH - M.GAP, M.MAX_LIST)
		if top < offset:peek() then
			offset:set(top)
		elseif top + M.ROW > offset:peek() + view then
			offset:set(top + M.ROW - view)
		end
	end
	local function on_key(e: KeyEvent): boolean
		local k = current:peek()
		if k == "" or k == dismissed:peek() then
			return false
		end
		if e.key == "Escape" then
			dismissed:set(k)
			return true
		end
		local n = #items:peek()
		if n == 0 then
			return false
		end
		if e.key == "ArrowDown" or e.key == "ArrowUp" then
			local step = if e.key == "ArrowDown" then 1 else -1
			local i = (sel:peek() - 1 + step) % n + 1
			sel:set(i)
			reveal(i)
			return true
		end
		if (e.key == "Enter" and not e.shift) or (e.key == "Tab" and not e.shift) then
			pick(sel:peek())
			return true
		end
		return false
	end
	local view = ui.presence(function()
		return if shown() then "open" else nil
	end, function(): Node
		-- The rows, built again for each new list (not on each move).
		return ui.presence(function()
			return tostring(generation:get())
		end, function(): Node
			local token = source.token()
			local empty = if token then (source.empty or says)(token) else ""
			return card(items:peek(), sel, offset, empty, o.id, pick)
		end)
	end)
	return {
		view = view,
		on_key = on_key,
		open = shown,
	}
end

-- A menu held open with `items` (a specimen): the first row the keyboard's.
function M.preview(props: { id: string?, token: Token, items: { Item } }): Node
	local sel = ui.use_state(1)
	local offset = ui.use_state(0)
	local items = M.filter(props.items, props.token.query)
	return card(items, sel, offset, says(props.token), props.id, function() end)
end

return M
