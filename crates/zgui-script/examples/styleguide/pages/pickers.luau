-- Pickers: the reasoning slider on its own, the compact model picker's two
-- pages laid out in the flow, and the real thing opening from a composer's
-- model chip.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local picker = require("@kit/compact_picker")
local effort_slider = require("@kit/effort_slider")

local LEVELS = { "Low", "Medium", "High", "X-High", "Max" }

local verbosity = ui.state("pk_verbosity", "Medium")
local summaries = ui.state("pk_summaries", "Auto")
local MODELS: { picker.Model } = {
	{
		id = "opus",
		label = "Claude Opus 5.5",
		harness = "Claude Code",
		mark = "claude-mark",
		tint = T.claude,
		levels = LEVELS,
		fast = true,
	},
	{
		id = "sonnet",
		label = "Claude Sonnet 5.5",
		harness = "Claude Code",
		mark = "claude-mark",
		tint = T.claude,
		levels = LEVELS,
	},
	{ id = "haiku", label = "Claude Haiku 5.5", harness = "Claude Code", mark = "claude-mark", tint = T.claude },
	{
		id = "gpt",
		label = "GPT-5.5 Codex",
		harness = "Codex",
		mark = "openai-mark",
		levels = { "Low", "Medium", "High", "X-High" },
		options = {
			{ id = "verbosity", label = "Verbosity", choices = { "Low", "Medium", "High" }, value = verbosity },
			{
				id = "summaries",
				label = "Summaries",
				choices = { "Auto", "Concise", "Detailed", "None" },
				value = summaries,
			},
		},
	},
	{
		id = "gpt-mini",
		label = "GPT-5.5 mini",
		harness = "Codex",
		mark = "openai-mark",
		levels = { "Low", "Medium", "High" },
	},
	{
		id = "composer",
		label = "Composer 2",
		harness = "Cursor",
		mark = "cursor-mark",
		levels = { "Low", "Medium", "High" },
	},
	{ id = "grok", label = "Grok Code", harness = "Cursor", mark = "grok-mark" },
	{ id = "devin", label = "Devin", harness = "Devin", mark = "devin-mark" },
	{ id = "opencode", label = "OpenCode", harness = "OpenCode", mark = "opencode-mark", levels = { "Low", "High" } },
}

-- One set of choices the three instances share, as the chat's would be.
local model = ui.state("pk_model", "opus")
local effort = ui.state("pk_effort", 3)
local fast = ui.state("pk_fast", false)
local favorites = ui.state("pk_favorites", { "sonnet" } :: { string })

local slider_level = ui.state("pk_slider", 2)
local slider_fast_level = ui.state("pk_slider_fast", 4)
local slider_fast = ui.state("pk_slider_fast_on", true)
local always = ui.state("pk_always", 1)
local panel_page = ui.state("pk_panel_page", "panel")
local models_page = ui.state("pk_models_page", "models")
local live_open = ui.state("pk_live_open", false)
local draft = ui.state("pk_draft", "")

local function current_label(): string
	for _, m in MODELS do
		if m.id == model:get() then
			return m.label
		end
	end
	return ""
end
local function current_effort(): string
	for _, m in MODELS do
		if m.id == model:get() then
			local l = m.levels or {}
			return l[effort:get()] or "Default"
		end
	end
	return ""
end

return function(): Node
	local p = state.page_by("pickers")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "Reasoning slider",
			note = "36 box · rail 28 of light glass · thumb 44×32 white, overhanging by 2 · stops and the pointer share the 22 centre inset · the fill runs 14 past the centre · glides 200 ms ease-out, follows a drag, a press lifts the thumb · ← → Home End from the card",
			ui.row {
				gap = "$zeron.space.32",
				items = "start",
				flex_wrap = true,
				specimen.cell {
					label = "five levels",
					ui.column {
						w = 228,
						gap = "$zeron.space.8",
						effort_slider { id = "slider_plain", levels = LEVELS, selected = slider_level },
						kit.text.text {
							function()
								return LEVELS[slider_level:get()]
							end,
							id = "slider_plain_value",
							size = "xs",
							color = T.tertiary,
						},
					},
				},
				specimen.cell {
					label = "fast mode on: the halo breathes, light flows to the thumb",
					ui.column {
						w = 228,
						gap = "$zeron.space.8",
						effort_slider {
							id = "slider_fast",
							levels = LEVELS,
							selected = slider_fast_level,
							fast = slider_fast,
						},
						kit.toggle { id = "slider_fast_toggle", value = slider_fast, label = "Fast mode", size = "sm" },
					},
				},
				specimen.cell {
					label = "one level: the thumb has nowhere to go",
					ui.column { w = 228, effort_slider { levels = { "Default" }, selected = always } },
				},
			},
		},
		specimen.section {
			title = "Compact picker",
			note = "256 wide · card inset 4, rows at radius 7 · header 48 (36 without a ladder), the fast button 32 · slider block 2 + 36 + 4 · option rows 26, their choices beside them at 232 · models page: back and the providers as 32 tabs, starred first, a search row at 40, seven 32 rows then a scroll fading at 12 · the pages swap as the card resizes over 200 ms",
			ui.row {
				gap = "$zeron.space.32",
				items = "start",
				flex_wrap = true,
				specimen.cell {
					label = "the panel · ↑↓ opens the list, Tab cycles providers, F toggles fast",
					kit.compact_picker {
						id = "cp",
						inline = true,
						open = live_open,
						models = MODELS,
						model = model,
						effort = effort,
						fast = fast,
						favorites = favorites,
						page = panel_page,
					},
				},
				specimen.cell {
					label = "the models page · hover shows a star, ⌘⇧F on the highlighted row",
					kit.compact_picker {
						id = "cpm",
						inline = true,
						open = live_open,
						models = MODELS,
						model = model,
						effort = effort,
						fast = fast,
						favorites = favorites,
						page = models_page,
					},
				},
			},
			kit.text.text {
				function()
					return `model: {current_label()} · effort: {current_effort()} · fast: {if fast:get()
						then "on"
						else "off"}`
				end,
				id = "cp_state",
				size = "xs",
				mono = true,
				color = T.tertiary,
			},
		},
		specimen.section {
			title = "From the composer",
			note = "the model chip opens the card above it; the chip's effort suffix follows the slider",
			specimen.cell {
				fill = true,
				label = "click the chip",
				ui.column {
					w_full = true,
					items = "center",
					pt = "$zeron.space.24",
					kit.composer {
						id = "pcomp",
						w = 640,
						value = draft,
						model = current_label,
						effort = current_effort,
						on_model = ui.toggle(live_open),
						model_picker = function(chip: Node): Node
							return kit.compact_picker {
								id = "cp_live",
								open = live_open,
								anchor = chip,
								models = MODELS,
								model = model,
								effort = effort,
								fast = fast,
								favorites = favorites,
							}
						end,
					},
				},
			},
		},
	}
end
