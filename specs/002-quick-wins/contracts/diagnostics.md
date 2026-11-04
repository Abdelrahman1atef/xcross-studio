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
| `sign.output_invalid` (011) | `xcross sign` | output path | `-o` is not an `.ipa` path or would overwrite the input | `Pass -o <file>.ipa, a path that is not the input file.` |
| `sign.no_device` (011) | `xcross sign` | — | the team has no registered device to sign for | `Connect the iPhone by USB (or pass --udid <id>) once, so it is registered on your team; the profile then covers it.` |
| `sign.verify_failed` (011) | `xcross sign`, after writing | output | what the inspector found (unsigned executable, no profile, leftover keys) | `Run xcross inspect on the input and report the problem with its output.` |
| `sign.encrypted_app` (011, warning) | `xcross sign` | app | `SC_Info` present | `App Store downloads are encrypted for one Apple ID; re-signed they install but do not start. Use a decrypted or self-built IPA.` |
| `build.podspec_only_plugin` | build: plugin discovery | plugin name | plugin name; native iOS code not included | `Use a plugin version that ships Package.swift (Swift Package Manager), or add your own: xcross_overrides/<plugin>/Package.swift in the project (see "Plugin overrides" in the README).` (changed by 006; override codes: [006 spec](../../006-plugin-overrides/spec.md#codes)) |
| `build.plugin_manifest_missing` | build: plugin discovery | plugin name | plugin declares native iOS code but has no Package.swift or podspec | `Check the plugin's ios/ or darwin/ folder; its platform channels will not respond at runtime.` |
| `build.asset_catalog_skipped` | build: asset catalog compile (004: only when the compiler fails) | catalog path | catalog path and the reason; icons and images inside are not in the app | `The catalog could not be compiled (see the message); fix or remove the asset it names. Loose PNGs plus CFBundleIcons in Info.plist still give the app an icon.` |
| `build.asset_unsupported` (004) | build: asset catalog compile | `<asset>/<file>` or asset name | asset kind or source format that is not compiled | `Use PNG (or JPEG) images at 1x/2x/3x, colour sets with explicit components, and one app icon set; other asset types are left out.` |
| `build.asset_invalid` (004) | build: asset catalog compile | `<asset>/<file>` or asset name | missing file, bad Contents.json or unreadable image | `Fix the file or its Contents.json entry (open the catalog in an editor or re-export the image); the rest of the catalog is compiled.` |
| `build.launch_screen_approximated` (004) | build: launch storyboard → UILaunchScreen | storyboard name | the elements UILaunchScreen cannot show | `Without Xcode the launch storyboard becomes a UILaunchScreen: one background colour and one centred image from the asset catalog. Move the rest into the first Flutter frame.` |
| `build.launch_screen_unreadable` (004) | build: launch storyboard → UILaunchScreen | storyboard name | storyboard path and the parse error | `Fix the storyboard XML, or add a UILaunchScreen dictionary to Info.plist yourself; the app starts with a blank launch screen.` |
| `build.storyboard_skipped` | build: resource staging and Info.plist | storyboard name | storyboard path or Info.plist key; not compiled, left out | `Storyboards cannot be compiled without Xcode; use a UILaunchScreen dictionary in Info.plist instead.` |
| `build.resource_missing` | build: resource staging | resource path | Xcode project lists a resource that does not exist | `Remove the stale reference from the Xcode project or restore the file.` |
| `build.runner_project_failed` (007) | build: link, `XCROSS_RUNNER=project` | `Runner` | why the project's Runner sources were not used (no sources, or the compiler's first errors); the generic runner is used | `Fix the error in ios/Runner, or unset XCROSS_RUNNER to build with the generic runner on purpose; until then AppDelegate code does not run.` |
| `build.runner_scene_delegate_replaced` (007) | build: link, `XCROSS_RUNNER=project` | `Runner` | the project's SceneDelegate has code that does not run | `Move that code to AppDelegate (or a plugin); without Xcode the window cannot come from Main.storyboard, so xcross supplies the scene delegate.` |

## Version line (FR-009)

Printed once per Flutter build as an info line:

```text
Version 1.0.7 (7) · name: pubspec.yaml · number: pubspec.yaml
```

The source labels are `--build-name`/`--build-number`, `pubspec.yaml`, `xcconfig`, `project.pbxproj` and `default`.
