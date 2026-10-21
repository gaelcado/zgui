-- Closing something still running asks first: a sheet over the window,
-- answered by its buttons, Enter or Escape.
local theme = require("../theme")
local state = require("../state")
local sessions = require("../sessions")
local actions = require("../actions")

local confirm = state.confirm

local M = {}

-- What is waiting to close: "pane" or "tab", and its id.
local function pending(c: string): (string?, string?)
	return c:match("^(%w+):(.+)$")
end

-- Close what was asked about, or keep it.
function M.decide(yes: boolean)
	local kind, id = pending(confirm:peek())
	confirm:set("")
	if not yes or not id then
		local pane = actions.current()
		if pane then
			sessions.focus_view(pane)
		end
		return
	end
	if kind == "pane" then
		actions.close_pane(id, true)
	elseif kind == "tab" then
		actions.close_tab(id, true)
	end
end

-- The window's keys while the sheet is up: Enter closes, Escape keeps.
function M.on_key(e: KeyEvent): boolean
	if confirm:peek() == "" then
		return false
	end
	if e.key == "Escape" or e.key == "Enter" then
		local kind, id = pending(confirm:peek())
		confirm:set("")
		if e.key == "Enter" and id then
			if kind == "pane" then
				actions.close_pane(id, true)
			else
				actions.close_tab(id, true)
			end
		end
		return true
	end
	return false
end

function M.Sheet(): Node
	local function what(): (string, string)
		local kind, id = pending(confirm:get())
		if kind == "pane" then
			return `Close “{sessions.describe(id).name}”?`, "The process running in it will be ended."
		end
		return "Close this tab?", "Processes running in its panes will be ended."
	end
	local function button(label: string, primary: boolean, on_click: () -> ()): Node
		return ui.button {
			label,
			h = 30,
			px = 14,
			rounded = 8,
			text_size = 13,
			color = if primary then "#ffffff" else theme.text,
			bg = if primary then "#e5534bd9" else theme.wash,
			hover = { bg = if primary then "#f0645c" else "#ffffff1f" },
			focus = { border = 0 },
			on_click = on_click,
		}
	end
	return ui.div {
		hidden = function()
			return confirm:get() == ""
		end,
		absolute = true,
		left = 0,
		top = 0,
		w_full = true,
		h_full = true,
		bg = "#0000004d",
		items = "center",
		justify = "center",
		on_click = function()
			M.decide(false)
		end,
		ui.column {
			w = 340,
			p = 18,
			gap = 6,
			rounded = 14,
			bg = "#1d1e22d9",
			backdrop_blur = 28,
			border = 1,
			border_color = "#ffffff1f",
			shadow = { y = 18, blur = 48, color = "#00000080" },
			-- Clicks on the sheet stay on it.
			on_click = function() end,
			ui.text {
				function()
					return (what())
				end,
				text_size = 14,
				bold = true,
				color = theme.text,
			},
			ui.text {
				function()
					local _, body = what()
					return body
				end,
				text_size = 12.5,
				color = theme.secondary,
			},
			ui.row {
				mt = 12,
				gap = 8,
				justify = "end",
				button("Cancel", false, function()
					M.decide(false)
				end),
				button("Close", true, function()
					M.decide(true)
				end),
			},
		},
	}
end

return M
