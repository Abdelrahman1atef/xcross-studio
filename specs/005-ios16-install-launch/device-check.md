# Device check: 005 (to run on the iPhone X, iOS 16.7.16)

Prerequisites:
- `xcross auth` (Apple ID) done once
- `pymobiledevice3` installed
- phone connected and unlocked

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | AC-005-4 | `xcross flutter run` (debug) in a Flutter project | `error: [device.legacy_debug_unsupported] …` before any build step | ✅ 2026-11-02, iPhone X iOS 16.7.16, Windows: `device.legacy_debug_unsupported` after 3.7 s, before any build step |
| 2 | AC-005-1, 3 | `xcross flutter run --release` | built, signed, installed; "Tap the app icon …" (no image); the app opens from its icon | ⏳ |
| 3 | AC-005-2 | same, with `~/.xcross/DeviceSupport/16.x/` from an Xcode that has it | the image is mounted and the app launches by itself | ⏳ (needs an Xcode ≤ 14.3 DeviceSupport folder) |
| 4 | AC-005-5 | `xcross install some.ipa` | re-signed, installed, guidance printed; the app opens from its icon | ⏳ |
| 5 | AC-005-6 | `xcross install notes.txt` | `error: [install.unsupported_input]` | ✅ 2026-11-02, iPhone X iOS 16.7.16, Windows: `install.unsupported_input` + hint |
