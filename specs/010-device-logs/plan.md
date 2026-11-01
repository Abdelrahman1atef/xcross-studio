# Implementation Plan: Device logs — see what the iPhone says

**Branch**: `010-device-logs` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-device-logs/spec.md`

## Summary

New read-only device commands in `packages/studio_ext`:

- **`xcross logs`**: live syslog with app, process, level and regex filters, presets (flutter/crash/push), push
  diagnosis, `--save`, NDJSON `--json`, masking on by default.
- **`xcross app info`**: entitlements as installed, signer type, ✔/✖ for push and associated domains.
- **`xcross crashes list|pull`**: newest first, exception summary.

All of it runs over plain usbmux through pymobiledevice3 (verified on an iPhone X with iOS 16.7.16 from Windows), with
no tunnel, no DeveloperDiskImage and no elevation. A shared `SyslogEntry` parser goes in `dart_mobile_device`, and
`DeviceLog` (flutter run) reuses it. Decisions D1–D12 are in [research.md](research.md).

## Technical Context

**Language/Version**: Dart `^3.10.0` (local 3.13.7)

**Primary Dependencies**:
- workspace: `cli_kit`, `dart_mobile_device` (`Pymd`, `PymdDeviceResolver`, `DeviceHostPolicy`), `args`, `meta`
- external process: pymobiledevice3 ≥ 11, GPL-3.0, called as a subprocess

**Storage**: crash reports pulled to `--out` (default `./crash-reports`) or a temp cache; `--save` file

**Testing**: `package:test` with a fake `DeviceLogBackend`, synthetic syslog/`apps list`/`.ips` fixtures, and real
device rows in `device-check.md`

**Target Platform**: Windows and Linux hosts; iOS 16 and 17+ devices over USB

**Project Type**: CLI feature in the fork package

**Performance Goals**: first app line < 2 s after launch; ≥ 2,000 lines/s through filter and format with constant
memory (SC-003)

**Constraints**:
- read-only toward the device (FR-005)
- masking by default (FR-004)
- NDJSON identical in shape on Windows and Linux (FR-006)
- `repo_analyzer` rules: no stdio or signals in library code; they are injected from composition

**Scale/Scope**: 3 commands, about 12 library files, 10 ACs

No open clarification items remain.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre | Post | Evidence |
|---|---|---|---|
| I. Minimal diff | ✅ | ✅ | Everything is in `studio_ext`. Upstream seams: `runner.dart` (register 3 commands, plus `--json` in `ownsMachineStdout`), the new `SyslogEntry` file in `dart_mobile_device`, and a one-line reuse in `DeviceLog`. All marked `// studio: 010`. |
| II. No Apple material | ✅ | ✅ | No DDI or SDK; reads logs, app metadata and crash reports from the user's own device. |
| III. Fail fast | ✅ | ✅ | Device precheck (service, device, trust) before streaming; coded errors with hints. |
| IV. CLI is the product | ✅ | ✅ | NDJSON `--json` contract for the GUI (008). |
| V. Windows and Linux | ✅ | ✅ | pymobiledevice3 runs on both; the service check is per host (002); UTF-8 byte output for human text. |
| VI. Test-first, device evidence | ✅ | ✅ | AC → test map; `device-check.md` rows on the real iPhone X. |
| VII. Simplicity | ✅ | ✅ | Reuses the pymobiledevice3 commands already proven, `PymdDeviceResolver`, the 002 service probe and codes; no new dependencies. |
| VIII. Credentials | ✅ | ✅ | UDIDs, tokens and emails masked by default; the signer identity (person name) is hidden unless `--show-sensitive`. |

**Gate result**: PASS.

## Project Structure

### Documentation

```text
specs/010-device-logs/
├── spec.md  plan.md  research.md  data-model.md  quickstart.md
├── contracts/cli.md  contracts/devicelog.schema.json
├── device-check.md   # during implementation
└── tasks.md
```

### Source Code

```text
packages/dart_mobile_device/lib/target/iphone/device/pymd/syslog_entry.dart   # NEW shared parser
packages/xcross/lib/src/target/iphone/device/device_log.dart                  # reuse SyslogEntry (seam)
packages/xcross/lib/src/composition/cli/runner.dart                           # register commands (seam)

packages/studio_ext/lib/target/iphone/device/
├── logs_command.dart        # xcross logs
├── app_command.dart         # xcross app info
└── crashes_command.dart     # xcross crashes list|pull
packages/studio_ext/lib/src/target/iphone/device/
├── device_log_backend.dart       # interface + PymdDeviceLogBackend
├── device_codes.dart             # coded errors (shape as 001/002)
├── log_filter.dart               # filters + presets + highlight
├── sensitive_masker.dart
├── push_diagnosis.dart
├── log_output.dart               # human line + NDJSON encoder
├── installed_app_info.dart       # apps list entry → info + signer
└── crash_reports.dart            # names, .ips summary
packages/studio_ext/test/target/iphone/device/…   # unit + command tests with a fake backend
```

**Structure Decision**: the same pattern as `inspect`. Public command classes under `lib/shared/`, `@internal` logic
under `lib/src/shared/`, and composition injecting `Pymd`, the file system, the byte/string writers and the
interrupt stream.

### AC → tests

| AC | Test |
|---|---|
| AC-010-1/2/3 | `logs_command_test`: app filter by executable, waiting notice, relaunch (new pid, same name) keeps streaming; real rows 2 |
| AC-010-4 | `log_filter_test` (process, grep, level) and `logs_command_test` `--save` |
| AC-010-5 | `log_filter_test` flutter preset |
| AC-010-6 | `installed_app_info_test` (signer, team, ✔/✖) and `app_command_test` |
| AC-010-7 | `log_filter_test` push preset and highlights |
| AC-010-8 | `push_diagnosis_test` (each verdict) and the `logs_command_test` diagnosis at 30 s and at the end |
| AC-010-9 | `crash_reports_test` (names, `.ips` summary, newest first) and `crashes_command_test` |
| AC-010-10 | `log_output_test` NDJSON plus schema validation |
| SC-003 | `throughput_test` |
| SC-004 | `sensitive_masker_test` and a no-leak check across the command tests |
| FR-007 | the existing `DeviceLog` tests stay green |

## Complexity Tracking

None.
