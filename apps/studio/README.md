# XCross Studio (desktop app)

A Flutter desktop GUI for Windows and Linux over the `xcross` CLI of this repository: build, sign, install and debug
Flutter iOS apps without a Mac. The app holds no build logic; every button runs an `xcross` command and shows its
output (see [specs/008-json-events-gui](../../specs/008-json-events-gui/spec.md)).

## Run

```sh
flutter run -d windows   # or: flutter run -d linux
flutter build windows    # build/windows/x64/runner/Release/xcross_studio.exe
```

In **Setup**, choose **Run from source** and pick the repository folder (runs `dart run
packages/xcross/bin/xcross.dart`), or point it at a compiled `xcross` executable.

## Layout

- `lib/src/cli`: how xcross is started, the command lines, NDJSON events, output-line classification, the process launcher
- `lib/src/host`: the Windows/Linux differences (kill tree, open folder, settings folder)
- `lib/src/state`: jobs, the device-log session, settings, the project summary
- `lib/src/ui`: Setup, Project & Build, Device & Install, Device logs, Console

## Test

```sh
flutter analyze
flutter test
```

XCross Studio is AGPL-3.0 and is not affiliated with Apple.
