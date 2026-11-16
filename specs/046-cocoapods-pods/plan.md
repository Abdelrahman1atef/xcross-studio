# Plan: 046 CocoaPods pods without CocoaPods

Read spec.md first (goals, acceptance criteria) and research.md (the facts). This file says **how**: each design
decision in the order the data flows, then phases, risks and the questions the owner must answer.

Revision 2 (2026-11-16): an independent review found 27 problems in revision 1. All are fixed below; research.md §12
lists each finding and where it was resolved.

Revision 3 (2026-11-16): the owner decided Q1 (clear warning + "send to developer" report: §12.1), Q3 (off by default
until Phase 1 passes) and Q9 (the 2026-11-15 changes were pushed first). See §17.

Contents

1. Decision summary
2. The pipeline
3. Where it plugs in: order of preference, drafts, switches, gating
4. Choosing versions
5. Fetching specs: CDN, cache, mirror, offline
6. Downloading sources
7. Package layout, names, staging, incremental builds
8. Converting source pods
9. Converting binary pods
10. The pod graph: sharing, duplicates, siblings, own subspecs
11. Run-time differences from CocoaPods
12. Errors, warnings, JSON, reports
13. What each command does
14. Studio seam (private repo)
15. Phases
16. Risks
17. Open questions for the owner
18. Decisions on every CocoaPods feature (research §11)
19. Explicitly out of scope

---

## 1. Decision summary

- **Do not run CocoaPods.** It is a Mac tool (Ruby, writes an Xcode project); xcross never uses Xcode.
- **Convert each pod into a local Swift package** (`pod-<PodName>`). Feed it to the existing SwiftPM pipeline: the same
  staging, compiling, linking, embedding and signing as every other plugin dependency.
- **Emulate what CocoaPods gives the code**: header paths, module names, prefix header, `COCOAPODS=1`, resource bundle
  names. Plugin and pod sources then compile without changes.
- **Use CocoaPods data directly**: specs from the CocoaPods CDN (already JSON), versions from `ios/Podfile.lock` when
  present.
- **Never make a build that works today fail** (G4):
  - Problems found before compiling leave the plugin out with a **clear warning** (§12.1), and the developer is offered
    to **send a report to the xcross developers** so the pod can be supported (owner decision Q1).
  - A compile or link failure inside a converted pod makes the engine rebuild once without that pod (plugin left out).
  - `--strict` and distribution builds' `release check` report `pod.*` problems as errors.
- **Turn pod kinds on one at a time**: binary pods first, then ObjC/C/C++ sources, then Swift and mixed pods. A kind
  whose phase has not passed its exit criteria is `unsupported: not_yet_supported`, even with the converter on.

## 2. The pipeline

```
plugin podspec (Ruby subset, existing parser)
   │  dependencies: name, requirement, subspec
   ▼
[A] classify each dependency ... flutter | sibling_plugin | own_subspec | swift_package | converted | unsupported
   │  pods only (project-wide, async: §3.1)
   ▼
[B] choose versions ............ Podfile.lock pins → resolver (whole graph, CocoaPods rules, app deployment target)
   ▼
[C] fetch specs ................ CDN → cache (JSON); consumer view for iOS + chosen subspecs
   ▼
[D] download sources ........... git / http → cache (checksum, safe extract, partial fetch for big repos)
   ▼
[E] convert .................... Package.swift + source tree + header trees + prefix header + xcframeworks + bundles
   ▼
[F] link into the plugin draft . `.package(name: "pod-X", path: "../pod-X")` + products (draft carries a marker)
   ▼
[G] stage and build (existing) . every pod aliased as Packages/pod-<Pod>; paths rewritten; fingerprint includes pods
```

Each step writes its result to the cache and is skipped when its inputs did not change (G6, AC-046-26).

## 3. Where it plugs in: order of preference, drafts, switches, gating

### 3.1 Order and classification

Order for each plugin (G4):

1. The plugin's own `Package.swift`.
2. The developer's override in `xcross_overrides/` (a file without the converter marker, §3.2).
3. A draft from the podspec. Each dependency of the podspec is classified:
   1. `Flutter` → `flutter` (the FlutterFramework package, existing).
   2. A plugin of the project (from `.flutter-plugins-dependencies`) → `sibling_plugin` (§10.3).
   3. A subspec of the plugin's own podspec → `own_subspec` (§10.4).
   4. A known Swift package whose `since` is reached (existing `swiftPackageFor`) → `swift_package`.
   5. A pod on the CDN, converter on, its kind enabled (§3.4) → `converted`.
   6. Otherwise `unsupported` with a reason (§12).
4. Nothing works → left out with a warning (today).

The classifier is **project-wide and async**: resolution needs every plugin's requirements at once, and may need the
network. New API: `PodGraphPlanner.plan(project, {offline})` in `packages/studio_ext/lib/src/shared/pods/`. It returns
per plugin the classified dependencies plus the resolved graph. `PluginDraftWriter.unknownPods` stays synchronous for
old callers and reads the planner's last result. Which command runs which steps: §13.

### 3.2 Drafts written with converted pods

Problem (review finding 2): once a draft exists, `PluginAutoDraft.draftMissing` skips the plugin
(`lookup.override != null`), and `PluginOverrides.apply` treats the folder as the developer's override. Without changes,
the pod graph would never be computed again, and a leftover draft would point at `../pod-X` even with the converter off.

Rules:

1. A draft that depends on converted pods starts with the existing draft marker plus a second line:
   `// xcross: pod-converter v1`.
2. On **every** build, `ios prepare`, `plugin status` and `plugin check`: scan every effective manifest (draft or
   override) for `.package(name: "pod-…")`. If any is found, run the planner for those pods so they are resolved,
   converted (build/prepare only) and staged. A developer's hand-written override may also use `pod-X` on purpose; it is
   handled the same way.
3. Converter off (`XCROSS_POD_CONVERTER=off`): a manifest with the converter marker is **not applicable**. The plugin
   is left out with today's warning. The file is not deleted. A hand-written override that uses `pod-X` gets
   `pod.converter_off` and its plugin is left out.
4. Converter turned back on: marked drafts are used again; `plugin status` shows a marked draft whose pod list no longer
   matches what the converter would write as `edited` (existing feature 028 rule).
5. Test (T009): build on → build off → build on, with the same project: today's output with off, a working build with
   on, no stale files.

### 3.3 Switches

- `XCROSS_POD_CONVERTER=off|on` (default: Q3). `off` gives exactly today's behaviour (AC-046-23).
- `XCROSS_POD_SKIP=PodA,PodB`: those pods are `unsupported: skipped_by_user` (AC-046-24).
- `XCROSS_POD_KINDS=binary,objc,swift,mixed`: overrides which kinds are enabled (§3.4), for testing.

### 3.4 Gating by pod kind

Each pod gets a kind when its spec is read: `binary` (only vendored frameworks/libraries + headers), `objc` (C, ObjC,
C++, ObjC++ sources, possibly with vendored binaries), `swift` (only Swift), `mixed` (Swift + C-family). A constant in
code lists the enabled kinds; a phase adds its kind only when its exit criteria pass (§15). Disabled kind →
`unsupported: not_yet_supported`, plugin left out, same as today.

### 3.5 Automatic fallback after a compile or link failure

When SwiftPM fails inside a converted pod (`pod.compile_failed`) or the linker reports duplicate symbols between pods
(`pod.duplicate_symbols`):

1. Mark that pod `unsupported: compile_failed` for this build.
2. Rebuild once without it; its plugins are left out with a warning that names the pod and quotes the first compiler
   error.
3. With `--strict`, or in a distribution build, do not fall back: fail with the error and the hint
   `XCROSS_POD_SKIP=<Pod>`.
4. The engine already retries module-cache races (`build_execution.dart`); this is a separate, single retry.

## 4. Choosing versions

### 4.1 Version rules (CocoaPods `Pod::Version` / `Pod::Requirement`, from RubyGems)

- A version is segments split on `.` (and `-`); a segment with a letter makes it a prerelease (`1.0.0-beta8`,
  `3.6.1b1`).
- Compare segment by segment, numbers numerically; missing segments are 0; a prerelease sorts before its release
  (`3.7.0b1 < 3.7.0`).
- Operators: `=`, `!=`, `>`, `<`, `>=`, `<=`, `~>`. A requirement can have several clauses; all must hold.
- **`~>` exactly as RubyGems:** `v ~> r` holds when `v >= r` **and** `v.release < r.bump`. `r.bump`: drop prerelease
  segments, drop the last segment (if more than one), increment the new last segment. `v.release`: `v` without its
  prerelease segments.
  - `~> 3.6.1b1`: bump of `3.6.1` is `3.7`. `3.7.0b1.release` = `3.7.0`, which is not `< 3.7`, so it is excluded.
    MobileVLCKit's version list therefore resolves to `3.6.1b1` (its only allowed version).
  - `~> 6.3` → `>= 6.3, < 7`. `~> 6.0.3` → `>= 6.0.3, < 6.1`.
- Prereleases are only picked when a requirement names one or the lock pins one (MLImage `1.0.0-beta8`).
- Odd versions: `7.00.0` compares as `7.0.0`; `3.30910.0` is a normal number. Git tags (`CocoaPods-10.1.1`) are for
  downloading only, never compared.

### 4.2 Using Podfile.lock

1. Parse `PODS:` into `name[/subspec] → version` with each entry's dependencies; read `EXTERNAL SOURCES` (plugins by
   `:path`, others by `:git`/`:podspec`), `CHECKOUT OPTIONS` (git commits), `SPEC REPOS`.
2. A pod pinned in the lock whose version satisfies every current requirement and the deployment target → use it.
3. Otherwise → `pod.lock_stale` warning ("Podfile.lock pins X 1.2, but plugin Y now needs ~> 1.4; using 1.4.3. Run
   `pod install` on a Mac or delete the entry.") and resolve normally.
4. The lock's selected subspecs are used too. The lock is read, never written.

### 4.3 Resolving without a lock

- Inputs: every requirement from every podspec-only plugin, then every requirement of every chosen pod version
  (transitive), with subspecs.
- **Candidate filter (as CocoaPods' `spec_is_platform_compatible?`):** a version whose iOS minimum is above the app's
  deployment target is not a candidate; the resolver falls back to an older version that fits. Only when no version
  fits is the pod `unsupported: ios_minimum`.
- Pick the newest candidate for each pod; on a conflict, backtrack (older versions of the most recently chosen pod) with
  a step limit. The graphs are small (goSellSDK Core has 17 pods at plugin 2.4.29).
- No solution → `pod.resolve_conflict`, naming each requirement and its source
  (`MLKitVision: google_mlkit_commons 0.11.1 needs ~> 10.0.0; GoogleMLKit 9.0.0 needs ~> 9.0`).

### 4.4 Output

A resolved graph: `pod → version, subspecs, kind, source, dependencies, required by`. It feeds every later cache key,
`plugin status --json`, and the build fingerprint (§7.5).

Q2: whether to also write `ios/xcross-pods.lock` so other machines get the same versions without a Podfile.lock.

## 5. Fetching specs: CDN, cache, mirror, offline

- Shard = the first 3 hex characters of `md5(name)` (research §5).
- Versions: `GET /all_pods_versions_<a>_<b>_<c>.txt`; cached for 24 hours. Offline: use the cached copy whatever its
  age.
- Spec: `GET /Specs/<a>/<b>/<c>/<Pod>/<version>/<Pod>.podspec.json` (follow redirects). Cached forever: published
  specs never change. Store its sha1 and compare it with `SPEC CHECKSUMS` in the lock; a mismatch is a warning.
- Not on the CDN → `unsupported: not_on_cdn`, reported as today's `unknown_pods`.
- `XCROSS_PODS_CDN` (default `https://cdn.cocoapods.org`): a mirror, in case the CDN goes away after trunk turns
  read-only (2 December 2026, confirmed: research §5).
- Proxy: honour `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY` like the rest of the engine. User-Agent `xcross`, no user data.
- Cache root: the engine's existing cache folder + `pods/` (use the engine's cache helper; do not invent a path).
  **Keys are 12 hex characters** to keep Windows paths under MAX_PATH.

```
pods/
  index/<a>_<b>_<c>.txt              versions lists (24 h)
  specs/<Pod>/<version>.json          specs (forever)
  sources/<key12>/                    extracted downloads (read-only after extraction)
  packages/<Pod>/<version>-<key12>/   generated packages (read-only after writing)
  locks/                              file locks (§6.6)
```

## 6. Downloading sources

### 6.1 Source kinds (the spec's `source`)

| Spec `source` | Action |
|---|---|
| `git` + `tag` / `commit` on github.com | `https://codeload.github.com/<owner>/<repo>/tar.gz/<ref>`. No git needed. |
| `git` + `branch` | Resolve the branch to a commit first (GitHub API or `git ls-remote`); cache by commit. |
| `git` elsewhere (dev.azure.com, GitLab, …) | `git clone --depth 1 --branch <tag>`, or fetch the commit. Needs git on PATH; missing → `pod.download_failed` "install Git". |
| `git` + `submodules: true` | GitHub archives lack submodules: use git with `--recurse-submodules`. |
| GitHub archive missing files | Archives leave out Git LFS objects and `export-ignore` files. If an extracted file is an LFS pointer, or a spec glob matches nothing, retry the download with git. |
| `http` | Download; type from `type` or the extension: zip, tgz/tar.gz, tbz/tar.bz2, txz/tar.xz, tar. `flatten: true`: if the archive has a single top folder, use its content. |
| `sha256` / `sha1` | Check after download. A mismatch → `pod.download_failed` "checksum mismatch"; the file is never used. |
| `svn`, `hg` | `unsupported: unsupported_source`. |

### 6.2 Big repositories

TensorFlowLiteSwift points at the whole TensorFlow repo. codeload sends no Content-Length, so the size cannot be known
before downloading. Rule: for github.com sources, read the repo `size` from the GitHub API (in KB). Above the limit
(setting, default 200 MB) → partial fetch: list the tree at the ref with the GitHub API, download only files matching
the spec's globs from `raw.githubusercontent.com`. Use `GITHUB_TOKEN` when set (60 requests/hour without it); fall back
to the archive on HTTP 403. Protobuf 3.11.4's archive is 5.1 MB, so it does not need this (review finding 18).

### 6.3 Safe extraction (untrusted data)

- Reject entries with absolute paths, drive letters, or `..` after normalising.
- Symbolic links: keep only links whose target stays inside the folder. On Windows, turn kept links into copies.
- **Skip slices for other platforms** in vendor xcframeworks (macOS, tvOS, …). They are not needed, and macOS framework
  slices contain symlinks Windows cannot create without developer mode.
- Extract into a temporary folder, then rename (atomic). A half-done download is never visible.
- Never execute anything from a download.

### 6.4 Sizes and progress

Stream to disk. `XCROSS_EVENTS=ndjson` gets `step` events `pod_download` and `pod_convert` with bytes done/total. Connect
timeout 30 s; 120 s without bytes → retry up to 3 times with backoff, then fail.

### 6.5 Licences

Keep each pod's `LICENSE` in the cache. Acknowledgements file: Q7.

### 6.6 Two builds at once

One file lock per cache entry (`locks/<key12>.lock`). The second build waits (message after 5 s), then reuses the
result. A lock whose process is gone is taken over (AC-046-28).

## 7. Package layout, names, staging, incremental builds

### 7.1 Layout

One package per pod version + subspec selection + build target/mode (conditional settings §8.4):

```
packages/<Pod>/<version>-<key12>/
  Package.swift
  Sources/<Module>/<original relative paths…>   pod sources, original folder tree kept (§8.4 PODS_TARGET_SRCROOT)
  Sources/<Module>/xcross/<Pod>-prefix.pch      prefix header (§8.6)
  Sources/<Module>/xcross/vers.c                version symbols (§8.5.7)
  Headers/Public/<Module>/…  (+ aliases)         public header tree (§8.5)
  Headers/Private/<Module>/…                     all headers, own target only (§8.5)
  Sources/<Module>_xcross/placeholder.c          wrapper target for binary pods (§9.1)
  Frameworks/<Framework>.xcframework             binaries (§9)
  Resources/…                                    bundles and plain resources (§8.7)
  LICENSE
  xcross-pod.json                                inputs, outputs, every patch applied
```

Files:

- Files in `Sources/` are **copies** of the downloaded files (so patches never touch the cache's originals).
- Header trees are **hard links** to the files in `Sources/` (same volume, same file identity). clang de-duplicates
  `#import` by file identity, so a header reached through both paths is parsed once. Copies would cause duplicate
  `@interface` errors.
- Hard links not possible → fail clearly; never fall back to copies.

### 7.2 Names

- Package name: `pod-<PodName>`.
- Module name: `module_name`, else the pod name made a C99 identifier (as CocoaPods `c99ext_identifier`): every character
  that is not a letter, digit or `_` becomes `_`, runs of `_` become one, and a leading digit gets a `_` in front.
  Example: PromisesObjC → `FBLPromises` (its `module_name`).
- Source target: the module name. Product: the module name.
- Binary target: the framework's own name. When it equals the module name (MLKitVision, MLKitCommon,
  TensorFlowLiteC, ObjectBox), the wrapper target is `<Module>_xcross` (§9.1).
- Target names must be unique in the whole SwiftPM graph. Converted pods that are also remote Swift packages never get
  here: §10.2 handles them first.

### 7.3 Paths in manifests

- The plugin draft is a project file (maybe committed): no machine paths. It declares
  `.package(name: "pod-MLKitVision", path: "../pod-MLKitVision")`.
- Converted pods that depend on other converted pods use the same symbolic form.

### 7.4 Staging (review finding 14)

- Stage **every** pod of the graph, transitive ones included, as an alias `Packages/pod-<Pod>` pointing at its cache
  folder. The package identity is then `pod-<Pod>`, matching the engine's identity-keyed logic (`consumedProducts`).
- `packageTargets` points `pod-<Pod>` at those aliases. The path rewrite runs on plugin manifests **and** on converted
  pods' manifests (today it runs only in `stagePluginPackage`).
- `SwiftPmSharedSearchPaths` scans only `checkouts/` and `artifacts/` today; add the converted pods' xcframeworks.
- Seams marked `// studio: 046` in `workspace_stager.dart`, `plugin_overlay.dart`, `shared_search_paths.dart`.

### 7.5 Incremental builds (review finding 1)

`discovery.dart` `incrementalBuildFingerprint` hashes only the plugin package trees plus toolchain and engine data. A
new pod version, a new converter version, or a change to `XCROSS_POD_SKIP` would leave it unchanged, and the engine
would reuse an old plugins dylib. Add a seam that hashes the resolved pod graph (each pod's name, version, package key)
plus `XCROSS_POD_CONVERTER`, `XCROSS_POD_SKIP` and `XCROSS_POD_KINDS`. Package keys already cover the contents, so no
need to hash trees. Test: change a pod version → rebuild; same inputs → reuse (AC-046-30).

## 8. Converting source pods

### 8.1 The consumer view (which attributes apply)

Build one effective spec for iOS from the root spec and the chosen subspecs (and their own subspecs), as CocoaPods
`Specification::Consumer` does. Source: CocoaPods Core `dsl.rb` / `attribute.rb` (in Core, `inherited` defaults to
`root_only`), checked by the review:

| Rule | Attributes |
|---|---|
| Root only | `name`, `version`, `source`, `module_name`, `module_map`, `prepare_command`, `static_framework`, `swift_versions`, `cocoapods_version`, `default_subspecs`, `license` |
| Inherited (a subspec gets the parent's value plus its own) | `dependencies`, `frameworks`, `weak_frameworks`, `libraries`, `compiler_flags`, `pod_target_xcconfig`, `user_target_xcconfig`, `requires_arc`, `header_dir`, `header_mappings_dir`, `prefix_header_contents`, `prefix_header_file` |
| Per spec (file patterns and the like, not inherited) | `source_files`, `public_header_files`, `private_header_files`, `project_header_files`, `exclude_files`, `resources`, `resource_bundles`, `vendored_frameworks`, `vendored_libraries`, `preserve_paths`, `info_plist` |

Merging rules:

- Hash attributes with the same key (xcconfig) merge as `parent + " " + child`.
- `ios: { … }` adds to lists and replaces single values. Then remove duplicates (MyFatoorah lists
  `SDK/v2/MFSDK.xcframework` both generally and under `ios:`; it must become one binary target).
- The root spec's own files apply whatever subspecs are selected. Remove duplicate files (nanopb's root and subspecs list
  the same files).
- No subspec requested and no `default_subspecs` → **all** subspecs that support iOS, excluding test specs and app specs
  (nested ones too, e.g. TensorFlowLiteSwift's test spec). `default_subspecs` can be a list, a string, or `:none`.
- `osx`, `tvos`, `watchos`, `visionos` keys are ignored.

Each rule gets a fixture test (T005). The research §11 decisions table (§18 here) says what happens to every attribute.

### 8.2 File selection

From CocoaPods `file_accessor.rb` / `path_list.rb` (checked by the review):

- Glob syntax: `*`, `**`, `?`, `[...]`, `{a,b}` (nested). Matching is **case-insensitive** (`FNM_CASEFOLD |
  FNM_PATHNAME`). On Linux the real file names are kept; only matching ignores case.
- Default extensions, appended **only when a pattern names a directory**, and only for files directly inside it:
  sources `.m .mm .i .c .cc .cxx .cpp .c++ .swift`; headers `.h .hh .hpp .ipp .tpp .hxx .def .inl .inc`. There is no
  `.s`/`.S`.
- A pattern such as `**/*` (GoogleDataTransport) or `ios/Classes/*` (flutter_sound_core) matches every file. Files that
  are not sources or headers are "other files": kept in the download, **not** copied into `Sources/`. SwiftPM would
  otherwise treat xib/storyboard/xcassets/xcdatamodeld/metal files in a target folder as resources needing Apple tools,
  and warn about the rest.
- `preserve_paths` files are copied into the package (they are needed: GoogleMLKit's `module.modulemap`).
- Paths are relative to the download root (after `flatten`). Nothing matched → `pod.conversion_failed` "source_files
  matched no file" (or retry with git: §6.1).

### 8.3 Targets

| Pod content | Targets |
|---|---|
| C/ObjC/C++ only | `<Module>` |
| Swift only | `<Module>` |
| Swift + C-family | two targets, direction chosen per pod (§8.8) |
| C-family with `requires_arc` false or a file list | ARC target `<Module>` + non-ARC target `<Module>_noarc` (`-fno-objc-arc`); the ARC target depends on it |
| Subspecs with different `compiler_flags` | one target per distinct flag set, or one target and a warning when splitting is not possible (shared headers) |
| Vendored binaries | binary target(s) + wrapper `<Module>_xcross` (§9.1), plus a source target if there are sources |
| Headers only (GoogleMLKit) | one target with a placeholder `.c` and the header tree; the pod's own `module.modulemap` when it ships one |

Per target:

- Language standards: from settings or flags (§8.4); defaults `gnu11` and `gnu++14`, C++ library `libc++` (the CocoaPods
  project defaults, from Xcodeproj `PROJECT_DEFAULT_BUILD_SETTINGS`).
- `platforms`: the pod's iOS minimum. The resolver already chose a version the app's deployment target allows (§4.3).
- Always `COCOAPODS=1` (C-family) and `COCOAPODS` (Swift), as CocoaPods sets for every pod.

### 8.4 Build settings (`pod_target_xcconfig`, `xcconfig`, `compiler_flags`)

Parse xcconfig values once (shared with Phase 1: T011).

**Conditional keys** (`KEY[sdk=iphonesimulator*]`, `[arch=arm64]`, `[config=Release]`): evaluate at conversion time
against the build target (device or simulator, arm64) and mode. The engine always builds plugins with
`--configuration debug`; distribution builds only add `-Xcc -UDEBUG`. So `[config=Release]` keys apply to
distribution builds; mapping them to SwiftPM `.when(configuration: .release)` would never take effect. Target and mode
are part of the package key.

**Variables**:

| Variable | Becomes |
|---|---|
| `${PODS_TARGET_SRCROOT}` | `Sources/<Module>` (the pod's original tree, kept, §7.1) |
| `${PODS_ROOT}/<ThisPod>/…` | that tree |
| `${PODS_ROOT}/<OtherPod>/…` | that dependency's tree (through its alias) or a warning |
| `${PODS_ROOT}/Headers/Public` and `…/Headers/Public/<Pod>` | the public header trees |
| `$(inherited)` | nothing |
| `${PODS_CONFIGURATION_BUILD_DIR}`, others | warning `pod.setting_ignored` |

**Keys**:

| Key | SwiftPM |
|---|---|
| `GCC_PREPROCESSOR_DEFINITIONS` | `.define(name, to: value)`; skip `$(inherited)` |
| `HEADER_SEARCH_PATHS`, `USER_HEADER_SEARCH_PATHS` | inside the package → `.headerSearchPath`; another pod → that pod's tree via `-I` (§8.5.5); else warning |
| `OTHER_CFLAGS`, `OTHER_CPLUSPLUSFLAGS` | flag rules below |
| `CLANG_CXX_LANGUAGE_STANDARD`, `GCC_C_LANGUAGE_STANDARD` | `cxxLanguageStandard`, `cLanguageStandard` |
| `CLANG_CXX_LIBRARY` | `libc++` only; anything else → warning |
| `CLANG_ENABLE_OBJC_WEAK` | `-fobjc-weak` |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | `swiftSettings .define` |
| `OTHER_SWIFT_FLAGS` | `-D<NAME>` → `swiftSettings .define`; others → warning |
| `SWIFT_VERSION` | language mode (§8.8) |
| `OTHER_LDFLAGS` (pod and `user_target_xcconfig`) | `-framework X` → `.linkedFramework`; `-weak_framework X` → linker flag; `-l<name>` → `.linkedLibrary`; `-ObjC` → nothing (already global); `-force_load` → warning |
| `DEFINES_MODULE`, `APPLICATION_EXTENSION_API_ONLY`, `ENABLE_BITCODE`, `VALID_ARCHS`, `EXCLUDED_ARCHS`, `IPHONEOS_DEPLOYMENT_TARGET` | ignored (module map always made; bitcode §9.5; slices §9.4) |
| anything else | `pod.setting_ignored` with key and pod (never silent) |

`user_target_xcconfig`: only its linker keys apply, to the plugins dylib link. Other keys get `pod.setting_ignored`.

**Compiler flags** (from `compiler_flags`, `OTHER_CFLAGS`, `OTHER_CPLUSPLUSFLAGS`). `.unsafeFlags` is allowed for local
path packages (SwiftPM `unsafeAllowedPackages`; existing plugin drafts already use it: research §9 rule 5).

| Flag | Rule |
|---|---|
| `-Werror`, `-Werror=*` | **always dropped** (Braintree, BraintreeDropIn, onnxruntime-objc use them; a newer clang adds warnings) |
| `-std=c++*`, `-std=gnu++*` | → `cxxLanguageStandard`, never in cSettings |
| `-std=c*`, `-std=gnu*` (C) | → `cLanguageStandard` |
| `-D…`, `-U…` | kept (`.define` when possible) |
| `-W…`, `-Wno-…`, `-w` | kept |
| `-fno-objc-arc`, `-fobjc-arc`, `-fobjc-arc-exceptions`, `-fobjc-weak` | kept |
| `-fvisibility=*` | kept (changes which symbols are exported) |
| others | dropped with `pod.setting_ignored` |
| any C flag | never passed to `swiftSettings` |

SwiftPM adds `-DSWIFT_PACKAGE=1` and `-fobjc-arc` before the build-settings flags, so `-USWIFT_PACKAGE` and
`-fno-objc-arc` in unsafeFlags take effect (checked by the review in SwiftPM source).

### 8.5 Headers and modules

Flutter's iOS Podfile template uses `use_frameworks!` (research §6; also in a client app's Podfile). That decides the
import paths code expects.

1. **Normalise `header_dir`**: `.` or `./` means none (PromisesObjC 2.4.1 has `header_dir: "./"`).
2. **Public headers** = `public_header_files`, or every header in `source_files` when not set. Private = `private_header_files`
   + `project_header_files` + the remaining headers.
3. **Public tree** `Headers/Public/`:
   - `<Module>/` with the public headers. In framework builds CocoaPods ignores `header_dir` and code imports
     `<Module/X.h>`.
   - Aliases with the same files (hard links): `<PodName>/` when it differs from the module name (Protobuf: module
     `protobuf`, imports `<Protobuf/…>`, and Linux is case-sensitive), and `<header_dir>/` when set (static builds use
     `Headers/Public/<PodName>/<header_dir>/`).
   - Flattened, unless `header_mappings_dir`: then keep the folders below that directory.
4. **Private tree** `Headers/Private/<Module>/` with **all** headers, for the pod's own targets. Pods import their own
   non-public headers as `<Module/X.h>` (Braintree: `<Braintree/BTAPIClient_Internal.h>`), which Xcode's header maps
   allow. Own targets get header search paths to `Headers/Private` and `Headers/Private/<Module>` (for `"X.h"`).
5. **Dependents** (other converted pods and plugin drafts that depend on the pod, directly or through other pods; never
   other plugins). They get `-I Headers/Public` (angle imports) and `-I Headers/Public/<Module>` (quoted `"X.h"`, as
   CocoaPods allows). These are injected at staging time, so drafts keep no machine paths: the overlay adds
   `.unsafeFlags(["-I", …])` to the dependent's targets. Not global: a global `-I` would expose every pod's headers to
   every existing plugin (review finding 20). Two pods exporting the same flat header name into one dependent →
   `pod.header_clash` naming both (first in graph order wins).
6. **Module map**: SwiftPM uses `include/` by convention; point `publicHeadersPath` at the public tree and write
   `module.modulemap` there:
   `module <Module> { umbrella header "<Module>/<Module>-umbrella.h" export * module * { export * } }`.
   The umbrella header lists every public header, as CocoaPods does. If the spec has `module_map` → use the pod's own
   file with paths rewritten. `module_map: false` → no module map, so `@import` is not available, as with CocoaPods.
   A pod that ships a `module.modulemap` through `preserve_paths` (GoogleMLKit) → use it, never generate a second one.
7. **Version symbols**: CocoaPods' umbrella header declares `<Module>VersionNumber` and `<Module>VersionString`. Generate
   `xcross/vers.c` defining them (cheap; some code reads them).
8. `@import <Module>;` (ObjC) and `import <Module>` (Swift) then resolve to the pod.

### 8.6 Prefix header (review finding 8)

CocoaPods writes `<Pod>-prefix.pch` for every pod unless `prefix_header_file` is `false`:

```
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif
```

plus `prefix_header_contents`, or the pod's own `prefix_header_file`. Old ObjC pods rely on UIKit coming from it; the
engine's global `-include` only imports Foundation. Generate the file and pass `-include <path>` through unsafeFlags to
the pod's C-family targets. Google's pods set `prefix_header_file: false`; respect it.

### 8.7 Resources (review finding 16)

Flutter's default is `use_frameworks!`, where CocoaPods puts a pod's resources inside the pod's framework. In xcross
all plugin code is in one dylib (`libFlutterPluginsGenerated.dylib`), so there is no per-pod framework. Placement:

| Pod declares | Placed in the app as | Why |
|---|---|---|
| `resource_bundles: { "Key" => […] }` | `Key.bundle/` at the app root, `Info.plist` with `CFBundleIdentifier` `org.cocoapods.Key` | Code finds it with `[NSBundle mainBundle]` (static style) or `Bundle(for: X.self)`, which returns the main bundle for code in a plain dylib **(verify T108: the whole resource plan depends on this)** |
| `resources: […]` (plain) | copied to the app root **only if no name collides** | static-style lookups work |
| a plain resource named `Info.plist` or `PrivacyInfo.xcprivacy` | never at the app root; put in `<Pod>Resources.bundle/` and reported | they would overwrite the app's own files |
| any name collision (with the app, another pod, or another bundle) | `pod.resource_clash`, plugin left out | silent overwrite would break the app or another pod |
| `.xib`, `.storyboard` | need `ibtool`: use the engine's compiler if it can (feature 033 compiles one simple storyboard), else `unsupported: uncompiled_resource` naming the file | — |
| `.xcassets` | the engine's catalog compiler (feature 004), else `uncompiled_resource` | — |
| `.xcdatamodeld`, `.metal` | `uncompiled_resource` | no compiler |
| `PrivacyInfo.xcprivacy` inside a bundle or framework | kept; `release check` must find it there | App Store |

SwiftPM's `.process()` is not used for these (it would name bundles `<package>_<target>.bundle`). Seam: the engine step
that copies files into the `.app` accepts a list of extra bundles and files from converted pods.

### 8.8 Swift and mixed pods (review finding 5)

- **Language mode** from `swift_versions` (or `swift_version` / `SWIFT_VERSION`): the highest one the toolchain accepts
  that the pod allows (Swift 6.4: check whether 4 and 4.2 are still accepted, T301). None given → 5.
- **Mixed pods**: choose the direction from the sources:
  - **ObjC uses the pod's Swift** (an ObjC file imports `<Module>-Swift.h`; Braintree 5.6.3 `BTPayPalDriver.m` imports
    `<Braintree/Braintree-Swift.h>`): reuse the engine's plugin draft design. The ObjC target `<Module>` depends on a
    Swift target `<Module>_swift`. The Swift target reaches the pod's ObjC headers through a generated bridging header
    (`-import-objc-header`). `-Swift.h` imports are patched to `@import <Module>_swift;`. Today's
    `patchSwiftHeaderImports` hard-codes the plugin name; it gets a module parameter.
  - **Swift uses the pod's ObjC only**: ObjC target `<Module>ObjC`, Swift target `<Module>` with a generated
    `@_exported import <Module>ObjC`. Swift consumers' `import <Module>` sees both halves. ObjC consumers'
    `#import <Module/X.h>` still finds the headers; their `@import <Module>;` is patched (copies) to also
    `@import <Module>ObjC;`.
  - **Both ways** (ObjC uses Swift, and Swift uses ObjC types that are not reachable through a bridging header) →
    `unsupported: objc_uses_own_swift`.
  - **Spike outcome (2026-11-16, T302)**:
    1. **Try 2.1.1**: Swift uses ObjC only (`Try.swift` calls `TryHelper.catchException`). Direction: `swiftUsesObjc`.
       Target layout: `TryObjC` (ObjC target) and `Try` (Swift target with `@_exported import TryObjC`).
    2. **SwiftyRSA 1.7.0**: Pure Swift core with optional ObjC subspec wrapper. Core is pure Swift; wrapper imports
       Swift core. Direction: `objcUsesSwift` when ObjC subspec is requested, else pure Swift.
    3. **Braintree 5.6.3**: ObjC uses Swift (`BTPayPalDriver.m` imports `<Braintree/Braintree-Swift.h>`). Direction:
       `objcUsesSwift`. Target layout: `Braintree_swift` (Swift target with bridging header) and `Braintree` (ObjC
       target depending on `Braintree_swift`, `#import` patched to `@import Braintree_swift;`).
    4. Two-way cycles: detected by `PodMixedSplitter.detectDirection` and rejected cleanly with `pod.objc_uses_own_swift`.
- Swift pods with `#if SWIFT_PACKAGE` branches: §8.9.

### 8.9 Source patches (on the package's copies; every patch listed in `xcross-pod.json`)

1. **`SWIFT_PACKAGE`**: SwiftPM always defines it (Swift and C). Pods that support both CocoaPods and SwiftPM use it to
   switch to SwiftPM module names (`#if SWIFT_PACKAGE @import GoogleUtilities_Environment;`). Converted pods are laid
   out like CocoaPods, so they must take the CocoaPods branch:
   - C-family targets: `-USWIFT_PACKAGE` (works: §8.4).
   - Swift sources: rewrite `#if SWIFT_PACKAGE`, `#if !SWIFT_PACKAGE` and compound conditions using it to an undefined
     name (`XCROSS_POD_NOT_SWIFT_PACKAGE`).
   - **Public headers too**: consumers (plugins, other pods) compile the pod's public headers with `SWIFT_PACKAGE`
     defined. Scan the header tree and patch the same conditions there (they are copies in `Sources/`, so the header
     tree's hard links see the patched file).
2. `-Swift.h` imports (§8.8).
3. Consumers' `@import` of mixed pods (§8.8).
4. Nothing else is patched. `-v` lists every patch.

## 9. Converting binary pods

### 9.1 Targets for binaries

- `.binaryTarget(name: <FrameworkName>, path: "Frameworks/<FrameworkName>.xcframework")`. The engine already writes
  local `path:` binary targets (`swiftpm_binary_target.dart`).
- Binary targets cannot carry linker settings, and pods need them (MobileVLCKit: `c++`, `xml2`, `z`, `bz2`, `iconv`). So
  there is always a wrapper target `<Module>_xcross` with a placeholder `.c`, the linker settings, and the header tree
  when the binary has none. The product lists the binary target(s) and the wrapper.
- A vendor `.xcframework` is copied (or hard-linked) unchanged, keeping its signature. Slices for other platforms are
  skipped (§6.3).

### 9.2 Legacy `.framework` → `.xcframework`

1. Read the framework binary. `mach_o_slices.dart` today only finds an arm64 range in a `FAT_MAGIC` file. Needed, and new
   work: `FAT_MAGIC_64`, every architecture, thin files, and members of static archives. `llvm-lipo` from the Swift
   toolchain is the fallback (the Windows LLVM install has none).
2. Platform per slice: `LC_BUILD_VERSION` (or `LC_VERSION_MIN_IPHONEOS` in old binaries); for archives, read the first
   object member. Old fat frameworks combine `arm64` (device) and `x86_64` (simulator).
3. Static or dynamic: Mach-O `MH_DYLIB` = dynamic; an `!<arch>` archive = static.
4. Write `<Name>.xcframework/` with `ios-arm64/<Name>.framework` and, when present, `ios-arm64-simulator/` (or
   `ios-arm64_x86_64-simulator/`). Copy `Headers/`, `Modules/`, `Info.plist` and resources into each slice. Write the
   xcframework `Info.plist` (`AvailableLibraries`, `SupportedPlatform`, `SupportedPlatformVariant`, `LibraryIdentifier`,
   `LibraryPath`, `BinaryPath`).
5. No `Modules/module.modulemap` → write
   `framework module <Name> { umbrella header "<Name>.h" export * module * { export * } }`, or list every header when
   there is no umbrella header.

### 9.3 Vendored `.a` libraries

Wrap in a library xcframework (slices as in 9.2). Headers: in the wrapper's header tree (§8.5), or as a module map in
the xcframework's `Headers/`.

### 9.4 Missing slice

The engine builds arm64 only: device `arm64-apple-ios` and simulator `arm64-apple-ios-simulator`. A pod without a slice
for the build's target → plugin left out of that build with `pod.no_slice` ("MLKitVision has ios-arm64,
ios-x86_64-simulator; this build needs ios-arm64-simulator. Device builds work."). An x86_64-only simulator slice
counts as missing.

### 9.5 Bitcode (review finding 22)

lld drops the `__LLVM` segment of input object files (lld `MachO/InputFiles.cpp`), so **static** vendored binaries
never carry bitcode into the app. Only **dynamic** frameworks embedded unchanged can. For those: detect a `__LLVM`
segment. In **distribution** builds (`forDistribution` / `XCROSS_PLUGIN_BUILD=distribution`, not every `--release`),
either strip it (a Dart stripper that drops the segment and fixes load commands; the engine already edits Mach-O in
`macho_dylib_rewriter.dart`) or leave the plugin out with `pod.bitcode`. T105 decides strip vs refuse; either satisfies
AC-046-11.

### 9.6 Swift binary frameworks

A slice with a `.swiftmodule` folder but no `.swiftinterface` was built without library evolution; another compiler
cannot import it → `pod.swift_binary_incompatible`. With `.swiftinterface` → fine.

### 9.7 Embedding and signing

Dynamic frameworks go to `Frameworks/` and are signed with the app, as dynamic binary targets are today (the
2026-11-15 probe embedded AppLovinSDK and FBAudienceNetwork). Static ones are linked into the plugins dylib. Check the
install names (`LC_ID_DYLIB`, `@rpath`) of re-wrapped dynamic frameworks.

### 9.8 iOS minimum, privacy manifests, SDK signatures (review finding 24)

- Framework `Info.plist` `MinimumOSVersion` must match the binary (App Store error 90208). Apply the engine's existing
  fix and `release check`'s `release.framework_minimum_os` to converted frameworks.
- Privacy manifests: keep `PrivacyInfo.xcprivacy` from frameworks and bundles; `release check` looks inside converted
  frameworks and pod bundles.
- **Apple's list of commonly used third-party SDKs** (developer.apple.com/support/third-party-SDK-requirements). Facts:
  - None of the Phase 1 probe pods (WebRTC-SDK, ObjectBox, MobileVLCKit, MyFatoorah) is on it.
  - The listed SDKs in research §3 (GoogleUtilities, GoogleDataTransport, GoogleToolboxForMac, nanopb, FBLPromises,
    GTMSessionFetcher, Protobuf, Toast, DKImagePickerController) are source pods, compiled into the plugins dylib.
  - OneSignal is listed and ships as a binary. Old pinned versions probably predate privacy manifests, and App Store
    Connect then rejects the upload (ITMS-91061).
- New `release check` warning `pod.sdk_privacy_manifest_missing`: a listed SDK (names stored in code, with the date of
  the list) without a privacy manifest in its bundle or framework.
- Signatures: a vendor xcframework keeps its signature. A legacy framework re-wrapped by us has none. The App Store test
  (test-plan §5) uses a **listed SDK embedded as a framework**, to learn whether App Store Connect accepts it (Q6).

### 9.9 dSYMs

Copy vendor `*.dSYM` next to the build's dSYM output (feature 018) when present. Optional; never fail on it.

## 10. The pod graph: sharing, duplicates, siblings, own subspecs

### 10.1 One package per pod

All plugins' requirements are resolved together (§4.3). A pod used by two plugins, or by a plugin and a pod, is one
package. Subspec choices are merged (the union), as CocoaPods does.

### 10.2 Pods that are also remote Swift packages (duplicate rule; review finding 4)

Risk: the same library built twice. Example: Firebase's Swift packages and Google ML Kit's pods both need
GoogleUtilities, GoogleDataTransport, nanopb, PromisesObjC and GTMSessionFetcher. Some of these clash on target names in
SwiftPM. Others (a converted GoogleUtilities, module `GoogleUtilities`, next to the remote `GoogleUtilities-*` targets;
GTMSessionFetcher vs `GTMSessionFetcherCore`) do not clash on names but fail later: duplicate ObjC classes at link
time or at run time.

Rule, applied **before compiling**, to **every** converted pod (not just a fixed list):

1. Look the pod up with `knownPackageFor` (the existing table, plus the infrastructure rows below).
2. If that Swift package is already in the build (any staged plugin manifest, or a resolved checkout), or the pod's
   requirement reaches the package's `since` → **use the Swift package's product instead of converting**. Feed the pod
   requirement, mapped to the package's version scheme, to the feature-045 pin checker.
3. If the versions cannot agree → `pod.duplicate_with_swift_package` with both versions; the plugin is left out (G4).

Infrastructure rows to add to the table. **Each row must be verified** (product names, first tag with a Package.swift,
headers against ML Kit's binary headers) in T402. The review's corrections are already in:

| Pod (subspec) | Swift package | Products | Version mapping |
|---|---|---|---|
| GoogleUtilities/Environment, /Logger, /NSData+zlib, /UserDefaults, … | `https://github.com/google/GoogleUtilities` | `GULEnvironment`, `GULLogger`, `GULNSData`, `GULUserDefaults`, … (`Privacy` has no product) | same numbers |
| GoogleDataTransport | `https://github.com/google/GoogleDataTransport` | `GoogleDataTransport` | same numbers |
| nanopb | `https://github.com/firebase/nanopb` | `nanopb` | pod `3.30910.x` ↔ SwiftPM tags `2.30910.x` (map the major) |
| PromisesObjC | `https://github.com/google/promises` | `FBLPromises` | same numbers |
| GTMSessionFetcher/Core | `https://github.com/google/gtm-session-fetcher` | `GTMSessionFetcherCore` | same numbers |
| GoogleToolboxForMac | none found yet | — | converted |

Header compatibility: binary pods may `#import <GoogleUtilities/GULLogger.h>` (CocoaPods layout) where the Swift
package exposes `GoogleUtilities_Logger` modules. If the package lacks the CocoaPods path, add a forwarding header tree
`Headers/Public/GoogleUtilities/…` in the wrapper of the pod that needs it. Decided in T402 with the real headers.

### 10.3 Sibling Flutter plugins as dependencies

`google_mlkit_text_recognition` → pod `google_mlkit_commons`:

1. The name is a plugin of the project (from `.flutter-plugins-dependencies`).
2. Read that plugin's product name from its own Package.swift, or from its draft (`<plugin>` with `_` → `-`).
3. Add `.package(name: "<plugin>", path: "../<plugin>")` and `.product(name: <product>, package: "<plugin>")`. The
   overlay already rewrites plugin paths.
4. Its public headers must be importable as `<google_mlkit_commons/X.h>`; drafts already use `publicHeadersPath`.

This is needed by the Phase 2 ML Kit probe, so it lands in Phase 2 (T403 moved; review finding 18).

### 10.4 Own subspecs

A plugin podspec with `s.subspec 'x' do |ss| … end` and a dependency on `<plugin>/x`: extend the Ruby-subset parser to
read subspec blocks (source_files, dependencies, frameworks, xcconfig) and merge them into the plugin's draft. Report
blocks it cannot read (`pod.podspec_unread`).

### 10.5 Known Swift package pinned before `since`

Today: left out (`… (its Swift package starts at 1.3.4)`). With the converter: build the exact pod, unless the
duplicate rule (§10.2) finds the same package elsewhere in the build. Each pod in research §3.14 gets a probe build or a
recorded "left out" decision.

## 11. Run-time differences from CocoaPods

1. **All plugin code is in one dylib** (`Frameworks/libFlutterPluginsGenerated.dylib`). With CocoaPods `use_frameworks!`
   each pod is its own framework; with static CocoaPods it is in the app binary. `Bundle(for:)` /
   `[NSBundle bundleForClass:]` for dylib code is believed to return the main bundle **(verify T108 first in Phase 1:
   §8.7 depends on it)**.
2. **ObjC categories**: `-ObjC` is already passed globally.
3. **`+load` order**: as static linking; watch for issues in probe apps.
4. **Swift runtime**: Swift pods are compiled into the plugins dylib like other Swift plugin code.
5. **Duplicate symbols** between two binary pods embedding the same library → parse ld64.lld's message into
   `pod.duplicate_symbols` naming both pods; the automatic fallback (§3.5) applies.

## 12. Errors, warnings, JSON, reports

Diagnostic codes (register in `packages/xcross/lib/src/shared/diagnostics/xcross_diagnostics.dart`):

| Code | Level | When | Default effect |
|---|---|---|---|
| `build.pod_converted` | info (one line per pod, first time only) | pod converted | built |
| `build.pod_unsupported` | warning | `unsupported` with a reason | plugin left out |
| `pod.resolve_conflict` | warning | no version fits | plugin left out |
| `pod.lock_stale` | warning | Podfile.lock pin no longer fits | resolver used |
| `pod.download_failed` | warning | network, checksum, git missing | plugin left out |
| `pod.no_slice` | warning | no slice for this target | plugin left out of this build |
| `pod.bitcode` | warning | dynamic framework with bitcode, not stripped, distribution build | plugin left out |
| `pod.swift_binary_incompatible` | warning | no `.swiftinterface` | plugin left out |
| `pod.duplicate_with_swift_package` | warning | versions cannot agree | plugin left out |
| `pod.resource_clash` | warning | resource name collision | plugin left out |
| `pod.header_clash` | warning | two pods export the same flat header to one dependent | built (first wins, named) |
| `pod.setting_ignored` | warning (all with `-v`) | setting or flag not translated | built |
| `pod.podspec_unread` | warning | plugin podspec lines not understood | built from what was read |
| `pod.converter_off` | warning | a hand-written override uses `pod-X` while the converter is off | plugin left out |
| `pod.conversion_failed` | warning | any other conversion problem, with details | plugin left out |
| `pod.compile_failed` | warning, then automatic fallback (§3.5); error with `--strict` / distribution | SwiftPM failed inside a converted pod | plugin left out after rebuild |
| `pod.duplicate_symbols` | as `pod.compile_failed` | linker duplicate symbols between pods | plugin left out after rebuild |
| `pod.sdk_privacy_manifest_missing` | `release check` warning | listed SDK without privacy manifest | — |

### 12.1 The warning and the report (owner decision Q1, 2026-11-16)

Every "plugin left out" case (any `pod.*` warning that leaves a plugin out, and `build.pod_unsupported`) is shown the
same clear way and offers a report.

**Warning text: four parts, plain words, always in this order**

```
⚠ Plugin "google_mlkit_text_recognition" is left out of this build: its features will not work in the app.
  Why: pod "MLKitVision 10.0.0" has no slice for the iOS simulator (it has ios-arm64, ios-x86_64-simulator).
  You can: build for a real iPhone instead (device builds include it).
  Report: send this to the xcross developers so they can fix it: xcross pods report MLKitVision
```

1. **What**: the plugin, and that its features will not work.
2. **Why**: the pod, its version, the reason in plain words (not only the code). For compile failures: the first
   compiler error line, paths shortened.
3. **You can**: the concrete step when one exists (raise `IPHONEOS_DEPLOYMENT_TARGET` to X, install Git, check the
   network or proxy, build for a device, run `pod install` on a Mac to refresh Podfile.lock). When nothing can be done
   on the developer's side: "nothing to do on your side; this pod is not supported yet."
4. **Report**: how to send it (CLI command; the Studio shows a button instead, §14).

The code (`pod.no_slice`, …) stays in the structured event for tools; the console line leads with the words.

**Report payload** (in the NDJSON warning event as `report`, and in `pods-report.json`):

| Field | Content |
|---|---|
| `code`, `reason` | e.g. `pod.no_slice`, `no_slice` |
| `plugin`, `pluginVersion` | the plugin left out |
| `pod`, `podVersion`, `kind`, `source` | the pod, its kind (binary/objc/swift/mixed), where its version came from |
| `requiredBy` | the dependency path (plugin → pod → pod) |
| `detail` | reason details: slices found, versions in conflict, first compiler error (max 20 lines) |
| `engine`, `flutter`, `swift`, `host` | versions and host OS |
| `buildTarget`, `mode` | device/simulator, debug/distribution |

**Never in a report**: the app's name, bundle id, team id, signing data, environment variables, tokens, file contents
other than the compiler lines in `detail`. User and project paths are shortened (`~`, `<project>`); the Studio's
existing redaction (user names in paths, secrets) runs again before sending.

**`xcross pods report [<Pod>] [--json]`** (§13): prints the report(s) from the last `pods-report.json`, ready to send.
In the public engine the hint names this command only (no server, no account: the engine stays free of Studio and
server code). CLI users can attach the output to an issue.

**Studio** (private repo, §14): a card "Plugin X won't work in this build" with the four parts and a **Send to
developer** button. It uses the existing reporter (`apps/studio/lib/src/reports/`):
- the existing dialog asks first, unless "Always send reports without asking" is on;
- an offline outbox;
- one report per signature;
- POST to the server's `report` function.

The first version uses report kind `build` with signature `pod/<Pod>/<version>/<reason>`, so the server and database
need no change (its `error_reports.kind` allows only `crash`, `build`, `setup`). A dedicated kind `plugin` (migration +
function + Studio enum) is optional later (T509). Reports land in the `error_reports` table; there is no admin page for
them yet (T510).

**Developer side**: each report says which pod and which reason. Fixing it means a new known package (the 2026-11-15
route), a converter fix, or a new supported pod kind. The owner reads them in the `error_reports` table until an admin
view exists.

### 12.2 Reasons

`unsupported` reasons: `prepare_command`, `script_phases`, `no_ios`, `not_on_cdn`, `non_trunk_repo`,
`unsupported_source`, `uncompiled_resource`, `ios_minimum`, `objc_uses_own_swift`, `not_yet_supported`,
`skipped_by_user`, `compile_failed`, `converter_off`.

`plugin status --json` (extends feature 028's `plugin_status`; nothing existing renamed): each plugin gets
`"pods": [{"name", "version", "kind", "class", "reason", "requiredBy", "source": "lock|resolved|cache"}]`.

**Pods report**: every build writes `build/xcross-ios/pods-report.json` (graph, classes, reasons, warnings).
`release check` reads it. Its new errors are **only** `pod.*` codes from that report (with `--strict` semantics for
distribution). It does not start failing for plugins that are left out today for other reasons, so existing gate results
do not change (review finding 21).

## 13. What each command does

| Command | Steps (§2) | Network | Notes |
|---|---|---|---|
| `xcross plugin status` | A–C from cache only | no | pods not yet resolved show `source: "cache"` or "not resolved yet: run ios prepare" |
| `xcross plugin check` | A–C from cache only | no | stays "seconds, without compiling" |
| `xcross ios prepare` | A–F | yes | downloads and converts; `--strict` turns pod warnings into errors |
| `flutter build` / `run` | A–G | yes (cache first) | writes the pods report |
| `xcross release check` | reads the pods report + IPA | no | new errors only from `pod.*` codes |
| `xcross cache` | lists/clears `pods/` | no | — |
| `xcross pods report [<Pod>] [--json]` | reads the last `pods-report.json` | no | prints the redacted report(s) of left-out plugins (§12.1) |

## 14. Studio seam (private repo)

- Project → Plugins tab: per plugin, its pods with class and reason ("Built from CocoaPods spec", "Swift package",
  "Left out: <reason>"). Data from `plugin status --json`, refreshed as today (feature 028).
- **Left-out plugin card** (Q1): after a build, prepare or status that leaves a plugin out, show "Plugin X won't work in
  this build" with the four parts of §12.1 and a **Send to developer** button. The button sends the report through the
  existing `ErrorReporter` / `ReportDialog` (asks first, honours "Always send reports without asking", outbox when
  offline, kind `build`, signature `pod/<Pod>/<version>/<reason>`). Show it also in the existing attention list
  (feature 028) so it is not missed.
- Settings: the converter switch; "Clear pod cache" (calls `xcross cache`).
- Build console: `step` events `pod_download` / `pod_convert` with progress.
- No Studio code in this repo; the CLI JSON is the contract.

## 15. Phases

A phase ends when its probe apps build and pass their run-time checks on Windows and Linux (devices where hardware
exists), its evidence is recorded, and its pod kind is added to the enabled kinds (§3.4). Until Phase 1 passes, the
whole converter is off by default (Q3).

| Phase | Scope (tasks) | Target pods | Exit |
|---|---|---|---|
| 0 Foundations | T001–T011: version rules, CDN, lock parser, resolver (with deployment target), consumer view, downloader, cache, planner + classification + status JSON, switches, gating, marker drafts, SwiftPM host checks, xcconfig parser | none built; dry run on every research §3 app | `plugin status` shows the right classes and versions for every app in research §3 |
| 1 Binary pods | T101–T112: binary targets + wrappers, legacy frameworks, `.a`, slices, bitcode, Swift binaries, embedding/App Store rules, resource bundles (+ T108 verification), module maps, linker settings, staging and fingerprint seams | WebRTC-SDK, ObjectBox, MobileVLCKit | P1 probes pass; `binary` kind enabled |
| 2 ObjC/C/C++ sources | T201–T209 + T403: file selection, header trees, dependents' headers, settings + flags, ARC split, `COCOAPODS`/`SWIFT_PACKAGE`, header-only pods, prefix header, sibling plugins | MTBBarcodeScanner, flutter_sound_core, Protobuf 3.11.4, MyFatoorah (headers + xcframework), GTMSessionFetcher, GoogleToolboxForMac, nanopb, PromisesObjC, GoogleDataTransport, the ML Kit closure | P2 probes pass, incl. ML Kit text recognition on a device; `objc` kind enabled |
| 3 Swift and mixed | T301–T306 + T210 | Try, SwiftyRSA, Tap closure (goSellSDK), Braintree 5.6.3 + DropIn, TensorFlowLiteSwift + C (partial fetch), onnxruntime-objc + c | P3 probes pass; `swift` and `mixed` kinds enabled |
| 4 Graph rules | T401–T409: subspec union, duplicate rule, own subspecs, since fallback, pin checker, duplicate symbols, lock writer | Firebase + ML Kit app, old stripe_ios, OneSignal 3.x | P4 probes pass |
| 5 Polish | T501–T506: private spec repos, app-level/extension pods (if Q8), Studio UI, acknowledgements (if Q7), docs, release | — | release gate passes; docs and CHANGELOG done |

Note: the ML Kit probe needs Phase 1 (its binary pods), Phase 2 (its source pods, sibling plugin) and, in an app with
Firebase, Phase 4 (duplicate rule). Without Firebase it passes at the end of Phase 2.

## 16. Risks

| # | Risk | Effect | Mitigation |
|---|---|---|---|
| R1 | CocoaPods has many corners (inheritance, globs, headers, prefix header) | compile errors in converted pods | rules from CocoaPods source (§8); fixture per rule; probe per phase; automatic fallback (§3.5); kind gating (§3.4) |
| R2 | Duplicate code with remote Swift packages | build or run-time failures in common apps | §10.2 rule for every converted pod; P4 probe |
| R3 | SDK signatures for re-wrapped frameworks | App Store rejection | App Store test with a listed, embedded SDK (test-plan §5); keep vendor xcframeworks unchanged |
| R4 | No arm64 simulator slice (ML Kit, old SDKs) | simulator builds of those apps | `pod.no_slice`; device builds unaffected |
| R5 | Bitcode in dynamic vendored frameworks | App Store rejection | detect; strip or refuse in distribution builds (§9.5) |
| R6 | Mixed pods with two-way Swift/ObjC use | cannot be expressed in SwiftPM | direction per pod (§8.8); `objc_uses_own_swift` only for true cycles |
| R7 | Big monorepo downloads | slow first build, disk | partial fetch by repo size (§6.2), cache |
| R8 | CDN availability after trunk read-only | no new specs | cache forever, `XCROSS_PODS_CDN` mirror |
| R9 | `Bundle(for:)` in the plugins dylib does not return the main bundle | resources not found at run time | verify first in T108; if false, place bundles where it looks (redesign §8.7 before Phase 1 ends) |
| R10 | Resource formats needing Apple tools | missing UI at run time | engine compilers where they exist, else `uncompiled_resource` naming the file |
| R11 | Ruby logic in plugin podspecs | wrong dependency list | `pod.podspec_unread`; tests on real podspecs |
| R12 | Header name clashes across pods | wrong header picked | per-dependent `-I` only (§8.5.5), `pod.header_clash` |
| R13 | Vendor SDK licences | — | nothing redistributed; downloads happen on the developer's machine, like CocoaPods; LICENSE kept |
| R14 | Engine release is automatic on push | half-done work reaches customers | converter off by default until Phase 1 evidence; kind gating; push only with owner approval |
| R15 | Linux host differences (case-sensitive files) | header or glob mismatches | case-insensitive matching (§8.2), header aliases (§8.5), probes on Linux (AC-046-29) |
| R16 | Stale plugins dylib reused after pod changes | old code shipped | fingerprint seam (§7.5) |
| R17 | Windows path length and symlinks | extraction failures | 12-character keys, skip non-iOS slices, links turned into copies (§6.3) |
| R18 | Hard links unavailable (different volume, FAT32) | header trees cannot be built | cache and packages on one volume; fail clearly (§7.1) |

Removed from revision 1: "R9 `.unsafeFlags` refused for local packages". SwiftPM allows them for path dependencies, and
existing drafts already use them.

## 17. Open questions for the owner

| # | Question | Recommendation |
|---|---|---|
| Q1 | When a pod cannot be converted or fails to compile: leave the plugin out, or fail the build? | **Decided 2026-11-16 by the owner: show a clear warning and ask to send it to the developer.** Implemented as: leave the plugin out (G4) with the four-part warning, automatic fallback after compile failures (§3.5), and a report the developer can send (§12.1; Studio button, `xcross pods report`). `--strict` and distribution `release check` still fail on `pod.*` codes, so an App Store build never ships without a plugin by accident. |
| Q2 | Write `ios/xcross-pods.lock` with the chosen versions? | Yes, when there is no Podfile.lock: the same versions on every machine. Commit it like Podfile.lock. |
| Q3 | Converter default in the first release? | **Decided 2026-11-16 (owner: OK):** off (opt-in `XCROSS_POD_CONVERTER=on`) until Phase 1 evidence; then on with kind gating. |
| Q4 | Should converted pods need a review like drafts (`review_pending`)? | The plugin's draft keeps the existing review flow; the pods themselves need no review (generated from specs). |
| Q5 | ML Kit without an arm64 simulator slice: accept device-only? | Yes, with `pod.no_slice` (a Mac has the same limit). |
| Q6 | If App Store Connect rejects re-wrapped unsigned SDK frameworks? | Use the vendor's own xcframework where one exists; otherwise leave out for distribution builds. |
| Q7 | Generate a licence acknowledgements file? | Later (Phase 5), only if users ask. |
| Q8 | Support app-level Podfile pods and app extension pods? | Phase 5, after the plugin path is solid; needs its own spec. |
| Q9 | Push the 2026-11-15 changes before 046? | **Decided and done 2026-11-16:** pushed to `main` (commits 8390200, 71485af, 0be3489) before 046 work; the device check (T000b) was not run first. |

## 18. Decisions on every CocoaPods feature (research §11)

| # | CocoaPods feature | Decision |
|---|---|---|
| 1 | Header maps / public and private header trees | §8.5 (trees from hard links, aliases, per-dependent `-I`) |
| 2 | Umbrella header and module map | §8.5.6 (generated, or the pod's own, or none for `module_map: false`) |
| 3 | Subspec inheritance | §8.1 table |
| 4 | Platform-specific attributes | §8.1 (`ios:` merged, duplicates removed; others ignored) |
| 5 | `requires_arc` | §8.3 (non-ARC target) |
| 6 | `static_framework`, `use_frameworks!` | no effect on linking (all pod code goes into the plugins dylib or a binary framework); `use_frameworks!` decides header paths (§8.5) and resources (§8.7) |
| 7 | Resource bundles / plain resources | §8.7 table |
| 8 | xcconfig variables | §8.4 variables table |
| 9 | `user_target_xcconfig` | §8.4: linker keys only |
| 10 | `weak_frameworks` | `-weak_framework` linker flag (§8.4) |
| 11 | Vendored libraries | §9.3 |
| 12 | `prepare_command`, `script_phases` | `unsupported` |
| 13 | `info_plist` | re-wrapped or vendored frameworks: merged into the framework `Info.plist`; resource bundles: into the bundle `Info.plist`; source pods compiled into the dylib: `pod.setting_ignored` (there is no pod framework) |
| 14 | `default_subspecs` | §8.1 (list, string, `:none`; none given → all iOS subspecs except test/app specs) |
| 15 | `swift_versions` | §8.8 |
| 16 | Acknowledgements | Q7 |
| 17 | Privacy manifests | §8.7, §9.8 |
| 18 | SDK signatures | §9.8, test-plan §5 |
| 19 | Bitcode | §9.5 |
| 20 | dSYMs | §9.9 |
| 21 | Test specs / app specs | skipped everywhere, nested ones too |
| 22 | `cocoapods_version` | ignored |
| 23 | `project_header_files` | private headers (§8.5.2) |
| 24 | `module_map: false` | no module map (§8.5.6) |
| 25 | Prefix header (`prefix_header_contents`, `prefix_header_file`) | §8.6 |
| 26 | `preserve_paths` | copied into the package (§8.2) |
| 27 | Version symbols in the umbrella header | §8.5.7 |
| 28 | `COCOAPODS` macro | always defined (§8.3) |
| 29 | `SWIFT_PACKAGE` macro (SwiftPM side) | removed / patched (§8.9) |

## 19. Explicitly out of scope

Running CocoaPods/Ruby/Xcode; `Pods.xcodeproj`; `prepare_command` and `script_phases`; `post_install` hooks (except the
existing permission_handler macros); macOS/tvOS/watchOS/visionOS; x86_64 simulator builds (the engine builds arm64
only); svn/hg sources; Core Data model and Metal compilation; redistributing pod files; changing the user's Podfile or
Podfile.lock.
