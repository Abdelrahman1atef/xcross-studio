# CLI contract: 016

## `xcross project bundle-id [original|prefixed] [--json]`

Run in a Flutter (or Compose) project root.

Text:
```
Bundle ID      com.example.app
Saved choice   original (pubspec.yaml)        | not saved
Override       XCROSS_BUNDLE_ID=prefixed      (only when set)
Next build     the real App ID com.example.app | the prefixed App ID XCR-<identity>.com.example.app
```
With a value: `Saved bundle_id: original (pubspec.yaml)`.

`--json` (one object on stdout):
```json
{"v":1,"type":"bundle_id","bundleId":"com.example.app","saved":"original","override":null,"settingsPath":"pubspec.yaml","next":"original"}
```
`saved`/`override` are `null` when absent; `next` is `original` or `prefixed`. Exit 64 for an invalid value,
1 outside a project.

## Diagnostic codes (warnings, `[code] message` + hint)

| Code | When | Hint |
|---|---|---|
| `build.push_entitlement_inferred` | push signal without declared `aps-environment` | Add `aps-environment` to `ios/Runner/Runner.entitlements` to make it explicit. |
| `build.maps_key_unresolved` | AppDelegate calls `provideAPIKey` but the key cannot be resolved | Pass a string literal or an Info.plist key read with `Bundle.main.object(forInfoDictionaryKey:)`. |
| `sign.capability_not_enabled` | a capability is still off after provisioning | Sign in with `xcross auth --apple-id` (or an Admin team key), or switch it on at developer.apple.com, then build again. |

## Environment

`XCROSS_RUNNER=auto|shim|project` (default `auto`).

## Doctor (`xcross flutter doctor`, section "Push notifications")

Checks `Push entitlement`, `Push App ID`, `Firebase config` (ndjson `check` events like every other check).
