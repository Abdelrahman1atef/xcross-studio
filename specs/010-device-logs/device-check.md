# Device check: 010 device logs

Real-device evidence (constitution Principle VI).

- **Host**: Windows 11 (native), 2026-11-01
- **Device**: iPhone X (`iPhone10,6`) on iOS 16.7.16, over USB
- **pymobiledevice3**: 11.49.1 via `py -m pymobiledevice3`
- **xcross**: `dart run packages/xcross/bin/xcross.dart …`

No device names, UDIDs or client bundle ids are recorded here.

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | AC-010-1 (stream) | `xcross logs --duration 5` | live lines over plain usbmux; no tunnel, no DDI, no admin | ✅ 3,611 lines in 5 s (D/I/N/E levels), `HH:MM:SS.mmm process[pid] L message`, exit 0 |
| 2 | AC-010-6 | `xcross app info <app with Arabic executable name>` | version, signer, team, ✔/✖ push and domains; Unicode shown correctly | ✅ the Arabic name printed correctly; `signer: app-store · team …`; `✔ push entitlement aps-environment = production`. `--json` is one ASCII-only `appinfo` line that round-trips the Arabic executable name. |
| 3 | AC-010-8 | `xcross logs --app <app> --preset push --json --duration 35` (app not launched) | waiting notice; diagnosis at 30 s and at the end | ✅ events: `notice` ×1, `diagnosis` ×2, verdict `app_not_running`, entitlement `production`, exit 0 |
| 4 | AC-010-10 | `xcross logs --json --duration 3` | every line is valid NDJSON, ASCII only | ✅ 816 events, all parse, ASCII only. The first run found a bug: the shared resolver's "Finding devices…" progress went to stdout and broke `--json`. Fixed by listing USB devices directly (no progress, no prompt) and re-verified. |
| 5 | Edge: no device | iPhone dropped off USB, then `xcross crashes list` | `error: [device.not_found] …` | ✅ `error: [device.not_found] No iPhone is connected by USB.` plus the hint |
| 6 | AC-010-3 | `xcross logs --app <app>`, then launch and relaunch the app | app lines appear and continue after relaunch | ⏳ needs the phone reconnected and the app launched by hand (unit-tested with a pid change) |
| 7 | AC-010-4 | `xcross logs --process SpringBoard --level notice --grep . --save f --duration 5` | filtered lines; the file equals stdout | ✅ 2026-11-02, iPhone X iOS 16.7.16, Windows: 37 lines on stdout, the same 37 in `sb.txt` |
| 8 | AC-010-9 | `xcross crashes list` / `crashes pull --latest` | newest first with exception types; the report saved with a summary | ✅ 2026-11-02, iPhone X iOS 16.7.16, Windows: list newest first with exception types; **bug found and fixed**: iOS moves copied reports into `/Retired`, so after the first `list` everything vanished and `pull --latest` said "Saved" without a file. Now `crash ls --depth 2`, a per-folder pull, the real saved path, and an error if nothing was copied; re-verified (1 file saved) |
| 9 | AC-010-5 | `xcross logs --app <flutter debug app> --preset flutter` | Dart output only | ⏳ needs a Flutter app launched on the device |
| 10 | AC-010-2 | rows 1–4 on an iOS 17+ device | same | ⏳ needs an iOS 17+ device |
| 11 | all | Ubuntu 24.04 host | same | ⏳ deferred (Linux verification deferred by the user) |

Known v1 limitation (found on the device): most Flutter apps use the executable name `Runner`. `--app` filters by
executable name, so if two `Runner` apps run at the same time, both apps' lines are shown.
