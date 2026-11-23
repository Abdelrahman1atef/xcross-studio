//! xcross-screen: live iPhone screen for XCross Studio (spec 048), started by `xcross screen`.
//!
//! Commands (one JSON object per line on stdout, logs on stderr):
//!   xcross-screen devices                         iPhones reachable through the screen driver
//!   xcross-screen stream --serial <udid> [--listen 127.0.0.1:0] [--seconds N]
//!
//! `stream` uses Apple's QuickTime screen capture over USB (ZenLink's `usbdirect`), serves the
//! H.264 stream on 127.0.0.1 behind a random token, and stops when stdin closes. Its stdin also
//! takes `wda http://127.0.0.1:<port>` (touch through WebDriverAgent, started by the engine).

mod annexb;
mod driver;
mod hub;
mod wda;


use std::net::TcpListener;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::json;
use zenlink_apple::usbdirect::{h264, libusb0, session, wire::Format};

/// The host display ZenLink announces to the device (`apps/desktop/src/usbdirect.rs`).
const HOST_DISPLAY: (u32, u32) = (3840, 2160);

fn emit(v: serde_json::Value) {
    let mut v = v;
    v["v"] = json!(1);
    println!("{v}");
}

struct StderrLog;
impl log::Log for StderrLog {
    fn enabled(&self, m: &log::Metadata) -> bool {
        m.level() <= log::max_level()
    }
    fn log(&self, r: &log::Record) {
        if self.enabled(r.metadata()) {
            eprintln!("[{}] {}: {}", r.level(), r.target(), r.args());
        }
    }
    fn flush(&self) {}
}

fn main() {
    static LOGGER: StderrLog = StderrLog;
    let _ = log::set_logger(&LOGGER);
    log::set_max_level(match std::env::var("XCROSS_SCREEN_LOG").as_deref() {
        Ok("debug") => log::LevelFilter::Debug,
        Ok("off") => log::LevelFilter::Off,
        _ => log::LevelFilter::Info,
    });

    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("devices") => devices(),
        Some("stream") => stream(&args[1..]),
        Some("driver") => driver_cmd(&args[1..]),
        Some("--version") => {
            println!("xcross-screen {}", env!("CARGO_PKG_VERSION"));
            0
        }
        _ => {
            eprintln!(
                "usage: xcross-screen devices | stream --serial <udid> [--listen 127.0.0.1:0] [--seconds N]\n\
                 \x20      xcross-screen driver status | enable --serial <udid> | restore --serial <udid>"
            );
            64
        }
    };
    std::process::exit(code);
}

fn opt<'a>(args: &'a [String], name: &str) -> Option<&'a str> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).map(String::as_str)
}

fn devices() -> i32 {
    match libusb0::apple_devices() {
        Ok(list) => {
            let devices: Vec<_> = list
                .iter()
                .map(|(serial, d)| {
                    let capture = d.configs.iter().any(|c| {
                        c.interfaces.iter().any(|i| i.class == 0xFF && i.subclass == 0x2A)
                    });
                    json!({ "serial": serial, "configurations": d.configs.len(), "captureReady": capture })
                })
                .collect();
            emit(json!({ "type": "screen_devices", "driver": "libusb0", "devices": devices }));
            0
        }
        Err(e) => {
            emit(json!({ "type": "screen_devices", "driver": "missing", "devices": [], "message": e }));
            0
        }
    }
}

/// `driver status`: each plugged-in iPhone and its driver; `driver enable|restore --serial`:
/// Smooth mode on/off (Windows; one admin prompt).
fn driver_cmd(args: &[String]) -> i32 {
    if !cfg!(windows) {
        emit(json!({ "type": "screen_driver", "devices": [], "message": "Smooth mode needs no driver change on this system." }));
        return 0;
    }
    match args.first().map(String::as_str) {
        Some("status") => match driver::nodes() {
            Ok(nodes) => {
                let devices: Vec<_> = nodes
                    .iter()
                    .map(|n| json!({ "serial": n.serial(), "instance": n.instance, "name": n.name, "state": n.state() }))
                    .collect();
                emit(json!({ "type": "screen_driver", "devices": devices }));
                0
            }
            Err(e) => {
                emit(json!({ "type": "screen_driver", "devices": [], "message": e }));
                1
            }
        },
        Some(action @ ("enable" | "restore")) => {
            let Some(serial) = opt(args, "--serial") else {
                eprintln!("driver {action}: --serial <udid> is required");
                return 64;
            };
            let event = driver::change(serial, action == "enable");
            let ok = event["ok"].as_bool().unwrap_or(false);
            emit(event);
            if ok { 0 } else { 1 }
        }
        _ => {
            eprintln!("usage: xcross-screen driver status | enable --serial <udid> | restore --serial <udid>");
            64
        }
    }
}

/// Receives the session's callbacks and feeds the hub.
struct Feed {
    hub: Arc<hub::Hub>,
}

impl session::Sink for Feed {
    fn state(&self, phase: &'static str, detail: &str) {
        emit(json!({ "type": "screen_preparing", "step": phase, "detail": detail }));
    }
    fn format(&self, f: &Format) {
        let avcc = h264::rewrite_avcc(&f.config);
        match annexb::avcc_to_annexb(&avcc) {
            Some(cfg) => {
                self.hub.set_config(cfg, f.width, f.height);
                emit(json!({ "type": "screen_format", "codec": "h264", "width": f.width, "height": f.height }));
            }
            None => log::warn!("unreadable decoder configuration ({} bytes)", f.config.len()),
        }
    }
    fn video(&self, au: Vec<u8>) {
        let au = h264::rewrite_access_unit(&au).unwrap_or(au);
        if let Some((annexb, idr)) = annexb::au_to_annexb(&au) {
            self.hub.push(annexb, idr);
        }
    }
    fn audio(&self, _pcm: &[u8]) {}
    fn product(&self, product_type: &str) {
        emit(json!({ "type": "screen_device", "productType": product_type }));
    }
}

fn stream(args: &[String]) -> i32 {
    let Some(serial) = opt(args, "--serial") else {
        eprintln!("stream: --serial <udid> is required");
        return 64;
    };
    let listen = opt(args, "--listen").unwrap_or("127.0.0.1:0");
    if !listen.starts_with("127.0.0.1:") {
        eprintln!("stream: --listen must be on 127.0.0.1");
        return 64;
    }
    let seconds: Option<u64> = opt(args, "--seconds").and_then(|s| s.parse().ok());

    // Windows: say plainly when the iPhone is on Apple's driver (Smooth mode off) or not
    // plugged in, instead of a generic "device not found" from the capture session.
    if cfg!(windows) {
        if let Ok(nodes) = driver::nodes() {
            match driver::find(&nodes, serial) {
                None => {
                    emit(json!({ "type": "screen_end", "reason": "unplugged", "message": "This iPhone is not plugged in by USB." }));
                    return 1;
                }
                Some(node) if node.state() != "smooth" => {
                    emit(json!({ "type": "screen_end", "reason": "driver_needed", "message": "Smooth mode is off for this iPhone." }));
                    return 1;
                }
                Some(_) => {}
            }
        }
    }

    let listener = match TcpListener::bind(listen) {
        Ok(l) => l,
        Err(e) => {
            emit(json!({ "type": "screen_end", "reason": "error", "message": format!("listen: {e}") }));
            return 1;
        }
    };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    let hub = hub::Hub::new(uuid::Uuid::new_v4().simple().to_string());
    hub.serve(listener);

    let (sess, control) = session::Session::new(
        serial,
        Arc::new(Feed { hub: hub.clone() }),
        HOST_DISPLAY,
        false,
    );

    // Commands on stdin, one per line: "wda http://127.0.0.1:<port>" turns touch on (the engine
    // started WebDriverAgent on the phone), "stop" stops. Stdin closing also stops.
    {
        let stop = control.stop.clone();
        let hub = hub.clone();
        std::thread::spawn(move || {
            for line in std::io::stdin().lines() {
                let Ok(line) = line else { break };
                let line = line.trim();
                if line == "stop" {
                    break;
                }
                if let Some(url) = line.strip_prefix("wda ") {
                    let Some(w) = wda::Wda::new(url) else {
                        log::warn!("touch: refused address {url}");
                        continue;
                    };
                    // The engine has just started WebDriverAgent; it takes a few seconds to answer.
                    let hub = hub.clone();
                    std::thread::spawn(move || {
                        let deadline = Instant::now() + Duration::from_secs(90);
                        while !w.ready() {
                            if Instant::now() > deadline {
                                emit(json!({ "type": "screen_touch", "available": false, "reason": "error", "message": "The touch helper on the iPhone did not answer." }));
                                return;
                            }
                            std::thread::sleep(Duration::from_millis(500));
                        }
                        // Straight to the phone over Wi-Fi when it answers there (faster than the
                        // forward); the forward stays the way otherwise.
                        if w.prefer_direct().is_none() {
                            log::info!("touch: through the port forward");
                        }
                        // Open the touch session now, so the first tap is not the slow one.
                        if let Err(e) = w.prepare() {
                            log::info!("touch: session not ready yet ({e})");
                        }
                        hub.set_wda(w);
                        emit(json!({ "type": "screen_touch", "available": true }));
                    });
                }
            }
            stop.store(true, Ordering::Relaxed);
        });
    }
    if let Some(s) = seconds {
        let stop = control.stop.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_secs(s));
            stop.store(true, Ordering::Relaxed);
        });
    }

    // Announce the URL once the first picture arrives; then stats every 2 s.
    {
        let hub = hub.clone();
        let stop = control.stop.clone();
        std::thread::spawn(move || {
            let url = format!("http://127.0.0.1:{port}/{}/stream.h264", hub.token());
            let viewer = format!("http://127.0.0.1:{port}/{}/viewer", hub.token());
            let mut announced = false;
            let (mut last_frames, mut last_bytes, mut last_t) = (0u64, 0u64, Instant::now());
            while !stop.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(250));
                let (frames, bytes) = hub.counters();
                if !announced && frames > 0 {
                    let (w, h) = hub.size();
                    emit(json!({ "type": "screen_ready", "url": url, "viewer": viewer, "codec": "h264", "width": w, "height": h, "method": "quicktime", "touch": false }));
                    announced = true;
                    last_frames = frames;
                    last_bytes = bytes;
                    last_t = Instant::now();
                }
                if announced && last_t.elapsed() >= Duration::from_secs(2) {
                    let dt = last_t.elapsed().as_secs_f64();
                    let fps = (frames - last_frames) as f64 / dt;
                    let mbps = (bytes - last_bytes) as f64 * 8.0 / dt / 1e6;
                    emit(json!({ "type": "screen_stats", "fps": (fps * 10.0).round() / 10.0, "mbps": (mbps * 10.0).round() / 10.0 }));
                    last_frames = frames;
                    last_bytes = bytes;
                    last_t = Instant::now();
                }
            }
        });
    }

    let result = sess.run();
    let (reason, message) = match &result {
        Ok(()) => ("stopped", String::new()),
        Err(e) => (classify(e), e.clone()),
    };
    emit(json!({ "type": "screen_end", "reason": reason, "message": message }));
    if result.is_ok() { 0 } else { 1 }
}

/// Map the session's error text to a stable reason for the engine and Studio.
fn classify(e: &str) -> &'static str {
    let l = e.to_lowercase();
    if l.contains("libusb0.dll") || l.contains("driver") {
        "driver_needed"
    } else if l.contains("not found") || l.contains("disconnected") || l.contains("no device") {
        "unplugged"
    } else if l.contains("trust") || l.contains("pair") {
        "not_trusted"
    } else if l.contains("lock") {
        "locked"
    } else {
        "error"
    }
}

#[cfg(test)]
mod tests {
    use super::classify;

    #[test]
    fn errors_map_to_stable_reasons() {
        assert_eq!(classify("libusb0.dll is not installed. Open Settings"), "driver_needed");
        assert_eq!(classify("The ZenLink Studio driver is installed, but Windows hasn't attached it"), "driver_needed");
        assert_eq!(classify("device not found"), "unplugged");
        assert_eq!(classify("Unlock the device and tap Trust"), "not_trusted");
        assert_eq!(classify("boom"), "error");
    }
}
