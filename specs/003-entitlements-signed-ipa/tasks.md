# Tasks: Apply the app's entitlements when signing

- [X] T001 `X/shared/flutter/build/flutter_app_entitlements.dart`: `FlutterAppEntitlements` with `locate`, `read` (path → map,
  `FormatException` when unreadable) and `withSigningKeys(plistXml, declared)` (adds the two keys; XML round trip). Adds the
  `build.entitlements_unreadable` code.
- [X] T002 Assembler hunk in `_writeInfoPlist` (`// studio: 003`): resolve the path, read it, warn on unreadable,
  merge.
- [X] T003 Tests `XT/flutter/build/flutter_app_entitlements_test.dart` (AC-003-1/2/3).
- [X] T004 Docs (CHANGELOG, ROADMAP, device-check); analyze; tests; commit; push.
