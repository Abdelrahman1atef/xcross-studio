# Research: 021

## R1 Resources used (App Store Connect API v1)
- **App**: `GET /v1/apps?filter[bundleId]=…`. Apple's public API has no app creation (the `apps` resource is
  read/update only), so a missing record is a link to the New App page.
- **Version**: `GET /v1/apps/{id}/appStoreVersions?filter[platform]=IOS`, editable when `appStoreState` (or the newer
  `appVersionState`) is one of `PREPARE_FOR_SUBMISSION`, `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`,
  `INVALID_BINARY`; `POST /v1/appStoreVersions` (`platform`, `versionString`, relationship `app`); `copyright` is a
  version attribute.
- **Localizations**: `appStoreVersionLocalizations` (`description`, `keywords`, `promotionalText`, `whatsNew`,
  `supportUrl`, `marketingUrl`) and `appInfoLocalizations` (`name`, `subtitle`, `privacyPolicyUrl`) under the
  editable `appInfos` record (state not `READY_FOR_DISTRIBUTION`/`READY_FOR_SALE`).
- **Categories**: `PATCH /v1/appInfos/{id}` relationships `primaryCategory`/`secondaryCategory` (`appCategories` ids
  such as `UTILITIES`); read with `include=primaryCategory,secondaryCategory`.
- **Age rating**: `GET /v1/appInfos/{id}/ageRatingDeclaration`, `PATCH /v1/ageRatingDeclarations/{id}`.
- **Screenshots**: `appScreenshotSets` (`screenshotDisplayType`, relationship `appStoreVersionLocalization`),
  `POST /v1/appScreenshots` (`fileName`, `fileSize`) returns `uploadOperations` (`method`, `url`, `offset`, `length`,
  `requestHeaders`); then `PATCH uploaded: true, sourceFileChecksum` (MD5 hex).
- **Build**: `GET /v1/builds?filter[app]=…&filter[version]=<CFBundleVersion>`; `PATCH
  /v1/appStoreVersions/{id}/relationships/build`.
- **Review**: `POST /v1/reviewSubmissions` (`platform`, relationship `app`), `POST /v1/reviewSubmissionItems`
  (relationships `reviewSubmission`, `appStoreVersion`), `PATCH /v1/reviewSubmissions/{id}` `submitted: true`; an
  unsubmitted submission is in state `READY_FOR_REVIEW`.
- **Not in the API**: App Privacy (data collection) answers, pricing and availability, agreements, tax and banking.

## R2 Screenshot sizes (Apple's screenshot specifications, portrait and landscape)
- `APP_IPHONE_67`: 1290×2796, 1320×2868, 1260×2736 · `APP_IPHONE_65`: 1242×2688, 1284×2778 · `APP_IPHONE_61`:
  1179×2556, 1170×2532 · `APP_IPHONE_58`: 1125×2436, 1080×2340, 1170×2532 · `APP_IPHONE_55`: 1242×2208 ·
  `APP_IPHONE_47`: 750×1334 · `APP_IPAD_PRO_3GEN_129`: 2048×2732, 2064×2752 · `APP_IPAD_PRO_129`: 2048×2732 ·
  `APP_IPAD_PRO_3GEN_11`: 1668×2388, 1640×2360, 1488×2266 · `APP_IPAD_105`: 1668×2224 · `APP_IPAD_97`: 1536×2048.
- **Decision:** a fixed table checked before upload; landscape is the swap.

## R3 Folder layout
- **Decision:** fastlane deliver's names (`name.txt`, `release_notes.txt`, `privacy_url.txt`, …) so teams moving from
  fastlane keep their folder.
