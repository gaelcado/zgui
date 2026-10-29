-- Settings → Shortcuts (settings/shortcuts.rs): a card of rebindable
-- bindings per section, under the title and Restore defaults; a click on
-- a combo records the next one (Escape cancels), refused while another
-- binding has it, the line under the cards saying why.
local T = require("../theme")
local txt = require("./text")
local button = require("./button")
local settings = require("./settings")
local shortcut = require("./shortcut")
local keymap = require("./keymap")

local M = {}

export type Props = {
	keymap: keymap.Keymap,
	-- Other preferences Restore defaults also resets (the send key, Escape),
	-- and whether they differ from their defaults.
	customised: (() -> boolean)?,
	on_restore: (() -> ())?,
}

function M.view(props: Props): Node
	local km = props.keymap
	local groups: { Node } = {}
	for _, name in keymap.GROUPS do
		local rows: { Node } = {}
		for _, b in km.bindings do
			if b.group == name then
				local row = shortcut.binding_props(km, b, `settings_shortcut_{b.id}`)
				row.anchor = `shortcut:{b.id}`
				table.insert(rows, shortcut.row(row))
			end
		end
		if #rows > 0 then
			table.insert(groups, settings.section { title = name, table.unpack(rows) })
		end
	end
	local function customised(): boolean
		return keymap.customised(km) or (props.customised ~= nil and props.customised())
	end
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.32",
		ui.row {
			w_full = true,
			items = "start",
			justify = "between",
			gap = "$zeron.space.24",
			ui.column {
				grow = 1,
				shrink = 1,
				min_w = 200,
				settings.header {
					title = "Keyboard shortcuts",
					description = "Click a binding, then press the new key combination.",
				},
			},
			button {
				id = "shortcuts_restore",
				label = "Restore defaults",
				icon = { name = "restart" },
				size = "sm",
				variant = "ghost",
				disabled = function()
					return not customised() or km.recording:get() ~= ""
				end,
				on_click = function()
					keymap.restore(km)
					if props.on_restore then
						props.on_restore()
					end
				end,
			},
		},
		ui.column {
			w_full = true,
			gap = "$zeron.space.12",
			ui.column { w_full = true, gap = "$zeron.space.32", groups },
			ui.row {
				w_full = true,
				min_h = 20,
				px = "$zeron.space.4",
				justify = "center",
				txt.text {
					function()
						if km.recording:get() ~= "" then
							return "Press Escape to cancel."
						end
						local notice = km.notice:get()
						return if notice ~= "" then notice else "Shortcuts must be unique."
					end,
					id = "shortcuts_helper",
					size = "sm",
					color = T.secondary,
					wrap = true,
				},
			},
		},
	}
end

return M
