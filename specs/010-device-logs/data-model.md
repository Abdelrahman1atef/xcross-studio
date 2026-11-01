# Data Model: 010 device logs

Phase 1 output for [plan.md](plan.md). JSON shapes: [contracts/devicelog.schema.json](contracts/devicelog.schema.json).

## SyslogEntry (dart_mobile_device; shared with `DeviceLog`)

Parsed from one `syslog live --format json` line. A line that is not JSON, or has no `pid`/`message`, gives null.

| Field | Source | Rule |
|---|---|---|
| `pid` | `pid` | int |
| `process` | basename of `filename` (else of `image_name`) | e.g. `SpringBoard`, `Runner` |
| `time` | `timestamp` | kept as the device-local string |
| `level` | `level` | lower-cased; unknown → `notice` |
| `subsystem`, `category` | `label.subsystem`, `label.category` | nullable |
| `message` | `message` | raw string |

## DeviceLogEvent (studio_ext; what is printed)

`SyslogEntry` plus `highlight` (`registration | delivery | error | null`) and the masked message.

## LogFilter

| Field | Rule |
|---|---|
| `appExecutable` | from `--app` via `apps list` (`CFBundleExecutable`); null = all processes |
| `bundleId` | for push/crash presets (system lines mentioning the app) |
| `processes` | names or pids (`--process`), any match |
| `grep` | case-insensitive RegExp on the message |
| `minLevel` | `debug < info < notice < error < fault` |
| `preset` | `none`, `flutter`, `crash` or `push` (rules in research D5) |

Order: preset/app scope → process → level → grep. One entry at a time; nothing is buffered.

## PushDiagnosis

| Field | Rule |
|---|---|
| `entitlement` | installed `aps-environment` or null |
| `appSeen`, `registrationSeen`, `deliverySeen`, `permissionDenied`, `entitlementError` | set by highlighted / matched lines |
| `verdict` / `hint` | first matching rule in research D6 |

Emitted 30 s after the first app line (or after start), and again when the stream ends.

## InstalledAppInfo

From an `apps list` entry: `bundleId`, `name` (display name, else name), `version`, `build`, `executable`,
`entitlements`, `teamId` (`com.apple.developer.team-identifier`, else the prefix of `application-identifier`),
`signer`, `push` (`aps-environment`) and `associatedDomains` (`com.apple.developer.associated-domains`).

Signer classification of `SignerIdentity`:

| `SignerIdentity` | Signer |
|---|---|
| `Apple iPhone OS Application Signing` | `app-store` |
| contains `TestFlight` | `testflight` |
| `Apple Development:` / `iPhone Developer:` | `development` |
| `Apple Distribution:` / `iPhone Distribution:` | `distribution` |
| anything else | `other` |

## CrashReportSummary

| Field | Rule |
|---|---|
| `name` | report file name, e.g. `Runner-2026-11-01-120000.ips` |
| `process` | the name before `-YYYY-MM-DD-HHMMSS` |
| `time` | `YYYY-MM-DDTHH:MM:SS` from the name |
| `exceptionType` | `.ips` body `exception.type` (else null) |
| `signal` | `exception.signal` |
| `frames` | top 5 frames of `threads[faultingThread]`: `usedImages[imageIndex].name` + `symbol` or `+imageOffset` |

## Masker

| Pattern | Replacement |
|---|---|
| `[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}`, `\b[0-9a-f]{40}\b` | `<udid>` |
| `\b[0-9a-fA-F]{64}\b`, `[A-Za-z0-9_-]{11,}:APA91b[A-Za-z0-9_-]{20,}` | `<token>` |
| email addresses | `<email>` |

Disabled by `--show-sensitive`.
