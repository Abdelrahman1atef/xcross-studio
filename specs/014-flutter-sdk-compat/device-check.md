# Device check: 014 Flutter SDK for iOS builds (Windows host, iPhone X iOS 16.7.16)

The PC's own Flutter is 3.47.8, which has no published iOS compiler for Windows (newest: 3.47.6).

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-014-6 | `xcross flutter sdk list` | "✖ no iOS release compiler", fix with 3.47.6 | ✅ 2026-11-02 (CLI, before the click) |
| 2 | AC-014-6 | `xcross flutter build --release --ipa` in a project | `error: [build.gen_snapshot_unavailable] …`, "Newest … : 3.47.6", hint `xcross flutter sdk auto` | ✅ 2026-11-02 |
| 3 | AC-014-8 | XCross Studio → Build & Run → Build IPA (release) | plain card "Your Flutter (3.47.8) is newer …", button "Set up Flutter 3.47.6 for iPhone builds" | ⏳ |
| 4 | AC-014-3, 8 | click the button | steps "Downloading Flutter 3.47.6 (about 1 GB, once)", "Preparing Flutter 3.47.6", "Selecting …"; then "Flutter 3.47.6 is set up for iPhone builds" | ⏳ |
| 5 | AC-014-11 | "Build again", then Build & Run (release) on the iPhone X | IPA built, signed, installed; the app opens from its icon | ⏳ |
| 6 | AC-014-10 | Settings → Flutter for iOS builds | "iOS builds use Flutter 3.47.6 · Installed by XCross Studio"; "Use my own Flutter" switches back | ⏳ |
| 7 | AC-014-9 | Overview after a doctor run | "iOS release compiler" card ✓ once fixed (✗ with the card before) | ⏳ |
