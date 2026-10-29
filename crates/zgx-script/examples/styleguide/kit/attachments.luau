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
	-- The picture itself, over the tint; a click opens it (`on_open`).
	src: string?,
	icon: icon_mod.Name?,
	on_remove: Handler?,
	on_open: Handler?,
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
			then ui.button {
				id = props.id and `{props.id}_open`,
				label = props.name,
				w_full = true,
				h_full = true,
				p = 0,
				variants = recipes.attachment_fill,
				bg = props.image,
				overflow = "hidden",
				cursor = if props.on_open then "pointer" else nil,
				focus = { border = 0 },
				on_click = props.on_open,
				props.src and ui.image { src = props.src, label = "", w_full = true, h_full = true, fit = "cover" },
			}
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

-- What a sent message carried (transcript.rs render_user_attachments): an
-- image's picture (`src`, `w` by `h` pixels) while `loaded`, the skeleton
-- while `loading`, the missing thumb once `failed`; uploading, its picture
-- under a dark veil with the upload's percent ring (`progress`, 0 to 100)
-- or the spinner before one is known. A file shows as its pill.
export type Sent = {
	id: string,
	name: string,
	kind: "image" | "file",
	src: string?,
	w: number?,
	h: number?,
	status: ("loaded" | "loading" | "failed" | "uploading")?,
	progress: number?,
}

-- The upload's ring (loaders.rs upload_progress_ring): a 2.5 track in white
-- at 22%, the arc in white at 95% clockwise from 12 o'clock, its percent at
-- 9 semibold in the middle.
function M.ring(percent: number, size: number?): Node
	local d = size or 34
	local r = d / 2 - 2.5
	local frac = math.clamp(percent / 100, 0, 1)
	local c = d / 2
	local arc = ""
	if frac >= 0.999 then
		arc =
			`<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="#ffffff" stroke-opacity="0.95" stroke-width="2.5"/>`
	elseif frac > 0 then
		local a = -math.pi / 2 + 2 * math.pi * frac
		local x, y = c + r * math.cos(a), c + r * math.sin(a)
		local large = if frac > 0.5 then 1 else 0
		arc =
			`<path d="M{c} {c - r}A{r} {r} 0 {large} 1 {x} {y}" fill="none" stroke="#ffffff" stroke-opacity="0.95" stroke-width="2.5"/>`
	end
	local svg = `<svg xmlns="http://www.w3.org/2000/svg" width="{d}" height="{d}" viewBox="0 0 {d} {d}">`
		.. `<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="#ffffff" stroke-opacity="0.22" stroke-width="2.5"/>`
		.. arc
		.. "</svg>"
	return ui.overlay {
		w = d,
		h = d,
		items = "center",
		justify = "center",
		ui.svg { code = svg, w = d, h = d },
		txt.text {
			`{math.floor(percent)}%`,
			literal = true,
			size = "micro",
			weight = "semibold",
			color = "#fffffff2",
			line = false,
		},
	}
end

-- A file a message carried (user_file_pill): 28 high, at most 260, radius 7
-- on ink 6%, its glyph 16 on a 24 well, its name at 13 in the text at 85%.
function M.pill(a: Sent): Node
	return ui.row {
		id = a.id,
		h = 28,
		max_w = 260,
		min_w = 0,
		pl = "$zeron.space.2",
		pr = "$zeron.space.10",
		gap = "$zeron.space.6",
		items = "center",
		rounded = "$zeron.radius.7",
		bg = T.ink2,
		shrink = 0,
		ui.row {
			w = 24,
			h = 24,
			shrink = 0,
			rounded = "$zeron.radius.5",
			bg = T.activity_well,
			items = "center",
			justify = "center",
			require("./file_icon").icon { path = a.name, size = 16 },
		},
		txt.text {
			a.name,
			literal = true,
			size = "md",
			color = T.activity_badge,
			truncate = true,
			line = false,
			shrink = 1,
			min_w = 0,
		},
	}
end

-- An image a message carried: 112×80 at radius 8; loaded, a hairline at 11%
-- round the picture (cover, radius 7 inside it) and a click opens it.
function M.sent(a: Sent, on_open: (() -> ())?): Node
	local status = a.status or (if a.src then "loaded" else "failed")
	if status == "loading" then
		return ui.div {
			id = a.id,
			w = M.THUMB_W,
			h = M.THUMB_H,
			shrink = 0,
			rounded = "$zeron.radius.8",
			border = 1,
			border_color = T.ink3,
			bg = T.ink2,
			on_mount = function(el: Element)
				require("./loaders").breathe(el, 0.35, 0.75)
			end,
		}
	elseif status == "failed" or not a.src then
		return ui.div {
			id = a.id,
			label = `{a.name} unavailable`,
			w = M.THUMB_W,
			h = M.THUMB_H,
			shrink = 0,
			rounded = "$zeron.radius.8",
			border = 1,
			border_dash = { 3, 3 },
			border_color = T.ink5,
			bg = T.ink1,
		}
	end
	local uploading = status == "uploading"
	return ui.button {
		id = a.id,
		label = `Preview {a.name}`,
		relative = true,
		w = M.THUMB_W,
		h = M.THUMB_H,
		p = 0,
		shrink = 0,
		rounded = "$zeron.radius.8",
		border = 1,
		border_color = T.ink4,
		bg = T.ink1,
		overflow = "hidden",
		focus = { border = 0 },
		cursor = "pointer",
		on_click = on_open,
		ui.image {
			src = a.src,
			label = "",
			w = M.THUMB_W - 2,
			h = M.THUMB_H - 2,
			rounded = "$zeron.radius.7",
			fit = "cover",
		},
		uploading and ui.row {
			id = `{a.id}_upload`,
			absolute = true,
			left = 0,
			top = 0,
			right = 0,
			bottom = 0,
			rounded = "$zeron.radius.7",
			bg = "#00000061",
			items = "center",
			justify = "center",
			if a.progress then M.ring(a.progress) else require("./loaders").mini_spinner { cell = 3 },
		} or nil,
	}
end

return M
