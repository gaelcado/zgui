-- Inputs: text fields, a textarea, checkboxes and toggles, by state.
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")

local name = ui.state("name", "")
local filled = ui.state("filled", "zeron/comet")
local search = ui.state("search", "")
local notes = ui.state("notes", "")
local path = ui.state("path", "~/zeron/zgui/crates/zgui-script")
local invalid = ui.state("invalid", "not an email")
local checks = {
	ui.state("c1", true),
	ui.state("c2", false),
	ui.state("c3", true),
	ui.state("c4", false),
}
local toggles = {
	ui.state("t1", true),
	ui.state("t2", false),
	ui.state("t3", true),
	ui.state("t4", false),
}

local function fields(): Node
	return specimen.matrix {
		id = "input_states",
		columns = { "rest", "focus", "filled", "error", "disabled" },
		rows = { "sm", "md", "lg" },
		col_w = 160,
		row_h = 60,
		build = function(column: string, row: string): Node
			local size = row :: "sm" | "md" | "lg"
			if column == "hover" then
				return kit.input { value = name, placeholder = "Placeholder", size = size, preview = "hover", w = 148 }
			elseif column == "focus" then
				return kit.input { value = name, placeholder = "Placeholder", size = size, preview = "focus", w = 148 }
			elseif column == "filled" then
				return kit.input { value = filled, size = size, w = 148 }
			elseif column == "error" then
				return kit.input { value = invalid, size = size, error = "Enter an address", w = 148 }
			elseif column == "disabled" then
				return kit.input { value = filled, size = size, disabled = true, w = 148 }
			end
			return kit.input { value = name, placeholder = "Placeholder", size = size, w = 148 }
		end,
	}
end

local function composed(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "label, hint",
			kit.input {
				id = "field_name",
				value = name,
				label = "Project name",
				hint = "Shown in the sidebar.",
				placeholder = "My project",
				w = 240,
			},
		},
		specimen.cell {
			label = "leading icon, trailing key cap",
			kit.input {
				id = "field_search",
				value = search,
				icon = "magnifer",
				placeholder = "Search…",
				trailing = kit.kbd { "⌘", "K", flat = true, size = "sm" },
				w = 240,
			},
		},
		specimen.cell {
			label = "mono, select on focus",
			kit.input { value = path, mono = true, select_on_focus = true, w = 280 },
		},
		specimen.cell {
			label = "error from state",
			kit.input {
				value = invalid,
				label = "Email",
				error = function()
					return if invalid:get():find("@") then "" else "Enter an email address"
				end,
				w = 240,
			},
		},
		specimen.cell {
			label = "textarea",
			kit.textarea {
				id = "field_notes",
				value = notes,
				label = "Notes",
				placeholder = "Anything the agent should know",
				w = 360,
				h = 96,
			},
		},
	}
end

local function checkboxes(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		ui.column {
			gap = "$zeron.space.8",
			kit.checkbox { id = "check_on", value = checks[1], label = "Checked" },
			kit.checkbox { id = "check_off", value = checks[2], label = "Unchecked" },
			kit.checkbox { value = checks[3], label = "Indeterminate", indeterminate = true },
			kit.checkbox { value = checks[1], label = "Disabled", disabled = true },
			kit.checkbox { value = checks[2], label = "Disabled", disabled = true },
		},
		ui.column {
			gap = "$zeron.space.8",
			w = 320,
			kit.checkbox {
				value = checks[4],
				label = "Always allow",
				description = "Skip this approval for the rest of the session.",
			},
			kit.checkbox {
				value = checks[3],
				label = "Follow the system appearance",
				description = "Dark and light with macOS.",
			},
		},
	}
end

local function switches(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		ui.column {
			gap = "$zeron.space.10",
			kit.toggle { id = "toggle_on", value = toggles[1], label = "On" },
			kit.toggle { id = "toggle_off", value = toggles[2], label = "Off" },
			kit.toggle { value = toggles[3], label = "Disabled", disabled = true },
			kit.toggle { value = toggles[4], label = "Disabled", disabled = true },
			kit.toggle { value = toggles[1], label = "Small", size = "sm" },
		},
		ui.column {
			gap = "$zeron.space.10",
			w = 320,
			kit.toggle { value = toggles[4], label = "Reduced motion", description = "Snap instead of animating." },
			kit.toggle { value = toggles[3], label = "Sounds", description = "A chime when an agent needs you." },
		},
	}
end

return function(): Node
	local page = state.page_by("inputs")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Text fields",
			note = "The frame carries the states; the editor draws nothing of its own.",
			fields(),
		},
		specimen.section {
			title = "Composed",
			composed(),
		},
		specimen.section {
			title = "Checkbox",
			checkboxes(),
		},
		specimen.section {
			title = "Toggle",
			switches(),
		},
	}
end
