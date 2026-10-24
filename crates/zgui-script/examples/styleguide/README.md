Zeron UI · styleguide
=====================

Zeron's UI kit and styleguide in Luau on zgui-script: a workbench whose
shell is built from the kit it shows. Phase 1 of Zeron's rewrite onto zgui.

```sh
cargo run --release -p zgui-script --example styleguide
```

Edit anything under this directory and save: the window reloads in place and
keeps its state. `zeron-dark.json` and `zeron-light.json` restyle live without
a reload. In a debug build (or with `ZGUI_CHECK=1`) every save is type checked
with luau-lsp and errors show in the window; `zgui check
crates/zgui-script/examples/styleguide` does the same from the shell.

Keys: ⌘K opens a palette that jumps to a page by name; ⌘1 to ⌘9 and ⌘0
jump to a page, ⌘[ and ⌘] go back and forward, ⌘I toggles the inspector,
⌘\ the sidebar; ⌃⌥⌘I zgui's layout inspector. The appearance card's
reduced-motion switch
collapses every fade and slide to 1 ms and holds loops (spinners, pulses,
breathing bars) still, as Zeron does.

The Zeron app
-------------

`app_zeron.luau` is Zeron rebuilt on the kit. It is the app itself, meant to
grow toward Zeron's, not a specimen. Its modules are in `zeron/`, and it
lives beside the kit because a script's modules come from its own directory.

```sh
STYLEGUIDE_APP=zeron cargo run --release -p zgui-script --example styleguide
```

- **Routes.** The chat (agents and threads) and the pull requests' board
  (PR #866). Each lays out its columns under Zeron's panel policy
  (`kit/panel_shell`, PRs #677 and #914):
  - The sidebar is shared by both routes.
  - Each route has a right pane of its own; the chat also has Files.
  - A route keeps its pane and divider while it is away and arrives at rest
    (`panel_shell.rest`).
  - Back and forward (⌘[ ⌘]) step through where the window has been.
- **The right pane.** Tabs (the changes, Wing's panes, a preview, a terminal,
  notes) open from ⌘K or the strip's +.
  - ⌘W closes the active tab only while the pane is on screen. The next tab
    takes over, or the one before it at the end.
  - With no tab left, the picker shows.
  - On the board, ⌘W closes the pull request's pane.
- **Layouts.** Four. Switch with ⌘⇧L (which cycles through them), ⌘K or
  Settings.
  - **Classic:** Zeron's unified titlebar over flush columns, with the right
    pane beside the chat.
  - **Glass:** the same columns in Rex's material. The sidebar sits on the
    window's glass and carries the window's controls beside the traffic
    lights. Every content column is a well inset 8 into the glass, a dark
    hairline outside and a light one inside (`zeron.well.*`).
  - **Tabs:** Tern's and Rex's. There is no sidebar and no right pane. Tabs
    sit in the topbar beside the traffic lights. A tab is a space: a named
    group of panes, showing its panes' glyphs and its name (a double click or
    its menu renames it; the sidebar lists the sessions, so tabs never
    repeat them). Each tab is a tree of panes
    (`kit/panes`), every pane a well with its own header (what it shows,
    split, zoom, close) and one surface: a session's chat, a terminal, the
    changes, a browser, the files, the board or a pull request, notes. A new
    pane shows a picker of those and the recent sessions.
    - ⌘T opens a new tab, ⌘D splits right and ⌘⇧D splits down.
    - ⌘W closes the focused pane, and with the last pane its tab.
    - ⌘⇧↩ zooms the focused pane, and ⌘⌥ with an arrow moves the focus.
    - ⌘1–9 jump to a tab, and ⌘⇧[ ⌘⇧] step through the tabs.
  - **Tabs and sidebar:** the same, with the sessions beside them under the
    panel policy. A session already shown comes forward, and another opens
    in the focused picker or a tab of its own. A pull request opens beside
    the board.
- **Over it.** ⌘K's palette (Zeron's: All, Threads, Commands and Files on
  ⌘1–4), ⌘, the settings page (Esc returns), ⌘\\ the sidebar, ⌘⇧E Files. +
  opens the new-session canvas; sending from it starts a session.
- **The sidebar** is Zeron's: the project filter and the view menu, then
  Pinned, the user's sections, Sessions (or a group per project) and
  Archived, in compact or two-line rows.

`tests/zeron_app.rs` walks the layouts, the routes, the tabs, the panes and the
history. `zeron/PARITY.md` tracks what old Zeron does and where this app
stands.

The Apps page also opens `app_palette.luau` (a frameless frosted @ picker) and
`app_settings.luau` (sections, the appearance cards and swatches, account
meters), each in a window shaped for it.

Structure
---------

```
app.luau         the shell: sidebar, canvas, inspector, keys, toasts
state.luau       the pages, the canvas's settings, the density and zoom overrides
theme.luau       the app's tokens (zeron.*) and the token names the kit uses
zeron-dark.json  Zeron's dark theme on zgui's tokens
zeron-light.json Zeron's light theme
source.json      which Zeron commit and files the values came from
icons/           Zeron's icon set (Solar Icons Linear, CC BY 4.0, 480 Design;
                 Zeron Icons for files, branches and arrows; harness marks)
kit/             one module per component (below), kit/init.luau re-exports them
pages/           colour, typography, metrics, motion, patterns, parity, buttons,
                 inputs, chips, overlays, lists, transcript, agent, changes, workspace,
                 panels, apps, shell, settings, composer
shell/           sidebar, toolbar, canvas, inspector, specimen (headers, grids)
lib/colour.luau  compositing and WCAG contrast on `#rrggbbaa`
```

Every component is a thin `ui.component` over a closed props table whose
`export type Props` luau-lsp checks, its look a `ui.variants` recipe. Its
states (disabled, loading, selected, error, working…) are props or derived
from state and choose the recipe's variants in Rust. Hover, press and focus
are the engine's pseudo-states, and what shows under a row's pointer (a
close button, a time turning into Archive) is the engine's `group_hover`
under a `hover_group`: none of it runs the script.

The design system
-----------------

- **Concentric corners.** A box inset inside a rounded one rounds at what
  is left, so both curves share a centre and the gap between them stays
  even: `T.concentric(outer, inset, border?)` is the token for
  `outer − inset − border` (on the scale, or an error) and
  `T.inset_radius` the number, for arithmetic. A menu row 4 in from the
  card's 12 inside its hairline is `T.concentric(12, 4, 1)`, 7; the
  queue tray's rows are 11 in its 16 and their 24 controls 7; the compact
  picker's rows 7 and their stars 3; an attachment's fill 7 inside the
  tile's 8 hairline; the question panel's options 9 inside the pill's 26.
  Derive an inner radius this way rather than picking one.
- **Tokens.** `theme.luau` declares the app's tokens (`zeron.*`: the colour
  roles, the spacing scale `zeron.space.*`, the radii `zeron.radius.*`,
  negative margins `zeron.pull.*`, the titlebar's metrics, the motion
  durations, shadows) for every theme; the theme files set the values.
  `T.space(n)`, `T.radius(n)` and `T.pull(n)` name a kit metric's token and
  fail if it is off the scale, so a constant used in arithmetic stays one
  number. Both apps run `ui.theme.strict("warn")`: a literal colour,
  spacing, radius, type size, weight or shadow outside the theme warns.
  `ui.raw(value, "why")` marks the few deliberate exceptions (measured
  geometry, a stand-in image, a contrast check's computed colour). The
  design lint reports 0 warnings over every page and the four layouts
  (`LINT=1 cargo run --release -p zgui-script --example zeron_bench`).
- **Recipes.** `kit/recipes.luau` holds every component's `ui.variants`
  recipe, as zterm does; the component passes its props through by axis
  name, and its prop types come from the recipe (`VariantOption<typeof(
  recipes.button), "size">`), so a recipe's options and the props cannot
  drift apart.
- **One implementation.** The app's sidebar (`session_sidebar`), ⌘K
  (`command_palette`), the topbar's spaces (`space_tabs`), the settings page
  (`settings_page`), the glass layout's wells and headers (`well`) and the
  session card (`session_card`) are kit components. `zeron/` gives them its
  data, state and actions; the workbench pages render the same components
  over sample data (Lists, Overlays, Panes, Settings, Shell, Panels).

Patterns, the pieces Zeron's screens are made of (`pages/patterns.luau`
shows them; `pages/parity.luau` puts Zeron's numbers and source lines next
to each):

| Module | |
| --- | --- |
| `frost` | the floating surface (popover::surface_bg): a faint tint under a blur of 16 and no shadow when frosted, the overlay with the large shadow when opaque (`zeron.frost`, `zeron.blur`, `zeron.float_shadow`, set by `kit/look`); hairline, radius 12, inset 4 |
| `scroll` | edge fades (24 unless set), only where content runs past; no scrollbar, as Zeron (`thumb = true` turns on zgui's overlay scrollbar); `runway` reserves space after the content and `on_measure` reports the view and content sizes, for the sent-turn hold |
| `chrome` | pane toolbars: 38 high, 24-point controls and tabs at radius 6, a 24-high field |
| `loaders` | the 3×3 gradient spinner, the 2×3 mini spinner, skeleton bars |
| `pill` | the running pill: 16 high, pulsing dot, mono count capped at 99+ |
| `glass` | Wing's glass (zterm): the active tint sliding between rows or tabs, the hover glass washing in, the press give |

Components:

| Module | |
| --- | --- |
| `button`, `icon_button` | ghost, primary (Zeron's solid neutral), secondary, danger at 28/32/36 and radius 8, a `ui.variants` recipe (tone, size, square, pill, ring, on); icon buttons 24/28 at radius 6; icon, trailing, loading, selected |
| `segmented` | options in a well, the pill slides with `layout_id`; ← → move |
| `input` | input and textarea in Zeron's frame: label, hint, error, icon, trailing |
| `checkbox`, `toggle` | solid when on; the row is the hit area |
| `chip`, `badge` | six tones by soft/outline/solid; filter and dismissible chips |
| `avatar` | initials or a mark, with a status dot; `status_dot` alone |
| `tooltip` | after 500 ms, at once while one just closed; laid out with its trigger |
| `menu` | items with icon, shortcut, check, detail, a note line, faded items; `rows = "popover"` for popover.rs menu_row's 33-high rows; ↑ ↓ Home End Enter Esc; Zeron's enter and exit at every opening |
| `popover`, `dialog` | Zeron's card and dialog over the engine's popover and modal; each opening plays the entrance (`enter`), and a popover leaves toward its trigger over 100 ms (`exit`, `popover.enter`/`exit`) |
| `lightbox` | the image viewer: one for the window (`lightbox.open(image)`, `lightbox.host()` at the root), the image fitted to 90% × 85% over the scrim with its name, a click zooming to its pixels and back, the wheel panning, Escape or the scrim closing |
| `toast` | `toast.push {}` from anywhere; `toast.host()` once in the root; sonner's: 356 wide, 24 in, held under the pointer, swiped away |
| `row` | list and sidebar rows; rows in a `group` hand the selection pill to each other |
| `tabs` | underline or pills, counts, closable |
| `scroll` | a scroll area with Zeron's edge fades, and zgui's overlay scrollbar when asked |
| `divider`, `kbd`, `text`, `icon`, `motion` | hairlines, key caps, the type scale, icons, curves and durations |
| `tabstrip`, `agent_row` | zterm's 28-high glass tabs, and the agents sidebar row with its status mark |
| `palette`, `hints`, `empty` | the command palette and @ picker, a footer of key hints, an empty pane |
| `transcript` | the conversation's pieces: user bubble, prose and headings, code block, inline code, quote, tool call, working trailer, message rail, turn actions |
| `dictation` | the 28-point mic morphing to the accent stop plate, the 32-high waveform track, the status line |
| `context_usage` | the 16-point ring and percentage chip, the context window card |
| `tray` | the frosted tray behind the composer: the todo list with its header and glyphs, queued messages with handle and actions |
| `diff` | file rows with counts and the fold, diff lines with rail, gutters and marker, hunk headers |
| `roll` | roll text: only the changed glyphs roll, 550 ms staggered |
| `message_badge` | the 24-high reference pill and its hover card |
| `file_tree` | the files tree: rows 27, indent guides, folder chevrons, git status colours |
| `pr` | pull request groups, rows and the breathing skeleton |
| `attachments` | composer tiles with their remove button, inline chips with an icon well, transcript thumbnails |
| `comment` | the add button, comment cards (edit and remove under the pointer) and the draft card (⌘⏎ posts, Escape drops) |
| `account` | usage meter lines, the update strip (lit while it can act), "Star on GitHub", the connection pill, an account row; `identity` and `menu_action` say what the footer shows as the workspace syncs |
| `history` | the commit table with its lane graph on a canvas, ref badges, the search field and load-more pill |
| `floating_tabs` | the frosted pill of equal segments with a sliding glass thumb (PR detail's Summary / Code / Activity) |
| `shortcut` | keyboard shortcut rows and the key chip with its recording state |
| `browser` | the browser pane's toolbar and address field, 112-wide tab chips, the empty state |
| `actions_pill` | the titlebar's project actions split pill and its states |
| `pr.status_chip`, `pr.badge` | PR status chips by tone, the sidebar / composer PR badge |
| `layout`, `panes` | Wing's split workspace: the pane tree (splits, ratios, frames as percentages plus points), cards placed absolutely that ease on a change of structure, dividers that drag the split, the grip, drops at a pane's nearest edge, zoom |
| `recipes` | every component's `ui.variants` recipe, and `wash` (a rest fill and a hover wash, for rows without a recipe of their own) |
| `session_sidebar` | the app's sidebar, as Zeron's: the project filter and the view menu (…), then one virtual list (`ui.list`) of Pinned, the user's sections (… on hover: archive all, delete), Sessions or a group per project (its monogram, + on hover), Archived (ten, then 25 at a time); compact 29 rows or two-line 45 to 63; Organize by device, Sort, rename in place, drag to pin, reorder and file, ⌘1–⌘9 hints, subagent pills, remote glyphs, hover cards, folding eased by the list; the notices over the footer; the footer's account menu (opening up, its sync rows), voice, pull requests and settings |
| `project_icon` | a project's monogram: its initial in mono 9 on a 13 tile, in one of eight tones its name keeps, lit under its row's pointer |
| `project_picker` | the sidebar's space switcher: the trigger, and a searchable card ("Search projects…", rows 32, "New project" pinned; rename and remove on a secondary click) |
| `disclosure` | a collapsible's chevron: right while shut, a quarter turn toward where its content opens when open (`opens`: down, or up for a tray that rises), over the fold |
| `command_palette` | the app's ⌘K: All, Threads, Commands and Files on ⌘1–4, sections, ↑ ↓ ↵ Esc, the scrim overlay |
| `space_tabs` | the tabs layouts' topbar: spaces as Wing's tabs (their panes' glyphs on 20 tiles, "+n" past three, the active glass sliding), rename in place, close under the pointer, drag to reorder; a pane dragged by its grip moves into a space, or onto the bar's end becomes one, + |
| `settings_page` | the app's settings: the sections down the left and each section's cards |
| `well`, `session_card` | the glass layout's well and its header, the split glyph; the session card over a conversation |
| `wash` | the hover of anything listed: the list's wash under the pointer, instant, in the engine |
| `tabbar` | zimmer's title-bar tabs after Dia: 30 in a 42 bar, 200 → 96, top corners 10, the chosen tab in the canvas colour, open/close 240 ms emphasized |
| `wing_panes` | Wing's zterm panes as his demos show them: the editor, the Hacker News reader, notes, the Claude Code pane |
| `right_panel` | the right panel's tab strip and surfaces (the columns themselves are `panel_shell`'s) |
| `panel_layout` | Zeron's panel policy, pure: the fit with least-recent eviction, the equal content split, the panel curve and its timing, the mask rule for content widths |
| `panel_shell` | the columns under that policy: sidebar, conversation, right pane, Files; seams that drag and reset on a double click, promotion of hidden columns, takeover, direct window resizing |
| `titlebar` | Zeron's unified titlebar: the full-width drag band, the window controls at 88, the gliding identity, actions, the pane's header strip, the right-edge anchors; its 24 controls and 28 buttons; the mirrored pane glyph and the session card glyph |
| `activity` | a turn's tool calls as Zeron's tree: the 26 header with its chevron centred on the trunk, 32 rows hung off the 1-point trunk, connectors drawn by length as rows arrive (live groups from a state), a running call's spinner popping into its icon, the summary rolling by its parts and a light sweeping it while the turn works (a masked copy the engine slides), the 140 ms fold on height and opacity; a row with a call, output, diff, counts or images opens under itself (mono 12 lines 18 high, 24 then "… N more lines", the image strip 220 high), its box built the first time it opens; all in the engine |
| `appearance` | the System / Light / Dark cards with their miniatures, accent swatches |
| `settings` | Zeron's preferences page: header, sections, cards, rows, the large switch, select, option cards |
| `notice`, `jump` | the warning/error chip; the "Scroll to bottom" pill |
| `composer` | Zeron's composer: the frosted pill at 26 (22 docked), expanded and compact rows, attach · model chip · mic · send/queue/stop, the attachment strip, the queue tray and error notice above, the question panel, the session footer; the draft grows its text area (`auto_height`) from 56 to 240, the pill easing over 180 ms; `references` opens the completion menus, the references it writes showing as chips that delete whole (`chips`); `compact = "auto"` folds it into the one row while the draft fits (`fits`, measured by the engine); ⌘⏎ on an empty draft sends the latest queued message; `comments` shows the staged review comments' badge; `model_picker` wraps the chip in its card |
| `completion` | the composer's @ / $ menus (composer.rs, popover.rs completion_card): the pill's width 6 above it, radius 12 inset 4, at most 320; rows 30, 2 apart, at 7 (16 icon, the label at 13 medium with the typed run lit, the detail at 12); prefix matches before inner ones; ↑↓ wrap, ⏎ or Tab pick, Esc dismisses until the token changes; empty states as Zeron says them; rises in over 140 ms; `ui.list` rows, edges fading |
| `own_turn` | the sent-turn hold, Zeron's overscroll: a runway reserved under a fresh prompt so the view scrolls past its content, the prompt gliding to 10 under the top over ~230 ms, the reply using the runway up, then the bottom pin; no rubber band (Zeron removed its 24 of scroll room) |
| `effort_slider` | the reasoning slider: a 28 rail of light glass, the 44×32 white thumb overhanging by 2, stops and pointer on the 22 centre inset, the accent fill to 14 past the centre, 200 ms glides, the drag, fast mode's halo and band of light |
| `compact_picker` | the compact model picker: the 256 card, the 48 header (effort title rolling, model name, the leaning chevron, the fast bolt), the slider, 26 option rows with their choices beside them; the models page with the provider strip, search and 32 rows (brand mark, name, star), seven before it scrolls; pages swap as the card resizes over 200 ms; ↑↓ ⏎ Tab ← → Home End F |

Tests: `cargo test --release -p zgui-script --test styleguide` walks every
page, drives the controls, menus, dialogs, toasts and composer states, and
holds the idle hot path to zero script calls and no frames.
`STYLEGUIDE_SNAPSHOT=/tmp/sg` writes software captures of each step (the
headless text measurer is approximate, so some labels clip there and not in
the window).

Themes and the accent
---------------------

`themes/generate.py` reads the seeds of every built-in theme in comet's
`crates/theme/src/builtins.rs` (Zeron, VS Code Default, Catppuccin, Tokyo
Night, Dracula, GitHub, Ayu, Gruvbox, Rosé Pine, Nord, One Dark Pro, Atom One
Dark, Night Owl, Winter is Coming, Palenight, SynthWave '84, Shades of Purple,
Cobalt2, Andromeda: 30 variants) and derives the roles as `variant()` and
`AccentRoles::derive` do, writing one zgui theme per variant into `themes/`
and `kit/theme_list.luau` for the picker. The two Zeron files at the root
stay hand-curated. The toolbar's theme menu lists the families; the
dark/light toggle moves to the family's sibling variant. The accent picker
also holds the material, the theme's own (frosted for Zeron's themes, opaque for the rest), Frosted or Opaque, as a theme scope mapping every surface as `theme.rs` does (`kit/look`: the window's glass, panels, wells, frost, inputs), with the double border (`zeron.rim.*`, `recipes.rim`: a hairline outside, a lit rim inside, per kind and mode, switchable); and holds Zeron's seven presets (Zeron, Orange, Amber, Green, Cyan, Blue, Pink,
each a dark and a light colour) and "Theme"; a preset is applied as a theme
scope on the window with the derived tokens (`accent.hover`, `accent.text`,
`selection`, `pressed`, the washes, the code wash, the diff hunk).

Panels and panes
----------------

Panels follow Zeron's layout policy (`shell/panel_layout.rs`, PRs #677 and
#914): `kit/panel_layout.luau` is the policy, pure; `kit/panel_shell.luau`
the columns under it. Up to four columns run the window's full height: the
sidebar and Files are tools that keep their own widths (256 and 286 by
default, 242 to 400 and 220 to 440); the conversation and the right pane
are content and split what the tools leave equally (the chat keeps 300, the
pane 360).

- Opening or closing a column re-splits the content; a dragged divider holds
  until then; double-clicking a seam resets it (a tool's to its default
  width) and re-splits.
- A window too narrow for every open column's minimum hides the least
  recently opened (in takeover the pane goes last). Toggling a hidden column
  brings it back, ranked most recent, and closes it only when it still
  cannot return.
- Columns ease on the dialog entrance's curve (`ease`), 180 ms up to the
  sidebar's width, up to 240 ms for wider moves, always from what they
  paint, so a reversal never jumps. A column's content lays out at its
  destination as it opens and keeps its layout as it closes: the right pane
  and Files are anchored to their right edge, and the column masks them.
- Expand gives the pane the conversation's room; the conversation keeps its
  layout beneath. Closing the pane leaves takeover.
- Resizing the window or dragging a seam applies at once.

The workbench itself runs on it (the pages tree as sidebar, the canvas as
conversation, the inspector in Files' place), as do the Zeron app and
the Panels page, whose frame can be narrowed to watch columns leave and
return. Wing's zterm splits a tab into a tree of panes with dividers and
drops; that is `kit.panes` and the Panes page, for the terminal
multiplexer, under the same philosophy: panes along an axis share it
equally (gaps counted, so three are true thirds), a dragged divider holds
until the next split, close or move, a double click shares equally again,
structure changes ease on the panel curve, the area resizing applies at
once, and an area too small for every pane's 160 hides the least recently
focused, which come back when focused.

Wash
----

**Wash** is the hover of anything listed, as Zeron's and the system's are:
the item under the pointer shows the list's wash at once, the selected one
excepted; no slide, no fade and no script. A list scopes the wash's colour
(`zeron.list.wash`: the glass hover in the sidebar, the menu hover in a
menu) to its rows; each row paints it from a layer behind its content that
`group_hover` shows, whatever recipe the row carries.

`kit/wash.luau`: `wash.list { group = …, color = … }` is the container (a
column, a strip with `direction = "row"`, a grid with `flex_wrap`);
`wash.item(group, props, selected?)` makes any item's props a member;
`wash.maybe` does so only when the caller gave a group (PR rows, diff
headers); `wash.layer(selected, radius)` is the layer alone, for rows built
by hand (tabs, segmented controls, `kit.row`, `agent_row`).
`list_rows_wash_under_the_pointer_without_script` checks the hovered row
washes, the one before it no longer does, and no script ran.

Labels on fills
---------------

A label set on a fill reads at 4.5:1 or more, in every state, in every theme
and accent. Each status colour has a plate in every theme
(`zeron.<danger|warning|success|info>.strong`, `.hover`, `.pressed`, and
the label `.text`): the colour moved away from its label just far enough,
hue kept. Danger and info carry white, as Zeron's destructive fill does
(dark: #f87171 becomes #ba5555). The generator also lifts body text that
falls under 4.5:1 on the strongest control wash, and caps the solid's
hover and pressed steps, as Zeron's `harden_model_foreground` does. The
Colour page's "Labels on fills" lists every pair with its ratio, and
`labels_read_on_their_fills_everywhere` walks all themes and accents and
fails under 4.5:1. A new fill with a label belongs in that list
(`pages/colour_labels.luau`).

Titlebar
--------

`kit/titlebar.luau` is Zeron's unified titlebar: one 38-high band across
the window over the columns, content 4 below centre on the traffic lights'
line, no bottom border. The whole band moves the window (and a double click
zooms it); its buttons keep their clicks. The window controls sit at 88
beside macOS's traffic lights (12 elsewhere; the host shares the platform):
the 24 sidebar toggle with its morphing glyph, then Back and Forward 2
apart. A title, when there is one, starts 16 past the sidebar or 12 past the
controls and glides with the sidebar. 28-point actions end the content's
stretch, the right pane's header strip rides over the pane as wide as it,
and the right-edge anchors (28 each, 4 apart, 6 from the edge) sit in a
slot as wide as the tool column beneath. In the workbench: the sidebar
toggle, Back and Forward through the pages visited (⌘[ ⌘]), the appearance
card (theme, variant, material, density, reduced motion, accent) on the
palette button, and the inspector's toggle at the right edge.

Tokens
------

Zeron's roles on zgui's standard tokens. Values are the ones Zeron's theme
crate derives for its `zeron-dark` and `zeron-light` variants at the commit in
`source.json`.

| Zeron role | zgui token | dark | light |
| --- | --- | --- | --- |
| background | `background` | `#060606` | `#ffffff` |
| terminal.background | `surface.sunken` | `#090909` | `#fafafa` |
| shell | `surface.base` | `#0d0d0d` | `#f3f3f5` |
| raised | `surface.raised` | `#343438` | `#ededf0` |
| overlay | `surface.overlay` | `#1b1b1c` | `#ffffff` |
| panel_bg (editor host, files, right panel) | `zeron.panel` | background at 40% over the glass | |
| card, dialog | `zeron.card`, `zeron.dialog` | `#0e0e0e`, `#151516` | `#ffffff`, `#fefefe` |
| text, text_muted, text_faint | `text.primary/secondary/tertiary` | `#e8e8ea #a9a9ae #85858a` | `#303035 #62626a #797981` |
| (text at 38%) | `text.disabled` | `#e8e8ea61` | `#30303561` |
| border, border_strong | `border`, `border.strong` | white 10%, 18% | black 12%, 22% |
| (hairline at 6%) | `border.subtle` | white 6% | black 7% |
| hover, active | `hover`, `pressed` | white 11%, accent 18% | black 6%, accent 10% |
| card_selected_bg, accent.selection | `selection.item`, `selection` | wash 11%, accent 35% | wash 6%, accent 24% |
| accent.primary, glyph light, accent.on | `accent`, `accent.hover`, `accent.text` | `#8b7cf6 #aba1f9 #000000` | `#5b43e8 #7965ec #ffffff` |
| danger, warning, success | the same | `#f87171 #facc15 #34d399` | `#dc2626 #a16207 #15803d` |
| (ANSI blue) | `info` | `#60a5fa` | `#2563eb` |
| *_muted | `zeron.danger/warning/success.muted` | mixed 25–28% to text | |
| border_strong | `focus.ring` | | |
| glass() | `glass.tint` | shell at 80% | |
| composer_surface_border | `zeron.input.border` | `#bdc7d117` | `#4352601a` |
| input | `input.bg` | raised at 72% | white |
| solid, on_solid | `zeron.solid`, `zeron.on_solid` | `#ebebef`, black | `#232328`, white |
| ink(a) | `zeron.ink.1..6` | white at 4/6/8/11/16/22% | black |
| diff_add/delete/hunk, line washes | `zeron.diff.add/delete/hunk`, `zeron.diff.add_wash/delete_wash` | success, danger, accent 8%, 5.5% | |
| code span, blockquote | `zeron.code.wash` (accent 22%), `zeron.accent_faint` (5%) | | |
| dictation plate, light glass | `zeron.accent.light` (accent → white 18%), `zeron.glass.light.top/bottom` | | |
| history lanes | `zeron.lane.1..6` | a palette at 72% saturation | |
| scrollbar thumb | `scrollbar.thumb` (.active) | text at 30% (55%) | |
| Geist, Geist Mono | `font.sans`, `font.mono` | | |
| 11 12 13 14 16 19 (10) | `font.size.xs…xxl` (`zeron.font.size.micro`) | | |
| CONTROL 6, PANEL 10, BUBBLE 16, inline code 4 | `radius.md lg xl sm` | | |
| CARD_RADIUS 12, MENU_ITEM_RADIUS 7, COMPOSER_RADIUS 26 | `zeron.radius.card/item/composer` | | |
| SPACE_XS…LG 4 8 12 16 | `space.1…4` (5…8 continue the scale) | | |
| PICKER_ROW_HEIGHT 32 | `control.height` (`zeron.control.sm/lg` 26, 38) | | |
| motion.rs | `motion.duration.fast/normal/slow` 140 180 320, `motion.ease.*`, `zeron.motion.*` (hover, menu_in/out, dialog_in, collapse, resize, glyph, resort, fade_in, tab_slide, scroll_glide, morph, roll) | | |

Zeron's HEAD has no named type scale; the one here names the sizes its
interface sets most (11 to 14 for the UI, 16 and 19 for headings) and
`markdown/render.rs`'s heading metrics. The accent is used as Zeron uses it:
status, selection, the working indicator; primary controls are the solid
neutral.

zgui gaps
---------

What was missing or awkward while building this; input to zgui's backlog and
the zlang/zasm rewrite.

- No focus-visible: a pointer click leaves the focus ring on. Rows, tabs and
  segmented options drop the ring and rely on their pill; buttons keep it.
- Pseudo-state styles (`hover`, `active`) switch instantly; Zeron eases hover
  over 150 ms. The kit takes the instant switch (variants chosen by state);
  eased transitions belong in the engine.
- `disabled` takes a condition or styles, not both; a button that is busy as
  well as disabled dims through a recipe axis (`dim`) of its own.
- `ui.menu_item` has a label only (no icon, shortcut, check or detail slot), so
  the kit's menu is a `ui.popover` with its own rows and keyboard handling.
- Fixed in zgui along the way: single-corner radii and per-axis gaps take
  tokens; `group_hover` under a `hover_group` styles a node by its row's
  hover (no `on_hover` writing state); `hidden = false` in a later layer
  shows what an earlier one hid; a component's positional children keep no
  hole where a child was `nil` or `false`; `VariantOption` types a prop from
  a recipe's axis.
- An empty `{}` for `theme = …` is read as an empty list and refused; a scope
  with nothing to override has to name the window's theme.
- A closed `popover`/`modal` keeps its layout (`find` and `bounds` see it), so
  tests read an open/closed text instead.
- Token values are not readable as numbers for arithmetic in props (no
  `calc`); density and zoom are whole override tables built from
  `ui.theme.get`, and the motion module reads its durations once per load.
- Text does not truncate inside a shrinking row without `shrink = 1, min_w =
  0, truncate = true` on each text; an `ellipsis` default would remove most of
  that boilerplate.
- An `absolute` node measures from the nearest `relative` ancestor anywhere
  up the tree (here the app root, for toasts), so every component that
  positions something inside itself has to be `relative`; a default of "the
  parent" would be less surprising.
- `h_full` on a child of a column measures against the whole column, siblings
  included, and overflows it; `grow = 1` with `min_h = 0, shrink = 1` is the
  working spelling. Children never shrink by default, so a fixed-height
  window needs `shrink = 1` down the whole chain.
- `ui.scroll` is 320 wide when nothing stretches it; a column's default
  `items = "start"` leaves it at that width inside a 232-wide panel.
- `self = "center"` on a node whose height changes while a press is in
  flight recentres it between pointer-down and pointer-up, and the click is
  lost (the composer page, choosing an option then a row). Centre with the
  parent's `items` instead.
- `gradient` stops take literal colours, not tokens.
- The software rasterizer (`zgui_desktop::raster`, used for headless
  snapshots) smears a backdrop blur past its box; the GPU path does not.
- Icons are 121 SVG files copied per example; a shared icon asset module
  across examples would be lighter.
- The software raster behind `STYLEGUIDE_SNAPSHOT` ignores fade masks: edge
  fades (`fade = …` on a scroll) show only on the GPU, in a window.
- Headless `TestApp` has no font shaper: text is measured at 0.6 em per
  grapheme, so snapshots clip letter-spaced and wide labels that the real
  renderer fits. Judge widths in a window, not in a snapshot.
- Not ported yet: the history header's drag-to-reorder columns, the image
  viewer's pinch and drag (it zooms on a click and pans with the wheel),
  the new-thread hero's feathered cutout around the composer (it fades out
  from its top through a mask instead).
- `Readable<T>` cannot be read (`get` takes `self: never`): a kit prop the
  component reads, not only binds, has to be a `State<T>`, so callers must
  own a state even for a constant.
- Canvas paints and gradient stops take literal colours; the kit resolves
  tokens with `ui.theme.get` at build time, so they miss a live theme change.
- A tray's bottom tucks under the composer by a negative top margin on the
  composer's wrapper; the composer's own props take no margins.
- Density and zoom scale tokens (type, control height, spacing). Pieces
  specified by Zeron in pixels (rows 27/36, the 28 mic, the 16 ring, the
  32 track) keep their sizes on purpose; only their text follows the zoom.
- `ui.each` lays its rows out about 8 points apart whatever `gap` says, so
  it cannot set glyphs side by side; roll text uses one presence per slot in
  a plain row instead.
- A node's intrinsic width comes from its widest text; a long caption under
  a specimen made its cell, and the `w_full` content above it, wider than
  the page. Captions that may run long must `wrap`.
- A focus style that changes a control's border width (`focus = { border = 0 }`
  on a bordered button) relays out between press and release, and the next
  click anywhere is lost. Keep the width and recolour instead. This was the
  swallowed click after choosing a composer option.
- A `popover`'s `on_mount` fires when the closed popover is built, not when
  it opens; an `el:focus()` there took the window's shortcuts (⌘K stopped
  opening the palette). The compact picker focuses its card from an effect
  on `open`, a frame later.
- `ui.scroll` has no overscroll of its own and the offset is clamped to the
  content, so a hold past the end needs real space: the kit's `runway`
  (Zeron: a tail reservation in its list). The glide is `anime` writing the
  offset state itself; `follow` then pins at the end.
- A `Binding` (`ui.loop`, `ui.tween`) cannot be read in a canvas `draw`, so
  an animated canvas needs a state fed by `anime`'s `onUpdate`; the slider's
  flowing band is an element on a looped `left` instead.
- A state as an `anime` target (`anime.animate(state, { value = … })`, which
  writes it without a script call per frame, as `zgui lint` asks) fails the
  type check; the call is cast to `any`.
- A column's `gap` is kept around children hidden by `ui.show` (they take no
  height, but the gaps on either side stay), so a list of hidden slots
  pushes what follows down by one gap each. The transcripts that hold a sent
  turn space their turns with `pt` and no gap.
- A node hidden by `ui.show` keeps its `ui.loop` bindings ticking, so a
  hidden animation still asks for frames; anything looping must leave the
  tree through `ui.presence` (the slider's fast-mode band and halo).
- No double-click event: the panel seams count two presses within 350 ms
  themselves. Nor can a script know whether the window is fullscreen, so the
  titlebar's controls stay at 88 where Zeron slides them to 12.
- The host has to tell scripts the platform (`host.shared("platform", …)`);
  nothing in the script API says which one it is.
- Building the node tree recurses once per level (`lower::build`), and a
  debug build's frames are large: the Panels page's window (a titlebar, a
  pane strip and its chips, inside the page, inside the workbench's
  columns) overflowed the test threads' 2 MiB stack. The styleguide tests
  run their bodies on a 32 MiB thread. An iterative build, or smaller
  frames, would lift that.
- Children never shrink unless told (`shrink = 1`): a row of tab chips
  inside a strip kept its full width and pushed the strip's expand button
  out from under the strip's clip, where a click reached the control
  behind it.
- `ui.modal` focuses its first focusable child as it opens, and without
  focus-visible a pointer-opened dialog shows that control's focus ring. The
  kit's checkbox rings its box (a 2-point halo) rather than the row, so the
  ring reads as a caret position, not a frame.
