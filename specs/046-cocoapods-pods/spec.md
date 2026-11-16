# Feature Specification: Build CocoaPods-only pods without CocoaPods

**Feature Branch**: `046-cocoapods-pods` | **Created**: 2026-11-16 | **Status**: Planned (not started)

**Files in this folder**

| File | What it is |
|---|---|
| [spec.md](spec.md) | This file: the problem, goals, scope, acceptance criteria |
| [research.md](research.md) | Every fact the plan relies on, with how it was checked; full pod inventory |
| [plan.md](plan.md) | The design, decision by decision, phases, risks, open questions |
| [tasks.md](tasks.md) | The ordered task list with "done when" for each task |
| [test-plan.md](test-plan.md) | Unit fixtures, probe apps, device and App Store checks, evidence rules |

**Input**: Some Flutter iOS plugins depend on pods that have no Swift package (Google ML Kit, WebRTC-SDK, MobileVLCKit,
TensorFlow Lite, flutter_sound_core, MTBBarcodeScanner, goSellSDK, MyFatoorah, Braintree, …). xcross builds plugins
only through Swift Package Manager, so today it leaves those plugins' native code out (`build.plugin_unknown_pods`) and
the app fails at run time. On 2026-11-16 the owner asked whether xcross can work with CocoaPods, "even if we make it
from scratch". Chosen direction: **do not run CocoaPods; convert each pod into a local Swift package** that the
existing SwiftPM build compiles ("the pod converter").

## 1. The problem in one paragraph

A plugin that ships only a podspec gets a drafted `Package.swift`. The draft can only use pods that map to a known Swift
package. For any other pod the plugin is left out of the app with a warning. The developer often learns about it only
when the feature fails on a phone. research.md §3 lists every such pod found in a scan of the most used pub.dev
plugins, with versions, sources and the podspec features each one needs.

## 2. Goals

- **G1** A plugin whose pods have no Swift package still gets its native code into the app, built on Windows or Linux,
  without a Mac, CocoaPods, Ruby or Xcode.
- **G2** When the project has `ios/Podfile.lock`, the same pod versions as a Mac build are used.
- **G3** Imports behave as with CocoaPods (`#import <Pod/Header.h>`, `#import "Header.h"`, `@import Pod;`,
  `import Pod`), so plugin sources need no patching.
- **G4** Nothing that builds today fails because of this feature. Order of preference: the plugin's own
  `Package.swift` → the developer's override → known Swift package (existing list) → **converted pod** → left out with
  the existing warning. A converted pod that fails to compile makes the engine rebuild once without it (plan §3.5).
- **G5** Every failure names the pod, the plugin that needs it, the reason, and what the developer can do.
- **G6** Builds are reproducible: the same inputs produce byte-identical generated packages, and repeated builds do not
  download or regenerate anything.

## 3. Non-goals

- Running CocoaPods, Ruby or Xcode; generating `Pods.xcodeproj`.
- Running a pod's `prepare_command` or `script_phases` (reported as unsupported).
- Podfile `post_install` hooks in general (the existing `permission_handler` macro support stays).
- macOS, tvOS and watchOS slices.
- Redistributing pod sources or binaries. Pods are downloaded on the developer's machine at build time, as CocoaPods
  does.
- x86_64 simulator builds (the engine builds arm64 only).
- Phases 0–4: private spec repositories, app-level Podfile pods, app extension targets (Phase 5, decision needed: plan
  §17 Q8).

## 4. What the developer sees

- **Build**: one line per converted pod, then nothing on later builds (cached):
  `[build.pod_converted] Pod "MLKitVision 10.0.0" (for google_mlkit_commons) is built from its CocoaPods spec.`
- **A plugin left out**: a clear four-part warning (what, why, what you can do, how to report it), plan §12.1:
  `⚠ Plugin "x" is left out of this build: its features will not work in the app.` / `Why: pod "Y 1.2" runs a
  prepare_command, which xcross cannot run.` / `You can: nothing on your side; this pod is not supported yet.` /
  `Report: send this to the xcross developers so they can fix it: xcross pods report Y`.
- **Studio**: a "Plugin X won't work in this build" card with a **Send to developer** button (existing report flow).
- **`xcross plugin status --json`**: each pod of a plugin with its classification (AC-046-1); the plugin keeps kind
  `draft`. A pod that is not on the CDN is still `unknown_pods`. Status and check never use the network (AC-046-31).
- **`xcross ios prepare`**: resolves, downloads and converts pods ahead of the first build, with progress events.
- **`xcross cache`**: shows and clears the pod caches.
- **Studio** (private repo, seam only): the Plugins tab shows "Built from CocoaPods spec" per pod, and the reason when
  unsupported.

## 5. Acceptance criteria

Each criterion is tested as described in test-plan.md.
- "Left out" means today's behaviour: the build succeeds, the plugin is not linked, and a warning names it.
- "Distribution build" means a build for App Store / TestFlight (`forDistribution`), not every `--release`.

### Classification and versions

1. **AC-046-1** Every dependency of a podspec-only plugin gets exactly one class: `flutter` (the Flutter pod),
   `sibling_plugin` (another Flutter plugin of the project), `own_subspec` (a subspec of the plugin's own podspec),
   `swift_package` (known Swift package and the requested version is at or after `since`), `converted` (pod built by
   the converter), or `unsupported` (with a reason code from plan §12). `plugin status --json` lists them per plugin.
2. **AC-046-2** Version choice:
   - A `PODS:` entry in `ios/Podfile.lock` wins when it satisfies every current requirement and the app's deployment
     target.
   - Otherwise the newest version wins that satisfies every requirement from every plugin and every pod in the graph,
     and whose iOS minimum the app's deployment target allows.
   - CocoaPods/RubyGems version rules apply: `~>` holds when `v >= r` and `v.release < r.bump`, so `~> 3.6.1b1`
     allows only `3.6.1b1` from MobileVLCKit's versions. Prereleases are chosen only when a requirement or the lock
     names one.
3. **AC-046-3** No version satisfies every requirement → the plugin is left out with `pod.resolve_conflict`, naming
   each requirement and who asked for it.
4. **AC-046-4** A stale Podfile.lock entry (its pinned version no longer satisfies a requirement) is not used for that
   pod, and `pod.lock_stale` says so.

### Fetching

5. **AC-046-5** Specs come from the CocoaPods CDN (research §5) and are cached. Cached specs are used offline. A pod
   that is not on the CDN is `unsupported: not_on_cdn`, shown as today's `unknown_pods`.
6. **AC-046-6** Downloading:
   - Sources are downloaded once per (URL, resolved commit or tag) into the cache.
   - git (tag, commit, branch resolved to a commit, submodules) and http (`zip`, `tar.gz`/`tgz`, `tar.bz2`, `tar.xz`,
     `tar`, `flatten`, `type`) are supported.
   - A declared `sha256`/`sha1` is checked.
   - Extraction refuses absolute paths, `..` and links leading outside the folder, and skips non-iOS slices of vendor
     xcframeworks.
   - Nothing from a download is run.
7. **AC-046-7** A failed download leaves the plugin out with `pod.download_failed`, naming the pod, the URL and the
   HTTP or git error, with a hint (network, proxy, git missing, offline cache).

### Binary pods

8. **AC-046-8** Binary forms:
   - A vendored `.xcframework` is used unchanged (signature kept) as a local binary target.
   - A vendored `.framework` (fat or thin, static or dynamic) becomes an `.xcframework` with one slice per platform.
   - A vendored `.a` is linked with its headers reachable.
   - Linker settings go on a wrapper target, and target names never collide.
9. **AC-046-9** Dynamic frameworks from converted pods are embedded in `Frameworks/` and signed like the existing binary
   targets; static ones are linked into the plugins library.
10. **AC-046-10** A binary with no slice for the build's target (arm64 device or arm64 simulator; an x86_64-only
    simulator slice counts as missing) leaves the plugin out of that build with `pod.no_slice`, naming the pod, the
    slices it has and the one needed. Builds for the other target are not affected.
11. **AC-046-11** A **dynamic** embedded framework containing bitcode never reaches a distribution IPA: it is stripped,
    or the plugin is left out of distribution builds with `pod.bitcode` (plan §9.5, T105). Static binaries need nothing
    (the linker drops bitcode).
12. **AC-046-12** A Swift binary framework without a `.swiftinterface` for the slice leaves the plugin out with
    `pod.swift_binary_incompatible`.

### Source pods

13. **AC-046-13** ObjC, C and C++ source pods compile with:
    - their files selected as CocoaPods selects them (case-insensitive globs, default extensions only for directory
      patterns, non-source files never compiled);
    - `requires_arc` (non-ARC files with `-fno-objc-arc`);
    - `compiler_flags` and `pod_target_xcconfig`, translated by plan §8.4: `-Werror` always dropped, `-std=` mapped to
      language standards, conditional keys evaluated;
    - `frameworks`, `weak_frameworks`, `libraries`;
    - the CocoaPods prefix header (generated, custom contents, own file, or none when `prefix_header_file` is false).
14. **AC-046-14** Imports work as with CocoaPods under `use_frameworks!` (Flutter's template):
    - `#import <Module/Header.h>`, plus `<PodName/…>` and `<header_dir/…>` when they differ;
    - a pod's own non-public headers as `<Module/X.h>`;
    - `#import "Header.h"` within a pod and from pods or plugins that depend on it;
    - `@import Module;` in ObjC and `import Module` in Swift.

    `module_name`, `header_dir` (`.`/`./` = none), `header_mappings_dir`, public, private and project headers, a custom
    `module_map` or `module_map: false`, and a pod-shipped module map are all honoured. A header reachable two ways is
    parsed once. Plugins that do not depend on a pod see none of its headers.
15. **AC-046-15** Swift pods compile in the highest language mode their `swift_versions` and the toolchain allow.
    Mixed Swift/ObjC pods are split with the dependency direction their sources need (ObjC using the pod's Swift, or
    Swift using its ObjC). `import Module` (Swift), `@import Module;` and `#import <Module/Module-Swift.h>` (ObjC) keep
    working. A true two-way cycle is `unsupported: objc_uses_own_swift`.
16. **AC-046-16** Subspecs are merged into one package per pod:
    - which: the requested ones; else `default_subspecs` (list, string or `:none`); else every subspec that supports
      iOS, never test or app specs;
    - attributes: inherited or per-spec as CocoaPods' consumer rules say (plan §8.1); `ios:` values merged; duplicate
      entries removed.
17. **AC-046-17** Resources are placed as plan §8.7 says:
    - `resource_bundles` → `<Key>.bundle` at the app root, with an `org.cocoapods.<Key>` identifier;
    - plain `resources` → the app root when no name collides;
    - `Info.plist` and `PrivacyInfo.xcprivacy` → never at the app root;
    - any collision → `pod.resource_clash`, plugin left out;
    - files needing Apple compilers → compiled by the engine or `uncompiled_resource`;
    - privacy manifests are kept.

### Graph

18. **AC-046-18** A pod needed by several plugins is converted and linked once, with the union of their subspecs.
19. **AC-046-19** Every converted pod that is also published as a remote Swift package (the known-package table plus
    the infrastructure pods in plan §10.2) is never built twice. Its Swift package product is used when versions can
    agree (with version mapping, e.g. nanopb); otherwise the plugin is left out with
    `pod.duplicate_with_swift_package`, showing both versions. This is decided before compiling.
20. **AC-046-20** A known Swift package pinned before its `since` version (left out today) is built from the exact pod
    instead, unless AC-046-19 applies.
21. **AC-046-21** Sibling plugin dependencies link to that plugin's package; own-subspec dependencies are merged into
    the plugin's draft.

### Unsupported cases, switches, fallback

22. **AC-046-22** A pod with `prepare_command` or `script_phases`, a pod without iOS support, or (until Phase 5) a pod
    from a non-trunk spec repo is `unsupported` with its reason; the plugin is left out; the build does not fail.
23. **AC-046-23** `XCROSS_POD_CONVERTER=off` gives exactly today's behaviour. Drafts written with converted pods carry
    the `// xcross: pod-converter v1` marker and are ignored when the converter is off (plugin left out). Turning the
    converter off and on again with the same project works without manual cleanup.
24. **AC-046-24** Compile and link failures:
    - A compile or link failure inside a converted pod (`pod.compile_failed`, `pod.duplicate_symbols`) makes the engine
      rebuild once without that pod. Its plugins are left out, and the warning names the pod, the plugin and the first
      compiler error.
    - With `--strict` or in a distribution build, the build fails instead, with the hint `XCROSS_POD_SKIP=<Pod>`.
    - `XCROSS_POD_SKIP` makes the listed pods `unsupported: skipped_by_user`.
25. **AC-046-25** A pod whose kind (`binary`, `objc`, `swift`, `mixed`) is not enabled yet is
    `unsupported: not_yet_supported`, even with the converter on. Kinds are enabled phase by phase.

### Product quality

26. **AC-046-26** Generated packages are byte-identical for identical inputs, and a repeated build neither downloads
    nor rewrites them.
27. **AC-046-27** A distribution IPA with converted pods passes `xcross release check` (privacy manifests, framework
    `MinimumOSVersion`, no bitcode, signed frameworks). `release check` warns `pod.sdk_privacy_manifest_missing` for an
    SDK on Apple's list without a manifest.
28. **AC-046-28** Two builds at the same time share the cache safely (lock, no half-written folders).
29. **AC-046-29** The same behaviour on Windows and Linux hosts.
30. **AC-046-30** Changing a pod's version, the converter version, or an `XCROSS_POD_*` setting rebuilds the plugins
    library; identical inputs reuse it.
31. **AC-046-31** `plugin status` and `plugin check` use the cache only (no network, no compiling). `ios prepare` and
    builds run every step.
32. **AC-046-32** Builds write `build/xcross-ios/pods-report.json`. `release check` reads it, and its new errors come only
    from `pod.*` codes, so results for projects without converted pods do not change. `ios prepare --strict` and
    distribution `release check` report `pod.*` warnings as errors (plan Q1).
33. **AC-046-33** Every "plugin left out" warning has the four parts of plan §12.1 in this order: what (plugin and
    that its features will not work), why (pod, version, reason in plain words), what the developer can do (or
    "nothing on your side"), and how to report it. Tested per reason code.
34. **AC-046-34** Reporting (owner decision Q1):
    - `xcross pods report [<Pod>] [--json]` prints the report of each left-out plugin from the last pods report, with
      the fields of plan §12.1.
    - Reports never contain the app name, bundle id, team id, signing data, environment variables or tokens; paths are
      shortened.
    - In the Studio, the **Send to developer** button sends it through the existing report flow: it asks first unless
      "always send" is on, queues when offline, and sends one report per signature.

## 6. Done means

All acceptance criteria pass their tests in test-plan.md. Device evidence is recorded in `device-check.md`, and no row
is marked passed without the hardware (AGENTS.md). Every pod in research.md §3 is either built in a probe app or listed
as unsupported with a reason the developer sees.
