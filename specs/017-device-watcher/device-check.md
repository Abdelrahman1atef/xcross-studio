# Device check: 017 device watcher (Windows host, iPhone X iOS 16.7.16)

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-017-1, 2 | `xcross devices --watch --json` with the iPhone connected | one `devices` snapshot with it; keeps running | ✅ 2026-11-03 (Apple Mobile Device Service, 127.0.0.1:27015) |
| 2 | AC-017-2 | unplug the cable | snapshot without it within ~1 s | ⏳ needs a hand on the cable |
| 3 | AC-017-2 | plug it back | snapshot with it within ~2 s | ⏳ |
| 4 | AC-017-3 | restart "Apple Mobile Device Service" | notice + empty snapshot, then a snapshot again | ⏳ (needs an elevated services.msc) |
| 5 | AC-017-6, 7 | XCross Studio top bar during 2–4 | badge: name ↔ "Plug in an iPhone" ↔ "Device service not reachable", no click | ⏳ after repackaging the desktop app |
| 6 | AC-017-1 | Linux host (usbmuxd, /var/run/usbmuxd) | same as 1–3 | ⏳ no Linux host in this session |
