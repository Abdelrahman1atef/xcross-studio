# Tasks: `xcross sign`

X = `packages/xcross/lib/src`, S = `packages/studio_ext/lib`.

- [X] T001 `X/target/iphone/device/device_backend.dart`: `NativeBackend.sign(…)` and `_signBundle` (install =
  sign + install); device ids as a list through provisioning and the offline cache check (`// studio: 011`).
- [X] T002 `X/composition/cli/app_bundle_input.dart`: input preparation moved out of `InstallCommand`; binary
  Info.plists to XML (`forSigning`); `setBundleId`; `looksEncrypted`.
- [X] T003 `InstallCommand`: `--[no-]resign`; runner installs as signed when `--no-resign`.
- [X] T004 `S/shared/ipa/ipa_writer.dart` (deterministic zip, Unix modes and made-by) and
  `S/shared/inspect/signed_bundle_check.dart` (inspector check and summary).
- [X] T005 `X/composition/cli/sign_command.dart` + runner registration; `sign.*` codes in `xcross_diagnostics.dart`.
- [X] T006 Tests: `sign_command_test.dart`, `install_command_test.dart` (AC-011-6), `signed_ipa_test.dart`,
  diagnostics prefix.
- [X] T007 GUI: "Sign only (.ipa)" button, `XcrossCommands.sign`, test.
- [X] T008 Docs: CHANGELOG, README row, ROADMAP, 002 diagnostics contract, runbook row, `device-check.md`; analyze;
  tests; commit; push.
