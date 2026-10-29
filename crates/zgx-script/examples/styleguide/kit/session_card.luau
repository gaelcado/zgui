-- The session card (Zeron's shell/session_info.rs, session_lanes.rs): where
-- the chat runs (its device, its project, its branch with what it adds over
-- its base) and the project's actions; under it the ports card (the servers
-- its agents started, only while one runs) and the lanes card (its side
-- chats and subagents). 272 wide, 12 in from the column's top right, the
-- cards 8 apart; rows 32, the cards 4 in, their rows 2 apart. Floating
-- over the transcript a card casts the popover's shadow (when opaque).
local T = require("../theme")
local recipes = require("./recipes")
local txt = require("./text")
local glyph = require("./icon")
local icon_mod = require("./icon")
local loaders = require("./loaders")
local frost = require("./frost")
local menu = require("./menu")
local project_icon = require("./project_icon")
local pr_badge = require("./pr")
local actions_pill = require("./actions_pill")
local disclosure = require("./disclosure")

export type Status = "working" | "input" | "failed" | "done" | "idle"
export type Harness = { icon: string, tint: Color? }
export type Info = {
	device: string,
	-- "laptop" this machine, "monitor" another, "cloud" a Cloud one.
	device_icon: icon_mod.Name?,
	-- A Cloud machine asleep: it wakes on the next send.
	asleep: (() -> boolean)?,
	project: string?,
	-- Where the project's checkout is (its row's tooltip).
	project_path: string?,
	branch: string?,
	-- What the branch adds over its base: { additions, deletions }.
	diff: { number }?,
}
export type Action = { id: string, name: string, command: string?, icon: actions_pill.Kind, setup: boolean? }
export type SideChat = {
	key: string,
	row: string,
	title: string,
	status: Status,
	harness: Harness?,
	pr: { number: number, state: string }?,
	ago: string,
}
export type Subagent = { id: string, title: string, status: "running" | "done" | "failed", ago: string }
export type Port = { id: string, name: string, port: number, url: string }
export type Props = {
	-- Its ids' prefix.
	prefix: string,
	-- Each card's element, for a press on them.
	ref: Ref?,
	info: Info,
	-- Over the transcript (a popover), not beside it.
	floating: boolean?,
	-- The project's actions and those its zeron.json offers; without
	-- them the card has no Actions section.
	actions: State<{ Action }>?,
	imports: State<{ Action }>?,
	ports: { Port }?,
	side_chats: State<{ SideChat }>,
	subagents: { Subagent }?,
	-- The session's harness: its subagents run on it.
	harness: Harness?,
	-- Its room: the cards stack at its top, the ports past a third of
	-- it scrolling, the lanes past half.
	h: Length?,
	on_diff: (() -> ())?,
	on_run: ((action: Action) -> ())?,
	on_edit: ((action: Action) -> ())?,
	on_import: ((action: Action) -> ())?,
	on_add_action: (() -> ())?,
	on_port: ((port: Port) -> ())?,
	on_side_chat: ((key: string) -> ())?,
	on_subagent: ((id: string) -> ())?,
	on_new_side_chat: (() -> ())?,
	on_fork: (() -> ())?,
}

local M = {}

M.WIDTH = 272
M.INSET = 12
-- The least gap the reading column keeps from it.
M.GAP = 24
-- Between the session card and the cards under it.
M.CARDS_GAP = 8
-- A lane shows this many, then pages in more.
M.INITIAL_ROWS = 8
M.PAGE_ROWS = 10
M.PORTS_INITIAL = 3

local ACTION_ICON: { [actions_pill.Kind]: icon_mod.Name } = {
	play = "action-play",
	test = "action-test",
	lint = "action-lint",
	configure = "action-configure",
	build = "action-build",
	debug = "action-debug",
}
M.ACTION_ICON = ACTION_ICON

local TONE: { [Status]: string } = {
	working = "$zeron.side.status.working",
	input = "$zeron.side.status.input",
	failed = "$zeron.side.status.failed",
	done = "$zeron.side.status.done",
	idle = "$zeron.side.status.idle",
}

-- A glyph in the rows' 16 slot, so every label starts at one edge.
local function slot(child: Node?): Node
	return ui.row { w = 16, h = 16, shrink = 0, items = "center", justify = "center", child }
end
local function row_glyph(name: icon_mod.Name): Node
	return glyph { name = name, size = 15, color = T.secondary }
end

-- A row that does nothing (info_row): the slot, the label at 13.
local function info_row(id: string, art: Node, label: string, tooltip: string?, trailing: Node?): Node
	return ui.row {
		id = id,
		w_full = true,
		min_h = 32,
		px = "$zeron.space.9",
		gap = "$zeron.space.8",
		items = "center",
		tooltip = tooltip,
		slot(art),
		txt.text { label, size = "md", line = false, truncate = true, grow = 1, shrink = 1, min_w = 0, literal = true },
		trailing,
	}
end

-- "Asleep" (asleep_badge): 20 high, 7 in, radius 6, the muted text at
-- 14% under 11 medium.
local function asleep_badge(id: string): Node
	return ui.row {
		id = id,
		h = 20,
		px = "$zeron.space.7",
		shrink = 0,
		items = "center",
		rounded = "$zeron.radius.6",
		bg = T.ink4,
		txt.text { "Asleep", size = "xs", weight = "medium", color = T.secondary, line = false },
	}
end

-- A row that acts (popover.rs picker_row): 32 at radius 7, 8 in, washed
-- under the pointer.
local function picker_row(props: { [any]: any }): Node
	local node: { [any]: any } = {
		w_full = true,
		min_h = 32,
		px = "$zeron.space.8",
		py = 0,
		gap = "$zeron.space.8",
		items = "center",
		rounded = T.concentric(12, frost.INSET, 1),
		variants = recipes.wash { hover = "ink1" },
		focus = { border = 0 },
		cursor = "pointer",
	}
	for k, v in props do
		node[k] = v
	end
	return ui.button(node :: any)
end

-- A 22 icon button on a row or a heading: radius 5, ink at 8% under the
-- pointer.
local function small_button(id: string, icon: icon_mod.Name, label: string, run: () -> (), hover_only: string?): Node
	return ui.button {
		id = id,
		label = label,
		tooltip = label,
		w = 22,
		h = 22,
		p = 0,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.5",
		variants = recipes.wash { hover = "ink3" },
		focus = { border = 0 },
		cursor = "pointer",
		-- Shown only under its row's pointer.
		opacity = if hover_only then 0 else nil,
		group_hover = if hover_only then { opacity = 1 } else nil,
		on_click = run,
		glyph { name = icon, size = 14, color = T.secondary },
	}
end

-- "Show N more" under a paged list, its label lined up with the rows'.
local function more(id: string, count: () -> number, run: () -> ()): Node
	return picker_row {
		id = id,
		label = "Show more",
		on_click = run,
		slot(nil),
		txt.text {
			function()
				return `Show {count()} more`
			end,
			size = "sm",
			color = T.secondary,
			line = false,
		},
	}
end

-- A card of the stack: frost, its rows 4 in, as tall as they are up to
-- `max_h` (a share of the stack's room), then scrolling, the edges fading
-- over 12 as a menu's. Only the lanes `give` when the room runs out.
local function surface(id: string, props: Props, max_h: Length, rows: { Child }, give: boolean?): Node
	return ui.scroll {
		id = id,
		ref = props.ref,
		w = M.WIDTH,
		shrink = if give then 1 else 0,
		min_h = if give then 0 else nil,
		max_h = max_h,
		p = 0,
		gap = 0,
		variants = recipes.frost { lifted = props.floating == true },
		fade = { 12, 12 },
		fade_overflow = true,
		-- A press on its padding stays on it.
		on_click = function() end,
		ui.column { w_full = true, p = T.space(frost.INSET), gap = "$zeron.space.2", rows },
	}
end

-- A status in a row's slot: Working spins, Done checks, the rest a dot
-- in its tone.
function M.status_mark(status: Status, id: string): Node
	if status == "working" then
		return loaders.mini_spinner { id = id }
	elseif status == "done" then
		return glyph { name = "check", size = 12, color = TONE.done }
	end
	return ui.div { w = 6, h = 6, shrink = 0, rounded = T.radius_full, bg = TONE[status] }
end

local function harness_mark(h: Harness?): Node?
	return h and glyph { name = h.icon :: any, size = 13, color = h.tint or T.secondary, opacity = 0.8 }
end

local function time_label(ago: string): Node
	return txt.text { ago, size = "xs", color = T.secondary, line = false, shrink = 0 }
end

-- The session card's own rows: where it runs, then the Actions.
local function session_rows(props: Props): { Child }
	local info = props.info
	local p = props.prefix
	local rows: { Child } = {
		if info.asleep
			then ui.presence(info.asleep, function(asleep: boolean): Node
				return info_row(
					`{p}_device`,
					row_glyph(info.device_icon or "laptop"),
					info.device,
					if asleep then "Asleep — wakes when you send" else nil,
					if asleep then asleep_badge(`{p}_asleep`) else nil
				)
			end, { w_full = true })
			else info_row(`{p}_device`, row_glyph(info.device_icon or "laptop"), info.device),
		if info.project
			then info_row(
				`{p}_project`,
				project_icon.icon { name = info.project, size = 16 },
				info.project,
				info.project_path
			)
			else info_row(`{p}_project`, row_glyph("home"), "No project"),
	}
	if info.branch then
		local diff = info.diff
		table.insert(
			rows,
			info_row(
				`{p}_branch`,
				row_glyph("git-branch"),
				info.branch,
				info.branch,
				-- What the branch adds over its base; it opens that diff.
				diff
						and (diff[1] + diff[2] > 0)
						and ui.button {
							id = `{p}_diff`,
							label = "Branch changes",
							tooltip = "Branch changes",
							shrink = 0,
							px = "$zeron.space.5",
							py = "$zeron.space.2",
							mr = T.pull(5),
							gap = "$zeron.space.6",
							items = "center",
							rounded = "$zeron.radius.5",
							variants = recipes.wash { hover = "ink3" },
							focus = { border = 0 },
							cursor = "pointer",
							on_click = props.on_diff,
							txt.text { `+{diff[1]}`, size = "xs", mono = true, color = T.diff_add, line = false },
							txt.text { `−{diff[2]}`, size = "xs", mono = true, color = T.diff_del, line = false },
						}
					or nil
			)
		)
	end
	local actions = props.actions
	if actions then
		local imports = props.imports
		table.insert(rows, menu.separator())
		table.insert(rows, menu.heading("Actions"))
		table.insert(
			rows,
			ui.each(actions, function(a: Action): Node
				-- The gear shows under the row's pointer and edits it.
				local group = `{p}_action_{a.id}`
				return picker_row {
					id = `{p}_action_{a.id}`,
					label = `Run {a.name}`,
					hover_group = group,
					on_click = function()
						if props.on_run then
							props.on_run(a)
						end
					end,
					slot(row_glyph(ACTION_ICON[a.icon])),
					txt.text {
						if a.setup then `{a.name} (setup)` else a.name,
						size = "md",
						line = false,
						truncate = true,
						grow = 1,
						shrink = 1,
						min_w = 0,
						literal = true,
					},
					small_button(`{p}_edit_action_{a.id}`, "settings-minimalistic", "Edit action", function()
						if props.on_edit then
							props.on_edit(a)
						end
					end, group),
				}
			end, {
				key = function(a: Action): string
					return a.id
				end,
				w_full = true,
				gap = "$zeron.space.2",
			})
		)
		if imports then
			table.insert(
				rows,
				ui.each(imports, function(a: Action, i: number): Node
					return picker_row {
						id = `{p}_import_{i}`,
						label = `Import {a.name}`,
						on_click = function()
							if props.on_import then
								props.on_import(a)
							end
						end,
						slot(row_glyph(ACTION_ICON[a.icon])),
						txt.text { a.name, size = "md", line = false, truncate = true, grow = 1, shrink = 1, min_w = 0 },
						txt.text { "Import", size = "xs", color = T.secondary, line = false, shrink = 0 },
					}
				end, {
					key = function(a: Action): string
						return a.name
					end,
					w_full = true,
					gap = "$zeron.space.2",
				})
			)
		end
		table.insert(
			rows,
			picker_row {
				id = `{p}_add_action`,
				label = "Add action",
				on_click = props.on_add_action,
				slot(row_glyph("plus")),
				txt.text { "Add action", size = "md", line = false },
			}
		)
	end
	return rows
end

-- The ports card: a row per server, the first three, then pages of ten.
local function ports_card(props: Props, ports: { Port }): Node
	local p = props.prefix
	local shown = ui.use_state(M.PORTS_INITIAL)
	local rows: { Child } = { menu.heading("Ports") }
	for i, port in ports do
		table.insert(
			rows,
			ui.show(
				function()
					return i <= shown:get()
				end,
				picker_row {
					id = `{p}_port_{port.id}`,
					label = `Open {port.name}`,
					tooltip = port.url,
					on_click = function()
						if props.on_port then
							props.on_port(port)
						end
					end,
					slot(row_glyph("globe")),
					txt.text {
						port.name,
						size = "md",
						line = false,
						truncate = true,
						grow = 1,
						shrink = 1,
						min_w = 0,
						literal = true,
					},
					txt.text { `:{port.port}`, size = "xs", mono = true, color = T.secondary, line = false },
				}
			)
		)
	end
	table.insert(
		rows,
		ui.show(
			function()
				return #ports > shown:get()
			end,
			more(`{p}_ports_more`, function()
				return math.min(#ports - shown:get(), M.PAGE_ROWS)
			end, function()
				shown:set(shown:peek() + M.PAGE_ROWS)
			end)
		)
	)
	return surface(`{p}_ports`, props, "33%", rows)
end

-- The lanes card: the side chats (starters while there are none, then
-- icon buttons on the heading so the chats lead), then the subagents, the
-- settled ones folded into one row.
local function lanes_card(props: Props): Node
	local p = props.prefix
	local shown = ui.use_state(M.INITIAL_ROWS)
	local finished_open = ui.use_state(false)
	local shown_finished = ui.use_state(M.INITIAL_ROWS)
	local chats = props.side_chats
	local function none(): boolean
		return #chats:get() == 0
	end
	local function start(fork: boolean)
		return function()
			local run = if fork then props.on_fork else props.on_new_side_chat
			if run then
				run()
			end
		end
	end
	local rows: { Child } = {
		ui.row {
			w_full = true,
			pr = "$zeron.space.2",
			items = "center",
			ui.column { grow = 1, menu.heading("Side chats") },
			ui.show(
				function()
					return not none()
				end,
				ui.row {
					gap = "$zeron.space.2",
					small_button(`{p}_side_chat_new`, "plus", "New side chat", start(false)),
					small_button(`{p}_fork`, "fork", "Fork chat", start(true)),
				}
			),
		},
		ui.show(
			none,
			ui.column {
				w_full = true,
				gap = "$zeron.space.2",
				picker_row {
					id = `{p}_side_chat`,
					label = "New side chat",
					on_click = start(false),
					slot(row_glyph("plus")),
					txt.text { "New side chat", size = "md", line = false },
				},
				picker_row {
					id = `{p}_fork_row`,
					label = "Fork chat",
					on_click = start(true),
					slot(row_glyph("fork")),
					txt.text { "Fork chat", size = "md", line = false },
				},
			}
		),
		ui.each(
			ui.computed(function(): { SideChat }
				local all = chats:get()
				return table.move(all, 1, math.min(#all, shown:get()), 1, {})
			end),
			function(c: SideChat): Node
				return picker_row {
					id = `{p}_lane_{c.row}`,
					label = `Open side chat {c.title}`,
					on_click = function()
						if props.on_side_chat then
							props.on_side_chat(c.key)
						end
					end,
					slot(M.status_mark(c.status, `{p}_lane_{c.row}_status`)),
					-- The harness mark leads the title, as on the sidebar's rows.
					harness_mark(c.harness),
					txt.faded {
						c.title,
						id = `{p}_lane_{c.row}_title`,
						size = "md",
						line = false,
						fade = 20,
						grow = 1,
						literal = true,
					},
					c.pr and pr_badge.badge { tone = c.pr.state :: any, number = c.pr.number } or nil,
					time_label(c.ago),
				}
			end,
			{
				key = function(c: SideChat): string
					return c.key
				end,
				w_full = true,
				gap = "$zeron.space.2",
			}
		),
		ui.show(
			function()
				return #chats:get() > shown:get()
			end,
			more(`{p}_lanes_more`, function()
				return math.min(#chats:get() - shown:get(), M.PAGE_ROWS)
			end, function()
				shown:set(shown:peek() + M.PAGE_ROWS)
			end)
		),
	}
	local subagents = props.subagents or {}
	if #subagents > 0 then
		local active: { Subagent } = {}
		local finished: { Subagent } = {}
		for _, s in subagents do
			table.insert(if s.status == "running" then active else finished, s)
		end
		local function sub_row(s: Subagent): Node
			local status: Status = if s.status == "running"
				then "working"
				elseif s.status == "done" then "done"
				else "failed"
			local trailing = ui.row {
				shrink = 0,
				gap = "$zeron.space.8",
				items = "center",
				harness_mark(props.harness),
				time_label(s.ago),
			}
			local open = props.on_subagent
			if open then
				-- A row opens the subagent's transcript in a tab.
				return picker_row {
					id = `{p}_subagent_{s.id}`,
					label = `Open subagent {s.title}`,
					on_click = function()
						open(s.id)
					end,
					slot(M.status_mark(status, `{p}_subagent_{s.id}_status`)),
					txt.text {
						s.title,
						size = "md",
						line = false,
						truncate = true,
						grow = 1,
						shrink = 1,
						min_w = 0,
						literal = true,
					},
					trailing,
				}
			end
			return info_row(
				`{p}_subagent_{s.id}`,
				M.status_mark(status, `{p}_subagent_{s.id}_status`),
				s.title,
				nil,
				trailing
			)
		end
		table.insert(rows, menu.separator())
		table.insert(rows, menu.heading("Subagents"))
		for _, s in active do
			table.insert(rows, sub_row(s))
		end
		if #finished > 0 then
			table.insert(
				rows,
				picker_row {
					id = `{p}_lanes_finished`,
					label = `{#finished} finished subagents`,
					on_click = ui.toggle(finished_open),
					slot(disclosure.chevron { open = finished_open, size = 12, color = T.secondary }),
					txt.text { `{#finished} finished`, size = "md", color = T.secondary, line = false, grow = 1 },
				}
			)
			for i, s in finished do
				table.insert(
					rows,
					ui.show(function()
						return finished_open:get() and i <= shown_finished:get()
					end, sub_row(s))
				)
			end
			table.insert(
				rows,
				ui.show(
					function()
						return finished_open:get() and #finished > shown_finished:get()
					end,
					more(`{p}_finished_more`, function()
						return math.min(#finished - shown_finished:get(), M.PAGE_ROWS)
					end, function()
						shown_finished:set(shown_finished:peek() + M.PAGE_ROWS)
					end)
				)
			)
		end
	end
	return surface(`{p}_lanes`, props, "50%", rows, true)
end

-- The card and the cards under it, its ids under `props.prefix`.
M.card = ui.component(function(props: Props): Node
	return ui.column {
		id = `{props.prefix}_session_card`,
		w = M.WIDTH,
		h = props.h,
		gap = T.space(M.CARDS_GAP),
		pointer_events = "none",
		-- The session's own rows keep their height; past the room they scroll.
		surface(`{props.prefix}_session_info`, props, "100%", session_rows(props)),
		props.ports and #props.ports > 0 and ports_card(props, props.ports) or nil,
		lanes_card(props),
	}
end)

return M
