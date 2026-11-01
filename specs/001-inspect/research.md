# Research: `xcross inspect`

Phase 0 output for [plan.md](plan.md). Each entry gives the decision, why, and what else was considered. Paths: X =
`packages/xcross/lib/src`, ADK = `packages/apple_developer_kit/lib/src/shared/signing`.

## R1 — Package and registration

- **Decision**: put the code in a new workspace package `packages/studio_ext`. The public entry point is
  `lib/shared/inspect/inspect_command.dart` (a plain `package:args` `Command<void>`, like `CompletionCommand`). It is
  registered in the command list of `XcrossCli.buildRunner` (`X/composition/cli/runner.dart:84-135`). `xcross`
  depends on `studio_ext`, and `studio_ext` depends only on `cli_kit` and third-party packages, so there is no cycle.
- **Rationale**: Principle I (fork features in new files, upstream touched only at seams). The command needs only two
  flags, so `ParsedCommand`/`build_cli` (xcross-internal, code generation) adds nothing.
- **Alternatives**: new files inside `packages/xcross` (rejected: against Principle I; an upstream PR can still move
  the code there later). Depending on `xcross` from `studio_ext` (rejected: dependency cycle and `@internal` access).

## R2 — Reuse vs own parsers

- **Decision**: write small read-only parsers in `studio_ext`.
- **Rationale**: the readers that exist are not usable from another package or not suitable:
  - `decodePropertyList` (`ADK/plist.dart:17`), `parseProfileCms` (`ADK/provisioning_profile.dart:27`), `DerReader`
    (`ADK/der.dart:257`), `MachOLayout` (`ADK/macho_format.dart:266`) and `BundleInspector` are `@internal` under
    `lib/src`. Importing them from another package breaks `implementation_imports`, the deep-import test and
    `invalid_use_of_internal_member`.
  - `MachOLayout` rejects fat, 32-bit, big-endian, non-arm64 and encrypted binaries (`ADK/internal/macho_header.dart:45-58`).
  - `DerReader` rejects indefinite-length encoding (`ADK/der.dart:291-292`).
  - The ADK signature code (`ADK/code_signature.dart`) only writes signatures. The only SuperBlob reader,
    `MachOCodeSignature.refreshAdHocPageHashes` (`X/shared/apple/mach_o_code_signature.dart`), is a private rewrite
    walk, not a reusable model.
- **Alternatives**: export the ADK readers publicly (rejected: many upstream edits, dropping `@internal`, and it still
  would not read fat or BER input). Shell out to `openssl`/`rcodesign`/`ldid` (rejected: not installed on target hosts,
  output differs by OS, and Principle VII).

## R3 — Property lists

- **Decision**: sniff the format. `bplist00` → binary, otherwise XML (`<?xml` or `<plist`). Parse with
  `propertylistserialization` 1.5.0 inside `runZoned(..., zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}))`.
  The library `print`s a stack trace on failure, which would otherwise corrupt `--json` stdout. JSON value mapping:
  - string, bool and int map to themselves
  - real → JSON number; NaN/Infinity → string
  - date → ISO-8601 UTC with `Z`
  - data (`ByteData`) → `{"$data": "<base64>"}`
  - array → array
  - dict → object with keys sorted by UTF-16 code unit
- **Rationale**: the library is already a dependency of both ADK and xcross. The zone keeps stdout clean. Sorted keys
  and the fixed mappings make the output deterministic.
- **Alternatives**: write our own binary plist parser (rejected: more code for no gain). Use the `xml` package for XML
  only (rejected: the binary format is also needed).

## R4 — Mach-O reading

- **Decision**:
  - Accept thin `MH_MAGIC`/`MH_MAGIC_64` (`0xfeedface`/`0xfeedfacf`) and fat `FAT_MAGIC`/`FAT_MAGIC_64`
    (`0xcafebabe`/`0xcafebabf`), in both byte orders.
  - Map cputype/subtype to names: `arm64` (0x0100000c/0), `arm64e` (subtype 2), `armv7` (12/9), `armv7s` (12/11),
    `x86_64` (0x01000007), `i386` (7). Anything else → `cpu:<type>/<subtype>`.
  - Walk load commands only to find `LC_CODE_SIGNATURE` (0x1d) → `dataoff`/`datasize`.
  - Read the signature and entitlements from the first arm64-family slice (otherwise the first slice).
  - Bounds-check every read. A truncated or unknown file becomes issue `inspect.macho_invalid` instead of aborting.
- **Rationale**: covers the "fat (universal) binary" and "truncated Mach-O" edge cases. iOS slices of one binary carry
  equivalent signatures, so one slice is enough for v1.
- **Alternatives**: report the signature of every slice (rejected for v1: no AC needs it; it can be added later
  without breaking the schema).

## R5 — Signature kind and bundle-level `signature.present`

- **Decision**:
  - Per executable: no `LC_CODE_SIGNATURE` → `none`. Otherwise parse the SuperBlob (`0xfade0cc0`, big-endian). A
    blob-wrapper/CMS (`0xfade0b01`) at slot `0x10000` with a payload longer than its 8-byte header → `certificate`.
    Anything else → `adhoc`.
  - From the CodeDirectory (`0xfade0c02`, slot 0): `linkerSigned` = flag `0x20000` (`CS_LINKER_SIGNED`),
    `identifier`, and `teamId` (only CodeDirectory version ≥ `0x20200`). A malformed blob → issue
    `inspect.signature_invalid`, and the executable's kind becomes `adhoc` if `LC_CODE_SIGNATURE` exists.
  - Bundle-level `signature.present` is `true` exactly when `_CodeSignature/CodeResources` exists at the bundle root.
    `signature.kind` copies the main executable's kind, and `signature.teamId` its CodeDirectory team id.
- **Rationale**: xcross IPAs are always unsigned (only `run` signs, in place). But binaries inside them can still carry
  linker ad-hoc signatures (`X/.../adhoc_signature_refresher.dart` refreshes them), and `Flutter.framework` may arrive
  pre-signed. Using "the main executable has any signature" as the test would break AC-001-1. Sealed resources are
  what installation depends on.
- **Alternatives**: decide by CodeDirectory flag `CS_ADHOC` (0x2) alone (rejected: `codesign` and ADK write flags
  differently; the CMS payload is the reliable sign of a certificate signature).

## R6 — Embedded entitlements

- **Decision**: decode the XML entitlements blob `0xfade7171` (slot 5) with R3. If only the DER blob `0xfade7172`
  (slot 7) exists, set `derEntitlementsPresent: true`, `entitlements: null`, and add issue
  `inspect.entitlements_der_only`. Full DER entitlement decoding is deferred.
- **Rationale**: every signer we target (ADK `buildEntitlementsXml`, `codesign`, `rcodesign`, `ldid`, `zsign`) writes
  the XML blob. Smallest change that meets AC-001-2.
- **Alternatives**: decode DER entitlements too (deferred until a real input needs it).

## R7 — Provisioning profile (CMS)

- **Decision**: a small BER walker (`ber_reader.dart`):
  - supports definite and indefinite lengths (`0x80` … `00 00`), low tag numbers, and constructed OCTET STRING
    (chunks are concatenated)
  - path: ContentInfo(signedData `1.2.840.113549.1.7.2`) → `[0]` SignedData → encapContentInfo → `[0]` eContent →
    plist bytes
  - no signature or certificate verification
- **Profile kind**:

  | Condition | Kind |
  |---|---|
  | `ProvisionsAllDevices == true` | `enterprise` |
  | `ProvisionedDevices` present and `Entitlements.get-task-allow == true` | `development` |
  | `ProvisionedDevices` present otherwise | `ad-hoc` |
  | neither | `app-store` |

- **Rationale**: Apple profiles may use BER indefinite-length encoding, which ADK `DerReader` rejects. The inner plist
  is all FR-003 needs. Verifying the signature is out of scope (the command is read-only and offline).
- **Alternatives**: scan for `<?xml … </plist>` in the raw bytes (rejected: fails when the OCTET STRING is chunked).
  `pointycastle` ASN.1 parser (rejected: its BER indefinite-length support is uncertain; the walker is ~100 lines and
  fully tested).

## R8 — Redaction (FR-004, SC-004)

- **Decision**: output follows an allow-list.
  - **Info.plist values** are reported only for the bundle fields (`CFBundleIdentifier`, `CFBundleName`,
    `CFBundleDisplayName`, `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleExecutable`, `MinimumOSVersion`,
    `UIDeviceFamily`) and for `CFBundleIcons`, `CFBundleIcons~ipad`, `CFBundleIconName`, `CFBundleIconFile`,
    `UILaunchScreen`, `UILaunchStoryboardName` and `UIBackgroundModes`.
  - **Every other key** is listed by name only (`infoPlistKeys`). Values such as `GMSApiKey`, Firebase ids or API
    tokens therefore never appear.
  - **Profiles**: `deviceCount` and `certificateCount` only. No `ProvisionedDevices` values, no `DeveloperCertificates`
    bytes, names or serials, no `TeamName`, no `AppIDName`.
  - **The xcross private keys** (`XCrossEntitlements`, `XCrossCapabilities`, `XCrossAppGroups`) are reported as
    presence booleans.
- **Rationale**: a block-list cannot anticipate every secret key name; an allow-list can only under-report.
- **Alternatives**: report the full Info.plist with masking heuristics (rejected: unsafe for bug reports, US3).

## R9 — Determinism (FR-007, AC-001-5)

- **Decision**:
  - **Field order**: each object's fields appear in a fixed order (the model's `toJson` insertion order). Plist-derived
    dicts are sorted (R3).
  - **List order**: lists are sorted by POSIX relative path, then by name or code.
  - **Formatting**: 2-space indent, LF line endings, one trailing newline.
  - **ASCII only**: all non-ASCII characters are escaped as `\uXXXX`. `cli_kit` writes through `IOSink.write`, which
    uses the stdout encoding, and on Windows that is the ANSI code page when stdout is piped.
  - **No absolute paths**: the input is reported by basename only, and bundle paths are POSIX and relative
    (zip entry names with `\` are normalised to `/`).
  - **No values that depend on the current time** (for example, no `expired` flag).
- **Rationale**: identical bytes on every host and locale; no usernames from paths leak into bug reports.
- **Alternatives**: rely on UTF-8 stdout (rejected: Windows pipe encoding varies).

## R10 — Normalisation (FR-005, AC-001-6)

- **Decision**: `--normalize` (requires `--json`) sets:
  - `input.sizeBytes`, `input.sha256` and `resources.assetsCar.sizeBytes` (also in extensions) → `null`
  - `profile.uuid` → `"<uuid>"`
  - `profile.creationDate` and `profile.expirationDate` → `"<date>"`
  - top-level `normalized` → `true`

  Code-signature hashes (cdhash, page hashes) are never reported, so they need no normalising.
- **Rationale**: these are the only fields that differ between two builds of the same source (zip mtimes change the
  archive hash and size; regenerated profiles change uuid and dates).
- **Alternatives**: a separate normalisation tool for golden tests (rejected: CI and users need the same mode).

## R11 — Input streaming and memory

- **Decision**:
  - **`.ipa` input**: open with `InputFileStream(fileSystem.file(path).path)` and `ZipDecoder().decodeStream(...)`,
    which reads the central directory and inflates entries lazily. Inflate only the entries the report needs (plists,
    executables, profiles), one at a time, and release each entry's content after use. Peak memory ≈ the largest
    single executable entry.
  - **`.app` input**: list with `HostFileSystemInterface.directory(path).listSync(recursive: true, followLinks: false)`
    and read through `RandomAccessFile` ranges. A symlink becomes issue `inspect.symlink_skipped`.
  - **Bundle location**: exactly one `Payload/<X>.app/` prefix is required. Zero → `inspect.no_app`; more than one →
    `inspect.multiple_apps`.
- **Rationale**: meets "streamed; memory bounded" without a custom inflater. File access stays behind the injected
  host file system, as `repo_analyzer`'s `native_acquisition` rule requires.
- **Alternatives**: a range-capturing streaming inflate that keeps only the header and signature range (deferred: more
  complexity than v1 needs). Extract to a temporary directory (rejected: extra I/O and cleanup).

## R12 — Errors and exit codes (FR-008)

- **Decision**:
  - **Fatal problems** throw `InspectFailure(code, message, hint)`. The command catches it, writes the JSON error
    document to stdout in `--json` mode, then throws cli_kit `CliError('[<code>] <message>\nhint: <hint>')`.
    `formatFailure` (`runner.dart:242-254`) already prints known `CliError`s as `error: …` without a stack trace, and
    `XcrossCli.run` returns exit code 1.
  - **Usage errors** (no path, extra arguments, `--normalize` without `--json`) use `usageException` → exit 64.
  - **Partial problems** go to `issues[]` with exit 0.
- **Rationale**: no change to `formatFailure` or the runner beyond registration. Error codes stay stable in both modes.
- **Alternatives**: a new error type added to `formatFailure` (rejected: one more upstream seam for no benefit).
  Distinct exit codes per error (rejected: `XcrossCli.run` maps every throw to 1).

## R13 — Fixtures and golden tests (SC-003, Principle VI)

- **Decision**: CI cannot build real iOS apps, because the Apple SDK may not be hosted (Principle II).
  `test/support/fixture_builder.dart` therefore generates three synthetic bundles deterministically. Zips get fixed
  mtimes and sorted entries.
  1. **`unsigned_v209`** (`.ipa`), shaped like xcross v2.0.9 output: XML Info.plist with an empty `UILaunchScreen`
     dict, no `CFBundleIcons` and no `Assets.car`. Contents: unsigned thin arm64 `Runner`, `Frameworks/App.framework`,
     a CMS-signed `Frameworks/Flutter.framework` and a loose plugin `.dylib`.
  2. **`adhoc_push`** (`.app` directory): binary Info.plist, `_CodeSignature/CodeResources`, and an ad-hoc `Runner`
     with XML entitlements (`aps-environment: development`, `com.apple.developer.associated-domains`). Resources:
     loose icon PNGs with `CFBundleIcons`, and `UILaunchScreen.UIImageName` pointing at a loose PNG.
  3. **`profile_appex`** (`.ipa`): a certificate-signed fat `Runner` (arm64 + armv7) and `Assets.car`. Its BER
     indefinite-length `embedded.mobileprovision` is a development profile with planted fake UDIDs and an `Info.plist`
     with a planted `GMSApiKey`. `PlugIns/Share.appex` has its own entitlements and profile.

  The goldens are `test/goldens/<fixture>.json`: the raw `--json` output, which is stable because the fixture bytes
  are deterministic. This keeps User Story 1 independent of `--normalize`, which `normalize_test` (AC-001-6) covers
  separately. Regenerate them with `UPDATE_GOLDENS=1`. The
  opt-in test `STUDIO_INSPECT_IPA=<path>` and the quickstart check real IPAs. Goldens for real `fixtures/*` apps come
  once fixture apps exist.
- **Rationale**: transparent, reviewable fixtures with no opaque binaries and no Apple material. The same goldens
  passing on Windows, Linux and macOS CI proves AC-001-5.
- **Alternatives**: commit real IPAs (rejected: large, and they contain Apple-built binaries such as the Flutter
  engine plus possible client data).

## R14 — Human-readable output (AC-001-7)

- **Decision**: a header line (input name, bundle id, version and build, minimum OS) followed by ✔/✖ lines:

  | Line | ✔ when |
  |---|---|
  | signed | `signature.present` (shows the kind) |
  | provisioning profile | a profile exists (kind, team id, device count) |
  | push entitlement | the main executable carries `aps-environment` (✖ notes when only the profile grants it) |
  | associated domains | the main executable carries associated domains |
  | icon | an icon is declared and resolved |
  | launch screen | a launch screen resolves |
  | frameworks | always; shows the count |

  The last line is `<n> issues — run with --json for details`. Only `--json` output must be deterministic.
- **Rationale**: these are the questions answered by hand during the client app session (HANDOFF "Proven in a real
  project").
- **Alternatives**: ASCII `[x]` markers (rejected: the spec asks for ✔/✖; Dart writes Unicode correctly to modern
  Windows terminals).

## R15 — CI matrix (HANDOFF step 4)

- **Decision**: no matrix change is needed. `unit-tests.yml` already runs ubuntu-24.04, ubuntu-24.04-arm, macos-15,
  windows-2022 and windows-11-arm. The only CI change is adding `studio_ext` to the hardcoded package loops in
  `unit-tests.yml` (lines 66-77) and `release.yml` (lines 68, 224).
- **Rationale**: verified in the workflow files during planning.
- **Alternatives**: none.
