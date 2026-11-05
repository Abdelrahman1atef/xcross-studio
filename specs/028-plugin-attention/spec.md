# Feature Specification: Plugin actions the developer cannot miss

**Feature Branch**: `028-plugin-attention` (work lands on `008-json-events-gui`) | **Created**: 2026-11-05 | **Status**: Implemented

**Input**: When a plugin needs the developer (an override left behind by an upgrade, a draft written before xcross copied
the privacy manifest, a draft nobody looked at) the developer only saw a build warning or a Release step 6 line, and had to
know to open the Plugins page. doctory's `fluttertoast`, `flutter_secure_storage` and `permission_handler_apple` drafts
lacked their privacy manifests and nothing before the IPA said so. The developer asked for the flow to be visible and
improved. Chosen: visible alerts with a one-click fix after a backup; a file the developer wrote is never rewritten
without asking.

## Acceptance Scenarios

1. **AC-028-1** `xcross plugin status --json` (`plugin_status`) gives, per plugin: name, version, kind (`swiftpm`, `draft`,
   `hand_written`, `podspec_only`, `no_ios_code`), the override folder, whether the draft differs from what xcross would
   write now (`edited`), the problems, the `action` (`regenerate`, `review`, `manual`) with its command, and
   `canRegenerate`. A podspec-only plugin needing a pod nobody knows is `unknown_pods`.
2. **AC-028-2** A draft xcross wrote waits for review (`review_pending`) until `xcross plugin ack <plugin>`.
3. **AC-028-3** A draft that lacks a file the plugin ships and the draft declares (the privacy manifest) is
   `manifest_missing`; `plugin shim --force` rewrites it after copying the old files to
   `.xcross/plugin-backups/<stamp>/<plugin>/<version>/`.
4. **AC-028-4** An override folder for another version of the plugin is `stale` (a build skips it), in `status` and in
   `plugin check`, which now fails with `plugin.override_stale`.
5. **AC-028-5** A `Package.swift` without xcross's DRAFT header is `hand_written`, never `canRegenerate`; `shim --force`
   refuses it (`plugin.hand_written`) unless `--replace-hand-written`, which backs it up first.
6. **AC-028-6** Drafts are recorded in one file at the root of `xcross_overrides/` (`.xcross-drafts.json`), written by
   `plugin shim` and by the build's own drafting; nothing is added to a plugin's folder, which is laid over the plugin at
   build time.
7. **AC-028-7** `ack` names a plugin that does not exist (`plugin.not_found`) or has no draft waiting (`plugin.no_draft`).
8. **AC-028-9** In the Studio the count shows on the Project item of the sidebar (a dot in the compact rail) and as "N to
   do" in the top bar; nothing shows when there is nothing to do.
9. **AC-028-10** Overview lists the items under "Needs your attention", Build & Run under "Before you build", the Project
   page under "To do", and Release step 6 under "Fix it here" when its issues are about manifests or permissions.
10. **AC-028-11** Regenerate asks first, names the backup folder, runs `plugin shim <p> --force`, and the item goes away.
11. **AC-028-12** The Plugins tab keeps listing every plugin with its badge ("Needs action" for one with a problem).

## Notes

- The state is read from `plugin status --json` and `permissions list --json` (`ProjectHealthController`), refreshed when
  the project changes and after a build, run, pub, plugin, permissions, capabilities, project or publish command; never from
  build output. `flutter doctor` does not refresh it.
- Deferred: a `subject` field on build warning events. `BuildWarnings` already has a subject per warning; the NDJSON event
  does not carry it, and the Studio does not need it now that the list comes from `plugin status`.

## Result on doctory (read-only)

`xcross plugin status` reports exactly `flutter_secure_storage`, `fluttertoast` and `permission_handler_apple` as
`manifest_missing` and nothing else.
