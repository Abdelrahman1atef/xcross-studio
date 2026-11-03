# Implementation Plan: Upload to App Store Connect and follow processing

**Branch**: `019-upload-processing` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

S = `packages/studio_ext/lib`, X = `packages/xcross/lib/src`.

- **S** `src/shared/appstore/build_upload.dart` (new): `BuildUploader` — create upload, reserve file, send
  operations (retry ×3, back-off), commit with MD5, resume state file; `UploadPart` progress callback.
- **S** `src/shared/appstore/build_processing.dart` (new): `BuildProcessing.wait` — poll the build upload, then the
  build's `processingState`; `duplicateBuild` lookup.
- **S** `shared/appstore/build_numbers.dart` (new, public for xcross): `nextBuildNumber(api, appId, local)`.
- **S** `src/shared/appstore/release_record.dart` (new): `build/xcross-ios/release.json` merge/write.
- **S** `src/shared/appstore/transporter.dart` (new): locate a user-installed `iTMSTransporter`, build the upload and
  verify command lines (API key arguments; the key file is linked where Transporter looks).
- **S** `shared/appstore/publish_command.dart` (new): `xcross publish [<ipa>] [--app-id] [--wait] [--timeout]
  [--json] [--transporter] [--validate]`.
- **X** `composition/cli/publish_commands.dart`: registers it with `openAscApi`, the git/Flutter readers and the
  Transporter runner. `composition/cli/flutter_build_command.dart`: `--build-number auto` seam (`// studio: 019`).

## Technical Context

Dart 3 · `http` (presigned PUT), `crypto` (MD5, SHA-256), `archive` (read Info.plist from the IPA) — all already
studio_ext dependencies · tests with `FakeAsc` (API) and the same fake for presigned URLs · Windows/Linux.

## Constitution Check

I new files + one seam · II Transporter only when the user installed it; never downloaded · III coded errors
(`publish.*`), role hints · IV CLI only · V Transporter locations are a list of candidates, no OS branch · VI
AC-named tests · VII no new dependency · VIII the token never goes to presigned URLs; nothing secret in
`release.json`. No violations.

## Tests

`packages/studio_ext/test/shared/appstore/publish_test.dart` (AC-019-1…9 except device evidence).
