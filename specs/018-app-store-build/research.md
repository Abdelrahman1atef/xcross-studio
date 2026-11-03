# Research: 018

## R1 Distribution certificate reuse
- **Decision:** like Codemagic's `fetch-signing-files --certificate-key`: a PEM private key
  (`XCROSS_CERTIFICATE_PRIVATE_KEY` in CI, else saved under the signing identity) identifies the certificate; a team
  `DISTRIBUTION`/`IOS_DISTRIBUTION` certificate whose modulus matches is reused, else one is created from a CSR of
  that key.
- **Rationale:** teams allow few distribution certificates; creating one per run (or revoking) breaks other machines.

## R2 Archive layout
- **Decision:** `Runner.xcarchive/Info.plist` (`ArchiveVersion` 2, `CreationDate`, `Name`, `SchemeName`,
  `ApplicationProperties {ApplicationPath, CFBundleIdentifier, CFBundleShortVersionString, CFBundleVersion,
  SigningIdentity, Team}`), `Products/Applications/<app>.app`, `dSYMs/<binary>.dSYM`.
- **Rationale:** the layout Xcode and `flutter build ipa` produce; Transporter and crash services read it.

## R3 DT keys
- **Decision:** `DTSDKBuild`/`DTPlatformBuild` = SDK `SystemVersion.plist` `ProductBuildVersion`; `DTXcode` = the
  Xcode version as `MMmp` (26.1 → `2610`); `DTXcodeBuild` = Xcode `version.plist` `ProductBuildVersion`;
  `DTCompiler` = `com.apple.compilers.llvm.clang.1_0`. `BuildMachineOSBuild` is not written (there is no macOS build).
- **Rationale:** Apple's processing reads these to decide the toolchain and SDK; they must be the real values of the
  SDK the binary was linked against.

## R4 Release-check tables
- **Plugin permissions:** camera (`image_picker`, `camera`, `mobile_scanner`), photos (`image_picker`,
  `photo_manager`, `gal`), location (`geolocator*`, `location`), microphone (`record`, `speech_to_text`,
  `flutter_sound`), contacts (`flutter_contacts`, `contacts_service`), Bluetooth (`flutter_blue_plus`), Face ID
  (`local_auth`), calendars (`device_calendar`), motion (`sensors_plus`), tracking (`app_tracking_transparency`).
- **Required-reason API symbols:** file timestamp (`NSFileCreationDate`, `NSFileModificationDate`,
  `NSURLContentModificationDateKey`, `getattrlist`), system boot time (`systemUptime`, `mach_absolute_time`), disk
  space (`NSFileSystemFreeSize`, `volumeAvailableCapacityKey`, `statfs`), active keyboards (`activeInputModes`), user
  defaults (`NSUserDefaults`).
- **SDKs needing a privacy manifest** (from Apple's list, the ones Flutter apps bundle): Firebase*, GoogleUtilities,
  GoogleDataTransport, nanopb, FBLPromises, Flutter, AppAuth, GTMSessionFetcher, OneSignal, SDWebImage, Alamofire,
  Kingfisher, Lottie, RxSwift, SnapKit, Starscream, SwiftyJSON, connectivity_plus, device_info_plus, file_picker,
  fluttertoast, image_picker_ios, package_info_plus, path_provider_foundation, shared_preferences_foundation, sqflite,
  url_launcher_ios, webview_flutter_wkwebview.
