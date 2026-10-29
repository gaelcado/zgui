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
local voice = require("./zeron/voice")
local browser = require("./zeron/browser")
local terminal = require("./zeron/terminal")
local session_card = require("./zeron/session_card")
local project_actions = require("./zeron/actions")
local keys = require("./zeron/keys")
local data = require("./zeron/data")
local session_sidebar = require("@kit/session_sidebar")
local projects = require("./zeron/projects")
local updates = require("./zeron/updates")

-- A session's conversation (a new one, the canvas) over its own
-- terminals (⌘J).
local function session_body(session: string): Node
	if session == "new" then
		return terminal.with_dock(
			session,
			ui.column {
				relative = true,
				grow = 1,
				min_h = 0,
				items = "stretch",
				conversation.canvas(nil, function(key: string)
					state.sessions_version:set(state.sessions_version:peek() + 1)
					state.go("chat", key)
				end),
				-- The agents' updates, at Home's foot.
				updates.island(),
			}
		)
	end
	-- A session or a file dropped on it: a mention, an attachment.
	return terminal.with_dock(
		session,
		dropzone.wrap(
			session,
			voice.transcript(session, function(): Node
				return conversation.view(session)
			end)
		)
	)
end

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
		-- What the voice stage covers fades under it (voice.UNDER).
		conversation = chrome.column {
			id = "well_conversation",
			column = "conversation",
			class = voice.UNDER,
			opacity = voice.under_opacity(),
			first = true,
			header = headers.conversation,
			body = if chat
				then function(): Node
					-- Each session its own. Navigation that moves the column
					-- fades through (conversation.handoff): what shows keeps
					-- its session while it fades out.
					return ui.presence(conversation.handoff, function(epoch: number): Node
						local shown: string? = nil
						return ui.presence(function(): string?
							local now = state.session:get()
							if conversation.handoff:get() == epoch then
								shown = now
							end
							return shown
						end, session_body, { w_full = true, h_full = true })
					end, {
						w_full = true,
						h_full = true,
						mode = "wait",
						exit = conversation.HANDOFF_OUT,
						enter = conversation.HANDOFF_IN,
					})
				end
				else prs.board,
		},
		right = chrome.column {
			id = "well_right",
			column = "right",
			class = voice.UNDER,
			opacity = voice.under_opacity(),
			header = headers.pane,
			body = if chat
				then function(): Node
					-- Its keys (⌃Tab steps its tabs) while it has the focus.
					return ui.column {
						id = "zpane_body",
						w_full = true,
						h_full = true,
						pt = chrome.top,
						variants = kit.recipes.panel_fill { glass = glass },
						items = "stretch",
						on_key = pane.on_key,
						on_mount = pane.mounted,
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
			then chrome.column {
				id = "well_files",
				column = "files",
				header = headers.files,
				body = files.view,
				class = voice.UNDER,
				opacity = voice.under_opacity(),
			}
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
			conversation = voice.under(tabs.body()),
		}),
	}
end

-- The app's menus (app_menus.rs): About and Zeron's own items in the
-- application menu, above Services, Hide and Quit; the Edit menu's
-- standard items, sent to whatever has focus; the appearance under View.
-- (The keys stay the view's: ⌘, is handled below, so the menu shows none
-- of its own.)
ui.command { menu = "app", about = { name = "Zeron", version = account.VERSION } }
ui.command { id = "zeron_check_updates", title = "Check for Updates…", menu = "app", run = account.check_for_updates }
ui.command { menu = "app", separator = true }
ui.command {
	id = "zeron_settings",
	title = "Settings",
	menu = "app",
	run = function()
		state.settings:set(not state.settings:peek())
	end,
}
ui.command { menu = "Edit", standard = "undo" }
ui.command { menu = "Edit", standard = "redo" }
ui.command { menu = "Edit", separator = true }
ui.command { menu = "Edit", standard = "cut" }
ui.command { menu = "Edit", standard = "copy" }
ui.command { menu = "Edit", standard = "paste" }
ui.command { menu = "Edit", separator = true }
ui.command { menu = "Edit", standard = "select_all" }
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

-- The tabs layouts' own keys (Tern's, where Zeron has none): tabs,
-- splits, zoom, moving between panes. ⌘D splits where the composer does
-- not take it for dictation.
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
-- ⌘J: the chat's terminals (the classic layouts'; a pane is one in the
-- tabs layouts).
palette.act.terminal_dock = function()
	if not state.tabbed_now() and state.route:peek() == "chat" then
		terminal.toggle(state.session:peek())
	end
end

-- The browser the keys act on: the right pane's tab on show, or the
-- focused pane.
local function active_browser(): string?
	if state.tabbed_now() then
		local pane, s = tabs.focused()
		return if s and s.kind == "preview" then pane else nil
	end
	local tab = state.tab:peek()
	if state.route:peek() == "chat" and ps.shown(state.chat, "right") and state.kind_of(tab) == "preview" then
		return tab
	end
	return nil
end

palette.act.files = function()
	if state.tabbed_now() then
		tabs.open_surface("files")
	else
		ps.toggle(state.chat, "files")
	end
end

-- The session the window works on: the chat's, or the focused pane's.
local function current_session(): string
	return if state.tabbed_now() then state.pane_session:peek() else state.session:peek()
end

-- Zeron's rebindable shortcuts (shell.rs apply_keymap), as Settings →
-- Shortcuts binds them. False lets the key go on (the tabs layouts' own
-- keys, the composer's).
local function run_binding(id: string): boolean
	local tabbed = state.tabbed_now()
	local chat = state.route:peek() == "chat"
	local jump = string.match(id, "^jump_(%d)$")
	if jump then
		-- The tabs layouts' digits choose a space.
		if tabbed then
			tabs.select(tonumber(jump) :: number)
			return true
		end
		return sidebar.jump(tonumber(jump) :: number)
	elseif id == "next_session" or id == "prev_session" then
		local by = if id == "next_session" then 1 else -1
		-- Pressed last, the right pane takes them for its tabs.
		if not tabbed and chat and pane.pressed and ps.shown(state.chat, "right") then
			pane.step(by)
		else
			sidebar.cycle(by)
		end
	elseif id == "new_session" then
		-- From anywhere, Settings too.
		state.settings:set(false)
		palette.act.new_tab()
	elseif id == "toggle_sidebar" then
		if state.layout:peek() == "tabs" then
			return false
		end
		ps.toggle(state.shell_now(), "sidebar")
	elseif id == "toggle_changes" then
		if tabbed then
			return false
		end
		state.toggle_right()
	elseif id == "toggle_files" then
		if not tabbed and not chat then
			return false
		end
		palette.act.files()
	elseif id == "toggle_terminal" then
		if tabbed then
			tabs.open_surface("terminal")
			return true
		end
		-- The session's terminal dock under its chat.
		palette.act.terminal_dock()
	elseif id == "browser_reload" then
		local page = active_browser()
		if not page then
			return false
		end
		browser.reload(page)
	elseif id == "open_model_picker" then
		if not chat or state.settings:peek() then
			return false
		end
		return conversation.open_model_picker(current_session())
	elseif id == "archive_session" then
		local key = current_session()
		if not chat or state.settings:peek() or data.session(key) == nil then
			return false
		end
		session_sidebar.set_archived(key, true)
	elseif id == "new_project" then
		-- The add-project flow (shell/spaces.rs open_add_space).
		if state.settings:peek() then
			return false
		end
		projects.start()
	elseif id == "random_wallpaper" then
		settings_page.random_wallpaper()
	else
		return false
	end
	return true
end

-- ⌘K's New chat and Archive thread, as ⌘N and ⌘⇧A; Archive thread only
-- while the session on show can go (archivable_selected_chat).
palette.act.new_chat = function()
	run_binding("new_session")
end
palette.act.archive_thread = function()
	run_binding("archive_session")
end
palette.can_archive = function(): boolean
	local key = current_session()
	local s = data.session(key)
	return state.route:get() == "chat"
		and not state.settings:get()
		and s ~= nil
		and not session_sidebar.archived(key, s.archived == true)
end

local function on_key(e: KeyEvent): boolean
	if e.key == "Escape" then
		if projects.open:peek() then
			projects.open:set(false)
			return true
		elseif state.palette:peek() then
			state.palette:set(false)
			return true
		elseif state.settings:peek() then
			state.settings:set(false)
			return true
		end
		-- With nothing else to close, Escape stops the agent at work
		-- (Settings → General).
		if settings_page.pref.escape_stops:peek() then
			return conversation.stop(current_session())
		end
		return false
	end
	if e.meta and e.key == "l" and e.shift then
		local at = table.find(LAYOUTS, state.layout:peek()) or 1
		state.layout:set(LAYOUTS[at % #LAYOUTS + 1] :: any)
		return true
	end
	local bound = keys.bound(e)
	if bound and run_binding(bound) then
		return true
	end
	if not e.meta then
		return false
	end
	-- ⌘F in Settings: its search.
	if e.key == "f" and not (e.shift or e.alt or e.ctrl) and state.settings:peek() then
		settings_page.focus_search()
		return true
	end
	if state.tabbed_now() and e.key ~= "k" and e.key ~= "," and tab_key(e) then
		return true
	end
	-- A browser's address: ⌘L. While its page or address has the
	-- keyboard, ⌘[ and ⌘] step the page's history and ⌘T opens another
	-- (browser/mod.rs bind_keys).
	local page = active_browser()
	if page and e.key == "l" and not e.shift then
		browser.focus_address(page)
		return true
	end
	if page and browser.has_focus(page) and not (e.shift or e.alt or e.ctrl) then
		if e.key == "[" then
			browser.back(page)
			return true
		elseif e.key == "]" then
			browser.forward(page)
			return true
		elseif e.key == "t" and not state.tabbed_now() then
			state.open_tab("preview")
			return true
		end
	end
	if e.key == "k" then
		state.palette:toggle()
	elseif e.key == "," then
		state.settings:set(not state.settings:peek())
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
-- Settings, the boot splash while the engine connects, enabling sync's
-- steps or the engine's gate cover the app: it stops painting beneath them
-- (the splash fades out over it).
local sync = require("./zeron/sync")
local onboarding = require("./zeron/onboarding")
local function beneath_settings(): boolean
	return state.settings:get() or account.booting:get() or sync.covering() or onboarding.covering()
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
	-- A press anywhere but on them dismisses the session card floating over
	-- the transcript and folds the agents' updates; where the last press
	-- landed (the right pane, or elsewhere) decides what ⌃Tab steps.
	on_press = function(e: PointerEvent)
		session_card.press(e)
		pane.press(e)
		updates.press(e)
	end,
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
		return ui.div { absolute = true, top = 0, left = 0, right = 0, voice.under(headers.titlebar(), false) }
	end, { absolute = true, top = 0, left = 0, right = 0, invisible = beneath_settings }),
	-- The voice call's stage: over the page and its chrome, under dialogs.
	voice.stage_view {
		artwork = conversation.artwork,
		top = function(): number
			return if state.layout:get() == "tabs_sidebar" then tabs.HEIGHT else 0
		end,
	},
	palette.view(),
	settings_page.view(),
	-- Enabling sync's steps and the engine's gate, in the window's place.
	sync.view(),
	account.dialogs(),
	sync.dialogs(),
	project_actions.dialogs(),
	kit.toast.host(),
	-- The image viewer, over everything while it shows one.
	kit.lightbox.host(),
	-- First-run setup, or signing in, a workspace and a first project
	-- (shell.rs gates).
	onboarding.view(),
	-- Adding a project: over onboarding's last step, which opens it.
	projects.view(),
	-- The boot splash, over every gate while the engine connects.
	ui.presence(function(): string?
		return if account.booting:get() then "boot" else nil
	end, function(): Node
		return kit.loaders.splash { id = "boot_splash" }
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		exit = kit.loaders.SPLASH_OUT,
	}),
}
