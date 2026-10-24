-- Zeron, rebuilt on the kit: the app, not a specimen. Two routes (the chat,
-- and the pull requests' board) each lay their columns out under Zeron's
-- panel policy (kit/panel_shell, PRs #677 and #914): the sidebar shared by
-- both, the content column, a right pane each, Files beside the chat. Two
-- layouts draw around the same columns: Zeron's unified titlebar over
-- flush columns, or glass (Rex's), the sidebar on the window's blur and
-- every content column a well inset into it. ⌘K's palette, ⌘, settings.
-- Opened from the workbench's Apps page, or with STYLEGUIDE_APP=zeron.
-- The design lint: every colour, spacing, radius, type and shadow comes
-- from a theme token (or `ui.raw` with its reason). Asked before any module
-- builds anything.
ui.theme.strict("warn")
local T = require("./theme")
local kit = require("@kit")
local look = require("@kit/look")
local ps = require("@kit/panel_shell")
local state = require("./zeron/state")
local chrome = require("./zeron/chrome")
local headers = require("./zeron/headers")
local sidebar = require("./zeron/sidebar")
local conversation = require("./zeron/conversation")
local pane = require("./zeron/pane")
local files = require("./zeron/files")
local prs = require("./zeron/prs")
local settings_page = require("./zeron/settings")
local tabs = require("./zeron/tabs")
local palette = require("./zeron/palette")
local account = require("./zeron/account")
local dropzone = require("./zeron/dropzone")

-- A route's columns, drawn in a layout.
local function columns(route: string, layout: string): Node
	local glass = layout == "glass"
	local chat = route == "chat"
	local shell = if chat then state.chat else state.prs
	return ps.view(shell, {
		w_full = true,
		h_full = true,
		hairlines = not glass,
		tone = not glass,
		sidebar = sidebar.view(),
		conversation = chrome.column {
			id = "well_conversation",
			column = "conversation",
			first = true,
			header = headers.conversation,
			body = if chat
				then function(): Node
					-- Each session its own conversation; a new one, the canvas.
					return ui.presence(state.session, function(session: string): Node
						if session == "new" then
							return conversation.canvas(nil, function(key: string)
								state.sessions_version:set(state.sessions_version:peek() + 1)
								state.go("chat", key)
							end)
						end
						-- A session or a file dropped on it: a mention, an attachment.
						return dropzone.wrap(session, conversation.view(session))
					end, { w_full = true, h_full = true })
				end
				else prs.board,
		},
		right = chrome.column {
			id = "well_right",
			column = "right",
			header = headers.pane,
			body = if chat
				then function(): Node
					return ui.column {
						w_full = true,
						h_full = true,
						pt = chrome.top,
						variants = kit.recipes.panel_fill { glass = glass },
						items = "stretch",
						pane.body(),
					}
				end
				else function(): Node
					return ui.column {
						w_full = true,
						h_full = true,
						pt = chrome.top,
						variants = kit.recipes.panel_fill { glass = glass },
						items = "stretch",
						prs.detail(),
					}
				end,
		},
		files = if chat
			then chrome.column { id = "well_files", column = "files", header = headers.files, body = files.view }
			else nil,
	})
end

-- The tabs layouts: the topbar over the active tab's panes, with the
-- sessions beside them in the second.
local function tabbed(with_sidebar: boolean): Node
	if not with_sidebar then
		return ui.column { w_full = true, h_full = true, tabs.topbar(false), tabs.body() }
	end
	return ui.column {
		w_full = true,
		h_full = true,
		tabs.topbar(true),
		ps.view(state.tabs_shell, {
			w_full = true,
			grow = 1,
			hairlines = false,
			tone = false,
			sidebar = sidebar.view(),
			conversation = ui.column { w_full = true, h_full = true, tabs.body() },
		}),
	}
end

-- The app's menus (app_menus.rs), as far as a host shows script commands:
-- Zeron's own items, and the appearance. (The keys stay the view's: ⌘,
-- is handled below, so the menu shows none of its own.)
ui.command { id = "zeron_check_updates", title = "Check for Updates…", menu = "Zeron", run = account.check_for_updates }
ui.command { menu = "Zeron", separator = true }
ui.command {
	id = "zeron_settings",
	title = "Settings",
	menu = "Zeron",
	run = function()
		state.settings:set(not state.settings:peek())
	end,
}
for _, mode in { { "system", "System" }, { "light", "Light" }, { "dark", "Dark" } } do
	ui.command {
		id = `zeron_appearance_{mode[1]}`,
		title = `Appearance: {mode[2]}`,
		menu = "View",
		run = function()
			state.look.mode:set(mode[1] :: any)
		end,
	}
end

local LAYOUTS = { "zeron", "glass", "tabs", "tabs_sidebar" }

-- The tabs layouts' keys: tabs, splits, zoom, moving between panes.
local function tab_key(e: KeyEvent): boolean
	local k = e.key
	if k == "t" then
		tabs.new_tab()
	elseif k == "w" then
		return tabs.close_focused()
	elseif k == "d" then
		tabs.split(if e.shift then "column" else "row")
	elseif k == "Enter" and e.shift then
		tabs.zoom()
	elseif (k == "[" or k == "]") and e.shift then
		tabs.cycle(if k == "]" then 1 else -1)
	elseif e.alt and (k == "ArrowLeft" or k == "ArrowRight" or k == "ArrowUp" or k == "ArrowDown") then
		local dir = { ArrowLeft = "left", ArrowRight = "right", ArrowUp = "up", ArrowDown = "down" }
		tabs.go(dir[k] :: any)
	elseif #k == 1 and k >= "1" and k <= "9" then
		tabs.select(tonumber(k) :: number)
	elseif k == "\\" and state.layout:peek() == "tabs_sidebar" then
		ps.toggle(state.tabs_shell, "sidebar")
	else
		return false
	end
	return true
end

-- The palette's commands run what the keys run.
palette.act.new_tab = function()
	if state.tabbed_now() then
		tabs.new_tab()
	else
		state.go("chat", "new")
	end
end
palette.act.split_right = function()
	if state.tabbed_now() then
		tabs.split("row")
	end
end
palette.act.split_down = function()
	if state.tabbed_now() then
		tabs.split("column")
	end
end
palette.act.close = function()
	if state.tabbed_now() then
		tabs.close_focused()
	else
		state.close_active()
	end
end
palette.act.sidebar = function()
	ps.toggle(state.shell_now(), "sidebar")
end
palette.act.files = function()
	if state.tabbed_now() then
		tabs.open_surface("files")
	else
		ps.toggle(state.chat, "files")
	end
end

local function on_key(e: KeyEvent): boolean
	if e.key == "Escape" then
		if state.palette:peek() then
			state.palette:set(false)
			return true
		elseif state.settings:peek() then
			state.settings:set(false)
			return true
		end
		return false
	end
	-- ⌃Tab, ⌃⇧Tab: the next or previous session.
	if e.ctrl and not e.meta and e.key == "Tab" then
		sidebar.cycle(if e.shift then -1 else 1)
		return true
	end
	if not e.meta then
		return false
	end
	if e.key == "l" and e.shift then
		local at = table.find(LAYOUTS, state.layout:peek()) or 1
		state.layout:set(LAYOUTS[at % #LAYOUTS + 1] :: any)
		return true
	end
	if state.tabbed_now() and e.key ~= "k" and e.key ~= "," and tab_key(e) then
		return true
	end
	local shell = state.shell_now()
	-- ⌘1 to ⌘9: jump to a session (the tabs layouts take them for spaces).
	if not e.shift and not e.alt and #e.key == 1 and e.key >= "1" and e.key <= "9" then
		return sidebar.jump(tonumber(e.key) :: number)
	end
	if e.key == "k" then
		state.palette:toggle()
	elseif e.key == "," then
		state.settings:set(not state.settings:peek())
	elseif e.key == "\\" then
		ps.toggle(shell, "sidebar")
	elseif e.key == "e" and e.shift and state.route:peek() == "chat" then
		ps.toggle(state.chat, "files")
	elseif e.key == "w" then
		return state.close_active()
	elseif e.key == "[" then
		state.back()
	elseif e.key == "]" then
		state.forward()
	else
		return false
	end
	return true
end

-- Settings takes the window's place: what it covers stops painting, so the
-- page sits on the window's glass as Zeron's does (and keeps its layout).
local function beneath_settings(): boolean
	return state.settings:get()
end

return ui.div {
	id = "zeron",
	relative = true,
	w_full = true,
	h_full = true,
	bg = T.glass,
	-- The look's accent and surface (kit/look) over the theme.
	theme = look.scope(state.look),
	color = T.text,
	font = T.sans,
	text_size = "$font.size.md",
	focusable = true,
	on_key = on_key,
	on_mount = function(el: Element)
		el:focus()
	end,
	-- A route or a layout change builds the columns again: the arriving
	-- route lays out at rest, and one layout's tree leaves before the
	-- other's mounts.
	ui.presence(function()
		local layout = state.layout:get()
		if layout == "tabs" or layout == "tabs_sidebar" then
			return layout
		end
		return `{state.route:get()}:{layout}`
	end, function(key: string): Node
		if key == "tabs" or key == "tabs_sidebar" then
			return tabbed(key == "tabs_sidebar")
		end
		local route, layout = string.match(key, "^(%w+):(%w+)$")
		return columns(route or "chat", layout or "zeron")
	end, { w_full = true, h_full = true, invisible = beneath_settings }),
	ui.presence(state.layout, function(layout: string): Node
		if layout ~= "zeron" then
			return ui.div {}
		end
		return ui.div { absolute = true, top = 0, left = 0, right = 0, headers.titlebar() }
	end, { absolute = true, top = 0, left = 0, right = 0, invisible = beneath_settings }),
	palette.view(),
	settings_page.view(),
	account.dialogs(),
	kit.toast.host(),
	-- The image viewer, over everything while it shows one.
	kit.lightbox.host(),
	-- Signing in, a workspace, a first project (shell.rs gates).
	require("./zeron/onboarding").view(),
}
