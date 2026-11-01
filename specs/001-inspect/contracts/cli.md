# CLI contract: `xcross inspect`

Command-line interface for feature 001. JSON output follows [inspect.schema.json](inspect.schema.json); entities are
explained in [../data-model.md](../data-model.md).

## Synopsis

```text
xcross inspect <path> [--json] [--normalize]
```

| Argument / flag | Meaning |
|---|---|
| `<path>` | an `.ipa` file or a `.app` directory (required, exactly one) |
| `--json` | print one JSON document (schema v1) to stdout instead of the human summary |
| `--normalize` | replace volatile fields with stable placeholders (research R10); only valid with `--json` |
| `-h, --help` | standard `package:args` help |

The input is classified by kind, not by its name alone. A directory whose name ends in `.app` → `app`. A regular file
that is a zip archive whose name ends in `.ipa` → `ipa`. Anything else → `inspect.unsupported_input`.

## Behaviour guarantees

- **Read-only (FR-006)**: never writes, renames or touches the input; no network; no device access; no temp files.
- **Determinism (FR-007)**: for the same input bytes, `--json` output is byte-identical on Windows, Linux and macOS:
  ASCII only, LF line endings, one trailing newline, fixed field order (research R9).
- **Clean stdout**: with `--json`, stdout contains only the JSON document. The xcross credits banner and update hint
  are suppressed (`ownsMachineStdout`), and diagnostics never go to stdout.
- **Privacy (FR-004)**: output never contains device UDIDs, certificate data, private keys, API keys or Apple account
  identifiers other than the team id (research R8).

## Exit codes

| Code | When | stdout | stderr |
|---|---|---|---|
| `0` | report produced; it may contain `issues[]` | report (JSON or summary) | nothing |
| `1` | fatal failure (table below) | `--json`: error document; otherwise nothing | `error: [<code>] <message>` + `hint: <hint>` |
| `64` | usage error: missing or extra arguments, unknown flag, `--normalize` without `--json` | nothing | usage message |

## Fatal error codes (exit 1)

| Code | Condition | Hint |
|---|---|---|
| `inspect.input_not_found` | `<path>` does not exist | Check the path; for a build output use `build/xcross-ios/<name>.ipa`. |
| `inspect.unsupported_input` | not an `.ipa` file and not a `.app` directory | Pass an `.ipa` file or a `.app` bundle directory. |
| `inspect.corrupt_archive` | the `.ipa` cannot be read as a zip (bad central directory or truncated) | Rebuild or re-download the IPA. |
| `inspect.no_app` | no `Payload/<X>.app/` in the IPA | The IPA must contain exactly one app under `Payload/`. |
| `inspect.multiple_apps` | more than one `Payload/<X>.app/` | Repackage with a single app under `Payload/`. |

## Issue codes (in `issues[]`, exit 0)

Severity `error` means that section of the report is incomplete; `warning` flags a likely problem in the app.

| Code | Severity | Condition | Hint (summary) |
|---|---|---|---|
| `inspect.info_plist_unreadable` | error | the bundle's Info.plist is missing or cannot be parsed | Check `ios/Runner/Info.plist`; rebuild. |
| `inspect.plist_unreadable` | error | a nested Info.plist (framework or extension) cannot be parsed | Rebuild the framework or extension. |
| `inspect.executable_missing` | error | the `CFBundleExecutable` file does not exist | Rebuild; check that the build did not skip the binary. |
| `inspect.macho_invalid` | error | the executable is truncated or not a Mach-O file | Rebuild; the file is damaged. |
| `inspect.signature_invalid` | error | `LC_CODE_SIGNATURE` points to a malformed SuperBlob | Re-sign the app. |
| `inspect.entitlements_unreadable` | error | the entitlements blob is not a valid plist | Re-sign with a valid entitlements file. |
| `inspect.entitlements_der_only` | warning | only DER entitlements are present; values not decoded in v1 | Re-sign with a signer that writes XML entitlements too. |
| `inspect.profile_unreadable` | error | `embedded.mobileprovision` is not a readable CMS profile | Re-download the profile and re-sign. |
| `inspect.symlink_skipped` | warning | a symbolic link inside a `.app` directory was not followed | iOS bundles should not contain symlinks; copy the target instead. |
| `inspect.no_icon` | warning | no `CFBundleIcons`/`CFBundleIconFile` and no `Assets.car` | Add icons (feature 004) or loose PNGs plus `CFBundleIcons`. |
| `inspect.icon_file_missing` | warning | a declared icon name matches no file | Ship `<name>@2x.png` / `<name>@3x.png` in the bundle root. |
| `inspect.no_launch_screen` | warning | neither `UILaunchScreen` nor `UILaunchStoryboardName` | Add a `UILaunchScreen` dict (feature 004). |
| `inspect.launch_screen_empty` | warning | `UILaunchScreen` is an empty dict (xcross v2.0.9 default) | Provide `UIImageName`/`UIColorName` from an asset catalog (feature 004). |
| `inspect.launch_image_missing` | warning | `UIImageName` resolves to no file and there is no `Assets.car` | Add the image to the asset catalog. |
| `inspect.launch_image_not_in_catalog` | warning | `UIImageName` resolves only to a loose PNG | iOS does not show loose PNGs as a launch image; put it in `Assets.car`. |
| `inspect.launch_storyboard_missing` | warning | `UILaunchStoryboardName` has no compiled `.storyboardc` | Storyboards are not compiled off-Mac; use `UILaunchScreen`. |
| `inspect.xcross_private_keys_in_signed_bundle` | warning | a signed bundle still has `XCrossEntitlements` or `XCrossCapabilities` | Re-sign with xcross; these build-time keys should be stripped. |

New codes may be added in later versions (additive). Existing codes are never renamed.

## Human summary (default output, AC-001-7)

Layout (✔ = present/OK, ✖ = missing/problem). Values in angle brackets are filled from the report:

```text
<input name>  <bundleId> <shortVersion> (<buildNumber>), iOS <minimumOSVersion>+
✔ signed               adhoc · team <teamId>             | ✖ signed  not signed (no _CodeSignature)
✔ provisioning profile development · team <teamId> · <deviceCount> devices | ✖ provisioning profile  none
✔ push entitlement     aps-environment = development    | ✖ push entitlement  missing (profile grants it)
✔ associated domains   2 domains                         | ✖ associated domains  none
✔ icon                 AppIcon60x60 (2 files)            | ✖ icon  none
✔ launch screen        UILaunchScreen · image in Assets.car | ✖ launch screen  UILaunchScreen is empty
✔ frameworks           5 (App, Flutter, …)
<n> issues — run with --json for details
```

The summary never shows UDIDs, certificate names, profile UUIDs or Info.plist values outside the allow-list. Its exact
spacing is not a stable interface; scripts must use `--json`.

## Examples

```text
$ xcross inspect build/xcross-ios/app.ipa --json > report.json        # exit 0
$ xcross inspect build/xcross-ios/app.ipa --json --normalize          # golden-test form
$ xcross inspect build/xcross-ios/Runner.app                          # human summary of a signed .app after `flutter run`
$ xcross inspect missing.ipa --json                                   # exit 1
{
  "schemaVersion": 1,
  "error": {
    "code": "inspect.input_not_found",
    "message": "missing.ipa does not exist.",
    "hint": "Check the path; for a build output use build/xcross-ios/<name>.ipa."
  }
}
```
