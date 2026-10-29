-- A project's actions (project_actions.rs, shell/actions_ui.rs): the
-- commands the session card lists under Actions. A row runs its action in
-- a terminal tab named for it (the last run kept per project); the gear
-- edits it; zeron.json's own are imported through the editor. The editor
-- (440 wide): its name, its command in mono, one of six icons, whether it
-- runs as a worktree is made; Escape or Cancel leaves it; deleting asks
-- first.
local T = require("../theme")
local kit = require("@kit")
local data = require("./data")
local state = require("./state")

local M = {}

type Action = data.Action
type Icon = data.ActionIcon

-- Each project's actions, those its zeron.json offers, the last run.
M.lists = ui.state("z_actions", data.ACTIONS)
M.imports = ui.state("z_action_imports", data.IMPORTS)
M.last = ui.state("z_action_last", {} :: { [string]: string })

-- The editor up: the project, the action edited (nil: a new one), and a
-- draft to start from (an import's).
export type Editing = { project: string, id: string?, from: Action? }
M.editing = ui.state("z_action_editing", nil :: Editing?)
M.open = ui.state("z_action_editor_open", false)
-- Deleting asks first, over the editor.
M.confirm = ui.state("z_action_confirm", false)

local ICONS: { { kind: Icon, label: string } } = {
	{ kind = "play", label = "Play" },
	{ kind = "test", label = "Test" },
	{ kind = "lint", label = "Lint" },
	{ kind = "configure", label = "Configure" },
	{ kind = "build", label = "Build" },
	{ kind = "debug", label = "Debug" },
}

function M.of(project: string): { Action }
	return M.lists:get()[project] or {}
end

-- Runs `action` of `project` in a terminal tab of its own.
function M.run(project: string, action: Action)
	M.last:set_key(project, action.id)
	state.open_terminal(action.name)
end

function M.edit(project: string, action: Action?, from: Action?)
	M.confirm:set(false)
	M.editing:set { project = project, id = action and action.id, from = action or from }
	M.open:set(true)
end

local function close()
	M.open:set(false)
	M.confirm:set(false)
end

-- What is wrong with a draft, as Zeron says it; nil when nothing is.
function M.problem(name: string, command: string): string?
	if name == "" then
		return "Action name is required"
	elseif utf8.len(name) and (utf8.len(name) :: number) > 80 then
		return "Action name must not exceed 80 characters"
	elseif command == "" then
		return "Action command is required"
	elseif #command > 16 * 1024 then
		return "Action command must not exceed 16384 bytes"
	end
	return nil
end

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") or ""
end

local function save(e: Editing, name: string, command: string, icon: Icon, setup: boolean)
	local all = table.clone(M.lists:peek())
	local list = table.clone(all[e.project] or {})
	local action: Action = { id = e.id or "", name = name, command = command, icon = icon, setup = setup or nil }
	local at = nil
	for i, a in list do
		if a.id == e.id then
			at = i
		end
	end
	if at then
		list[at] = action
	else
		-- A new one's id from its name, kept unique.
		local base = string.lower((string.gsub(name, "[^%w]+", "_")))
		local id, n = base, 1
		local function taken(candidate: string): boolean
			for _, a in list do
				if a.id == candidate then
					return true
				end
			end
			return false
		end
		while taken(id) do
			n += 1
			id = `{base}_{n}`
		end
		action.id = id
		table.insert(list, action)
	end
	all[e.project] = list
	M.lists:set(all)
	-- An import saved leaves zeron.json's offers.
	if e.from and e.id == nil then
		local offers = table.clone(M.imports:peek())
		local rest = {}
		for _, a in offers[e.project] or {} do
			if a.name ~= e.from.name then
				table.insert(rest, a)
			end
		end
		offers[e.project] = rest
		M.imports:set(offers)
	end
	close()
end

local function delete(e: Editing)
	local all = table.clone(M.lists:peek())
	local rest = {}
	for _, a in all[e.project] or {} do
		if a.id ~= e.id then
			table.insert(rest, a)
		end
	end
	all[e.project] = rest
	M.lists:set(all)
	if e.id and M.last:peek()[e.project] == e.id then
		M.last:set_key(e.project, nil)
	end
	close()
end

local function label(text: string): Node
	return kit.text.text {
		text,
		size = "sm",
		weight = "medium",
		color = T.secondary,
		mt = "$zeron.space.12",
		mb = "$zeron.space.5",
	}
end

local function button(id: string, text: string, variant: string, run: () -> ()): Node
	return kit.button { id = id, label = text, variant = variant :: any, size = "sm", on_click = run }
end

-- The editor's form, its fields starting from what it edits.
local function editor(e: Editing): Node
	local from = e.from
	local name = ui.use_state(if from then from.name else "")
	local command = ui.use_state(if from then from.command else "")
	local icon = ui.use_state((if from then from.icon else "play") :: Icon)
	local setup = ui.use_state(from ~= nil and from.setup == true)
	local error = ui.use_state(nil :: string?)
	local function submit()
		local n, c = trim(name:peek()), trim(command:peek())
		local wrong = M.problem(n, c)
		if wrong then
			error:set(wrong)
			return
		end
		save(e, n, c, icon:peek(), setup:peek())
	end
	local tiles: { Node } = {}
	for _, choice in ICONS do
		local kind = choice.kind
		table.insert(
			tiles,
			ui.button {
				id = `action_icon_{kind}`,
				label = choice.label,
				tooltip = choice.label,
				w = 34,
				h = 34,
				p = 0,
				items = "center",
				justify = "center",
				rounded = "$zeron.radius.7",
				border = 1,
				border_color = function()
					return if icon:get() == kind then T.secondary else T.border
				end,
				bg = function()
					return if icon:get() == kind then T.ink4 else T.ink1
				end,
				focus = { border = 0 },
				cursor = "pointer",
				on_click = function()
					icon:set(kind)
				end,
				kit.icon { name = kit.session_card.ACTION_ICON[kind], size = 16, color = T.secondary },
			}
		)
	end
	return ui.modal {
		id = "action_editor",
		open = M.open,
		label = if e.id then "Edit action" else "Add action",
		variants = kit.recipes.dialog,
		w = 440,
		enter = {
			opacity = { 0, 1 },
			y = { 6, 0 },
			scale = { 0.98, 1 },
			duration = kit.motion.d(kit.motion.DIALOG_IN),
			ease = kit.motion.EASE,
		},
		kit.text.text { if e.id then "Edit action" else "Add action", size = "xl", weight = "semibold" },
		label("Name"),
		kit.input { id = "action_name", value = name, placeholder = "Action name", w_full = true },
		label("Command"),
		kit.input {
			id = "action_command",
			value = command,
			placeholder = "Command",
			multiline = true,
			mono = true,
			h = 88,
			w_full = true,
		},
		label("Icon"),
		ui.row { gap = "$zeron.space.6", tiles },
		ui.row {
			mt = "$zeron.space.14",
			kit.checkbox {
				id = "action_setup",
				value = setup,
				label = "Run automatically on worktree creation",
			},
		},
		ui.show(
			function()
				return error:get() ~= nil
			end,
			kit.text.text {
				function()
					return error:get() or ""
				end,
				id = "action_error",
				size = "sm",
				color = T.danger,
				mt = "$zeron.space.10",
			}
		),
		ui.row {
			mt = "$zeron.space.18",
			w_full = true,
			items = "center",
			justify = "between",
			ui.row {
				e.id and kit.button {
					id = "action_delete",
					label = "Delete action",
					variant = "ghost_danger",
					size = "sm",
					on_click = function()
						M.confirm:set(true)
					end,
				} or nil,
			},
			ui.row {
				gap = "$zeron.space.8",
				button("action_cancel", "Cancel", "ghost", close),
				button("action_save", "Save action", "primary", submit),
			},
		},
	}
end

-- Mounted once in the app's root: the editor, or what deleting asks.
function M.dialogs(): Node
	return ui.presence(function(): string?
		local e = M.editing:get()
		if not M.open:get() or not e then
			return nil
		end
		return `{if M.confirm:get() then "delete" else "edit"}:{e.project}:{e.id or ""}`
	end, function(key: string): Node
		local e = M.editing:peek() :: Editing
		if string.sub(key, 1, 7) == "delete:" then
			local name = ""
			for _, a in M.lists:peek()[e.project] or {} do
				if a.id == e.id then
					name = a.name
				end
			end
			return kit.dialog {
				id = "action_delete_dialog",
				open = M.open,
				title = "Delete action?",
				description = `“{name}” will be permanently deleted.`,
				actions = {
					button("action_delete_cancel", "Cancel", "ghost", function()
						M.confirm:set(false)
					end),
					button("action_delete_confirm", "Delete", "danger", function()
						delete(e)
					end),
				},
			}
		end
		return editor(e)
	end)
end

return M
