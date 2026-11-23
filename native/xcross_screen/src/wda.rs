//! Touch on iPhones without Apple's touch service (iOS 16 and older, spec 048): WebDriverAgent
//! runs on the phone (started by the engine) and this sends it taps, swipes and buttons.
//!
//! Coordinates arrive normalized (0..1 of the picture) and are turned into WDA points with the
//! session's window size. Plain HTTP/1.1 on one kept-open connection: first through the engine's
//! port forward on 127.0.0.1, then straight to the phone over Wi-Fi when it answers there (the
//! address comes from WDA itself), which saves about 50 ms per touch.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::Mutex;
use std::time::Duration;

use serde_json::{json, Value};

pub struct Wda {
    /// Where requests go: the engine's forward, or the phone's own address.
    target: Mutex<SocketAddr>,
    /// WDA's port on the phone (8100), for the direct route.
    device_port: u16,
    /// The kept-open connection; one request at a time, so touches stay in order.
    conn: Mutex<Option<TcpStream>>,
    session: Mutex<Option<(String, f64, f64)>>,
}

/// A tap or a drag from the viewer, in 0..1 of the picture.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Gesture {
    /// `hold` seconds: a long press when the mouse was held.
    Tap { x: f64, y: f64, hold: f64 },
    Swipe { x1: f64, y1: f64, x2: f64, y2: f64, seconds: f64 },
}

impl Gesture {
    /// Parses the viewer's JSON body for `tap` or `swipe`; values are clamped to the picture.
    pub fn parse(kind: &str, body: &str) -> Option<Self> {
        let v: Value = serde_json::from_str(body).ok()?;
        let n = |k: &str| v.get(k).and_then(Value::as_f64).map(|f| f.clamp(0.0, 1.0));
        match kind {
            "tap" => Some(Gesture::Tap {
                x: n("x")?,
                y: n("y")?,
                hold: v.get("hold").and_then(Value::as_f64).unwrap_or(0.03).clamp(0.03, 3.0),
            }),
            "swipe" => Some(Gesture::Swipe {
                x1: n("x1")?,
                y1: n("y1")?,
                x2: n("x2")?,
                y2: n("y2")?,
                seconds: v.get("seconds").and_then(Value::as_f64).unwrap_or(0.2).clamp(0.05, 1.5),
            }),
            _ => None,
        }
    }

    /// The WDA request (path after the session, body) for a window of `w` x `h` points: W3C
    /// pointer actions, the quickest way through XCTest.
    pub fn request(&self, w: f64, h: f64) -> (&'static str, Value) {
        let pt = |x: f64, y: f64| ((x * w).round(), (y * h).round());
        let steps = match *self {
            Gesture::Tap { x, y, hold } => {
                let (px, py) = pt(x, y);
                json!([
                    { "type": "pointerMove", "duration": 0, "x": px, "y": py },
                    { "type": "pointerDown" },
                    { "type": "pause", "duration": (hold * 1000.0).round() },
                    { "type": "pointerUp" },
                ])
            }
            Gesture::Swipe { x1, y1, x2, y2, seconds } => {
                let ((ax, ay), (bx, by)) = (pt(x1, y1), pt(x2, y2));
                json!([
                    { "type": "pointerMove", "duration": 0, "x": ax, "y": ay },
                    { "type": "pointerDown" },
                    { "type": "pointerMove", "duration": (seconds * 1000.0).round(), "x": bx, "y": by },
                    { "type": "pointerUp" },
                ])
            }
        };
        (
            "/actions",
            json!({ "actions": [{
                "type": "pointer", "id": "finger1", "parameters": { "pointerType": "touch" }, "actions": steps,
            }] }),
        )
    }
}

impl Wda {
    /// `base` is `http://127.0.0.1:<port>` (anything else is refused: the phone is reached only
    /// through the engine's local forward).
    pub fn new(base: &str) -> Option<Self> {
        let rest = base.trim().trim_end_matches('/').strip_prefix("http://127.0.0.1:")?;
        let port: u16 = rest.parse().ok()?;
        Some(Self {
            target: Mutex::new(SocketAddr::from(([127, 0, 0, 1], port))),
            device_port: 8100,
            conn: Mutex::new(None),
            session: Mutex::new(None),
        })
    }

    #[cfg(test)]
    fn with_device_port(mut self, port: u16) -> Self {
        self.device_port = port;
        self
    }

    /// Switches to the phone's own address when WDA answers there (same Wi-Fi); keeps the
    /// forward otherwise. Returns the address used.
    pub fn prefer_direct(&self) -> Option<SocketAddr> {
        let status = self.call("GET", "/status", None).ok()?;
        let ip: std::net::IpAddr = status.pointer("/value/ios/ip")?.as_str()?.parse().ok()?;
        let addr = SocketAddr::new(ip, self.device_port);
        let mut probe = TcpStream::connect_timeout(&addr, Duration::from_millis(800)).ok()?;
        let _ = probe.set_nodelay(true);
        let _ = probe.set_read_timeout(Some(Duration::from_secs(2)));
        let head = "GET /status HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n";
        probe.write_all(head.as_bytes()).ok()?;
        let answer = parse_response(&read_response(&mut probe).ok()?).ok()?;
        // The same phone answers there (it reports the same address).
        if answer.pointer("/value/ios/ip") != status.pointer("/value/ios/ip") {
            return None;
        }
        *self.target.lock().unwrap() = addr;
        *self.conn.lock().unwrap() = Some(probe);
        log::info!("touch: straight to the iPhone over Wi-Fi ({addr})");
        Some(addr)
    }

    fn call(&self, method: &str, path: &str, body: Option<&Value>) -> Result<Value, String> {
        self.call_within(method, path, body, Duration::from_secs(20))
    }

    fn call_within(&self, method: &str, path: &str, body: Option<&Value>, wait: Duration) -> Result<Value, String> {
        let payload = body.map(|b| b.to_string()).unwrap_or_default();
        let request = format!(
            "{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{payload}",
            payload.len()
        );
        let mut conn = self.conn.lock().unwrap();
        for attempt in 0..2 {
            if conn.is_none() {
                let target = *self.target.lock().unwrap();
                let stream = TcpStream::connect_timeout(&target, Duration::from_secs(3))
                    .map_err(|e| format!("touch helper: {e}"))?;
                let _ = stream.set_nodelay(true);
                *conn = Some(stream);
            }
            let stream = conn.as_mut().expect("connected above");
            let _ = stream.set_read_timeout(Some(wait));
            // A kept-open connection the other side has dropped fails here or answers nothing:
            // the request was not taken, so sending it again on a new connection is safe.
            if stream.write_all(request.as_bytes()).is_err() {
                *conn = None;
                continue;
            }
            match read_response(stream) {
                Ok(raw) if raw.is_empty() && attempt == 0 => {
                    *conn = None;
                }
                Ok(raw) => {
                    if keeps_open(&raw) == Some(false) {
                        *conn = None;
                    }
                    return parse_response(&raw);
                }
                Err(e) => {
                    // Sent but no answer: never send a touch twice.
                    *conn = None;
                    return Err(format!("touch helper: {e}"));
                }
            }
        }
        Err("touch helper: the connection keeps closing".into())
    }

    /// The session id and window size, creating the session on first use.
    fn session(&self) -> Result<(String, f64, f64), String> {
        if let Some(s) = self.session.lock().unwrap().clone() {
            return Ok(s);
        }
        // No waiting for the app to be idle before each touch (1.4 s -> 0.5 s per tap on an iPhone X).
        let caps = json!({ "capabilities": { "alwaysMatch": {
            "shouldWaitForQuiescence": false, "waitForIdleTimeout": 0,
            "shouldUseTestManagerForVisibilityDetection": false,
        } } });
        let created = self.call("POST", "/session", Some(&caps))?;
        let sid = created
            .get("sessionId")
            .or_else(|| created.pointer("/value/sessionId"))
            .and_then(Value::as_str)
            .ok_or("touch helper: no session")?
            .to_string();
        // snapshotMaxDepth 1: WDA looks at the app in front before each touch; a shallow look
        // cuts a tap from ~660 to ~430 ms on an iPhone X while it streams (Studio never asks
        // for elements).
        let settings = json!({ "settings": {
            "waitForIdleTimeout": 0, "animationCoolOffTimeout": 0, "snapshotMaxDepth": 1,
        } });
        if let Err(e) = self.call("POST", &format!("/session/{sid}/appium/settings"), Some(&settings)) {
            log::info!("touch: settings not taken ({e})");
        }
        let size = self.call("GET", &format!("/session/{sid}/window/size"), None)?;
        let w = size.pointer("/value/width").and_then(Value::as_f64).unwrap_or(375.0);
        let h = size.pointer("/value/height").and_then(Value::as_f64).unwrap_or(812.0);
        let s = (sid, w, h);
        *self.session.lock().unwrap() = Some(s.clone());
        Ok(s)
    }

    /// Sends a gesture; retries once with a new session (WDA drops idle sessions).
    pub fn gesture(&self, g: Gesture) -> Result<(), String> {
        for attempt in 0..2 {
            let (sid, w, h) = self.session()?;
            let (path, body) = g.request(w, h);
            match self.call("POST", &format!("/session/{sid}{path}"), Some(&body)) {
                Ok(_) => return Ok(()),
                Err(e) if attempt == 0 => {
                    log::info!("touch: retrying with a new session ({e})");
                    *self.session.lock().unwrap() = None;
                }
                Err(e) => return Err(e),
            }
        }
        Ok(())
    }

    /// `home` (Home button); other names are refused.
    pub fn button(&self, name: &str) -> Result<(), String> {
        match name {
            "home" => self.call("POST", "/wda/homescreen", None).map(|_| ()),
            _ => Err(format!("unknown button {name}")),
        }
    }

    /// Opens the session ahead of the first touch.
    pub fn prepare(&self) -> Result<(), String> {
        self.session().map(|_| ())
    }

    /// Whether WDA answers.
    pub fn ready(&self) -> bool {
        // Short: before WDA is up, the port forward keeps the connection open without answering.
        let ok = self.call_within("GET", "/status", None, Duration::from_secs(2)).is_ok();
        if !ok {
            *self.conn.lock().unwrap() = None;
        }
        ok
    }
}

/// Reads one HTTP response: up to Content-Length, to the last chunk, or to the end. WDA (behind a
/// port forward) keeps the connection open after answering, so "read to the end" alone hangs.
pub fn read_response(conn: &mut impl Read) -> std::io::Result<Vec<u8>> {
    let mut raw = Vec::new();
    let mut buf = [0u8; 8192];
    loop {
        if let Some(split) = raw.windows(4).position(|w| w == b"\r\n\r\n") {
            let head = String::from_utf8_lossy(&raw[..split]).to_ascii_lowercase();
            let length = head
                .lines()
                .find_map(|l| l.strip_prefix("content-length:"))
                .and_then(|v| v.trim().parse::<usize>().ok());
            let chunked = head.contains("transfer-encoding: chunked");
            let body = raw.len() - split - 4;
            match length {
                Some(n) if body >= n => return Ok(raw),
                None if chunked && raw.ends_with(b"0\r\n\r\n") => return Ok(raw),
                _ => {}
            }
        }
        let n = conn.read(&mut buf)?;
        if n == 0 {
            return Ok(raw);
        }
        raw.extend_from_slice(&buf[..n]);
    }
}

/// Whether the response lets the connection stay open (`Connection: close` says no).
fn keeps_open(raw: &[u8]) -> Option<bool> {
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n")?;
    let head = String::from_utf8_lossy(&raw[..split]).to_ascii_lowercase();
    Some(!head.lines().any(|l| l.starts_with("connection:") && l.contains("close")))
}

/// The JSON body of an HTTP response; an HTTP error or a WDA error status is an Err.
pub fn parse_response(raw: &[u8]) -> Result<Value, String> {
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n").ok_or("touch helper: bad reply")?;
    let head = String::from_utf8_lossy(&raw[..split]);
    let status: u16 = head.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let mut body = raw[split + 4..].to_vec();
    if head.to_ascii_lowercase().contains("transfer-encoding: chunked") {
        body = dechunk(&body);
    }
    let v: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
    if !(200..300).contains(&status) {
        let msg = v.pointer("/value/message").and_then(Value::as_str).unwrap_or("error");
        return Err(format!("touch helper HTTP {status}: {msg}"));
    }
    Ok(v)
}

fn dechunk(mut data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    while let Some(nl) = data.windows(2).position(|w| w == b"\r\n") {
        let size = usize::from_str_radix(String::from_utf8_lossy(&data[..nl]).trim(), 16).unwrap_or(0);
        if size == 0 || data.len() < nl + 2 + size {
            break;
        }
        out.extend_from_slice(&data[nl + 2..nl + 2 + size]);
        data = &data[(nl + 4 + size).min(data.len())..];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_local_forward_is_accepted() {
        assert!(Wda::new("http://127.0.0.1:18100").is_some());
        assert!(Wda::new("http://127.0.0.1:18100/").is_some());
        assert!(Wda::new("http://192.168.1.5:8100").is_none());
        assert!(Wda::new("https://127.0.0.1:1").is_none());
        assert!(Wda::new("http://127.0.0.1:notaport").is_none());
    }

    #[test]
    fn gestures_parse_clamp_and_scale_to_points() {
        let t = Gesture::parse("tap", r#"{"x":0.5,"y":1.4}"#).unwrap();
        assert_eq!(t, Gesture::Tap { x: 0.5, y: 1.0, hold: 0.03 });
        let (path, body) = t.request(375.0, 812.0);
        assert_eq!(path, "/actions");
        let steps = &body["actions"][0]["actions"];
        assert_eq!((steps[0]["x"].clone(), steps[0]["y"].clone()), (json!(188.0), json!(812.0)));
        assert_eq!(steps[2]["duration"], 30.0);
        let long = Gesture::parse("tap", r#"{"x":0.1,"y":0.1,"hold":0.8}"#).unwrap();
        assert_eq!(long.request(375.0, 812.0).1["actions"][0]["actions"][2]["duration"], 800.0);

        let s = Gesture::parse("swipe", r#"{"x1":0.5,"y1":0.9,"x2":0.5,"y2":0.2,"seconds":9}"#).unwrap();
        let (path, body) = s.request(375.0, 812.0);
        assert_eq!(path, "/actions");
        let steps = &body["actions"][0]["actions"];
        assert_eq!(steps[0]["y"], 731.0);
        assert_eq!(steps[2]["y"], 162.0);
        assert_eq!(steps[2]["duration"], 1500.0, "duration clamped");

        assert!(Gesture::parse("tap", r#"{"x":0.5}"#).is_none());
        assert!(Gesture::parse("pinch", r#"{}"#).is_none());
    }

    /// A reader that never ends: like WDA behind a forward that keeps the connection open.
    struct Open(std::io::Cursor<Vec<u8>>);
    impl Read for Open {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            match self.0.read(buf)? {
                0 => Err(std::io::Error::new(std::io::ErrorKind::TimedOut, "would hang")),
                n => Ok(n),
            }
        }
    }

    #[test]
    fn a_response_is_complete_without_the_connection_closing() {
        let sized = b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"value\":1}".to_vec();
        assert_eq!(read_response(&mut Open(std::io::Cursor::new(sized.clone()))).unwrap(), sized);
        let chunked = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n".to_vec();
        assert_eq!(read_response(&mut Open(std::io::Cursor::new(chunked.clone()))).unwrap(), chunked);
    }

    /// A WDA stand-in that keeps connections open: counts connections and requests.
    fn keep_alive_server(ip: &str) -> (u16, std::sync::Arc<std::sync::atomic::AtomicUsize>) {
        use std::sync::atomic::{AtomicUsize, Ordering};
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let conns = std::sync::Arc::new(AtomicUsize::new(0));
        let counter = conns.clone();
        let status = format!(r#"{{"value":{{"ios":{{"ip":"{ip}"}}}}}}"#);
        std::thread::spawn(move || {
            for conn in l.incoming().flatten() {
                counter.fetch_add(1, Ordering::SeqCst);
                let status = status.clone();
                std::thread::spawn(move || {
                    let mut reader = std::io::BufReader::new(conn.try_clone().unwrap());
                    let mut conn = conn;
                    loop {
                        use std::io::BufRead;
                        let mut line = String::new();
                        if reader.read_line(&mut line).unwrap_or(0) == 0 {
                            return;
                        }
                        let mut length = 0;
                        loop {
                            let mut h = String::new();
                            reader.read_line(&mut h).unwrap();
                            if h == "\r\n" {
                                break;
                            }
                            if let Some(v) = h.to_ascii_lowercase().strip_prefix("content-length:") {
                                length = v.trim().parse().unwrap();
                            }
                        }
                        let mut body = vec![0; length];
                        reader.read_exact(&mut body).unwrap();
                        let reply = if line.starts_with("GET /status") { status.clone() } else { r#"{"value":null}"#.to_string() };
                        write!(conn, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{reply}", reply.len()).unwrap();
                    }
                });
            }
        });
        (port, conns)
    }

    #[test]
    fn requests_share_one_kept_open_connection() {
        use std::sync::atomic::Ordering;
        let (port, conns) = keep_alive_server("10.0.0.9");
        let wda = Wda::new(&format!("http://127.0.0.1:{port}")).unwrap();
        for _ in 0..3 {
            assert!(wda.ready());
        }
        assert!(wda.button("home").is_ok());
        assert_eq!(conns.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn the_direct_route_is_used_only_when_the_phone_answers_there() {
        // The "phone" reports 127.0.0.1, where a second WDA stand-in listens.
        let (direct_port, direct_conns) = keep_alive_server("127.0.0.1");
        let (fwd_port, _) = keep_alive_server("127.0.0.1");
        let wda = Wda::new(&format!("http://127.0.0.1:{fwd_port}")).unwrap().with_device_port(direct_port);
        let addr = wda.prefer_direct().expect("direct route");
        assert_eq!(addr.port(), direct_port);
        assert!(wda.button("home").is_ok());
        assert_eq!(direct_conns.load(std::sync::atomic::Ordering::SeqCst), 1, "the probe connection is kept");

        // Nothing listens at the reported address: stay on the forward.
        let (fwd2, _) = keep_alive_server("127.0.0.1");
        let free = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let stay = Wda::new(&format!("http://127.0.0.1:{fwd2}")).unwrap().with_device_port(free);
        assert!(stay.prefer_direct().is_none());
        assert!(stay.ready());
    }

    #[test]
    fn responses_parse_plain_and_chunked_and_report_errors() {
        let ok = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"value\":{\"width\":375}}";
        assert_eq!(parse_response(ok).unwrap()["value"]["width"], 375);
        let chunked = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n6\r\n{\"a\":1\r\n1\r\n}\r\n0\r\n\r\n";
        assert_eq!(parse_response(chunked).unwrap()["a"], 1);
        let err = b"HTTP/1.1 404 Not Found\r\n\r\n{\"value\":{\"message\":\"invalid session id\"}}";
        assert!(parse_response(err).unwrap_err().contains("invalid session id"));
    }
}
