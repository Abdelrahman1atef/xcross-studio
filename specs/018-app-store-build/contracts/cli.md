# CLI contract: 018

## `xcross flutter build --release --ipa --export-method app-store`

Writes `build/xcross-ios/ipa/<name>.ipa` and `build/xcross-ios/archive/Runner.xcarchive`; `artifact` events `ipa`
and `xcarchive`. `XCROSS_CERTIFICATE_PRIVATE_KEY` (PEM) selects the distribution key.

## `xcross release check [<ipa|app>] [--json] [--project <dir>]`

Text: a configuration block, then `error [release.x] message` / `warning …` / `info …` lines with `hint:`; exit 1
on an error. JSON: `{"v":1,"type":"release_check","input":"…","configuration":{…},"issues":[{"code","severity",
"message","path","hint"}],"errors":n,"warnings":n}`.

## Project settings

`xcross: uses_non_exempt_encryption: false|true` → `ITSAppUsesNonExemptEncryption`.
