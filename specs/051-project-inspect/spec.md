# 051 Project inspect: the iOS setup in one report

## Why
Before an App Store upload, a Flutter project's iOS settings live in many files: the Xcode project (bundle ID per configuration, team, signing style, minimum iOS), Info.plist, the Podfile, pubspec.yaml (version), the entitlements (push), and three Firebase files that must name the same iOS app (`GoogleService-Info.plist`, `lib/firebase_options.dart`, `firebase.json`). A mismatch is found late: on a Mac, at upload, or when push or Firebase quietly fails on the phone. Desktop front-ends need one machine-readable report, and fixes that change every file at once.

## Commands
- `xcross project inspect [--json]`: reads the project, never writes. Emits `project_inspect` with groups of items (`id`, `label`, `value`, `status` ok|info|warning|error, `message`, `path`, `secret`, `code`), plus `bundleId`, `teamId`, `version`, `build`, `errors`, `warnings`.
- `xcross project set-bundle-id <id> [--dry-run] [--json]`: sets the app target's bundle ID in every configuration, moves targets that sat under the old ID (tests, extensions) under the new one, and replaces a hard-coded Info.plist `CFBundleIdentifier` with `$(PRODUCT_BUNDLE_IDENTIFIER)`. Firebase files are not changed. Emits `project_bundle_id_change`.
- `xcross project firebase-import <plist> [--dry-run] [--json]`: puts a GoogleService-Info.plist in `ios/Runner` and points the `ios` options of `firebase_options.dart` and the iOS app IDs in `firebase.json` at the same Firebase app. It refuses a plist for another bundle ID or another Firebase project. Emits `project_firebase_import`.

Every rewrite keeps formatting and line endings and changes only the values it names.

## Problem codes
`project.no_ios_app`, `bundle_id.missing`, `bundle_id.configs_differ`, `bundle_id.variable`, `bundle_id.target_outside`, `bundle_id.info_plist`, `team.configs_differ`, `deployment_target.podfile_higher`, `version.info_plist_fixed`, `push.no_entitlement`, `push.entitlements_not_linked`, `firebase.no_plist`, `firebase.bundle_mismatch`, `firebase.app_mismatch`, `firebase.project_mismatch`, `firebase.api_key_mismatch`, `keys.empty`.

## Acceptance
- **AC-051-1** `inspect` reports the bundle ID, team, signing style, minimum iOS (app target, else project, with the Podfile), version and build, push and Firebase values, each with the file it came from.
- **AC-051-2** It flags as errors: configurations with different bundle IDs, an extension outside the app ID, a Podfile higher than the app's minimum iOS, a missing push entitlement when the app uses push, and Firebase files for another bundle ID, app or project.
- **AC-051-3** Other keys (the Google Maps key in AppDelegate.swift; Info.plist `…AppID`, `…ApiKey`, `…ClientToken`, `…Secret`) are listed; keys and tokens are marked `secret`; empty ones warn.
- **AC-051-4** `set-bundle-id` changes every app configuration and the targets under the old ID and nothing else; `--dry-run` writes nothing; an invalid ID is refused.
- **AC-051-5** `firebase-import` leaves the three Firebase files naming one iOS app; Android values are untouched; a plist for another bundle ID or project is refused and nothing is written.

Tests: `packages/xcross/test/flutter/project/project_inspection_test.dart`.
