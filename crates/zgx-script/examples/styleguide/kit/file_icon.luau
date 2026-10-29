-- A file's or folder's own icon (file_icons.rs): the Symbols theme's
-- colour artwork (kit/file_icon_theme), drawn as authored, never tinted.
-- The exact name wins (any case, the folder ignored), then the longest
-- compound extension ("component.test.tsx" before "tsx"), then the
-- generic document; a folder by its name, else the plain folder. In a
-- dark theme an icon with darker accents takes its lifted variant.
local THEME = require("./file_icon_theme")
local THEMES = require("./theme_list")

export type Props = {
	-- The path (or the name alone).
	path: string,
	folder: boolean?,
	size: number?,
	id: string?,
	opacity: Reactive<number>?,
}

local M = {}

local function basename(path: string): string
	return string.lower(string.match(path, "([^/\\]+)$") or path)
end

-- The icon's asset under icons/file-icons, without ".svg".
function M.asset(path: string, folder: boolean?): string
	local name = basename(path)
	if folder then
		return THEME.folders[name] or THEME.folder
	end
	local exact = THEME.names[name]
	if exact then
		return exact
	end
	-- Each extension from the first dot on, the longest first.
	local at = string.find(name, ".", 1, true)
	while at do
		local ext = string.sub(name, at + 1)
		if ext ~= "" and THEME.extensions[ext] then
			return THEME.extensions[ext]
		end
		at = string.find(name, ".", at + 1, true)
	end
	return THEME.file
end

-- Whether `path` has an icon of its own rather than the document.
function M.specific(path: string): boolean
	return M.asset(path) ~= THEME.file
end

local function dark(): boolean
	local id = ui.theme.current:get()
	for _, t in THEMES do
		if t.id == id then
			return t.kind == "dark"
		end
	end
	return true
end

-- The icon's source: a function of the theme when it has a dark variant.
function M.src(path: string, folder: boolean?): Reactive<string>
	local asset = M.asset(path, folder)
	if not THEME.dark[asset] then
		return `icons/file-icons/{asset}.svg`
	end
	return function(): string
		return if dark() then `icons/file-icons/dark/{asset}.svg` else `icons/file-icons/{asset}.svg`
	end
end

M.icon = function(props: Props): Node
	local size = props.size or 14
	return ui.svg {
		id = props.id,
		src = M.src(props.path, props.folder) :: any,
		w = size,
		h = size,
		shrink = 0,
		opacity = props.opacity,
	}
end

return M
