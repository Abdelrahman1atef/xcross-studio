# CLI contract: device logs, app info, crashes

JSON shapes: [devicelog.schema.json](devicelog.schema.json).

All commands are read-only toward the device and work over plain usbmux (USB) on iOS 16 and 17+, on Windows and
Linux, with no tunnel, no DeveloperDiskImage and no elevation.

## `xcross logs`

```text
xcross logs [--udid <id>] [--app <bundle-id>] [--process <name|pid>]... [--grep <regex>]
            [--level debug|info|notice|error|fault] [--preset push|crash|flutter]
            [--save <file>] [--json] [--duration <seconds>] [--show-sensitive]
```

| Option | Meaning |
|---|---|
| `--app` | only the app's process (by its `CFBundleExecutable`); attaches when it starts and re-attaches after relaunch |
| `--process` | process name or pid, repeatable |
| `--grep` | case-insensitive regex on the message |
| `--level` | minimum level |
| `--preset` | `flutter`: Dart output only, without the `flutter: ` prefix. `crash`: crash-related lines. `push`: push-related lines plus a diagnosis. `crash` and `push` need `--app`. |
| `--save` | also write the rendered lines to a file |
| `--json` | NDJSON events on stdout |
| `--duration` | stop after N seconds; otherwise run until Ctrl+C |
| `--show-sensitive` | do not mask UDIDs, tokens and emails |

**Human line format**: `HH:MM:SS.mmm process[pid] L message`, where L is `D`, `I`, `N`, `E` or `F`, with a `★` prefix
for highlighted push lines.

## `xcross app info <bundle-id>`

Options: `[--udid <id>] [--json] [--show-sensitive]`.

```text
<name> (<bundle-id>) <version> (<build>)
signer: development · team <TEAMID>
✔ push entitlement     aps-environment = development
✖ associated domains   none
entitlements:
  application-identifier: TEAMID.com.example.app
  …
```

Signer types are `app-store`, `testflight`, `development`, `distribution` (ad-hoc or enterprise) and `other`. The raw
signer identity is shown only with `--show-sensitive`.

## `xcross crashes`

```text
xcross crashes list [--udid <id>] [--app <bundle-id>] [--json]
xcross crashes pull (<name> | --latest) [--udid <id>] [--app <bundle-id>] [--out <dir>]
```

- **list**: newest first, showing process, date and exception type.
- **pull**: saves the report to `--out` (default `./crash-reports`) and prints the exception type, the signal and the
  faulting thread's top frames.

## `xcross devices` and `xcross app list` (feature 008)

```text
xcross devices [--json]
xcross app list [--udid <id>] [--json]
```

- **devices**: the iPhones connected by USB (`device` events: `udid`, `name`, `osVersion`, `connection`). Human form:
  `<name>  iOS <version>  <udid>`. No devices → no events (human: "No iPhone is connected by USB.").
- **app list**: the user apps installed on the iPhone, sorted by bundle id (`app` events: `bundleId`, `name`,
  `version`, `build`, `executable`). Human form: `<bundle-id>  <name>  <version>`.

## Exit codes

| Code | When |
|---|---|
| 0 | success (including Ctrl+C or `--duration` ending `logs`) |
| 1 | coded error (below) |
| 64 | usage error (for example `--preset push` without `--app`) |

## Error codes

| Code | When | Hint |
|---|---|---|
| `device.not_found` | no USB device, or `--udid` matches none | the 002 hint |
| `device.host_service_unavailable` | usbmuxd / Apple Mobile Device Service unreachable | the 002 host-specific hint |
| `device.select_required` | several USB devices and no `--udid` | Pass --udid <id> to pick one (list them with: pymobiledevice3 usbmux list). |
| `device.not_trusted` | device locked, or this computer not trusted | Unlock the iPhone and tap Trust on "Trust This Computer?", then retry. |
| `app.not_installed` | `--app` / `app info` bundle id not installed | Check the bundle id with `xcross app info` on an installed app, or install the app first. |
| `crash.not_found` | `crashes pull` name not on the device / no crash for `--app` | Run `xcross crashes list` to see available reports. |
