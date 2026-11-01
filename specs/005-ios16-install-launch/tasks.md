# Tasks: iOS 16 install and launch, and `xcross install`

X = `packages/xcross/lib/src`, XT = `packages/xcross/test`. Every edited upstream hunk is marked `// studio: 005`.

## Phase 1: Foundational

- [X] T001 `X/target/iphone/device/ddi_locator.dart`: `DdiLocator(fileSystem, paths, {environment, home})` with
  `({String image, String signature})? find(String osVersion, {String? explicitDir})`. The search order is FR-003; an
  image needs `DeveloperDiskImage.dmg` plus `DeveloperDiskImage.dmg.signature`. Tests: `XT/device/ddi_locator_test.dart`.
- [X] T002 `X/target/iphone/device/legacy_device_launcher.dart`: `LegacyDeviceLauncher(run, log)`. `launch({udid,
  bundleId, osVersion, ddi})` runs `mounter mount-developer <image> <sig> --udid` (an "already mounted" error is
  success; any other error warns and falls back), then `developer dvt launch <bundleId> --udid`. Without a disk image
  it prints the tap-to-open guidance plus `xcross logs --app <id>`. Tests: `XT/device/legacy_device_launcher_test.dart`.

## Phase 2: US1 — run on iOS 16 (P1)

- [X] T003 [US1] `device_precheck.dart`: default `minimumIos` 15. `PrecheckedDevice` gains `osVersion` and
  `bool get legacy` (major < 17). Update the `device.ios_unsupported` text; the hint now names iOS 15.
- [X] T004 [US1] In `device_run_operation.dart`, when `prechecked?.legacy` (or the read major < 17 when not
  prechecked), skip terminate/launch through CoreDevice after install and call `LegacyDeviceLauncher`. Add a
  `ddiDirectory` option. The old iOS 17 throw is removed (iOS < 15 is caught by the precheck).
- [X] T005 [US1] `flutter_run_command.dart`: no `--ddi` flag here. It reads `XCROSS_DDI_DIR` /
  `~/.xcross/DeviceSupport`, which avoids regenerating the build_cli parser; `--ddi` is on `xcross install`. After the
  precheck, if the device is legacy and the build is not precompiled, throw `codedError(device.legacy_debug_unsupported, …)` before the build. Add the code
  to `xcross_diagnostics.dart` and the contract.
- [X] T006 [US1] Tests: `XT/device/legacy_run_test.dart`, covering `AC-005-1 iOS 16 accepted` (the precheck),
  `AC-005-4 debug on iOS 16 fails before build` (command with seams) and `AC-005-3 legacy install then tap guidance`
  (run operation with a fake backend and launcher).

## Phase 3: US2 — `xcross install` (P1)

- [X] T007 [US2] `X/composition/cli/install_command.dart`: `InstallCommand` with `<path> [--udid] [--ddi]
  [--no-launch]`.
  - An `.ipa` is extracted to a temp dir (`Payload/*.app`, exactly one); an `.app` is copied to a temp dir so the
    original is never modified.
  - The bundle id is read from Info.plist.
  - Then precheck → `DeviceRunOperation.run(pack: PackResult(...), prechecked:, launchProfile: native)`.
  - Codes: `install.unsupported_input`, `install.no_app`.
- [X] T008 [US2] Register it in `runner.dart` (`// studio: 005`).
- [X] T009 [US2] Tests: `XT/cli/install_command_test.dart`, covering `AC-005-6` input errors and `AC-005-5` IPA
  extraction feeding the device run (seams).

## Phase 4: Polish

- [X] T010 Contract `contracts/cli.md`, README row, CHANGELOG, ROADMAP, HANDOFF, and `device-check.md` with rows
  for tomorrow's iPhone test.
- [X] T011 Analyze, run the tests, commit, push.
