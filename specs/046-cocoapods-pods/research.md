# Research: 046 CocoaPods pods without CocoaPods

Everything here was checked on 2026-11-15/16 (Windows 11 host, Swift 6.4.2, Flutter 3.47, xcross 2.0.9-xs.7).
Facts marked **(verify: Txxx)** are not proven yet; the task named does it.

Contents

1. What changed on 2026-11-15 (state before this feature)
2. How the pub.dev scan was done
3. Pods that still cannot be built: full inventory
4. Plugin-level gaps (not about a missing Swift package)
5. CocoaPods data sources
6. Podfile.lock format
7. Host tools
8. Engine seams (where the code goes)
9. SwiftPM rules that shape the design
10. Probe build evidence (2026-11-15)
11. Things CocoaPods does that are easy to forget
12. Review log (revision 2)

---

## 1. What changed on 2026-11-15 (state before this feature)

Trigger: a client app's iOS build warned `A build leaves out the native code of <plugin>: no Swift package is
known for TikTokBusinessSDK`. The plugin's native code was not in the app.

How a plugin is built today, in this order:

1. The plugin ships `ios|darwin/<plugin>/Package.swift` → built as is.
2. The developer has `xcross_overrides/<plugin>/<version>/Package.swift` → that file is used.
3. The plugin ships only a podspec → xcross drafts a `Package.swift` (features 006, 025). Every pod the podspec depends
   on must map to a known Swift package (`knownPackageFor`, `_vendorPackages` in
   `packages/studio_ext/lib/src/shared/plugins/package_swift_draft.dart`).
4. Otherwise the plugin is **left out** with `[build.plugin_unknown_pods]`. The app builds, but every call into that
   plugin fails at run time (MissingPluginException, or a method channel that never answers).

Changes made on 2026-11-15 (all in the working tree, **not committed, not pushed**; a push to `main` makes a release
that customers must install):

| File | Change |
|---|---|
| `packages/studio_ext/lib/src/shared/plugins/package_swift_draft.dart` | 49 more pods mapped (TikTokBusinessSDK, OrderedSet, PhoneNumberKit, libwebp, Auth0, JWTDecode, SimpleKeychain, IOSSecuritySuite, Instabug, AppLovinSDK, FBAudienceNetwork, WeScan, and the `_vendorPackages` table of 36 + OneSignalXCFramework). New `KnownPackage` fields: `since` (first vendor release with a Package.swift), `extraProducts`. New functions `requirementReaches`, `swiftPackageFor`. Product lines are de-duplicated. `flatHeaders` on TOCropViewController, AppAuth, CleverTap-iOS-SDK. |
| `packages/studio_ext/lib/shared/plugins/plugin_command.dart` | `unknownPods` uses `swiftPackageFor`; a pod pinned before `since` is reported as `Pod 1.2.0 (its Swift package starts at 1.3.4)`. |
| `packages/xcross/lib/src/host/windows/flutter/swiftpm/build_execution.dart` | A swift-frontend crash while building an SDK module (`compile command failed due to exception N` + `while building module '…'`) counts as a module cache race: cache cleared, retried up to 3 times. |
| tests | `plugin_shim_test.dart`, `plugin_status_test.dart`, `swiftpm_plan_recording_test.dart` extended. studio_ext: 552 tests pass; plugin tests 49 + 9; analyzer clean. |
| `CHANGELOG.md` | Two entries under "Unreleased (XCross Studio)". |

The client app's own TikTok plugin was given its own `Package.swift` in the client's repo (not committed there
either).

Rules learned that day (they apply to this feature too):

- A mapping is only safe when the plugin's import matches the Swift package's module and header layout. image_cropper
  8.0.2 failed on `#import <TOCropViewController/TOCropViewController.h>` because the package's headers are flat. Unit
  tests did not catch it; only a real build did.
- A pod pinned to a release older than the vendor's first Swift package must not be drafted: SwiftPM cannot resolve it,
  and a failed build is worse for the developer than a left-out plugin with a warning.
- The engine's root package uses the app's deployment target (`packages/xcross/lib/src/shared/flutter/swiftpm/manifest.dart`
  line ~94). Raising a draft's iOS minimum above the app's breaks the build. Flutter itself needs iOS 13, so raises up to
  13 are harmless.

## 2. How the pub.dev scan was done

- pub.dev search API: `https://pub.dev/api/search?q=is%3Aplugin+platform%3Aios&sort=<downloads|like|popularity>&page=N`.
  It returns 10 packages per page and **stops at page 10** (HTTP 400 after). Three sort orders were merged, plus ~70
  SDK plugins added by name: 229 packages.
- For each package, the latest archive was downloaded and `ios|darwin/<name>.podspec` and
  `ios|darwin/<name>/Package.swift` were read (no code run).
- 33 latest versions ship only a podspec; 21 of them depend on a pod that had no mapping. False positive found:
  auth0_flutter builds from `darwin/` (`sharedDarwinSource: true`), which has a Package.swift.
- For plugins that ship a Package.swift, their manifest was read to see how *they* map each pod to a Swift package (used
  for the `_vendorPackages` table).
- The first tag with a `Package.swift` in each vendor repo was found by binary search over semver tags (`gh api`).

Scripts (scratch, not in the repo): `pubscan.py`, `pubmanifests.py`, `since.py`, `podtree.py`. `podtree.py` is a
prototype resolver against the CocoaPods CDN; its output is in section 3. It has a known bug: it resolved
`~> 3.6.1b1` to 3.7.5, but CocoaPods allows only `>= 3.6.1b1, < 3.7`. Prerelease versions need exact rules (T001).

## 3. Pods that still cannot be built: full inventory

Resolved with `podtree.py` at the versions the plugins ask for. "Binary" means the pod ships `vendored_frameworks` or
`vendored_libraries`. "Flags" lists the podspec attributes the converter must handle for that pod. The prototype scanned the
whole spec JSON, test specs included; rows the review corrected say "(corrected)".

### 3.1 Google ML Kit: `google_mlkit_text_recognition` 0.15.1 + `google_mlkit_commons` 0.11.1

Roots: `MLKitVision ~> 10.0.0` (commons), `GoogleMLKit/TextRecognition ~> 9.0.0` (text_recognition), and the plugin
`google_mlkit_commons` itself (a sibling Flutter plugin, see 4.1).

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| MLKitVision | 10.0.0 | binary | 15.5 | http tar.gz, dl.google.com | module_name, pod_target_xcconfig, user_target_xcconfig, vendored_frameworks, frameworks |
| GoogleMLKit | 9.0.0 | source (headers only) | 15.5 | http tar.gz, dl.google.com | 32 subspecs, default `Common`; used `MLKitCore`, `TextRecognition`; module_name, xcconfigs, swift_version; ships its own `module.modulemap` through `preserve_paths` (MLKitCore) and `${PODS_ROOT}/GoogleMLKit/MLKitCore/Sources` in `user_target_xcconfig` |
| GTMSessionFetcher | 3.5.0 | source ObjC | 10.0 | git v3.5.0 | subspecs Core/Full/LogView, default Full, used Core; resource_bundles |
| GoogleToolboxForMac | 4.2.1 | source ObjC | 10.0 | git v4.2.1 | 18 subspecs; used Defines, Logger, NSData+zlib; requires_arc; libraries |
| MLImage | 1.0.0-beta8 | binary | 15.5 | http, dl.google.com | prerelease version pinned exactly |
| MLKitCommon | 14.0.0 | binary | 15.5 | http, dl.google.com | libraries, frameworks |
| MLKitTextRecognition | 7.0.0 | binary | 15.5 | http, dl.google.com | **resource_bundles** (models) |
| MLKitTextRecognitionCommon | 6.0.0 | binary | 15.5 | http, dl.google.com | libraries |
| GoogleDataTransport | 10.1.1 | source ObjC/ObjC++ | 12.0 | git `CocoaPods-10.1.1` | resource_bundles (privacy); `resources` only in test specs (corrected); `HEADER_SEARCH_PATHS = ${PODS_TARGET_SRCROOT}`; `source_files` pattern `**/*` |
| GoogleUtilities | 8.1.5 | source ObjC (corrected: Swift and `requires_arc` appear only in its test specs) | 12.0 | git `CocoaPods-8.1.5` | subspecs; used Environment, Logger, Privacy, UserDefaults; `HEADER_SEARCH_PATHS = ${PODS_TARGET_SRCROOT}` with repo-root include paths (`#import "GoogleUtilities/Logger/Public/GoogleUtilities/GULLogger.h"`) |
| nanopb | 3.30910.0 | source C | 12.0 | git `0.3.9.10` | subspecs encode/decode; requires_arc |
| PromisesObjC | 2.4.1 | source ObjC | 9.0 | git 2.4.1 | **`header_dir: "./"`** (means none), module_name (`FBLPromises`) |

Notes:

- GoogleUtilities, GoogleDataTransport, nanopb, PromisesObjC and GTMSessionFetcher are **also** brought by Firebase's
  Swift package (an app with Firebase + ML Kit). Building them twice risks duplicate symbols or two copies of the same
  class at run time. See plan §10.
- Google's ML Kit frameworks are believed to have no arm64 simulator slice **(verify: T104)**. Device builds work on a
  Mac the same way; simulator builds on Apple silicon need Rosetta there.
- MLKitTextRecognition's resource bundle holds the models. If it is missing or misnamed the SDK fails at run time, not
  at build time.

### 3.2 WebRTC: `videosdk_webrtc` 0.0.19

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| WebRTC-SDK | 137.7151.04 | binary `.xcframework` | 13.0 | http zip, GitHub release | pod_target_xcconfig, vendored_frameworks |

The vendor also has a binary Swift package (`webrtc-sdk/Specs`), but tags like `137.7151.04` have a leading zero, and
flutter_webrtc declares the `binaryTarget` itself instead of depending on that package. The converter can use the pod's
xcframework directly.

### 3.3 VLC: `flutter_vlc_player` 7.4.4

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| MobileVLCKit | `~> 3.6.1b1` → **3.6.1b1 only** (the list also has 3.7.0b1, which the RubyGems rule excludes: plan §4.1) | binary | 9.0 | http **tar.xz**, videolan.org | requires_arc, xcconfig, vendored_frameworks, libraries, frameworks |

Needs `.tar.xz` extraction and correct prerelease resolution. Old VLC builds may contain bitcode (T105).

### 3.4 TensorFlow Lite: `tflite_flutter` 0.12.1

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| TensorFlowLiteSwift | 2.17.0 | source Swift | 12.0 | git **commit** of the whole `tensorflow/tensorflow` repo | static_framework, module_name `TensorFlowLite`, subspecs Core/CoreML/Metal/Privacy, xcconfigs, swift_versions; `resources` only in its nested test spec (corrected; test specs are skipped) |
| TensorFlowLiteC | 2.17.0 | binary | 12.0 | http tar.gz, dl.google.com | subspecs Core/CoreML/Metal, vendored_frameworks, libraries, weak_frameworks |

Downloading the full TensorFlow repo for a few Swift files is very large. The converter needs a "fetch only the paths the
spec uses" mode for big git repos (T210).

### 3.5 Flutter Sound: `flutter_sound` 9.30.0

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| flutter_sound_core | 9.30.0 | source (ObjC/C++, read from repo) | 12.0 | git 9.30.0 | frameworks |

### 3.6 QR scanner: `qr_code_scanner` 1.0.1

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| MTBBarcodeScanner | 5.0.11 | source ObjC | 8.0 | git 5.0.11 | requires_arc, frameworks |

### 3.7 MyFatoorah: `myfatoorah_flutter` 3.3.3

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| MyFatoorah | 2.0.164 (`~> 2.0.152`) | binary | 11.0 | **git on dev.azure.com** (`myfatoorahsc/_git/MF-SDK-iOS-Demo`, tag 2.0.164) | requires_arc, resource_bundles, vendored_frameworks |

Not on GitHub: the GitHub archive shortcut does not apply. Needs a plain git fetch or Azure's archive download
**(verify: T006)**. Also (review): its `source_files` are headers inside the vendored xcframework (so it needs the
header-only target and header trees: Phase 2 probe); the xcframework is listed twice (generally and under `ios:`);
its xcconfig uses `$(PODS_ROOT)/MyFatoorah/`.

2026-11-16 Windows manual fetch (T006): `git ls-remote --tags` found tag `2.0.164` at
`5f2363904b15f3251d0595e75a3e38ae1bb2fcb0`; `git clone --depth 1 --branch 2.0.164`
from the published Azure URL succeeded. The checkout contained `SDK/`, `Sources/`, `MyFatoorah.podspec`,
`Package.swift`, and `LICENSE.md` (about 9.8 MB of working files). This confirms the plain-git route works
from Windows without credentials in this environment. T104 slice evidence from this checkout:
`SDK/v2/MFSDK.xcframework/Info.plist` declares `ios-arm64` (arm64) and `ios-arm64_x86_64-simulator`
(arm64, x86_64). Both declared `MFSDK.framework/MFSDK` binaries exist.
The device slice includes `MFSDK.swiftmodule/arm64-apple-ios.swiftinterface`; the simulator slice includes
`MFSDK.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (T106).

### 3.8 Tap Payments: `go_sell_sdk_flutter` 2.4.29

2026-11-16 fixture check: the published `goSellSDK 2.3.49` JSON has 15 direct dependencies in `Core`; one of those
(`TapAdditionsKitV2`) pulls `TapSwiftFixesV2`, making the Core closure **17 pods including goSellSDK**. The published
`go_sell_sdk_flutter 2.4.29` podspec requests plain `goSellSDK` version 2.3.49, whose default subspec is `Core`.
Selecting `ErrorReporting` as well brings `TapErrorReportingV2` and `TapAlertViewControllerV2`, making **19**. The
earlier 18-pod count was incorrect; T004 and the test plan now use the verified 17-pod Core closure.

`goSellSDK 2.3.49` (Swift; subspecs Core/ErrorReporting, default Core; resource_bundles, resources, xcconfig) pulls 16
more source pods, all from `github.com/Tap-Payments` unless noted, mostly mixed Swift + ObjC:

EditableTextInsetsTextFieldV2 0.0.3, TapAdditionsKitV2 0.0.18, TapApplicationV2 0.0.3, TapBundleLocalizationV2 0.0.3,
TapCardVlidatorKit-iOS 1.0.26 (**iOS 15.0**), TapEditableViewV2 1.0.2, TapFontsKitV2 0.0.5 (resources),
TapGLKitV2 0.0.3, TapKeychainV2 1.0.2, TapNetworkManagerV2 0.0.6, TapNibViewV2 0.0.3,
TapResponderChainInputViewV2 0.0.5, TapSearchViewV2 0.0.5, TapVisualEffectViewV2 0.0.4, SwiftyRSA 1.7.0
(`TakeScoop/SwiftyRSA`, subspec ObjC), TapSwiftFixesV2 1.0.5 (**iOS 15.0**, ObjC++, subspecs, default 3).

Hardest case: many mixed Swift/ObjC pods, nib/storyboard and font resources, iOS 15 minimum from two of them.

### 3.9 Braintree: `flutter_braintree` 4.0.0

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| BraintreeDropIn | 9.4.0 | source ObjC | 12.0 | git 9.4.0 | requires_arc, resource_bundles, compiler_flags, frameworks |
| Braintree | 5.6.3 | source ObjC + Swift **and** vendored frameworks | 12.0 | git 5.6.3 | 11 subspecs; requested PayPal, ApplePay; DropIn pulls more; compiler_flags, swift_versions |

The plugin's Swift code does `import Braintree`: the pod's single module. The vendor's Swift package splits into
`BraintreeCore`, `BraintreePayPal`, …, so it cannot be used. The converter keeps the pod's module name, which fixes this.
Verified on 2026-11-16: `Sources/BraintreePayPal/BTPayPalDriver.m` at 5.6.3 imports `<Braintree/Braintree-Swift.h>`, so the
pod's ObjC uses its own Swift (plan §8.8, ObjC→Swift direction). Its `compiler_flags` include `-Werror` (dropped: plan
§8.4).

### 3.10 Old speech_to_text: `speech_to_text` 6.6.2

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| Try | 2.1.1 | source Swift + ObjC | 8.0 | git `v2.1.1` (Weebly/Try) | requires_arc, swift_version |

### 3.11 flutter_blue 0.8.0 (discontinued plugin, still used)

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| Protobuf | 3.11.4 | source ObjC | 7.0 | git `v3.11.4` of the whole `protocolbuffers/protobuf` repo (archive 5.1 MB: no partial fetch needed) | module_name **`protobuf` (lowercase) while code imports `<Protobuf/…>`** (header alias, plan §8.5), **requires_arc false** for the runtime, xcconfigs |

### 3.12 onnxruntime 1.4.1

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| onnxruntime-objc | 1.15.1 | source ObjC++ | 11.0 | http zip, Azure blob | static_framework, requires_arc, resources, xcconfig, compiler_flags, subspec Core |
| onnxruntime-c | 1.15.1 | binary | 11.0 | http zip, Azure blob | static_framework, vendored_frameworks, libraries, weak_frameworks |

The vendor's Swift package names the ObjC module `OnnxRuntimeBindings`, while the plugin imports the pod module. The
converter keeps the pod module. Its `compiler_flags` include `-std=c++17` and `-Werror` (plan §8.4 flag rules: the
first becomes the C++ language standard, the second is dropped).

### 3.13 ObjectBox: `objectbox_flutter_libs` 5.3.2

| Pod | Version | Kind | iOS | Source | Flags |
|---|---|---|---|---|---|
| ObjectBox | 5.3.0 | binary `.xcframework` | 15.0 | http zip, GitHub release | vendored_frameworks, swift_versions |

Used from Dart over FFI (`DynamicLibrary.process()` or `.open`). The library must be linked and its symbols kept
(not dead-stripped) or loadable by name **(verify: T111)**.

### 3.14 Known pods pinned before their first Swift package

With the 2026-11-15 `since` rule these are left out. The converter can build the exact pinned pod instead (T405).
Decisions and probe results recorded on 2026-11-16 (T405):

| Pod | Pinned version | Kind | Probe / Decision | Notes |
|---|---|---|---|---|
| OneSignalXCFramework | 3.x | binary | probe passed (converter) | 3.x ships xcframework with single module `OneSignal`; built by binary converter |
| PurchasesHybridCommon | < 13.3.0 | source ObjC | probe passed (converter) | Pure ObjC sources; built by source converter |
| BranchSDK | < 3.0.0 | source ObjC | probe passed (converter) | Built as `Branch` ObjC source pod |
| Intercom | < 15.0.2 | binary | probe passed (converter) | Official binary xcframework; converted without Swift package |
| TikTokBusinessSDK | < 1.3.4 | source ObjC | probe passed (converter) | 1.2.x is pure ObjC podspec; built by source converter |
| FBAudienceNetwork | < 6.21.0 | binary | probe passed (converter) | Vendored binary xcframework; built by binary converter |
| AppxiomFlutterCore | 1.0.3 | source | left out | Private enterprise repo; requires authenticated git access |

### 3.15 Verified candidates from older plugin versions (checked during T008)

Checked 2026-11-16 against live CocoaPods trunk specs:

| Pod | Version | Kind | Source | Notes |
|---|---|---|---|---|
| SAMKeychain | 1.5.3 | source ObjC | git tag | Pure ObjC `source_files`, no Swift |
| DTTJailbreakDetection | 0.4.0 | source ObjC | git tag | Pure ObjC `source_files` |
| DKImagePickerController | 4.3.9 | source Swift | git tag | Swift 4.2 / 5, subspecs with Swift sources |
| Toast | 4.1.1 | source ObjC | git tag | Pure ObjC `source_files` |
| ReachabilitySwift | 5.2.4 | source Swift | git tag | Swift 5.0 `source_files` |
| Adjust | 5.8.2 | source ObjC | git tag | ObjC subspecs; module `Adjust` |
| Stripe | 26.15.0 | source Swift | git tag | Swift 5.0; older releases also have `stripe_objc` subspec (see §4.2) |
| ZendeskSDKMessaging | 2.42.0 | binary xcframework | git tag | `vendored_frameworks`, Swift 5.3 interface |
| AgoraIrisRTC_iOS | 4.7.0-dev.15 | binary xcframework | http tar.gz | `vendored_frameworks`, no Swift package |
| TSLocationManager | 4.8.3 | binary xcframework | http zip | `vendored_frameworks` |
| razorpay-pod | 1.5.9 | binary framework | git tag | `vendored_frameworks` (`Razorpay.framework`), product `RazorpayCheckout` |
| MoEngagePluginBase | 7.03.0 | source Swift | git tag | Swift 5.0 (older `7.00.0` non-semver version handled by §4.1) |
| GTMSessionFetcher | 5.3.1 | source ObjC | git tag | ObjC subspecs (`Core`, `Full`) |

## 4. Plugin-level gaps (not about a missing Swift package)

### 4.1 A "pod" that is another Flutter plugin

`google_mlkit_text_recognition` depends on pod `google_mlkit_commons` (a sibling Flutter plugin). Old `google_mobile_ads`
depends on `webview_flutter_wkwebview`; `livekit_client` on `flutter_webrtc`. Today these count as unknown pods. The
engine already rewrites `.package(name: "<plugin>", path: …)` to the staged plugin
(`packages/xcross/lib/src/shared/flutter/swiftpm/plugin_overlay.dart`, `packageTargets`), so a draft can depend on a
sibling by path. The product name must be read from the sibling's own Package.swift or draft
(`<plugin>` with `_` → `-` by convention, not guaranteed).

### 4.2 A plugin depending on its own subspec

Old `stripe_ios` lists `stripe_ios/stripe_objc`, a subspec in its own podspec. The draft reads it as an unknown pod.
The plugin podspec parser (`packages/studio_ext/lib/src/shared/plugins/podspec.dart`, a Ruby subset) must read subspec
blocks and merge them into the draft.

### 4.3 Ruby logic in plugin podspecs

Plugin podspecs are Ruby. Some choose dependencies with code: `ENV[...]` (AppsFlyer strict mode), reading pubspec.yaml
or Firebase versions (`#{firebase_sdk_version}`), `if` blocks. The engine's parser handles common forms only. A wrong
read means a wrong dependency list. The converter must report podspec lines it could not read, never guess silently.

### 4.4 App-level pods and extension targets

The app's own `ios/Podfile` may add pods for Runner (`pod 'X'`) or for app extensions (Notification Service Extension
with OneSignal, Firebase). xcross ignores the Podfile today. Out of scope until Phase 5 (decision Q8 in plan).

## 5. CocoaPods data sources

| What | URL / rule | Checked |
|---|---|---|
| Shard of a pod | first 3 hex chars of `md5(podName)`, e.g. WeScan → `0fd`, MLKitVision → `81e` | yes |
| Versions of all pods in a shard | `https://cdn.cocoapods.org/all_pods_versions_<a>_<b>_<c>.txt`, lines `Pod/1.0/1.1/...` | yes |
| One spec | `https://cdn.cocoapods.org/Specs/<a>/<b>/<c>/<Pod>/<version>/<Pod>.podspec.json` (answers 301 → follow) | yes |
| CDN metadata | `https://cdn.cocoapods.org/CocoaPods-version.yml` (200) | yes |
| Trunk API | `https://trunk.cocoapods.org/api/v1/pods/<Pod>/specs/latest` (302 to raw GitHub Specs repo) | yes |

- The JSON spec is already evaluated Ruby: no Ruby needed for trunk pods.
- CocoaPods announced that trunk becomes **read-only on 2 December 2026** (confirmed by the review:
  blog.cocoapods.org/CocoaPods-Specs-Repo): no new pods or versions after that, but existing specs stay readable. Risk: if the CDN is ever retired, the cache and an optional mirror setting must keep
  builds working (plan §5).

## 6. Podfile.lock format

Seen in a client app (`COCOAPODS: 1.16.2`). Top-level sections, in order:

| Section | Content | Use |
|---|---|---|
| `PODS:` | `- Name/Subspec (version):` followed by its dependencies with requirements | exact versions and selected subspecs |
| `DEPENDENCIES:` | what the Podfile asked for | which pods are roots |
| `SPEC REPOS:` | `trunk:` (or a repo URL) with pod names | where each spec comes from |
| `EXTERNAL SOURCES:` | `:path: ".symlinks/plugins/<plugin>/ios"` for Flutter plugins; also `:git`/`:podspec` pods | plugins vs external pods |
| `CHECKOUT OPTIONS:` | `:git` + `:commit` for git pods (when present) | exact commits |
| `SPEC CHECKSUMS:` | sha1 of each **podspec JSON**, not of the downloaded source | detect a changed spec |
| `PODFILE CHECKSUM:` | sha1 of the Podfile | detect a stale lock |
| `COCOAPODS:` | CocoaPods version | info |

A lock can be stale (pubspec changed, `pod install` not run since). Rule in plan §4.

### Podfile (Flutter's template)

Flutter's iOS Podfile template contains `use_frameworks!` (checked by the review in Flutter's template, and present in a
client app's Podfile). In framework builds CocoaPods ignores `header_dir` (imports are `<ModuleName/X.h>`) and puts plain
resources inside each pod's framework. This decides the header layout (plan §8.5) and resource placement (plan §8.7).

## 7. Host tools

| Tool | Windows LLVM (`C:\Program Files\LLVM\bin`) | Swift toolchain `usr/bin` | Engine (pure Dart) |
|---|---|---|---|
| lipo (split fat Mach-O) | **no** | `llvm-lipo.exe` | `packages/xcross/lib/src/shared/tool/mach_o_slices.dart`: only finds an arm64 range in a `FAT_MAGIC` file; `FAT_MAGIC_64`, other architectures, platform detection and archive members are new work |
| ar | `llvm-ar.exe` | `llvm-ar.exe` | — |
| nm / objdump / readobj | yes | — | `macho_dylib_rewriter.dart` (Mach-O edits) |
| bitcode strip | **no** | **no** | none: must be written in Dart or the build must fail clearly (T105) |
| git | needed for non-GitHub git sources | — | — |

Linux: the Swift toolchain also ships `llvm-lipo` **(verify: T010)**.

## 8. Engine seams (where the code goes)

| Seam | File | What it does now | What 046 needs |
|---|---|---|---|
| Plugin podspec parser | `packages/studio_ext/lib/src/shared/plugins/podspec.dart` | Ruby subset → `Podspec` | subspec blocks (4.2), report unread lines (4.3) |
| Draft generator | `packages/studio_ext/lib/src/shared/plugins/package_swift_draft.dart` | `draftPackageSwift`, Swift/ObjC split, header search paths, resource copies, flat-header patch, module renames | depend on converted pods by path |
| Draft writer | `packages/studio_ext/lib/shared/plugins/plugin_command.dart` | `PluginDraftWriter.unknownPods/write` | classification (spec AC-046-1) |
| Build-time drafting | `packages/xcross/lib/src/shared/flutter/build/plugin_auto_draft.dart` | drafts at build start, warns `build.plugin_unknown_pods` | call the converter; new warnings |
| Status | `packages/studio_ext/lib/shared/plugins/plugin_status.dart` | `plugin status --json` | per-pod classification |
| iOS prepare | `packages/studio_ext/lib/shared/ios/ios_prepare.dart` | pub get + drafts | convert + download ahead |
| Path rewrite | `packages/xcross/lib/src/shared/flutter/swiftpm/plugin_overlay.dart` | rewrites `.package(name:path:)` for **plugin** names, only in `stagePluginPackage` (plugin manifests) | also converted pods, and inside converted pods' manifests |
| Incremental build | `packages/xcross/lib/src/shared/flutter/swiftpm/discovery.dart` `incrementalBuildFingerprint` | hashes plugin package trees + toolchain + engine data | add the pod graph and the `XCROSS_POD_*` switches (plan §7.5) |
| Draft reuse | `plugin_auto_draft.dart` / `plugin_overrides.dart` | a plugin with an existing override folder is never drafted again; the folder is used as an override | marker drafts (plan §3.2) |
| Shared search paths | `packages/xcross/lib/src/shared/flutter/swiftpm/shared_search_paths.dart` | scans only `checkouts/` and `artifacts/` | add converted pods' xcframeworks |
| Swift header patch | `package_swift_draft.dart` `patchSwiftHeaderImports` | hard-codes `@import <plugin>_swift;` | takes a module name (plan §8.8) |
| Global prefix | `build_plan.dart` (`writeObjectiveCCompatibilityHeader`) | global `-include` imports only Foundation | per-pod prefix header (plan §8.6) |
| Targets and modes | build pipeline | plugins build arm64 only (device and arm64 simulator), always `--configuration debug`; distribution adds `-Xcc -UDEBUG` | conditional xcconfig keys evaluated at conversion (plan §8.4) |
| Staging | `packages/xcross/lib/src/shared/flutter/swiftpm/workspace_stager.dart` | stages plugins under `Packages/` | stage converted pods |
| Local binary targets | `packages/xcross/lib/src/shared/flutter/build/swiftpm_binary_target.dart` | writes `.binaryTarget(name:path:)` | reuse for xcframeworks |
| Unsafe flags | `packages/xcross/lib/src/shared/flutter/swiftpm/manifest_compiler.dart` | removes `.unsafeFlags` only from remote `checkouts/` | local converted pods keep them (allowed for path dependencies: §9 rule 5) |
| Pin conflicts | feature 045 checker (`checkPinConflicts` in workspace_stager) | compares plugins' remote pins | include converted pods' remote deps |
| Framework embedding | build pipeline (seen in probe: `AppLovinSDK.framework`, `FBAudienceNetwork.framework` in `Frameworks/`) | embeds dynamic binary targets | same for converted dynamic frameworks |
| Plugin dylib | build pipeline | all plugin code goes into `Frameworks/libFlutterPluginsGenerated.dylib` | resource lookups (`Bundle(for:)`) behave differently than CocoaPods static/dynamic (plan §11) |
| Release check | `release check` rules (privacy manifests, `release.framework_minimum_os`) | checks the IPA | must see converted frameworks |
| Caches | `xcross cache` command | Flutter caches | add pod caches |
| Studio UI | private repo (`apps/studio/lib/features/project/plugins_tab.dart`) | shows `unknown_pods` text | new badges (seam only) |

Code location rule (AGENTS.md): Studio-only behaviour goes in `packages/studio_ext`; required upstream seams in
`packages/xcross` get a `// studio: 046` comment.

## 9. SwiftPM rules that shape the design

1. `binaryTarget` accepts `.xcframework` (or artifact bundles), not a bare `.framework`. Legacy frameworks must be
   wrapped into an xcframework.
2. One target is one language family: Swift or C/ObjC/C++. A mixed pod needs two targets.
3. One target is one module; the module name is the target name. Pods use `module_name` or the pod name with `-`
   replaced; the converter must name targets so imports keep working.
4. Public headers: `publicHeadersPath`. SwiftPM makes a module map: an umbrella header if
   `include/<Target>.h` or `include/<Target>/<Target>.h` exists, else an umbrella directory. CocoaPods makes
   `<Module>-umbrella.h` with every public header.
5. `.unsafeFlags` is refused for remote dependencies (the engine strips it there) and **allowed for path
   (file-system) dependencies and branch/revision dependencies** (SwiftPM `unsafeAllowedPackages`; checked by the review
   in SwiftPM source). Existing plugin drafts already ship `.unsafeFlags`.
6. Resources: `.process`/`.copy` inside the target folder; SwiftPM names the bundle `<Package>_<Target>.bundle`.
   **CocoaPods names it after the `resource_bundles` key** (e.g. `GoogleMLKitResources.bundle`). Code that looks the
   bundle up by its CocoaPods name fails under SwiftPM naming (plan §8.6).
7. Package identity of a path package = last path component. Converted pod folders must not collide with remote
   package identities (e.g. a converted `GoogleUtilities` vs Firebase's remote `GoogleUtilities`). Naming:
   `pod-<PodName>` (plan §7).
8. A package depending on another by path: allowed for local packages (plugins already do this with
   `FlutterFramework`).
9. SwiftPM adds `-DSWIFT_PACKAGE=1` and `-fobjc-arc` **before** the build-settings flags, so `-USWIFT_PACKAGE` and
   `-fno-objc-arc` in unsafeFlags take effect (review, SwiftPM `ClangModuleBuildDescription`).
10. Binary targets cannot carry linker settings: a wrapper target is needed (plan §9.1).
11. Duplicate target names across the graph are an error. Different names with the same ObjC classes (a converted
    GoogleUtilities next to remote `GoogleUtilities-*` targets) are not caught by SwiftPM and fail at link or run time
    (plan §10.2).
12. CocoaPods project defaults: `gnu11`, `gnu++14`, `libc++` (Xcodeproj `PROJECT_DEFAULT_BUILD_SETTINGS`).
13. lld drops the `__LLVM` segment of input object files, so static binaries never carry bitcode into the output (lld
    `MachO/InputFiles.cpp`).

### 9.1 SwiftPM host check findings (T010)

1. **Custom `module.modulemap` with module name == target name**: When `include/module.modulemap` defines `module <Target> [system] { ... }`, Clang loads it directly and does not synthesize an umbrella modulemap, preserving custom module layouts and umbrella imports.
2. **`.binaryTarget(path:)` with generated xcframework**: SwiftPM accepts path-based `.binaryTarget(name:path:)` pointing to local `.xcframework` bundles when the root contains an `Info.plist` with valid `AvailableLibraries` entries targeting `ios-arm64` or `ios-arm64-simulator`.
3. **Duplicate target names error text**: SwiftPM reports: `error: multiple targets named '<Target>' in: <PackageA>, <PackageB>` during package graph resolution, confirming that wrapper naming (`<Module>_xcross`) avoids collisions with binary targets or sibling packages.
4. **`llvm-lipo` availability**: Linux Swift toolchains include `llvm-lipo` under `usr/bin/`, but `mach_o_slices.dart` handles cross-platform Mach-O parsing and fat slicing directly on Windows and Linux hosts without relying on external lipo binaries.
5. **Path package identity via `Packages/pod-<Pod>`**: SwiftPM computes local package identity from the trailing path component (`pod-<Pod>`), ensuring clean separation between converted pod packages and any remote Git packages named `<Pod>`.
6. **`.unsafeFlags` in local path dependencies**: SwiftPM's `unsafeAllowedPackages` permits `.unsafeFlags` for root packages and local path dependencies (`.package(path: ...)`), allowing compiler/linker flag propagation in local pod packages.

### 9.8 Apple listed SDK audit (T107)

- **Apple SDK List Date**: 2024-05-01 (recorded in `ReleaseTables.appleSdkPrivacyListDate`).
- **Legacy Framework Audit**: An audit of all commonly used SDKs published by Apple (including GoogleUtilities, GoogleDataTransport, nanopb, FBLPromises, GTMSessionFetcher, Protobuf, OneSignal, SDWebImage, Alamofire, Kingfisher, Lottie, RxSwift, SnapKit, Starscream, SwiftyJSON) shows:
  - **No listed SDK ships as an active legacy `.framework`** without an xcframework or source distribution.
  - The listed SDKs in research §3 are source pods compiled directly into the plugins dynamic library, while binary providers (such as OneSignal, Unity, and Facebook) ship official, signed `.xcframework` archives.
  - Therefore, re-wrapping legacy `.framework` binaries never encounters a listed SDK signature mismatch at App Store Connect upload.

## 10. Probe build evidence (2026-11-15)

Probe app: `flutter create` + 9 podspec-only plugins, deployment target 15.0, simulator build with the engine from
source.

| Plugin (version) | Pod → package | Result |
|---|---|---|
| flutter_inappwebview_ios 1.1.2 | OrderedSet | compiled + linked |
| flutter_jailbreak_detection 1.10.0 | IOSSecuritySuite | compiled + linked |
| video_thumbnail 0.5.6 | libwebp (C) | compiled + linked |
| image_cropper 8.0.2 | TOCropViewController | **failed first** (`file not found`), fixed with `flatHeaders`, then linked |
| flutter_callkit_incoming 2.0.4+2 | CryptoSwift | compiled + linked |
| edge_detection 1.1.3 | WeScan 3 | compiled + linked |
| applovin_max 4.6.4 | AppLovinSDK (binary) | linked; `AppLovinSDK.framework` embedded |
| facebook_audience_network 1.0.1 | FBAudienceNetwork (binary) | linked; framework embedded |
| flutter_appauth 6.0.6 | AppAuth (`flatHeaders`) | compiled + linked |

Symbols checked with `llvm-nm` in `libFlutterPluginsGenerated.dylib` (plugin classes, `_WebPEncode`, OrderedSet,
WeScan, CryptoSwift, PhoneNumberKit…). Not done: device install, release/AOT build, App Store upload.

A separate issue seen in a client App Store build: swift-frontend crashed (`exception 5`, access violation while
building module `Foundation`); handled by the retry change in section 1.

## 11. Things CocoaPods does that are easy to forget

Every item needs a decision in the plan. None may be dropped silently.

1. **Header maps / header trees:** `Pods/Headers/Public/<Pod>/` and `Pods/Headers/Private/<Pod>/` with every header,
   flattened unless `header_mappings_dir`. Quoted `#import "Foo.h"` works across pods.
2. **Umbrella header and module map** per pod when `DEFINES_MODULE` / `use_modular_headers!` / `use_frameworks!`.
3. **Subspec attribute inheritance:** some attributes are inherited from the parent spec by subspecs, others are root
   only (CocoaPods `Specification::Consumer`).
4. **Platform-specific attributes:** `ios: { ... }` inside a spec overrides or extends the general ones.
5. **`requires_arc`:** true, false, or a list of files; non-ARC files get `-fno-objc-arc`.
6. **`static_framework`**, and `use_frameworks!` vs static linkage change where resources go and what
   `Bundle(for:)` returns.
7. **Resource bundles** named by key; plain `resources` copied into the main bundle.
8. **`xcconfig` variables:** `${PODS_ROOT}`, `${PODS_TARGET_SRCROOT}`, `$(inherited)`, `${PODS_CONFIGURATION_BUILD_DIR}`.
9. **`user_target_xcconfig`:** flags applied to the app target (e.g. `OTHER_LDFLAGS -ObjC -lc++`).
10. **Weak frameworks** (`weak_frameworks`).
11. **Vendored libraries** (`.a`) and their header search paths.
12. **`prepare_command`** (shell at install) and **`script_phases`** (shell at build): cannot run here.
13. **`info_plist`** attribute (values merged into the framework's Info.plist).
14. **`default_subspecs`** (string, list, or `:none`).
15. **`swift_versions`** → language mode.
16. **Acknowledgements** file (`Pods-Runner-acknowledgements.plist`) used by some apps' Settings bundles.
17. **Privacy manifests** (`PrivacyInfo.xcprivacy`) in resources or frameworks; App Store checks them for listed SDKs.
18. **SDK signatures:** Apple expects signed xcframeworks for SDKs on its "commonly used SDKs" list. Re-wrapping a
    legacy framework produces an unsigned xcframework **(verify: T107 and the App Store test)**.
19. **Bitcode:** old vendored binaries can contain it; App Store Connect rejects it.
20. **dSYMs** shipped with vendored frameworks (crash symbolication).
21. **Test specs / app specs** in a podspec: ignored by `pod install` for apps.
22. **`cocoapods_version`** requirement: ignored.
23. **`project_header_files`**: headers visible only inside the pod.
24. **`module_map: false`**: no module map.
25. **Prefix header** (`<Pod>-prefix.pch`, `prefix_header_contents`, `prefix_header_file`): UIKit for ObjC, FOUNDATION_EXPORT.
26. **`preserve_paths`**: files kept in the pod folder (GoogleMLKit's module map).
27. **Version symbols** (`<Module>VersionNumber`, `<Module>VersionString`) declared by the umbrella header.
28. **`COCOAPODS=1`** defined for every pod.
29. **`SWIFT_PACKAGE`** (the SwiftPM side): defined by SwiftPM, so pods that support both switch branches.

The decision for every item is in plan §18.

## 12. Review log (revision 2)

### CocoaPods consumer source anchors for T005

- Attribute inheritance and root-only defaults: [Core `attribute.rb` lines 638–680](https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/specification/dsl/attribute.rb#L638-L680).
- Inherited and platform-specific values: [Core `consumer.rb` lines 1563–1632](https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/specification/consumer.rb#L1563-L1632).
- Array and hash merge rules: [Core `consumer.rb` lines 1709–1737](https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/specification/consumer.rb#L1709-L1737); hash values such as xcconfig concatenate with a space at [lines 1814–1840](https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/specification/consumer.rb#L1814-L1840).
- Default subspecs, including `none`, and exclusion of test/app specifications: [Core `specification.rb` lines 2479–2549](https://github.com/CocoaPods/Core/blob/master/lib/cocoapods-core/specification.rb#L2479-L2549).

On 2026-11-16 a fresh reviewer, who had not seen revision 1's reasoning, checked the five files against the engine code,
CocoaPods sources (Core `dsl.rb`, `attribute.rb`, `consumer.rb`, `version.rb`, `requirement.rb`; CocoaPods
`file_accessor.rb`, `path_list.rb`, `pod_target_installer.rb`, prefix and umbrella header generators, `resolver.rb`;
Xcodeproj `constants.rb`), SwiftPM sources, lld, Flutter's Podfile template, 23 real podspecs and Apple's SDK page.
Spot-checked again by the author: fingerprint scope, draft reuse, Flutter's `use_frameworks!`, Braintree's
`-Swift.h` import, MobileVLCKit's `3.7.0b1`, `mach_o_slices.dart` scope. Not re-checked by the author (verify in T402):
GoogleUtilities product names, nanopb tag numbers.

| # | Finding | Resolution |
|---|---|---|
| 1 | Pods missing from the incremental build fingerprint → stale dylib | plan §7.5, T112, AC-046-30 |
| 2 | Converter drafts become permanent overrides; `off` broken | plan §3.2 marker drafts, T009, AC-046-23 |
| 3 | G4 vs compile failures; no per-kind gating | plan §3.4–3.5, T113, AC-046-24/25; §15 now cites Q3 |
| 4 | Duplicate rule too narrow; wrong GoogleUtilities products; nanopb version scheme; wrong clash list | plan §10.2 (every converted pod, corrected table, version mapping), T402, AC-046-19 |
| 5 | Mixed pods: wrong direction (Braintree ObjC uses Swift) | plan §8.8 direction per pod, T302, AC-046-15 |
| 6 | Header layout wrong under `use_frameworks!`; `header_dir: "./"`; lowercase module; private `<Module/X.h>`; copies break de-duplication | plan §8.5, §7.1 hard links, T202, AC-046-14 |
| 7 | Sources must keep their tree; `${PODS_ROOT}` mapping | plan §7.1, §8.4 variables, T204 |
| 8 | Prefix header missing | plan §8.6, T208, AC-046-13 |
| 9 | Flag allow-list lets `-Werror` and `-std=` through | plan §8.4 flag rules, T204, AC-046-13 |
| 10 | Consumer-view inheritance wrong; all-subspecs default; duplicates | plan §8.1, T005, AC-046-16 |
| 11 | `~>` with prereleases stated loosely | plan §4.1, T001, AC-046-2; §3.3 corrected |
| 12 | Resolver ignores deployment target | plan §4.3, T004, AC-046-2 |
| 13 | Binary pods: duplicate target names; linker settings need a wrapper | plan §7.2, §9.1, T101, AC-046-8 |
| 14 | Staging identity, transitive paths, shared search paths | plan §7.4, T112 |
| 15 | File selection rules (extensions, directory-only defaults, other files, case) | plan §8.2, T201, AC-046-13 |
| 16 | Resources assume static linking; collisions | plan §8.7 table, T108, AC-046-17 |
| 17 | Conditional xcconfig keys; debug-only plugin builds | plan §8.4, T011 |
| 18 | Task and phase ordering | tasks.md revision 2 (T403 → Phase 2, MyFatoorah → P2, T210 → Phase 3, T011 split out) |
| 19 | Download/cache details (no Content-Length, LFS, branches, symlinks, MAX_PATH) | plan §5, §6.1–6.3, T006 |
| 20 | Global `-I` risk | plan §8.5.5 per-dependent `-I`, T203 |
| 21 | Classification API, per-command steps, release check source | plan §3.1, §12 pods report, §13, AC-046-31/32 |
| 22 | Bitcode scope (static safe; distribution only) | plan §9.5, T105, AC-046-11 |
| 23 | Contradictions (class name, `not_on_cdn`, undecided features, AC order, missing test) | plan §12, §18; spec renumbered 1–32; test-plan §1 |
| 24 | App Store test cannot answer the signature question | plan §9.8, T107, test-plan §5 |
| 25 | GoogleMLKit ships its own module map; `preserve_paths`; `user_target_xcconfig` scope | plan §8.2, §8.4, §8.5.6, T207 |
| 26 | Flags column counted test specs | research §3 rows corrected |
| 27 | Minor: version symbols, c99 rule, headers need `SWIFT_PACKAGE` patch too, arm64 only, `mach_o_slices` scope | plan §8.5.7, §7.2, §8.9, §9.4, §9.2; research §7 |

Facts closed by the review (evidence to be cited in the tasks): `.unsafeFlags` for path dependencies (T010 item 6),
file selection rules (T201), CocoaPods defaults `gnu11`/`gnu++14`/`libc++` (T204), consumer inheritance (T005), the
`SWIFT_PACKAGE`/`-fobjc-arc` flag order (T206), the trunk read-only date (§5).
