# Feature Specification: Apply the app's entitlements when signing (push, associated domains)

**Feature Branch**: `003-entitlements-signed-ipa` | **Created**: 2026-11-01 | **Status**: Draft

**Input**: ROADMAP 003: "Apply `Runner.entitlements` (push, associated domains) via reusable signing"; upstream
#149 (entitlements part). The `xcross sign` export of a signed IPA is deferred, since `xcross install` (005) already
signs and installs any app.

## User Story 1 - Push and deep links work after `xcross flutter run` / `xcross install` (P1)

A Flutter developer whose `ios/Runner/Runner.entitlements` declares `aps-environment` and
`com.apple.developer.associated-domains` wants the installed app to carry them, so push and universal links work.
Today they are ignored for Flutter builds (only Compose builds pass them on).

**Independent Test**: build a project with `Runner.entitlements`; the built bundle's Info.plist carries the declared
entitlements and capabilities for the signer; after install, `xcross app info <id>` shows `aps-environment`.

**Acceptance Scenarios**:

1. **AC-003-1** — **Given** the app target's `CODE_SIGN_ENTITLEMENTS` (or `ios/Runner/Runner.entitlements`)
   declares entitlements, **When** I build, **Then** the bundle's Info.plist carries `XCrossEntitlements` (the
   declared dictionary) and `XCrossCapabilities` (the App Store Connect capability types they need, for example
   `PUSH_NOTIFICATIONS` and `ASSOCIATED_DOMAINS`). These are the keys the signer already uses to enable capabilities
   and embed entitlements, and it removes them before signing.
2. **AC-003-2** — **Given** no entitlements file, **When** I build, **Then** nothing changes.
3. **AC-003-3** — **Given** an entitlements file that is not a valid plist, **When** I build, **Then** a coded warning
   `build.entitlements_unreadable` is printed and the build continues without them.
4. **AC-003-4** — **Given** the app installed with push declared, **When** I run `xcross app info <id>` (010),
   **Then** `aps-environment` is present (device evidence).

## Requirements

- **FR-001**: Flutter builds MUST pass the app target's declared entitlements and the derived capabilities to the
  signer through `XCrossEntitlements` / `XCrossCapabilities`, the same contract the Compose builder uses.
- **FR-002**: The entitlements file is found through the app target's `CODE_SIGN_ENTITLEMENTS`, else
  `ios/Runner/Runner.entitlements`.
- **FR-003**: An unreadable file MUST produce a coded warning, not a silent skip.

## Success Criteria

- **SC-001**: An app built from a project with push declared shows `✔ push entitlement` in `xcross app info` after
  `xcross flutter run --release` or `xcross install`.

## Assumptions

- Push needs a paid Apple Developer account; free personal teams cannot enable the capability (Apple's rule). The
  signer reports Apple's error.
- The signer merges the profile's granted values (for example the development `aps-environment`) as it does for
  Compose apps today.
