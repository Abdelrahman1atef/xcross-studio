# Workspace and Integration Contracts

## CLI Boundary

### Selected PATH binary inventory (2026-11-06, Windows)

Read-only `--version` and `--help` probes resolved `C:\Users\man12\AppData\Local\xcross\bin\xcross.exe` as `xcross 2.0.9`. Top-level commands advertised are `auth`, `cache`, `completion`, `compose`, `config`, `flutter`, `ide`, `sdk`, `setup`, `tunnel`, and `update`. The GUI's `devices`, `install`, `release`, `sign`, `logs`, and `inspect` top-level commands are absent from this help. This binary is an unsupported dialect for those actions. Its event modes, cancellation, capture, inspection, and attachment support remain unknown; no mutating command was run. Source-checkout CLI behavior is a separate target and must be probed before enabling it.

Windows dispatch now resolves only `.exe` candidates from PATH and rejects explicit `.bat`/`.cmd` invocations; the process is launched without `runInShell`. This addresses the shell parsing risk documented by [Dart Process.run](https://api.dart.dev/dart-io/Process/run.html), which notes that Windows batch files may run through a shell even with `runInShell: false`. The current tests cover resolution and explicit shim rejection; metacharacter process-level cases are still pending.

1. Query selected executable version/help/options without build, sign-in or project scripts. Cache against identity; unknown is not supported.
2. Use validated argument arrays and existing invocation/builders. Validate working directory. Windows native/shim paths require metacharacter tests before wiring user inputs.
3. Select supported dialect: existing `--json` and `XCROSS_EVENTS=ndjson` only where established. Do not append flags universally from examples. Reuse v1 wire schema; conceptual models add no wire fields.
4. Decode stdout/stderr incrementally; sanitize structured fields/text including split/multiline credentials before retention/display. Troubleshooting raw logs mean sanitized raw text. Copy/export/command preview share this boundary.
5. Unknown/malformed/new-version events become sanitized text/diagnostics, never stage advancement. Preserve multiline text. Supported step/progress/log/warning/error/artifact/device/check/done events drive their actual semantics.
6. Process state and VM attachment are separate. Reload/restart requires supported interaction and attached session. Stop shows requested/stopping/completed; unsupported cancellation explains its limitation.
7. Verify artifact existence before reveal/inspect. Runtime codes/hints are authoritative; local fallback errors do not impersonate backend codes.

## Files / Language

Discover actual contents, canonicalize paths and prevent unintended writes outside root. Reveal/copy-path are explicit. Delete confirms; unsupported mutations are disabled. Save returns actionable failure or success, clearing dirty only on success. External revision changes require resolution.

Language requests identify document/revision; stale replies cannot replace current diagnostics. Required semantic actions: completion, formatting, definitions, rename, references and diagnostics. Server failure preserves text and offers recovery. Breakpoints need a verified debug backend; a gutter is not evidence. Open Terminal is explicit and never auto-runs scripts.

## UI

Menu/button/palette/shortcut route to one guarded action. Apply source section 7 defaults and display current mapping. Editor typing must not cause unintended reload. Chrome is native, never fake macOS.

Source dimensions: window 1600×900/min1100×700; toolbar52/min48; navigator280/min190; inspector300/min240; preview350/min260; console210/min120; status25/min24; editor min360. Include dividers/hit targets/scaled text in fit. At1360–1599 default navigator/editor/inspector; at1180–1359 allow an auxiliary pane only if it fits; below1180 default navigator/editor. Clamp persisted layouts.

Inspector uses source4.4 contexts/fields; unsupported edits look read-only. Console has five primary tabs plus gated Crashes/Push. Omit unavailable status metadata. Preview zoom is independent of text scale; disconnected/metadata/timestamped screenshot/demo labels differ; live needs real verified streaming.

## Security and Failures

No raw password storage, telemetry or secret-bearing bug reports. Preserve source5.1 Apple ID/2FA/nonstandard-sign-in/anisette notices. Mask credentials, guard deliberate reveal/copy and always sanitize logs/exports. Credential persistence belongs to OS/CLI protected stores. Unknown checks stay unknown. Each failure has a reason and useful next action where possible; validate issue paths before opening.

## Review clarification precedence

Apply [R1–R12](../requirements-review.md) for exact conflict, selection, lifecycle, credential/clipboard and path-safety rules. Guarded credential Copy means identifiers only; raw passwords, tokens, 2FA and private-key bodies have no Copy action.
