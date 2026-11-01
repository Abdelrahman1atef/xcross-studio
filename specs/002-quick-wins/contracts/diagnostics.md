# Contract: diagnostics codes for feature 002

User-facing error and warning codes added by 002. Codes are stable: they are never renamed, and new codes may be added.
Errors stop the command (exit code 1) and print:

```text
error: [<code>] <message>
hint: <hint>
```

Warnings go to stderr (the existing `!` warning style) and never change the exit code:

```text
! [<code>] <message>
  hint: <hint>
```

At the end of a Flutter build that printed warnings, one summary line is printed, even when the build fails:

```text
! Build finished with 3 warnings: build.asset_catalog_skipped ×1, build.podspec_only_plugin ×1, build.storyboard_skipped ×1
```

Each distinct warning (same code and same subject) is printed once per build.

## Errors (stop `xcross flutter run` / `xcross compose run` before the build)

| Code | When | Message contains | Hint |
|---|---|---|---|
| `device.ios_unsupported` | device OS major version < 17 | device name, iOS version, required minimum | `Use a device on iOS 17 or later. iOS 16 install and launch support is planned (feature 005).` |
| `device.not_found` | no device found / no device matches `--device-id`/`--udid` | the selector, if given | `Connect the iPhone with a cable, unlock it and tap Trust, then retry (or pass --wifi for a paired wireless device).` |
| `device.host_service_unavailable` | host device service not reachable (USB search, or nothing found) | the address that was tried | Windows: `Install Apple Devices (Microsoft Store) or iTunes and make sure "Apple Mobile Device Service" is running (Administrator PowerShell: Start-Service "Apple Mobile Device Service").` Linux: `Install usbmuxd and start it: sudo systemctl start usbmuxd (and add the udev rules shipped with usbmuxd if the device is not detected).` |
| `device.query_timeout` | device listing did not answer in time | the timed-out command | `Unplug and reconnect the iPhone, unlock it, and retry. If it keeps happening, restart the device service.` |

## Warnings

| Code | Where | Subject | Message contains | Hint |
|---|---|---|---|---|
| `toolchain.path_linker_unusable` | doctor ("Configured PATH" check), and once before a build | PATH entry | the entry and why its `ld64.lld` is unusable | `Remove this directory from environment.PATH in your xcross configuration (xcross config); xcross picks an iOS-capable linker by itself.` |
| `build.podspec_only_plugin` | build: plugin discovery | plugin name | plugin name; native iOS code not included | `Use a plugin version that ships Package.swift (Swift Package Manager), or an override (feature 006).` |
| `build.plugin_manifest_missing` | build: plugin discovery | plugin name | plugin declares native iOS code but has no Package.swift or podspec | `Check the plugin's ios/ or darwin/ folder; its platform channels will not respond at runtime.` |
| `build.asset_catalog_skipped` | build: resource staging | catalog path | catalog path; icons and images inside are not in the app | `Asset catalogs are not compiled yet (feature 004); add loose PNGs plus CFBundleIcons for the app icon meanwhile.` |
| `build.storyboard_skipped` | build: resource staging and Info.plist | storyboard name | storyboard path or Info.plist key; not compiled, left out | `Storyboards cannot be compiled without Xcode; use a UILaunchScreen dictionary in Info.plist instead.` |
| `build.resource_missing` | build: resource staging | resource path | Xcode project lists a resource that does not exist | `Remove the stale reference from the Xcode project or restore the file.` |

## Version line (FR-009)

Printed once per Flutter build as an info line:

```text
Version 1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml
```

The source labels are `--build-name`/`--build-number`, `pubspec.yaml`, `xcconfig`, `project.pbxproj` and `default`.
