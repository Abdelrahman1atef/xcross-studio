# Research: 020

## R1 API resources (App Store Connect API v1)
- **Builds:** `GET /v1/builds?filter[app]=<id>&sort=-uploadedDate&include=preReleaseVersion,buildBetaDetail,betaGroups`;
  `filter[version]` is the build number, `filter[preReleaseVersion.version]` the marketing version. Attributes:
  `version`, `uploadedDate`, `processingState`, `expired`, `usesNonExemptEncryption`. `buildBetaDetails` carry
  `internalBuildState` and `externalBuildState`.
- **Groups:** `GET /v1/betaGroups?filter[app]=<id>`; `POST /v1/betaGroups` (`name`, `isInternalGroup`,
  `publicLinkEnabled`, `publicLinkLimitEnabled`, `publicLinkLimit`, relationship `app`); `PATCH /v1/betaGroups/<id>`
  for the public link (the link itself is the `publicLink` attribute); builds join a group through
  `POST /v1/betaGroups/<id>/relationships/builds`.
- **Testers:** `POST /v1/betaTesters` (`email`, `firstName`, `lastName`, relationship `betaGroups`); an existing email
  answers 409, then `GET /v1/betaTesters?filter[email]=…` and `POST /v1/betaGroups/<id>/relationships/betaTesters`;
  `GET /v1/betaGroups/<id>/betaTesters` lists them.
- **What to Test:** `GET /v1/builds/<id>/betaBuildLocalizations`, then `PATCH /v1/betaBuildLocalizations/<id>`
  (`whatsNew`) or `POST /v1/betaBuildLocalizations` (`locale`, `whatsNew`, relationship `build`).
- **Export compliance:** `PATCH /v1/builds/<id>` with `usesNonExemptEncryption`.
- **External testing:** `betaAppLocalizations` (`description`, `feedbackEmail`, `marketingUrl`, `privacyPolicyUrl`,
  `locale`; GET via `/v1/betaAppLocalizations?filter[app]=<id>`), `betaAppReviewDetails` (id = app id;
  `contactFirstName`, `contactLastName`, `contactEmail`, `contactPhone`, `demoAccountName`, `demoAccountPassword`,
  `demoAccountRequired`, `notes`), `POST /v1/betaAppReviewSubmissions` (relationship `build`; attribute
  `betaReviewState`).
- **Decision:** call these directly through `AscApi`; no generated client.
- **Alternatives:** Apple's OpenAPI generator (a large dependency for a dozen calls).
