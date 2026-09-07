# Bug

Native SwiftUI macOS 15+ menu bar audio recorder, part of the Worklog suite.

- Keep the app lightweight, local, and free of a web runtime or background service.
- Match Worklog's 360-point popover, mint accent, system typography, and subtle rounded cards.
- Capture only on explicit Record. Never simulate live audio or a successful export.
- Keep capture buffers bounded and write audio incrementally to disk.
- Preserve source recordings when export fails or is cancelled.
- Check `swift build`, `scripts/test.sh`, and `scripts/package-app.sh` after integration. Require an explicit executed test count; plain `swift test` can miss Swift Testing under standalone CLT.
- Avoid recording actual user audio during automated verification.
- Do not modify the sibling agent-dashboard repository.
