# Data Model: `xcross inspect` report (schemaVersion 1)

Phase 1 output for [plan.md](plan.md). The normative machine contract is
[contracts/inspect.schema.json](contracts/inspect.schema.json); this document explains the entities, rules and
ordering. Decisions are referenced by id from [research.md](research.md).

## Conventions

- Field names are camelCase. Every field listed is always present; "nullable" means its value may be `null`.
- Paths are POSIX, relative to the bundle root (`Frameworks/Flutter.framework/Flutter`). The only exception is
  `bundle.path`, which is relative to the input. No absolute paths are ever written (R9).
- Plist values are mapped as in R3. Dates are ISO-8601 UTC strings ending in `Z`.
- Field order inside each object is the order of the tables below. Arrays are sorted as stated (R9).
- `--normalize` replaces the fields marked **(N)** as described in R10.

## InspectReport (top level)

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | always `1` |
| `normalized` | bool | `true` only with `--normalize` |
| `input` | [InputInfo](#inputinfo) | |
| `bundle` | [BundleInfo](#bundleinfo) | main app bundle |
| `signature` | [BundleSignature](#bundlesignature) | bundle-level summary (R5) |
| `executables` | [ExecutableInfo](#executableinfo)[] | main app and its frameworks/dylibs/extensions; sorted by `path` |
| `profile` | [ProfileSummary](#profilesummary) \| null | from the root `embedded.mobileprovision` |
| `resources` | [Resources](#resources) | main bundle resources |
| `frameworks` | [FrameworkInfo](#frameworkinfo)[] | sorted by `path` |
| `extensions` | [ExtensionInfo](#extensioninfo)[] | `PlugIns/*.appex`; sorted by `path` |
| `issues` | [Issue](#issue)[] | sorted by `path` (null first), then `code` |

Relationships: an executable with role `extension` belongs to the ExtensionInfo with the same bundle path prefix. An
executable with role `framework` belongs to the FrameworkInfo whose `path` is its parent directory. Extension
executables appear in the top-level `executables[]` (paths include `PlugIns/<X>.appex/`).

## InputInfo

| Field | Type | Notes |
|---|---|---|
| `kind` | `"ipa"` \| `"app"` | `.ipa` file or `.app` directory (FR-001) |
| `name` | string | basename only, e.g. `Runner.ipa` |
| `sizeBytes` | int \| null **(N)** | file size for `ipa`; `null` for `app` |
| `sha256` | string \| null **(N)** | lowercase hex of the `.ipa` file; `null` for `app` |

## BundleInfo

| Field | Type | Source / notes |
|---|---|---|
| `path` | string | `Payload/<Name>.app` for `ipa`, `.` for `app` |
| `bundleId` | string \| null | `CFBundleIdentifier` |
| `name` | string \| null | `CFBundleName` |
| `displayName` | string \| null | `CFBundleDisplayName` |
| `shortVersion` | string \| null | `CFBundleShortVersionString` |
| `buildNumber` | string \| null | `CFBundleVersion` |
| `executable` | string \| null | `CFBundleExecutable` |
| `minimumOSVersion` | string \| null | `MinimumOSVersion` |
| `deviceFamily` | int[] | `UIDeviceFamily`, sorted; `[]` if absent |
| `infoPlistFormat` | `"xml"` \| `"binary"` \| null | `null` if Info.plist is missing or unreadable |
| `infoPlistKeys` | string[] | all top-level key names, sorted; values are not reported (R8) |
| `plist` | object | allow-listed keys only, when present: `CFBundleIcons`, `CFBundleIcons~ipad`, `CFBundleIconName`, `CFBundleIconFile`, `UILaunchScreen`, `UILaunchStoryboardName`, `UIBackgroundModes`; keys sorted |
| `xcrossPrivateKeys` | object | `{XCrossEntitlements: bool, XCrossCapabilities: bool, XCrossAppGroups: bool}` (presence only) |

Validation: a missing or unreadable Info.plist does not abort the report. It produces issue
`inspect.info_plist_unreadable` (severity `error`), every value above becomes `null` or `[]`, and executable
discovery falls back to the bundle directory name without `.app`.

## BundleSignature

| Field | Type | Notes |
|---|---|---|
| `present` | bool | `true` exactly when `_CodeSignature/CodeResources` exists at the bundle root (R5) |
| `kind` | `"none"` \| `"adhoc"` \| `"certificate"` | the main executable's signature kind |
| `teamId` | string \| null | the main executable's CodeDirectory team id |

## ExecutableInfo

| Field | Type | Notes |
|---|---|---|
| `path` | string | relative to the main bundle root |
| `role` | `"main"` \| `"framework"` \| `"dylib"` \| `"extension"` | discovered structurally, see below |
| `architectures` | string[] | slice order as in the file (R4 names); `[]` if unreadable |
| `signature` | [ExecutableSignature](#executablesignature) | |
| `entitlements` | object \| null | decoded XML entitlements blob (R6), keys sorted; `null` if none or DER-only |
| `derEntitlementsPresent` | bool | DER entitlements blob present |

Discovery (structural, R4):

| Role | Location |
|---|---|
| `main` | `<CFBundleExecutable>` at the root |
| `framework` | `Frameworks/<X>.framework/<CFBundleExecutable of its Info.plist, else X>` |
| `dylib` | `Frameworks/*.dylib` |
| `extension` | `PlugIns/<X>.appex/<its CFBundleExecutable>` |

A referenced executable that does not exist → issue `inspect.executable_missing`, and no ExecutableInfo is written. An
unreadable Mach-O → issue `inspect.macho_invalid`, and an ExecutableInfo is written with `architectures: []` and
signature kind `none`.

### ExecutableSignature

| Field | Type | Notes |
|---|---|---|
| `kind` | `"none"` \| `"adhoc"` \| `"certificate"` | R5 |
| `linkerSigned` | bool | CodeDirectory flag `0x20000` |
| `identifier` | string \| null | CodeDirectory identifier |
| `teamId` | string \| null | CodeDirectory team id (version ≥ `0x20200`) |

## ProfileSummary

Built from `embedded.mobileprovision` (R7) and redacted by allow-list (R8).

| Field | Type | Notes |
|---|---|---|
| `kind` | `"development"` \| `"ad-hoc"` \| `"app-store"` \| `"enterprise"` | R7 rules |
| `name` | string \| null | `Name` |
| `teamId` | string \| null | first `TeamIdentifier` |
| `uuid` | string \| null **(N)** | `UUID` |
| `creationDate` | string \| null **(N)** | `CreationDate` |
| `expirationDate` | string \| null **(N)** | `ExpirationDate` |
| `platforms` | string[] | `Platform`, sorted |
| `entitlements` | object | `Entitlements`, keys sorted |
| `provisionsAllDevices` | bool | `ProvisionsAllDevices == true` |
| `deviceCount` | int \| null | length of `ProvisionedDevices`; `null` if the key is absent |
| `certificateCount` | int | length of `DeveloperCertificates` |

Never present: device UDIDs, certificate bytes, names or serials, `TeamName`, `AppIDName` (FR-004). An unreadable
profile → `profile: null` plus issue `inspect.profile_unreadable`.

## Resources

| Field | Type | Notes |
|---|---|---|
| `icons` | [Icons](#icons) | |
| `assetsCar` | `{present: bool, sizeBytes: int \| null (N)}` | root `Assets.car`; contents are not parsed in v1 |
| `launchScreen` | [LaunchScreen](#launchscreen) | |
| `storyboards` | string[] | paths of `*.storyboardc` directories, sorted |

### Icons

| Field | Type | Notes |
|---|---|---|
| `iconName` | string \| null | `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName` (asset-catalog icon) |
| `declared` | DeclaredIcon[] | sorted by `set`, then `name` |

DeclaredIcon:

| Field | Type | Notes |
|---|---|---|
| `set` | string | `CFBundleIcons`, `CFBundleIcons~ipad` or `CFBundleIconFile` |
| `name` | string | an entry of `CFBundlePrimaryIcon.CFBundleIconFiles` or the legacy file name |
| `files` | string[] | sorted existing files matching iOS lookup: `<name>[@2x\|@3x][~ipad][.png]` |
| `resolved` | bool | `files` is non-empty |

Issues: no declared icon and no `Assets.car` → `inspect.no_icon`. A declared name with no files →
`inspect.icon_file_missing`.

### LaunchScreen

| Field | Type | Notes |
|---|---|---|
| `kind` | `"UILaunchScreen"` \| `"storyboard"` \| `"none"` | `UILaunchScreen` wins when both are declared (as on iOS) |
| `keys` | string[] | keys of the `UILaunchScreen` dict, sorted; `[]` otherwise |
| `image` | `{name, source}` \| null | from `UIImageName`; `source` is `loose-file`, `asset-catalog` (name not loose, `Assets.car` present; not verified per rendition) or `missing` |
| `storyboard` | `{name, compiledPresent}` \| null | from `UILaunchStoryboardName`; `compiledPresent` = `<name>.storyboardc` exists |

Issues:
- `kind == none` → `inspect.no_launch_screen`
- `kind == UILaunchScreen` with an empty dict (xcross v2.0.9 output) → `inspect.launch_screen_empty`
- `image.source == missing` → `inspect.launch_image_missing`
- `image.source == loose-file` → `inspect.launch_image_not_in_catalog` (warning: proven on device that a loose PNG
  shows no splash)
- `storyboard.compiledPresent == false` → `inspect.launch_storyboard_missing`

## FrameworkInfo

| Field | Type | Notes |
|---|---|---|
| `name` | string | directory or file name, e.g. `Flutter.framework`, `libfoo.dylib` |
| `path` | string | relative path |
| `kind` | `"framework"` \| `"dylib"` | |
| `bundleId` | string \| null | the framework's `CFBundleIdentifier`; `null` for dylibs |

## ExtensionInfo

| Field | Type | Notes |
|---|---|---|
| `path` | string | `PlugIns/<X>.appex` |
| `bundleId` | string \| null | |
| `extensionPoint` | string \| null | `NSExtension.NSExtensionPointIdentifier` |
| `executable` | string \| null | path of its executable (matches an `executables[]` entry) |
| `profile` | ProfileSummary \| null | its own `embedded.mobileprovision` |

## Issue

| Field | Type | Notes |
|---|---|---|
| `code` | string | stable `inspect.*` code ([contracts/cli.md](contracts/cli.md)) |
| `severity` | `"warning"` \| `"error"` | `error` = the report section is incomplete |
| `path` | string \| null | relative path the issue refers to |
| `message` | string | one sentence, no secrets |
| `hint` | string \| null | concrete fix |

A signed bundle (`signature.present`) that still contains `XCrossEntitlements` or `XCrossCapabilities` →
`inspect.xcross_private_keys_in_signed_bundle` (xcross strips both before signing).

## Error document (fatal failure, `--json` only)

`{ "schemaVersion": 1, "error": { "code": "inspect.no_app", "message": "…", "hint": "…" } }`. It is written to
stdout before the process exits with code 1 (R12).

## Example (normalised, fixture `unsigned_v209`, abridged)

```json
{
  "schemaVersion": 1,
  "normalized": true,
  "input": { "kind": "ipa", "name": "unsigned_v209.ipa", "sizeBytes": null, "sha256": null },
  "bundle": {
    "path": "Payload/Runner.app",
    "bundleId": "com.example.fixture",
    "shortVersion": "1.0.0",
    "buildNumber": "1",
    "minimumOSVersion": "13.0",
    "plist": { "UILaunchScreen": {} },
    "xcrossPrivateKeys": { "XCrossEntitlements": false, "XCrossCapabilities": false, "XCrossAppGroups": false }
  },
  "signature": { "present": false, "kind": "none", "teamId": null },
  "profile": null,
  "frameworks": [
    { "name": "App.framework", "path": "Frameworks/App.framework", "kind": "framework", "bundleId": "io.flutter.flutter.app" },
    { "name": "Flutter.framework", "path": "Frameworks/Flutter.framework", "kind": "framework", "bundleId": "io.flutter.flutter" }
  ],
  "issues": [
    { "code": "inspect.launch_screen_empty", "severity": "warning", "path": null, "message": "…", "hint": "…" },
    { "code": "inspect.no_icon", "severity": "warning", "path": null, "message": "…", "hint": "…" }
  ]
}
```
