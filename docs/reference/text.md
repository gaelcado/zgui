# Text: text, rich, span

`ui.text` shows one string in one style; `ui.rich` shows runs of differently styled text (`ui.span`s) as one paragraph. Both follow state without calling the script when their text is a template, and call it again only for a function.

```luau
ui.text(content: Text | TextProps) -> Node
ui.rich(props: RichProps) -> Node
ui.span(content: Text | SpanProps) -> Span

type Text = string | number | (() -> TextValue)
type TextValue = (string | number | boolean)?
```

`ui.text "Hello"`, `ui.text(function() … end)` and `ui.text { "Hello", text_size = 18 }` are the same element: the table form takes the text first and [properties](properties.md) after it. A string child of a container (`ui.column { "Hello" }`) is a `ui.text` too.

## Text

| Form | Shows |
| --- | --- |
| `"Count: {count}"` | the string, with `{name}` replaced by the state named `name`, followed in Rust (no script call per change) |
| `"{{" "}}"` | literal braces; braces around anything but a name (`{not a name}`) are literal too |
| a number | it, as written (`3`, `2.5`) |
| a function | what it returns, run again when the state it reads changes: strings as they are, numbers and booleans as text, `nil` as nothing |

A template's `{name}` looks for, in order: the calling module's own `ui.state` or `ui.persist` of that key, the script's, then `ui.shared`. A list shows its items joined by ", ".

## Text options

Any [property](properties.md); these are the text ones (they also set the default for text inside a container that has them):

| Option | Type | Default | |
| --- | --- | --- | --- |
| `[1]` | `Text` | `""` | the text |
| `text_size` | `number` | `16` | points |
| `color` | `Color` | `"#e5edf7"` | |
| `weight` | `number` | `400` | 100 to 900 |
| `bold` | `boolean` | `false` | weight 700 |
| `italic` | `boolean` | `false` | |
| `font` | `string` | the host's | `"mono"` (or `"monospace"`), `"sans"`, `"serif"`, or a family name |
| `align` | `"start" \| "left" \| "center" \| "right"` | `"start"` | within the text's own box |
| `wrap` | `boolean` | `false` | wrap at the box's width |
| `lines` | `number` | none | at most this many lines |
| `truncate` | `boolean` | `false` | end an overflowing line with "…" |
| `line_height` | `number` | the font's | points |
| `letter_spacing` | `number` | `0` | points |
| `tabular` | `boolean` | `false` | tabular figures (OpenType `tnum`): every digit one width, for numbers that change in place |

## Rich text and spans

`ui.rich` takes its runs as array entries, and any [property](properties.md) for the paragraph (`wrap`, `text_size`, `color`… are the runs' defaults):

| Entry | |
| --- | --- |
| `ui.span { "text", … }` | a styled run |
| a string or function | a run in the paragraph's style (templates work) |
| a table, `{ "text", bold = true }` | a span's options in place: the same as `ui.span { … }` |

| Span option | Type | Default | |
| --- | --- | --- | --- |
| `[1]` | `Text` | `""` | the run's text: a template or a function follows state |
| `color` | `Color` | the paragraph's | |
| `bg` | `Color` | none | behind the run (a highlight) |
| `text_size` | `number` | the paragraph's | |
| `weight` | `number` | the paragraph's | `bold = true` is 700 |
| `bold`, `italic`, `underline`, `strike` | `boolean` | `false` | |
| `font` | `"mono"` | the paragraph's | |
| `on_click` | `Handler \| Action` | none | a click on the run (a link) |

## Example

```lua
local count = ui.state("count", 0)
local name = ui.state("name", "Ada")
return ui.column {
	p = 24,
	gap = 10,
	w = 360,
	ui.text { "Hello, {name}", text_size = 22, bold = true },
	ui.text {
		function()
			return if count:get() == 1 then "1 message" else `{count:get()} messages`
		end,
		color = "#8b95a5",
	},
	ui.text {
		"A long line wraps at the column's width instead of running out of it.",
		wrap = true,
	},
	ui.rich {
		wrap = true,
		"Press ",
		ui.span { "Add", bold = true },
		" or edit ",
		ui.span { "app.luau", font = "mono", bg = "#ffffff14" },
		" ",
		ui.span { "({count} so far)", color = "#5ea5ff", underline = true, on_click = ui.add(count) },
	},
}
```

## Gotchas

- A template names state by its key, not by its Luau variable: `"{count}"` shows `ui.state("count", …)` whatever the local is called. A name no state has is an error when the text is built.
- Text does not wrap by default, and a row does not shrink it: `wrap = true` (in a box with a width), or `shrink = 1, min_w = 0, truncate = true` in a row.
- Span options are plain values, read once: a state or function there is not followed (its value at build time is used). Only the run's text follows state. To restyle a run, build the paragraph in a function, or use two texts.
- A span's `font` only knows `"mono"`; any other family is ignored (`ui.text`'s `font` takes names).
- A span is used once: putting the same `ui.span` in two paragraphs is an error. Make a new one each time.
- `ui.text` and `ui.rich` take no children; extra array entries in `ui.text` are an error.
- A function's text is called again for each change it read; prefer a template for plain state, which costs no script call.
