# Device check: 011 `xcross sign` (Windows host, iPhone X iOS 16.7.16)

Prerequisites: `xcross auth` done. Use this fork's CLI (`$X`, see `specs/DEVICE-TEST-RUNBOOK.md`). No device ids,
names or client bundle ids are recorded here.

| # | AC | Command | Expected | Result |
|---|---|---|---|---|
| 1 | AC-011-1, 2, 4 | phone connected: `& $X sign <app>.ipa` | "Including 1 device"; `✔ Signed: <app>-signed.ipa` with team, development profile, expiry | ⏳ |
| 2 | AC-011-4 | `& $X inspect <app>-signed.ipa` | signature: certificate; profile: development; entitlements listed | ⏳ |
| 3 | AC-011-6, 9 | `& $X install --no-resign <app>-signed.ipa` | installed without signing; opens from its icon | ⏳ |
| 4 | AC-011-9 | `& $X app info <bundle-id>` | `signer: development · team …` | ⏳ |
| 5 | AC-011-2 | phone unplugged: `& $X sign <app>.ipa --no-usb -o b.ipa` | "No device given…"; signed for the team's devices (the iPhone X is already registered) | ⏳ |
| 6 | AC-011-9 | install `<app>-signed.ipa` with another tool (e.g. Sideloadly "install without signing", if available) | installs and opens | ⏳ (optional) |
| 7 | AC-011-5 | `& $X sign <third-party>.ipa --bundle-id com.<you>.test` | signed under the new id | ⏳ |
| — | Linux | rows 1–5 on Ubuntu 24.04 | | ⏳ deferred |
