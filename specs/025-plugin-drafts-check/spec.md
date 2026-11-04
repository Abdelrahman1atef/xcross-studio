# Feature Specification: Plugin drafts during the build, a check before compiling

**Feature Branch**: `025-plugin-drafts-check` (work lands on `008-json-events-gui`) | **Created**: 2026-11-04 | **Status**: Implemented

**Input**: xcross builds Swift packages only. A plugin that ships just a podspec has to get a `Package.swift` draft from
`xcross plugin shim` by hand, and until then its native code is left out and the app fails when it calls the plugin.
The developer asked for that to happen during the build, for problems to show before minutes of compiling, and for a
build that stops after a compile error to end instead of hanging. Checking push on a client app found two more build
problems, fixed here: plugins registered after launch finished, and plugins built for debugging in App Store builds.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A podspec-only plugin builds without a manual step (Priority: P1)

A developer adds a plugin that ships only a podspec and builds. xcross drafts its `Package.swift` into the project,
says so, and builds it.

**Independent Test**: a project with a podspec-only plugin and no `xcross_overrides/` builds, and the folder now holds
the draft.

**Acceptance Scenarios**:

1. **AC-025-1**: When a build starts, a plugin with a podspec and no `Package.swift` gets
   `xcross_overrides/<plugin>/<version>/Package.swift` with the same files `xcross plugin shim` writes, and the build
   uses it. `[build.plugin_drafted]` names the file and what to review.
2. **AC-025-2**: A plugin needing a pod with no known Swift package is not drafted: a draft could not link it.
   `[build.plugin_unknown_pods]` names the plugin and the pods, and its native code is left out as before. The build
   goes on.
3. **AC-025-3**: Nothing else is touched: a plugin with its own `Package.swift` or no native code, and any override
   folder already there, even one that does not apply to this version. `XCROSS_PLUGIN_DRAFTS=off` turns drafting off.

### User Story 2 - Problems show before compiling (Priority: P1)

**Acceptance Scenarios**:

1. **AC-025-4**: `xcross plugin check [--project <dir>]` says what a build will do with each iOS plugin, without
   compiling or writing anything, and fails with `[plugin.unknown_pods]` when a build would leave one out. A build
   makes the same decisions first, before it compiles anything.

### User Story 3 - A build stuck after a compile error ends (Priority: P1)

After a compile error, `swift build` could stay alive with a compiler still running, and the build waited for hours.

**Acceptance Scenarios**:

1. **AC-025-5**: On Windows, `swift build` that printed an error and then nothing for 5 minutes is ended with its
   compilers, and the build fails showing the errors and saying why it was ended. Output that keeps coming means it is
   still working. Once it has exited, a compiler left holding its pipes does not keep the build waiting.

### User Story 4 - Push works from App Store builds (Priority: P1)

xcross builds plugins with SwiftPM's debug configuration, which defines `DEBUG` and turns optimization off.
`firebase_messaging` marks the APNs token as sandbox under `#ifdef DEBUG`, which is wrong for an App Store profile.

**Acceptance Scenarios**:

1. **AC-025-6**: `--export-method app-store` builds plugins without `DEBUG` and with optimization (`-UDEBUG -O2` for C
   languages, `-O` for Swift), in a workspace of their own, so the everyday build is not thrown away. `xcross flutter
   clean` removes it. `XCROSS_PLUGIN_BUILD=distribution` does the same for an app signed for distribution outside
   xcross. Other builds are unchanged: they are signed for development, whose tokens are sandbox tokens.

### User Story 5 - Plugins are registered in time (Priority: P1)

`firebase_messaging` connects to push when it hears `UIApplicationDidFinishLaunchingNotification`. xcross makes its
window in code, at scene connection, after that notification, and registered plugins on the window's engine. The plugin
never connected, iOS never gave it an APNs token, and the app had no FCM token, while Firebase features needing only
the network worked.

**Acceptance Scenarios**:

1. **AC-025-7**: The generic runner starts its engine and registers plugins during launch, and the window uses that
   engine. So does the project runner for an app delegate that registers with `self` (feature 007, AC-007-6). An app
   delegate on Flutter's UIScene template still registers when its engine is made, as under Xcode.
2. **AC-025-8** (device, `device-check.md`): on an iPhone, an app using `firebase_messaging` has an FCM token: it
   appears in its login request.

## Assumptions

- A draft that does not compile fails the build with the compiler's errors. That is better than an app that fails at
  run time, and the developer can edit or delete the draft.
- Drafts belong to the project and are meant to be reviewed and committed.
- Plugins stay in SwiftPM's debug configuration with flags added, because moving to its release configuration would
  change the layout the build reads its results from.
- Generating packages for unknown pods from CocoaPods' published pod details stays out of scope for now.

## Success Criteria *(mandatory)*

- **SC-025-1**: A podspec-only plugin whose pods are known builds with no manual step.
- **SC-025-2**: Plugins a build will leave out are named within seconds of the build starting.
- **SC-025-3**: No build stays stuck for more than 5 minutes after its last output following a compile error.
