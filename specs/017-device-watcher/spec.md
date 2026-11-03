# Feature Specification: The desktop app sees an iPhone being plugged in or out

**Feature Branch**: `017-device-watcher` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 017. On the Windows PC the iPhone's USB link drops now
and then, and XCross Studio only notices when the user presses Refresh or a build fails with "no device". US-IOS-001
AC-08 device testing needs the device state to be live. A Dart usbmuxd `Listen` client, `xcross devices --watch
--json` and a background watch in the desktop app give that.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Live device list from the CLI (Priority: P1)

A developer (or the desktop app) runs `xcross devices --watch --json` and gets the connected iPhones at once and
again each time one is plugged in, unplugged, or the device service restarts.

**Why this priority**: everything else consumes this stream.

**Independent Test**: with a fake usbmux service, attaching and detaching a device produces new snapshots; stopping
the service produces a notice and an empty snapshot, and restarting it resumes.

**Acceptance Scenarios**:

1. **AC-017-1**: `dart_mobile_device` has a usbmuxd `Listen` client: it connects to `USBMUXD_SOCKET_ADDRESS`, else
   the host default (`127.0.0.1:27015` on Windows, `/var/run/usbmuxd` on Linux), sends the plist `Listen` request
   (16-byte header: length, version 1, message 8, tag), checks the `Result`, and turns `Attached`/`Detached`
   messages into events with the device id, UDID and connection type. A closed or refused connection ends the
   stream with an error the caller can retry on.
2. **AC-017-2**: `xcross devices --watch --json` prints one `{"v":1,"type":"devices","devices":[…]}` snapshot at
   start (each entry as in `devices --json`: `udid`, `name`, `osVersion`, `connection`), and another whenever the
   list changes: a detach removes the device at once; an attach re-reads names and iOS versions (bursts within
   300 ms are merged). USB devices only, as in `devices`.
3. **AC-017-3**: When the device service is unreachable or drops, the command prints a `notice` ("The device
   service is not reachable; retrying…") and an empty snapshot once, retries every 2 s, and prints a fresh snapshot
   when it is back. It runs until it is stopped (Ctrl+C or the parent closing it) and exits 0.
4. **AC-017-4**: Without `--json`, `--watch` prints readable lines: the initial list, then `+ <name> (iOS x)` and
   `- <name>` as devices come and go, and the service notices.

### User Story 2 - Live device badge in XCross Studio (Priority: P1)

The user plugs the iPhone in or out; within about two seconds the top bar's device badge, the Devices page and the
Build & Run device picker update, with no Refresh press.

**Independent Test**: a fake launcher streaming snapshots updates `DeviceController.devices` and the badge.

**Acceptance Scenarios**:

1. **AC-017-5**: `DeviceController.watch()` runs `xcross devices --watch --json` as a background job when the app
   starts, replaces the device list with each snapshot, keeps auto-selecting a single device, and restarts the
   watch (after 3 s) if the process ends while the app is open. Refresh still works.
2. **AC-017-6**: The top bar shows a live device badge: the selected iPhone's name with a green dot, "Plug in an
   iPhone" with a grey dot when none is connected, and "Device service not reachable" with a warning dot after a
   service notice.

### User Story 3 - Device evidence (Priority: P2)

1. **AC-017-7** (device, `device-check.md`): on Windows with the iPhone X, unplugging and plugging the cable updates
   the badge within about 2 s, and restarting the Apple Mobile Device Service shows the notice and then recovers.

### Edge Cases

- A device attached over the network (Wi-Fi sync) is ignored, as `devices` lists USB only.
- An attach whose listing fails (locked, untrusted) still appears with the UDID once the listing succeeds; until
  then the previous snapshot stands.
- Several quick plugs: snapshots are merged; the last state wins.
- The GUI closes: the watch process is killed with the app (job cancel on dispose).

## Requirements *(mandatory)*

- **FR-001**: The Listen client is pure Dart (no pymobiledevice3 process per event) and lives in
  `dart_mobile_device/lib/host/shared/usbmux_listen.dart`.
- **FR-002**: The host default address comes from the host policy (`DeviceHostPolicy.defaultUsbmuxAddress`), not from
  OS checks in shared code.
- **FR-003**: Snapshots never print anything beyond what `devices --json` already prints.
- **FR-004**: The GUI consumes only the CLI's events (Constitution IV).

## Success Criteria *(mandatory)*

- **SC-001**: Plugging or unplugging the iPhone updates XCross Studio within about 2 seconds, with no click.
- **SC-002**: A device service restart is recovered from without restarting the app.

## Assumptions

- Names and iOS versions are read with the existing listing (pymobiledevice3) after an attach; the usbmux messages
  carry only the UDID and connection type.
- Out of scope: Wi-Fi devices, macOS hosts' Apple service quirks (the protocol is the same).
