# XCross Studio — Xcode-Inspired IDE Design System

> **Status:** Proposed product/design specification · **Version:** 2.0 · **Updated:** 2026-11-06  
> **Platform:** Windows and Linux desktop · **Implementation:** Flutter  
> **Visual direction:** Xcode-inspired IDE layout and interaction model, adapted for the XCross CLI and Flutter workflows.

**Product statement:** **Build for iOS. Anywhere.**

**Reference mockup:** `a_detailed_macos_xcode_like_ide_ui_mockup_for_xcr.png` (concept illustration; the device preview, progress and results are illustrative, not verified live behavior).

---

## 1. Product vision

Turn XCross Studio from a collection of CLI wrappers into a cohesive **Flutter-focused iOS development IDE**. Developers should be able to open projects, inspect Dart source, configure builds and signing, manage iPhones, run/debug apps, and understand build issues in one workspace.

### Goals

1. Preserve Xcode's recognizable **navigator → editor → inspector → debug console** information hierarchy without copying Apple proprietary assets.
2. Make the most common action obvious: **select target → Run**.
3. Keep technical detail available through logs, diagnostic codes and copyable XCross commands.
4. Display truthful build and device states, with explicit recovery steps.
5. Work comfortably by keyboard and mouse on Windows/Linux.
6. Separate **implemented capabilities** from proposed IDE functionality and simulated/mock preview UI.

### Non-goals for initial release

- Recreating the whole Xcode build system or macOS native window chrome.
- Claiming that a static device preview is a live iOS simulator.
- Promising App Store Connect uploads merely because the CLI can produce an IPA; distribution/upload needs its own separately implemented and verified feature.
- Executing arbitrary project-supplied scripts silently.

---

## 2. Visual language

**Keywords:** precise, compact, native-feeling, calm, technical, low-glare, focused.

**Design inspiration:** Xcode's four-pane workbench, inspector patterns, and blue selection emphasis. Implement original assets, icons, controls and tokens, rather than reproducing Apple's UI pixel-for-pixel.

**Primary theme:** dark. Include an accessible light theme later, based on semantic tokens rather than ad hoc per-widget colors.

### 2.1 Dark color palette

| Token | Hex | Usage |
|---|---|---|
| `color.canvas` | `#111318` | Outer workspace background |
| `color.toolbar` | `#202329` | Main top toolbar |
| `color.navigator` | `#1B1D23` | Project navigator |
| `color.editor` | `#17191F` | Source editor background |
| `color.inspector` | `#202228` | Properties inspector |
| `color.console` | `#111318` | Debug/build console |
| `color.surface` | `#262931` | Menus, popovers, segmented controls |
| `color.surfaceHover` | `#30343D` | Hovered items |
| `color.divider` | `#343840` | Panel separators, borders |
| `color.selection` | `#1B4E8E` | Selected file/tab/row |
| `color.accent` | `#0A84FF` | Primary action, link, active state |
| `color.accentHover` | `#369AFF` | Hovered primary action |
| `color.text` | `#EBEDF2` | Primary text |
| `color.textSecondary` | `#ACB1BB` | Descriptions, labels |
| `color.textMuted` | `#808794` | Placeholder, inactive metadata |
| `color.success` | `#32D77B` | Build ready/succeeded |
| `color.warning` | `#FFB340` | Issues needing attention |
| `color.error` | `#FF5E5B` | Build failed, critical problems |
| `color.info` | `#65B3FF` | Informational state |
| `color.focus` | `#80BEFF` | Keyboard focus ring |

**Rules:** Use the accent for selection and primary interactions, not large decorative backgrounds. Never communicate state by color alone: pair colors with text and meaningful icons. Maintain accessible contrast for small type, especially in code and console output.

### 2.2 Syntax highlighting

| Code token | Suggested color |
|---|---|
| Keywords (`class`, `const`, `return`) | `#D7A1F9` |
| Types (`Widget`, `BuildContext`) | `#7AC7F8` |
| Strings | `#F5AB87` |
| Functions | `#8BD9D0` |
| Numbers | `#C9C0FF` |
| Comments | `#81909A` |
| Errors/diagnostics | `#FF7775` |

Use a syntax highlighting engine for Dart, not regular expressions alone, if accurate parsing is required. Colors are a **design proposal**, subject to editor/theme contrast review.

### 2.3 Typography

| Use | Family | Size | Weight |
|---|---|---:|---|
| Main toolbar | Inter / Segoe UI | 13–14 px | 500–600 |
| Panel headings | Inter / Segoe UI | 12–13 px | 600 |
| Tree rows / body | Inter / Segoe UI | 12–13 px | 400–500 |
| Inspector labels | Inter / Segoe UI | 12 px | 400 |
| Editor | JetBrains Mono / system mono | 13–14 px | 400 |
| Console | JetBrains Mono / system mono | 12–13 px | 400 |
| Status metadata | Inter / Segoe UI | 11–12 px | 400–500 |

Use locally bundled fonts only when properly licensed; otherwise use system fallbacks. Do **not** depend on Apple's San Francisco font being redistributable for a Windows/Linux app.

### 2.4 Geometry and spacing

- Spacing scale: `4 / 8 / 12 / 16 / 24 / 32` px.
- Icon sizes: `16` px compact, `18` px standard, `20` px toolbar.
- Toolbar control height: `28–32` px; primary Run button touch/click target at least `36` px.
- Tree row height: `25–28` px.
- Standard input height: `30–32` px.
- Panel and popover corners: `6–10` px; editors and primary panes can remain square-edged.
- Divider: `1` physical pixel where possible; use a draggable split handle with a larger invisible hit target.
- Motion: `120–180` ms for panel/tab transitions; reduced-motion setting disables nonessential animation.

---

## 3. IDE window architecture

The five work regions are **navigator, editor, device preview, inspector and console**. The global toolbar and status strip are additional persistent chrome.

```text
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ TOP TOOLBAR  Project ▾   ▶ Run  ■ Stop   Target: iPhone ▾   Build status    Search  Settings │
├───────────────────┬─────────────────────────────────────────┬──────────────────┬────────────┤
│ PROJECT NAVIGATOR │ CODE EDITOR                             │ DEVICE PREVIEW   │ INSPECTOR  │
│                   │ main.dart  app.dart                      │                  │            │
│ project tree      │ syntax / diagnostics / breakpoints      │ iPhone screen    │ file /     │
│ folders/files     │                                         │ or build target  │ build /    │
│ search/issues     │                                         │ details          │ device     │
│ dependencies      │                                         │                  │ properties │
├───────────────────┴─────────────────────────────────────────┴──────────────────┴────────────┤
│ CONSOLE DRAWER   All Output | Issues | Build Log | Flutter | Device                         │
│ [time]  ✓ Build succeeded · installed on device · VM Service connected                     │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ STATUS STRIP  Git branch · Flutter SDK · xcross version · build mode · connection · diagnostics│
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Default desktop dimensions

| Region | Default | Min | Behavior |
|---|---:|---:|---|
| Window | 1600 × 900 px | 1100 × 700 px | Resizable; persist window bounds |
| Top toolbar | 52 px high | 48 px | Always visible |
| Navigator | 280 px wide | 190 px | Resizable; can hide |
| Inspector | 300 px wide | 240 px | Resizable; can hide |
| Device preview | 350 px wide | 260 px | Toggleable; can dock beside editor |
| Bottom console | 210 px high | 120 px | Resizable; can collapse |
| Status strip | 25 px high | 24 px | Always visible |
| Editor | Flexible | 360 px wide | Receives remaining space |

**Small-window adaptation:** At widths below ~1360 px, collapse either the preview or inspector by default. Below ~1180 px, default to navigator + editor, with preview and inspector available through toggle controls. Never force all four columns into unusably narrow widths.

**Platform chrome:** Windows uses Windows window controls; Linux uses the current desktop's window integration. The reference image's macOS titlebar/menu bar is aesthetic inspiration only. A Windows/Linux implementation must not render fake Apple system controls.

### 3.2 Global toolbar

From left to right:

1. **Workspace selector:** project name and recent projects.
2. **Run button:** runs current configuration; disabled when prerequisites fail, with reason.
3. **Stop button:** stops the active launch/build when cancellation is supported.
4. **Scheme/config selector:** Debug / Profile / Release, Flutter flavor and entrypoint.
5. **Device selector:** detected USB/Wi-Fi iPhones and connection status.
6. **Activity/status area:** truthful build state, progress, duration, warnings.
7. **Search/command palette**, panel toggles, settings and account access.

Do not hardcode mock values like "Build Succeeded | 2.4s"; duration must be measured from actual events.

---

## 4. Pane specifications

### 4.1 Left pane — Project Navigator

**Purpose:** Quickly locate and work with project files.

**Sections / modes:** Files, Search, Issues, Git (future), Dependencies, XCross tools.

**Elements:**
- Hierarchical file tree with expansion arrows, icon, filename, selected-row background, optional status decoration.
- `lib/`, `ios/`, `android/`, `assets/`, `test/`, `pubspec.yaml`, and any other folders **as actually discovered**; never assume a fixed project structure.
- Right-click actions: Open, Reveal in Explorer/File Manager, Copy Relative Path, Rename (when enabled), New File, Delete with confirmation.
- Filter field (`Ctrl+P` opens quick-file search; `Ctrl+Shift+F` searches workspace content).
- Git changes and external-file updates when backed by working integrations.
- Empty states: *Open a Flutter project to begin*, *No matching files*.

**States:** normal, hovered, selected, modified, read-only, file missing, compile-error indicator.

### 4.2 Center pane — Source Editor

**Purpose:** Read and edit Dart code; surface diagnostics and launch context.

**Visual specification:**
- Tabs (`main.dart`, `app.dart`) with close controls and unsaved-dot indicators.
- Breadcrumb line (`XCrossApp > lib > main.dart`).
- Line-number gutter, breakpoint gutter, matching-brace highlighting, selection highlight.
- Softly highlighted current line; indentation guides; configurable word wrap and tab width.
- Inline errors and optional minimap (off by default on laptop widths).

**Editing capabilities to implement/verify separately:** file open/save, undo/redo, search/replace, auto-indent, code completion, go-to-definition, formatting, diagnostics, breakpoints. Flutter/Dart language-server integration is required for robust semantic behaviors; a styled text field is **not** a complete IDE.

**Editor menu actions:** Save, Format Document, Go to Definition, Rename Symbol, Find References, Toggle Breakpoint, Open Terminal, Reveal File.

### 4.3 Center-right pane — iPhone Preview

**Purpose:** Keep the selected target/device and app result visible while coding.

**Header:** `Preview (iPhone • Device name)` plus controls for zoom, screenshot refresh, view mode, and maximize.

**Modes:**

| Mode | User-facing label | Truthful behavior |
|---|---|---|
| No device | `No iPhone connected` | Shows connection steps, no simulated live device |
| Ready | `Device connected` | Device metadata and launch action |
| Screenshot | `Latest device screenshot` | An explicitly timestamped captured image; refresh requires supported device capture |
| Live view (future) | `Live device view` | Only shown after a real streaming implementation exists |
| Concept/demo | `Demo preview` | Clearly marked static sample for onboarding/design review |

A physical iPhone + XCross's device launch protocol does **not automatically mean** a live embedded iOS simulator or device-mirroring stream exists. The mockup's iPhone screen should be treated as a sample concept until preview capture or streaming is implemented and tested.

**Device frame:** optional subtle frame with rounded screen rectangle; avoid wasting too much editor area. Keep preview zoom separate from application text scale.

### 4.4 Right pane — Context Inspector

**Purpose:** Show the settings that apply to the current selection.

Inspector selection drives content:

| Context | Inspector sections |
|---|---|
| Dart file | Identity & Type, Path, Encoding, Line Endings, Indentation |
| Flutter project | Bundle ID, Version, Build Number, Entry Point, Flavor, Targets |
| iPhone | Name, iOS version, Connection (USB/Wi-Fi), Pairing, Tunnel, Developer Mode status |
| Build configuration | Mode, Defines, Artifact Type, Signing Profile, Output |
| IPA artifact | App identity, signed bundle ID, architecture, size, inspection warnings |
| Plugin | Version, SwiftPM support, override status, error details |

**Rules:** Use section headings, labeled form rows, disclosure sections, copyable values and tooltips. Only show controls the backend can support; read-only properties must look read-only.

### 4.5 Bottom pane — Debug and Build Console

**Tabs:** `All Output`, `Issues`, `Build Log`, `Flutter`, `Device`, with optional `Crashes` and `Push` when those CLI extensions are available.

- Time-stamped rows with severity icon and text.
- Monospaced output; preserve multiline formatting.
- Search field, severity filter, autoscroll toggle, Copy, Export, Clear.
- Clicking an issue opens the relevant file/line if a source location is available.
- Structured progress shows stages as they are emitted; don't invent percentages.
- Sensitive values (tokens, Apple credentials, `.p8` contents, private keys) **must be redacted before display/export**.

**Example, illustrative only:**

```text
18:21:03  INFO     Resolving Flutter project…
18:21:04  SUCCESS  Flutter engine artifacts available
18:21:08  SUCCESS  SwiftPM plugins built
18:21:10  INFO     Signing com.example.app for selected device
18:21:12  SUCCESS  Installed on iPhone
18:21:13  SUCCESS  Flutter VM Service connected
18:21:13  HINT     Hot reload: R  |  Hot restart: Shift+R
```

CLI output and keyboard shortcuts shown here are proposed UX labels; verify actual command interaction before wiring actions.

### 4.6 Status strip

Show, only when available: source-control branch, current Flutter SDK, selected xcross executable and version, build mode, connection type, issue count, line/column, encoding. Status items can open context menus or detail views.

---

## 5. Primary workflows

### 5.1 First-run onboarding

1. **Welcome:** Open project or Set up XCross.
2. **Prerequisites:** Detect Flutter, Swift, LLVM, Python, `pymobiledevice3`, Windows Build Tools where relevant.
3. **SDK:** Select `Xcode.xip`, preview requirements, run `xcross sdk install`, verify compatibility with installed Swift.
4. **Authentication:** Apple ID or App Store Connect API key; explain trust boundaries, 2FA, and third-party anisette usage.
5. **Device:** USB or supported Wi-Fi pairing; Developer Mode, tunnel and Developer Disk Image.
6. **Project:** Open Flutter root and run `xcross flutter doctor`.
7. **Ready:** Show Run action and a copyable CLI command.

**Security notice:** Project documentation warns that Apple ID sign-in uses a nonstandard path and may risk account lockout; recommend a secondary account and explain public anisette-server privacy concerns. Never store raw passwords. For production automation, API keys can be preferable if appropriate and authorized.

### 5.2 Debug run

```text
Choose project → Validate SDK & device → Choose Debug + target
→ Run → Compile → Sign → Install → Launch → Attach VM Service
→ Edit code → Hot Reload / Hot Restart → Stop
```

**UI requirements:** One visible action per stage, live step state, actionable errors, accessible stop/cancel. The Run control reflects actual CLI/session state.

### 5.3 Release / IPA

```text
Choose Release → Validate bundle ID, version, signing & dependencies
→ xcross flutter build --release [artifact options if supported]
→ Verify output → Inspect IPA → Reveal artifact in file manager
```

Do not conflate **building an IPA** with **uploading it to TestFlight/App Store Connect**. Add a separate publishing workflow only when a tested uploader/backend is implemented and Apple requirements are satisfied.

### 5.4 Device connectivity

- Show USB and Wi-Fi connection types distinctly.
- Surface trust pairing, Developer Mode, tunnel readiness and DDI mounting as separate checks.
- Use `xcross tunnel` / `xcross tunnel --wifi` where supported.
- For reconnect issues show exact actionable diagnostics, not a generic "Device error".
- No clickable `Run` against a device in an unsupported iOS state without a clear explanation.

---

## 6. Component library

Use `X` prefix for shared widgets. All interactive elements need default, hover, focused, pressed, disabled, busy and error variants as applicable.

| Widget | Variants / purpose |
|---|---|
| `XAppShell` | Full IDE shell and persisted split-pane state |
| `XToolbar` | Global project, Run/Stop, target and status controls |
| `XIconButton` | 28/32/36 px compact actions with tooltips |
| `XButton` | Primary, secondary, destructive, quiet, busy |
| `XSegmentedControl` | Debug / Profile / Release; dock modes |
| `XDropdown` | Project, flavor, device and file setting selection |
| `XProjectTree` | Virtualized/scrollable tree, keyboard navigation |
| `XEditorTab` | Active/inactive/dirty/closable file tabs |
| `XEditorBreadcrumb` | Selected file hierarchy |
| `XInspectorSection` | Collapsible property groups |
| `XPropertyRow` | Label, editable/read-only value, validation |
| `XDeviceCard` | Device, iOS, USB/Wi-Fi, readiness |
| `XDevicePreview` | Placeholder, screenshot, explicit live mode |
| `XStatusChip` | Succeeded, active, warning, failed, disconnected |
| `XBuildTimeline` | Structured stages, current step, duration |
| `XConsole` | Virtualized log, filtering, search and redaction |
| `XIssueRow` | Diagnostic code, severity, hint, source jump |
| `XEmptyState` | Illustration/icon, clear action, optional docs |
| `XCommandPreview` | Copy CLI command, show arguments and path |
| `XSplitPane` | Draggable/resizable with min dimensions |
| `XCommandPalette` | Keyboard-first search across actions and files |
| `XSecureField` | Masked credentials; guarded reveal/copy |

### 6.1 Status content guidelines

| State | Icon | Text example |
|---|---|---|
| Ready | Check circle | `Environment ready` |
| Working | Spinner | `Signing application…` |
| Warning | Alert triangle | `Swift SDK version mismatch` |
| Failed | X circle | `Build failed: plugin unsupported` |
| Disconnected | Plug off | `iPhone disconnected` |
| Completed | Check circle | `Build succeeded` |

Use text, shape and consistent placement as well as color. A status chip must never be the only place the developer sees why an action is blocked.

---

## 7. Keyboard navigation

| Shortcut (Windows/Linux) | Behavior |
|---|---|
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+P` | Quick-open file |
| `Ctrl+S` | Save current file |
| `Ctrl+Shift+F` | Workspace search |
| `Ctrl+B` | Toggle navigator |
| `Ctrl+J` | Toggle console |
| `Ctrl+Alt+I` | Toggle inspector |
| `F5` | Run/debug selected target when safe |
| `Shift+F5` | Stop current session |
| `Ctrl+Shift+R` | Hot reload when attached |
| `Ctrl+Alt+R` | Hot restart when attached |
| `Alt+1 / Alt+2 / Alt+3` | Focus navigator / editor / inspector |

These are **proposed Studio shortcuts**, not claims about existing XCross CLI or IDE bindings. Respect OS-reserved shortcuts, support user customization and show current mappings in menus.

---

## 8. Application screens and navigation

The IDE shell is the default workspace. Administrative tasks can be dockable tools or secondary screens rather than replacing the editor:

- **Workspace** — Editor, navigator, preview, inspector and console.
- **Welcome** — Recent projects, create/open project, onboarding status.
- **Build configurations** — Mode, Dart defines, entrypoints, flavors, signing and artifacts.
- **Devices** — Pair, tunnel, view state, install and diagnostics.
- **Signing & Accounts** — Apple ID, API key, certificate/profile status with security notices.
- **Plugins** — SwiftPM support and plugin overrides, with honest compatibility warnings.
- **Artifacts** — Successful `.app`/`.ipa` outputs and metadata inspection where supported.
- **Settings** — Appearance, editor, shortcut map, toolchain paths, Flutter SDK, xcross executable.

### Error-state design

For each failed operation show:

```text
Title: Unable to build iOS application
Code: toolchain.path_linker_unusable
Cause: The selected LLVM linker cannot be executed.
Fix: Check the configured LLVM path, then rerun Environment Check.
Actions: [Open Settings] [Copy Diagnostic] [View Logs]
```

Error codes above are examples based on the provided XCross Studio command documentation. Read actual codes and hints from runtime output when available.

---

## 9. Responsive behavior and persistence

**Large screens (≥1600 px):** navigator, editor, device preview, inspector and console can all be open.

**Standard laptops (1360–1599 px):** start with navigator + editor + either preview or inspector. A segmented control switches the last pane.

**Compact windows (1100–1359 px):** prioritize editor; navigator is collapsible, inspector and preview become toggleable sidebars.

**Persist per workspace:** split widths, hidden/open panes, console height, active file, selected mode/target, inspector context, editor font size and theme. Restore safe settings on restart without auto-executing builds or sign-in flows.

**Accessibility:** semantic labels, full keyboard focus order, focus-ring visibility, scalable text, reduced-motion support, contrast verification and screen-reader-readable diagnostic messages. Avoid focus traps between panes and modal dialogs.

---

## 10. CLI and platform integration

The XCross CLI remains the authoritative backend for builds, signing, installation and device operations. The IDE is responsible for orchestration and presentation, not reimplementing signing protocols inside widgets.

### 10.1 Example command mappings

| Studio action | CLI command (illustrative) |
|---|---|
| Environment check | `xcross flutter doctor` |
| Prepare SDK | `xcross sdk install <Xcode.xip>` |
| Authenticate Apple ID | `xcross auth --apple-id <email>` |
| Authenticate API key | `xcross auth --issuer-id <id> --key-id <id> --private-key <path>` |
| Start USB tunnel | `xcross tunnel` |
| Start Wi-Fi tunnel | `xcross tunnel --wifi` |
| Debug/run | `xcross flutter run` |
| Run via Wi-Fi | `xcross flutter run --wifi` |
| Release build | `xcross flutter build --release` |
| Inspect output | `xcross inspect <artifact>` *if supported by selected CLI/fork* |
| Prepare IDE tools | `xcross ide vscode` *for external VS Code configuration* |

The supplied project description includes some `<!-- studio: -->` fork-only commands. Detect availability **by querying the installed CLI** and hide or disable missing operations. Do not assume all users run the same fork/version.

### 10.2 Structured output

The provided XCross Studio description proposes `XCROSS_EVENTS=ndjson` with event types such as `step`, `progress`, `log`, `warning`, `error`, `artifact`, `device`, `check` and `done`. **If supported by the selected binary**, parse them into strongly typed domain objects, render stage progress, and preserve raw logs for troubleshooting.

Recommended layers:

```text
Flutter UI (design system, panes, controller state)
       ↓
Feature state / ViewModels
       ↓
Application services (projects, builds, devices, auth, logs)
       ↓
CLI adapter (argument validation, process lifecycle, NDJSON parser)
       ↓
Installed xcross executable + Flutter/Dart language tooling
```

**Process safety:** Use safe argument arrays rather than shell string concatenation; do not dump credentials to logs; confirm destructive operations; validate project roots and artifact paths; show what is being executed and why.

---

## 11. Proposed Flutter source structure

```text
lib/
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── workspace_controller.dart
├── design_system/
│   ├── tokens/
│   │   ├── x_colors.dart
│   │   ├── x_spacing.dart
│   │   ├── x_typography.dart
│   │   ├── x_dimensions.dart
│   │   └── x_radii.dart
│   ├── theme/
│   │   ├── x_dark_theme.dart
│   │   └── x_light_theme.dart
│   ├── components/
│   │   ├── x_button.dart
│   │   ├── x_status_chip.dart
│   │   ├── x_build_timeline.dart
│   │   ├── x_project_tree.dart
│   │   ├── x_console.dart
│   │   ├── x_inspector_section.dart
│   │   └── x_split_pane.dart
│   └── layouts/
│       ├── x_app_shell.dart
│       └── x_ide_workspace.dart
├── features/
│   ├── welcome/
│   ├── projects/
│   ├── editor/
│   ├── build_run/
│   ├── devices/
│   ├── signing/
│   ├── preview/
│   ├── artifacts/
│   ├── plugins/
│   ├── diagnostics/
│   └── settings/
├── services/
│   ├── xcross_cli.dart
│   ├── process_runner.dart
│   ├── cli_event_parser.dart
│   ├── project_file_service.dart
│   └── secret_redactor.dart
└── main.dart
```

### Example token implementation

```dart
import 'package:flutter/material.dart';

abstract final class XColors {
  static const canvas = Color(0xFF111318);
  static const toolbar = Color(0xFF202329);
  static const navigator = Color(0xFF1B1D23);
  static const editor = Color(0xFF17191F);
  static const inspector = Color(0xFF202228);
  static const surface = Color(0xFF262931);
  static const divider = Color(0xFF343840);
  static const selection = Color(0xFF1B4E8E);
  static const accent = Color(0xFF0A84FF);
  static const text = Color(0xFFEBEDF2);
  static const textSecondary = Color(0xFFACB1BB);
  static const success = Color(0xFF32D77B);
  static const warning = Color(0xFFFFB340);
  static const error = Color(0xFFFF5E5B);
}

abstract final class XDimensions {
  static const toolbarHeight = 52.0;
  static const navigatorDefaultWidth = 280.0;
  static const inspectorDefaultWidth = 300.0;
  static const previewDefaultWidth = 350.0;
  static const consoleDefaultHeight = 210.0;
  static const statusBarHeight = 25.0;
}
```

---

## 12. Recommended build phases

### Phase 1 — Design-system foundation

- [ ] Finalize dark tokens, typography, icon language and spacing.
- [ ] Implement theme and core components with interaction states.
- [ ] Build `XAppShell`, toolbar, resizable panes, tabs and persistence.
- [ ] Create a component gallery using demo data, clearly labeled as demo.

### Phase 2 — Real workspace

- [ ] Open existing Flutter project and show actual file tree.
- [ ] Read/edit/save Dart files with unsaved changes handling.
- [ ] Implement real file tabs, breadcrumbs, search and inspector.
- [ ] Integrate Dart analysis tooling for diagnostics and language features.

### Phase 3 — XCross operations

- [ ] Detect installed xcross version and supported commands.
- [ ] Run `xcross flutter doctor` and show fixable prerequisites.
- [ ] Select device, debug/release configuration and build target.
- [ ] Start/stop CLI processes safely; stream and filter logs.
- [ ] Parse structured events when available; connect to timeline/artifacts.

### Phase 4 — Device, signing and preview

- [ ] Add guarded Apple ID/API key setup with strong security messaging.
- [ ] Device pairing and tunnel workflow, including actionable diagnostics.
- [ ] Artifact browser and inspection where supported.
- [ ] Implement screenshot preview if supported; no false live-preview claim.

### Phase 5 — Polished IDE

- [ ] Contextual actions, command palette, customizable shortcuts.
- [ ] Accessibility review and window-size stress testing.
- [ ] Theme variants, performance and process recovery.
- [ ] Optional advanced debugger/real preview only after backend verification.

---

## 13. Acceptance criteria

The design can be considered correctly implemented when:

1. The default screen presents a clear Xcode-inspired navigator/editor/preview/inspector/console layout.
2. Panels resize and collapse without clipping the editor or hiding its core controls.
3. Project tree and editor are backed by real project files, not hardcoded demo files.
4. Build Run/Stop and status reflect real backend operations.
5. Unknown device/build/signing states are shown as unknown—not green success.
6. Preview mode communicates whether it is a static demo, screenshot or genuine live feed.
7. The app does not display, log or export raw Apple credentials or `.p8` contents.
8. CLI command compatibility is detected and unsupported fork-only features are gated.
9. Every failure shows a reason and at least one useful next step where possible.
10. Keyboard-only navigation, focus and screen reader paths work in major panes.
11. Layout works on common Windows/Linux screens without fake macOS window controls.
12. The app never describes IPA creation as App Store/TestFlight publication unless a real upload flow succeeds.

---

## 14. Suggested design handoff

Create a Figma component library with pages for **Tokens**, **Components**, **Shell**, **Editor**, **Devices**, **Signing**, **Console**, **Onboarding**, **Error States**, and **Responsive Layouts**. Name component variants consistently with their Flutter counterpart (`XButton/Primary/Hover`, `XStatusChip/Warning`, etc.).

Useful mockup states to create:

- Empty workspace, no project.
- Flutter project open, code visible, device disconnected.
- iPhone connected and environment ready.
- Build in progress with real-progress presentation.
- Build succeeded with artifact/action panel.
- Build failed with a specific diagnostic and repair action.
- Plugin unsupported or missing SwiftPM support.
- API-key authentication selected with masked credentials.

**Final direction:** **Xcode's spatial clarity, Flutter's cross-platform tooling, and XCross's transparent CLI power**, all in an original Windows/Linux desktop UI.

## 15. Requirements review clarifications

The [029 requirements review](../specs/029-xcode-ide-workspace/requirements-review.md) specifies fit/collapse precedence, editor conflict decisions, inspector edit rules, session evidence, credential and clipboard handling, safe filesystem/process dispatch, and measurable accessibility checks. These clarify this design under the requested requirements review; they do not assert implementation or release completion.
