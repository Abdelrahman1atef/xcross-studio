# Feature Specification: TestFlight from the CLI

**Feature Branch**: `020-testflight` (work lands on `008-json-events-gui`) | **Created**: 2026-11-03 |
**Status**: Implemented (store rows open)

**Input**: handoff plan `specs/HANDOFF-2026-11-03.md`, feature 020 (US-IOS-001 AC-13 status part, AC-14, AC-15).
After `xcross publish` (019) a build sits in App Store Connect; the story then needs it checked (processing and beta
states), handed to internal testers with "What to Test", answered for export compliance, and, for external testers,
described, sent to beta review and shared by public link. On a Mac this is the App Store Connect web site; xcross
does it through the App Store Connect API so the whole release runs from Windows, Linux or CI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See where a build is (Priority: P1)

**Acceptance Scenarios**:

1. **AC-020-1**: `xcross testflight status [--build <n>] [--version <x.y.z>] [--app-id <id>] [--json]` lists the
   app's newest builds (or the one asked for) with marketing version, build number, upload date, processing state
   (`PROCESSING`, `VALID`, `FAILED`, `INVALID`), expired flag, export compliance answer, internal and external beta
   states (`READY_FOR_BETA_TESTING`, `MISSING_EXPORT_COMPLIANCE`, `IN_BETA_REVIEW`, …) and the beta groups it is in.
   `--json` prints one `{"v":1,"type":"testflight_status","appId",…,"builds":[…]}` object.
2. **AC-020-2**: The app is `--app-id`, else the App Store Connect record whose bundle ID is the project's
   (`ios/Runner.xcodeproj` in the current folder); the build is `--build <number>`, else the newest upload. A missing
   app, build or group is an error that says what to pass; Apple refusals carry the role hint (403: a team key with
   the Admin or App Manager role).

### User Story 2 - Internal testing (Priority: P1)

1. **AC-020-3**: `testflight groups [--json]` lists groups (internal/external, tester count when known, public
   link); `testflight group create <name> [--external] [--public-link] [--public-link-limit <n>]` creates one.
2. **AC-020-4**: `testflight add --group <name> [--build <n>]` adds the build to the group.
3. **AC-020-5**: `testflight what-to-test "<text>" [--build <n>] [--locale en-US]` sets the build's "What to Test",
   updating the localization when it exists.
4. **AC-020-6**: `testflight testers add <email>… --group <name> [--first-name] [--last-name]` invites testers into
   the group (an existing tester is added to the group); `testflight testers list --group <name>` lists them.
5. **AC-020-7**: `testflight compliance --no-encryption|--uses-encryption [--build <n>]` answers the build's export
   compliance question (clears `MISSING_EXPORT_COMPLIANCE`).

### User Story 3 - External testing (Priority: P2)

1. **AC-020-8**: `testflight app-info [--description] [--feedback-email] [--marketing-url] [--privacy-url]
   [--locale]` sets the beta app information; `testflight review-info --contact-first-name … --contact-email …
   [--demo-user --demo-password] [--notes]` sets the beta review contact and demo account (the password is never
   printed).
2. **AC-020-9**: `testflight submit [--build <n>]` submits the build to TestFlight App Review and prints the review
   state; `testflight public-link --group <name> [--enable|--disable] [--limit <n>]` turns the group's public link
   on or off and prints it.
3. **AC-020-10** (store, `device-check.md`): with a team key, a processed build is added to an internal group,
   installed from TestFlight on the iPhone, and a beta review submission is accepted.

### Edge Cases

- A tester that already exists (409): found by email and added to the group.
- A build still processing: `status` shows it; `add` and `submit` pass Apple's refusal through.
- No build uploaded yet: an error naming `xcross publish`.

## Requirements *(mandatory)*

- **FR-001**: All requests go through the shared `AscApi` (019 groundwork); commands live in `studio_ext` and are
  registered only through `testflightCommands(runtime)`.
- **FR-002**: Demo passwords and keys are never printed; JSON mirrors only what App Store Connect returns.

## Success Criteria *(mandatory)*

- **SC-001**: From a terminal on Windows or Linux, a release manager can take an uploaded build to internal testers
  in four commands (status, compliance, add, what-to-test).
- **SC-002**: Every TestFlight step of the story's guide (12) has a CLI command.

## Assumptions

- A team key with the Admin or App Manager role (Developer keys can upload but not manage TestFlight).
- Apple's beta review and tester limits (100 internal, 10,000 external, 90 days) stay Apple-side.
