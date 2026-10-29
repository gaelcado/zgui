-- Message badges (badges.rs): a 24-high pill on ink 6% naming what a
-- message carries (a selection, a comment, a file), and the frosted card
-- that opens under it after 280 ms with each item's location and text.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local frost = require("./frost")
local motion = require("./motion")

export type Item = { where: string, tag: string?, body: string }
export type Props = {
	id: string?,
	label: string,
	icon: icon_mod.Name?,
	items: { Item }?,
	-- Shown at rest, for specimens.
	preview: boolean?,
}

local M = {}

M.DELAY = 280

function M.card(items: { Item }, id: string?): Node
	local rows: { Node } = {}
	for _, it in items do
		table.insert(
			rows,
			ui.row {
				w_full = true,
				variants = recipes.quote,
				ui.div { variants = recipes.quote_rail },
				ui.column {
					grow = 1,
					shrink = 1,
					min_w = 0,
					gap = "$zeron.space.4",
					ui.row {
						gap = "$zeron.space.6",
						items = "center",
						txt.text {
							it.where,
							size = "micro",
							mono = true,
							color = T.tertiary,
							truncate = true,
							shrink = 1,
							min_w = 0,
						},
						it.tag and ui.row {
							variants = recipes.tag,
							txt.text { it.tag, size = "micro", mono = true, color = T.tertiary, line = false },
						},
					},
					txt.text { it.body, size = "sm", wrap = true, lines = 3 },
				},
			}
		)
	end
	return frost.card { id = id, w = 320, p = "$zeron.space.6", gap = "$zeron.space.4", rows }
end

return ui.component(function(props: Props): Node
	local open = ui.use_state(props.preview == true)
	local pending: (() -> ())? = nil
	return ui.column {
		id = props.id,
		relative = true,
		self = "start",
		on_hover = function(inside: boolean)
			if pending then
				pending()
				pending = nil
			end
			if props.preview then
				return
			end
			if inside then
				pending = ui.after(M.DELAY, function()
					pending = nil
					open:set(true)
				end)
			else
				open:set(false)
			end
		end,
		ui.row {
			variants = recipes.message_badge,
			props.icon and icon { name = props.icon, size = 12, color = T.secondary, opacity = 0.7 },
			txt.text { props.label, size = "sm", weight = "medium", color = T.secondary, line = false },
		},
		props.items and ui.presence(function()
			return if open:get() then "card" else nil
		end, function(): Node
			return M.card(props.items :: { Item }, props.id and `{props.id}_card`)
		end, {
			absolute = true,
			top = 28,
			left = 0,
			enter = { opacity = { 0, 1 }, y = { -2, 0 }, duration = motion.d(motion.MENU_IN), ease = motion.EASE },
			exit = { opacity = 0, duration = motion.d(motion.MENU_OUT) },
		}),
	}
end)
