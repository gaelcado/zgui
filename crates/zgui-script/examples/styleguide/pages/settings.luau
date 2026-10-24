-- Settings: Zeron's preferences page as the kit lays it out.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local wash = require("@kit/wash")
local specimen = require("@shell/specimen")
local settings_page = require("@kit/settings_page")
local appearance = require("@kit/appearance")
local look = require("@kit/look")

-- The specimens' look: it styles nothing (the workbench has its own).
local specimen_look = look.new("s", "zeron", "system", false)
local shortcut = require("@kit/shortcut")

local mode = ui.state("s_mode", "dark" :: appearance.Mode)
local recording = ui.state("s_recording", false)

local function shortcuts(): Node
	return specimen.cell {
		label = "card rows · key chip ≥ 96 × 32, radius 8, mono 12 · recording on the accent at 16%",
		ui.column {
			w = 560,
			rounded = T.radius_card,
			bg = T.card,
			overflow = "hidden",
			shortcut.row { id = "sc_palette", title = "Open the palette", meta = { "Panels" }, keys = "Cmd+K" },
			shortcut.row {
				id = "sc_sidebar",
				title = "Toggle the sidebar",
				meta = { "Appearance" },
				keys = "Cmd+\\",
				customised = true,
			},
			shortcut.row {
				id = "sc_record",
				title = "New session",
				meta = { "Sessions", "click to record" },
				keys = "Cmd+N",
				recording = recording,
				on_click = ui.toggle(recording),
			},
		},
	}
end

local function appearance_cells(): Node
	local modes: { Node } = {}
	for _, m in { "system", "light", "dark" } :: { appearance.Mode } do
		table.insert(
			modes,
			appearance.card {
				id = `mode_{m}`,
				mode = m,
				selected = function()
					return mode:get() == m
				end,
				on_click = ui.set(mode, m),
			}
		)
	end
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "mode cards · 148 · border and caption to the accent",
			ui.row { gap = "$zeron.space.16", modes },
		},
		specimen.cell {
			label = "accent swatches · 30 · a 2-point bar under the chosen one",
			look.swatches(specimen_look, "swatch"),
		},
	}
end

local function account(): Node
	return ui.row {
		gap = "$zeron.space.32",
		items = "start",
		flex_wrap = true,
		specimen.cell {
			label = "usage meters · 16 high · label 52 · bar 88×4 · percent 34",
			ui.column {
				gap = "$zeron.space.6",
				kit.account.meter { label = "Session", level = 0.37 },
				kit.account.meter { label = "Weekly", level = 0.84 },
				kit.account.meter { label = "Opus", level = 0.97 },
			},
		},
		specimen.cell {
			label = "account row · avatar 32 with a 1.5 accent ring when in use · 'In use' in the accent · … opens the menu",
			wash.list {
				group = "accounts",
				w = 400,
				gap = "$zeron.space.4",
				color = T.ink1,
				kit.account.row {
					group = "accounts",
					email = "cado.gael@gmail.com",
					initial = "G",
					active = true,
					session = 0.37,
					weekly = 0.84,
				},
				kit.account.row {
					group = "accounts",
					email = "wing@zeron.sh",
					initial = "W",
					session = 0.12,
					weekly = 0.4,
				},
			},
		},
		specimen.cell {
			label = "update strip · padding 8×6 · radius 6 · text 11 medium",
			ui.column {
				w = 232,
				gap = "$zeron.space.6",
				kit.account.update_strip { id = "update", state = "available", version = "v0.2.110" },
				kit.account.update_strip { state = "downloading", version = "v0.2.110" },
				kit.account.update_strip { state = "ready" },
				kit.account.update_strip { state = "failed", detail = "checksum mismatch" },
			},
		},
	}
end

-- The page itself: the app's, in a frame.
local function page(): Node
	return ui.column {
		w_full = true,
		h = 600,
		rounded = T.radius_card,
		bg = T.bg,
		border = 1,
		border_color = T.hairline,
		overflow = "hidden",
		settings_page.view {
			section = ui.state("s_section", "appearance"),
			prefs = settings_page.prefs("s"),
			look = specimen_look,
		},
	}
end

local function notices(): Node
	return ui.column {
		gap = "$zeron.space.12",
		w = 520,
		kit.notice {
			message = "The agent stopped: OpenTable needs a verification code it cannot read.",
			tone = "warning",
		},
		kit.notice { message = "Could not reach api.zeron.sh. Retrying in 10 s.", tone = "danger", tile = true },
	}
end

return function(): Node
	local p = state.page_by("settings")
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		specimen.section {
			title = "A page",
			note = "The app's page: 760 wide · header 20/26 · sections 32 apart · cards at radius 12 on wash 4.5% · rows 60.",
			page(),
		},
		specimen.section { title = "Appearance", appearance_cells() },
		specimen.section { title = "Account", account() },
		specimen.section { title = "Shortcuts", shortcuts() },
		specimen.section {
			title = "Notices",
			note = "notice.rs: accent at 5% with a 16% border; plain, or with a 20-point tile.",
			notices(),
		},
	}
end
