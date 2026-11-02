# Feature Specification: A Flutter SDK with an iOS compiler for this computer, set up for the user

**Feature Branch**: `014-flutter-sdk-compat` | **Created**: 2026-11-02 | **Status**: Implemented (device rows open)

**Input**: the user, after an iPhone X release build failed with "No prebuilt iOS AOT compiler (gen_snapshot) is
available for Flutter 3.47.8": "i want in app this woring this not visable to users and don't now why the error
happen". Release/profile iOS builds need Flutter's iOS AOT compiler, which Flutter publishes for macOS only.
xcross downloads Windows/Linux builds from `arxdeus/xcross_gen_snapshot`, which lags behind Flutter (newest 3.47.6
when the user had 3.47.8). In WSL the user fixed it by hand: a second Flutter in `roots.flutterSdk` +
`tools.flutter`. XCross Studio must do that by itself and say why in plain words.

## User Story 1 - The error explains itself and fixes itself (P1)

A developer whose Flutter is newer than the published compilers presses Build. Instead of a raw compiler error,
they see what is wrong, which Flutter is needed, and one button that sets it up. After that they build again.

**Acceptance Scenarios**:

1. **AC-014-1**: The version to use is the newest one with a published release compiler for this host in the same
   major.minor line (3.47.8 → 3.47.6). If there is none, the newest stable version overall is used and the CLI says
   so. If the active Flutter has a compiler (published, cached or pinned), nothing changes.
2. **AC-014-2**: The list of versions with a compiler comes from the GitHub releases of
   `arxdeus/xcross_gen_snapshot`, filtered by `gen_snapshot-release-<host>.zip`. It is cached for 6 hours in
   `<cache>/xcross/gen-snapshot/catalog.json`, and an older cache is used when offline.
3. **AC-014-3**: `xcross flutter sdk install <version>` clones `flutter/flutter` at that tag (depth 1) into
   `<config>/xcross/flutter-sdks/<version>` through a `.partial` folder, then runs `flutter --version` once to
   download its Dart SDK. A retry cleans leftovers. Failures are `toolchain.flutter_sdk_install_failed`; a version
   without a compiler is refused (`toolchain.flutter_sdk_version_unavailable`) unless `--force`; a missing Git is
   `toolchain.git_missing`. Only plain `x.y.z` versions are accepted.
4. **AC-014-4**: `xcross flutter sdk use <version|path>` writes `roots.flutterSdk` and `tools.flutter` into the
   xcross config and keeps every other key. `reset` removes them, and deletes the file when nothing else remains, so
   xcross goes back to the Flutter on PATH. The user's own Flutter is never modified.
5. **AC-014-5**: `xcross flutter sdk list [--json] [--refresh]` shows the Flutter used for iOS builds, whether it
   has a compiler, the versions xcross installed, the versions with a compiler, and the suggestion. `auto [--yes]`
   does check → choose → install (asking first on a terminal; `--yes` without one) → use, and prints one plain
   paragraph explaining why. All of these report `step`/`log`/`error`/`done` events under `XCROSS_EVENTS=ndjson`.
6. **AC-014-6**: A release/profile build without a compiler fails with `[build.gen_snapshot_unavailable]`, naming
   the active and suggested versions, with the hint `xcross flutter sdk auto` (the config-pin option stays).
   `xcross flutter doctor` shows "AOT compiler (release)" as ✗ (profile ⚠) with the same suggestion, also outside a
   project.
7. **AC-014-7**: The desktop app turns that error (from the event or the printed line) or the doctor check into a
   plain card: "Your Flutter (3.47.8) is newer than the iOS compiler XCross Studio can use on Windows. iPhone
   release builds need Flutter 3.47.6 …"
8. **AC-014-8**: Build & Run shows the card instead of the generic one. "Set up Flutter 3.47.6 for iPhone builds"
   runs `xcross flutter sdk auto --yes` with progress. On success, "Build again" reruns the same command. "Show
   details" reveals the CLI text and "Copy command" copies the fix command.
9. **AC-014-9**: Overview readiness has an "iOS release compiler" card, and the status bar's Toolchain includes it.
   The wizard's Environment step offers the same fix.
10. **AC-014-10**: Settings → "Flutter for iOS builds" shows which Flutter iPhone builds use (installed by XCross
    Studio, or the user's own) with "Use my own Flutter" (`sdk reset`) and the fix when needed.
11. **AC-014-11** (device): on the Windows PC with Flutter 3.47.8, the button installs 3.47.6, and a release build
    and run on the iPhone X then succeed.

## Out of scope

Per-project SDK selection (xcross has no project config file; `use --project` is not offered), deleting installed
SDKs (remove the folder by hand), and building a compiler for unpublished Flutter versions.
