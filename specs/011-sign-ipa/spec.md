# Feature Specification: `xcross sign`, a re-signed IPA without installing

**Feature Branch**: `011-sign-ipa` | **Created**: 2026-11-01 | **Status**: Implemented (device rows open)

**Input**: ROADMAP 003, deferred half: "`xcross sign <any.ipa>` re-signs any IPA with Apple ID or App Store Connect key
(Sideloadly replacement, part 1)"; upstream #146 (unsigned IPA / no sign command).

## User Story 1 - Get a signed IPA I can keep and share (P1)

A developer on Windows or Linux has an `.ipa` (their own xcross build, or one from another source) and wants a copy
signed with their Apple ID or App Store Connect key. They want to install it later, or hand it to a tester whose
iPhone is registered on the team. Nothing should be installed now.

**Independent Test**: `xcross sign app.ipa` writes `app-signed.ipa`. `xcross inspect app-signed.ipa` shows a certificate
signature, an embedded development profile and the entitlements. `xcross install --no-resign app-signed.ipa`
installs it unchanged.

**Acceptance Scenarios**:

1. **AC-011-1**: **Given** an `.ipa` or `.app`, **When** I run `xcross sign <path>`, **Then** a copy is provisioned
   and signed with the saved credentials (the same pipeline as `xcross install`) and written as
   `<input>-signed.ipa` (or `-o <file>.ipa`). The input is never modified and the work folder is removed.
2. **AC-011-2**: Devices in the profile: every `--udid` (repeatable, need not be connected) and every iPhone connected
   by USB (unless `--no-usb`) is registered on the team first. The development profile also lists every device
   already on the team. If the team has no device at all, the command fails with `sign.no_device` and a hint.
3. **AC-011-3**: The IPA is `Payload/<App>.app/…` with entries sorted, one fixed timestamp, Unix modes (Mach-O 0755,
   other files 0644, directories 0755) and the archive marked as made on Unix, so the modes survive extraction. The
   same bundle gives the same bytes.
4. **AC-011-4**: Before reporting success, the written IPA is read back with the feature 001 inspector. It must have
   `_CodeSignature/CodeResources`, every executable certificate-signed, an embedded profile (app and extensions) and
   no `XCrossEntitlements`/`XCrossCapabilities` left. Otherwise the output is deleted and the command fails with
   `sign.verify_failed`. On success a ✔ summary shows bundle id, team, profile kind, expiry, device count and
   entitlement keys (no device ids, no certificate names).
5. **AC-011-5**: `--bundle-id <id>` signs under another bundle id; extensions keep their suffix under it.
6. **AC-011-6**: `xcross install --no-resign <ipa>` installs a signed IPA as it is (byte-identical bundle).
7. **AC-011-7**: Bad input or output fails fast: `install.unsupported_input` / `install.no_app` for the input,
   `sign.output_invalid` when `-o` is not an `.ipa` path or would overwrite the input.
8. **AC-011-8**: A bundle with `SC_Info` (App Store encryption) gets the warning `sign.encrypted_app`: it installs but
   does not start after re-signing.
9. **AC-011-9** (device): an IPA signed on the Windows PC installs on the iPhone X with `xcross install --no-resign`
   and opens; `xcross app info` shows the development signer and team.

## Requirements

- **FR-001**: Reuse the install pipeline (credentials, certificate, App ID, capabilities from `XCrossEntitlements`,
  extensions, App Groups, profile, `BundleSigner`); the only difference is that nothing is installed.
- **FR-002**: Binary Info.plists are rewritten as XML in the copy before signing (the signer edits XML). With
  `install --no-resign` the copy stays byte-identical.
- **FR-003**: Coded errors and warnings with hints (`sign.*`), as in feature 002.

## Out of scope

Ad-hoc and App Store distribution profiles (only development profiles are issued today), re-signing App Store
encrypted apps, notarisation of any kind.
