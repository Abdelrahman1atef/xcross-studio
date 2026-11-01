# Implementation Plan: Plugin overrides

**Branch**: `006-plugin-overrides` | **Date**: 2026-11-01 | **Spec**: [spec.md](spec.md)

## Summary

The narrowest seam is the plugin list itself. After `PluginDiscovery`, `_buildPlugins`
(`flutter_artifact_compiler.dart`) passes the plugins through `PluginOverrides.apply`. An overridden plugin is
**re-rooted**: it gets a new `IosPlugin` whose `packageRoot` is a staged copy under the SwiftPM workspace cache
(`<workspace>/overrides/<plugin>/`). That copy holds:

- `pubspec.yaml`, for the `pluginClass`;
- `<ios|darwin>/<plugin>/`: the plugin's own package directory (or, for a podspec-only plugin, its `ios/` folder
  without the podspec), with the override's files on top.

Everything downstream sees an ordinary SwiftPM plugin and is unchanged: `usesSwiftPackageManager`, the overlay
stager, the manifest compiler and the registrant. The SwiftPM rule that target paths stay inside the package root
holds because the sources are copied in. The deployment-target resolver uses the same locator, so an override's
platform floor counts.

New file: `packages/xcross/lib/src/shared/flutter/build/plugin_overrides.dart`. It lives next to `ios_plugins.dart`
as an upstream-PR candidate (#145), like feature 003. It holds:

- `PluginOverrideLocator`: the search order and `override.yaml`.
- `PluginOverrides`: apply, materialize, and a content-compared sync.
- `OverrideVersion` / `OverrideVersionConstraint`: small pub-style semver ranges, with no new dependency.

## Technical Context

**Language/Version**: Dart `^3.10`

**Primary Dependencies**: existing `yaml`, `path`, `cli_kit` (`HostFileSystemInterface`). No new dependency.

**Testing**: `test/flutter/build/plugin_overrides_test.dart` (real temp directories, dart:io-backed host file system).

**Constraints**:

- The pub cache is never written.
- Unchanged files keep their timestamps (SwiftPM incremental builds).
- No Apple material is involved.

## Constitution Check

| Principle | Status | Note |
|---|---|---|
| I | ⚠ justified | upstream PR candidate (#145); one new file plus marked hunks in `flutter_artifact_compiler.dart`, `ios_deployment_target_resolver.dart`, `flutter_build_runtime.dart`, `xcross_diagnostics.dart` |
| II | ✅ | user-supplied files only |
| III | ✅ | invalid or mismatching folders warn with a code and hint; never silent |
| IV, V | ✅ | pure Dart, both hosts |
| VI | ✅ | AC → tests below; device rows |

## AC → tests

| AC | Test |
|---|---|
| AC-006-1 | `AC-006-1 lookup order` (2 tests) |
| AC-006-2 | `AC-006-2 versions` (3 tests) |
| AC-006-3 | `AC-006-3 podspec-only plugin + override` (2 tests) |
| AC-006-4 | `AC-006-4 the override wins over a shipped Package.swift` |
| AC-006-5 | `AC-006-5 an invalid override warns and leaves the plugin as it was` |
| AC-006-6 | `AC-006-6 the override Package.swift sets the deployment floor` |
| AC-006-7 | `device-check.md` |
