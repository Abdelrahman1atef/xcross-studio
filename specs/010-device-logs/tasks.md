---

description: "Task list for feature 010-device-logs"
---

# Tasks: Device logs — see what the iPhone says

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: Required (Principle VI). Test names contain `AC-010-n`.

**Stories**:

| Story | Priority | Scope |
|---|---|---|
| US1 | P1 | live app logs |
| US2 | P1 | push: app info, push preset, diagnosis |
| US3 | P2 | crashes |
| US4 | P2 | `--json` contract |

Paths: SX = `packages/studio_ext`, SXD = `packages/studio_ext/lib/src/target/iphone/device`,
SXT = `packages/studio_ext/test/target/iphone/device`.

## Rules

- `@internal` on every public declaration in `SXD`.
- No stdio, `Platform` or `ProcessSignal` in library code; composition injects them.
- Upstream seams are marked `// studio: 010`.

## Phase 1: Setup

- [X] T001 Add `dart_mobile_device: ^1.0.0` to `SX/pubspec.yaml`; run `dart pub get`.
- [X] T002 Create `packages/dart_mobile_device/lib/target/iphone/device/pymd/syslog_entry.dart`:
  - `final class SyslogEntry {pid, process, time, level, subsystem, category, message}` with
    `static SyslogEntry? tryParse(String line)`, following the rules in data-model.md
  - unit tests in `packages/dart_mobile_device/test/syslog_entry_test.dart`: the real field shape, a non-JSON line,
    a missing pid

## Phase 2: Foundational

- [X] T003 [P] `SXD/device_codes.dart`: `DeviceCode(code, hint)` constants (`device.not_found`,
  `device.host_service_unavailable`, `device.not_trusted`, `app.not_installed`, `crash.not_found`) with hints from
  [contracts/cli.md](contracts/cli.md), plus `DeviceFailure` (code, message, hint) and
  `CliError cliErrorOf(DeviceFailure)` producing `[code] message\nhint: …`.
- [X] T004 [P] `SXD/sensitive_masker.dart`: `String mask(String text)` with the data-model patterns. Tests:
  `SXT/sensitive_masker_test.dart`, test `SC-004 masks UDIDs, tokens and emails`.
- [X] T005 [P] `SXD/log_output.dart`:
  - `String humanLine(DeviceLogEvent)`, `String ndjson(Map<String, Object?>)` (one line, ASCII-escaped, LF)
  - `DeviceLogEvent {entry, message (masked), highlight}` and `toJson()`

  Tests in `SXT/log_output_test.dart`.
- [X] T006 `SXD/device_log_backend.dart`:
  - `abstract interface class DeviceLogBackend` with `Future<String> ensureDevice(String? udid)` (returns the udid
    used), `Future<SyslogSession> syslog(String udid)` (`lines`, `stop()`),
    `Future<Map<String, Map<String, Object?>>> installedApps(String udid)`, `Future<List<String>> crashNames(String
    udid)`, `Future<void> pullCrashes(String udid, List<String> names, String directory)`
  - `PymdDeviceLogBackend(Pymd)` implementing it with pymobiledevice3: `syslog live --format json --udid`,
    `apps list --type User`, `crash ls`, `crash pull <dir> --match <regex>`; environment `PYTHONUNBUFFERED=1`,
    `PYTHONIOENCODING=utf-8` plus `pymd.usbmuxEnvironment()`
  - `ensureDevice`: service probe → `PymdDeviceResolver(pymd).resolveDevice(selector, mode: usb)`, mapped to coded
    errors; trust failures (`PasswordProtected|PairingDialogResponsePending|NotPaired|InvalidHostID`) →
    `device.not_trusted`
  - `test/support/fake_device_backend.dart` for the command tests

## Phase 3: US1 — live app logs (P1) 🎯 MVP

- [X] T007 [P] [US1] `SXT/log_filter_test.dart`:
  - `AC-010-4 process, grep and level filters combine`
  - `AC-010-5 flutter preset strips the prefix`
  - `AC-010-1 app filter keeps only the app executable`
  - `AC-010-3 a relaunched app (new pid) still matches`
- [X] T008 [US1] `SXD/log_filter.dart`:
  - `LogLevel` (ordered), `LogPreset {none, flutter, crash, push}`
  - `LogFilter({appExecutable, bundleId, processes, grep, minLevel, preset})` with
    `DeviceLogEvent? apply(SyslogEntry, {required bool mask})`
  - crash and push matching plus highlights (research D5)
- [X] T009 [P] [US1] `SXT/logs_command_test.dart` with the fake backend:
  - app resolution via `installedApps` (`CFBundleExecutable`); `app.not_installed`
  - the waiting notice
  - streaming and `--save` (same lines)
  - `--duration` stop
  - an interrupt stops cleanly with exit 0
  - `--preset push` without `--app` → `UsageException`
  - no UDID in the output
- [X] T010 [US1] Create the public `SX/lib/target/iphone/device/logs_command.dart`:
  - `LogsCommand({required DeviceLogBackend backend, required HostFileSystemInterface fileSystem,
    required void Function(List<int>) writeBytes, required Stream<void> interrupts,
    Future<void> Function(Duration) delay})`
  - options as in the contract; a session loop applying the filter, writing UTF-8 bytes (human) or ASCII NDJSON,
    and appending to `--save` synchronously
  - stops on stream end, `--duration` or an interrupt; on start-up failure it surfaces `pymobiledevice3` stderr
- [X] T011 [US1] Register in `packages/xcross/lib/src/composition/cli/runner.dart` (`// studio: 010`):
  - `LogsCommand(backend: PymdDeviceLogBackend(pymd), fileSystem: runtime.host.fileSystem, writeBytes: stdout.add,
    interrupts: ProcessSignal.sigint.watch().map((_) {}))`
  - extend `ownsMachineStdout` for `logs --json`
- [X] T012 [US1] In `packages/xcross/lib/src/target/iphone/device/device_log.dart`, make `appLogMessage` use
  `SyslogEntry.tryParse` (`// studio: 010`); the existing tests stay green (FR-007).

## Phase 4: US2 — push (P1)

- [X] T013 [P] [US2] `SXT/installed_app_info_test.dart`: `AC-010-6 signer, team, push and domains from apps list`,
  covering each signer type.
- [X] T014 [P] [US2] `SXT/push_diagnosis_test.dart`, test `AC-010-8 each verdict`, plus a highlight test for the push
  preset in `log_filter_test.dart` (`AC-010-7`).
- [X] T015 [US2] `SXD/installed_app_info.dart` (data model) and `SXD/push_diagnosis.dart` (observe(event), verdict,
  hint, `toJson()`).
- [X] T016 [US2] Create the public `SX/lib/target/iphone/device/app_command.dart`: `AppCommand` with the subcommand `info
  <bundle-id>` (`--udid`, `--json`, `--show-sensitive`), producing the human format from the contract or one
  `appinfo` NDJSON line. Add `SXT/app_command_test.dart`.
- [X] T017 [US2] Push diagnosis in `logs`:
  - with `--preset push`, read the entitlement from `installedApps`
  - emit the diagnosis 30 s after the first app line (or after start) and at the end (human block or `diagnosis`
    event)
  - test in `logs_command_test.dart`: `AC-010-8 diagnosis after 30 s and at the end`, using an injected delay
- [X] T018 [US2] Register `AppCommand` in `runner.dart` (seam); `ownsMachineStdout` for `app info --json`.

## Phase 5: US3 — crashes (P2)

- [X] T019 [P] [US3] `SXT/crash_reports_test.dart`, test `AC-010-9 names, newest first, .ips summary`, with a
  synthetic `.ips` (header line plus body) and a legacy non-JSON body.
- [X] T020 [US3] `SXD/crash_reports.dart`: `CrashName.tryParse`, `CrashReportSummary.fromIps(String text)`,
  `topFrames`.
- [X] T021 [US3] Create the public `SX/lib/target/iphone/device/crashes_command.dart`: `crashes list [--app] [--json]`
  (pulls the newest 20 matching into a temp cache to read exception types) and `crashes pull <name|--latest> [--app]
  [--out]`. Add `SXT/crashes_command_test.dart`.
- [X] T022 [US3] Register `CrashesCommand` (seam); `ownsMachineStdout` for `crashes list --json`.

## Phase 6: US4 — JSON contract (P2)

- [X] T023 [P] [US4] `SXT/devicelog_schema_test.dart`, test `AC-010-10 every event validates`: `devicelog`,
  `diagnosis`, `crash`, `appinfo` and `notice` events from the command tests, checked against
  `specs/010-device-logs/contracts/devicelog.schema.json` (reuse `test/support/json_schema_lite.dart`).

## Phase 7: Polish

- [X] T024 [P] `SXT/throughput_test.dart`, test `SC-003 20000 lines filtered and formatted under 10 s`.
- [ ] T025 Real-device run on the connected iPhone X (quickstart §2 rows 1, 2, 3, 5, 6, 7, 8, 9), recorded in
  `specs/010-device-logs/device-check.md` (no device names, UDIDs or bundle ids of client apps).
  _Partial (see `device-check.md`): rows 1–5 pass on the iPhone X; rows 6–9 need the phone reconnected and an app
  launched by hand; rows 10–11 need an iOS 17+ device and a Linux host._
- [X] T026 [P] Docs: README command rows, CHANGELOG entry, `specs/ROADMAP.md`, `specs/HANDOFF.md`.
- [X] T027 `dart format` (touched files only), `dart analyze --fatal-warnings`, and the full tests for `studio_ext`,
  `dart_mobile_device` and `xcross`.
- [X] T028 Commit on `010-device-logs` and push.

## Dependencies

Setup → Foundational (T003–T006) → US1 (T007–T012) → US2 (T013–T018) → US3 (T019–T022) → US4 (T023) → Polish.
`runner.dart` edits (T011, T018, T022) are sequential.
