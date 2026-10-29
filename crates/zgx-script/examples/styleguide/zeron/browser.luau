-- The browser (browser/): a page per tab where the window shows pages
-- (WebKit), its toolbar following the page (back and forward while it has
-- history, reload and open-in-browser while it has a page) and its address
-- bar taking what is typed as model.rs does (localhost and loopback over
-- http, the rest over https, only web addresses, nothing with credentials).
-- A new tab offers the project's dev servers (a pane outside a session,
-- which has none, asks for an address); a page that fails to load says so
-- with Try again, and one whose view is still starting says that. Where
-- pages are not the window's own, an address opens in the system's
-- browser, as Zeron does there. Annotate picks elements on the page into
-- the session's draft (zeron/annotate). Pages go only where model.rs lets
-- them, share one store of website data per workspace (profile.rs), and
-- their tabs show their favicons.
local T = require("../theme")
local kit = require("@kit")
local browser_kit = require("@kit/browser")
local data = require("./data")
local state = require("./state")
local annotate = require("./annotate")
local account = require("./account")

local M = {}

-- Whether the window shows pages as its own.
function M.native(): boolean
	return ui.native:get().web
end

-- ---- addresses (model.rs) --------------------------------------------------

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or ""
end

function M.loopback(host: string): boolean
	local h = string.lower(host)
	if h == "localhost" or string.sub(h, -10) == ".localhost" then
		return true
	end
	if h == "[::1]" then
		return true
	end
	local a, b, c, d = string.match(h, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	return a == "127" and b ~= nil and c ~= nil and d ~= nil
end

-- `url`'s scheme, host (IPv6 in its brackets) and port, if it is a web
-- address; nil for one with credentials, a host that is not one, or no
-- authority at all.
local function parts(url: string): (string?, string?, string?, string?)
	local scheme, rest = string.match(url, "^(%a[%w+.-]*):(.*)$")
	if not scheme or not rest then
		return nil, nil, nil, nil
	end
	if string.sub(rest, 1, 2) ~= "//" then
		return string.lower(scheme), nil, nil, rest
	end
	local authority, tail = string.match(string.sub(rest, 3), "^([^/?#]*)(.*)$")
	if not authority or authority == "" then
		return string.lower(scheme), nil, nil, tail
	end
	if string.find(authority, "@", 1, true) then
		return string.lower(scheme), "@", nil, tail
	end
	local host, port = string.match(authority, "^(%[[%x:.]+%])(.*)$")
	if not host then
		host, port = string.match(authority, "^([%w.%-]+)(.*)$")
	end
	if not host or (port ~= "" and not string.match(port or "", "^:%d+$")) then
		return string.lower(scheme), nil, nil, tail
	end
	return string.lower(scheme), string.lower(host), if port ~= "" then string.sub(port :: string, 2) else nil, tail
end

-- What is typed, as the address to load, or why it is not one.
function M.normalize(input: string): (string?, string?)
	local text = trim(input)
	if text == "" then
		return nil, "Enter a website or localhost address."
	end
	if string.find(text, "%c") then
		return nil, "This address contains invalid characters."
	end
	-- A bare host:port reads as a scheme to a URL parser: only a numeric
	-- port settles it.
	local authority = string.match(text, "^([^/?#]*)") or text
	local host_port = string.match(authority, ":(%d+)$") ~= nil
	local explicit = string.find(text, "://", 1, true) ~= nil
		or (string.find(text, ":", 1, true) ~= nil and not host_port and string.sub(text, 1, 1) ~= "[")
	local url = if explicit then text else `https://{text}`
	if string.find(url, "%s") then
		return nil, "Enter a valid website or localhost address."
	end
	local scheme, host, port, tail = parts(url)
	if host == "@" then
		return nil, "Use an address without an embedded username or password."
	end
	if scheme == "http" or scheme == "https" then
		if not host then
			return nil, "Enter a valid website or localhost address."
		end
	elseif scheme == nil then
		return nil, "Enter a valid website or localhost address."
	else
		return nil, "Only http and https addresses are supported."
	end
	local s = scheme :: string
	if not explicit and M.loopback(host :: string) then
		s = "http"
	end
	local default = (s == "http" and port == "80") or (s == "https" and port == "443")
	local at = if port and not default then `{host}:{port}` else host :: string
	local path = tail or ""
	if path == "" or string.sub(path, 1, 1) ~= "/" then
		path = "/" .. path
	end
	return `{s}://{at}{path}`, nil
end

-- Where a page may go (model.rs allowed_navigation and
-- allowed_frame_navigation): a web address with a host and no
-- credentials; a frame also to a document of its own (about:blank,
-- about:srcdoc, data:, blob:), never a scheme that leaves the page.
function M.allowed(r: { url: string, main_frame: boolean }): boolean
	local scheme, host = parts(r.url)
	if (scheme == "http" or scheme == "https") and host ~= nil and host ~= "@" then
		return true
	end
	return not r.main_frame and (scheme == "about" or scheme == "data" or scheme == "blob")
end

-- Whether `url` is this device's own (a loopback address), not a
-- preview of another device's dev server through the engine's proxy
-- (`*.localhost` on PREVIEW_PROXY_PORT).
local PREVIEW_PROXY_PORT = "7331"
function M.local_only(url: string): boolean
	local scheme, host, port = parts(url)
	if not (scheme == "http" or scheme == "https") or not host or host == "@" then
		return false
	end
	if port == PREVIEW_PROXY_PORT and string.sub(host, -10) == ".localhost" then
		return false
	end
	return M.loopback(host)
end

-- The website data a workspace's pages share (profile.rs): this device's
-- for a local workspace, the account's for a synced one.
local function profile(): string
	local a = account.account:peek()
	return if a.scope == "local" then `zeron:local:{data.THIS}` else `zeron:{a.scope}:{a.email}`
end

-- The device the window's session runs on, when it is not this one: its
-- localhost is not the page's.
function M.remote(): string?
	local session = if state.tabbed_now() then state.pane_session:get() else state.session:get()
	return data.ELSEWHERE[session]
end

-- The page's icon (macos.rs discover_favicon): its `<link rel=icon>`, or
-- the site's /favicon.ico.
local FAVICON = "(() => { const link = document.querySelector('link[rel~=icon]'); "
	.. "return link ? link.href : new URL('/favicon.ico', location.href).href; })()"

-- A tab's label: the page's title, or its host, or "Browser".
function M.label(title: string, url: string): string
	local t = trim(title)
	if t ~= "" then
		return t
	end
	local _, host = parts(url)
	return if host and host ~= "@" then string.gsub(host, "^%[(.*)%]$", "%1") else "Browser"
end

-- ---- a tab -----------------------------------------------------------------

type Tab = {
	web: Web,
	-- What the address field holds; what was typed until it goes.
	address: State<string>,
	focused: State<boolean>,
	-- Why the address typed is not one ("" when it is).
	invalid: State<string>,
	-- Where pages are not the window's own: what was opened in the
	-- system's browser.
	opened: State<string>,
	field: Ref,
	-- Annotating: the pick's nonce while one is under way, the picks it
	-- took, the draft they went to and each chip's marker on the page.
	annotating: State<boolean>,
	pick: { nonce: number, picks: number, draft: State<string>? },
	marks: State<{ number }>,
	-- Its page's icon, once found ("" until then).
	favicon: State<string>,
}
local tabs: { [string]: Tab } = {}

local function tab(id: string): Tab
	local t = tabs[id]
	if not t then
		t = {
			web = ui.web(`zweb:{id}`, { profile = profile() }),
			address = ui.state(`zweb_address:{id}`, ""),
			focused = ui.state(`zweb_focused:{id}`, false),
			invalid = ui.state(`zweb_invalid:{id}`, ""),
			opened = ui.state(`zweb_opened:{id}`, ""),
			field = ui.ref(),
			annotating = ui.state(`zweb_annotating:{id}`, false),
			pick = { nonce = 0, picks = 0, draft = nil :: State<string>? },
			marks = ui.state(`zweb_marks:{id}`, {} :: { number }),
			favicon = ui.state(`zweb_favicon:{id}`, ""),
		}
		tabs[id] = t
	end
	return t :: Tab
end

-- The page's address, embedded or opened outside.
local function url(t: Tab): string
	return if M.native() then t.web.url else t.opened:get()
end
local function url_now(t: Tab): string
	return if ui.native:peek().web then t.web.url else t.opened:peek()
end

function M.title(id: string): () -> string
	local t = tab(id)
	return function()
		return M.label(if M.native() then t.web.title else "", url(t))
	end
end

-- Its page's icon, "" while it has none.
function M.favicon(id: string): () -> string
	local t = tab(id)
	return function()
		return if M.native() then t.favicon:get() else ""
	end
end

-- A page loaded: its icon, if it is still the page shown and a web
-- address.
local function find_icon(t: Tab, page: string)
	t.web:eval(FAVICON, function(value: any)
		if type(value) == "string" and t.web.url == page and M.allowed { url = value, main_frame = true } then
			t.favicon:set(value)
		end
	end)
end

function M.loading(id: string): () -> boolean
	local t = tab(id)
	return function()
		return M.native() and t.web.loading and t.web.error == nil
	end
end

-- Go to what was typed, or say why it is not an address.
function M.navigate(id: string, input: string)
	local t = tab(id)
	local to, why = M.normalize(input)
	if not to then
		t.invalid:set(why or "")
		return
	end
	t.invalid:set("")
	t.address:set(to)
	if ui.native:peek().web then
		t.web:load(to)
		t.web:focus()
	else
		t.opened:set(to)
		ui.open_url(to)
	end
end

function M.focus_address(id: string)
	local el = tab(id).field:get()
	if el then
		el:focus()
	end
end

function M.reload(id: string)
	local t = tab(id)
	if not ui.native:peek().web then
		local at = t.opened:peek()
		if at ~= "" then
			ui.open_url(at)
		end
	elseif t.web.error ~= nil and t.web.url ~= "" then
		t.web:load(t.web.url)
	else
		t.web:reload()
	end
end

-- Whether the tab's page or its address has the keyboard (Zeron's
-- "Browser" key context): ⌘[ and ⌘] step its history then.
function M.has_focus(id: string): boolean
	local t = tabs[id]
	return t ~= nil and (t.focused:peek() or (ui.native:peek().web and t.web.focused))
end

function M.back(id: string)
	tab(id).web:back()
end

function M.forward(id: string)
	tab(id).web:forward()
end

function M.open_outside(id: string)
	local t = tab(id)
	local at = if ui.native:peek().web then t.web.url else t.opened:peek()
	if at ~= "" then
		ui.open_url(at)
	end
end

-- ---- annotating (browser/mod.rs) ------------------------------------------

-- Annotation needs an embedded, loaded page.
local function can_annotate(t: Tab): boolean
	return M.native() and t.web.url ~= "" and t.web.error == nil
end

-- The overlay's palette and type, so the page's chrome reads as Zeron's.
local function palette(): string
	local function css(token: string): string
		return string.format("%q", tostring(ui.theme.get(token)))
	end
	return `\{"accent":{css("accent")},"surface":{css("popover.bg")},"border":{css("border")},`
		.. `"text":{css("text.primary")},"muted":{css("text.secondary")},"faint":{css("text.tertiary")},`
		.. `"chip":{css("zeron.ink.3")},"font":{css("font.sans")},"dark":{if ui.theme.kind() == "dark"
			then "true"
			else "false"}}`
end

function M.stop_annotating(id: string)
	local t = tabs[id]
	if not t or not t.annotating:peek() then
		return
	end
	t.pick.nonce = 0
	t.annotating:set(false)
	t.web:run("(() => { window.__zeronAnnotator?.stop(); return 'stopped'; })()")
end

function M.annotate(id: string)
	local t = tab(id)
	if t.annotating:peek() then
		M.stop_annotating(id)
		return
	end
	if not can_annotate(t) then
		return
	end
	-- Below 2^31, so the page's numbers hold it exactly.
	local nonce = math.random(1, 2 ^ 31 - 1)
	local draft = state.hooks.draft
	t.pick = { nonce = nonce, picks = 0, draft = if draft then draft(state.session:peek()) else nil }
	t.annotating:set(true)
	t.web:run(`{annotate.SCRIPT}\n;window.__zeronAnnotator.start({nonce}, {palette()}); 'started'`)
end

-- What the page posted: picks of the pick under way (its nonce, from the
-- top frame), each a chip in the draft, its marker numbered as the chip; a
-- pick ended by the page (a click without Shift, Escape) or the cap ends.
local function on_message(id: string, value: any, main_frame: boolean)
	local t = tabs[id]
	if
		not t
		or not main_frame
		or type(value) ~= "table"
		or value.zeron ~= "annotate"
		or value.nonce ~= t.pick.nonce
		or t.pick.nonce == 0
	then
		return
	end
	local draft = t.pick.draft
	if draft and type(value.picks) == "table" then
		for _, pick in value.picks do
			if t.pick.picks >= annotate.MAX_PICKS then
				break
			end
			t.pick.picks += 1
			local n = annotate.add(draft, annotate.bounded(pick))
			local marker = if type(pick) == "table" and type(pick.marker) == "number" then pick.marker else 0
			t.web:run(`(() => \{ window.__zeronAnnotator?.label({math.floor(marker)}, {n}); return 'ok'; })()`)
			t.marks:push(n)
		end
	end
	if value.state ~= "active" then
		t.pick.nonce = 0
		t.annotating:set(false)
	elseif t.pick.picks >= annotate.MAX_PICKS then
		M.stop_annotating(id)
	end
end

-- Markers stay while their chips do: a chip taken out of the draft takes
-- its marker off the page. Read only while the page has some.
local function keep_marks(t: Tab)
	ui.effect(function()
		local marks = t.marks:get()
		local draft = t.pick.draft
		if #marks == 0 or not draft then
			return
		end
		local kept = annotate.numbers(draft:get())
		local still: { number } = {}
		for _, n in marks do
			if table.find(kept, n) then
				table.insert(still, n)
			end
		end
		if #still ~= #marks then
			t.marks:set(still)
			t.web:run(`(() => \{ window.__zeronAnnotator?.keep([{table.concat(still, ",")}]); return 'ok'; })()`)
		end
	end)
end

-- Ends tab `id`'s page.
function M.close(id: string)
	local t = tabs[id]
	if t then
		t.web:close()
		tabs[id] = nil
	end
end

-- The dev servers the project runs (the engine's WatchPreviews).
local SERVICES: { browser_kit.Service } = data.PREVIEWS

local function body(id: string, t: Tab, new_window: ((url: string) -> ())?, previews: boolean): Node
	return ui.presence(function()
		if url(t) == "" then
			return if previews then "new" elseif M.native() then "empty" else "empty_outside"
		elseif not M.native() then
			return "outside"
		elseif t.web.error ~= nil then
			return "error"
		end
		return "page"
	end, function(what: string): Node
		if what == "new" then
			return kit.browser.previews {
				id = `{id}_previews`,
				services = SERVICES,
				on_open = function(to: string)
					M.navigate(id, to)
				end,
				on_address = function()
					M.focus_address(id)
				end,
			}
		elseif what == "page" then
			-- Until the page's view exists (WebView2 makes it a moment
			-- later), the tab says it is starting.
			return ui.column {
				relative = true,
				grow = 1,
				w_full = true,
				min_h = 0,
				items = "stretch",
				ui.webview {
					id = `{id}_page`,
					web = t.web,
					grow = 1,
					w_full = true,
					min_h = 0,
					bg = T.bg,
					navigation = M.allowed,
					on_new_window = new_window,
					on_message = function(value: any, _origin: string, main_frame: boolean)
						on_message(id, value, main_frame)
					end,
					-- A new page, a new icon.
					on_navigate = function(e: WebEvent)
						if e.kind == "started" and t.favicon:peek() ~= "" then
							t.favicon:set("")
						end
					end,
					on_load = function(page: string)
						find_icon(t, page)
					end,
				},
				ui.show(
					function()
						return not t.web.attached
					end,
					ui.column {
						absolute = true,
						top = 0,
						left = 0,
						right = 0,
						bottom = 0,
						items = "center",
						justify = "center",
						bg = T.bg,
						kit.browser.empty {
							id = `{id}_starting`,
							title = "Starting browser…",
							body = "You can keep working while your page opens.",
						},
					}
				),
			}
		end
		local failed = what == "error"
		local empty = what == "empty" or what == "empty_outside"
		return ui.column {
			grow = 1,
			w_full = true,
			items = "center",
			justify = "center",
			kit.browser.empty {
				id = `{id}_empty`,
				title = if failed
					then "Couldn’t load this page"
					elseif empty then "Preview your work"
					else "Opened in your browser",
				body = if failed
					then function()
						return t.web.error or ""
					end
					elseif what == "empty" then "Preview your local app or keep a website beside your conversation."
					else "Open a website or local app in your default browser. Embedded browsing is available on macOS.",
				action = if failed then "Try again" else "Enter an address",
				action_id = `{id}_action`,
				hint = if failed then nil else ui.shortcut_text("cmd+l"),
				on_action = function()
					if failed then
						M.reload(id)
					else
						M.focus_address(id)
					end
				end,
			},
		}
	end, { grow = 1, w_full = true, min_h = 0, items = "stretch" })
end

-- Tab `id`'s surface: the toolbar, why an address is not one, the page.
-- `new_window`: where a link the page opens in a new window goes. A tab
-- outside a session (`previews` false) has no dev servers to offer.
function M.surface(id: string, new_window: ((url: string) -> ())?, previews: boolean?): Node
	local t = tab(id)
	local web = t.web
	keep_marks(t)
	local function has_page(): boolean
		return url(t) ~= ""
	end
	-- What the page shows goes into the field unless it is being edited.
	ui.effect(function()
		local at = url(t)
		if not t.focused:peek() and t.address:peek() ~= at then
			t.address:set(at)
		end
	end)
	local function on_key(e: KeyEvent): boolean
		if e.meta or e.ctrl or e.alt then
			return false
		end
		if e.key == "Enter" and not e.shift then
			M.navigate(id, t.address:peek())
			return true
		elseif e.key == "Escape" and t.annotating:peek() then
			M.stop_annotating(id)
			return true
		elseif e.key == "Escape" then
			t.address:set(url_now(t))
			t.invalid:set("")
			if ui.native:peek().web and web.url ~= "" then
				web:focus()
			end
			return true
		end
		return false
	end
	local external = not ui.native:peek().web
	return ui.column {
		id = `preview_{id}`,
		w_full = true,
		h_full = true,
		items = "stretch",
		-- Escape ends a pick while the page is not the one listening.
		on_key = function(e: KeyEvent): boolean
			if e.key == "Escape" and t.annotating:peek() then
				M.stop_annotating(id)
				return true
			end
			return false
		end,
		kit.browser.toolbar {
			id = `{id}_bar`,
			value = t.address,
			external = external,
			address_ref = t.field,
			-- A new tab waits for an address.
			autofocus = url_now(t) == "",
			can_back = function()
				return web.can_go_back
			end,
			can_forward = function()
				return web.can_go_forward
			end,
			has_page = has_page,
			invalid = function()
				return t.invalid:get() ~= ""
			end,
			editing = function()
				return t.focused:get() or t.address:get() ~= url(t)
			end,
			on_key = on_key,
			on_focus = function()
				t.focused:set(true)
			end,
			on_blur = function()
				t.focused:set(false)
			end,
			on_go = function()
				M.navigate(id, t.address:peek())
			end,
			on_back = function()
				web:back()
			end,
			on_forward = function()
				web:forward()
			end,
			on_reload = function()
				M.reload(id)
			end,
			on_open = function()
				M.open_outside(id)
			end,
			annotating = t.annotating,
			can_annotate = function()
				return can_annotate(t)
			end,
			on_annotate = function()
				M.annotate(id)
			end,
		},
		-- Where the system keeps no store of the app's own (macOS before 14).
		ui.show(
			function()
				return ui.native:get().temporary_stores
			end,
			kit.text.text {
				"Logins are temporary on this macOS version. Use macOS 14 or later, or open this page in your default browser, to keep them.",
				id = `{id}_temporary`,
				size = "xs",
				color = T.secondary,
				wrap = true,
				px = "$zeron.space.12",
				py = "$zeron.space.8",
			}
		),
		ui.show(
			function()
				return t.invalid:get() ~= ""
			end,
			kit.text.text {
				function()
					return t.invalid:get()
				end,
				id = `{id}_invalid`,
				size = "xs",
				color = T.danger,
				px = "$zeron.space.12",
				py = "$zeron.space.8",
			}
		),
		-- On another device's session, localhost is this device's (view.rs).
		ui.show(
			function()
				return M.remote() ~= nil and M.local_only(url(t))
			end,
			ui.div {
				id = `{id}_remote_loopback`,
				px = "$zeron.space.12",
				py = "$zeron.space.8",
				border_sides = { 0, 0, 1, 0 },
				border_color = T.border,
				kit.text.text {
					"Localhost opens on this device. Open a detected preview from a new tab to reach your other device.",
					size = "xs",
					color = T.secondary,
					wrap = true,
				},
			}
		),
		ui.column { grow = 1, min_h = 0, w_full = true, items = "stretch", body(id, t, new_window, previews ~= false) },
		external and ui.row {
			h = 26,
			shrink = 0,
			px = "$zeron.space.10",
			gap = "$zeron.space.5",
			items = "center",
			border_sides = { 1, 0, 0, 0 },
			border_color = T.border,
			kit.icon { name = "arrow-up-right", size = 11, color = T.tertiary },
			kit.text.text { "Opens in your default browser", size = "micro", color = T.tertiary, line = false },
		} or nil,
	}
end

return M
