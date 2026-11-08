# Feature Specification: `xcross ios prepare` — a fresh iOS project without a Mac

**Feature Branch**: `032-ios-prepare` (work lands on `codex/029-xcode-ide-workspace`) | **Created**: 2026-11-08 | **Status**: Implemented, not yet run on a real fresh app

**Input**: On a Mac, a new Flutter app has to be opened or `pod install`ed once before it builds. The developer asked for the
same "make the project ready" step without a Mac. xcross already needs no CocoaPods: plugins are built as Swift packages,
and `Podfile`, `Pods/`, `Podfile.lock`, `Runner.xcworkspace` and `Generated.xcconfig` are optional. What was missing is one
step that gets a fresh project to the point where a build works, and says up front what a build would leave out (before a
multi-minute build), instead of finding out late.

## Scope

- `xcross ios prepare [--project <dir>] [--no-pub] [--strict] [--json]`:
  1. checks that `ios/` has a Runner project (otherwise: `flutter create --platforms=ios .`);
  2. runs `flutter pub get` (skipped with `--no-pub`), which writes `.flutter-plugins-dependencies`, the list of plugins
     a build reads. A missing list is a blocker (a build treats it as "no plugins" without saying so);
  3. classifies every iOS plugin as a build does (Swift package, draft or your override, no iOS code) and writes a draft
     `xcross_overrides/<plugin>/<version>/Package.swift` for each podspec-only plugin whose pods are known (what a build
     does first anyway);
  4. names each plugin whose native code a build would leave out (a pod with no known Swift package, or drafts switched off
     with `XCROSS_PLUGIN_DRAFTS=off`);
  5. reads the bundle ID and deployment target from the project file and the `PERMISSION_*` switches from `Info.plist` and
     the Podfile.
- Exit code is non-zero only for a blocker; `--strict` also fails when a plugin would be left out.
- `xcross doctor` has an "iOS project" check with the same two blockers.
- Studio: Project → Plugins has a "Prepare iOS project" button that runs the command and shows the steps and the plugins
  left out.

## Not in scope

- Resolving a pod that has no known Swift package from CocoaPods' own data (spec 025 keeps this out of scope), vendored
  frameworks in podspecs, and Podfile `pod` lines or `post_install` hooks: the command reports these cases, it cannot make
  them compile.
- Warming the plugin build cache (`swift build`) ahead of time.

## Acceptance Scenarios

1. **AC-032-1** A fresh app (an `ios/` Runner project, no Podfile, Pods or workspace) is ready, with its bundle ID, deployment
   target and permission switches read; nothing a Mac writes is created.
2. **AC-032-2** No `ios/` folder fails and names `flutter create --platforms=ios .`.
3. **AC-032-3** `flutter pub get` runs first. A run that leaves no plugin list is a blocker; a failed run with a list from
   before is a warning; with `--no-pub` and no list it is a blocker.
4. **AC-032-4** A podspec-only plugin is drafted before the build; running again does not write it twice and asks for the
   review the draft needs (feature 028) without blocking.
5. **AC-032-5** A plugin with an unknown pod is named as left out, does not block, and does with `--strict`.
6. **AC-032-6** With drafts switched off a podspec-only plugin is named as left out.
7. **AC-032-7** `--json` prints one `ios_prepare` line; `--no-pub` does not run pub get.
8. **AC-032-8** The Studio button runs `ios prepare --json --project <open project>`; nothing runs by itself.
9. **AC-032-9** Plugins left out are named in a warning with the reason.
10. **AC-032-10** A project that cannot be prepared says so with the diagnostics.
11. **AC-032-11** Studio reads the `ios_prepare` line and builds the command.
12. **AC-032-12** `xcross doctor` reports "iOS project": a warning for no `ios/` or no plugin list, a success otherwise.

## Tests

`packages/studio_ext/test/shared/ios/ios_prepare_test.dart` (AC-032-1 to 7),
`packages/xcross/test/cli/doctor_command_test.dart` (AC-032-12) and
`apps/studio/test/ui/ios_prepare_test.dart` (AC-032-8 to 11).

## Not checked

Run on a scripted file system only. Still to do on Windows: `xcross ios prepare` on a new `flutter create` app and on a real
app with podspec-only plugins, then a release build from the prepared project; record the outcome here.
