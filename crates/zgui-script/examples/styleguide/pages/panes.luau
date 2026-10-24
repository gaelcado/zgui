-- Panes: Wing's split workspace. Split the focused pane right or down,
-- drag a divider, drag a pane by its grip onto another's edge, zoom, close.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local panes = require("@kit/panes")
local layout = require("@kit/layout")

local address = ui.state("panes_address", "localhost:5173")
local hn_filter = ui.state("panes_hn", "Top")
local notes = ui.state("panes_notes", "")

local README = {
	"The same deterministic streaming-text and 100,000-row",
	"",
	"```sh",
	"ZGUI_MODE=both ZGUI_SECONDS=10 cargo run --release -p zgui",
	"ZGUI_MODE=idle ZGUI_SECONDS=0 cargo run --release -p zgui",
	"```",
	"",
	"The component workload uses the native GPU host and owns",
	"",
	"A heavier scene, `heavy_workload` (with a GPUI adapter",
	"",
	"See [benchmark commands and methodology](docs/benchmarks",
	"[parity-expansion comparison](docs/results/gpui-parity",
	"36 matched trials and 10,808 audited samples on Mesa",
	"delivered 59.6–59.95 model updates per requested second",
	"",
	"## Validation and current boundaries",
	"",
	"```sh",
	"cargo test --workspace --all-targets --locked",
	"cargo fmt --all -- --check",
	"```",
}
local STORIES = {
	{ title = "OpenAI CLI", domain = "github.com", score = 54, by = "armcat", age = "2h", comments = 29 },
	{
		title = "The recently proposed o(n log n) integer multiplication algorithm [pdf]",
		domain = "web.maths.unsw.edu.au",
		score = 169,
		by = "craigcitro",
		age = "5h",
		comments = 94,
	},
	{
		title = "WorldTUI: I trained a 360M model to pretend to be a terminal",
		domain = "simedw.com",
		score = 104,
		by = "alphax314",
		age = "5h",
		comments = 41,
	},
	{
		title = "There isn't an easy exploit for this PHP vulnerability",
		domain = "eliastaylor.com",
		score = 466,
		by = "zkldi",
		age = "8h",
		comments = 248,
	},
	{
		title = "GitLab critical patch release",
		domain = "docs.gitlab.com",
		score = 326,
		by = "artooro",
		age = "12h",
		comments = 75,
	},
	{
		title = "Compromised LiteLLM 1.107.0 on PyPI Installs a Credential Stealer and Backdoor",
		domain = "safedep.io",
		score = 488,
		by = "abhisek",
		age = "17h",
		comments = 167,
	},
	{
		title = "Using LLM for confidence scoring is a bad idea",
		domain = "rumple.github.io",
		score = 64,
		by = "jimauthors",
		age = "1d",
		comments = 39,
	},
	{
		title = "Rust Style Guide",
		domain = "google.github.io",
		score = 281,
		by = "kaycebasques",
		age = "12h",
		comments = 166,
	},
}

local KINDS: { [string]: string } = {}

local function terminal_lines(pane: string): Node
	local lines: { Node } = {}
	for i, l in
		{
			`~/zeron/zgui · {pane}`,
			"$ cargo test -p zgui-script --test styleguide",
			"   Compiling zgui-script v0.1.0",
			"    Finished test [unoptimized] in 1.2s",
			"test result: ok. 7 passed; 0 failed",
			"$ ▍",
		}
	do
		table.insert(
			lines,
			kit.text.text { l, size = "sm", mono = true, color = if i == 1 then T.tertiary else T.text, truncate = true }
		)
	end
	return ui.column {
		p = "$zeron.space.12",
		pt = "$zeron.space.10",
		gap = "$zeron.space.3",
		grow = 1,
		w_full = true,
		lines,
	}
end

local ws = panes.new {
	id = "ws",
	root = layout.pane("ws_p0"),
	name = function(pane: string)
		local k = KINDS[pane]
		return if k == "browser"
			then "Browser"
			elseif k == "editor" then "Editor"
			elseif k == "hn" then "Hacker News"
			elseif k == "notes" then "Notes"
			elseif k == "claude" then "Claude Code"
			else "Terminal"
	end,
	render = function(pane: string, inner: () -> number): Node
		local kind = KINDS[pane]
		if kind == "editor" then
			return kit.wing_panes.editor {
				id = "wing_editor",
				name = "README.md",
				path = "~/Documents/GitHub/zgui",
				lines = README,
				first_line = 115,
				language = "Markdown",
				selection = { 15, 22 },
			}
		elseif kind == "hn" then
			return kit.wing_panes.hn { id = "wing_hn", stories = STORIES, filter = hn_filter }
		elseif kind == "notes" then
			return kit.wing_panes.notes { id = "wing_notes", value = notes }
		elseif kind == "claude" then
			return kit.wing_panes.claude { id = "wing_claude" }
		end
		if KINDS[pane] == "browser" then
			return ui.column {
				grow = 1,
				w_full = true,
				items = "stretch",
				kit.browser.toolbar { value = address },
				ui.column {
					grow = 1,
					items = "center",
					justify = "center",
					kit.browser.empty {
						title = "Preview your work",
						body = "Start a dev server and its address shows up here.",
					},
				},
			}
		end
		return terminal_lines(pane)
	end,
}

local function toolbar(): Node
	local function tool(id: string, icon: string, label: string, on_click: () -> ())
		return kit.button {
			id = id,
			label = label,
			icon = { name = icon :: any },
			size = "sm",
			variant = "secondary",
			on_click = on_click,
		}
	end
	return ui.row {
		gap = "$zeron.space.8",
		items = "center",
		flex_wrap = true,
		tool("ws_split_right", "split-columns", "Split right", function()
			panes.split(ws, "row")
		end),
		tool("ws_split_down", "fold-vertical", "Split down", function()
			panes.split(ws, "column")
		end),
		tool("ws_browser", "globe", "Browser beside", function()
			local id = panes.split(ws, "row")
			if id then
				KINDS[id] = "browser"
			end
		end),
		tool("ws_editor", "document", "Editor", function()
			local id = panes.split(ws, "row")
			if id then
				KINDS[id] = "editor"
			end
		end),
		tool("ws_hn", "list", "Hacker News", function()
			local id = panes.split(ws, "row")
			if id then
				KINDS[id] = "hn"
			end
		end),
		tool("ws_notes", "pen", "Notes", function()
			local id = panes.split(ws, "column")
			if id then
				KINDS[id] = "notes"
			end
		end),
		tool("ws_claude", "claude-mark", "Claude Code", function()
			local id = panes.split(ws, "row")
			if id then
				KINDS[id] = "claude"
			end
		end),
		tool("ws_wing", "split-columns", "Wing's layout", function()
			-- His screenshot: the editor beside Hacker News, as one tab.
			local a, b, sp = panes.fresh(ws, "p"), panes.fresh(ws, "p"), panes.fresh(ws, "s")
			KINDS[a] = "editor"
			KINDS[b] = "hn"
			ws.root:set(layout.split(layout.pane(a), a, "row", b, sp))
			ws.ratios:set { [sp] = 0.6 }
			ws.zoom:set(nil)
			ws.focus:set(a)
		end),
		tool("ws_zoom", "expand-arrows", "Zoom", function()
			panes.toggle_zoom(ws)
		end),
		tool("ws_equalize", "collapse-arrows", "Equalize", function()
			panes.equalize(ws)
		end),
		tool("ws_close", "close", "Close", function()
			panes.close(ws)
		end),
		-- The area hides the least recently focused panes when they cannot
		-- all keep 160; this brings the latest back (it ranks most recent).
		ui.show(
			function()
				return #panes.hidden(ws) > 0
			end,
			kit.button {
				id = "ws_bring_back",
				label = "Bring back",
				size = "sm",
				variant = "ghost",
				icon = { name = "restart" },
				on_click = function()
					local hidden = panes.hidden(ws)
					local latest: string? = nil
					for _, id in hidden do
						if latest == nil or (ws.seen[id] or 0) > (ws.seen[latest :: string] or 0) then
							latest = id
						end
					end
					if latest then
						panes.focus(ws, latest)
					end
				end,
			}
		),
		kit.text.text {
			function()
				local n = #panes.panes(ws)
				local f = ws.focus:get()
				local hidden = #panes.hidden(ws)
				local held = next(ws.ratios:get()) ~= nil
				return `{n} pane{if n == 1 then "" else "s"} · focus {f or "—"}{if hidden > 0
					then ` · {hidden} hidden`
					else ""}{if held then " · divider held" else ""}`
			end,
			id = "ws_state",
			size = "xs",
			mono = true,
			color = T.tertiary,
		},
	}
end

-- The tabs layouts' topbar, the app's own, over three sample spaces.
local space_ids = ui.state("sg_spaces", { "s1", "s2", "s3" })
local space_active = ui.state("sg_space_active", "s1")
local space_names =
	ui.state("sg_space_names", { s1 = "Release notes", s2 = "Layout refactor", s3 = "Shell" } :: { [string]: string })
local space_renaming = ui.state("sg_space_renaming", "")
local SPACE_PANES: { [string]: { string } } = { s1 = { "chat", "term", "diff" }, s2 = { "chat" }, s3 = { "term" } }
local space_tabs = require("@kit/space_tabs")
local LOOKS: { [string]: space_tabs.Look } = {
	chat = { icon = "claude-mark", tint = T.claude },
	term = { icon = "terminal" },
	diff = { icon = "git-branch" },
}
local function topbar(): Node
	return ui.column {
		w_full = true,
		rounded = T.radius_card,
		bg = T.glass,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		space_tabs.topbar {
			ids = space_ids,
			active = space_active,
			names = space_names,
			renaming = space_renaming,
			panes = function(space: string)
				return SPACE_PANES[space] or {}
			end,
			look = function(pane: string)
				return LOOKS[pane] or { icon = "widget" }
			end,
			look_key = function(pane: string)
				return pane
			end,
			activate = function(space: string)
				space_active:set(space)
			end,
			rename = function(space: string, name: string)
				space_names:set_key(space, name)
				space_renaming:set("")
			end,
			new = function() end,
			close = function() end,
			close_others = function() end,
			project = "zgui",
		},
	}
end

return function(): Node
	local p = state.page_by("panes")
	return ui.column {
		gap = "$zeron.space.24",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.cell {
			label = "the tabs layouts' topbar · a space is a named group of panes, their glyphs before its name · close under the pointer · two presses rename it",
			topbar(),
		},
		toolbar(),
		specimen.cell {
			fill = true,
			label = "cards 4 apart · radius concentric with the window · ring when focused among several · grip 36×22 near the top, two rows of three dots, dragging a chip of the pane as a tab · dividers are the gap, a pill under the pointer, each side keeps 160 · under Zeron's panel policy: panes along an axis share it equally, a dragged divider holds until the next split, close or move, a double click shares equally again; structure changes ease on the panel curve (180 to 240 ms); an area too small for every pane hides the least recently focused",
			ui.column {
				w_full = true,
				max_w = "100%",
				min_w = 0,
				shrink = 1,
				h = 520,
				p = "$zeron.space.6",
				rounded = T.radius_card,
				bg = T.glass,
				border = 1,
				border_color = T.hairline,
				panes.view(ws, { grow = 1, w_full = true }),
			},
		},
		specimen.section {
			title = "Keys",
			ui.row {
				gap = "$zeron.space.24",
				flex_wrap = true,
				kit.hints {
					items = {
						{ keys = { "⌘", "D" }, label = "split right" },
						{ keys = { "⌘", "⇧", "D" }, label = "split down" },
						{ keys = { "⌘", "W" }, label = "close pane" },
						{ keys = { "⌘", "⏎" }, label = "zoom" },
						{ keys = { "⌥", "←↑↓→" }, label = "focus a neighbour" },
					},
				},
			},
		},
	}
end
