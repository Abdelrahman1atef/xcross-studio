# Data Model: 002 quick wins

Phase 1 output for [plan.md](plan.md). Codes and texts: [contracts/diagnostics.md](contracts/diagnostics.md).

## DiagnosticCode

| Field | Type | Rule |
|---|---|---|
| `code` | String | dotted, stable: `device.*`, `toolchain.*`, `build.*` |
| `hint` | String | one concrete fix; may be overridden per call (OS-specific service hint) |

## PrecheckedDevice (result of the device precheck)

| Field | Type | Rule |
|---|---|---|
| `device` | Device | the device install and launch will use; never re-resolved after the build |
| `osMajor` | int? | null when unreadable (the run continues with a warning, as today) |

State flow: `service check` → `resolve device` → `read OS version` → `gate (≥ 17)` → `PrecheckedDevice` (or a
coded error).

| Search mode | Service down | Result |
|---|---|---|
| USB only | yes | error `device.host_service_unavailable` |
| both | yes, and no device found | error `device.host_service_unavailable` |
| both | yes, but a device is found | proceed |
| Wi-Fi only | — | check skipped |

## Device (existing, extended)

| Field | Change |
|---|---|
| `osVersion` | **new**, String?, from `usbmux list` `ProductVersion`; null for tunnel-only entries |

## IosBundleVersions (existing, extended)

| Field | Type | Rule |
|---|---|---|
| `shortVersion` | String | first non-empty, `$`-free value of: `--build-name`, pubspec build name, xcconfig `FLUTTER_BUILD_NAME` (else `MARKETING_VERSION`), pbxproj `MARKETING_VERSION` of the Runner app target, `1.0.0` |
| `bundleVersion` | String | same order with `--build-number`, pubspec build number, xcconfig `FLUTTER_BUILD_NUMBER` (else `CURRENT_PROJECT_VERSION`), pbxproj `CURRENT_PROJECT_VERSION`, `1` |
| `shortVersionSource` | VersionSource | **new** |
| `bundleVersionSource` | VersionSource | **new** |

`VersionSource`: `flag`, `pubspec`, `xcconfig`, `projectFile`, `fallback`. The pubspec values come from
`PubspecInfo.buildName/buildNumber`: a valid semantic version only, so an invalid version falls through, after the
existing hint.

## SkippedResource (returned by resource staging)

| Field | Type | Rule |
|---|---|---|
| `path` | String | project resource path as listed in the Xcode project |
| `reason` | enum | `assetCatalog`, `uncompiledStoryboard`, `missing` |

## BuildWarnings (per build)

| Field | Type | Rule |
|---|---|---|
| `seen` | Set<(code, subject)> | a warning prints only the first time its (code, subject) is seen |
| `counts` | Map<code, int> | for the summary, sorted by code |

Lifecycle: created with the Flutter build runtime; `takeSummary()` at the end of each pack prints the summary and
resets the collector.

## PathLinkerGuard

| Field | Type | Rule |
|---|---|---|
| cache | Map<directory, String?> | reason why `<dir>/ld64.lld` cannot be used (iOS link probe failure or lld < 19 selector-stub defect); null when usable or absent |
