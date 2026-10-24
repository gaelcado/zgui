-- Chips, badges, avatars and status dots.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")
local chip = require("@kit/chip")
local avatar = require("@kit/avatar")

local TONES: { string } = { "neutral", "accent", "danger", "warning", "success", "info" }
local VARIANTS: { string } = { "soft", "outline", "solid" }
local filters = {
	ui.state("f1", true),
	ui.state("f2", false),
	ui.state("f3", false),
}
type Tag = { id: string, label: string }
local tags = ui.state(
	"tags",
	{
		{ id = "a", label = "Dinner menu.pdf" },
		{ id = "b", label = "opentable.com" },
		{ id = "c", label = "photo.jpg" },
	} :: { Tag }
)

local function tones(): Node
	return specimen.matrix {
		id = "chip_tones",
		columns = TONES,
		rows = VARIANTS,
		col_w = 110,
		build = function(column: string, row: string): Node
			return kit.chip { label = column, tone = column :: chip.Tone, variant = row :: chip.Variant }
		end,
	}
end

local function sizes(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "end",
		specimen.cell { label = "xs (badge)", kit.chip { label = "Draft", size = "xs" } },
		specimen.cell { label = "sm", kit.chip { label = "Draft", size = "sm" } },
		specimen.cell { label = "md", kit.chip { label = "Draft", size = "md" } },
		specimen.cell { label = "icon", kit.chip { label = "main", icon = "git-branch", tone = "accent" } },
		specimen.cell { label = "dot", kit.chip { label = "Working", dot = true, tone = "accent" } },
		specimen.cell { label = "mono", kit.chip { label = "PDF", mono = true, tone = "danger", size = "xs" } },
		specimen.cell { label = "square", kit.chip { label = "v0.2.108", mono = true, pill = false } },
		specimen.cell { label = "disabled", kit.chip { label = "Archived", disabled = true } },
		specimen.cell {
			label = "picker trigger · 20 · radius 6",
			kit.chip { label = "Claude Opus", icon = "magic-stick-3", variant = "trigger", on_click = function() end },
		},
	}
end

local function filter_chips(): Node
	local labels = { "Open tabs", "History", "Bookmarks" }
	local chips: { Node } = {}
	for i, label in labels do
		chips[i] = kit.chip {
			id = `filter_{i}`,
			label = label,
			size = "md",
			selected = filters[i],
			on_click = function()
				filters[i]:toggle()
			end,
		}
	end
	return ui.row { gap = "$zeron.space.6", chips }
end

local function removable(): Node
	return ui.row {
		gap = "$zeron.space.6",
		items = "center",
		ui.each(tags, function(tag: Tag)
			return kit.chip {
				label = tag.label,
				size = "md",
				icon = "paperclip",
				on_remove = function()
					for i, t in tags:peek() do
						if t.id == tag.id then
							tags:remove(i)
						end
					end
				end,
			}
		end, {
			key = function(tag: Tag)
				return tag.id
			end,
			gap = "$zeron.space.6",
			direction = "row",
			animate = true,
			exit = { opacity = 0, scale = 0.9, duration = kit.motion.d(kit.motion.FAST) },
		}),
		kit.button {
			id = "tags_reset",
			label = "Reset",
			size = "sm",
			variant = "ghost",
			on_click = function()
				tags:set {
					{ id = "a", label = "Dinner menu.pdf" },
					{ id = "b", label = "opentable.com" },
					{ id = "c", label = "photo.jpg" },
				}
			end,
		},
	}
end

local function badges(): Node
	return ui.row {
		gap = "$zeron.space.24",
		items = "center",
		specimen.cell { label = "count", kit.badge { label = "3" } },
		specimen.cell { label = "count · accent", kit.badge { label = "12", tone = "accent", variant = "solid" } },
		specimen.cell { label = "status", kit.badge { label = "Needs you", tone = "warning", dot = true } },
		specimen.cell { label = "status", kit.badge { label = "Failed", tone = "danger", dot = true } },
		specimen.cell { label = "status", kit.badge { label = "Done", tone = "success", dot = true } },
		specimen.cell { label = "type", kit.badge { label = "PDF", tone = "danger", mono = true } },
		specimen.cell {
			label = "in a row",
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				kit.text.text { "Inbox", size = "md" },
				kit.badge { label = "24" },
			},
		},
	}
end

local function avatars(): Node
	local statuses: { avatar.Status } = { "working", "blocked", "error", "done", "idle" }
	local cells: { Node } = {}
	for _, s in statuses do
		table.insert(cells, specimen.cell { label = s, kit.avatar { name = "Ada Lovelace", size = 32, status = s } })
	end
	return ui.column {
		gap = "$zeron.space.24",
		ui.row {
			gap = "$zeron.space.24",
			items = "end",
			specimen.cell { label = "20", kit.avatar { name = "Ada Lovelace", size = 20 } },
			specimen.cell { label = "24", kit.avatar { name = "Grace Hopper", size = 24 } },
			specimen.cell { label = "32", kit.avatar { name = "Alan Turing", size = 32 } },
			specimen.cell { label = "40", kit.avatar { name = "Edsger Dijkstra", size = 40 } },
			specimen.cell { label = "icon", kit.avatar { name = "Claude", icon = "magic-stick-3", size = 32 } },
			specimen.cell { label = "square", kit.avatar { name = "zeron", size = 32, square = true } },
		},
		ui.row { gap = "$zeron.space.24", items = "end", cells },
		ui.row {
			gap = "$zeron.space.16",
			items = "center",
			kit.text.text { "Status dots alone:", size = "sm", color = T.secondary },
			kit.status_dot("working"),
			kit.status_dot("blocked"),
			kit.status_dot("error"),
			kit.status_dot("done"),
			kit.status_dot("idle"),
			kit.text.text { "working pulses at 30 fps; the rest ask for no frames", size = "xs", color = T.tertiary },
		},
	}
end

return function(): Node
	local page = state.page_by("chips")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(page.title, page.blurb),
		specimen.section {
			title = "Tones and variants",
			tones(),
		},
		specimen.section {
			title = "Sizes and parts",
			sizes(),
		},
		specimen.section {
			title = "Filter chips",
			filter_chips(),
		},
		specimen.section {
			title = "Dismissible",
			removable(),
		},
		specimen.section {
			title = "Badges",
			badges(),
		},
		specimen.section {
			title = "Avatars and status",
			avatars(),
		},
	}
end
