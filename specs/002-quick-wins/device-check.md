# Device check: 002 quick wins

Real-host and real-device evidence for the device-affecting ACs (constitution Principle VI). Host: Windows 11
(native), 2026-11-01. Linux rows are deferred, like feature 001's T045.

| # | AC | Setup | Expected | Result |
|---|---|---|---|---|
| 1 | AC-002-3 | Windows, Apple Mobile Device Service running | service probe of `127.0.0.1:27015` is reachable | ✅ reachable in 27 ms |
| 2 | AC-002-3 | Windows, nothing listening on the probed port | probe reports unreachable within the 2 s timeout | ✅ unreachable after 2015 ms (Windows retries refused localhost connects until the timeout) |
| 3 | AC-002-1 | iPhone X, iOS 16.7, USB, `xcross flutter run` | `error: [device.ios_unsupported] …` in < 5 s, before any build output | ⏳ open: `pymobiledevice3` is not installed natively on this Windows host |
| 4 | AC-002-2 | no device attached, `xcross flutter run` | `error: [device.not_found] …` before the build | ⏳ open: needs `pymobiledevice3` |
| 5 | AC-002-3 | Apple Mobile Device Service stopped, `xcross flutter run --usb` | `error: [device.host_service_unavailable] …` with the Windows hint | ⏳ open: needs `pymobiledevice3` and an admin shell to stop the service |
| 6 | AC-002-3 | same, `xcross flutter doctor` | failed "Device service" check | ⏳ open: doctor returns early while "Device tools" (`pymobiledevice3`) is missing |
| 7 | all | Ubuntu 24.04 host, same rows | same results | ⏳ deferred (Linux verification deferred by the user) |

To close rows 3–6: install `pymobiledevice3` natively, for example `py -m pip install -U pymobiledevice3` (the
`WindowsDeviceHost.installCommand`), then follow [quickstart.md](quickstart.md) §2.
