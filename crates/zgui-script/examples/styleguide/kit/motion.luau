-- The kit's motion: Zeron's curves and durations (motion.rs), the lab's
-- spring, and the two switches the workbench drives: reduced motion (every
-- duration collapses) and slow motion (the engine's speed).
local M = {}

-- Durations in ms, read from the theme once per load (a theme change
-- reloads nothing, so these are the theme's at load; the tokens exist so a
-- theme can say otherwise).
local function ms(name: string, fallback: number): number
	local v = ui.theme.get(name)
	return if type(v) == "number" then v else fallback
end
M.FAST = ms("motion.duration.fast", 140)
M.NORMAL = ms("motion.duration.normal", 180)
M.SLOW = ms("motion.duration.slow", 320)
M.HOVER = ms("zeron.motion.hover", 150)
M.MENU_IN = ms("zeron.motion.menu_in", 140)
M.MENU_OUT = ms("zeron.motion.menu_out", 100)
M.DIALOG_IN = ms("zeron.motion.dialog_in", 180)
M.COLLAPSE = ms("zeron.motion.collapse", 180)
M.GLYPH = ms("zeron.motion.glyph", 280)
M.RESORT = ms("zeron.motion.resort", 260)
M.RESIZE = ms("zeron.motion.resize", 200)
M.TAB_SLIDE = ms("zeron.motion.tab_slide", 150)
M.SCROLL_GLIDE = ms("zeron.motion.scroll_glide", 500)
-- The dictation mic's morph and roll text's glyphs.
M.MORPH = ms("zeron.motion.morph", 420)
M.ROLL = ms("zeron.motion.roll", 550)

-- motion.rs's curves, as anime.js eases.
M.EASE = "cubicBezier(0.25, 0.1, 0.25, 1)"
M.EASE_OUT = "cubicBezier(0, 0, 0.58, 1)"
M.EASE_OUT_EXPO = "cubicBezier(0.16, 1, 0.3, 1)"
M.EASE_OUT_QUINT = "cubicBezier(0.22, 1, 0.36, 1)"
M.EASE_IN_OUT = "cubicBezier(0.42, 0, 0.58, 1)"
M.EASE_TAILWIND = "cubicBezier(0.4, 0, 0.2, 1)"
M.EASE_OUT_SOFT = "cubicBezier(0.2, 0, 0, 1)"
-- Every named curve, for the motion page.
local CURVES: { { name: string, ease: string, used: string } } = {
	{ name = "ease-out-soft", ease = M.EASE_OUT_SOFT, used = "indicator slides; the standard ease" },
	{ name = "ease-out-expo", ease = M.EASE_OUT_EXPO, used = "fade in, what arrives" },
	{ name = "ease-out-quint", ease = M.EASE_OUT_QUINT, used = "glyph states, resorting rows" },
	{ name = "ease-out", ease = M.EASE_OUT, used = "resize, collapse, tab slide" },
	{ name = "ease", ease = M.EASE, used = "menus, dialogs, quick fades" },
	{ name = "tailwind", ease = M.EASE_TAILWIND, used = "hover fades" },
	{ name = "ease-in-out", ease = M.EASE_IN_OUT, used = "scroll glides" },
}
M.CURVES = CURVES

-- The lab's spring: bounce 0.1, settling in 400 ms.
function M.spring(bounce: number?, duration: number?): AnimeEase
	return anime.spring { bounce = bounce or 0.1, duration = duration or 400 }
end
-- Press feedback: a stiff spring back.
function M.press_spring(): AnimeEase
	return anime.createSpring { stiffness = 600, damping = 28 }
end

-- Reduced motion: when on, `d(ms)` is 1 ms, so every fade and slide the kit
-- plays snaps, as Zeron snaps its one-shot animations.
M.reduced = ui.state("reduced", false)
function M.d(duration: number): number
	return if M.reduced:peek() then 1 else duration
end
-- Loops (spinners, pulses, breathing bars) do not run at all under reduced
-- motion, as Zeron holds them still; their durations never collapse.
function M.loops(): boolean
	return not M.reduced:peek()
end

-- Slow motion: the engine's speed, 1 / factor.
M.slow = ui.state("slow", 1)
ui.effect(function()
	anime.engine.speed = 1 / M.slow:get()
end)

return M
