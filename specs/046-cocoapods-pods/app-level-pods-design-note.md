# Design Note: App-Level Podfile Pods and App Extensions (Q8)

**Date**: 2026-11-16  
**Status**: Deferred to dedicated future feature (feature candidate `047-app-level-pods`)  
**Context**: Feature 046 focuses on Flutter plugin pod dependencies without CocoaPods/Xcode runtime. This note records architectural considerations for app-level pods declared directly in `ios/Podfile`.

---

## 1. Background

In standard Flutter projects, developers occasionally add CocoaPods pods directly in `ios/Podfile` rather than through Flutter plugin `.podspec` files:
```ruby
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__file__))

  # Direct app-level pods
  pod 'Firebase/Analytics'
  pod 'Google-Mobile-Ads-SDK', '~> 11.0'
end

target 'OneSignalNotificationServiceExtension' do
  use_frameworks!
  pod 'OneSignalXCFramework', '>= 5.0.0', '< 6.0'
end
```

---

## 2. Architectural Analysis

### 2.1 Podfile Target Discovery
- The engine will need a Podfile parser extracting targets:
  - Main app target: `Runner`
  - Extension targets: e.g. `OneSignalNotificationServiceExtension`, `ShareExtension`
- Pod declarations within each target must be resolved separately or as a union where shared dependencies align versions.

### 2.2 Extension Target Compilation in SwiftPM
- SwiftPM does not natively produce iOS Application Extensions without specific linker flags and target definitions (`.executableTarget` vs extension bundles).
- Converted pods for extensions must be linked against the extension binary rather than `libFlutterPluginsGenerated.dylib`.

### 2.3 Framework Embedding and App Extension Constraints
- App extensions cannot use certain iOS APIs (`sharedApplication`, background tasks) and have strict memory limits (e.g. 15–30 MB for notification service extensions).
- Frameworks shared between the main app and an extension must either be dynamically linked in the main app's `Frameworks/` directory with `@rpath` configured in the extension, or statically compiled into both.

---

## 3. Scope Recommendation

- Keep Feature 046 focused on plugin-declared pods (the vast majority of Flutter ecosystem use-cases).
- Direct app-level pods and app extensions should be specified in a separate, dedicated feature (e.g. `047-app-level-pods`) following real-world evidence from 046 deployment.
