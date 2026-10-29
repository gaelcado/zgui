-- A text field: Zeron's input surface around the engine's editor, with a
-- label above, a hint or an error below, and an icon or control at either
-- end. `textarea` is the same with several lines. Its look is
-- `recipes.field`.
local T = require("../theme")
local types = require("./types")
local icon_mod = require("./icon")
local icon = require("./icon")
local txt = require("./text")
local recipes = require("./recipes")

export type Props = {
	id: string?,
	value: State<string>,
	placeholder: Reactive<string>?,
	-- A visible label above the field (also its accessible name).
	label: string?,
	-- Under the field: a hint, or an error that colours the field.
	hint: string?,
	error: Reactive<string>?,
	icon: icon_mod.Name?,
	-- At the end: a clear button, a key cap, a unit.
	trailing: Child?,
	size: VariantOption<typeof(recipes.field), "size">?,
	disabled: types.Cond?,
	mono: boolean?,
	select_on_focus: boolean?,
	w: Reactive<Length>?,
	w_full: boolean?,
	grow: number?,
	multiline: boolean?,
	-- A textarea's height.
	h: Length?,
	ref: Ref?,
	on_key: ((e: KeyEvent) -> boolean?)?,
	on_focus: Handler?,
	on_blur: Handler?,
	-- Shown focused, for specimens.
	preview: ("focus" | "hover")?,
}

local SIZE: { [string]: { text: string, icon: number } } = {
	sm = { text = "$font.size.sm", icon = 12 },
	md = { text = "$font.size.md", icon = 16 },
	lg = { text = "$font.size.lg", icon = 16 },
}

local field = ui.component(function(props: Props): Node
	local size = props.size or "md"
	local inner = SIZE[size]
	-- The editor's focus, which the frame shows (CSS's :focus-within).
	local focused = ui.use_state(props.preview ~= nil)
	local function focus(): boolean
		return focused:get()
	end
	local function error_text(): string
		local e = props.error
		if e == nil then
			return ""
		elseif type(e) == "string" then
			return e
		elseif type(e) == "function" then
			return e() or ""
		end
		return (e :: any):get() or ""
	end
	local function invalid(): boolean
		return error_text() ~= ""
	end
	local editor_props: InputProps = {
		id = props.id,
		ref = props.ref,
		value = props.value,
		label = props.label or "",
		placeholder = props.placeholder,
		placeholder_color = T.tertiary,
		select_on_focus = props.select_on_focus,
		grow = 1,
		shrink = 1,
		min_w = 0,
		h = if props.multiline then nil else "100%",
		h_full = props.multiline,
		px = 0,
		py = if props.multiline then "$zeron.space.8" else 0,
		bg = T.clear,
		border = 0,
		rounded = 0,
		font = if props.mono then T.mono else T.sans,
		text_size = inner.text,
		color = T.text,
		-- The frame shows focus; the editor itself draws no ring.
		focus = { border = 0 },
		wrap = props.multiline,
		-- Zeron's input fade (INPUT_FADE_BAND): 12 where the text runs past.
		fade = if props.multiline then { 12, 12 } else nil,
		fade_overflow = props.multiline,
		on_key = props.on_key,
		on_focus = function()
			focused:set(true)
			if props.on_focus then
				props.on_focus()
			end
		end,
		on_blur = function()
			focused:set(false)
			if props.on_blur then
				props.on_blur()
			end
		end,
	}
	local editor = if props.multiline then ui.textarea(editor_props) else ui.input(editor_props)
	local frame = ui.row {
		id = props.id and props.id .. "_frame",
		variants = recipes.field {
			size = size :: any,
			lines = if props.multiline then "many" else "one",
			focused = if props.preview ~= nil then true else focus,
			invalid = if props.error ~= nil then invalid else false,
		},
		h = if props.multiline then props.h or 96 else nil,
		w = props.w,
		w_full = props.w_full,
		grow = props.grow,
		disabled = props.disabled,
		props.icon and icon {
			name = props.icon,
			size = inner.icon,
			color = "currentColor",
			variants = recipes.field_icon { focused = focus },
		},
		editor,
		props.trailing,
	}
	if not props.label and not props.hint and props.error == nil then
		return frame
	end
	return ui.column {
		gap = "$zeron.space.6",
		w = props.w,
		w_full = props.w_full,
		grow = props.grow,
		props.label and txt.text { props.label, size = "sm", weight = "medium", color = T.secondary },
		frame,
		(props.hint or props.error ~= nil) and txt.text {
			function()
				local e = error_text()
				return if e ~= "" then e else props.hint or ""
			end,
			size = "xs",
			color = "inherit",
			variants = recipes.field_hint { invalid = invalid },
			hidden = function()
				return error_text() == "" and props.hint == nil
			end,
		},
	}
end)

local M = {}
M.input = ui.component(function(props: Props): Node
	return field(props)
end)
M.textarea = ui.component(function(props: Props): Node
	local p = table.clone(props)
	p.multiline = true
	return field(p)
end)
return M
