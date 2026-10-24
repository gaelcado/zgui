-- The Panels page's title-bar tabs (zimmer, after Dia), on their own so
-- the checker keeps up with the page.
local T = require("../theme")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local tabbar = require("@kit/tabbar")

local M = {}

local INITIAL: { tabbar.Tab } = {}
table.insert(INITIAL, { id = "d1", title = "zgui", icon = "folder", count = 3 } :: tabbar.Tab)
table.insert(
	INITIAL,
	{ id = "d2", title = "Write the release notes", icon = "claude-mark", tint = T.claude, working = true } :: tabbar.Tab
)
table.insert(INITIAL, { id = "d3", title = "comet", icon = "folder" } :: tabbar.Tab)
table.insert(INITIAL, { id = "d4", title = "Preview", icon = "globe", pinned = true } :: tabbar.Tab)
local dia_tabs = ui.state("dia_tabs", INITIAL)
local dia_value = ui.state("dia_value", "d2")
local dia_n = 4

local function dia_close(id: string)
	for i, t in dia_tabs:peek() do
		if t.id == id then
			dia_tabs:remove(i)
		end
	end
end
local function dia_add()
	dia_n += 1
	local t: tabbar.Tab = { id = `d{dia_n}`, title = `Conversation {dia_n}`, icon = "chat-round-line" }
	dia_tabs:push(t)
	dia_value:set(`d{dia_n}`)
end

local LABEL =
	"zimmer's title-bar tabs, after Dia: bar 42, tabs 30 at 200 → 96, 2 apart, top corners 10; the chosen tab in the canvas colour, hover lift 90 ms; close keeps its room; open and close 240 ms emphasized"

local function content(): Node
	local body: Node = ui.column {
		h = 120,
		w_full = true,
		bg = T.bg,
		items = "center",
		justify = "center",
		kit.text.text { "the chosen tab's content", size = "sm", color = T.tertiary },
	}
	local bar: Node = kit.tabbar.bar({
		id = "dia",
		tabs = dia_tabs,
		value = dia_value,
		on_close = dia_close,
		on_add = dia_add,
	} :: tabbar.Props)
	return ui.column {
		w_full = true,
		rounded = T.radius_card,
		bg = T.glass,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		bar,
		body,
	}
end

function M.bar(): Node
	local inner: Node = content()
	return specimen.cell { fill = true, label = LABEL, inner }
end

return M
