# Device check: 002 quick wins

Real-host and real-device evidence for the device-affecting ACs (constitution Principle VI).

- **Host**: Windows 11 (native), 2026-11-01
- **Device**: iPhone X (`iPhone10,6`) on iOS 16.7.16, over USB
- **pymobiledevice3**: 11.49.1 via `py -m pymobiledevice3`
- **xcross**: run with `dart run packages/xcross/bin/xcross.dart` in `examples/flutter_example`

Timings marked "net" subtract the `dart run` start-up, measured with `xcross --version`: about 9.6 s on this machine.
A compiled `xcross.exe` has no such overhead.

Linux rows are deferred, like feature 001's T045. No device name or UDID is recorded here.

| # | AC | Setup | Expected | Result |
|---|---|---|---|---|
| 1 | AC-002-3 | Apple Mobile Device Service running | probe of `127.0.0.1:27015` is reachable | ✅ reachable in 27 ms |
| 2 | AC-002-3 | nothing listening on the probed port | unreachable within the 2 s timeout | ✅ unreachable after 2015 ms (Windows retries refused localhost connects until the timeout) |
| 3 | AC-002-1 | iPhone X on iOS 16.7.16, `xcross flutter run --usb` | `error: [device.ios_unsupported] …` in < 5 s, before any build step | ✅ `error: [device.ios_unsupported] <device> runs iOS 16.7.16; xcross needs iOS 17 or later to install and launch.` plus the hint. No build step ran ("Finding devices 1.5–1.7 s" was the only step). Net precheck cost: median **1.4 s** over 3 warm runs. |
| 4 | AC-002-2 | `xcross flutter run -d NoSuchPhone` (selector matches no device) | `error: [device.not_found] …` before the build | ✅ `error: [device.not_found] No connected device matching "NoSuchPhone".` plus the hint. Unplugged-cable variant (phone dropped off USB during feature 010 testing): `error: [device.not_found] No devices connected…` before the build ✅. |
| 5 | AC-002-3 | `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27016` (closed port; same probe code path as a stopped service), `xcross flutter run --usb` | `error: [device.host_service_unavailable] …` with the Windows hint, before the build | ✅ exact contract text. Net about **3.9 s**, including the 2 s probe timeout. The real service was not stopped, because that needs an Administrator shell. |
| 6 | AC-002-3 | `xcross flutter doctor`, service reachable / overridden as in row 5 | "Device service" check is ✓ / ✗ with the code | ✅ `✓ Device service  Reachable`; with the override `✗ Device service  [device.host_service_unavailable] …` |
| 7 | AC-002-4 | supported (iOS 17+) device: precheck once, install and launch the same device | single device prompt, no re-resolution | ⏳ needs an iOS 17+ device; covered by unit tests (`run_precheck_order_test.dart`, `device_precheck_test.dart`) |
| 8 | all | Ubuntu 24.04 host, rows 1–6 | same results | ⏳ deferred (Linux verification deferred by the user) |

Observation (upstream, not changed here): doctor's existing "Device" check prints the device UDID next to its name.
Mask it before sharing doctor output.
