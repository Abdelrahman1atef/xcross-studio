# Implementation Plan: Plugin drafts during the build, a check before compiling

**Spec**: [spec.md](spec.md)

## Technical Context

Dart monorepo. `packages/studio_ext` owns the podspec parser and `Package.swift` drafting (`xcross plugin shim`).
`packages/xcross` owns the build. `packages/cli_kit` owns the process runner. **Testing**: `dart test`, `flutter test`.

## Constitution Check

CLI first; the desktop app only updates a tooltip. Nothing new leaves the machine. Writing into a project is limited to
`xcross_overrides/`, which exists to hold these files, and each write is reported by a warning.

## Design

- **Drafts**: `PluginDraftWriter` is lifted out of `PluginShimCommand` so a build writes the same files. It is used by
  `PluginAutoDraft`, which `FlutterArtifactCompiler.compile` calls first, so warnings come before any compiling. Overrides
  then apply as they always have, so a draft takes the path a hand-made one takes.
- **Check**: `PluginCheckCommand` uses the same writer to find unknown pods, and writes nothing.
- **Stuck builds**: `ErrorStallWatchdog` arms on the first `error:` in the output and fires after silence. `runChecked`
  gets `stallAfterError`, used by `WindowsSwiftPmBuildExecution`. The tree kill reaches compilers while `swift build` is
  alive; output is no longer awaited forever after it exits. The ending message avoids the words that mark a timeout, so
  a module cache race that stalled is still retried.
- **Distribution**: `FlutterBuildOptions.forDistribution` flows to `SwiftPmBuildPlan.swiftBuildArguments`. The flags come
  after SwiftPM's own, and for `-D`/`-U` the last one counts. `SwiftPmWorkspace` gets a `-distribution` suffix.
- **Registration**: the generic runner and `XcrossRunnerSupport.m` start the engine during launch. It is Flutter's
  documented order for an engine made ahead of its view controller: run, register, then `initWithEngine:`.

## Risks

- The engine now starts before `super.application(_:didFinishLaunchingWithOptions:)` in every generic-runner app. Needs
  the device check; the desktop app is packaged with it, so a failure there is visible at once.
- A distribution build cannot be run on a device (an App Store profile does not install). It is compile-checked through
  `XCROSS_PLUGIN_BUILD=distribution`, and the push itself needs a TestFlight install.
