# Implementation Plan: TestFlight from the CLI

**Branch**: `020-testflight` (on `008-json-events-gui`) | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)

## Summary

S = `packages/studio_ext/lib`.

- **S/src/shared/appstore/testflight_api.dart** (new): `TestFlightApi` over `AscApi`: builds (with
  `preReleaseVersion`, `buildBetaDetail`, `betaGroups` included), groups, group create, add build, What to Test,
  testers, compliance, beta app localization, beta review detail, review submission, public link. Plain records
  (`TestFlightBuild`, `TestFlightGroup`) with `toJson`.
- **S/shared/appstore/testflight_command.dart** (new): `xcross testflight …` subcommands; app from `--app-id` or the
  project bundle ID (`ReleaseProject.bundleId`, feature 018); build from `--build` or the newest upload; errors
  through `ascFailure`.
- **packages/xcross/lib/src/composition/cli/testflight_commands.dart**: fills `testflightCommands(runtime)` with
  `openAscApi(runtime)` (the only xcross change).

## Technical Context

Dart 3 · no new dependency (studio_ext already depends on `apple_developer_kit` and `http` since the 019
groundwork) · tests with `FakeAsc` (scripted JSON:API over `MockClient`) · Windows/Linux.

## Constitution Check

I new files, one composition seam that was prepared for it · II nothing Apple-supplied · III refusals explained with
the role needed · IV CLI only · V no OS branching · VI tests named AC-020-n, store rows in `device-check.md` ·
VII reuses `AscApi`, `resolveAscApp`, `ReleaseProject` · VIII passwords never printed. No violations.

## Tests

`packages/studio_ext/test/shared/appstore/testflight_test.dart` (AC-020-1…9).
