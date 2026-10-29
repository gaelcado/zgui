-- Voice and Appshots (dictation/model.rs, settings/appshots.rs,
-- appshots.rs; v0.2.129). Voice: where Codex's voice runs and its style;
-- dictation, its speech model downloaded as it is turned on (its progress,
-- a cancel, a failure said in a toast), the microphone (one unplugged
-- stays chosen as "Disconnected microphone"), the shortcut, and the model's
-- Remove (refused while dictating). Appshots: the capture, its sound, the
-- global shortcut (one that cannot work system-wide is refused), where
-- captures go, and each permission's status with the step that grants it,
-- checked again on request. Sample devices and permissions until the
-- engine is wired.
local T = require("../theme")
local txt = require("./text")
local button = require("./button")
local select = require("./select")
local settings = require("./settings")
local shortcut = require("./shortcut")
local keymap = require("./keymap")
local toast = require("./toast")
local dictation = require("./dictation")
local agents = require("./settings_agents")

local M = {}

-- The on-device speech model (zeron_voice): Parakeet v3, 640 MB.
M.MODEL_MB = 640
-- Whether it is on disk and loaded; the bytes a download has, while one
-- runs (nil otherwise).
M.model = ui.state("voice_model", { present = true, ready = true })
M.downloaded = ui.state("voice_model_downloaded", nil :: number?)
-- The sample's input devices, and whether the USB one is plugged in.
M.usb = ui.state("voice_usb_microphone", true)
-- The devices remote voice can run on, the Build box until it is removed
-- (⌘K's sample engine).
M.build_box = ui.state("voice_build_box", true)

local DOWNLOAD_STEP = 100
local cancel_download: (() -> ())? = nil

-- Dictation's switch (VoiceCard::primary): cancels a download under way,
-- turns dictation on or off once the model is there, or downloads it.
local function download(enabled: State<boolean>)
	if cancel_download then
		return
	end
	local fails = agents.failing()
	local cancelled = false
	M.downloaded:set(0)
	local stop = ui.every(DOWNLOAD_STEP, function()
		local now = (M.downloaded:peek() or 0) + 48
		if fails and now >= M.MODEL_MB * 0.4 then
			cancel_download = nil
			M.downloaded:set(nil)
			toast.push {
				title = "Couldn’t download or verify the model. Check your connection and free storage, then retry.",
				tone = "danger",
			}
			return false
		end
		if now >= M.MODEL_MB then
			cancel_download = nil
			M.downloaded:set(nil)
			M.model:set { present = true, ready = true }
			enabled:set(not cancelled)
			return false
		end
		M.downloaded:set(now)
		return true
	end)
	cancel_download = function()
		cancelled = true
		stop()
		cancel_download = nil
		M.downloaded:set(nil)
		toast.push { title = "Download cancelled.", tone = "danger" }
	end
end
local function primary(enabled: State<boolean>)
	if cancel_download then
		cancel_download()
	elseif M.model:peek().ready then
		enabled:set(not enabled:peek())
	else
		download(enabled)
	end
end
-- Remove (VoiceCard::remove): refused while a composer dictates.
function M.remove(enabled: State<boolean>)
	if dictation.busy() then
		toast.push { title = "Stop dictation before removing the model.", tone = "danger" }
		return
	end
	if agents.failing() then
		toast.push { title = "Could not remove the model. Check folder permissions and retry.", tone = "danger" }
		return
	end
	enabled:set(false)
	M.model:set { present = false, ready = false }
end

export type VoicePrefs = {
	dictation: State<boolean>,
	microphone: State<string>,
	voice_host: State<string>,
	voice_style: State<string>,
}

-- Where Codex's voice can run (shell.rs Voice hosts): this device, then
-- each other one, available only online and new enough.
type Host = { id: string, name: string, available: boolean, detail: string }
local function hosts(): { Host }
	local out: { Host } = { { id = "", name = "This device", available = true, detail = "Local" } }
	for _, d in agents.devices:get() do
		if not d.you and not d.cloud and (d.name ~= "Build box" or M.build_box:get()) then
			local online = d.seen == ""
			local compatible = d.version == nil or d.version >= "0.2.128"
			table.insert(out, {
				id = d.id,
				name = d.name,
				available = online and compatible,
				detail = if not online
					then "Offline"
					elseif not compatible then "Update Zeron to use remote voice"
					else "Available",
			})
		end
	end
	return out
end

local VOICES = { "alloy", "ash", "ballad", "coral", "echo", "sage", "shimmer", "verse" }

-- The Voice page. `live`: whether a voice call is on (its device holds).
function M.voice(prefs: VoicePrefs, km: keymap.Keymap, live: (() -> boolean)?): Node
	local function calling(): boolean
		return live ~= nil and live()
	end
	-- The host select: a choice that cannot run voice is refused, as is
	-- any during a call; a device gone stays chosen, "Unavailable device".
	local host_choice = ui.use_state(prefs.voice_host:peek())
	ui.effect(function()
		local want = host_choice:get()
		if want == prefs.voice_host:peek() then
			return
		end
		local ok = false
		for _, h in hosts() do
			if h.id == want then
				ok = h.available
			end
		end
		if ok and not calling() then
			prefs.voice_host:set(want)
		else
			host_choice:set(prefs.voice_host:peek())
		end
	end)
	local host_select = ui.presence(function(): string
		local parts = { prefs.voice_host:get() }
		for _, h in hosts() do
			table.insert(parts, `{h.id}:{h.detail}`)
		end
		return table.concat(parts, "|")
	end, function(): Node
		local options: { select.Option } = {}
		local known = false
		for i, h in hosts() do
			known = known or h.id == prefs.voice_host:peek()
			table.insert(options, { value = h.id, label = h.name, detail = h.detail, id = `voice_host_{i}` })
		end
		if not known then
			table.insert(options, {
				value = prefs.voice_host:peek(),
				label = "Unavailable device",
				detail = "Choose another device",
				id = "voice_host_gone",
			})
		end
		return select { id = "voice_host", label = "Codex voice device", value = host_choice, options = options, w = 200 }
	end)
	local styles: { select.Option } = { { value = "", label = "Codex default", id = "voice_style_1" } }
	for i, v in VOICES do
		table.insert(
			styles,
			{ value = v, label = string.upper(string.sub(v, 1, 1)) .. string.sub(v, 2), id = `voice_style_{i + 1}` }
		)
	end

	-- Dictation's switch shows the download under way or dictation on.
	local shown = ui.use_state(false)
	ui.effect(function()
		local on = M.downloaded:get() ~= nil or (prefs.dictation:get() and M.model:get().ready)
		if shown:peek() ~= on then
			shown:set(on)
		end
	end)
	local function dictation_meta(): string
		local got = M.downloaded:get()
		if got then
			return `Downloading · {got} of {M.MODEL_MB} MB`
		end
		return if M.model:get().ready then "" else `{M.MODEL_MB} MB download`
	end
	local progress = ui.show(
		function()
			return M.downloaded:get() ~= nil
		end,
		ui.div {
			id = "voice_progress",
			w_full = true,
			h = 3,
			mt = "$zeron.space.8",
			rounded = T.radius_full,
			bg = T.border,
			ui.div {
				h_full = true,
				rounded = T.radius_full,
				bg = T.accent,
				w = function()
					return `{math.clamp((M.downloaded:get() or 0) / M.MODEL_MB, 0, 1) * 100}%`
				end,
			},
		}
	)
	-- The microphones: the system's default (its device), each plugged in,
	-- and one chosen but unplugged.
	local microphone = ui.presence(function(): string
		return `{M.usb:get()}:{prefs.microphone:get()}`
	end, function(): Node
		local names = { "MacBook Pro Microphone" }
		if M.usb:peek() then
			table.insert(names, "USB Microphone")
		end
		local options: { select.Option } = {
			{ value = "System default", label = "System default", detail = names[1], id = "settings_microphone_1" },
		}
		local known = prefs.microphone:peek() == "System default"
		for i, n in names do
			known = known or prefs.microphone:peek() == n
			table.insert(options, { value = n, label = n, id = `settings_microphone_{i + 1}` })
		end
		if not known then
			table.insert(options, {
				value = prefs.microphone:peek(),
				label = "Disconnected microphone",
				id = "settings_microphone_gone",
			})
		end
		return select {
			id = "settings_microphone",
			label = "Microphone",
			value = prefs.microphone,
			options = options,
			w = 200,
		}
	end)
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.24",
		settings.header { title = "Voice" },
		settings.card {
			settings.row {
				anchor = "codex_voice_device",
				title = "Codex voice device",
				meta = {
					function()
						return if calling()
							then "End the call to change devices"
							else "Runs Codex; audio stays on this device"
					end,
				},
				control = host_select,
			},
			settings.row {
				anchor = "codex_voice_style",
				title = "Codex voice style",
				meta = { "Applies to your next voice session" },
				control = select {
					id = "voice_style",
					label = "Codex voice style",
					value = prefs.voice_style,
					options = styles,
					w = 200,
				},
			},
		},
		settings.card {
			ui.column {
				w_full = true,
				on_mount = settings.anchor("dictation"),
				settings.row {
					title = "Dictation",
					meta = { dictation_meta },
					control = settings.switch {
						id = "settings_dictation",
						value = shown,
						on_change = function()
							primary(prefs.dictation)
						end,
					},
				},
				ui.show(
					function()
						return M.downloaded:get() ~= nil
					end,
					ui.column { w_full = true, px = "$zeron.space.16", pb = "$zeron.space.12", mt = T.pull(12), progress }
				),
			},
			ui.show(function()
				return prefs.dictation:get() and M.model:get().ready
			end, settings.row { anchor = "microphone", title = "Microphone", control = microphone }),
			settings.row {
				anchor = "shortcut:toggle_dictation",
				title = "Shortcut",
				meta = { "Hold to talk, release to transcribe" },
				control = shortcut.binding(km, "toggle_dictation", "settings_dictation_key"),
			},
		},
		ui.show(
			function()
				return M.model:get().present and M.downloaded:get() == nil
			end,
			settings.card {
				settings.row {
					anchor = "speech_model",
					title = "Speech model",
					meta = { "Parakeet v3", `{M.MODEL_MB} MB` },
					control = button {
						id = "settings_speech_remove",
						label = "Remove",
						size = "sm",
						variant = "secondary",
						on_click = function()
							M.remove(prefs.dictation)
						end,
					},
				},
			}
		),
	}
end

-- Appshots' capabilities (appshots.rs CapabilityState) on the sample Mac:
-- what the system has granted, what the page last read of it, and whether
-- each permission's request has been made (its button then opens System
-- Settings).
export type Capability = "Checking" | "Ready" | "Required" | "Unavailable"
M.granted = ui.state("appshots_granted", { window = true, text = false })
M.capabilities = ui.state(
	"appshots_capabilities",
	{ window = "Ready", text = "Required", shortcut = "Ready" } :: {
		window: Capability,
		text: Capability,
		shortcut: Capability,
	}
)
M.prompted = ui.state("appshots_prompted", { window = false, text = false })
local SETTINGS_URL = {
	window = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
	text = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
}

-- Check permissions again: each "Checking" a moment, then as granted.
function M.check()
	local now = table.clone(M.capabilities:peek())
	now.window, now.text = "Checking", "Checking"
	M.capabilities:set(now)
	ui.after(300, function()
		local g = M.granted:peek()
		local next = table.clone(M.capabilities:peek())
		next.window = if g.window then "Ready" else "Required"
		next.text = if g.text then "Ready" else "Required"
		M.capabilities:set(next)
	end)
end
-- The sample's permissions taken back (a fresh install's).
function M.revoke()
	M.granted:set { window = false, text = false }
	M.prompted:set { window = false, text = false }
	M.check()
end
-- A permission's step: the system's prompt first (the sample's user then
-- allows it, for Check again to find), System Settings after.
local function request(kind: "window" | "text")
	local p = table.clone(M.prompted:peek())
	if p[kind] then
		ui.open_url(SETTINGS_URL[kind])
		return
	end
	p[kind] = true
	M.prompted:set(p)
	local g = table.clone(M.granted:peek())
	g[kind] = true
	M.granted:set(g)
end

local BADGE: { [Capability]: string } =
	{ Checking = "Checking", Ready = "Ready", Required = "Required", Unavailable = "Unavailable" }

export type AppshotPrefs = {
	appshots: State<boolean>,
	appshot_sound: State<boolean>,
	appshot_destination: State<string>,
}
type Choice = { label: string, detail: string }
M.DESTINATIONS = {
	{
		label = "Automatic",
		detail = "Use the open session, or the new-session composer when no session is open.",
	},
	{
		label = "Last session",
		detail = "Use the open session, or return to the last session used for an Appshot.",
	},
	{
		label = "New session",
		detail = "Stage captures in a new-session composer, keeping existing drafts intact.",
	},
} :: { Choice }

function M.appshots(prefs: AppshotPrefs, km: keymap.Keymap): Node
	local destinations: { select.Option } = {}
	for i, d in M.DESTINATIONS do
		table.insert(destinations, { value = d.label, label = d.label, id = `settings_appshot_destination_{i}` })
	end
	local function destination_detail(): string
		for _, d in M.DESTINATIONS do
			if d.label == prefs.appshot_destination:get() then
				return d.detail
			end
		end
		return ""
	end
	local function capability(kind: "window" | "text" | "shortcut"): Capability
		return (M.capabilities:get() :: any)[kind]
	end
	-- A permission's badge and, while capture is on and it is required,
	-- the step that grants it.
	local function access(kind: "window" | "text", first: string): Node
		return ui.row {
			gap = "$zeron.space.10",
			items = "center",
			shrink = 0,
			settings.badge(function()
				return BADGE[capability(kind)]
			end, `appshots_{kind}_status`),
			ui.show(
				function()
					return prefs.appshots:get() and capability(kind) == "Required"
				end,
				button {
					id = `appshots_{kind}_access`,
					label = function()
						return if (M.prompted:get() :: any)[kind] then "Open System Settings" else first
					end,
					size = "sm",
					variant = "ghost",
					on_click = function()
						request(kind)
					end,
				}
			),
		}
	end
	return ui.column {
		w_full = true,
		max_w = settings.WIDTH,
		self = "center",
		gap = "$zeron.space.24",
		settings.header {
			title = "Appshots",
			description = "Set up once, one permission at a time. Screen Recording captures the window; Accessibility optionally adds off-screen application text.",
		},
		ui.column {
			w_full = true,
			gap = "$zeron.space.8",
			settings.card {
				settings.row {
					anchor = "capture_appshots",
					title = "Capture Appshots",
					meta = { "Captures are staged for review and never sent automatically." },
					control = settings.switch { id = "settings_appshots", value = prefs.appshots },
				},
				settings.row {
					anchor = "appshot_sound",
					title = "Capture sound",
					meta = { "Play a sound when an Appshot is ready." },
					control = settings.switch { id = "settings_appshot_sound", value = prefs.appshot_sound },
				},
				settings.row {
					anchor = "shortcut:capture_appshot",
					title = "Global shortcut",
					meta = {
						function()
							return if capability("shortcut") == "Ready"
								then "The shortcut works while another application has focus."
								else "This shortcut is unavailable. Choose a different key combination."
						end,
					},
					control = ui.row {
						gap = "$zeron.space.10",
						items = "center",
						settings.badge(function()
							return BADGE[capability("shortcut")]
						end),
						shortcut.binding(km, "capture_appshot", "settings_appshot_key"),
					},
				},
				settings.row {
					anchor = "appshot_destination",
					title = "Destination",
					meta = { destination_detail },
					control = select {
						id = "settings_appshot_destination",
						label = "Destination",
						value = prefs.appshot_destination,
						options = destinations,
						w = 148,
					},
				},
				settings.row {
					anchor = "window_capture",
					title = "Window capture",
					meta = {
						"Screen Recording lets Zeron capture the frontmost window. macOS may request one restart.",
					},
					control = access("window", "Allow window capture"),
				},
				settings.row {
					anchor = "application_text",
					title = "Application text",
					meta = {
						"Accessibility adds visible and off-screen application text. Screenshots work without it.",
					},
					control = access("text", "Enable text capture"),
				},
			},
			-- Recording's hint, or why the last combo was refused.
			ui.row {
				w_full = true,
				min_h = 20,
				px = "$zeron.space.8",
				txt.text {
					function()
						if km.recording:get() == "capture_appshot" then
							return "Press Escape to cancel."
						end
						return km.notice:get()
					end,
					id = "appshots_helper",
					size = "sm",
					color = T.secondary,
					wrap = true,
				},
			},
			ui.row {
				w_full = true,
				pl = "$zeron.space.8",
				gap = "$zeron.space.12",
				items = "center",
				txt.text {
					"Changed a permission? Check again after returning to Zeron.",
					size = "sm",
					color = T.secondary,
					grow = 1,
					wrap = true,
				},
				button {
					id = "appshots_check",
					label = "Check again",
					size = "sm",
					variant = "ghost",
					on_click = M.check,
				},
			},
		},
	}
end

return M
