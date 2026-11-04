# Device check: Plugin drafts during the build, a check before compiling

On a new test project (`flutter create`) unless a row says otherwise, not a client project.

| # | AC | Step | Expected | Result |
|---|----|------|----------|--------|
| 1 | AC-025-1 | Add a podspec-only plugin; build | `[build.plugin_drafted]`; the draft in `xcross_overrides/`; the plugin in the plugins library | ✅ 2026-11-04, simulator build |
| 2 | AC-025-4 | `xcross plugin check` | one line per plugin; nothing written | ✅ 2026-11-04 |
| 3 | AC-025-6 | `XCROSS_PLUGIN_BUILD=distribution`; build | a workspace of its own; `-UDEBUG` after `-DDEBUG=1` in a plugin's compile command; it links | ⏳ on a real plugin set, after `-O2` and `-O` crashed the compiler there |
| 4 | AC-025-7 | Build with the generic and the project runner | both compile and link with plugins | ✅ 2026-11-04, compile and link only, simulator build |
| 5 | AC-025-8 | A client app using `firebase_messaging`: run on an iPhone, log in | `fcmToken` in the login request | ⏳ needs the iPhone connected |
| 6 | AC-025-6 | A real App Store build, installed from TestFlight | a push arrives | ⏳ needs the distribution certificate decision |
