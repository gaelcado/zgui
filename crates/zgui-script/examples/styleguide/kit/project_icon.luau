-- A project's icon, as Zeron draws it until the repository's own artwork
-- loads (shell/project_icon.rs): its initial in mono 9 medium on a 3-radius
-- tile, in one of eight tones the name picks and keeps. In a row it lights
-- as the pointer comes over the row (`group_hover`, the engine's: no
-- script), and stays lit on the chosen row (`lit`).
local T = require("../theme")
local recipes = require("./recipes")

export type Props = {
	name: string,
	size: number?,
	id: string?,
	-- Lit whatever the pointer does (the chosen row's).
	lit: (State<boolean> | (() -> boolean))?,
}

local M = {}

M.TONES = 8

-- The name's tone, from 1: the same name always gets the same one.
function M.tone(name: string): number
	local h = 5381
	for i = 1, #name do
		h = (h * 33 + string.byte(name, i)) % 4294967296
	end
	return h % M.TONES + 1
end

function M.initial(name: string): string
	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	local first = string.match(trimmed, "^[%z\1-\127\194-\244][\128-\191]*") or "?"
	return string.upper(first)
end

M.icon = ui.component(function(props: Props): Node
	local size = props.size or 13
	return ui.row {
		id = props.id,
		w = size,
		h = size,
		shrink = 0,
		items = "center",
		justify = "center",
		rounded = "$zeron.radius.3",
		variants = recipes.project_tile { tone = tostring(M.tone(props.name)) :: any, lit = props.lit or false },
		ui.text {
			M.initial(props.name),
			literal = true,
			text_size = "$zeron.font.size.tile",
			line_height = size,
			weight = "$font.weight.medium",
			font = T.mono,
		},
	}
end)

return M
