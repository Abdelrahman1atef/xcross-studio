# Tasks: XCross Studio desktop GUI (MVP)

S = `packages/studio_ext`, G = `apps/studio`.

- [X] T001 S: `DeviceLogBackend.usbDevices()`; `ensureDevice` uses it; the fake backend gains `devices`.
- [X] T002 S: `DevicesCommand` (`xcross devices [--json]`) and `AppListCommand` (`xcross app list [--json]`);
  contract `device` + `app` events; runner registration and `_deviceJson` (`// studio: 008`).
- [X] T003 `bin/xcross.dart`: `XCROSS_OUTPUT_ENCODING=utf-8` → UTF-8 stdout/stderr (`// studio: 008`).
- [X] T004 S tests: `picker_commands_test.dart` (AC-008-1, AC-008-2).
- [X] T005 G: `flutter create --platforms=windows,linux`; dependencies `file_selector` and `path`.
- [X] T006 G `lib/src/host/host_platform.dart`: Windows/Linux kill tree, open folder, settings folder, process group.
- [X] T007 G `lib/src/cli/`: `XcrossInvocation`, `XcrossCommands`, `XcrossEvent` parsing, `OutputLine`,
  `ProcessLauncher`.
- [X] T008 G `lib/src/state/`: `Job`, `JobCenter`, `LogSession` (throttled, bounded, filters, pause), `Settings`,
  `ProjectInfo`.
- [X] T009 G `lib/src/ui/`: Setup, Project & Build, Device & Install, Device logs (app info, push checklist,
  crashes), Console; `StudioApp` shell.
- [X] T010 G tests: `cli_test`, `state_test`, `app_test` (AC-008-3…9).
- [X] T011 `flutter analyze`, `flutter test`, `flutter build windows --release`; `dart analyze` and tests for S and
  xcross.
- [X] T012 Docs: README (GUI section), CHANGELOG, ROADMAP, `apps/studio/README.md`, `device-check.md`; commit; push.
