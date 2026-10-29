-- Context usage (context_usage.rs): a 16-point ring with a 1.8 stroke
-- that fills clockwise from 12 o'clock, its percentage beside it in a
-- 24-high chip; muted until 75%, warning to 90%, danger past it. The card
-- under it says the numbers.
local T = require("../theme")
local txt = require("./text")
local recipes = require("./recipes")
local frost = require("./frost")
local popover = require("./popover")
local menu = require("./menu")
local account = require("./account")

export type Props = {
	id: string?,
	-- 0–1, or nil when unknown.
	used: State<number?>,
	-- Tokens, for the card.
	total: number?,
	on_click: (Handler | Action)?,
}
export type CardProps = { id: string?, used: number, total: number }
export type UsageProps = { id: string?, used: State<number?>, total: number }

local M = {}

M.RING = 16
M.STROKE = 1.8

local function tone(used: number?): Color
	if used == nil then
		return T.tertiary
	elseif used >= 0.9 then
		return T.danger
	elseif used >= 0.75 then
		return T.warning
	end
	return T.secondary
end

function M.ring(used: State<number?>, color: ((used: number) -> Color)?): Node
	return ui.canvas {
		-- How full the context is, worked out only while a screen reader
		-- reads it.
		label = function(): string
			local u = used:get()
			return if u == nil then "Context usage unknown" else `Context {math.floor(u * 100 + 0.5)}% used`
		end,
		w = M.RING,
		h = M.RING,
		shrink = 0,
		draw = function(cv: Canvas, w: number, h: number)
			local u = used:get()
			local r = (w - M.STROKE) / 2
			local track = ui.theme.get("zeron.ink.4") :: string
			cv.circle(cv, w / 2, h / 2, r, T.clear)
			cv.stroke(cv, ui.path():arc(w / 2, h / 2, r, 0, 360), track, M.STROKE)
			if u and u > 0 then
				cv.stroke(
					cv,
					ui.path():arc(w / 2, h / 2, r, -90, 360 * math.min(1, u)),
					tostring(ui.theme.get(string.sub((color or tone)(u) :: string, 2))),
					M.STROKE,
					{ cap = "butt" }
				)
			end
		end,
	}
end

M.chip = ui.component(function(props: Props): Node
	return ui.button {
		id = props.id,
		variants = recipes.context_chip {
			level = function()
				local u = props.used:get()
				return if u == nil then "none" elseif u >= 0.9 then "full" elseif u >= 0.75 then "high" else "low"
			end,
		},
		on_click = props.on_click,
		M.ring(props.used),
		txt.text {
			function()
				local u = props.used:get()
				return if u == nil then "—" else ui.number(u, { style = "percent" })
			end,
			size = "xs",
			tabular = true,
			-- Room for "100%" in tabular figures: the measured run comes up
			-- short of the painted one and would clip the percent sign.
			wrap = false,
			min_w = 26,
			line = false,
			color = "inherit",
		},
	}
end)

local function thousands(n: number): string
	return ui.number(math.floor(n), { decimals = 0 })
end

local function numbers(used_fraction: number, total: number): { Node }
	local used = math.floor(used_fraction * total)
	return {
		txt.text { "Context window", size = "xs", color = T.tertiary, px = "$zeron.space.8", py = "$zeron.space.4" },
		ui.column {
			px = "$zeron.space.8",
			pb = "$zeron.space.6",
			txt.text { `{thousands(used)} / {thousands(total)} tokens`, size = "sm", color = T.secondary },
			txt.text { `{thousands(total - used)} tokens remaining`, size = "sm", color = T.secondary },
		},
	}
end

M.card = ui.component(function(props: CardProps): Node
	return frost.card {
		id = props.id,
		w = 220,
		numbers(props.used, props.total),
	}
end)

-- The chip in the session footer, its card opening above it, end-aligned
-- 6 away (account_usage.rs anchored_menu_above_end); the numbers are
-- read as it opens.
M.usage = ui.component(function(props: UsageProps): Node
	local open = ui.use_state(false)
	return popover.popover {
		id = props.id and `{props.id}_card`,
		open = open,
		label = "Context window",
		placement = popover.ABOVE_END,
		w = 220,
		p = T.space(frost.INSET),
		anchor = M.chip { id = props.id, used = props.used, on_click = ui.toggle(open) },
		ui.presence(function()
			return if open:get() then tostring(props.used:get() or "none") else nil
		end, function(): Node
			local used = props.used:peek()
			if used == nil then
				-- The harness reports none (context_usage.rs details).
				return ui.column {
					txt.text {
						"Context window",
						size = "xs",
						color = T.tertiary,
						px = "$zeron.space.8",
						py = "$zeron.space.4",
					},
					ui.column {
						px = "$zeron.space.8",
						pb = "$zeron.space.6",
						txt.text {
							"Context usage not reported by this harness yet",
							id = props.id and `{props.id}_unreported`,
							size = "sm",
							color = T.secondary,
						},
					},
				}
			end
			return ui.column { numbers(used, props.total) }
		end),
	}
end)

-- The account's plan usage (account_usage.rs): the same 16 ring before the
-- context's, its arc in the accent (the warning colour from 80%, the
-- danger's from 95, as the meters), its percentage muted until then; the
-- harness's accounts open above it, each with its two meters, and a click
-- on another switches to it.
export type Window = { label: string, used: number, resets: string? }
export type Account = {
	id: string,
	email: string,
	plan: string?,
	active: boolean,
	switchable: boolean?,
	windows: { Window },
}
export type AccountProps = {
	id: string?,
	-- The harness's accounts.
	accounts: State<{ Account }>,
	-- "Claude", "Codex": the card's heading says "Claude accounts".
	provider: string,
	on_switch: ((id: string) -> ())?,
}

local function level_tone(used: number): Color
	return if used >= 0.95 then T.danger elseif used >= 0.8 then T.warning else T.accent
end

-- The binding limit: the live account's most-used window.
function M.used(accounts: { Account }): number?
	for _, a in accounts do
		if a.active then
			local most: number? = nil
			for _, w in a.windows do
				most = math.max(most or 0, math.clamp(w.used, 0, 1))
			end
			return most
		end
	end
	return nil
end

local function account_row(a: Account, i: number, id: string?, switch: ((id: string) -> ())?): Node
	local can = not a.active and a.switchable ~= false
	local resets: { string } = {}
	for _, w in a.windows do
		table.insert(resets, if w.resets then `{w.label}: {w.resets}` else w.label)
	end
	local meters: { Node } = {}
	for k, w in a.windows do
		if k > 2 then
			break
		end
		table.insert(meters, account.meter { label = w.label, level = w.used })
	end
	return ui.button {
		id = id and `{id}_row_{i}`,
		label = a.email,
		w_full = true,
		px = "$zeron.space.8",
		py = "$zeron.space.6",
		gap = "$zeron.space.10",
		items = "center",
		rounded = T.concentric(12, frost.INSET, 1),
		variants = recipes.picker_choice { selected = a.active },
		focus = { border = 0 },
		cursor = if can then "pointer" else "default",
		on_click = if can and switch
			then function()
				switch(a.id)
			end
			else nil,
		ui.column {
			grow = 1,
			shrink = 1,
			min_w = 0,
			gap = "$zeron.space.2",
			txt.text { a.email, size = "sm", weight = "medium", truncate = true, line = false, literal = true },
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				a.plan and txt.text { a.plan, size = "xs", color = T.secondary, line = false } or nil,
				a.plan and a.active and txt.text { "·", size = "xs", color = T.tertiary, line = false } or nil,
				a.active and txt.text { "In use", size = "xs", color = T.accent, line = false } or nil,
			},
		},
		#meters > 0 and ui.column {
			id = id and `{id}_meters_{i}`,
			shrink = 0,
			gap = "$zeron.space.2",
			tooltip = table.concat(resets, " · "),
			meters,
		} or nil,
	}
end

M.account = ui.component(function(props: AccountProps): Node
	local open = ui.use_state(false)
	local used = ui.computed(function(): number?
		return M.used(props.accounts:get())
	end)
	return popover.popover {
		id = props.id and `{props.id}_card`,
		open = open,
		label = `{props.provider} accounts`,
		placement = popover.ABOVE_END,
		w = 400,
		p = T.space(frost.INSET),
		gap = "$zeron.space.2",
		anchor = ui.button {
			id = props.id,
			label = "Plan usage",
			variants = recipes.context_chip {
				level = function()
					local u = used:get() or 0
					return if u >= 0.95 then "full" elseif u >= 0.8 then "high" else "low"
				end,
			},
			on_click = ui.toggle(open),
			M.ring(used, level_tone),
			txt.text {
				function()
					return ui.number(used:get() or 0, { style = "percent" })
				end,
				size = "xs",
				tabular = true,
				wrap = false,
				min_w = 26,
				line = false,
				color = "inherit",
			},
		},
		ui.presence(function()
			return if open:get() then "open" else nil
		end, function(): Node
			return ui.column {
				w_full = true,
				gap = "$zeron.space.2",
				menu.heading(`{props.provider} accounts`),
				ui.each(props.accounts, function(a: Account, i: number): Node
					return account_row(a, i, props.id, props.on_switch)
				end, {
					key = function(a: Account): string
						return a.id
					end,
					w_full = true,
					gap = "$zeron.space.2",
				}),
			}
		end, { w_full = true }),
	}
end)

return M
