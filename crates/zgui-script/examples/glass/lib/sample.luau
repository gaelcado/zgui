-- What the demo shows: pinned favourites, spaces of items (Dia's tabs,
-- zimmer's conversations, Rex's sessions), and each item's content.
export type Kind = "chat" | "doc" | "terminal" | "web"
export type Message = { from: "me" | "them", text: string }
export type Item = {
	id: string,
	title: string,
	kind: Kind,
	meta: string,
	-- A chat's messages, a document's paragraphs, a terminal's lines.
	messages: { Message }?,
	paragraphs: { string }?,
	lines: { string }?,
	url: string?,
}
export type Space = { id: string, title: string, items: { string } }
export type Pin = { id: string, icon: string, title: string }

local M = {}

M.pins = {
	{ id = "pin_home", icon = "home", title = "Home" },
	{ id = "pin_star", icon = "star", title = "Starred" },
	{ id = "pin_clock", icon = "clock-circle", title = "Scheduled" },
	{ id = "pin_globe", icon = "globe", title = "Web" },
} :: { Pin }

M.items = {
	plan = {
		id = "plan",
		title = "Plan the week",
		kind = "chat",
		meta = "2m",
		messages = {
			{ from = "me", text = "What's left before Friday's release?" },
			{
				from = "them",
				text = "Three things. The glass material lands in the styleguide, the panes follow the new policy, and the notarized build needs one more run on CI.",
			},
			{
				from = "them",
				text = "The build is the only one that can slip: last night's run failed on the live DPI probe, which Wing has since fixed on main.",
			},
			{ from = "me", text = "Queue the CI run and remind me at four." },
			{ from = "them", text = "Queued on main. I'll check back at 4:00 PM and tell you how it went." },
		},
	},
	story = {
		id = "story",
		title = "Three thousand word story",
		kind = "doc",
		meta = "11:54",
		paragraphs = {
			"In the morning he went to the ribbon-cutting. He had not intended to. He had intended to sleep until noon and then sit in his kitchen and feel whatever he was going to feel.",
			"The brass band was enthusiastic and slightly flat. The scissors were, as promised, nearly half a meter long. The mayor gave a speech in which he thanked the engineers and the construction crews and the regional development fund.",
			"Katrin Vogel stood near the front in a clean reflective vest. When the ribbon fell and the crowd surged forward onto the bridge, she caught his eye across the crowd and held up one hand, palm out.",
			"Then he walked across.",
			"It took him a little over six minutes on foot. At the very top of the arc, he stopped and leaned on the railing and looked down. Far below, small and green and flat, the Margarethe sat at her eastern landing.",
			'"The rest of it," said Teodor Haas, "is that I got to carry everybody across."',
		},
	},
	build = {
		id = "build",
		title = "cargo build --release",
		kind = "terminal",
		meta = "running",
		lines = {
			"$ cargo build --release -p zgui-run",
			"   Compiling zgui v0.1.0 (crates/zgui)",
			"   Compiling zgui-script v0.1.0 (crates/zgui-script)",
			"   Compiling zgui-desktop v0.1.0 (crates/zgui-desktop)",
			"   Compiling zgui-run v0.1.0 (crates/zgui-run)",
			"    Finished `release` profile [optimized] target(s) in 57.32s",
			"$ zgui-run examples/glass",
			"glass: window 1180×760, plain glass, inset titlebar",
			"glass: watching 9 files",
		},
	},
	dia = {
		id = "dia",
		title = "Dia — the browser for AI",
		kind = "web",
		meta = "diabrowser.com",
		url = "diabrowser.com",
		paragraphs = {
			"Chat with your tabs. Ask about the page you're on, compare it with the others, and write with all of them in view.",
			"Your tabs live in the sidebar, in spaces, the way you think about them.",
		},
	},
	notes = {
		id = "notes",
		title = "Glass, measured",
		kind = "doc",
		meta = "yesterday",
		paragraphs = {
			"Rex's sidebar is the brightest surface (50, 51, 57) and its pane the darkest (36, 45, 54): the chrome is light and the content a well.",
			"The pane's edge is two hairlines: a dark one outside (22, 24, 28) and a lighter one just inside it (67, 70, 76). The well floats with a gap on all four sides.",
			"The material is neutral grey: the blur does the colouring, so the wallpaper reads through desaturated rather than under a navy paint.",
		},
	},
	review = {
		id = "review",
		title = "Review the panes PR",
		kind = "chat",
		meta = "1h",
		messages = {
			{ from = "me", text = "Does #914 keep the dragged divider?" },
			{
				from = "them",
				text = "Until the next toggle, yes. Double-clicking the seam puts the split back to equal shares.",
			},
		},
	},
	tests = {
		id = "tests",
		title = "cargo test -p zgui-script",
		kind = "terminal",
		meta = "passed",
		lines = {
			"$ cargo test -p zgui-script --test styleguide",
			"running 13 tests",
			"test walks_every_page_and_rests ... ok",
			"test panels_follow_the_policy ... ok",
			"test panes_follow_the_policy ... ok",
			"test lists_glide_to_the_hovered_row ... ok",
			"test result: ok. 13 passed; 0 failed",
		},
	},
} :: { [string]: Item }

M.spaces = {
	{ id = "today", title = "Today", items = { "plan", "story", "build", "dia" } },
	{ id = "misty", title = "misty-isle", items = { "notes", "review", "tests" } },
} :: { Space }

M.icons = {
	chat = "chat-round-line",
	doc = "document",
	terminal = "terminal",
	web = "globe",
} :: { [Kind]: string }

return M
