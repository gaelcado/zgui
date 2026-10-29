# Containers: column, row, div, overlay, grid, split, tabs, tree, data_grid, disclosure, accordion, separator

Boxes that lay out their children. Each takes one table: string keys are [properties](properties.md) and [events](events.md), array entries are children.

```luau
ui.column(props: ContainerProps?) -> Node
ui.row(props: ContainerProps?) -> Node
ui.div(props: ContainerProps?) -> Node
ui.overlay(props: ContainerProps?) -> Node
ui.grid(props: ContainerProps?) -> Node
ui.split(props: SplitProps) -> Node
ui.tabs(props: TabsProps) -> Node
ui.tree(props: TreeProps) -> Node
ui.data_grid(props: DataGridProps) -> Node
ui.disclosure(props: DisclosureProps) -> Node
ui.accordion(props: AccordionProps) -> Node
ui.section(props: SectionProps) -> Node
ui.separator(props: SeparatorProps?) -> Node
```

| Function | Lays its children out |
| --- | --- |
| `column` | top to bottom (a flex column) |
| `row` | left to right (a flex row) |
| `div` | as `column` does; `direction = "row"` turns it |
| `overlay` | all in one box, each aligned on its own: `items` across, `justify` down. With neither set they stretch to fill it, except along an axis they size themselves on. The overlay is as large as its largest child |
| `grid` | in equal columns and rows: a `div` with `grid = true`; `cols` and `rows` set the tracks, children take `col_span`, `row_span`, `col_start`, `row_start` |
| `split` | its two children side by side (`vertical = true`: one over the other) with a divider between them that drags to resize the first; the second fills the rest |

## Options

Children, and any [property](properties.md) and [event](events.md). What the containers start with:

| Option | Type | Default | |
| --- | --- | --- | --- |
| children (array entries) | `Child` | none | nodes, strings (text), functions (computed text), nested lists (flattened); `nil` and `false` are skipped |
| `items` | `"start" \| "center" \| "end" \| "baseline" \| "stretch"` | `"stretch"` | alignment across the main axis: as CSS's flexbox, children stretch across it unless they have a size of their own there; `"start"` keeps each as wide (or tall) as it is |
| `justify` | `"start" \| "center" \| "end" \| "between" \| "around" \| "evenly" \| "stretch"` | `"start"` (`overlay`: `"stretch"`) | distribution along it |
| `gap` | `number` | `0` | between children; `gap_x`, `gap_y` per axis |
| `grow`, `shrink` | `number` | `0`, `1` | as a child of a row or column: it gives way in one too small for its children, no further than its content needs |
| `cols`, `rows` | `number` | unset | `grid`'s equal tracks: `cols = 3` makes three columns |

## split

```lua
local width = ui.persist("sidebar", 280)
return ui.split {
	size = width,
	min = 200,
	max = 480,
	min_rest = 320,
	h_full = true,
	ui.column { p = 12, ui.text { "Sidebar" } },
	ui.column { p = 12, ui.text { "Content" } },
}
```

| Option | Type | Default | |
| --- | --- | --- | --- |
| `size` | `State<number>` | required | the first pane's width (height, `vertical`) in points, both ways: the divider writes it as it drags, and a `ui.persist` keeps the layout across launches |
| `vertical` | `boolean` | `false` | one pane over the other |
| `second` | `boolean` | `false` | `size` is the second pane's (an inspector at the right), and the first fills the rest |
| `min`, `max` | `number` | `0`, none | the first pane's bounds |
| `label` | `string` | `"Resize"` | what assistive technology calls the divider, which it reads as a splitter with its size and range, and can set |
| `min_rest` | `number` | `0` | the second pane's smallest size: the divider stops short of it, and a window too small for both shrinks the first pane, down to `min` |

The divider drags without running script (only the panes lay out again), shows a resize cursor, takes Tab focus (the arrows move it ten points, a hundred with Shift; Home and End take it to its ends), and goes back to where it started on a double click. Assistive technology sees a splitter.

## tabs

A strip of tabs and the panel of the chosen one, as WAI-ARIA's tabs and an editor's tab strip. One Tab stop: the arrows move among the tabs and the choice follows (mirrored right to left), Home and End go to the ends. A closable tab closes with its ×, Delete, or a middle click; closing the chosen one chooses its neighbour. Reorderable tabs drag along the strip, or move with ⌘ (Ctrl) Shift and an arrow. A strip too long for its width scrolls, and a menu at its end lists every tab.

```lua
local items = ui.state(
	"items",
	{
		{ id = "a", label = "README.md", closable = true },
		{ id = "b", label = "main.rs", closable = true },
	} :: { TabItem }
)
local chosen = ui.state("chosen", "a")
return ui.column {
	w = 400,
	h = 200,
	ui.tabs {
		label = "Files",
		items = items,
		value = chosen,
		reorderable = true,
		panel = function(id: string): Node
			return ui.text { `Editing {id}`, p = 12 }
		end,
	},
}
```

| Option | Type | Default | |
| --- | --- | --- | --- |
| `items` | `State<{ TabItem }>` | required | `{ id, label, closable? }` each, or a bare string (its own id), two-way: closing removes one, reordering moves it; other fields are kept as they are |
| `value` | `State<string>` | required | the chosen tab's id |
| `panel` | `(id: string) -> Node` | none | the chosen tab's panel, built as it is chosen; without one, `ui.tabs` is the strip alone, its panels the app's to place (a title bar's tabs) |
| `tab` | `(item, close: () -> ()) -> Node` | none | each tab as the app draws it (below) |
| `reorderable` | `boolean` | `false` | |
| `closable` | `boolean` | `false` | every tab closes, bare strings included |
| `on_close` | `(id: string) -> boolean?` | none | asked before a tab closes; `false` keeps it open (an editor asking to save first) |
| `on_move` | `(id: string, index: number) -> ()` | none | a tab moved, dragged or by the keys, to `index` (from 1): an app keeping the order, or tapping the trackpad (`ui.haptic("alignment")`) as tabs swap places |
| `preview` | `(item) -> Node` | none | what follows the pointer as a tab is dragged (the tab lifted), its corner kept where the tab was grabbed |
| `dragging` | `State<string>` | none | written the id of the tab being dragged, `""` once it is let go: for the tab to show where it was (dimmed under its preview) |
| `gap` | `number` | `2` | how far apart the tabs lie |
| `label` | `string` | `""` | the strip's accessible name |

A tab is chosen as it is pressed, as a browser's are. A press on a tab's × closes it without choosing it: a background tab closes and the choice stays where it was. A drag starts once the pointer moves 4 points, so a press on a button in a tab stays that button's click, and a drag's end is no click. The drag is the engine's (`on_drag`'s), carrying the tab's id: the tab takes its neighbours' places as the pointer passes their middles, while its `preview` follows the pointer. Its close is the app's to animate: `on_close` returning `false` keeps the tab while it fades, and the app closes it after.

`tab` draws the tabs: the node it returns for an item dresses the bare tab (its styles, children and handlers; its id finds it), and the strip keeps what makes it one: its role and selection, focus, the keys, the drag. It adds no look of its own (no padding, fill or ×): `close` closes the tab, asking `on_close` first. Tabs that can shrink (`shrink = 1` with a `min_w`) share the strip before it scrolls; `layout = "position"` slides them as they move, and a `layout_id` inside slides the chosen one's highlight from tab to tab.

```lua
local spaces = ui.state("spaces", { "s1", "s2" })
local names = ui.state("names", { s1 = "Release", s2 = "Shell" })
local current = ui.state("current", "s1")
return ui.tabs {
	label = "Spaces",
	items = spaces,
	value = current,
	closable = true,
	reorderable = true,
	gap = 3,
	on_move = function()
		ui.haptic("alignment")
	end,
	tab = function(id: string, close: () -> ())
		return ui.button {
			id = `space_{id}`,
			h = 28,
			px = 8,
			gap = 6,
			min_w = 88,
			max_w = 210,
			shrink = 1,
			layout = "position",
			bg = function(): Color
				return if current:get() == id then "$selection.item" else "#00000000"
			end,
			ui.text { function() return names:get()[id] end, truncate = true, shrink = 1, min_w = 0 },
			ui.button { focusable = false, w = 16, h = 16, p = 0, on_click = close, "×" },
		}
	end,
}
```

## tree

Items in a hierarchy, as WAI-ARIA's tree and Finder's sidebar. The tree is one Tab stop and keeps focus; its current item is its active descendant, which assistive technology reads with its level and its place among its siblings. Up and Down move; Right opens an item and then enters it, Left closes it and then goes to its parent (mirrored right to left); Home and End go to the ends; typing goes to the next item starting with it; Enter or a double click activates. A click chooses, and a click on the chevron opens and closes. The rows are virtual: a tree of thousands builds only what shows.

```lua
local items = ui.state(
	"items",
	{
		{ id = "src", label = "src", children = { { id = "main", label = "main.luau" } } },
		{ id = "docs", label = "docs", lazy = true },
	} :: { TreeNode }
)
local open = ui.state("open", {} :: { string })
local current = ui.state("current", nil :: string?)
return ui.column {
	h = 240,
	ui.tree {
		label = "Files",
		items = items,
		open = open,
		value = current,
		on_open = function(id: string)
			if id == "docs" then
				items:set_key({ 2, "children" }, { { id = "guide", label = "guide.md" } })
			end
		end,
	},
}
```

| Option | Type | Default | |
| --- | --- | --- | --- |
| `items` | `State<{ TreeNode }>` | required | `{ id, label?, children?, lazy? }` each; `lazy = true` without children shows "Loading…" until the app adds them |
| `open` | `State<{ string }>` | required | the open items' ids, both ways |
| `value` | `State<string?>` | required | the current item's id, both ways |
| `on_open` | `(id: string) -> ()` | none | an item opened: load its children now |
| `on_activate` | `(id: string) -> ()` | none | Enter or a double click |
| `row` | `(item, level: number) -> Node` | none | each row as the app draws it, from its item (the app's own table) and its level, 1 at the roots |
| `row_height` | `number` | `26` | every row's height |
| `open_on_click` | `boolean` | `false` | a press on a parent opens or closes it as it chooses it, as a file explorer's folders do; otherwise its chevron does |
| `selection` | `State<{ string }>` | none | the chosen items' ids, both ways, choosing several as a file explorer does: ⌘ (Ctrl) and a click adds an item or takes it away, Shift and a click chooses the visible rows from the anchor (⌘⇧ adds them), Shift and Up or Down extends; a plain click or move chooses the current item alone, as `value` written by the app does; Escape keeps only the current item; a plain press on the empty space below the rows chooses none (and no current item) |
| `label` | `string` | `""` | its accessible name |

`row` draws the rows: the node it returns dresses the bare row (its styles, children and handlers: a context menu, a field renaming it), which keeps its role, level, place, choice and expanded state, and the tree its keys (a field in a row keeps its own). The tree adds no indent, chevron or fill to it: the row lays them out from its level, and reads whether it is open or chosen from `open` and `value` (and `selection`). A row is drawn again as its item changes (its label, or another field of the app's table, as a file's status), and a row that drags (`on_drag`) is still chosen as it is pressed; with `open_on_click`, such a parent opens or closes as the press comes up without having dragged, and a press on one of several chosen chooses it alone only then, so its drag can carry them all.

## data_grid

Records in rows under a header of columns, as WAI-ARIA's grid and a spreadsheet's table. The grid is one Tab stop and keeps focus; its current cell is its active descendant, which assistive technology reads with its row and column (the grid's size counts the rows not built). The arrows move (mirrored right to left), Home and End go to the row's ends and, with ⌘ or Ctrl, the grid's; Page Up and Down go a page. Enter or F2 edits an editable cell, as typing over it does; Enter keeps the edit and moves down, Escape drops it, and Delete clears the cell. Enter on a cell that doesn't edit activates its row, as a double click does. Up from the first row reaches the header: Enter or Space sorts its column (ascending, descending, then as given), ⌘⇧ (Ctrl+Shift) with an arrow moves it, Alt with an arrow narrows or widens it. With the pointer, a header's click sorts, a drag moves its column, and its edge's drag resizes it (a double click there puts the width back). The rows are virtual: a grid of a hundred thousand builds only what shows.

```lua
local people = ui.state("people", {
	{ name = "Ada", age = 36 },
	{ name = "Grace", age = 85 },
	{ name = "Linus", age = 21 },
})
local columns = ui.state(
	"columns",
	{
		{ id = "name", title = "Name", width = 160, sortable = true, editable = true },
		{ id = "age", title = "Age", width = 80, sortable = true, editable = true, align = "end" },
	} :: { GridColumn }
)
local sort = ui.state("sort", nil :: GridSort?)
return ui.column {
	h = 240,
	ui.data_grid {
		label = "People",
		columns = columns,
		rows = people,
		sort = sort,
		on_activate = function(row: number)
			ui.toast { title = people:get()[row].name }
		end,
	},
}
```

Each cell shows its row's field named by the column's `id` (or what `cell` makes of it). ⌘C (Ctrl+C) copies as a spreadsheet does: the current cell, or the selected rows, as tab-separated text and an HTML table. The grid sorts `rows` itself (numbers by value, text without case); `row` in `value`, `on_edit` and `on_activate` is the record's index in `rows`, whatever the sort.

| Option | Type | Default | |
| --- | --- | --- | --- |
| `columns` | `{ GridColumn }` or a state of them | required | `{ id, title?, width?, min_width?, sortable?, editable?, align? }` each; `width` 120 unless set, `align = "end"` for numbers. A state is written as columns are resized and moved, the app's other fields kept |
| `rows` | `State<{ any }>` | required | the records |
| `sort` | `State<GridSort?>` | none | `{ column, descending? }`, both ways; nil shows `rows` as they are |
| `value` | `State<{ row: number, column: string }?>` | none | the current cell, both ways |
| `selection` | `State<{ number }>` | none | the selected rows, both ways: a click selects one, Shift (or Shift and an arrow) extends from the last, ⌘ (Ctrl) adds or takes one away, ⌘A (Ctrl+A) selects all |
| `cell` | `(value: any, column: string, record: any) -> string` | the value as text | a cell's text: `function(v, column) return if column == "price" then string.format("$%.2f", v) else tostring(v) end` |
| `on_edit` | `(row: number, column: string, text: string) -> ()` | none | an edit kept; without it the text is written into the record, a number staying a number |
| `on_activate` | `(row: number) -> ()` | none | Enter on a cell that doesn't edit, or a double click |
| `label` | `string` | `""` | its accessible name |

In Rust (`zgx-components`), `data_grid(label, columns, sort, current, GridSource::new(rows, cell).on_edit(…).on_activate(…))`: `cell(row, column)` gives each cell's text, and the app gives its rows in the order `sort` asks.

## disclosure, accordion, separator

`ui.disclosure { open = state, summary = "Advanced", … }` shows its children while `open`, as HTML's `<details>`: its summary is a button (Enter or Space toggles it) that says it is `expanded`, with a chevron that turns as it opens. `summary` is text or a node.

With `bare = true` the app draws it: the `summary` node dresses the bare summary button (its styles, children and handlers; its id finds it), which keeps its `expanded` state and its toggling by a click, Enter or Space, with no chevron, padding or wash of the disclosure's own. The children stay mounted and fold as the app has them follow `open`, a fold that animates:

```lua
local open = ui.state("open", false)
return ui.disclosure {
	open = open,
	bare = true,
	summary = ui.row { h = 30, gap = 6, items = "center", ui.text { "Ran 3 commands" } },
	ui.presence(function()
		return if open:get() then "rows" else nil
	end, function()
		return ui.column { ui.text { "cargo test" } }
	end, { layout = "height", layout_clip = true, enter = { opacity = { 0, 1 }, duration = 140 }, exit = { opacity = 0, duration = 140 } }),
}
```

`ui.accordion { open = state, ui.section { id = "ship", title = "Shipping", … }, … }` holds sections of which one at most is open: `open` is its `id`, or nil; opening one closes the one open. A section's children are built when it opens.

`ui.separator {}` is a line between groups across a menu or a list (`vertical = true`: down a toolbar), in the theme's subtle border colour and hidden from assistive technology.

```lua
local open = ui.state("open", false)
local section = ui.state("section", "ship" :: string?)
return ui.column {
	w = 320,
	gap = 8,
	ui.disclosure { open = open, summary = "Advanced", ui.text { "Hidden until opened" } },
	ui.separator {},
	ui.accordion {
		open = section,
		ui.section { id = "ship", title = "Shipping", ui.text { "By sea" } },
		ui.section { id = "pay", title = "Payment", ui.text { "By card" } },
	},
}
```

## Example

```lua
local selected = ui.state("selected", "Inbox")
local function item(name: string)
	return ui.button {
		w_full = true,
		bg = function()
			return if selected:get() == name then "#2f4058" else "#00000000"
		end,
		on_click = ui.set(selected, name),
		name,
	}
end
return ui.row {
	w_full = true,
	h_full = true,
	items = "stretch",
	ui.column { w = 180, p = 8, gap = 2, bg = "#161b22", item("Inbox"), item("Archive") },
	ui.column {
		grow = 1,
		p = 24,
		gap = 12,
		ui.text { "{selected}", text_size = 22, bold = true },
		ui.grid {
			cols = 3,
			gap = 8,
			ui.div { h = 60, rounded = 8, bg = "#232e40", col_span = 2 },
			ui.div { h = 60, rounded = 8, bg = "#232e40" },
		},
		-- A badge over a tile's top right corner.
		ui.overlay {
			items = "end",
			justify = "start",
			ui.div { w = 64, h = 64, rounded = 12, bg = "#5b8def" },
			ui.row {
				w = 18,
				h = 18,
				rounded = 9,
				bg = "#e5534b",
				items = "center",
				justify = "center",
				ui.text { "3", text_size = 11 },
			},
		},
	},
}
```

## Gotchas

- Children stretch across a column or row by default (`items = "stretch"`, as CSS): `items = "start"` keeps each as wide (or tall) as it is.
- Children shrink in a row too narrow for them (`shrink = 1`, as CSS), but a text no narrower than its longest word, and a box no narrower than its content needs. `shrink = 0` holds a child at its size; `min_w = 0` lets one shrink past its content (with `truncate = true` on text to end it with "…").
- Text does not wrap by default: `wrap = true` on the text, inside a box with a width.
- A percentage size inside a box sized by its content falls back to the content's size (`ZGX_LAYOUT_WARNINGS=1` reports it).
- `show`, `switch` and `presence` lay out as what they show, as if it stood in their place; `each` and `slot` are a box of their own that lays its rows out as its parent would. Absolute positioning searches for a `relative` ancestor, so mark the one you mean rather than relying on being its direct child ([properties](properties.md#position)).
- A container returned by a function is built once, when the function runs: to make a part of the tree follow state, use [`show`, `switch`, `each`](dynamic.md) or a function property.
