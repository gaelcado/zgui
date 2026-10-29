-- Changes, as Zeron's right pane shows them (changes.rs): a header with the
-- scope (the working tree, the branch against a base, the latest turn) and
-- the branch's "{branch} → {base}" with a searchable picker of bases, or,
-- for one commit's own diff, its short SHA and subject; then the toggles:
-- split view, wrapping long lines, folding every file. Under it the strip
-- saying what is shown ("3 Uncommitted changes", "2 Changed files in this
-- commit"), the counts, and "Partial snapshot" when the diff was cut
-- short; then every file's header (its own icon), its notices ("New file",
-- "Binary file — contents not shown"), its hunks and their lines as rows
-- of one virtual list (`ui.list`, only what shows is built), the file
-- headers sticking to the top as their lines scroll by. Wrapped, the rows
-- take their height as they show (a measured list). A file folds under its
-- header. Nothing to show says so ("No uncommitted changes", "Empty
-- commit"); no patch yet, preparing. The working tree's trash discards it,
-- asked first.
--
-- Review comments (comments.rs, comment_ui.rs): under the pointer a line
-- shows a 16 "+" on the solid in its number's gutter (unified: the old
-- number's for a deletion; split: the new side's alone), which opens a
-- draft card under the line; posted, a comment shows as a card under its
-- line (full width in both views), staged for the session's next prompt,
-- its pen editing it in place. The pointer runs no script (`group_hover`).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local icon_button = require("./icon_button")
local tooltip = require("./tooltip")
local file_icon = require("./file_icon")
local diff = require("./diff")
local patch = require("./patch")
local select = require("./select")
local loaders = require("./loaders")
local frost = require("./frost")
local popover = require("./popover")
local recipes = require("./recipes")
local comment = require("./comment")
local dialog = require("./dialog")
local button = require("./button")

-- A review comment on a line: of the original file ("L", a deletion's
-- number) or of the changed one ("R"); none for a file's own line. On a
-- renamed file, `old_path` is where an "L" line lives, and what it cites.
export type Comment = {
	id: string,
	path: string,
	side: ("L" | "R")?,
	line: number,
	body: string,
	old_path: string?,
}
export type Scope = "working" | "branch" | "turn" | "commit"
export type Mode = "unified" | "split"
export type Commit = { sha: string, subject: string }
export type Props = {
	id: string,
	-- The patch for a scope (against `base` for the branch's, the commit's
	-- SHA for a commit's); nil while it is being prepared. Read where it
	-- changes.
	patch: (scope: Scope, base: string) -> string?,
	-- Whether that patch was cut short (the engine's partial snapshot).
	partial: ((scope: Scope, base: string) -> boolean)?,
	-- The branch checked out, and those the branch scope can compare against.
	branch: string?,
	branches: { string }?,
	scope: State<Scope>?,
	base: State<string>?,
	mode: State<Mode>?,
	-- Long lines wrapped rather than cut.
	wrap: State<boolean>?,
	-- One commit's own diff (a History row's): no scope to choose.
	commit: Commit?,
	-- Discarding the working tree, once asked (its trash in the header).
	on_discard: (() -> ())?,
	-- The file's own view (its whole text).
	on_open_file: ((path: string) -> ())?,
	-- The comments on its lines (read where they change), and what posting,
	-- editing and removing one do; without `on_comment`, lines take none.
	comments: (() -> { Comment })?,
	on_comment: ((c: Comment) -> ())?,
	on_edit_comment: ((id: string, body: string) -> ())?,
	on_remove_comment: ((id: string) -> ())?,
}

local M = {}

M.HEADER = 38
-- The strip under the header (render_header_strip), as tall.
M.STRIP = 38
-- A comment card's height (comments.rs card_height): its insets and header
-- (46) and its body's lines, guessed at 64 columns, 1 to 8 of them; a
-- draft's (DRAFT_CARD_HEIGHT, at the kit's metrics).
M.DRAFT = 124
function M.card_height(body: string): number
	local lines = 0
	for line in string.gmatch(body .. "\n", "([^\n]*)\n") do
		lines += math.max(math.ceil((utf8.len(line) or #line) / 64), 1)
	end
	return 46 + math.clamp(lines, 1, 8) * 18
end
-- Where a line's comment is: its side and number (a deletion's old one).
local function anchor(l: diff.Line): ("L" | "R", number?)
	if l.kind == "del" then
		return "L", l.old
	end
	return "R", l.new
end

local SCOPES: { { id: Scope, label: string } } = {
	{ id = "working", label = "Working tree" },
	{ id = "branch", label = "Branch changes" },
	{ id = "turn", label = "Latest turn" },
}

-- What the strip says of `n` files (changes.rs scope_label).
function M.summary(scope: Scope, n: number, base: string): string
	local files = if n == 1 then "file" else "files"
	if scope == "working" then
		return if n == 1 then "1 Uncommitted change" else `{n} Uncommitted changes`
	elseif scope == "branch" then
		return `{n} Changed {files} vs {base}`
	elseif scope == "turn" then
		return `{n} Changed {files} this turn`
	end
	return `{n} Changed {files} in this commit`
end

-- What a scope with nothing in it says (changes.rs clean_message).
function M.clean_message(scope: Scope, base: string): string
	if scope == "branch" then
		return `No changes vs {base}`
	elseif scope == "turn" then
		return "No changes this turn"
	end
	return if scope == "commit" then "Empty commit" else "No uncommitted changes"
end

-- The branches holding `query` (any case), those starting with it first
-- (popover.rs filter_indices).
function M.filter(branches: { string }, query: string): { string }
	local q = string.lower(query)
	if q == "" then
		return branches
	end
	local starts, within = {}, {}
	for _, b in branches do
		local at = string.find(string.lower(b), q, 1, true)
		if at == 1 then
			table.insert(starts, b)
		elseif at then
			table.insert(within, b)
		end
	end
	table.move(within, 1, #within, #starts + 1, starts)
	return starts
end

type RowKind = "file" | "notice" | "hunk" | "line" | "pair" | "comment" | "draft"
type Row = {
	key: string,
	kind: RowKind,
	file: patch.File?,
	-- A line's file path (its comments'), and its path before a rename; a
	-- comment, a draft's target.
	path: string?,
	old_path: string?,
	comment: Comment?,
	-- The file's place among the files, from 1.
	index: number?,
	-- A hunk's header, a notice's words.
	header: string?,
	line: diff.Line?,
	pair: patch.Pair?,
}

-- The draft open under a line: where, and the comment it edits.
type Draft = { path: string, side: "L" | "R", line: number, editing: string?, old_path: string? }

-- The path a comment's line is in: an old side's on a renamed file, the
-- file's old path (comments.rs cite_path).
local function cite(path: string, side: ("L" | "R")?, old_path: string?): string
	return if side == "L" and old_path then old_path else path
end

-- The base's picker (changes.rs render_ref_menu): a 240 card under its
-- trigger, "Search branches…" over the branches in mono 12 (the base on
-- the selected wash), at most 240 before they scroll; Up and Down move,
-- Enter picks, Escape closes.
local function base_picker(
	id: string,
	open: State<boolean>,
	base: State<string>,
	branches: { string },
	anchor_node: Node
): Node
	local function content(): Node
		local query = ui.use_state("")
		local active = ui.use_state(math.max(table.find(branches, base:peek()) or 1, 1))
		ui.effect(function()
			if query:get() ~= "" then
				active:set(1)
			end
		end)
		local function rows(): { string }
			return M.filter(branches, query:get())
		end
		local function choose(name: string)
			base:set(name)
			open:set(false)
		end
		local function on_key(e: KeyEvent): boolean
			local list = rows()
			if e.key == "ArrowDown" or e.key == "ArrowUp" then
				if #list > 0 then
					local by = if e.key == "ArrowDown" then 1 else -1
					active:set((active:peek() - 1 + by) % #list + 1)
				end
				return true
			elseif e.key == "Enter" then
				local pick = list[active:peek()]
				if pick then
					choose(pick)
				end
				return true
			elseif e.key == "Escape" then
				open:set(false)
				return true
			end
			return false
		end
		return ui.column {
			w_full = true,
			gap = "$zeron.space.2",
			ui.row {
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
					label = "Search branches",
					placeholder = "Search branches…",
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
				max_h = 240,
				fade = { 12, 12 },
				fade_overflow = true,
				ui.presence(function(): string
					return table.concat(rows(), "\n")
				end, function(): Node
					local list = rows()
					if #list == 0 then
						return ui.row {
							px = "$zeron.space.8",
							py = "$zeron.space.6",
							txt.text {
								if #branches == 0 then "No branches" else "No matching branches",
								size = "md",
								color = T.tertiary,
								line = false,
							},
						}
					end
					local built: { Node } = {}
					for i, name in list do
						table.insert(
							built,
							ui.button {
								id = `{id}_{string.gsub(name, "[^%w]", "_")}`,
								w_full = true,
								min_h = 32,
								px = "$zeron.space.8",
								py = 0,
								items = "center",
								rounded = T.radius_item,
								variants = recipes.picker_choice {
									selected = function()
										return base:get() == name
									end,
									keyed = function()
										return active:get() == i
									end,
								},
								color = T.text,
								focus = { border = 0 },
								cursor = "pointer",
								on_click = function()
									choose(name)
								end,
								txt.text {
									name,
									literal = true,
									size = "md",
									mono = true,
									color = "inherit",
									truncate = true,
									line = false,
									grow = 1,
									min_w = 0,
								},
							}
						)
					end
					return ui.column { w_full = true, gap = "$zeron.space.2", built }
				end, { w_full = true }),
			},
		}
	end
	return ui.popover {
		id = id,
		open = open,
		label = "Base branch",
		anchor = anchor_node,
		w = 240,
		p = T.space(frost.INSET),
		gap = "$zeron.space.2",
		rounded = T.radius_card,
		bg = T.frost,
		backdrop_blur = frost.BLUR,
		border = 1,
		border_color = T.border,
		shadow = T.float_shadow,
		color = T.text,
		placement = { side = "bottom", align = "start", offset = 10 },
		enter = popover.enter(nil, 4),
		exit = popover.exit(nil, 4),
		ui.presence(function(): boolean?
			return if open:get() then true else nil
		end, content, { w_full = true }),
	}
end

-- A header toggle (changes.rs header_toggle): 24 square, its 14 icon, on
-- the selected wash while it is on; named by its tooltip.
local function toggle(
	id: string,
	glyph: icon.Name,
	label: string,
	on: State<boolean> | () -> boolean,
	run: () -> ()
): Node
	return tooltip {
		label = label,
		icon_button {
			id = id,
			icon = glyph,
			size = 24,
			icon_size = 14,
			label = label,
			no_ring = true,
			selected = on :: any,
			on_click = run,
		},
	}
end

M.view = ui.component(function(props: Props): Node
	local scope = props.scope or ui.use_state("working" :: Scope)
	local base = props.base or ui.use_state((props.branches or { "main" })[1])
	local mode = props.mode or ui.use_state("unified" :: Mode)
	local wrap = props.wrap or ui.use_state(false)
	local commit = props.commit
	-- Files folded shut, by path.
	local folded = ui.use_state({} :: { [string]: boolean })
	-- Where the list is scrolled: kept as a fold or a mode builds it again.
	local offset = ui.use_state(0)
	-- The draft open under a line, and what it says.
	local draft = ui.use_state(nil :: Draft?)
	local draft_text = ui.use_state("")
	local discarding = ui.use_state(false)
	local picking = ui.use_state(false)
	local commenting = props.on_comment ~= nil
	local made = 0

	local function shown(): (Scope, string)
		if commit then
			return "commit", commit.sha
		end
		return scope:get(), base:get()
	end

	local files = ui.computed(function(): { patch.File }?
		local text = props.patch(shown())
		return if text then patch.parse(text) else nil
	end)

	-- Every file folded shut (and there is one).
	local function all_folded(): boolean
		local fs = files:get() or {}
		local shut = folded:get()
		for _, f in fs do
			if not shut[f.path] then
				return false
			end
		end
		return #fs > 0
	end

	-- Every row in order: a file's header, then (open) its notices, its
	-- hunks' headers and lines, or their split pairs, each line's comments
	-- under it.
	local rows = ui.computed(function(): { Row }
		local out: { Row } = {}
		local split = mode:get() == "split"
		local shut = folded:get()
		local notes = if commenting and props.comments then props.comments() else {}
		local open_draft = if commenting then draft:get() else nil
		local editing = if open_draft then open_draft.editing else nil
		-- Where a new draft is open, as `path|side|line`.
		local new_at = if open_draft and not editing
			then `{open_draft.path}|{open_draft.side}|{open_draft.line}`
			else nil
		-- A line's comments (the one being edited as its draft), then a new
		-- draft open there.
		local function under(path: string, side: "L" | "R", number: number)
			for _, c in notes do
				if c.path == path and c.side == side and c.line == number then
					if editing == c.id then
						table.insert(out, { key = "draft", kind = "draft" :: RowKind, path = path })
					else
						table.insert(out, { key = `c{c.id}`, kind = "comment" :: RowKind, comment = c, path = path })
					end
				end
			end
			if new_at == `{path}|{side}|{number}` then
				table.insert(out, { key = "draft", kind = "draft" :: RowKind, path = path })
			end
		end
		for fi, f in files:get() or {} do
			local open = not shut[f.path]
			table.insert(out, { key = `f{fi}:{open}`, kind = "file" :: RowKind, file = f, index = fi })
			if open then
				for ni, n in patch.notices(f) do
					table.insert(out, { key = `n{fi}.{ni}`, kind = "notice" :: RowKind, header = n })
				end
				for hi, h in f.hunks do
					table.insert(out, { key = `h{fi}.{hi}`, kind = "hunk" :: RowKind, header = h.header })
					if split then
						for li, p in patch.pairs(h.lines) do
							table.insert(out, {
								key = `p{fi}.{hi}.{li}`,
								kind = "pair" :: RowKind,
								pair = p,
								path = f.path,
								old_path = f.old_path,
							})
							-- Both sides' comments, full width under the pair: a
							-- deletion's (the old side), then the new side's line.
							if p.left and p.left.kind == "del" and p.left.old then
								under(f.path, "L", p.left.old)
							end
							if p.right and p.right.new then
								under(f.path, "R", p.right.new)
							end
						end
					else
						for li, l in h.lines do
							table.insert(out, {
								key = `l{fi}.{hi}.{li}`,
								kind = "line" :: RowKind,
								line = l,
								path = f.path,
								old_path = f.old_path,
							})
							local side, number = anchor(l)
							if number then
								under(f.path, side, number)
							end
						end
					end
				end
			end
		end
		return out
	end)

	local function file_row(f: patch.File, index: number): Node
		local function open(): boolean
			return not folded:get()[f.path]
		end
		return ui.row {
			id = `{props.id}_file_{index}`,
			variants = recipes.disclosure { tone = "plain" },
			w_full = true,
			h = M.HEADER,
			px = "$zeron.space.12",
			gap = "$zeron.space.8",
			items = "center",
			bg = T.card,
			border_sides = if index > 1 then { 1, 0, 0, 0 } else { 0, 0, 1, 0 },
			border_color = T.hairline,
			on_click = function()
				folded:set_key(f.path, if open() then true else nil)
			end,
			ui.row {
				w = 14,
				h = 14,
				shrink = 0,
				items = "center",
				justify = "center",
				require("./disclosure").chevron { open = open, size = 13 },
			},
			file_icon.icon { path = f.path, size = 14 },
			txt.text {
				f.path,
				literal = true,
				size = "sm",
				mono = true,
				color = "inherit",
				truncate = true,
				grow = 1,
				shrink = 1,
				min_w = 0,
				line = false,
			},
			f.binary and txt.text { "BIN", size = "micro", color = T.tertiary, line = false } or nil,
			(f.added > 0 or not f.binary)
					and txt.text { `+{f.added}`, size = "xs", mono = true, color = T.diff_add, line = false }
				or nil,
			(f.removed > 0 or not f.binary)
					and txt.text { `−{f.removed}`, size = "xs", mono = true, color = T.diff_del, line = false }
				or nil,
			props.on_open_file and tooltip {
				label = "Open in file browser",
				ui.button {
					variants = recipes.wash { hover = "ink3" },
					w = 24,
					h = 24,
					p = 0,
					items = "center",
					justify = "center",
					rounded = T.radius_md,
					focus = { border = 0 },
					label = "Open in file browser",
					on_click = function()
						(props.on_open_file :: (string) -> ())(f.path)
					end,
					icon { name = "document", size = 14, color = T.secondary },
				},
			} or nil,
		}
	end

	-- The "+" that opens a draft at a line, shown under its row's pointer.
	local function adder(path: string, side: "L" | "R", number: number, left: number, old_path: string?): Node
		return ui.div {
			absolute = true,
			top = (diff.LINE - 16) / 2,
			left = left,
			opacity = 0,
			group_hover = { opacity = 1 },
			comment.add(function()
				draft_text:set("")
				draft:set { path = path, side = side, line = number, old_path = old_path }
			end),
		}
	end

	local function build(r: Row?, index: number, wrapped: boolean): Node
		if not r then
			return ui.div {}
		end
		if r.kind == "file" then
			return file_row(r.file :: patch.File, r.index or index)
		elseif r.kind == "notice" then
			return diff.notice(r.header :: string)
		elseif r.kind == "hunk" then
			return diff.hunk_header(r.header :: string)
		elseif r.kind == "pair" then
			local p = r.pair :: patch.Pair
			-- The new side alone takes a "+" (the old one is inert).
			local right = p.right
			if commenting and right and right.new then
				return diff.split(
					p.left,
					right,
					adder(r.path :: string, "R", right.new, (diff.GUTTER - 16) / 2),
					wrapped
				)
			end
			return diff.split(p.left, right, nil, wrapped)
		elseif r.kind == "comment" then
			local c = r.comment :: Comment
			return ui.column {
				w_full = true,
				pb = "$zeron.space.6",
				comment.card {
					id = `{props.id}_comment_{c.id}`,
					where = `{cite(c.path, c.side, c.old_path)}:{c.line}`,
					body = c.body,
					on_edit = if props.on_edit_comment and c.side
						then function()
							draft_text:set(c.body)
							draft:set {
								path = c.path,
								side = c.side :: "L" | "R",
								line = c.line,
								editing = c.id,
								old_path = c.old_path,
							}
						end
						else nil,
					on_remove = function()
						if props.on_remove_comment then
							props.on_remove_comment(c.id)
						end
					end,
				},
			}
		elseif r.kind == "draft" then
			local at = draft:peek()
			if not at then
				return ui.div {}
			end
			local function post()
				local body = draft_text:peek()
				if string.match(body, "%S") then
					if at.editing then
						if props.on_edit_comment then
							props.on_edit_comment(at.editing, body)
						end
					elseif props.on_comment then
						made += 1
						props.on_comment {
							id = `{props.id}_{made}`,
							path = at.path,
							side = at.side,
							line = at.line,
							body = body,
							old_path = if at.side == "L" then at.old_path else nil,
						}
					end
				end
				draft:set(nil)
			end
			return comment.draft {
				id = `{props.id}_draft`,
				where = `{cite(at.path, at.side, at.old_path)}:{at.line}`,
				value = draft_text,
				autofocus = true,
				action = if at.editing then "Save" else "Comment",
				on_submit = post,
				on_cancel = function()
					draft:set(nil)
				end,
			}
		end
		local l = r.line :: diff.Line
		local side, number = anchor(l)
		if not commenting or not number then
			return diff.line(l, wrapped)
		end
		-- The "+" in the number's gutter, under the pointer.
		return ui.div {
			w_full = true,
			h = if wrapped then nil else diff.LINE,
			relative = true,
			hover_group = true,
			diff.line(l, wrapped),
			adder(
				r.path :: string,
				side,
				number :: number,
				3 + (if side == "L" then 0 else diff.GUTTER) + (diff.GUTTER - 16) / 2,
				r.old_path
			),
		}
	end

	local function height(r: Row): number
		if r.kind == "comment" then
			return M.card_height((r.comment :: Comment).body) + 6
		elseif r.kind == "draft" then
			return M.DRAFT
		elseif r.kind == "notice" then
			return diff.NOTICE
		end
		return if r.kind == "file" then M.HEADER elseif r.kind == "hunk" then diff.HUNK else diff.LINE
	end

	local scopes: { select.Option } = {}
	for _, s in SCOPES do
		table.insert(scopes, { value = s.id, label = s.label })
	end
	local branches = props.branches or { "main" }

	local function empty(): boolean
		return #(files:get() or {}) == 0
	end

	-- `{branch} → {base ⌄}`: the base's trigger opens its picker.
	local function refs(): Node
		local trigger = ui.button {
			id = `{props.id}_base`,
			variants = recipes.wash { hover = "ink3" },
			h = 24,
			px = "$zeron.space.6",
			gap = "$zeron.space.4",
			items = "center",
			rounded = T.radius_md,
			focus = { border = 0 },
			cursor = "pointer",
			label = "Base branch",
			on_click = ui.toggle(picking),
			txt.text {
				function()
					return base:get()
				end,
				size = "sm",
				mono = true,
				color = T.secondary,
				truncate = true,
				line = false,
				min_w = 0,
			},
			icon { name = "alt-arrow-down", size = 12, color = T.tertiary },
		}
		return ui.row {
			ml = "$zeron.space.4",
			gap = "$zeron.space.6",
			items = "center",
			shrink = 1,
			min_w = 0,
			txt.text {
				props.branch or "HEAD",
				literal = true,
				size = "sm",
				mono = true,
				color = T.secondary,
				truncate = true,
				line = false,
				shrink = 1,
				min_w = 0,
			},
			icon { name = "arrow-right", size = 12, color = T.tertiary },
			base_picker(`{props.id}_bases`, picking, base, branches, trigger),
		}
	end

	-- What the diff is of: the scope and its base, or the commit.
	local what: { Node } = if commit
		then {
			-- Its short SHA on a chip, then its subject.
			ui.row {
				id = `{props.id}_sha`,
				h = 24,
				px = "$zeron.space.6",
				items = "center",
				shrink = 0,
				rounded = "$zeron.radius.6",
				bg = T.ink2,
				txt.text { string.sub(commit.sha, 1, 7), size = "xs", mono = true, color = T.tertiary, line = false },
			},
			txt.text {
				if commit.subject == "" then string.sub(commit.sha, 1, 7) else commit.subject,
				literal = true,
				size = "sm",
				truncate = true,
				line = false,
				grow = 1,
				shrink = 1,
				min_w = 0,
			},
		}
		else {
			select {
				id = `{props.id}_scope`,
				label = "Scope",
				look = "quiet",
				value = scope :: any,
				options = scopes,
				menu_w = 180,
			},
			ui.show(function()
				return scope:get() == "branch"
			end, refs()),
			ui.div { grow = 1 },
		}

	local header = ui.row {
		w_full = true,
		h = 40,
		px = "$zeron.space.12",
		gap = "$zeron.space.6",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		what,
		-- The working tree's alone, first of the controls (changes.rs
		-- discard_button): faint and inert while there is nothing to discard.
		(props.on_discard and not commit) and ui.show(
			function()
				return scope:get() == "working"
			end,
			ui.button {
				id = `{props.id}_discard`,
				variants = recipes.wash { hover = "ink3", inert = "faint" },
				w = 24,
				h = 24,
				p = 0,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_md,
				focus = { border = 0 },
				cursor = "pointer",
				label = "Discard changes",
				tooltip = "Discard changes",
				disabled = empty,
				on_click = ui.set(discarding, true),
				icon { name = "trash-bin-minimalistic", size = 14, color = T.secondary },
			}
		) or nil,
		toggle(`{props.id}_split`, "split-columns", "Split view", function()
			return mode:get() == "split"
		end, function()
			mode:set(if mode:peek() == "split" then "unified" else "split")
		end),
		toggle(`{props.id}_wrap`, "wrap-text", "Wrap long lines", wrap, function()
			wrap:set(not wrap:peek())
		end),
		ui.presence(all_folded, function(shut: boolean): Node
			local label = if shut then "Expand all files" else "Collapse all files"
			return tooltip {
				label = label,
				icon_button {
					id = `{props.id}_fold_all`,
					icon = "fold-vertical",
					size = 24,
					icon_size = 14,
					label = label,
					no_ring = true,
					on_click = function()
						-- Every file shut, or all open once every one is.
						if shut then
							folded:set {}
						else
							local all = {}
							for _, f in files:peek() or {} do
								all[f.path] = true
							end
							folded:set(all)
						end
					end,
				},
			}
		end),
	}

	-- What is shown and its counts, once there is a patch: built again
	-- only as they change.
	local strip = ui.presence(function()
		local fs = files:get()
		if not fs then
			return nil
		end
		local added, removed = 0, 0
		for _, f in fs do
			added += f.added
			removed += f.removed
		end
		local s, b = shown()
		local partial = props.partial ~= nil and props.partial(s, b)
		return `{M.summary(s, #fs, b)}\n+{added}\n−{removed}\n{partial}`
	end, function(said: string): Node
		local label, added, removed, partial = string.match(said, "^(.*)\n(.*)\n(.*)\n(%a+)$")
		return ui.row {
			w_full = true,
			h = M.STRIP,
			px = "$zeron.space.16",
			gap = "$zeron.space.10",
			items = "center",
			shrink = 0,
			border_sides = { 0, 0, 1, 0 },
			border_color = T.hairline,
			txt.text {
				label or "",
				literal = true,
				id = `{props.id}_counts`,
				size = "sm",
				color = T.secondary,
				truncate = true,
				line = false,
				shrink = 1,
				min_w = 0,
			},
			txt.text { added or "", literal = true, size = "xs", mono = true, color = T.diff_add, line = false },
			txt.text { removed or "", literal = true, size = "xs", mono = true, color = T.diff_del, line = false },
			ui.div { grow = 1 },
			partial == "true" and ui.row {
				id = `{props.id}_partial`,
				px = "$zeron.space.6",
				py = "$zeron.space.2",
				rounded = "$zeron.radius.4",
				bg = T.warning_wash,
				shrink = 0,
				txt.text { "Partial snapshot", size = "micro", color = T.warning, opacity = 0.75, line = false },
			} or nil,
		}
	end, { w_full = true, shrink = 0 })

	local body = ui.presence(function()
		local fs = files:get()
		if fs == nil then
			return "preparing"
		end
		return if #fs == 0 then "clean" else "list"
	end, function(state: string): Node
		if state == "preparing" then
			return ui.column {
				grow = 1,
				w_full = true,
				items = "center",
				justify = "center",
				gap = "$zeron.space.8",
				-- Zeron's: the gradient spinner at cell 3 over "Preparing diff…".
				loaders.gradient_spinner { cell = 3 },
				txt.text { "Preparing diff…", size = "sm", color = T.tertiary, line = false },
			}
		elseif state == "clean" then
			return ui.column {
				grow = 1,
				w_full = true,
				items = "center",
				justify = "center",
				txt.text {
					function()
						return M.clean_message(shown())
					end,
					id = `{props.id}_clean`,
					size = "sm",
					color = T.tertiary,
					line = false,
				},
			}
		end
		-- Built again when the rows change (a fold, a mode, a scope): each
		-- row is then built once, as it comes into view, with no watcher of
		-- its own; the offset carries the scroll position over.
		return ui.presence(function()
			local keys = {}
			for _, r in rows:get() do
				-- Comments and a draft change the rows (and their heights).
				if r.kind ~= "line" and r.kind ~= "pair" then
					table.insert(keys, r.key)
				end
			end
			local s, b = shown()
			return `{s}|{b}|{mode:get()}|{wrap:get()}|{#rows:get()}|{table.concat(keys, ",")}`
		end, function(): Node
			local list = rows:peek()
			local wrapped = wrap:peek()
			local sticky: { number } = {}
			for i, r in list do
				if r.kind == "file" then
					table.insert(sticky, i)
				end
			end
			local function row(index: number): Node
				return build(list[index], index, wrapped)
			end
			if wrapped then
				-- Wrapped lines take the height they need, measured as they show.
				return ui.list {
					id = `{props.id}_rows`,
					grow = 1,
					w_full = true,
					scrollbar = true,
					label = "Changes",
					offset = offset,
					count = #list,
					measured = true,
					height = diff.LINE,
					sticky = sticky,
					row = row,
				}
			end
			local heights: { number } = {}
			for _, r in list do
				table.insert(heights, height(r))
			end
			return ui.list {
				id = `{props.id}_rows`,
				grow = 1,
				w_full = true,
				scrollbar = true,
				label = "Changes",
				offset = offset,
				heights = heights,
				sticky = sticky,
				row = row,
			}
		end, { grow = 1, w_full = true, min_h = 0 })
	end, { grow = 1, w_full = true, min_h = 0 })

	-- Asked first (shell.rs discard_working_tree_modal); built as it is
	-- asked (it closes at once, as Zeron's).
	local confirm = props.on_discard
		and ui.show(
			discarding,
			dialog {
				id = `{props.id}_discard_dialog`,
				open = discarding,
				title = "Discard working tree changes?",
				description = "Discard all uncommitted changes in this working tree? This can’t be undone.",
				actions = {
					button {
						id = `{props.id}_discard_cancel`,
						label = "Cancel",
						variant = "ghost",
						size = "sm",
						on_click = ui.set(discarding, false),
					},
					button {
						id = `{props.id}_discard_confirm`,
						label = "Discard changes",
						variant = "danger",
						size = "sm",
						on_click = function()
							discarding:set(false)
							if props.on_discard then
								props.on_discard()
							end
						end,
					},
				},
			}
		)

	return ui.column {
		id = props.id,
		w_full = true,
		h_full = true,
		header,
		strip,
		body,
		confirm or nil,
	}
end)

return M
