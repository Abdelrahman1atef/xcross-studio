# Feature Specification: Plugin overrides (your own Package.swift for a Flutter plugin)

**Feature Branch**: `006-plugin-overrides` | **Created**: 2026-11-01 | **Status**: MVP implemented

**Input**: ROADMAP 006, upstream #145: "Override `Package.swift` lookup, remote binary targets + resource bundles,
Google Maps, Pusher shim, `xcross plugin shim`". This MVP delivers the override mechanism. Remote binary targets,
the Google Maps / Pusher shims and `xcross plugin shim` are follow-ups.

## User Story 1 - Build a plugin that only ships a podspec (P1)

A Flutter developer depends on a plugin that only ships a CocoaPods podspec. Today xcross skips it with
`build.podspec_only_plugin`, and the app's calls to that plugin never return. They want to write (or download) a
`Package.swift` for the plugin, drop it in a folder, and have xcross build the plugin with it, without forking the
plugin or touching the pub cache.

**Independent Test**: add `xcross_overrides/<plugin>/Package.swift` to a project that uses a podspec-only plugin and
build. The plugin is compiled, and the build says which override it used.

**Acceptance Scenarios**:

1. **AC-006-1**: Lookup order. The first folder that applies wins:
   1. `<project>/xcross_overrides/<plugin>/<version>/`
   2. `<project>/xcross_overrides/<plugin>/`
   3. `~/.xcross/overrides/<plugin>/<version>/`
   4. `~/.xcross/overrides/<plugin>/`

   `<version>` is the `version:` in the plugin's `pubspec.yaml`.
2. **AC-006-2**: An any-version folder may hold an `override.yaml` with `versions: "<constraint>"`. The constraint
   uses pub syntax (`any`, `1.2.3`, `^1.2.3`, `>=1.2.0 <2.0.0`). A folder whose constraint excludes the plugin
   version, or whose version folders do not include it, is skipped with a warning, and the search goes on.
3. **AC-006-3**: For a podspec-only plugin, the override is laid over a staged copy of the plugin's `ios/` (or
   `darwin/`) folder, without the podspec. The result becomes the plugin's Swift package, so the override's targets
   can point at `Classes/…`. The plugin is then built like any Swift Package Manager plugin. Nothing is written into
   the pub cache.
4. **AC-006-4**: For a plugin that ships its own `Package.swift`, the override's files are laid over the plugin's own
   package and its `Package.swift` wins. This fixes broken manifests.
5. **AC-006-5**: A folder without `Package.swift`, or with an unreadable `override.yaml`, gives
   `build.plugin_override_invalid` and is not used. The plugin is then handled as before.
6. **AC-006-6**: The override's `platforms: [.iOS("x")]` floor counts when xcross picks the app's deployment target.
7. **AC-006-7**: Device evidence: a podspec-only plugin built with an override works on the iPhone (see
   `device-check.md`).

## User Story 2 - Get a starting Package.swift from the podspec (P2)

Writing a `Package.swift` by hand is the hard part of an override. `xcross plugin shim <plugin>` drafts one.

**Acceptance Scenarios**:

8. **AC-006-8**: The podspec's declarative statements are read: `name`, `version`, `source_files`,
   `public_header_files`, `dependency` (with requirement), `frameworks`/`libraries`, `ios.deployment_target` /
   `platform :ios`, `resource_bundles`. Comments and `osx.` lines are ignored.
9. **AC-006-9**: The draft has one target, or a Swift and an Objective-C target when the plugin mixes the two (SwiftPM
   can't mix them). Paths are relative to the staged `ios/` folder. `publicHeadersPath` comes from
   `public_header_files`. Known pods (GoogleMaps, Google-Maps-iOS-Utils, Firebase*, PusherSwift, Alamofire,
   SDWebImage, Kingfisher) become Swift package dependencies with mapped version requirements; unknown pods become
   TODO lines. The result has no trailing commas in argument lists, so older Swift toolchains accept it.
10. **AC-006-10**: `xcross plugin list` shows each iOS plugin as swiftpm / podspec only / override.
    `xcross plugin shim <plugin> [--global] [--force]` writes `xcross_overrides/<plugin>/<version>/Package.swift`
    (or `~/.xcross/overrides/…`), refuses to overwrite without `--force`, and prints the review notes. Errors:
    `plugin.not_found`, `plugin.no_podspec`, `plugin.no_project`, `plugin.override_exists`.
16. **AC-006-16**: A privacy manifest the podspec's `resource_bundles` names outside the target folder is copied byte
    for byte into that folder of the override and declared as a resource, because CocoaPods ships it from anywhere in
    the pod and a SwiftPM target only sees its own folder. A mixed plugin's Objective-C target declares it and its Swift
    target excludes it. Other resources outside the folder, and a manifest the plugin does not have, stay review notes.
    Existing drafts are left alone; `xcross plugin shim <plugin> --force` replaces one.

## Requirements

- **FR-001**: A used override is announced with `build.plugin_override_applied`, naming the folder.
- **FR-002**: Staging rewrites only changed files, so SwiftPM's incremental build stays warm, and removes files that
  are gone from the override.
- **FR-003**: The `build.podspec_only_plugin` hint names `xcross_overrides/<plugin>/Package.swift`.

## Codes

| Code | When | Hint |
|---|---|---|
| `build.plugin_override_applied` | a plugin is built with an override | Review the override when you upgrade the plugin; delete the folder to build the plugin's own package. |
| `build.plugin_override_invalid` | an override folder is skipped (no `Package.swift`, bad `override.yaml`, other versions) | An override folder needs a Package.swift; an override.yaml may only set versions: to a pub-style constraint such as ">=1.2.0 <2.0.0". |

## Assumptions and limits

- The staged package holds only the plugin's `ios/` (or `darwin/`) folder plus the override. Sources elsewhere in the
  plugin (for example `../shared`) must be copied into the override.
- Writing a correct `Package.swift` for a mixed Objective-C/Swift plugin is the user's job. `xcross plugin shim`
  (a podspec-to-manifest draft) is a follow-up.
