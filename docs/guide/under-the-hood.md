# Under the hood

[← xcross README](../../README.md) · [All guides](README.md)

xcross does not wrap or patch `flutter build ios` - that command simply refuses to run off-macOS. Instead, it re-implements the parts of Flutter's toolchain that matter for a device build (debug JIT, profile and release AOT), using the same engine artifacts, the same compilers, and the same device protocols the official tooling uses.

```text
xcross flutter run / build
   ├─ FlutterPacker
   │    ├─ IosEngineCache        download engine artifacts pinned to the SDK's engine hash
   │    ├─ FlutterDebugBundler   frontend_server → app.dill → App.framework (JIT, debug)
   │    ├─ FlutterAotSnapshotter AOT app.dill → gen_snapshot → App.framework/App + dSYM (profile/release)
   │    │    └─ IosGenSnapshotResolver  Flutter's gen_snapshot on macOS, xcross-compilers / xcross_gen_snapshot elsewhere
   │    ├─ Native assets         Dart build hooks → arm64 frameworks + manifest
   │    ├─ SwiftPM plugins       swift build (Darwin SDK) → libFlutterPluginsGenerated.dylib
   │    ├─ RunnerShim            clang / ld64.lld → Runner Mach-O
   │    └─ assemble              Flutter.framework + Info.plist + flutter_assets → .app
   ├─ in-process codesign → install
   └─ CoreDeviceLauncher    RSD tunnel → launch suspended → gdb-remote attach
        └─ HotReloadController   DevFS + VM Service ⇄ frontend_server
```

## 1. Engine artifacts, straight from Flutter's CDN

`IosEngineCache` reads the engine revision from your Flutter SDK (the same hash `flutter` itself pins) and downloads exactly what Flutter's tool would cache: the prebuilt **`Flutter.xcframework`**, the debug **`vm_snapshot_data`** / **`isolate_snapshot_data`** JIT snapshots, the host **`frontend_server`**, and the Flutter **patched Dart SDK**. Your app therefore runs on the *identical* engine binary an Xcode build would embed - xcross never rebuilds or modifies the engine.

## 2. Kernel compilation with `frontend_server`

In debug mode Flutter apps are not compiled to machine code - the Dart VM runs **kernel bytecode** (JIT). `FlutterDebugBundler` drives the same `frontend_server` the Flutter tool uses (against the patched SDK, with your `--dart-define`s and flavor entrypoint) to produce `app.dill`, then lays out `App.framework` exactly like Flutter does:

- `flutter_assets/kernel_blob.bin` - the kernel program
- `flutter_assets/vm_snapshot_data`, `isolate_snapshot_data` - VM heap seeds
- `AssetManifest.bin/json`, `FontManifest.json`, fonts and assets - generated in Dart from your `pubspec.yaml`, replicating Flutter's asset bundling
- The `App.framework` *binary* in a debug build is only a stub - xcross compiles that stub with `clang` targeting `arm64-apple-ios` and writes the framework's `Info.plist` itself.

Because a debug app is pure JIT, no `gen_snapshot` is needed. Profile and release builds instead compile a whole-program AOT kernel and `FlutterAotSnapshotter` lets `gen_snapshot` write `App.framework/App` directly, then extracts its dSYM and strips it, as `flutter build ios` does. `IosGenSnapshotResolver` picks the compiler: the one in your Flutter SDK on macOS, and on Linux and Windows a verified download from the [xcross-compilers](https://github.com/Abdelrahman1atef/xcross-compilers) or [xcross_gen_snapshot](https://github.com/arxdeus/xcross_gen_snapshot) releases (see [Flutter versions and iOS compilers](flutter-versions.md#flutter-versions-and-ios-compilers)).

## 3. Native code without Xcode

- **Darwin SDK** - `darwin_sdk_kit` unpacks `Xcode.xip` with pure-Dart **xar**, **pbzx**, and **cpio** readers and assembles a Swift SDK bundle (iOS sysroot + frameworks) usable by upstream Swift/LLVM on Windows and Linux.
- **Runner** - the `Runner` executable (Flutter's `AppDelegate`/`main` shim) is compiled with `clang` and linked with `ld64.lld`, LLVM's Mach-O linker, against `Flutter.xcframework` from the SDK above.
- **Native assets** - Dart package build hooks run through Flutter's native-assets target with cross-platform Apple tool shims. Their output is thinned to arm64, embedded as frameworks, and recorded in `NativeAssetsManifest.json`.
- **Plugins** - SwiftPM iOS plugins are built with `swift build` against the same SDK into a single `libFlutterPluginsGenerated.dylib`, with a generated registrant mirroring Flutter's `GeneratedPluginRegistrant`. A Mach-O rewriter fixes install names and rpaths so the dylibs resolve inside the `.app` bundle.
- <!-- studio: 004 --> **Asset catalogs** - `Assets.xcassets` is compiled to `Assets.car` in pure Dart (a port of [AssetKit](https://github.com/xtool-org/AssetKit)): image sets, colour sets and the app icon, plus the loose icon PNGs SpringBoard falls back to. A `LaunchScreen.storyboard` with a colour and one image view is compiled by xcross itself into `LaunchScreen.storyboardc`, with the logo shipped as loose PNGs; a storyboard with more in it becomes a `UILaunchScreen` (its background colour and centred image), and the rest is reported as `build.launch_screen_approximated` (`XCROSS_LAUNCH_STORYBOARD=off` forces the `UILaunchScreen`). iOS caches launch screens: delete the app and reboot to see a changed one.

## 4. Signing and device install, natively

`apple_developer_kit` implements Apple's **GrandSlam** login (with ADI machine attestation via the Android libraries), Developer Services provisioning (certificates, device registration, provisioning profiles), and **in-process Mach-O code signing** - no `codesign`, no `ldid`. Installation goes over the standard device protocols via `pymobiledevice3`.

## 5. iOS 17+ CoreDevice launch

iOS 17 replaced the old debug-launch path with **CoreDevice** over an encrypted **RSD tunnel**. `xcross tunnel` mounts the Developer Disk Image and brings the tunnel up; `CoreDeviceLauncher` then launches the app **suspended**, attaches a minimal **gdb-remote** client (the same protocol `debugserver` speaks) to resume and supervise the process, and port-forwards the **Dart VM Service** from the phone to localhost.

## 6. Hot reload: a faithful DevFS reimplementation

Hot reload is pure Flutter-internals territory, reimplemented protocol-for-protocol:

1. A long-lived `frontend_server` session (from `frontend_server_kit`) holds incremental compile state; a file watcher tracks your `lib/`.
2. On `r`, changed files are recompiled to an **incremental dill**, which is gzip-uploaded to the device via the VM Service's HTTP **DevFS** endpoint (`_createDevFS` + `PUT` - the same `org-dartlang-devfs://` filesystem Flutter's tool uses).
3. xcross calls `reloadSources` on the root isolate, then triggers `ext.flutter.reassemble` so the widget tree rebuilds.
4. `R` (hot restart) resets the compiler, uploads a full dill, and re-runs the app in each `FlutterView` via `_flutter.listViews` / run-in-view - matching Flutter's hot restart semantics.
5. The `frontend_server` is also registered as the VM Service's **expression compiler**, so debugger watch/evaluate works on-device.

## 7. IDE debugging via DAP

`xcross_dap` implements a **Debug Adapter Protocol** server that routes launch/attach, breakpoints, stepping, and hot-reload requests to the same VM Service connection. VS Code reaches it through a shim that intercepts launch configs marked with `"env": { "XCROSS": "true" }` (everything else falls through to Flutter's own adapter); JetBrains IDEs reach it through an LSP4IJ DAP run configuration.
