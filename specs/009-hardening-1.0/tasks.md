# Tasks: Hardening for 1.0 (packaging + triage)

G = `apps/studio`.

- [X] T001 G `tool/package.dart`: portable folder + zip (Windows) / tar.gz (Linux) with LICENSE and NOTICE.txt (done
  in 008).
- [X] T002 G `installer/windows/xcross-studio.iss`: Inno Setup per-user installer (done in 008).
- [X] T003 G `linux/packaging/`: app icon (256 px PNG, also used for the Windows `.ico`) and desktop entry
  `dev.xcrossstudio.xcross_studio.desktop` (matches the GTK application id).
- [X] T004 G `tool/package.dart` on Linux: `.deb` (`dpkg-deb --root-owner-group`; `/opt/xcross-studio`,
  `/usr/bin/xcross-studio`, desktop entry, icon; depends on GTK 3 and usbmuxd) and AppImage (`APPIMAGETOOL`).
- [X] T005 CI `studio-gui.yml`: pinned appimagetool 1.9.1 (SHA-256 checked), package checks (`dpkg-deb --info/
  --contents`, AppImage extract + packaged CLI run), upload `.deb` and `.AppImage`.
- [X] T006 Upstream issue triage in `spec.md`; README installation section for the packages.
- [ ] T007 Device check: install the `.deb` / AppImage on Ubuntu 24.04 and run the 008 GUI rows with the iPhone
  (deferred with the other Linux device checks).
- [ ] T008 Installer code signing (SignPath Foundation), GUI auto-update (later).
