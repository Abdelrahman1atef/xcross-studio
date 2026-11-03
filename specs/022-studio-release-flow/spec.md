# Feature Specification: XCross Studio release flow

**Feature Branch**: `022-studio-release-flow` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 022 (US-IOS-001 AC-08 quality gate, AC-10 archives,
§11 release evidence, §12 CI). Features 016–021 give the CLI every release step; the desktop app has none of them. A
**Release** destination walks the story in order, an **Archives** page replaces Xcode's Organizer list, and two CLI
commands the app needs (`release gate`, `release ci`) keep the GUI a thin shell (Constitution IV).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Release in order from the desktop app (Priority: P1)

**Acceptance Scenarios**:

1. **AC-022-1**: A **Release** destination shows ten numbered steps with a status each: 1 readiness (doctor areas,
   push), 2 version and build (project version; "Use the next App Store Connect build number" → `--build-number
   auto`), 3 signing (team key needed for the App Store; link to Signing), 4 quality gate, 5 archive and IPA, 6
   release check, 7 upload, 8 processing, 9 TestFlight, 10 submission. Every step runs an `xcross` command and shows
   its job; nothing is done in the GUI itself.
2. **AC-022-2**: Step 5 runs `xcross flutter build --release --ipa --export-method app-store [--build-number auto]`
   (structured events) and shows the IPA and archive it reports. Step 6 runs `xcross release check --json` and lists
   the configuration and the issues, errors first, with their hints. Step 7 runs `xcross publish --wait --json` and
   shows part progress, upload and processing states and Apple's issues. Step 8 refreshes with `xcross testflight
   status --json`.
3. **AC-022-3**: Step 9 lists the builds (`testflight status --json`) and offers "Add to group" (`testflight add
   --group <name>`) and "What to Test" (`testflight what-to-test`); step 10 shows `appstore status --json`, a "Check
   (dry run)" (`appstore submit --dry-run`) and "Submit for review" behind a confirmation (`appstore submit`).
4. **AC-022-4**: A release record card shows `build/xcross-ios/release.json` (version, build, upload, processing,
   commit) with "Copy" and "Open folder".

### User Story 2 - Quality gate and CI from the CLI (Priority: P1)

1. **AC-022-5**: `xcross release gate [--json] [--skip-tests] [--fatal-infos]` runs `flutter analyze` and
   `flutter test` (the Flutter xcross builds with) in the project and reports each as passed/failed with the last
   lines of its output (without the package resolution `flutter analyze` prints first); exit 1 when one fails.
   Analyzer errors and warnings fail the gate; infos (a deprecation, a style lint) are listed but only fail it with
   `--fatal-infos` (`flutter analyze --no-fatal-infos` by default). The analyze step lists each issue it parsed.
   JSON: `{"v":1,"type":"release_gate","steps":[{"name","passed","exitCode","tail"}]}`; the analyze step adds
   `"issues":[{"severity","message","file","line","column","code"}]` and `"errors"`, `"warnings"`, `"infos"`.
   The Release page's step 4 runs it and shows a step that passed with issues as a warning with the issues listed.
2. **AC-022-6**: `xcross release ci [--output <path>] [--force]` writes a GitHub Actions workflow (default
   `.github/workflows/xcross-testflight.yml`) that runs the whole release on `ubuntu-latest` with the same secrets as
   the reference Mac workflow plus `XCODE_XIP_URL`; it refuses to overwrite without `--force`. The same file is in
   the repo as `docs/ci/github-testflight.yml`. The Release page has "Create CI workflow".

### User Story 4 - Change the version quickly (Priority: P1)

Added 2026-11-03 at the user's request ("in release make version and build can change the version and build number
for quick").

1. **AC-022-9**: `xcross project version [<x.y.z>[+<n>]] [--build <n>] [--bump major|minor|patch|build] [--json]`
   shows or changes the `version:` line of `pubspec.yaml`, keeping quotes, comments and every other line; a new
   major, minor or patch version also raises the build number (Flutter uses it as Android's `versionCode`, which
   must always grow); malformed values are usage errors and change nothing. JSON: `{"v":1,"type":"project_version",
   "version","build","previous","changed","pubspec"}`. Step 2 of the Release page has Version and Build fields with
   Save, and one-click bumps labelled with their result ("Patch → 1.0.8 (8)").

### User Story 3 - Archives (Priority: P2)

1. **AC-022-7**: An **Archives** destination lists every `build/xcross-ios/archive/*.xcarchive` of the open project
   with version, build, date, bundle ID, signing identity and team (from the archive's `Info.plist`), the IPA next to
   it, and "Open folder". An empty list explains how to make one.
2. **AC-022-8** (device, `device-check.md`): the packaged desktop app shows both pages; on app A the gate, the release
   check and the archive list work (the store steps need a team key).

### Edge Cases

- No project open: every step and the Archives page say "Open a Flutter project".
- An older CLI without these commands: the job's error is shown as is.

## Requirements *(mandatory)*

- **FR-001**: The GUI starts only `xcross` commands and reads only files the CLI wrote (`release.json`, archive
  `Info.plist`) for display.
- **FR-002**: "Submit for review" always asks for confirmation first.

## Success Criteria *(mandatory)*

- **SC-001**: A release manager can go from a clean checkout to a submitted build in the order of US-IOS-001 without
  leaving XCross Studio, given a team key.

## Assumptions

- CI hosts download the user's own Xcode `.xip` from a private URL they provide (`XCODE_XIP_URL`), honouring
  Constitution II; the template never fetches Apple material from elsewhere.
