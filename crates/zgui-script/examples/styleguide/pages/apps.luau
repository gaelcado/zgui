-- Apps: the kit as whole windows. Each opens on its own, outside the
-- workbench, from `app_<name>.luau`.
local T = require("../theme")
local state = require("../state")
local kit = require("@kit")
local specimen = require("@shell/specimen")

type App = { id: string, title: string, blurb: string, size: string, icon: string, keys: { string }? }
local APPS: { App } = {
	{
		id = "zeron",
		title = "Zeron",
		blurb = "The window: agents and threads, glass tabs switching the pane (transcript, changes, an empty terminal), the todo tray behind the composer, the update strip and usage chip. ⌘K palette, ⌘, settings, ⌘\\ sidebar.",
		size = "1180 × 760",
		icon = "chat-round-line",
	},
	{
		id = "palette",
		title = "Palette",
		blurb = "A frameless frosted window holding the @ reference picker. Escape closes it.",
		size = "560 × 440",
		icon = "command",
	},
	{
		id = "settings",
		title = "Settings",
		blurb = "Sections down the left, cards on the right.",
		size = "760 × 600",
		icon = "settings-minimalistic",
	},
}

local function card(app: App): Node
	return specimen.frame {
		w = 300,
		p = "$zeron.space.16",
		gap = "$zeron.space.10",
		bg = T.base,
		ui.row {
			gap = "$zeron.space.10",
			items = "center",
			ui.row {
				w = 32,
				h = 32,
				items = "center",
				justify = "center",
				rounded = T.radius_lg,
				bg = T.ink2,
				kit.icon { name = app.icon :: any, size = 16 },
			},
			ui.column {
				gap = "$zeron.space.1",
				kit.text.text { app.title, size = "md", weight = "semibold" },
				kit.text.text { app.size, size = "xs", mono = true, color = T.tertiary },
			},
		},
		kit.text.text { app.blurb, size = "sm", color = T.secondary, wrap = true },
		ui.row {
			mt = "$zeron.space.4",
			kit.button {
				id = "open_" .. app.id,
				label = "Open",
				icon = { name = "arrow-up-right" },
				size = "sm",
				on_click = ui.action("open_app", app.id),
			},
		},
	}
end

return function(): Node
	local p = state.page_by("apps")
	local cards: { Node } = {}
	for _, app in APPS do
		table.insert(cards, card(app))
	end
	return ui.column {
		gap = "$zeron.space.40",
		w_full = true,
		specimen.header(p.title, p.blurb),
		ui.row { gap = "$zeron.space.16", flex_wrap = true, cards },
		kit.text.text {
			"Or from a shell: STYLEGUIDE_APP=zeron cargo run --release -p zgui-script --example styleguide",
			size = "xs",
			mono = true,
			color = T.tertiary,
		},
	}
end
