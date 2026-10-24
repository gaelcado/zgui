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
		where = "zgui",
		status = "blocked",
		waits = "question",
		icon = "openai-mark",
		ago = "6m",
	},
	{
		id = "a3",
		name = "Fix flaky test",
		where = "zgui",
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

local FILES: { file_tree.Entry } = {
	{ id = "crates", name = "crates", level = 0, folder = true, open = true },
	{ id = "zgui", name = "zgui", level = 1, folder = true, open = true, icon = "folder-with-files" },
	{ id = "f1", name = "compose.rs", level = 2, icon = "file-code", git = "modified" },
	{ id = "f2", name = "compose_scrollbar.rs", level = 2, icon = "file-code" },
	{ id = "styleguide", name = "styleguide", level = 1, folder = true },
	{ id = "f3", name = "Cargo.toml", level = 0, icon = "file-data" },
	{ id = "f4", name = "README.md", level = 0, icon = "file-markdown" },
}

local PRS: { pr.Row } = {
	{
		id = "p1",
		title = "Scroll fade on the transcript's bottom edge",
		number = 412,
		author = "Gaël Cado",
		status = "open",
		checks = "passed",
		sha = "9c245b6",
		date = "2h ago",
		added = 128,
		removed = 41,
		labels = { "ui" },
	},
	{
		id = "p2",
		title = "Dictation: the stop plate on the accent glass",
		number = 409,
		author = "Wing",
		status = "changes",
		checks = "failed",
		sha = "51f122b",
		date = "yesterday",
		added = 302,
		removed = 17,
		starred = true,
	},
	{
		id = "p3",
		title = "WIP: queue tray drag",
		number = 401,
		author = "Gaël Cado",
		status = "draft",
		date = "3d ago",
		added = 44,
		removed = 9,
	},
	{
		id = "p4",
		title = "Rebase onto the new layout root",
		number = 398,
		author = "Wing",
		status = "conflicting",
		checks = "pending",
		sha = "2cec833",
		date = "4d ago",
		added = 12,
		removed = 230,
		labels = { "layout", "breaking" },
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
	-- Started in this window: no turns of its own yet.
	fresh: boolean?,
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
	},
	{
		key = "agent:a2",
		row = "agent_a2",
		title = "Refactor the layout engine",
		harness = "codex",
		status = "input",
		project = "zgui",
		branch = "layout-root",
		pr = { number = 398, state = "open" },
		ago = "6m",
		pinned = true,
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
		title = "zgui prod: Windows platform",
		harness = "claude",
		status = "done",
		project = "zgui",
		branch = "windows/webview2",
		ago = "3m",
		section = "Cross Platform ZGUI",
	},
	{
		key = "agent:a7",
		row = "agent_a7",
		title = "zgui prod: CI + Linux + zgui-script",
		harness = "claude",
		status = "working",
		project = "zgui",
		pr = { number = 96, state = "open" },
		ago = "20m",
		section = "Cross Platform ZGUI",
	},
	{
		key = "agent:a8",
		row = "agent_a8",
		title = "zgui: native Mac multi-window",
		harness = "cursor",
		status = "failed",
		project = "zgui",
		ago = "1h",
		section = "Cross Platform ZGUI",
	},
	{
		key = "agent:a3",
		row = "agent_a3",
		title = "Fix flaky test",
		harness = "claude",
		status = "done",
		project = "zgui",
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
		project = "zgui",
		ago = "3w",
		archived = true,
	},
}
-- How many sessions the Archived shelf holds in all (it pages them in).
M.ARCHIVED_TOTAL = 585
M.PROJECTS = { "comet", "zgui", "grid-website" }
M.HARNESS = {
	claude = { icon = "claude-mark", tint = T.claude },
	codex = { icon = "openai-mark" },
	cursor = { icon = "cursor-mark" },
} :: { [Harness]: { icon: string, tint: Color? } }

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
	images: { { src: string, name: string, w: number, h: number } }?,
}
export type Turn = { user: string, tools: { Tool }?, reply: string, working: string? }
local TEST_OUTPUT = table.concat({
	"running 20 tests",
	"test dpi::caret_after_first_layout ... ok",
	"test dpi::caret_at_two_x ... ok",
	"test dpi::centred_single_line_caret ... FAILED",
	"test dpi::fractional_scale_snaps ... ok",
	"test dpi::live_probe_reads_caret ... ok",
}, "\n") .. string.rep("\ntest dpi::repeat ... ok", 24) .. "\n\ntest result: FAILED. 19 passed; 1 failed\n"
local TRANSCRIPTS: { [string]: { Turn } } = {
	["agent:a1"] = {
		{
			user = "Can you draft the release notes for 0.2.117?",
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
					label = "Ran",
					detail = "git log --oneline v0.2.116..HEAD",
					call = "git log --oneline v0.2.116..HEAD",
					output = "548985a Build: dependencies keep line tables\na00d4fb Build: one skrifa and read-fonts, not two\ne38b0d3 cosmic-text: a word's cache key hashes once a line\n3a8ab50 zgui-script: debug builds give script calls more time\n5212aa5 Layout: a column's automatic minimum is its items' height\n",
				},
			},
			reply = "Here is a first pass, grouped by area, with the breaking change first.\n\n## 0.2.117\n\n**Breaking:** the panel width setting now stores the pane's latest split.\n\n- **Cloud:** repaired Codex installs, and the engine starts on wake.\n- **Pull requests:** the pane follows the shared panel layout (`#914`).\n- **Windows:** web views are WebView2 pages composited with zgui.\n\nTell me whether you want it shorter, or split by platform.",
		},
		{
			user = "Shorter, and lead with Cloud.",
			reply = "- **Cloud:** Codex installs repair themselves; the engine starts on wake.\n- **Pull requests:** the pane splits the room with the board.\n- **Breaking:** the pane's width setting is now its latest split.",
			working = "Checking the links",
		},
	},
	["agent:a2"] = {
		{
			user = "Refactor the layout engine so a column's gap skips hidden children.",
			tools = {
				{
					icon = "document",
					label = "Read",
					detail = "crates/zgui/src/layout.rs",
					file = true,
					call = "crates/zgui/src/layout.rs",
					output = "fn place(&mut self, node: NodeId) {\n    let parent = self.parent(node);\n    let gaps = gap * children.len().saturating_sub(1) as f32;\n    for child in children {\n        self.place(child);\n    }\n}\n",
				},
				{
					icon = "magnifer",
					label = "Searched",
					detail = "gap around hidden",
					call = "gap around hidden in crates/zgui/src",
					output = "crates/zgui/src/layout.rs:412: // the gap around hidden children\ncrates/zgui/src/layout.rs:418: let gaps = gap * children.len()\n",
				},
			},
			reply = "The gap is added between every pair of children, hidden or not. Two ways out:\n\n| Approach | Cost | Risk |\n| --- | --- | --- |\n| Skip hidden children when summing gaps | one pass | none |\n| Collapse hidden children to zero and their gaps | two passes | margins change |\n\nI'd take the first:\n\n```rust\nlet shown = children.iter().filter(|c| !c.hidden);\nlet gaps = gap * shown.count().saturating_sub(1) as f32;\n```\n\n> Before I change it: should `invisible` (which keeps its room) still take a gap?",
		},
	},
	["agent:a3"] = {
		{
			user = "The DPI probe fails on CI about once in ten runs. Find out why.",
			tools = {
				{
					icon = "terminal",
					label = "Ran",
					detail = "cargo test -p zgui --test dpi -- --test-threads=1 (×20)",
					call = "for i in $(seq 20); do cargo test -p zgui --test dpi -- --test-threads=1 || break; done",
					output = TEST_OUTPUT,
				},
				{
					icon = "document",
					label = "Read",
					detail = "target/dpi/caret.jpg",
					file = true,
					call = "target/dpi/caret.jpg",
					images = {
						{ src = "images/shadow.jpg", name = "caret.jpg", w = 720, h = 480 },
						{ src = "images/screenshot-tall.jpg", name = "caret-2x.jpg", w = 480, h = 720 },
					},
				},
				{
					icon = "pen",
					label = "Edited",
					detail = "crates/zgui/src/layout.rs",
					file = true,
					call = "crates/zgui/src/layout.rs",
					hunks = { HUNK },
				},
			},
			reply = "Found it. The probe reads the caret before the editor's first layout, so on a slow runner it sees the old position.\n\n1. Wait for the editor's `layout` event before reading the caret.\n2. Center the expected caret for single-line editors, as main now does.\n3. Run it 50 times: **50 passed**.\n\n![The caret, after the fix](images/shadow.jpg)\n\n- [x] Fix the race\n- [x] Update the expectation\n- [ ] Ask Wing whether the probe should time out sooner",
		},
	},
	["thread:h2"] = {
		{
			user = "Sketch the admin dashboard's first screen.",
			reply = "A first screen with three cards and a table:\n\n- **Revenue** this month, against last\n- **Active teams**, with the trend\n- **Failed jobs** in the last day\n\nUnder them, the newest sign-ups with their plan and their team size.",
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

-- A session started from the new-session canvas, at the top of the list.
local created = 0
function M.add_session(title: string, project: string): Session
	created += 1
	local s: Session = {
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

function M.session(key: string): Session?
	for _, s in SESSIONS do
		if s.key == key then
			return s
		end
	end
	return nil
end

-- The branch's commits, newest first, as `git log --graph` lays them
-- out (kit/history).
M.COMMITS = {
	{
		sha = "bd62d21a",
		subject = "styleguide: ⌘K jumps to a page through the kit's palette",
		author = "Gaël Cado",
		date = "2m ago",
		lane = 0,
		parents = { 0 },
		refs = { "main", "origin/main" },
		head = true,
	},
	{
		sha = "3b87140c",
		subject = "styleguide: the Zeron app's todo tray, usage chip and update strip",
		author = "Gaël Cado",
		date = "1h ago",
		lane = 0,
		parents = { 0, 1 },
	},
	{
		sha = "efad969d",
		subject = "styleguide: files tree, pull requests, comments, attachments",
		author = "Gaël Cado",
		date = "2h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "a1c2e3f4",
		subject = "glass: the hover layer under the active one",
		author = "Wing",
		date = "3h ago",
		lane = 1,
		parents = { 1 },
		refs = { "wing/glass" },
	},
	{
		sha = "9c245b6e",
		subject = "styleguide: parity for dictation, context usage and the trays",
		author = "Gaël Cado",
		date = "3h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "7f8e9d0c",
		subject = "glass: press gives to 0.985",
		author = "Wing",
		date = "5h ago",
		lane = 1,
		parents = { 0 },
	},
	{
		sha = "2537d86b",
		subject = "styleguide: motion tokens for the morph, roll, tab slide and glide",
		author = "Gaël Cado",
		date = "6h ago",
		lane = 0,
		parents = { 0 },
	},
	{
		sha = "51f122b0",
		subject = "styleguide: the Zeron app's transcript from the kit",
		author = "Gaël Cado",
		date = "7h ago",
		lane = 0,
		parents = {},
	},
} :: { history.Commit }

M.SESSIONS = SESSIONS
M.AGENTS = AGENTS
M.THREADS = THREADS
M.TODOS = TODOS
M.MODELS = MODELS
M.HUNK = HUNK

-- The checkout's diffs, as `git diff` gives them: the working tree, the
-- branch against a base, the latest turn.
local WORKING = [[
diff --git a/crates/zgui/src/compose.rs b/crates/zgui/src/compose.rs
index 3f2a1c4..9b7e0d2 100644
--- a/crates/zgui/src/compose.rs
+++ b/crates/zgui/src/compose.rs
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
diff --git a/crates/zgui-script/examples/styleguide/shell/canvas.luau b/crates/zgui-script/examples/styleguide/shell/canvas.luau
index 7a1b2c3..4d5e6f7 100644
--- a/crates/zgui-script/examples/styleguide/shell/canvas.luau
+++ b/crates/zgui-script/examples/styleguide/shell/canvas.luau
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

local BRANCH = WORKING
	.. [[
diff --git a/crates/zgui/src/layout_old.rs b/crates/zgui/src/layout.rs
similarity index 92%
rename from crates/zgui/src/layout_old.rs
rename to crates/zgui/src/layout.rs
index 1111111..2222222 100644
--- a/crates/zgui/src/layout_old.rs
+++ b/crates/zgui/src/layout.rs
@@ -12,3 +12,3 @@ pub enum Align {
     Start,
-    Centre,
+    Center,
     End,
]]

-- The patch for a scope; the branch's against `main` (another base, the
-- working tree's alone).
function M.patch(scope: string, base: string): string?
	if scope == "turn" then
		return TURN
	elseif scope == "branch" then
		return if base == "main" then BRANCH else WORKING
	end
	return WORKING
end
M.BRANCHES = { "main", "release/0.2", "wing/layout" }
M.STORIES = STORIES
M.README = README
M.REPLY = REPLY
M.FILES = FILES
M.PRS = PRS

return M
