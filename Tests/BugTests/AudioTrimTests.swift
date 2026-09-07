import AVFoundation
import Foundation
import Testing
@testable import Bug

final class AudioTrimTests {
    private let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BugTrimTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    private func track(_ name: String = "system", seconds: Double, rate: Double = 48_000,
                       sample: (Double, Int) -> Float) throws -> URL {
        let url = root.appendingPathComponent(name + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var position = 0
        let length = Int(seconds * rate)
        while position < length {
            let count = min(4096, length - position)
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0..<2 {
                for i in 0..<count { buffer.floatChannelData![channel][i] = sample(Double(position + i) / rate, channel) }
            }
            try file.write(from: buffer)
            position += count
        }
        return url
    }

    private func samples(_ url: URL) throws -> [[Float]] {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return withExtendedLifetime(buffer) {
            (0..<Int(buffer.format.channelCount)).map {
                Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength)))
            }
        }
    }

    @Test func trimsEightSecondHeadTenSecondTailPreservingPaddingAndInteriorPause() async throws {
        let source = try track(seconds: 28) { time, channel in
            (8..<12).contains(time) || (14..<18).contains(time) ? (channel == 0 ? 0.2 : -0.3) : 0
        }
        let original = try Data(contentsOf: source)
        let range = try #require(await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil))
        #expect(range == AudioTrimRange(startFrame: 360_000, endFrame: 888_000))
        #expect(range.duration == 11)
        let output = root.appendingPathComponent("trimmed.wav")
        try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: output, format: .wav, trimRange: range)
        let pcm = try samples(output)
        #expect(pcm[0].count == 528_000)
        #expect(pcm[0][23_999] == 0)
        #expect(abs(pcm[0][24_000] - 0.2) < 0.00001)
        #expect(abs(pcm[1][24_000] + 0.3) < 0.00001)
        #expect(pcm[0][Int(5 * 48_000)] == 0) // An interior pause stays in place.
        #expect(pcm[0][504_000] == 0)
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func silentContinuousAndShortRecordingsRemainUnchanged() async throws {
        let silent = try track("silent", seconds: 1) { _, _ in 0 }
        let continuous = try track("continuous", seconds: 1) { _, _ in 0.1 }
        let short = try track("short", seconds: 0.2) { t, _ in (0.08..<0.12).contains(t) ? 0.1 : 0 }
        for source in [silent, continuous, short] {
            #expect(try await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil) == nil)
        }
    }

    @Test func quietFadesStereoAndOppositePhaseSourcesAreNotSummedForDetection() async throws {
        let source = try track(seconds: 5) { t, channel in
            guard (1..<4).contains(t) else { return 0 }
            return channel == 1 ? 0.002 : 0 // -54 dBFS, only in the right channel.
        }
        let opposite = try track("mic", seconds: 5) { t, channel in
            (1..<4).contains(t) && channel == 1 ? -0.002 : 0
        }
        let range = try await AudioTrimmer().analyze(systemURL: source, microphoneURL: opposite)
        #expect(range == AudioTrimRange(startFrame: 24_000, endFrame: 216_000))
    }

    @Test func microphoneExtendsBoundsAcrossSampleRates() async throws {
        let source = try track(seconds: 6) { t, _ in (2..<3).contains(t) ? 0.2 : 0 }
        let mic = try track("mic", seconds: 7, rate: 44_100) { t, _ in (1..<5).contains(t) ? 0.1 : 0 }
        let range = try #require(await AudioTrimmer().analyze(systemURL: source, microphoneURL: mic))
        // Resampler ringing may conservatively extend activity a few frames.
        #expect(abs(range.startFrame - 24_000) < 100)
        #expect(abs(range.endFrame - 264_000) < 100)
    }

    @Test func configurablePaddingClampsToExistingAudioAndNeverAddsSilence() async throws {
        let source = try track(seconds: 4) { t, _ in (0..<1).contains(t) ? 0.1 : 0 }
        let zero = try await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil, padding: 0)
        #expect(zero == AudioTrimRange(startFrame: 0, endFrame: 48_000))
        let two = try await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil, padding: 2)
        #expect(two == AudioTrimRange(startFrame: 0, endFrame: 144_000))
        await #expect(throws: AudioTrimError.self) {
            try await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil, padding: .nan)
        }
    }

    @Test func invalidBoundsAndCancellationPreserveDestination() async throws {
        let source = try track(seconds: 1) { _, _ in 0.1 }
        let output = root.appendingPathComponent("existing.wav")
        let sentinel = Data("keep this destination".utf8)
        try sentinel.write(to: output)
        for range in [AudioTrimRange(startFrame: -1, endFrame: 4),
                      AudioTrimRange(startFrame: 10, endFrame: 10),
                      AudioTrimRange(startFrame: 0, endFrame: 96_000)] {
            await #expect(throws: AudioTrimError.self) {
                try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: output, format: .wav, trimRange: range)
            }
            #expect(try Data(contentsOf: output) == sentinel)
        }
        let task = Task { try await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func trimmedMP3HasSelectedDuration() async throws {
        let source = try track(seconds: 4) { t, _ in (1..<2).contains(t) ? 0.2 * sin(Float(t) * 440 * 2 * .pi) : 0 }
        let range = try #require(await AudioTrimmer().analyze(systemURL: source, microphoneURL: nil))
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let exporter = AudioExporter(encoderURL: repo.appendingPathComponent("Resources/Encoder/libmp3lame.dylib"))
        let output = root.appendingPathComponent("trimmed.mp3")
        try await exporter.export(systemURL: source, microphoneURL: nil, to: output, format: .mp3, trimRange: range)
        let decoded = try samples(output)
        #expect(abs(Double(decoded[0].count) / 48_000 - 2) < 0.1) // Includes MP3 encoder padding.
        #expect(decoded[0].contains { abs($0) > 0.1 })
    }

    @Test @MainActor func trimPersistsAcrossRelaunchUndoAndRenameWithoutTouchingSources() async throws {
        let source = try track(seconds: 4) { t, _ in (1..<2).contains(t) ? 0.2 : 0 }
        let library = try RecordingLibrary(root: root.appendingPathComponent("library"))
        let id = UUID()
        let directory = try library.createSession(id: id)
        let stored = directory.appendingPathComponent("system.caf")
        try FileManager.default.copyItem(at: source, to: stored)
        let original = try Data(contentsOf: stored)
        let recording = Recording(id: id, createdAt: Date(), title: "Test", duration: 4, systemFilename: "system.caf", microphoneFilename: nil)
        try library.save(recording)
        let suite = "BugTrimTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
        #expect(store.trimPadding == 0.5)
        await store.trim(recording)
        #expect(store.recordings.first?.playbackDuration == 2)
        #expect(store.recordings.first?.duration == 4)
        let range = try #require(store.recordings.first?.trimRange)
        await store.trim(recording) // A repeated/stale request must not compound the trim.
        #expect(store.recordings.first?.trimRange == range)
        store.rename(recording, to: "Renamed") // Stale UI snapshot must not erase the trim.
        #expect(store.recordings.first?.trimRange == range)
        let reopened = RecorderStore(library: library, preferences: preferences, startTimer: false)
        #expect(reopened.recordings.first?.trimRange == range)
        reopened.undoTrim(recording)
        #expect(reopened.recordings.first?.playbackDuration == 4)
        #expect(try library.load().first?.trimRange == nil)
        #expect(try library.load().first?.title == "Renamed")
        #expect(try Data(contentsOf: stored) == original)
    }

    @Test @MainActor func failedTrimLeavesMetadataUnchanged() async throws {
        let library = try RecordingLibrary(root: root.appendingPathComponent("library"))
        let recording = Recording(id: UUID(), createdAt: Date(), title: "Missing audio", duration: 4, systemFilename: "missing.caf", microphoneFilename: nil)
        _ = try library.createSession(id: recording.id)
        try library.save(recording)
        let store = RecorderStore(library: library, startTimer: false)
        await store.trim(recording)
        #expect(store.errorMessage != nil)
        #expect(store.trimmingID == nil)
        #expect(try library.load() == [recording])
    }

    @Test func legacyMetadataDecodesWithoutTrimField() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"title":"Legacy","duration":3,"systemFilename":"system.caf"}
        """
        let recording = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        #expect(recording.trimRange == nil)
        #expect(recording.playbackDuration == 3)
    }

    @Test func backgroundBelowThresholdIsTrimmedButNoiseAboveItIsPreserved() async throws {
        let quiet = try track("quiet", seconds: 4) { t, _ in (1..<2).contains(t) ? 0.1 : 0.0001 }
        let noisy = try track("noisy", seconds: 4) { t, _ in (1..<2).contains(t) ? 0.1 : 0.002 }
        #expect(try await AudioTrimmer().analyze(systemURL: quiet, microphoneURL: nil)
                == AudioTrimRange(startFrame: 24_000, endFrame: 120_000))
        #expect(try await AudioTrimmer().analyze(systemURL: noisy, microphoneURL: nil) == nil)
    }

    @Test @MainActor func metadataWriteFailureDoesNotPretendTrimOrUndoSucceeded() async throws {
        let source = try track(seconds: 4) { t, _ in (1..<2).contains(t) ? 0.1 : 0 }
        let library = try RecordingLibrary(root: root.appendingPathComponent("library"))
        var recording = Recording(id: UUID(), createdAt: Date(), title: "Test", duration: 4, systemFilename: "system.caf", microphoneFilename: nil)
        let directory = try library.createSession(id: recording.id)
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent("system.caf"))
        let suite = "BugTrimTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let metadata = directory.appendingPathComponent("recording.json")
        try library.save(recording)
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        await store.trim(recording)
        #expect(store.errorMessage != nil)
        #expect(store.recordings.first?.trimRange == nil)
        try FileManager.default.removeItem(at: metadata)
        recording.trimRange = AudioTrimRange(startFrame: 24_000, endFrame: 120_000)
        try library.save(recording)
        let trimmedStore = RecorderStore(library: library, preferences: preferences, startTimer: false)
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
        trimmedStore.undoTrim(recording)
        #expect(trimmedStore.errorMessage != nil)
        #expect(trimmedStore.recordings.first?.trimRange == recording.trimRange)
    }
}
