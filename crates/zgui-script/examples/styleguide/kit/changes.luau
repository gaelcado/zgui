-- Changes, as Zeron's right pane shows them (changes.rs): a header with the
-- scope (the working tree, the branch against a base, the latest turn),
-- the counts and unified or split; then every file's header, its hunks and
-- their lines as rows of one virtual list (`ui.list`, only what shows is
-- built), the file headers sticking to the top as their lines scroll by.
-- A file folds under its header. Nothing to show reads as clean; no patch
-- yet, as preparing.
--
-- Review comments (comments.rs, comment_ui.rs), in the unified view: under
-- the pointer a line shows a 16 "+" on the solid in its number's gutter
-- (the old number's for a deletion), which opens a draft card under the
-- line; posted, a comment shows as a card under its line, staged for the
-- session's next prompt. The pointer runs no script (`group_hover`).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local diff = require("./diff")
local patch = require("./patch")
local menu = require("./menu")
local segmented = require("./segmented")
local loaders = require("./loaders")
local recipes = require("./recipes")
local comment = require("./comment")

-- A review comment on a line: of the original file ("L", a deletion's
-- number) or of the changed one ("R").
export type Comment = { id: string, path: string, side: "L" | "R", line: number, body: string }
export type Scope = "working" | "branch" | "turn"
export type Mode = "unified" | "split"
export type Props = {
	id: string,
	-- The patch for a scope (against `base` for the branch's); nil while
	-- it is being prepared. Read where it changes.
	patch: (scope: Scope, base: string) -> string?,
	-- The branches the branch scope can compare against.
	branches: { string }?,
	scope: State<Scope>?,
	base: State<string>?,
	mode: State<Mode>?,
	-- The file's own view (its whole text).
	on_open_file: ((path: string) -> ())?,
	-- The comments on its lines (read where they change), and what posting
	-- and removing one do; without `on_comment`, lines take none.
	comments: (() -> { Comment })?,
	on_comment: ((c: Comment) -> ())?,
	on_remove_comment: ((id: string) -> ())?,
}

local M = {}

M.HEADER = 38
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

local function scope_label(scope: Scope, base: string): string
	if scope == "branch" then
		return `Against {base}`
	end
	return if scope == "turn" then "Latest turn" else "Working tree"
end

-- What a scope with nothing in it says (changes.rs clean_message).
local function clean_message(scope: Scope, base: string): string
	if scope == "branch" then
		return `Nothing differs from {base}.`
	end
	return if scope == "turn" then "The latest turn changed no file." else "The working tree is clean."
end

type RowKind = "file" | "hunk" | "line" | "pair" | "comment" | "draft"
type Row = {
	key: string,
	kind: RowKind,
	file: patch.File?,
	-- A line's file path (its comments'), a comment, a draft's target.
	path: string?,
	comment: Comment?,
	-- The file's place among the files, from 1.
	index: number?,
	header: string?,
	line: diff.Line?,
	pair: patch.Pair?,
}

local ICONS = { added = "add-circle", deleted = "close-circle", renamed = "arrow-right", modified = "file-code" }

M.view = ui.component(function(props: Props): Node
	local scope = props.scope or ui.use_state("working" :: Scope)
	local base = props.base or ui.use_state((props.branches or { "main" })[1])
	local mode = props.mode or ui.use_state("unified" :: Mode)
	-- Files folded shut, by path.
	local folded = ui.use_state({} :: { [string]: boolean })
	local scope_open = ui.use_state(false)
	-- Where the list is scrolled: kept as a fold or a mode builds it again.
	local offset = ui.use_state(0)
	local base_open = ui.use_state(false)
	-- The draft open under a line, and what it says.
	local draft = ui.use_state(nil :: { path: string, side: "L" | "R", line: number }?)
	local draft_text = ui.use_state("")
	local commenting = props.on_comment ~= nil
	local made = 0

	local files = ui.computed(function(): { patch.File }?
		local text = props.patch(scope:get(), base:get())
		return if text then patch.parse(text) else nil
	end)

	-- Every row in order: a file's header, then (open) its hunks' headers
	-- and lines, or their split pairs.
	local rows = ui.computed(function(): { Row }
		local out: { Row } = {}
		local split = mode:get() == "split"
		local shut = folded:get()
		local notes = if commenting and props.comments then props.comments() else {}
		local open_draft = if commenting then draft:get() else nil
		for fi, f in files:get() or {} do
			local open = not shut[f.path]
			table.insert(out, { key = `f{fi}:{open}`, kind = "file" :: RowKind, file = f, index = fi })
			if open then
				for hi, h in f.hunks do
					table.insert(out, { key = `h{fi}.{hi}`, kind = "hunk" :: RowKind, header = h.header })
					if split then
						for li, p in patch.pairs(h.lines) do
							table.insert(out, { key = `p{fi}.{hi}.{li}`, kind = "pair" :: RowKind, pair = p })
						end
					else
						for li, l in h.lines do
							table.insert(
								out,
								{ key = `l{fi}.{hi}.{li}`, kind = "line" :: RowKind, line = l, path = f.path }
							)
							-- Its comments under it, then a draft open there.
							local side, number = anchor(l)
							if number then
								for _, c in notes do
									if c.path == f.path and c.side == side and c.line == number then
										table.insert(
											out,
											{ key = `c{c.id}`, kind = "comment" :: RowKind, comment = c, path = f.path }
										)
									end
								end
								if
									open_draft
									and open_draft.path == f.path
									and open_draft.side == side
									and open_draft.line == number
								then
									table.insert(out, { key = "draft", kind = "draft" :: RowKind, path = f.path })
								end
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
			icon { name = (ICONS[f.status] or "file-code") :: any, size = 14, color = "currentColor" },
			f.old_path and txt.text {
				`{f.old_path} →`,
				literal = true,
				size = "sm",
				mono = true,
				color = T.tertiary,
				truncate = true,
				shrink = 1,
				min_w = 0,
				line = false,
			} or nil,
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
			f.added > 0 and txt.text { `+{f.added}`, size = "xs", mono = true, color = T.diff_add, line = false }
				or nil,
			f.removed > 0 and txt.text { `−{f.removed}`, size = "xs", mono = true, color = T.diff_del, line = false }
				or nil,
			require("./disclosure").chevron { open = open, size = 13 },
			props.on_open_file and ui.button {
				variants = recipes.wash { hover = "ink3" },
				w = 24,
				h = 24,
				p = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_md,
				focus = { border = 0 },
				on_click = function()
					(props.on_open_file :: (string) -> ())(f.path)
				end,
				icon { name = "document", size = 14, color = T.secondary },
			} or nil,
		}
	end

	local function build(r: Row?, index: number): Node
		if not r then
			return ui.div {}
		end
		if r.kind == "file" then
			return file_row(r.file :: patch.File, r.index or index)
		elseif r.kind == "hunk" then
			return diff.hunk_header(r.header :: string)
		elseif r.kind == "pair" then
			local p = r.pair :: patch.Pair
			return diff.split(p.left, p.right)
		elseif r.kind == "comment" then
			local c = r.comment :: Comment
			return ui.column {
				w_full = true,
				pb = "$zeron.space.6",
				comment.card {
					id = `{props.id}_comment_{c.id}`,
					where = `{c.path}:{c.line} ({c.side})`,
					body = c.body,
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
				if string.match(body, "%S") and props.on_comment then
					made += 1
					props.on_comment {
						id = `{props.id}_{made}`,
						path = at.path,
						side = at.side,
						line = at.line,
						body = body,
					}
				end
				draft:set(nil)
			end
			return comment.draft {
				id = `{props.id}_draft`,
				where = `{at.path}:{at.line} ({at.side})`,
				value = draft_text,
				autofocus = true,
				on_submit = post,
				on_cancel = function()
					draft:set(nil)
				end,
			}
		end
		local l = r.line :: diff.Line
		local side, number = anchor(l)
		if not commenting or not number then
			return diff.line(l)
		end
		-- The "+" in the number's gutter, under the pointer.
		return ui.div {
			w_full = true,
			h = diff.LINE,
			relative = true,
			hover_group = true,
			diff.line(l),
			ui.div {
				absolute = true,
				top = (diff.LINE - 16) / 2,
				left = 3 + (if side == "L" then 0 else diff.GUTTER) + (diff.GUTTER - 16) / 2,
				opacity = 0,
				group_hover = { opacity = 1 },
				comment.add(function()
					draft_text:set("")
					draft:set { path = r.path :: string, side = side, line = number :: number }
				end),
			},
		}
	end

	local function height(r: Row): number
		if r.kind == "comment" then
			return M.card_height((r.comment :: Comment).body) + 6
		elseif r.kind == "draft" then
			return M.DRAFT
		end
		return if r.kind == "file" then M.HEADER elseif r.kind == "hunk" then diff.HUNK else diff.LINE
	end

	local function counts(): string
		local fs = files:get() or {}
		local added, removed = 0, 0
		for _, f in fs do
			added += f.added
			removed += f.removed
		end
		return `{#fs} {if #fs == 1 then "file" else "files"}  +{added} −{removed}`
	end

	local scope_items: { any } = {}
	for _, s in SCOPES do
		table.insert(scope_items, {
			id = `{props.id}_scope_{s.id}`,
			label = s.label,
			checked = function()
				return scope:get() == s.id
			end,
			on_click = function()
				scope:set(s.id)
			end,
		})
	end
	local base_items: { any } = {}
	for _, b in props.branches or { "main" } do
		table.insert(base_items, {
			id = `{props.id}_base_{b}`,
			label = b,
			icon = "git-branch",
			checked = function()
				return base:get() == b
			end,
			on_click = function()
				base:set(b)
			end,
		})
	end

	local header = ui.row {
		w_full = true,
		h = 40,
		px = "$zeron.space.12",
		gap = "$zeron.space.6",
		items = "center",
		shrink = 0,
		border_sides = { 0, 0, 1, 0 },
		border_color = T.hairline,
		menu.menu {
			id = `{props.id}_scopes`,
			open = scope_open,
			w = 200,
			items = scope_items,
			anchor = ui.button {
				id = `{props.id}_scope`,
				variants = recipes.wash { hover = "ink3" },
				h = 26,
				px = "$zeron.space.8",
				gap = "$zeron.space.6",
				items = "center",
				rounded = T.radius_md,
				focus = { border = 0 },
				on_click = ui.toggle(scope_open),
				txt.text {
					function()
						return scope_label(scope:get(), base:get())
					end,
					size = "sm",
					weight = "medium",
					line = false,
				},
				icon { name = "alt-arrow-down", size = 12, color = T.tertiary },
			},
		},
		ui.show(
			function()
				return scope:get() == "branch"
			end,
			menu.menu {
				id = `{props.id}_bases`,
				open = base_open,
				w = 200,
				items = base_items,
				anchor = ui.button {
					id = `{props.id}_base`,
					variants = recipes.wash { hover = "ink3" },
					h = 26,
					px = "$zeron.space.8",
					gap = "$zeron.space.4",
					items = "center",
					rounded = T.radius_md,
					focus = { border = 0 },
					on_click = ui.toggle(base_open),
					icon { name = "git-branch", size = 12, color = T.secondary },
					txt.text {
						function()
							return base:get()
						end,
						size = "sm",
						mono = true,
						color = T.secondary,
						line = false,
					},
				},
			}
		),
		ui.div { grow = 1 },
		txt.text { counts, id = `{props.id}_counts`, size = "xs", mono = true, color = T.tertiary, line = false },
		segmented {
			id = `{props.id}_mode`,
			size = "sm",
			value = mode :: any,
			options = {
				{ id = "unified", icon = "list", tip = "Unified" },
				{ id = "split", icon = "split-columns", tip = "Split" },
			},
		},
	}

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
				loaders.mini_spinner { color = T.secondary },
				txt.text { "Preparing the diff…", size = "sm", color = T.tertiary, line = false },
			}
		elseif state == "clean" then
			return ui.column {
				grow = 1,
				w_full = true,
				items = "center",
				justify = "center",
				gap = "$zeron.space.6",
				icon { name = "check", size = 20, color = T.tertiary },
				txt.text {
					function()
						return clean_message(scope:get(), base:get())
					end,
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
			return `{scope:get()}|{base:get()}|{mode:get()}|{table.concat(keys, ",")}`
		end, function(): Node
			local list = rows:peek()
			local heights: { number } = {}
			local sticky: { number } = {}
			for i, r in list do
				table.insert(heights, height(r))
				if r.kind == "file" then
					table.insert(sticky, i)
				end
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
				row = function(index: number): Node
					return build(list[index], index)
				end,
			}
		end, { grow = 1, w_full = true, min_h = 0 })
	end, { grow = 1, w_full = true, min_h = 0 })

	return ui.column {
		id = props.id,
		w_full = true,
		h_full = true,
		header,
		body,
	}
end)

return M
