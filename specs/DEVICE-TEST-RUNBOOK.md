# Device test runbook: iPhone X (iOS 16.7.16), Windows host

One pass over every open device row (features 003, 004, 005, 006, 007, 008, 010, 011). Record each result in the
feature's own `device-check.md` (✅ / ❌ plus a short note). Never paste UDIDs, device names or client bundle ids into
committed files.

## 0. Prepare

1. Use **this fork's** CLI. The `xcross` on PATH is upstream 2.0.9 and lacks the new commands.

   ```powershell
   cd D:\Programing\xcross-studio\apps\studio
   dart run tool/package.dart            # rebuilds CLI + GUI into ..\..\dist (about 5 min)
   $X = "D:\Programing\xcross-studio\dist\xcross-studio-windows-x64\xcross\bin\xcross.exe"
   & $X --help                           # lists devices, install, logs, app, crashes, inspect
   ```

   No rebuild? Use `dart run D:\Programing\xcross-studio\packages\xcross\bin\xcross.dart` in place of `& $X`.
2. Connect the iPhone by USB, unlock it, tap **Trust**. Check with `& $X devices`, which should show
   `iPhone … iOS 16.7.16 …`.
3. Run `& $X flutter doctor` (there is no top-level `xcross doctor`). On 2026-11-01 this PC reported:
   device service ✓ and Python tools ✓, but **no Swift toolchain, no clang/LLVM, no Darwin SDK and no sign-in**.
   Nothing can be built until step 4 is done. Rows that need no build can run first: 010, plus `install` / `sign` /
   `app info` / `logs` on an existing `.ipa`.
4. **One-time toolchain setup** (needed for every build row; allow 30–60 min, mostly the SDK extraction):

   ```powershell
   & $X setup                         # installs Swift, LLVM, Python via winget (asks before each installer)
   # open a NEW terminal so PATH picks up Swift and LLVM, set $X again, then:
   & $X sdk install "$env:USERPROFILE\Downloads\Xcode_27.1.xip"   # once; builds the Darwin SDK
   & $X auth                          # Apple ID + password; type the 2FA code
   & $X flutter doctor                # every iOS toolchain line should now be ✓
   ```

5. Pick a Flutter test project (`$P`) and, if available, an `.ipa` from another source (`$IPA`).

## 1. Feature 010: device logs (rows 6–9)

| Row | Command | Expect |
|---|---|---|
| 6 | `& $X logs --app <bundle-id>`, then open, close and reopen the app | app lines, continuing after the relaunch |
| 7 | `& $X logs --process SpringBoard --level notice --grep . --save sb.txt --duration 5` | filtered lines; `sb.txt` matches the screen |
| 8 | `& $X crashes list`, then `& $X crashes pull --latest` | newest first; report saved with a summary |
| 9 | `& $X logs --app <flutter app id> --preset flutter` (release build prints `print()` output too) | Dart output only |

## 2. Feature 005: iOS 16 run and `xcross install`

| Row | Command (in `$P`) | Expect |
|---|---|---|
| 1 | `& $X flutter run` (debug) | `error: [device.legacy_debug_unsupported]` before any build step |
| 2 | `& $X flutter run --release` | built, signed, installed; "Tap the app icon…"; the app opens from its icon |
| 3 | same, with a DeviceSupport `16.x` folder from your own Xcode in `~/.xcross/DeviceSupport/` | image mounted, app opens by itself (skip if you have no such folder) |
| 4 | `& $X install $IPA` | re-signed, installed, guidance printed |
| 5 | `& $X install notes.txt` | `error: [install.unsupported_input]` |
| 6 (011) | `& $X sign $IPA`, then `& $X install --no-resign <name>-signed.ipa`, then `& $X app info <bundle-id>` | `✔ Signed` summary (team, development profile, expiry); installs without re-signing; signer development. Rows: `specs/011-sign-ipa/device-check.md` |

## 3. Feature 003: entitlements

Needs `ios/Runner/Runner.entitlements` with `aps-environment`. Push needs a **paid** team; a free team gets Apple's
capability error, which is itself a valid result to record.

| Row | Command | Expect |
|---|---|---|
| 1 | `& $X flutter build --release --ipa`, then `& $X inspect build\xcross-ios\<name>.ipa --json` | `XCrossEntitlements: true` under `xcrossPrivateKeys` |
| 2 | `& $X flutter run --release`, then `& $X app info <bundle-id>` | `✔ push entitlement` |
| 3 | same, with associated domains declared | `✔ associated domains` |
| 4 | break the XML in `Runner.entitlements`, build | `warning: [build.entitlements_unreadable]`; the build continues |
| 5 | `& $X logs --app <bundle-id> --preset push`, then send a test push | diagnosis: registered / delivered |

## 4. Feature 004: icon and launch screen

| Row | Step | Expect |
|---|---|---|
| 1 | `& $X flutter run --release` | no `build.asset_catalog_skipped`; the app icon shows on the home screen |
| 2 | `& $X inspect build\xcross-ios\<name>.app` (or the IPA) | `Assets.car` present, `CFBundleIcons`, launch screen image from the asset catalog |
| 3 | delete the app, **reboot the phone**, install again, open | splash shows the storyboard background colour (and image, if the project has a real `LaunchImage`) |
| 4 | a project with `flutter_native_splash` | its colour and centred logo |

Details: `specs/004-icon-launch-screen/device-check.md`.

## 4b. Feature 007: the project's own AppDelegate (opt-in)

Use a project whose `ios/Runner/AppDelegate.swift` does something visible, such as registering a method channel.
Run `$env:XCROSS_RUNNER = "project"; & $X flutter run --release`, then `Remove-Item Env:XCROSS_RUNNER`.
Expect no `build.runner_project_failed`; the app starts and the channel answers. Without the variable, the default
runner is unchanged. Rows: `specs/007-native-runner-code/device-check.md`.

## 5. Feature 008: the desktop app

Run `D:\Programing\xcross-studio\dist\xcross-studio-windows-x64\xcross_studio.exe`; it uses the bundled `xcross`
automatically. Click through rows 1–13 of `specs/008-json-events-gui/device-check.md`: doctor, device list, build, run,
install, live logs with filters, app info badges, push checklist, crashes, Stop, sign-in.

## 6. Feature 006: plugin overrides

A project with a podspec-only plugin (today: `warning: [build.podspec_only_plugin]`). In `$P` run `& $X plugin list`,
then `& $X plugin shim <plugin>`, review the drafted `xcross_overrides/<plugin>/<version>/Package.swift`, then
`& $X flutter run --release`. Expect `[build.plugin_override_applied]`, a successful build, and the plugin working on
the phone. Rows: `specs/006-plugin-overrides/device-check.md`.

## If something fails

Run with `-v` where supported, save the output, and record the stable error code (`[device.*]`, `[build.*]`,
`[install.*]`). For build output, attach `& $X inspect <ipa> --json --normalize`.
