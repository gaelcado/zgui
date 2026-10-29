-- Settings → Billing (settings/billing.rs, v0.2.129): the credits that run
-- Cloud sessions. Credits: the balance and the hours it buys over a bar of
-- plan and extra credits, then a line for each. Plan: Base, Pro and Max
-- side by side, the current one ringed ("Choose Base", or Switch while on
-- one), then the plan's line (Renews, Ends, or the payment that failed)
-- and Manage subscription. Extra credits: packs (Fewer and More packs, at
-- most 20) and "Buy for $X". Stripe's pages open in the browser; while one
-- is, "Finish in your browser" shows until what it changes lands (a
-- toast says what), or Dismiss. A server without billing says so and
-- buys nothing. The sample engine's account, its states on ⌘K.
local T = require("../theme")
local kit = require("@kit")
local button_kit = require("@kit/button")
local icon_kit = require("@kit/icon")

local M = {}

export type Plan = { id: string, name: string, price: number, credits: number }
M.PLANS = {
	{ id = "base", name = "Base", price = 2000, credits = 45000 },
	{ id = "pro", name = "Pro", price = 5000, credits = 112500 },
	{ id = "max", name = "Max", price = 20000, credits = 450000 },
} :: { Plan }
M.PACK = { price = 1000, credits = 12000 }
local MAX_PACKS = 20

local DAY = 86400
local function now(): number
	return os.time()
end

export type Status = {
	-- Billing is set up on the server.
	available: boolean,
	plan: string?,
	-- The last payment failed (Stripe's past_due), or it ends at the period's end.
	past_due: boolean?,
	ends: boolean?,
	-- When the period ends (seconds).
	period_end: number,
	monthly: number,
	monthly_total: number,
	extra: number,
}
local function sample(): Status
	return {
		available = true,
		plan = "pro",
		period_end = now() + 8 * DAY,
		monthly = 84210,
		monthly_total = 112500,
		extra = 12000,
	}
end
M.status = ui.state("billing_status", sample())
M.packs = ui.state("billing_packs", 1)
-- The button waiting on the engine ("plan:<id>", "credits", "portal").
M.busy = ui.state("billing_busy", "")
-- A Stripe page is open in the browser.
M.pending = ui.state("billing_pending", false)
M.error = ui.state("billing_error", "")
-- The next Cloud or billing step fails (⌘K).
M.fail_next = ui.state("cloud_fail_next", false)
function M.failing(): boolean
	if M.fail_next:peek() then
		M.fail_next:set(false)
		return true
	end
	return false
end

function M.plan_of(id: string?): Plan?
	for _, p in M.PLANS do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- What's left: plan credits, then extra.
function M.total(): number
	local s = M.status:get()
	return math.max(s.monthly, 0) + math.max(s.extra, 0)
end
function M.out_of_credits(): boolean
	return M.total() <= 0
end

-- "45,000": whole, grouped by thousands.
function M.group(value: number): string
	local digits = tostring(math.floor(math.abs(value) + 0.5))
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	out = string.gsub(out, "^,", "")
	return if value < 0 and out ~= "0" then `-{out}` else out
end
-- "1,240 credits", a decimal only under ten.
function M.credits(value: number): string
	local v = math.abs(value)
	local number = if v > 0 and v < 10 and v % 1 >= 0.05 then string.format("%.1f", v) else M.group(v)
	local unit = if number == "1" then "credit" else "credits"
	return `{if value < 0 then "-" else ""}{number} {unit}`
end
-- "$20", "$12.50".
function M.price(cents: number): string
	return if cents % 100 == 0 then `${cents // 100}` else `${cents // 100}.{string.format("%02d", cents % 100)}`
end
-- "about 750 hours" of the default machine (a credit is a minute).
function M.hours(credits: number): string
	return `about {M.group(math.floor(credits / 60 + 0.5))} hours`
end
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
-- "Nov 5".
function M.short_date(seconds: number): string
	local d = os.date("*t", seconds) :: any
	return `{MONTHS[d.month]} {d.day}`
end

-- What landed, in a sentence (change_message).
local function change_message(before: Status, after: Status): string?
	if after.plan ~= before.plan then
		local p = M.plan_of(after.plan)
		return if p then `You're on {p.name} — {M.credits(p.credits)} a month` else "Your plan has ended"
	end
	if (after.ends or false) ~= (before.ends or false) then
		return if after.ends then "Your plan won't renew" else "Your plan will renew"
	end
	local added = after.extra - before.extra
	return if added >= 1 then `Added {M.credits(added)}` else nil
end

-- Open a Stripe page: a moment on the engine, then the browser; the
-- sample's page lands `change` a moment later.
local token = 0
local function open(busy: string, change: ((s: Status) -> ())?)
	if M.busy:peek() ~= "" then
		return
	end
	token += 1
	local mine = token
	M.busy:set(busy)
	M.error:set("")
	ui.after(500, function()
		if token ~= mine then
			return
		end
		M.busy:set("")
		if M.failing() then
			M.error:set("Couldn't reach Stripe: the request timed out")
			return
		end
		M.pending:set(true)
		if not change then
			return
		end
		local apply = change
		ui.after(1600, function()
			if token ~= mine or not M.pending:peek() then
				return
			end
			local before = M.status:peek()
			local after = table.clone(before)
			apply(after)
			M.pending:set(false)
			M.status:set(after)
			local message = change_message(before, after)
			if message then
				kit.toast.push { title = message, tone = "success" }
			end
		end)
	end)
end
function M.stop_watching()
	token += 1
	M.pending:set(false)
end

local function subscribe(p: Plan)
	open(`plan:{p.id}`, function(s: Status)
		s.plan = p.id
		s.monthly = p.credits
		s.monthly_total = p.credits
		s.period_end = now() + 30 * DAY
		s.past_due = nil
		s.ends = nil
	end)
end
local function buy()
	local packs = M.packs:peek()
	open("credits", function(s: Status)
		s.extra += M.PACK.credits * packs
	end)
end

-- The sample engine's account (⌘K): no plan, a failed payment, a plan
-- ending, no credits left, or billing not set up on the server.
function M.sample(kind: string)
	local s = sample()
	if kind == "none" then
		s.plan = nil
		s.monthly = 0
		s.monthly_total = 0
		s.extra = 0
	elseif kind == "past_due" then
		s.past_due = true
	elseif kind == "ends" then
		s.ends = true
	elseif kind == "empty" then
		s.monthly = 0
		s.extra = 0
	elseif kind == "unavailable" then
		s.available = false
	end
	M.stop_watching()
	M.status:set(s)
end

-- A caption: 12 muted.
local function caption(text: Text, color: Color?): Node
	return kit.text.text { text, size = "sm", color = color or T.secondary, wrap = true }
end
-- A figure and its unit on one baseline.
local function figure(size: string, text: Text, unit: string): Node
	return ui.row {
		gap = "$zeron.space.6",
		items = "baseline",
		ui.text {
			text,
			font = T.sans,
			text_size = size,
			weight = "$font.weight.semibold",
			color = T.text,
		},
		kit.text.text { unit, size = "sm", color = T.secondary, line = false },
	}
end
local function button(id: string, label: Text, variant: button_kit.Variant, enabled: () -> boolean, run: () -> ()): Node
	return kit.button {
		id = id,
		label = label,
		size = "sm",
		variant = variant,
		disabled = function()
			return not enabled()
		end,
		on_click = run,
	}
end
local function idle(): boolean
	return M.busy:get() == "" and M.status:get().available
end

-- The balance: one number and the time it buys, the bar, a line for
-- each kind.
local function credits(): Node
	return ui.presence(function(): string
		local s = M.status:get()
		return `{s.monthly}|{s.monthly_total}|{s.extra}|{s.period_end}`
	end, function(): Node
		local s = M.status:peek()
		local monthly, extra = math.max(s.monthly, 0), math.max(s.extra, 0)
		local total = monthly + extra
		local parts = math.max(total, 1)
		local function line(id: string, title: string, detail: string, value: string): Node
			return ui.row {
				id = id,
				w_full = true,
				min_h = 52,
				px = "$zeron.space.16",
				py = "$zeron.space.10",
				gap = "$zeron.space.16",
				items = "center",
				ui.column {
					grow = 1,
					min_w = 0,
					gap = "$zeron.space.2",
					kit.text.text { title, size = "md", weight = "medium" },
					caption(detail),
				},
				kit.text.text { value, size = "md", line = false, tabular = true },
			}
		end
		local plan_detail, plan_value = "No plan yet — choose one below", "—"
		if s.monthly_total > 0 then
			plan_detail = `Of {M.group(s.monthly_total)} · resets {M.short_date(s.period_end)}`
			plan_value = M.group(math.floor(monthly))
		end
		return kit.settings.section {
			title = "Credits",
			id = "billing_credits",
			ui.column {
				p = "$zeron.space.16",
				ui.row {
					w_full = true,
					items = "baseline",
					gap = "$zeron.space.12",
					ui.row {
						id = "billing_total",
						grow = 1,
						figure(
							"$zeron.font.size.figure",
							M.group(math.floor(total)),
							if total == 1 then "credit" else "credits"
						),
					},
					kit.text.text {
						if total > 0 then M.hours(total) else "Choose a plan or buy credits to run Cloud",
						size = "sm",
						color = T.secondary,
						line = false,
					},
				},
				total > 0 and ui.row {
					w_full = true,
					h = 4,
					mt = "$zeron.space.14",
					rounded = T.radius_full,
					bg = T.ink3,
					overflow = "hidden",
					monthly > 0
						and ui.div { h_full = true, w = `{monthly / parts * 100}%`, bg = "$zeron.credits.plan" },
					extra > 0 and ui.div { h_full = true, w = `{extra / parts * 100}%`, bg = "$zeron.credits.extra" },
				} or nil,
			},
			line("billing_plan_credits", "Plan credits", plan_detail, plan_value),
			line(
				"billing_extra_credits",
				"Extra credits",
				"Never expire · used once plan credits run out",
				M.group(math.floor(extra))
			),
		}
	end, { w_full = true })
end

local function plan_card(p: Plan, current: boolean, action: Node): Node
	return ui.column {
		id = `billing_plan_{p.id}`,
		grow = 1,
		basis = 0,
		min_w = 0,
		p = "$zeron.space.16",
		gap = "$zeron.space.4",
		rounded = T.radius_card,
		bg = T.ink1,
		border = 1,
		border_color = if current then "$zeron.credits.current" else T.clear,
		ui.row {
			w_full = true,
			h = 18,
			items = "center",
			justify = "between",
			kit.text.text { p.name, size = "md", weight = "medium", color = T.secondary, line = false },
			current and kit.settings.badge("Current") or nil,
		},
		ui.row { mt = "$zeron.space.4", figure("$zeron.font.size.hero", M.price(p.price), "/ month") },
		kit.text.text { `{M.credits(p.credits)} a month`, size = "sm", mt = "$zeron.space.4" },
		caption(M.hours(p.credits)),
		ui.column { mt = "$zeron.space.12", w_full = true, action },
	}
end

-- The plans, the current one marked; on one, switching and canceling go
-- through Stripe's portal.
local function plans(): Node
	return ui.presence(function(): string
		local s = M.status:get()
		return `{s.plan or ""}|{s.past_due}|{s.ends}|{s.period_end}`
	end, function(): Node
		local s = M.status:peek()
		local current = M.plan_of(s.plan)
		local cards: { Node } = {}
		for i, p in M.PLANS do
			local action: Node
			if current and current.id == p.id then
				action = kit.button {
					id = `billing_plan_{p.id}_current`,
					label = "Current plan",
					size = "sm",
					w_full = true,
					disabled = true,
				}
			elseif current then
				action = kit.button {
					id = `billing_plan_{p.id}_switch`,
					label = function()
						return if M.busy:get() == `plan:{p.id}` then "Opening…" else "Switch"
					end,
					size = "sm",
					w_full = true,
					disabled = function()
						return not idle()
					end,
					on_click = function()
						open(`plan:{p.id}`, function(after: Status)
							after.plan = p.id
							after.monthly_total = p.credits
							after.monthly = math.min(after.monthly, p.credits)
						end)
					end,
				}
			else
				action = kit.button {
					id = `billing_plan_{p.id}_choose`,
					label = function()
						return if M.busy:get() == `plan:{p.id}` then "Opening…" else `Choose {p.name}`
					end,
					size = "sm",
					variant = if i == 1 then "primary" else "secondary",
					w_full = true,
					disabled = function()
						return not idle()
					end,
					on_click = function()
						subscribe(p)
					end,
				}
			end
			table.insert(cards, plan_card(p, current ~= nil and current.id == p.id, action))
		end
		local detail, color = "", T.secondary
		if current then
			if s.past_due then
				detail, color =
					"Your last payment didn't go through — update your card to keep your plan.", T.warning_muted
			elseif s.ends then
				detail = `Ends {M.short_date(s.period_end)}. You keep its credits until then.`
			else
				detail = `Renews {M.short_date(s.period_end)}.`
			end
		end
		-- The plans side by side, then the current one's line, each a
		-- block of its own.
		return ui.column {
			id = "billing_plans",
			w_full = true,
			gap = "$zeron.space.10",
			kit.text.text { "Plan", size = "md", color = T.secondary },
			ui.column {
				w_full = true,
				gap = "$zeron.space.12",
				ui.row { w_full = true, gap = "$zeron.space.12", cards },
				current and kit.settings.card {
					ui.row {
						id = "billing_current",
						w_full = true,
						min_h = 52,
						px = "$zeron.space.16",
						py = "$zeron.space.10",
						gap = "$zeron.space.16",
						items = "center",
						ui.column {
							grow = 1,
							min_w = 0,
							gap = "$zeron.space.2",
							kit.text.text {
								`{current.name} · {M.price(current.price)} a month`,
								size = "md",
								weight = "medium",
							},
							caption(detail, color),
						},
						kit.button {
							id = "billing_manage",
							label = function()
								return if M.busy:get() == "portal" then "Opening…" else "Manage subscription"
							end,
							size = "sm",
							variant = "ghost",
							disabled = function()
								return M.busy:get() ~= ""
							end,
							on_click = function()
								open("portal", nil)
							end,
						},
					},
				} or nil,
			},
		}
	end, { w_full = true })
end

-- Packs: how many (− count +), then Buy.
local function extra(): Node
	local function step(id: string, glyph: icon_kit.Name, label: string, by: number): Node
		local function can(): boolean
			local n = M.packs:get() + by
			return n >= 1 and n <= MAX_PACKS
		end
		return ui.button {
			id = id,
			label = label,
			tooltip = label,
			w = 32,
			h = 32,
			p = 0,
			items = "center",
			justify = "center",
			rounded = "$zeron.radius.8",
			bg = T.clear,
			hover = { bg = T.ink2 },
			focus = { border = 0 },
			cursor = "pointer",
			disabled = function()
				return not can()
			end,
			opacity = function()
				return if can() then 1 else 0.35
			end,
			on_click = function()
				M.packs:set(math.clamp(M.packs:peek() + by, 1, MAX_PACKS))
			end,
			kit.icon { name = glyph, size = 12, color = T.secondary },
		}
	end
	return kit.settings.section {
		title = "Extra credits",
		id = "billing_extra",
		ui.row {
			w_full = true,
			min_h = 64,
			px = "$zeron.space.16",
			py = "$zeron.space.12",
			gap = "$zeron.space.16",
			items = "center",
			ui.column {
				grow = 1,
				min_w = 0,
				gap = "$zeron.space.2",
				kit.text.text {
					function()
						return M.credits(M.PACK.credits * M.packs:get())
					end,
					id = "billing_pack_credits",
					size = "md",
					weight = "medium",
				},
				caption(function()
					return `Never expire · {M.hours(M.PACK.credits * M.packs:get())}`
				end),
			},
			ui.row {
				gap = "$zeron.space.8",
				items = "center",
				ui.row {
					h = 32,
					items = "center",
					rounded = "$zeron.radius.8",
					bg = T.ink2,
					step("billing_fewer", "minus", "Fewer packs", -1),
					kit.text.text {
						function()
							return tostring(M.packs:get())
						end,
						id = "billing_packs",
						size = "md",
						weight = "medium",
						align = "center",
						min_w = 24,
						line = false,
						tabular = true,
					},
					step("billing_more", "plus", "More packs", 1),
				},
				ui.column {
					min_w = 96,
					button("billing_buy", function()
						return if M.busy:get() == "credits"
							then "Opening…"
							else `Buy for {M.price(M.PACK.price * M.packs:get())}`
					end, "secondary", idle, buy),
				},
			},
		},
	}
end

-- While a Stripe page is open: what it waits on, and a way to stop.
local function pending(): Node
	return ui.show(
		M.pending,
		ui.row {
			id = "billing_pending",
			w_full = true,
			px = "$zeron.space.14",
			py = "$zeron.space.10",
			gap = "$zeron.space.10",
			items = "center",
			rounded = T.radius_card,
			bg = T.ink1,
			kit.loaders.mini_spinner { color = T.secondary },
			kit.text.text {
				"Finish in your browser — this page updates when it's done.",
				size = "sm",
				grow = 1,
				min_w = 0,
				wrap = true,
			},
			kit.button {
				id = "billing_pending_dismiss",
				label = "Dismiss",
				size = "sm",
				variant = "ghost",
				on_click = M.stop_watching,
			},
		}
	)
end

-- A strip: the warning's or the danger's wash and its words.
local function strip(id: string, text: Text, tone: "warning" | "danger", on_click: (() -> ())?): Node
	return ui.row {
		id = id,
		w_full = true,
		px = "$zeron.space.14",
		py = "$zeron.space.10",
		rounded = T.radius_card,
		bg = if tone == "warning" then T.warning_wash else T.danger_wash,
		cursor = if on_click then "pointer" else nil,
		on_click = on_click,
		kit.text.text {
			text,
			size = "sm",
			color = if tone == "warning" then T.warning_muted else T.danger_muted,
			wrap = true,
		},
	}
end

-- The page, built while it shows.
function M.page(): Node
	return ui.column {
		id = "billing_page",
		w_full = true,
		max_w = kit.settings.WIDTH,
		self = "center",
		gap = "$zeron.space.32",
		kit.settings.header { title = "Billing", description = "Credits run your Cloud sessions." },
		ui.show(
			function()
				return M.error:get() ~= ""
			end,
			strip(
				"billing_error",
				function()
					return M.error:get()
				end,
				"danger",
				function()
					M.error:set("")
				end
			)
		),
		ui.show(
			function()
				return not M.status:get().available
			end,
			strip(
				"billing_unavailable",
				"Billing isn't set up on this server yet, so plans and credits can't be bought here.",
				"warning"
			)
		),
		pending(),
		-- Where settings search lands.
		ui.column { w_full = true, on_mount = kit.settings.anchor("credits"), credits() },
		ui.column { w_full = true, on_mount = kit.settings.anchor("plan"), plans() },
		ui.column { w_full = true, on_mount = kit.settings.anchor("extra_credits"), extra() },
	}
end

return M
