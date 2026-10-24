-- Attachments (composer.rs, composer/chip.rs, transcript.rs): the
-- composer's 56 tiles with an 18 remove button at their corner, the
-- inline chip on ink 9% with its icon well, and the transcript's 112×80
-- thumbnails in their loaded, loading and failed states.
local T = require("../theme")
local recipes = require("./recipes")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")

export type TileProps = {
	id: string?,
	-- An image tile (the tint stands in for the picture) or a file tile.
	name: string,
	image: Color?,
	icon: icon_mod.Name?,
	on_remove: Handler?,
}
export type ChipProps = { id: string?, label: string, icon: icon_mod.Name?, h: number? }
export type ThumbProps = { id: string?, state: ("loaded" | "loading" | "error")?, image: Color? }

local M = {}

M.TILE = 56
M.THUMB_W = 112
M.THUMB_H = 80

M.tile = ui.component(function(props: TileProps): Node
	return ui.column {
		id = props.id,
		relative = true,
		hover_group = true,
		w = M.TILE,
		h = M.TILE,
		variants = recipes.attachment,
		overflow = "visible",
		if props.image
			then ui.div { w_full = true, h_full = true, variants = recipes.attachment_fill, bg = props.image }
			else ui.column {
				w_full = true,
				h_full = true,
				variants = recipes.attachment_fill,
				items = "center",
				justify = "center",
				gap = "$zeron.space.3",
				px = "$zeron.space.4",
				icon { name = props.icon or "document", size = 24, color = T.secondary },
				txt.text { props.name, size = "micro", color = T.secondary, truncate = true, line = false },
			},
		-- The remove button shows while the pointer is over the tile.
		ui.button {
			absolute = true,
			top = -6,
			right = -6,
			w = 18,
			h = 18,
			variants = recipes.attachment_remove,
			invisible = true,
			group_hover = { invisible = false },
			on_click = props.on_remove,
			icon { name = "close-circle", size = 14, color = T.secondary },
		},
	}
end)

-- The inline chip: radius 5 on ink 9%, an icon well inset 1 at radius 4.
M.chip = ui.component(function(props: ChipProps): Node
	local h = props.h or 20
	return ui.row {
		id = props.id,
		h = h,
		pl = "$zeron.space.1",
		pr = "$zeron.space.6",
		gap = "$zeron.space.4",
		variants = recipes.attachment_chip,
		ui.row {
			w = h - 2,
			h = h - 2,
			variants = recipes.attachment_well,
			icon { name = props.icon or "document", size = math.min(14, h - 6), color = T.secondary },
		},
		txt.text { props.label, size = "sm", line = false, truncate = true },
	}
end)

M.thumb = ui.component(function(props: ThumbProps): Node
	local s = props.state or "loaded"
	local id = props.id or `thumb{math.random(1, 1e9)}`
	return ui.column {
		id = props.id,
		w = M.THUMB_W,
		h = M.THUMB_H,
		variants = recipes.attachment_thumb { state = s },
		if s == "loaded"
			then ui.div { w_full = true, h_full = true, variants = recipes.attachment_fill, bg = props.image or T.ink4 }
			elseif s == "loading" then ui.div {
				w_full = true,
				h_full = true,
				bg = T.ink3,
				class = `{id}_pulse`,
				on_mount = function(el: Element)
					if not motion.loops() then
						return
					end
					anime.animate(el, {
						opacity = { 0.3, 0.7, 0.3 },
						duration = 2400,
						ease = motion.EASE,
						loop = true,
						frameRate = 30,
					})
				end,
			}
			else icon { name = "gallery", size = 16, color = T.tertiary },
	}
end)

return M
