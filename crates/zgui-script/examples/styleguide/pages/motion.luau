-- Motion: Zeron's curves raced side by side, its durations, the lab's
-- spring, and the fades the kit plays, all under the slow-motion player.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local motion = kit.motion

-- The player: speed, and a Play that replays whatever the page shows.
local run = ui.state("run", 0)
local function play()
	run:set(run:peek() + 1)
end

local function player(): Node
	return ui.row {
		gap = "$zeron.space.10",
		items = "center",
		kit.button {
			id = "motion_play",
			label = "Play",
			icon = { name = "action-play" },
			variant = "primary",
			size = "sm",
			on_click = play,
		},
		kit.text.text { "Speed", size = "sm", color = T.secondary, ml = "$zeron.space.8" },
		kit.segmented {
			id = "motion_speed",
			size = "sm",
			value = ui.computed(function()
				return tostring(motion.slow:get())
			end) :: State<string>,
			options = { { id = "1", label = "1×" }, { id = "4", label = "¼" }, { id = "10", label = "⅒" } },
			on_change = function(id: string)
				motion.slow:set(tonumber(id) or 1)
			end,
		},
		kit.text.text {
			function()
				return if motion.reduced:get() then "reduced motion: durations collapse to 1 ms" else ""
			end,
			size = "xs",
			color = T.warning,
			ml = "$zeron.space.8",
		},
	}
end

-- A curve: its graph, and a dot that crosses a track with it when played.
local function curve(c: { name: string, ease: string, used: string }): Node
	local dot: Element? = nil
	local function bezier(): { number }
		local a, b, cc, d = c.ease:match("cubicBezier%(([%d.]+), ([%d.]+), ([%d.]+), ([%d.]+)%)")
		return { tonumber(a) or 0, tonumber(b) or 0, tonumber(cc) or 1, tonumber(d) or 1 }
	end
	local graph = ui.canvas {
		w = 64,
		h = 48,
		draw = function(cv: Canvas, w: number, h: number)
			local accent = ui.theme.get("accent")
			local faint = ui.theme.get("border")
			local p = bezier()
			local pad = 4
			local gw, gh = w - 2 * pad, h - 2 * pad
			cv.line(cv, pad, h - pad, w - pad, pad, faint, 1, { dash = { 2, 3 } })
			local path =
				ui.path()
					:move(pad, h - pad)
					:cubic(pad + p[1] * gw, h - pad - p[2] * gh, pad + p[3] * gw, h - pad - p[4] * gh, w - pad, pad)
			cv.stroke(cv, path, accent, 1.5, { cap = "round" })
		end,
	}
	ui.effect(function()
		if run:get() > 0 and dot then
			anime.animate(dot, { x = { 0, 200 }, duration = motion.d(900), ease = c.ease })
		end
	end)
	return ui.row {
		gap = "$zeron.space.14",
		items = "center",
		h = 52,
		graph,
		ui.column {
			w = 150,
			gap = "$zeron.space.2",
			kit.text.text { c.name, size = "sm", weight = "medium" },
			kit.text.text { c.ease:gsub("cubicBezier", ""), size = "micro", mono = true, color = T.tertiary },
		},
		ui.overlay {
			w = 216,
			h = 16,
			items = "start",
			justify = "center",
			ui.div { w = 216, h = 2, rounded = "$zeron.radius.1", bg = T.ink3, self = "center" },
			ui.div {
				w = 16,
				h = 16,
				rounded = "$zeron.radius.8",
				bg = T.solid,
				on_mount = function(el: Element)
					dot = el
				end,
			},
		},
		kit.text.text { c.used, size = "xs", color = T.tertiary, w = 220 },
	}
end

local function curves(): Node
	local rows: { Node } = {}
	for _, c in motion.CURVES do
		table.insert(rows, curve(c))
	end
	return ui.column { gap = "$zeron.space.4", rows }
end

-- Durations: a bar fills in each.
local function durations(): Node
	local specs: { { name: string, ms: number, note: string } } = {
		{ name = "menu_out", ms = motion.MENU_OUT, note = "a menu leaving" },
		{ name = "fast · menu_in", ms = motion.FAST, note = "menus, tooltips, hover washes" },
		{ name = "hover", ms = motion.HOVER, note = "hover fades (tailwind)" },
		{ name = "normal · dialog_in", ms = motion.NORMAL, note = "dialogs, page changes, collapses" },
		{ name = "resort", ms = motion.RESORT, note = "rows resorting, pills sliding" },
		{ name = "glyph", ms = motion.GLYPH, note = "a glyph changing state" },
		{ name = "tab_slide", ms = motion.TAB_SLIDE, note = "queue rows and tabs sliding (ease-out)" },
		{ name = "resize", ms = motion.RESIZE, note = "a width or height settling (ease-out)" },
		{ name = "morph", ms = motion.MORPH, note = "the mic becoming the stop plate (ease-out-soft)" },
		{
			name = "scroll_glide",
			ms = motion.SCROLL_GLIDE,
			note = "the transcript gliding to a rail tick (ease-in-out)",
		},
		{ name = "roll", ms = motion.ROLL, note = "a glyph rolling (ease-out-quint)" },
		{ name = "slow", ms = motion.SLOW, note = "the lab's long crossfade, panels" },
	}
	local rows: { Node } = {}
	for _, s in specs do
		local bar: Element? = nil
		ui.effect(function()
			if run:get() > 0 and bar then
				anime.animate(bar, { scaleX = { 0, 1 }, duration = motion.d(s.ms), ease = "linear" })
			end
		end)
		table.insert(
			rows,
			ui.row {
				gap = "$zeron.space.14",
				items = "center",
				h = 26,
				kit.text.text { s.name, size = "sm", w = 150 },
				kit.text.text {
					`{s.ms} ms`,
					size = "xs",
					mono = true,
					color = T.tertiary,
					tabular = true,
					w = 56,
					align = "end",
				},
				ui.div {
					w = 320,
					h = 6,
					rounded = "$zeron.radius.3",
					bg = T.ink3,
					overflow = "hidden",
					ui.div {
						w_full = true,
						h_full = true,
						rounded = "$zeron.radius.3",
						bg = T.solid,
						origin = { 0, 0.5 },
						scale_x = 0,
						on_mount = function(el: Element)
							bar = el
						end,
					},
				},
				kit.text.text { s.note, size = "xs", color = T.tertiary },
			}
		)
	end
	return ui.column { gap = "$zeron.space.2", rows }
end

-- The spring: a card that springs between two docks on click; and a block
-- whose space springs open and shut (`layout = "height"`).
local function spring(): Node
	local side = ui.state("spring_side", false)
	local open = ui.state("spring_open", true)
	local card: Element? = nil
	ui.effect(function()
		local at = if side:get() then 220 else 0
		if card then
			anime.animate(card, { x = at, ease = motion.spring(0.1, 400) })
		end
	end)
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		specimen.cell {
			label = "spring { bounce 0.1, 400 ms }: click to dock",
			ui.div {
				w = 300,
				h = 56,
				p = "$zeron.space.4",
				rounded = T.radius_lg,
				bg = T.ink2,
				border = 1,
				border_color = T.hairline,
				ui.button {
					id = "spring_card",
					w = 72,
					h = 46,
					rounded = T.radius_md,
					bg = T.raised,
					hover = { bg = T.button_hover },
					focus = { border = 1.5, border_over = true, border_color = T.ring },
					items = "center",
					justify = "center",
					on_click = ui.toggle(side),
					on_mount = function(el: Element)
						card = el
					end,
					kit.icon { name = "drag-handle", size = 16 },
				},
			},
		},
		specimen.cell {
			label = 'layout = "height": the space eases with the same spring',
			ui.column {
				w = 280,
				gap = "$zeron.space.8",
				kit.button { id = "spring_fold", label = "Fold", size = "sm", on_click = ui.toggle(open) },
				ui.presence(function()
					return if open:get() then "on" else nil
				end, function(): Node
					return ui.column {
						p = "$zeron.space.12",
						gap = "$zeron.space.6",
						rounded = T.radius_lg,
						bg = T.base,
						border = 1,
						border_color = T.hairline,
						kit.text.text { "Approval details", size = "sm", weight = "medium" },
						kit.text.text {
							"The run wants to write three files under src/.",
							size = "sm",
							color = T.secondary,
							wrap = true,
						},
					}
				end, {
					layout = "height",
					layout_clip = true,
					enter = { opacity = { 0, 1 }, duration = motion.d(motion.NORMAL) },
					exit = { opacity = 0, duration = motion.d(motion.FAST) },
				}),
			},
		},
	}
end

-- Fades: three tiles fade out and in over the lab's three lengths.
local function fades(): Node
	local tiles: { Node } = {}
	for _, ms in { 140, 180, 320 } do
		local el: Element? = nil
		ui.effect(function()
			if run:get() > 0 and el then
				anime.animate(el, {
					opacity = { 1, 0, 1 },
					y = { 0, 4, 0 },
					duration = motion.d(ms) * 2,
					ease = motion.EASE,
				})
			end
		end)
		table.insert(
			tiles,
			specimen.cell {
				label = `{ms} ms`,
				ui.column {
					w = 120,
					h = 64,
					p = "$zeron.space.10",
					rounded = T.radius_lg,
					bg = T.base,
					border = 1,
					border_color = T.hairline,
					justify = "end",
					on_mount = function(e: Element)
						el = e
					end,
					kit.text.text { "Fades", size = "sm", color = T.secondary },
				},
			}
		)
	end
	return ui.row { gap = "$zeron.space.24", tiles }
end

-- Press feedback: the kit's buttons squish on press and spring back.
local function press(): Node
	return ui.row {
		gap = "$zeron.space.12",
		kit.button { label = "Press me", variant = "primary" },
		kit.button { label = "And me" },
		kit.icon_button { icon = "star" },
	}
end

return function(): Node
	local page = state.page_by("motion")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		player(),
		specimen.section {
			title = "Curves",
			note = "Raced over 900 ms.",
			curves(),
		},
		specimen.section {
			title = "Durations",
			durations(),
		},
		specimen.section {
			title = "Spring",
			note = "bounce 0.1, 400 ms; layout animation uses the same.",
			spring(),
		},
		specimen.section {
			title = "Fades",
			note = "140 near and small, 180 dialogs and pages, 320 panels.",
			fades(),
		},
		specimen.section {
			title = "Press",
			press(),
		},
	}
end
