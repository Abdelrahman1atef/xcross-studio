# Data model: 016

- **BundleIdMode** `original | prefixed` — saved as `bundle_id` (`xcross:` in `pubspec.yaml` or
  `xcross_project.yaml`); override `XCROSS_BUNDLE_ID`. Resolution order in spec AC-016-1.
- **PushSignals** `{usesFirebaseMessaging: bool, remoteNotificationMode: bool}` — `reason` is the first that holds;
  none → nothing inferred.
- **MapsKey** `{key: String?, source: String (file name, or "Info.plist <KEY>"), unresolved: bool}`.
- **RunnerMode** `auto (default) | shim | project` from `XCROSS_RUNNER`.
- **Push readiness checks** (doctor `check` events, section "Push notifications"): `Push entitlement`,
  `Push App ID`, `Firebase config`.
