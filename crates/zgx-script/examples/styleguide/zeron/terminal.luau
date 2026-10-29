-- Terminals (terminal/panel.rs): a Ghostty session per right-pane tab, per
-- pane and per tab of the dock that ⌘J opens under a session's chat. The
-- dock keeps its own tabs for each session, opens 280 high (dragged between
-- 160 and 55% of the window, a double press on its edge back to 280) and
-- eases open and shut over 200 ms; closing its last tab shuts it. A tab is
-- named by what its program titles it, "Terminal N" until then. Sessions
-- outlive the views that show them; closing a tab ends its process. Each
-- draws in the theme's terminal colours and Appearance's Terminal font,
-- restyled as they change; the dock shutting hands the keyboard to the
-- chat's draft.
local T = require("../theme")
local kit = require("@kit")
local motion = require("@kit/motion")
local state = require("./state")

local M = {}

M.HEIGHT = 280
M.MIN = 160
M.MAX = 0.55
-- The edge that resizes it.
M.HANDLE = 5

-- Whether the window shows terminals (Ghostty, with the desktop host's
-- `ghostty` feature).
function M.native(): boolean
	return ui.native:get().terminals
end

-- Ghostty's configuration as the theme and Appearance's Terminal font say
-- now (read lazily: settings requires the app's modules).
local function size_of(text: string): number
	return tonumber(string.match(text, "^%s*([%d.]+)")) or kit.terminal.FONT
end
local config = ui.computed(function(): string
	local pref = require("./settings").pref
	return kit.terminal.config(pref.font_terminal:get(), size_of(pref.font_terminal_size:get()))
end)
local sessions: { [string]: Term } = {}
-- Every session restyles with the theme (one call each per change).
ui.effect(function()
	local now = config:get()
	for _, term in sessions do
		term:configure(now)
	end
end)

function M.session(id: string): Term
	local term = ui.term(`zterm:{id}`, { font_size = kit.terminal.FONT, config = config:peek() })
	sessions[id] = term
	return term
end

-- "Terminal N": one more than the terminals open beside it as it opens (a
-- dock's tabs, or the panes' and right pane's).
local numbers: { [string]: number } = {}
local function number(id: string, open: number?): number
	local n = numbers[id]
	if not n then
		if not open then
			local docked = string.sub(id, 1, 4) == "dock"
			open = 0
			for other in numbers do
				if (string.sub(other, 1, 4) == "dock") == docked then
					open = (open :: number) + 1
				end
			end
		end
		n = (open :: number) + 1
		numbers[id] = n
	end
	return n
end

-- What its tab says: the program's title (OSC 0/2), or "Terminal N".
function M.title(id: string): () -> string
	local term = M.session(id)
	local n = number(id)
	return function()
		local t = string.match(term.title, "^%s*(.-)%s*$") or ""
		return if t ~= "" then t else `Terminal {n}`
	end
end

function M.exited(id: string): () -> boolean
	local term = M.session(id)
	return function()
		return term.exited ~= nil
	end
end

-- The surface of a right-pane tab or a pane.
function M.surface(id: string): Node
	return kit.terminal.view { id = `term_{id}`, term = M.session(id), native = M.native }
end

-- Ends tab `id`'s session.
function M.close(id: string)
	M.session(id):close()
	sessions[id] = nil
	numbers[id] = nil
end

-- ---- the dock --------------------------------------------------------------

type Dock = {
	open: State<boolean>,
	tabs: State<{ string }>,
	active: State<string>,
	-- The height it shows at, easing to the target as it opens and shuts.
	shown: State<number>,
}

local height = ui.state("zdock_height", M.HEIGHT)
local made = ui.state("zdock_made", 0)
local docks: { [string]: Dock } = {}
local anims: { [string]: Animation } = {}

local function dock(session: string): Dock
	local d = docks[session]
	if not d then
		d = {
			open = ui.state(`zdock_open:{session}`, false),
			tabs = ui.state(`zdock_tabs:{session}`, {} :: { string }),
			active = ui.state(`zdock_active:{session}`, ""),
			shown = ui.state(`zdock_shown:{session}`, 0),
		}
		docks[session] = d
	end
	return d :: Dock
end

local function ease(session: string, to: number)
	local d = dock(session)
	local a = anims[session]
	if a then
		a:cancel()
		anims[session] = nil
	end
	if not motion.loops() or math.abs(d.shown:peek() - to) < 0.5 then
		d.shown:set(to)
		return
	end
	-- anime writes the height itself, without a script call per frame.
	anims[session] = (anime.animate :: any)(d.shown, {
		value = to,
		duration = motion.d(motion.RESIZE),
		ease = motion.EASE_OUT,
		onComplete = function()
			anims[session] = nil
		end,
	}) :: Animation
end

-- A new tab in `session`'s dock, chosen and focused.
function M.add(session: string): string
	local d = dock(session)
	made:set(made:peek() + 1)
	local id = `dock{made:peek()}`
	number(id, #d.tabs:peek())
	d.tabs:push(id)
	d.active:set(id)
	M.session(id):focus()
	return id
end

-- ⌘J: open (with a first tab if it has none) or shut `session`'s dock.
function M.toggle(session: string)
	local d = dock(session)
	local open = not d.open:peek()
	d.open:set(open)
	if open and #d.tabs:peek() == 0 then
		M.add(session)
	elseif open then
		M.session(d.active:peek()):focus()
	else
		-- The terminal goes from under the keyboard: the draft takes it
		-- (shell.rs toggle_terminal).
		local active = d.active:peek()
		if active ~= "" then
			M.session(active):blur()
		end
		local field = state.composer_field(session):peek()
		if field then
			field:focus()
		end
	end
	ease(session, if open then height:peek() else 0)
end

-- A tab closed: the next takes over, or the one before it at the end;
-- the last shuts the dock.
local function closed(session: string, id: string)
	local d = dock(session)
	local list = d.tabs:peek()
	local at = table.find(list, id)
	M.close(id)
	if not at then
		return
	end
	local rest = table.clone(list)
	table.remove(rest, at)
	if d.active:peek() == id then
		d.active:set(rest[at] or rest[at - 1] or "")
	end
	d.tabs:set(rest)
	if #rest == 0 and d.open:peek() then
		M.toggle(session)
	end
end

local function bar(session: string, d: Dock): Node
	return kit.terminal.bar {
		id = "zdock_bar",
		on_add = function()
			M.add(session)
		end,
		on_hide = function()
			M.toggle(session)
		end,
		ui.tabs {
			id = "zdock_tabs",
			label = "Terminals",
			items = d.tabs,
			value = d.active,
			gap = "$zeron.space.4",
			shrink = 1,
			min_w = 0,
			closable = true,
			reorderable = true,
			on_close = function(id: string): boolean
				closed(session, id)
				return false
			end,
			tab = function(id: string, close: () -> ()): Node
				return kit.terminal.chip {
					id = `zdock_tab_{id}`,
					title = M.title(id),
					exited = M.exited(id),
					selected = function()
						return d.active:get() == id
					end,
					on_click = function()
						M.session(id):focus()
					end,
					on_close = close,
				}
			end,
		},
	}
end

-- The edge that resizes the dock: a 1-point line in the strong border
-- under the pointer, no script as it passes.
local function edge(session: string, d: Dock, area: Ref): Node
	local from: { y: number, h: number }? = nil
	return ui.div {
		id = "zdock_edge",
		absolute = true,
		top = 0,
		left = 0,
		right = 0,
		h = M.HANDLE,
		cursor = "row_resize",
		hover_group = true,
		on_press = function(e: PointerEvent)
			if (e.clicks or 1) >= 2 then
				from = nil
				height:set(M.HEIGHT)
				ease(session, M.HEIGHT)
				return
			end
			from = { y = e.y, h = d.shown:peek() }
		end,
		-- Only while pressed: the pointer passing over runs nothing.
		on_press_move = function(e: PointerEvent)
			local f = from
			if not f then
				return
			end
			local el = area:get()
			local room = if el and el.height then el.height else M.HEIGHT / M.MAX
			local h = math.clamp(f.h + (f.y - e.y), M.MIN, math.max(room * M.MAX, M.MIN))
			height:set(h)
			d.shown:set(h)
		end,
		on_release = function()
			from = nil
		end,
		ui.div {
			absolute = true,
			top = 0,
			left = 0,
			right = 0,
			h = 1,
			bg = T.clear,
			pointer_events = "none",
			group_hover = { bg = T.strong },
		},
	}
end

-- `body` (a session's chat, growing into what the dock leaves) over its
-- dock, `area` the column they share.
function M.with_dock(session: string, body: Node): Node
	local d = dock(session)
	local area = ui.ref()
	return ui.column {
		ref = area,
		w_full = true,
		h_full = true,
		items = "stretch",
		body,
		ui.presence(function()
			return if d.shown:get() > 0.5 then "dock" else nil
		end, function(): Node
			return ui.div {
				id = "zdock",
				relative = true,
				w_full = true,
				shrink = 0,
				h = d.shown,
				overflow = "hidden",
				bg = T.terminal,
				border_sides = { 1, 0, 0, 0 },
				border_color = T.border,
				-- Laid out at its full height, clipped as it eases: nothing
				-- inside reflows.
				ui.column {
					absolute = true,
					top = 0,
					left = 0,
					right = 0,
					h = height,
					items = "stretch",
					bar(session, d),
					ui.presence(d.active, function(id: string): Node
						if id == "" then
							return ui.div {}
						end
						return kit.terminal.view {
							id = `zdock_term_{id}`,
							term = M.session(id),
							native = M.native,
							bg = T.clear,
						}
					end, { grow = 1, min_h = 0, w_full = true, items = "stretch" }),
				},
				edge(session, d, area),
			}
		end, { w_full = true, shrink = 0 }),
	}
end

return M
