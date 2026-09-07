// Developer-only offscreen rendering. This never starts audio capture.
import AppKit
import SwiftUI

@main
struct BugPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BugPreview-\(UUID())")
        let library = try RecordingLibrary(root: directory)
        let suite = "BugPreview-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            preferences.removePersistentDomain(forName: suite)
        }
        if CommandLine.arguments.contains("--trim-fixture") || CommandLine.arguments.contains("--trimmed-fixture") {
            var recording = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_788_804_000),
                title: "Afternoon live stream", duration: 28, systemFilename: "system.caf", microphoneFilename: nil)
            if CommandLine.arguments.contains("--trimmed-fixture") {
                recording.trimRange = AudioTrimRange(startFrame: 360_000, endFrame: 888_000)
            }
            _ = try library.createSession(id: recording.id)
            try library.save(recording)
        }
        let content: AnyView
        if CommandLine.arguments.contains("--silence-reminder") {
            content = AnyView(SilenceReminderView(delay: .thirtySeconds, keepRecording: {}, stopRecording: {}))
        } else {
            let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
            if CommandLine.arguments.contains("--deleted-fixture") {
                store.notice = "Moved 13 session folders to Trash. Exported copies are unchanged."
            }
            content = AnyView(BugMenuView(store: store,
                                           showingSettings: CommandLine.arguments.contains("--settings")))
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
}
