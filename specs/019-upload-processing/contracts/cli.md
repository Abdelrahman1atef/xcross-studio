# CLI contract: 019

## `xcross publish [<ipa>] [--app-id <id>] [--wait] [--timeout <minutes>] [--json] [--transporter] [--validate]`

Text: `Uploading 1.2.3 (7) to <app name>`, a part counter, `Upload state: PROCESSING`, `Build processing: VALID`.
Exit 0 on success (or `VALID` with `--wait`), 1 on failure, 2 on a `--wait` timeout.

`--json` (NDJSON):
```
{"v":1,"type":"publish","event":"progress","part":3,"parts":12,"bytes":…,"total":…}
{"v":1,"type":"publish","event":"state","upload":"PROCESSING"}
{"v":1,"type":"publish","event":"published","uploadId":"…","uploadState":"COMPLETE","buildId":"…","processingState":"VALID","issues":[{"severity":"warning","code":"…","description":"…"}]}
```

Codes: `publish.duplicate_build`, `publish.upload_failed`, `publish.processing_failed`, `publish.transporter_missing`,
`publish.no_ipa`.

## `xcross flutter build … --build-number auto`

`APP_STORE_APP_ID` selects the app; otherwise the project bundle ID.

## `build/xcross-ios/release.json`

```json
{"app":"…","bundleId":"…","teamId":"…","version":"1.2.3","build":"7","minimumOS":"15.0","sdk":"iphoneos27.1",
 "flutter":"3.47.0","git":{"commit":"…","dirty":false},"ipa":{"path":"…","sha256":"…","size":123},
 "upload":{"id":"…","state":"COMPLETE","at":"…"},"build_record":{"id":"…","processingState":"VALID"}}
```
