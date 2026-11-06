# Research and Decisions

**2026-11-06 — local source/repository review only.** No package adoption, web research, process spike or device verification. Product scope comes only from the supplied design document.

| Decision | Evidence and rationale | Alternative considered |
|---|---|---|
| Extend composition | `apps/studio/lib/app/services.dart` owns host, launcher, settings, jobs, readiness, devices and project health. | A second service stack duplicates lifecycle. |
| Evolve shell/tokens | Existing `XAppShell`, console dock and token files are reuse seams; current screen navigation is not the requested IDE. | Wholesale renaming adds churn. |
| Reuse event parser | `src/cli/xcross_events.dart` supports v1/text fallback; `specs/012-build-events/contracts/events.schema.json` is local wire evidence. | Inventing fields from UI models creates false compatibility. |
| Negotiate capabilities | Local command builders do not establish installed-fork support. Probe version/help/options without mutations. | Version-only assumptions are insufficient. |
| Redact before retention | Command display masks separate password arguments; generalized ingestion redaction was not found. Existing job/device logs are bounded. | Widget-only redaction leaves retained/exported data exposed. |
| Verify Windows invocation | Launcher uses `runInShell` on Windows for shims. Argument arrays alone do not prove safety. | Declaring existing code safe without metacharacter tests. |
| Model attachment | Existing reload uses running debug job plus stdin; this is weaker than actual VM attachment. | Process-running state can wrongly enable reload. |
| Add real editor integration | No editor/language-service feature surfaced. Prove syntax, editing, IME, accessibility, semantic features and both hosts before dependency selection. | Styled text field cannot satisfy an IDE. |
| Separate previews | Icon/splash previews render designs, not iPhone capture/streaming. | Treating those images as live device output is misleading. |
| Preserve publication boundary | Existing publish screens are not evidence of successful uploads. | Expanding scope to a new uploader conflicts with source. |

## Design Interpretations

Default laptop auxiliary pane is inspector; remember later user choice. Combine section 9 width bands with section 3.1's 1180 compact rule, always preserving editor minimum. Section 7 bindings override illustrative log hints. Optional Git/live/advanced debugger stays deferred. Dark foundation precedes phase-5 light theme. Suggested Figma handoff becomes a local inventory.

## Implementation Investigation Gates

| Gate | Tasks | Required evidence | Safe unavailable outcome |
|---|---|---|---|
| Editor/tooling selection | T002, T017 | Candidate comparison, license/NOTICE impact, Windows/Linux editing+IME+semantic proof | Editor milestone stays incomplete; no claim a text field is a finished IDE |
| CLI dialect/support | T003, T006 | Selected binary/version/help, event fixtures and cancellation behavior | Disable unknown/unsupported actions with reason |
| Secrets/Windows shims | T004–T005 | Chunked/multiline secret tests, metacharacter paths/arguments | Do not connect unsafe invocation/log capture |
| Debug attachment | T026 | Verified attach/disconnect and reload/restart interaction | Disable unavailable actions |
| Capture/inspection | T032–T033 | Supported command, validated output, real-device evidence | Metadata preview / unavailable inspection explanation |

These are future engineering tasks, not completed experiments or unresolved product questions. No new numeric performance promise is inferred.

## T002 investigation resumed after requirements review

The 2026-11-06 checklist review passed; this is investigation evidence, not editor adoption.

| Candidate | Evidence / gap | Disposition |
|---|---|---|
| Flutter EditableText plus Dart analysis server | Existing Flutter dependency; selection, text input and undo hooks are documented. Requires a real syntax layer, gutters, editor focus behavior, large-file profiling and native IME/screen-reader verification. | Candidate for a bounded prototype; not selected for production |
| Bare styled TextField | Text entry alone supplies no semantic navigation, rename, references or compiler diagnostics. | Insufficient as a complete editor |
| Embedded browser editor | Would introduce a browser/runtime bridge and additional licensing/accessibility/native integration work; none verified in this environment. | Not adopted; no license or both-host claim |

Primary references: [Flutter EditableText](https://api.flutter.dev/flutter/widgets/EditableText-class.html), [Dart analysis server](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/README.md), [Dart LSP support](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md). These document building blocks, not application acceptance.

Local Windows spike used the installed Dart 3.13.0 SDK's native `dart.exe language-server --protocol=lsp` with JSON-RPC initialize/initialized/shutdown/exit and no project root. Initialize advertised completion (with resolve), formatting, definition, rename, references and incremental text synchronization. Shutdown exited 0. No document was opened and no semantic-action result, diagnostic correctness, UI performance, IME or screen-reader behavior was verified.

T002 remains open: production selection requires an editor prototype proving syntax/undo/redo/IME/keyboard/screen-reader/large-file behavior and semantic actions on native Windows and Linux. No new dependency was adopted; NOTICE is unchanged. The next engineering step is that prototype and host validation, not a product-scope decision. T017 cannot integrate a production editor until this evidence exists.
