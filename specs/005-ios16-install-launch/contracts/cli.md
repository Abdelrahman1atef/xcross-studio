# CLI contract: iOS 15/16 run and `xcross install`

## `xcross flutter run` / `xcross compose run` on iOS 15/16

- **Supported**: iOS 15 and later (was 17). iOS 15/16 run the legacy path.
- **Install**: signed with the saved Apple ID / App Store Connect key, installed over USB (installation_proxy). No
  tunnel and no elevation.
- **Launch**: needs a developer disk image from the user's own Xcode, found through `XCROSS_DDI_DIR` or
  `~/.xcross/DeviceSupport/<major.minor>/` (`DeveloperDiskImage.dmg` + `DeveloperDiskImage.dmg.signature`). xcross
  runs `mounter mount-developer` and then `developer dvt launch`. It never downloads an image.
- **Without an image**: `Installed  Tap the app icon on the iPhone to open it …`, then `Logs  xcross logs --app <id>`;
  exit 0.
- **Debug builds**: `error: [device.legacy_debug_unsupported] …`, with the hint to use `--release` or `--profile`.
  This happens before the build.

## `xcross install <ipa|app> [--udid <id>] [--ddi <dir>] [--no-launch]`

- **`.ipa`**: the single `Payload/*.app` is extracted to a temp folder; paths containing `..` are ignored.
- **`.app`**: copied to a temp folder, so the input is never modified.
- **Then**: precheck → sign + install → open (as above, with `--ddi`). With `--no-launch` it only signs and installs.
- **Errors**:

  | Code | When |
  |---|---|
  | `install.unsupported_input` | not an existing `.ipa` / `.app`, or an unreadable zip |
  | `install.no_app` | not exactly one app, or no or invalid `Info.plist` / `CFBundleIdentifier` |
  | device codes | the 002 device codes (`device.*`) |
