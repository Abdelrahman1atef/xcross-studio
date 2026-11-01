# Device check: 012 build events (Windows host, iPhone X iOS 16.7.16)

No device names, UDIDs or client bundle ids are recorded here.

| # | AC | Step | Expected | Result |
|---|---|---|---|---|
| 1 | AC-012-2, 5 | `$env:XCROSS_EVENTS='ndjson'; xcross flutter doctor` (outside a project) | every line is JSON; `check` per check; `error` + `done` 1 when checks fail | ✅ 2026-11-01, run from source on Windows: 22 lines, all JSON (14 `check`, 6 `log`, 1 `error`, `done` 1). This host has no Swift/Darwin SDK, so those checks fail for real |
| 2 | AC-012-3 | `xcross doctor` (no such top-level command) with the variable set | `error` with the usage text, `done` 64 | ✅ 2026-11-01 |
| 3 | AC-012-7, 8 | GUI → Project → Build (release, .ipa) on a host with the SDK | step chips fill in with times; download bar during the engine download; warnings with codes and hints; **Install demo.ipa** names the built file | ⏳ |
| 4 | AC-012-4, 8 | GUI → Device → Build & run (release) with the iPhone X | `device` event (iOS 16.7.16, legacy); steps through install; the app opens or tap-the-icon guidance | ⏳ |
| 5 | AC-012-8 | GUI → Setup → Run doctor | checklist grouped by section, with ✔ / ! / ✖ | ⏳ |
| 6 | AC-012-9 | same commands without the variable in a terminal | human output unchanged (spinners, ✓/✗) | ⏳ |
