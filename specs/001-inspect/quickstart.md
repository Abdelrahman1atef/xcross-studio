# Quickstart: validate `xcross inspect`

Run guide for feature 001. It proves the acceptance criteria end to end. Contracts:
[contracts/cli.md](contracts/cli.md), [contracts/inspect.schema.json](contracts/inspect.schema.json). Entities:
[data-model.md](data-model.md).

## Prerequisites

- Dart SDK matching the workspace (`^3.10.0`; verified with 3.13.7), on Windows **and** Linux.
- From the repo root: `dart pub get` (CI uses `dart pub get --enforce-lockfile`).
- No Apple SDK, device or network is needed for the automated checks.

## 1. Static checks

```bash
dart analyze --fatal-warnings            # includes repo_analyzer architecture rules
dart format --output=none --set-exit-if-changed packages/studio_ext
```

Expected: no warnings. In particular there are no `library_layout`, `missing_internal`, `native_acquisition` or
`ambient_platform_state` findings in `packages/studio_ext`.

## 2. Unit, golden and contract tests

```bash
cd packages/studio_ext && dart test
cd packages/xcross && dart test test/cli/inspect_registration_test.dart test/no_deep_imports_test.dart
```

Expected: all green on every OS. Test names contain the AC ids, so `dart test --name AC-001-` runs just the
acceptance tests. Checks per id:

| Id | Expected result |
|---|---|
| AC-001-1 | `unsigned_v209.ipa` reports `signature.present = false` and `profile = null`, with bundle id, versions, minimum OS and the `Frameworks/` list |
| AC-001-2 | `adhoc_push` main executable has `entitlements.aps-environment = "development"` |
| AC-001-3 | `profile_appex` profile: `kind = development`, team id, expiry, entitlements, `deviceCount`, no UDID anywhere |
| AC-001-4 | declared icon names with resolved files, `assetsCar.present`, `UILaunchScreen` keys and image source |
| AC-001-5 | committed goldens match byte for byte; the same files pass on Windows, Linux and macOS CI |
| AC-001-6 | two builds of the same fixture with different mtimes, profile dates and uuid produce identical `--normalize` output |
| AC-001-7 | the human summary has ✔/✖ lines and no secrets |
| SC-001 | a 20 MB synthetic IPA is inspected in under 3 s |
| SC-004 | planted fake UDIDs, a `GMSApiKey` value and certificate bytes are absent from every output |

To regenerate goldens after an intended change, run `UPDATE_GOLDENS=1 dart test test/shared/inspect/golden_test.dart`
(PowerShell: `$env:UPDATE_GOLDENS='1'; dart test …`). Review the JSON diff in the PR.

## 3. Run the command

From the repo root, against a fixture written by the test support (or any IPA):

```bash
dart run packages/xcross/bin/xcross.dart inspect path/to/app.ipa
dart run packages/xcross/bin/xcross.dart inspect path/to/app.ipa --json > report.json
dart run packages/xcross/bin/xcross.dart inspect path/to/app.ipa --json --normalize > report.normalized.json
dart run packages/xcross/bin/xcross.dart inspect does-not-exist.ipa --json; echo "exit=$?"
dart run packages/xcross/bin/xcross.dart inspect path/to/app.ipa --normalize; echo "exit=$?"
```

Expected:
1. a summary (exit 0)
2. pure JSON with no credits banner, valid against the schema (exit 0)
3. volatile fields replaced and `"normalized": true`
4. an error document with `inspect.input_not_found` (exit 1)
5. a usage error (exit 64)

Optional schema check with any JSON Schema 2020-12 validator, for example
`npx ajv-cli validate --spec=draft2020 -s specs/001-inspect/contracts/inspect.schema.json -d report.json`.

## 4. Real-world checks (manual, both hosts)

Run on a Windows 11 host and an Ubuntu 24.04 host:

1. **Unsigned xcross IPA**: `xcross flutter build --release --ipa` on `examples/flutter_example` (or the client app), then
   `xcross inspect build/xcross-ios/<name>.ipa`. Expected: ✖ signed, profile none, ✖ icon (`inspect.no_icon`), ✖
   launch screen (`inspect.launch_screen_empty`), frameworks listed. This matches the failure modes found in the
   client app session (SC-002).
2. **Signed `.app`**: after `xcross flutter run` on a device, `xcross inspect build/xcross-ios/<name>.app`. Expected:
   ✔ signed (certificate), development profile with a device count but no UDIDs, entitlements of the main executable
   as signed.
3. **Opt-in automated real-IPA test**: `STUDIO_INSPECT_IPA=/path/to/app.ipa dart test test/shared/inspect/real_ipa_test.dart`
   in `packages/studio_ext`. It passes when the report validates against the schema and contains no secret patterns.
4. **Host parity**: copy the same IPA to both hosts, run `--json --normalize` on each, and `diff` the two files.
   Expected: identical.

Never commit real IPAs, profiles or reports that contain client names or bundle ids (HANDOFF "Before anything goes
public").
