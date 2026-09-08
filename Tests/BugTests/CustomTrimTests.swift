import AVFoundation
import Testing
@testable import Bug

final class CustomTrimTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BugCustomTrimTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    private func track(_ name: String, seconds: Double,
                       sample: (Int) -> Float) throws -> URL {
        let url = root.appendingPathComponent(name + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let total = Int(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var position = 0
        while position < total {
            let count = min(4096, total - position)
            buffer.frameLength = AVAudioFrameCount(count)
            for frame in 0..<count { buffer.floatChannelData![0][frame] = sample(position + frame) }
            try file.write(from: buffer)
            position += count
        }
        return url
    }

    @Test func selectionClampsHandlesAndPreservesExistingBounds() {
        var selection = CustomTrimSelection(duration: 10,
            initialRange: AudioTrimRange(startFrame: 48_000, endFrame: 432_000))
        #expect(selection.startFraction == 0.1)
        #expect(selection.endFraction == 0.9)
        selection.setStart(fraction: -1)
        selection.setEnd(fraction: 2)
        #expect(selection.range == AudioTrimRange(startFrame: 0, endFrame: 480_000))
        selection.setStart(fraction: 0.9)
        selection.setEnd(fraction: 0.1)
        #expect(selection.endFrame - selection.startFrame == CustomTrimSelection.minimumFrames)
    }

    @Test func waveformAnalysisIsBoundedAndIncludesBothSources() async throws {
        let system = try track("system", seconds: 1) { $0 < 24_000 ? 0.2 : 0 }
        let microphone = try track("microphone", seconds: 1) { $0 >= 24_000 ? 0.4 : 0 }
        let waveform = try await AudioWaveformAnalyzer().analyze(
            systemURL: system, microphoneURL: microphone, duration: 1, bucketCount: 8)
        #expect(waveform.count == 8)
        #expect(waveform[0] > 0.19)
        #expect(waveform[7] > 0.39)
    }

    @Test func tenTimesZoomUsesPinnedEdgeWindowsAndFineDragScale() {
        #expect(abs(CustomTrimZoom.adjustedFraction(anchor: 0.5, translation: 30, width: 300) - 0.51) < 0.000_001)
        let samples = (0..<100).map(Float.init)
        #expect(CustomTrimZoom.detailSamples(samples, boundary: 0.2, edge: .start) == Array(samples[20..<30]))
        #expect(CustomTrimZoom.detailSamples(samples, boundary: 0.8, edge: .end) == Array(samples[70..<80]))
        #expect(CustomTrimZoom.overviewSamples(samples, maximumCount: 10) == [9, 19, 29, 39, 49, 59, 69, 79, 89, 99])
    }

    @Test @MainActor func customTrimSavesMetadataWithoutChangingSource() async throws {
        let source = try track("source", seconds: 2) { frame in frame < 48_000 ? 0.2 : -0.2 }
        let library = try RecordingLibrary(root: root.appendingPathComponent("library"))
        let recording = Recording(id: UUID(), createdAt: Date(), title: "Manual edit", duration: 2,
                                  systemFilename: "system.caf", microphoneFilename: nil)
        let directory = try library.createSession(id: recording.id)
        let stored = directory.appendingPathComponent("system.caf")
        try FileManager.default.copyItem(at: source, to: stored)
        try library.save(recording)
        let original = try Data(contentsOf: stored)
        let store = RecorderStore(library: library, startTimer: false)

        await store.customTrim(recording)
        #expect(store.customTrimState?.recordingID == recording.id)
        store.setCustomTrimStart(0.25)
        store.setCustomTrimEnd(0.75)
        store.saveCustomTrim()

        #expect(store.customTrimState == nil)
        #expect(store.trimmingID == nil)
        #expect(store.recordings.first?.trimRange == AudioTrimRange(startFrame: 24_000, endFrame: 72_000))
        #expect(try library.load().first?.trimRange == AudioTrimRange(startFrame: 24_000, endFrame: 72_000))
        #expect(try Data(contentsOf: stored) == original)
    }

    @Test @MainActor func cancellingCustomTrimPreservesTheExistingEdit() async throws {
        let source = try track("cancel-source", seconds: 2) { _ in 0.1 }
        let library = try RecordingLibrary(root: root.appendingPathComponent("cancel-library"))
        var recording = Recording(id: UUID(), createdAt: Date(), title: "Already trimmed", duration: 2,
                                  systemFilename: "system.caf", microphoneFilename: nil)
        recording.trimRange = AudioTrimRange(startFrame: 12_000, endFrame: 84_000)
        let directory = try library.createSession(id: recording.id)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("system.caf"))
        try library.save(recording)
        let store = RecorderStore(library: library, startTimer: false)

        await store.customTrim(recording)
        #expect(store.customTrimState?.selection.range == recording.trimRange)
        store.setCustomTrimStart(0.4)
        store.cancelCustomTrim()

        #expect(store.customTrimState == nil)
        #expect(try library.load().first?.trimRange == recording.trimRange)
    }
}
