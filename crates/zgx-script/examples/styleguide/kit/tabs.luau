-- Tabs: a strip of labels with an underline under the selected one, or
-- pills, on zgx's tabs (`ui.tabs`: one Tab stop, the arrows, Home and End
-- choose, Delete closes, a strip too long scrolls with a menu of them all).
-- The kit draws each tab: the selection stays where it is, each washes
-- under the pointer (kit/wash); a closable tab shows its ×.
local T = require("../theme")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local motion = require("./motion")
local badge = require("./badge")
local wash = require("./wash")
local recipes = require("./recipes")

export type Tab = { id: string, label: string, icon: icon_mod.Name?, count: number?, closable: boolean? }
export type Props = {
	id: string,
	-- The tabs, or (`items`) a state of them that closing a tab writes.
	tabs: { Tab }?,
	items: State<{ any }>?,
	value: State<string>,
	variant: VariantOption<typeof(recipes.tabs), "variant">?,
	size: VariantOption<typeof(recipes.tab), "size">?,
	-- A tab closed: the app's to remove (else, a state's, the strip does).
	on_close: ((id: string) -> ())?,
	grow: number?,
	label: string?,
}

return ui.component(function(props: Props): Node
	local pills = props.variant == "pills"
	local small = props.size == "sm"
	local given: { Tab } = props.tabs or {}
	local items: State<{ any }> = props.items or ui.use_state(given :: { any })
	local radius = if pills then T.radius_item else T.radius_sm
	local function tab(t: Tab, close: () -> ()): Node
		local function on(): boolean
			return props.value:get() == t.id
		end
		-- The chosen tab's pill or underline, where it is.
		local indicator = if pills
			then wash.selection(on, T.radius_item, T.selected)
			else ui.div {
				absolute = true,
				left = 0,
				right = 0,
				bottom = 0,
				h = 2,
				rounded = "$zeron.radius.1",
				bg = T.text,
				pointer_events = "none",
				opacity = ui.tween(ui.computed(on), { from = 0, to = 1, duration = motion.d(90) }),
			}
		return ui.button {
			id = `{props.id}_{t.id}`,
			hover_group = true,
			variants = recipes.tab {
				variant = if pills then "pills" else "underline",
				size = if small then "sm" else "md",
				on = on,
			},
			wash.layer(on, radius),
			indicator,
			t.icon and icon { name = t.icon, size = 14, color = "currentColor" },
			txt.text {
				t.label,
				size = if small then "sm" else "md",
				weight = "medium",
				line = false,
				color = "inherit",
			},
			t.count and badge { label = tostring(t.count) },
			t.closable and ui.button {
				id = `{props.id}_{t.id}_close`,
				variants = recipes.tab_close,
				-- Not a stop of its own: the arrows go tab to tab.
				focusable = false,
				on_click = close,
				icon { name = "close", size = 12, color = "currentColor" },
			},
		}
	end
	local on_close = props.on_close
	return ui.tabs {
		id = props.id,
		label = props.label or "Tabs",
		items = items,
		value = props.value,
		-- The pills 2 apart; the underlined tabs keep their own margins.
		gap = if pills then T.space(2) else 0,
		variants = recipes.tabs { variant = if pills then "pills" else "underline" },
		grow = props.grow,
		on_close = if on_close
			then function(id: string): boolean
				on_close(id)
				return false
			end
			else nil,
		tab = tab,
	}
end)
