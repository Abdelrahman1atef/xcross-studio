# Tasks: App Store build and release check

K = `packages/apple_developer_kit/lib`, X = `packages/xcross/lib/src`, S = `packages/studio_ext/lib`.

## Phase 1: Foundational

- [X] T001 K: `DistributionProvisioningClient` + `AscClient` methods; `AscPayloads.appStoreProfile`.
- [X] T002 K: `AscProvisioning.provisionDistributionIdentity` (R1) and its test
  `packages/apple_developer_kit/test/appstoreconnect/distribution_test.dart` (AC-018-2).

## Phase 2: User Story 1 — App Store IPA and archive (P1)

- [X] T003 [US1] X `target/iphone/device/app_store_export.dart`: session, provisioning, signing, IPA, archive.
- [X] T004 [US1] X `target/iphone/device/xcode_archive.dart`: `.xcarchive` writer and `dsymutil` (AC-018-5).
- [X] T005 [US1] X `composition/cli/flutter_build_command.dart`: `--export-method` seam and artifact events.
- [X] T006 [P] [US1] Tests `packages/xcross/test/flutter/build/app_store_export_test.dart` (AC-018-1, 3, 4, 5).

## Phase 3: User Story 2 — toolchain identity (P1)

- [X] T007 [US2] X `shared/sdk/xcode_build_info.dart` + record seam in `shared/sdk/sdk_archive_extraction.dart` +
  DT keys in `target/shared/flutter/ios_plist_metadata.dart` (AC-018-6).
- [X] T008 [US2] X doctor SDK ≥ 26 (AC-018-7); assembler `ITSAppUsesNonExemptEncryption` (AC-018-8).
- [X] T009 [P] [US2] Tests `packages/xcross/test/flutter/build/xcode_build_info_test.dart`.

## Phase 4: User Story 3 — release check (P1)

- [X] T010 [US3] S `src/shared/release/macho_build_version.dart`, `src/shared/release/release_tables.dart`.
- [X] T011 [US3] S `src/shared/release/release_checks.dart` (AC-018-9…13) and
  `shared/release/release_check_command.dart` (AC-018-14); register in
  `packages/xcross/lib/src/composition/cli/runner.dart` (`// studio: 018`); JSON owns stdout.
- [X] T012 [P] [US3] Tests `packages/studio_ext/test/shared/release/release_check_test.dart`.

## Phase 5: Evidence and polish

- [X] T013 Rebuild the CLI; app A `release check` on the current IPA; App Store export when a team key is available
  (`device-check.md`, AC-018-15).
- [X] T014 Analyze, tests, CHANGELOG, README, user story statuses (AC-03…AC-11, TC-07/09/11/12/15/16/18/32).
- [X] T015 SwiftSupport in the App Store IPA and archive (AC-018-16): SDK install keeps the iPhoneOS Swift runtime,
  `swift_support.dart`, `IpaPackager(extraEntries)`, `release.swift_support_missing`.
- [X] T016 `release.permission_missing_for_call` (AC-018-17).
- [X] T017 `release check --online` and Studio step 6 (AC-018-18). **Still owed on the real account:** an upload that
  App Store Connect accepts with the SwiftSupport folder (needs `xcross sdk install` again, then a rebuild).

## Dependencies

T001 → T002 → T003 → T005; T004 independent; US2 and US3 do not depend on US1.
