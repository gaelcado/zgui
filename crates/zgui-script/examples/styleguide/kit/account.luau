-- The account's footer pieces: the usage meter line (settings/accounts.rs),
-- the update strip above the user menu (shell.rs render_update_strip), the
-- connection pill over it (render_connection_pill), and what the footer
-- says of the account as the workspace syncs (sidebar_account_identity,
-- account_menu_action).
local T = require("../theme")
local txt = require("./text")
local icon = require("./icon")
local wash = require("./wash")
local icon_button = require("./icon_button")
local recipes = require("./recipes")
local motion = require("./motion")
local loaders = require("./loaders")

export type RowProps = {
	-- The glide list it sits in.
	group: string,
	email: string,
	-- Its initial, on the avatar.
	initial: string,
	active: boolean?,
	session: number?,
	weekly: number?,
}
export type MeterProps = { id: string?, label: string, level: number, w: Length? }
export type UpdateState = "available" | "downloading" | "ready" | "failed" | "restarting"
-- Where the workspace lives: on this device, synced to an account, or a
-- development build without authentication.
export type Scope = "local" | "synced" | "development"
-- Where enabling sync (or signing out) stands (shell.rs SyncFlow).
export type SyncFlow =
	"idle"
	| "enabling"
	| "canceling"
	| "switch_offer"
	| "restart_pending"
	| "import_failed"
	| "switching"
	| "importing"
	| "import_done"
	| "sign_out_confirm"
	| "signing_out"
	| "signed_out_restart"
export type Account = {
	scope: Scope?,
	flow: SyncFlow?,
	-- The signed-in user's.
	name: string?,
	email: string?,
}
-- What the account menu offers under its identity line.
export type MenuAction = "enable_sync" | "sync_in_progress" | "restart_pending" | "sign_out"
-- The edge's posture: healthy shows nothing.
export type Connection = "connected" | "offline" | "reconnecting" | "storage_error" | "syncing"
-- An update the app found, where its flow stands.
export type Update = { state: UpdateState, version: string?, detail: string? }
export type UpdateProps = {
	id: string?,
	state: UpdateState,
	version: string?,
	detail: string?,
	on_click: (Handler | Action)?,
	w: Length?,
}

local M = {}

-- 16 high: label 52 muted, a 88×4 bar on wash 8%, the percent 34 wide.
M.meter = ui.component(function(props: MeterProps): Node
	local level = math.clamp(props.level, 0, 1)
	local color = if level >= 0.95 then T.danger elseif level >= 0.8 then T.warning else T.accent
	return ui.row {
		id = props.id,
		w = props.w,
		h = 16,
		gap = "$zeron.space.8",
		items = "center",
		txt.text { props.label, size = "xs", color = T.secondary, line = false, w = 52, truncate = true },
		ui.row {
			w = 88,
			h = 4,
			rounded = "$zeron.radius.2",
			bg = T.ink3,
			overflow = "hidden",
			ui.div {
				w = `{math.max(1.5, level * 100)}%`,
				h_full = true,
				rounded = "$zeron.radius.2",
				bg = color,
				opacity = if level >= 0.8 then 0.9 else 0.8,
			},
		},
		txt.text {
			`{math.floor(level * 100 + 0.5)}%`,
			size = "xs",
			color = T.secondary,
			tabular = true,
			line = false,
			w = 34,
			align = "end",
		},
	}
end)

local LABEL: { [UpdateState]: (string?, string?) -> string } = {
	available = function(v)
		return `Update available — {v or "?"}`
	end,
	downloading = function(v)
		return `Downloading {v or "?"}…`
	end,
	ready = function()
		return "Update ready — restart to apply"
	end,
	failed = function(_, d)
		return `Update failed: {d or "unknown"}`
	end,
	restarting = function()
		return "Restarting…"
	end,
}

-- Padding 8×6, radius 6, text 11 medium on gpui's 1.618 line (wrapping
-- when it must), the sidebar's inset in from its edges; the accent wash,
-- the accent at 16% under the pointer (danger at 14% and 22% when it
-- failed); clickable only when there is something to do (not while it
-- downloads or restarts).
M.update_strip = ui.component(function(props: UpdateProps): Node
	local failed = props.state == "failed"
	local actionable = props.state == "available" or props.state == "ready" or failed
	local text = LABEL[props.state](props.version, props.detail)
	return ui.button {
		id = props.id,
		variants = recipes.update_strip { failed = failed, actionable = actionable },
		w = props.w,
		w_full = props.w == nil,
		px = "$zeron.space.8",
		py = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		focus = { border = 0 },
		disabled = not actionable,
		on_click = props.on_click,
		txt.text {
			text,
			literal = true,
			size = "xs",
			weight = "medium",
			color = if failed then T.danger else T.accent,
			line_height = ui.raw(18, "gpui's default line, 1.618 at 11"),
			wrap = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
		},
	}
end)

-- "Star on GitHub" (render_github_star_banner), cut as the update strip:
-- 8 in and 4 at its end, 4 high, radius 6, the star 12 (half a point
-- low, on the cap height) 6 from the label at 11 medium in the accent, on
-- the accent wash, lit under the pointer; its ✕ 18 square at radius 4,
-- the accent at 22% (its wash) under the pointer. A click on it opens the repository;
-- either dismisses it for good.
M.star_banner = ui.component(function(props: { id: string?, on_open: (() -> ())?, on_dismiss: () -> () }): Node
	local id = props.id or "star_banner"
	return ui.button {
		id = id,
		variants = recipes.update_strip { actionable = true },
		w_full = true,
		pl = "$zeron.space.8",
		pr = "$zeron.space.4",
		py = "$zeron.space.4",
		gap = "$zeron.space.6",
		items = "center",
		rounded = T.radius_md,
		focus = { border = 0 },
		on_click = function()
			if props.on_open then
				props.on_open()
			end
			props.on_dismiss()
		end,
		ui.div { shrink = 0, y = 0.5, icon { name = "star-bold", size = 12, color = T.accent } },
		txt.text {
			"Star on GitHub",
			size = "xs",
			weight = "medium",
			color = T.accent,
			line_height = ui.raw(18, "gpui's default line, 1.618 at 11"),
			truncate = true,
			grow = 1,
			shrink = 1,
			min_w = 0,
		},
		ui.button {
			id = `{id}_dismiss`,
			w = 18,
			h = 18,
			p = 0,
			shrink = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.4",
			bg = T.clear,
			hover = { bg = T.accent_wash },
			focus = { border = 0 },
			cursor = "pointer",
			tooltip = "Dismiss",
			on_click = props.on_dismiss,
			icon { name = "close", size = 10, color = T.accent },
		},
	}
end)

-- The footer's label and the account menu's identity line
-- (sidebar_account_identity): a local workspace reads "Local" and says
-- where it is stored; a signed-in one its name (or address) over its
-- address; anything else "Local", not signed in.
function M.identity(a: Account): (string, string)
	if a.scope == "local" then
		return "Local", if a.flow == "restart_pending" then "Sync ready after restart" else "Stored on this device"
	elseif a.scope == "development" then
		return "Development", "Authentication disabled"
	end
	if a.email then
		local name = a.name and string.match(a.name, "^%s*(.-)%s*$")
		return if name and name ~= "" then name else a.email, a.email
	end
	return "Local", "Not signed in"
end

local SWITCHING: { [string]: boolean } = { switching = true, importing = true, import_done = true }

-- What the account menu offers (account_menu_action): a local workspace
-- enables sync, follows its setup, or finishes it after a restart; a
-- synced one signs out (or follows a switch under way); none while
-- signing out, or in a development build.
function M.menu_action(a: Account): MenuAction?
	local flow: string = a.flow or "idle"
	if a.scope == "local" then
		if flow == "idle" then
			return "enable_sync"
		elseif flow == "enabling" or flow == "canceling" or SWITCHING[flow] then
			return "sync_in_progress"
		elseif flow == "switch_offer" or flow == "restart_pending" or flow == "import_failed" then
			return "restart_pending"
		end
		return nil
	elseif a.scope == "synced" then
		if flow == "signed_out_restart" then
			return nil
		elseif flow == "import_failed" then
			return "restart_pending"
		elseif SWITCHING[flow] then
			return "sync_in_progress"
		end
		return "sign_out"
	end
	return nil
end

local CONNECTION: { [Connection]: string } = {
	storage_error = "Changes could not be saved",
	offline = "Offline — sends are saved",
	reconnecting = "Reconnecting…",
	syncing = "Syncing…",
}

-- The connection pill (render_connection_pill): over the update strip
-- while the edge is not healthy, appearing being the signal. A 5 dot in
-- the warning colour (offline, a failed save) or the mono spinner
-- (reconnecting, syncing), 6 from the label at 11 in the faint colour;
-- 12 in from the sidebar's edges, 8 above what follows. It fades in.
M.connection_pill = ui.component(function(props: { id: string?, state: Connection, label: string? }): Node
	local spinning = props.state == "reconnecting" or props.state == "syncing"
	return ui.row {
		id = props.id,
		w_full = true,
		px = "$zeron.space.4",
		pb = "$zeron.space.8",
		gap = "$zeron.space.6",
		items = "center",
		on_mount = function(el: Element)
			anime.animate(el, { opacity = { 0, 1 }, duration = motion.d(motion.MENU_IN), ease = motion.EASE })
		end,
		if spinning
			then loaders.mini_spinner { color = T.secondary }
			else ui.div { w = 5, h = 5, shrink = 0, rounded = T.radius_full, bg = T.warning },
		txt.text {
			props.label or CONNECTION[props.state] or "",
			literal = true,
			size = "xs",
			color = T.tertiary,
			line = false,
			truncate = true,
			shrink = 1,
			min_w = 0,
		},
	}
end)

-- An account (settings/accounts.rs): the avatar at 32, ringed 1.5 in the
-- accent while in use; the address with "In use", the session and weekly
-- meters under it; its menu at the end. In a glide list.
M.row = ui.component(function(props: RowProps): Node
	local active = props.active == true
	return ui.row(wash.item(props.group, {
		w_full = true,
		min_h = 56,
		p = "$zeron.space.10",
		gap = "$zeron.space.14",
		items = "center",
		rounded = T.radius_lg,
		ui.row {
			w = 32,
			h = 32,
			border = 1.5,
			variants = recipes.account_ring { active = active },
			ui.row {
				w = 25,
				h = 25,
				rounded = T.radius_full,
				bg = T.ink3,
				items = "center",
				justify = "center",
				txt.text { props.initial, size = "xs", weight = "medium", color = "inherit", line = false },
			},
		},
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.6",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				txt.text { props.email, size = "sm", weight = "medium", truncate = true, line = false },
				active and txt.text { "In use", size = "xs", color = T.accent, line = false } or nil,
			},
			ui.column {
				gap = "$zeron.space.4",
				M.meter { label = "Session", level = props.session or 0 },
				M.meter { label = "Weekly", level = props.weekly or 0 },
			},
		},
		icon_button { icon = "more-horizontal", size = 28, icon_size = 14, label = "More", no_ring = true },
	}))
end)

return M
