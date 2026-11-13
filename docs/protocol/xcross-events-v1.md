# xcross NDJSON events, protocol v1

This is how the `xcross` CLI reports machine-readable results to programs that run it, such as desktop front-ends and CI scripts. It is a public, versioned interface. Machine-readable schema: [`xcross-events-v1.schema.json`](xcross-events-v1.schema.json).

## Framing
- Output is **one JSON object per line** (NDJSON), ASCII-only, on stdout.
- Every event has `"v": 1` and a string `"type"`. Example: `{"v":1,"type":"step","name":"Compiling Runner","status":"start"}`
- Build, run, install and doctor commands emit events when `XCROSS_EVENTS=ndjson` is set. Commands with a `--json` flag emit their result events with that flag.
- A tool that writes straight to stdout can leave a partial line, so an event may follow plain text on the same line. Consumers look for `{"v":1,"type":` within the line.
- Plain text lines that are not events may appear between events. Treat them as log output.

## Compatibility rules
1. **Consumers ignore unknown `type` values and unknown fields.**
2. Within v1, producers may **add** event types and fields. They don't remove or rename fields, or change a field's meaning or JSON type.
3. Any breaking change uses `"v": 2`. Consumers ignore versions they don't know.
4. Optional fields may be absent or `null`. Consumers apply their own defaults.

## Reading the schema
- Each event type is a `$defs/event_<type>` entry, selected by `type`. Field names come from the code on both sides.
- Fields are listed by name, and their value shapes are left open on purpose: rule 1 lets them grow. Field-level schemas from earlier contracts are in `specs/012-build-events/contracts/events.schema.json` and `specs/010-device-logs/contracts/devicelog.schema.json`.
- `examples` are taken from real test data where they exist (`x-example-source`).
- `x-cli-emitters` lists the source files that emit the type. `x-consumed-by-studio` and `x-studio-class` record which types the desktop app currently reads. The other 5 types are emitted for scripts and are ignored by the app.

## Event types (43)
| Type | Studio reads it | Studio class | Fields | Emitted in |
|---|---|---|---|---|
| `app` | yes | InstalledApp | build, bundleId, executable, name, version | packages/studio_ext/lib/target/iphone/device/app_command.dart |
| `appinfo` | yes | AppInfo | associatedDomains, build, bundleId, entitlements, executable, name, push, signer, teamId, version | packages/studio_ext/lib/src/target/iphone/device/installed_app_info.dart |
| `appstore_app` | no (ignored) | - | bundleId, found, id, name, newAppUrl, primaryLocale, sku | packages/studio_ext/lib/shared/appstore/appstore_command.dart |
| `appstore_status` | yes | AppStoreStatus | build, state, submissions, version | packages/studio_ext/lib/src/shared/appstore/app_store_review.dart |
| `appstore_version` | no (ignored) | - | created, id, state, version | packages/studio_ext/lib/shared/appstore/appstore_command.dart |
| `artifact` | yes | BuildArtifact | kind, path | packages/xcross/lib/src/composition/cli/flutter_build_command.dart, packages/xcross/lib/src/shared/flutter/build/flutter_pack_operation.dart |
| `asc_account` | yes | AccountDetailsReport | holderName, problem, teamId | packages/studio_ext/lib/shared/auth/account_lookup.dart |
| `auth_status` | yes | AuthStatusReport | apiKey, appStoreBuilds, appleId, deviceBuilds | packages/studio_ext/lib/shared/auth/saved_sign_in.dart |
| `bundle_id` | yes | BundleIdStatus | bundleId, next, override, saved, settingsPath | packages/xcross/lib/src/target/iphone/cli/basic/project_command.dart |
| `capabilities` | yes | CapabilitiesReport | capabilities, entitlements, project, unknownEntitlements | packages/studio_ext/lib/shared/permissions/permissions_command.dart |
| `capabilities_change` | yes | ProjectChange | action, backup, changed, id, key, notes | packages/studio_ext/lib/shared/permissions/permissions_command.dart |
| `check` | yes | DoctorCheckResult | message, name, path, section, status | packages/xcross/lib/src/shared/cli/basic/doctor_command.dart |
| `crash` | yes | CrashReport | exceptionType, name, process, time | packages/studio_ext/lib/target/iphone/device/crashes_command.dart |
| `device` | yes | ConnectedDevice | connection, legacy, name, osVersion, udid | packages/studio_ext/lib/target/iphone/device/devices_command.dart, packages/xcross/lib/src/target/iphone/device/device_precheck.dart |
| `devicelog` | yes | DeviceLogLine | category, highlight, level, message, pid, process, subsystem, time | packages/studio_ext/lib/src/target/iphone/device/log_output.dart |
| `devices` | yes | DeviceSnapshot | devices | packages/studio_ext/lib/target/iphone/device/devices_command.dart |
| `diagnosis` | yes | PushDiagnosis | appSeen, bundleId, deliverySeen, entitlement, hint, permissionDenied, registrationSeen, verdict | packages/studio_ext/lib/src/target/iphone/device/push_diagnosis.dart |
| `done` | yes | BuildDone | exitCode | packages/xcross/lib/src/composition/cli/runner.dart |
| `engine_info` | yes | EngineInfoReport | engine, protocol, version | packages/studio_ext/lib/shared/engine/engine_info_command.dart |
| `error` | yes | BuildIssue | code, hint, message | packages/studio_ext/lib/shared/events/ndjson_events.dart |
| `flutter_sdks` | yes | FlutterSdkStatus | active, available, catalogError, catalogStale, managed, platform, suggested | packages/xcross/lib/src/shared/cli/flutter/subcommands/flutter_sdk_command.dart |
| `icons_check` | yes | IconsCheckReport | errors, issues, path, placement, set, slots, source, style, warnings | packages/studio_ext/lib/src/shared/icons/icon_check.dart |
| `icons_generate` | yes | IconsGenerateResult | background, backup, check, issues, notes, padding, path, source, targets, upscaled, written | packages/studio_ext/lib/shared/icons/icons_generate_command.dart |
| `icons_preview` | yes | IconsPreview | error, paths, seq | packages/studio_ext/lib/shared/icons/icons_generate_command.dart |
| `ios_prepare` | yes | IosPrepareReport | bundleId, deploymentTarget, leftOut, permissionMacros, plugins, ready, steps | packages/studio_ext/lib/shared/ios/ios_prepare.dart |
| `log` | yes | BuildLog | level, message, step, stream | packages/studio_ext/lib/shared/events/ndjson_events.dart |
| `notice` | yes | Notice | message | packages/studio_ext/lib/target/iphone/device/devices_command.dart, packages/studio_ext/lib/target/iphone/device/logs_command.dart |
| `permissions` | yes | PermissionsReport | catalog, infoPlist, missing, permissions, project | packages/studio_ext/lib/shared/permissions/permissions_command.dart |
| `permissions_change` | yes | ProjectChange | action, backup, changed, id, key, notes | packages/studio_ext/lib/shared/permissions/permissions_command.dart |
| `plugin_ack` | no (ignored) | - | plugin | packages/studio_ext/lib/shared/plugins/plugin_status.dart |
| `plugin_status` | yes | PluginStatusReport | plugins, project | packages/studio_ext/lib/shared/plugins/plugin_status.dart |
| `progress` | yes | BuildProgress | current, fraction, label, total, unit | packages/cli_kit/lib/shared/progress/progress.dart |
| `project_version` | yes | ProjectVersion | build, changed, previous, pubspec, version | packages/xcross/lib/src/target/iphone/cli/basic/project_command.dart |
| `publish` | yes | PublishEvent | event | packages/studio_ext/lib/shared/appstore/publish_command.dart |
| `release_check` | yes | ReleaseCheckReport | configuration, errors, input, issues, warnings | packages/studio_ext/lib/src/shared/release/release_checks.dart |
| `release_gate` | yes | ReleaseGateResult | steps | packages/studio_ext/lib/shared/release/release_gate_command.dart |
| `splash_check` | yes | SplashCheckReport | android, errors, ios, issues, warnings | packages/studio_ext/lib/src/shared/splash/splash_check.dart |
| `splash_generate` | yes | SplashGenerateResult | backup, check, issues, path, platforms, removed, written | packages/studio_ext/lib/shared/splash/splash_command.dart |
| `step` | yes | BuildStep | done, elapsedMs, message, name, status | packages/studio_ext/lib/shared/events/ndjson_events.dart |
| `testflight_groups` | no (ignored) | - | groups | packages/studio_ext/lib/shared/appstore/testflight_command.dart |
| `testflight_status` | yes | TestFlightStatus | appId, builds, bundleId | packages/studio_ext/lib/shared/appstore/testflight_command.dart |
| `testflight_testers` | no (ignored) | - | group, testers | packages/studio_ext/lib/shared/appstore/testflight_command.dart |
| `warning` | yes | BuildIssue | code, hint, message | packages/studio_ext/lib/shared/events/ndjson_events.dart |

`publish` events also carry fields that depend on the publish step (`event` = start, progress, uploaded, state, issue, published, note).

## Keeping this in sync
Contract tests fail when the protocol drifts:
- `apps/studio/test/cli/protocol_schema_contract_test.dart`: every schema example parses, every type the app reads dispatches to its class, and the 5 script-only types are ignored.
- `packages/studio_ext/test/protocol_schema_contract_test.dart`: every event type the CLI emits is in the schema, and the schema lists nothing the CLI no longer emits.

When you add an event type or field, update the schema and this table in the same change.
