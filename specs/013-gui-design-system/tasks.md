# Tasks: XCross Studio design system

G = `apps/studio`.

- [X] T001 Fonts: Inter 4.1 + JetBrains Mono 2.304 (official releases, SHA-256 in plan.md) with OFL licences in
  `G/assets/fonts/`; registered in `pubspec.yaml`.
- [X] T002 `G/lib/design_system/tokens/` (colours §3.1, type §3.3, spacing/radii §3.4, motion §3.5) and
  `theme/x_theme.dart` (dark default, derived light).
- [X] T003 Components (§8): `XButton`, `XIconButton`, `XStatusBadge`, `XCard`, `XCheckRow`, `XCallout`,
  `XDeviceCard`, `XToolchainCard`, `XBuildStepper`, `XProgressIndicator`, `XDiagnosticCard`, `XConsole`,
  `XCommandPreview`, `XCredentialField`, `XTextField`, `XEmptyState`, `XConfirmDialog`, `XFilePickerField`,
  `XSidebarItem`.
- [X] T004 Layouts: `XAppShell`, `XConsoleDock`, `WorkspaceLayout`.
- [X] T005 State: `ReadinessController`, `DeviceController`; `Settings` (wizard, theme, console, Xcode.xip);
  command builders (`setup`, `sdk install`, `--version`, `update --check`, `ide`, `tunnel`, `--anisette-url`).
- [X] T006 `G/lib/app/`: services, app controller, shell (top bar, sidebar, dock, status bar, shortcuts), quick
  commands.
- [X] T007 Screens: Overview, Build & Run, Devices, Signing, Logs & Debug, Plugins, Settings; wizard (§7).
- [X] T008 Tests: `app_test.dart`, `components_test.dart`, `build_events_test.dart` (AC-012-8 on the new
  components), opt-in `screenshot_test.dart`.
- [X] T009 `flutter analyze`, `flutter test`, `flutter build windows --release`; smoke run.
- [X] T010 Docs: CHANGELOG, ROADMAP, README, getting-started guide, the 008 device-check remap, runbook §5.
- [ ] T011 Device check on the iPhone X (rows in `device-check.md`); a screen-reader pass; Linux visual check.
