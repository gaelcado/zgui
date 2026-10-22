//! A page served from a scheme of the app's own, with a script injected
//! before the page's and a navigation policy (WKWebView on macOS).
//!
//! `cargo run -p zgui-desktop --example web_view_schemes`
//! `-- --fixture`: checks each against the live page, prints `FIXTURE`
//! lines and exits (non-zero on failure).
use std::{cell::RefCell, rc::Rc, time::Duration};
use zgui::{
    compose::prelude::*,
    web_view::{
        SchemeHandler, SchemeResponse, UserScript, WebView, WebViewEvent, WebViewOptions, web_view,
    },
};
use zgui_desktop::{Application, WindowOptions};

const PAGE: &str = r#"<!doctype html><meta charset="utf-8"><title>served</title>
<body style="font: 20px -apple-system, sans-serif; padding: 40px">
<h1>Served by the app</h1>
<p id="facts"></p>
<script>
  document.getElementById("facts").textContent = JSON.stringify({
    origin: location.origin, secure: isSecureContext, injected: window.injectedFirst === true,
  })
</script>"#;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let fixture = std::env::args().any(|arg| arg == "--fixture");
    Application::new()
        .window(WindowOptions {
            title: "zgui web view schemes".into(),
            width: 900.,
            height: 600.,
            ..Default::default()
        })
        .run(move |cx| {
            // Served from a thread, as a real handler (disk, network) would.
            let demo = SchemeHandler::new("demo", |request, responder| {
                std::thread::spawn(move || {
                    let path = request
                        .url
                        .split_once("://")
                        .map(|(_, rest)| rest)
                        .unwrap_or("");
                    let response = match path {
                        p if p.ends_with("/missing") => return drop(responder),
                        _ => SchemeResponse {
                            status: 200,
                            headers: vec![(
                                "content-type".into(),
                                "text/html; charset=utf-8".into(),
                            )],
                            body: PAGE.as_bytes().to_vec(),
                        },
                    };
                    responder.respond(response);
                });
            });
            let web = WebView::new(
                &cx.ui.runtime,
                WebViewOptions {
                    schemes: vec![demo],
                    scripts: vec![UserScript {
                        source: "window.injectedFirst = true".into(),
                        main_frame_only: true,
                    }],
                    ..Default::default()
                },
            );
            web.set_navigation_policy(|request| !request.url.contains("blocked"));
            web.load_url("demo://site.one/");
            if fixture {
                run_fixture(cx, web.clone());
            }
            cx.render(column().grow().child(web_view(&web).grow()));
        })
}

fn run_fixture(cx: &mut zgui_desktop::WindowContext, web: WebView) {
    let failures = Rc::new(RefCell::new(0_u32));
    let check = {
        let failures = failures.clone();
        move |ok: bool, what: &str, detail: String| {
            println!(
                "FIXTURE {} {what}: {detail}",
                if ok { "ok" } else { "FAILED" }
            );
            if !ok {
                *failures.borrow_mut() += 1;
            }
        }
    };
    let failed_loads = Rc::new(RefCell::new(Vec::<String>::new()));
    let subscription = {
        let failed_loads = failed_loads.clone();
        web.on_event(move |event| {
            if let WebViewEvent::NavigationFailed { url, .. } = event {
                failed_loads.borrow_mut().push(url.clone());
            }
        })
    };
    cx.tasks.spawn(async move {
        let _subscription = subscription;
        zgui::timer::sleep(Duration::from_secs(2)).await;
        let (sender, receiver) = std::sync::mpsc::channel();
        web.evaluate_js(
            "document.getElementById('facts').textContent",
            move |result| {
                let _ = sender.send(result);
            },
        );
        zgui::timer::sleep(Duration::from_millis(300)).await;
        let facts = receiver
            .try_recv()
            .ok()
            .and_then(Result::ok)
            .unwrap_or_default();
        check(
            facts.contains(r#"\"origin\":\"demo://site.one\""#),
            "own origin",
            facts.clone(),
        );
        check(
            facts.contains(r#"\"secure\":true"#),
            "secure context",
            facts.clone(),
        );
        check(
            facts.contains(r#"\"injected\":true"#),
            "script ran before the page's",
            facts.clone(),
        );

        web.load_url("demo://blocked.example/");
        zgui::timer::sleep(Duration::from_millis(800)).await;
        check(
            web.url().contains("site.one"),
            "policy cancels a navigation",
            web.url(),
        );

        web.load_url("demo://site.one/missing");
        zgui::timer::sleep(Duration::from_millis(800)).await;
        let failed = failed_loads
            .borrow()
            .iter()
            .any(|url| url.ends_with("/missing"));
        check(
            failed,
            "a dropped responder fails the load",
            format!("{:?}", failed_loads.borrow()),
        );

        let failures = *failures.borrow();
        println!("FIXTURE {failures} failures");
        std::process::exit(if failures == 0 { 0 } else { 1 });
    });
}
