# Implementation Plan: App Store submission from the CLI

**Branch**: `021-app-store-submission` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

S = `packages/studio_ext/lib`. Built on the 019 groundwork (`AscApi`, `OpenAscApi`, `resolveAscApp`, `ascFailure`).

- `S/src/shared/appstore/app_store_project.dart`: bundle ID (`ReleaseProject.bundleId`, feature 018), display name
  (Info.plist literal, else pubspec `name`), SKU suggestion.
- `S/src/shared/appstore/app_store_versions.dart`: editable-state list, find/create the version, find a build by
  number.
- `S/src/shared/appstore/app_store_metadata.dart`: folder model (`MetadataFolder` read/write) and `MetadataSync`
  (pull, push with a change list).
- `S/src/shared/appstore/app_store_screenshots.dart`: display-type size table, PNG `IHDR` size reader, the reserve →
  upload operations → commit flow (`api.httpClient` for presigned URLs, no token).
- `S/src/shared/appstore/app_store_review.dart`: blockers, review submission create/reuse/add/submit, status.
- `S/shared/appstore/appstore_command.dart`: `appstore app|version|metadata pull|push|screenshots push|attach|
  submit|status`.
- `packages/xcross/lib/src/composition/cli/appstore_commands.dart`: fills `appStoreCommands` (`// studio: 021`).

## Technical Context

Dart 3 · existing deps (`http`, `crypto`, `apple_developer_kit`, `args`) · tests with `FakeAsc` (studio_ext test
support) · Windows and Linux.

## Constitution Check

I new files, one composition seam · II nothing Apple-supplied · III every refusal explained (role, missing record,
wrong screenshot size before upload) · IV CLI only · V paths through `p.Context`, no OS branch · VI AC-named tests ·
VII no new dependency · VIII the token never leaves `AscApi`; presigned URLs get only Apple's own headers.
No violations.

## Tests

`packages/studio_ext/test/shared/appstore/appstore_test.dart` (AC-021-1 … AC-021-10).
