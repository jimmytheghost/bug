// Developer-only offscreen rendering. This never starts audio capture.
import AppKit
import AVFoundation
import SwiftUI

@main
struct BugPreview {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BugPreview-\(UUID())")
        let library = try RecordingLibrary(root: directory)
        let suite = "BugPreview-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        var previewStore: RecorderStore?
        defer {
            previewStore?.cancelCustomTrim()
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        let hasTrimFixture = CommandLine.arguments.contains("--trim-fixture")
            || CommandLine.arguments.contains("--trimmed-fixture")
            || CommandLine.arguments.contains("--custom-trim")
            || CommandLine.arguments.contains("--custom-trim-head-zoom")
            || CommandLine.arguments.contains("--custom-trim-tail-zoom")
            || CommandLine.arguments.contains("--delete-confirmation")
            || CommandLine.arguments.contains("--rename-confirmation")
        var fixtureRecording: Recording?
        if hasTrimFixture {
            var recording = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_788_804_000),
                title: "Afternoon live stream",
                duration: CommandLine.arguments.contains(where: { $0.hasPrefix("--custom-trim") }) ? 12 : 28,
                systemFilename: "system.caf", microphoneFilename: nil)
            if CommandLine.arguments.contains("--trimmed-fixture") {
                recording.trimRange = AudioTrimRange(startFrame: 360_000, endFrame: 888_000)
            }
            let session = try library.createSession(id: recording.id)
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--custom-trim") }) {
                try writeSyntheticTrack(to: session.appendingPathComponent("system.caf"), seconds: recording.duration)
            }
            try library.save(recording)
            fixtureRecording = recording
        }
        let content: AnyView
        if CommandLine.arguments.contains("--silence-reminder") {
            content = AnyView(SilenceReminderView(delay: .thirtySeconds, keepRecording: {}, stopRecording: {}))
        } else {
            let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
            previewStore = store
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--custom-trim") }), let fixtureRecording {
                await store.customTrim(fixtureRecording)
            }
            if CommandLine.arguments.contains("--delete-confirmation"), let fixtureRecording {
                store.requestDelete(fixtureRecording)
            }
            if CommandLine.arguments.contains("--rename-confirmation"), let fixtureRecording {
                store.requestRename(fixtureRecording)
            }
            if CommandLine.arguments.contains("--deleted-fixture") {
                store.notice = "Moved 13 session folders to Trash. Exported copies are unchanged."
            }
            let zoomEdge: CustomTrimEdge? = CommandLine.arguments.contains("--custom-trim-head-zoom") ? .start
                : CommandLine.arguments.contains("--custom-trim-tail-zoom") ? .end : nil
            content = AnyView(BugMenuView(store: store,
                                          showingSettings: CommandLine.arguments.contains("--settings"),
                                          customTrimPreviewZoomEdge: zoomEdge))
        }
        let view = content.environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }

    private static func writeSyntheticTrack(to url: URL, seconds: TimeInterval) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = Int(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var position = 0
        while position < frames {
            let count = min(4096, frames - position)
            buffer.frameLength = AVAudioFrameCount(count)
            for frame in 0..<count {
                let sample = position + frame
                let envelope = Float(0.12 + 0.35 * abs(sin(Double(sample) / 18_000)))
                buffer.floatChannelData![0][frame] = envelope * sin(Float(sample) * 2 * .pi * 220 / 48_000)
                buffer.floatChannelData![1][frame] = envelope * sin(Float(sample) * 2 * .pi * 330 / 48_000)
            }
            try file.write(from: buffer)
            position += count
        }
    }
}
