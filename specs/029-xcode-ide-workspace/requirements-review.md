# Requirements review resolution — 2026-11-06

This normative clarification supplements spec.md and the design source under the user's explicit review request. It approves requirement quality only. Runtime acceptance, task completion and release approval remain separate. The CLI stays authoritative; no new publishing, signing or device backend is introduced.

## R1 — Workspace geometry (CHK001)

The five work regions are navigator, editor, preview, inspector and console. The global toolbar and status strip are additional persistent chrome. All dimensions in source sections 2, 3 and 9 are logical pixels except the physical divider. Native titlebar space is excluded from content fitting. Retain the source defaults/minima: window 1600×900/1100×700; toolbar 52/48; navigator 280/190; inspector 300/240; preview 350/260; console 210/120; status 25/24; editor width at least 360.

At ≥1600 show all columns if they fit; 1360–1599 defaults to navigator/editor/inspector with a preview/inspector switch; 1180–1359 permits one auxiliary pane only if all minima and dividers fit; below 1180 defaults to navigator/editor. Shrink resizable panes to minima, then collapse preview, inspector and navigator in that order, except retain the user's chosen auxiliary pane over the other. Never shrink the editor below 360. Hidden panes remain accessible through toolbar and keyboard actions. Console spans the entire workbench width. Scaled controls may grow beyond default heights; overflow controls stay keyboard reachable. If OS constraints force a smaller window, hide auxiliary panes and provide scrolling rather than clipped inaccessible controls. Restore preferences clamped to current screen and scale, without operations.

## R2 — Components and gallery (CHK002)

All 22 source component roles remain required. Action controls implement default/hover/focus/pressed/disabled/busy/error where meaningful; disabled actions expose a reason, busy actions prevent duplicate dispatch, and errors preserve entered values. Selection and dirty state are independent of focus. Read-only rows expose selectable text but no editable styling. Split handles expose keyboard resize, current value and bounds. Noninteractive text and containers need no artificial pressed/busy state. Tooltips are supplementary to accessible names.

The eight states in design-handoff.md must each define visible selection, device/readiness, operation state, available actions and error/recovery text: empty workspace; project/disconnected; ready device; active build; successful artifact; failed build; unsupported plugin; masked API-key setup. Every gallery scenario is labeled Demo and uses isolated fixture state; it cannot dispatch real commands or contain real credentials. Production empty and error states must not fall back to demo results.

## R3 — Editor and filesystem decisions (CHK003)

Closing a dirty file, closing the app or switching roots offers Save / Discard / Cancel per dirty document, including a reviewable Save All option. Cancel aborts the transition; a failed save preserves buffer, dirty flag and current root. Successful writes alone clear dirty state. Preserve encoding/line endings; unsupported decoding opens read-only with an explanation rather than silently replacing bytes. Undo/redo remain document-local across tab switches. Language edits carry document revision, validate every changed path and apply only against matching revisions; multi-file rename previews affected files and requires explicit apply.

On external edits: clean buffers may reload while preserving a clamped cursor; dirty buffers retain local text and offer Compare, Reload disk (explicitly discards local changes), or Overwrite after confirmation of the displayed disk revision. A second disk change invalidates that confirmation. Missing/deleted files retain dirty buffers and offer Save As within the root or close; read-only files disable Save and explain the cause. Renames update canonical document identity only after filesystem success. No silent overwrite, recreation or discard.

Workspace switch during an active operation offers Stay or Stop and switch. Switching waits for confirmed process termination; failure/unsupported stop keeps the current root and explains recovery. Operation events remain bound to their original workspace/session. Restore never restarts a job. Semantic actions require actual Dart tooling; unavailable or stale replies cannot overwrite edits. Unsupported breakpoint/terminal actions explain why they are disabled.

## R4 — Inspector and configuration (CHK004)

All source 4.4 fields must be represented; unknown values show Unavailable with a reason, not fabricated defaults. Loading, empty selection, stale selection, read-only, editing, invalid and backend failure states are distinct. A stale device/artifact/plugin selection disables mutations until refreshed.

| Context | Read-only fields | Supported edits and validation |
|---|---|---|
| Dart file | Identity/type, canonical path | Encoding, line endings and indentation only through a supported lossless editor conversion; preview changes, preserve dirty buffer on failure |
| Project | Discovered targets | Bundle ID, version/build number, entrypoint/flavor through verified project commands; validate CLI constraints, existing in-root entrypoint, discovered flavor/target |
| Device | Name, iOS, transport, pairing, tunnel, Developer Mode | No fabricated property editing; explicit supported Pair/Tunnel/Diagnose actions with readiness guards |
| Build configuration | Backend-derived capability restrictions | Mode, defines, artifact type, signing reference, output; reject unsupported options, missing signing references and invalid paths; secret defines use protected references and sanitized previews |
| IPA artifact | Identity, signed bundle ID, architecture, size, warnings | No metadata editing; verified Inspect/Reveal only |
| Plugin | Version, SwiftPM support, override state, diagnostics | Supported override/regenerate actions only; show affected paths and backup/overwrite consequences |

Invalid values show field-local explanation and disable Apply/Run; failed backend edits retain the attempted values and previous confirmed state. No widget reimplements CLI build/signing logic.

## R5 — Session and device truth (CHK005)

Process lifecycle and VM attachment are independent. Starting/running is never proof of launch or attach. Stop transitions to stopping and becomes cancelled only after termination evidence; failed stop remains actionable. A done/exit disagreement is failure with both values shown. Missing done may establish process exit only, never unreported stages. Each pairing, Developer Mode, tunnel, DDI and transport check is ready/blocked/unknown with observation time and reason. Disconnect invalidates readiness and attachment immediately; reconnect requires fresh checks. Reload/restart require verified support and current attached-session evidence. One conflicting run per workspace; repeat Run cannot start another process.

## R6 — Credential and output boundary (CHK006)

Sanitize stdout and stderr before callbacks, event models, retained state, UI, search indexes, diagnostics, previews, clipboard or exports. This includes unknown/malformed/new-version events, exception strings, argument echoes, stdin/2FA, Apple credentials, tokens and multiline PEM/.p8 content. Incremental decoding must handle secrets split across byte chunks, UTF-8 boundaries and lines. Sanitization must preserve usable event structure; secret values must not become stage or artifact evidence. If a payload cannot safely be sanitized, suppress it with a reason rather than retaining raw bytes for troubleshooting. No raw fallback log, crash attachment or telemetry.

Use synthetic sentinels to verify every sink, including paused device logs and callback consumers. Keep transient credential input only as long as needed; clear controllers/references after submission, cancellation and disposal. Do not claim guaranteed memory erasure in managed Dart. Avoid putting raw secrets in process arguments when supported stdin/protected-file input exists; unsupported safe secret transport disables that credential submission path with a fix.

## R7 — Credential UI and clipboard (CHK007)

Persist only opaque references to OS credential storage or CLI-protected files. Unavailable protected storage disables Remember; no plaintext fallback. Preserve source Apple ID/nonstandard sign-in, secondary-account, 2FA and anisette trust notices before submission, and keep API-key authentication within existing CLI scope.

XSecureField is masked by default and after blur, navigation or app deactivation. Reveal is an explicit temporary action; accessibility labels never contain the hidden value. Passwords, 2FA codes, tokens and private-key bodies have no raw Copy action. Guarded Copy for credential identifiers (issuer/key ID) is explicitly labeled; confirmation names the field, never its value. Console, diagnostic and command Copy/Export always uses sanitized content. Ordinary source-file copying remains a normal editor operation. If an existing authentication flow requires raw secret copying, it stays disabled until separately specified and verified; clipboard expiry cannot guarantee removal from OS history or other applications. Do not erase unrelated clipboard contents.

## R8 — Preview and capabilities (CHK008)

Capabilities are supported/unsupported/unknown per executable identity, command, option and interaction; invalidate on changed executable/path/version or probe failure. Version alone is insufficient. Probes are bounded read-only help/version operations, never auth/build/project scripts. Unknown support disables the affected operation with a reason and recheck action. Existing verified CLI actions retain their behavior.

Screenshots retain target identity and capture time. Disconnect, target switch, refresh failure or older capture completion marks the image stale; label it Last screenshot with its time and stale reason. Discard replies from superseded target/request IDs. Metadata is the fallback when capture is unsupported; a still image is never Live. Demo stays explicitly labeled. Artifact success requires existing output from the recorded operation; partial output is labeled incomplete. Existing publication routes remain separate and show success only from their uploader evidence.

## R9 — Paths, processes and destructive actions (CHK009)

Canonicalize the workspace and resolve symlink/junction targets before file access. Reject traversal, absolute paths outside root and link escapes for create/write/rename/delete/search/source jumps; external dependencies may be explicitly opened read-only. Revalidate parent and revision immediately before mutation; reject if identity changes. Save with replacement semantics that preserve the original on failure. Reveal/inspect only verified files associated with a known operation or explicit user selection; do not pass untrusted log paths to an opener.

Pass executable and arguments separately, never concatenate a shell command. Resolve the actual executable and validate working directory; test spaces, Unicode, quotes, ampersands, pipes, percent expansion and newlines on both hosts. Unsupported shim/argument combinations fail before dispatch with a supported-binary remediation. Command preview is informational, not an executable shell script. Preserve existing CLI command behavior through verified adapters, not unsafe shell fallback.

Delete, overwrite, credential removal and destructive regeneration require a dialog naming the target, affected scope and permanence/backup behavior. Cancel is the default; nothing runs before explicit confirmation. Dirty file deletion also resolves its buffer via R3. Revalidate targets after confirmation; a changed target requires fresh confirmation. No silent recursion outside the selected root and no automatic project script execution. Errors expose actual cause and safe next action without sensitive values.

## R10 — Accessible workflows (CHK010)

Test opening a project, tree/search, edit/save/conflict, inspector editing, configuration/Run/Stop, device recovery, authentication, artifact inspection, console copy/export and settings using keyboard only. Tab/Shift+Tab traverse controls in visual order; tree arrows and Enter work; pane focus shortcuts restore last valid control; Escape closes transient UI and restores its invoker. Dialogs contain focus while open and return it on close. Editor Tab behavior must have a documented keyboard escape to pane navigation. No hidden/collapsed pane retains focus.

All source section 7 bindings share action guards with menus/buttons/palette; remapping identifies conflicts before save, reserved OS keys are rejected with a reason, and reset restores defaults. Accessible names describe role/state, dirty/read-only status and blocking reason; diagnostics and operation changes are announced without continuously reading log streams or secrets. Test 100/150/200% text scaling in the viewport matrix, both themes and reduced motion. Require text contrast ≥4.5:1 for ordinary text and ≥3:1 for large text, with ≥3:1 distinguishability for focus and control boundaries; adjust semantic tokens where the proposed palette fails. Status includes text/icon as well as color. Native Windows screen-reader and Linux screen-reader checks remain separate evidence gates.

## R11 — Acceptance traceability (CHK011)

The 12 rows of test-plan.md Acceptance Coverage map AC-029-1 through AC-029-12 to automated test paths, implementation tasks and identified device-check.md rows. These are planned proofs, except explicitly dated execution records. R1–R10 cases are added to the test plan and existing tasks, not counted as new acceptance IDs. A subset of passing redaction tests does not approve AC-029-7 or the full feature. Manual rows require host/device/version/procedure/expected/actual/evidence; unavailable hardware remains pending.

## R12 — Scope and release gates (CHK012)

All five phases, real file editing, required semantic actions, accessibility and light theme are required for complete source acceptance. Git, optional minimap, live streaming and advanced debugger remain optional; their honest absence does not waive required semantic editor behavior. Screenshot/inspection controls require actual selected-binary support; otherwise the specified metadata/unavailable behavior is required. T002 editor/license/IME/native-host investigation, T003/T006 CLI negotiation, T004/T005 security evidence, attachment/capture proof and T040 both-host checks remain engineering gates. Missing evidence does not create an unresolved product decision and must not be marked passed. No release/merge until constitution gates and applicable device evidence are satisfied.
