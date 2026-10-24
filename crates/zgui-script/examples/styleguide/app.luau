-- Zeron's UI kit and styleguide on zgui-script: a workbench whose shell is
-- built from the kit it shows. theme.luau declares the tokens and loads the
-- Zeron themes; state.luau holds the pages and the canvas's settings;
-- shell/ is the sidebar, toolbar, canvas and inspector; pages/ the
-- specimens; kit/ the components.
-- The design lint: every colour, spacing, radius, type and shadow comes
-- from a theme token (or `ui.raw` with its reason). Asked before any module
-- builds anything.
ui.theme.strict("warn")
local T = require("./theme")
local state = require("./state")
local kit = require("@kit")
local look = require("@kit/look")
local sidebar = require("@shell/sidebar")
local canvas = require("@shell/canvas")
local inspector = require("@shell/inspector")
local titlebar = require("@shell/titlebar")
local panel_shell = require("@kit/panel_shell")

-- The theme segmented control writes `ui.theme.current`, which applies it.

local palette_mod = require("@kit/palette")

-- ⌘K: a palette over the window that jumps to a page; typed keys filter
-- it, ↑↓ move, ↩ opens, esc closes.
local jump_open = ui.state("jump_open", false)
local jump_query = ui.state("jump_query", "")
local jump_sel = ui.state("jump_sel", "")

local function matches(query: string): { palette_mod.Result }
	local q = string.lower(query)
	local out: { palette_mod.Result } = {}
	for _, page in state.PAGES do
		local at = if q == "" then 1 else string.find(string.lower(page.title), q, 1, true)
		if at then
			-- A match at the start shows bold; one inside leaves the title whole.
			local head = at == 1 and q ~= ""
			table.insert(out, {
				id = page.id,
				title = if head then string.sub(page.title, #q + 1) else page.title,
				match = if head then string.sub(page.title, 1, #q) else nil,
				description = page.blurb,
				group = page.group,
				icon = page.icon :: any,
			})
		end
	end
	return out
end

local function open_jump()
	jump_query:set("")
	jump_sel:set(state.page:peek())
	jump_open:set(true)
end

local function jump_key(e: KeyEvent): boolean
	local list = matches(jump_query:peek())
	local function index(): number
		for i, r in list do
			if r.id == jump_sel:peek() then
				return i
			end
		end
		return 0
	end
	if e.key == "Escape" then
		jump_open:set(false)
	elseif e.key == "Enter" then
		local id = jump_sel:peek()
		if id ~= "" then
			state.page:set(id)
		end
		jump_open:set(false)
	elseif e.key == "ArrowDown" or e.key == "ArrowUp" then
		if #list > 0 then
			local step = if e.key == "ArrowDown" then 1 else -1
			jump_sel:set(list[((index() - 1 + step) % #list) + 1].id)
		end
	elseif e.key == "Backspace" then
		jump_query:set(string.sub(jump_query:peek(), 1, -2))
	elseif #e.key == 1 and not e.meta and not e.ctrl then
		jump_query:set(jump_query:peek() .. e.key)
	else
		return false
	end
	if e.key == "Backspace" or #e.key == 1 then
		local fresh = matches(jump_query:peek())
		jump_sel:set(if #fresh > 0 then fresh[1].id else "")
	end
	return true
end

local function jump(): Node
	return ui.column {
		id = "jump",
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		items = "center",
		pt = "$zeron.space.96",
		bg = T.scrim,
		on_click = ui.set(jump_open, false),
		ui.div {
			on_click = function() end,
			ui.presence(function()
				return jump_query:get()
			end, function(q: string): Node
				local list = matches(q)
				return kit.palette {
					id = "jump_palette",
					icon = "command",
					placeholder = "Jump to a page…",
					query = jump_query,
					count = `{#list} pages`,
					results = list,
					selected = jump_sel,
					w = 520,
					hints = {
						{ keys = { "↑", "↓" }, label = "move" },
						{ keys = { "↩" }, label = "open" },
						{ keys = { "esc" }, label = "close" },
					},
					on_choose = function(id: string)
						state.page:set(id)
						jump_open:set(false)
					end,
				}
			end),
		},
	}
end

-- Keys the window answers: ⌘K the jump palette, ⌘1-9 and ⌘0 a page, ⌘I the
-- inspector, ⌘\ the sidebar.
local function on_key(e: KeyEvent): boolean
	if jump_open:peek() then
		return jump_key(e)
	end
	if not e.meta then
		return false
	end
	if e.key == "k" or e.key == "p" then
		open_jump()
		return true
	end
	local n = tonumber(e.key)
	if n == 0 then
		n = #state.PAGES
	end
	if n and state.PAGES[n] then
		state.page:set(state.PAGES[n].id)
		return true
	end
	if e.key == "i" then
		panel_shell.toggle(state.layout, "files")
		return true
	end
	if e.key == "\\" then
		panel_shell.toggle(state.layout, "sidebar")
		return true
	end
	if e.key == "[" then
		state.back()
		return true
	end
	if e.key == "]" then
		state.forward()
		return true
	end
	return false
end

-- The host may name a page to open on (STYLEGUIDE_PAGE), for a look at
-- one page in a window.
local start_page = ui.shared("start_page", "")
if start_page:peek() ~= "" then
	state.page:set(start_page:peek())
end

-- The window: the columns under Zeron's panel policy, running the full
-- height, and the titlebar over their top 38 (their seams run through it).
return ui.div {
	id = "styleguide",
	relative = true,
	w_full = true,
	h_full = true,
	-- Zeron's window: one glass tint (the shell at 80% over the desktop blur)
	-- under everything; the sidebar adds its tone, the panels their fill
	-- (panel_shell), the canvas nothing.
	bg = T.glass,
	color = T.text,
	font = T.sans,
	text_size = "$font.size.md",
	-- The look's accent and surface (kit/look) over the theme.
	theme = look.scope(state.look),
	focusable = true,
	on_key = on_key,
	on_mount = function(el: Element)
		el:focus()
	end,
	panel_shell.view(state.layout, {
		w_full = true,
		h_full = true,
		sidebar = sidebar.Sidebar(),
		conversation = canvas.Canvas(),
		files = inspector.Inspector(),
	}),
	ui.div { absolute = true, top = 0, left = 0, right = 0, titlebar.Titlebar() },
	ui.presence(function()
		return if jump_open:get() then "on" else nil
	end, function(): Node
		return jump()
	end, {
		-- No box of its own: closed, it must not sit over the window.
		enter = { opacity = { 0, 1 }, duration = kit.motion.d(kit.motion.FAST) },
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.MENU_OUT) },
	}),
	-- Toasts stack over everything, bottom right.
	kit.toast.host(),
}
