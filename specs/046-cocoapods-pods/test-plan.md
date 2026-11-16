# Test plan: 046 CocoaPods pods without CocoaPods

Three levels:
1. Unit tests with fixtures (every rule).
2. Probe app builds (real plugins, real pods).
3. Device and App Store checks (real hardware, real upload).

A passing unit suite never counts as proof for a probe or device row (AGENTS.md). Revision 2 (2026-11-16) follows the
review (research §12).

## 1. Unit tests

Location: `packages/studio_ext/test/shared/pods/` (converter) and `packages/xcross/test/...` (seams). Test names start
with the AC id.

| Area (tasks) | Fixtures | Cases (minimum) |
|---|---|---|
| Versions (T001) | inline + MobileVLCKit's real version list | every plan §4.1 rule; RubyGems `~>` (`v >= r && v.release < r.bump`); `~> 3.6.1b1` over MobileVLCKit's list → `3.6.1b1`; `7.00.0`; `3.30910.0`; `1.0.0-beta8`; `>= 3.3.2, < 4.0` |
| CDN (T002) | local HTTP server | shard math (WeScan → 0fd, MLKitVision → 81e); 301; 404 → `not_on_cdn`; offline; 24 h refresh; mirror |
| Lock (T003) | crafted `Podfile.lock` | every section; subspecs; nested deps; quoted names; missing sections |
| Resolver (T004) | saved spec JSON | ML Kit (12 pods); goSellSDK Core (17 pods, as requested by plugin 2.4.29); conflict naming both sources; stale lock; prerelease pin; newest version above the deployment target skipped for an older one |
| Consumer view (T005) | synthetic specs | each §8.1 table row; xcconfig merge `parent + " " + child`; `ios:` duplicates removed (MyFatoorah); root files always applied; duplicate files removed (nanopb); no request + no defaults → all iOS subspecs except test/app specs (nested too) |
| Downloader (T006) | local server + archives | zip, tar.gz, tgz, tar.bz2, tar.xz, tar; flatten; checksum mismatch; `../x`, `/x`, `C:\x`; outside symlink; interrupted download; branch → commit; LFS pointer → git fallback; non-iOS xcframework slices skipped |
| Cache (T007) | temp folders | key stability (12 chars); read-only; two processes; stale lock; clear; hard-link failure message |
| Planner (T008) | fake projects | every class and reason; `plugin status --json` schema; status/check make **no network calls** (AC-046-31) |
| Switches, gating, markers (T009) | the 2026-11-15 probe app + fake projects | `off` output identical to today; `XCROSS_POD_SKIP`; disabled kind → `not_yet_supported` (AC-046-25); on → off → on with the same project (AC-046-23) |
| xcconfig (T011) | inline | each variable; `[sdk=]`, `[arch=]`, `[config=]` against device/simulator and debug/distribution; unknown key → `pod.setting_ignored` |
| Binary (T101–T110) | synthetic Mach-O bytes: fat, `FAT_MAGIC_64`, thin, archive, dylib, dylib with `__LLVM`, with/without `.swiftinterface` | xcframework layout and Info.plist; slice platform detection; arm64-only rule (x86_64-only simulator = missing); wrapper target names never collide (MLKitVision); module map generation; linker settings golden files; bitcode only checked in dynamic frameworks |
| Resources (T108) | small bundles | `<Key>.bundle` + `org.cocoapods.<Key>`; plain resources at the root; `Info.plist`/`PrivacyInfo.xcprivacy` never at the root; collision → `pod.resource_clash` |
| Staging + fingerprint (T112) | fake graph | aliases `Packages/pod-<Pod>`; transitive `../pod-Y` resolves; xcframeworks in shared search paths; pod version change → fingerprint changes; same inputs → same fingerprint (AC-046-30) |
| Fallback + report (T113) | injected failures | compile failure → one rebuild without the pod (AC-046-24); `--strict`/distribution → error with hint; pods report written; release check unchanged for a project without converted pods (AC-046-32) |
| Sources (T201–T208) | synthetic specs + small trees | globs (case-insensitive, directory-only defaults, other files not copied); header trees (golden: PromisesObjC `./`, Protobuf alias, GoogleMLKit own map); a header reached two ways parsed once; per-dependent `-I` only (existing plugins unchanged); flag rules (`-Werror` dropped, `-std=` mapped); `${PODS_ROOT}` mapping; ARC split; `COCOAPODS`; `SWIFT_PACKAGE` patches in sources and headers; header-only pods; prefix header (generated, custom contents, own file, `false`) |
| Swift/mixed (T301–T305) | small fixture pods | language modes; ObjC→Swift direction (bridging header, `-Swift.h` patch with module parameter); Swift→ObjC (`@_exported import`); two-way cycle → `objc_uses_own_swift` |
| Graph (T401–T409) | saved specs | shared pod + subspec union; duplicate rule for every converted pod incl. version mapping (nanopb 3.x ↔ 2.x); sibling plugin; own subspec; since fallback; pin conflict; duplicate-symbol message parsing |

Golden files: each research §3 pod gets a golden `Package.swift` and header tree generated from its saved spec JSON.
Specs are metadata and may be saved as fixtures. Vendor source or binaries are never committed.

## 2. What every probe build must show

For each plugin in a probe app:

1. The build log has the expected `build.pod_converted` lines and no `plugin_unknown_pods` for that plugin.
2. `llvm-nm` on `Frameworks/libFlutterPluginsGenerated.dylib` (and on embedded frameworks) shows the plugin's
   registered class and a symbol from each converted pod. This is the check used on 2026-11-15 (research §10).
3. Resource bundles named as in CocoaPods are in the app (`<Key>.bundle`).
4. On a device, a minimal Dart call into the plugin works (table in §4), not just "the app starts".
5. A second build changes nothing in the cache, downloads nothing, and reuses the plugins dylib (AC-046-26, AC-046-30).
6. With `XCROSS_POD_CONVERTER=off`, the same project builds exactly as today (AC-046-23).

## 3. Regression probe (every phase)

The 2026-11-15 probe app must still build with the converter on and off, and must not use the converter for any of its
plugins (they are `swift_package`). It has 9 plugins mapped to known Swift packages, and deployment target 15.0:

| Plugin | Version |
|---|---|
| flutter_inappwebview_ios | 1.1.2 |
| flutter_jailbreak_detection | 1.10.0 |
| video_thumbnail | 0.5.6 |
| image_cropper | 8.0.2 |
| flutter_callkit_incoming | 2.0.4+2 |
| edge_detection | 1.1.3 |
| applovin_max | 4.6.4 |
| facebook_audience_network | 1.0.1 |
| flutter_appauth | 6.0.6 |

## 4. Probe apps per phase

Each probe app is `flutter create` + the listed plugin versions, kept outside the repo in a scratch folder. Run each on
Windows and Linux hosts. Device rows use the hardware listed in ROADMAP (iPhone X iOS 16.7 and one iOS 17+ device).

| Probe | Phase | Plugins (exact versions) | Minimal run-time check on a device |
|---|---|---|---|
| P1-a | 1 | videosdk_webrtc 0.0.19 | create a peer connection / local video track |
| P1-b | 1 | objectbox_flutter_libs 5.3.2 (+ objectbox Dart package) | open a store, put and get one object (FFI symbols found) |
| P1-c | 1 | flutter_vlc_player 7.4.4 (MobileVLCKit 3.6.1b1) | play a bundled short video |
| P1-r | 1 | a tiny local plugin that loads a bundle via `Bundle(for:)` | answers T108's question before resources are built on it |
| P2-a | 2 | qr_code_scanner 1.0.1 | open the camera scanner, read a printed QR code |
| P2-b | 2 | flutter_sound 9.30.0 | record 2 s and play it back |
| P2-c | 2 | flutter_blue 0.8.0 | start a BLE scan (needs Bluetooth permission strings) |
| P2-d | 2 | google_mlkit_text_recognition 0.15.1 + google_mlkit_commons 0.11.1 | recognise text in a bundled image (device only if no arm64 simulator slice) |
| P2-e | 2 | myfatoorah_flutter 3.3.3 (moved from Phase 1: headers inside the xcframework) | initialise the SDK in test mode and open its payment screen; **no real payment** |
| P3-a | 3 | speech_to_text 6.6.2 | `initialize()` returns true |
| P3-b | 3 | go_sell_sdk_flutter 2.4.29 | open the SDK's payment UI in sandbox mode; **no real payment** |
| P3-c | 3 | flutter_braintree 4.0.0 | open Drop-in with a sandbox tokenization key; **no real payment** |
| P3-d | 3 | tflite_flutter 0.12.1 | load a tiny bundled model and run one inference |
| P3-e | 3 | onnxruntime 1.4.1 | run a tiny bundled model |
| P4-a | 4 | firebase_core + firebase_messaging (current) + google_mlkit_text_recognition 0.15.1 | Firebase init + text recognition in one app; no duplicate-class warnings in the device log |
| P4-b | 4 | an old podspec-only stripe_ios version (found in T404) | Stripe init in test mode |
| P4-c | 4 | onesignal_flutter 3.x (OneSignalXCFramework 3.x) | SDK init |
| P4-d | 4 | a probe with an `ios/Podfile.lock` pinning older versions | pinned versions used (build log + `plugin status`) |
| P4-e | 4 | the same probe with a stale lock entry | `pod.lock_stale`; resolver result used |
| P4-f | 4 | a probe whose newest pod version needs a higher iOS than the app | an older compatible version chosen (AC-046-2) |

Payment and account SDKs (MyFatoorah, Tap, Braintree, Stripe) are only opened in their sandbox or test modes: no real
money, no real customer data.

## 5. App Store tests (need owner approval: outward-facing)

Facts first (plan §9.8): none of the Phase 1 probe pods is on Apple's list of commonly used third-party SDKs. The
listed SDKs in research §3 are source pods compiled into the plugins dylib, and OneSignal (listed, binary) appears only
in P4-c. So the tests are split by what they can answer:

| Test | When | IPA | Question |
|---|---|---|---|
| A | end of Phase 1 | P1 apps, `--export-method app-store` | embedded converted frameworks: signing, `MinimumOSVersion`, no bitcode; `release check` passes (AC-046-27) |
| B | end of Phase 4 | P4-c (OneSignal 3.x, a listed SDK shipped as a binary) | does App Store Connect reject a listed SDK without a privacy manifest (expected ITMS-91061)? Does `pod.sdk_privacy_manifest_missing` catch it before upload? |
| C | when T107 finds one | a listed SDK that ships as a legacy `.framework` (re-wrapped by us, unsigned) | are re-wrapped, unsigned SDK frameworks accepted (Q6)? If no such pod exists, record that the question is moot. |

For each test:
1. `xcross release check` first.
2. Upload to TestFlight with the owner's account **only after the owner says yes**.
3. Record App Store Connect's answer (accepted, warnings, rejection codes) in device-check.md.

## 6. Evidence

`specs/046-cocoapods-pods/device-check.md`, one row per probe × host × device:

| Probe | Host | Device / iOS | Build | Run-time check | Date | Notes |
|---|---|---|---|---|---|---|

Values: `passed`, `failed: <short reason>`, `not run: <why>`. Hardware that is not available is `not run`, never
`passed`.

## 7. Acceptance criteria coverage

Every criterion in spec.md §5 and where it is proven. "§2.n" is a check every probe build does (section 2 above).

| AC | Unit tests (tasks) | Probe / device / App Store |
|---|---|---|
| AC-046-1 classes | T008 | all probes (`plugin status`) |
| AC-046-2 version choice | T001, T004 | P4-d, P4-f, P1-c (3.6.1b1) |
| AC-046-3 conflict | T004 | — |
| AC-046-4 stale lock | T003, T004 | P4-e |
| AC-046-5 CDN, offline, not on CDN | T002 | — |
| AC-046-6 downloading | T006 | all probes |
| AC-046-7 download failure | T006 | — |
| AC-046-8 binary forms | T101, T102, T103, T110 | P1 |
| AC-046-9 embedding and signing | T107 | P1, App Store test A |
| AC-046-10 missing slice | T104 | P2-d on the simulator |
| AC-046-11 bitcode | T105 | App Store test A |
| AC-046-12 Swift binaries | T106 | — |
| AC-046-13 source compile rules | T201, T204, T205, T208 | P2 |
| AC-046-14 imports | T202, T203, T206, T207 | P2, P3 |
| AC-046-15 Swift and mixed | T301, T302, T303 | P3 |
| AC-046-16 subspecs | T005, T401 | P2-d (GoogleMLKit subspecs) |
| AC-046-17 resources | T108, T304 | P1-r, P2-d (ML Kit models), P2-e |
| AC-046-18 one package per pod | T401 | P4-a |
| AC-046-19 duplicates with Swift packages | T402 | P4-a |
| AC-046-20 since fallback | T405 | P4-c |
| AC-046-21 siblings, own subspecs | T403, T404 | P2-d, P4-b |
| AC-046-22 unsupported reasons | T008 | — |
| AC-046-23 converter off, markers | T009 | §2.6 on every probe |
| AC-046-24 compile failure fallback | T113 | — |
| AC-046-25 kind gating | T009 | — |
| AC-046-26 deterministic, no re-download | T007 | §2.5 on every probe |
| AC-046-27 release check passes | T107 | App Store tests A, B |
| AC-046-28 concurrent builds | T007 | — |
| AC-046-29 Windows and Linux | (TX2) | every probe on both hosts |
| AC-046-30 fingerprint | T112 | §2.5 on every probe |
| AC-046-31 status/check offline | T008 | — |
| AC-046-32 pods report, release check scope | T113 | App Store test B |
| AC-046-33 four-part warning | T114 (golden text per reason) | every probe that leaves a plugin out (e.g. P2-d on the simulator) |
| AC-046-34 report command, redaction, Studio button | T114, T507 | one report sent from a test build reaches `error_reports` |
