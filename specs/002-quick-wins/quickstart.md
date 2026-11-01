# Quickstart: validate 002 quick wins

Contract: [contracts/diagnostics.md](contracts/diagnostics.md). Model: [data-model.md](data-model.md).

## Prerequisites

- Dart 3.13.x; run `dart pub get` from the repo root.
- For the device checks: an iPhone, `pymobiledevice3` on PATH, and the host device service (Windows: Apple Mobile
  Device Service; Linux: usbmuxd).

## 1. Automated checks

```bash
dart analyze --fatal-warnings
cd packages/dart_mobile_device && dart test
cd packages/xcross && dart test --name "AC-002-"
cd packages/xcross && dart test   # full suite; on Windows one clang-dependent test needs clang on PATH
```

## 2. Fail fast (AC-002-1…4)

| Setup | Command | Expected |
|---|---|---|
| iOS 16 iPhone attached | `xcross flutter run` in any Flutter project | `error: [device.ios_unsupported] …` within 5 s, before any build output |
| No device | same command | `error: [device.not_found] …` |
| Windows: `Stop-Service "Apple Mobile Device Service"` (admin); Linux: `sudo systemctl stop usbmuxd` | `xcross flutter run --usb` | `error: [device.host_service_unavailable] …` |
| Same, service stopped | `xcross flutter doctor` | a failed "Device service" check |

Restart the service afterwards.

## 3. Versions (AC-002-5…8)

1. In a Flutter project, set `version: 1.0.7+7` in `pubspec.yaml`.
2. Edit `ios/Flutter/Generated.xcconfig` to `FLUTTER_BUILD_NAME=1.0.6`, `FLUTTER_BUILD_NUMBER=6`.
3. Run `xcross flutter build --release --ipa`.

Expected: the log shows `Version 1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml`, and
`xcross inspect build/xcross-ios/<name>.ipa --json` reports `shortVersion` 1.0.7 and `buildNumber` 7. With
`--build-name 2.0.0 --build-number 42`: 2.0.0 (42).

## 4. PATH guard (AC-002-9…11)

1. Add a directory whose `ld64.lld` cannot link iOS (for example the Swift toolchain `bin`) to `environment.PATH`
   with `xcross config`.
2. Run `xcross flutter doctor`: expect warning `[toolchain.path_linker_unusable]` naming the directory.
3. Build a project with native assets: expect the same warning once, and a successful link.

## 5. Loud warnings (AC-002-12…15)

Build a project that has a podspec-only plugin, `ios/Runner/Assets.xcassets` and `Base.lproj/LaunchScreen.storyboard`.
Expect:
- one `[build.podspec_only_plugin]` warning
- one `[build.asset_catalog_skipped]` warning
- one `[build.storyboard_skipped]` warning per storyboard
- the final `Build finished with N warnings: …` line
- exit code 0
