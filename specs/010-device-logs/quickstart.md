# Quickstart: validate 010 device logs

CLI contract: [contracts/cli.md](contracts/cli.md). Event schema: [contracts/devicelog.schema.json](contracts/devicelog.schema.json).

## Prerequisites

- An iPhone connected by USB, unlocked and trusting this computer.
- `pymobiledevice3` installed: `py -m pip install -U pymobiledevice3` on Windows, `pipx install pymobiledevice3` on
  Linux.
- The host device service running (Apple Mobile Device Service / usbmuxd).
- Run the commands with `dart run packages/xcross/bin/xcross.dart …`, or an installed `xcross`.

## 1. Automated

```bash
dart analyze --fatal-warnings
cd packages/studio_ext && dart test --name "AC-010-"
cd packages/dart_mobile_device && dart test
cd packages/xcross && dart test test/device test/cli
```

## 2. Real device

| # | Command | Expected |
|---|---|---|
| 1 | `xcross logs --duration 5` | live lines `HH:MM:SS.mmm process[pid] L message` within 2 s; no tunnel, no DDI, no admin |
| 2 | `xcross logs --app <bundle-id> --duration 60`, then launch the app | "waiting for <exe>", then the app's lines; relaunching the app keeps streaming (AC-010-1, AC-010-3) |
| 3 | `xcross logs --level error --grep <word> --save out.log --duration 10` | only matching lines, the same ones in `out.log` (AC-010-4) |
| 4 | `xcross logs --app <flutter app> --preset flutter` | only Dart output, without the `flutter: ` prefix (AC-010-5) |
| 5 | `xcross app info <bundle-id>` | version, signer type, team, entitlements; ✔/✖ for push and associated domains (AC-010-6) |
| 6 | `xcross logs --app <bundle-id> --preset push --duration 45`, then open the app (send a test push) | highlighted push lines; a diagnosis after 30 s and at the end (AC-010-7, AC-010-8) |
| 7 | `xcross crashes list` / `xcross crashes pull --latest` | newest-first list; the report saved with its exception summary (AC-010-9) |
| 8 | `xcross logs --json --duration 5` | NDJSON lines valid against the schema (AC-010-10) |
| 9 | Default output | no UDIDs, tokens or emails (SC-004) |
