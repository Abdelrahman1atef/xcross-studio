//! Fan-out of the live H.264 stream to local viewers over HTTP on 127.0.0.1.
//!
//! Endpoints (all behind `/<token>/`; anything else, or a wrong token, gets 404):
//! - `stream.h264`: Annex-B bytes: SPS/PPS, the last IDR access unit, then every new one.
//! - `stream.frames`: the same, framed for the viewer: `[u32 BE length][u8 kind][payload]`,
//!   kind 1 = decoder config (SPS/PPS), 2 = key access unit, 3 = delta access unit.
//! - `viewer`: a page that decodes `stream.frames` with the system's hardware decoder (WebCodecs).
//! - `info`: picture size and counters (JSON).
//!
//! A viewer that falls behind is dropped (it reconnects and restarts at a key frame). No frame
//! is ever logged.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, RwLock};
use std::time::Instant;

const VIEWER_QUEUE: usize = 240;
const VIEWER_PAGE: &str = include_str!("viewer.html");

use crate::wda::{Gesture, Wda};

pub const KIND_CONFIG: u8 = 1;
pub const KIND_KEY: u8 = 2;
pub const KIND_DELTA: u8 = 3;

#[derive(Clone)]
struct Frame {
    data: Arc<Vec<u8>>,
    kind: u8,
}

#[derive(Default)]
struct State {
    config: Vec<u8>,
    last_idr: Option<Arc<Vec<u8>>>,
    viewers: Vec<SyncSender<Frame>>,
    width: u32,
    height: u32,
    frames: u64,
    bytes: u64,
}

pub struct Hub {
    state: Mutex<State>,
    token: String,
    started: Instant,
    /// Touch through WebDriverAgent, once the engine has started it (iOS 16 and older).
    wda: RwLock<Option<Arc<Wda>>>,
}

/// `[u32 BE length][u8 kind][payload]`, the length counting the kind byte.
pub fn frame_header(kind: u8, payload_len: usize) -> [u8; 5] {
    let n = (payload_len as u32 + 1).to_be_bytes();
    [n[0], n[1], n[2], n[3], kind]
}

impl Hub {
    pub fn new(token: String) -> Arc<Self> {
        Arc::new(Self { state: Mutex::default(), token, started: Instant::now(), wda: RwLock::new(None) })
    }

    /// Turns touch on: gestures from the viewer go to [wda].
    pub fn set_wda(&self, wda: Wda) {
        *self.wda.write().unwrap() = Some(Arc::new(wda));
    }

    pub fn touch(&self) -> bool {
        self.wda.read().unwrap().is_some()
    }

    pub fn token(&self) -> &str {
        &self.token
    }

    /// A new decoder configuration (Annex-B SPS/PPS) and picture size.
    pub fn set_config(&self, annexb: Vec<u8>, width: u32, height: u32) {
        let mut s = self.state.lock().unwrap();
        s.config = annexb.clone();
        s.width = width;
        s.height = height;
        s.last_idr = None;
        let f = Frame { data: Arc::new(annexb), kind: KIND_CONFIG };
        s.viewers.retain(|v| v.try_send(f.clone()).is_ok());
    }

    /// One Annex-B access unit.
    pub fn push(&self, au: Vec<u8>, idr: bool) {
        let data = Arc::new(au);
        let mut s = self.state.lock().unwrap();
        s.frames += 1;
        s.bytes += data.len() as u64;
        if idr {
            s.last_idr = Some(data.clone());
        }
        let f = Frame { data, kind: if idr { KIND_KEY } else { KIND_DELTA } };
        s.viewers.retain(|v| match v.try_send(f.clone()) {
            Ok(()) => true,
            Err(TrySendError::Full(_)) | Err(TrySendError::Disconnected(_)) => false,
        });
    }

    /// (frames, bytes) since start, for the stats line.
    pub fn counters(&self) -> (u64, u64) {
        let s = self.state.lock().unwrap();
        (s.frames, s.bytes)
    }

    pub fn size(&self) -> (u32, u32) {
        let s = self.state.lock().unwrap();
        (s.width, s.height)
    }

    /// The frames a new viewer starts with, and its live queue.
    fn subscribe(&self) -> (Vec<Frame>, Receiver<Frame>) {
        let (tx, rx) = sync_channel(VIEWER_QUEUE);
        let mut s = self.state.lock().unwrap();
        let mut head = Vec::new();
        if !s.config.is_empty() {
            head.push(Frame { data: Arc::new(s.config.clone()), kind: KIND_CONFIG });
        }
        if let Some(idr) = &s.last_idr {
            head.push(Frame { data: idr.clone(), kind: KIND_KEY });
        }
        s.viewers.push(tx);
        (head, rx)
    }

    /// Serve viewers on [listener] until the process ends.
    pub fn serve(self: &Arc<Self>, listener: TcpListener) {
        let hub = self.clone();
        std::thread::Builder::new()
            .name("viewers".into())
            .spawn(move || {
                for conn in listener.incoming().flatten() {
                    let hub = hub.clone();
                    let _ = std::thread::Builder::new()
                        .name("viewer".into())
                        .spawn(move || hub.handle(conn));
                }
            })
            .expect("viewer thread");
    }

    fn handle(&self, mut conn: TcpStream) {
        let _ = conn.set_nodelay(true);
        let Some((method, path, body)) = read_request(&conn) else { return };
        let base = format!("/{}/", self.token);
        let route = path.split('?').next().unwrap_or("");
        let Some(name) = route.strip_prefix(&base) else {
            return not_found(&mut conn);
        };
        match name {
            "stream.h264" => self.stream(&mut conn, "video/h264", false),
            "stream.frames" => self.stream(&mut conn, "application/octet-stream", true),
            "viewer" => respond(&mut conn, "text/html; charset=utf-8", VIEWER_PAGE.as_bytes()),
            "tap" | "swipe" | "button" if method == "POST" => self.touch_request(&mut conn, name, &path, &body),
            "info" => {
                let (w, h) = self.size();
                let (frames, bytes) = self.counters();
                let body = serde_json::json!({
                    "codec": "h264", "width": w, "height": h, "frames": frames, "bytes": bytes,
                    "uptimeMs": self.started.elapsed().as_millis() as u64, "touch": self.touch(),
                })
                .to_string();
                respond(&mut conn, "application/json", body.as_bytes());
            }
            _ => not_found(&mut conn),
        }
    }

    fn touch_request(&self, conn: &mut TcpStream, name: &str, path: &str, body: &str) {
        let Some(wda) = self.wda.read().unwrap().clone() else {
            return status(conn, "409 Conflict", "touch is not available for this iPhone");
        };
        let result = if name == "button" {
            let button = path.split("name=").nth(1).unwrap_or("").split('&').next().unwrap_or("");
            wda.button(button)
        } else {
            match Gesture::parse(name, body) {
                Some(g) => wda.gesture(g),
                None => return status(conn, "400 Bad Request", "bad gesture"),
            }
        };
        match result {
            Ok(()) => status(conn, "204 No Content", ""),
            Err(e) => {
                log::warn!("touch failed: {e}");
                status(conn, "502 Bad Gateway", "the iPhone did not take the touch")
            }
        }
    }

    fn stream(&self, conn: &mut TcpStream, content_type: &str, framed: bool) {
        let (head, rx) = self.subscribe();
        let header = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        );
        if conn.write_all(header.as_bytes()).is_err() {
            return;
        }
        let send = |conn: &mut TcpStream, f: &Frame| -> bool {
            if framed && conn.write_all(&frame_header(f.kind, f.data.len())).is_err() {
                return false;
            }
            conn.write_all(&f.data).is_ok()
        };
        for f in &head {
            if !send(conn, f) {
                return;
            }
        }
        while let Ok(f) = rx.recv() {
            if !send(conn, &f) {
                return;
            }
        }
    }
}

fn respond(conn: &mut TcpStream, content_type: &str, body: &[u8]) {
    let head = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: {content_type}\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = conn.write_all(head.as_bytes()).and_then(|_| conn.write_all(body));
}

fn status(conn: &mut TcpStream, code: &str, text: &str) {
    let head = format!(
        "HTTP/1.1 {code}\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}",
        text.len()
    );
    let _ = conn.write_all(head.as_bytes());
}

fn not_found(conn: &mut TcpStream) {
    let _ = conn.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
}

/// Method, path and body (bodies over 64 KiB are refused).
fn read_request(conn: &TcpStream) -> Option<(String, String, String)> {
    let mut reader = BufReader::new(conn.try_clone().ok()?);
    let mut line = String::new();
    reader.read_line(&mut line).ok()?;
    let mut parts = line.split_whitespace();
    let method = parts.next()?.to_string();
    let path = parts.next()?.to_string();
    let mut length = 0usize;
    loop {
        let mut h = String::new();
        if reader.read_line(&mut h).ok()? == 0 || h == "\r\n" || h == "\n" {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            if k.trim().eq_ignore_ascii_case("content-length") {
                length = v.trim().parse().unwrap_or(0);
            }
        }
    }
    if length > 65536 {
        return None;
    }
    let mut body = vec![0u8; length];
    reader.read_exact(&mut body).ok()?;
    Some((method, path, String::from_utf8_lossy(&body).into_owned()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::time::Duration;

    fn start(hub: &Arc<Hub>) -> u16 {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        hub.serve(l);
        port
    }

    fn get(port: u16, path: &str) -> TcpStream {
        let mut c = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(c, "GET {path} HTTP/1.1\r\nHost: x\r\n\r\n").unwrap();
        c
    }

    fn read_until(c: &mut TcpStream, done: impl Fn(&[u8]) -> bool) -> Vec<u8> {
        let mut buf = vec![0u8; 512];
        let mut got = Vec::new();
        c.set_read_timeout(Some(Duration::from_millis(800))).unwrap();
        while let Ok(n) = c.read(&mut buf) {
            if n == 0 {
                break;
            }
            got.extend_from_slice(&buf[..n]);
            if done(&got) {
                break;
            }
        }
        got
    }

    fn body(got: &[u8]) -> &[u8] {
        &got[got.windows(4).position(|w| w == b"\r\n\r\n").unwrap() + 4..]
    }

    #[test]
    fn wrong_token_gets_404() {
        let hub = Hub::new("secret".into());
        let port = start(&hub);
        for path in ["/other/stream.h264", "/secret/nothing", "/secretx/viewer", "/"] {
            let mut c = get(port, path);
            let mut s = String::new();
            c.read_to_string(&mut s).unwrap();
            assert!(s.starts_with("HTTP/1.1 404"), "{path}");
        }
    }

    #[test]
    fn new_viewer_starts_with_config_and_last_key_frame() {
        let hub = Hub::new("t".into());
        hub.set_config(vec![0, 0, 0, 1, 0x67], 10, 20);
        hub.push(vec![0, 0, 0, 1, 0x41], false); // before any key frame: not replayed
        hub.push(vec![0, 0, 0, 1, 0x65], true);
        let port = start(&hub);
        let mut c = get(port, "/t/stream.h264");
        std::thread::sleep(Duration::from_millis(100));
        hub.push(vec![0, 0, 0, 1, 0x41, 0x99], false);
        let got = read_until(&mut c, |g| g.ends_with(&[0x41, 0x99]));
        assert_eq!(body(&got), &[0, 0, 0, 1, 0x67, 0, 0, 0, 1, 0x65, 0, 0, 0, 1, 0x41, 0x99]);
    }

    #[test]
    fn framed_stream_marks_config_key_and_delta() {
        let hub = Hub::new("t".into());
        hub.set_config(vec![0xAA], 1, 1);
        hub.push(vec![0xBB], true);
        let port = start(&hub);
        let mut c = get(port, "/t/stream.frames");
        std::thread::sleep(Duration::from_millis(100));
        hub.push(vec![0xCC, 0xDD], false);
        let got = read_until(&mut c, |g| g.ends_with(&[0xCC, 0xDD]));
        assert_eq!(
            body(&got),
            &[0, 0, 0, 2, KIND_CONFIG, 0xAA, 0, 0, 0, 2, KIND_KEY, 0xBB, 0, 0, 0, 3, KIND_DELTA, 0xCC, 0xDD]
        );
    }

    #[test]
    fn viewer_page_is_served_with_a_strict_policy() {
        let hub = Hub::new("t".into());
        let port = start(&hub);
        let mut c = get(port, "/t/viewer");
        let mut s = String::new();
        c.read_to_string(&mut s).unwrap();
        assert!(s.starts_with("HTTP/1.1 200"));
        assert!(s.contains("Content-Security-Policy: default-src 'self'"));
        assert!(s.contains("VideoDecoder"));
    }

    fn post(port: u16, path: &str, body: &str) -> String {
        let mut c = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(c, "POST {path} HTTP/1.1\r\nHost: x\r\nContent-Length: {}\r\n\r\n{body}", body.len()).unwrap();
        let mut s = String::new();
        c.read_to_string(&mut s).unwrap();
        s
    }

    /// A fake WebDriverAgent: answers session, window size and tap; records the tap body.
    fn fake_wda() -> (u16, std::sync::mpsc::Receiver<String>) {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            for conn in l.incoming().flatten() {
                let Some((method, path, body)) = read_request(&conn) else { continue };
                let reply = match (method.as_str(), path.as_str()) {
                    ("POST", "/session") => r#"{"sessionId":"S1","value":{"sessionId":"S1"}}"#.to_string(),
                    ("GET", "/session/S1/window/size") => r#"{"value":{"width":375,"height":812}}"#.to_string(),
                    ("POST", "/session/S1/actions") => {
                        tx.send(body).unwrap();
                        r#"{"value":null}"#.to_string()
                    }
                    _ => r#"{"value":null}"#.to_string(),
                };
                let mut conn = conn;
                let _ = write!(conn, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{reply}", reply.len());
            }
        });
        (port, rx)
    }

    #[test]
    fn touch_is_refused_until_the_engine_turns_it_on() {
        let hub = Hub::new("t".into());
        let port = start(&hub);
        assert!(post(port, "/t/tap", r#"{"x":0.5,"y":0.5}"#).starts_with("HTTP/1.1 409"));
        assert!(post(port, "/other/tap", r#"{"x":0.5,"y":0.5}"#).starts_with("HTTP/1.1 404"));
    }

    #[test]
    fn a_tap_reaches_webdriveragent_in_points() {
        let (wda_port, taps) = fake_wda();
        let hub = Hub::new("t".into());
        hub.set_wda(Wda::new(&format!("http://127.0.0.1:{wda_port}")).unwrap());
        let port = start(&hub);
        assert!(post(port, "/t/tap", r#"{"x":0.5,"y":0.5}"#).starts_with("HTTP/1.1 204"));
        let body: serde_json::Value = serde_json::from_str(&taps.recv_timeout(Duration::from_secs(2)).unwrap()).unwrap();
        let first = &body["actions"][0]["actions"][0];
        assert_eq!(first["x"], 188.0);
        assert_eq!(first["y"], 406.0);
        assert!(post(port, "/t/tap", r#"{"nope":1}"#).starts_with("HTTP/1.1 400"));
    }

    #[test]
    fn info_reports_size_and_counters() {
        let hub = Hub::new("t".into());
        hub.set_config(vec![], 1126, 2436);
        hub.push(vec![1, 2, 3], false);
        let port = start(&hub);
        let mut c = get(port, "/t/info");
        let mut s = String::new();
        c.read_to_string(&mut s).unwrap();
        let v: serde_json::Value = serde_json::from_str(s.split("\r\n\r\n").nth(1).unwrap()).unwrap();
        assert_eq!(v["width"], 1126);
        assert_eq!(v["frames"], 1);
    }
}
