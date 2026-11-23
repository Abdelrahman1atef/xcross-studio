# Flutter plugins

[← xcross README](../../README.md) · [All guides](README.md)

Swift Package Manager iOS plugins work on both Windows and Linux. Their native code is compiled against the extracted Darwin SDK into `Frameworks/libFlutterPluginsGenerated.dylib` and registered by the generated runner.

## Plugins that use CocoaPods

With the CocoaPods pod converter (feature 046), xcross compiles plugins that depend on CocoaPods pods on Windows and Linux without running CocoaPods, Ruby, or Xcode.

Each pod is fetched from the CocoaPods CDN, converted into a local Swift package under `.dart_tool/xcross/Packages/pod-<Pod>`, and integrated directly into SwiftPM compilation:
- **Binary pods** (`binary`): Vendor `.xcframework` archives, legacy `.framework` bundles (converted to xcframeworks), and static `.a` libraries with header trees.
- **Source pods** (`objc`, `swift`, `mixed`): C, Objective-C, Objective-C++, and Swift sources with automatic header trees, synthetic umbrella headers, module maps, and language standard configuration.
- **Dependency resolution**: Parses `ios/Podfile.lock` or uses the built-in backtracking resolver against CDN specs, writing `ios/xcross-pods.lock` when no `Podfile.lock` is present.
- **Gating & switches**: Enable with `XCROSS_POD_CONVERTER=on`. Fine-tune enabled kinds with `XCROSS_POD_KINDS=binary,objc,swift,mixed` or exclude specific pods with `XCROSS_POD_SKIP=pod1,pod2`.
- **Automatic fallback**: If a converted pod fails compiling or linking during development, xcross logs a 4-part warning and rebuilds once with that pod excluded so the rest of your app continues running. Strict mode (`--strict`) and distribution builds fail immediately to guarantee full integrity.

### Inspecting and Reporting Pods

```sh
xcross plugin status --json          # View converted pods and their resolution source
xcross pods report [<Pod>] [--json]  # View redacted diagnostic reports for left-out pods
xcross cache clear pods              # Clear cached pod downloads and converted packages
```

### Troubleshooting Diagnostic Codes

| Code | Explanation | Recommended Action |
|---|---|---|
| `pod.resolve_conflict` | No version satisfies all plugin constraints | Align plugin versions in `pubspec.yaml` or run `pod update` on macOS. |
| `pod.lock_stale` | `Podfile.lock` pin no longer matches constraints | Refresh lockfile or delete `ios/Podfile.lock` to resolve afresh. |
| `pod.download_failed` | Failed to download pod source archive or git repo | Check network connection, proxies, or ensure Git is installed. |
| `pod.no_slice` | Binary framework missing slice for active build target | Build for arm64 iOS device instead of simulator if slice is missing. |
| `pod.bitcode` | Dynamic framework contains deprecated Bitcode | Update to a modern version of the pod built without Bitcode. |
| `pod.swift_binary_incompatible` | Swift binary lacks `.swiftinterface` | Request vendor build with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`. |
| `pod.duplicate_with_swift_package` | Converted pod collides with a Swift package dependency | Prefer the official Swift package. |
| `pod.duplicate_symbols` | Duplicate symbols between colliding libraries | Exclude redundant dependencies or report the conflict. |
| `pod.compile_failed` | SwiftPM failed compiling converted pod sources | Inspect compiler output or submit diagnostic report. |
| `pod.converter_off` | Pod requires converter but `XCROSS_POD_CONVERTER` is off | Set `XCROSS_POD_CONVERTER=on`. |


<!-- studio: 006 -->
## Plugin overrides

A build drafts the `Package.swift` of a plugin that only ships a podspec, into `xcross_overrides/<plugin>/<version>/`
in the project, and says so with `[build.plugin_drafted]`. Review it and commit it. A plugin needing a pod with no known
Swift package is left out and named by `[build.plugin_unknown_pods]`. See what a build will do without compiling:
`xcross plugin check`. `XCROSS_PLUGIN_DRAFTS=off` turns drafting off.

Give xcross your own `Package.swift` for a plugin: for one that only ships a podspec, or one whose manifest does not
build. Put it in the project (or in `~/.xcross/overrides/` for all projects):

```text
my_app/xcross_overrides/
  some_plugin/
    Package.swift          # any version of some_plugin
    override.yaml          # optional: versions: ">=1.2.0 <2.0.0"
    1.4.0/Package.swift    # only for some_plugin 1.4.0 (wins over the folder above)
```

xcross searches `xcross_overrides/<plugin>/<version>/`, then `xcross_overrides/<plugin>/`, then the same two under
`~/.xcross/overrides/`. The override's files are laid over a staged copy of the plugin's `ios/` (or `darwin/`) folder,
which becomes the Swift package root, so targets can point at the plugin's own sources. The pub cache is never touched.

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "some_plugin",
    platforms: [.iOS("13.0")],
    products: [.library(name: "some-plugin", targets: ["some_plugin"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "some_plugin",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")],
            path: "Classes",
            publicHeadersPath: "include"
        )
    ]
)
```

Let xcross draft the `Package.swift` from the plugin's podspec, then review it:

```sh
xcross plugin list                  # ✖ marks podspec-only plugins
xcross plugin shim some_plugin      # writes xcross_overrides/some_plugin/<version>/Package.swift
```

The draft maps common pods (Google Maps, Firebase, Pusher, Alamofire, SDWebImage, Kingfisher) to their Swift packages,
splits mixed Swift/Objective-C sources into two targets, copies in a privacy manifest kept outside the source folder, and
prints what still needs a human (unknown pods, other resources outside the source folder).

The build reports `build.plugin_override_applied` for each override it uses, and `build.plugin_override_invalid` for a
folder it skips (no `Package.swift`, bad `override.yaml`, other plugin versions). See
[specs/006-plugin-overrides](../../specs/006-plugin-overrides/spec.md).

<!-- studio: 007, 016 -->
