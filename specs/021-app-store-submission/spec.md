# Feature Specification: App Store submission from the CLI

**Feature Branch**: `021-app-store-submission` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Implemented (store rows open)

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 021 (US-IOS-001 AC-01 app record, AC-16). After an
upload (019) and TestFlight (020), the release manager still has to open App Store Connect in a browser to check the
app record, fill the product page, upload screenshots, attach the build and submit for review. This feature does those
steps from Windows or Linux with the App Store Connect API, and says plainly which steps the public API cannot do
(creating the app record, App Privacy answers, pricing, agreements).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The app record and the version to submit (Priority: P1)

**Acceptance Scenarios**:

1. **AC-021-1**: `xcross appstore app [--app-id <id>] [--json]` finds the App Store Connect app whose bundle ID is the
   project's (`PRODUCT_BUNDLE_IDENTIFIER` of the app target in `ios/Runner.xcodeproj`), and prints its name, Apple ID,
   SKU and primary locale. When there is none it explains that Apple's public API cannot create apps and prints the
   New App page (`https://appstoreconnect.apple.com/apps`) with the bundle ID, a name (Info.plist display name, else
   the pubspec name) and a SKU to enter; `--json` prints `{"v":1,"type":"appstore_app","found":false,"newAppUrl":…}`.
   The command exits 1 when the record is missing.
2. **AC-021-2**: `xcross appstore version [<x.y.z>] [--create] [--json]` shows the editable iOS App Store version
   (`PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`, `INVALID_BINARY`), the named one
   when a version string is given; `--create` creates it (`POST appStoreVersions`, platform `IOS`) when the app has no
   editable version. Without one and without `--create` it says how to create it.

### User Story 2 - The product page from a folder (Priority: P1)

1. **AC-021-3**: `xcross appstore metadata pull [--dir appstore/metadata] [--version x.y.z]` writes a
   fastlane-deliver-style folder: `<locale>/name.txt`, `subtitle.txt`, `privacy_url.txt` (app info localizations),
   `<locale>/description.txt`, `keywords.txt`, `promotional_text.txt`, `release_notes.txt`, `support_url.txt`,
   `marketing_url.txt` (version localizations), and at the top `copyright.txt`, `primary_category.txt`,
   `secondary_category.txt` and `age_rating.json`.
2. **AC-021-4**: `xcross appstore metadata push [--dir …] [--version x.y.z]` reads the same folder, creates missing
   localizations, patches only fields whose text differs (trailing whitespace ignored), sets the copyright, the
   categories and the age rating, and prints one line per change ("nothing to change" when the page already
   matches). Files that are absent leave the field as it is.

### User Story 3 - Screenshots (Priority: P1)

1. **AC-021-5**: `xcross appstore screenshots push [--dir appstore/screenshots] [--replace] [--version x.y.z]` uploads
   `<locale>/<display type>/*.png` (display types as App Store Connect names them: `APP_IPHONE_67`, `APP_IPHONE_65`,
   `APP_IPAD_PRO_3GEN_129`, …). Every image's pixel size is checked against the sizes Apple accepts for its display
   type before anything is uploaded; a wrong size, an unknown display type or a non-PNG stops the command with the
   accepted sizes.
2. **AC-021-6**: Each image is reserved (`POST appScreenshots` with name and size), sent to every upload operation
   Apple returns (method, URL, offset, length and its request headers, without the API token), then committed
   (`PATCH uploaded: true` with the file's MD5 as `sourceFileChecksum`). Missing screenshot sets are created;
   `--replace` deletes the screenshots already in a set first; without it an image whose file name is already in the
   set is skipped.

### User Story 4 - Attach, submit, follow (Priority: P1)

1. **AC-021-7**: `xcross appstore attach --build <number> [--version x.y.z]` attaches the app's build with that
   build number to the version (`PATCH appStoreVersions/{id}/relationships/build`); a build still processing or
   invalid is refused with its state.
2. **AC-021-8**: `xcross appstore submit [--version x.y.z] [--dry-run]` creates (or reuses an unsubmitted) review
   submission for the app, adds the version as an item and submits it (`submitted: true`). Before that it lists the
   blockers it can see: no build attached, a version localization without description, keywords or support URL, a
   localization without screenshots, an app info localization without a name. Blockers stop the submission;
   `--dry-run` prints them (or "ready to submit") and changes nothing.
3. **AC-021-9**: `xcross appstore status [--json]` prints the editable (else latest) version's state, its build and
   the latest review submissions' states.
4. **AC-021-10**: App Privacy answers, pricing and availability, and agreements/tax/banking are not in the public API:
   `xcross appstore` says so in its help and the `submit` output names the App Store Connect pages to check.
5. **AC-021-11** (store, `device-check.md`): with a team key, app A's metadata round-trips, screenshots upload, and a
   dry-run submission lists only real blockers.

### Edge Cases

- No project folder: `--app-id` is required.
- An individual or Developer key: Apple refuses the writes; the message names the role (Admin or App Manager).
- Several editable versions (rare): the named one, else the newest.

## Requirements *(mandatory)*

- **FR-001**: All logic in `studio_ext` (`lib/shared/appstore/`, `lib/src/shared/appstore/`); the composition root only
  opens the API session (`openAscApi`) and registers the command group.
- **FR-002**: Presigned upload URLs never receive the App Store Connect token.
- **FR-003**: No secret (key, token) is printed; errors go through `ascFailure`.

## Success Criteria *(mandatory)*

- **SC-001**: A release manager can prepare and submit a version for review without opening a browser, except for
  the pages Apple keeps out of the API.
- **SC-002**: A screenshot with the wrong size is caught before any upload.

## Assumptions

- Writes need a team key with the Admin or App Manager role (individual keys are refused by Apple for most of them).
- Reviewer contact details, demo account and phased release are left to App Store Connect (not in this feature).
