-- Zeron's shortcuts (settings.rs ShortcutId, shell.rs apply_keymap): the
-- bindings at their defaults, each change kept across runs; what the
-- app's keys, the composer's and the editor's read.
local keymap = require("@kit/keymap")

local M = {}

M.map = keymap.new("zkeys", keymap.ZERON, ui.persist("zeron_keymap", {} :: { [string]: string }))

-- Whether `e` presses binding `id`.
function M.is(id: string, e: KeyEvent): boolean
	return keymap.is(M.map, id, e)
end

-- The binding `e` presses, if any.
function M.bound(e: KeyEvent): string?
	return keymap.bound(M.map, e)
end

-- Binding `id` as key caps, for a menu's or the palette's row.
function M.caps(id: string): { string }
	return keymap.caps(keymap.combo_now(M.map, id))
end

return M
