-- Typography: the scale, weights, line heights, the mono face, and how text
-- behaves when it runs out of room.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local txt = require("@kit/text")

type Step = { name: txt.Size, size: string, line: string, used: string }
local STEPS: { Step } = {
	{ name = "xxl", size = "font.size.xxl", line = "font.line.xxl", used = "settings page title (20), markdown h1" },
	{ name = "xl", size = "font.size.xl", line = "font.line.xl", used = "markdown h2, dialog titles (15)" },
	{ name = "lg", size = "font.size.lg", line = "font.line.lg", used = "prose 14/22, dialog fields, markdown h3" },
	{
		name = "md",
		size = "font.size.md",
		line = "font.line.md",
		used = "menus, pickers, rows, buttons, section labels",
	},
	{ name = "sm", size = "font.size.sm", line = "font.line.sm", used = "meta lines, chips, tabs, tool text" },
	{ name = "xs", size = "font.size.xs", line = "font.line.xs", used = "sublines 11/14, code language labels" },
	{
		name = "micro",
		size = "zeron.font.size.micro",
		line = "font.line.xs",
		used = "status words, menu headings, kbd, running pill (mono)",
	},
}
local WEIGHTS: { txt.Weight } = { "regular", "medium", "semibold", "bold" }

local function num(token: string): Node
	return kit.text.text {
		function()
			return tostring(ui.theme.get(token))
		end,
		size = "xs",
		mono = true,
		color = T.tertiary,
		w = 28,
		align = "end",
	}
end

local function scale(): Node
	local rows: { Node } = {}
	for _, step in STEPS do
		table.insert(
			rows,
			ui.row {
				items = "baseline",
				gap = "$zeron.space.16",
				py = "$zeron.space.6",
				border_sides = { 0, 0, 1, 0 },
				border_color = T.hairline,
				ui.row {
					w = 132,
					gap = "$zeron.space.6",
					items = "baseline",
					kit.text.text { step.name, size = "xs", mono = true, color = T.secondary, w = 40 },
					num(step.size),
					kit.text.text { "/", size = "xs", color = T.tertiary },
					num(step.line),
				},
				kit.text.text {
					"Agents run where the work is",
					size = step.name,
					weight = if step.name == "xxl" or step.name == "xl" then "semibold" else "regular",
					grow = 1,
					shrink = 1,
					min_w = 0,
					truncate = true,
				},
				kit.text.text { step.used, size = "xs", color = T.tertiary, w = 200, shrink = 0 },
			}
		)
	end
	return ui.column { w_full = true, max_w = 820, rows }
end

local function weights(): Node
	local cells: { Node } = {}
	for _, w in WEIGHTS do
		table.insert(
			cells,
			specimen.cell {
				label = w .. " · " .. tostring(ui.theme.get("font.weight." .. w)),
				kit.text.text { "Review the plan", size = "lg", weight = w },
			}
		)
	end
	return ui.row { gap = "$zeron.space.32", cells }
end

local function paragraph(): Node
	local body =
		"Zeron keeps every agent's status in its session server, so the sidebar shows what each one is doing without polling: working, blocked on a question, failed, or done and not yet seen."
	return ui.row {
		gap = "$zeron.space.24",
		items = "start",
		ui.column {
			w = 320,
			gap = "$zeron.space.8",
			kit.text.eyebrow("body · lg / 22"),
			kit.text.text { body, size = "lg", wrap = true, color = T.text },
		},
		ui.column {
			w = 260,
			gap = "$zeron.space.8",
			kit.text.eyebrow("secondary · md / 18"),
			kit.text.text { body, size = "md", wrap = true, color = T.secondary },
		},
		ui.column {
			w = 220,
			gap = "$zeron.space.8",
			kit.text.eyebrow("clamped to two lines"),
			kit.text.text { body, size = "md", wrap = true, lines = 2, color = T.text },
			kit.text.eyebrow("truncated"),
			kit.text.text { body, size = "md", truncate = true, w = 220 },
		},
	}
end

local function mono(): Node
	local lines = {
		"fn render(cx: &mut Context) -> View {",
		"    let count = cx.state(0);",
		'    column().gap(8.).child(text("Count"))',
		"}",
	}
	local code: { Node } = {}
	for i, l in lines do
		table.insert(
			code,
			ui.row {
				gap = "$zeron.space.14",
				kit.text.text {
					tostring(i),
					size = "sm",
					mono = true,
					color = T.tertiary,
					tabular = true,
					w = 14,
					align = "end",
				},
				kit.text.text { l, size = "sm", mono = true, color = T.text },
			}
		)
	end
	local figures: { Node } = {}
	for _, n in { "1,024", "48,213", "0.126", "99.9%" } do
		table.insert(
			figures,
			kit.text.text { n, size = "lg", mono = true, tabular = true, color = T.text, align = "end", w = 72 }
		)
	end
	return ui.row {
		gap = "$zeron.space.24",
		items = "start",
		ui.column {
			w = 420,
			p = "$zeron.space.14",
			gap = "$zeron.space.2",
			rounded = T.radius_lg,
			bg = T.sunken,
			border = 1,
			border_color = T.hairline,
			code,
		},
		ui.column {
			gap = "$zeron.space.8",
			kit.text.eyebrow("tabular figures"),
			ui.column { gap = "$zeron.space.2", items = "end", figures },
			kit.text.text {
				"Every digit one width, so a changing number holds still.",
				size = "xs",
				color = T.tertiary,
			},
		},
		ui.column {
			gap = "$zeron.space.8",
			kit.text.eyebrow("inline code"),
			ui.rich {
				wrap = true,
				w = 240,
				text_size = "$font.size.md",
				color = T.text,
				"Run ",
				ui.span { "cargo run --example styleguide", font = "mono", bg = "$zeron.code.wash" },
				" and edit ",
				ui.span { "kit/button.luau", font = "mono", bg = "$zeron.code.wash" },
				" to see it reload.",
			},
		},
	}
end

return function(): Node
	local page = state.page_by("typography")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Scale",
			note = "Size over line height, in points.",
			scale(),
		},
		specimen.section {
			title = "Weights",
			weights(),
		},
		specimen.section {
			title = "Paragraphs",
			paragraph(),
		},
		specimen.section { title = "Mono", mono() },
	}
end
