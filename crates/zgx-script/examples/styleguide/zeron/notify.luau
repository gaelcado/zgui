-- What a session's run tells you as it changes (sound.rs, the engine's
-- desktop_notify.rs): a run finished, input wanted, a run failed, the
-- connection lost. The chime follows Sounds: Session sounds and the
-- event's own (Zeron's done.wav, request.wav, attention.wav; `chime`
-- counts what rang). The banner follows Desktop notifications: the
-- desktop's, with the session's title and what happened, only while the
-- window is at the back unless "Only when in the background" is off;
-- where the platform shows none (headless, off macOS), a toast. A banner
-- clicked opens its chat (agent updates, Settings → Agents), as
-- lib.rs open_notification_target does. One baseline per session, which
-- its first sight seeds silently, so a launch never rings; side chats
-- never ring.
local kit = require("@kit")
local data = require("./data")
local account = require("./account")

local M = {}

export type Event = "done" | "input" | "failed"

M.BODY = {
	done = "Run finished",
	input = "Waiting on your input",
	failed = "Run failed",
} :: { [Event]: string }
M.SOUNDS = {
	done = "sounds/done.wav",
	input = "sounds/request.wav",
	failed = "sounds/attention.wav",
} :: { [Event]: string }

-- The chimes rung, in order.
M.chime = ui.state("zeron_chime", { count = 0, kind = "" })

-- A failure seen by two watches at once (a session's and the
-- connection's) chimes once.
local COALESCE = 250
local failed_at = -math.huge

-- What a banner clicked opens: Settings → Agents for agent updates, else
-- its session.
M.AGENT_UPDATES = "agent_updates"
ui.on_notification(function(target: any)
	if type(target) ~= "string" then
		return
	end
	local state = require("./state")
	if target == M.AGENT_UPDATES then
		require("./settings").section:set("harnesses")
		state.settings:set(true)
	elseif data.session(target) then
		state.settings:set(false)
		state.open_session(target)
	end
end)

-- The desktop's banner, as the settings allow: the platform shows it only
-- while the app is at the back with Only when in the background; where it
-- shows none (headless, off macOS) and banners are wanted even in front, a
-- toast. `target`: what a click on it opens.
local function banner(title: string, body: string, tone: string?, target: string?)
	local pref = require("./settings").pref
	if not pref.desktop:peek() then
		return
	end
	local back = pref.background_only:peek()
	if not ui.notify { title = title, body = body, background = back, data = target } and not back then
		kit.toast.push { title = title, description = body, tone = tone :: any }
	end
end

-- Session `target`'s run (none: the connection) did `kind`.
function M.event(kind: Event, title: string?, body: string?, target: string?)
	local pref = require("./settings").pref
	local wanted = if kind == "done"
		then pref.notify_done:peek()
		elseif kind == "input" then pref.notify_input:peek()
		else pref.notify_failed:peek()
	if pref.sounds:peek() and wanted then
		local now = ui.now()
		if kind ~= "failed" or now - failed_at >= COALESCE then
			if kind == "failed" then
				failed_at = now
			end
			local last = M.chime:peek()
			M.chime:set { count = last.count + 1, kind = kind }
			ui.play_sound(M.SOUNDS[kind])
		end
	end
	banner(title or "New session", body or M.BODY[kind], if kind == "failed" then "danger" else nil, target)
end

-- A banner of the app's own (agent updates, as Agent updates allows): no
-- chime.
function M.banner(title: string, body: string)
	if require("./settings").pref.agent_updates:peek() then
		banner(title, body, nil, M.AGENT_UPDATES)
	end
end

-- What a session's status moving from `before` calls for: failing and
-- waiting ring as they start, a run finishing as it ends.
function M.ping_since(now: string, before: string): Event?
	if now == "failed" and before ~= "failed" then
		return "failed"
	elseif now == "input" and before ~= "input" then
		return "input"
	elseif before == "working" and (now == "done" or now == "idle") then
		return "done"
	end
	return nil
end

local baseline: { [string]: string } = {}
for _, s in data.SESSIONS do
	baseline[s.key] = s.status
end

-- Session `key` is now `status`: the baseline moves, and a change worth
-- it rings (a side chat's never does).
function M.observe(key: string, status: string)
	local before = baseline[key]
	baseline[key] = status
	if before == nil or before == status then
		return
	end
	local s = data.session(key)
	if s == nil or s.parent ~= nil then
		return
	end
	local kind = M.ping_since(status, before)
	if kind then
		M.event(kind, s.title, nil, key)
	end
end

-- The connection: losing it rings once (offline, or trying again); it
-- coming back, or a launch into an outage, is quiet.
local function degraded(c: string): boolean
	return c == "offline" or c == "reconnecting"
end
local seen: string? = nil
ui.effect(function()
	local c = account.connection:get()
	local before = seen
	seen = c
	if before ~= nil and degraded(c) and not degraded(before) then
		M.event(
			"failed",
			"Connection unavailable",
			if c == "offline" then "Your device is offline" else "Zeron is trying to reconnect"
		)
	end
end)

-- The sample engine's sessions, until one is wired: the release notes'
-- run finishing, asking, failing, then at work again.
M.SAMPLE = "agent:a1"
function M.sample(status: string)
	if status ~= "working" and baseline[M.SAMPLE] ~= "working" then
		M.observe(M.SAMPLE, "working")
	end
	M.observe(M.SAMPLE, status)
end

return M
