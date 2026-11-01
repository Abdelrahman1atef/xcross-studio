# XCross Studio — Design System

**Working name:** XCross Forge  
**Product:** XCross Studio (Windows & Linux)  
**Platform:** Flutter desktop  
**Version:** 1.0 (proposed)  
**Status:** Design proposal — not an implementation or a claim about the current app

---

## 1. Vision

XCross Studio should feel like a purpose-built developer workspace for building, signing, installing, and debugging Flutter iOS applications from Windows or Linux.

**Product promise:** *Build for iOS. Anywhere.*

Design goals:

- Make complex iOS setup understandable without hiding technical detail.
- Keep the project, build state, device status, and relevant logs visible.
- Provide clear, actionable errors and repair paths.
- Support mouse, keyboard, and screen-reader navigation.
- Make the underlying CLI transparent and copyable.
- Work well on small laptop screens as well as large desktop monitors.

**Personality:** precise, calm, capable, technical, and trustworthy. Avoid unnecessary gradients, glossy effects, or overdone motion.

## 2. Design principles

1. **Developer-first.** Show meaningful technical details, not vague progress indicators.
2. **Clarity over decoration.** Use spacing, contrast, and hierarchy to establish priorities.
3. **One primary action per context.** Each workflow should have one obvious next step.
4. **Status is always visible.** Running, ready, warning, failed, and disconnected states must not rely on color alone.
5. **Errors should be fixable.** Include the diagnostic code, what happened, and a concrete remedy.
6. **Progress is honest.** Use determinate percentages only when real progress is measurable.
7. **Power-user friendly.** Support keyboard shortcuts, command previews, and copyable diagnostics.
8. **Secure by default.** Never show passwords, private keys, tokens, or provisioning secrets in logs.

## 3. Brand and visual direction

**Visual references:** a combination of the clean workspace organization of VS Code, the restrained look of Linear, and the operational feedback of CI/CD dashboards.

**Logo direction (concept):** an `X` built from crossing paths or two chevrons, suggesting cross-platform compilation and delivery. Keep a recognizable monochrome variant.

### 3.1 Color tokens — dark theme (default)

| Token | Hex | Usage |
|---|---|---|
| `color.canvas` | `#0B1020` | Main application background |
| `color.surface` | `#141B2D` | Sidebars, panels, cards |
| `color.surfaceElevated` | `#1D2840` | Inputs, menus, elevated panels |
| `color.border` | `#2F3D56` | Dividers, controls, panel edges |
| `color.primary` | `#4F8CFF` | Primary actions, selections, links |
| `color.primaryHover` | `#76A6FF` | Hover/focus emphasis where appropriate |
| `color.success` | `#36C89B` | Successful checks, completed steps |
| `color.warning` | `#F4B860` | Recoverable issues, cautions |
| `color.error` | `#F27676` | Build failures, destructive operations |
| `color.textPrimary` | `#F2F6FF` | Main titles and content |
| `color.textSecondary` | `#A6B5CA` | Supportive copy and metadata |
| `color.textMuted` | `#8593AA` | Low-emphasis informational labels |
| `color.console` | `#090E19` | Console and log surface |

These are *initial proposed tokens*. Validate accessible contrast between every text/background pairing before shipping. Do not use muted colors for critical content without testing.

### 3.2 Semantic color usage

- **Primary blue:** selected navigation, the main button, active build steps.
- **Green:** completed step, verified toolchain, connected device.
- **Amber:** outdated SDK, missing optional capability, setup attention needed.
- **Red:** failed build, untrusted credential status, destructive action.
- **Neutral gray:** idle, unavailable, not yet checked.

Use accompanying labels or icons: e.g., `✓ Ready`, `! Needs attention`, `× Failed`, `○ Not checked`.

### 3.3 Typography

| Style | Font | Recommended starting point |
|---|---|---|
| App / screen title | Inter Semibold | 24 px / 32 px |
| Section title | Inter Semibold | 18 px / 26 px |
| Card title | Inter Medium | 15 px / 22 px |
| Body | Inter Regular | 14 px / 21 px |
| Supporting text | Inter Regular | 12–13 px / 18 px |
| Code / logs | JetBrains Mono | 12–13 px / 19 px |

Allow UI scaling and avoid fixed-height text containers that clip large-font content. Fall back to system fonts when necessary.

### 3.4 Spacing, shape, and elevation

Use an **8 px base grid** with 4 px half steps.

| Token | Value | Typical use |
|---|---:|---|
| `space.1` | 4 px | Tight icon/text gap |
| `space.2` | 8 px | Compact controls |
| `space.3` | 12 px | Internal card elements |
| `space.4` | 16 px | Standard card padding |
| `space.6` | 24 px | Major section spacing |
| `space.8` | 32 px | Wide content separation |
| `radius.sm` | 6 px | Tags / small controls |
| `radius.md` | 10 px | Inputs / buttons |
| `radius.lg` | 12 px | Cards / panels |
| `radius.xl` | 16 px | Large dialogs |

Prefer subtle borders and surface changes to heavy shadows. Keep row targets approximately 40–44 px tall for primary interactive controls.

### 3.5 Motion

- Hover / focus feedback: about 120–160 ms.
- Panel expansion / dialogs: about 160–220 ms.
- No gratuitous loading animation during builds; a spinner is appropriate only for indeterminate activity.
- Respect reduced-motion preferences.

## 4. Information architecture

The primary navigation has seven destinations:

| Area | Purpose | Key capabilities |
|---|---|---|
| **Overview** | Workspace and project readiness | Recent builds, project status, quick actions, diagnostics |
| **Build & Run** | Primary development workflow | Debug/profile/release, flavors, build output, hot reload |
| **Devices** | Physical iPhone management | USB/Wi-Fi pairing, tunnels, app installation, device state |
| **Signing** | Signing and provisioning | Apple ID, API keys, profiles, bundle identity, entitlements |
| **Logs & Debug** | Investigation and monitoring | Console, search, presets, crash reports, diagnostics |
| **Plugins** | Native plugin compatibility | SwiftPM status, overrides, shim generation |
| **Settings** | Tooling and personalization | SDK/toolchain paths, config, updates, IDE integration |

**First-run Setup** is a guided workflow accessible from Overview and Settings rather than a permanent top-level tab.

## 5. Application shell

### 5.1 Desktop layout

```text
┌──────────────────────────────────────────────────────────────────┐
│ XCross Studio   Project: my_flutter_app      iPhone: Connected  │
├───────────────┬──────────────────────────────────────────────────┤
│ Overview      │ Screen title                    Quick actions   │
│ Build & Run   │                                                  │
│ Devices       │ Main content / cards / workflow                  │
│ Signing       │                                                  │
│ Logs & Debug  │                                                  │
│ Plugins       ├──────────────────────────────────────────────────┤
│ Settings      │ Optional docked console / build output          │
├───────────────┴──────────────────────────────────────────────────┤
│ Toolchain ✓    Signing ✓    Device ✓             CLI / status  │
└──────────────────────────────────────────────────────────────────┘
```

- **Top bar:** active project, device selector, alerts, quick command access.
- **Sidebar:** primary navigation with clear selection state.
- **Main workspace:** page-specific controls and content.
- **Console dock:** resizable, collapsible, persistent when useful.
- **Status bar:** readiness indicators, running tasks, XCross version.

### 5.2 Adaptive layout

- **Wide windows:** full sidebar, two-column content where useful, side-by-side inspector.
- **Medium windows:** compact sidebar, narrower cards, console still dockable.
- **Narrow windows:** icon rail or drawer, single-column content, console as resizable bottom pane.
- Preserve the main action and build status as space becomes constrained.
- Do not hide error descriptions solely because a window is narrow.

## 6. Core screen specifications

### 6.1 Overview

**Goal:** answer “Am I ready to build, and what should I do next?”

Sections:

- Current Flutter project (name, path, selected entrypoint, flavor if any).
- Readiness cards: Flutter, Swift, LLVM, Darwin SDK, authentication, device.
- Connected device summary.
- Last build status and output location.
- Recommended action: **Open Project**, **Fix Setup**, or **Build & Run**.
- Recent builds list, when available.

When no project is selected, show an explanatory empty state and **Open Flutter Project** as the primary action.

### 6.2 Build & Run

**Goal:** build, sign, install, and launch while making every step understandable.

Controls:

- Flutter project / entrypoint.
- Build mode: Debug, Profile, Release.
- Device selector and transport (USB/Wi-Fi).
- Optional build name/number, flavor, Dart defines, IPA packaging.
- Primary **Build & Run** action; separate **Build IPA** action when appropriate.
- Inspectable generated CLI command before execution.

**Pipeline display:**

1. Validate project and toolchain.
2. Resolve Flutter engine artifacts.
3. Compile Dart and native dependencies.
4. Assemble `.app` / `.ipa`.
5. Sign application.
6. Install and launch (when running on device).
7. Attach VM Service and debugging (for debug runs).

Only display actual stages reported by the active command. Profile/release and build-only workflows will differ from debug-and-run.

**Running debug controls:** Hot Reload (`r`), Hot Restart (`R`), Stop; preserve current connection and process status.

**Finish state:** clearly show the artifact path, copy/open-folder actions, timing if reported, and install options.

### 6.3 Devices

**Goal:** diagnose and manage real iPhone connectivity.

- Device card: friendly name, iOS version, transport, pairing state, UDID with optional copy.
- **Prepare USB Tunnel** / **Prepare Wi-Fi Tunnel** actions as applicable.
- Connection progress: trusted pairing → developer services → DDI → RSD tunnel.
- Installed apps and app details where supported.
- Install existing `.ipa`, inspect capabilities, and open crash/log views.
- Warnings for Developer Mode, USB trust, firewall/mDNS, unsupported OS, or missing elevation.

**Important UX:** avoid equating “device discovered” with “ready to run.” Show each readiness requirement explicitly.

### 6.4 Signing

**Goal:** authenticate securely and make signing failures understandable.

- Choice between **Apple ID** and **App Store Connect API key**.
- Explain that the API key is the preferable documented credential for supported workflows and CI.
- Apple ID flow: explain non-standard login mechanism, account lock risk, 2FA, secondary-account recommendation, and anisette service trust implications.
- API key fields: Issuer ID, Key ID, private key file picker.
- Show **authenticated / expiring / expired / not configured** states.
- Bundle ID strategy: original vs prefixed, including capability trade-offs.
- App Group status where relevant.
- **Sign Out / Clear Credentials** destructive action with confirmation.

Never print or persist credential secrets in visible logs. Obscure sensitive values and redact them from copied diagnostics.

### 6.5 Logs & Debug

**Goal:** make failures searchable and actionable.

- Live console with timestamps and command/source labels.
- Presets: All, Flutter, Build, Signing, Push, Crash (where supported).
- Severity filters; search text; pause autoscroll; save sanitized logs.
- Copy diagnostics with secrets and personal identifiers redacted.
- Expand a diagnostic card to reveal stable code, explanation, and suggested fix.
- Link a log entry to the corresponding build step.
- Open crash reports and app info where available.

**Console states:** following live output, paused, disconnected, ended, and failed.

### 6.6 Plugins

**Goal:** surface native iOS plugin compatibility before builds fail.

- Installed Flutter plugins and detected integration mode.
- `SwiftPM supported` / `podspec only` / `override active` / `unknown` badges.
- Explain limitations of podspec-only plugins.
- Generate a `Package.swift` shim draft and show review-required warnings.
- Open and validate local overrides without silently modifying pub cache.

### 6.7 Settings

- Toolchain paths: Flutter, Swift, LLVM, Darwin SDK, Java/Kotlin where applicable.
- Configuration readout and validation result.
- XCross CLI version and update channel.
- IDE integrations: VS Code and JetBrains.
- Theme preference, console appearance, keyboard shortcut reference.
- Diagnostics export and data/credential handling information.

## 7. First-run onboarding wizard

The setup wizard has five stages:

| Step | Title | Main action | Definition of success |
|---|---|---|---|
| 1 | Environment | Check / install prerequisites | Required host tools are available |
| 2 | Darwin SDK | Select `Xcode.xip`; install SDK | SDK usable with selected Swift toolchain |
| 3 | Authentication | Configure Apple ID or API key | Authentication/signing readiness confirmed |
| 4 | Device | Pair and prepare tunnel | Device connection ready for desired operation |
| 5 | First build | Open project and run | App built; optionally installed and launched |

Provide **Retry**, **Show Details**, and **Copy Command** at each stage. Allow the user to revisit completed stages. Explicitly distinguish required items from optional features.

## 8. Components inventory

| Flutter component | Variants / states | Responsibility |
|---|---|---|
| `XButton` | Primary, secondary, text, danger; idle/loading/disabled | Standard actions |
| `XIconButton` | Neutral, destructive, selected | Compact toolbar actions |
| `XStatusBadge` | Ready, running, warning, failed, idle | Accessible status communication |
| `XCard` | Basic, elevated, interactive | Content grouping |
| `XDeviceCard` | Connected, unavailable, pairing, error | Device identity and readiness |
| `XToolchainCard` | Valid, missing, mismatched, checking | Prerequisite health |
| `XBuildStepper` | Waiting, active, passed, failed, skipped | Build lifecycle |
| `XProgressIndicator` | Determinate, indeterminate | Honest task progress |
| `XDiagnosticCard` | Info, warning, error | Actionable error and hint |
| `XConsole` | Live, paused, complete, failed | Logs and diagnostics |
| `XCommandPreview` | Collapsed / expanded | Visible CLI mapping and copy |
| `XCredentialField` | Empty, obscured, invalid, verified | Secure auth input |
| `XEmptyState` | No project, no device, no logs, etc. | Helpful zero states |
| `XConfirmDialog` | Standard, destructive | Confirmation of impactful actions |
| `XFilePickerField` | Empty, selected, invalid | Paths and artifact selection |
| `XSidebarItem` | Default, hovered, selected, disabled | Navigation |

### 8.1 Button standards

- Use **one primary button** per action region.
- A destructive button must be unmistakable and include confirmation for irreversible operations.
- A loading button remains labeled with the active operation (e.g., “Signing…”).
- Disabling a button should be accompanied by an explanation when the reason is not obvious.

### 8.2 Diagnostic card example

```text
✕ Swift toolchain mismatch

The Darwin SDK was prepared for a different Swift toolchain.
Code: toolchain.swift_sdk_mismatch  [example; map to an actual emitted code]

Suggested fix:
Reinstall the Darwin SDK using the currently selected Swift version.

[Copy command]   [Open settings]   [View logs]
```

Diagnostic codes must be taken from actual CLI output. Do not fabricate codes in the production UI.

## 9. Interaction and accessibility guidelines

- Support complete keyboard operation, logical tab order, and visible focus rings.
- Expose labels, roles, state, and progress through Flutter semantics.
- Keep error descriptions readable; don't depend on hue alone.
- Ensure dialogs return focus to the invoking control.
- Allow console text selection and copying.
- Clearly label shortcuts. Initial proposals: `Ctrl+,` Settings; `Ctrl+K` quick commands; `Ctrl+L` focus logs. Avoid conflicts with existing OS / IDE conventions.
- Preserve user-entered config when navigation changes or errors occur.
- Use semantic actions and explanatory empty states rather than disabled unexplained controls.

## 10. Operational states

Define consistent UI states for every asynchronous workflow:

| State | Visual / copy | Available actions |
|---|---|---|
| Idle | “Ready to build” | Start, configure |
| Validating | “Checking prerequisites…” | View details, cancel if supported |
| Running | Current named step and live output | Open logs, cancel if supported |
| Completed | Clear result and artifact path | Open artifact, run again |
| Warning | Specific issue and consequence | Inspect, fix, continue only when safe |
| Failed | Error + code + remedy | Retry, copy diagnostics |
| Disconnected | Device/tunnel lost | Reconnect, inspect connection |

Build and signing operations may be non-cancelable at certain stages; only expose a Cancel action when cancellation is genuinely supported.

## 11. CLI-to-GUI command mapping

| GUI action | CLI mapping |
|---|---|
| Check Flutter readiness | `xcross flutter doctor` |
| Install prerequisites | `xcross setup` |
| Install Darwin SDK | `xcross sdk install <Xcode.xip>` |
| Sign in with Apple ID | `xcross auth --apple-id <email>` |
| Configure API key | `xcross auth --issuer-id <uuid> --key-id <id> --private-key <path>` |
| Prepare USB device | `xcross tunnel` |
| Prepare Wi-Fi device | `xcross tunnel --wifi` |
| Run Flutter app | `xcross flutter run` |
| Produce release artifact | `xcross flutter build --release` |
| Configure VS Code | `xcross ide vscode` |
| Configure JetBrains | `xcross ide idea` |
| Check updates | `xcross update --check` |
| Inspect an app / IPA | `xcross inspect <ipa-or-app>` (Studio fork) |
| View devices | `xcross devices --json` (Studio fork) |

**Implementation note:** The pasted project description includes some XCross Studio fork-specific commands. Detect the installed CLI's actual capabilities/version and hide or explain unsupported actions rather than assuming all commands exist.

## 12. Security and trust requirements

- Explain Apple ID risk before authentication; prominently encourage a secondary Apple ID for non-standard login flows.
- Disclose that public anisette servers are third parties and may see connection metadata and attestation-related traffic.
- Prefer self-hosted anisette where practical, and let users inspect the configured URL.
- Keep API keys in secure OS-backed storage where feasible; avoid writing plaintext secrets to project configuration.
- Redact tokens, passwords, certificates, signing keys, personal device identifiers, and sensitive paths from diagnostics shared externally.
- Ask before running remote setup scripts; display origin, checksum, and intended changes.
- Clearly distinguish verified toolchain health from merely detected executables.

## 13. Suggested Flutter codebase structure

```text
lib/
├── app/
│   ├── app.dart
│   └── router.dart
├── design_system/
│   ├── tokens/
│   │   ├── colors.dart
│   │   ├── typography.dart
│   │   ├── spacing.dart
│   │   └── radii.dart
│   ├── theme/
│   │   ├── dark_theme.dart
│   │   └── light_theme.dart
│   ├── components/
│   │   ├── x_button.dart
│   │   ├── x_status_badge.dart
│   │   ├── x_device_card.dart
│   │   ├── x_build_stepper.dart
│   │   ├── x_diagnostic_card.dart
│   │   ├── x_command_preview.dart
│   │   └── x_console.dart
│   └── layouts/
│       ├── app_shell.dart
│       └── workspace_layout.dart
└── features/
    ├── onboarding/
    ├── overview/
    ├── build/
    ├── devices/
    ├── signing/
    ├── logs/
    ├── plugins/
    └── settings/
```

Keep **design-system components independent of CLI/subprocess operations**. Feature controllers should translate CLI events to semantic UI state, which components render.

## 14. Suggested implementation phases

### Phase 1 — Foundations

- Establish color, typography, spacing, theme, and accessibility tokens.
- Build the app shell, navigation, dialogs, and common components.
- Implement responsive/dockable console layout.

### Phase 2 — Primary experience

- Implement onboarding and prerequisite health checks.
- Build Overview and Build & Run with transparent CLI command mapping.
- Handle progress, success, failure, cancellation, and diagnostic details.

### Phase 3 — Device and signing experience

- Add USB/Wi-Fi device workflows and tunnel readiness states.
- Add secure authentication screens and provisioning status.
- Connect artifact installation and app details.

### Phase 4 — Advanced developer tools

- Add structured logs, crash reports, plugin compatibility tools, IDE integration, update paths, and refined keyboard shortcuts.
- Validate accessibility, small-window behavior, and recovery from disconnected devices.

## 15. Success criteria

The design is successful when a developer can:

- See within seconds whether the machine is ready for an iOS build.
- Diagnose exactly which prerequisite is missing and what fixes it.
- Open a Flutter project and run on a connected iPhone without memorizing commands.
- Find the build artifact, logs, and relevant errors immediately.
- Understand the security implications of the selected Apple authentication method.
- Use the GUI without losing access to the powerful XCross CLI.

---

**Recommended starting point:** establish the design tokens and app shell, then build the onboarding wizard and Build & Run workflow. These create the reusable patterns needed for the remaining screens.
