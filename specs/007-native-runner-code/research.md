# Research: how the Runner is built today, and how to build the project's own

## How xcross builds `Runner` today

- `FlutterArtifactLinker._buildRunnerBinary` calls `RunnerShim.buildRunnerBinary`
  (`packages/xcross/lib/src/shared/flutter/build/runner_shim.dart`).
  - The shim writes an embedded Objective-C `Runner.m` containing:
    - `AppDelegate : FlutterAppDelegate <FlutterImplicitEngineDelegate>`, which registers plugins in
      `didInitializeImplicitFlutterEngine`;
    - `SceneDelegate : FlutterSceneDelegate`, which creates `FlutterViewController` and the `UIWindow` in code;
    - `main()`, which calls `UIApplicationMain(…, @"AppDelegate")`.
  - **Compile:** the Darwin clang (`toolchain.resolveDarwinClang`) with
    `-target <triple> -isysroot <iPhoneOS.sdk> -F <SubFrameworks> -F <engine slice> -fobjc-arc`.
  - **Link:** `ld64.lld` with `-platform_version`, `-syslibroot`, Flutter/UIKit/Foundation, the plugins dylib,
    native-asset frameworks (`-needed_framework`) and `-rpath @executable_path/Frameworks`.
- **Plugins:** they are built by the SwiftPM driver as one Swift package (`FlutterPluginsGenerated`). Its registrant
  is exported as the C symbol `XcrossRegisterGeneratedPlugins` (`@_cdecl`, `swiftpm/manifest.dart`). There is no
  CocoaPods build, so Flutter's `GeneratedPluginRegistrant.m`, which imports each plugin's Objective-C headers,
  cannot be compiled.
- **Info.plist** (`FlutterBundleAssembler._writeInfoPlist`):
  - `InfoPlist.applySceneLifecycle` forces a scene configuration whose `UISceneDelegateClassName` is `SceneDelegate`,
    with no storyboard.
  - `normalizeObjCClassNames` strips module prefixes, because the shim's classes are unqualified Objective-C classes.
- **Swift for iOS** is already compiled with the host `swiftc` (Swift toolchain on PATH) in two places:
  `AppExtensionBuilder` (Flutter app extensions) and `SwiftRunnerBuilder` (Compose). Both use:
  - `-sdk <iPhoneOS.sdk> -target <triple>` and `-resource-dir` set to the Darwin SDK's own Swift resources;
  - `-use-ld=<ld64.lld>`, with `-arch` and `-platform_version` passed explicitly through `-Xlinker`;
  - the SDK's `libclang_rt.ios.a`, plus `-F <engine slice>` and `-I <plugin modules>`.

## The Flutter template (3.47)

- The Runner target's Sources are `AppDelegate.swift`, `SceneDelegate.swift` and `GeneratedPluginRegistrant.m`.
  `SWIFT_OBJC_BRIDGING_HEADER` is `Runner/Runner-Bridging-Header.h` (`#import "GeneratedPluginRegistrant.h"`).
- `AppDelegate` is `@main @objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate` and registers
  plugins in `didInitializeImplicitFlutterEngine`. Older apps instead use `@UIApplicationMain` and call
  `GeneratedPluginRegistrant.register(with: self)` in `didFinishLaunching`.
- `SceneDelegate` is empty: `class SceneDelegate: FlutterSceneDelegate {}`. The window comes from
  `UISceneStoryboardFile = Main`, which xcross cannot compile.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Opt-in through `XCROSS_RUNNER=project`; the default stays the shim | The flutter build and run options are build_cli-generated parsers. The user tests default builds on a device tomorrow, so they must not change |
| D2 | Sources from the pbxproj application target (`buildPhaseFiles` + `synchronizedFiles`, reusing `PbxProject`); fallback: list `ios/Runner` | The same reader app extensions use, so Xcode 16 projects work |
| D3 | Replace `GeneratedPluginRegistrant.m` with xcross's implementation forwarding to `XcrossRegisterGeneratedPlugins`; keep the project's header (identical interface; xcross writes one when missing) | Plugins are a Swift package here; the bridging header and `register(with:)` keep working unchanged |
| D4 | `XcrossSceneDelegate` (Objective-C, in xcross's support file) creates the window; Info.plist names it for project runners only | Storyboards cannot be compiled. The project's `SceneDelegate` is replaced, with a warning when it has code |
| D5 | Pre-UIScene app delegates (no `FlutterImplicitEngineDelegate`): `XcrossSceneDelegate` registers plugins on the scene's engine | Registering with `self` at launch happens before any engine exists |
| D6 | Swift: clang compiles the Objective-C sources to objects; `swiftc` compiles Swift and links everything. Objective-C only: `ld64.lld` links like the shim | Mirrors the toolchain already used for app extensions and the shim |
| D7 | Any exception falls back to the shim with `build.runner_project_failed` and the compiler's first `error:` lines; output is captured, not streamed, so it can be quoted | FR-002: never fail the build |

## Verification limits on the development PC (2026-11-01)

The Windows PC this was written on has no Darwin SDK, no Swift toolchain and no LLVM. Only the upstream `xcross`
binary is installed. No real compile or link could run. The following are unit-tested:

- source discovery from a template-shaped pbxproj;
- the clang, swiftc and ld64.lld command lines;
- the support source;
- the Info.plist rewrite, including the assembler hand-off (Linux CI);
- fallback and warnings, with fakes.

Still unverified:

- whether `swiftc` accepts the exact flags against a real Darwin SDK (they follow `AppExtensionBuilder`, which works);
- whether ld64.lld links the mixed Swift/Objective-C objects;
- behaviour on a device: AppDelegate code runs, the window appears, plugins register, a method channel answers.
