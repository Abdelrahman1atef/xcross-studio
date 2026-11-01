# Feature Specification: Device logs — see what the iPhone says

**Feature Branch**: `010-device-logs`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Push notification didn't work but I don't have logs to debug if it works or not. I want
the tool to be able to show the logs of the iPhone (Apple devices) so I can debug anything."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Watch my app's live logs (Priority: P1)

A developer opens their app on a USB-connected iPhone and wants to see, live, everything the app and iOS say about
it, including the app's Dart output, to understand black screens, failed requests or crashes.

**Why this priority**: Without device logs every on-device problem is guesswork (it took a long manual session to
diagnose a real client app's black screen and missing push). This is the single most useful debugging tool and is cheap to build
because xcross already streams syslog during `run` (`DeviceLog`).

**Independent Test**: With any app installed (also one installed by another tool, e.g. Sideloadly), run
`xcross logs --app <bundle-id>`, open the app, and see its lines appear within 2 seconds.

**Acceptance Scenarios**:

1. **AC-010-1** — **Given** an iPhone on iOS 16 connected by USB to a Windows or Linux host, **When** I run
   `xcross logs --app com.example.app` and launch the app, **Then** the app's log lines stream live, without a tunnel,
   without mounting a DeveloperDiskImage, and without admin rights.
2. **AC-010-2** — **Given** the same command on an iOS 17+ device, **When** the app runs, **Then** the behaviour is the
   same as AC-010-1.
3. **AC-010-3** — **Given** the app is not running yet, **When** I start `xcross logs --app <id>`, **Then** the tool
   waits, attaches when the app's process appears, and re-attaches automatically after the app is relaunched.
4. **AC-010-4** — **Given** filters `--process <name>`, `--grep <text|regex>`, `--level <debug|info|notice|error|fault>`,
   **When** I combine them, **Then** only matching lines are shown; `--save <file>` writes the same lines to a file.
5. **AC-010-5** — **Given** `--preset flutter`, **When** the app prints from Dart, **Then** only the `flutter: ` lines are
   shown, with the prefix removed.

---

### User Story 2 - Find out why push notifications don't arrive (Priority: P1)

A developer whose Firebase/APNs notifications never arrive wants a one-step answer: does the installed app even have the
push entitlement, did iOS register it with APNs, and did a message reach the device?

**Why this priority**: This is the exact failure that triggered the feature; push problems are invisible without device
logs and installed-app entitlements.

**Independent Test**: Install an app without `aps-environment` and one with it; run `xcross app info` on both and
`xcross logs --app <id> --preset push` while sending a test message from the Firebase console.

**Acceptance Scenarios**:

1. **AC-010-6** — **Given** an installed app, **When** I run `xcross app info <bundle-id>`, **Then** I see its version,
   signer type (development / distribution / ad-hoc / TestFlight), team id, and the entitlements **as installed**, with
   an explicit ✖ line when `aps-environment` or associated domains are missing.
2. **AC-010-7** — **Given** `--preset push`, **When** the app launches and a test message is sent, **Then** the stream
   shows only push-relevant lines from `apsd`, `usernotificationsd`, `SpringBoard` and the app, and highlights:
   APNs registration/token events, delivery events, and entitlement/registration errors.
3. **AC-010-8** — **Given** the push preset found no APNs registration for the app within 30 seconds of launch,
   **When** the run ends, **Then** the tool prints a short diagnosis with the most likely cause (missing entitlement,
   notification permission denied, no network to APNs) and the next step to check.

---

### User Story 3 - Get crash reports (Priority: P2)

A developer whose app closes immediately wants the crash report from the phone.

**Why this priority**: Native crashes leave reports on the device that the live log does not explain fully.

**Independent Test**: Force a crash in a fixture app; run `xcross crashes list --app <id>` and `xcross crashes pull`.

**Acceptance Scenarios**:

1. **AC-010-9** — **Given** crash reports exist on the device, **When** I run `xcross crashes list [--app <id>]`,
   **Then** I see them newest first (process, date, exception type), and `xcross crashes pull <name|--latest>` saves
   the report locally and prints its exception type and crashed-thread summary.

---

### User Story 4 - The same in the GUI (Priority: P2)

A developer using XCross Studio wants a Device Logs screen instead of a terminal.

**Why this priority**: The GUI is the product's main interface (feature 008); it depends on the `--json` output here.

**Independent Test**: `xcross logs --json` emits one JSON object per line matching the published schema; the GUI
screen renders them (verified in feature 008).

**Acceptance Scenarios**:

1. **AC-010-10** — **Given** `--json`, **When** logs stream, **Then** each line is an NDJSON event
   (`{v:1, type:"devicelog", time, process, pid, subsystem?, level, message}`), plus `type:"diagnosis"` events for the
   push preset and `type:"crash"` for crash listings, matching `specs/010-device-logs/contracts/devicelog.schema.json`.

### Edge Cases

- Device locked or not trusted → clear error with code `device.not_trusted` and the hint "unlock and tap Trust".
- No device / several devices → pick with `--udid`, otherwise list devices and exit with `device.select_required`.
- Windows host without Apple Mobile Device Service, Linux host without `usbmuxd` → error with the exact install hint
  for that OS (`host.device_service_missing`).
- Very chatty devices (thousands of lines/s) → bounded memory, back-pressure, filters applied before printing.
- Unicode/Arabic text in log messages → printed correctly (UTF-8) on Windows consoles and in `--json`.
- Release builds whose app logging is disabled → the tool still shows system lines for the app and notes that the
  app itself printed nothing (suggest a profile build).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The CLI MUST provide `xcross logs`, `xcross crashes list|pull` and `xcross app info`.
- **FR-002**: All three MUST work over plain usbmux/lockdown on iOS 16 and iOS 17+, on Windows and Linux, with no
  tunnel, no DeveloperDiskImage and no elevation.
- **FR-003**: `xcross logs` MUST support `--app`, `--process`, `--grep`, `--level`, `--preset push|crash|flutter`,
  `--save`, `--json`, `--udid`, and attach/re-attach to the app's process automatically.
- **FR-004**: Sensitive values (device UDID, APNs/FCM tokens, account identifiers) MUST be masked by default;
  `--show-sensitive` reveals them.
- **FR-005**: The commands MUST be read-only toward the device (no install, no settings change).
- **FR-006**: `--json` output MUST follow a versioned schema and be identical in shape on Windows and Linux.
- **FR-007**: The existing crash-reason behaviour of `xcross flutter run` (`DeviceLog`) MUST keep working, reusing the
  same stream implementation.

### Key Entities

- **DeviceLogEvent**: time, process, pid, subsystem/category, level, message, flags (highlight, sensitive-masked).
- **PushDiagnosis**: entitlement status, permission status (if detectable), APNs registration seen, delivery seen,
  verdict and hint.
- **CrashReportSummary**: name, process, date, exception type, crashed thread summary.
- **InstalledAppInfo**: bundle id, version, signer type, team id, entitlements.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From plugging in an iPhone to seeing the app's first log line takes under 30 seconds with one command.
- **SC-002**: The client-app push failure (missing `aps-environment` after re-signing) is identified by `xcross app info`
  plus the push preset in under 2 minutes, without any other tool.
- **SC-003**: The log stream sustains at least 2,000 lines/second without dropping filtered lines or growing memory
  beyond a fixed bound.
- **SC-004**: Zero unmasked UDIDs or tokens in default output across all test fixtures.

## Assumptions

- Implementation generalises `DeviceLog` (`packages/xcross/lib/src/target/iphone/device/device_log.dart`, which already
  runs `pymobiledevice3 syslog live --format json` over usbmux) into a reusable stream in `packages/studio_ext`, and adds
  `Pymd` wrappers for `crash ls/pull` and `apps list` next to `PymdDevices` in `packages/dart_mobile_device`.
- pymobiledevice3 remains the device backend (GPL-3.0, called as a separate process).
- Symbolication of crash reports (dSYM) is out of scope for v1.
- The GUI screen is delivered in feature 008; this feature delivers the CLI and the JSON contract.
