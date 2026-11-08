# Data Model (Planning Contract)

Conceptual additions/adaptations, not a new CLI wire schema. Reuse current Settings, Job, device and event classes.

| Entity | Fields / relationships | Validation and lifecycle |
|---|---|---|
| Workspace | canonical root ID, layout version, panes, console height, active file, mode/target, inspector context, font/theme | Root must exist and be Flutter; mutations cannot escape root through symlinks. Clamp restored dimensions; no build/sign-in on restore. |
| EditorDocument | canonical path, text, saved revision, dirty, encoding/line ending/indentation, cursor, diagnostics | Explicit read-only/missing states. Save before dirty clears; external revision mismatch requires resolution; close/switch offers save/discard/cancel. |
| Selection | file/project/device/configuration/artifact/plugin kind, entity ID | Inspector follows valid entity; stale selection becomes empty/unavailable. |
| BuildConfiguration | debug/profile/release, entrypoint, flavor, defines, target, signing reference, artifact/output | Validate paths and supported options; secrets are references, not serialized values. |
| CliCapabilities | executable identity/version, command/option support, event dialect, capture/inspect/watch/cancel/attach, evidence time | supported/unsupported/unknown; invalidate on binary/path change; enable only supported actions. |
| OperationSession | ID, project/config snapshot, process ID, stages, monotonic times, result/exit, attachment, diagnostics/artifacts | One conflicting build/run per workspace. idle → validating → starting → running → succeeded/failed/cancelled; stopping is nonterminal. Attachment unknown/detached/attached is independent. |
| DeviceReadiness | ID, label/iOS, USB/Wi-Fi, connected, pairing/developer mode/tunnel/DDI checks | Each check ready/blocked/unknown with reason/hint/time. Disconnect invalidates readiness/attachment. |
| PreviewState | target, disconnected/metadata/screenshot/demo/live, capture time/image, zoom/availability | Screenshot needs capture+timestamp; live needs stream; demo labeled; stale capture never implies current connection. |
| Artifact | operation, canonical path/type, identity/architecture/size, verification/inspection/warnings | File exists before reveal; partial output is not success; artifact success differs from publication. |
| Diagnostic / LogEntry | operation/source, time, severity, code/cause/hint, optional path/line, sanitized multiline text | Redact before retention. Missing code/location stays absent; unknown events are text, not success. |
| ShortcutBinding | action ID, default/current keys, scope, enabled reason | Detect collisions/reserved keys; same action guards as buttons/menu/palette. |

## Invariants

Requested cancellation is not completed cancellation. Success event plus failing exit exposes inconsistent evidence, not green success. A debug process may stay running/attached; exit is not needed to reflect launch. Progress percentage requires actual event data; durations are measured. Exit without final evidence reports verified process outcome and missing stages, never fabricated sign/install/attach success. Workspace switch explicitly preserves/stops/blocks an active job instead of redirecting its events to another root.

Persist safe preferences and stable references only. Corrupt/newer schema falls back safely with recovery. Existing bounds of 5,000 job lines and 20,000 device lines are reuse defaults, not new source performance requirements.

## Review clarification precedence

Apply [R1–R12](requirements-review.md) for exact conflict, selection, lifecycle, credential/clipboard and path-safety rules. Guarded credential Copy means identifiers only; raw passwords, tokens, 2FA and private-key bodies have no Copy action.
