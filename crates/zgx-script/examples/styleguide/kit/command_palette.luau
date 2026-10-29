-- ⌘K, as Zeron draws it (shell/command_palette.rs): a 560 frosted card at
-- radius 16 over the window; a 44-high search row with its own hint; tabs
-- (All, Threads, Commands, Files: ⌘1 to ⌘4, Tab steps); one-line rows 30
-- high in sections under quiet headers with a hairline between them, each
-- an icon, the label, the detail, and its shortcut; a footer of key hints.
-- With nothing typed, All lists Recent Files, Quick Actions and Recent
-- Threads; typed, Threads, Commands, Files and In Files.
-- ↑ ↓ move, ↵ opens, Esc closes. The app gives it what it lists.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local kbd = require("./kbd")
local motion = require("./motion")
local recipes = require("./recipes")

export type Tab = "all" | "threads" | "commands" | "files"
export type Row = {
	id: string,
	section: string,
	label: string,
	-- Muted text after the label (a thread's project, a file's folder).
	detail: string?,
	icon: string,
	-- A file's path: its own icon (kit/file_icon) for `icon`.
	file: string?,
	tint: Color?,
	keys: { string }?,
	run: () -> (),
	-- A thread's searchable fields, each with its weight (thread_search.rs:
	-- the title 100, the project 40, the branch 30, the device 20, the pull
	-- request 20); whether it is archived (it scores half, and is not
	-- recent); minutes since it last spoke (ties, and Recent Threads).
	fields: { { text: string, weight: number } }?,
	archived: boolean?,
	recency: number?,
	-- A command listed only while this holds (Archive thread, with a
	-- thread to archive), and one of the Quick Actions All shows first.
	shown: (() -> boolean)?,
	quick: boolean?,
	-- A match in a file's text: `label` is its line, the match at bytes
	-- `lit[1]` to `lit[2]`; `detail` is "path:line".
	lit: { number }?,
}
-- A file whose text the palette searches ("In Files"), and what opening a
-- match does (its line, from 1).
export type Content = {
	path: string,
	text: string,
	icon: string?,
	open: (line: number) -> (),
}
export type Options = {
	query: State<string>,
	commands: { Row },
	threads: { Row },
	-- The workspace's files, or what lists them as it is now.
	files: { Row } | () -> { Row },
	-- With nothing typed: the files opened here, then those recently
	-- changed; and the thread on show, left out of Recent Threads.
	recent_files: (() -> { Row })?,
	current_thread: (() -> string?)?,
	-- The workspace's files, searched for what is typed.
	contents: { Content }?,
	-- Closing it (Esc, a click outside, a row chosen).
	on_close: (() -> ())?,
	-- Its field takes the focus as it opens (not in a specimen).
	autofocus: boolean?,
}
export type Palette = Options & {
	tab: State<Tab>,
	active: State<number>,
}

local M = {}

local TABS: { { id: Tab, label: string } } = {
	{ id = "all", label = "All" },
	{ id = "threads", label = "Threads" },
	{ id = "commands", label = "Commands" },
	{ id = "files", label = "Files" },
}
-- In All, each section shows this many rows; Threads and Files more.
local ALL_LIMIT = 5
local THREADS_LIMIT = 50
local FILES_LIMIT = 50
-- In Files (command_palette.rs): matches in the files' text once two
-- characters are typed, at most three a file, 100 under Files.
local CONTENT_MIN = 2
local CONTENT_PER_FILE = 3
local CONTENT_LIMIT = 100

-- A palette over `options`, its tab and highlight named under `id`.
function M.new(id: string, options: Options): Palette
	local p = table.clone(options) :: any
	p.tab = ui.state(`{id}_tab`, "all" :: Tab)
	p.active = ui.state(`{id}_active`, 1)
	-- Typing moves the highlight back to the first result.
	ui.effect(function()
		options.query:get()
		p.active:set(1)
	end)
	return p :: Palette
end

-- The query's words, lowercased.
local function words(q: string): { string }
	local out: { string } = {}
	for w in string.gmatch(string.lower(q), "%S+") do
		table.insert(out, w)
	end
	return out
end

-- Every word in the label or the detail (all-words substring matching).
local function matches(r: Row, ws: { string }): boolean
	local label = string.lower(r.label)
	local detail = if r.detail then string.lower(r.detail) else ""
	for _, w in ws do
		if not string.find(label, w, 1, true) and not string.find(detail, w, 1, true) then
			return false
		end
	end
	return true
end

-- A thread's score for the words (thread_search.rs), or nil when a word
-- matches none of its fields: each word counts its best field, that
-- field's weight, half again where the word starts a word of it; an
-- archived thread scores half.
function M.score(r: Row, ws: { string }): number?
	local fields = r.fields or { { text = r.label, weight = 100 } }
	local total = 0
	for _, w in ws do
		local best = 0
		for _, f in fields do
			local text = string.lower(f.text)
			local at = 1
			while true do
				local i = string.find(text, w, at, true)
				if not i then
					break
				end
				local starts = i == 1 or not string.find(string.sub(text, i - 1, i - 1), "%w")
				best = math.max(best, if starts then f.weight * 1.5 else f.weight)
				if starts then
					break
				end
				at = i + 1
			end
		end
		if best == 0 then
			return nil
		end
		total += best
	end
	return if r.archived then total / 2 else total
end

-- Threads for the words: ranked by score, then by recency; with none
-- typed, the recent ones (unarchived, newest first, the one on show aside).
local function threads_for(list: { Row }, ws: { string }, current: string?): { Row }
	type Scored = { row: Row, score: number, at: number }
	local scored: { Scored } = {}
	for i, r in list do
		if #ws == 0 then
			if not r.archived and r.id ~= current then
				table.insert(scored, { row = r, score = 0, at = i })
			end
		else
			local score = M.score(r, ws)
			if score then
				table.insert(scored, { row = r, score = score, at = i })
			end
		end
	end
	-- Stable sorts, the last the first key: by score, ties the most recent
	-- first (none last), then as listed.
	ui.sort(scored, function(s: Scored): number?
		return s.row.recency
	end)
	ui.sort(scored, function(s: Scored): number
		return s.score
	end, true)
	local out: { Row } = {}
	for _, s in scored do
		table.insert(out, s.row)
	end
	return out
end

-- The lines of `contents` holding what is typed (as typed, any case),
-- in the files' order, each line from its first non-blank character.
function M.content_matches(contents: { Content }, query: string, limit: number): { Row }
	local q = string.lower(string.match(query, "^%s*(.-)%s*$") or "")
	local out: { Row } = {}
	if (utf8.len(q) or #q) < CONTENT_MIN then
		return out
	end
	for _, c in contents do
		local n, found = 0, 0
		for line in string.gmatch(c.text .. "\n", "([^\n]*)\n") do
			n += 1
			local lead = #(string.match(line, "^%s*") or "")
			local shown = string.sub(line, lead + 1)
			local at = string.find(string.lower(shown), q, 1, true)
			if at then
				local number = n
				table.insert(out, {
					id = `content_{string.gsub(c.path, "[^%w]", "_")}_{number}`,
					section = "In Files",
					label = shown,
					detail = `{c.path}:{number}`,
					icon = c.icon or "document",
					lit = { at, at + #q - 1 },
					run = function()
						c.open(number)
					end,
				})
				found += 1
				if found >= CONTENT_PER_FILE or #out >= limit then
					break
				end
			end
		end
		if #out >= limit then
			break
		end
	end
	return out
end

-- What the palette lists for the tab and query, in order, by section
-- (command_palette.rs palette_sections). (Rows hold functions, which a
-- computed state cannot carry, so this runs where read.)
local function results(p: Palette): { Row }
	local ws = words(p.query:get())
	local typed = #ws > 0
	local t = p.tab:get()
	local out: { Row } = {}
	-- Up to `limit` of `list` (matching what is typed unless `ranked`),
	-- under `section` when given.
	local function take(list: { Row }, limit: number?, ranked: boolean?, section: string?, quick: boolean?)
		local n = 0
		for _, r in list do
			if limit and n >= limit then
				break
			end
			if (ranked or matches(r, ws)) and (r.shown == nil or r.shown()) and (not quick or r.quick) then
				if section and r.section ~= section then
					r = table.clone(r)
					r.section = section
				end
				table.insert(out, r)
				n += 1
			end
		end
	end
	local contents = p.contents or {}
	local current = if p.current_thread then p.current_thread() else nil
	local files = if type(p.files) == "function" then p.files() else p.files
	local recent = if p.recent_files then p.recent_files() else {}
	if t == "all" and not typed then
		take(recent, ALL_LIMIT, true, "Recent Files")
		take(p.commands, nil, true, "Quick Actions", true)
		take(threads_for(p.threads, ws, current), ALL_LIMIT, true, "Recent Threads")
	elseif t == "all" then
		take(threads_for(p.threads, ws), ALL_LIMIT, true, "Threads")
		take(p.commands, nil, false, "Commands")
		take(files, ALL_LIMIT, false, "Files")
		take(M.content_matches(contents, p.query:get(), ALL_LIMIT), nil, true)
	elseif t == "threads" then
		take(threads_for(p.threads, ws, current), THREADS_LIMIT, true, if typed then "Threads" else "Recent Threads")
	elseif t == "commands" then
		take(p.commands, nil, false, if typed then "Commands" else "Quick Actions")
	elseif not typed then
		take(recent, FILES_LIMIT, true, "Recent Files")
	else
		take(files, FILES_LIMIT, false, "Files")
		take(M.content_matches(contents, p.query:get(), CONTENT_LIMIT), nil, true)
	end
	return out
end

local function close(p: Palette)
	if p.on_close then
		p.on_close()
	end
end

local function choose(p: Palette, index: number)
	local r = results(p)[index]
	if r then
		close(p)
		r.run()
	end
end

local function step_tab(p: Palette, by: number)
	local at = 1
	for i, t in TABS do
		if t.id == p.tab:peek() then
			at = i
		end
	end
	p.tab:set(TABS[((at - 1 + by) % #TABS) + 1].id)
	p.active:set(1)
end

local function keys(p: Palette): (e: KeyEvent) -> boolean?
	return function(e: KeyEvent): boolean?
		local n = #results(p)
		if e.key == "ArrowDown" then
			p.active:set(if n == 0 then 1 else (p.active:peek() % n) + 1)
		elseif e.key == "ArrowUp" then
			p.active:set(if n == 0 then 1 else ((p.active:peek() - 2) % n) + 1)
		elseif e.key == "Enter" then
			choose(p, p.active:peek())
		elseif e.key == "Tab" then
			step_tab(p, if e.shift then -1 else 1)
		elseif e.key == "Escape" then
			close(p)
		elseif e.meta and #e.key == 1 and e.key >= "1" and e.key <= "4" then
			p.tab:set(TABS[tonumber(e.key) :: number].id)
			p.active:set(1)
		else
			return nil
		end
		return true
	end
end

-- A match in a file: "path:line" muted (at most 200), then the line in
-- mono, the match on the code wash.
local function content_line(r: Row): Node
	local lit = r.lit :: { number }
	return ui.row {
		grow = 1,
		shrink = 1,
		min_w = 0,
		gap = "$zeron.space.8",
		items = "center",
		txt.text {
			r.detail or "",
			literal = true,
			size = "sm",
			color = T.tertiary,
			line = false,
			truncate = true,
			max_w = 200,
			shrink = 0,
		},
		ui.rich {
			grow = 1,
			shrink = 1,
			min_w = 0,
			truncate = true,
			font = "mono",
			text_size = "$font.size.sm",
			color = T.secondary,
			string.sub(r.label, 1, lit[1] - 1),
			ui.span { string.sub(r.label, lit[1], lit[2]), color = T.text, bg = T.code_wash },
			string.sub(r.label, lit[2] + 1),
		},
	}
end

-- A row: the icon, the label, the detail, the shortcut. The pointer moves
-- the highlight (the keyboard's), as Zeron's.
local function row(p: Palette, r: Row, index: number): Node
	local function on(): boolean
		return p.active:get() == index
	end
	return ui.column {
		w_full = true,
		px = "$zeron.space.8",
		ui.button {
			id = `palette_{r.id}`,
			w_full = true,
			min_h = 30,
			py = "$zeron.space.4",
			px = "$zeron.space.8",
			gap = "$zeron.space.10",
			items = "center",
			rounded = "$zeron.radius.8",
			cursor = "pointer",
			focus = { border = 0 },
			variants = recipes.active_glass { selected = on },
			on_hover = function(inside: boolean)
				if inside then
					p.active:set(index)
				end
			end,
			on_click = function()
				choose(p, index)
			end,
			if r.file
				then require("./file_icon").icon { path = r.file, size = 16 }
				else icon { name = r.icon :: any, size = 16, color = r.tint or T.secondary },
			if r.lit then content_line(r) else txt.text { r.label, size = "md", line = false, shrink = 0 },
			(not r.lit and r.detail) and txt.text {
				r.detail,
				size = "sm",
				color = T.tertiary,
				line = false,
				truncate = true,
				shrink = 1,
				min_w = 0,
			},
			ui.div { grow = 1 },
			r.keys and kbd { size = "sm", flat = true, table.unpack(r.keys) },
		},
	}
end

local function section_header(title: string, first: boolean): Node
	return ui.column {
		w_full = true,
		pt = if first then "$zeron.space.8" else 0,
		(not first) and ui.div { w_full = true, h = 1, my = "$zeron.space.8", bg = T.hairline } or nil,
		ui.row {
			px = "$zeron.space.16",
			pt = "$zeron.space.2",
			pb = "$zeron.space.4",
			txt.text { title, size = "xs", color = T.tertiary, line = false },
		},
	}
end

local function body(p: Palette): Node
	return ui.presence(function()
		-- Rebuilt as the list changes: each row's index is its place.
		local ids: { string } = { p.tab:get() }
		for _, r in results(p) do
			table.insert(ids, `{r.section}:{r.id}`)
		end
		return table.concat(ids, ",")
	end, function(): Node
		local list = results(p)
		local children: { Node } = {}
		local section = ""
		for i, r in list do
			if r.section ~= section then
				table.insert(children, section_header(r.section, section == ""))
				section = r.section
			end
			table.insert(children, row(p, r, i))
		end
		if #list == 0 then
			-- Files with nothing typed: none opened or changed yet.
			local recent = p.tab:peek() == "files" and string.match(p.query:peek(), "%S") == nil
			table.insert(
				children,
				ui.column {
					id = "palette_empty",
					w_full = true,
					py = "$zeron.space.24",
					px = "$zeron.space.16",
					gap = "$zeron.space.6",
					items = "center",
					txt.text { if recent then "No recent files" else "No results", size = "md", line = false },
					txt.text {
						if recent
							then "Files you open or change in this workspace show up here."
							else "Try a command, chat title, project, or device.",
						size = "sm",
						color = T.tertiary,
						line = false,
					},
				}
			)
		end
		return ui.scroll {
			w_full = true,
			max_h = 360,
			fade = { 18, 18 },
			fade_overflow = true,
			ui.column { w_full = true, pb = "$zeron.space.8", gap = "$zeron.space.2", children },
		}
	end, { w_full = true })
end

local function tabs(p: Palette): Node
	local chips: { Node } = {}
	for i, t in TABS do
		table.insert(
			chips,
			ui.button {
				id = `palette_tab_{t.id}`,
				h = 24,
				px = "$zeron.space.8",
				gap = "$zeron.space.6",
				items = "center",
				rounded = "$zeron.radius.6",
				cursor = "pointer",
				focus = { border = 0 },
				variants = recipes.palette_tab {
					selected = function()
						return p.tab:get() == t.id
					end,
				},
				on_click = function()
					p.tab:set(t.id)
					p.active:set(1)
				end,
				txt.text { t.label, size = "sm", weight = "medium", line = false, color = "inherit" },
				kbd { size = "sm", flat = true, "⌘", tostring(i) },
			}
		)
	end
	return ui.row {
		w_full = true,
		px = "$zeron.space.12",
		py = "$zeron.space.6",
		gap = "$zeron.space.4",
		items = "center",
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		chips,
	}
end

local function hint(keys_: { string }, label: string): Node
	return ui.row {
		gap = "$zeron.space.5",
		items = "center",
		kbd { size = "sm", flat = true, table.unpack(keys_) },
		txt.text { label, size = "xs", color = T.tertiary, line = false },
	}
end

-- The card itself.
M.card = ui.component(function(p: Palette): Node
	local on_key = keys(p)
	return ui.column {
		id = "palette",
		w = 560,
		max_w = "90%",
		rounded = "$zeron.radius.16",
		bg = T.frost,
		backdrop_blur = T.frost_blur,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		overflow = "hidden",
		on_click = function() end,
		on_key = on_key,
		ui.row {
			w_full = true,
			min_h = 44,
			px = "$zeron.space.16",
			py = "$zeron.space.8",
			gap = "$zeron.space.10",
			items = "center",
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			icon { name = "magnifer", size = 16, color = T.tertiary },
			ui.input {
				id = "palette_input",
				value = p.query,
				placeholder = "Search commands, threads and files",
				placeholder_color = T.tertiary,
				grow = 1,
				min_w = 0,
				bg = T.clear,
				border = 0,
				rounded = 0,
				focus = { border = 0, bg = T.clear },
				hover = { bg = T.clear },
				p = 0,
				text_size = "$font.size.lg",
				on_key = on_key,
				on_mount = if p.autofocus ~= false
					then function(el: Element)
						el:focus()
					end
					else nil,
			},
			kbd { size = "sm", flat = true, "⌘", "K" },
		},
		tabs(p),
		body(p),
		ui.row {
			w_full = true,
			px = "$zeron.space.16",
			py = "$zeron.space.7",
			gap = "$zeron.space.12",
			items = "center",
			border_sides = { 1, 0, 0, 0 },
			border_color = T.hairline,
			hint({ "↑", "↓" }, "Navigate"),
			hint({ "↵" }, "Open"),
			hint({ "esc" }, "Close"),
		},
	}
end)

-- The palette over the window while `open`: a faint scrim, the card a
-- little above the middle. Each opening starts empty, on All.
function M.overlay(p: Palette, open: State<boolean>): Node
	return ui.presence(function()
		return if open:get() then "on" else nil
	end, function(): Node
		p.query:set("")
		p.tab:set("all")
		p.active:set(1)
		return ui.column {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			items = "center",
			pt = "14%",
			bg = T.scrim_soft,
			on_click = function()
				close(p)
			end,
			on_mount = function(el: Element)
				anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(motion.FAST) })
			end,
			M.card(p),
		}
	end, { exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) } })
end

return M
