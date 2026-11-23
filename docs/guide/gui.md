# Using xcross from a GUI

[← xcross README](../../README.md) · [All guides](README.md)

This repository holds only the `xcross` engine (CLI). Desktop apps drive it as a subprocess and keep no build logic
of their own. `xcross engine info --json` tells a GUI which engine and protocol version it is talking to.

<!-- studio: 012 -->
**Machine-readable output:** with `XCROSS_EVENTS=ndjson` set, `xcross flutter build`, `flutter run`, `install` and
`flutter doctor` print one JSON event per line on stdout: `step`, `progress`, `log`, `warning`/`error` (with `code` and
`hint`), `artifact` (the `.app`/`.ipa` path), `device`, `check` and `done` (exit code). A GUI can use it for a
step list, progress bar, issue list and Install button. Schema:
[specs/012-build-events/contracts/events.schema.json](../../specs/012-build-events/contracts/events.schema.json).

<!-- studio: 014 -->
**No iOS compiler for a Flutter version?** A release or profile build stops with `[build.gen_snapshot_unavailable]`,
names the nearest Flutter version that has one, and `xcross flutter sdk auto` installs it for iOS builds only. See
[Flutter versions and iOS compilers](flutter-versions.md#flutter-versions-and-ios-compilers) for where compilers come from.
