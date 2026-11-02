# Feature Specification: Individual App Store Connect API keys

**Feature**: `015-individual-api-key`
**Created**: 2026-11-02
**Status**: Implemented

## Context

App Store Connect issues two kinds of API key:

- **Team keys** (Users and Access → Integrations → Team Keys) have an Issuer ID. Their token carries `iss: <issuer>`.
- **Individual keys** (Integrations → Individual Keys) belong to one user and have no Issuer ID. Their token
  carries `sub: "user"` and no `iss`.

Before this feature, xcross only supported team keys. A user who saved an individual key with their company's
Issuer ID got `HTTP 401 NOT_AUTHORIZED` and no explanation.

Apple also restricts individual keys. Checked on 2026-11-02 with a real key: `GET /v1/apps` returned 200, but
devices, certificates, bundle IDs and profiles returned 401. Individual keys therefore authenticate but cannot
provision, and signing or installing needs a Team key (Admin or App Manager) or an Apple ID.

## User story

As a developer whose company gave me an individual key rather than a team key, I can pick the kind of key I have.
xcross signs requests correctly for it and tells me plainly what that key can and cannot do.

## Acceptance criteria

| ID | Criterion | Test |
|----|-----------|------|
| AC-015-1 | An individual key's token has `sub: "user"` and no `iss`. Its identity is `individual-<keyId>`, and a team key's identity is its Issuer ID. | `packages/apple_developer_kit/test/appstoreconnect/asc_jwt_test.dart` |
| AC-015-2 | Saved individual credentials have `keyType: individual` and no `issuerId`, and they load back as individual. | same |
| AC-015-3 | `xcross auth --key-id … --private-key …` (no `--issuer-id`) saves an individual key and probes provisioning access. | `packages/xcross/test/cli/auth_key_type_test.dart` |
| AC-015-4 | A key that Apple refuses as a team key but accepts as individual is saved as individual. | same |
| AC-015-5 | Offline (Apple unreachable), a team key stays a team key. | same |
| AC-015-6 | GUI: choosing "Individual key" hides the Issuer ID field and runs `auth` without `--issuer-id`. The doctor's individual-key message shows "This individual key cannot sign apps" with "Create a Team key" and "Use Apple ID instead". | `apps/studio/test/ui/signing_result_test.dart` |
| AC-015-7 | `XcrossCommands.authApiKey` adds `--issuer-id` only when an Issuer ID is given. | `apps/studio/test/cli/cli_test.dart` |

## Behaviour

- `xcross auth` requires `--key-id` and `--private-key`. `--issuer-id` is optional; leaving it out means the key
  is individual.
- After saving, `xcross auth` checks the key with Apple (`GET /v1/apps?limit=1`). If a team key gets a 401, it
  retries as an individual key, and on success it saves the key as individual and says so. For individual keys it
  probes `GET /v1/devices`. On 401/403 it warns that signing and installing need a Team key or an Apple ID. If the
  network fails, nothing changes.
- `xcross flutter doctor` reports an individual key that cannot provision as ✗ under Authentication, with the
  same explanation.
- Signing caches are keyed by the credential identity, so a team key and an individual key never share
  certificates or profiles.

## Out of scope

- Making individual keys provision. Apple's API does not allow it.
- Telling key kinds apart without a network call. The `.p8` file looks the same for both.
