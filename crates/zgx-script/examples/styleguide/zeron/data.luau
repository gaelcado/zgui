-- The app's sample data: the agents and threads in the sidebar, the
-- models, a turn's todos and reply, the changes' hunk, the pane's stories
-- and README, the files, the pull requests. Everything here stands for what
-- the engine will send.
local T = require("../theme")
local agent_row = require("@kit/agent_row")
local tray = require("@kit/tray")
local compact_picker = require("@kit/compact_picker")
local diff = require("@kit/diff")
local history = require("@kit/history")
local file_tree = require("@kit/file_tree")
local pr = require("@kit/pr")
local visuals = require("./visuals")

local M = {}

local AGENTS: { agent_row.Agent } = {
	{
		id = "a1",
		name = "Write the release notes",
		where = "comet",
		status = "working",
		icon = "claude-mark",
		tint = T.claude,
		ago = "2m",
	},
	{
		id = "a2",
		name = "Refactor the layout engine",
		where = "zgx",
		status = "blocked",
		waits = "question",
		icon = "openai-mark",
		ago = "6m",
	},
	{
		id = "a3",
		name = "Fix flaky test",
		where = "zgx",
		status = "done",
		icon = "claude-mark",
		tint = T.claude,
		ago = "1h",
	},
}

export type Thread = { id: string, title: string, project: string, when: string }
local THREADS: { Thread } = {
	{ id = "h1", title = "Casual greeting exchange", project = "comet @ MacBook Pro", when = "3d" },
	{ id = "h2", title = "Production admin dashboard", project = "grid-website", when = "5d" },
	{ id = "h3", title = "Voice glyph", project = "comet", when = "6d" },
}

local TODOS: { tray.Todo } = {
	{ id = "t1", text = "Read the failing test", state = "done" },
	{ id = "t2", text = "Fix the recentre on blur", state = "active" },
	{ id = "t3", text = "Run the suite", state = "pending" },
}

local MODELS: { compact_picker.Model } = {
	{
		id = "opus",
		label = "Claude Opus 5.5",
		harness = "Claude Code",
		mark = "claude-mark",
		tint = T.claude,
		levels = { "Low", "Medium", "High", "X-High", "Max" },
		fast = true,
	},
	{
		id = "sonnet",
		label = "Claude Sonnet 5.5",
		harness = "Claude Code",
		mark = "claude-mark",
		tint = T.claude,
		levels = { "Low", "Medium", "High", "X-High", "Max" },
	},
	{
		id = "codex",
		label = "GPT-5.5 Codex",
		harness = "Codex",
		mark = "openai-mark",
		levels = { "Low", "Medium", "High", "X-High" },
	},
	{
		id = "composer2",
		label = "Composer 2",
		harness = "Cursor",
		mark = "cursor-mark",
		levels = { "Low", "Medium", "High" },
	},
}

local HUNK: diff.HunkProps = {
	header = "@@ -404,7 +404,9 @@ fn place(&mut self, node: NodeId)",
	lines = {
		{ kind = "ctx", old = 404, new = 404, text = "    let parent = self.parent(node);" },
		{ kind = "del", old = 405, text = "    let centred = self_align == Some(Align::Center);" },
		{ kind = "add", new = 405, text = "    let centred = parent.items == Align::Center && self_align.is_none();" },
		{ kind = "ctx", old = 406, new = 406, text = "    if centred {" },
	},
}

-- A generated table written whole: 640 lines added, more than a tool
-- row shows.
local ATLAS: diff.HunkProps = (function()
	local lines: { diff.Line } = {}
	for i = 1, 640 do
		table.insert(lines, {
			kind = "add" :: diff.Kind,
			new = i,
			text = `    ({i}, Glyph \{ x: {(i % 32) * 16}, y: {i // 32 * 16} \}),`,
		})
	end
	return { header = "@@ -0,0 +1,640 @@", lines = lines }
end)()

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
}

local README = {
	"## Validation and current boundaries",
	"",
	"```sh",
	"cargo test --workspace --all-targets --locked",
	"cargo test --workspace --doc --locked",
	"cargo clippy --workspace --all-targets --locked -- -D warnings",
	"cargo fmt --all -- --check",
	"```",
}

-- A streamed reply, in the chunks it arrives in (markdown once joined).
local REPLY = {
	"Here is a shorter pass that leads with the glass: one tint over the desktop's blur, the chat straight on it.\n\n",
	"- **Lists** fade at their edges rather than ending at a line.\n",
	"- **The composer** floats as a pill under the thread, and tool calls fold into a tree.\n\n",
	"Tell me whether you want this trimmed further or split into sections.",
}

local FILES: { file_tree.Flat } = {
	{ id = "crates", name = "crates", level = 0, folder = true, open = true },
	{ id = "zgx", name = "zgx", level = 1, folder = true, open = true },
	{ id = "f1", name = "compose.rs", level = 2, git = "modified" },
	{ id = "f2", name = "compose_scrollbar.rs", level = 2 },
	{ id = "styleguide", name = "styleguide", level = 1, folder = true },
	{ id = "f3", name = "Cargo.toml", level = 0 },
	{ id = "f4", name = "README.md", level = 0 },
}

local PRS: { pr.Row } = {
	{
		id = "p1",
		title = "Scroll fade on the transcript's bottom edge",
		number = 412,
		author = "gaelcado",
		status = "open",
		checks = "passed",
		sha = "9c245b6",
		date = "2h ago",
		updated = 120,
		opened = 4320,
		added = 128,
		removed = 41,
		labels = { "ui" },
	},
	{
		id = "p2",
		title = "Dictation: the stop plate on the accent glass",
		number = 409,
		author = "wing",
		status = "changes",
		checks = "failed",
		sha = "51f122b",
		date = "1d ago",
		updated = 1440,
		opened = 2880,
		added = 302,
		removed = 17,
		starred = true,
	},
	{
		id = "p3",
		title = "WIP: queue tray drag",
		number = 401,
		author = "gaelcado",
		status = "draft",
		date = "3d ago",
		updated = 4320,
		opened = 5760,
		added = 44,
		removed = 9,
	},
	{
		id = "p4",
		title = "Rebase onto the new layout root",
		number = 398,
		author = "wing",
		status = "conflicting",
		checks = "pending",
		sha = "2cec833",
		date = "4d ago",
		updated = 5760,
		opened = 10080,
		added = 12,
		removed = 230,
		labels = { "layout", "breaking" },
	},
}
-- What the board's "Load more" brings: GitHub's next page.
local MORE_PRS: { pr.Row } = {
	{
		id = "p5",
		title = "Wheel scrolling eases in whole pixels",
		number = 395,
		author = "wing",
		status = "open",
		checks = "passed",
		sha = "77d0e4b",
		date = "5d ago",
		updated = 7200,
		opened = 8640,
		added = 58,
		removed = 22,
	},
	{
		id = "p6",
		title = "Docs: the Metal driver's floor comes with any frame drawn",
		number = 391,
		author = "gaelcado",
		status = "open",
		checks = "passed",
		sha = "adeeb32",
		date = "6d ago",
		updated = 8640,
		opened = 12960,
		added = 9,
		removed = 3,
		labels = { "docs" },
	},
}

-- The sessions, as Zeron's sidebar lists them. `key` is how the app opens
-- one (`agent:` the agents, `thread:` the older threads); `row` names its
-- sidebar row.
export type Harness = "claude" | "codex" | "cursor"
export type Status = "working" | "input" | "failed" | "done" | "idle"
export type PrState = "open" | "draft" | "merged" | "closed"
export type Session = {
	key: string,
	row: string,
	title: string,
	harness: Harness,
	status: Status,
	project: string,
	branch: string?,
	pr: { number: number, state: PrState }?,
	ago: string,
	pinned: boolean?,
	-- A section of the user's own.
	section: string?,
	archived: boolean?,
	-- Started in this window: no turns of its own yet; on another device
	-- than this one (its name).
	fresh: boolean?,
	device: string?,
	-- What the branch adds over its base (the session card's branch row).
	diff: { number }?,
	-- A side chat's: the chat it runs beside, the chat it forked (a fresh
	-- side chat forks none), and whether its first message has yet to mint
	-- it (shell/side_chats.rs: nothing is written until then).
	parent: string?,
	fork: string?,
	unsaved: boolean?,
}
local SESSIONS: { Session } = {
	{
		key = "agent:a1",
		row = "agent_a1",
		title = "Write the release notes",
		harness = "claude",
		status = "working",
		project = "comet",
		branch = "release/0.2.117",
		ago = "2m",
		pinned = true,
		diff = { 12, 3 },
	},
	{
		key = "agent:a2",
		row = "agent_a2",
		title = "Refactor the layout engine",
		harness = "codex",
		status = "input",
		project = "zgx",
		branch = "layout-root",
		pr = { number = 398, state = "open" },
		ago = "6m",
		pinned = true,
		diff = { 148, 61 },
	},
	{
		key = "agent:a4",
		row = "agent_a4",
		title = "Durable Object token vault",
		harness = "claude",
		status = "idle",
		project = "comet",
		branch = "zeron/durable-object-token-vault",
		pr = { number = 971, state = "open" },
		ago = "42m",
		section = "Cloud + Onboarding",
	},
	{
		key = "agent:a5",
		row = "agent_a5",
		title = "Cloud: repair Codex installs",
		harness = "codex",
		status = "done",
		project = "comet",
		branch = "zeron/cloud-codex-repair",
		pr = { number = 975, state = "draft" },
		ago = "1h",
		section = "Cloud + Onboarding",
	},
	{
		key = "agent:a6",
		row = "agent_a6",
		title = "zgx prod: Windows platform",
		harness = "claude",
		status = "done",
		project = "zgx",
		branch = "windows/webview2",
		ago = "3m",
		section = "Cross Platform ZGX",
	},
	{
		key = "agent:a7",
		row = "agent_a7",
		title = "zgx prod: CI + Linux + zgx-script",
		harness = "claude",
		status = "working",
		project = "zgx",
		pr = { number = 96, state = "open" },
		ago = "20m",
		section = "Cross Platform ZGX",
	},
	{
		key = "agent:a8",
		row = "agent_a8",
		title = "zgx: native Mac multi-window",
		harness = "cursor",
		status = "failed",
		project = "zgx",
		ago = "1h",
		section = "Cross Platform ZGX",
	},
	{
		key = "agent:a3",
		row = "agent_a3",
		title = "Fix flaky test",
		harness = "claude",
		status = "done",
		project = "zgx",
		branch = "fix/flaky-dpi-probe",
		pr = { number = 94, state = "merged" },
		ago = "1h",
	},
	{
		key = "thread:h1",
		row = "thread_h1",
		title = "Casual greeting exchange",
		harness = "claude",
		status = "idle",
		project = "comet",
		ago = "3d",
	},
	{
		key = "thread:h2",
		row = "thread_h2",
		title = "Production admin dashboard",
		harness = "codex",
		status = "idle",
		project = "grid-website",
		branch = "admin",
		ago = "5d",
	},
	{
		key = "thread:h3",
		row = "thread_h3",
		title = "Voice glyph",
		harness = "claude",
		status = "idle",
		project = "comet",
		ago = "6d",
	},
	{
		key = "thread:h4",
		row = "thread_h4",
		title = "Onboarding copy pass",
		harness = "claude",
		status = "idle",
		project = "comet",
		ago = "2w",
		archived = true,
	},
	{
		key = "thread:h5",
		row = "thread_h5",
		title = "Try the Metal encoder",
		harness = "codex",
		status = "idle",
		project = "zgx",
		ago = "3w",
		archived = true,
	},
}
-- How many sessions the Archived shelf holds in all (it pages them in).
M.ARCHIVED_TOTAL = 585
M.PROJECTS = { "comet", "zgx", "grid-website" }
-- The artwork each project's checkout carries (project_icon.rs ICON_PATHS:
-- an apple-touch icon, a favicon, a logo); grid-website has none, so it
-- keeps its monogram.
M.PROJECT_ART = {
	comet = "images/projects/comet.svg",
	zgx = "images/projects/zgx.svg",
} :: { [string]: string }
-- Which devices hold each project, and which are reachable now: sample
-- presence until the engine is wired (the Cloud machine is asleep).
M.ONLINE = { ["MacBook Pro"] = true, ["Mac Studio"] = true, Cloud = false } :: { [string]: boolean }
M.PROJECT_DEVICES = {
	comet = { "MacBook Pro", "Mac Studio" },
	zgx = { "MacBook Pro" },
	["grid-website"] = { "Cloud" },
} :: { [string]: { string } }
-- Whether no device holding `project` is reachable (state.rs
-- project_device_tag): the space switcher's offline glyph.
function M.project_offline(project: string): boolean
	local devices = M.PROJECT_DEVICES[project]
	if not devices or #devices == 0 then
		return false
	end
	for _, d in devices do
		if M.ONLINE[d] then
			return false
		end
	end
	return true
end
-- This machine: where a session not said to run elsewhere runs.
M.THIS = "MacBook Pro"
-- The sessions hosted on another device, and which.
M.ELSEWHERE = {
	["agent:a7"] = "Mac Studio",
	["agent:a8"] = "Mac Studio",
	["thread:h2"] = "Mac Studio",
	["thread:h3"] = "Cloud",
} :: { [string]: string }
-- The dev servers the project runs, as the engine's preview discovery
-- reports them.
M.PREVIEWS = {
	{ id = "docs", name = "vite · zgx-docs", port = 5173, url = "http://localhost:5173/" },
	{ id = "site", name = "next · zeron.sh", port = 3000, url = "http://localhost:3000/" },
} :: { { id: string, name: string, port: number, url: string, device: string? } }
M.HARNESS = {
	claude = { name = "Claude Code", icon = "claude-mark", tint = T.claude },
	codex = { name = "Codex", icon = "openai-mark" },
	cursor = { name = "Cursor", icon = "cursor-mark" },
} :: { [Harness]: { name: string, icon: string, tint: Color? } }

-- Each session's transcript: its turns, each the user's message, the tools
-- the agent ran and its reply in markdown. A session without one shows
-- `DEFAULT_TURNS`.
-- A tool's call in full and what came back open under its row
-- (kit/activity): `call`, `output`, `hunks`, `images`.
export type Tool = {
	icon: string,
	label: string,
	detail: string,
	file: boolean?,
	call: string?,
	output: string?,
	hunks: { diff.HunkProps }?,
	images: { { src: string, name: string, w: number, h: number, path: string? } }?,
	-- A file it writes as it is done, and the diff that leaves in the
	-- working tree: the workspace shows it at once.
	writes: string?,
	patch: string?,
	-- Its whole output, kept apart (M.BLOBS), and its size.
	output_ref: string?,
	output_bytes: number?,
	-- A reasoning part ("Thought process"): its text.
	thought: string?,
	-- Still running (a turn that works on).
	status: ("running" | "done" | "failed")?,
	failed: boolean?,
}
-- What a prompt carried: an image (its picture, `w` by `h`; none, or
-- `failed`, for one that could not be read) or a file.
export type Attachment = {
	name: string,
	kind: "image" | "file",
	src: string?,
	w: number?,
	h: number?,
	failed: boolean?,
}
-- A subagent the turn spawned (its row opens its transcript, `M.SUBAGENTS`).
export type Spawn = { id: string, detail: string, model: string? }
-- An image the agent made: `src` none for one that is unavailable.
export type Generated = { name: string, src: string?, w: number?, h: number? }
-- A visual the agent showed (show_visual): its title and Luau script, none
-- for one whose script could not be read.
export type Visual = { title: string, script: string? }
-- `asked` and `answered`: when the prompt and the reply were sent, as
-- Zeron says it under a message ("Jul 1, 3:45 PM").
export type Turn = {
	user: string,
	tools: { Tool }?,
	spawns: { Spawn }?,
	images: { Generated }?,
	visuals: { Visual }?,
	reply: string,
	-- Still working, these seconds in (the working line's timer).
	working: number?,
	-- How long it worked, in seconds (compact mode's "Worked for").
	worked: number?,
	asked: string?,
	answered: string?,
	-- Sent by another chat (Zeron's send_message): that session's key.
	from: string?,
	attachments: { Attachment }?,
	-- How the run ended in error (its exit status and stderr).
	error: string?,
	-- A question it asked: answered, or awaiting its answer.
	question: { label: string, answer: string? }?,
	-- The send never reached the agent (no reply): a retry sends it.
	undelivered: boolean?,
	-- The chat switched provider at this message (its seam over it).
	switched: { from: Harness, to: Harness }?,
	-- Messages its agent sent other chats (send_message): each to a
	-- session's key or a title the workspace does not list; failed, or
	-- not returned yet.
	messages: { { to: string, failed: boolean?, pending: boolean? } }?,
}
local TEST_OUTPUT = table.concat({
	"running 20 tests",
	"test dpi::caret_after_first_layout ... ok",
	"test dpi::caret_at_two_x ... ok",
	"test dpi::centred_single_line_caret ... FAILED",
	"test dpi::fractional_scale_snaps ... ok",
	"test dpi::live_probe_reads_caret ... ok",
}, "\n") .. string.rep("\ntest dpi::repeat ... ok", 24) .. "\n\ntest result: FAILED. 19 passed; 1 failed\n"
-- The loop's whole output, kept apart from the transcript (its sidecar):
-- every run's, past the 400 lines a fetch shows.
local FULL_TEST_OUTPUT = (function(): string
	local runs: { string } = {}
	for i = 1, 20 do
		table.insert(runs, `run {i}\n{TEST_OUTPUT}`)
	end
	return table.concat(runs, "\n")
end)()
-- Sidecars by key (FETCH_TOOL_BLOB's).
local BLOBS: { [string]: string } = { ["a3/dpi-loop"] = FULL_TEST_OUTPUT }
function M.blob(ref: string): string?
	return BLOBS[ref]
end
local TRANSCRIPTS: { [string]: { Turn } } = {
	["agent:a1"] = {
		{
			user = "Can you draft the release notes for 0.2.117?",
			asked = "Oct 24, 9:41 AM",
			answered = "Oct 24, 9:42 AM",
			worked = 70,
			tools = {
				{
					icon = "document",
					label = "Read",
					detail = "CHANGELOG.md",
					file = true,
					call = "CHANGELOG.md",
					output = "# Changelog\n\n## 0.2.116\n\n- Cloud: the engine starts on wake.\n- Pull requests: the board follows the panel layout.\n",
				},
				{
					icon = "terminal",
					label = "Run",
					detail = "git log --oneline v0.2.116..HEAD",
					call = "git log --oneline v0.2.116..HEAD",
					output = "548985a Build: dependencies keep line tables\na00d4fb Build: one skrifa and read-fonts, not two\ne38b0d3 cosmic-text: a word's cache key hashes once a line\n3a8ab50 zgx-script: debug builds give script calls more time\n5212aa5 Layout: a column's automatic minimum is its items' height\n",
				},
				{
					icon = "chat-round-line",
					label = "Thought process",
					detail = "",
					thought = "Five commits since **v0.2.116**, in three areas:\n\n- Cloud and pull requests read well from the log alone.\n- The Windows notes need the WebView2 work read closely.\n\nHand that and the list of merged pull requests to subagents, and lead with the breaking change, as the last notes did.",
				},
			},
			spawns = {
				{ id = "sa2", detail = "collect the merged pull requests", model = "haiku" },
				{ id = "sa3", detail = "draft the Windows notes" },
			},
			reply = "Here is a first pass, grouped by area, with the breaking change first.\n\n## 0.2.117\n\n**Breaking:** the panel width setting now stores the pane's latest split.\n\n- **Cloud:** repaired Codex installs, and the engine starts on wake.\n- **Pull requests:** the pane follows the shared panel layout (`#914`).\n- **Windows:** web views are WebView2 pages composited with zgx.\n\nTell me whether you want it shorter, or split by platform.",
		},
		{
			user = "Shorter, and lead with Cloud.",
			asked = "Oct 24, 9:47 AM",
			answered = "Oct 24, 9:47 AM",
			tools = {
				{
					icon = "bot",
					label = "Tool",
					detail = "Wait for agents",
					status = "running",
				},
			},
			spawns = {
				{ id = "sa1", detail = "verify the release links", model = "sonnet" },
			},
			reply = "- **Cloud:** Codex installs repair themselves; the engine starts on wake.\n- **Pull requests:** the pane splits the room with the board.\n- **Breaking:** the pane's width setting is now its latest split.",
			working = 112,
		},
	},
	["agent:a2"] = {
		{
			user = "Before you touch the gap pass: the DPI fix changes `place` in layout.rs too. Rebase on fix/flaky-dpi-probe first.",
			from = "agent:a3",
			asked = "Oct 23, 4:02 PM",
			answered = "Oct 23, 4:03 PM",
			worked = 41,
			reply = "Rebased on `fix/flaky-dpi-probe`; `place` now reads the caret after the first layout, and the gap pass goes on top of it in [#398](https://github.com/zeron/comet/pull/398).",
		},
		{
			user = "Refactor the layout engine so a column's gap skips hidden children.",
			switched = { from = "claude", to = "codex" },
			asked = "Oct 23, 4:12 PM",
			answered = "Oct 23, 4:14 PM",
			worked = 134,
			question = { label = "Should `invisible` children still take a gap?" },
			tools = {
				{
					icon = "document",
					label = "Read",
					detail = "crates/zgx/src/layout.rs",
					file = true,
					call = "crates/zgx/src/layout.rs",
					output = "fn place(&mut self, node: NodeId) {\n    let parent = self.parent(node);\n    let gaps = gap * children.len().saturating_sub(1) as f32;\n    for child in children {\n        self.place(child);\n    }\n}\n",
				},
				{
					icon = "magnifer",
					label = "Search",
					detail = "gap around hidden",
					call = "gap around hidden in crates/zgx/src",
					output = "crates/zgx/src/layout.rs:412: // the gap around hidden children\ncrates/zgx/src/layout.rs:418: let gaps = gap * children.len()\n",
				},
			},
			reply = "The gap is added between every pair of children, hidden or not. Two ways out:\n\n| Approach | Cost | Risk |\n| --- | --- | --- |\n| Skip hidden children when summing gaps | one pass | none |\n| Collapse hidden children to zero and their gaps | two passes | margins change |\n\nI'd take the first:\n\n```rust\nlet shown = children.iter().filter(|c| !c.hidden);\nlet gaps = gap * shown.count().saturating_sub(1) as f32;\n```\n\nThe change sits in `crates/zgx/compose.rs`, beside its [scrollbar](crates/zgx/compose_scrollbar.rs); `Cargo.toml` needs nothing. The [flexbox spec](https://www.w3.org/TR/css-flexbox-1/#main-sizing) counts gaps the same way.\n\n```mermaid\ngraph LR\n  A[A child] --> B{Hidden?}\n  B -->|No| C[A gap before it]\n  B -->|Yes| D[Skipped]\n```\n\n> Before I change it: should `invisible` (which keeps its room) still take a gap?",
		},
	},
	["agent:a3"] = {
		{
			user = "The DPI probe fails on CI about once in ten runs. Find out why.",
			asked = "Oct 22, 11:05 AM",
			answered = "Oct 22, 11:09 AM",
			worked = 248,
			tools = {
				{
					icon = "terminal",
					label = "Run",
					detail = "cargo test -p zgx --test dpi -- --test-threads=1 (×20)",
					call = "for i in $(seq 20); do cargo test -p zgx --test dpi -- --test-threads=1 || break; done",
					output = TEST_OUTPUT,
					output_ref = "a3/dpi-loop",
					output_bytes = #FULL_TEST_OUTPUT,
				},
				{
					icon = "document",
					label = "Read",
					detail = "target/dpi/caret.jpg",
					file = true,
					call = "target/dpi/caret.jpg",
					images = {
						{
							src = "images/shadow.jpg",
							name = "caret.jpg",
							w = 720,
							h = 480,
							path = "target/dpi/caret.jpg",
						},
						{
							src = "images/screenshot-tall.jpg",
							name = "caret-2x.jpg",
							w = 480,
							h = 720,
							path = "target/dpi/caret-2x.jpg",
						},
					},
				},
				{
					icon = "pen",
					label = "Edit",
					detail = "crates/zgx/src/layout.rs",
					file = true,
					call = "crates/zgx/src/layout.rs",
					hunks = { HUNK },
				},
				{
					icon = "pen",
					label = "Write",
					detail = "crates/zgx-gpu/src/atlas_table.rs",
					file = true,
					call = "crates/zgx-gpu/src/atlas_table.rs",
					hunks = { ATLAS },
				},
			},
			-- It told the layout chat to rebase; the checklist's chat was
			-- archived away.
			messages = {
				{ to = "agent:a2" },
				{ to = "Release checklist", failed = true },
			},
			reply = "Found it. The probe reads the caret before the editor's first layout, so on a slow runner it sees the old position.\n\n1. Wait for the editor's `layout` event before reading the caret.\n2. Center the expected caret for single-line editors, as main now does.\n3. Run it 50 times: **50 passed**.\n\n![The caret, after the fix](images/shadow.jpg)\n\n- [x] Fix the race\n- [x] Update the expectation\n- [ ] Ask Wing whether the probe should time out sooner",
		},
	},
	["thread:h2"] = {
		{
			user = "Sketch the admin dashboard's first screen.",
			reply = "A first screen with three cards and a table:\n\n- **Revenue** this month, against last\n- **Active teams**, with the trend\n- **Failed jobs** in the last day\n\nUnder them, the newest sign-ups with their plan and their team size.",
		},
		{
			user = "Make a mockup of it, and one of the empty state.",
			worked = 96,
			images = {
				{ name = "dashboard.png", src = "images/shadow.jpg", w = 720, h = 480 },
				{ name = "dashboard-empty.png" },
			},
			reply = "The first is the dashboard with a month of data. The empty state's image did not come back from the generator; ask again and I will retry it.",
		},
		{
			user = "Chart the sign-ups for the last six weeks, show me the rack whose jobs failed, and the uptime by region.",
			worked = 71,
			visuals = {
				{ title = "Sign-ups by week", script = visuals.SIGNUPS },
				{ title = "The cluster's rack", script = visuals.RACK },
				{ title = "Uptime by region", script = visuals.UPTIME },
			},
			reply = "Pro sign-ups grew every week but one. Week over week the growth is $g_t = \\frac{s_t - s_{t-1}}{s_{t-1}}$, and over the six weeks it averages\n\n$$\\bar g = \\Big(\\prod_{t=1}^{5} (1 + g_t)\\Big)^{1/5} - 1 \\approx 5.7\\%$$\n\nThe third server is the one whose jobs failed. The uptime by region needs the status page, which a visual cannot reach.",
		},
	},
	["agent:a4"] = {
		{
			user = "Move the vault into @crates/cloud/src/vault.rs and keep @docs/cloud.md in step with it.",
			asked = "Oct 21, 2:30 PM",
			answered = "Oct 21, 2:36 PM",
			worked = 352,
			tools = {
				{
					icon = "document",
					label = "Read",
					detail = "crates/cloud/src/tokens.rs",
					file = true,
					call = "crates/cloud/src/tokens.rs",
				},
				{
					icon = "pen",
					label = "Write",
					detail = "crates/cloud/src/vault.rs",
					file = true,
					call = "crates/cloud/src/vault.rs",
				},
				{
					icon = "pen",
					label = "Edit",
					detail = "docs/cloud.md",
					file = true,
					call = "docs/cloud.md",
				},
			},
			reply = "The vault is its own module now: `vault.rs` holds the Durable Object and its token store, and `tokens.rs` only asks it. The docs describe the new split.",
		},
		{
			user = "Add a test for the vault's token rotation.",
			asked = "Oct 21, 3:02 PM",
			answered = "Oct 21, 3:02 PM",
			reply = "",
			error = "Claude AI usage limit reached. Your limit resets at 5 PM (Europe/Paris).",
		},
	},
	["agent:a5"] = {
		{
			user = "Codex installs fail on the Cloud machines after an update. Here is what I see, and the install log.",
			asked = "Oct 20, 10:12 AM",
			answered = "Oct 20, 10:19 AM",
			worked = 431,
			attachments = {
				{ name = "Install failed.png", kind = "image", src = "images/screenshot-tall.jpg", w = 480, h = 720 },
				{ name = "Update prompt.png", kind = "image", failed = true },
				{ name = "codex-install.log", kind = "file" },
			},
			reply = "The update replaces the binary while the old one still runs, and the install marks itself done before the copy finishes. The repair now waits for the old process to exit, then checks the binary's version before it says it is done.",
		},
		{
			user = "Check the repair on the staging machines too.",
			asked = "Oct 20, 11:40 AM",
			answered = "Oct 20, 11:40 AM",
			reply = "",
			error = "Codex is not signed in. Run codex login, then try again.",
		},
	},
	["agent:a6"] = {
		{
			user = "Run the WebView2 smoke on Windows.",
			asked = "Oct 24, 8:10 AM",
			answered = "Oct 24, 8:14 AM",
			worked = 255,
			reply = "The smoke passes on Windows 11 x64: pages load, a popup opens a tab, and the composited view follows a resize.",
		},
		{
			user = "Run the WebView2 smoke on the ARM runner too.",
			asked = "Oct 24, 9:58 AM",
			undelivered = true,
			reply = "Started on the ARM runner: the smoke passes there as well, in about the same time.",
		},
	},
	["agent:a7"] = {
		{
			user = "CI fails on Linux since this morning. The log:\n\nerror[E0599]: no method named `set_selection` found for struct `Element`\n  --> crates/zgx-script/src/element.rs:812:14\n   |\n812 |         self.set_selection(a, b)\n   |              ^^^^^^^^^^^^^ method not found in `Element`\n   |\n   = help: items from traits can only be used if the trait is in scope\nhelp: trait `Selectable` which provides `set_selection` is implemented but not in scope\n   |\n1  + use zgx::text::Selectable;\n   |\nerror: could not compile `zgx-script` (lib) due to 1 previous error\n\nFix it, and make sure the Linux smokes run on the change.",
			asked = "Oct 24, 7:40 AM",
			answered = "Oct 24, 7:52 AM",
			worked = 720,
			tools = {
				{
					icon = "document",
					label = "Read",
					detail = "crates/zgx-script/src/element.rs",
					file = true,
					call = "crates/zgx-script/src/element.rs",
				},
				{
					icon = "terminal",
					label = "Run",
					detail = "python3 scripts/linux_smokes.py --only selection",
					call = "python3 scripts/linux_smokes.py --only selection",
					output = "selection: ok (x11)\nselection: ok (wayland)\n",
				},
			},
			reply = "The trait import was dropped in the last refactor; it is back, and the selection smokes pass on X11 and Wayland.",
		},
	},
	["agent:a8"] = {
		{
			user = "Open a second window from the dock menu.",
			asked = "Oct 24, 8:31 AM",
			answered = "Oct 24, 8:32 AM",
			worked = 38,
			tools = {
				{
					icon = "terminal",
					label = "Run",
					detail = "cargo run -p zgx-desktop --example multi_window",
					call = "cargo run -p zgx-desktop --example multi_window",
					output = "thread 'main' panicked at crates/zgx-desktop/src/mac/window.rs:212:9\n",
					failed = true,
				},
			},
			reply = "",
			error = "cursor-agent exited with status 1\nerror: the window server refused the second NSWindow (kCGErrorIllegalArgument)\n  at crates/zgx-desktop/src/mac/window.rs:212:9",
		},
	},
	-- The subagents' own transcripts (a spawn row opens one in a tab).
	["subagent:sa1"] = {
		{
			user = "Verify every link in docs/release-notes.md resolves, and say which redirect.",
			working = 64,
			tools = {
				{
					icon = "global",
					label = "Fetch",
					detail = "https://github.com/zeronsh/comet/pull/914",
					call = "https://github.com/zeronsh/comet/pull/914",
					output = "301 → https://github.com/zeronsh/comet/pull/914 (merged)\n",
				},
			},
			reply = "",
		},
	},
	["subagent:sa2"] = {
		{
			user = "List the pull requests merged since v0.2.116, with their numbers and titles.",
			worked = 52,
			tools = {
				{
					icon = "terminal",
					label = "Run",
					detail = "gh pr list --state merged --search 'merged:>2026-10-17'",
					call = "gh pr list --state merged --search 'merged:>2026-10-17'",
					output = "914  Pull requests: the board follows the panel layout\n911  Cloud: the engine starts on wake\n906  Windows: WebView2 pages\n",
				},
			},
			reply = "Three since v0.2.116: **#914** (the board follows the panel layout), **#911** (the engine starts on wake), **#906** (WebView2 pages on Windows).",
		},
	},
	["subagent:sa3"] = {
		{
			user = "Draft the Windows section of the 0.2.117 notes from the WebView2 commits.",
			worked = 19,
			reply = "",
			error = "The subagent stopped: its context ran out reading crates/zgx-desktop/src/windows/webview.rs (3,412 lines).",
		},
	},
}
local DEFAULT_TURNS: { Turn } = {
	{
		user = "Pick up where we left off.",
		reply = "Here is where things stand:\n\n- The branch is up to date with `main`.\n- Two tests were flaky last run; both pass now.\n\nWhat should I do next?",
	},
}
function M.turns(session: string?): { Turn }
	return (session and TRANSCRIPTS[session]) or DEFAULT_TURNS
end

-- The voice orchestrator's chat (voice.rs): projectless Codex on this
-- device, resumed across calls, its transcript what was said. It takes no
-- sidebar row.
local VOICE: Session = {
	key = "agent:voice-orchestrator-1",
	row = "agent_voice",
	title = "Voice session",
	harness = "codex",
	status = "idle",
	project = "",
	ago = "now",
}
TRANSCRIPTS[VOICE.key] = {}
function M.voice_turns(): { Turn }
	return TRANSCRIPTS[VOICE.key]
end

-- A session started from the new-session canvas, at the top of the list.
local created = 0
function M.add_session(title: string, project: string, device: string?): Session
	created += 1
	local s: Session = {
		device = device,
		key = `agent:n{created}`,
		row = `agent_n{created}`,
		title = title,
		harness = "claude",
		status = "working",
		project = project,
		ago = "now",
		fresh = true,
	}
	table.insert(SESSIONS, 1, s)
	return s
end

-- The side chats (session_lanes.rs): chats run beside another, forked
-- from it or started fresh; the sidebar never lists them, the session
-- card's lanes do.
local SIDE_CHATS: { Session } = {
	{
		key = "side:s1",
		row = "side_s1",
		title = "Check the release links",
		harness = "claude",
		status = "done",
		project = "comet",
		branch = "release/0.2.117",
		ago = "4m",
		parent = "agent:a1",
		fork = "agent:a1",
	},
	{
		key = "side:s2",
		row = "side_s2",
		title = "A shorter post for the blog",
		harness = "codex",
		status = "working",
		project = "comet",
		branch = "release/0.2.117",
		ago = "1m",
		parent = "agent:a1",
		fork = "agent:a1",
	},
}
TRANSCRIPTS["side:s1"] = {
	{
		user = "Do the links in the notes still resolve?",
		reply = "All five resolve. `#914` redirects to the merged pull request; the others are direct.",
	},
}

function M.session(key: string): Session?
	for _, s in SESSIONS do
		if s.key == key then
			return s
		end
	end
	if key == VOICE.key then
		return VOICE
	end
	for _, s in SIDE_CHATS do
		if s.key == key then
			return s
		end
	end
	return nil
end

-- The live side chats of `parent`, the most recent first (as the lanes
-- list them); those still unsaved list once their first message is sent.
function M.side_chats(parent: string): { Session }
	local out: { Session } = {}
	for i = #SIDE_CHATS, 1, -1 do
		local s = SIDE_CHATS[i]
		if s.parent == parent and not s.unsaved and not s.archived then
			table.insert(out, s)
		end
	end
	return out
end

-- A side chat of `parent` on its device and checkout: `fork`'s history
-- copied through its latest reply, or a fresh one, unsaved until its
-- first message.
local sides = 0
function M.add_side_chat(parent: string, fork: string?): Session
	sides += 1
	local from = M.session(parent)
	local s: Session = {
		key = `side:n{sides}`,
		row = `side_n{sides}`,
		title = "New side chat",
		harness = if from then from.harness else "claude",
		status = "idle",
		project = if from then from.project else "zgx",
		branch = from and from.branch,
		ago = "now",
		parent = parent,
		fork = fork,
		unsaved = fork == nil,
	}
	table.insert(SIDE_CHATS, s)
	return s
end

-- A side chat titles itself on its first message (until then "New side
-- chat"); an unsaved one is minted by it.
function M.side_chat_sent(key: string, text: string)
	local s = M.session(key)
	if not s or not s.parent then
		return
	end
	s.unsaved = nil
	s.status = "working"
	s.ago = "now"
	if s.title == "New side chat" then
		s.title = if #text > 48 then string.sub(text, 1, 47) .. "…" else text
	end
end

-- What a chat shows before what is sent to it in this window, oldest
-- first: a fork's source (its own history first), then where it forked,
-- then its own turns.
export type Entry = { turn: Turn?, fork: string? }
function M.history(key: string): { Entry }
	local s = M.session(key)
	local out: { Entry } = {}
	if s and s.fork then
		out = M.history(s.fork)
		local source = M.session(s.fork)
		table.insert(out, { fork = if source then source.title else "the conversation" })
	end
	local own = if s and (s.fresh or s.parent) then TRANSCRIPTS[key] or {} else M.turns(key)
	for _, t in own do
		table.insert(out, { turn = t })
	end
	return out
end

-- Where each project's checkout is on this machine.
M.DEVICE = "MacBook Pro"
M.PROJECT_PATHS = {
	comet = "~/zeron/comet",
	zgx = "~/zeron/zgx",
	["grid-website"] = "~/Sites/grid-website",
} :: { [string]: string }

-- A session's subagents, as its transcript's spawn chips name them
-- (session_lanes.rs subagent_rows): what runs, then what settled.
export type Subagent = { id: string, title: string, status: "running" | "done" | "failed", ago: string }
M.SUBAGENTS = {
	["agent:a1"] = {
		{ id = "sa1", title = "verify the release links", status = "running", ago = "2m" },
		{ id = "sa2", title = "collect the merged pull requests", status = "done", ago = "8m" },
		{ id = "sa3", title = "draft the Windows notes", status = "failed", ago = "9m" },
	},
	["agent:a2"] = {
		{ id = "sb1", title = "measure the gap pass", status = "done", ago = "1d" },
	},
} :: { [string]: { Subagent } }

-- How many subagents each session has running (the sidebar's pill).
M.RUNNING_SUBAGENTS = { ["agent:a1"] = 3, ["agent:a7"] = 1 } :: { [string]: number }

-- Subagent `id`, wherever it runs.
function M.subagent(id: string): Subagent?
	for _, list in M.SUBAGENTS do
		for _, s in list do
			if s.id == id then
				return s
			end
		end
	end
	return nil
end

-- The servers a session's agents and terminals started (the ports card).
export type Port = { id: string, name: string, port: number }
M.PORTS = {
	["agent:a1"] = {
		{ id = "web", name = "zeron-web", port = 5173 },
		{ id = "docs", name = "Docs", port = 3000 },
	},
} :: { [string]: { Port } }

-- Each harness's accounts with their plan's usage (account_usage.rs):
-- the windows' share used, and when each resets.
export type UsageWindow = { label: string, used: number, resets: string? }
export type Account = {
	id: string,
	email: string,
	plan: string?,
	active: boolean,
	switchable: boolean?,
	windows: { UsageWindow },
}
M.ACCOUNTS = {
	claude = {
		{
			id = "claude-1",
			email = "gael@zeron.sh",
			plan = "Max",
			active = true,
			switchable = true,
			windows = {
				{ label = "5h", used = 0.42, resets = "resets 3:45 PM" },
				{ label = "Weekly", used = 0.18, resets = "resets Nov 2" },
			},
		},
		{
			id = "claude-2",
			email = "studio@grid.dev",
			plan = "Pro",
			active = false,
			switchable = true,
			windows = {
				{ label = "5h", used = 0.05, resets = "resets 6:10 PM" },
				{ label = "Weekly", used = 0.61, resets = "resets Oct 31" },
			},
		},
	},
	codex = {
		{
			id = "codex-1",
			email = "gael@zeron.sh",
			plan = "Plus",
			active = true,
			switchable = true,
			windows = {
				{ label = "5h", used = 0.86, resets = "resets 4:20 PM" },
				{ label = "Weekly", used = 0.31, resets = "resets Nov 1" },
			},
		},
	},
} :: { [string]: { Account } }
M.PROVIDERS = { claude = "Claude", codex = "Codex", cursor = "Cursor" } :: { [string]: string }

-- Each project's actions (project_actions.rs), and those its zeron.json
-- offers to import; `setup` runs as a worktree is made.
export type ActionIcon = "play" | "test" | "lint" | "configure" | "build" | "debug"
export type Action = { id: string, name: string, command: string, icon: ActionIcon, setup: boolean? }
M.ACTIONS = {
	comet = {
		{ id = "dev", name = "Run dev", command = "cargo run -p zeron", icon = "play" },
		{ id = "test", name = "Test", command = "cargo test --workspace", icon = "test" },
		{ id = "install", name = "Install", command = "pnpm install", icon = "build", setup = true },
	},
	zgx = {
		{ id = "gallery", name = "Gallery", command = "cargo run -p zgx-desktop --example gallery", icon = "play" },
		{ id = "test", name = "Test", command = "cargo test -p zgx --locked", icon = "test" },
	},
} :: { [string]: { Action } }
M.IMPORTS = {
	comet = {
		{ id = "", name = "Lint", command = "cargo clippy --workspace -- -D warnings", icon = "lint" },
	},
	zgx = {
		{ id = "", name = "Clippy", command = "cargo clippy --workspace --all-targets", icon = "lint" },
	},
} :: { [string]: { Action } }

-- The branch's commits, newest first, as `git log --graph` lays them
-- out (kit/history).
M.COMMITS = {
	{
		sha = "bd62d21a",
		subject = "styleguide: ⌘K jumps to a page through the kit's palette",
		author = "Gaël Cado",
		date = "Oct 28, 2026",
		lane = 0,
		parents = { 0 },
		refs = { "main", "origin/main" },
		head = true,
	},
	{
		sha = "3b87140c",
		subject = "styleguide: the Zeron app's todo tray, usage chip and update strip",
		author = "Gaël Cado",
		date = "Oct 28, 2026",
		lane = 0,
		parents = { 0, 1 },
	},
	{
		sha = "efad969d",
		subject = "styleguide: files tree, pull requests, comments, attachments",
		author = "Gaël Cado",
		date = "Oct 27, 2026",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "a1c2e3f4",
		subject = "glass: the hover layer under the active one",
		author = "Wing",
		date = "Oct 27, 2026",
		lane = 1,
		parents = { 1 },
		refs = { "wing/glass" },
	},
	{
		sha = "9c245b6e",
		subject = "styleguide: parity for dictation, context usage and the trays",
		author = "Gaël Cado",
		date = "Oct 26, 2026",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "7f8e9d0c",
		subject = "glass: press gives to 0.985",
		author = "Wing",
		date = "Oct 25, 2026",
		lane = 1,
		parents = { 1 },
	},
	{
		sha = "6e5d4c3b",
		subject = "glass: the rim at one device pixel",
		author = "Wing",
		date = "Oct 25, 2026",
		lane = 1,
		parents = { 1 },
	},
	{
		sha = "c0ffee42",
		subject = "glass: a layer of its own for the hover",
		author = "Wing",
		date = "Oct 24, 2026",
		lane = 1,
		parents = { 0 },
	},
	{
		sha = "2537d86b",
		subject = "styleguide: motion tokens for the morph, roll, tab slide and glide",
		author = "Gaël Cado",
		date = "Oct 24, 2026",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "51f122b0",
		subject = "styleguide: the Zeron app's transcript from the kit",
		author = "Gaël Cado",
		date = "Oct 23, 2026",
		lane = 0,
		parents = {},
	},
} :: { history.Commit }

-- The commit `sha` names (its start will do).
function M.commit(sha: string): history.Commit?
	for _, c in M.COMMITS do
		if string.sub(c.sha, 1, #sha) == sha then
			return c
		end
	end
	return nil
end

-- Why a session's file updates stopped, if they did: the failed run on the
-- Mac mini lost its connection.
function M.watch_error(session: string): string?
	return if session == "agent:a8" then "File updates stopped: the connection to Mac mini was lost" else nil
end

-- How the branch stands against its base (GitHistoryComparison).
M.COMPARISON = { base = "origin/main", ahead = 3, behind = 1 }

-- What the `n`th fetch says went wrong, if anything: the first finds the
-- network down.
function M.fetch(n: number): string?
	return if n == 1 then "Could not resolve host: github.com" else nil
end

M.SESSIONS = SESSIONS
M.AGENTS = AGENTS
M.THREADS = THREADS
M.TODOS = TODOS
-- Where a new session can run, and the refs of its project: the branches
-- (the current one, those checked out in a worktree), then the tags,
-- more than the picker shows at once.
M.DEVICES = { "MacBook Pro", "Mac Studio", "Cloud" }
export type Ref = { name: string, current: boolean?, worktree: boolean?, tag: boolean? }
M.REFS = (function(): { Ref }
	local out: { Ref } = {
		{ name = "main", current = true },
		{ name = "layout-root", worktree = true },
		{ name = "release/0.2.117" },
		{ name = "zeron/composer-markdown", worktree = true },
		{ name = "zeron/queue-edit" },
	}
	for minor = 1, 3 do
		for patch = 0, 109 do
			table.insert(out, { name = `v0.{minor}.{patch}`, tag = true })
		end
	end
	return out
end)()
-- A longer plan (the CI session's): the tray folds it to three around
-- the current item, "2 earlier" and "3 later" at its ends.
M.LONG_TODOS = {
	{ id = "c1", text = "Read the failing Linux job", state = "done" },
	{ id = "c2", text = "Pin the Ubuntu runner", state = "done" },
	{ id = "c3", text = "Cache the zig toolchain", state = "done" },
	{ id = "c4", text = "Run the native smokes under Xvfb", state = "active" },
	{ id = "c5", text = "Gate zgx-script on luau-lsp", state = "pending" },
	{ id = "c6", text = "Split the integration tests by area", state = "pending" },
	{ id = "c7", text = "Upload the snapshots as artifacts", state = "pending" },
	{ id = "c8", text = "Write the CI notes in validation.md", state = "pending" },
} :: { tray.Todo }
function M.todos(key: string?): { tray.Todo }
	return if key == "agent:a7" then M.LONG_TODOS else TODOS
end
-- What a session waiting on input asks (UserInputQuestion): the layout
-- session's three questions, a single choice, a multiple one and one to
-- type.
M.QUESTIONS = {
	["agent:a2"] = {
		{
			id = "root",
			header = "Layout root",
			question = "Which node should own the root's insets?",
			options = { "The window", "The root view", "Each pane" },
		},
		{
			id = "suites",
			header = "Tests",
			question = "Which suites should run before I push?",
			options = { "Layout", "Scene", "Scripting", "Native smokes" },
			multi = true,
		},
		{
			id = "note",
			header = "Release note",
			question = "How should the release note describe it?",
			options = { "One line", "A paragraph with the numbers" },
		},
	},
} :: { [string]: { any } }
M.MODELS = MODELS
M.HUNK = HUNK

-- The checkout's diffs, as `git diff` gives them: the working tree, the
-- branch against a base, the latest turn.
local WORKING = [[
diff --git a/crates/zgx/src/compose.rs b/crates/zgx/src/compose.rs
index 3f2a1c4..9b7e0d2 100644
--- a/crates/zgx/src/compose.rs
+++ b/crates/zgx/src/compose.rs
@@ -404,7 +404,9 @@ fn place(&mut self, node: NodeId)
     let parent = self.parent(node);
-    let centred = self_align == Some(Align::Center);
+    let centred = parent.items == Align::Center && self_align.is_none();
+    // A stretched child is never centred: it fills the cross axis.
+    let stretched = self_align == Some(Align::Stretch);
     if centred {
         offset = (room - size) / 2.;
     }
@@ -431,6 +433,7 @@ fn place(&mut self, node: NodeId)
     let gap = self.gap(parent);
     for child in self.children(node) {
         let at = cursor + margin(child);
+        debug_assert!(at.is_finite());
         self.set_origin(child, at);
         cursor = at + size(child) + gap;
     }
diff --git a/crates/zgx-script/examples/styleguide/shell/canvas.luau b/crates/zgx-script/examples/styleguide/shell/canvas.luau
index 7a1b2c3..4d5e6f7 100644
--- a/crates/zgx-script/examples/styleguide/shell/canvas.luau
+++ b/crates/zgx-script/examples/styleguide/shell/canvas.luau
@@ -58,10 +58,10 @@ local function page_column(id: string): Node
 		return ui.column {
-			w = function()
-				return math.min(880, canvas_w:get())
-			end,
-			ml = function()
-				return math.max(0, (canvas_w:get() - 880) / 2)
-			end,
+			w_full = true,
+			max_w = 880,
+			self = "center",
+			px = "$zeron.space.32",
 			pt = "$zeron.space.24",
 			pb = "$zeron.space.64",
diff --git a/docs/layout.md b/docs/layout.md
new file mode 100644
index 0000000..1c2d3e4
--- /dev/null
+++ b/docs/layout.md
@@ -0,0 +1,4 @@
+# Layout
+
+A column centres its children only when they do not stretch.
+A stretched child fills the cross axis.
diff --git a/assets/old-logo.png b/assets/old-logo.png
deleted file mode 100644
index 5a6b7c8..0000000
Binary files a/assets/old-logo.png and /dev/null differ
]]

local TURN = [[
diff --git a/docs/layout.md b/docs/layout.md
new file mode 100644
index 0000000..1c2d3e4
--- /dev/null
+++ b/docs/layout.md
@@ -0,0 +1,4 @@
+# Layout
+
+A column centres its children only when they do not stretch.
+A stretched child fills the cross axis.
]]

local RENAME = [[
diff --git a/scripts/linux_smokes.py b/scripts/linux_smokes.py
old mode 100644
new mode 100755
diff --git a/crates/zgx/src/layout_old.rs b/crates/zgx/src/layout.rs
similarity index 92%
rename from crates/zgx/src/layout_old.rs
rename to crates/zgx/src/layout.rs
index 1111111..2222222 100644
--- a/crates/zgx/src/layout_old.rs
+++ b/crates/zgx/src/layout.rs
@@ -12,3 +12,3 @@ pub enum Align {
     Start,
-    Centre,
+    Center,
     End,
]]

-- Each commit's own diff (`git show`), by SHA; the merge's is empty.
local COMMIT_PATCHES: { [string]: string } = {
	bd62d21a = [[
diff --git a/crates/zgx-script/examples/styleguide/app.luau b/crates/zgx-script/examples/styleguide/app.luau
index 51c2a10..77d0e4b 100644
--- a/crates/zgx-script/examples/styleguide/app.luau
+++ b/crates/zgx-script/examples/styleguide/app.luau
@@ -88,6 +88,9 @@ local function keys(e: KeyEvent): boolean
 	if e.cmd and e.key == "k" then
-		palette:set(true)
+		kit.command_palette.open {
+			sections = pages.sections(),
+		}
 		return true
 	end
]],
	["3b87140c"] = "",
	a1c2e3f4 = [[
diff --git a/crates/zgx-script/examples/styleguide/kit/glass.luau b/crates/zgx-script/examples/styleguide/kit/glass.luau
index 0a1b2c3..4d5e6f7 100644
--- a/crates/zgx-script/examples/styleguide/kit/glass.luau
+++ b/crates/zgx-script/examples/styleguide/kit/glass.luau
@@ -40,4 +40,6 @@ function M.list(props: ListProps): Node
 	return ui.column {
+		-- The hover glass under the active one.
+		ui.div { absolute = true, bg = T.glass_hover },
 		props.children,
 	}
]],
	["7f8e9d0c"] = [[
diff --git a/crates/zgx-script/examples/styleguide/kit/glass.luau b/crates/zgx-script/examples/styleguide/kit/glass.luau
index 9a8b7c6..0a1b2c3 100644
--- a/crates/zgx-script/examples/styleguide/kit/glass.luau
+++ b/crates/zgx-script/examples/styleguide/kit/glass.luau
@@ -12,3 +12,3 @@ local M = {}
-M.PRESS = 0.98
+M.PRESS = 0.985
 M.SPRING = { stiffness = 520, damping = 34 }
]],
}

-- The working tree's diff: what discarding it, or a turn editing a file,
-- leaves.
M.working = ui.state("z_working_patch", WORKING)

-- The patch for a scope; the branch's against `main` (another base, the
-- working tree's alone); a commit's by its SHA (`base`).
function M.patch(scope: string, base: string): string?
	if scope == "turn" then
		return TURN
	elseif scope == "commit" then
		return COMMIT_PATCHES[base] or TURN .. RENAME
	end
	local working = M.working:get()
	if scope == "branch" and base == "main" then
		return working .. RENAME
	end
	return working
end
-- Whether the engine cut that patch short: against an old release, the
-- branch's diff is too big to send whole.
function M.partial(scope: string, base: string): boolean
	return scope == "branch" and base == "release/0.1"
end
-- The branch checked out, and the bases it can be compared against (the
-- default branch first).
M.BRANCH = "gael/zeron-parity"
M.BRANCHES = {
	"main",
	"release/0.2",
	"release/0.1",
	"wing/layout",
	"wing/glass",
	"fix/scroll-ease",
	"feat/file-icons",
	"origin/main",
	"origin/release/0.2",
	"origin/wing/layout",
}
M.STORIES = STORIES
M.README = README
M.REPLY = REPLY
M.FILES = FILES
M.PRS = PRS
M.MORE_PRS = MORE_PRS

-- The host's `sample_at_rest`: every run settled (sessions and side chats
-- done, turns finished, subagents done), nothing animating, as a window
-- at rest is (the bench's idle).
if ui.shared("sample_at_rest", false):peek() == true then
	for _, list in { AGENTS, SESSIONS, SIDE_CHATS } :: { { { status: string } } } do
		for _, s in list do
			if s.status == "working" then
				s.status = "done"
			end
		end
	end
	for _, turns in TRANSCRIPTS do
		for _, t in turns do
			if t.working then
				t.worked, t.working = t.working, nil
			end
			for _, tool in t.tools or {} do
				if tool.status == "running" then
					tool.status = "done"
				end
			end
		end
	end
	for _, list in M.SUBAGENTS do
		for _, s in list do
			if s.status == "running" then
				s.status = "done"
			end
		end
	end
	table.clear(M.RUNNING_SUBAGENTS)
end

return M
