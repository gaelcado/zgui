-- Settings search (settings/search.rs, search/reveal.rs,
-- shell/settings_search.rs; v0.2.129): the field under Back finds any
-- setting on any page, a page by its name or a shortcut by its action, and
-- lists the hits in the sections' place: each under its page's glyph, the
-- match lit in its title, a setting over its page and block, a shortcut
-- with its binding; "No matching settings" when none. ⌘F reaches the field;
-- ↑↓ walk the hits, Enter or a click opens one: its page, glided to its row,
-- which glows a moment. Escape clears the query first.
--
-- Ranking follows the palette's: every word must match a field, weighted
-- by the field (the title, words kept for the row, its block, its page),
-- half again where it starts a word, and a whole-title match on top. A
-- word no entry spells may find a title or page word it misspells (within
-- one edit up to seven letters, two from eight), below every real match.
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local kbd = require("./kbd")
local wash = require("./wash")
local recipes = require("./recipes")
local motion = require("./motion")
local settings = require("./settings")
local keymap = require("./keymap")

local M = {}

-- Field weights, per query word.
local TITLE, TERMS, GROUP, PAGE = 100, 40, 30, 20
local EXACT = TITLE
local TYPO = 10

-- A row the search lands on: its anchor (`settings.row { anchor }`), page,
-- the block it sits in, its title, the words people search by that the
-- title lacks; where to land while it hides (its parent's row, or nil:
-- the page's top).
type Row = { anchor: string, section: string, group: string?, title: string, terms: string, parent: string? }
local function row(anchor: string, section: string, group: string?, title: string, terms: string, parent: string?): Row
	return { anchor = anchor, section = section, group = group, title = title, terms = terms, parent = parent }
end

-- The index, each page top to bottom (search.rs settings_index).
M.ROWS = {
	row("send_messages_with", "general", nil, "Send messages with", "enter return submit modifier keyboard composer"),
	row("compact_mode", "general", nil, "Compact mode", "collapse thinking tools transcript dense density"),
	row("compact_model_picker", "general", nil, "Compact model picker", "effort reasoning slider model list"),
	row("escape_stops", "general", nil, "Stop agent with Escape", "esc interrupt cancel halt run keyboard"),
	row("open_prs", "general", "Links", "Open pull requests in", "pr pull request badges board browser github"),
	row("thread_naming", "general", nil, "Thread naming", "titles rename sessions model"),
	row("worktree_location", "general", "Git", "Custom worktree location", "folder directory path checkout branches"),
	row(
		"commit_credit",
		"general",
		"Git",
		"Credit Zeron in commits",
		"co-author coauthor attribution bot commit message"
	),
	row("color_scheme", "appearance", nil, "Color scheme", "system light dark mode"),
	row("light_theme", "appearance", nil, "Light theme", "palette colors"),
	row("dark_theme", "appearance", nil, "Dark theme", "palette colors"),
	row("accent_color", "appearance", nil, "Accent color", "tint highlight swatch"),
	row("wallpaper_colors", "appearance", nil, "Match wallpaper colors", "tint accent surface desktop"),
	row(
		"glass",
		"appearance",
		"Material and background",
		"Glass",
		"frosted translucent opaque transparency blur vibrancy surface"
	),
	row(
		"double_border",
		"appearance",
		"Material and background",
		"Double border",
		"rim hairline outline panels panes wells"
	),
	row(
		"new_thread_background",
		"appearance",
		"Material and background",
		"New thread background",
		"image picture wallpaper composer"
	),
	row(
		"wallpaper_folder",
		"appearance",
		"Material and background",
		"Wallpaper folder",
		"random shuffle images directory"
	),
	row(
		"background_effect",
		"appearance",
		"Material and background",
		"Background effect",
		"blur dim image",
		"new_thread_background"
	),
	row("layout", "appearance", "Material and background", "Layout", "classic glass tabs sidebar panes window"),
	row("reduce_motion", "appearance", "Motion", "Reduce motion", "animations accessibility"),
	row(
		"pause_animations",
		"appearance",
		"Motion",
		"Pause animations in background",
		"focus unfocused inactive window battery"
	),
	row("smooth_scrolling", "appearance", "Motion", "Smooth scrolling", "mouse wheel glide ease"),
	row("theme_library", "appearance", nil, "Theme library", "import add custom themes"),
	row("interface_font", "appearance", "Fonts and layout", "Interface font", "typeface text size menus conversations"),
	row("terminal_font", "appearance", "Fonts and layout", "Terminal font", "monospace typeface size"),
	row("code_font", "appearance", "Fonts and layout", "Code & diff font", "monospace typeface editor files size"),
	row(
		"conversation_width",
		"appearance",
		"Fonts and layout",
		"Conversation width",
		"transcript messages composer column maximum"
	),
	row("render_math", "appearance", "Fonts and layout", "Render math", "latex formulas equations markdown typeset"),
	row("math_font", "appearance", "Fonts and layout", "Math font", "latex formulas typeface"),
	row("math_size", "appearance", "Fonts and layout", "Math size", "latex formulas scale"),
	row("desktop_notifications", "notifications", "Desktop", "Desktop notifications", "alerts banners system"),
	row("agent_updates", "notifications", "Desktop", "Agent updates", "cli banner new version"),
	row("background_only", "notifications", "Desktop", "Only when in the background", "focus unfocused"),
	row("session_sounds", "notifications", "Sounds", "Session sounds", "audio chime mute"),
	row("task_completed", "notifications", "Sounds", "Task completed", "done finished audio sound"),
	row("input_required", "notifications", "Sounds", "Input required", "question waiting approval audio sound"),
	row("error_sound", "notifications", "Sounds", "Errors and disconnections", "failure offline audio sound"),
	row("codex_voice_device", "voice", nil, "Codex voice device", "remote host machine"),
	row("codex_voice_style", "voice", nil, "Codex voice style", "speech tone"),
	row("dictation", "voice", nil, "Dictation", "speech to text transcribe talk"),
	row("microphone", "voice", nil, "Microphone", "input audio mic", "dictation"),
	row("speech_model", "voice", nil, "Speech model", "parakeet download remove", "dictation"),
	row("skill_dollar", "harnesses", "Completion", "Use $ for skills", "dollar skill picker composer autocomplete"),
	row("skill_slash", "harnesses", "Completion", "Separate / commands", "slash menu skills autocomplete"),
	row("native_subagents", "harnesses", "Delegation", "Native subagents", "subagent delegate side chats tasks spawn"),
	row("update_policy", "harnesses", "Updates", "Update policy", "automatic upgrade version cli"),
	row("cloud_usage", "cloud", nil, "Usage", "hours consumption range"),
	row("cloud_github", "cloud", nil, "GitHub", "connect repositories account"),
	row("credits", "billing", nil, "Credits", "balance"),
	row("plan", "billing", nil, "Plan", "subscription upgrade manage stripe"),
	row("extra_credits", "billing", nil, "Extra credits", "buy packs top up"),
	row("autosave", "files", nil, "Autosave", "save automatically"),
	row("autosave_delay", "files", nil, "Autosave delay", "debounce wait", "autosave"),
	row("word_wrap", "files", nil, "Word wrap", "soft wrap long lines editor"),
	row("show_all_files", "files", nil, "Show hidden and ignored files", "dotfiles gitignore tree"),
	row("capture_appshots", "appshots", nil, "Capture Appshots", "screenshot screen"),
	row("appshot_sound", "appshots", nil, "Capture sound", "shutter audio"),
	row("appshot_destination", "appshots", nil, "Destination", "session composer where"),
	row("window_capture", "appshots", nil, "Window capture", "screen recording permission"),
	row("application_text", "appshots", nil, "Application text", "accessibility semantic permission"),
} :: { Row }

-- A provider's own rows show once it is opened: until then, its page.
local PER_PROVIDER = { skill_dollar = true, skill_slash = true, native_subagents = true, update_policy = true }

-- Shortcuts recorded on a feature page rather than on Shortcuts.
local FEATURED: { [string]: { section: string, title: string, terms: string } } = {
	toggle_dictation = {
		section = "voice",
		title = "Dictation shortcut",
		terms = "hold to dictate talk keybinding hotkey",
	},
	capture_appshot = {
		section = "appshots",
		title = "Global shortcut",
		terms = "capture appshot screenshot preferred keybinding hotkey",
	},
}

-- What a page is also called, and what it holds that has no row.
local PAGE_TERMS: { [string]: string } = {
	general = "preferences composer conversations behavior",
	appearance = "theme look colors fonts",
	notifications = "alerts sounds banners",
	voice = "speech dictation microphone codex",
	shortcuts = "keyboard keybindings hotkeys keys",
	harnesses = "harnesses agents cli claude code codex cursor devin grok hermes pi opencode antigravity muse install enable disable update policy accounts sign in login",
	devices = "machines computers remote this device other devices rename",
	cloud = "machine remote github repositories usage",
	billing = "plan credits subscription payment stripe",
	files = "editor autosave wrap hidden",
	appshots = "screenshots capture permissions",
	archived = "archive unarchive restore delete sessions threads",
}

-- One thing the search returns: a row, a shortcut or a page. `anchor`:
-- what it lands on ("" for a page's top); `binding`: a shortcut's.
export type Section = { id: string, title: string, icon: string }
export type Entry = {
	-- "page", "setting" or "shortcut".
	kind: string,
	section: Section,
	group: string?,
	title: string,
	terms: string,
	anchor: string,
	fallback: string?,
	binding: string?,
}
type Indexed = { entry: Entry, title: string, terms: string, group: string, page: string, at: number }
export type Hit = { entry: Entry, ranges: { { number } } }

-- Every entry in nav order: each page, its rows, then its shortcuts.
local function index(sections: { Section }, km: keymap.Keymap): { Indexed }
	local entries: { Entry } = {}
	for _, s in sections do
		table.insert(entries, {
			kind = "page",
			section = s,
			title = s.title,
			terms = PAGE_TERMS[s.id] or "",
			anchor = "",
		})
		for _, r in M.ROWS do
			if r.section == s.id then
				table.insert(entries, {
					kind = "setting",
					section = s,
					group = r.group,
					title = r.title,
					terms = r.terms,
					anchor = r.anchor,
					fallback = r.parent or (if PER_PROVIDER[r.anchor] then "" else nil),
				})
			end
		end
		for _, b in km.bindings do
			local featured = FEATURED[b.id]
			if (featured and featured.section == s.id) or (not featured and s.id == "shortcuts") then
				table.insert(entries, {
					kind = "shortcut",
					section = s,
					group = if featured then nil else b.group,
					title = if featured then featured.title else b.label,
					terms = if featured then featured.terms else "shortcut keybinding hotkey",
					anchor = `shortcut:{b.id}`,
					binding = b.id,
				})
			end
		end
	end
	local out: { Indexed } = {}
	for i, e in entries do
		table.insert(out, {
			entry = e,
			title = string.lower(e.title),
			terms = string.lower(e.terms),
			group = string.lower(e.group or ""),
			page = string.lower(e.section.title),
			at = i,
		})
	end
	return out
end

local function starts_word(field: string, at: number): boolean
	return at == 1 or string.match(string.sub(field, at - 1, at - 1), "%w") == nil
end
-- `weight` for a match, plus half again where one starts a word.
local function field_score(field: string, word: string, weight: number): number?
	local best: number? = nil
	local from = 1
	while true do
		local at = string.find(field, word, from, true)
		if not at then
			return best
		end
		if starts_word(field, at) then
			return weight + weight // 2
		end
		best = weight
		from = at + 1
	end
end
-- Where `word` shows in `title`: where it starts a word, else first.
local function title_match(title: string, word: string): { number }?
	local first: { number }? = nil
	local from = 1
	while true do
		local at = string.find(title, word, from, true)
		if not at then
			return first
		end
		if starts_word(title, at) then
			return { at, at + #word - 1 }
		end
		first = first or { at, at + #word - 1 }
		from = at + 1
	end
end
-- Optimal string alignment distance (a swap of neighbours counts once),
-- or nil past `budget`.
local function distance(a: string, b: string, budget: number): number?
	if math.abs(#a - #b) > budget then
		return nil
	end
	-- d[i + 1][j + 1]: the distance between a's first i and b's first j.
	local d: { { number } } = {}
	for i = 1, #a + 1 do
		d[i] = { i - 1 }
	end
	for j = 1, #b + 1 do
		d[1][j] = j - 1
	end
	for i = 1, #a do
		local least = i
		for j = 1, #b do
			local cost = if string.byte(a, i) == string.byte(b, j) then 0 else 1
			local cell = math.min(d[i][j + 1] + 1, d[i + 1][j] + 1, d[i][j] + cost)
			if
				i > 1
				and j > 1
				and string.byte(a, i) == string.byte(b, j - 1)
				and string.byte(a, i - 1) == string.byte(b, j)
			then
				cell = math.min(cell, d[i - 1][j - 1] + 1)
			end
			d[i + 1][j + 1] = cell
			least = math.min(least, cell)
		end
		if least > budget then
			return nil
		end
	end
	local total = d[#a + 1][#b + 1]
	return if total <= budget then total else nil
end
-- The word of `field` that `word` misspells, whole or as far as typed.
local function misspelled(field: string, word: string): { number }?
	local budget = if #word <= 3 then 0 elseif #word <= 7 then 1 else 2
	if budget == 0 then
		return nil
	end
	local from = 1
	while true do
		local s, e = string.find(field, "%w+", from)
		if not s or not e then
			return nil
		end
		local candidate = string.sub(field, s, e)
		for _, len in { #candidate, #word - 1, #word, #word + 1 } do
			if len <= #candidate and len > 0 and distance(word, string.sub(candidate, 1, len), budget) then
				return { s, e }
			end
		end
		from = e + 1
	end
end
local function merged(ranges: { { number } }): { { number } }
	table.sort(ranges, function(a: { number }, b: { number }): boolean
		return a[1] < b[1]
	end)
	local out: { { number } } = {}
	for _, r in ranges do
		local last = out[#out]
		if last and r[1] <= last[2] + 1 then
			last[2] = math.max(last[2], r[2])
		else
			table.insert(out, { r[1], r[2] })
		end
	end
	return out
end

-- The hits for `query` among `sections`' pages, best first; none for a
-- blank query.
function M.search(query: string, sections: { Section }, km: keymap.Keymap): { Hit }
	local words: { string } = {}
	for w in string.gmatch(string.lower(query), "%S+") do
		table.insert(words, w)
	end
	if #words == 0 then
		return {}
	end
	local all = index(sections, km)
	local typo: { boolean } = {}
	for i, w in words do
		local spelled = false
		for _, x in all do
			if
				string.find(x.title, w, 1, true)
				or string.find(x.terms, w, 1, true)
				or string.find(x.group, w, 1, true)
				or string.find(x.page, w, 1, true)
			then
				spelled = true
				break
			end
		end
		typo[i] = not spelled
	end
	local whole = table.concat(words, " ")
	type Scored = { score: number, page: boolean, at: number, hit: Hit }
	local scored: { Scored } = {}
	for _, x in all do
		local total = 0
		local ranges: { { number } } = {}
		local ok = true
		for i, w in words do
			local best: number? = nil
			for _, f in { { x.title, TITLE }, { x.terms, TERMS }, { x.group, GROUP }, { x.page, PAGE } } :: { { any } } do
				local s = field_score(f[1], w, f[2])
				if s and (best == nil or s > best) then
					best = s
				end
			end
			if best then
				total += best
				local r = title_match(x.title, w)
				if r then
					table.insert(ranges, r)
				end
			elseif typo[i] then
				local r = misspelled(x.title, w)
				if not r and not misspelled(x.page, w) then
					ok = false
					break
				end
				if r then
					table.insert(ranges, r)
				end
				total += TYPO
			else
				ok = false
				break
			end
		end
		if ok then
			if x.title == whole then
				total += EXACT
			end
			table.insert(scored, {
				score = total,
				page = x.entry.kind == "page",
				at = x.at,
				hit = { entry = x.entry, ranges = merged(ranges) },
			})
		end
	end
	-- Equal scores: a page before the rows it holds, then nav order.
	table.sort(scored, function(a: Scored, b: Scored): boolean
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.page ~= b.page then
			return a.page
		end
		return a.at < b.at
	end)
	local out: { Hit } = {}
	for _, s in scored do
		table.insert(out, s.hit)
	end
	return out
end

-- Landing (search/reveal.rs): the page's scroll, its content and the band
-- above it, as the page mounts them; the lit row's glow.
local view = {
	offset = nil :: State<number>?,
	content = nil :: Element?,
	frame = nil :: Element?,
	top = nil :: Element?,
}
function M.page_offset(offset: State<number>)
	view.offset = offset
end
function M.mount(part: "content" | "frame" | "top"): (el: Element) -> ()
	return function(el: Element)
		view[part] = el
	end
end
-- The glow's box in the page's content, and the anchor it lights.
M.glow_box = ui.state("settings_glow_box", { x = 0, y = 0, w = 0, h = 0 })
M.lit = ui.state("settings_search_lit", "")

local SEEK_LIMIT = 1500
local CLEARANCE = 24
local LANDING = 0.3
local BLEED = 8
local glide: any = nil

local function glow(anchor: string)
	M.lit:set(anchor)
	anime.animate("#settings_glow", {
		opacity = {
			{ to = 1, duration = motion.d(motion.FAST), ease = motion.EASE_OUT },
			{ to = 1, duration = motion.d(900) },
			{ to = 0, duration = motion.d(600), ease = motion.EASE },
		},
	})
end

-- Land on `anchor` (or `fallback` while it hides; "" the page's top) once
-- its page has laid it out: glide it into view a third of the way down,
-- unless it shows already, then light it.
function M.reveal(anchor: string, fallback: string?)
	local asked = ui.now()
	local function seek()
		local el = settings.anchors[anchor]
		local lit = anchor
		if not (el and el.mounted and el.y) and fallback and fallback ~= "" then
			el = settings.anchors[fallback]
			lit = fallback
		end
		local content, frame, top, offset = view.content, view.frame, view.top, view.offset
		-- Laid out, not just mounted: a row has its size once a layout ran.
		local laid = el
			and el.mounted
			and el.y
			and (el.width or 0) > 0
			and content
			and content.mounted
			and content.y
			and frame
			and top
		if not laid then
			if ui.now() - asked < SEEK_LIMIT then
				ui.after(16, seek)
			end
			return
		end
		local e, c, f, t = el :: Element, content :: Element, frame :: Element, top :: Element
		local scrolled = if offset then offset:peek() else 0
		local view_top = (t.y :: number) + (t.height :: number)
		local height = (f.y :: number) + (f.height :: number) - view_top
		local row_top = (e.y :: number) - (c.y :: number)
		local row_h = e.height :: number
		local shown_top = row_top - scrolled
		M.glow_box:set {
			x = (e.x :: number) - (c.x :: number) + BLEED,
			y = row_top,
			w = (e.width :: number) - 2 * BLEED,
			h = row_h,
		}
		if offset and not (shown_top >= CLEARANCE and shown_top + row_h <= height - CLEARANCE) then
			local land = math.max(math.min(height * LANDING, height - CLEARANCE - row_h), CLEARANCE)
			local to = math.clamp(row_top - land, 0, math.max(0, (c.height :: number) - height))
			if glide then
				glide:cancel()
			end
			glide = (anime.animate :: any)(offset, {
				value = to,
				duration = motion.d(motion.SCROLL_GLIDE),
				ease = motion.EASE_IN_OUT,
				onComplete = function()
					glide = nil
					glow(lit)
				end,
			})
		else
			glow(lit)
		end
	end
	ui.after(0, seek)
end

-- The glow under a landed row: the accent's wash, 8 into its block's inset.
function M.glow(): Node
	return ui.div {
		id = "settings_glow",
		absolute = true,
		left = function()
			return M.glow_box:get().x
		end,
		top = function()
			return M.glow_box:get().y
		end,
		w = function()
			return M.glow_box:get().w
		end,
		h = function()
			return M.glow_box:get().h
		end,
		rounded = "$zeron.radius.8",
		bg = T.accent_wash,
		opacity = 0,
		pointer_events = "none",
	}
end

-- The field and its hits, for a settings page whose sections are
-- `sections()` and whose chosen one is `section`.
export type Props = {
	sections: () -> { Section },
	section: State<string>,
	keymap: keymap.Keymap,
}
M.query = ui.state("settings_search_query", "")
M.active = ui.state("settings_search_active", 1)
local field: Element? = nil

-- ⌘F: the field, its query selected so typing replaces it.
function M.focus()
	local el = field
	if el and el.mounted then
		el:focus()
		el:select_all()
	end
end
-- Settings left: the next visit starts from the sections.
function M.reset()
	M.query:set("")
	M.active:set(1)
	M.lit:set("")
end
function M.searching(): boolean
	return string.match(M.query:get(), "%S") ~= nil
end

local function hits(props: Props): { Hit }
	return M.search(M.query:get(), props.sections(), props.keymap)
end

-- Open hit `i`: its page, landing on its row; the keyboard stays in the
-- field for the next pick.
local function open(props: Props, list: { Hit }, i: number)
	local hit = list[i]
	if not hit then
		return
	end
	M.active:set(i)
	props.section:set(hit.entry.section.id)
	if hit.entry.kind ~= "page" then
		M.reveal(hit.entry.anchor, hit.entry.fallback)
	end
	local el = field
	if el and el.mounted then
		el:focus()
	end
end

-- The field under Back: ⌘F's hint while it sits idle, a clear button once
-- it holds a query.
function M.field(props: Props): Node
	local focused = ui.state("settings_search_focused", false)
	local results = ui.computed(function()
		return hits(props)
	end)
	local function on_key(e: KeyEvent): boolean
		if e.meta or e.ctrl or e.alt then
			return false
		end
		local list = results:peek()
		if e.key == "ArrowDown" and #list > 0 then
			M.active:set(math.min(M.active:peek() + 1, #list))
		elseif e.key == "ArrowUp" and #list > 0 then
			M.active:set(math.max(M.active:peek() - 1, 1))
		elseif e.key == "Enter" and #list > 0 then
			open(props, list, M.active:peek())
		elseif e.key == "Escape" and M.query:peek() ~= "" then
			M.query:set("")
		else
			return false
		end
		return true
	end
	return ui.row {
		id = "settings_search_field",
		w_full = true,
		h = 32,
		shrink = 0,
		px = "$zeron.space.8",
		gap = "$zeron.space.8",
		items = "center",
		rounded = "$zeron.radius.8",
		bg = T.ink1,
		hover = { bg = T.ink2 },
		cursor = "text",
		on_click = M.focus,
		ui.row {
			w = 16,
			shrink = 0,
			justify = "center",
			icon { name = "magnifer", size = 14, color = T.secondary },
		},
		ui.input {
			id = "settings_search",
			value = M.query,
			label = "Search settings",
			placeholder = "Search settings",
			placeholder_color = T.tertiary,
			grow = 1,
			min_w = 0,
			p = 0,
			border = 0,
			rounded = 0,
			bg = T.clear,
			focus = { border = 0, bg = T.clear },
			text_size = "$font.size.md",
			color = T.text,
			on_mount = function(el: Element)
				field = el
			end,
			on_focus = ui.set(focused, true),
			on_blur = ui.set(focused, false),
			on_change = function()
				M.active:set(1)
			end,
			on_key = on_key,
		},
		-- A shortcut of the user's on ⌘F takes it before Settings can.
		ui.show(function()
			if M.query:get() ~= "" or focused:get() then
				return false
			end
			for _, b in props.keymap.bindings do
				if keymap.combo(props.keymap, b.id) == "mod-f" then
					return false
				end
			end
			return true
		end, kbd { if keymap.MAC then "⌘" else "Ctrl", "F", flat = true, size = "sm" }),
		ui.show(
			function()
				return M.query:get() ~= ""
			end,
			ui.button {
				id = "settings_search_clear",
				label = "Clear search",
				w = 20,
				h = 20,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.4",
				variants = recipes.wash { hover = "ink3" },
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					M.query:set("")
					M.focus()
				end,
				icon { name = "close", size = 12, color = T.secondary },
			}
		),
	}
end

-- A title with its matched ranges lit, as the palette lights them.
local function lit_title(title: string, ranges: { { number } }): Node
	local parts: { any } = {}
	local at = 1
	for _, r in ranges do
		if r[1] > at then
			table.insert(parts, string.sub(title, at, r[1] - 1))
		end
		table.insert(parts, ui.span { string.sub(title, r[1], r[2]), color = T.text, bg = T.code_wash })
		at = r[2] + 1
	end
	if at <= #title then
		table.insert(parts, string.sub(title, at))
	end
	local rich: any = {
		min_w = 0,
		truncate = true,
		text_size = "$font.size.md",
		color = T.text,
	}
	for i, p in parts do
		rich[i] = p
	end
	return ui.rich(rich)
end

-- The hits, best first, where the sections were.
function M.results(props: Props): Node
	return ui.presence(function(): string
		return M.query:get()
	end, function(): Node
		local list = hits(props)
		if #list == 0 then
			return ui.column {
				id = "settings_search_empty",
				w_full = true,
				py = "$zeron.space.24",
				px = "$zeron.space.16",
				gap = "$zeron.space.6",
				items = "center",
				txt.text { "No matching settings", size = "md", line = false },
				txt.text { "Try a setting, page, or shortcut.", size = "sm", color = T.tertiary, line = false },
			}
		end
		local rows: { Node } = {}
		for i, hit in list do
			local e = hit.entry
			local trail = if e.kind == "page"
				then nil
				elseif e.group then `{e.section.title} · {e.group}`
				else e.section.title
			local function active(): boolean
				return M.active:get() == i
			end
			table.insert(
				rows,
				ui.button(wash.item("settings_search_hits", {
					id = `settings_search_hit_{i}`,
					label = e.title,
					role = "option",
					w_full = true,
					min_h = 32,
					px = "$zeron.space.8",
					py = "$zeron.space.6",
					gap = "$zeron.space.8",
					items = "center",
					rounded = "$zeron.radius.8",
					focus = { border = 0 },
					cursor = "pointer",
					variants = recipes.active_glass { selected = active },
					on_click = function()
						open(props, list, i)
					end,
					icon { name = e.section.icon :: any, size = 16, color = T.secondary },
					ui.column {
						grow = 1,
						shrink = 1,
						min_w = 0,
						lit_title(e.title, hit.ranges),
						trail and txt.text {
							trail,
							literal = true,
							size = "xs",
							color = T.secondary,
							truncate = true,
							line = false,
						},
					},
					e.binding and kbd(keymap.caps(keymap.combo_now(props.keymap, e.binding)) :: any),
				}, active))
			)
		end
		return ui.scroll {
			id = "settings_search_results",
			label = "Settings search results",
			w_full = true,
			grow = 1,
			fade = { 16, 16 },
			fade_overflow = true,
			wash.list {
				group = "settings_search_hits",
				w_full = true,
				gap = "$zeron.space.2",
				py = "$zeron.space.8",
				rows,
			},
		}
	end, { w_full = true, grow = 1, min_h = 0 })
end

return M
