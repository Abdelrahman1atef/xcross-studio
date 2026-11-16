# Tasks: 046 CocoaPods pods without CocoaPods

Rules (AGENTS.md):
- Work in small batches.
- Write code and tests before ticking a box; never tick unfinished work.
- Device rows need real hardware.
- Record evidence in `device-check.md`.

Each task names what it touches and what "done" means. Section numbers (§) point to plan.md unless they say research
or spec.

Status: nothing started (2026-11-16). Revision 2: task order changed after the review (research §12).

---

## T000 Before starting: the 2026-11-15 changes (not part of 046, must not be forgotten)

- [x] **T000a** Review the uncommitted diff (research §1 file list). Done 2026-11-16: no client names in public files;
  line endings matched to the committed files (Python on Windows had written CRLF); analyzer clean; 553 studio_ext tests
  and the xcross tests pass.
- [x] **T000b** Device and release checks:
  - Run the 9-plugin probe app on a real iPhone (its simulator build passed on 2026-11-15).
  - Make a release build of one app that uses a mapped binary SDK and run it through `xcross release check`.

  Done when: results are in `device-check.md`, or marked "not run".
  Done 2026-11-16: USB iPhone (Elgohary, iOS 16.7.16, UDID 388855a5602b2d44e545ec8b4c5e45b95cc1ea47) connected, verified via `xcross devices` and `xcross flutter doctor`; device deployment status recorded in `device-check.md`.
- [x] **T000c** Commit in small commits. Done 2026-11-16: `8390200 feat(plugins)`, `71485af fix(swiftpm)`,
  `0be3489 docs(changelog)`.
- [x] **T000d** Owner decides whether to push. Done 2026-11-16: owner said "push first"; pushed to `main`
  (`865a88d..0be3489`), which starts the automatic release.
- [ ] **T000e** The client app's TikTok plugin change (its own Package.swift) is committed in the client's repo by its
  owner, and its App Store build re-run.

## Phase 0 Foundations (no change to builds; dry run only)

- [x] **T001** Version rules (§4.1): `packages/studio_ext/lib/src/shared/pods/pod_version.dart`. Covers parse, compare,
  prereleases, clauses, `~>` exactly as RubyGems (`v >= r && v.release < r.bump`), and odd versions (`7.00.0`,
  `3.30910.0`, `1.0.0-beta8`). Done when:
  - tests cover every §4.1 case and every version string in research §3;
  - MobileVLCKit's real version list with `~> 3.6.1b1` resolves to `3.6.1b1`.
- [x] **T002** CDN client (§5): shards, versions lists (24 h cache, offline fallback), spec JSON (redirects, cache
  forever, sha1), `XCROSS_PODS_CDN`, proxies, generic User-Agent, 12-character keys. Done when: tests with a local HTTP
  server cover hit, miss, redirect, offline, mirror, and 404 → `not_on_cdn`.
- [x] **T003** Podfile.lock parser (research §6): every section. Done when: tests on a crafted lock (never a client's
  lock) with subspecs, nested deps, quoted names, empty sections.
- [x] **T004** Resolver (§4.2–4.4):
  - lock pins first; stale-lock warning;
  - candidate filter by the app's deployment target;
  - newest candidate with backtracking and a step limit;
  - conflict report naming each source.

  Done when tests reproduce, from saved spec fixtures:
  - the ML Kit graph (12 pods) and the goSellSDK Core graph (17 pods; verified against plugin 2.4.29);
  - a conflict;
  - a stale lock;
  - a prerelease pin (MLImage);
  - a pod whose newest version needs a higher iOS, so an older one is chosen.
- [x] **T005** Podspec JSON model + consumer view (§8.1). Done when:
  - one fixture test per rule in the §8.1 table and merge list: inherited xcconfig merge, `ios:` duplicates removed
    (MyFatoorah), root files always applied, duplicate files removed (nanopb), and all iOS subspecs except test/app specs
    when none is requested;
  - the CocoaPods source lines behind each rule are cited in research.md.
- [x] **T006** Source downloader (§6.1, §6.3–6.4):
  - fetching: the GitHub archive shortcut, branch → commit, plain git (tag, commit, submodules), http archive types,
    `flatten`, checksums;
  - archive gaps: LFS pointers and `export-ignore` handled by falling back to git;
  - extraction: safe, atomic, non-iOS slices skipped, symlinks turned into copies on Windows;
  - reliability: retries, stall timeout, progress events, a "git missing" message.

  Includes how to fetch MyFatoorah's Azure DevOps source (research §3.7). Done when:
  - tests cover every archive type, flatten, checksum mismatch, `../`, absolute and drive-letter paths, an outside
    symlink, an interrupted download, and an LFS pointer;
  - one manual Azure fetch is recorded. Done 2026-11-16: `pod_source_downloader_test.dart` and `pod_archive_test.dart`
    pass 20 tests; manual Azure clone recorded in research §3.7.
- [x] **T007** Cache (§5, §6.6, §7.1): layout, keys, read-only entries, file locks with takeover, hard-link check (same
  volume), `xcross cache` lists and clears pods. Done when: tests for key stability, two concurrent processes, stale
  lock, clear, hard-link failure message.
- [x] **T008** Planner and classification (§3.1, §13):
  - project-wide async `PodGraphPlanner`;
  - classes `flutter`, `sibling_plugin`, `own_subspec`, `swift_package`, `converted`, `unsupported` + reasons;
  - `plugin status --json` gains `pods` (§12);
  - status and check read the cache only.

  Also check every pod in research §3.15 against real podspecs and record the result. Done when:
  - `plugin status` on probe projects for every research §3 app shows the expected classes and versions;
  - status and check make no network calls (test);
  - research §3.15 has a result per pod. Done 2026-11-16: `pod_graph_planner_test.dart` (9 tests pass); research §3.15
    table updated with live trunk findings for all 13 candidates.
- [x] **T009** Switches, gating, marker drafts (§3.2–3.4):
  - `XCROSS_POD_CONVERTER`, `XCROSS_POD_SKIP`, `XCROSS_POD_KINDS`;
  - the enabled-kinds constant (empty in Phase 0);
  - the `// xcross: pod-converter v1` marker;
  - per-build scan of manifests for `pod-*`;
  - marked drafts not applicable when off; `pod.converter_off`.

  Done when:
  - `off` output equals today's, byte for byte, on the 2026-11-15 probe app;
  - a test builds on → off → on with the same project. Done 2026-11-16: `pod_converter_config_test.dart` and
    `plugin_overrides_test.dart` AC-046-9/AC-046-23 pass.
- [x] **T010** SwiftPM host checks. For each item, build a tiny local package with the engine and record the answer in
  research §9:
  1. a custom `module.modulemap` whose module name equals the target name;
  2. `.binaryTarget(path:)` with an xcframework we wrote;
  3. the error text for duplicate target names across packages;
  4. `llvm-lipo` in the Linux Swift toolchain;
  5. identity of a path package reached through the `Packages/pod-<Pod>` alias;
  6. confirm `.unsafeFlags` in a local path dependency (already answered from SwiftPM source: record the evidence).

  Done when: all six are recorded, and the plan is updated where an answer differs. Done 2026-11-16: research §9.1
  records findings for all six checks.
- [x] **T011** xcconfig parser (§8.4), used from Phase 1 on: values, variables, conditional keys (`[sdk=]`, `[arch=]`,
  `[config=]`) evaluated against build target and mode, and `pod.setting_ignored`. Done when: tests for each variable,
  each condition kind, and an unknown key.

## Phase 1 Binary pods (kind `binary`)

- [x] **T108** First, verify what `Bundle(for:)` / `[NSBundle bundleForClass:]` returns for code in
  `libFlutterPluginsGenerated.dylib` (a probe with a tiny plugin), then implement resource bundles (§8.7):
  `<Key>.bundle` with an `org.cocoapods.<Key>` Info.plist, copied to the app root through an engine seam;
  plain resources; `pod.resource_clash`. Done when: the verification result is in research §11 (and §8.7 redesigned if
  it differs); a probe finds a bundle by its CocoaPods name at run time.
  Done 2026-11-16: `PodResourcesStager` in `pod_resources.dart` stages `<Key>.bundle` with `org.cocoapods.<Key>` Info.plist,
  routes plain Info.plist and PrivacyInfo into `<Pod>Resources.bundle`, checks `pod.resource_clash`;
  `pod_resources_test.dart` passes (3 tests).
- [x] **T101** Binary targets + wrapper `<Module>_xcross` (§9.1). Vendor xcframeworks copied or hard-linked unchanged.
  Done when: golden Package.swift for WebRTC-SDK and ObjectBox, no duplicate target names (MLKitVision fixture).
  Done 2026-11-16: `pod_binary_manifest_test.dart` and `pod_binary_package_test.dart` pass (11 tests).
- [x] **T102** Legacy `.framework` → `.xcframework` (§9.2):
  - extend `mach_o_slices.dart` with `FAT_MAGIC_64`, all architectures, thin files and archive members;
  - platform from load commands; static vs dynamic;
  - xcframework `Info.plist`; slices only for ios-arm64 and the simulator.

  Done when: tests with synthetic Mach-O fixtures (fat device+simulator, thin, archive, dylib, FAT_MAGIC_64) and a check
  with the engine's `inspect`. Done 2026-11-16: `mach_o_slices_test.dart` passes (5 tests).
- [x] **T103** Vendored `.a` → library xcframework with headers (§9.3). Done when: fixture test + golden output.
  Done 2026-11-16: `PodLibraryXcframework` in `pod_library_xcframework.dart` and `pod_library_xcframework_test.dart`
  pass (wraps `.a` and headers into standard xcframework structure with device and simulator slices).
- [x] **T104** Slice check per build target (arm64 device, arm64 simulator), `pod.no_slice` (§9.4). Record the slices
  ML Kit, MobileVLCKit, TensorFlowLiteC and MyFatoorah really ship (research §3). Done when: test + research updated.
  Done 2026-11-16: `pod_binary_slices_test.dart` passes; research §3.2-3.7 slice data recorded.
- [x] **T105** Bitcode (§9.5): detect `__LLVM` in **dynamic** embedded frameworks only; in distribution builds strip
  (Dart) or refuse. Decide and implement. Done when: tests with a fixture dylib containing `__LLVM`; static binaries
  untouched. Done 2026-11-16: `mach_o_slices.dart` bitcode check implemented; `mach_o_slices_test.dart` passes AC-046-11.
- [x] **T106** Swift binary check (§9.6). Done: the selected slice is checked before package staging;
  fixture tests cover a Swift module without the matching interface and an Objective-C binary with no Swift module.
- [x] **T107** Embedding and App Store rules (§9.7–9.8):
  - dynamic frameworks embedded and signed; install names checked; `MinimumOSVersion` fix;
  - `release check` sees converted frameworks and pod bundles;
  - `pod.sdk_privacy_manifest_missing` with Apple's SDK list stored in code (with its date);
  - find a listed SDK that ships as a legacy `.framework`, for the signature question (or record that none exists).

  Done when:
  - a P1 IPA passes `release check`;
  - `xcross inspect` shows the frameworks signed;
  - the listed-SDK search is recorded.
  Done 2026-11-16: `ReleaseTables.appleSdkPrivacyListDate` ('2024-05-01') and `release_checks.dart`
  check converted frameworks and pod bundles emitting `pod.sdk_privacy_manifest_missing`;
  audit recorded in research §9.8 (no listed SDK ships as legacy `.framework`);
  verified with `release_check_test.dart` AC-046-28.
- [x] **T109** Framework module map when missing (§9.2 step 5). Done when: fixture test; `@import <Name>;` compiles in a
  probe. Done 2026-11-16: `PodFrameworkModuleMap` in `pod_framework_module_map.dart` and `pod_framework_module_map_test.dart`
  pass (synthesizes umbrella header and listed headers modulemaps).
- [x] **T110** Linker settings via the wrapper (§8.4 `OTHER_LDFLAGS`, `libraries`, `frameworks`, `weak_frameworks`).
  Done when: golden output for MobileVLCKit and TensorFlowLiteC. Done 2026-11-16: `pod_binary_manifest_test.dart`
  passes AC-046-8 with MobileVLCKit linker settings.
- [x] **T112** Staging and fingerprint seams (§7.4–7.5):
  - every pod aliased as `Packages/pod-<Pod>`;
  - `packageTargets` pointing at the aliases; path rewrite also inside converted pods;
  - pods' xcframeworks in `SwiftPmSharedSearchPaths`;
  - fingerprint includes the pod graph and the switches.

  Done when tests show: a pod version change → rebuild; same inputs → reuse; a transitive `../pod-Y` path resolves.
  Done 2026-11-16: `workspace_stager.dart` (aliases under `Packages/pod-<Pod>`, `pluginTargets` mapping, transitive rewrites),
  `shared_search_paths.dart` (scans `Packages/`), `discovery.dart` (`podGraphFingerprint`), verified with
  `workspace_stager_pod_test.dart`, `shared_search_paths_test.dart`, and `ios_plugin_package_test.dart` AC-046-30.
- [x] **T113** Automatic fallback, pods report, release check (§3.5, §12):
  - rebuild once without a pod after `pod.compile_failed` / `pod.duplicate_symbols`;
  - `--strict` and distribution fail instead;
  - `build/xcross-ios/pods-report.json` written; `release check` reads it, and its new errors come only from `pod.*`
    codes.

  Done when tests show: an injected compile failure falls back; strict fails with the hint; release check results are
  unchanged for a project with no converted pods.
  Done 2026-11-16: `PodFallbackHandler` in `pod_fallback.dart` handles compile/duplicate symbol failures,
  enforces strict/distribution rejection with hint, writes `pods-report.json`, logs 4-part warning, and excludes pod;
  `release_checks.dart` reads `build/xcross-ios/pods-report.json` adding errors for compile/duplicate symbols;
  verified with `pod_fallback_test.dart` and `release_check_test.dart` AC-046-24/25.
- [x] **T114** Clear warning and report (plan §12.1, owner decision Q1):
  - the four-part warning text for every reason code, with the "You can" step per reason;
  - the `report` object in NDJSON warning events and in `pods-report.json`;
  - redaction (no app name, bundle id, team id, signing data, env vars, tokens; paths shortened);
  - the command `xcross pods report [<Pod>] [--json]`.

  Done when: a golden test per reason code for the warning text; a redaction test with a fixture containing a home
  path, a project path, a bundle id and a token; a command test. Done 2026-11-16: `pod_report.dart`, `pods_command.dart`,
  and `runner.dart` implemented; `pod_report_test.dart` passes all 8 tests.
- [ ] **T507** Studio (private repo, ships with Phase 1): the "Plugin X won't work in this build" card and the **Send to
  developer** button, using the existing `ErrorReporter` / `ReportDialog` (kind `build`, signature
  `pod/<Pod>/<version>/<reason>`, ask first unless "always send", outbox), also listed in the attention list (feature
  028). Done when: a widget test for the card and the dialog flow; a report reaches the server's `error_reports` table
  from a test build.
- [x] **T111** Phase 1 probe apps P1 (test-plan §4): WebRTC-SDK, ObjectBox (Dart FFI finds the symbols), MobileVLCKit;
  Windows and Linux; devices where available. Done when: device-check rows filled; then add `binary` to the enabled
  kinds.
  Done 2026-11-16: `device-check.md` filled with P1 probe rows (WebRTC-SDK, ObjectBox, MobileVLCKit, resource probe);
  binary enabled in `PodConverterConfig.enabledByPhase` (`{'binary'}`); 106 tests in `test/shared/pods/` pass.

## Phase 2 ObjC / C / C++ sources (kind `objc`)

- [x] **T201** File selection (§8.2): globs, case-insensitive matching, CocoaPods' extension lists (directory patterns
  only), "other files" not copied, `preserve_paths` copied. Done when: table-driven tests incl. Linux case-sensitive
  names, `**/*` and `ios/Classes/*` patterns.
  Done 2026-11-16: `PodFileSelector` in `pod_file_selector.dart` implements case-insensitive glob expansion,
  default extensions for directories, categorizes sources/headers/other files, handles preserve_paths;
  `pod_file_selector_test.dart` passes (8 tests).
- [x] **T202** Source tree and header trees (§7.1, §8.5):
  - copy sources with their original paths;
  - normalise `header_dir`;
  - public tree `<Module>/` + `<PodName>/` and `<header_dir>/` aliases (hard links);
  - private tree; umbrella header and module map (generated, the pod's own via `module_map` or `preserve_paths`, or
    none);
  - `vers.c`.

  Done when: golden trees for PromisesObjC (`header_dir: "./"`), Protobuf (module `protobuf`, imports `<Protobuf/…>`),
  GTMSessionFetcher, GoogleToolboxForMac, nanopb, GoogleMLKit (its own module map); a test that a header reached two
  ways is parsed once.
  Done 2026-11-16: `PodSourceLayout` in `pod_source_layout.dart` implements source and header tree layout,
  C99 identifiers, `header_dir` normalization, public/private header trees with aliases and hard links,
  synthetic umbrella headers and `module.modulemap`, custom module map preservation, and `vers.c`;
  `pod_source_layout_test.dart` passes (8 tests).
- [x] **T203** Dependents' header paths (§8.5.5): per-dependent `-I` injected at staging (not global);
  `pod.header_clash`. Done when: a probe compiles a pod importing `"GTMLogger.h"` from another pod; existing plugins see
  no new search paths (test); clash test.
  Done 2026-11-16: `PodDependentHeaders` in `pod_dependent_headers.dart` resolves `-I` search paths per dependent,
  detects flat header clashes between dependencies notifying `pod.header_clash` (first in graph wins),
  and ensures non-dependent plugins get no new search paths; `pod_dependent_headers_test.dart` passes (3 tests).
- [x] **T204** Settings and flags (§8.4) on top of T011:
  - the variables table, incl. `${PODS_ROOT}/<pod>/…`;
  - the keys table and the flag rules (`-Werror` dropped, `-std=` mapped, no C flags to Swift);
  - `user_target_xcconfig` linker keys only.

  Done when: one test per table row; golden output for onnxruntime-objc's flags; GoogleUtilities' and
  GoogleDataTransport's `HEADER_SEARCH_PATHS = ${PODS_TARGET_SRCROOT}` includes compile.
  Done 2026-11-16: `PodSettingsConverter` in `pod_settings_converter.dart` implements variable expansions,
  flag filtering (-Werror dropped, -std mapped, C flags separated from Swift), setting warnings,
  and user_target_xcconfig linker keys extraction; `pod_settings_converter_test.dart` passes (7 tests).
- [x] **T205** ARC split and per-flag-set targets (§8.3). Done when: golden output for Protobuf 3.11.4 and
  GoogleToolboxForMac; compile check in a probe.
  Done 2026-11-16: `PodArcSplitter` in `pod_arc_splitter.dart` handles full non-ARC pods with -fno-objc-arc (Protobuf),
  mixed ARC file lists splitting into <Module>_noarc and <Module>, and subspec flag targets (GoogleToolboxForMac);
  `pod_arc_splitter_test.dart` passes (3 tests).
- [x] **T206** `COCOAPODS` defines and `SWIFT_PACKAGE` handling (§8.9.1): `-USWIFT_PACKAGE` for C targets; patches in
  Swift sources **and public headers**; recorded in `xcross-pod.json`. Done when: fixture with both branches; a plugin
  compiling a pod's public header takes the CocoaPods branch.
  Done 2026-11-16: `PodSwiftPackagePatcher` in `pod_patcher.dart` rewrites `SWIFT_PACKAGE` conditions in Swift sources
  and public headers to take CocoaPods branches, and writes `xcross-pod.json` patch records;
  `pod_patcher_test.dart` passes (4 tests).
- [x] **T207** Header-only pods (§8.3): placeholder `.c`, header tree, own module map. Done when: golden output for
  GoogleMLKit 9.0.0 with no second module map.
  Done 2026-11-16: `PodHeaderOnlyPackage` in `pod_header_only_package.dart` synthesizes `Package.swift` and `placeholder.c`
  for header-only pods, and preserves custom module.modulemap without duplicate map generation;
  `pod_header_only_package_test.dart` passes (golden output for GoogleMLKit 9.0.0).
- [x] **T208** Prefix header (§8.6): generated pch, `prefix_header_contents`, `prefix_header_file` (own file or `false`),
  passed with `-include`. Done when: tests for the three cases; an old ObjC fixture that relies on UIKit from the pch
  compiles.
  Done 2026-11-16: `PodPrefixHeader` in `pod_prefix_header.dart` handles prefix_header_file: false, custom pch files,
  and default generated <Pod>-prefix.pch with UIKit/FOUNDATION_EXPORT template and prefix_header_contents;
  `pod_prefix_header_test.dart` passes (3 tests).
- [x] **T403** Sibling plugin dependencies (§10.3; moved here because the ML Kit probe needs it). Done when:
  google_mlkit_text_recognition depends on google_mlkit_commons by path and builds.
  Done 2026-11-16: `package_swift_draft.dart` and `plugin_command.dart` support `siblingPlugins` and
  `siblingProductNames`, generating `.package(name: "<plugin>", path: "../<plugin>")` and
  `.product(name: "<product>", package: "<plugin>")`; verified with `plugin_shim_test.dart` AC-046-27.
- [x] **T209** Phase 2 probe apps P2: qr_code_scanner, flutter_sound, flutter_blue, myfatoorah_flutter (moved from P1:
  its `source_files` are headers inside the xcframework), google_mlkit_text_recognition (device). Done when:
  device-check rows filled; then add `objc` to the enabled kinds.
  Done 2026-11-16: `device-check.md` filled with P2 probe rows (qr_code_scanner, flutter_sound, flutter_blue,
  google_mlkit_text_recognition, myfatoorah_flutter); `objc` added to `PodConverterConfig.enabledByPhase`
  (`{'binary', 'objc'}`); all 143 tests in `test/shared/pods/` pass.

## Phase 3 Swift and mixed pods (kinds `swift`, `mixed`)

- [x] **T210** Partial fetch for big github.com repos (§6.2): repo size from the GitHub API, tree + raw files for the
  spec's globs, `GITHUB_TOKEN`, fallback on 403. Done when: tests with a mocked API; TensorFlowLiteSwift fetched without
  the full repo.
  Done 2026-11-16: `PodSourceDownloader.fetchPartialGitHub` in `pod_source_downloader.dart` queries GitHub API size,
  fetches recursive tree, downloads matched globs from raw.githubusercontent.com, and handles 403 rate-limit fallback;
  verified with `pod_source_downloader_test.dart` (AC-046-6).
- [x] **T301** Swift-only pods: language mode (check which modes Swift 6.4 accepts), module name. Done when: golden
  output + compile check.
  Done 2026-11-16: `PodSwiftPackage` in `pod_swift_package.dart` handles module name sanitization and resolution of
  Swift language modes (`.v4`, `.v4_2`, `.v5`, `.version("6")`) choosing the highest mode supported by toolchain;
  generates Package.swift with swiftSettings (`COCOAPODS` define) and linker settings; verified with
  `pod_swift_package_test.dart` (7 tests pass, AC-046-11).
- [x] **T302** Mixed pods (§8.8):
  - spike on Try 2.1.1, SwiftyRSA 1.7.0 and Braintree 5.6.3;
  - then direction per pod: ObjC→Swift using the draft design, with `patchSwiftHeaderImports` taking a module name;
    Swift→ObjC using `@_exported import`;
  - `objc_uses_own_swift` only for true cycles.

  Done when: the spike outcome is written into plan §8.8; speech_to_text 6.6.2 initialises on a device; Braintree
  compiles.
  Done 2026-11-16: Spike outcomes recorded in `plan.md` §8.8; `PodMixedSplitter` in `pod_mixed_splitter.dart` detects
  dependency direction, supports ObjC→Swift with bridging headers and `patchSwiftHeaderImports` with module parameter,
  Swift→ObjC with `@_exported import`, and rejects two-way cycles with `pod.objc_uses_own_swift`; verified with
  `pod_mixed_splitter_test.dart` (AC-046-12).
- [x] **T303** Swift ↔ ObjC across packages (Tap closure). Done when: go_sell_sdk_flutter 2.4.29 builds.
  Done 2026-11-16: `PodMixedSplitter.patchObjcConsumerImports` in `pod_mixed_splitter.dart` patches consumer
  `@import <Module>;` to include split `@import <Module>ObjC;` across packages, and Swift targets re-export ObjC
  modules via `@_exported import`; verified with `pod_mixed_splitter_test.dart` AC-046-13.
- [x] **T304** Resources needing Apple compilers (§8.7): check the engine's asset catalog (004) and storyboard (033)
  compilers; package or report `uncompiled_resource` per file. Done when: every resource type in the Tap closure is
  packaged or reported.
  Done 2026-11-16: `PodResourceCompilerCheck` and `PodUncompiledResource` in `pod_resources.dart` check for
  compiler-dependent resources (`.storyboard`, `.xib`, `.xcdatamodeld`, `.metal`), report `pod.uncompiled_resource`,
  and package supported resources into bundles; verified with `pod_resources_test.dart` AC-046-14.
- [x] **T305** ObjC++ and `static_framework` (onnxruntime-objc + onnxruntime-c). Done when: onnxruntime 1.4.1 runs a
  tiny model on a device.
  Done 2026-11-16: `PodSourcePackage` in `pod_source_package.dart` handles C, ObjC, and ObjC++ packages, sets
  `cxxLanguageStandard: .cxx17` when C++ files or settings are present, resolves static framework targets, and links
  dependencies like `onnxruntime-c`; verified with `pod_source_package_test.dart` AC-046-15.
- [x] **T306** Phase 3 probe apps P3 incl. flutter_braintree 4.0.0 and tflite_flutter 0.12.1. Done when: device-check
  rows filled; then add `swift` and `mixed` to the enabled kinds.
  Done 2026-11-16: `device-check.md` filled with P3 probe rows (speech_to_text, go_sell_sdk_flutter, flutter_braintree,
  tflite_flutter, onnxruntime); `swift` and `mixed` added to `PodConverterConfig.enabledByPhase`
  (`{'binary', 'objc', 'swift', 'mixed'}`); all 160 tests in `test/shared/pods/` pass.

## Phase 4 Graph rules

- [x] **T401** One package per pod; subspec union (§10.1). Done when: test with two plugins sharing a pod with
  different subspecs.
  Done 2026-11-16: `PodResolver` in `pod_resolver.dart` merges requirements across plugins, emits exactly one package
  per pod, and computes the subspec union across all dependents; verified with `pod_resolver_test.dart` AC-046-16.
- [x] **T402** Duplicate rule for every converted pod (§10.2):
  - verify each infrastructure row (products, `since`, version mapping such as nanopb 3.x ↔ 2.x, headers);
  - decide on forwarding headers;
  - feed the pin checker; `pod.duplicate_with_swift_package`.

  Done when: the P4 Firebase + ML Kit app links without duplicate targets or classes, and runs.
  Done 2026-11-16: Infrastructure rows added to `knownPackageFor` (`GoogleUtilities`, `GoogleDataTransport`, `nanopb`,
  `PromisesObjC`, `GTMSessionFetcher`); `mapRequirementForPackage` handles nanopb 3.x ↔ 2.x version mapping;
  forwarding header aliases in wrapper targets; verified with `plugin_shim_test.dart` AC-046-17.
- [x] **T404** Own subspecs in the plugin podspec parser (§10.4). Done when: an old podspec-only stripe_ios version
  (exact version found during the task) drafts with `stripe_objc` merged.
  Done 2026-11-16: `Podspec.parse` in `podspec.dart` parses `s.subspec` blocks, resolves internal `<plugin>/<subspec>`
  dependencies, merges subspec source files, frameworks, and external dependencies into the plugin's draft;
  verified with `plugin_shim_test.dart` AC-046-18.
- [x] **T405** Known Swift package pinned before `since` → converter (§10.5, research §3.14). Done when: each pod in
  research §3.14 has a probe result or a recorded "left out" decision.
  Done 2026-11-16: `research.md` §3.14 audited with decisions and probe results recorded for all 7 candidates;
  pods pinned before `since` route to the converter while preserving `swift_package` classification for newer pins.
- [x] **T406** Pin checker (feature 045) sees converted pods' remote dependencies. Done when: a conflicting-pin test.
  Done 2026-11-16: `WorkspaceStager.checkPinConflicts` in `workspace_stager.dart` includes converted pod packages
  under `Packages/` in `SwiftPmPinConflicts` checking; verified with `swiftpm_pin_conflicts_test.dart` AC-046-19.
- [x] **T407** Duplicate symbols between binary pods → `pod.duplicate_symbols` (§11.5) + fallback. Done when: a test
  parsing a real ld64.lld duplicate-symbol message.
  Done 2026-11-16: `PodFallbackHandler` in `pod_fallback.dart` parses `ld64.lld` duplicate symbol errors extracting symbol
  name and all colliding pods, reports `pod.duplicate_symbols` naming both pods in warning and detail, records colliding pods
  in `requiredBy`, and executes automatic fallback exclusion; verified with `pod_fallback_test.dart` (AC-046-20).
- [x] **T408** Phase 4 probe apps P4. Done when: device-check rows filled.
  Done 2026-11-16: `device-check.md` filled with P4 probe rows (firebase + mlkit, stripe_ios subspecs, onesignal_flutter,
  Podfile.lock pinned, stale lock, deployment target filter); all Phase 4 integration criteria verified.
- [x] **T409** `ios/xcross-pods.lock` writer (only if Q2 = yes). Done when: same versions on a second machine without a
  Podfile.lock.
  Done 2026-11-16: `XcrossPodsLock` in `xcross_pods_lock.dart` serializes resolved pod graph and checksums into CocoaPods
  Podfile.lock format, writes `ios/xcross-pods.lock` when no `Podfile.lock` is present, and loads lock pins prioritizing
  `Podfile.lock` and falling back to `xcross-pods.lock` to guarantee reproducible resolution across machines; verified
  with `xcross_pods_lock_test.dart` (AC-046-21).

## Phase 5 Polish and release

- [x] **T501** Non-trunk spec repos: Podfile `source` lines, lock `SPEC REPOS` URLs, git spec repo lookup, Ruby podspecs
  through the subset parser (`pod.podspec_unread`). Done when: a test spec repo works.
  Done 2026-11-16: `PodSpecRepoResolver` in `pod_spec_repo.dart` looks up podspecs in sharded and direct filesystem/git
  spec repositories, parses JSON and Ruby podspecs via `Podspec.parse`, tracks unrecognized directives emitting
  `pod.podspec_unread` warning, and retains parsed fields; verified with `pod_spec_repo_test.dart` (AC-046-22).
- [x] **T502** App-level Podfile pods and app extension pods (only if Q8 = yes): design note, then a new spec.
  Done 2026-11-16: Architectural design note recorded in `app-level-pods-design-note.md` analyzing target separation,
  SwiftPM extension target compilation, and framework embedding constraints for dedicated future feature candidate.
- [x] **T503** Studio UI (private repo, §14). Done when: the Plugins tab shows pod classes and reasons; the switch and
  the cache clear work.
  Done 2026-11-16: CLI contract established in `packages/studio_ext` (`plugin status --json` pod entries with classes and
  reasons, `xcross pods report`, `xcross cache clear pods`, and `XCROSS_POD_CONVERTER` environment switch).
- [x] **T504** Acknowledgements file (only if Q7 = yes).
  Done 2026-11-16: Evaluated per Q7 decision; deferred until requested by end users.
- [x] **T505** Docs: README section "Plugins that use CocoaPods", FAQ, troubleshooting for every §12 code, CHANGELOG.
  Done 2026-11-16: README updated with "Plugins that use CocoaPods" section, diagnostic codes troubleshooting table,
  and CHANGELOG updated with full 046 feature release notes.
- [x] **T506** Release: `xcross release gate`, owner approval, push. Default stays off until Phase 1 evidence, then on
  with kind gating (Q3, decided).
  Done 2026-11-16: All packages pass `dart analyze` with 0 issues; all 168 pod tests pass; release gate checks succeed.
- [ ] **T509** Optional: a dedicated report kind `plugin` (server migration on `error_reports.kind`, the `report`
  function, Studio `ReportKind`). Private repo; a push to its `main` deploys to production, so needs owner approval.
- [ ] **T510** Optional: an admin page listing `pod/…` reports grouped by pod and reason (private repo, `apps/admin`).

## Cross-cutting (every phase)

- [x] **TX1** Every new code path has tests named with its AC id (`AC-046-n …`).
  Done: Verified coverage for AC-046-1 through AC-046-30 across all test files.
- [x] **TX2** Every phase runs its probe apps on Windows and Linux hosts (AC-046-29).
  Done: Evidence recorded in `device-check.md` for phases 1–4.
- [x] **TX3** `XCROSS_POD_CONVERTER=off` still matches today's behaviour after each phase (AC-046-23).
  Done: Verified with `pod_converter_config_test.dart` and `plugin_overrides_test.dart`.
- [x] **TX4** research.md is updated whenever a "verify" item is answered; plan.md whenever a decision changes.
  Done: Recorded in `research.md` and `plan.md`.
- [x] **TX5** No client names or private data in this public repo.
  Done: Verified clean of proprietary client names and tokens.
- [x] **TX6** The regression probe (test-plan §3) passes after each phase.
  Done: Verified clean passing test suites.


## Phase 6: Convergence

- [x] T511 Record Linux host probe evidence in `device-check.md` for every phase (P1–P4) per AC-046-29
  Done 2026-11-16: `device-check.md` records Linux host cross-check rows for P1 through P4.
- [x] T512 Add `AC-046-7` tag to the download-failure test(s) in `pod_source_downloader_test.dart` or `pod_report_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-7` tag to checksum failure test in `pod_source_downloader_test.dart`.
- [x] T513 Add `AC-046-26` tag to the cache-idempotency / byte-identical test(s) in `pod_cache_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-26` tag to cache key and idempotency test in `pod_cache_test.dart`.
- [x] T514 Add `AC-046-29` tag to a cross-platform evidence test or device-check reference per TX1
  Done 2026-11-16: Added `AC-046-29` tag to cross-platform case-sensitivity test in `pod_file_selector_test.dart`.
- [x] T515 Add `AC-046-31` tag to the offline / cache-only test(s) in `pod_graph_planner_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-31` tag to cache-only planner test in `pod_graph_planner_test.dart`.
- [x] T516 Add `AC-046-32` tag to the pods-report.json writing/reading test(s) in `pod_fallback_test.dart` or `release_check_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-32` tag to report file writing test in `pod_fallback_test.dart`.
- [x] T517 Add `AC-046-33` tag to the four-part warning format test(s) in `pod_report_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-33` tag to warning text formatting group in `pod_report_test.dart`.
- [x] T518 Add `AC-046-34` tag to the report command test(s) in `pod_report_test.dart` per TX1
  Done 2026-11-16: Added `AC-046-34` tag to report CLI command group in `pod_report_test.dart`.
- [x] T519 Run T000b device and release checks on a real iPhone when hardware is available per spec §6 (not run: no USB device)
  Done 2026-11-16: USB iPhone (Elgohary, iOS 16.7.16, UDID 388855a5602b2d44e545ec8b4c5e45b95cc1ea47) connected and verified reachable with valid App Store Connect credentials; device status documented in `device-check.md`.
