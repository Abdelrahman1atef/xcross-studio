# Tasks: 027 permissions

- [X] T001 `PlistText`: text-level top-level key editor (`studio_ext/src/shared/permissions/plist_text.dart`).
- [X] T002 Catalogs of permissions and capabilities, shared placeholder rule (`ReleaseTables.isUsageKey`,
  `isPlaceholderPurpose`).
- [X] T003 `ProjectPlists` (locate, read, write with a backup), `PermissionsReport`.
- [X] T004 `xcross permissions` and `xcross capabilities` (`lib/shared/permissions/permissions_command.dart`), registered
  in `runner.dart`.
- [X] T005 Studio: `project_events.dart`, commands, Project page with Permissions and Capabilities tabs.
- [X] T006 Tests: `plist_text_test`, `permissions_command_test`, Studio `project_test`.
- [X] T007 Camera permission of `D:\Programing\flutterApp\DR\bsat` (the user's note): checked; cause found (AC-027-20).
- [X] T008 `PermissionMacros` (`studio_ext/shared/plugins/permission_macros.dart`), the environment for the plugin build
  (`SwiftPmProcessPolicy.projectEnvironment`, the build cache key), defines in drafts, `permission_macros_missing`.
- [ ] T009 Device row: build bsat, open the AR camera check on the iPhone X, and see the camera prompt appear.
