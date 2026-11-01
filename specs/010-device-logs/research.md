# Research: 010 device logs

Phase 0 output for [plan.md](plan.md). Facts come from the real iPhone X (iOS 16.7.16) over USB from native Windows
with pymobiledevice3 11.49.1 (2026-11-01), plus the existing `DeviceLog` code.

## Observed backend facts

- **`pymobiledevice3 syslog live --format json`** streams over plain usbmux: no tunnel, no DDI, no elevation (an
  idle iPhone X sent about 490 lines/s).
  - Each line is one JSON object with the keys `pid`, `procid`, `thread_id`, `timestamp` (local time, no zone),
    `level` (`DEBUG|INFO|NOTICE|ERROR|FAULT`), `image_name` (library path), `filename` (the process executable path),
    `message` and `label` (`{subsystem, category}`).
  - The process name is the basename of `filename`.
  - Filters exist: `--pid`, `--process-name`, `--match`, `--regex`.
- **`pymobiledevice3 apps list --type User`** returns a JSON object keyed by bundle id. Each value carries:
  - `CFBundleExecutable` (the process name to filter syslog by)
  - `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleDisplayName`
  - `Entitlements` (as installed: `aps-environment`, `application-identifier`,
    `com.apple.developer.team-identifier`, …)
  - `SignerIdentity` (a certificate common name, which can contain a person's name)
- **`pymobiledevice3 crash ls`** lists `/<Process>-YYYY-MM-DD-HHMMSS.ips` files and folders. `crash pull <out>
  [remote] --match <regex>` copies matching files. `.ips` files (iOS 15+) are one JSON header line (`app_name`,
  `bundleID`, `timestamp`, `bug_type`, `os_version`) followed by a JSON body (`exception{type,signal}`,
  `faultingThread`, `threads[].frames[]`, `usedImages[]`).
- `DeviceLog` (`packages/xcross/lib/src/target/iphone/device/device_log.dart`) already runs `syslog live --format json`
  during `flutter run`, filters by pid, and keeps a crash-reason ring buffer.

## Decisions

### D1 — Placement (Principle I)

- **Decision**: the commands (`xcross logs`, `xcross app info`, `xcross crashes list|pull`) and all their logic go in
  **`packages/studio_ext`**, registered at the `runner.dart` seam like `inspect`. One small shared piece goes in
  **`dart_mobile_device`**: `SyslogEntry` (parse one `syslog live --format json` line). `DeviceLog` reuses it (FR-007)
  in a one-line seam.
- **Rationale**: these are new fork features with minimal upstream diff. Sharing the parser is the "same stream
  implementation" FR-007 asks for, without rewriting `DeviceLog`.
- **Alternatives**: rewrite `DeviceLog` on top of the new stream (rejected: a large upstream diff, and risky for the
  hot-reload path).

### D2 — App filtering without a pid

- **Decision**: `--app <bundle-id>` resolves the bundle's `CFBundleExecutable` through `apps list`, then keeps entries
  whose process name (basename of `filename`) equals it. The tool prints "waiting for <exe>… launch the app" until
  the first app line arrives.
- **Rationale**: no process list is needed (that would need the DDI on iOS 16). Filtering by name follows relaunches
  automatically (AC-010-3), and works for apps installed by any tool.
- **Alternatives**: `dvt proclist` / `--pid` (rejected: needs the DDI on iOS < 17, and loses relaunches).

### D3 — Backend seam

- **Decision**: studio_ext defines `DeviceLogBackend`, implemented by `PymdDeviceLogBackend(Pymd)`, with these
  methods:
  - `ensureDevice(udid)`: the 002-style precheck (service probe and `PymdDeviceResolver`, USB mode)
  - `syslog(udid)`: a stream of lines plus `stop()`
  - `installedApps(udid)`
  - `crashNames(udid)`
  - `pullCrashes(udid, names, dir)`

  It uses only public dart_mobile_device API: `Pymd.resolve()`, `Pymd.runner`, `Pymd.usbmuxEnvironment()`,
  `hostPolicy.deviceServiceProblem`, `PymdDeviceResolver`. Commands and tests depend on the interface.
- **Rationale**: unit tests run on every OS with a fake backend. Wireless devices are out of scope (on
  Windows/Linux, usbmux syslog only reaches USB devices), so resolution uses USB mode.

### D4 — Filters and levels

- **Decision**:
  - `--level <debug|info|notice|error|fault>` keeps that level and above.
  - `--process` is repeatable and matches the process name or pid.
  - `--grep` is a regex (case-insensitive) on the message.
  - Filters run in Dart, before formatting, on one line at a time, so memory stays bounded (SC-003).
  - A `--duration <s>` option (an addition for scripts and validation) stops the stream after N seconds.
- **Rationale**: a single place for the preset logic; pymobiledevice3's own filters cannot express "app OR apsd
  mentioning the bundle id".

### D5 — Presets

- **flutter**: app process only, messages starting with `flutter: `, prefix removed (the same rule as `DeviceLog`).
- **crash**: the app's `ERROR`/`FAULT` lines, plus any line mentioning the app that matches crash patterns
  (`Terminating app due to uncaught exception`, `EXC_`, `SIGABRT`, `Fatal error`, `jetsam`, `crash`, `exited`), from
  `ReportCrash`, `SpringBoard`, `runningboardd` or the app.
- **push**:
  - Shows lines from the app that match push keywords, and from `apsd`, `usernotificationsd` and `SpringBoard`
    that mention the bundle id, or that match push error patterns.
  - Highlights: `registration` (register/token/APNS), `delivery` (received/incoming push or notification), `error`
    (`aps-environment`, `no valid`, `Failed to register`, `denied`, `not authorized`).

### D6 — Push diagnosis (AC-010-8)

- **Decision**: `PushDiagnosis` combines:
  - the installed `aps-environment` (from `apps list`)
  - the highlights seen (registration, delivery, entitlement error, permission denied)
  - whether the app produced any line at all

  A verdict and hint are printed 30 s after the first app line (or 30 s after start if the app never logs), again
  when the stream ends, and as a `diagnosis` event in `--json`.

  | Condition (first match) | Verdict |
  |---|---|
  | `aps-environment` missing, or an entitlement error | missing entitlement → re-sign with push (feature 003) |
  | permission denied seen | notifications denied → Settings |
  | no app lines | app not running → launch it |
  | no registration | app did not register (FCM/APNs setup, network) |
  | registration but no delivery | registered; send a test message, check development vs production APNs |
  | delivery | delivered |

- **Rationale**: answers "why no push" in one run (SC-002).

### D7 — Masking (FR-004, SC-004)

- **Decision**: by default, replace these patterns in messages:

  | Pattern | Replacement |
  |---|---|
  | device UDIDs: 8-16 hex with a dash, or 40 hex | `<udid>` |
  | APNs tokens: 64 hex | `<token>` |
  | FCM tokens: `…:APA91b…` | `<token>` |
  | email addresses | `<email>` |

  `app info` shows the signer type but not the raw `SignerIdentity` (it can contain a name). `--show-sensitive`
  disables all of this.

### D8 — Output

- **Human**: `HH:MM:SS.mmm process[pid] L message`, where L is D/I/N/E/F, with `★` before highlighted lines.
- **`--json`**: NDJSON lines with `v: 1` and a `type`:
  - `devicelog`: `time`, `process`, `pid`, `subsystem`, `category`, `level`, `message`, `highlight`
  - `diagnosis`
  - `crash`
  - `appinfo`

  Contract: [contracts/devicelog.schema.json](contracts/devicelog.schema.json).
- **Encoding**: JSON is ASCII-escaped, the same rule as feature 001. Human text is written as **UTF-8 bytes**
  through an injected byte writer (composition passes `stdout.add`), so Arabic and other non-ASCII text shows
  correctly in UTF-8 consoles and files on Windows.
- **`--save <file>`** gets the same rendered lines, written synchronously through `HostFileSystemInterface` so nothing
  is lost on Ctrl+C.

### D9 — Interrupts

- **Decision**: composition injects `Stream<void> interrupts` (`ProcessSignal.sigint.watch()`). On Ctrl+C, `logs`
  stops pymobiledevice3, prints the final push diagnosis (push preset), closes `--save` and exits 0.
- **Rationale**: library code stays free of ambient process state (`repo_analyzer`).

### D10 — Crashes

- **list**:
  - `crash ls` lists the files; only top-level `*.ips` files are parsed from their names (process, timestamp).
  - The list is filtered by `--app` (process name equals the app executable) and sorted newest first.
  - The newest 20 are pulled into a cache directory and their header/body give the exception type.
- **pull**: `crashes pull <name|--latest> [--app] [--out dir]` copies the file to `--out` (default
  `./crash-reports`). It prints the exception type, signal, and the top 5 frames of the faulting thread
  (`usedImages` name + symbol, else offset). Symbolication is out of scope.
- The saved file may contain device identifiers, and the command says so.

### D11 — Errors (Principle III)

- **Decision**: the same `[code] message` + `hint:` shape as feature 001:
  - `device.not_found` and `device.host_service_unavailable` reuse the codes and hints from 002
  - `device.not_trusted`: the pymobiledevice3 error mentions `PasswordProtected`, `PairingDialogResponsePending`,
    `NotPaired` or `InvalidHostID`
  - `app.not_installed`
  - `crash.not_found`
- **Spec alignment**: the draft spec's edge-case code names (`host.device_service_missing`, `device.select_required`)
  map onto 002's `device.host_service_unavailable` and the existing multi-device picker / `--udid` error, so codes
  stay consistent across features.

### D12 — Testing

- **Decision**:
  - **Unit tests in studio_ext**: `SyslogEntry` (in dart_mobile_device), filters, presets, masking, diagnosis,
    formatter, crash name/`.ips` parsing, signer classification, and command tests with a fake backend. Test names
    contain the AC ids.
  - **Throughput test**: 20,000 synthetic lines through filter and format in < 10 s, with constant memory
    (SC-003).
  - **Real-device rows**: `device-check.md` on the iPhone X.
