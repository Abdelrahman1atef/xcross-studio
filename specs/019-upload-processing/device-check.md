# Store check: 019 upload and processing (Windows host)

An upload creates a build record on the client's App Store Connect account and needs an App Store IPA signed with a
team key, so it is not run without the user's go-ahead.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-019-7 | `xcross flutter build --build-number auto` in app A with the individual key | reads the newest build number (read-only), or falls back to the pubspec number with a warning | see row 3 |
| 2 | AC-019-1…6 | `xcross publish --wait` with app A's App Store IPA | upload COMPLETE, processing VALID, `release.json` filled | ⏳ needs a team key and the user's go-ahead |
| 3 | AC-019-4 | read-only App Store Connect calls with the individual key | app found by bundle ID | ✅ 2026-11-03: app B found, builds read (the same lookup `publish` and `--build-number auto` use); app A has no record visible to this key |
| 4 | AC-019-9 | `xcross publish --validate` with Transporter installed | Transporter's verify result | ⏳ Transporter not installed on this PC |
