//! The component library's `ui.*` (`zgx-components`), behind the
//! `components` feature (on by default): the data grid, tree, calendar,
//! date picker and time field, combobox, select, tabs, command palette,
//! segmented control, stepper, disclosure, accordion and separator, each a
//! [`Library`] kind of node, built by [`register`]'s functions and lowered by
//! [`lower`]. Toasts (`ui.toast`) are `data.rs`'s.
use crate::{
    Vm,
    lower::{Lowering, bridge, lower, need, shortcut_label},
    node::{Kind, Node, expect_node, expect_state, fill, label, node_ud, owner},
    value::Value,
};
use mlua::{Function, Lua, Table};
use std::rc::Rc;
use zgx::{
    compose::{Context, View, prelude::*},
    reactive::Signal,
    scene::Color,
    theme::Themed,
};
use zgx_components::{voice, *};

/// A component of the library, as a node of the interface.
#[derive(Clone)]
pub(crate) enum Library {
    /// `ui.tabs { items = state, value = state, panel = fn(id)?, tab =
    /// fn(item, close)?, … }`: without a panel, the strip alone.
    Tabs {
        label: String,
        items: Signal<Value>,
        value: Signal<Value>,
        reorderable: bool,
        /// Every tab closes (bare ids among the items included).
        closable: bool,
        on_close: Option<Function>,
        on_move: Option<Function>,
        panel: Option<Function>,
        /// Each tab's node, which dresses it.
        tab: Option<Function>,
        /// What follows the pointer as a tab is dragged, from its item.
        preview: Option<Function>,
        /// Written the id of the tab being dragged (`""` once let go).
        dragging: Option<Signal<Value>>,
    },
    /// `ui.select { value = state, options = { … }, placeholder }`: its
    /// node styles its button, its children are the button's face.
    Select {
        label: String,
        value: Signal<Value>,
        options: Vec<Choice>,
        placeholder: String,
        /// `menu = { … }`: the menu's panel, and its `enter` and `exit`.
        menu: Option<(Rc<Node>, Option<Rc<crate::node::OverlayMotion>>)>,
        /// Where the menu opens: over the button unless placed.
        placement: Option<zgx::compose::Placement>,
    },
    /// `ui.combobox { text = state, items = state, value?, loading?, … }`.
    Combobox {
        label: String,
        text: Signal<Value>,
        value: Option<Signal<Value>>,
        items: Signal<Value>,
        loading: Option<Signal<Value>>,
        empty: Option<String>,
    },
    /// `ui.command_palette { open = state, commands?, on_run? }`: the app's
    /// commands, unless it lists its own.
    CommandPalette {
        open: Signal<Value>,
        commands: Option<Vec<PaletteCommand>>,
        on_run: Option<Function>,
    },
    /// `ui.tree { items = state, open = state, value = state, … }`.
    Tree {
        label: String,
        items: Signal<Value>,
        open: Signal<Value>,
        value: Signal<Value>,
        on_open: Option<Function>,
        on_activate: Option<Function>,
        /// Each row's node, which dresses it, from its item and level.
        row: Option<Function>,
        row_height: Option<f32>,
        open_on_click: bool,
        /// The chosen items' ids, when it chooses several.
        selection: Option<Signal<Value>>,
    },
    /// `ui.data_grid { columns, rows = state, sort?, value?, … }`.
    DataGrid {
        label: String,
        /// A state (resizing and moving write it), or the columns as given.
        columns: Result<Signal<Value>, Value>,
        rows: Signal<Value>,
        sort: Option<Signal<Value>>,
        value: Option<Signal<Value>>,
        /// The selected rows, indices into `rows` from 1.
        selection: Option<Signal<Value>>,
        /// A cell's text from its value, column and record.
        cell: Option<Function>,
        on_edit: Option<Function>,
        on_activate: Option<Function>,
    },
    /// `ui.calendar { value = state, … }`, and `ui.date_picker` (a button
    /// opening one): a date as `"2026-10-23"`.
    Calendar {
        label: String,
        value: Signal<Value>,
        picker: bool,
        min: Option<String>,
        max: Option<String>,
        first_weekday: u8,
        unavailable: Option<Function>,
        format: Option<Function>,
    },
    /// `ui.time_field { value = state, hour12?, minute_step? }`: a time as
    /// `"09:30"`.
    TimeField {
        label: String,
        value: Signal<Value>,
        hour12: bool,
        minute_step: u8,
    },
    /// `ui.separator { vertical? }`: a line between groups.
    Separator { vertical: bool },
    /// `ui.segmented { value = state, options = { … } }`: one of a few.
    Segmented {
        label: String,
        value: Signal<Value>,
        /// Each option's value, what it shows (or names it), and the node
        /// of an option that draws its segment.
        options: Vec<(Value, String, Option<Rc<Node>>)>,
    },
    /// `ui.stepper { value = state, min, max, step, decimals }`.
    Stepper {
        label: String,
        value: Signal<Value>,
        options: StepperOptions,
    },
    /// `ui.disclosure { open = state, summary = "…", content… }`.
    Disclosure {
        open: Signal<Value>,
        summary: Summary,
        /// `bare = true`: the summary node dresses the bare summary
        /// button, and the children stay mounted, folding as the app has
        /// them.
        bare: bool,
    },
    /// `ui.accordion { open = state, ui.section { … }… }`: sections, one
    /// open at a time (`open` its id, or nil).
    Accordion { open: Signal<Value> },
    /// `ui.section { id, title, content… }`: an accordion's section.
    Section { id: Value, title: String },
    /// `ui.voice_glyph { kind?, mode, speaking?, … }`: a call's dot-matrix
    /// glyph, stepped in the engine.
    VoiceGlyph(Box<Glyph>),
}

/// `ui.voice_glyph`'s description.
#[derive(Clone)]
pub(crate) struct Glyph {
    /// A beam filling its box, else a field `dots` across and down.
    beam: bool,
    dots: (usize, usize),
    dot: f32,
    outline: voice::Outline,
    falloff: Option<f32>,
    rest: Option<f32>,
    soft_rim: bool,
    dissolve: bool,
    touch: bool,
    mode: Option<Signal<Value>>,
    speaking: Option<Signal<Value>>,
    still: Option<Signal<Value>>,
    /// What it says to assistive technology (its mode, as the app words it).
    label: Option<Signal<Value>>,
    /// Codex's and the user's three inks each (colours or theme tokens).
    agent: Option<[Themed<Color>; 3]>,
    user: Option<[Themed<Color>; 3]>,
}
impl Library {
    /// Its name in `ui` (the element's tag).
    pub(crate) fn tag(&self) -> &'static str {
        match self {
            Library::Separator { .. } => "separator",
            Library::Tabs { .. } => "tabs",
            Library::Tree { .. } => "tree",
            Library::DataGrid { .. } => "data_grid",
            Library::Calendar { picker: false, .. } => "calendar",
            Library::Calendar { picker: true, .. } => "date_picker",
            Library::TimeField { .. } => "time_field",
            Library::Combobox { .. } => "combobox",
            Library::CommandPalette { .. } => "command_palette",
            Library::Select { .. } => "select",
            Library::Segmented { .. } => "segmented",
            Library::Stepper { .. } => "stepper",
            Library::Disclosure { .. } => "disclosure",
            Library::Accordion { .. } => "accordion",
            Library::Section { .. } => "section",
            Library::VoiceGlyph(_) => "voice_glyph",
        }
    }
    /// Whether it holds children (content, sections, a select's face).
    pub(crate) fn takes_children(&self) -> bool {
        matches!(
            self,
            Library::Disclosure { .. }
                | Library::Accordion { .. }
                | Library::Section { .. }
                | Library::Select { .. }
        )
    }
    /// Whether its node styles a part of it, which it dresses itself: a
    /// select's button.
    pub(crate) fn dresses_itself(&self) -> bool {
        matches!(self, Library::Select { .. })
    }
    /// Whether it needs a component context (state bridges, effects): all
    /// but a separator and a section.
    pub(crate) fn needs_context(&self) -> bool {
        !matches!(self, Library::Separator { .. } | Library::Section { .. })
    }
}

/// An accordion's section's id and title, if `kind` is one.
pub(crate) fn section(kind: &Kind) -> Option<(&Value, &String)> {
    match kind {
        Kind::Library(library) => match &**library {
            Library::Section { id, title } => Some((id, title)),
            _ => None,
        },
        _ => None,
    }
}

/// Add the library's functions to `ui`.
pub(crate) fn register(lua: &Lua, ui: &Table) -> mlua::Result<()> {
    // `ui.<widget> { label?, value = state, … }`.
    let widget = |build: fn(&Lua, String, Signal<Value>, &Table) -> mlua::Result<Kind>| {
        lua.create_function(move |lua, table: Table| {
            crate::form::apply_field(lua, &table, false)?;
            let value = expect_state(&table.get("value")?, "`value`")?;
            let kind = build(lua, label(&table)?, value, &table)?;
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })
    };
    ui.set("toast", lua.create_function(toast)?)?;
    ui.set(
        "dismiss_toast",
        lua.create_function(|lua, id: u64| {
            let runtime = crate::node::env(lua)?.runtime.clone();
            Toaster::of(&runtime).dismiss(id);
            Ok(())
        })?,
    )?;
    ui.set(
        "tabs",
        lua.create_function(|lua, table: Table| {
            let items = expect_state(&table.get("items")?, "ui.tabs's `items`")?;
            // Not the `items` alignment style: the tabs.
            table.raw_remove("items")?;
            let value = expect_state(&table.get("value")?, "ui.tabs's `value`")?;
            let kind = Kind::Library(Box::new(Library::Tabs {
                label: label(&table)?,
                items,
                value,
                reorderable: table.get::<Option<bool>>("reorderable")?.unwrap_or(false),
                closable: table.get::<Option<bool>>("closable")?.unwrap_or(false),
                on_close: table.get("on_close")?,
                on_move: table.get("on_move")?,
                panel: table.get("panel")?,
                tab: table.get("tab")?,
                preview: table.get("preview")?,
                dragging: match table.get::<mlua::Value>("dragging")? {
                    mlua::Value::Nil => None,
                    state => Some(expect_state(&state, "ui.tabs's `dragging`")?),
                },
            }));
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    ui.set(
        "select",
        widget(|lua, label, value, t| {
            let list: Table = t
                .get("options")
                .map_err(|_| mlua::Error::runtime("ui.select needs `options`"))?;
            let mut options = Vec::new();
            for option in list.sequence_values::<mlua::Value>() {
                options.push(match option? {
                    // With children or styles, it draws its menu item.
                    mlua::Value::Table(o) => {
                        let shown: String = o.get("label").map_err(|_| {
                            mlua::Error::runtime("a ui.select option needs a `label`")
                        })?;
                        let value = match o.get::<mlua::Value>("value")? {
                            mlua::Value::Nil => Value::Str(shown.as_str().into()),
                            v => crate::value::convert(v, None)?,
                        };
                        Choice {
                            value,
                            shown,
                            disabled: o.get::<Option<bool>>("disabled")?.unwrap_or(false),
                            id: o.get("id")?,
                            drawn: drawn(lua, &o, &["label", "value", "disabled"])?,
                        }
                    }
                    other => {
                        let value = crate::value::convert(other, None)?;
                        let shown = value.to_string();
                        Choice {
                            value,
                            shown,
                            disabled: false,
                            id: None,
                            drawn: None,
                        }
                    }
                });
            }
            let menu = match t.get::<Option<Table>>("menu")? {
                Some(menu) => Some((
                    Rc::new(fill(lua, Node::new(owner(lua)?, Kind::Div), Some(&menu))?),
                    crate::node::overlay_motion(&menu)?,
                )),
                None => None,
            };
            Ok(Kind::Library(Box::new(Library::Select {
                label,
                value,
                options,
                placeholder: t.get::<Option<String>>("placeholder")?.unwrap_or_default(),
                menu,
                placement: crate::node::placement_of(t.get("placement")?)?,
            })))
        })?,
    )?;
    ui.set(
        "tree",
        lua.create_function(|lua, table: Table| {
            let kind = Kind::Library(Box::new(Library::Tree {
                label: label(&table)?,
                items: expect_state(&table.get("items")?, "ui.tree's `items`")?,
                open: expect_state(&table.get("open")?, "ui.tree's `open`")?,
                value: expect_state(&table.get("value")?, "ui.tree's `value`")?,
                on_open: table.get("on_open")?,
                on_activate: table.get("on_activate")?,
                row: table.get("row")?,
                row_height: table.get("row_height")?,
                open_on_click: table.get::<Option<bool>>("open_on_click")?.unwrap_or(false),
                selection: match table.get::<mlua::Value>("selection")? {
                    mlua::Value::Nil => None,
                    v => Some(expect_state(&v, "ui.tree's `selection`")?),
                },
            }));
            // Not the `items` alignment style: the tree's.
            table.raw_remove("items")?;
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    ui.set(
        "data_grid",
        lua.create_function(|lua, table: Table| {
            let optional_state = |key: &str| -> mlua::Result<Option<Signal<Value>>> {
                match table.get::<mlua::Value>(key)? {
                    mlua::Value::Nil => Ok(None),
                    v => expect_state(&v, &format!("ui.data_grid's `{key}`")).map(Some),
                }
            };
            let columns = match table.get::<mlua::Value>("columns")? {
                v @ mlua::Value::Table(_) => Err(crate::value::convert(v, None)?),
                mlua::Value::Nil => {
                    return Err(mlua::Error::runtime("ui.data_grid needs `columns`"));
                }
                v => Ok(expect_state(&v, "ui.data_grid's `columns`")?),
            };
            let kind = Kind::Library(Box::new(Library::DataGrid {
                label: label(&table)?,
                columns,
                rows: expect_state(&table.get("rows")?, "ui.data_grid's `rows`")?,
                sort: optional_state("sort")?,
                value: optional_state("value")?,
                selection: optional_state("selection")?,
                cell: table.get("cell")?,
                on_edit: table.get("on_edit")?,
                on_activate: table.get("on_activate")?,
            }));
            // Not the `rows` grid style: the grid's.
            table.raw_remove("rows")?;
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    for (name, picker) in [("calendar", false), ("date_picker", true)] {
        ui.set(
            name,
            lua.create_function(move |lua, table: Table| {
                let kind = Kind::Library(Box::new(Library::Calendar {
                    label: label(&table)?,
                    value: expect_state(&table.get("value")?, &format!("ui.{name}'s `value`"))?,
                    picker,
                    min: table.get("min")?,
                    max: table.get("max")?,
                    first_weekday: table.get::<Option<u8>>("first_weekday")?.unwrap_or(0) % 7,
                    unavailable: table.get("unavailable")?,
                    format: table.get("format")?,
                }));
                node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
            })?,
        )?;
    }
    ui.set(
        "time_field",
        lua.create_function(|lua, table: Table| {
            let kind = Kind::Library(Box::new(Library::TimeField {
                label: label(&table)?,
                value: expect_state(&table.get("value")?, "ui.time_field's `value`")?,
                hour12: table.get::<Option<bool>>("hour12")?.unwrap_or(false),
                minute_step: table
                    .get::<Option<u8>>("minute_step")?
                    .unwrap_or(1)
                    .clamp(1, 30),
            }));
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    ui.set(
        "combobox",
        lua.create_function(|lua, table: Table| {
            crate::form::apply_field(lua, &table, false)?;
            let optional_state = |key: &str| -> mlua::Result<Option<Signal<Value>>> {
                match table.get::<mlua::Value>(key)? {
                    mlua::Value::Nil => Ok(None),
                    v => expect_state(&v, &format!("ui.combobox's `{key}`")).map(Some),
                }
            };
            let kind = Kind::Library(Box::new(Library::Combobox {
                label: label(&table)?,
                text: expect_state(&table.get("text")?, "ui.combobox's `text`")?,
                value: optional_state("value")?,
                items: expect_state(&table.get("items")?, "ui.combobox's `items`")?,
                loading: optional_state("loading")?,
                empty: table.get("empty")?,
            }));
            // Not the `items` alignment style: the options.
            table.raw_remove("items")?;
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    ui.set(
        "command_palette",
        lua.create_function(|lua, table: Table| {
            let open = expect_state(&table.get("open")?, "ui.command_palette's `open`")?;
            let commands = match table.get::<Option<Table>>("commands")? {
                None => None,
                Some(list) => Some(
                    list.sequence_values::<Table>()
                        .map(|c| palette_command(&c?))
                        .collect::<mlua::Result<Vec<_>>>()?,
                ),
            };
            let kind = Kind::Library(Box::new(Library::CommandPalette {
                open,
                commands,
                on_run: table.get("on_run")?,
            }));
            node_ud(lua, fill(lua, Node::new(owner(lua)?, kind), Some(&table))?)
        })?,
    )?;
    ui.set(
        "separator",
        lua.create_function(|lua, table: Option<Table>| {
            let vertical = match &table {
                Some(t) => t.get::<Option<bool>>("vertical")?.unwrap_or(false),
                None => false,
            };
            node_ud(
                lua,
                fill(
                    lua,
                    Node::new(
                        owner(lua)?,
                        Kind::Library(Box::new(Library::Separator { vertical })),
                    ),
                    table.as_ref(),
                )?,
            )
        })?,
    )?;
    ui.set(
        "segmented",
        widget(|lua, label, value, t| {
            let list: Table = t
                .get("options")
                .map_err(|_| mlua::Error::runtime("ui.segmented needs `options`"))?;
            let mut options = Vec::new();
            for option in list.sequence_values::<mlua::Value>() {
                options.push(match option? {
                    // `{ value = "w", label = "Week" }`, or the label alone;
                    // with children or styles, it draws its segment.
                    mlua::Value::Table(o) => {
                        let shown: String = o.get("label").map_err(|_| {
                            mlua::Error::runtime("a ui.segmented option needs a `label`")
                        })?;
                        let value = match o.get::<mlua::Value>("value")? {
                            mlua::Value::Nil => Value::Str(shown.as_str().into()),
                            v => crate::value::convert(v, None)?,
                        };
                        (value, shown, drawn(lua, &o, &["label", "value"])?)
                    }
                    other => {
                        let value = crate::value::convert(other, None)?;
                        (value.clone(), value.to_string(), None)
                    }
                });
            }
            if options.is_empty() {
                return Err(mlua::Error::runtime(
                    "ui.segmented needs at least one option",
                ));
            }
            Ok(Kind::Library(Box::new(Library::Segmented {
                label,
                value,
                options,
            })))
        })?,
    )?;
    ui.set(
        "stepper",
        widget(|_, label, value, t| {
            let defaults = StepperOptions::default();
            let options = StepperOptions {
                min: t.get::<Option<f64>>("min")?.unwrap_or(defaults.min),
                max: t.get::<Option<f64>>("max")?.unwrap_or(defaults.max),
                step: t.get::<Option<f64>>("step")?.unwrap_or(defaults.step),
                decimals: t
                    .get::<Option<f64>>("decimals")?
                    .map_or(defaults.decimals, |d| d.clamp(0., 10.) as usize),
            };
            if !(options.min <= options.max && options.step > 0. && options.step.is_finite()) {
                return Err(mlua::Error::runtime(
                    "ui.stepper needs min <= max and a positive step",
                ));
            }
            Ok(Kind::Library(Box::new(Library::Stepper {
                label,
                value,
                options,
            })))
        })?,
    )?;
    ui.set(
        "disclosure",
        lua.create_function(|lua, table: Table| {
            let open = expect_state(&table.get("open")?, "ui.disclosure's `open`")?;
            let summary = match table.get::<mlua::Value>("summary")? {
                mlua::Value::String(s) => Summary::Text(s.to_string_lossy()),
                mlua::Value::Nil => {
                    return Err(mlua::Error::runtime("ui.disclosure needs a `summary`"));
                }
                node => Summary::Node(expect_node(node, "ui.disclosure's `summary`")?),
            };
            node_ud(
                lua,
                fill(
                    lua,
                    Node::new(
                        owner(lua)?,
                        Kind::Library(Box::new(Library::Disclosure {
                            open,
                            summary,
                            bare: table.get::<Option<bool>>("bare")?.unwrap_or(false),
                        })),
                    ),
                    Some(&table),
                )?,
            )
        })?,
    )?;
    ui.set(
        "accordion",
        lua.create_function(|lua, table: Table| {
            let open = expect_state(&table.get("open")?, "ui.accordion's `open`")?;
            let node = fill(
                lua,
                Node::new(
                    owner(lua)?,
                    Kind::Library(Box::new(Library::Accordion { open })),
                ),
                Some(&table),
            )?;
            if let Some(other) = node.children.iter().find(|c| section(&c.kind).is_none()) {
                return Err(mlua::Error::runtime(format!(
                    "ui.accordion holds ui.section nodes, not {}",
                    other.tag()
                )));
            }
            node_ud(lua, node)
        })?,
    )?;
    ui.set("voice_glyph", lua.create_function(voice_glyph_node)?)?;
    ui.set(
        "section",
        lua.create_function(|lua, table: Table| {
            let id = match table.get::<mlua::Value>("id")? {
                mlua::Value::Nil => return Err(mlua::Error::runtime("ui.section needs an `id`")),
                v => crate::value::convert(v, None)?,
            };
            let title: String = table
                .get("title")
                .map_err(|_| mlua::Error::runtime("ui.section needs a `title`"))?;
            node_ud(
                lua,
                fill(
                    lua,
                    Node::new(
                        owner(lua)?,
                        Kind::Library(Box::new(Library::Section { id, title })),
                    ),
                    Some(&table),
                )?,
            )
        })?,
    )?;
    Ok(())
}

/// The view `library`, a node of the interface, lowers to.
/// Whether the component `library` lowers to names an inner node with its
/// label (`zgx::compose::FollowedLabel`).
pub(crate) fn follows_label(library: &Library) -> bool {
    matches!(
        library,
        Library::Tree { .. }
            | Library::DataGrid { .. }
            | Library::Calendar { .. }
            | Library::TimeField { .. }
            | Library::Combobox { .. }
            | Library::Tabs { .. }
            | Library::Select { .. }
    )
}

pub(crate) fn view(
    library: &Library,
    node: &Rc<Node>,
    vm: &Rc<Vm>,
    low: &Rc<Lowering>,
    mut cx: Option<&mut Context>,
) -> View {
    match library {
        Library::Separator { vertical } => separator(*vertical),
        Library::Tree {
            label,
            items,
            open,
            value,
            on_open,
            on_activate,
            row,
            row_height,
            open_on_click,
            selection,
        } => {
            let cx = need(&mut cx);
            let ids = |state: &Signal<Value>, cx: &mut Context| {
                bridge(
                    cx,
                    state,
                    |v| v.list().iter().map(Value::to_string).collect::<Vec<_>>(),
                    |ids: Vec<String>| {
                        Value::List(ids.into_iter().map(|s| Value::Str(s.into())).collect())
                    },
                )
            };
            let open_signal = ids(open, cx);
            let selection = selection.as_ref().map(|s| ids(s, cx));
            let selected = bridge(
                cx,
                value,
                |v| (!matches!(v, Value::Nil)).then(|| v.to_string()),
                |s: Option<String>| s.map_or(Value::Nil, |s| Value::Str(s.into())),
            );
            // An item: `{ id, label, children?, lazy? }`; one lazy without
            // children is loading.
            fn find<'v>(list: &'v [Value], id: &str) -> Option<&'v Value> {
                for item in list {
                    if item.field("id").map(Value::to_string).as_deref() == Some(id) {
                        return Some(item);
                    }
                    if let Some(found) = item.field("children").and_then(|c| find(c.list(), id)) {
                        return Some(found);
                    }
                }
                None
            }
            fn items_of(list: &[Value]) -> Vec<TreeItem> {
                list.iter()
                    .map(|item| {
                        let id = item.field("id").map(Value::to_string).unwrap_or_default();
                        let shown = item
                            .field("label")
                            .map(Value::to_string)
                            .unwrap_or_else(|| id.clone());
                        let parent = item.field("children").is_some_and(|c| !c.list().is_empty())
                            || item.field("lazy").is_some_and(Value::truthy);
                        // The rest of the script's item (a file's status):
                        // its row is drawn again as it changes.
                        let revision = match item {
                            Value::Map(fields) => {
                                use std::hash::{Hash, Hasher};
                                let mut hasher = std::collections::hash_map::DefaultHasher::new();
                                for (key, value) in fields.iter() {
                                    if &**key != "children" {
                                        key.hash(&mut hasher);
                                        format!("{value:?}").hash(&mut hasher);
                                    }
                                }
                                hasher.finish()
                            }
                            _ => 0,
                        };
                        TreeItem {
                            id,
                            label: shown,
                            parent,
                            revision,
                        }
                    })
                    .collect()
            }
            let source = items.clone();
            let children = move |parent: Option<&str>| {
                source.with(|v| match parent {
                    None => TreeChildren::Ready(items_of(v.list())),
                    Some(id) => match find(v.list(), id).and_then(|item| item.field("children")) {
                        Some(c) if !c.list().is_empty() => TreeChildren::Ready(items_of(c.list())),
                        _ if find(v.list(), id)
                            .is_some_and(|i| i.field("lazy").is_some_and(Value::truthy)) =>
                        {
                            TreeChildren::Loading
                        }
                        _ => TreeChildren::Ready(Vec::new()),
                    },
                })
            };
            // A lazy item opened without its children: the app is asked.
            if let Some(on_open) = on_open.clone() {
                let (open, vm, runtime) = (open_signal.clone(), vm.clone(), cx.runtime());
                let mut asked: std::collections::HashSet<String> = Default::default();
                let quiet = runtime.clone();
                cx.retain(runtime.effect(move || {
                    let now = open.get();
                    for id in now
                        .iter()
                        .filter(|id| !asked.contains(*id))
                        .cloned()
                        .collect::<Vec<_>>()
                    {
                        asked.insert(id.clone());
                        quiet.untracked(|| {
                            if let Err(error) = vm.call::<()>(&on_open, id) {
                                vm.report(error);
                            }
                        });
                    }
                    asked.retain(|id| now.contains(id));
                }));
            }
            // Each row dressed by the node `row` makes of its item (the
            // script's own table) and its level.
            let dress = row.clone().map(|f| {
                let (vm, low, items) = (vm.clone(), low.clone(), items.clone());
                let dress: DressRow = Rc::new(
                    move |item: &TreeItem, level: usize, bare: View, cx: &mut Context| {
                        let found = items
                            .with_untracked(|v| find(v.list(), &item.id).cloned())
                            .unwrap_or_else(|| Value::Str(item.id.as_str().into()));
                        dressed(bare, &f, (found, level), &vm, &low, cx)
                    },
                );
                dress
            });
            let options = TreeOptions {
                row: dress,
                row_height: *row_height,
                open_on_click: *open_on_click,
                selection,
            };
            let (on_activate, vm) = (on_activate.clone(), vm.clone());
            tree_with(
                label.clone(),
                children,
                open_signal,
                selected,
                move |id| {
                    if let Some(f) = &on_activate
                        && let Err(error) = vm.call::<()>(f, id)
                    {
                        vm.report(error);
                    }
                },
                options,
            )
        }
        Library::DataGrid {
            label,
            columns,
            rows,
            sort,
            value,
            selection,
            cell,
            on_edit,
            on_activate,
        } => {
            use crate::value::PathKey;
            let cx = need(&mut cx);
            // A column: `{ id, title?, width?, min_width?, sortable?,
            // editable?, align? }`.
            fn column_of(v: &Value) -> Option<GridColumn> {
                let id = v.field("id")?.to_string();
                let title = v
                    .field("title")
                    .map_or_else(|| id.clone(), Value::to_string);
                let width = v.field("width").and_then(Value::as_f64).unwrap_or(120.);
                let mut column = GridColumn::new(id, title, width as f32);
                if let Some(min) = v.field("min_width").and_then(Value::as_f64) {
                    column.min_width = min as f32;
                }
                column.sortable = v.field("sortable").is_some_and(Value::truthy);
                column.editable = v.field("editable").is_some_and(Value::truthy);
                column.align_end = v.field("align").is_some_and(|a| a.to_string() == "end");
                Some(column)
            }
            fn columns_of(v: &Value) -> Vec<GridColumn> {
                v.list().iter().filter_map(column_of).collect()
            }
            fn sort_of(v: &Value) -> Option<GridSort> {
                Some(GridSort {
                    column: v.field("column")?.to_string(),
                    descending: v.field("descending").is_some_and(Value::truthy),
                })
            }
            fn sort_value(sort: Option<GridSort>) -> Value {
                let Some(sort) = sort else {
                    return Value::Nil;
                };
                Value::Nil
                    .set_path(
                        &[PathKey::Key("column".into())],
                        Value::Str(sort.column.as_str().into()),
                    )
                    .and_then(|v| {
                        v.set_path(
                            &[PathKey::Key("descending".into())],
                            Value::Bool(sort.descending),
                        )
                    })
                    .unwrap_or(Value::Nil)
            }
            // Numbers by value, text without case, then the rest; nil last.
            fn compare(a: Option<&Value>, b: Option<&Value>) -> std::cmp::Ordering {
                let rank = |v: Option<&Value>| match v {
                    Some(Value::Num(_) | Value::Bool(_)) => 0,
                    Some(Value::Str(_)) => 1,
                    None | Some(Value::Nil) => 3,
                    _ => 2,
                };
                match (a, b) {
                    (Some(Value::Num(x)), Some(Value::Num(y))) => x.total_cmp(y),
                    (Some(Value::Bool(x)), Some(Value::Bool(y))) => x.cmp(y),
                    (Some(Value::Str(x)), Some(Value::Str(y))) => x
                        .chars()
                        .flat_map(char::to_lowercase)
                        .cmp(y.chars().flat_map(char::to_lowercase))
                        .then_with(|| x.cmp(y)),
                    _ => rank(a).cmp(&rank(b)),
                }
            }
            let columns_state = match columns {
                Ok(state) => state.clone(),
                Err(given) => cx.state(given.clone()),
            };
            // Written back in their new order and widths, all else as the
            // app had it.
            let written = columns_state.clone();
            let columns = bridge_with(
                cx,
                &columns_state,
                columns_of,
                move |next: Vec<GridColumn>| {
                    written.with_untracked(|old| {
                        let items: Vec<Value> = next
                            .iter()
                            .filter_map(|c| {
                                let item = old.list().iter().find(|o| {
                                    o.field("id").map(Value::to_string).as_deref() == Some(&*c.id)
                                })?;
                                item.set_path(
                                    &[PathKey::Key("width".into())],
                                    Value::Num(c.width as f64),
                                )
                                .ok()
                            })
                            .collect();
                        Value::List(items.into())
                    })
                },
            );
            let sort = match sort {
                Some(state) => bridge(cx, state, sort_of, sort_value),
                None => cx.state(None),
            };
            // The rows as they show: `rows` sorted, by their indices (none:
            // as they are).
            let order: Signal<Option<Rc<Vec<usize>>>> = cx.state(None);
            {
                let (rows, sort, order) = (rows.clone(), sort.clone(), order.clone());
                cx.retain(cx.runtime().effect(move || {
                    let next = sort.get().map(|by| {
                        rows.with(|v| {
                            let list = v.list();
                            let mut index: Vec<usize> = (0..list.len()).collect();
                            index.sort_by(|&a, &b| {
                                let (a, b) = (list[a].field(&by.column), list[b].field(&by.column));
                                if by.descending {
                                    compare(b, a)
                                } else {
                                    compare(a, b)
                                }
                            });
                            Rc::new(index)
                        })
                    });
                    order.set(next);
                }));
            }
            // A row shown's index in `rows`, from 0.
            let original = {
                let order = order.clone();
                move |r: usize| {
                    order.with_untracked(|o| {
                        o.as_ref().map_or(r, |o| o.get(r).copied().unwrap_or(r))
                    })
                }
            };
            let (count, cells, cell_order) = (rows.clone(), rows.clone(), order.clone());
            let (format, format_vm) = (cell.clone(), vm.clone());
            let mut source = GridSource::new(
                move || count.with(|v| v.list().len()),
                move |r, column| {
                    let i = cell_order
                        .with(|o| o.as_ref().map_or(r, |o| o.get(r).copied().unwrap_or(r)));
                    let Some(format) = &format else {
                        return cells.with(|v| {
                            v.list()
                                .get(i)
                                .and_then(|row| row.field(column))
                                .map(Value::to_string)
                                .unwrap_or_default()
                        });
                    };
                    // `cell(value, column, record)`: the app's text for it.
                    let record = cells
                        .with(|v| v.list().get(i).cloned())
                        .unwrap_or(Value::Nil);
                    let value = record.field(column).cloned().unwrap_or(Value::Nil);
                    format_vm
                        .call::<String>(format, (value.clone(), column.to_owned(), record))
                        .unwrap_or_else(|error| {
                            format_vm.report(error);
                            value.to_string()
                        })
                },
            );
            {
                // Told to `on_edit`, or written into the row: a number stays
                // one if the text is one.
                let (rows, vm, on_edit, at) =
                    (rows.clone(), vm.clone(), on_edit.clone(), original.clone());
                source = source.on_edit(move |r, column, text| {
                    let i = at(r);
                    if let Some(f) = &on_edit {
                        if let Err(error) = vm.call::<()>(f, (i + 1, column.to_owned(), text)) {
                            vm.report(error);
                        }
                        return;
                    }
                    let path = [PathKey::Index(i + 1), PathKey::Key(column.into())];
                    let old = rows.with_untracked(|v| v.at(&path).cloned());
                    let leaf = match old {
                        Some(Value::Num(_)) if text.trim().is_empty() => Value::Nil,
                        Some(Value::Num(_)) => text
                            .trim()
                            .parse::<f64>()
                            .map_or_else(|_| Value::Str(text.as_str().into()), Value::Num),
                        Some(Value::Bool(_)) if text == "true" || text == "false" => {
                            Value::Bool(text == "true")
                        }
                        _ => Value::Str(text.as_str().into()),
                    };
                    match rows.with_untracked(|v| v.set_path(&path, leaf)) {
                        Ok(next) => {
                            rows.set(next);
                        }
                        Err(error) => vm.report(mlua::Error::runtime(error)),
                    }
                });
            }
            if let Some(f) = on_activate.clone() {
                let (vm, at) = (vm.clone(), original.clone());
                source = source.on_activate(move |r| {
                    if let Err(error) = vm.call::<()>(&f, at(r) + 1) {
                        vm.report(error);
                    }
                });
            }
            // The current cell, its row an index into `rows` from 1. That
            // state is the truth: as the rows' order changes, the cell
            // follows its record (as a sorted list keeps its selection).
            let state = match value {
                Some(state) => state.clone(),
                None => cx.state(Value::Nil),
            };
            fn cell_of(v: &Value, order: &Option<Rc<Vec<usize>>>) -> Option<GridCell> {
                let row = v.field("row").and_then(Value::as_f64)? as usize;
                let column = v.field("column")?.to_string();
                let r = match order {
                    Some(o) => o.iter().position(|&i| i + 1 == row),
                    None => row.checked_sub(1),
                }?;
                Some(GridCell::new(r, column))
            }
            fn value_of(cell: &Option<GridCell>, order: &Option<Rc<Vec<usize>>>) -> Value {
                let Some(cell) = cell else {
                    return Value::Nil;
                };
                let i = order
                    .as_ref()
                    .map_or(cell.row, |o| o.get(cell.row).copied().unwrap_or(cell.row));
                Value::Nil
                    .set_path(&[PathKey::Key("row".into())], Value::Num((i + 1) as f64))
                    .and_then(|v| {
                        v.set_path(
                            &[PathKey::Key("column".into())],
                            Value::Str(cell.column.as_str().into()),
                        )
                    })
                    .unwrap_or(Value::Nil)
            }
            let current: Signal<Option<GridCell>> =
                cx.state(state.with_untracked(|v| order.with_untracked(|o| cell_of(v, o))));
            {
                let (state, order, current) = (state.clone(), order.clone(), current.clone());
                cx.retain(cx.runtime().effect(move || {
                    let o = order.get();
                    current.set(state.with(|v| cell_of(v, &o)));
                }));
            }
            {
                let (state, order, current) = (state.clone(), order.clone(), current.clone());
                let mut first = true;
                cx.retain(cx.runtime().effect(move || {
                    let cell = current.get();
                    if !std::mem::take(&mut first) {
                        state.set(order.with_untracked(|o| value_of(&cell, o)));
                    }
                }));
            }
            // The selected rows, indices into `rows` from 1: that state is the
            // truth, the rows following their records as the order changes.
            if let Some(state) = selection {
                fn shown_of(v: &Value, order: &Option<Rc<Vec<usize>>>) -> GridSelection {
                    let given = v
                        .list()
                        .iter()
                        .filter_map(Value::as_f64)
                        .filter(|i| *i >= 1.)
                        .map(|i| i as usize - 1);
                    match order {
                        // Each record's place as shown.
                        Some(o) => {
                            let mut place = vec![usize::MAX; o.len()];
                            for (shown, &i) in o.iter().enumerate() {
                                place[i] = shown;
                            }
                            GridSelection::from_rows(
                                given.filter_map(|i| {
                                    place.get(i).copied().filter(|p| *p != usize::MAX)
                                }),
                            )
                        }
                        None => GridSelection::from_rows(given),
                    }
                }
                let chosen = cx.state(GridSelection::default());
                {
                    let (state, order, chosen) = (state.clone(), order.clone(), chosen.clone());
                    cx.retain(cx.runtime().effect(move || {
                        let o = order.get();
                        let next = state.with(|v| shown_of(v, &o));
                        // The same rows keep what Shift extends from.
                        if !chosen.with_untracked(|c| c.rows().eq(next.rows())) {
                            chosen.set(next);
                        }
                    }));
                }
                {
                    let (state, order, chosen) = (state.clone(), order.clone(), chosen.clone());
                    let mut first = true;
                    cx.retain(cx.runtime().effect(move || {
                        let rows: Vec<usize> = chosen.with(|c| c.rows().collect());
                        if std::mem::take(&mut first) {
                            return;
                        }
                        let records = order.with_untracked(|o| {
                            rows.iter()
                                .map(|&r| {
                                    let i =
                                        o.as_ref().map_or(r, |o| o.get(r).copied().unwrap_or(r));
                                    Value::Num((i + 1) as f64)
                                })
                                .collect::<Vec<_>>()
                        });
                        let same = state.with_untracked(|v| state_rows_equal(v, &records));
                        if !same {
                            state.set(Value::List(records.into()));
                        }
                    }));
                }
                source = source.selection(chosen);
            }
            data_grid(label.clone(), columns, sort, current, source)
        }
        Library::Calendar {
            label,
            value,
            picker,
            min,
            max,
            first_weekday,
            unavailable,
            format,
        } => {
            let cx = need(&mut cx);
            // A date as `"2026-10-23"`; anything else is none.
            let date = bridge(
                cx,
                value,
                |v| match v {
                    Value::Str(s) => CalendarDate::parse(s),
                    _ => None,
                },
                |d: Option<CalendarDate>| {
                    d.map_or(Value::Nil, |d| Value::Str(d.to_string().as_str().into()))
                },
            );
            let mut options = CalendarOptions {
                min: min.as_deref().and_then(CalendarDate::parse),
                max: max.as_deref().and_then(CalendarDate::parse),
                first_weekday: *first_weekday,
                ..Default::default()
            };
            if let Some(f) = unavailable.clone() {
                let vm = vm.clone();
                options.disabled = Some(Rc::new(move |d: CalendarDate| {
                    vm.call::<bool>(&f, (d.to_string(), d.weekday()))
                        .unwrap_or_else(|error| {
                            vm.report(error);
                            false
                        })
                }));
            }
            if let Some(f) = format.clone() {
                let vm = vm.clone();
                options.format = Some(Rc::new(move |d: CalendarDate| {
                    vm.call::<String>(&f, d.to_string())
                        .unwrap_or_else(|error| {
                            vm.report(error);
                            d.to_string()
                        })
                }));
            }
            if *picker {
                date_picker(label.clone(), date, options)
            } else {
                calendar(label.clone(), date, options)
            }
        }
        Library::TimeField {
            label,
            value,
            hour12,
            minute_step,
        } => {
            let cx = need(&mut cx);
            // A time as `"09:30"`; anything else is none.
            let time = bridge(
                cx,
                value,
                |v| match v {
                    Value::Str(s) => TimeOfDay::parse(s),
                    _ => None,
                },
                |t: Option<TimeOfDay>| {
                    t.map_or(Value::Nil, |t| Value::Str(t.to_string().as_str().into()))
                },
            );
            time_field(
                label.clone(),
                time,
                TimeOptions {
                    minute_step: *minute_step,
                    hour12: *hour12,
                },
            )
        }
        Library::Combobox {
            label,
            text: text_state,
            value,
            items,
            loading,
            empty,
        } => {
            let cx = need(&mut cx);
            let text_signal = bridge(cx, text_state, |v| v.to_string(), |s| Value::Str(s.into()));
            let value_signal = match value {
                Some(value) => bridge(
                    cx,
                    value,
                    |v| (!matches!(v, Value::Nil)).then(|| v.to_string()),
                    |s: Option<String>| s.map_or(Value::Nil, |s| Value::Str(s.into())),
                ),
                None => cx.state(None),
            };
            // Each option: `{ value, label, detail? }`, or text alone.
            let item_of = |item: &Value| match item {
                Value::Map(_) => {
                    let shown = item
                        .field("label")
                        .map(Value::to_string)
                        .unwrap_or_default();
                    let mut option = ComboItem::new(
                        item.field("value").map_or(shown.clone(), Value::to_string),
                        shown,
                    );
                    option.detail = item.field("detail").map(Value::to_string);
                    option
                }
                other => ComboItem::new(other.to_string(), other.to_string()),
            };
            // The list is the app's: followed, never written.
            let items_signal = follow_with(cx, items, move |v: &Value| {
                v.list().iter().map(item_of).collect::<Vec<_>>()
            });
            let mut options = ComboboxOptions::default();
            if let Some(loading) = loading {
                options.loading = Some(bridge(cx, loading, Value::truthy, Value::Bool));
            }
            if let Some(empty) = empty {
                options.empty = empty.clone();
            }
            combobox(
                label.clone(),
                text_signal,
                value_signal,
                items_signal,
                options,
            )
        }
        Library::CommandPalette {
            open,
            commands,
            on_run,
        } => {
            let open = bridge(need(&mut cx), open, Value::truthy, Value::Bool);
            let listed = commands.clone();
            let registry = low.commands.clone();
            let list = move || match &listed {
                Some(list) => list.clone(),
                // The app's menu commands, with their menus and keys.
                None => registry.list.with(|all| {
                    all.iter()
                        .filter(|c| !c.separator && !c.id.is_empty())
                        .map(|c| {
                            let mut command = PaletteCommand::new(c.id.clone(), c.title.clone())
                                .detail(c.menu.clone());
                            command.shortcut = c.key.as_deref().map(shortcut_label);
                            command
                        })
                        .collect()
                }),
            };
            let (on_run, vm, registry) = (on_run.clone(), vm.clone(), low.commands.clone());
            command_palette(open, list, move |id| match &on_run {
                Some(f) => {
                    if let Err(error) = vm.call::<()>(f, id) {
                        vm.report(error);
                    }
                }
                None => {
                    registry.run(id);
                }
            })
        }
        Library::Tabs {
            label,
            items,
            value,
            reorderable,
            closable,
            on_close,
            on_move,
            panel,
            tab,
            preview,
            dragging,
        } => {
            // The script's items, as tabs (a bare string is its own id);
            // written back as its own values, reordered or removed.
            let source = items.clone();
            let every = *closable;
            let tabs_of = move |v: &Value| -> Vec<Tab> {
                v.list()
                    .iter()
                    .map(|item| Tab {
                        id: tab_id(item),
                        label: item
                            .field("label")
                            .map(Value::to_string)
                            .unwrap_or_default(),
                        closable: every || item.field("closable").is_some_and(Value::truthy),
                    })
                    .collect()
            };
            let cx = need(&mut cx);
            let tabs_signal = bridge_with(cx, items, tabs_of, move |tabs: Vec<Tab>| {
                let old = source.with_untracked(Clone::clone);
                let kept: Vec<Value> = tabs
                    .iter()
                    .filter_map(|tab| {
                        old.list()
                            .iter()
                            .find(|item| tab_id(item) == tab.id)
                            .cloned()
                    })
                    .collect();
                Value::List(kept.into())
            });
            let selected = bridge(cx, value, |v| v.to_string(), |s| Value::Str(s.into()));
            let on_close = on_close.clone().map(|f| {
                let vm = vm.clone();
                let ask: CloseTab = Rc::new(move |id: &str| {
                    !matches!(
                        vm.call::<mlua::Value>(&f, id),
                        Ok(mlua::Value::Boolean(false))
                    )
                });
                ask
            });
            let on_move = on_move.clone().map(|f| {
                let vm = vm.clone();
                let told: MoveTab = Rc::new(move |id: &str, to: usize| {
                    if let Err(error) = vm.call::<()>(&f, (id, to + 1)) {
                        vm.report(error);
                    }
                });
                told
            });
            // Each tab dressed by the node `tab` makes of its item, given
            // what closes it.
            let dress = tab.clone().map(|f| {
                let (vm, low, items) = (vm.clone(), low.clone(), items.clone());
                let dress: DressTab = Rc::new(
                    move |tab: &Tab, bare: View, close: Rc<dyn Fn()>, cx: &mut Context| {
                        let item = items
                            .with_untracked(|v| {
                                v.list().iter().find(|i| tab_id(i) == tab.id).cloned()
                            })
                            .unwrap_or_else(|| Value::Str(tab.id.as_str().into()));
                        let closes = vm.lua.create_function(move |_, ()| {
                            close();
                            Ok(())
                        });
                        match closes {
                            Ok(closes) => dressed(bare, &f, (item, closes), &vm, &low, cx),
                            Err(error) => {
                                vm.report(error);
                                bare
                            }
                        }
                    },
                );
                dress
            });
            // The tabs lie as far apart as the node's `gap` says.
            let list = node
                .props
                .iter()
                .find_map(|(prop, source)| match (prop, source) {
                    (crate::node::Prop::Gap, crate::node::Source::Lit(lit)) => match lit {
                        crate::node::Lit::Num(n) => Some(Styles::new().gap(*n)),
                        crate::node::Lit::Len(zgx::layout::Length::Px(n)) => {
                            Some(Styles::new().gap(*n))
                        }
                        crate::node::Lit::Token(t) => {
                            Some(Styles::new().token(zgx::theme::Field::Gap, *t))
                        }
                        _ => None,
                    },
                    _ => None,
                });
            // What a dragged tab lifts, built from its item.
            let preview = preview.clone().map(|f| {
                let (vm, low, items) = (vm.clone(), low.clone(), items.clone());
                let preview: PreviewTab = Rc::new(move |tab: &Tab| {
                    let item = items
                        .with_untracked(|v| v.list().iter().find(|i| tab_id(i) == tab.id).cloned())
                        .unwrap_or_else(|| Value::Str(tab.id.as_str().into()));
                    let result = vm.call::<mlua::Value>(&f, item);
                    crate::lower::built(&vm, result, &low, &f)
                });
                preview
            });
            let dragging = dragging
                .clone()
                .map(|state| bridge(cx, &state, |v| v.to_string(), |s| Value::Str(s.into())));
            let options = TabsOptions {
                reorderable: *reorderable,
                on_close,
                on_move,
                tab: dress,
                list,
                preview,
                dragging,
            };
            match panel.clone() {
                None => tab_strip(label.clone(), tabs_signal, selected, options),
                Some(panel) => {
                    let (vm, low) = (vm.clone(), low.clone());
                    tabs(
                        label.clone(),
                        tabs_signal,
                        selected,
                        options,
                        move |id, cx| crate::lower::build_scoped(&vm, cx, &low, &panel, id),
                    )
                }
            }
        }
        Library::Select {
            label,
            value,
            options,
            placeholder,
            menu,
            placement,
        } => {
            // Options by their value's text; written back as the value itself.
            let values: Rc<[Value]> = options.iter().map(|o| o.value.clone()).collect();
            let texts: Vec<String> = values.iter().map(Value::to_string).collect();
            let chosen = bridge_with(
                need(&mut cx),
                value,
                |v| v.to_string(),
                move |text: String| {
                    values
                        .iter()
                        .find(|v| v.to_string() == text)
                        .cloned()
                        .unwrap_or_default()
                },
            );
            let list = options
                .iter()
                .zip(texts)
                .map(|(o, text)| {
                    let mut option = SelectOption::new(text, o.shown.clone());
                    option.disabled = o.disabled;
                    option.id = o.id.clone();
                    option
                })
                .collect();
            // The node styles the button, its children its face; a `menu`
            // table the menu's panel; an option drawing itself its item.
            let parts = SelectParts {
                button: Some({
                    let (node, vm, low) = (node.clone(), vm.clone(), low.clone());
                    Box::new(move |button, cx| {
                        crate::lower::dress(button, &node, None, &vm, &low, cx)
                    })
                }),
                bare_button: !node.children.is_empty(),
                menu: menu.clone().map(|(panel, motion)| {
                    let (vm, low) = (vm.clone(), low.clone());
                    let dress: Dress = Box::new(move |view, cx| {
                        crate::lower::dress(view, &panel, motion.as_ref(), &vm, &low, cx)
                    });
                    dress
                }),
                item: options.iter().any(|o| o.drawn.is_some()).then(|| {
                    let drawn: Vec<Option<Rc<Node>>> =
                        options.iter().map(|o| o.drawn.clone()).collect();
                    let (vm, low) = (vm.clone(), low.clone());
                    let dress: DressItem =
                        Box::new(move |i, item, cx| match drawn.get(i).cloned().flatten() {
                            Some(node) => crate::lower::dress(item, &node, None, &vm, &low, cx),
                            None => item,
                        });
                    dress
                }),
                placement: *placement,
            };
            select_with(label.clone(), chosen, list, placeholder.clone(), parts)
        }
        Library::Segmented {
            label,
            value,
            options,
        } => {
            // The chosen option's value, as its index both ways.
            let values: Rc<[Value]> = options.iter().map(|(v, _, _)| v.clone()).collect();
            let index = {
                let values = values.clone();
                move |v: &Value| values.iter().position(|o| o == v).unwrap_or(0)
            };
            let cx = need(&mut cx);
            let chosen = bridge_with(cx, value, index, move |i: usize| {
                values.get(i).cloned().unwrap_or_default()
            });
            if options.iter().all(|(_, _, drawn)| drawn.is_none()) {
                return segmented(
                    label.clone(),
                    chosen,
                    options.iter().map(|(_, shown, _)| shown.clone()),
                );
            }
            // Options drawing their segments: each its node's look and
            // face, named by its label.
            segmented_with(label.clone(), chosen, options.len(), |i, button| {
                let (_, shown, drawn) = &options[i];
                let button = button.accessible_label(shown.clone());
                match drawn {
                    Some(node) => crate::lower::dress(button, node, None, vm, low, cx),
                    None => button.child(zgx::compose::text(shown.clone())),
                }
            })
        }
        Library::Stepper {
            label,
            value,
            options,
        } => stepper(
            label.clone(),
            bridge(
                need(&mut cx),
                value,
                |v| v.as_f64().unwrap_or(0.),
                Value::Num,
            ),
            *options,
        ),
        Library::Disclosure {
            open,
            summary,
            bare: true,
        } => {
            // The app's own summary and fold: its node dresses the button,
            // its children stay, folding as they follow `open`.
            let cx = need(&mut cx);
            let open = bridge(cx, open, Value::truthy, Value::Bool);
            let content = column().children(node.children.iter().map(|c| lower(c, low)));
            disclosure_with(
                open,
                |bare| match summary {
                    Summary::Node(summary) => crate::lower::dress(bare, summary, None, vm, low, cx),
                    Summary::Text(text) => bare.child(zgx::compose::text(text.clone())),
                },
                content,
            )
        }
        Library::Disclosure { open, summary, .. } => {
            let open = bridge(need(&mut cx), open, Value::truthy, Value::Bool);
            let summary = match summary {
                Summary::Text(text) => zgx::compose::text(text.clone()),
                Summary::Node(node) => lower(node, low),
            };
            let (children, low) = (node.children.clone(), low.clone());
            disclosure(open, summary, move || {
                column()
                    .gap(8.)
                    .children(children.iter().map(|c| lower(c, &low)))
            })
        }
        Library::Accordion { open } => {
            let ids: Rc<[Value]> = node
                .children
                .iter()
                .map(|c| section(&c.kind).map_or(Value::Nil, |(id, _)| id.clone()))
                .collect();
            let index = {
                let ids = ids.clone();
                move |v: &Value| ids.iter().position(|id| id == v)
            };
            let open = bridge_with(need(&mut cx), open, index, move |i: Option<usize>| {
                i.and_then(|i| ids.get(i).cloned()).unwrap_or_default()
            });
            let sections = node.children.iter().map(|section| {
                let title = crate::library::section(&section.kind)
                    .map_or_else(String::new, |(_, title)| title.clone());
                let (content, low) = (section.children.clone(), low.clone());
                let build: Rc<dyn Fn() -> View> = Rc::new(move || {
                    column()
                        .gap(8.)
                        .children(content.iter().map(|c| lower(c, &low)))
                });
                (title, build)
            });
            accordion(open, sections.collect::<Vec<_>>())
        }
        // Lowered by its accordion.
        Library::Section { .. } => div(),
        Library::VoiceGlyph(glyph) => voice_glyph_view(glyph, need(&mut cx)),
    }
}

/// `ui.voice_glyph { … }`: a field (the call's disc, `dots` across) or a
/// beam (`kind = "beam"`, filling its box), on dots `dot` wide.
fn voice_glyph_node(lua: &Lua, table: Table) -> mlua::Result<mlua::AnyUserData> {
    // A state, or a function kept current in Rust (run as what it reads
    // changes, never a frame).
    let followed = |name: &str| -> mlua::Result<Option<Signal<Value>>> {
        let value: mlua::Value = table.get(name)?;
        if let Some(state) = crate::node::state_of(&value) {
            return Ok(Some(state));
        }
        Ok(match value {
            mlua::Value::Nil => None,
            mlua::Value::Function(f) => {
                Some(crate::node::computed(lua, &*crate::node::env(lua)?, f))
            }
            other => {
                let value = crate::value::convert(other, None)?;
                Some(crate::node::env(lua)?.runtime.signal(value))
            }
        })
    };
    let beam = match table.get::<Option<String>>("kind")?.as_deref() {
        None | Some("field") => false,
        Some("beam") => true,
        Some(other) => {
            return Err(mlua::Error::runtime(format!(
                "ui.voice_glyph's `kind` is \"field\" or \"beam\", not {other:?}"
            )));
        }
    };
    let dots = match table.get::<mlua::Value>("dots")? {
        mlua::Value::Nil => (44, 44),
        mlua::Value::Table(pair) => (pair.get::<f64>(1)? as usize, pair.get::<f64>(2)? as usize),
        n => {
            let n = lua.unpack::<f64>(n)? as usize;
            (n, n)
        }
    };
    let radius = table.get::<Option<f32>>("radius")?.unwrap_or(0.);
    let outline = match table.get::<Option<String>>("outline")?.as_deref() {
        None | Some("square") => voice::Outline::Square,
        Some("disc") => voice::Outline::Disc,
        Some("stadium") => voice::Outline::Stadium,
        Some("rounded") => voice::Outline::Rounded(radius),
        Some("under") => voice::Outline::Under(radius),
        Some(other) => {
            return Err(mlua::Error::runtime(format!(
                "ui.voice_glyph's `outline` is square, disc, stadium, rounded or under, not {other:?}"
            )));
        }
    };
    let inks = |name: &str| -> mlua::Result<Option<[Themed<Color>; 3]>> {
        let Some(list) = table.get::<Option<Table>>(name)? else {
            return Ok(None);
        };
        let mut out = Vec::new();
        for ink in list.sequence_values::<mlua::Value>() {
            let value = crate::value::convert(ink?, None)?;
            out.push(crate::node::themed_color(&value).ok_or_else(|| {
                mlua::Error::runtime(format!(
                    "ui.voice_glyph's `{name}` are colours or theme tokens"
                ))
            })?);
        }
        out.try_into()
            .map(Some)
            .map_err(|_| mlua::Error::runtime(format!("ui.voice_glyph's `{name}` are three inks")))
    };
    let glyph = Glyph {
        beam,
        dots,
        dot: table
            .get::<Option<f32>>("dot")?
            .unwrap_or(if beam { 2.4 } else { 3. }),
        outline,
        falloff: table.get("falloff")?,
        rest: table.get("rest")?,
        soft_rim: table.get::<Option<bool>>("soft_rim")?.unwrap_or(false),
        dissolve: table.get::<Option<bool>>("dissolve")?.unwrap_or(false),
        touch: table.get::<Option<bool>>("touch")?.unwrap_or(false),
        mode: followed("mode")?,
        speaking: followed("speaking")?,
        still: followed("still")?,
        label: followed("label")?,
        agent: inks("agent_inks")?,
        user: inks("user_inks")?,
    };
    // The glyph's own, not the element's (`outline` is a style's).
    for key in [
        "kind",
        "dots",
        "dot",
        "outline",
        "radius",
        "falloff",
        "rest",
        "soft_rim",
        "dissolve",
        "touch",
        "mode",
        "speaking",
        "still",
        "label",
        "agent_inks",
        "user_inks",
    ] {
        table.raw_remove(key)?;
    }
    node_ud(
        lua,
        fill(
            lua,
            Node::new(
                owner(lua)?,
                Kind::Library(Box::new(Library::VoiceGlyph(Box::new(glyph)))),
            ),
            Some(&table),
        )?,
    )
}

fn voice_glyph_view(glyph: &Glyph, cx: &mut Context) -> View {
    let grid = voice::Grid::dense(glyph.dot);
    let options = if glyph.beam {
        let mut beam = voice::Beam::default();
        if let Some(rest) = glyph.rest {
            beam = beam.resting(rest);
        }
        voice::VoiceGlyph::beam(beam, grid)
    } else {
        let mut field = voice::Field::new(voice::Rings::Round);
        if glyph.soft_rim {
            field = field.soft_rimmed();
        }
        if glyph.dissolve {
            field = field.dissolving();
        }
        if let Some(falloff) = glyph.falloff {
            field = field.falling(falloff);
        }
        if let Some(rest) = glyph.rest {
            field = field.resting(rest);
        }
        voice::VoiceGlyph::field(field, glyph.dots.0, glyph.dots.1, grid)
    };
    let mode = glyph.mode.clone();
    let speaking = glyph.speaking.clone();
    let still = glyph.still.clone();
    let (agent, user, theme) = (glyph.agent, glyph.user, cx.theme());
    let rgb = move |ink: Themed<Color>| -> voice::glyph::Rgb {
        let Color(r, g, b, _) = match ink {
            Themed::Token(token) => theme.get(token).color().unwrap_or(Color(0, 0, 0, 0)),
            Themed::Value(color) => color,
        };
        [r, g, b].map(|c| c as f32 / 255.)
    };
    let accent = Themed::Token(zgx::theme::token("accent"));
    let options = options
        .outline(glyph.outline)
        .mode(move || {
            mode.as_ref().map_or(voice::Mode::Listening, |mode| {
                match mode.with(|v| v.to_string()).as_str() {
                    "connecting" => voice::Mode::Connecting,
                    "thinking" => voice::Mode::Thinking,
                    "asking" => voice::Mode::Asking,
                    "processing" => voice::Mode::Processing,
                    "muted" => voice::Mode::Muted,
                    _ => voice::Mode::Listening,
                }
            })
        })
        .speaker(move || {
            speaking.as_ref().map_or(voice::Speaker::Nobody, |who| {
                match who.with(|v| v.to_string()).as_str() {
                    "user" => voice::Speaker::User,
                    "agent" => voice::Speaker::Agent,
                    _ => voice::Speaker::Nobody,
                }
            })
        })
        .still(move || {
            still
                .as_ref()
                .is_some_and(|still| still.with(Value::truthy))
        })
        .inks(move || voice::Inks {
            agent: agent.map_or(voice::glyph::SUNRISE, |inks| inks.map(&rgb)),
            ..voice::Inks::new(user.unwrap_or([accent; 3]).map(&rgb))
        });
    let options = match glyph.label.clone() {
        Some(label) => options.label(move || label.with(Value::to_string)),
        None => options,
    };
    voice::voice_glyph(if glyph.touch {
        options.touchable()
    } else {
        options
    })
}

/// An option table that draws its part of the control (a segment, a menu
/// item), as a node: one with children, or properties besides its `own`
/// fields. `None` for one that only says what it is.
fn drawn(lua: &Lua, option: &Table, own: &[&str]) -> mlua::Result<Option<Rc<Node>>> {
    let mut draws = false;
    for pair in option.pairs::<mlua::Value, mlua::Value>() {
        let (key, _) = pair?;
        if !matches!(&key, mlua::Value::String(k) if own.contains(&&*k.to_string_lossy())) {
            draws = true;
            break;
        }
    }
    if !draws {
        return Ok(None);
    }
    let node = fill(lua, Node::new(owner(lua)?, Kind::Button), Some(option))?;
    Ok(Some(Rc::new(node)))
}

/// `{ id, title?, detail?, shortcut? }`: a command a palette lists.
fn palette_command(c: &Table) -> mlua::Result<PaletteCommand> {
    let id: String = c.get("id")?;
    let title: Option<String> = c.get("title")?;
    let mut command = PaletteCommand::new(id.clone(), title.unwrap_or(id));
    command.detail = c.get("detail")?;
    command.shortcut = c
        .get::<Option<String>>("shortcut")?
        .map(crate::lower::shown_shortcut);
    Ok(command)
}

/// `ui.toast { title, body?, kind?, duration?, action = { label, run }? }`:
/// shows a toast; its id dismisses it (`ui.dismiss_toast`).
fn toast(lua: &Lua, table: Table) -> mlua::Result<u64> {
    let env = crate::node::env(lua)?;
    let (runtime, vm) = (env.runtime.clone(), env.vm.clone());
    drop(env);
    let mut toast = Toast::new(
        table
            .get::<String>("title")
            .map_err(|_| mlua::Error::runtime("ui.toast needs a `title`"))?,
    );
    toast.body = table.get("body")?;
    toast.kind = match table.get::<Option<String>>("kind")?.as_deref() {
        None | Some("info") => ToastKind::Info,
        Some("success") => ToastKind::Success,
        Some("warning") => ToastKind::Warning,
        Some("error") => ToastKind::Error,
        Some(other) => {
            return Err(mlua::Error::runtime(format!(
                "ui.toast's `kind` is \"info\", \"success\", \"warning\" or \"error\", not {other:?}"
            )));
        }
    };
    toast.duration = table
        .get::<Option<f64>>("duration")?
        .map(|ms| crate::duration_ms("ui.toast's duration", ms))
        .transpose()?;
    if let Some(action) = table.get::<Option<Table>>("action")? {
        let label: String = action.get("label")?;
        let run: mlua::Function = action.get("run")?;
        toast = toast.action(label, move || {
            if let Some(vm) = vm.upgrade()
                && let Err(error) = vm.call::<()>(&run, ())
            {
                vm.report(error);
            }
        });
    }
    Ok(Toaster::of(&runtime).show(toast))
}

/// A tab item's id: its `id`, or the item itself (a bare string).
fn tab_id(item: &Value) -> String {
    match item {
        Value::Str(s) => s.to_string(),
        _ => item.field("id").map(Value::to_string).unwrap_or_default(),
    }
}

/// `bare`, a component's own part, dressed by the node `f` returns for
/// `args`: built as a row is (`ui.use_state` keeps to it), its styles,
/// children and handlers laid over the part.
fn dressed(
    bare: View,
    f: &Function,
    args: impl mlua::IntoLuaMulti,
    vm: &Rc<Vm>,
    low: &Rc<Lowering>,
    cx: &mut Context,
) -> View {
    let scope = Rc::new(crate::node::Scope::default());
    let previous = vm
        .lua
        .app_data_ref::<crate::node::Env>()
        .map(|env| env.scope.replace(Some(scope.clone())));
    let result = vm.call::<mlua::Value>(f, args);
    if let (Some(previous), Some(env)) = (previous, vm.lua.app_data_ref::<crate::node::Env>()) {
        *env.scope.borrow_mut() = previous;
    }
    for resource in scope.retained.borrow_mut().drain(..) {
        cx.retain(resource);
    }
    let node = match result {
        Ok(value) => match expect_node(value, "a dressed part") {
            Ok(node) => node,
            Err(error) => {
                vm.report(error);
                return bare;
            }
        },
        Err(error) => {
            vm.report(error);
            return bare;
        }
    };
    let view = crate::lower::dress(bare, &node, None, vm, low, cx);
    let mounted: Vec<Function> = scope.mounted.borrow_mut().drain(..).collect();
    if mounted.is_empty() {
        return view;
    }
    let vm = vm.clone();
    view.on_mount(move |_| {
        for f in mounted {
            if let Err(e) = vm.call::<()>(&f, ()) {
                vm.report(e);
            }
        }
    })
}

/// A select's option: its value, what it shows, whether it is disabled,
/// its item's id, and the node of one that draws its item.
#[derive(Clone)]
pub(crate) struct Choice {
    value: Value,
    shown: String,
    disabled: bool,
    id: Option<String>,
    drawn: Option<Rc<Node>>,
}

/// What a disclosure's summary shows: text, or a node of the app's.
#[derive(Clone)]
pub(crate) enum Summary {
    Text(String),
    Node(Rc<Node>),
}

/// `value` as a typed signal that follows it, one way (an app's list).
fn follow_with<T: PartialEq + Clone + 'static>(
    cx: &mut Context,
    value: &Signal<Value>,
    from: impl Fn(&Value) -> T + 'static,
) -> Signal<T> {
    let typed = cx.state(value.with_untracked(&from));
    let (v, t) = (value.clone(), typed.clone());
    cx.retain(cx.runtime().effect(move || {
        t.set(v.with(&from));
    }));
    typed
}

/// `bridge`, converting with closures (a value to its index among options).
fn bridge_with<T: PartialEq + Clone + 'static>(
    cx: &mut Context,
    value: &Signal<Value>,
    from: impl Fn(&Value) -> T + 'static,
    to: impl Fn(T) -> Value + 'static,
) -> Signal<T> {
    let from = Rc::new(from);
    let typed = cx.state(value.with_untracked(|v| from(v)));
    let runtime = cx.runtime();
    let (v, t, f) = (value.clone(), typed.clone(), from.clone());
    cx.retain(runtime.effect(move || {
        t.set(f(&v.get()));
    }));
    let (v, t) = (value.clone(), typed.clone());
    let mut first = true;
    cx.retain(runtime.effect(move || {
        let next = t.get();
        if !std::mem::take(&mut first) {
            v.set(to(next));
        }
    }));
    typed
}

/// Whether a state's list holds `records`, in any order.
fn state_rows_equal(state: &Value, records: &[Value]) -> bool {
    let mut held: Vec<i64> = state
        .list()
        .iter()
        .filter_map(Value::as_f64)
        .map(|n| n as i64)
        .collect();
    let mut given: Vec<i64> = records
        .iter()
        .filter_map(Value::as_f64)
        .map(|n| n as i64)
        .collect();
    held.sort_unstable();
    given.sort_unstable();
    held == given
}
