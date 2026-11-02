<!-- The user story as provided on 2026-11-03 (Mac/Xcode edition). Feature work rewrites it
     for XCross Studio as docs/release/US-IOS-001-xcross.md; see specs/HANDOFF-2026-11-03.md. -->

# US-IOS-001 — Build, Archive, Sign, Upload, and Distribute Flutter iOS Application

**Story Type:** Technical / Release Engineering  
**Priority:** High  
**Platform:** iOS / iPadOS  
**Technology:** Flutter, Dart, Xcode, Apple Developer Program, App Store Connect, TestFlight  
**Primary Owner:** iOS / Flutter Developer  
**Supporting Roles:** QA Engineer, Release Manager, Apple Developer Account Holder  
**Scope:** First-time publication and subsequent production builds  
**Requirements Verified:** November 3, 2026

---

## 1. User Story

**As an iOS Mobile Developer,**

I want to configure, compile, archive, code-sign, validate, and upload my Flutter application's production-ready iOS build using Xcode and App Store Connect,

**So that** I can securely distribute the application through TestFlight, enable internal and external beta testing, collect feedback, and prepare the validated application for Apple's final App Store review and public release.

### Business Value

- Establish a reliable, repeatable iOS release process.
- Ensure compliance with Apple's signing, security, privacy, and distribution requirements.
- Prevent rejected uploads caused by configuration errors.
- Allow QA testers to install the same production configuration intended for release.
- Minimize manual mistakes and build-number conflicts.
- Maintain traceability between the application source code, release archive, and App Store Connect build.
- Enable repeatable future releases without recreating the entire deployment configuration.

### Expected Outcome

The developer produces a valid iOS release archive, successfully uploads it, verifies Apple's processing result, and makes it available for the appropriate TestFlight testing group. The build is also eligible for selection in the App Store submission workflow once all required release metadata and compliance steps are complete.

---

# 2. Preconditions and Dependencies

## 2.1 Hardware and Operating System

**Given** the developer is preparing an iOS production release,

**When** the local development environment is reviewed,

**Then** the following requirements must be satisfied:

- A supported Mac running macOS is available.
- Xcode is fully installed, not only Command Line Tools.
- The selected Xcode version supports the iOS SDK required by App Store Connect.
- As of November 2026, the build must use Xcode 26 or later and iOS SDK 26 or later.
- The app's iOS deployment target must be at least iOS 13, and may need to be higher depending on Flutter plugins and native dependencies.
- Xcode license agreements and first-launch setup are completed.
- Xcode Command Line Tools are correctly selected.
- Flutter SDK is installed and compatible with the selected Xcode version.
- CocoaPods is available when required by project dependencies.
- Sufficient disk space is available for dependencies, DerivedData, archives, symbols, and IPA exports.
- Internet connectivity is available for Apple authentication, dependency retrieval, validation, and upload.
- At least one compatible physical iPhone or iPad is available for release testing, or there is an approved device-testing plan.

**Validation Commands:**

```bash
sw_vers
xcodebuild -version
xcode-select -p
xcrun --sdk iphoneos --show-sdk-version
flutter --version
flutter doctor -v
pod --version
```

**Expected Result:** The tools resolve correctly and no outstanding environment issue prevents a production release.

**Technical Note:** An iOS release cannot be compiled natively using Xcode on Windows. A local Mac or an approved macOS build environment is required.

## 2.2 Apple Developer Program

**Given** the application will be distributed through Apple's App Store Connect infrastructure,

**When** the developer authenticates,

**Then**:

- An active Apple Developer Program membership must exist.
- The correct Apple Account must be added under Xcode → Settings → Accounts.
- The correct development team must be selected.
- The team must be authorized to sign and distribute the intended application.
- Required Apple Developer and App Store Connect agreements must be accepted.
- Required authentication or two-factor verification must be completed.
- The App Store Connect app record must exist before the first upload.
- The developer must have an appropriate role and access to the app.
- Certificates and provisioning profiles must be available or creatable through permitted signing workflows.

**Role distinctions:**

- Account Holder, Admin, and App Manager can perform broader App Store Connect release-management operations.
- A Developer role can upload builds when appropriately authorized.
- Managing TestFlight external testers, metadata, and final App Review submission may require an Account Holder, Admin, or App Manager.

**Individual Account Note:** A personal Apple Developer Program membership can distribute applications through TestFlight and the App Store. An organization account is not mandatory.

## 2.3 Source Code Readiness

**Given** a release candidate has been approved,

**When** the development branch is prepared,

**Then**:

- The release branch, tag, or commit must be identified.
- All intended features must be merged.
- No unresolved release-blocking defects may remain.
- `flutter analyze` must pass under the project's agreed quality policy.
- Required automated tests must pass.
- The production API environment must be configured.
- The application must not reference testing or staging endpoints unintentionally.
- Private signing keys, API credentials, and secrets must not be committed.
- Plugin and dependency versions must be reviewed for compatibility.
- Any generated configuration files needed for the iOS build must be available.
- The release must be reproducible from the recorded source revision.

---

# 3. Acceptance Criteria

## AC-01 — Application Registration and Bundle Identifier

**Given** the developer has access to the Apple Developer portal,

**When** a new iOS application is registered,

**Then**:

1. A unique, explicit Bundle ID must be registered in Apple Certificates, Identifiers & Profiles.
2. The Bundle ID must follow reverse-domain notation, for example `com.company.product`.
3. The identifier must be associated with the correct Apple Developer team.
4. Required Apple services and capabilities must be configured for the App ID.
5. An iOS app record must be created in App Store Connect under Apps → New App.
6. The app record must contain the intended app name, platform, primary language, Bundle ID, and unique SKU.
7. The app record must reference the same Bundle ID as the Xcode application target.
8. The App Store Connect app record must be visible to the release owner.
9. The app must not accidentally use the identifier belonging to another application or environment.
10. App extensions, notification service extensions, widgets, and other additional targets must have their own appropriately configured identifiers when applicable.

**Failure Conditions:**

- Bundle ID already registered to another team.
- Xcode identifier differs from the App Store Connect record.
- App record does not exist.
- Required Apple services are missing.
- Developer lacks permission to access the app.

**Expected Result:** The Apple app record and Xcode application reference the same unique, registered identifier.

## AC-02 — Flutter Version and Build Number Configuration

**Given** the source code is ready for deployment,

**When** the developer updates `pubspec.yaml`,

**Then** the application version and build number must use a valid format.

**Example:**

```yaml
version: 1.0.0+1
```

Here:

- `1.0.0` is the marketing version.
- `1` is the build number.

The mapping to iOS must be verified:

| Flutter value | iOS value | Purpose |
|---|---|---|
| `1.0.0` | `CFBundleShortVersionString` | User-facing version |
| `1` | `CFBundleVersion` | Uploaded build identification |

**Additional Acceptance Rules:**

1. Every new uploaded build must have a valid, unused build identifier for its version.
2. Version and build number must not unintentionally be overridden by Xcode settings, CI configuration, or command-line arguments.
3. The final compiled application must contain the expected version values.
4. The App Store Connect version association must match the intended release.
5. Flutter values such as `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER` must be checked when the project uses the standard generated build configuration.
6. Different flavors or release schemes must not produce unexpected version values.
7. The build number must be traceable to a release commit or CI build.
8. If an upload is accepted, subsequent uploads must use a new appropriate build number.
9. Version changes must be documented in the release notes or release record.

**Alternative CLI Override:**

```bash
flutter build ipa --release \
  --build-name=1.0.0 \
  --build-number=1
```

**Expected Result:** The version displayed in the compiled app and App Store Connect matches the approved release version.

## AC-03 — Xcode Project and Target Configuration

**Given** Flutter dependencies have been resolved,

**When** the developer runs:

```bash
open ios/Runner.xcworkspace
```

**Then**:

1. Xcode must open the workspace successfully.
2. The developer must select the correct project and application target.
3. The application target must have the correct Display Name.
4. The Bundle Identifier must be correct.
5. The intended iOS Deployment Target must be configured.
6. Supported destinations must match the product requirements.
7. The app must use the correct release scheme and build configuration.
8. The Release configuration must be used for distribution.
9. Required Swift or Objective-C native integrations must compile.
10. Frameworks and native plugins must link successfully.
11. The app must contain the correct app icons and launch screen.
12. The correct production environment must be selected.
13. No debug-only native configuration may accidentally be included.
14. The application target's Info.plist and generated build settings must resolve to valid values.

**Important:** Open `Runner.xcworkspace`, not `Runner.xcodeproj`, for a standard Flutter project using CocoaPods.

**Expected Result:** Xcode is correctly configured to produce the intended production iOS application.

## AC-04 — Apple Code Signing and Provisioning

**Given** the correct Xcode target has been selected,

**When** the developer opens Signing & Capabilities,

**Then**:

- The correct Apple Developer team must be selected.
- Automatically Manage Signing should be enabled unless the project uses an approved manual-signing process.
- Xcode must obtain or resolve the required distribution signing assets.
- The application must be signed for App Store distribution.
- The bundle identifier must match the registered App ID.
- Provisioning profiles must be valid and associated with the correct App ID.
- The distribution certificate must be valid and accessible through the appropriate keychain.
- The signing identity must match the selected team.
- Every embedded extension must be appropriately signed.
- The app's final entitlements must match the provisioning profile's authorized capabilities.
- Development-only profiles must not be used for the submitted production archive.
- Any certificate expiration or revocation must be detected before distribution.

### Required Entitlements and Capabilities

Depending on the application, validate:

- Push Notifications.
- Associated Domains and Universal Links.
- Sign in with Apple.
- App Groups.
- Keychain Sharing.
- Background Modes.
- In-App Purchase.
- Apple Pay.
- iCloud.
- HealthKit.
- Other registered Apple capabilities.

Only enable the capabilities actually used by the app.

**Failure Condition:** An archive may compile successfully but fail validation or distribution when the entitlement and provisioning configurations do not match.

**Expected Result:** The application is signed using a valid production distribution configuration.

## AC-05 — Native Permissions and Info.plist Configuration

**Given** the Flutter application uses device capabilities or protected user information,

**When** the developer reviews `ios/Runner/Info.plist`,

**Then** every applicable native permission must have the required Apple usage-description key and a meaningful explanation.

**Examples:**

| Feature | Common Info.plist key |
|---|---|
| Camera | `NSCameraUsageDescription` |
| Microphone | `NSMicrophoneUsageDescription` |
| Photo library access | `NSPhotoLibraryUsageDescription` |
| Save-only photo access | `NSPhotoLibraryAddUsageDescription` |
| Location while using app | `NSLocationWhenInUseUsageDescription` |
| Background location | Applicable always-location usage keys |
| Bluetooth | `NSBluetoothAlwaysUsageDescription` |
| Contacts | `NSContactsUsageDescription` |
| Calendars | Applicable calendar usage-description keys |
| Face ID | `NSFaceIDUsageDescription` |
| Motion data | `NSMotionUsageDescription` |
| Tracking | `NSUserTrackingUsageDescription` when ATT permission is required |

**Given** the application requests camera access,

**When** the native camera API is invoked,

**Then** the iOS permission dialog must display an accurate explanation such as:

> Camera access is used to capture photos that you choose to attach to your profile.

**Additional Validation:**

1. Permission descriptions must explain their actual purpose.
2. Only necessary permissions should be requested.
3. Permissions must be requested at an appropriate point in the user flow.
4. The app must handle granted, denied, restricted, and unavailable permission states.
5. Localized permission messages must be provided when required by the product's supported-language policy, using the appropriate localization mechanism such as `InfoPlist.strings`.
6. If permission is denied, the application must remain stable.
7. Native permissions introduced through Flutter plugins must also be reviewed.
8. Unnecessary broad App Transport Security exceptions must not be added.
9. Background-mode declarations must correspond to legitimate app functionality.

**Expected Result:** All protected-resource requests behave correctly without missing-description crashes or invalid permission configurations.

## AC-06 — Privacy, SDK and Compliance Validation

**Given** the application contains Flutter plugins and third-party dependencies,

**When** it is prepared for distribution,

**Then**:

1. All third-party iOS SDKs must be reviewed for Apple's current privacy manifest and SDK-signature requirements.
2. Any required `PrivacyInfo.xcprivacy` declarations must be present and valid.
3. Any required-reason APIs used by the application or included SDKs must have approved, accurate reasons declared in the appropriate privacy manifests.
4. Data collection by analytics, advertising, crash reporting, authentication, and other SDKs must be reviewed.
5. App Store Connect privacy disclosures must reflect actual data collection and handling.
6. A valid public privacy policy URL must be prepared for App Store submission.
7. App Tracking Transparency requirements must be satisfied if the app performs activities classified by Apple as tracking.
8. The application's encryption and export compliance obligations must be evaluated.
9. Export compliance questions must be answered accurately in App Store Connect.
10. `ITSAppUsesNonExemptEncryption` must only be set when the application's encryption assessment supports the declared value.
11. The release must not contain secret credentials or private keys.
12. Required user-data deletion or account deletion functionality must be provided where Apple's rules apply.
13. Any regulated-product, financial, medical, user-generated-content, or region-specific obligations must be reviewed if relevant.

**Technical Note:** Adding camera or location permission strings does not replace the need for privacy disclosures, privacy manifests, or required-reason API declarations.

**Expected Result:** The application meets the applicable Apple privacy, security, SDK, and export compliance requirements.

## AC-07 — App Icons, Launch Screen and Device Compatibility

**Given** the app is being prepared for production,

**When** the developer reviews the application's visual resources,

**Then**:

- Placeholder Flutter icons must be replaced.
- App icons must comply with Apple's current asset requirements.
- Light, dark, or tinted icon variants must be reviewed where applicable.
- The launch screen must use the intended branding.
- App icons must be present in the Xcode asset catalog.
- The intended app name must be displayed correctly on the home screen.
- The launch screen must not show broken images or development placeholders.
- Device orientation behavior must match the product requirements.
- iPhone and iPad compatibility must be configured intentionally.
- If the app supports iPad, it must be tested for the relevant layout and multitasking behaviors.
- Supported OS versions must align with native dependencies and Flutter constraints.
- Display layouts must be verified on representative supported screen sizes.

**Expected Result:** The production application presents the intended visual identity and works on its declared supported devices.

## AC-08 — Pre-Archive Quality Validation

**Given** the source code is ready for release,

**When** the developer executes the release-quality checks,

**Then** the following checks must pass.

**Static Validation:**

```bash
flutter pub get
flutter analyze
```

**Automated Tests:**

```bash
flutter test
```

**Environment Validation:**

```bash
flutter doctor -v
```

**Additional Release Testing:**

- Login and logout.
- Account creation, if implemented.
- Password reset or account recovery.
- Core user journeys.
- API connectivity.
- Authentication token handling.
- Secure storage.
- Image/file uploads, if implemented.
- Push notifications, if implemented.
- Deep links and Universal Links, if implemented.
- Background and foreground transitions.
- App relaunch.
- Offline behavior.
- Network timeout handling.
- Permission-denied scenarios.
- Payment and purchase flows, if implemented.
- Localization and right-to-left layouts, if supported.
- Accessibility and screen-reader behavior.
- App startup and runtime stability.
- Production endpoint connectivity.
- Relevant integration or end-to-end tests.

**Expected Result:** The app passes the team's release gate before an archive is generated.

## AC-09 — Release Build Generation

**Given** the application configuration and dependencies are valid,

**When** the developer executes:

```bash
flutter build ipa --release
```

**Then**:

1. Flutter must compile the Dart application in release mode.
2. Dart code must be compiled ahead of time to native machine code for the applicable iOS device architecture.
3. Flutter must produce the necessary native application resources.
4. Xcode must compile and link required native code and frameworks.
5. Production signing requirements must be applied.
6. The build process must finish without errors.
7. An `.xcarchive` must be generated.
8. When IPA export succeeds, an `.ipa` must be generated.
9. The final package must represent the intended release version.
10. The application must use production configuration values.
11. No debug-mode behavior or development-only functionality may be unintentionally included.

**Expected Flutter Build Output:**

```text
build/ios/archive/*.xcarchive
build/ios/ipa/*.ipa
```

**Optional Code Obfuscation:**

```bash
flutter build ipa --release \
  --obfuscate \
  --split-debug-info=build/symbols/ios
```

If obfuscation is used, its matching Dart symbol files must be retained securely for crash symbolication.

**Technical Notes:**

- Obfuscation is optional and is not a substitute for security controls.
- Flutter release builds must not contain hardcoded production secrets.
- Build warnings must be reviewed even when compilation succeeds.
- Xcode-generated native dSYM files and Flutter symbol artifacts have different roles and should be handled appropriately.
- A successful archive does not guarantee successful upload or Apple processing.

**Expected Result:** A valid production archive and, for the Flutter CLI path, an exported IPA are available.

## AC-10 — Archive Generation Using Xcode GUI

**Given** the developer prefers the Xcode graphical workflow,

**When** the project is opened in Xcode,

**Then** the following sequence must be supported:

1. Open `ios/Runner.xcworkspace`.
2. Select the correct application scheme, normally `Runner`.
3. Select the appropriate generic iOS device destination, such as Any iOS Device (arm64).
4. Ensure the archive action uses the Release configuration.
5. Open the Product menu.
6. Select Archive.
7. Monitor the build output.
8. Confirm the archive operation completes successfully.
9. Open Xcode Organizer using Window → Organizer if it is not already open.
10. Select the newly created archive.
11. Confirm the archive belongs to the intended application.
12. Verify its version, build number, and creation date.

**Expected Result:** Xcode Organizer contains a valid release archive.

**Important:** Product → Archive creates an Xcode archive. An IPA is created separately during an export operation when that output is requested.

## AC-11 — Archive Validation Before Distribution

**Given** an archive exists,

**When** the developer selects it in Xcode Organizer and initiates distribution validation,

**Then**:

- The intended application must be selected.
- The appropriate App Store Connect distribution path must be chosen.
- The developer must not accidentally choose a development or ad-hoc distribution profile.
- Xcode must verify applicable signing, entitlement, application identity, and packaging requirements.
- The correct team must be used.
- The final bundle identifier must match the registered application.
- The version and build number must be correct.
- Applicable embedded frameworks and extensions must be valid.
- Validation errors must be resolved before the final upload.
- Relevant warnings must be reviewed and recorded.

**Validation Failure Examples:**

- Invalid provisioning profile.
- Expired signing certificate.
- Unsupported SDK.
- Unsupported deployment target.
- Missing required privacy manifest data.
- Incorrect Bundle ID.
- Invalid entitlements.
- Missing application icons.
- Invalid embedded framework configuration.
- Duplicate uploaded build identification.
- Missing mandatory native declarations.

**Expected Result:** The selected archive passes distribution validation.

## AC-12 — Uploading the Archive to App Store Connect

**Given** the archive passes validation,

**When** the developer selects the upload action in Xcode Organizer,

**Then**:

1. The appropriate App Store Connect distribution destination must be selected.
2. The developer must review the signing and distribution options.
3. The correct Apple Developer account and team must be used.
4. The correct app identity must be verified.
5. The release must be uploaded using the intended App Store distribution workflow.
6. Xcode must initiate Apple's upload validation and transfer process.
7. The binary and applicable accompanying debug-symbol information must be handled through the selected distribution workflow.
8. The developer must monitor upload progress.
9. Any authentication, network, signing, or package errors must be handled.
10. Xcode must report successful upload completion before the task is marked uploaded.
11. The uploaded version and build number must be recorded.
12. The upload confirmation must be retained as release evidence.

**Alternative IPA Upload Methods:**

- Apple Transporter application.
- Supported App Store Connect upload command-line tooling.
- An approved CI/CD pipeline using an authorized Apple authentication method.

**Important:** An IPA exported for development or ad-hoc distribution must not be treated as an App Store distribution package.

**Expected Result:** Apple accepts delivery of the uploaded build.

## AC-13 — Post-Upload Processing Verification

**Given** Xcode or the upload tool reports success,

**When** the developer opens App Store Connect → Apps → Selected App → TestFlight,

**Then**:

1. The app's iOS build upload history must be checked.
2. The uploaded version and build number must match the release record.
3. The developer must monitor Apple's processing status.
4. A `Processing` state must be treated as an in-progress operation.
5. A `Complete` upload status must be treated as successful processing.
6. A `Failed` status must prevent the build from passing the release acceptance criteria.
7. Processing warnings must be reviewed.
8. The build must become available in the appropriate TestFlight build list.
9. The developer must check for missing export compliance, invalid binary, or other build-specific issues.
10. If processing remains unresolved beyond Apple's stated guidance, the issue must be investigated or escalated.

**Possible Upload States:**

| Status | Meaning | Required action |
|---|---|---|
| Processing | Apple is processing the upload | Monitor |
| Complete | Processing completed successfully | Continue with build eligibility checks |
| Failed | Processing encountered an error | Investigate and correct |

**Possible TestFlight Build States:**

| Status | Meaning |
|---|---|
| Ready to Submit | Eligible for the next applicable submission or distribution action |
| Ready to Test | Eligible for testing; testers may still need to be added |
| Testing | Build is assigned for testing |
| Missing Compliance | Export compliance action is required |
| Waiting for Review | Beta review is pending |
| In Beta Review | Apple is reviewing the beta build |
| Rejected | Build cannot proceed through the rejected beta-testing path |
| Expired | TestFlight availability has ended |
| Invalid Binary | Build failed applicable binary requirements |

**Expected Result:** The uploaded build completes processing and reaches a state appropriate for its intended testing or release workflow.

**Processing Note:** If a build remains in the upload Processing state for more than 24 hours, Apple recommends contacting support or using Feedback Assistant.

## AC-14 — Internal TestFlight Distribution

**Given** a processed build is eligible for internal testing,

**When** the developer or authorized release manager configures TestFlight,

**Then**:

1. An internal testing group must exist.
2. The required App Store Connect users must have appropriate access.
3. The intended release build must be added to the group.
4. The build's `What to Test` information must identify relevant changes or scenarios.
5. Automatic or manual tester notification must be configured intentionally.
6. Authorized testers must be invited or otherwise granted access through the group.
7. Testers must be able to open the TestFlight application.
8. Testers must be able to accept the invitation and install the intended version.
9. QA must verify successful installation and app launch.
10. Core release acceptance tests must run against the uploaded build.
11. Test results must be recorded.

**Limits and Constraints:**

- Apple supports up to 100 internal testers with App Store Connect access.
- TestFlight builds are normally available for up to 90 days.
- Builds marked **TestFlight Internal Only** cannot later be distributed to external testers or submitted to customers.
- If external testing or final App Store submission is intended, the distribution method must not unintentionally create an internal-only build.

**Expected Result:** Authorized internal testers can install and test the intended release build through TestFlight.

## AC-15 — External TestFlight Distribution

**Given** external beta testing is included in the release plan,

**When** an authorized release manager prepares the external testing workflow,

**Then**:

1. An internal testing group must first be created if none exists.
2. An external testing group must be created.
3. The intended eligible build must be added to the group.
4. The Beta App Description must be supplied where required.
5. A feedback email and required beta review contact information must be provided.
6. The `What to Test` instructions must identify meaningful test scenarios.
7. Functional review credentials or demo instructions must be supplied where necessary.
8. The build must be submitted for TestFlight App Review when required.
9. External testers must not be told that testing is available before the build is eligible and approved.
10. Once approved, testers can be invited by email or public link.
11. Automatic or manual tester notification must be handled appropriately.
12. At least one external tester must be able to accept an invitation and install the build.
13. Any review rejection must be documented and resolved.

**Limits and Constraints:**

- Apple supports up to 10,000 external testers per application.
- The first external-testing build generally requires a full beta review.
- Later builds may require additional review.
- TestFlight App Review is separate from final App Store review.
- Builds must remain within their TestFlight availability period.

**Expected Result:** Approved external testers can install and validate the intended beta build.

## AC-16 — App Store Submission Preparation

**Given** the build has passed internal release requirements,

**When** the release manager prepares the application for final App Store submission,

**Then** the required product-page and review information must be completed.

**Required or Applicable Items:**

- Application name.
- App subtitle and description, as applicable.
- Keywords.
- Primary and secondary app categories as appropriate.
- App icon.
- Required iPhone screenshots.
- Required iPad screenshots if iPad is supported.
- App previews, if desired.
- Support URL.
- Privacy policy URL.
- App privacy disclosures.
- Age rating questionnaire.
- Content rights information.
- Copyright and required contact information.
- Release version metadata.
- Export compliance declarations.
- App Review contact information.
- Demo account credentials or review instructions where needed.
- Pricing and regional availability.
- Required business, tax, banking, or paid-app agreements where applicable.
- In-App Purchase or subscription configuration where applicable.
- Appropriate digital goods, regional compliance, and regulated-service declarations where applicable.
- Release method or scheduling preferences.

**Given** the intended build is selected for App Store review,

**When** the authorized release manager initiates submission,

**Then** the application must meet all of Apple's current submission prerequisites.

**Submission Steps:**

1. Open App Store Connect.
2. Select the application.
3. Open the intended iOS version.
4. Complete mandatory metadata.
5. Attach the correct processed build.
6. Resolve all missing information and warnings that block submission.
7. Select Add for Review.
8. Review the prepared submission.
9. Select Submit for Review.
10. Monitor Apple's submission status and any review messages.

**Expected Result:** The app version can be submitted for final review. Approval and publication are controlled by Apple and are not guaranteed by a successful upload.

---

# 4. End-to-End Developer Execution Guide

This is the reference manual procedure for a typical Flutter project using the default Runner scheme.

## Step 1 — Verify Toolchain

```bash
flutter doctor -v
flutter --version
xcodebuild -version
xcode-select -p
```

Resolve blocking issues before continuing.

## Step 2 — Open Project and Resolve Dependencies

```bash
cd /path/to/flutter_project

flutter pub get
flutter analyze
flutter test
```

If CocoaPods requires manual dependency synchronization:

```bash
cd ios
pod install
cd ..
```

Flutter commonly manages CocoaPods integration during iOS builds, so manual installation is not necessary for every release.

Use `flutter clean` only when there is a reason to reset generated build artifacts; it is not mandatory for every release.

## Step 3 — Update Release Version

In `pubspec.yaml`:

```yaml
version: 1.0.0+1
```

For later releases, increment the version or build number as required.

Record the exact source-control commit used for the release.

## Step 4 — Open Xcode

```bash
open ios/Runner.xcworkspace
```

Review:

- Runner target.
- General settings.
- Signing & Capabilities.
- Build Settings.
- Deployment target.
- Bundle identifier.
- Release configuration.
- Info.plist.
- App icons and launch screen.
- Native entitlements.

## Step 5 — Verify Apple Signing

Navigate to:

`Runner → TARGETS → Runner → Signing & Capabilities`

Select the correct Apple Developer team and resolve any signing errors.

Verify the production application identifier and enabled capabilities.

## Step 6 — Verify Native Permissions

Review:

```text
ios/Runner/Info.plist
```

Ensure every protected native resource used by the app has the correct permission declaration.

Test the permission dialogs on a compatible physical device.

## Step 7 — Verify Production Configuration

Check the intended release values:

- Backend API base URL.
- Environment selection.
- Firebase or other service configuration.
- App link and deep link domains.
- Push notification configuration.
- Payment environment.
- Analytics configuration.
- Production feature flags.
- Certificate and domain dependencies.

If the project uses flavors, confirm that the selected Flutter flavor, Xcode scheme, bundle ID, provisioning profile, and App Store Connect app record all correspond to the same environment.

Avoid embedding confidential values in Dart defines or other client application resources; values compiled into a mobile app must be considered extractable.

## Step 8 — Create the Archive

**Preferred Flutter CLI path:**

```bash
flutter build ipa --release
```

**Optional version override:**

```bash
flutter build ipa --release \
  --build-name=1.0.0 \
  --build-number=1
```

**Optional project-specific flavor:**

```bash
flutter build ipa --release \
  --flavor production \
  --build-name=1.0.0 \
  --build-number=1
```

Use the flavor command only if the project has an appropriately configured production flavor and Xcode scheme.

**Alternative Xcode path:**

1. Open Runner workspace.
2. Choose the correct scheme.
3. Select a generic iOS device destination.
4. Select Product → Archive.
5. Inspect the new archive in Organizer.

Do not run both paths unnecessarily; they are alternative methods to create a release archive.

## Step 9 — Inspect Output

For the Flutter CLI path:

```bash
ls -lh build/ios/archive/
ls -lh build/ios/ipa/
```

Confirm the expected archive and IPA exist.

Verify that files are nonempty and correspond to the expected build.

## Step 10 — Validate and Upload

In Xcode Organizer:

1. Select the intended archive.
2. Use Validate App when available.
3. Resolve blocking errors.
4. Select Distribute App or the equivalent distribution control for the installed Xcode version.
5. Choose the intended App Store Connect upload workflow.
6. Review the signing and distribution settings.
7. Confirm application identity.
8. Upload.
9. Record successful completion.

**Alternative:** Upload a correctly exported App Store IPA using Apple Transporter.

## Step 11 — Verify App Store Connect

Open:

`https://appstoreconnect.apple.com/`

Navigate to:

`Apps → Your App → TestFlight → iOS Builds`

Check:

- Correct application.
- Correct version.
- Correct build number.
- Processing and upload statuses.
- Any warnings.
- TestFlight availability.
- Export compliance.
- Tester eligibility.

Do not mark the task complete only because the local upload tool displayed success.

## Step 12 — Make the Build Available to QA

1. Create or select an internal TestFlight group.
2. Assign the processed, eligible build.
3. Add the required testers.
4. Enter `What to Test`.
5. Notify testers when necessary.
6. Install the build using TestFlight.
7. Perform release smoke tests.
8. Record pass/fail results.
9. Track feedback and release-blocking defects.

For external testing, complete the additional TestFlight App Review workflow.

---

# 5. QA Test Cases

| ID | Test scenario | Expected result |
|---|---|---|
| TC-01 | Verify macOS, Xcode, Flutter and CocoaPods environment | Required dependencies available |
| TC-02 | Validate Apple Developer account and team | Correct team and permissions |
| TC-03 | Check App Store Connect application record | App record exists |
| TC-04 | Compare registered Bundle ID with Xcode | Exact identifier match |
| TC-05 | Verify version in pubspec and resulting build | Correct marketing version |
| TC-06 | Verify build number | Correct unique build identifier |
| TC-07 | Validate signing configuration | Correct distribution signing |
| TC-08 | Verify app capabilities and entitlements | Entitlements match provisioning |
| TC-09 | Validate native permission strings | All applicable descriptions present |
| TC-10 | Deny native device permissions | App remains stable |
| TC-11 | Verify privacy manifests and third-party SDKs | Applicable requirements satisfied |
| TC-12 | Validate app icon and launch screen | Correct production branding |
| TC-13 | Run static analysis | Agreed release quality gate passes |
| TC-14 | Run automated tests | Required tests pass |
| TC-15 | Generate Flutter release archive | Archive created successfully |
| TC-16 | Generate App Store IPA | Correct IPA created |
| TC-17 | Archive using Xcode directly | Organizer contains valid archive |
| TC-18 | Validate archive for distribution | No blocking validation errors |
| TC-19 | Upload archive to App Store Connect | Upload accepted |
| TC-20 | Verify uploaded build identity | Version, build number and app match |
| TC-21 | Monitor App Store Connect processing | Processing completes successfully |
| TC-22 | Check missing export compliance | Correctly declared or resolved |
| TC-23 | Add build to internal TestFlight group | Group has eligible build |
| TC-24 | Install build using TestFlight | Installation and launch succeed |
| TC-25 | Test production backend connection | Expected production environment |
| TC-26 | Test critical user journeys | No release-blocking failures |
| TC-27 | Test external beta review workflow | Review and approval handled |
| TC-28 | Confirm public submission metadata | Mandatory information complete |
| TC-29 | Attempt duplicate build upload | Duplicate rejected or blocked appropriately |
| TC-30 | Simulate interrupted upload | Clear failure and safe retry procedure |
| TC-31 | Verify release evidence | Archive, commit, build ID and QA evidence recorded |
| TC-32 | Validate symbol files if applicable | Required debugging symbols retained |

## Example Detailed QA Case

**Test Case:** TC-20 — Verify Uploaded Build Identity

**Preconditions:**

- A release archive has been uploaded.
- The App Store Connect app record exists.
- The tester has access to the app record.

**Test Steps:**

1. Open App Store Connect.
2. Navigate to Apps.
3. Select the intended application.
4. Select TestFlight.
5. Open the iOS build list.
6. Locate the uploaded release version.
7. Compare the listed version with the release record.
8. Compare the build number with the generated archive.
9. Confirm that the build belongs to the intended app.
10. Review upload processing details.

**Expected Result:**

The exact intended version and build number appear in App Store Connect, and the build completes processing without unresolved blocking errors.

**Pass Condition:** Correct build identity and successful processing.

**Fail Condition:** Incorrect application, version mismatch, missing build, failed processing, or unresolved blocking issue.

---

# 6. Failure Handling and Recovery

| Failure | Probable cause | Required response |
|---|---|---|
| Xcode unavailable | No macOS build environment | Use a supported Mac |
| Flutter doctor reports issues | Missing dependency or configuration | Correct environment |
| CocoaPods installation fails | Dependency or tooling conflict | Review Podfile, lockfile, and dependency compatibility |
| No signing certificate | Signing configuration incomplete | Configure authorized distribution identity |
| Profile mismatch | Wrong App ID, team, or entitlements | Correct signing and provisioning |
| Archive unavailable | Compilation or native integration issue | Review Xcode build logs |
| IPA export fails | Export or signing configuration error | Review distribution configuration |
| Invalid Bundle ID | App record mismatch | Correct the identifier and archive |
| Duplicate build number | Build identifier previously uploaded | Increment the build number and rebuild |
| Unsupported SDK | Xcode or SDK below Apple's minimum | Update supported build toolchain |
| Missing permission usage string | Info.plist incomplete | Add accurate required description and rebuild |
| Privacy manifest validation fails | Missing or invalid declaration | Correct application or SDK privacy metadata |
| App upload authentication fails | Account, role or session issue | Verify access and reauthenticate |
| Upload network failure | Connection interrupted | Inspect delivery history and retry as appropriate |
| Build remains processing | Apple processing not completed | Monitor; escalate if unusually prolonged |
| Missing Compliance | Export information incomplete | Complete Apple compliance workflow |
| Build unavailable to testers | Status, group, profile, or review issue | Check eligibility and group configuration |
| External build rejected | TestFlight App Review issue | Review feedback and correct submission |
| Release-only crash | Production configuration or optimization issue | Reproduce using release/TestFlight build |
| Missing symbols | Symbol artifacts not preserved/uploaded | Recover matching symbols and correct symbolication setup |
| App Store review rejection | Guideline or metadata issue | Resolve review feedback and resubmit |

### Recovery Principles

1. Do not modify and repackage an already signed release without repeating the applicable build, signing, and validation process.
2. Do not assume that a failed upload has been accepted.
3. Check whether Apple has already accepted a build number before attempting a retry.
4. Reuse a build number only when permitted, such as when no successful upload has consumed it.
5. Preserve the failing build's logs and release identifiers.
6. Avoid arbitrary certificate revocation or provisioning changes without assessing their effect on other builds and team members.
7. When source code or build inputs change, create and validate a new release artifact.
8. When a TestFlight defect is fixed, build and upload a new eligible version with an appropriate build number.

---

# 7. Technical and Non-Functional Requirements

## Security

- Production builds must be code signed.
- Signing assets must be protected.
- Private certificates and API keys must not be committed to source control.
- API secrets must not be embedded in the application.
- Production API traffic must use appropriate transport security.
- Permission usage must be minimized.
- Sensitive user data must be handled according to the application's security requirements.
- Third-party SDKs must be reviewed for known security and compatibility issues.

## Reliability

- The release workflow must produce reproducible artifacts from recorded source revisions.
- Build failures must be identifiable through logs.
- Upload failures must not be treated as successful releases.
- Required smoke tests must pass on the TestFlight build.
- Release-blocking defects must be resolved before final review.

## Maintainability

- Signing and build configuration must be documented.
- Environment-specific settings must be identifiable.
- Release versioning must follow a documented policy.
- Native project changes must be version-controlled where appropriate.
- A new team member with appropriate access must be able to repeat the deployment procedure.

## Observability

- Archive and upload logs must be available.
- Build version, source commit and upload status must be recorded.
- Crash-reporting and symbolication support must be verified if implemented.
- TestFlight tester feedback and crash information must be reviewed.

## Compatibility

- The release must support its declared minimum iOS version.
- Supported device types must be tested.
- Framework and plugin compatibility must be verified.
- Any accessibility, localization, or right-to-left requirements must be satisfied.

---

# 8. Technical Sub-Tasks for Sprint Planning

| Task | Owner | Deliverable |
|---|---|---|
| IOS-01 Configure macOS build environment | iOS Developer | Valid Flutter/Xcode toolchain |
| IOS-02 Verify Developer Program access | Account Holder | Authorized signing access |
| IOS-03 Register app identifier | iOS Developer / Account Holder | Registered Bundle ID |
| IOS-04 Create App Store Connect record | Release Manager | iOS app record |
| IOS-05 Configure Xcode target | iOS Developer | Correct project settings |
| IOS-06 Configure signing and capabilities | iOS Developer | Valid distribution signing |
| IOS-07 Configure version and build number | iOS Developer | Traceable release identity |
| IOS-08 Audit Info.plist and permissions | iOS Developer | Complete native declarations |
| IOS-09 Audit privacy and SDK compliance | iOS Developer | Compliance checklist |
| IOS-10 Prepare production resources | iOS Developer / Designer | Final icon and launch assets |
| IOS-11 Validate release configuration | iOS Developer | Correct production endpoints |
| IOS-12 Execute automated validation | Developer / QA | Passing release tests |
| IOS-13 Generate release archive | iOS Developer | `.xcarchive` |
| IOS-14 Generate or export IPA | iOS Developer | `.ipa`, when applicable |
| IOS-15 Validate archive | iOS Developer | Valid distribution package |
| IOS-16 Upload build | iOS Developer | App Store Connect upload |
| IOS-17 Verify Apple processing | iOS Developer | Successfully processed build |
| IOS-18 Configure internal TestFlight | Release Manager | Internal test access |
| IOS-19 Execute TestFlight smoke testing | QA Engineer | QA report |
| IOS-20 Configure external testing | Release Manager | External testing availability |
| IOS-21 Complete App Store metadata | Release Manager | Submission-ready app record |
| IOS-22 Submit for App Review | Authorized Release Manager | Recorded submission |
| IOS-23 Document release evidence | Release Manager | Release audit record |

**Dependencies:** App registration and signing must be ready before successful production distribution. Build processing must finish before the applicable TestFlight actions. Final App Store submission requires the correct eligible build and mandatory app information.

---

# 9. Definition of Ready

The story may enter implementation when:

- [ ] Flutter project is available in source control.
- [ ] Release branch or release candidate is identified.
- [ ] Required Mac and Xcode environment is available.
- [ ] Apple Developer Program membership is active.
- [ ] Authorized team and App Store Connect access are available.
- [ ] App Bundle ID is agreed.
- [ ] Target production environment is identified.
- [ ] Required native permissions are documented.
- [ ] Required app capabilities are identified.
- [ ] TestFlight testing scope is defined.
- [ ] Required QA resources and test devices are available.
- [ ] Release owner and responsible roles are assigned.

---

# 10. Definition of Done

The primary release story is complete when:

- [ ] Required toolchain meets Apple's upload requirements.
- [ ] App Store Connect record exists.
- [ ] Bundle ID is correctly registered and configured.
- [ ] Production signing works.
- [ ] Entitlements and capabilities are validated.
- [ ] Version and build number are correct.
- [ ] Native permission declarations are complete.
- [ ] Required privacy manifest and compliance checks pass.
- [ ] App icon and launch resources are production-ready.
- [ ] Static analysis and mandatory automated tests pass.
- [ ] Release configuration is validated.
- [ ] Release archive is generated successfully.
- [ ] IPA is generated when the selected workflow requires one.
- [ ] Archive validation passes.
- [ ] Upload completes successfully.
- [ ] App Store Connect processing completes.
- [ ] Correct version and build number appear in TestFlight.
- [ ] No blocking compliance or binary issues remain.
- [ ] Intended internal tester group can access the build.
- [ ] Required release smoke tests pass on the TestFlight build.
- [ ] Logs, symbols, and release evidence are retained as applicable.
- [ ] The release owner approves the build for the next stage.

**Additional Definition of Done for External TestFlight:**

- [ ] External testing metadata is complete.
- [ ] TestFlight App Review approval is obtained where required.
- [ ] Approved external testers can install the build.

**Additional Definition of Done for Final App Store Submission:**

- [ ] App Store metadata and required screenshots are complete.
- [ ] Required privacy, compliance, and age-rating information is complete.
- [ ] Correct processed build is attached.
- [ ] App Review information is complete.
- [ ] Submission is successfully sent to Apple.
- [ ] Submission reference and status are recorded.

**Important:** Final Apple approval and public release are separate external milestones. They should not be represented as guaranteed outcomes of the engineering build-and-upload story.

---

# 11. Required Release Evidence

Maintain a release record containing:

| Field | Required information |
|---|---|
| Application | Approved app name |
| Bundle Identifier | Registered bundle ID |
| Apple Developer Team | Correct team identifier |
| Marketing Version | Example: `1.0.0` |
| Build Number | Example: `1` |
| Flutter Version | Exact toolchain version |
| Xcode Version | Exact build tool version |
| iOS SDK | Exact SDK version |
| Deployment Target | Minimum supported iOS version |
| Source Revision | Git commit SHA or tag |
| Release Environment | Production |
| Archive | Generated archive reference |
| IPA | Exported IPA reference, if applicable |
| Signing | Authorized distribution configuration |
| Upload Result | Successful or failed |
| Processing Result | Complete or failed |
| TestFlight Status | Applicable beta-build state |
| QA Result | Approved or blocked |
| Release Owner | Responsible person or team |
| Release Date | Actual release operation date |
| Known Issues | Outstanding nonblocking issues and decisions |

Store sensitive signing material separately using an approved secure credential-management process.

---

# 12. Out of Scope Unless Separately Requested

The core build-and-upload story does not automatically include:

- Building the Android application.
- Creating new application features.
- Rebuilding the app's architecture.
- Adding new payment integrations.
- Creating a full CI/CD pipeline.
- Migrating the Apple Developer account.
- Publishing to alternative marketplaces.
- Automatically approving the application on Apple's behalf.
- Making the application publicly available before business approval.

These can be linked technical stories when needed.

---

# 13. Official Technical References

1. [Flutter — Build and release an iOS app](https://docs.flutter.dev/deployment/ios)
2. [Apple — Upload builds to App Store Connect](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
3. [Apple — Create a new app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
4. [Apple — Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
5. [Apple — Xcode SDK and System Requirements](https://developer.apple.com/xcode/system-requirements)
6. [Apple — Build Upload Statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/build-upload-statuses)
7. [Apple — App Build Statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/app-build-statuses)
8. [Apple — TestFlight Overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
9. [Apple — Invite External Testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
10. [Apple — Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
11. [Apple — Third-Party SDK Requirements](https://developer.apple.com/support/third-party-SDK-requirements/)
12. [Apple — Export Compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
13. [Apple — Manage App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
14. [Apple — Screenshot Specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
15. [Apple — Submit an App for Review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)

**Final Acceptance Statement**

The Flutter iOS release process is considered technically successful when a correctly configured, signed, validated, production-ready build has been accepted and processed by App Store Connect, is accessible to the intended TestFlight testing audience, and has passed the required release-quality checks. Final App Store submission, approval, and publication must be tracked independently according to the release plan.
