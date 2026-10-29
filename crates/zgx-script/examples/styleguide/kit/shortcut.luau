-- Keyboard shortcuts (settings/shortcuts): a card row with the action's
-- name, a "Reset" link when customised, and the key chip: at least 96
-- wide, 32 high, radius 8, mono 12, wash 6% (10% hovered); recording
-- shows "Press keys…" on the accent at 16% with a 55% accent border.
local types = require("./types")
local txt = require("./text")
local recipes = require("./recipes")
local settings = require("./settings")
local keymap = require("./keymap")

export type ChipProps = {
	id: string?,
	keys: Text,
	recording: types.Cond?,
	on_click: (Handler | Action)?,
	label: string?,
	-- While it records: the keys it is given, and its focus leaving.
	on_key: ((e: KeyEvent) -> boolean)?,
	on_blur: Handler?,
}
export type RowProps = {
	id: string?,
	title: string,
	meta: { Text }?,
	keys: Text,
	customised: types.Cond?,
	recording: types.Cond?,
	on_click: (Handler | Action)?,
	on_reset: Handler?,
	on_key: ((e: KeyEvent) -> boolean)?,
	on_blur: Handler?,
	-- Its name for settings search.
	anchor: string?,
}

local M = {}

M.chip = ui.component(function(props: ChipProps): Node
	local function rec(): boolean
		return types.on(props.recording)
	end
	return ui.button {
		id = props.id,
		label = props.label,
		variants = recipes.shortcut { recording = rec },
		on_click = props.on_click,
		on_key = props.on_key,
		on_blur = props.on_blur,
		txt.text {
			function()
				if rec() then
					return "Press keys…"
				end
				local k = props.keys
				return if type(k) == "function" then (k :: any)() else k :: any
			end,
			size = "sm",
			mono = true,
			line = false,
			color = "inherit",
		},
	}
end)

-- Reset (while customised and not recording) and the chip.
local function control(props: RowProps): Node
	return ui.row {
		gap = "$zeron.space.20",
		items = "center",
		props.customised and ui.show(
			function()
				return types.on(props.customised) and not types.on(props.recording)
			end,
			ui.button {
				id = props.id and `{props.id}_reset`,
				label = `Reset {props.title} shortcut`,
				variants = recipes.text_button,
				on_click = props.on_reset,
				txt.text { "Reset", size = "xs", color = "inherit", line = false },
			}
		),
		M.chip {
			id = props.id and `{props.id}_chip`,
			label = `Change {props.title} shortcut`,
			keys = props.keys,
			recording = props.recording,
			on_click = props.on_click,
			on_key = props.on_key,
			on_blur = props.on_blur,
		},
	}
end

M.row = ui.component(function(props: RowProps): Node
	return settings.row {
		id = props.id,
		anchor = props.anchor,
		title = props.title,
		meta = props.meta,
		control = control(props),
	}
end)

-- Binding `binding`'s Reset and chip, recording into `km` (a feature
-- page's shortcut, ShortcutField; the Shortcuts page's rows).
function M.binding_props(km: keymap.Keymap, binding: keymap.Binding, id: string): RowProps
	return {
		id = id,
		title = binding.label,
		meta = if binding.meta then { binding.meta } else nil,
		keys = function()
			return keymap.display(keymap.combo(km, binding.id))
		end,
		customised = function()
			return km.custom:get()[binding.id] ~= nil
		end,
		recording = function()
			return km.recording:get() == binding.id
		end,
		on_click = function()
			keymap.start(km, binding.id)
		end,
		on_reset = function()
			keymap.reset(km, binding.id)
		end,
		on_key = function(e: KeyEvent): boolean
			return keymap.record(km, binding.id, e)
		end,
		on_blur = function()
			keymap.stop(km, binding.id)
		end,
	}
end
function M.binding(km: keymap.Keymap, binding_id: string, id: string): Node
	return control(M.binding_props(km, km.by_id[binding_id], id))
end

return M
