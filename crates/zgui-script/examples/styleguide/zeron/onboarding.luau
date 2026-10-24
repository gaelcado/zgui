-- Onboarding, as Zeron's gates (shell.rs render_gate_card, render_org_gate,
-- the no-projects canvas): over the window's background and a 44-point
-- grid fading toward its edges, a card at a time, each entering over
-- 500 ms. "Log in to Zeron" (a 360 card: the logo, 18 semibold, the 13
-- line under it and a full-width Log in in the text colour); "Create your
-- workspace" (400: a name and Create, the workspaces you belong to, "Use a
-- different account"); then "Add a project to get started" on the canvas.
-- Each step waits on what it asks; nothing runs while it rests.
local T = require("../theme")
local kit = require("@kit")

local M = {}

export type Step = "" | "signin" | "signing" | "workspace" | "project"

-- The step shown; "" once done.
M.step = ui.state("onboarding_step", "" :: Step)
local workspace = ui.state("onboarding_workspace", "")
local creating = ui.state("onboarding_creating", false)

-- From the start, as after signing out.
function M.start()
	workspace:set("")
	creating:set(false)
	M.step:set("signin")
end

-- The background over the grid's ends, fading out (gradients take
-- colours: the theme's, read as it is).
local function fade(angle: number): () -> Gradient
	return function(): Gradient
		local bg = tostring(ui.theme.get("background") or "#000000")
		return { angle = angle, stops = { { 0, bg }, { 1, `alpha({bg}, 0)` } } }
	end
end

local STEP = 44
local SPAN = 2640
local function grid(): Node
	local lines: { Node } = {}
	for i = 1, SPAN // STEP - 1 do
		table.insert(lines, ui.div { absolute = true, left = i * STEP, top = 0, bottom = 0, w = 1, bg = T.ink1 })
	end
	for i = 1, (SPAN * 3 // 4) // STEP - 1 do
		table.insert(lines, ui.div { absolute = true, top = i * STEP, left = 0, right = 0, h = 1, bg = T.ink1 })
	end
	return ui.div {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		overflow = "hidden",
		pointer_events = "none",
		lines,
		-- The grid fades into the background toward the window's edges.
		ui.div {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			h = 120,
			gradient = fade(180),
		},
		ui.div {
			absolute = true,
			left = 0,
			right = 0,
			bottom = 0,
			h = 120,
			gradient = fade(0),
		},
	}
end

-- The solid button: 36 high, radius 6, the text colour, 14 medium.
local function solid(id: string, label: Text, on_click: Handler, w_full: boolean?): Node
	return ui.button {
		id = id,
		w_full = w_full,
		h = 36,
		px = "$zeron.space.16",
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.6",
		bg = T.text,
		hover = { opacity = 0.9 },
		focus = { border = 0 },
		cursor = "pointer",
		shrink = 0,
		on_click = on_click,
		kit.text.text { label, size = "lg", weight = "medium", color = T.bg, line = false },
	}
end

local function card(id: string, w: number, ...: Node): Node
	return ui.column {
		id = id,
		w = w,
		px = "$zeron.space.32",
		py = "$zeron.space.40",
		rounded = T.radius_card,
		border = 1,
		border_color = T.border,
		bg = T.card,
		shadow = T.shadow_lg,
		items = "center",
		on_mount = function(el: Element)
			anime.animate(
				el,
				{ opacity = { 0, 1 }, y = { 6, 0 }, duration = kit.motion.d(500), ease = kit.motion.EASE }
			)
		end,
		{ ... },
	}
end

local function sign_in(): Node
	return card(
		"onboarding_signin",
		360,
		kit.icon { name = "zeron-logo", size = 36, color = T.text },
		kit.text.text { "Log in to Zeron", size = "xl", weight = "semibold", mt = "$zeron.space.24", line = false },
		kit.text.text {
			"This opens your browser to finish logging in — you'll come right back.",
			size = "md",
			color = T.secondary,
			align = "center",
			wrap = true,
			mt = "$zeron.space.6",
			mb = "$zeron.space.24",
		},
		solid("onboarding_login", function()
			return if M.step:get() == "signing" then "Waiting for the browser…" else "Log in"
		end, function()
			if M.step:peek() ~= "signin" then
				return
			end
			M.step:set("signing")
			-- The browser hands the sign-in back.
			ui.after(1200, function()
				if M.step:peek() == "signing" then
					M.step:set("workspace")
				end
			end)
		end, true)
	)
end

local MEMBERSHIPS = { "Zeron", "Grid" }
local function create_workspace(): Node
	local function create()
		if workspace:peek() == "" or creating:peek() then
			return
		end
		creating:set(true)
		ui.after(600, function()
			creating:set(false)
			M.step:set("project")
		end)
	end
	local rows: { Node } = {}
	for i, name in MEMBERSHIPS do
		table.insert(
			rows,
			ui.button {
				id = `onboarding_member_{i}`,
				variants = kit.recipes.wash { hover = "ink2" },
				w_full = true,
				h = 36,
				px = "$zeron.space.12",
				gap = "$zeron.space.10",
				items = "center",
				rounded = "$zeron.radius.8",
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					M.step:set("project")
				end,
				ui.row {
					w = 20,
					h = 20,
					rounded = "$zeron.radius.5",
					bg = T.ink3,
					items = "center",
					justify = "center",
					kit.text.text { string.sub(name, 1, 1), size = "xs", weight = "medium", line = false },
				},
				kit.text.text { name, size = "md", grow = 1, line = false },
				kit.icon { name = "arrow-right", size = 14, color = T.tertiary },
			}
		)
	end
	return card(
		"onboarding_workspace",
		400,
		kit.icon { name = "zeron-logo", size = 28, color = T.text },
		kit.text.text { "Create your workspace", size = "xl", weight = "semibold", mt = "$zeron.space.20", line = false },
		kit.text.text {
			"Zeron is organized around workspaces — create one for yourself or your team.",
			size = "md",
			color = T.secondary,
			align = "center",
			wrap = true,
			mt = "$zeron.space.6",
			mb = "$zeron.space.24",
		},
		ui.row {
			w_full = true,
			gap = "$zeron.space.8",
			ui.input {
				id = "onboarding_workspace_name",
				value = workspace,
				label = "Workspace name",
				placeholder = "Workspace name",
				placeholder_color = T.tertiary,
				grow = 1,
				min_w = 0,
				h = 36,
				px = "$zeron.space.12",
				rounded = "$zeron.radius.8",
				border = 1,
				border_color = T.border,
				bg = T.bg,
				font = T.sans,
				text_size = "$font.size.md",
				color = T.text,
				on_key = function(e: KeyEvent): boolean
					if e.key == "Enter" then
						create()
						return true
					end
					return false
				end,
			},
			ui.column {
				opacity = function()
					return if creating:get() or workspace:get() == "" then 0.5 else 1
				end,
				solid("onboarding_create", function()
					return if creating:get() then "Creating…" else "Create"
				end, create),
			},
		},
		kit.text.text {
			"Or continue in a workspace you belong to",
			size = "xs",
			color = T.tertiary,
			mt = "$zeron.space.24",
			mb = "$zeron.space.8",
			line = false,
		},
		ui.column { w_full = true, gap = "$zeron.space.2", rows },
		ui.button {
			id = "onboarding_other_account",
			variants = kit.recipes.text_button,
			mt = "$zeron.space.24",
			on_click = function()
				M.step:set("signin")
			end,
			kit.text.text { "Use a different account", size = "sm", color = "inherit", line = false },
		}
	)
end

local function add_project(): Node
	return ui.column {
		id = "onboarding_project",
		items = "center",
		on_mount = function(el: Element)
			anime.animate(el, { opacity = { 0, 1 }, duration = kit.motion.d(500), ease = kit.motion.EASE })
		end,
		kit.icon { name = "zeron-logo", size = 48, color = T.ink3 },
		kit.text.text {
			"Add a project to get started",
			size = "xl",
			weight = "medium",
			mt = "$zeron.space.24",
			line = false,
		},
		kit.text.text {
			"A project is a folder on one of your devices.",
			size = "md",
			color = T.tertiary,
			mt = "$zeron.space.6",
			line = false,
		},
		ui.column {
			mt = "$zeron.space.20",
			solid("onboarding_add_project", "Add a project", function()
				M.step:set("")
			end),
		},
	}
end

-- Over the window while a step shows.
function M.view(): Node
	return ui.presence(function()
		-- Waiting on the browser is still the sign-in card.
		-- Nothing over the window once done (nor in the pointer's way).
		local step = M.step:get()
		if step == "" then
			return nil
		end
		return if step == "signing" then "signin" else step
	end, function(step: string): Node
		return ui.column {
			id = "onboarding",
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			bottom = 0,
			bg = T.bg,
			items = "center",
			justify = "center",
			grid(),
			if step == "signin" then sign_in() elseif step == "workspace" then create_workspace() else add_project(),
		}
	end, {
		absolute = true,
		left = 0,
		right = 0,
		top = 0,
		bottom = 0,
		exit = { opacity = 0, duration = kit.motion.d(kit.motion.SLOW) },
	})
end

return M
