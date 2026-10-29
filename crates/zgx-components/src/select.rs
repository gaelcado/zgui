//! A select: a button showing the chosen option that opens a menu of them
//! over itself, the chosen one under the pointer, as AppKit's pop-up button
//! (and WAI-ARIA's select-only combobox). Closed, typing chooses the next
//! option starting with what was typed, Up and Down and Enter and Space
//! open it; open, it is a menu (arrows, typeahead, Enter, Escape).
use std::{
    cell::RefCell,
    rc::Rc,
    time::{Duration, Instant},
};
use zgx::{
    compose::{Context, Placement, View, button, component, menu, menu_item, text, text_signal},
    input::{EventPhase, InputEvent, Key},
    reactive::Signal,
    semantics::Role,
    style::Styled,
    theme::tok,
};

/// An option of a [`select`]: its value, what it shows, and whether it can
/// be chosen.
#[derive(Clone, Debug, PartialEq)]
pub struct SelectOption {
    /// What `select`'s value is when it is chosen.
    pub value: String,
    /// What it shows.
    pub label: String,
    /// Shown but not chosen.
    pub disabled: bool,
    /// Its menu item's id: its value unless set.
    pub id: Option<String>,
}
impl SelectOption {
    /// An option showing `label`.
    pub fn new(value: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            value: value.into(),
            label: label.into(),
            disabled: false,
            id: None,
        }
    }
    /// One shown but not chosen.
    pub fn disabled(mut self) -> Self {
        self.disabled = true;
        self
    }
    /// With its menu item's id `id`.
    pub fn id(mut self, id: impl Into<String>) -> Self {
        self.id = Some(id.into());
        self
    }
    fn item_id(&self) -> String {
        self.id.clone().unwrap_or_else(|| self.value.clone())
    }
}

/// Gives a part of a [`select_with`] its look and content.
pub type Dress = Box<dyn FnOnce(View, &mut Context) -> View>;
/// Gives option `i`'s menu item its look and content.
pub type DressItem = Box<dyn FnMut(usize, View, &mut Context) -> View>;

/// The parts of a [`select_with`] the app draws; any it leaves keep the
/// select's own.
#[derive(Default)]
pub struct SelectParts {
    /// Dresses the button (its role, value and keys set): styles over its
    /// own look, handlers.
    pub button: Option<Dress>,
    /// The button comes to `button` bare: none of the select's look, nor
    /// its face (the chosen option's label and a chevron), the app's own.
    pub bare_button: bool,
    /// The menu's panel, its items in it: styles, motion.
    pub menu: Option<Dress>,
    /// Each option's item, bare (its label naming it): with children of
    /// its own it draws itself, the check included (the select still marks
    /// it checked to assistive technology).
    pub item: Option<DressItem>,
    /// Where the menu opens. Without it, over the button, the chosen
    /// option over it (AppKit's pop-up button).
    pub placement: Option<Placement>,
}

/// How long typed letters add up to one search, as a menu's typeahead.
const TYPEAHEAD: Duration = Duration::from_millis(750);

/// A button showing the option `value` names (`placeholder` when none
/// does) that opens a menu of `options`, chosen one over the button; its
/// menu is as wide as it, at least. `label` names it.
pub fn select(
    label: impl Into<String>,
    value: Signal<String>,
    options: Vec<SelectOption>,
    placeholder: impl Into<String>,
) -> View {
    select_with(label, value, options, placeholder, SelectParts::default())
}

/// A [`select`] whose button, menu and items the app draws (`parts`): it
/// keeps what makes it a select (the roles, what assistive technology
/// hears, typing to choose, the menu's keys), and none of its own look
/// where the app gives one.
pub fn select_with(
    label: impl Into<String>,
    value: Signal<String>,
    options: Vec<SelectOption>,
    placeholder: impl Into<String>,
    parts: SelectParts,
) -> View {
    let (label, placeholder) = (label.into(), placeholder.into());
    let options = Rc::new(options);
    component(move |cx| {
        // A label that changes (a translation, a state), where the caller
        // gave one (`FollowedLabel::around`).
        let followed = zgx::compose::FollowedLabel::take(cx);
        let SelectParts {
            button: dress_button,
            bare_button,
            menu: dress_menu,
            item: mut dress_item,
            placement,
        } = parts;
        let open = cx.runtime().signal(false);
        let shown = {
            let (value, options, placeholder) =
                (value.clone(), options.clone(), placeholder.clone());
            move || {
                value.with(|v| {
                    options
                        .iter()
                        .find(|o| o.value == *v)
                        .map_or(placeholder.clone(), |o| o.label.clone())
                })
            }
        };
        let search: Rc<RefCell<(String, Instant)>> =
            Rc::new(RefCell::new((String::new(), Instant::now())));
        let (key_value, key_options, key_open) = (value.clone(), options.clone(), open.clone());
        let (expanded, value_text, label_text) = (open.clone(), shown.clone(), shown.clone());
        let trigger = button()
            .role(Role::ComboBox)
            .accessible_label_or(label.clone(), followed.as_ref())
            .value_when(value_text)
            .expanded_when(move || expanded.get());
        let trigger = if bare_button {
            trigger
        } else {
            trigger
                .min_w(120.)
                .gap(8.)
                .justify_between()
                .child(text_signal(label_text).grow())
                .child(text("⌄").text_color(tok::TEXT_SECONDARY))
        };
        let trigger = match dress_button {
            Some(dress) => dress(trigger, cx),
            None => trigger,
        };
        let trigger = trigger.on_event(move |cx| {
            if cx.phase == EventPhase::Capture || key_open.with_untracked(|o| *o) {
                return;
            }
            let InputEvent::KeyDown { key, modifiers, .. } = &cx.event else {
                return;
            };
            match key {
                Key::ArrowDown | Key::ArrowUp => {
                    key_open.set(true);
                }
                // Typing chooses, closed, as a native select does.
                Key::Character(typed)
                    if !(modifiers.meta || modifiers.control || modifiers.alt) =>
                {
                    let mut search = search.borrow_mut();
                    if search.1.elapsed() > TYPEAHEAD {
                        search.0.clear();
                    }
                    search.0.push_str(&typed.to_lowercase());
                    search.1 = Instant::now();
                    let current = key_value.with_untracked(Clone::clone);
                    let at = key_options.iter().position(|o| o.value == current);
                    // One letter again cycles through those starting with it.
                    let first = search.0.chars().next();
                    let repeated = search.0.chars().all(|c| Some(c) == first);
                    let prefix = if repeated {
                        search.0[..search.0.chars().next().map_or(0, char::len_utf8)].to_owned()
                    } else {
                        search.0.clone()
                    };
                    let start = if repeated {
                        at.map_or(0, |a| a + 1)
                    } else {
                        at.unwrap_or(0)
                    };
                    let n = key_options.len();
                    let found = (0..n).map(|i| (start + i) % n).find(|&i| {
                        let o = &key_options[i];
                        !o.disabled && o.label.to_lowercase().starts_with(&prefix)
                    });
                    if let Some(i) = found {
                        key_value.set(key_options[i].value.clone());
                    }
                }
                _ => return,
            }
            cx.prevent_default();
            cx.stop_propagation();
        });
        let mut list = menu(label.clone(), open.clone(), trigger)
            .accessible_label_or(label.clone(), followed.as_ref())
            .match_anchor_width();
        list = match placement {
            Some(placement) => list.placement(placement),
            None => list.open_over({
                let (value, options) = (value.clone(), options.clone());
                // The chosen option's item, by its id.
                move || {
                    value.with(|v| {
                        options
                            .iter()
                            .find(|o| o.value == *v)
                            .map_or_else(|| v.clone(), SelectOption::item_id)
                    })
                }
            }),
        };
        for (i, option) in options.iter().enumerate() {
            let (checked, chosen, id, set) = (
                value.clone(),
                value.clone(),
                option.value.clone(),
                option.value.clone(),
            );
            let item = menu_item(option.label.clone());
            let item = match dress_item.as_mut() {
                Some(dress) => dress(i, item, cx),
                None => item,
            };
            let item = item
                .id(option.item_id())
                .menu_radio()
                .menu_checked_when(move || checked.with(|v| *v == id))
                .disabled(option.disabled)
                .on_click(move || {
                    chosen.set(set.clone());
                });
            list = list.child(item);
        }
        match dress_menu {
            Some(dress) => dress(list, cx),
            None => list,
        }
    })
}
