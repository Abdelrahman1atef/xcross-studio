# Research: 019

## R1 Build Upload API (App Store Connect API 4.1+)
- `POST /v1/buildUploads`: attributes `cfBundleShortVersionString`, `cfBundleVersion`, `platform` (`IOS`);
  relationship `app`. State `AWAITING_UPLOAD | PROCESSING | FAILED | COMPLETE` with `errors`, `warnings`, `infos`
  (`StateDetail {code, description}`).
- `POST /v1/buildUploadFiles`: attributes `assetType` (`ASSET`), `fileName`, `fileSize`, `uti` (`com.apple.ipa`);
  relationship `buildUpload`. The response carries `uploadOperations [{method, url, offset, length, partNumber,
  requestHeaders [{name, value}], expiration}]`.
- `PATCH /v1/buildUploadFiles/{id}`: `uploaded: true`, `sourceFileChecksums {file {hash, algorithm: MD5}}`.
- `GET /v1/buildUploads/{id}` for the state; `GET /v1/builds?filter[app]=…&filter[version]=<build>&filter[
  preReleaseVersion.version]=<version>` for the build and its `processingState`.
- **Decision:** use this API by default (no Apple tool needed); Transporter stays an opt-in fallback.

## R2 Build number
- **Decision:** the newest build of the app (`/v1/builds?filter[app]=…&sort=-uploadedDate&limit=50`, numeric
  `version` attributes) + 1, never lower than the pubspec number; the same rule as the reference workflow.

## R3 Transporter
- Installed by the user from Apple (`iTMSTransporter` under `C:\Program Files (x86)\itms\` on Windows,
  `/usr/local/itms/bin/` on Linux); API key auth with `-apiKey <keyId> -apiIssuer <issuerId>` and the `.p8` in
  `~/.appstoreconnect/private_keys/`. **Decision:** look up those paths and `XCROSS_TRANSPORTER`, never download.
