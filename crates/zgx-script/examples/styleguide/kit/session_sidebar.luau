-- The sidebar, as Zeron's (shell.rs render_chat_sidebar, shell/spaces.rs,
-- sidebar_sections.rs): the project filter and the view menu, then one
-- list of the sections (Pinned, the user's own, Sessions or a group per
-- project, Archived), the update strip and the footer (the account menu,
-- voice, pull requests, settings), inset from the window by the shell's
-- gap (`zeron.well.gap`). The list is virtual (`ui.list`): of a thousand
-- sessions only those in view are built. The app gives it its sessions,
-- what is selected and what opening one does; `head` is what the layout
-- puts above it (the window's controls, or room for a titlebar).
local T = require("../theme")
local kit = {
	icon = require("./icon"),
	text = require("./text"),
	loaders = require("./loaders"),
	wash = require("./wash"),
	recipes = require("./recipes"),
	disclosure = require("./disclosure"),
	menu = require("./menu").menu,
	menus = require("./menu"),
	motion = require("./motion"),
	account = require("./account"),
	project_icon = require("./project_icon"),
	dialog = require("./dialog"),
	project_picker = require("./project_picker"),
	button = require("./button"),
	input = require("./input").input,
	popover = require("./popover").popover,
	popover_mod = require("./popover"),
}
local account_mod = require("./account")

export type Status = "working" | "input" | "failed" | "done" | "idle"
export type PrState = "open" | "draft" | "merged" | "closed"
export type Session = {
	key: string,
	row: string,
	title: string,
	harness: string,
	status: Status,
	project: string,
	branch: string?,
	pr: { number: number, state: PrState }?,
	ago: string,
	pinned: boolean?,
	-- A section of the user's own.
	section: string?,
	archived: boolean?,
	-- The device it runs on (its name), and whether that is another
	-- machine than this one.
	device: string?,
	remote: boolean?,
	-- How many subagents run under it now.
	subagents: number?,
	-- Minutes since it was created, and since its last message: the sorts.
	created: number?,
	updated: number?,
}
-- `name`: the harness as a conversation link names it ("Codex").
export type Harness = { icon: string, tint: Color?, name: string? }
-- A voice call, as the footer shows it: whether voice is offered,
-- underway, its stage up, why its start failed ("" when it did not), its
-- glyph; toggling the stage, and forgetting the failure.
export type VoiceCall = {
	offered: () -> boolean,
	live: () -> boolean,
	stage: () -> boolean,
	failure: () -> string,
	glyph: () -> Node,
	toggle: () -> (),
	dismiss: () -> (),
}
export type Context = {
	-- Its node's id ("sidebar" unless set).
	id: string?,
	-- The sessions, or what lists them now (read as the list is built).
	sessions: { Session } | () -> { Session },
	projects: { string },
	harness: { [string]: Harness },
	-- The user's sections in their order, an empty one included (the
	-- sessions' own `section` names otherwise, as they come).
	sections: { string }?,
	-- How many pull requests the board holds.
	prs: number,
	-- How many sessions the Archived shelf holds in all (it pages them in).
	archived_total: number,
	-- Bumped when the sessions change: the list is built again.
	version: State<number>?,
	-- Whether the sidebar marks `key` ("prs" is the board).
	selected: (key: string) -> boolean,
	open: (key: string) -> (),
	-- A row's pull request badge: that pull request (the board unless set).
	open_pr: ((key: string) -> ())?,
	-- "Open in a new space", while `tabbed()`.
	open_in_tab: ((key: string) -> ())?,
	tabbed: (() -> boolean)?,
	-- A project group's + ("New chat in project"): a new session there;
	-- a device's No project group's ("New chat on {device}"), one there
	-- without a project ("" for `project`).
	new_session: ((project: string, device: string?) -> ())?,
	-- This machine's name: its group leads when organized by device.
	this_device: string?,
	-- The devices a chat can start on without a project (not Cloud): their
	-- No project groups' +.
	devices: { string }?,
	-- Whether a change (a rename, a pin, an archive, a section) may go to
	-- the engine now; false keeps things as they are (it says why).
	can_change: (() -> boolean)?,
	-- How many sessions may be pinned (`M.MAX_PINS` unless set), and what
	-- says a change was refused ("You can pin up to 200 sessions").
	max_pins: number?,
	on_notice: ((message: string) -> ())?,
	-- Whether no device holding the project is reachable: the space
	-- switcher shows the offline glyph after its name.
	offline: ((project: string) -> boolean)?,
	-- A session renamed in place, or deleted (after its question).
	on_rename: ((key: string, title: string) -> ())?,
	on_delete: ((key: string) -> ())?,
	-- The space switcher's "New project".
	on_new_project: (() -> ())?,
	-- A copy from a row's menu, said by a toast ("Path copied").
	on_copied: ((what: string) -> ())?,
	on_settings: (() -> ())?,
	-- Whether settings are up (its button stays lit).
	settings_open: (() -> boolean)?,
	on_voice: (() -> ())?,
	-- Whether voice is offered (Zeron's needs Codex on the device): the
	-- voice button shows only then (unless set, when `on_voice` is).
	voice: boolean?,
	-- The call `on_voice` places: while it is live its beam takes the
	-- button's place and a click shows or hides its stage; a failed start
	-- explains itself above the button until dismissed with its ✕.
	voice_call: VoiceCall?,
	on_sign_out: (() -> ())?,
	-- The account menu's sync rows: "Enable sync", "Finish sync setup".
	on_enable_sync: (() -> ())?,
	on_finish_sync: (() -> ())?,
	-- "Check for updates" at the account menu's end (where there is no app
	-- menu to hold it: not macOS).
	on_check_updates: (() -> ())?,
	-- Who is signed in and how the workspace syncs (kit/account): the
	-- footer's label and the menu's identity line follow it. Without it,
	-- `user` signed in as `identity`.
	account: State<account_mod.Account>?,
	user: string?,
	identity: string?,
	-- The app's update, while there is one: the strip over the footer.
	update: State<account_mod.Update?>?,
	on_update: ((u: account_mod.Update) -> ())?,
	-- The edge's posture: the connection pill shows while it is not
	-- "connected".
	connection: State<account_mod.Connection>?,
	-- "Star on GitHub" over the strip until dismissed (it writes false);
	-- `on_star` opens the repository.
	star: State<boolean>?,
	on_star: (() -> ())?,
	-- The sidebar's width: the account menu spans the footer up to the
	-- settings button, as Zeron's (240 without it).
	width: (() -> number)?,
	head: Node?,
}

local M = {}

-- A session row's context menu: Zeron's card, 216 wide.
local ROW_MENU = (function()
	local style = table.clone(require("./menu").CARD) :: { [string]: any }
	style.w = 216
	return style
end)()

-- Zeron's sidebar metrics: compact rows 29; two-line rows 45, a third line
-- for the branch (14) or the pull request (16) adding 2 and its height,
-- and the project's line 16 less when hidden; 2 between rows; section
-- headers 28, 12 above each and 4 between a header and its rows; one 8
-- inset for every icon column (`zeron.list.inset`); the 13 glyphs.
M.ROW = 29
M.HEADER = 28
M.GAP = 2
M.SECTION_GAP = 12
M.BODY_INSET = 4
M.GLYPH = 13
-- A label too long for its room fades over its last 20 rather than ending
-- in "…" (sidebar_faded_label): titles, the location and branch lines,
-- section headers, the footer's name, the project filter's.
M.FADE = 20
-- The footer: 28 controls (the account pill, the buttons), the avatar 16,
-- 4 between the pill and the buttons; the list's inset at its sides.
M.FOOTER_BUTTON = 28
M.FOOTER_AVATAR = 16
M.FOOTER_GAP = 4
M.FOOTER_INSET = 6
-- The Archived shelf shows ten, then pages by 25.
M.ARCHIVED_FIRST = 10
M.ARCHIVED_PAGE = 25
-- At most this many pins (zeron_proto MAX_SIDEBAR_PINS).
M.MAX_PINS = 200

-- Each sidebar's sessions in the order it shows them, by its id: what ⌃Tab
-- cycles and ⌘1 to ⌘9 jump to (sidebar_visible_order): the rows of the
-- open sections, top to bottom, as last built.
local orders: { [string]: () -> { string } } = {}
function M.visible(id: string?): { string }
	local f = orders[id or "sidebar"]
	return if f then f() else {}
end

-- Archiving or unarchiving a session from elsewhere (⌘⇧A, Settings →
-- Archived), as its row's menu does; and whether one is archived, its
-- data's flag unless changed here (read where it changes).
local archivers: { [string]: (key: string, on: boolean) -> () } = {}
function M.set_archived(key: string, on: boolean, id: string?)
	local f = archivers[id or "sidebar"]
	if f then
		f(key, on)
	end
end
-- Opens or closes the project switcher (New project pinned under it).
function M.toggle_projects()
	local open = ui.state("side_filter_open", false)
	open:set(not open:peek())
end
-- The project filter follows a project added (land_in_space): "All"
-- stays as it is.
function M.follow_project(name: string)
	local filter = ui.state("side_filter", "")
	if filter:peek() ~= "" then
		filter:set(name)
	end
end
function M.archived(key: string, base: boolean): boolean
	local over = ui.state("side_archived", {} :: { [string]: boolean }):get()[key]
	return if over ~= nil then over else base
end

-- A row's height as the view options draw it.
function M.row_height(compact: boolean, label: boolean, branch: boolean, pr: boolean): number
	if compact then
		return M.ROW
	end
	local meta = 0
	if branch then
		meta = 14
	end
	if pr then
		meta = 16
	end
	local h = if meta == 0 then 45 else 47 + meta
	return if label then h else h - 16
end

local SAYS: { [Status]: string } = { working = "Working", input = "Input", failed = "Failed", done = "Done" }
local TONE: { [Status]: string } = {
	working = "$zeron.side.status.working",
	input = "$zeron.side.status.input",
	failed = "$zeron.side.status.failed",
	done = "$zeron.side.status.done",
	idle = "$zeron.side.status.idle",
}

-- A status's glyph: Working turns in the accent's tones (`id` its spinner),
-- Done checks, the rest a 6 dot in its tone (idle's faint).
local function status_glyph(status: Status, id: string): Node
	if status == "working" then
		return kit.loaders.mini_spinner { id = id }
	elseif status == "done" then
		return kit.icon { name = "check", size = 11, color = TONE.done }
	end
	return ui.div { w = 6, h = 6, shrink = 0, rounded = T.radius_full, bg = TONE[status] }
end

-- A collapsed section's count, cut as the pull request's badge: 16 at
-- radius 4, mono 10 medium.
local function count_badge(n: number): Node
	return ui.row {
		h = 16,
		px = "$zeron.space.4",
		shrink = 0,
		items = "center",
		rounded = "$zeron.radius.4",
		bg = T.ink2,
		kit.text.text { tostring(n), size = "micro", weight = "medium", mono = true, color = T.tertiary, line = false },
	}
end

function M.view(ctx: Context): Node
	local GROUP = "zeron-side"
	local INSET = "$zeron.well.gap"

	-- How the list is drawn (Zeron's view menu: Organize, Show).
	local compact = ui.state("side_compact", true)
	local organize = ui.state("side_organize", "list" :: "list" | "project" | "device")
	-- The rest's order: by their last message, or as they were created.
	local sort = ui.state("side_sort", "updated" :: "updated" | "created")
	local show_filter = ui.state("side_show_filter", true)
	-- Titles given here, sessions deleted here, the session being renamed.
	local titles = ui.state("side_titles", {} :: { [string]: string })
	local deleted = ui.state("side_deleted", {} :: { [string]: boolean })
	local renaming = ui.state("side_renaming", "")
	-- Sections made here (in order), and names given here (by the first).
	local made = ui.state("side_sections_made", {} :: { string })
	local renamed = ui.state("side_sections_renamed", {} :: { [string]: string })
	-- The question up: "" none, "new" or "edit:<section>" a section's,
	-- "delete:<key>" a session's.
	local asking = ui.state("side_asking", "")
	-- A row menu's Copy submenu.
	local copy_open = ui.state("side_copy_open", false)
	-- Dragging a row (sidebar_pins.rs, spaces.rs): its key, and where it
	-- would land (the entry the gap opens under, the zone, the key it goes
	-- before); the pins' order and sections given here.
	local dragging = ui.state("side_dragging", "")
	local landing = ui.state("side_landing", {} :: { after: number?, zone: string?, before: string? })
	local pin_order = ui.state("side_pin_order", {} :: { string })
	local moved = ui.state("side_moved", {} :: { [string]: string })
	-- Reordering the user's sections (sidebar_sections.rs): their order
	-- given here, the one lifted by its header, and where it would land
	-- among the others.
	local section_order = ui.state("side_section_order", {} :: { string })
	local lifting = ui.state("side_lifting", "")
	local section_over = ui.state("side_section_over", 0)
	-- Projects renamed (their names as shown) and removed here.
	local project_names = ui.state("side_project_names", {} :: { [string]: string })
	local projects_gone = ui.state("side_projects_gone", {} :: { [string]: boolean })
	local show_branch = ui.state("side_show_branch", true)
	local show_pr = ui.state("side_show_pr", true)
	local show_harness = ui.state("side_show_harness", true)
	local show_icon = ui.state("side_show_icon", true)
	local show_project = ui.state("side_show_project", true)
	local show_archived = ui.state("side_show_archived", true)
	-- The project filter ("" for all).
	local filter = ui.state("side_filter", "")
	-- Sessions archived, unarchived, pinned or unpinned here, over the data's
	-- own flags; sections deleted here.
	local archived = ui.state("side_archived", {} :: { [string]: boolean })
	local pinned_over = ui.state("side_pinned", {} :: { [string]: boolean })
	local removed = ui.state("side_removed", {} :: { [string]: boolean })
	-- Sections folded (none at first: the Archived shelf starts open, as
	-- Zeron's), and how much of the shelf shows.
	local folded = ui.state("side_folded", {} :: { [string]: boolean })
	local shelf_shown = ui.state("side_shelf_shown", M.ARCHIVED_FIRST)
	-- The list's scroll, kept as it is built again.
	local offset = ui.state("side_offset", 0)

	local function sessions_now(): { Session }
		local list = ctx.sessions
		return if type(list) == "function" then list() else list
	end

	-- The sessions as the sidebar shows them, in the data's order: each
	-- session's own fields with what was changed here over them (archived,
	-- pinned, its section, its title, deleted), its place among the pins and
	-- when it last spoke. A list state: a change here writes the fields it
	-- changes (`set_key`), and the sections below are `ui.sorted` views of
	-- it, which re-place only the rows written; the data changing
	-- (`version`) builds it again.
	local rows = ui.state("side_rows", {} :: { Session })
	-- Each session's place in `rows`, and the sections the data names, in
	-- the order it names them.
	local index_of: { [string]: number } = {}
	local data_sections: { string } = {}
	local function row_of(s: Session, i: number, pins: { [string]: number }): Session
		local key = s.key
		local r = table.clone(s) :: any
		local a = archived:peek()[key]
		r.archived = if a ~= nil then a else s.archived == true
		local pin = pinned_over:peek()[key]
		r.pinned = if pin ~= nil then pin else s.pinned == true
		local over = moved:peek()[key]
		local name = if over ~= nil then (if over == "" then nil else over) else s.section
		r.section = if name and not removed:peek()[name] then name else nil
		r.title = titles:peek()[key] or s.title
		r.deleted = deleted:peek()[key] or nil
		r.order = i
		r.recency = s.updated or s.created
		r.pin = pins[key]
		return r
	end
	local function pin_places(): { [string]: number }
		local pins: { [string]: number } = {}
		for i, key in pin_order:peek() do
			pins[key] = i
		end
		return pins
	end
	local function rebuild()
		local list: { Session } = {}
		local names: { string } = {}
		index_of = {}
		local pins = pin_places()
		for i, s in sessions_now() do
			list[i] = row_of(s, i, pins)
			index_of[s.key] = i
			if s.section and not table.find(names, s.section) then
				table.insert(names, s.section)
			end
		end
		data_sections = names
		rows:set(list)
	end
	-- What changed here for `key`, written into its row alone.
	local FIELDS = { "archived", "pinned", "section", "title", "deleted", "pin" }
	local function refresh(key: string)
		local i = index_of[key]
		local s = if i then sessions_now()[i] else nil
		if not i or not s or s.key ~= key then
			rebuild()
			return
		end
		local now = rows:at(i) :: any
		local next = row_of(s, i, pin_places()) :: any
		ui.batch(function()
			for _, f in FIELDS do
				if now[f] ~= next[f] then
					rows:set_key({ i, f }, next[f])
				end
			end
		end)
	end
	ui.effect(function()
		if ctx.version then
			ctx.version:get()
		end
		rebuild()
	end)

	local function is_archived(s: Session): boolean
		return s.archived == true
	end
	-- Whether a change may go to the engine now (`can_change`: it says why
	-- not, as a toast).
	local function allowed(): boolean
		return ctx.can_change == nil or ctx.can_change()
	end
	local function set_archived(s: Session, on: boolean)
		if not allowed() then
			return
		end
		archived:set_key(s.key, on)
		refresh(s.key)
	end
	archivers[ctx.id or "sidebar"] = function(key: string, on: boolean)
		archived:set_key(key, on)
		refresh(key)
	end
	local function is_pinned(s: Session): boolean
		return s.pinned == true
	end
	-- Whether `key` may join the pins (Zeron keeps MAX_SIDEBAR_PINS); if
	-- not, it says so.
	local function pin_room(key: string): boolean
		local limit = ctx.max_pins or M.MAX_PINS
		local n = 0
		for _, r in rows:peek() do
			if r.pinned and not (r :: any).deleted and r.key ~= key then
				n += 1
			end
		end
		if n < limit then
			return true
		end
		if ctx.on_notice then
			ctx.on_notice(`You can pin up to {limit} sessions`)
		end
		return false
	end
	-- The rows each part of the list shows, in its order: as the project
	-- filter and the projects removed here leave them.
	local function shown(): (Session) -> boolean
		local f, out = filter:get(), projects_gone:get()
		return function(r: Session): boolean
			return not (r :: any).deleted and not out[r.project] and (f == "" or r.project == f)
		end
	end
	-- Pinned, in the order given here (the unordered last, as they come).
	local pinned_rows = ui.sorted(rows, function()
		local keep = shown()
		return {
			by = "pin",
			filter = function(r: Session): boolean
				return keep(r) and not r.archived and r.pinned == true
			end,
		}
	end)
	-- In sections of the user's own, as they come.
	local own_rows = ui.sorted(rows, function()
		local keep = shown()
		return {
			by = "order",
			filter = function(r: Session): boolean
				return keep(r) and not r.archived and not r.pinned and r.section ~= nil
			end,
		}
	end)
	-- The rest, newest first: by their last message (or as created, when
	-- none), or as created (compare_sidebar_chats); ties keep their order.
	local rest_rows = ui.sorted(rows, function()
		local keep = shown()
		return {
			by = if sort:get() == "created" then "created" else "recency",
			filter = function(r: Session): boolean
				return keep(r) and not r.archived and not r.pinned and r.section == nil
			end,
		}
	end)
	-- The Archived shelf, as they come.
	local shelf_rows = ui.sorted(rows, function()
		local keep = shown()
		return {
			by = "order",
			filter = function(r: Session): boolean
				return keep(r) and r.archived == true
			end,
		}
	end)
	local function items(list: State<{ Session }>): { Session }
		local out: { Session } = {}
		for i = 1, list:len() do
			out[i] = list:at(i) :: Session
		end
		return out
	end

	local function project_label(name: string): string
		return project_names:peek()[name] or name
	end
	local function projects_now(): { string }
		local out: { string } = {}
		for _, p in ctx.projects do
			if not projects_gone:get()[p] then
				table.insert(out, p)
			end
		end
		return out
	end
	local function title_of(s: Session): string
		return titles:peek()[s.key] or s.title
	end
	-- A section's name as shown: as given here, or its own.
	local function section_label(name: string): string
		return renamed:peek()[name] or name
	end

	-- Running subagents (running_pill.rs): 16 high, round, the busy colour
	-- (the accent) at 16%; a 5 dot breathing 0.4 to 1 over 2.4 s, 4 from
	-- the count in mono 10 medium (99+ at most); 6 in at each side.
	local function subagent_pill(s: Session): Node?
		local n = s.subagents or 0
		if n <= 0 then
			return nil
		end
		local dot = `{s.row}_subagents_dot`
		return ui.row {
			id = `{s.row}_subagents`,
			h = 16,
			px = "$zeron.space.6",
			gap = "$zeron.space.4",
			shrink = 0,
			items = "center",
			rounded = T.radius_full,
			bg = T.accent_lit,
			tooltip = if n == 1 then "1 subagent running" else `{n} subagents running`,
			ui.div {
				id = dot,
				w = 5,
				h = 5,
				shrink = 0,
				rounded = T.radius_full,
				bg = T.accent,
				on_mount = function(el: Element)
					if kit.motion.loops() then
						anime.animate(el, {
							opacity = { 0.4, 1, 0.4 },
							duration = 2400,
							ease = kit.motion.EASE_IN_OUT,
							loop = true,
							-- A 5-point dot's breath: 15 steps a second are smooth.
							frameRate = 15,
						})
					end
				end,
			},
			kit.text.text {
				if n > 99 then "99+" else tostring(n),
				size = "micro",
				weight = "medium",
				mono = true,
				color = T.accent,
				line = false,
			},
		}
	end

	-- A session's hover card (session_hover_card.rs), beside its row once
	-- the pointer has rested 550 ms on it: 284 wide, 12 in, radius 12, the
	-- popover's surface. Its title (13 medium on 18, three lines at most)
	-- and how long ago it last spoke (11, secondary), the device's glyph at
	-- the corner; then a line each (18 high, the 14 glyph slot 7 from the
	-- text at 12) for its project, its branch and its pull request. Built
	-- only as it shows.
	local function hover_card(s: Session): Node
		local function line(glyph: Node, text: string, trailing: Node?): Node
			return ui.row {
				w_full = true,
				h = 18,
				gap = "$zeron.space.7",
				items = "center",
				ui.row { w = 14, shrink = 0, items = "center", justify = "center", glyph },
				kit.text.text {
					text,
					literal = true,
					size = "sm",
					color = T.text,
					line = false,
					truncate = true,
					shrink = 1,
					min_w = 0,
				},
				trailing,
			}
		end
		local pr = s.pr
		local tone = if pr then `$zeron.side.pr.{pr.state}` else nil
		return ui.column {
			id = `{s.row}_card`,
			w = 284,
			p = "$zeron.space.12",
			gap = "$zeron.space.10",
			rounded = T.radius_card,
			bg = T.frost,
			backdrop_blur = T.frost_blur,
			border = 1,
			border_color = T.border,
			shadow = T.float_shadow,
			color = T.text,
			ui.row {
				w_full = true,
				gap = "$zeron.space.8",
				items = "start",
				ui.column {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.4",
					kit.text.text {
						if title_of(s) == "" then "New session" else title_of(s),
						literal = true,
						size = "md",
						weight = "medium",
						line_height = ui.raw(18, "the card title's line"),
						wrap = true,
						lines = 3,
					},
					kit.text.text {
						if s.ago == "now" then "just now" else `{s.ago} ago`,
						literal = true,
						size = "xs",
						color = T.secondary,
						line = false,
					},
				},
				kit.icon {
					name = if s.remote then "remote-server" else "laptop",
					size = 13,
					color = T.secondary,
					opacity = 0.8,
				},
			},
			ui.column {
				w_full = true,
				gap = "$zeron.space.2",
				line(kit.project_icon.icon { name = s.project }, project_label(s.project)),
				s.branch and line(
					kit.icon { name = "git-branch", size = 13, color = T.secondary, opacity = 0.8 },
					s.branch
				) or nil,
				(pr and tone) and line(
					kit.icon {
						name = if pr.state == "draft" then "pull-request-draft" else "pull-request",
						size = 13,
						color = `{tone}.fg`,
					},
					"Pull request",
					kit.text.text {
						`#{pr.number}`,
						size = "xs",
						mono = true,
						color = `{tone}.fg`,
						line = false,
					}
				) or nil,
			},
		}
	end

	-- The title, or its editor while it is renamed (chat_title_editor): as
	-- wide as the title, 21 high over the 17 line (2 over and under it),
	-- 4 in, radius 4, an accent hairline on the input's glass; the title
	-- selected. Enter or leaving it keeps the name (an empty or unchanged
	-- one is dropped), Escape leaves it as it was.
	local function title_editor(s: Session): Node
		local draft = ui.use_state(title_of(s))
		local done = false
		local function finish(keep: boolean)
			if done then
				return
			end
			done = true
			local name = string.match(draft:peek(), "^%s*(.-)%s*$") or ""
			if keep and name ~= "" and name ~= title_of(s) and allowed() then
				titles:set_key(s.key, name)
				refresh(s.key)
				if ctx.on_rename then
					ctx.on_rename(s.key, name)
				end
			end
			renaming:set("")
		end
		return ui.input {
			id = `{s.row}_rename`,
			value = draft,
			placeholder = "Session title",
			grow = 1,
			shrink = 1,
			min_w = 0,
			h = 21,
			my = T.pull(2),
			px = "$zeron.space.4",
			py = 0,
			rounded = "$zeron.radius.4",
			border = 1,
			border_color = T.accent,
			bg = T.input,
			focus = { border = 1, border_color = T.accent },
			text_size = "$font.size.md",
			line_height = ui.raw(17, "the row title's 17 line"),
			color = T.text,
			select_on_focus = true,
			on_mount = function(el: Element)
				el:focus()
			end,
			on_key = function(e: KeyEvent): boolean?
				if e.key == "Enter" then
					finish(true)
					return true
				elseif e.key == "Escape" then
					finish(false)
					return true
				end
				return nil
			end,
			on_blur = function()
				finish(true)
			end,
		}
	end

	-- A pull request's badge: 16 at radius 4, the glyph and the number (mono
	-- 10 medium) in its state's tone on that tone at 8%, 16% under the
	-- pointer; it opens that pull request (`open_pr`), or the board.
	local function pr_badge(s: Session, suffix: string): Node
		local pr = s.pr :: { number: number, state: PrState }
		local tone = `$zeron.side.pr.{pr.state}`
		return ui.button {
			id = `{s.row}_{suffix}`,
			h = 16,
			px = "$zeron.space.4",
			py = 0,
			gap = "$zeron.space.3",
			shrink = 0,
			items = "center",
			rounded = "$zeron.radius.4",
			bg = `{tone}.wash`,
			hover = { bg = `{tone}.lit` },
			focus = { border = 0 },
			cursor = "pointer",
			tooltip = `Pull request #{pr.number}`,
			on_click = function()
				if ctx.open_pr then
					ctx.open_pr(s.key)
				else
					ctx.open("prs")
				end
			end,
			kit.icon {
				name = if pr.state == "draft" then "pull-request-draft" else "pull-request",
				size = 10,
				color = `{tone}.fg`,
			},
			kit.text.text {
				`{pr.number}`,
				size = "micro",
				weight = "medium",
				mono = true,
				color = `{tone}.fg`,
				line = false,
			},
		}
	end

	-- Archive (or bring back) from the row: shown in the corner's place
	-- while the pointer is over the row.
	local function archive_button(s: Session, gone: boolean, worded: boolean, hint: State<boolean> | boolean): Node
		return ui.button {
			variants = kit.recipes.jump_archive { hint = hint },
			id = `{s.row}_archive`,
			-- Over the corner, at its end.
			absolute = true,
			top = if worded then -2 else 0,
			right = if worded then -4 else 0,
			h = if worded then 18 else 14,
			px = if worded then "$zeron.space.4" else 0,
			gap = "$zeron.space.4",
			items = "center",
			rounded = "$zeron.radius.5",
			bg = if worded then T.ink3 else T.clear,
			hover = if worded then { bg = T.ink5 } else nil,
			focus = { border = 0 },
			cursor = "pointer",
			tooltip = if gone then "Unarchive session" else "Archive session",
			on_click = function()
				set_archived(s, not gone)
			end,
			kit.icon {
				name = if gone then "archive-up-minimalistic" else "archive-minimalistic",
				size = if worded then 11 else M.GLYPH,
				color = T.secondary,
			},
			worded and kit.text.text {
				if gone then "Unarchive" else "Archive",
				size = "micro",
				color = T.secondary,
				line = false,
			} or nil,
		}
	end

	-- ⌘ alone held (and nothing else): the first nine rows say their key
	-- (⌘1 to ⌘9) in their corner, as long as it is.
	local holding = ui.computed(function(): boolean
		local k = ui.keys:get()
		return k.meta and not (k.shift or k.alt or k.ctrl)
	end)
	-- A row's place in the order the sidebar shows (nil past the ninth),
	-- as the list was built: a fold rebuilds it once it has settled.
	local function place(s: Session): number?
		local at = table.find(M.visible(ctx.id), s.key)
		return if at and at <= 9 then at else nil
	end
	-- Bumped as a fold settles: the rows take their new places.
	local settled = ui.state("side_settled", 0)

	-- A session's row (render_chat_row). Compact, one line: the status, the
	-- harness, the project, the title, its pull request and the time, which
	-- turns into Archive under the pointer. Two-line: the project with the
	-- status word (or the time) in the corner, then the harness, the
	-- project's icon and the title, then the branch and the pull request.
	local function row(s: Session, grouped: boolean, height: number): Node
		local gone = is_archived(s)
		local harness = ctx.harness[s.harness]
		local is_compact = compact:peek()
		-- Chosen: one computed the row's choices share (each would call a
		-- function of its own).
		local on = ui.computed(function(): boolean
			return ctx.selected(s.key)
		end)
		-- Lifted by a drag: it dims where it was.
		local lifted = ui.use_state(false)
		local mark = (show_harness:peek() and harness)
				and kit.icon {
					name = harness.icon :: any,
					size = M.GLYPH,
					color = harness.tint or T.secondary,
					opacity = if gone then 0.4 else 0.8,
				}
			or nil
		local project = (show_icon:peek() and not grouped)
				and ui.div {
					shrink = 0,
					opacity = if gone then 0.4 else 1,
					-- The project, and where it is (project_icon.rs).
					-- Built when it first shows.
					tooltip = if s.device
						then function(): Node
							return ui.column {
								variants = kit.recipes.tooltip { keys = false },
								items = "start",
								kit.text.text { s.project, literal = true, size = "xs", weight = "medium", line = false },
								kit.text.text {
									s.device,
									literal = true,
									size = "xs",
									color = T.secondary,
									line = false,
								},
							}
						end
						else s.project,
					kit.project_icon.icon { name = s.project, lit = on },
				}
			or nil
		local title = if renaming:peek() == s.key
			then title_editor(s)
			else kit.text.text {
				title_of(s),
				literal = true,
				size = "md",
				line = false,
				-- Its end fades where it runs out of room (sidebar_faded_label).
				fade = M.FADE,
				grow = 1,
				shrink = 1,
				min_w = 0,
				color = "inherit",
				group_hover = { color = T.text },
			}
		local pr = (show_pr:peek() and s.pr ~= nil)
		local pill = subagent_pill(s)
		-- Its jump key, while ⌘ is held, if it is among the first nine
		-- (the engine shows and hides it: no script as ⌘ goes down).
		local at = place(s)
		local hinting: State<boolean> | boolean = if at then holding else false
		local hint_label = if at then `⌘{at}` else ""
		local body: Node
		if is_compact then
			body = ui.row {
				w_full = true,
				h_full = true,
				gap = "$zeron.space.4",
				items = "center",
				ui.row {
					id = `{s.row}_status`,
					w = M.GLYPH,
					h = M.GLYPH,
					shrink = 0,
					items = "center",
					justify = "center",
					tooltip = SAYS[s.status] or "Idle",
					status_glyph(s.status, `{s.row}_spinner`),
				},
				mark,
				project,
				title,
				pr and pr_badge(s, "pr") or nil,
				-- One fixed slot (30): the time (or the running subagents),
				-- Archive under the pointer, the jump key while ⌘ is held.
				ui.row {
					relative = true,
					min_w = 30,
					h = 14,
					shrink = 0,
					items = "center",
					justify = "end",
					ui.row {
						variants = kit.recipes.jump_corner { hint = hinting },
						pill or kit.text.text { s.ago, size = "xs", color = T.tertiary, line = false },
					},
					at and ui.div {
						id = `{s.row}_jump`,
						absolute = true,
						right = 0,
						variants = kit.recipes.jump_hint { hint = hinting },
						kit.text.text {
							hint_label,
							literal = true,
							size = "xs",
							color = T.tertiary,
							line = false,
						},
					} or nil,
					archive_button(s, gone, false, hinting),
				},
			}
		else
			local says = SAYS[s.status]
			-- The status word (or the time), the running subagents 6 before it.
			local corner = ui.row {
				relative = true,
				h = 14,
				shrink = 0,
				items = "center",
				ui.row {
					gap = "$zeron.space.4",
					items = "center",
					variants = kit.recipes.jump_corner { hint = hinting },
					pill and ui.div { shrink = 0, mr = "$zeron.space.2", pill } or nil,
					says and status_glyph(s.status, `{s.row}_spinner`) or nil,
					kit.text.text {
						says or s.ago,
						size = "micro",
						weight = "medium",
						color = if says then TONE[s.status] else T.tertiary,
						line = false,
					},
				},
				-- The jump key's chip while ⌘ is held: 16, 4 in, radius 4, mono
				-- 10 medium on the secondary colour at 8%.
				at and ui.row {
					id = `{s.row}_jump`,
					absolute = true,
					top = -1,
					right = 0,
					h = 16,
					px = "$zeron.space.4",
					shrink = 0,
					items = "center",
					rounded = "$zeron.radius.4",
					bg = T.ink3,
					variants = kit.recipes.jump_hint { hint = hinting },
					kit.text.text {
						hint_label,
						literal = true,
						size = "micro",
						weight = "medium",
						mono = true,
						color = T.secondary,
						line = false,
					},
				} or nil,
				archive_button(s, gone, true, hinting),
			}
			local label = show_project:peek()
			local branch = show_branch:peek() and s.branch or nil
			body = ui.column {
				w_full = true,
				h_full = true,
				py = "$zeron.space.6",
				gap = T.space(M.GAP),
				label and ui.row {
					w_full = true,
					h = 14,
					gap = "$zeron.space.8",
					items = "center",
					kit.text.text {
						-- Where it runs, when that is another machine.
						if s.remote and s.device
							then `{project_label(s.project)} @ {s.device}`
							else project_label(s.project),
						literal = true,
						size = "xs",
						color = T.tertiary,
						line = false,
						fade = M.FADE,
						grow = 1,
						shrink = 1,
						min_w = 0,
					},
					corner,
				} or nil,
				ui.row {
					w_full = true,
					h = 17,
					gap = "$zeron.space.8",
					items = "center",
					mark,
					project,
					title,
					-- Another machine's, when the location line is off.
					(not label and s.remote) and ui.div {
						id = `{s.row}_remote`,
						shrink = 0,
						label = "Remote session",
						kit.icon { name = "remote-server", size = M.GLYPH, color = T.tertiary },
					} or nil,
					not label and corner or nil,
				},
				(branch or pr) and ui.row {
					w_full = true,
					h = if pr then 16 else 14,
					gap = "$zeron.space.4",
					items = "center",
					branch and kit.icon { name = "git-branch", size = 11, color = T.tertiary } or nil,
					branch and kit.text.text {
						branch,
						literal = true,
						size = "xs",
						color = T.tertiary,
						line = false,
						fade = M.FADE,
						shrink = 1,
						min_w = 0,
					} or nil,
					ui.div { grow = 1, min_w = 0 },
					pr and pr_badge(s, "pr") or nil,
				} or nil,
			}
		end
		-- What a screen reader says for it: its title, then its status, its
		-- project and what it is here (pinned, archived).
		local said = { if title_of(s) == "" then "New session" else title_of(s) }
		table.insert(said, SAYS[s.status] or "Idle")
		table.insert(said, project_label(s.project))
		if is_pinned(s) then
			table.insert(said, "pinned")
		end
		if gone then
			table.insert(said, "archived")
		end
		return ui.button(kit.wash.item(GROUP, {
			id = s.row,
			label = table.concat(said, ", "),
			w_full = true,
			h = height,
			shrink = 0,
			px = "$zeron.list.inset",
			py = 0,
			items = "center",
			rounded = "$zeron.radius.8",
			cursor = "pointer",
			focus = { border = 0 },
			variants = kit.recipes.side_row {
				selected = on,
				archived = gone,
				dragged = lifted,
			},
			on_click = function()
				ctx.open(s.key)
			end,
			-- Dragged: a frosted copy follows the pointer, the row dims
			-- where it was (archived rows stay put).
			on_drag = if gone
				then nil
				else function(): any
					dragging:set(s.key)
					lifted:set(true)
					return { kind = "session", key = s.key, title = title_of(s) }
				end,
			drag_preview = function(): Node
				return ui.row {
					id = "side_drag_row",
					w = 220,
					h = M.ROW,
					px = "$zeron.list.inset",
					gap = "$zeron.space.8",
					items = "center",
					rounded = "$zeron.radius.8",
					bg = T.frost,
					backdrop_blur = T.frost_blur,
					shadow = T.shadow_md,
					color = T.text,
					status_glyph(s.status, `{s.row}_spinner`),
					kit.text.text {
						title_of(s),
						literal = true,
						size = "md",
						line = false,
						fade = M.FADE,
						grow = 1,
						shrink = 1,
						min_w = 0,
						color = "inherit",
					},
				}
			end,
			on_drag_end = function()
				lifted:set(false)
				dragging:set("")
				landing:set {}
			end,
			-- Its hover card, after a rest.
			tooltip = function(): Node
				return hover_card(s)
			end,
			tooltip_delay = 550,
			tooltip_placement = { side = "right", align = "start", offset = 10 },
			-- A second press renames it in place.
			on_press = function(e: PointerEvent)
				if (e.clicks or 1) >= 2 and not gone then
					renaming:set(s.key)
				end
			end,
			-- A secondary click: Zeron's card (popover_card, 216 wide) at the
			-- pointer, its rows popover.rs menu_row's (33, the 16 glyph in the
			-- secondary colour 10 from the label): Rename, Pin, Archive,
			-- Copy ›, then under a hairline Delete… in the danger colour. In
			-- the tabs layouts it opens in a new space first.
			context_menu_style = ROW_MENU,
			context_menu = function()
				local pinned = is_pinned(s)
				local function item(id: string, label: string, glyph: string, run: () -> (), danger: boolean?): Node
					return kit.menus.item({
						id = `{s.row}_menu_{id}`,
						label = label,
						icon = glyph :: any,
						danger = danger,
						on_click = run,
					}, function() end, nil, nil, "popover")
				end
				local items: { Node } = {}
				if ctx.open_in_tab and ctx.tabbed and ctx.tabbed() then
					table.insert(
						items,
						item("tab", "Open in a new space", "add-circle", function()
							if ctx.open_in_tab then
								ctx.open_in_tab(s.key)
							end
						end)
					)
					table.insert(items, kit.menus.separator())
				end
				if not gone then
					table.insert(
						items,
						item("rename", "Rename", "pen", function()
							renaming:set(s.key)
						end)
					)
					table.insert(
						items,
						item("pin", if pinned then "Unpin" else "Pin", "pin", function()
							if not allowed() or (not pinned and not pin_room(s.key)) then
								return
							end
							pinned_over:set_key(s.key, not pinned)
							refresh(s.key)
						end)
					)
				end
				table.insert(
					items,
					item(
						"archive",
						if gone then "Unarchive" else "Archive",
						if gone then "archive-up-minimalistic" else "archive-minimalistic",
						function()
							set_archived(s, not gone)
						end
					)
				)
				-- Copy › (its card 232 wide beside the row): the conversation's
				-- links, each with the copy glyph.
				local harness = ctx.harness[s.harness]
				local function copy(id: string, label: string, text: string, said: string): any
					return {
						id = `{s.row}_copy_{id}`,
						label = label,
						icon = "copy",
						on_click = function()
							ui.clipboard.write(text)
							if ctx.on_copied then
								ctx.on_copied(said)
							end
						end,
					}
				end
				local id = string.match(s.key, ":(.*)$") or s.key
				local copies: { any } = {
					copy("link", "Zeron conversation link", `zeron://chat/{id}`, "Zeron conversation link"),
				}
				if harness and harness.name then
					local name = harness.name :: string
					table.insert(
						copies,
						copy(
							"harness",
							`{name} conversation link`,
							`{string.lower(name)}://resume/{id}`,
							`{name} conversation link`
						)
					)
				end
				table.insert(
					items,
					kit.menus.nested({
						id = `{s.row}_menu_copy_trigger`,
						label = "Copy",
						icon = "copy",
						heading = "",
						h = 33,
						chevron = 14,
						open = copy_open,
						submenu = copies,
					}, function() end, "popover")
				)
				table.insert(items, kit.menus.separator())
				table.insert(
					items,
					item("delete", "Delete…", "trash-bin-minimalistic", function()
						asking:set(`delete:{s.key}`)
					end, true)
				)
				return items
			end,
			body,
		}, on))
	end

	-- A custom section's options (sidebar_sections.rs): its header's …
	-- (20, radius 4, the glass wash under the pointer), shown on the
	-- header's hover and while its menu is up. The menu (180, Zeron's card
	-- and rows, words alone) opens where the … is pressed (menu_at): from
	-- the button's middle.
	local section_menu = ui.component(function(p: { id: string, name: string }): Node
		local open = ui.use_state(false)
		local menu = kit.menu {
			id = `side_{p.id}_menu`,
			open = open,
			w = 180,
			rows = "popover",
			placement = { side = "bottom", align = "start", offset = 0 },
			items = {
				{
					id = `side_{p.id}_edit`,
					label = "Edit section",
					on_click = function()
						asking:set(`edit:{p.name}`)
					end,
				},
				{
					id = `side_{p.id}_archive_all`,
					label = "Archive all",
					on_click = function()
						ui.batch(function()
							for _, s in rows:peek() do
								if s.section == p.name and not is_archived(s) then
									set_archived(s, true)
								end
							end
						end)
					end,
				},
				{
					id = `side_{p.id}_delete`,
					label = "Delete",
					on_click = function()
						removed:set_key(p.name, true)
						rebuild()
					end,
				},
			} :: { any },
			-- A point at the button's middle, under which the press passes
			-- to the button.
			anchor = ui.div { w = 1, h = 1, pointer_events = "none" },
		}
		return ui.div {
			w = 20,
			h = 20,
			shrink = 0,
			relative = true,
			-- Under the button, which takes the press.
			ui.div { absolute = true, left = 10, top = 10, menu },
			ui.button {
				id = `side_{p.id}_more`,
				w = 20,
				h = 20,
				p = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.4",
				variants = kit.recipes.section_more { on = open },
				focus = { border = 0 },
				cursor = "pointer",
				tooltip = "Section options",
				on_click = ui.toggle(open),
				kit.icon { name = "more-horizontal", size = 14, color = "currentColor" },
			},
		}
	end)

	-- What the list holds, top to bottom: headers, rows, an empty section's
	-- note, Archived's "Show more"; each with its height (the gaps under it
	-- included).
	type Entry = {
		-- "header", "row", "empty", "none" (no sessions), "more", "end".
		kind: string,
		-- Its height open (the gap under it included); a folded section's
		-- body takes 0, and its header loses the inset under it.
		h: number,
		-- The section it sits in (a header's own), which folds it.
		section: string?,
		-- Where a row dropped on it lands: "pinned", "custom:<name>", or
		-- "regular" (unpinned, in no section of one's own); nil takes none.
		zone: string?,
		-- A header's.
		id: string?,
		label: string?,
		count: number?,
		top: number?,
		open: boolean?,
		project: string?,
		custom: boolean?,
		-- A custom section's own name (its label may be one given here).
		name: string?,
		-- A No project group's device (its + starts a chat there).
		device: string?,
		-- A row's.
		session: Session?,
		grouped: boolean?,
		-- The row's own height (`h` less the gap under it).
		body: number?,
		-- "Show N more"'s.
		more: number?,
	}

	local function entries(): { Entry }
		local out: { Entry } = {}
		local is_compact = compact:get()
		local label = show_project:get()
		local branches, prs = show_branch:get(), show_pr:get()
		-- Labels the headers show.
		renamed:get()
		project_names:get()
		local function height(s: Session): number
			return M.row_height(is_compact, label, branches and s.branch ~= nil, prs and s.pr ~= nil)
		end
		-- The section the entries after a header sit in. A folded one keeps
		-- its rows, at 0: folding changes heights alone, which the list eases.
		local current: string? = nil
		local zone: string? = nil
		local function open_section(id: string, text: string, n: number, extra: Entry?)
			local top = if #out == 0 then M.BODY_INSET else M.SECTION_GAP
			if id == "archived" and #out > 0 then
				top = M.BODY_INSET * 2
			end
			local e: Entry = extra or ({} :: any)
			e.kind = "header"
			e.id = id
			e.section = id
			e.label = text
			e.count = n
			e.top = top
			e.h = top + M.HEADER + M.BODY_INSET
			zone = if id == "pinned"
				then "pinned"
				elseif e.custom then `custom:{e.name or text}`
				elseif id == "archived" then nil
				else "regular"
			e.zone = zone
			table.insert(out, e)
			current = id
			return true
		end
		local function rows(list: { Session }, grouped: boolean)
			for i, s in list do
				local last = i == #list
				table.insert(out, {
					kind = "row",
					section = current,
					zone = zone,
					session = s,
					grouped = grouped,
					body = height(s),
					h = height(s) + (if last then 0 else M.GAP),
				})
			end
		end

		-- Each part in its order, as the sorted views keep it.
		local pinned = items(pinned_rows)
		local rest = items(rest_rows)
		local shelf = items(shelf_rows)
		local own: { [string]: { Session } } = {}
		local own_order: { string } = {}
		-- The sections in their own order: as given, then as the data names
		-- them (a row moved into one does not move it up), then made here.
		local names = table.clone(ctx.sections or {})
		for _, name in data_sections do
			if not table.find(names, name) then
				table.insert(names, name)
			end
		end
		for _, name in made:get() do
			table.insert(names, name)
		end
		-- As dragged into order here, any others after.
		local order = section_order:get()
		if #order > 0 then
			local ranked: { string } = {}
			for _, name in order do
				if table.find(names, name) then
					table.insert(ranked, name)
				end
			end
			for _, name in names do
				if not table.find(ranked, name) then
					table.insert(ranked, name)
				end
			end
			names = ranked
		end
		local gone_sections = removed:get()
		for _, name in names do
			if not gone_sections[name] and not own[name] then
				own[name] = {}
				table.insert(own_order, name)
			end
		end
		for _, s in items(own_rows) do
			local section = s.section :: string
			if not own[section] then
				own[section] = {}
				table.insert(own_order, section)
			end
			table.insert(own[section], s)
		end

		local active = #pinned + #rest
		for _, name in own_order do
			active += #own[name]
		end
		if active == 0 then
			table.insert(out, { kind = "none", h = 32 })
		end
		if #pinned > 0 and open_section("pinned", "Pinned", #pinned) then
			rows(pinned, false)
		end
		for _, name in own_order do
			local id = string.lower((string.gsub(name, "[^%w]+", "_")))
			local list = own[name]
			if open_section(id, section_label(name), #list, { custom = true, name = name } :: any) then
				if #list == 0 then
					table.insert(out, { kind = "empty", section = current, zone = zone, h = 40 })
				else
					rows(list, false)
				end
			end
		end
		local organized = organize:get()
		if organized == "project" then
			for _, project in ctx.projects do
				local list: { Session } = {}
				for _, s in rest do
					if s.project == project then
						table.insert(list, s)
					end
				end
				if
					#list > 0
					and open_section(`project_{project}`, project_label(project), #list, { project = project } :: any)
				then
					rows(list, true)
				end
			end
			-- Chats in no project: a "No project" group per device (this
			-- one's first), each named by its device's + (spaces.rs).
			local loose: { [string]: { Session } } = {}
			local devices: { string } = {}
			for _, s in rest do
				if s.project == "" then
					local d = s.device or ctx.this_device or ""
					if not loose[d] then
						loose[d] = {}
						table.insert(devices, if d == ctx.this_device then 1 else #devices + 1, d)
					end
					table.insert(loose[d], s)
				end
			end
			for _, d in devices do
				local id = `noproject_{string.lower((string.gsub(d, "[^%w]+", "_")))}`
				if open_section(id, "No project", #loose[d], { device = d } :: any) then
					rows(loose[d], true)
				end
			end
		elseif organized == "device" then
			-- A group per device, this one's first, the rest as they come.
			local groups: { [string]: { Session } } = {}
			local devices: { string } = {}
			for _, s in rest do
				local d = s.device or "Unknown device"
				if not groups[d] then
					groups[d] = {}
					if d == ctx.this_device then
						table.insert(devices, 1, d)
					else
						table.insert(devices, d)
					end
				end
				table.insert(groups[d], s)
			end
			for _, d in devices do
				local id = `device_{string.lower((string.gsub(d, "[^%w]+", "_")))}`
				if open_section(id, d, #groups[d]) then
					rows(groups[d], false)
				end
			end
		elseif #rest > 0 and open_section("sessions", "Sessions", #rest) then
			rows(rest, false)
		end
		-- A pin dragged with nothing unpinned: where it would unpin.
		if #rest == 0 and dragging:get() ~= "" then
			local key = dragging:peek()
			local pin = false
			for _, s in pinned do
				pin = pin or s.key == key
			end
			if pin and open_section("sessions", "Sessions", 0) then
				table.insert(out, { kind = "unpin", section = current, zone = zone, h = 48 })
			end
		end
		local total = math.max(#shelf, ctx.archived_total)
		if show_archived:get() and total > 0 and open_section("archived", "Archived", total) then
			local shown = shelf_shown:get()
			local visible: { Session } = {}
			for i, s in shelf do
				if i > shown then
					break
				end
				table.insert(visible, s)
			end
			rows(visible, false)
			if total > shown then
				table.insert(out, {
					kind = "more",
					section = current,
					more = math.min(total - shown, M.ARCHIVED_PAGE),
					h = M.GAP + (if is_compact then M.ROW else 36),
				})
			end
		end
		table.insert(out, { kind = "end", h = 12 })
		return out
	end

	-- The user's sections in the list, in order: each one's name and its
	-- entries (its header to its last row).
	type Span = { name: string, id: string, first: number, last: number }
	local function custom_spans(all: { Entry }): { Span }
		local out: { Span } = {}
		local open: Span? = nil
		for i, e in all do
			if e.kind == "header" then
				open = if e.custom
					then { name = (e.name or e.label) :: string, id = e.id :: string, first = i, last = i }
					else nil
				if open then
					table.insert(out, open)
				end
			elseif open and e.section == open.id then
				open.last = i
			else
				open = nil
			end
		end
		return out
	end

	-- Each entry's height as the sections are folded now: a folded
	-- section's body 0, its header without the inset under it.
	local function base_heights(all: { Entry }): { number }
		local shut = folded:get()
		-- A dragged row's gap where it would land: as tall as a row and
		-- the gap under it.
		local after = landing:get().after
		local out: { number } = {}
		for i, e in all do
			local h = e.h
			if e.section and shut[e.section] then
				h = if e.kind == "header" then h - M.BODY_INSET else 0
			end
			if i == after then
				h += (if compact:peek() then M.ROW else 45) + M.GAP
			end
			out[i] = h
		end
		return out
	end
	-- And while a section is lifted: its slot is where it would land, the
	-- others sliding to make it (the list eases its heights).
	local function heights_of(all: { Entry }): { number }
		local out = base_heights(all)
		local lift = lifting:get()
		if lift == "" then
			return out
		end
		local spans = custom_spans(all)
		local others: { Span } = {}
		local from: Span? = nil
		for _, sp in spans do
			if sp.name == lift then
				from = sp
			else
				table.insert(others, sp)
			end
		end
		if not from then
			return out
		end
		local total = 0
		for i = from.first, from.last do
			total += out[i]
			out[i] = 0
		end
		local over = math.clamp(section_over:get(), 0, #others)
		local at = if #others == 0
			then from.last
			elseif over < #others then others[over + 1].first - 1
			else others[#others].last
		out[math.max(at, 1)] += total
		return out
	end

	-- What the list shows, worked out again (in one call) as what it reads
	-- changes: a row written moves between the sorted views, and this
	-- re-places the entries.
	local plan = ui.computed(entries)
	-- Each row's place by its key, as last given the list: a row built at
	-- one place finds where it is now (rows before it come and go).
	local places: { [string]: number } = {}
	local named: { string } = {}

	-- Dropping a row: Pinned takes it at its place, a section of one's own
	-- takes it (unpinned), anywhere else among the sessions unpins it.
	-- Where the last drag over an entry would land it (kept past the drag's
	-- end, which may come before the drop).
	type Aim = { after: number?, zone: string?, before: string? }
	local aim: Aim = {}
	-- The entry that aimed it: leaving that one (for the chat, say)
	-- closes the gap; leaving for another entry, that one aims anew first.
	local aimed_by = 0
	local function land(key: string)
		local l = aim
		aim = {}
		local zone = l.zone
		if not zone or not allowed() then
			return
		end
		if zone == "pinned" then
			local r = rows:peek()[index_of[key] or 0]
			if not (r and r.pinned) and not pin_room(key) then
				return
			end
			local order: { string } = {}
			for _, e in pin_order:peek() do
				if e ~= key then
					table.insert(order, e)
				end
			end
			-- The pins as they show, where none were ordered yet.
			for i = 1, pinned_rows:len() do
				local s = pinned_rows:at(i) :: Session
				if s.key ~= key and not table.find(order, s.key) then
					table.insert(order, s.key)
				end
			end
			local at = if l.before then table.find(order, l.before) else nil
			table.insert(order, at or #order + 1, key)
			ui.batch(function()
				pin_order:set(order)
				pinned_over:set_key(key, true)
				moved:set_key(key, "")
				-- Every pin's place moves: the rows again.
				rebuild()
			end)
		else
			local section = string.match(zone, "^custom:(.*)$")
			ui.batch(function()
				pinned_over:set_key(key, false)
				moved:set_key(key, section or "")
				refresh(key)
			end)
		end
	end

	-- What a list entry takes while a row is dragged over it: where the
	-- gap opens (over a row's upper half, before it; its lower half, after
	-- it; a header or an empty section, at its top).
	local function drop_props(built: number, key: string?): { [string]: any }
		local function where(): number
			return if key then places[key] or built else built
		end
		local e = plan:peek()[built]
		if not e.zone then
			return {}
		end
		local zone = e.zone :: string
		return {
			drop_when = function(payload: any): boolean
				return type(payload) == "table" and payload.kind == "session"
			end,
			on_drag_over = function(payload: any, p: DragPoint)
				local all = plan:peek()
				local index = where()
				local after, before = index, nil
				if e.kind == "row" and zone ~= "regular" then
					local upper = p.local_y < p.h / 2
					after = if upper then index - 1 else index
					local next = all[if upper then index else index + 1]
					before = if next
							and next.kind == "row"
							and next.zone == zone
						then (next.session :: Session).key
						else nil
				elseif e.kind == "row" then
					-- The sessions keep their own order: the gap opens under
					-- their header.
					for i = index, 1, -1 do
						if all[i].kind == "header" then
							after = i
							break
						end
					end
				else
					local next = all[index + 1]
					before = if next
							and next.kind == "row"
							and next.zone == zone
						then (next.session :: Session).key
						else nil
				end
				local now = landing:peek()
				aim = { after = after, zone = zone, before = before } :: Aim
				aimed_by = index
				if now.after ~= after or now.zone ~= zone or now.before ~= before then
					landing:set(aim)
				end
			end,
			on_drag_leave = function()
				if aimed_by == where() then
					aim = {}
					aimed_by = 0
					landing:set {}
				end
			end,
			on_drop = function(payload: any)
				land(payload.key)
				landing:set {}
			end,
		}
	end

	-- A section's header (sidebar_disclosure_header): its project's icon
	-- (a project group), the label at 12 medium, the count while folded,
	-- what it offers on hover (a project's +, a section's …) and the
	-- chevron, right while folded and down when open.
	local function merge(t: { [any]: any }, extra: { [string]: any }?): ContainerProps
		for k, v in extra or {} do
			t[k] = v
		end
		return t :: any
	end

	-- A section lifted by its header (render_lifted_sidebar_section): its
	-- header and rows on a frosted card that follows the pointer.
	local function lifted_card(e: Entry): Node
		local shown: { Node } = {}
		for _, x in plan:peek() do
			if x.kind == "row" and x.section == e.id then
				local s = x.session :: Session
				table.insert(
					shown,
					ui.row {
						h = M.ROW,
						shrink = 0,
						px = "$zeron.list.inset",
						gap = "$zeron.space.8",
						items = "center",
						status_glyph(s.status, `side_lift_{s.row}`),
						kit.text.text {
							title_of(s),
							literal = true,
							size = "md",
							line = false,
							fade = M.FADE,
							grow = 1,
							shrink = 1,
							min_w = 0,
							color = "inherit",
						},
					}
				)
			end
		end
		return ui.column {
			id = "side_lifted_section",
			w = if ctx.width then ctx.width() - 16 else 240,
			p = "$zeron.space.4",
			gap = T.space(M.GAP),
			rounded = "$zeron.radius.8",
			bg = T.frost,
			backdrop_blur = T.frost_blur,
			shadow = T.shadow_md,
			color = T.text,
			ui.row {
				h = M.HEADER,
				shrink = 0,
				px = "$zeron.list.inset",
				items = "center",
				kit.text.text {
					e.label :: string,
					literal = true,
					size = "sm",
					weight = "medium",
					color = T.secondary,
					line = false,
					fade = M.FADE,
					shrink = 1,
					min_w = 0,
				},
			},
			shown,
		}
	end

	local function header(e: Entry, extra: { [string]: any }?): Node
		local id = e.id :: string
		local function open(): boolean
			return not folded:get()[id]
		end
		local action: Node? = nil
		local device = e.device
		if (e.project or (device and table.find(ctx.devices or {}, device))) and ctx.new_session then
			local project = e.project or ""
			local says = if e.project then "New chat in project" else `New chat on {device}`
			action = ui.button {
				id = `side_{id}_new`,
				w = 20,
				h = 20,
				p = 0,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.4",
				opacity = 0,
				group_hover = { opacity = 1 },
				variants = kit.recipes.wash { hover = "ink3" },
				focus = { border = 0 },
				cursor = "pointer",
				tooltip = says,
				label = says,
				on_click = function()
					if ctx.new_session then
						ctx.new_session(project, device)
					end
				end,
				kit.icon { name = "plus", size = 14, color = "currentColor" },
			}
		elseif e.custom then
			action = section_menu { id = id, name = (e.name or e.label) :: string }
		end
		return ui.column(merge({
			id = `side_{id}`,
			w_full = true,
			h_full = true,
			px = INSET,
			pt = T.space(e.top :: number),
			ui.button {
				id = `side_{id}_header`,
				w_full = true,
				h = M.HEADER,
				shrink = 0,
				px = "$zeron.list.inset",
				py = 0,
				gap = "$zeron.space.8",
				items = "center",
				rounded = "$zeron.radius.8",
				hover_group = true,
				variants = kit.recipes.disclosure,
				on_click = function()
					folded:set_key(id, not folded:peek()[id])
					-- Settled, the rows take their places (the jump keys).
					ui.after(kit.motion.d(kit.motion.COLLAPSE) + 40, function()
						settled:set(settled:peek() + 1)
					end)
				end,
				-- A section of one's own lifts by its header, to go among
				-- the others.
				on_drag = if e.custom
					then function(): any
						local name = (e.name or e.label) :: string
						for i, sp in custom_spans(plan:peek()) do
							if sp.name == name then
								section_over:set(i - 1)
							end
						end
						lifting:set(name)
						return { kind = "section", name = name }
					end
					else nil,
				drag_preview = if e.custom
					then function(): Node
						return lifted_card(e)
					end
					else nil,
				on_drag_end = if e.custom
					then function()
						lifting:set("")
					end
					else nil,
				e.project and kit.project_icon.icon { name = e.project :: string } or nil,
				kit.text.text {
					e.label :: string,
					literal = true,
					size = "sm",
					weight = "medium",
					color = "inherit",
					line = false,
					fade = M.FADE,
					shrink = 1,
					min_w = 0,
				},
				-- The count while folded.
				e.count and ui.row {
					id = `side_{id}_count`,
					shrink = 0,
					hidden = open,
					count_badge(e.count :: number),
				} or nil,
				ui.div { grow = 1 },
				action,
				kit.disclosure.chevron { id = `side_{id}_chevron`, open = open },
			},
		}, extra))
	end

	local function body(e: Entry, extra: { [string]: any }?): Node
		if e.kind == "row" then
			local s = e.session :: Session
			local s_h = e.body :: number
			-- It fills its slot (a drop's gap under it included, so a drop
			-- there is its), the row its own height at the top.
			return ui.column(merge({
				w_full = true,
				h_full = true,
				px = INSET,
				row(s, e.grouped == true, s_h),
			}, extra))
		elseif e.kind == "empty" then
			return ui.row(merge({
				w_full = true,
				h_full = true,
				items = "start",
				px = INSET,
				ui.row {
					w_full = true,
					h = e.h,
					px = "$zeron.list.inset",
					items = "center",
					kit.text.text { "Drop sessions here", size = "sm", color = T.disabled, line = false },
				},
			}, extra))
		elseif e.kind == "unpin" then
			-- A pin dragged with nothing unpinned (shell.rs regular sessions).
			return ui.row(merge({
				w_full = true,
				h_full = true,
				items = "start",
				px = INSET,
				ui.row {
					id = "side_unpin",
					w_full = true,
					h = e.h,
					px = "$zeron.list.inset",
					items = "center",
					kit.text.text { "Drop here to unpin", size = "sm", color = T.secondary, line = false },
				},
			}, extra))
		elseif e.kind == "none" then
			return ui.row {
				w_full = true,
				h = e.h,
				px = INSET,
				ui.row {
					id = "side_empty",
					w_full = true,
					h_full = true,
					px = "$zeron.list.inset",
					items = "center",
					kit.text.text { "No sessions yet", size = "sm", color = T.disabled, line = false },
				},
			}
		elseif e.kind == "more" then
			return ui.column {
				w_full = true,
				h = e.h,
				px = INSET,
				pt = T.space(M.GAP),
				ui.button {
					id = "side_archived_more",
					w_full = true,
					grow = 1,
					px = "$zeron.list.inset",
					gap = "$zeron.space.10",
					items = "center",
					rounded = "$zeron.radius.6",
					variants = kit.recipes.disclosure,
					on_click = function()
						shelf_shown:set(shelf_shown:peek() + M.ARCHIVED_PAGE)
					end,
					kit.icon { name = "plus", size = 14, color = "currentColor" },
					kit.text.text { `Show {e.more} more`, size = "md", color = "inherit", line = false },
				},
			}
		end
		return ui.div { w_full = true, h = e.h }
	end
	local function build(index: number): Node
		local e = plan:peek()[index]
		local extra = drop_props(index, named[index])
		if e.kind == "header" then
			return header(e, extra)
		end
		-- Drawn at its own height; as its section folds, its slot eases to
		-- 0 and the list clips it there.
		return body(e, extra)
	end

	-- The list: built once, its rows in view as they come; folding only
	-- eases its heights (Zeron's COLLAPSE, 180 ms ease-out). A row is built
	-- again only when what it shows changes: the entry at its place, or how
	-- rows are drawn.
	local function look(): string
		return table.concat({
			tostring(compact:get()),
			tostring(show_harness:get()),
			tostring(show_icon:get()),
			tostring(show_project:get()),
			tostring(show_branch:get()),
			tostring(show_pr:get()),
			-- The jump keys' places, as a fold settles.
			tostring(settled:get()),
		}, ",")
	end
	local function identity(e: Entry, drawn: string): string
		if e.kind == "row" then
			local r = e.session :: any
			local pr = r.pr
			return table.concat({
				"row",
				e.section or "",
				tostring(e.grouped),
				tostring(e.body),
				r.key,
				r.title,
				r.status,
				r.ago,
				tostring(r.archived),
				tostring(r.pinned),
				r.project,
				r.branch or "",
				if pr then `{pr.number}{pr.state}` else "",
				tostring(r.subagents or 0),
				r.device or "",
				tostring(r.remote),
				tostring(renaming:get() == r.key),
				project_label(r.project),
				drawn,
			}, "|")
		elseif e.kind == "header" then
			return table.concat({
				"header",
				e.id or "",
				e.label or "",
				tostring(e.count),
				tostring(e.top),
				e.project or "",
				e.name or "",
				tostring(e.custom),
			}, "|")
		end
		return `{e.kind}|{e.section or ""}|{e.h}|{e.more or 0}`
	end
	-- Each entry's key, by what it shows (one shown twice is told apart by
	-- its count), and each key's place.
	local row_keys = ui.computed(function(): { string }
		local drawn = look()
		local out: { string } = {}
		local at: { [string]: number } = {}
		for i, e in plan:get() do
			local id = identity(e, drawn)
			if at[id] then
				local n = 2
				while at[`{id}#{n}`] do
					n += 1
				end
				id = `{id}#{n}`
			end
			out[i] = id
			at[id] = i
		end
		places = at
		named = out
		return out
	end)
	-- Where a lifted section would land (section_drop_index): among the
	-- others, past each whose middle its leading edge has passed, from
	-- the list's point `y` (the pointer, a little into the header).
	local function section_drop(y: number)
		local all = plan:peek()
		local hs = base_heights(all)
		local spans = custom_spans(all)
		local tops: { number } = {}
		local at = 0
		for i, h in hs do
			tops[i] = at
			at += h
		end
		local sizes: { number } = {}
		local from = 0
		for i, sp in spans do
			sizes[i] = tops[sp.last] + hs[sp.last] - tops[sp.first]
			if sp.name == lifting:peek() then
				from = i
			end
		end
		if from == 0 then
			return
		end
		local grab = (all[spans[from].first].top or 0) + M.HEADER / 2
		local top = y + offset:peek() - grab - tops[spans[1].first]
		local bottom = top + sizes[from]
		local slot, over = 0, 0
		for i, h in sizes do
			local middle = slot + h / 2
			if (i < from and top > middle) or (i > from and bottom > middle) then
				over += 1
			end
			slot += h
		end
		if section_over:peek() ~= over then
			section_over:set(over)
		end
	end
	-- Dropped: the sections in their new order, kept here.
	local function place_section(name: string)
		local names: { string } = {}
		for _, sp in custom_spans(plan:peek()) do
			if sp.name ~= name then
				table.insert(names, sp.name)
			end
		end
		table.insert(names, math.clamp(section_over:peek(), 0, #names) + 1, name)
		lifting:set("")
		if allowed() then
			section_order:set(names)
		end
	end

	local function list(): Node
		orders[ctx.id or "sidebar"] = function(): { string }
			local shut = folded:peek()
			local keys: { string } = {}
			for _, e in plan:peek() do
				if e.kind == "row" and not (e.section and shut[e.section]) and e.section ~= "archived" then
					table.insert(keys, (e.session :: Session).key)
				end
			end
			return keys
		end
		return ui.list {
			id = "side_list",
			label = "Sessions",
			grow = 1,
			w_full = true,
			min_h = 0,
			offset = offset,
			heights = function(): { number }
				return heights_of(plan:get())
			end,
			animate = { duration = kit.motion.d(kit.motion.COLLAPSE), ease = kit.motion.EASE_OUT },
			-- Its edges fade over 24 where it runs past (SIDEBAR_GLASS_FADE_BAND).
			fade = { 24, 24 },
			fade_overflow = true,
			-- A lifted section, wherever it is over the list.
			drop_when = function(payload: any): boolean
				return type(payload) == "table" and payload.kind == "section"
			end,
			on_drag_over = function(_payload: any, p: DragPoint)
				section_drop(p.local_y)
			end,
			on_drop = function(payload: any)
				place_section(payload.name)
			end,
			theme = { ["zeron.list.wash"] = "{zeron.glass.hover}" },
			-- Each row keyed by what it shows: rows that come or go before
			-- it move it, and only a row whose entry changes is built again.
			key = function(i: number): string
				return row_keys:at(i) or tostring(i)
			end,
			row = function(_: string, index: State<number>): Node
				return build(index:peek())
			end,
		}
	end

	-- The top: the project filter (29, 13 medium, its icon 16; the menu opens
	-- below, its chevron down) and the view options (…, 24).
	local function top(): Node
		local filter_open = ui.state("side_filter_open", false)
		local view_open = ui.state("side_view_open", false)
		-- Its groups' cards.
		local organize_open = ui.state("side_view_organize_open", false)
		local sort_open = ui.state("side_view_sort_open", false)
		local show_open = ui.state("side_view_show_open", false)
		-- A Show toggle: the menu stays up for the next.
		local function check(id: string, label: string, value: State<boolean>, glyph: string, run: (() -> ())?): any
			return {
				id = id,
				label = label,
				icon = glyph,
				icon_size = 15,
				keep_open = true,
				checked = function()
					return value:get()
				end,
				on_click = function()
					value:toggle()
					if run then
						run()
					end
				end,
			}
		end
		-- A choice: its card closes, the menu stays up.
		local function choice(
			id: string,
			label: string,
			glyph: string,
			value: State<any>,
			v: string,
			card: State<boolean>
		): any
			return {
				id = id,
				label = label,
				icon = glyph,
				icon_size = 15,
				keep_open = true,
				checked = function()
					return value:get() == v
				end,
				on_click = function()
					value:set(v)
					card:set(false)
				end,
			}
		end
		local ORGANIZED = { device = "By device", project = "By project", list = "None" }
		local SORTED = { updated = "Last updated", created = "Created" }
		return ui.row {
			w_full = true,
			px = INSET,
			pt = "$zeron.space.8",
			pb = "$zeron.space.4",
			gap = "$zeron.space.4",
			items = "center",
			-- The space switcher: as wide as the row (and its card as wide
			-- as the sidebar's gutters leave).
			ui.overlay {
				grow = 1,
				min_w = 0,
				hidden = function()
					return not show_filter:get()
				end,
				kit.project_picker.picker {
					id = "side_filter_menu",
					rows = "side_filter",
					open = filter_open,
					projects = projects_now,
					value = filter,
					label = project_label,
					offline = ctx.offline,
					w = function(): number
						return if ctx.width then ctx.width() - 2 * M.FOOTER_INSET else 240
					end,
					on_new = ctx.on_new_project,
					on_rename = function(name: string)
						asking:set(`rename_project:{name}`)
					end,
					on_remove = function(name: string)
						asking:set(`remove_project:{name}`)
					end,
					anchor = kit.project_picker.trigger {
						id = "side_filter",
						value = filter,
						open = filter_open,
						label = project_label,
						offline = ctx.offline,
					},
				},
			},
			-- With the filter hidden, the view options keep their end.
			ui.div {
				grow = 1,
				hidden = function()
					return show_filter:get()
				end,
			},
			-- The view options (spaces.rs render_sidebar_view_menu): as wide
			-- as the sidebar less 16, beside the button (6 past it, its top
			-- on the button's: anchored_menu_right). Organize and Sort (rows
			-- 30, the choice in the secondary colour, a chevron) and Show
			-- open their cards beside it (232: the heading, then the choices
			-- with their 15 glyphs and the check at the end); then Compact
			-- with its switch, and Create Section. Choosing leaves the menu up
			-- (a choice closes its card).
			kit.menu {
				id = "side_view_menu",
				open = view_open,
				w = function(): number
					return if ctx.width then ctx.width() - 16 else 240
				end :: any,
				rows = "popover",
				placement = { side = "right", align = "start", offset = 6 },
				items = {
					{
						id = "side_view_organize",
						label = "Organize",
						value = function(): string
							return ORGANIZED[organize:get()] or ""
						end,
						open = organize_open,
						checks = "end",
						submenu = {
							choice("side_view_device", "By device", "laptop", organize, "device", organize_open),
							choice("side_view_project", "By project", "folder", organize, "project", organize_open),
							choice("side_view_list", "None", "list", organize, "list", organize_open),
						},
					} :: any,
					{
						id = "side_view_sort",
						label = "Sort",
						value = function(): string
							return SORTED[sort:get()] or ""
						end,
						open = sort_open,
						checks = "end",
						submenu = {
							choice("side_view_updated", "Last updated", "clock-circle", sort, "updated", sort_open),
							choice("side_view_created", "Created", "calendar", sort, "created", sort_open),
						},
					} :: any,
					"-",
					{
						id = "side_view_show",
						label = "Show",
						open = show_open,
						checks = "end",
						submenu = {
							check("side_view_branch", "Branch", show_branch, "git-branch"),
							check("side_view_pr", "Pull request", show_pr, "pull-request"),
							check("side_view_harness", "Harness", show_harness, "bot"),
							check("side_view_icon", "Project icon", show_icon, "project-default"),
							check("side_view_project_label", "Location", show_project, "remote-server"),
							-- Hidden, it stops narrowing the list.
							check("side_view_filter", "Project filter", show_filter, "folder", function()
								if not show_filter:peek() then
									filter:set("")
								end
							end),
						},
					} :: any,
					"-",
					{
						id = "side_view_compact",
						label = "Compact",
						h = 30,
						keep_open = true,
						toggle = compact,
					} :: any,
					"-",
					{
						id = "side_view_new_section",
						label = "Create Section",
						icon = "plus",
						icon_size = 14,
						on_click = function()
							asking:set("new")
						end,
					} :: any,
				},
				-- 24, radius 6, the glass wash under the pointer and while
				-- the menu is up.
				anchor = ui.button {
					id = "side_view",
					w = 24,
					h = 24,
					p = 0,
					shrink = 0,
					items = "center",
					justify = "center",
					rounded = "$zeron.radius.6",
					variants = kit.recipes.side_control { tone = "glyph", on = view_open },
					focus = { border = 0 },
					cursor = "pointer",
					tooltip = "Sidebar view options",
					on_click = ui.toggle(view_open),
					kit.icon { name = "more-horizontal", size = 16, color = T.secondary },
				},
			},
		}
	end

	-- The footer (render_user_menu): the account pill opening its menu
	-- upward, then voice, the pull requests and settings; 8 above and
	-- below, the list's inset at its sides (Zeron's sidebar pads both 8).
	-- The pill (28, radius 8, 8 in, 8 between): the avatar (16, the
	-- initial in mono 10 semibold, the background's colour on the text's)
	-- and the label at 13 medium on a 17 line, fading out at its end when
	-- it runs long; at 80% at rest, its wash at 80% under the pointer, full
	-- while the menu is up. The buttons: 28 at radius 8, the 15 glyph
	-- secondary, primary under the glass wash (and while lit); 2 apart, 4
	-- from the pill.
	local function footer(): Node
		local account_open = ui.state("side_account_open", false)
		local function account_now(): account_mod.Account
			if ctx.account then
				return ctx.account:get()
			end
			return { scope = "synced", name = ctx.user, email = ctx.identity or ctx.user or "Local" }
		end
		local function user_line(): string
			local line = account_mod.identity(account_now())
			return line
		end
		local function button(id: string, icon: string, label: string, run: (() -> ())?, lit: (() -> boolean)?): Node
			return ui.button {
				id = id,
				w = M.FOOTER_BUTTON,
				h = M.FOOTER_BUTTON,
				p = 0,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.8",
				variants = kit.recipes.side_control { tone = "glyph", on = lit or false },
				focus = { border = 0 },
				cursor = "pointer",
				tooltip = label,
				on_click = run,
				kit.icon { name = icon :: any, size = 15, color = "currentColor" },
			}
		end
		local pill = ui.button {
			id = "side_account",
			label = "Account menu",
			h = M.FOOTER_BUTTON,
			-- The presence box the menu sits in grows to the buttons; the
			-- pill fills it (and so its menu's owner).
			w_full = true,
			min_w = 0,
			px = "$zeron.space.8",
			gap = "$zeron.space.8",
			items = "center",
			rounded = "$zeron.radius.8",
			variants = kit.recipes.side_pill { on = account_open },
			focus = { border = 0 },
			cursor = "pointer",
			on_click = ui.toggle(account_open),
			ui.row {
				id = "side_account_avatar",
				w = M.FOOTER_AVATAR,
				h = M.FOOTER_AVATAR,
				shrink = 0,
				items = "center",
				justify = "center",
				rounded = T.radius_full,
				bg = T.text,
				kit.text.text {
					function()
						local first = string.match(user_line(), "^%s*([%z\1-\127\194-\244][\128-\191]*)")
						return string.upper(first or "?")
					end,
					size = "micro",
					weight = "semibold",
					mono = true,
					color = T.bg,
					line_height = ui.raw(M.FOOTER_AVATAR, "the avatar's own height"),
				},
			},
			-- The label fades over its last 20 as it runs past the pill
			-- (sidebar_faded_label), rather than ending in "…".
			kit.text.text {
				user_line,
				id = "side_account_label",
				size = "md",
				weight = "medium",
				color = "inherit",
				line_height = ui.raw(17, "Zeron's 17 line under the 13 label"),
				fade = M.FADE,
				grow = 1,
			},
		}
		-- The menu (popover_card, w the sidebar's less its insets, the
		-- settings button and the gap before it): the identity line, then
		-- what the account offers as the workspace syncs. It opens upward,
		-- 6 over the pill, its left edge on the pill's.
		local account_menu = ui.presence(function(): string
			local a = account_now()
			local _, identity = account_mod.identity(a)
			return `{account_mod.menu_action(a) or ""}|{identity}`
		end, function(key: string): Node
			local action, identity = string.match(key, "^([^|]*)|(.*)$")
			local items: { any } = { { note = identity } }
			if action == "enable_sync" then
				table.insert(items, {
					id = "side_account_enable_sync",
					label = "Enable sync",
					icon = "global",
					on_click = ctx.on_enable_sync,
				})
			elseif action == "sync_in_progress" then
				table.insert(items, {
					id = "side_account_sync_progress",
					label = "Sync setup in progress",
					icon = "global",
					faded = true,
				})
			elseif action == "restart_pending" then
				table.insert(items, {
					id = "side_account_sync_restart",
					label = "Finish sync setup",
					icon = "restart",
					on_click = ctx.on_finish_sync,
				})
			elseif action == "sign_out" then
				table.insert(items, {
					id = "side_account_sign_out",
					label = "Sign out",
					icon = "logout-2",
					on_click = ctx.on_sign_out,
				})
			end
			if ctx.on_check_updates then
				local check = ctx.on_check_updates
				table.insert(items, {
					id = "side_account_check_updates",
					label = "Check for updates",
					icon = "refresh",
					on_click = check,
				})
			end
			return kit.menu {
				id = "side_account_menu",
				open = account_open,
				rows = "popover",
				w = function(): number
					if ctx.width then
						return ctx.width() - 2 * M.FOOTER_INSET - M.FOOTER_BUTTON - M.FOOTER_GAP
					end
					return 240
				end :: any,
				placement = { side = "top", align = "start", offset = 6 },
				items = items,
				anchor = pill,
			}
		end, { grow = 1, shrink = 1, min_w = 0 })
		local voice = if ctx.voice ~= nil then ctx.voice else ctx.on_voice ~= nil
		-- Voice (render_voice_trigger): the voice wave places a call. While
		-- one is live the call's beam in miniature takes its place and a
		-- click shows or hides the stage. A failed start explains itself in a
		-- card 6 above the button's end (232 wide: the warning glyph, the
		-- reason at 12, its ✕), a warning dot in the button's corner; the
		-- card stays through clicks elsewhere until its ✕, and the next
		-- press retries. Without Codex on the device there is none.
		local function voice_button(): Node?
			if not voice then
				return nil
			end
			local call = ctx.voice_call
			if not call then
				return button("side_voice", "voice-wave", "Start voice · Codex orchestrator", ctx.on_voice)
			end
			return ui.presence(function(): string?
				if not call.offered() then
					return nil
				end
				if call.live() then
					return if call.stage() then "hide" else "open"
				end
				return if call.failure() ~= "" then "failed" else "idle"
			end, function(kind: string): Node
				if kind == "hide" or kind == "open" then
					local hide = kind == "hide"
					return ui.button {
						id = "side_voice",
						label = if hide then "Hide voice" else "Open voice",
						w = M.FOOTER_BUTTON,
						h = M.FOOTER_BUTTON,
						p = 0,
						shrink = 0,
						items = "center",
						justify = "center",
						rounded = "$zeron.radius.8",
						variants = kit.recipes.side_control { tone = "glyph" },
						focus = { border = 0 },
						cursor = "pointer",
						tooltip = if hide then "Hide voice · Esc" else "Voice is live · open",
						on_click = call.toggle,
						call.glyph(),
					}
				end
				local failure = call.failure()
				local mic = ui.button {
					id = "side_voice",
					label = "Start voice",
					w = M.FOOTER_BUTTON,
					h = M.FOOTER_BUTTON,
					p = 0,
					shrink = 0,
					relative = true,
					items = "center",
					justify = "center",
					rounded = "$zeron.radius.8",
					variants = kit.recipes.side_control { tone = "glyph" },
					focus = { border = 0 },
					cursor = "pointer",
					tooltip = if failure ~= "" then failure else "Start voice · Codex orchestrator",
					on_click = ctx.on_voice,
					kit.icon { name = "voice-wave", size = 15, color = "currentColor" },
					if kind == "failed"
						then ui.div {
							id = "side_voice_failed",
							absolute = true,
							top = 4,
							right = 4,
							w = 5,
							h = 5,
							rounded = T.radius_full,
							bg = T.warning,
						}
						else nil,
				}
				if kind ~= "failed" then
					return mic
				end
				local open = ui.use_state(true)
				ui.effect(function()
					if not open:get() then
						call.dismiss()
					end
				end)
				return kit.popover {
					id = "side_voice_failure",
					open = open,
					anchor = mic,
					label = failure,
					dismiss_on_backdrop = false,
					w = 232,
					p = "$zeron.space.4",
					placement = kit.popover_mod.ABOVE_END,
					ui.row {
						w_full = true,
						gap = "$zeron.space.8",
						items = "start",
						ui.div {
							mt = "$zeron.space.1",
							shrink = 0,
							kit.icon { name = "danger-triangle", size = 14, color = T.warning },
						},
						kit.text.text { failure, size = "sm", color = T.secondary, wrap = true, grow = 1, min_w = 0 },
						ui.button {
							id = "side_voice_dismiss",
							label = "Dismiss",
							p = 0,
							shrink = 0,
							rounded = "$zeron.radius.4",
							focus = { border = 0 },
							cursor = "pointer",
							on_click = call.dismiss,
							kit.icon { name = "close", size = 14, color = T.tertiary },
						},
					},
				}
			end, { shrink = 0 })
		end
		return ui.row {
			id = "side_footer",
			w_full = true,
			px = INSET,
			py = "$zeron.space.8",
			gap = T.space(M.FOOTER_GAP),
			items = "center",
			shrink = 0,
			account_menu,
			ui.row {
				shrink = 0,
				gap = "$zeron.space.2",
				items = "center",
				voice_button(),
				button("nav_prs", "pull-request", "Pull requests", function()
					ctx.open("prs")
				end, function()
					return ctx.selected("prs")
				end),
				-- Its tooltip says what a click does: built again as settings
				-- open and close, so the pointer over it runs nothing.
				ui.presence(function(): boolean
					return if ctx.settings_open then ctx.settings_open() else false
				end, function(open: boolean): Node
					return button(
						"side_settings",
						"settings",
						if open then "Close settings · ⌘," else "Settings · ⌘,",
						ctx.on_settings,
						ctx.settings_open
					)
				end, { shrink = 0 }),
			},
		}
	end

	-- The question up (asking): a section's name (sidebar_sections.rs), or
	-- whether to delete a session; built only while one is.
	local function questions(): Node
		return ui.presence(function(): string?
			local a = asking:get()
			return if a == "" then nil else a
		end, function(a: string): Node
			local open = ui.use_state(true)
			ui.effect(function()
				if not open:get() then
					asking:set("")
				end
			end)
			local function close()
				open:set(false)
			end
			local project = string.match(a, "^rename_project:(.*)$")
			if project then
				local which = project :: string
				local name = ui.use_state(project_label(which))
				local function rename()
					local text = string.match(name:peek(), "^%s*(.-)%s*$") or ""
					if text ~= "" then
						project_names:set_key(which, text)
					end
					close()
				end
				return kit.dialog {
					id = "side_project_rename_dialog",
					open = open,
					title = "Rename project",
					on_enter = rename,
					kit.input {
						id = "side_project_name",
						value = name,
						placeholder = "Project name",
						w_full = true,
						select_on_focus = true,
					},
					actions = {
						kit.button {
							id = "side_project_rename_cancel",
							label = "Cancel",
							variant = "ghost",
							size = "sm",
							on_click = close,
						},
						kit.button {
							id = "side_project_rename_save",
							label = "Rename",
							variant = "primary",
							size = "sm",
							on_click = rename,
						},
					},
				}
			end
			project = string.match(a, "^remove_project:(.*)$")
			if project then
				local name = project :: string
				local count = 0
				local where = ctx.this_device or "this device"
				for _, s in sessions_now() do
					if s.project == name and not deleted:peek()[s.key] then
						count += 1
					end
				end
				return kit.dialog {
					id = "side_project_remove_dialog",
					open = open,
					title = "Remove project?",
					description = `Removing “{project_label(name)}” permanently deletes its {count} session{if count
							== 1
						then ""
						else "s"} on {where}. This can’t be undone.`,
					actions = {
						kit.button {
							id = "side_project_remove_cancel",
							label = "Cancel",
							variant = "ghost",
							size = "sm",
							on_click = close,
						},
						kit.button {
							id = "side_project_remove_confirm",
							label = "Remove",
							variant = "danger",
							size = "sm",
							on_click = function()
								projects_gone:set_key(name, true)
								if filter:peek() == name then
									filter:set("")
								end
								close()
							end,
						},
					},
				}
			end
			local key = string.match(a, "^delete:(.*)$")
			if key then
				local title = "this session"
				for _, s in sessions_now() do
					if s.key == key then
						title = title_of(s)
					end
				end
				return kit.dialog {
					id = "side_delete_dialog",
					open = open,
					title = "Delete session?",
					description = `“{title}” will be permanently deleted. This can’t be undone.`,
					actions = {
						kit.button {
							id = "side_delete_cancel",
							label = "Cancel",
							variant = "ghost",
							size = "sm",
							on_click = close,
						},
						kit.button {
							id = "side_delete_confirm",
							label = "Delete",
							variant = "danger",
							size = "sm",
							on_click = function()
								if not allowed() then
									close()
									return
								end
								deleted:set_key(key, true)
								refresh(key)
								if ctx.on_delete then
									ctx.on_delete(key)
								end
								close()
							end,
						},
					},
				}
			end
			local editing = string.match(a, "^edit:(.*)$")
			local name = ui.use_state(if editing then section_label(editing) else "")
			local function save()
				local text = string.sub(string.match(name:peek(), "^%s*(.-)%s*$") or "", 1, 120)
				if text == "" then
					return
				end
				if not allowed() then
					close()
					return
				end
				if editing then
					renamed:set_key(editing, text)
				else
					local list = table.clone(made:peek())
					table.insert(list, text)
					made:set(list)
				end
				close()
			end
			return kit.dialog {
				id = "side_section_dialog",
				open = open,
				title = if editing then "Edit section" else "New section",
				description = "Group sessions however you like",
				on_enter = save,
				kit.input {
					id = "side_section_name",
					value = name,
					placeholder = "Section name",
					w_full = true,
					select_on_focus = true,
				},
				actions = {
					kit.button {
						id = "side_section_cancel",
						label = "Cancel",
						variant = "ghost",
						size = "sm",
						on_click = close,
					},
					kit.button {
						id = "side_section_save",
						label = if editing then "Save" else "Create section",
						variant = "primary",
						size = "sm",
						disabled = function()
							return (string.match(name:get(), "^%s*(.-)%s*$") or "") == ""
						end,
						on_click = save,
					},
				},
			}
		end)
	end

	-- Over the footer, while there is something to say: the connection
	-- pill, then the update strip, right under the list (the footer's own
	-- 8 is the gap below it).
	local function notices(): Node?
		local parts: { Node } = {}
		if ctx.connection then
			local connection = ctx.connection
			table.insert(
				parts,
				ui.presence(function(): string?
					local c = connection:get()
					return if c == "connected" then nil else c
				end, function(c: string): Node
					return account_mod.connection_pill { id = "side_connection", state = c :: any }
				end, { w_full = true, px = INSET })
			)
		end
		if ctx.star then
			local star = ctx.star
			local update = ctx.update
			table.insert(
				parts,
				ui.presence(function(): boolean?
					return if star:get() then true else nil
				end, function(_: boolean): Node
					return account_mod.star_banner {
						on_open = ctx.on_star,
						on_dismiss = function()
							star:set(false)
						end,
					}
				end, {
					w_full = true,
					px = INSET,
					-- 4 over the strip, when there is one.
					pb = function()
						return if update and update:get() then "$zeron.space.4" else 0
					end,
				})
			)
		end
		if ctx.update then
			local update = ctx.update
			table.insert(
				parts,
				ui.presence(function(): string?
					local u = update:get()
					return if u then `{u.state}|{u.version or ""}|{u.detail or ""}` else nil
				end, function(_key: string): Node
					local now = update:peek() :: account_mod.Update
					return account_mod.update_strip {
						id = "update_strip",
						state = now.state,
						version = now.version,
						detail = now.detail,
						on_click = function()
							if ctx.on_update then
								ctx.on_update(now)
							end
						end,
					}
				end, { w_full = true, px = INSET })
			)
		end
		if #parts == 0 then
			return nil
		end
		return ui.column { w_full = true, shrink = 0, table.unpack(parts) }
	end

	return ui.column {
		id = ctx.id or "sidebar",
		w_full = true,
		h_full = true,
		ctx.head,
		top(),
		list(),
		notices(),
		footer(),
		questions(),
	}
end

return M
