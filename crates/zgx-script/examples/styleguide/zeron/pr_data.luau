-- What the engine would send for each pull request the board lists
-- (ChangeRequestDetail, and its patch): the branch and revisions, the
-- review decision and mergeability, the checks, the description, the
-- activity (conversation comments, reviews, inline review threads), and
-- whether this device has a checkout of the repository. Images in the
-- descriptions resolve to the styleguide's own (`MEDIA`), as the engine's
-- image loader would fetch them.
local M = {}

export type Check = { name: string, status: string, link: string? }
-- An inline review comment's thread (ChangeRequestReviewThread).
export type Thread = {
	path: string,
	line: number?,
	resolved: boolean,
	outdated: boolean?,
	reply: boolean?,
	url: string?,
}
export type Message = {
	id: string,
	author: string,
	-- A review's state (APPROVED, CHANGES_REQUESTED, COMMENTED).
	state: string?,
	-- When, as the activity says it, and its order in time.
	at: string,
	order: number,
	body: string,
	thread: Thread?,
}
export type Ci = "passed" | "failed" | "pending" | "skipped" | "none" | "unknown"
export type Detail = {
	repository: string,
	url: string,
	head: string,
	base: string,
	oid: string,
	state: "OPEN" | "MERGED" | "CLOSED",
	draft: boolean,
	-- APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, or "" (none reported).
	review: string,
	-- MERGEABLE, CONFLICTING, UNKNOWN.
	mergeable: string,
	authored: boolean?,
	requested: boolean?,
	ci: Ci,
	-- Checks the rollup counts (more than `checks` lists when it is cut).
	ci_total: number,
	checks: { Check },
	body: string,
	patch: string,
	activity: { Message },
	-- Inline review threads came back (false: GitHub did not return them).
	threads: boolean,
	-- This device has a checkout of the repository.
	checkout: boolean,
	-- The first diff read fails (a timeout), the retry succeeds.
	diff_fails: boolean?,
	-- The first read of the pull request itself fails (a timeout).
	read_fails: boolean?,
}

-- The signed-in GitHub account.
M.VIEWER = "gaelcado"

-- Description images, by address: the file the loader would decode, its
-- size, or that it fails.
-- `full_fails`: shown in the description, its full size fails to load.
export type Media = { src: string, w: number, h: number, fails: boolean?, full_fails: boolean? }
M.MEDIA = {
	["https://github.com/user-attachments/assets/7d1c9e52-before"] = { src = "images/shadow.jpg", w = 720, h = 480 },
	["https://github.com/user-attachments/assets/4be0a113-after"] = {
		src = "images/screenshot-tall.jpg",
		w = 480,
		h = 720,
		full_fails = true,
	},
	["https://i.imgur.com/fade-curve.png"] = { src = "images/shadow.jpg", w = 720, h = 480 },
	["https://github.com/user-attachments/assets/2f5d-stop-plate"] = { src = "images/shadow.jpg", w = 720, h = 480 },
	["https://github.com/user-attachments/assets/91aa-missing"] = { src = "", w = 0, h = 0, fails = true },
	["https://github.com/zeron/zgx/blob/main/docs/layout-root.png"] = {
		src = "images/screenshot-tall.jpg",
		w = 480,
		h = 720,
	},
} :: { [string]: Media }

local P412 = [[
diff --git a/crates/ui/src/edge_fade.rs b/crates/ui/src/edge_fade.rs
index 1a2b3c4..5d6e7f8 100644
--- a/crates/ui/src/edge_fade.rs
+++ b/crates/ui/src/edge_fade.rs
@@ -12,9 +12,14 @@ pub fn edge_faded(band: f32, top: bool, bottom: bool, content: impl IntoElement)
     let mut mask = Mask::new();
-    if top {
-        mask.fade_top(band);
-    }
+    // Only the edge that has content past it fades.
+    if top && overflow.above {
+        mask.fade_top(band);
+    }
+    if bottom && overflow.below {
+        mask.fade_bottom(band);
+    }
     mask.apply(content)
 }

@@ -40,6 +45,9 @@ impl EdgeFade {
     fn overflow(&self, scroll: &ScrollHandle) -> Overflow {
         let offset = scroll.offset().y;
+        let max = scroll.max_offset().height;
+        // Half a point of slack: a list at rest never flickers its fade.
+        let below = offset.abs() + 0.5 < max;
         Overflow { above: offset < -0.5, below }
     }
 }
diff --git a/crates/ui/src/transcript/scroll.rs b/crates/ui/src/transcript/scroll.rs
index 7f8e9d0..a1b2c3d 100644
--- a/crates/ui/src/transcript/scroll.rs
+++ b/crates/ui/src/transcript/scroll.rs
@@ -88,7 +88,8 @@ fn render_transcript(&mut self, cx: &mut Context<Self>) -> AnyElement {
-    edge_faded(24.0, true, false, list)
+    // The bottom edge fades too, under the composer.
+    edge_faded(24.0, true, true, list)
         .fade_overflow_y(&self.scroll)
         .into_any_element()
 }
diff --git a/crates/ui/src/transcript/fade_tests.rs b/crates/ui/src/transcript/fade_tests.rs
new file mode 100644
index 0000000..3e4f5a6
--- /dev/null
+++ b/crates/ui/src/transcript/fade_tests.rs
@@ -0,0 +1,12 @@
+use super::*;
+
+#[gpui::test]
+fn the_bottom_edge_fades_only_with_content_below(cx: &mut gpui::TestAppContext) {
+    let view = transcript_with_turns(cx, 40);
+    assert!(view.fades_bottom(cx), "a long transcript fades at its foot");
+    view.scroll_to_end(cx);
+    assert!(!view.fades_bottom(cx), "nothing below its end");
+}
+
+// A short transcript has nothing past either edge.
+fn transcript_with_turns(cx: &mut gpui::TestAppContext, turns: usize) -> TestView { todo!() }
diff --git a/crates/ui/src/transcript/old_fade.rs b/crates/ui/src/transcript/fade.rs
similarity index 88%
rename from crates/ui/src/transcript/old_fade.rs
rename to crates/ui/src/transcript/fade.rs
index 2222222..3333333 100644
--- a/crates/ui/src/transcript/old_fade.rs
+++ b/crates/ui/src/transcript/fade.rs
@@ -3,3 +3,3 @@ use gpui::Pixels;
 pub const BAND: f32 = 24.0;
-pub const SLACK: f32 = 0.25;
+pub const SLACK: f32 = 0.5;
 pub const MIN_CONTENT: f32 = 48.0;
diff --git a/docs/transcript.md b/docs/transcript.md
index 4d5e6f7..8a9b0c1 100644
--- a/docs/transcript.md
+++ b/docs/transcript.md
@@ -21,4 +21,5 @@ ## Scrolling
 The transcript fades over its top 24 points while there is history above.
+Its bottom edge fades the same way, under the composer, while turns run past it.
 Jumping to the end restores the follow mode.

diff --git a/assets/fade-before.png b/assets/fade-before.png
deleted file mode 100644
index 5a6b7c8..0000000
Binary files a/assets/fade-before.png and /dev/null differ
]]

local P409 = [[
diff --git a/crates/ui/src/dictation/stop_plate.rs b/crates/ui/src/dictation/stop_plate.rs
index 0a1b2c3..4d5e6f7 100644
--- a/crates/ui/src/dictation/stop_plate.rs
+++ b/crates/ui/src/dictation/stop_plate.rs
@@ -30,12 +30,18 @@ pub fn stop_plate(theme: &Theme, recording: bool) -> impl IntoElement {
     div()
         .size(px(PLATE))
         .rounded_full()
-        .bg(theme.solid)
+        // The accent's glass: its tint over the composer's blur.
+        .bg(theme.accent.opacity(0.18))
+        .border_1()
+        .border_color(theme.accent.opacity(0.32))
         .flex()
         .items_center()
         .justify_center()
-        .child(square(theme.on_solid))
+        .child(square(theme.accent))
+        .when(recording, |el| el.shadow(accent_glow(theme)))
 }
+
+fn accent_glow(theme: &Theme) -> Vec<BoxShadow> {
+    vec![BoxShadow { color: theme.accent.opacity(0.24), blur: px(12.0), ..Default::default() }]
+}
diff --git a/crates/ui/src/dictation/track.rs b/crates/ui/src/dictation/track.rs
index 1b2c3d4..5e6f7a8 100644
--- a/crates/ui/src/dictation/track.rs
+++ b/crates/ui/src/dictation/track.rs
@@ -55,7 +55,7 @@ impl Track {
     fn bar_color(&self, theme: &Theme, level: f32) -> Hsla {
-        theme.text.opacity(0.4 + 0.6 * level)
+        theme.accent.opacity(0.4 + 0.6 * level)
     }
 }
diff --git a/crates/ui/tests/dictation.rs b/crates/ui/tests/dictation.rs
index 9c8d7e6..5f4a3b2 100644
--- a/crates/ui/tests/dictation.rs
+++ b/crates/ui/tests/dictation.rs
@@ -102,6 +102,13 @@ fn the_stop_plate_ends_dictation(cx: &mut TestAppContext) {
     assert!(composer.dictation_phase(cx).is_idle());
 }

+#[gpui::test]
+fn the_stop_plate_glows_while_recording(cx: &mut TestAppContext) {
+    let composer = dictating(cx);
+    assert!(composer.stop_plate_shadow(cx).is_some());
+    composer.stop(cx);
+    assert!(composer.stop_plate_shadow(cx).is_none());
+}
]]

local P401 = [[
diff --git a/crates/ui/src/queue/tray.rs b/crates/ui/src/queue/tray.rs
index 3c4d5e6..7f8a9b0 100644
--- a/crates/ui/src/queue/tray.rs
+++ b/crates/ui/src/queue/tray.rs
@@ -71,6 +71,10 @@ impl QueueTray {
     fn render_row(&self, index: usize, cx: &mut Context<Self>) -> AnyElement {
         let item = &self.items[index];
         row(item)
+            // WIP: the grip starts a drag; dropping reorders.
+            .on_drag(index, |index, _, _, cx| cx.new(|_| DragChip(*index)))
+            .on_drop(cx.listener(move |tray, from: &usize, _, cx| tray.reorder(*from, index, cx)))
+            .drag_over::<usize>(|style, _, _, _| style.bg(gpui::transparent_black()))
             .into_any_element()
     }
 }
]]

local P398 = [[
diff --git a/crates/zgx/src/layout/root.rs b/crates/zgx/src/layout/root.rs
index 4a5b6c7..8d9e0f1 100644
--- a/crates/zgx/src/layout/root.rs
+++ b/crates/zgx/src/layout/root.rs
@@ -1,18 +1,9 @@
-use crate::layout::{Constraints, LegacyRoot, NodeId};
+use crate::layout::{Constraints, NodeId, Root};

-pub struct LayoutRoot {
-    legacy: LegacyRoot,
-    dirty: Vec<NodeId>,
-}
-
-impl LayoutRoot {
-    pub fn new() -> Self {
-        Self { legacy: LegacyRoot::default(), dirty: Vec::new() }
-    }
-
-    pub fn layout(&mut self, constraints: Constraints) {
-        self.legacy.relayout(&self.dirty, constraints);
-        self.dirty.clear();
-    }
-}
+/// The new root: dirty nodes are its own, laid out in tree order.
+pub fn layout(root: &mut Root, constraints: Constraints) {
+    root.relayout(constraints);
+}
diff --git a/crates/zgx/src/layout/legacy.rs b/crates/zgx/src/layout/legacy.rs
deleted file mode 100644
index 6e7f8a9..0000000
--- a/crates/zgx/src/layout/legacy.rs
+++ /dev/null
@@ -1,6 +0,0 @@
-//! The old root, kept while callers moved over.
-pub struct LegacyRoot;
-impl LegacyRoot {
-    pub fn relayout(&mut self, _: &[super::NodeId], _: super::Constraints) {}
-}
-impl Default for LegacyRoot { fn default() -> Self { Self } }
]]

M.DETAILS = {
	p1 = {
		repository = "zeron/comet",
		url = "https://github.com/zeron/comet/pull/412",
		head = "gael/transcript-bottom-fade",
		base = "main",
		oid = "9c245b6e1f0a4d2c8b7e3a5f6d9c0b1a2e4f6a8c",
		state = "OPEN",
		draft = false,
		review = "APPROVED",
		mergeable = "MERGEABLE",
		authored = true,
		requested = false,
		ci = "passed",
		ci_total = 5,
		checks = {
			{
				name = "build (macos-latest)",
				status = "SUCCESS",
				link = "https://github.com/zeron/comet/actions/runs/1101",
			},
			{
				name = "build (ubuntu-latest)",
				status = "SUCCESS",
				link = "https://github.com/zeron/comet/actions/runs/1102",
			},
			{ name = "clippy", status = "SUCCESS", link = "https://github.com/zeron/comet/actions/runs/1103" },
			{ name = "fmt", status = "SUCCESS" },
			{ name = "windows smoke", status = "SKIPPED" },
		},
		body = table.concat({
			"The transcript fades over its bottom 24 points while turns run past it, as it already does at its top. A list at rest at its end shows no fade.",
			"",
			"| Before | After |",
			"| --- | --- |",
			"| ![The old edge](https://github.com/user-attachments/assets/7d1c9e52-before) | ![The new edge](https://github.com/user-attachments/assets/4be0a113-after) |",
			"",
			"The fade's curve, from the design file:",
			"",
			"![Fade curve](https://i.imgur.com/fade-curve.png)",
			"",
			"```rust",
			"edge_faded(24.0, true, true, list).fade_overflow_y(&self.scroll)",
			"```",
			"",
			"- [x] Fade only the edge with content past it",
			"- [x] Half a point of slack at rest",
			"- [ ] Check the opaque theme",
		}, "\n"),
		patch = P412,
		activity = {
			{
				id = "c1",
				author = "wing",
				at = "3 hours ago",
				order = 1,
				body = "Nice. Does the slack hold on a fractional scale factor? `0.5` reads like a magic number.",
			},
			{
				id = "c2",
				author = "gaelcado",
				at = "2 hours ago",
				order = 2,
				body = "It does: offsets land on half points at 1.5×. I named it `SLACK` in `fade.rs`.",
			},
			{
				id = "t1",
				author = "wing",
				at = "2 hours ago",
				order = 3,
				body = "Could this read `max_offset()` once per frame instead of per call?",
				thread = {
					path = "crates/ui/src/edge_fade.rs",
					line = 47,
					resolved = true,
					url = "https://github.com/zeron/comet/pull/412#discussion_r101",
				},
			},
			{
				id = "t2",
				author = "gaelcado",
				at = "1 hour ago",
				order = 4,
				body = "Done in 5d6e7f8.",
				thread = {
					path = "crates/ui/src/edge_fade.rs",
					line = 47,
					resolved = true,
					reply = true,
					url = "https://github.com/zeron/comet/pull/412#discussion_r102",
				},
			},
			{
				id = "r1",
				author = "wing",
				state = "APPROVED",
				at = "40 minutes ago",
				order = 5,
				body = "Looks good. Ship it.",
			},
		},
		threads = true,
		checkout = true,
	},
	p2 = {
		repository = "zeron/comet",
		url = "https://github.com/zeron/comet/pull/409",
		head = "wing/dictation-accent-plate",
		base = "main",
		oid = "51f122b0c3d4e5f60718293a4b5c6d7e8f901234",
		state = "OPEN",
		draft = false,
		review = "CHANGES_REQUESTED",
		mergeable = "MERGEABLE",
		authored = false,
		requested = true,
		ci = "failed",
		ci_total = 4,
		checks = {
			{
				name = "test (macos-latest)",
				status = "FAILURE",
				link = "https://github.com/zeron/comet/actions/runs/2201/job/1",
			},
			{
				name = "test (ubuntu-latest)",
				status = "SUCCESS",
				link = "https://github.com/zeron/comet/actions/runs/2201/job/2",
			},
			{ name = "clippy", status = "FAILURE", link = "https://ci.example.com/zeron/comet/2201" },
			{ name = "fmt", status = "SUCCESS" },
		},
		body = table.concat({
			"Dictation's stop plate takes the accent's glass instead of the solid, and the level bars follow it.",
			"",
			"![The stop plate while recording](https://github.com/user-attachments/assets/2f5d-stop-plate)",
			"",
			"The light theme's capture didn't upload:",
			"",
			"![Light theme](https://github.com/user-attachments/assets/91aa-missing)",
		}, "\n"),
		patch = P409,
		activity = {
			{
				id = "r1",
				author = "gaelcado",
				state = "CHANGES_REQUESTED",
				at = "yesterday",
				order = 1,
				body = "The plate loses its contrast on the light theme. Can the border come from the accent's glyph tone there?",
			},
			{
				id = "t1",
				author = "gaelcado",
				at = "yesterday",
				order = 2,
				body = "This glow paints outside the composer's clip on the docked composer.",
				thread = {
					path = "crates/ui/src/dictation/stop_plate.rs",
					line = 41,
					resolved = false,
					url = "https://github.com/zeron/comet/pull/409#discussion_r201",
				},
			},
			{
				id = "t2",
				author = "gaelcado",
				at = "yesterday",
				order = 3,
				body = "The level bars were the text colour on purpose: the accent fights the waveform.",
				thread = {
					path = "crates/ui/src/dictation/track.rs",
					line = 57,
					resolved = false,
					outdated = true,
					url = "https://github.com/zeron/comet/pull/409#discussion_r202",
				},
			},
			{
				id = "c1",
				author = "wing",
				at = "5 hours ago",
				order = 4,
				body = "I'll take the glyph tone for the border. @gaelcado the glow can go, it was a leftover.",
			},
		},
		threads = true,
		checkout = true,
	},
	p3 = {
		repository = "zeron/comet",
		url = "https://github.com/zeron/comet/pull/401",
		head = "gael/queue-drag",
		base = "main",
		oid = "3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f",
		state = "OPEN",
		draft = true,
		review = "",
		mergeable = "MERGEABLE",
		authored = true,
		requested = false,
		ci = "none",
		ci_total = 0,
		checks = {},
		body = "",
		patch = P401,
		activity = {},
		threads = true,
		checkout = true,
	},
	p4 = {
		repository = "zeron/zgx",
		url = "https://github.com/zeron/zgx/pull/398",
		head = "wing/layout-root",
		base = "main",
		oid = "2cec8330a1b2c3d4e5f60718293a4b5c6d7e8f90",
		state = "OPEN",
		draft = false,
		review = "REVIEW_REQUIRED",
		mergeable = "CONFLICTING",
		authored = false,
		requested = true,
		ci = "pending",
		ci_total = 5,
		checks = {
			{ name = "build", status = "IN_PROGRESS", link = "https://github.com/zeron/zgx/actions/runs/3301" },
			{ name = "test", status = "QUEUED" },
		},
		body = table.concat({
			"Moves every caller onto the new layout root and deletes the legacy one.",
			"",
			'<img width="480" alt="The new root" src="https://github.com/zeron/zgx/blob/main/docs/layout-root.png">',
			"",
			"<details><summary>Why now</summary>",
			"",
			"The legacy root relaid out dirty nodes out of tree order, so a parent could settle after its child.",
			"",
			"</details>",
		}, "\n"),
		patch = P398,
		activity = {
			{
				id = "c1",
				author = "wing",
				at = "4 days ago",
				order = 1,
				body = "Rebased twice already; `main` moved the grid code under me again.",
			},
			{
				id = "c2",
				author = "gaelcado",
				at = "3 days ago",
				order = 2,
				body = "I'll look once the conflicts are resolved.",
			},
		},
		threads = false,
		checkout = false,
		diff_fails = true,
	},
} :: { [string]: Detail }

-- The board's second page: a review waiting on someone else, and an
-- approved one whose first read times out.
local function like_p1(fields: { [string]: any }): Detail
	local d = table.clone(M.DETAILS.p1) :: any
	for k, v in fields do
		d[k] = v
	end
	return d
end
M.DETAILS.p5 = like_p1 {
	url = "https://github.com/zeron/comet/pull/395",
	head = "wing/wheel-whole-pixels",
	oid = "77d0e4b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7",
	review = "REVIEW_REQUIRED",
	authored = false,
	body = "Wheel deltas round to whole pixels once the ease settles, so text never rests on a half pixel.",
	activity = {},
}
M.DETAILS.p6 = like_p1 {
	url = "https://github.com/zeron/comet/pull/391",
	head = "gael/metal-floor-docs",
	oid = "adeeb32f1e2d3c4b5a69788776655443322110ff",
	body = "The Metal driver's floor comes with any frame drawn, popups or not.",
	activity = {},
	read_fails = true,
}

-- What the board can list, by repository: its pull requests as GitHub
-- sends them (most recently updated first), a page at a time.
M.PAGE = 4
M.BOARD = {
	["zeron/comet"] = { "p1", "p2", "p3", "p5", "p6" },
	["zeron/zgx"] = { "p4" },
	["zeron/website"] = {},
} :: { [string]: { string } }
-- The projects whose checkouts name a repository, and the desktop devices
-- the board can read from (Cloud is asleep).
M.PROJECTS = {
	{ name = "comet", repository = "zeron/comet" },
	{ name = "zgx", repository = "zeron/zgx" },
}
M.DEVICES = { "MacBook Pro", "Mac Studio", "Cloud" }
-- A repository GitHub refuses this device's sign-in for, and one whose
-- refresh times out (the board keeps what it showed).
M.FAILS = { ["zeron/private"] = "auth" } :: { [string]: string }
M.FLAKY = { ["zeron/zgx"] = true } :: { [string]: boolean }

return M
