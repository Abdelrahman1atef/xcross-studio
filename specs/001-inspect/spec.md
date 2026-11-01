# Feature Specification: `xcross inspect` — machine-readable IPA/app report

**Feature Branch**: `001-inspect`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Add `xcross inspect <ipa|app> --json` that reports what is really inside a built iOS
app (Info.plist keys, entitlements per Mach-O, provisioning profile type, icons, asset catalog, frameworks) so every
later feature can be verified with golden tests and device evidence on Windows and Linux."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See what is inside my IPA (Priority: P1)

A developer who built an IPA wants to know, without a Mac, whether it is signed, which entitlements it carries,
whether it has an icon and launch screen, and which frameworks are bundled — the exact questions we had to answer by
hand while shipping a real client app.

**Why this priority**: It is the foundation for testing every other feature (golden tests, device-check evidence,
bug reports). Without it, regressions in signing/entitlements/assets are invisible until a device test fails.

**Independent Test**: Run `xcross inspect build/xcross-ios/app.ipa` on any IPA (including an unsigned v2.0.9 build)
and get a readable summary; run with `--json` and get a document that validates against the published schema.

**Acceptance Scenarios**:

1. **AC-001-1** — **Given** an unsigned IPA built by xcross v2.0.9, **When** I run `xcross inspect <ipa> --json`,
   **Then** the output reports `signature.present = false`, `provisioningProfile = null`, the bundle identifier,
   short version, build number, minimum OS, and the list of frameworks under `Frameworks/`.
2. **AC-001-2** — **Given** an IPA whose main executable carries an embedded entitlements blob (e.g. ad-hoc signed
   with `aps-environment = development`), **When** I inspect it, **Then** `executables[].entitlements` for the main
   executable contains `aps-environment: "development"`.
3. **AC-001-3** — **Given** an IPA that contains `embedded.mobileprovision`, **When** I inspect it, **Then** the
   report includes the profile kind (development / ad-hoc / app-store / enterprise), team id, expiry date, the
   entitlements granted by the profile, and the number of provisioned devices — never the device UDIDs themselves
   and never certificate private material.
4. **AC-001-4** — **Given** an IPA with `CFBundleIcons` and loose icon PNGs, or with an `Assets.car`, **When** I
   inspect it, **Then** the report lists declared icon names, which referenced files exist, and whether `Assets.car`
   is present; for `UILaunchScreen` it reports the declared keys and whether referenced images resolve.
5. **AC-001-5** — **Given** the same input file, **When** `inspect --json` runs on Windows and on Linux, **Then** the
   outputs are byte-identical.

---

### User Story 2 - Compare two builds (Priority: P2)

A maintainer wants CI to fail when a change accidentally drops an entitlement, an icon or a framework.

**Why this priority**: Enables golden tests across the whole roadmap; depends on Story 1's JSON.

**Independent Test**: Commit a normalised golden JSON for a fixture app; CI regenerates it and diffs.

**Acceptance Scenarios**:

1. **AC-001-6** — **Given** `--json --normalize`, **When** I inspect two builds of the same source made at different
   times, **Then** the outputs are identical (timestamps, absolute paths, signature hashes and other volatile fields
   are removed or replaced with stable placeholders).

---

### User Story 3 - Attach a safe report to a bug (Priority: P3)

A user filing an issue wants to attach what is inside their IPA without leaking secrets.

**Why this priority**: Improves upstream/fork issue quality (maintainers repeatedly ask for details); low effort once
Story 1 exists.

**Independent Test**: Inspect an IPA signed with a development profile; confirm no UDID, certificate serial, private
key, or API key appears in the output.

**Acceptance Scenarios**:

1. **AC-001-7** — **Given** any IPA, **When** I run `xcross inspect <ipa>` (human-readable), **Then** the output is a
   short summary with ✔/✖ lines for: signed, profile kind, push entitlement, associated domains, icon, launch screen,
   frameworks count — and contains no device UDIDs or credential material.

### Edge Cases

- Input is a `.app` directory instead of an `.ipa` → same report.
- IPA with multiple `.app` entries or none under `Payload/` → clear error with a stable code (`inspect.no_app` /
  `inspect.multiple_apps`).
- Corrupt zip, truncated Mach-O, fat (universal) binary, or binary/XML Info.plist → handled; per-file errors are
  reported in an `issues[]` array instead of aborting the whole report.
- App extensions (`PlugIns/*.appex`) → reported as nested bundles with their own entitlements.
- Very large IPA (> 500 MB) → streamed; memory bounded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The CLI MUST provide `xcross inspect <path>` accepting an `.ipa` file or a `.app` directory.
- **FR-002**: `--json` MUST print a single JSON document conforming to a versioned schema
  (`schemaVersion: 1`) published at `specs/001-inspect/contracts/inspect.schema.json`.
- **FR-003**: The report MUST include: bundle (id, name, display name, versions, minimum OS, device family),
  Info.plist keys relevant to this roadmap (`CFBundleIcons`, `UILaunchScreen`, `UILaunchStoryboardName`,
  `UIBackgroundModes`), executables (main, frameworks, dylibs, extensions) with architecture, signature presence,
  signature kind (none / ad-hoc / certificate) and embedded entitlements; provisioning profile summary; resources
  (icons, `Assets.car`, storyboards); frameworks list.
- **FR-004**: The report MUST NOT contain device UDIDs, certificate private keys, raw certificate data, API keys, or
  Apple account identifiers other than the team id.
- **FR-005**: `--normalize` MUST remove or stabilise volatile fields so that reports of identical sources are equal.
- **FR-006**: The command MUST be read-only: it never modifies the input and never contacts the network or a device.
- **FR-007**: Output MUST be identical on Windows and Linux for the same input.
- **FR-008**: Failures MUST use stable error codes and a non-zero exit code; partial problems go to `issues[]`.

### Key Entities

- **InspectReport**: top-level document (schemaVersion, input kind, bundle, executables[], profile, resources,
  frameworks[], issues[]).
- **ExecutableInfo**: relative path, role (main/framework/dylib/extension), architectures, signature kind,
  entitlements (map).
- **ProfileSummary**: kind, team id, name, expiry, granted entitlements, device count.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Inspecting a 20 MB IPA completes in under 3 seconds on a typical laptop, on both OSes.
- **SC-002**: The client-app-style failure modes from this project (unsigned IPA, missing `aps-environment`, missing icons,
  missing launch screen, skipped plugin frameworks) are each detectable from one `inspect` run.
- **SC-003**: At least 3 fixture apps have committed golden reports used by CI by the end of M0.
- **SC-004**: Zero secrets (UDIDs, keys, certificate material) appear in any golden file or test output.

## Assumptions

- Mach-O and code-signature parsing reuses existing code in `packages/apple_developer_kit` (signing package) where it
  exposes readers; otherwise a small read-only parser is added in `packages/studio_ext`.
- The command lives in the fork (`studio_ext`) and is registered at the CLI composition root seam; it is a good
  upstream candidate.
- Asset catalog (`Assets.car`) content is reported at presence/size level in v1; per-rendition listing may come with
  feature 004.
- No GUI work is part of this feature; the GUI consumes `inspect --json` later (feature 008).
