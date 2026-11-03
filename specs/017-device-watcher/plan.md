# Implementation Plan: The desktop app sees an iPhone being plugged in or out

**Branch**: `017-device-watcher` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

D = `packages/dart_mobile_device/lib`, S = `packages/studio_ext/lib`, G = `apps/studio/lib`.

- **D/host/shared/usbmux_listen.dart** (new): `UsbmuxFrames` (encode/decode the 16-byte header + XML plist),
  `UsbmuxListener.listen()` → `Stream<UsbmuxEvent>` (`UsbmuxAttached` with device id, UDID, connection type;
  `UsbmuxDetached`); errors as `UsbmuxUnavailable`. Socket connect reuses the `host:port` / unix-path parsing of
  `usbmux_service_probe.dart`.
- **D/shared/host/device_host_policy.dart**: `defaultUsbmuxAddress` (Windows `127.0.0.1:27015`, POSIX
  `/var/run/usbmuxd`; the constants already exist in the hosts). `Pymd.usbmuxListenAddress()` =
  `resolvedUsbmuxAddress() ?? hostPolicy.defaultUsbmuxAddress`.
- **S/src/target/iphone/device/device_watch.dart** (new): `DeviceWatch.run(stop)` — connect, list once, relist on
  attach (300 ms debounce, serialized), drop on detach, `notice` + empty snapshot once when the service is down,
  retry every 2 s. Pure logic with injected `listen`, `list`, `delay`.
- **S/target/iphone/device/devices_command.dart**: `--watch` (JSON snapshots or `+`/`-` lines; stops on Ctrl+C).
  Wired in `packages/xcross/lib/src/composition/cli/runner.dart` (`// studio: 017`); `devices --watch --json` owns
  stdout (already covered by `_deviceJson`).
- **G**: `DeviceSnapshot` event (`devices`); `XcrossCommands.devicesWatch()`; `JobCenter.background()` (a job not
  listed in the console or the running count); `DeviceController.watch()` (snapshots, service notice, restart after
  3 s only when the watch had run ≥ 10 s, so an older CLI without `--watch` falls back to Refresh); shell starts it
  next to `refresh()`; top-bar chip: name + green, "Plug in an iPhone" grey, "Device service not reachable" warning.

## Complexity Tracking

`propertylistserialization ^1.5.0` is added to `dart_mobile_device` (Constitution VII): the same version
`xcross`, `apple_developer_kit` and `studio_ext` already use, for usbmuxd's XML plist messages, instead of a
hand-written plist parser.

## Technical Context

Dart 3 / Flutter 3.47 · dependencies already present (`propertylistserialization` in dart_mobile_device) · tests:
fake usbmux server on a loopback TCP port (real socket), fake streams for the watch, FakeLauncher for the GUI ·
Windows and Linux (TCP and unix socket).

## Constitution Check

I minimal diff: new files plus marked seams · II nothing Apple-supplied · III service down → notice with retry ·
IV GUI only consumes events · V address from the host policy, no OS branches in shared code · VI tests named
AC-017-n, device rows · VII no new dependency · VIII snapshots carry only what `devices --json` already prints.
No violations.

## Tests

`packages/dart_mobile_device/test/usbmux_listen_test.dart` (AC-017-1), `packages/studio_ext/test/device_watch_test.dart`
(AC-017-2…4), `apps/studio/test/state/device_watch_test.dart` (AC-017-5, 6).
