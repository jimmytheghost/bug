import AVFoundation
import Testing
@testable import Bug

struct AudioExportTests {
    private let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BugExportTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func track(_ name: String, rate: Double = 48_000, channels: Int = 1,
                       frames: Int, sample: (Int, Int) -> Float) throws -> URL {
        let url = directory.appendingPathComponent(name + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(channels))!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var position = 0
        while position < frames {
            let count = min(4096, frames - position)
            buffer.frameLength = AVAudioFrameCount(count)
            for c in 0..<channels { for i in 0..<count { buffer.floatChannelData![c][i] = sample(position + i, c) } }
            try file.write(from: buffer)
            position += count
        }
        return url
    }
    private func pcm(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return buffer
    }

    @Test func testWAVAlignmentStereoTailAnd24BitHeader() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = try track("system", channels: 2, frames: 12_000) { _, c in c == 0 ? 0.1 : -0.2 }
        let mic = try track("mic", frames: 8_000) { i, _ in i < 4_800 ? 0 : 0.3 }
        let destination = directory.appendingPathComponent("mixed.wav")
        try await AudioExporter().export(systemURL: system, microphoneURL: mic, to: destination, format: .wav)
        let data = try Data(contentsOf: destination)
        #expect((data.count) == (44 + 12_000 * 6))
        #expect((Array(data[20..<24])) == ([1, 0, 2, 0]))
        #expect((Array(data[24..<28])) == ([0x80, 0xbb, 0, 0]))
        #expect((Array(data[34..<36])) == ([24, 0]))
        let audio = try pcm(destination)
        #expect((audio.frameLength) == (12_000))
        for (frame, left, right): (Int, Float, Float) in [(100, 0.1, -0.2), (5000, 0.4, 0.1), (9000, 0.1, -0.2)] {
            #expect(abs((audio.floatChannelData![0][frame]) - (left)) <= 0.000001)
            #expect(abs((audio.floatChannelData![1][frame]) - (right)) <= 0.000001)
        }
    }

    @Test func testPeakGainIsConstantAndPreventsClipping() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try track("loud", frames: 10_000) { i, _ in i < 5000 ? 0.9 : 0.45 }
        let destination = directory.appendingPathComponent("peak.wav")
        try await AudioExporter().export(systemURL: source, microphoneURL: source, to: destination, format: .wav)
        let audio = try pcm(destination)
        #expect(abs((audio.floatChannelData![0][100]) - (0.95)) <= 0.000001)
        #expect(abs((audio.floatChannelData![0][9000]) - (0.475)) <= 0.000001)
    }

    @Test func testResamples44100MonoWithCorrectDuration() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try track("44k", rate: 44_100, frames: 44_100) { i, _ in 0.25 * sin(Float(i) * 2 * .pi * 440 / 44_100) }
        let destination = directory.appendingPathComponent("48k.wav")
        try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: destination, format: .wav)
        let audio = try pcm(destination)
        #expect((audio.format.sampleRate) == (48_000))
        #expect(abs((Int(audio.frameLength)) - (48_000)) <= 2)
        #expect((audio.floatChannelData![0][2000]) == (audio.floatChannelData![1][2000]))
        #expect((abs(audio.floatChannelData![0][2000])) > (0.1))
    }

    @Test func testFailuresAndCancellationPreserveDestinationAndSources() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try track("source", frames: 500_000) { _, _ in 0.1 }
        let original = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent("existing.wav")
        let sentinel = Data("original destination".utf8)
        try sentinel.write(to: destination)
        do {
            try await AudioExporter().export(systemURL: source, microphoneURL: directory.appendingPathComponent("missing"), to: destination, format: .wav)
            Issue.record("Missing microphone must fail")
        } catch {}
        do {
            try await AudioExporter(encoderURL: directory.appendingPathComponent("missing.dylib"))
                .export(systemURL: source, microphoneURL: nil, to: destination, format: .mp3)
            Issue.record("Missing encoder must fail")
        } catch {}
        let task = Task { try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: destination, format: .wav) }
        task.cancel()
        do { try await task.value; Issue.record("Cancelled export must fail") } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect((try Data(contentsOf: destination)) == (sentinel))
        #expect((try Data(contentsOf: source)) == (original))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bug-export-") }))
    }

    @Test func testRefusesSourceAndHardLinkDestination() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try track("source", frames: 100) { _, _ in 0.1 }
        let alias = directory.appendingPathComponent("alias.wav")
        try FileManager.default.linkItem(at: source, to: alias)
        for destination in [source, alias] {
            do {
                try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: destination, format: .wav)
                Issue.record("Must protect source")
            } catch AudioExportError.sourceDestinationConflict {} catch { Issue.record("\(error)") }
        }
    }


    @Test func testLongerMicrophoneAndSuccessfulReplacement() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let system = try track("short", frames: 2000) { _, _ in 0.1 }
        let mic = try track("long", frames: 9000) { _, _ in 0.2 }
        let original = try Data(contentsOf: system)
        let destination = directory.appendingPathComponent("replace.wav")
        try Data("old file".utf8).write(to: destination)
        try await AudioExporter().export(systemURL: system, microphoneURL: mic, to: destination, format: .wav)
        let audio = try pcm(destination)
        #expect(audio.frameLength == 9000)
        #expect(abs(audio.floatChannelData![0][100] - 0.3) < 0.000001)
        #expect(abs(audio.floatChannelData![0][8500] - 0.2) < 0.000001)
        #expect(try Data(contentsOf: system) == original)
    }

    @Test func testRenameFailureCleansStagingFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try track("source", frames: 3000) { _, _ in 0.1 }
        let destination = directory.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("keep")
        try Data([42]).write(to: sentinel)
        do {
            try await AudioExporter().export(systemURL: source, microphoneURL: nil, to: destination, format: .wav)
            Issue.record("Replacing a directory must fail")
        } catch {}
        #expect(try Data(contentsOf: sentinel) == Data([42]))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".bug-export-") })
    }

    private static var encoderURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Encoder/libmp3lame.dylib")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.encoderURL.path),
                   "Run scripts/prepare-encoder.sh to enable real MP3 verification"))
    func testMP3IsDecodable320KbpsStereo() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoder = Self.encoderURL
        let source = try track("tone", channels: 2, frames: 48_000) { i, c in 0.2 * sin(Float(i) * 2 * .pi * Float(c == 0 ? 440 : 880) / 48_000) }
        let destination = directory.appendingPathComponent("tone.mp3")
        try await AudioExporter(encoderURL: encoder).export(systemURL: source, microphoneURL: nil, to: destination, format: .mp3)
        let data = try Data(contentsOf: destination)
        #expect((data.count) > (40_000))
        #expect((data.count) < (43_000))
        #expect((data[0]) == (0xff))
        #expect((data[1] & 0xfe) == (0xfa)) // MPEG-1 Layer III
        #expect((data[2] >> 4) == (14)) // 320 kbps
        #expect(((data[2] >> 2) & 3) == (1)) // 48 kHz
        let audio = try pcm(destination)
        #expect((audio.format.channelCount) == (2))
        #expect((audio.format.sampleRate) == (48_000))
        #expect((audio.frameLength) > (47_000))
        let peak = (0..<Int(audio.frameLength)).map { abs(audio.floatChannelData![0][$0]) }.max()!
        #expect((peak) > (0.1))
    }
}
