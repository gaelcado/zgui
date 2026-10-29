use std::{cell::RefCell, rc::Rc, time::Instant};
use zgx::{
    compose::{TaskRunner, prelude::*},
    frame::{Frame, FrameClock},
    scene::{Color, NodeKind},
    task::LocalExecutor,
    widgets::Ui,
};

/// The alpha of each run of the paragraph under `owner`, with its range.
fn alphas(ui: &Ui, owner: zgx::scene::NodeId) -> Vec<(std::ops::Range<usize>, u8)> {
    let scene = ui.scene.borrow();
    let node = scene.children(owner)[0];
    let NodeKind::RichText { text } = scene.kind(node) else {
        panic!("a paragraph")
    };
    text.runs()
        .iter()
        .map(|r| (r.range.clone(), r.color.3))
        .collect()
}

/// A frame well past every fade, then the tasks it wakes.
fn settle(clock: &FrameClock, executor: &Rc<RefCell<LocalExecutor>>, index: u64) {
    executor.borrow_mut().tick();
    clock.deliver(Frame {
        index,
        time: Instant::now() + std::time::Duration::from_secs(5),
        interval: std::time::Duration::from_millis(8),
    });
    executor.borrow_mut().tick();
}

#[test]
fn appended_text_fades_in_frame_by_frame_and_then_stops() {
    let mut ui = Ui::new(400., 100.);
    let executor = Rc::new(RefCell::new(LocalExecutor::new()));
    let clock = FrameClock::new();
    let text = ui.signal(String::from("Hello"));
    let source = text.clone();
    let handle = ui.mount(provide(
        clock.clone(),
        provide(
            TaskRunner::from_executor(executor.clone()),
            rich_text_signal(move || {
                vec![text_span(source.get()).text_color(Color(200, 200, 200, 255))]
            })
            .veil(None)
            .id("reply"),
        ),
    ));
    ui.prepare_frame();
    let owner = handle.find("reply").unwrap();
    // The first text fades in whole.
    assert_eq!(alphas(&ui, owner), [(0..5, 0)]);
    executor.borrow_mut().tick();
    assert!(clock.wants_frame(), "fading: a frame asked");
    settle(&clock, &executor, 1);
    assert_eq!(alphas(&ui, owner), [(0..5, 255)], "settled");
    executor.borrow_mut().tick();
    assert!(!clock.wants_frame(), "settled: no more frames");
    // What it gains fades; what it had stays.
    text.set("Hello world".into());
    ui.prepare_frame();
    assert_eq!(alphas(&ui, owner), [(0..5, 255), (5..11, 0)]);
    settle(&clock, &executor, 2);
    assert_eq!(alphas(&ui, owner), [(0..11, 255)]);
}

#[test]
fn a_keyed_veil_fades_only_what_a_paragraph_built_again_gained() {
    let mut ui = Ui::new(400., 100.);
    let executor = Rc::new(RefCell::new(LocalExecutor::new()));
    let clock = FrameClock::new();
    let mount = |ui: &mut Ui, text: &'static str| {
        let view = provide(
            clock.clone(),
            provide(
                TaskRunner::from_executor(executor.clone()),
                View::from(rich_text().child(text_span(text)))
                    .id("block")
                    .veil(Some("veil-test:reply-1:0")),
            ),
        );
        let handle = ui.mount(view);
        ui.prepare_frame();
        handle
    };
    let first = mount(&mut ui, "One");
    settle(&clock, &executor, 1);
    first.unmount();
    let second = mount(&mut ui, "One two");
    let owner = second.find("block").unwrap();
    assert_eq!(alphas(&ui, owner), [(0..3, 255), (3..7, 0)]);
}
