# Feature Specification: Upload to App Store Connect and follow processing

**Feature Branch**: `019-upload-processing` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Draft

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 019 (US-IOS-001 AC-02 build numbers, AC-11 Apple
validation, AC-12 upload, AC-13 processing, §11 release evidence; QA TC-19, TC-20, TC-21, TC-29, TC-30, TC-31). The
reference Mac workflow uploads with Codemagic's `app-store-connect publish` and picks the build number from App Store
Connect. xcross has no upload at all. App Store Connect's **Build Upload API** (`buildUploads`, `buildUploadFiles`,
presigned upload operations, commit) lets a Windows or Linux machine upload without Transporter.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Upload an App Store IPA (Priority: P1)

**Acceptance Scenarios**:

1. **AC-019-1**: `xcross publish [<ipa>] [--app-id <id>]` (default: the newest IPA in `build/xcross-ios/ipa/`, then
   `build/xcross-ios/`) reads the bundle ID, version and build number from the IPA, finds the app (`--app-id`, else
   the record with that bundle ID), creates a build upload (`POST /v1/buildUploads`, platform `IOS`), reserves the
   file (`POST /v1/buildUploadFiles`, `ASSET`, `com.apple.ipa`, name and size), sends every upload operation to its
   presigned URL with the operation's method and headers (no API token), and commits it (`PATCH
   /v1/buildUploadFiles/{id}`: `uploaded: true`, MD5 `sourceFileChecksums`). Progress is shown per part.
2. **AC-019-2** (TC-29): before uploading, a build with the same build number for that version already on App Store
   Connect (`/v1/builds` filtered by app, build number and version) stops the upload with `publish.duplicate_build`
   and the hint `--build-number auto`.
3. **AC-019-3** (TC-30): a failed part is retried up to 3 times with back-off. An interrupted upload leaves
   `build/xcross-ios/.publish-<version>-<build>.json` (upload and file ids, finished parts, IPA SHA-256); running the
   same `xcross publish` again resumes the parts not sent yet when the IPA is unchanged and the reservation has not
   expired, and starts a new upload otherwise.
4. **AC-019-4**: A key the upload is refused for (401/403) stops with the role hint (team key with Admin, App Manager
   or Developer role; individual keys as their user's role allows).

### User Story 2 - Processing (Priority: P1)

1. **AC-019-5**: `xcross publish --wait [--timeout <minutes>]` follows the upload state (`AWAITING_UPLOAD` →
   `PROCESSING` → `COMPLETE`/`FAILED`, with Apple's errors, warnings and infos by code) and then the build's
   `processingState` (`PROCESSING` → `VALID`/`FAILED`/`INVALID`). It exits 0 on `VALID`, 1 on a failure, 2 on
   timeout (default 60 minutes; the upload is not cancelled).
2. **AC-019-6**: `--json` prints `{"v":1,"type":"publish",…}` events: `progress` per part, `state` changes, and a
   final `published` object (upload id, state, build id, processing state, issues).

### User Story 3 - Build numbers and release record (Priority: P2)

1. **AC-019-7**: `xcross flutter build --build-number auto` uses max(the pubspec build number, the newest App
   Store Connect build number of the app + 1); the app comes from `APP_STORE_APP_ID` or the project bundle ID.
   Offline or without a key it falls back to the pubspec number with a warning.
2. **AC-019-8** (§11, TC-31): every publish writes `build/xcross-ios/release.json`: app, bundle ID, team, version,
   build, minimum iOS, SDK, Flutter version, git commit (and dirty flag), IPA SHA-256 and size, upload id, upload
   state, build id, processing state, time stamps. Values are merged into an existing record.

### User Story 4 - Transporter fallback (Priority: P3)

1. **AC-019-9**: `--transporter` uploads with a user-installed Transporter (`iTMSTransporter -m upload -assetFile …
   -apiKey … -apiIssuer …`, looked up in Apple's install locations or `XCROSS_TRANSPORTER`); `--validate` runs its
   `-m verify` (AC-11). Without Transporter both stop with `publish.transporter_missing` and Apple's download page;
   xcross never downloads it.
2. **AC-019-10** (store evidence, `device-check.md`): app A's App Store IPA uploaded with a team key reaches
   `VALID` and appears in `xcross testflight status` (feature 020).

### Edge Cases

- An IPA without `CFBundleShortVersionString`/`CFBundleVersion`: refused before any request.
- The upload state comes back `FAILED` with Apple codes (ITMS-…): printed with their descriptions and recorded in
  `release.json`; they go into the user story's failure table when seen.
- `--wait` interrupted: the upload continues on Apple's side; `xcross testflight status` shows it later.

## Requirements *(mandatory)*

- **FR-001**: The upload never sends the API token to presigned URLs, and never prints them.
- **FR-002**: Only the files the user built are uploaded; no Apple tool is downloaded.

## Success Criteria *(mandatory)*

- **SC-001**: A developer uploads an App Store build from Windows or Linux with one command and sees its processing
  result without opening App Store Connect.
- **SC-002**: A duplicate build number never consumes an upload.

## Assumptions

- Uploading with an App Store Connect key needs the Admin, App Manager or Developer role (team keys); whether the
  user's individual key may upload depends on the user's own role and is recorded in `device-check.md` when tried.
