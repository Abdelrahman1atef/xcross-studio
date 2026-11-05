# Feature Specification: See, add and remove permissions and capabilities, like Xcode

**Feature Branch**: `027-permissions` (work lands on `008-json-events-gui`) | **Created**: 2026-11-05 | **Status**: Implemented

**Input**: A developer who builds without Xcode has no Info tab and no Signing & Capabilities tab. A missing purpose
string (Apple 90683 for doctory's `NSLocationAlwaysAndWhenInUseUsageDescription`) or a camera key left out is only found
in a build, or after an upload. The developer asked to see, add and remove permissions the way Xcode does, to make it
easy, and (answering the scope question) for capabilities as well as purpose strings.

## Scope

- `xcross permissions list|set|remove` edits the `NS…UsageDescription` keys (and `NFCReaderUsageDescription`) of
  `ios/Runner/Info.plist`.
- `xcross capabilities list|add|remove` edits the entitlements file and, for Background Modes, `UIBackgroundModes` of
  `Info.plist`.
- A Project page in the Studio (tabs Permissions, Capabilities, Plugins) drives both through the CLI.
- Not in scope: writing `CODE_SIGN_ENTITLEMENTS` into the Xcode project (no pbxproj writer exists); iCloud and network
  extension capabilities (structured values); `permission_handler`'s per-permission keys (the editor offers the key, the
  plugin table does not guess which ones an app uses).

## Acceptance Scenarios

1. **AC-027-1** `list` shows the top-level keys only: a key nested inside another dictionary is not a permission.
2. **AC-027-2** `set` adds a key before the closing `</dict>` or changes its value in place. Comments, key order,
   indentation, `$(VARIABLES)` and the file's line endings (LF or CRLF) are kept; values are XML-escaped.
3. **AC-027-3** `remove` takes the key and its value and nothing else; removing a key that is not there changes nothing
   (`changed: false`). `set` then `remove` returns the original text.
4. **AC-027-4** A binary plist or a file whose root is not a dictionary is refused with `permissions.binary_plist` or
   `permissions.bad_plist`; the file is not touched.
5. **AC-027-5** `list` reports each purpose string with its status (`ok`, `placeholder`, `unknown_key`), the plugins that
   use it, and the keys the project's plugins need and `Info.plist` lacks (`missing`), plus the catalog of keys that can
   be added with a starting sentence. The placeholder rule is the release check's (one function).
6. **AC-027-6** Every change copies the old file to `.xcross/permission-backups/<stamp>/<relative path>` first and
   reports it (`backup`). A key that is not a purpose string (`permissions.bad_key`) or an empty sentence
   (`permissions.empty_value`) is refused. A placeholder sentence is written with a note.
7. **AC-027-7** `capabilities list` says which capabilities are on, whether the entitlements file exists and whether the
   Xcode project names it. `add` writes the key with the right shape (flag, choice, list), creating the file when needed;
   list values add up (domains, groups, modes) and a missing value is `capabilities.value_required`. `remove` turns it
   off, or takes out just the `--value`s given. Adding says what is left to do: the App ID capability xcross switches on
   when it signs, and `CODE_SIGN_ENTITLEMENTS` for Xcode when the project does not name the file. A file the project
   names is the one that is edited.
8. **AC-027-8** Catalogs agree with the rest: every key the release check knows is in the permission catalog, each
   suggested sentence passes the placeholder rule, and each capability's App Store Connect type is the one
   `AscCapabilities` maps its key to.
9. **AC-027-13** In the Studio, a missing permission shows as a card with "Add with a starting sentence" (one click,
   backed up) and "Open".
10. **AC-027-14** The Permissions tab lists each key with its name, status and an editable sentence (Save), and adds one
    from a searchable catalog with its starting sentence.
11. **AC-027-15** Removing asks first and names the backup folder.
12. **AC-027-16** The Capabilities tab has a switch per capability, chips for background modes, an input for domains and
    groups, and shows the notes the CLI returned.

13. **AC-027-20** (camera permission under xcross) `permission_handler_apple` compiles a permission out unless its
    `PERMISSION_X` macro is set, and a compiled-out permission answers "denied" without asking. CocoaPods builds take the
    macros from the Podfile; xcross builds plugins with Swift Package Manager and did not. When the plugin build starts,
    xcross reads the project's Info.plist purpose strings and the Podfile's `PERMISSION_X=1|0` lines and gives the plugin
    the environment variable it reads for each macro (the table is the one in the plugin's own `Package.swift`). A Podfile
    `=0` turns a permission off even with the string present. The variables are part of the plugin build's cache key, and
    the build says which permissions it switched on. Found on `bsat`: the camera key was in Info.plist and
    `PERMISSION_CAMERA=1` in the Podfile, yet the manifest printed "Could not locate the host app, so every iOS permission
    has been compiled out" (probed with `swift package dump-package`: no variable gives `PERMISSION_CAMERA=0`, the variable
    gives `1`; pointing at the Info.plist did not help on the Windows toolchain).
14. **AC-027-21** (older drafts) A plugin built from a podspec draft (permission_handler_apple 9.4.x, Objective-C) reads its
    macros only from the draft's compile settings. The drafter writes `.define("PERMISSION_X", to: "1")` for each switch the
    project declares, and `plugin status` reports `permission_macros_missing` (action: regenerate) for a draft that lacks one
    the project now declares: doctory's draft had none, so every permission answered "denied".

## Result on doctory (read-only)

`xcross permissions list` shows its six purpose strings and no missing key; `capabilities list` shows Push,
Background Modes and Associated Domains on. Neither wrote anything.
