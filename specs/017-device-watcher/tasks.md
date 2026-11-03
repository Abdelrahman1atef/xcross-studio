# Tasks: The desktop app sees an iPhone being plugged in or out

D = `packages/dart_mobile_device/lib`, S = `packages/studio_ext/lib`, G = `apps/studio/lib`.

## Phase 1: Setup

- [X] T001 `D/shared/host/device_host_policy.dart`: `defaultUsbmuxAddress`; implement in
  `D/host/windows/windows_device_host.dart` and `D/host/shared/posix_device_host.dart`; update the two test fakes in
  `packages/dart_mobile_device/test/`; `Pymd.usbmuxListenAddress()` in `D/target/iphone/device/pymd/pymd.dart`.

## Phase 2: User Story 1 — live list from the CLI (P1)

- [X] T002 [US1] `D/host/shared/usbmux_listen.dart`: frames, `UsbmuxListener`, events, `UsbmuxUnavailable`.
- [X] T003 [P] [US1] `packages/dart_mobile_device/test/usbmux_listen_test.dart` (AC-017-1) with a loopback fake
  usbmuxd.
- [X] T004 [US1] `S/src/target/iphone/device/device_watch.dart`: `DeviceWatch` (debounce 300 ms, retry 2 s,
  snapshot on change only).
- [X] T005 [US1] `S/target/iphone/device/devices_command.dart`: `--watch` (JSON and text), Ctrl+C stop;
  wire `listen` in `packages/xcross/lib/src/composition/cli/runner.dart` (`// studio: 017`).
- [X] T006 [P] [US1] `packages/studio_ext/test/device_watch_test.dart` (AC-017-2, 3, 4).

## Phase 3: User Story 2 — live badge (P1)

- [X] T007 [US2] G: `DeviceSnapshot` in `src/cli/xcross_events.dart`, `XcrossCommands.devicesWatch()`,
  `JobCenter.background()` in `src/state/job.dart`.
- [X] T008 [US2] G: `DeviceController.watch()`/`serviceDown` in `src/state/devices.dart`; start in `app/shell.dart`;
  chip states in the top bar.
- [X] T009 [P] [US2] `apps/studio/test/state/device_watch_test.dart` (AC-017-5, 6).

## Phase 4: User Story 3 — device evidence (P2)

- [X] T010 [US3] Rebuild the CLI; run `devices --watch --json`, unplug/plug (needs the user's hands), record in
  `specs/017-device-watcher/device-check.md` (AC-017-7).

## Phase 5: Polish

- [X] T011 Analyze (dart_mobile_device, studio_ext, xcross, GUI), tests, CHANGELOG, README, user story TC-34 / AC-08.

## Dependencies

T001 → T002 → T004 → T005; T007 → T008. US2 needs the event contract only.
