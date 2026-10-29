-- Colour arithmetic on the `#rrggbbaa` strings `ui.theme.get` returns:
-- compositing a translucent token over its surface, and WCAG contrast.
local M = {}

export type Rgba = { r: number, g: number, b: number, a: number }

function M.parse(hex: string?): Rgba?
	if type(hex) ~= "string" or hex:sub(1, 1) ~= "#" then
		return nil
	end
	local h = hex:sub(2)
	if #h == 3 or #h == 4 then
		local out = ""
		for i = 1, #h do
			out ..= h:sub(i, i):rep(2)
		end
		h = out
	end
	if #h ~= 6 and #h ~= 8 then
		return nil
	end
	local n = tonumber(h:sub(1, 6), 16)
	if not n then
		return nil
	end
	local a = if #h == 8 then (tonumber(h:sub(7, 8), 16) or 255) / 255 else 1
	return { r = n // 65536, g = (n // 256) % 256, b = n % 256, a = a }
end

-- `top` over `under` (an opaque surface): the colour the eye sees.
function M.over(top: Rgba, under: Rgba): Rgba
	local a = top.a
	return {
		r = top.r * a + under.r * (1 - a),
		g = top.g * a + under.g * (1 - a),
		b = top.b * a + under.b * (1 - a),
		a = 1,
	}
end

local function channel(c: number): number
	local v = c / 255
	return if v <= 0.03928 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
end
function M.luminance(c: Rgba): number
	return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
end

-- The WCAG contrast ratio between a colour and the surface it sits on,
-- compositing the colour over the surface first.
function M.contrast(fg: Rgba, bg: Rgba): number
	local f = M.luminance(M.over(fg, bg))
	local b = M.luminance(bg)
	local hi, lo = math.max(f, b), math.min(f, b)
	return (hi + 0.05) / (lo + 0.05)
end

-- A ratio as "4.5:1".
function M.ratio(r: number): string
	return string.format("%.1f:1", r)
end

-- "#rrggbb" plus " 11%" when translucent, as the colour page labels it.
function M.label(hex: string?): string
	local c = M.parse(hex)
	if not c then
		return tostring(hex)
	end
	local base = string.format("#%02X%02X%02X", c.r, c.g, c.b)
	if c.a < 1 then
		return `{base} {math.floor(c.a * 100 + 0.5)}%`
	end
	return base
end

-- The token's colour, tracked, or nil.
function M.token(name: string): Rgba?
	return M.parse(ui.theme.get(name))
end

return M
