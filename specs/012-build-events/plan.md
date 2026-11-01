# Implementation Plan: NDJSON build events

**Branch**: `012-build-events` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

- **Seam (cli_kit)**: `Log` gets an optional `LogEvents` observer (`// studio: 012`). When it is set, `logStatus`,
  `logTrace`, `logWarn` and `logError`, `Step` start/output/done/fail, and `ProgressBar` updates go to the observer
  instead of `output`, with no spinner or bar drawing. `Log` is a `final class` that every command already reaches
  (`runtime.log`), so this one hook covers all steps, warnings and errors without touching the commands.
- **Writer (studio_ext)**: `shared/events/ndjson_events.dart`. `NdjsonEvents` implements `LogEvents` and writes v1
  ASCII-only NDJSON. It parses `[code] message` + `hint:` (the format of `codedError`, `codedWarning` and
  `formatFailure`) into `warning`/`error` events. `NdjsonLogOutput` turns text written straight to `Log.output` into
  `log` events.
- **xcross hooks** (each marked `// studio: 012`):
  - `native_runtime.dart`: `XCROSS_EVENTS=ndjson` selects the writer as `Log.events` and `Log.output`.
  - `runner.dart`: failures go through `reportFailure` (an `error` event in event mode); `done` comes from `finally`.
  - `flutter_pack_operation.dart`: an `artifact` event for the `.app`.
  - `flutter_build_command.dart`: an `artifact` event for the `.ipa`.
  - `device_precheck.dart` and `device_run_operation.dart`: a `device` event.
  - `doctor_command.dart`: `check` events.
- **GUI**: `XcrossEvent.split` and the new event classes. `Job(structured: true)` sets the variable and keeps steps,
  progress, artifacts, checks, the device and the exit code. `StepsPanel`, `IssueList` and `DoctorReport` widgets.
  The Project page's Install uses `job.artifact('ipa')`. Also fixed: Setup's doctor ran a nonexistent top-level
  `xcross doctor`; it now runs `flutter doctor`.

## Technical Context

**Language/Version**: Dart `^3.10` (CLI), Flutter 3.47 (GUI)

**Dependencies**: none new.

**Testing**: cli_kit `log_events_test.dart`; studio_ext `ndjson_events_test.dart` (contract validation through
`JsonSchemaLite.buildEventsContract()`); xcross `test/cli/build_events_test.dart`; GUI
`test/state/build_events_test.dart`. Real run: `XCROSS_EVENTS=ndjson xcross flutter doctor` on Windows printed 22
lines, all JSON (14 `check`, `log`, `error`, `done`).

**Constraints**: default output unchanged; no UDIDs; ASCII-only.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ⚠ justified | one optional observer in cli_kit's `Log` (`final class`; no other way to see steps without text scraping); the writer lives in studio_ext; xcross hooks are one to six lines each |
| III | ✅ | coded warnings/errors keep their stable codes and hints as fields |
| IV | ✅ | the GUI consumes events, holds no build logic |
| V | ✅ | pure Dart; the same on Windows and Linux |
| VI | ✅ | AC → tests below; device row in `device-check.md` |
| VIII | ✅ | no UDID in `device` events |

## AC → tests

| AC | Test |
|---|---|
| AC-012-1 | `packages/cli_kit/test/log_events_test.dart` |
| AC-012-2 | `packages/studio_ext/test/shared/events/ndjson_events_test.dart` |
| AC-012-3, 4, 5 | `packages/xcross/test/cli/build_events_test.dart` |
| AC-012-6, 7, 8 | `apps/studio/test/state/build_events_test.dart` |
| AC-012-9 | existing human-output tests unchanged; `device-check.md` |
