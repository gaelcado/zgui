-- Changes: file rows with their counts, the diff folding under them.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local diff = require("@kit/diff")
local wash = require("@kit/wash")

local open_a = ui.state("diff_a", true)
local open_b = ui.state("diff_b", false)
local open_c = ui.state("diff_c", false)

local HUNK: diff.HunkProps = {
	header = "@@ -404,7 +404,9 @@ fn place(&mut self, node: NodeId)",
	lines = {
		{ kind = "ctx", old = 404, new = 404, text = "    let parent = self.parent(node);" },
		{ kind = "del", old = 405, text = "    let centred = self_align == Some(Align::Center);" },
		{
			kind = "add",
			new = 405,
			text = "    // Centre from the parent so a height change cannot move the pressed node.",
		},
		{ kind = "add", new = 406, text = "    let centred = parent.items == Align::Center && self_align.is_none();" },
		{ kind = "ctx", old = 406, new = 407, text = "    if centred {" },
		{ kind = "ctx", old = 407, new = 408, text = "        self.offset(node, (parent.w - size.w) / 2.0);" },
		{ kind = "ctx", old = 408, new = 409, text = "    }" },
	},
}

local function files(): Node
	return specimen.frame {
		w = 760,
		p = 0,
		bg = T.card,
		overflow = "hidden",
		wash.list {
			group = "changes_files",
			color = T.ink2,
			diff.change {
				file = {
					id = "file_a",
					group = "changes_files",
					path = "crates/zgx/src/compose.rs",
					added = 2,
					removed = 1,
					open = open_a,
				},
				hunks = { HUNK },
			},
			diff.change {
				file = {
					id = "file_b",
					group = "changes_files",
					path = "crates/zgx-script/examples/styleguide/shell/canvas.luau",
					added = 4,
					removed = 4,
					open = open_b,
					first = false,
				},
				hunks = { HUNK },
			},
			diff.change {
				file = {
					id = "file_c",
					group = "changes_files",
					path = "assets/icons/zeron-logo.png",
					binary = true,
					open = open_c,
					first = false,
				},
				hunks = {},
			},
		},
	}
end

return function(): Node
	local p = state.page_by("changes")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "Files",
			note = "row 38 · chevron 13 · path mono 12 · +N / −N mono 11 · fold 180 ms ease-out",
			files(),
		},
		specimen.section {
			title = "Lines",
			note = "21 high · rail 3 at 55% · gutters 36 · marker 28 · wash 5.5%",
			ui.row {
				gap = "$zeron.space.32",
				items = "start",
				specimen.cell {
					label = "add / delete / context",
					specimen.frame {
						w = 560,
						p = 0,
						bg = T.card,
						overflow = "hidden",
						diff.line(HUNK.lines[3]),
						diff.line(HUNK.lines[2]),
						diff.line(HUNK.lines[1]),
					},
				},
				specimen.cell {
					label = "hunk header 28",
					specimen.frame {
						w = 400,
						p = 0,
						bg = T.card,
						overflow = "hidden",
						diff.hunk { header = HUNK.header, lines = {} },
					},
				},
			},
		},
		kit.text.text { "", size = "xs" },
	}
end
