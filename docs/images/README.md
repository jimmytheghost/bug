# README interface images

Generated **2026-10-20** from the v0.6.1 SwiftUI/AppKit views on Apple Silicon, macOS 26.6.2, Swift 6.3.3. These are offscreen renders of the actual interface, not screenshots of an interactive menu bar session or evidence of live capture.

- `bug-recorder.png`: idle recorder with an empty isolated library, 720 × 1022 pixels, displayed at 360 points in the README.
- `bug-custom-trim.png`: Custom Trim with a generated 12-second stereo test signal and disposable metadata, 720 × 920 pixels, displayed at 360 points. The fixture title is “Afternoon live stream”; it is not a captured stream.

Both images were visually checked for readable controls, complete edges, and absence of personal information. No capture was started, no user library was accessed, and temporary audio/preferences were removed by the preview helper. The waveform illustrates the editor using synthetic data.

Compile `scripts/render-preview.swift` using the command in [HANDOFF.md](../HANDOFF.md#offscreen-layout-preview), then run from the repository root:

```sh
.build/qa/render-preview docs/images/bug-recorder.png
.build/qa/render-preview docs/images/bug-custom-trim.png --custom-trim
```

Regenerate and visually inspect these images when the interface changes. Keep the README captions accurate about their offscreen, synthetic provenance.
