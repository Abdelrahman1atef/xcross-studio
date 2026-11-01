# Feature Specification: Compile the project's own Runner code (AppDelegate)

**Feature Branch**: `007-native-runner-code` | **Created**: 2026-11-01 | **Status**: Implemented (opt-in; device check pending)

**Input**: ROADMAP 007: "Compile project `ios/Runner/*.swift|*.m` (AppDelegate) with `--runner=shim` fallback"; upstream
#149 (AppDelegate note). xcross links a generic runner as the app's `Runner` executable, so code in the project's
`AppDelegate.swift` never runs: custom method channels, push setup, the `UNUserNotificationCenter` delegate,
`GMSServices.provideAPIKey`, and so on.

## User Story 1 - My AppDelegate code runs (P1)

A Flutter developer whose `ios/Runner/AppDelegate.swift` registers a method channel (or configures push or Maps) builds
with `XCROSS_RUNNER=project`. The app runs that code. If it does not compile, the build still succeeds with the generic
runner and says why.

**Independent Test**: set `XCROSS_RUNNER=project` and run `xcross flutter run --release` on a project whose AppDelegate
registers a channel; calling the channel from Dart returns the native value.

**Acceptance Scenarios**:

1. **AC-007-1**: **Given** `XCROSS_RUNNER` is unset (or not `project`), **When** I build, **Then** the generic runner
   is used exactly as before, and nothing new runs or prints.
2. **AC-007-2**: **Given** `XCROSS_RUNNER=project`, **When** I build, **Then** the sources come from the app target's
   Sources build phase in `project.pbxproj` (plus Xcode 16 synchronized folders), or from every `.swift`/`.m`/`.mm` in
   `ios/Runner` when there is no usable project file. `GeneratedPluginRegistrant.m` is left out. The bridging header
   comes from `SWIFT_OBJC_BRIDGING_HEADER` (default `Runner/Runner-Bridging-Header.h`), and the module name from the
   target name.
3. **AC-007-3**: Objective-C sources are compiled with the Darwin clang. With Swift sources, `swiftc` compiles them and
   links the `Runner`. That link uses the Darwin SDK, its Swift resources, ld64.lld, Flutter.framework, the plugins
   library and its Swift modules (so `import <plugin>` works), native-asset frameworks and
   `@executable_path/Frameworks`. An Objective-C-only Runner is linked with ld64.lld, like the shim.
4. **AC-007-4**: xcross adds two things.
   - Its own `GeneratedPluginRegistrant`, which forwards to the plugins library's registrant, so
     `GeneratedPluginRegistrant.register(with:)` keeps working.
   - `XcrossSceneDelegate`, which creates the Flutter window (the template takes it from `Main.storyboard`, which
     cannot be compiled without Xcode). Info.plist names `XcrossSceneDelegate` for project runners only.
5. **AC-007-5**: **Given** the sources do not compile (or there are none), **When** I build, **Then** a
   `build.runner_project_failed` warning lists the compiler's first errors with a hint, and the generic runner is used.
   The build never fails because of this feature.
6. **AC-007-6**: Two warnings, neither of which stops the build:
   - `build.runner_legacy_registration` when the app delegate registers plugins with `self` at launch (pre-UIScene
     template). xcross then registers them on the scene's engine instead.
   - `build.runner_scene_delegate_replaced` when the project's `SceneDelegate` has code, which does not run.
7. **AC-007-7**: On the iPhone X (iOS 16.7.16), an app whose AppDelegate registers a method channel answers it
   (`device-check.md`).

## Requirements

- **FR-001**: Opt-in through `XCROSS_RUNNER=project`. The default stays the generic runner. A `--runner` flag would
  require regenerating the build_cli parsers of `flutter build` and `flutter run`, so it is deferred.
- **FR-002**: No failure of the project runner may fail the build.
- **FR-003**: Coded warnings (`build.runner_*`) with hints, never silent skips.

## Out of scope

`--runner=project|shim` flags; running the project's own `SceneDelegate`; Objective-C `@import` (clang modules) in
project `.m` files; extra Runner frameworks or linker flags from the Xcode project (`OTHER_LDFLAGS`); app-extension
changes.
