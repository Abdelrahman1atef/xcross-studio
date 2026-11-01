---

description: "Task list for feature 001-inspect (xcross inspect)"
---

# Tasks: `xcross inspect` — machine-readable IPA/app report

**Input**: Design documents from `specs/001-inspect/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[contracts/cli.md](contracts/cli.md), [contracts/inspect.schema.json](contracts/inspect.schema.json),
[quickstart.md](quickstart.md)

**Tests**: Required. Constitution Principle VI (test-first): every `AC-001-n` maps to a test whose name contains the
AC id. Write each story's tests first and confirm they fail before implementing.

**Organization**: tasks are grouped by user story. US1 = see what is inside an IPA (P1, MVP), US2 = compare builds
(`--normalize`, P2), US3 = safe report for bug reports (P3).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1, US2 or US3
- Paths are repo-relative. `SX` = `packages/studio_ext`, `SXI` = `packages/studio_ext/lib/src/shared/inspect`,
  `SXT` = `packages/studio_ext/test/shared/inspect`.

## Rules that apply to every task

- Every file under `SXI` is library code: annotate each public top-level declaration with `@internal`
  (`package:meta`). No `export` directives, no `show`/`hide`, no private class names (`_Foo`).
- No `File()`, `Directory()`, `Link()`, `FileSystemEntity.*`, `Process.*`, `stdout`, `stderr` or `Platform.*` in
  `SX/lib`. Files come through the injected cli_kit `HostFileSystemInterface`, and output through an injected
  `void Function(String)` writer. Do not build effectful services in field initialisers or parameter defaults.
- Upstream files are changed only at the seams listed in plan.md, and each change carries a `// studio:` comment
  (`# studio:` in YAML).
- New fork files start with the repository's usual header style (none upstream; do not invent licence banners).
- After each phase, run `dart analyze --fatal-warnings` from the repo root and `dart test` in `SX`; both must be clean.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: create the `studio_ext` workspace package and wire it into the workspace and CI.

- [X] T001 Create `packages/studio_ext/pubspec.yaml`, modelled on `packages/cli_kit/pubspec.yaml`:
  - `name: studio_ext`, `version: 0.1.0`, `publish_to: none`, `environment: sdk: ^3.10.0`, `resolution: workspace`
  - dependencies `archive: ^4.5.2`, `args: ^2.7.0`, `cli_kit: ^1.0.0`, `crypto: ^3.0.8`, `meta: ^1.19.0`,
    `path: ^1.9.1`, `propertylistserialization: ^1.5.0` (all already in the workspace lock)
  - dev_dependencies `test: ^1.33.0`

  Also create `packages/studio_ext/analysis_options.yaml` (copy `packages/cli_kit/analysis_options.yaml`, which
  includes `../../analysis_options.yaml`), `packages/studio_ext/README.md` (one paragraph: fork-only features of
  XCross Studio, first one `xcross inspect`) and `packages/studio_ext/LICENSE` (copy of the root `LICENSE`).
- [X] T002 Add `- packages/studio_ext  # studio: fork features package` to the `workspace:` list in the root
  `pubspec.yaml`, run `dart pub get` from the repo root, and keep the regenerated `pubspec.lock` (CI uses
  `--enforce-lockfile`).
- [X] T003 [P] Add `studio_ext` to the package test loops in `.github/workflows/unit-tests.yml` (lines 67-68) and
  `.github/workflows/release.yml` (lines 67-68 and 223-224), each with a `# studio:` comment. In `release.yml`,
  disable the "Validate pub.dev package" step (`dart pub publish --dry-run`, line 72-74) with
  `if: false  # studio: fork does not publish xcross to pub.dev; xcross depends on unpublished studio_ext`.
- [X] T004 [P] Add `'studio_ext'` to the `_packages` set in `packages/xcross/test/no_deep_imports_test.dart`
  (`// studio:` comment) so imports of `package:studio_ext/src/...` from other packages are rejected.

**Checkpoint**: `dart pub get` and `dart analyze --fatal-warnings` succeed with the empty package.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: test fixtures, report model, deterministic JSON and the low-level read-only parsers that every story
needs.

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T005 Create the synthetic fixture builder `packages/studio_ext/test/support/fixture_builder.dart` (research R13).
  It is test-only code with no I/O except writing into a caller-provided temp directory, and it provides:
  - **Mach-O**: thin 64-bit arm64, thin 32-bit armv7, fat 32-bit (`0xcafebabe`) and fat 64-bit (`0xcafebabf`)
    containers, each optionally with an `LC_CODE_SIGNATURE` (0x1d) load command pointing at a signature blob.
  - **Code signature**: a big-endian SuperBlob (`0xfade0cc0`) containing a CodeDirectory (`0xfade0c02`, version
    `0x20400`, configurable flags `0x2`/`0x20000`, identifier, team id), an optional XML entitlements blob
    (`0xfade7171`, slot 5), an optional DER entitlements blob (`0xfade7172`, slot 7) and an optional CMS
    blob-wrapper (`0xfade0b01`, slot `0x10000`) that is empty or non-empty.
  - **Profile**: `embedded.mobileprovision` bytes as a CMS ContentInfo/SignedData whose eContent is an XML plist. It
    supports both DER definite lengths and BER indefinite lengths with a chunked constructed OCTET STRING.
  - **Plists**: XML and binary, via `PropertyListSerialization` from `propertylistserialization`.
  - **Bundles**: `.app` directories, and `.ipa` files written with `archive`'s `ZipEncoder`, with every entry's
    `lastModTime` fixed to 2020-01-01T00:00:00Z and entries sorted by name.
  - **The three named fixtures from research R13**: `unsignedV209`, `adhocPush`, `profileAppex` (with planted fake
    UDIDs `00008020-001A2B3C4D5E6F70` style, planted `GMSApiKey`, planted certificate bytes). Plus negative variants:
    no app, two apps, corrupt zip, truncated Mach-O, missing icon files, binary Info.plist, symlink in a `.app`
    directory.
- [X] T006 [P] Create `SXI/inspect_codes.dart`: string constants for every fatal and issue code in
  [contracts/cli.md](contracts/cli.md) (`inspect.input_not_found` … `inspect.xcross_private_keys_in_signed_bundle`),
  each paired with its fix hint text from that table. Also create `SXI/inspect_failure.dart` with
  `final class InspectFailure implements Exception { code, message, hint }`.
- [X] T007 [P] Create the report model `SXI/inspect_report.dart`, matching [data-model.md](data-model.md) exactly:
  - **Classes**: immutable `InspectReport`, `InputInfo`, `BundleInfo`, `BundleSignature`, `ExecutableInfo`,
    `ExecutableSignature`, `ProfileSummary`, `Resources`, `Icons`, `DeclaredIcon`, `AssetsCar`, `LaunchScreen`,
    `LaunchImage`, `LaunchStoryboard`, `FrameworkInfo`, `ExtensionInfo` and `Issue` (severity enum
    `warning`/`error`).
  - **Serialisation**: each class has `Map<String, Object?> toJson()` that emits fields in the data-model table
    order, always emitting every field (nullable fields as `null`).
  - **Values**: enum-like strings are exactly `"ipa" | "app"`, `"none" | "adhoc" | "certificate"`,
    `"main" | "framework" | "dylib" | "extension"`, `"development" | "ad-hoc" | "app-store" | "enterprise"`,
    `"UILaunchScreen" | "storyboard" | "none"`, `"loose-file" | "asset-catalog" | "missing"` and
    `"framework" | "dylib"`.
  - **Sorting**: `InspectReport` sorts `executables`, `frameworks` and `extensions` by `path`, and `issues` by `path`
    (null first) then `code`.
- [X] T008 [P] Create `SXI/report_json.dart`, the deterministic encoder (research R9):
  `String encodeReportJson(Object? json)` uses `JsonEncoder.withIndent('  ')`, then escapes every code unit above
  `0x7e` as `\uXXXX` (lowercase hex, 4 digits), ends with exactly one `\n`, and never writes `\r`. Add tests in
  `SXT/report_json_test.dart`: ASCII escaping of `é`, `✔`, an emoji (surrogate pair), key order preserved, trailing
  newline, and no `\r`.
- [X] T009 [P] Create `SXI/plist_reader.dart` (research R3):
  - `PlistDocument? readPlist(Uint8List bytes)` returns `{format: xml|binary, Object root}`, or `null` when the bytes
    are neither format.
  - Parse with `PropertyListSerialization.propertyListWithData` (binary, after a `bplist00` sniff) or
    `propertyListWithString` (XML, UTF-8 decoded) inside
    `runZoned(..., zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}))`. Catch every exception and return
    `null`.
  - `Object? plistToJson(Object? value)`: dicts become sorted-key maps; `DateTime` → UTC ISO-8601 ending in `Z`;
    `ByteData`/`Uint8List` → `{"$data": base64}`; non-finite doubles → string.

  Add tests in `SXT/plist_reader_test.dart`: XML and binary round trip, date and data mapping, invalid bytes return
  `null`, and nothing is printed (wrap the test in a zone that records `print`).
- [X] T010 [P] Create `SXI/ber_reader.dart` (research R7): a minimal BER/DER reader over `Uint8List`.
  - It handles tag class, constructed bit and low tag numbers, definite short/long lengths, and indefinite lengths
    terminated by `00 00`.
  - API: `BerElement read(Uint8List, int offset)` returning `{tag, constructed, contentStart, contentEnd,
    elementEnd, children}`, plus `Uint8List octetStringValue(BerElement)` that concatenates chunked constructed
    OCTET STRINGs.
  - Throw `FormatException` on overruns.

  Add tests in `SXT/ber_reader_test.dart`: definite, indefinite, nested indefinite, chunked OCTET STRING, truncated
  input.
- [X] T011 [P] Create `SXI/macho_reader.dart` (research R4):
  - `MachOInfo readMachO(Uint8List bytes)` → `{List<MachOSlice> slices}`, where each slice is
    `{architecture, offset, size, codeSignatureOffset?, codeSignatureSize?}`.
  - Accept magics `0xfeedface`, `0xfeedfacf` (either byte order), `0xcafebabe` and `0xcafebabf`.
  - Architecture names: `arm64` (0x0100000c/0), `arm64e` (0x0100000c/2), `armv7` (12/9), `armv7s` (12/11),
    `x86_64` (0x01000007), `i386` (7), otherwise `cpu:<type>/<subtype>` with the subtype masked by `0x00ffffff`.
  - `MachOSlice preferredSlice` = the first arm64/arm64e slice, else the first slice.
  - Bounds-check every read and throw `FormatException('truncated …')` on overrun.
  - `bool hasMachOMagic(Uint8List head)` checks for all six magics.

  Add tests in `SXT/macho_reader_test.dart`: thin 64-bit, thin 32-bit, fat 32-bit, fat 64-bit, byte-swapped,
  truncated header, truncated load commands, signature offset found.
- [X] T012 Create `SXI/code_signature_reader.dart` (research R5, R6; depends on T009, T011):
  - `CodeSignatureInfo readCodeSignature(Uint8List sliceBytes, MachOSlice slice)` → `{kind, linkerSigned,
    identifier?, teamId?, entitlements?, derEntitlementsPresent, malformed}`.
  - Kind: `none` without `LC_CODE_SIGNATURE`; `certificate` when slot `0x10000` is a `0xfade0b01` blob with length
    > 8; else `adhoc`.
  - `linkerSigned` = CodeDirectory flags & `0x20000`. The team id is read only when CodeDirectory version ≥
    `0x20200`.
  - Entitlements come from the slot-5 `0xfade7171` blob via `readPlist` + `plistToJson`; null if absent.
  - A malformed SuperBlob → `malformed: true` and kind `adhoc`.

  Add tests in `SXT/code_signature_reader_test.dart`: unsigned, linker ad-hoc, ad-hoc with XML entitlements
  (`aps-environment: development`), DER-only, certificate (non-empty CMS), empty CMS treated as ad-hoc, malformed
  blob.
- [X] T013 Create `SXI/profile_reader.dart` (research R7, R8; depends on T009, T010):
  - `ProfileSummary? readProfile(Uint8List bytes)` walks ContentInfo (OID `1.2.840.113549.1.7.2`) → `[0]`
    SignedData → encapContentInfo → `[0]` eContent → plist. It returns `null` on any failure.
  - Kind rules, verbatim from data-model: "`ProvisionsAllDevices == true` → enterprise; `ProvisionedDevices` present
    and `Entitlements.get-task-allow == true` → development; `ProvisionedDevices` present otherwise → ad-hoc;
    neither → app-store".
  - Copy only `Name`, the first `TeamIdentifier`, `UUID`, `CreationDate`/`ExpirationDate` (ISO-8601 UTC), sorted
    `Platform`, `Entitlements` (sorted), `provisionsAllDevices`, `deviceCount` (length of `ProvisionedDevices`, or
    `null` when absent) and `certificateCount`.
  - "Never present: device UDIDs, certificate bytes, names or serials, `TeamName`, `AppIDName`".

  Add tests in `SXT/profile_reader_test.dart` for all 4 kinds × {DER, BER indefinite}. Also assert that the encoded
  JSON of the summary contains none of the planted UDIDs and no `TeamName`.
- [X] T014 Create `SXI/inspect_source.dart` (research R11; depends on T006):
  - The abstract `InspectSource` exposes `kind`, `name`, `sizeBytes?`, `sha256?`, `bundlePath`,
    `List<String> entries` (POSIX paths relative to the bundle root, sorted), `Uint8List? read(String relPath)`,
    `List<String> skippedSymlinks` and `void close()`.
  - **`IpaSource.open(HostFileSystemInterface fs, String path)`**: `InputFileStream(fs.file(path).path)` +
    `ZipDecoder().decodeStream`. Normalise `\` to `/` in entry names. Find `Payload/<X>.app/` prefixes: none →
    `InspectFailure(inspect.no_app)`, several → `InspectFailure(inspect.multiple_apps)`. A decode failure →
    `InspectFailure(inspect.corrupt_archive)`. Inflate entries lazily and release their content after `read`.
    Compute the file's `sha256` with `package:crypto` over the file read in chunks (lowercase hex).
  - **`AppDirectorySource.open(fs, path)`**: list with `fs.directory(path).listSync(recursive: true,
    followLinks: false)`. Links go to `skippedSymlinks`. Read through `fs.file(...)`. `sizeBytes`/`sha256` are
    `null`.
  - **`InspectSource.open(fs, path)`**: missing path → `inspect.input_not_found`; a directory ending in `.app` →
    `AppDirectorySource`; a file ending in `.ipa` → `IpaSource`; else `inspect.unsupported_input`.

  Add tests in `SXT/inspect_source_test.dart` using a real temp dir and `cli_kit`'s native host file system (see
  how `packages/xcross/test/cli/runtime_fixture.dart` builds `LinuxHost(fileSystem: …)`, or implement a tiny
  `HostFileSystemInterface` test double over `dart:io` in `packages/studio_ext/test/support/test_file_system.dart`).
  Cover: ipa entries, app entries, no app, multiple apps, corrupt zip, unsupported input, missing input, symlink
  skipped (skip only the symlink case on Windows when creating links needs privileges, with a reason).

**Checkpoint**: all parser unit tests are green on the local OS; `dart analyze --fatal-warnings` is clean.

---

## Phase 3: User Story 1 — See what is inside my IPA (Priority: P1) 🎯 MVP

**Goal**: `xcross inspect <ipa|app>` prints a readable summary, and `--json` prints a document that validates against
`contracts/inspect.schema.json` (AC-001-1…5, FR-001…004, FR-006…008).

**Independent Test**: inspect `unsignedV209.ipa`, `adhocPush.app` and `profileAppex.ipa` from the fixture builder;
the JSON matches the committed goldens byte for byte on every OS, and the summary prints.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T015 [P] [US1] `SXT/inspector_test.dart`, test `AC-001-1 unsigned v2.0.9-style IPA`: `signature.present ==
  false`, `profile == null`, and correct `bundle.bundleId`, `shortVersion`, `buildNumber`, `minimumOSVersion`.
  `frameworks` lists `App.framework`, `Flutter.framework` and the plugin dylib, sorted by path. Also
  `resources.launchScreen.kind == "UILaunchScreen"` with `keys == []` and issue `inspect.launch_screen_empty`.
- [X] T016 [P] [US1] `SXT/inspector_test.dart`, test `AC-001-2 ad-hoc main executable exposes aps-environment`: the
  main `executables[]` entry has `signature.kind == "adhoc"` and `entitlements["aps-environment"] == "development"`,
  and associated domains are present.
- [X] T017 [P] [US1] `SXT/inspector_test.dart`, test `AC-001-3 profile summary without UDIDs`: `profile.kind ==
  "development"`, `teamId`, `expirationDate`, `entitlements`, `deviceCount == <planted count>`. The encoded JSON
  contains no planted UDID and no certificate bytes (base64 or hex). The extension's own `profile` is reported.
- [X] T018 [P] [US1] `SXT/bundle_resources_test.dart` and `SXT/inspector_test.dart`, test `AC-001-4 icons, Assets.car,
  launch screen`:
  - declared `CFBundleIcons` names, with `files` resolved by the `<name>[@2x|@3x][~ipad][.png]` rules and
    `resolved` flags
  - `inspect.icon_file_missing` for a name without files
  - `assetsCar.present` true with `sizeBytes`
  - `UILaunchScreen` keys and `image.source` for `loose-file` (issue `inspect.launch_image_not_in_catalog`),
    `asset-catalog` and `missing` (issue `inspect.launch_image_missing`)
  - a storyboard with `compiledPresent == false` (issue `inspect.launch_storyboard_missing`)
  - `inspect.no_icon` when nothing is declared and there is no `Assets.car`
- [X] T019 [P] [US1] `SXT/golden_test.dart`, test `AC-001-5 report matches committed golden` (one case per fixture,
  covering SC-003): build each fixture into a temp dir and run the inspector + `encodeReportJson`. Compare with
  `packages/studio_ext/test/goldens/<fixture>.json` byte for byte; write the file instead when
  `UPDATE_GOLDENS=1`. The test reads the env var through `Platform.environment`, which is allowed in `test/`. Fixture
  inputs must be named identically on every OS so `input.name` and `sha256` match.
- [X] T020 [P] [US1] `SXT/inspect_command_test.dart`: run `InspectCommand` through
  `CommandRunner<void>('xcross', 'test')..addCommand(...)` with a recording writer, and assert:
  - `--json` output is exactly one JSON document with nothing before or after it
  - a fatal error writes the error document (`schemaVersion: 1`, `error.code`) and throws `CliError` whose message
    starts with `[inspect.input_not_found]`
  - missing path → `UsageException`; two paths → `UsageException`
  - test `FR-006 input is not modified`: the input file's sha256 and mtime are unchanged afterwards
  - edge cases `inspect.no_app`, `inspect.multiple_apps` and `inspect.corrupt_archive` surface as error documents
  - a truncated Mach-O yields exit-0 output with issue `inspect.macho_invalid`
- [X] T021 [P] [US1] `SXT/schema_conformance_test.dart`: for each fixture's JSON, check structurally against
  `specs/001-inspect/contracts/inspect.schema.json` without a new dependency. Assert that the top-level and nested
  objects have exactly the required key sets listed in the schema (load the schema JSON at runtime from the repo
  path, walk `required`/`properties` for `report` and its `$ref`s), plus enum values and the `relPath` rule (no
  leading `/`, no drive letter, no `\`).
- [X] T022 [P] [US1] `packages/xcross/test/cli/inspect_registration_test.dart`: the runner built by
  `XcrossCli.buildRunner(testApplication(), configTerminal: TestTerminal())` (see `test/cli/runtime_fixture.dart`)
  has an `inspect` command. `XcrossCli.ownsMachineStdout(['inspect', 'x.ipa', '--json'], runner)` is `true`, and it is
  `false` without `--json`.

### Implementation for User Story 1

- [X] T023 [US1] Create `SXI/bundle_resources.dart` (depends on T007, T014):
  - **Icons**: `Resources readResources(InspectSource, Map<String, Object?>? infoPlist, List<Issue> issues)` reads
    `CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles`, `CFBundleIcons~ipad` and legacy `CFBundleIconFile`.
    Icon file matching is "`<name>[@2x|@3x][~ipad][.png]`" against root-level entries, case-sensitive. `iconName`
    comes from `CFBundlePrimaryIcon.CFBundleIconName`.
  - **Assets.car**: root `Assets.car` presence and size.
  - **Launch screen**: "`UILaunchScreen` wins when both are declared". Image source rules: `loose-file` when a
    matching PNG exists, else `asset-catalog` when `Assets.car` is present, else `missing`. Storyboard
    `compiledPresent` = `<name>.storyboardc/` exists.
  - **Storyboards**: all `*.storyboardc` directory paths, sorted.
  - **Issues**: emit `inspect.no_icon`, `inspect.icon_file_missing`, `inspect.no_launch_screen`,
    `inspect.launch_screen_empty`, `inspect.launch_image_missing`, `inspect.launch_image_not_in_catalog` and
    `inspect.launch_storyboard_missing` as specified in data-model.md, with hints from `inspect_codes.dart`.
- [X] T024 [US1] Create `SXI/inspector.dart` (depends on T009–T014, T023):
  - **Entry point**: `InspectReport inspect(InspectSource source)` reads the root `Info.plist`. Missing or invalid →
    issue `inspect.info_plist_unreadable` (severity `error`), with every bundle value `null`/`[]`.
  - **Bundle**: build `BundleInfo` (allow-listed `plist` values only: `CFBundleIcons`, `CFBundleIcons~ipad`,
    `CFBundleIconName`, `CFBundleIconFile`, `UILaunchScreen`, `UILaunchStoryboardName`, `UIBackgroundModes`; all key
    names in `infoPlistKeys`; `xcrossPrivateKeys` booleans).
  - **Executables**: discover them structurally (main; `Frameworks/<X>.framework/<exec>` with the exec name from its
    Info.plist, else `X`; `Frameworks/*.dylib`; `PlugIns/<X>.appex/<exec>`). Read each with `readMachO` +
    `readCodeSignature`. A missing file → `inspect.executable_missing`; a `FormatException` →
    `inspect.macho_invalid` with `architectures: []`; a malformed signature → `inspect.signature_invalid`; DER-only
    → `inspect.entitlements_der_only`; an unreadable XML entitlements blob → `inspect.entitlements_unreadable`.
  - **Signature**: `BundleSignature.present` = root `_CodeSignature/CodeResources` exists; kind and team id come
    from the main executable.
  - **Profile**: read the root profile with `readProfile`; failure → `inspect.profile_unreadable`.
  - **Frameworks and extensions**: build `FrameworkInfo` (with `bundleId` from the framework Info.plist; an invalid
    one → `inspect.plist_unreadable`) and `ExtensionInfo` (with `NSExtension.NSExtensionPointIdentifier` and its
    own profile).
  - **Other issues**: `inspect.symlink_skipped` for each skipped link. `inspect.xcross_private_keys_in_signed_bundle`
    when `signature.present` and `XCrossEntitlements` or `XCrossCapabilities` is present.
  - **Input**: `input` from the source (`name` = basename only).
- [X] T025 [US1] Create `SXI/human_summary.dart` (research R14, [contracts/cli.md](contracts/cli.md) "Human summary"):
  `String renderHumanSummary(InspectReport report)`. It prints a header line, then ✔/✖ lines for signed,
  provisioning profile, push entitlement (✖ notes "profile grants it" when only the profile has
  `aps-environment`), associated domains, icon, launch screen and frameworks, and ends with
  `<n> issues — run with --json for details`. Only allow-listed values appear, never UDIDs, profile UUIDs or
  certificate data.
- [X] T026 [US1] Create the public command `packages/studio_ext/lib/shared/inspect/inspect_command.dart` (depends on
  T008, T024, T025):
  - `final class InspectCommand extends Command<void>`, `name = 'inspect'`, with a description and the
    `invocation` from cli.md. Constructor `InspectCommand({required HostFileSystemInterface fileSystem,
    required void Function(String) write})`. Flags `--json` (`negatable: false`).
  - `run()`: exactly one rest argument, else `usageException`. Then `InspectSource.open` → `inspect` → write
    `encodeReportJson(report.toJson())` or `renderHumanSummary(report)`.
  - On `InspectFailure`: with `--json` write the error document via `encodeReportJson`; then throw
    `CliError('[<code>] <message>\nhint: <hint>')`. Always `source.close()` in `finally`.
- [X] T027 [US1] Register the command at the upstream seams:
  - `packages/xcross/pubspec.yaml`: add `studio_ext: ^0.1.0  # studio:`, then `dart pub get`.
  - `packages/xcross/lib/src/composition/cli/runner.dart`: import
    `package:studio_ext/shared/inspect/inspect_command.dart`, and add
    `InspectCommand(fileSystem: runtime.host.fileSystem, write: runtime.log.output.write), // studio:` to the
    `commands` list after `CompletionCommand`.
  - In `ownsMachineStdout`, add `|| command?.name == 'inspect' && command?['json'] == true // studio:`.
- [X] T028 [US1] Generate and commit the three goldens: run `UPDATE_GOLDENS=1 dart test test/shared/inspect/golden_test.dart`
  in `packages/studio_ext`. Review `packages/studio_ext/test/goldens/{unsigned_v209,adhoc_push,profile_appex}.json`
  by hand against data-model.md (field order, sorting, no secrets, ASCII only), then re-run without the env var
  (green).
- [X] T029 [P] [US1] `SXT/perf_test.dart`, test `SC-001 20 MB IPA under 3 s`: the fixture builder creates an IPA
  with a 20 MB incompressible `Frameworks/App.framework/App` Mach-O (random-but-seeded bytes after a valid
  header). Assert that `inspect` + encode completes in < 3 s (Stopwatch).
- [X] T030 [P] [US1] `SXT/real_ipa_test.dart`: skipped unless `STUDIO_INSPECT_IPA` is set
  (`skip: Platform.environment['STUDIO_INSPECT_IPA'] == null ? 'set STUDIO_INSPECT_IPA=<path>' : false`). Inspects
  the given IPA, runs the structural schema check from T021, and asserts no UDID-shaped strings
  (`[0-9a-f]{40}` or `[0-9A-F]{8}-[0-9A-F]{16}`) appear.

**Checkpoint**: US1 complete. `dart run packages/xcross/bin/xcross.dart inspect <fixture.ipa> --json` prints pure
JSON with no credits banner, and all US1 tests are green.

---

## Phase 4: User Story 2 — Compare two builds (Priority: P2)

**Goal**: `--json --normalize` output is identical for two builds of the same source (AC-001-6, FR-005).

**Independent Test**: build the same fixture twice with different zip mtimes, profile dates and profile UUID; the
normalised outputs are equal.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T031 [P] [US2] `SXT/normalize_test.dart`, test `AC-001-6 two builds of the same source normalise equal`:
  - Build `profileAppex` twice with different mtimes, `CreationDate`/`ExpirationDate` and `UUID`.
  - Raw outputs differ; `--normalize` outputs are byte-identical.
  - Normalised: `normalized == true`, `input.sizeBytes == null`, `input.sha256 == null`, `profile.uuid ==
    "<uuid>"`, `profile.creationDate == "<date>"`, `profile.expirationDate == "<date>"`,
    `resources.assetsCar.sizeBytes == null`, and the same for every extension profile.
- [X] T032 [P] [US2] Extend `SXT/inspect_command_test.dart`: `--normalize` without `--json` → `UsageException`;
  `--json --normalize` sets `normalized: true`.

### Implementation for User Story 2

- [X] T033 [US2] Create `SXI/report_normalizer.dart`: `Map<String, Object?> normalizeReportJson(Map<String, Object?>)`
  works on the report's JSON map (simpler than copying every model class) and returns a copy with exactly the
  replacements in research R10 (including `extensions[].profile`); nothing else changes.
- [X] T034 [US2] In `packages/studio_ext/lib/shared/inspect/inspect_command.dart`, add the `--normalize` flag
  (`negatable: false`). Without `--json` → `usageException('--normalize requires --json')`; with it, apply
  `normalizeReport` before encoding.

**Checkpoint**: US1 and US2 both work; the golden tests (raw) and the normalize test are green.

---

## Phase 5: User Story 3 — Attach a safe report to a bug (Priority: P3)

**Goal**: the human summary (default output) is a short ✔/✖ list, and no output mode leaks secrets (AC-001-7, FR-004,
SC-004).

**Independent Test**: inspect `profileAppex` (planted UDIDs, API key, certificate bytes) in every output mode and find
no secret.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T035 [P] [US3] `SXT/human_summary_test.dart`, test `AC-001-7 ✔/✖ summary without secrets`:
  - For each fixture, the summary has the lines signed, provisioning profile, push entitlement, associated domains,
    icon, launch screen, frameworks and the issue count, with the expected ✔/✖ markers.
  - `unsignedV209`: ✖ signed, ✖ profile, ✖ push, ✖ icon, ✖ launch screen.
  - `adhocPush`: ✔ push.
  - `profileAppex`: ✔ signed (certificate), ✔ profile development with device count.
- [X] T036 [P] [US3] `SXT/redaction_test.dart`, test `SC-004 no UDID, key or certificate bytes in any output`: for
  every fixture × {human, `--json`, `--json --normalize`}, the output contains none of the planted UDIDs, the
  planted `GMSApiKey` value, the planted certificate bytes (base64, hex, raw), `TeamName` or `AppIDName` values, or
  any absolute temp-dir path.

### Implementation for User Story 3

- [X] T037 [US3] Fix whatever T035/T036 expose in `SXI/human_summary.dart`, `SXI/inspector.dart` or
  `SXI/profile_reader.dart`. Keep the allow-list approach (research R8) and do not add masking heuristics.
- [X] T038 [US3] Add a "Reporting a bug" note to `README.md`, next to the new command row (T039): attach
  `xcross inspect <ipa> --json --normalize`, which by design contains no UDIDs, keys or certificate data.

**Checkpoint**: all three stories are complete and independently tested.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T039 [P] Document the command in `README.md`: a row `xcross inspect <ipa|app> [--json] [--normalize]` in the
  command table (around lines 367-396) and a `<details>` block with the flags and exit codes, in the existing
  style. Mark it as a fork addition (`<!-- studio: -->`).
- [X] T040 [P] Add a fork entry to `CHANGELOG.md` in the existing bullet style: "`xcross inspect` reports what is
  inside an IPA or .app (Info.plist, entitlements per Mach-O, provisioning profile, icons, launch screen,
  frameworks) as text or deterministic JSON."
- [X] T041 [P] Update `specs/ROADMAP.md` row 001 status to `Implemented`, and `specs/HANDOFF.md` "State right now"
  (001 implemented; `origin` remote still to add if not done).
- [X] T042 Run `dart format packages/studio_ext` plus the touched upstream Dart files, then
  `dart analyze --fatal-warnings` from the repo root. Fix every finding, including `repo_analyzer` rules.
- [X] T043 Run the full test suites locally: `dart test` in `packages/studio_ext`, and in `packages/xcross` at least
  `test/cli/inspect_registration_test.dart`, `test/no_deep_imports_test.dart` and `test/cli/runner_test.dart` if it
  exists (prefer the full `dart test` when time allows). Record the results.
- [X] T044 Run the [quickstart.md](quickstart.md) sections 1–3 manually: run the command on a fixture IPA in each
  mode, check exit codes 0/1/64, and confirm that `--json` stdout has no banner. Note in the completion report that
  section 4 (real IPAs on Windows and Linux hosts) still needs the user.

- [ ] T045 **Deferred by the user (2026-11-01): Linux verification.** On an Ubuntu 24.04 host (or via the
  `ubuntu-24.04` unit-test CI job), run `dart test` in `packages/studio_ext` and confirm the committed goldens match
  byte for byte (AC-001-5, Principle V). Then run [quickstart.md](quickstart.md) section 4 on Linux: inspect the same
  real IPA as on Windows with `--json --normalize` and `diff` the two outputs (expected: identical).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T003 and T004 run in parallel after T001/T002.
- **Foundational (Phase 2)**: depends on Setup. T005 first, because the parser tests use it. T006–T011 then run in
  parallel. T012 needs T009 and T011. T013 needs T009 and T010. T014 needs T006.
- **US1 (Phase 3)**: depends on Phase 2. Tests T015–T022 [P] come first. Then T023 → T024 → T025 → T026 → T027 →
  T028. T029 and T030 can run after T024.
- **US2 (Phase 4)**: depends on Phase 2 and on T026 (the command exists). T031/T032 → T033 → T034.
- **US3 (Phase 5)**: depends on T025/T026 (summary and command) and T034 (the normalize mode is part of the audit).
  T035/T036 → T037 → T038.
- **Polish (Phase 6)**: after the desired stories; T042–T044 last.

### User Story Dependencies

- **US1 (P1)**: independent; it is the MVP.
- **US2 (P2)**: reuses the US1 report and command, and adds only the normaliser and a flag. It is testable on its own
  with `normalize_test`.
- **US3 (P3)**: reuses the US1 summary; it adds verification and hardening. It is testable on its own with the
  summary and redaction tests.

### Within Each User Story

- Tests are written first and must fail.
- Model/parsers (Phase 2) → resources → inspector → summary → command → registration → goldens.

## Parallel Example: User Story 1

```text
Task: "T015 AC-001-1 test in packages/studio_ext/test/shared/inspect/inspector_test.dart"
Task: "T018 AC-001-4 test in packages/studio_ext/test/shared/inspect/bundle_resources_test.dart"
Task: "T020 command tests in packages/studio_ext/test/shared/inspect/inspect_command_test.dart"
Task: "T021 schema conformance test in packages/studio_ext/test/shared/inspect/schema_conformance_test.dart"
Task: "T022 registration test in packages/xcross/test/cli/inspect_registration_test.dart"
```

Foundational parsers in parallel: T008 `report_json.dart`, T009 `plist_reader.dart`, T010 `ber_reader.dart`, T011
`macho_reader.dart`.

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1 Setup → Phase 2 Foundational.
2. Phase 3 (US1) → **validate**: goldens green, `xcross inspect --json` works end to end.
3. That is enough for M0's "inspect works on a v2.0.9 IPA".

### Incremental Delivery

1. US1 → JSON + summary (MVP).
2. US2 → `--normalize` for CI comparisons.
3. US3 → summary acceptance + redaction audit.
4. Polish → docs, changelog, roadmap, analyze, full tests.

## Notes

- AC ids must appear verbatim in test names (`dart test --name AC-001-` selects them).
- Do not commit real IPAs, profiles or reports with client data.
- Do not commit or push without the user's go-ahead; leave changes in the working tree.
