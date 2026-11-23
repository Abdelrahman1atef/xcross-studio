# Command reference

[← xcross README](../../README.md) · [All guides](README.md)

| Command | Description |
|---|---|
| `xcross setup` | Install host dependencies: apt/dnf/pacman or Homebrew packages, `pipx`, and `pymobiledevice3` (Linux/macOS need Swift on `PATH` first). On Windows, or when `setup:` is configured, runs a setup script after showing its name, URL, and SHA-256 and asking first (`--yes` skips the prompt) |
| `xcross config` | Interactively create or edit executable overrides, Swift/LLVM toolchain directories, roots, and child-environment paths |
| `xcross config show` / `validate` | Print the selected YAML configuration or validate all configured paths |
| `xcross sdk install <Xcode.xip>` | Extract a private Darwin Swift SDK from an Xcode archive, patched against the Swift toolchain currently on `PATH` |
| `xcross sdk clean` | Remove the installed Darwin Swift SDK and any leftover backup or staging copies |
| `xcross flutter precache [--mode debug\|profile\|release\|all]` | Download the iOS engine artifacts and, for profile and release, the iOS AOT compiler for the current Flutter SDK, so CI images and offline machines build without the network |
| `xcross cache prune [--dry-run] [--older-than <days>]` | Remove cached Flutter engine artifacts and AOT compilers for engines no discoverable Flutter SDK uses and that went unused for `--older-than` days (default 30) |
| `xcross auth` | Save Apple ID or App Store Connect credentials |
| `xcross auth status` | Show how you signed in and what each kind of build uses, offline |
| `xcross auth clean` | Delete saved credentials, sessions, and signing material |
| `xcross tunnel` | Mount the Developer Disk Image + start the iOS 17+ RSD tunnel over USB |
| `xcross tunnel --wifi` | Prepare wireless pairing, reconnect or advertise pair-host, mount DDI, and open the Wi-Fi RSD tunnel |
| `xcross flutter run` | Build → sign → install → launch → hot reload |
| `xcross flutter build --release` | Build an ahead-of-time compiled `.app` or `.ipa` (also `--profile`) |
| `xcross flutter doctor` | Read-only check of the Flutter project, Swift/LLVM iOS toolchain, Darwin SDK, authentication, and devices |
| `xcross compose setup` | Install Kotlin/Compose iOS cross-build helpers |
| `xcross compose doctor` | Read-only check of the Gradle project, Kotlin/Native, JDK 21+, Gradle, swiftc, clang, Darwin SDK, `ld64.lld`, authentication, and devices |
| `xcross compose build` | Build a KMP iOS framework or `.app` from the current Gradle project |
| `xcross compose run -d <device>` | Build, sign, install, and launch a runnable KMP iOS app |
| `xcross compose run --watch` | Same, plus `r` to rebuild + reinstall + relaunch (Compose has no in-place reload) |
| `xcross flutter clean` | Clear this Flutter project's xcross native asset and SwiftPM build caches (device and simulator) |
| `xcross compose clean` | Clear this Compose project's xcross build output and Kotlin/Native caches (device and simulator) |
| `xcross flutter dap` | Run the Debug Adapter Protocol server (used by IDEs) |
| `xcross ide vscode` | Upsert `.vscode/*` for Run & Debug / Hot Reload |
| `xcross ide idea` | Write a JetBrains DAP run configuration (needs LSP4IJ) |
| `xcross update` | Update xcross to the latest release, verified against its checksums |
| `xcross completion` | Print a shell-completion script |
| `xcross sign <ipa\|app> [-o <out.ipa>] [--udid <id>]... [--bundle-id <id>]` | <!-- studio: --> Re-sign any app with your Apple ID or App Store Connect key and write an installable `.ipa` (nothing is installed; `--udid` adds testers' devices). Install it later with `xcross install --no-resign` or any tool |
| `xcross install <ipa\|app> [--udid <id>] [--ddi <dir>]` | <!-- studio: --> Sign any app with your Apple ID and install it on the iPhone (iOS 15+); iOS 15/16 open via your own developer disk image or from the icon |
| `xcross logs [--app <bundle-id>] [--preset push\|crash\|flutter] [--json]` | <!-- studio: --> Live iPhone log over USB (iOS 16 and 17+), with filters, presets, `--save`, NDJSON. XCross Studio fork addition |
| `xcross app info <bundle-id>` | <!-- studio: --> Installed app's version, signer type, team and entitlements as installed (push / associated domains ✔/✖) |
| `xcross crashes list\|pull` | <!-- studio: --> List crash reports on the iPhone and pull one with its exception summary |
| `xcross devices [--json] [--watch]` | <!-- studio: --> List the iPhones connected by USB with their iOS version (used by the XCross Studio GUI); `--watch` keeps running and reports the list again on every plug, unplug or device service restart (studio: 017) |
| `xcross app list [--json]` | <!-- studio: --> List the apps you installed on the iPhone (used by the GUI's app picker) |
| `xcross plugin list` / `xcross plugin shim <plugin>` | <!-- studio: --> Show how each iOS plugin is built; draft a `Package.swift` override from a podspec-only plugin's podspec |
| `xcross inspect <ipa\|app> [--json] [--normalize]` | <!-- studio: --> Read-only report of what is inside an `.ipa` or `.app`: Info.plist, entitlements per Mach-O, provisioning profile summary, icons, launch screen, frameworks and extensions. XCross Studio fork addition |
| `xcross flutter sdk list \| install <version> \| use <version\|path> \| auto \| reset` | <!-- studio: 014 --> Flutter SDKs for iOS builds only: list them, install one, select one (or your own folder), pick the nearest with an iOS compiler, or go back to your own Flutter ([details](flutter-versions.md#flutter-versions-and-ios-compilers)) |
| `xcross plugin check` / `plugin status [--json]` | <!-- studio: --> What a build will do with each iOS plugin (SwiftPM, drafted, converted pods, left out) without compiling |
| `xcross pods report [<Pod>] [--json]` / `cache clear pods` | <!-- studio: 046 --> Redacted reports for pods a build left out; clear cached pod downloads and converted packages |
| `xcross release preflight [--json]` | <!-- studio: --> App Store problems the project already shows (icon alpha, purpose strings, privacy manifest, export compliance), in seconds and before compiling |
| `xcross privacy init` | <!-- studio: --> Write `ios/Runner/PrivacyInfo.xcprivacy` and add it to the Runner target, without Xcode |
| `xcross icons generate\|check` / `xcross splash generate\|check` | <!-- studio: 023, 024 --> App icons and splash screens for every size from one image ([App Store builds](app-store.md)) |
| `xcross engine info --json` | <!-- studio: 008 --> Which engine and protocol version a GUI is talking to |

<details>
<summary><b><code>xcross flutter run</code> options</b></summary>

```text
-t, --target <path>          entrypoint (default: lib/main.dart)
-D, --dart-define k=v        repeatable
    --dart-define-from-file  .json / .env, repeatable
    --[no-]pub               run flutter pub get first (default: on)
    --build-name             CFBundleShortVersionString
    --build-number           CFBundleVersion
    --flavor                 flavor entrypoint selection
-i, --ipa                    package an .ipa instead of an .app
-d, --device-id              device id or name
-u, --udid                   device UDID; wins if both selectors are set
    --usb / --wifi           search USB-attached or wireless devices only
    --device-connection      attached | wireless | both
    --route
-a, --dart-entrypoint-args   repeatable
-v, --verbose
```
</details>

<!-- studio: XCross Studio feature 001 (specs/001-inspect) -->
<details>
<summary><b><code>xcross inspect</code> options</b></summary>

```text
<path>           an .ipa file or a .app directory
    --json       print one JSON document (schema: specs/001-inspect/contracts/inspect.schema.json)
    --normalize  with --json: replace hashes, sizes, profile UUIDs and dates with
                 stable placeholders so two builds of the same source compare equal
```

Exit codes: `0` report printed (problems are listed as issues), `1` the input cannot be inspected (stable
`inspect.*` error code; with `--json` an error document is printed), `64` usage error. The command never modifies the
input and never contacts the network or a device.

<!-- studio: 002 -->
**Diagnostics codes:** errors and warnings from the fork carry stable codes such as `device.ios_unsupported`,
`toolchain.path_linker_unusable` or `build.asset_unsupported`, each followed by a `hint:` line; see
`specs/002-quick-wins/contracts/diagnostics.md`. Bundle versions come from `--build-name`/`--build-number`, then
`pubspec.yaml`, then the xcconfig, then the Xcode project, then 1.0.0 (1).

**Reporting a bug:** attach the output of `xcross inspect <ipa> --json --normalize`. By design it contains no device
UDIDs, certificate data, API keys or Info.plist values outside a short allow-list, and no absolute paths.
</details>

<!-- studio: 008 -->
