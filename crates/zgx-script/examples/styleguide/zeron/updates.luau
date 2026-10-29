-- Home's agent-update island (shell/harness_updates.rs): one surface at the
-- new-session canvas's foot for the coding agents' updates. Compact, it is
-- a pill (38 high) saying what is new with the agents' marks overlapping,
-- and with one update its action (Update, View steps, Cancel, Retry
-- update, Check again); with several its chevron opens it into a list
-- (360 wide, rows 64, three and a half before it scrolls), each agent's
-- state and action. An update waits for the agent's run under way, then
-- steps through Preparing, Downloading, Installing and Verifying to
-- Updated; Cancel stops it before installing. While the engine is away a
-- row says so, its engine's actions inert.
-- Newly found releases post one banner a second after they arrive. Sample
-- statuses until the engine watches the devices.
local T = require("../theme")
local kit = require("@kit")
local data = require("./data")
local notify = require("./notify")

local M = {}

export type Phase =
	"checking"
	| "current"
	| "available"
	| "waiting"
	| "preparing"
	| "downloading"
	| "installing"
	| "verifying"
	| "updated"
	| "failed"
export type Status = {
	harness: string,
	device: string,
	phase: Phase,
	installed: string?,
	latest: string?,
	-- Zeron can apply it itself; otherwise its steps are in Settings.
	can_apply: boolean,
	-- What failed: the update itself, or checking for one.
	failure: ("install" | "check")?,
	error: string?,
	manual: string?,
	progress: string?,
}

M.NAMES = {
	claude = "Claude Code",
	codex = "Codex",
	cursor = "Cursor",
	opencode = "OpenCode",
} :: { [string]: string }
local MARKS = {
	claude = { icon = "claude-mark", tint = T.claude },
	codex = { icon = "openai-mark" },
	cursor = { icon = "cursor-mark" },
	opencode = { icon = "opencode-mark" },
} :: { [string]: { icon: string, tint: Color? } }

M.SAMPLE = {
	{
		harness = "claude",
		device = data.THIS,
		phase = "available",
		installed = "2.1.3",
		latest = "2.1.4",
		can_apply = true,
	},
	{
		harness = "codex",
		device = data.THIS,
		phase = "available",
		installed = "0.48.0",
		latest = "0.49.1",
		can_apply = true,
	},
	{
		harness = "cursor",
		device = data.THIS,
		phase = "available",
		latest = "1.7",
		can_apply = false,
		manual = "curl https://cursor.com/install -fsS | bash",
	},
	{
		harness = "opencode",
		device = data.THIS,
		phase = "failed",
		failure = "check",
		error = "Couldn’t reach the npm registry",
		can_apply = false,
	},
} :: { Status }

M.statuses = ui.state("upd_statuses", table.clone(M.SAMPLE) :: { Status })
M.expanded = ui.state("upd_expanded", false)
-- Each step of an update, in ms.
M.STEP = 500

-- What the island shows: updates found, under way, done or failed.
local function shown(s: Status): boolean
	return s.phase ~= "checking" and s.phase ~= "current"
end
local function active(s: Status): boolean
	if s.phase == "waiting" then
		return true
	end
	return s.phase == "preparing" or s.phase == "downloading" or s.phase == "installing" or s.phase == "verifying"
end
function M.visible(): { Status }
	local out: { Status } = {}
	for _, s in M.statuses:get() do
		if shown(s) then
			table.insert(out, s)
		end
	end
	return out
end

local function index(harness: string): number?
	for i, s in M.statuses:peek() do
		if s.harness == harness then
			return i
		end
	end
	return nil
end
local function set(harness: string, fields: { [string]: any })
	local i = index(harness)
	if not i then
		return
	end
	local s = table.clone(M.statuses:peek()[i]) :: any
	for k, v in fields do
		s[k] = v
	end
	-- Fields set to false are cleared.
	for k, v in s do
		if v == false and k ~= "can_apply" then
			s[k] = nil
		end
	end
	M.statuses:set_key(i, s)
end

-- Each harness's update in flight: a later step for a cancelled one is
-- dropped.
local runs: { [string]: number } = {}
local failed_once: { [string]: boolean } = {}

function M.update(harness: string)
	runs[harness] = (runs[harness] or 0) + 1
	local this = runs[harness]
	local s = M.statuses:peek()[index(harness) or 0]
	if not s then
		return
	end
	local steps: { { phase: Phase, progress: string? } } = {
		{ phase = "preparing" },
		{ phase = "downloading", progress = "Downloading 18.2 MB…" },
		{ phase = "installing" },
		{ phase = "verifying" },
	}
	-- An agent at work finishes its run first (WaitingForIdle).
	local conversation = require("./conversation")
	if conversation.busy(harness) then
		set(harness, { phase = "waiting", failure = false, error = false })
		local function wait()
			ui.after(M.STEP, function()
				if runs[harness] ~= this then
					return
				elseif conversation.busy(harness) then
					wait()
				else
					M.update(harness)
				end
			end)
		end
		wait()
		return
	end
	set(harness, { phase = "preparing", failure = false, error = false })
	for k = 2, #steps + 1 do
		ui.after(M.STEP * (k - 1), function()
			if runs[harness] ~= this then
				return
			end
			local next = steps[k]
			-- Codex's first download breaks off: the update failed, its
			-- release still known.
			if harness == "codex" and k == 3 and not failed_once[harness] then
				failed_once[harness] = true
				runs[harness] += 1
				set(harness, { phase = "failed", failure = "install", error = "The download was interrupted" })
				return
			end
			if next then
				set(harness, { phase = next.phase, progress = next.progress or false })
			else
				set(harness, { phase = "updated", installed = s.latest or false, progress = false })
			end
		end)
	end
end

function M.cancel(harness: string)
	runs[harness] = (runs[harness] or 0) + 1
	set(harness, { phase = "available", progress = false })
end

function M.check(harness: string)
	runs[harness] = (runs[harness] or 0) + 1
	local this = runs[harness]
	set(harness, { phase = "checking", failure = false, error = false })
	ui.after(M.STEP, function()
		if runs[harness] == this then
			set(harness, { phase = "available", installed = "1.4.0", latest = "1.4.2", can_apply = true })
		end
	end)
end

-- Its steps: Settings, on the agents' page.
local function view_steps()
	M.expanded:set(false)
	local settings = require("./settings")
	settings.section:set("harnesses")
	require("./state").settings:set(true)
end

-- The action a status offers: its label, what it runs, whether it is
-- the filled one.
local function action(s: Status): (string?, (() -> ())?, boolean)
	local h = s.harness
	if s.phase == "available" and s.can_apply then
		return "Update", function()
			M.update(h)
		end, true
	elseif s.phase == "available" then
		return "View steps", view_steps, false
	elseif s.phase == "waiting" or s.phase == "preparing" or s.phase == "downloading" then
		return "Cancel", function()
			M.cancel(h)
		end, false
	elseif s.phase == "failed" and s.failure == "install" then
		return "Retry update", function()
			M.update(h)
		end, true
	elseif s.phase == "failed" then
		return "Check again", function()
			M.check(h)
		end, false
	end
	return nil, nil, false
end

local function name(s: Status): string
	return M.NAMES[s.harness] or s.harness
end

function M.detail(s: Status): string
	local p = s.phase
	if p == "available" then
		if s.installed and s.latest then
			return `{s.installed} → {s.latest}`
		end
		return if s.latest then `Version {s.latest} available` else "Update available"
	elseif p == "waiting" then
		return "Waiting for the current run"
	elseif p == "preparing" then
		return "Preparing update…"
	elseif p == "downloading" then
		return s.progress or "Downloading…"
	elseif p == "installing" then
		return "Installing…"
	elseif p == "verifying" then
		return "Verifying installation…"
	elseif p == "updated" then
		return if s.installed then `Updated to {s.installed}` else "Updated"
	elseif p == "failed" then
		return s.error or (if s.failure == "install" then "Update failed" else "Couldn’t check for updates")
	end
	return "Checking for updates…"
end

-- The compact line: one update's state, or how many.
function M.title(): string
	local list = M.visible()
	local first = list[1]
	if not first then
		return ""
	end
	local title: string
	if #list > 1 then
		local all = true
		for _, s in list do
			all = all and s.phase == "updated"
		end
		title = if all then `{#list} agents updated` else `{#list} agent updates`
	else
		local n, p = name(first), first.phase
		if p == "available" then
			title = if first.latest then `{n} {first.latest} available` else `{n} update available`
		elseif p == "waiting" then
			title = `{n} · waiting for idle`
		elseif p == "preparing" then
			title = `Preparing {n}…`
		elseif p == "downloading" then
			title = `Downloading {n}…`
		elseif p == "installing" then
			title = `Updating {n}…`
		elseif p == "verifying" then
			title = `Verifying {n}…`
		elseif p == "updated" then
			title = `{n} updated`
		elseif first.failure == "install" then
			title = `{n} update failed`
		else
			title = `{n} update check failed`
		end
	end
	local devices: { string } = {}
	for _, s in list do
		if not table.find(devices, s.device) then
			table.insert(devices, s.device)
		end
	end
	return if #devices == 1 then `{title} · {devices[1]}` else `{title} · {#devices} devices`
end

-- ---- the banner ---------------------------------------------------------------

-- Releases already announced, by device, harness and version.
local announced: { [string]: boolean } = {}
local pending = false
local function key(s: Status): string?
	if s.phase ~= "available" then
		return nil
	end
	return `{s.device}:{s.harness}:{s.latest or "versionless"}`
end
local function announce()
	local new: { string } = {}
	for _, s in M.statuses:peek() do
		local k = key(s)
		if k and not announced[k] then
			table.insert(new, k)
		end
	end
	if #new == 0 then
		return
	end
	for _, k in new do
		announced[k] = true
	end
	local n = #new
	notify.banner(
		if n == 1 then "1 agent update available" else `{n} agent updates available`,
		if n == 1 then "A coding agent update is ready" else "Coding agent updates are ready"
	)
end
-- Releases arrive one by one: a second after the first, one banner.
ui.effect(function()
	for _, s in M.statuses:get() do
		local k = key(s)
		if k and not announced[k] and not pending then
			pending = true
			ui.after(1000, function()
				pending = false
				announce()
			end)
		end
	end
end)

-- ---- drawing ------------------------------------------------------------------

local CHIP = 38
local ROW = 64
local LIST_W = 360
local MARK = 22
local MARK_STEP = 14

local card_ref = ui.ref()

-- A press outside the open list folds it (the root's on_press).
function M.press(e: PointerEvent)
	if not M.expanded:peek() then
		return
	end
	for _, el in card_ref:elements() do
		if el.x and el.y and el.width and el.height then
			if e.x >= el.x and e.x <= el.x + el.width and e.y >= el.y and e.y <= el.y + el.height then
				return
			end
		end
	end
	M.expanded:set(false)
end

local function mark(s: Status, size: number): Node
	local m = MARKS[s.harness]
	return kit.icon {
		name = (if m then m.icon else "bot") :: any,
		size = size,
		color = if m and m.tint then m.tint else T.secondary,
	}
end

-- The marks overlapping, in the list's order (a phase change never
-- reshuffles them): three at most.
local function marks(list: { Status }): Node
	local n = math.min(#list, 3)
	local items: { Node } = {}
	for i = n, 1, -1 do
		table.insert(
			items,
			ui.row {
				absolute = true,
				left = ui.raw((i - 1) * MARK_STEP, "the marks' overlap"),
				top = 0,
				w = MARK,
				h = MARK,
				items = "center",
				justify = "center",
				rounded = T.radius_full,
				bg = if n > 1 then T.raised else T.clear,
				border = if n > 1 then 1 else 0,
				border_color = T.input_border,
				mark(list[i], 16),
			}
		)
	end
	return ui.div {
		relative = true,
		shrink = 0,
		w = ui.raw(MARK + MARK_STEP * (n - 1), "the marks' stack"),
		h = MARK,
		items,
	}
end

-- Whether the engine reaches the agents' devices now.
local function connected(): boolean
	return require("./account").connection:get() ~= "offline"
end

local function button(s: Status, prefix: string): Node?
	local label, run, primary = action(s)
	if not label then
		return nil
	end
	-- Steps in Settings are this window's; the rest is the engine's.
	local inert = not connected() and run ~= view_steps
	return ui.button {
		id = `{prefix}_{s.harness}`,
		label = `{label} · {name(s)} · {s.device}`,
		h = 26,
		px = "$zeron.space.9",
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = T.radius_full,
		bg = if primary then T.solid else T.ink3,
		color = if primary then T.on_solid else T.secondary,
		hover = if inert then nil else { opacity = 0.85 },
		opacity = if inert then 0.38 else 1,
		focus = { border = 0 },
		cursor = if inert then nil else "pointer",
		on_click = if inert then nil else run,
		kit.text.text { label, size = "xs", weight = "medium", color = "inherit", line = false },
	}
end

local function summary(list: { Status }, opening: boolean): Node
	local multiple = #list > 1
	local first = list[1]
	local busy, all_done = false, true
	for _, s in list do
		busy = busy or active(s)
		all_done = all_done and s.phase == "updated"
	end
	local glyph: Node? = nil
	if busy then
		glyph = kit.loaders.mini_spinner { color = T.secondary }
	elseif all_done then
		glyph = kit.icon { name = "check", size = 14, color = T.success }
	elseif not multiple and first.phase == "failed" then
		glyph = kit.icon { name = "danger-triangle", size = 14, color = T.danger }
	end
	local act = if multiple then nil else button(first, "update_action")
	return ui.button {
		id = "update_summary",
		label = if multiple
			then (if M.expanded:peek() then "Collapse agent updates" else "Show agent updates")
			else M.title(),
		w_full = true,
		h = CHIP - 2,
		shrink = 0,
		pl = "$zeron.space.12",
		pr = if multiple then "$zeron.space.8" elseif act then "$zeron.space.5" else "$zeron.space.12",
		gap = "$zeron.space.8",
		items = "center",
		focusable = multiple,
		focus = { border = 0 },
		cursor = if multiple then "pointer" else nil,
		bg = T.clear,
		tooltip = if not multiple then (first.error or first.manual) else nil,
		on_click = if multiple then ui.toggle(M.expanded) else nil,
		ui.show(function()
			return not M.expanded:get()
		end, marks(list)),
		kit.text.text {
			M.title(),
			literal = true,
			size = "sm",
			weight = "medium",
			line = false,
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
		},
		glyph,
		act,
		multiple and ui.row {
			w = 24,
			h = 24,
			shrink = 0,
			items = "center",
			justify = "center",
			rotate = if M.expanded:peek() then 0 else 180,
			on_mount = if opening
				then function(el: Element)
					anime.animate(el, { rotate = { 180, 0 }, duration = kit.motion.d(240), ease = kit.motion.EASE })
				end
				else nil,
			kit.icon { name = "alt-arrow-down", size = 14, color = T.secondary },
		} or nil,
	}
end

local function row(s: Status, i: number, devices: number): Node
	local failed = s.phase == "failed"
	local said = if connected() then M.detail(s) else "Disconnected · reconnect to update"
	return ui.row {
		id = `update_row_{s.harness}`,
		relative = true,
		w_full = true,
		h = ROW,
		shrink = 0,
		px = "$zeron.space.12",
		gap = "$zeron.space.10",
		items = "center",
		tooltip = `{name(s)} · {s.device}\n{s.error or s.manual or said}`,
		i > 1 and ui.div {
			absolute = true,
			top = 0,
			left = 42,
			right = 12,
			h = 1,
			bg = T.hairline,
		} or nil,
		mark(s, 20),
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.1",
			kit.text.text { name(s), size = "sm", weight = "medium", line = false, truncate = true },
			devices > 1 and kit.text.text {
				s.device,
				size = "xs",
				color = T.tertiary,
				line = false,
				truncate = true,
			} or nil,
			kit.text.text {
				said,
				id = `update_detail_{s.harness}`,
				literal = true,
				size = "xs",
				color = if failed then T.danger else T.tertiary,
				line = false,
				truncate = true,
			},
		},
		s.phase == "updated" and kit.icon { name = "check", size = 14, color = T.success } or nil,
		button(s, "update_row_action"),
	}
end

local function list(statuses: { Status }, opening: boolean): Node
	local devices: { string } = {}
	for _, s in statuses do
		if not table.find(devices, s.device) then
			table.insert(devices, s.device)
		end
	end
	local rows: { Node } = {}
	for i, s in statuses do
		table.insert(rows, row(s, i, #devices))
	end
	return ui.column {
		id = "update_list",
		w_full = true,
		border_sides = { 1, 0, 0, 0 },
		border_color = T.hairline,
		bg = T.ink1,
		-- Its rows show once the surface has made room.
		on_mount = if opening
			then function(el: Element)
				anime.animate(el, {
					opacity = { 0, 1 },
					y = { 3, 0 },
					duration = kit.motion.d(kit.motion.FAST),
					delay = kit.motion.d(100),
				})
			end
			else nil,
		ui.scroll {
			w_full = true,
			max_h = ROW * 3.5,
			fade = { 32, 32 },
			fade_overflow = true,
			ui.column { w_full = true, rows },
		},
	}
end

-- The island on Home, over the canvas's foot. Built again as its rows
-- change; its box glides from the last one's (`layout_id`), its bottom
-- edge still.
local was_open = false
function M.island(): Node
	return ui.presence(function(): string?
		local statuses = M.visible()
		if #statuses == 0 then
			return nil
		end
		-- One update never opens.
		local parts: { string } = { tostring(M.expanded:get() and #statuses > 1), tostring(connected()) }
		for _, s in statuses do
			table.insert(parts, `{s.harness}:{s.phase}`)
		end
		return table.concat(parts, ",")
	end, function(): Node
		local statuses = M.visible()
		local open = M.expanded:peek() and #statuses > 1
		local opening = open and not was_open
		was_open = open
		return ui.row {
			absolute = true,
			left = 0,
			right = 0,
			bottom = 24,
			justify = "center",
			ui.column {
				id = "update_card",
				ref = card_ref,
				layout_id = "update_card",
				layout = "size",
				layout_clip = true,
				w = if open then LIST_W else nil,
				rounded = if open then "$zeron.radius.16" else T.radius_full,
				overflow = "hidden",
				border = 1,
				border_color = T.border,
				bg = T.frost,
				backdrop_blur = T.frost_blur,
				color = T.text,
				summary(statuses, opening),
				open and list(statuses, opening) or nil,
			},
		}
	end, { absolute = true, left = 0, right = 0, bottom = 0, top = 0, pointer_events = "none" })
end

return M
