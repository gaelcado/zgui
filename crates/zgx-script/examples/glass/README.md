# Glass

Rex's glass material in the layout Dia, zimmer, Rex and Tern share. The
sidebar sits straight on the window's blur, and the content sits in wells
inset into that glass.

```sh
cargo run --release -p zgx-run -- crates/zgx-script/examples/glass
```

## The material

The difference from the styleguide's glass is measured from Rex
(superlogical.com/rex) beside Zeron:

- **Neutral glass.** `zgx.json` asks for `"glass": "plain"`: only the blur,
  with no desktop tint and no saturation boost. `glass.tint` lays a neutral
  grey over it, never a hue of the theme's, so the wallpaper reads through
  desaturated.
- **The chrome is light and the content is a well.** The sidebar has no
  fill of its own, so it is the window's glass and the brightest surface.
  The well (`shell.well`) is darker and translucent, and floats with a gap
  (`shell.gap`, 8) on every side: from the window's top, right and bottom
  edges, and from the sidebar.
- **A two-line edge.** A dark hairline outside (`border`, `shell.edge`) and
  a light one inside it (`inset_shadow`, `shell.inner`: an inset ring two
  points wide, whose outer point the border covers). A well that has lost
  the focus to the one beside it keeps a dimmer inner line
  (`shell.inner_dim`).

`glass-dark.json` and `glass-light.json` set those tokens. `theme.luau`
declares them with defaults in standard tokens, so any theme styles the
app.

## The layout

- **Titlebar.** The sidebar's controls sit beside the traffic lights (an
  inset titlebar, `shell.lights`): the sidebar toggle, back and forward,
  and new. Both the row and each well's header drag the window.
- **Sidebar.** A search field with its ⌘K hint, pinned favourites as tiles
  (Dia's, Arc's), and spaces of items: chats, documents, terminals, pages
  (Dia's tabs, zimmer's conversations, Rex's sessions). A space folds from
  its title. The chosen row is a lighter pane of glass with a hairline of
  its own.
- **Wells.** The header holds the item's icon, title and time, then split
  and more. The body follows the item's kind: a chat with its composer, a
  document, a terminal, a page. ⌘D splits the content into two wells of
  equal share, a gap apart. A sidebar click opens in the focused well, and
  ⌘W closes the second.
- **Sidebar shut.** ⌘\ eases the sidebar to nothing over 220 ms. The first
  well's header then makes room for the traffic lights and takes the
  sidebar's toggle.

⌘⇧L switches between light and dark.

## The design system

Every piece is a `ui.variants` recipe in `components/kit.luau`: the icon
button, the sidebar row, the pinned tile, the icon tile, the well, the
fields and the key chip. `app.luau` turns the design lint on
(`ui.theme.strict("warn")`), and the test fails on any warning. So every
colour, spacing, radius and shadow is a theme token. The app's own steps
between the standard scale's are `shell.hair`, `shell.tight`, `shell.xs`,
`shell.sm`, `shell.md`, `shell.lg` and `shell.page`. The sidebar glyph's two
radii are `ui.raw`, with their reason.

Icons are Solar (Linear, CC BY 4.0, 480 Design), copied from the
styleguide.

`tests/glass_example.rs` runs it headless. It checks the insets, a split
into equal shares, the sidebar easing shut and back, a message sent and the
light theme. `STYLEGUIDE_SNAPSHOT=<dir>` writes snapshots to that directory.
