-- Zeron's icons: Solar Icons (Linear, 1.5 stroke; CC BY 4.0, 480 Design)
-- with Zeron Icons (icons.zeron.sh, 1.75 stroke) for files, branches and
-- arrows, and the harness marks, as `icons/<name>.svg`; `tint` recolours.
export type Name =
	"action-build"
	| "action-configure"
	| "action-debug"
	| "action-lint"
	| "action-play"
	| "action-test"
	| "add-circle"
	| "alt-arrow-down"
	| "alt-arrow-left"
	| "alt-arrow-right"
	| "alt-arrow-up"
	| "antigravity-mark"
	| "archive-minimalistic"
	| "archive-up-minimalistic"
	| "arrow-down"
	| "arrow-left"
	| "arrow-right"
	| "arrow-up"
	| "arrow-up-right"
	| "bell"
	| "bot"
	| "calendar"
	| "chat-round-line"
	| "check"
	| "checklist"
	| "claude-mark"
	| "clock-circle"
	| "close"
	| "close-circle"
	| "cloud"
	| "collapse-arrows"
	| "command"
	| "copy"
	| "cursor-mark"
	| "danger-triangle"
	| "devin-mark"
	| "document"
	| "document-add"
	| "drag-handle"
	| "expand-arrows"
	| "eye"
	| "eye-closed"
	| "fast-tier"
	| "fast-tier-bold"
	| "file-code"
	| "file-data"
	| "file-image"
	| "file-markdown"
	| "file-style"
	| "file-tree"
	| "floppy-disk"
	| "fold-vertical"
	| "folder"
	| "folder-tree"
	| "folder-with-files"
	| "fork"
	| "gallery"
	| "git-branch"
	| "global"
	| "globe"
	| "grok-mark"
	| "hard-drive"
	| "hermes-mark"
	| "home"
	| "info-circle"
	| "key-minimalistic"
	| "keyboard"
	| "laptop"
	| "list"
	| "logout-2"
	| "magic-stick-3"
	| "magnifer"
	| "microphone"
	| "microphone-off"
	| "monitor"
	| "moon"
	| "more-horizontal"
	| "openai-mark"
	| "opencode-mark"
	| "palette"
	| "palette-search"
	| "paperclip"
	| "pen"
	| "pen-new-square"
	| "phone-hang-up"
	| "pi-mark"
	| "pin"
	| "plus"
	| "project-default"
	| "pull-request"
	| "pull-request-draft"
	| "queue-check"
	| "queue-close"
	| "queue-drag-handle"
	| "queue-paperclip"
	| "queue-send"
	| "refresh"
	| "remote-server"
	| "restart"
	| "return"
	| "settings"
	| "settings-minimalistic"
	| "smartphone"
	| "sort"
	| "sort-vertical"
	| "split-columns"
	| "star"
	| "star-bold"
	| "stop"
	| "sun"
	| "tag"
	| "terminal"
	| "trash-bin-minimalistic"
	| "tuning"
	| "volume-loud"
	| "widget"
	| "wifi-off"
	| "window-maximize"
	| "window-minimize"
	| "window-restore"
	| "worktree"
	| "wrap-text"
	| "zeron-logo"

export type Props = {
	name: Name,
	size: number?,
	color: Reactive<Color>?,
	id: string?,
	class: string?,
	opacity: Reactive<number>?,
	hidden: Reactive<boolean>?,
	on_mount: ((el: Element) -> ())?,
	-- A recipe's choice for the icon's own colour (`color` is then
	-- `"currentColor"`, the colour it chooses).
	variants: Variants?,
}

return function(props: Props): Node
	local size = props.size or 16
	return ui.svg {
		id = props.id,
		class = props.class,
		src = `icons/{props.name}.svg`,
		w = size,
		h = size,
		shrink = 0,
		tint = props.color or "$text.secondary",
		opacity = props.opacity,
		hidden = props.hidden,
		on_mount = props.on_mount,
		variants = props.variants,
	}
end
