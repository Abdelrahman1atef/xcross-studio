# Feature Specification: XCross Studio desktop GUI (MVP) and the device pickers it needs

**Feature Branch**: `008-json-events-gui` | **Created**: 2026-11-01 | **Status**: MVP implemented

**Input**: ROADMAP 008: "`--json` NDJSON event stream + Flutter desktop GUI (Windows + Linux): Setup, Project
(create/open), Build, Device & Install, Logs". PLAN "GUI v1". The full NDJSON event stream for builds
(step/progress/artifact) is deferred. The MVP drives the existing commands and classifies their stable
`error:`/`warning:`/`hint:` lines; the device commands already speak NDJSON (feature 010).

## User Story 1 - Do everything from one window (P1)

A Flutter developer on Windows or Linux opens XCross Studio, checks the computer, signs in, opens their project,
builds an IPA, picks the iPhone, runs or installs the app and watches its log, without typing commands.

**Independent Test**: run the app, click through Setup → Project → Device → Device logs → Console with an iPhone
connected; every action runs the matching `xcross` command and shows its output.

**Acceptance Scenarios**:

1. **AC-008-1**: `xcross devices [--json]` lists the USB iPhones (`device` events: udid, name, iOS version,
   connection). The Device page shows them and marks iOS 15/16 as release/profile only. A host-service problem is a
   coded error.
2. **AC-008-2**: `xcross app list [--json]` lists the installed user apps (`app` events, sorted by bundle id) for
   the Device logs app picker.
3. **AC-008-3**: The GUI parses every v1 NDJSON event (`devicelog`, `diagnosis`, `appinfo`, `app`, `device`,
   `crash`, `notice`) and ignores plain text, other JSON and unknown versions or types.
4. **AC-008-4**: Each GUI action builds the right xcross command line (doctor, flutter doctor, build, run, install,
   devices, app list/info, logs with presets and filters, crashes list/pull, auth). Passwords are never shown.
5. **AC-008-5**: Commands stream their output live. `error:`/`warning:` lines with a `[code]` count as issues. Stop
   ends the whole process tree (Windows `taskkill /T /F`; Linux process group via `setsid` + `kill -- -pgid`). Typed
   input reaches the command's stdin (2FA codes, `q`). Output is read as UTF-8 (`XCROSS_OUTPUT_ENCODING`).
6. **AC-008-6**: Device logs show a live table coloured by level, with push lines highlighted. Client-side filters
   (text, process, minimum level), pause/resume, clear, copy and save to file. At most 20 000 lines are kept. The
   push diagnosis is shown as a checklist.
7. **AC-008-7**: App info shows ✔/✖ for the push entitlement and associated domains, plus all installed
   entitlements. Crash reports can be listed and saved.
8. **AC-008-8**: The GUI holds no build or device logic and never imports the xcross packages; every action is an
   `xcross` command.
9. **AC-008-9**: Every page opens from the navigation rail, and the Windows release build compiles (device evidence
   in `device-check.md`).

## Requirements

- **FR-001**: The GUI runs `xcross` (installed, or `dart run <repo>/packages/xcross/bin/xcross.dart` from source) as
  a subprocess. It stores that choice, the project, the device and the DDI folder in a settings file.
- **FR-002**: OS differences live in one `HostPlatform` (Windows/Linux): kill tree, open folder, settings folder,
  process group.
- **FR-003**: xcross writes UTF-8 to stdout/stderr when `XCROSS_OUTPUT_ENCODING=utf-8` (Windows pipes otherwise use
  the ANSI code page).
- **FR-004**: The Setup page shows the not-affiliated-with-Apple notice and never offers Apple downloads.

## Out of scope (later)

NDJSON build events (step/progress/artifact), the project creation wizard, Xcode.xip import, one-click
pymobiledevice3 install, the elevated tunnel for iOS 17+, the bug-report zip, and installers (feature 009).
