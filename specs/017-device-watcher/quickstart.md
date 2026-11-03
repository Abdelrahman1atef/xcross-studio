# Quickstart: verify 017

1. `xcross devices --watch --json` with the iPhone connected → one snapshot with it.
2. Unplug → a snapshot without it within ~1 s; plug in → a snapshot with it within ~2 s.
3. Windows: restart "Apple Mobile Device Service" (services.msc) → notice + empty snapshot, then a snapshot again.
4. XCross Studio: the top-bar badge follows steps 2 and 3 with no click.
