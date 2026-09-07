import Testing
import AVFoundation
@testable import Bug

final class CapturePCMWriterTests {
    private var directories: [URL] = []
    deinit { for url in directories { try? FileManager.default.removeItem(at: url) } }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    private func buffer(rate: Double = 48_000, channels: AVAudioChannelCount = 2,
                        count: AVAudioFrameCount, value: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        pcm.frameLength = count
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(count) { pcm.floatChannelData![channel][frame] = value }
        }
        return pcm
    }

    private func read(_ url: URL) throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: pcm)
        return pcm
    }

    // Read a scalar while the PCM owner is explicitly alive. Assertion macros may
    // otherwise retain an unsafe channel pointer beyond the owner's last use.
    private func sample(_ pcm: AVAudioPCMBuffer, channel: Int, frame: Int) -> Float {
        withExtendedLifetime(pcm) {
            pcm.floatChannelData![channel][frame]
        }
    }

    @Test func testDelayedNativeMicrophoneSharesSystemEpochAndEnd() throws {
        let folder = try directory()
        let system = CapturePCMWriter(url: folder.appendingPathComponent("system.caf"))
        let mic = CapturePCMWriter(url: folder.appendingPathComponent("microphone.caf"))
        _ = try system.append(buffer(count: 480, value: 0.25), seconds: 0)
        _ = try mic.append(buffer(rate: 44_100, channels: 1, count: 441, value: 0.5), seconds: 0.02)
        try system.finish(duration: 0.04)
        try mic.finish(duration: 0.04)
        let a = try read(system.url)
        let b = try read(mic.url)
        #expect(a.frameLength == 1920)
        #expect(b.frameLength == 1764)
        #expect(b.format.sampleRate == 44_100)
        #expect(b.format.channelCount == 1)
        #expect(b.format.commonFormat == .pcmFormatFloat32)
        #expect(sample(b, channel: 0, frame: 881) == 0)
        #expect(sample(b, channel: 0, frame: 882) == 0.5)
        #expect(sample(b, channel: 0, frame: 1322) == 0.5)
        #expect(sample(b, channel: 0, frame: 1323) == 0)
        #expect(sample(a, channel: 1, frame: 479) == 0.25)
        #expect(sample(a, channel: 1, frame: 480) == 0)
    }

    @Test func testGapPaddingAndOverlapsDoNotShiftTimeline() throws {
        let track = CapturePCMWriter(url: try directory().appendingPathComponent("system.caf"))
        _ = try track.append(buffer(count: 480, value: 0.25), seconds: -0.005)
        #expect(track.frames == 240)
        _ = try track.append(buffer(count: 480, value: 0.5), seconds: 0)
        #expect(track.frames == 480)
        _ = try track.append(buffer(count: 480, value: 0.75), seconds: 0.02)
        try track.finish(duration: 0.03)
        let pcm = try read(track.url)
        #expect(pcm.frameLength == 1440)
        #expect(sample(pcm, channel: 0, frame: 239) == 0.25)
        #expect(sample(pcm, channel: 0, frame: 240) == 0.5)
        #expect(sample(pcm, channel: 0, frame: 479) == 0.5)
        #expect(sample(pcm, channel: 0, frame: 480) == 0)
        #expect(sample(pcm, channel: 0, frame: 959) == 0)
        #expect(sample(pcm, channel: 0, frame: 960) == 0.75)
    }

    @Test func testRMSUsesActualSamplesAndSanitizesNonFiniteValues() throws {
        let track = CapturePCMWriter(url: try directory().appendingPathComponent("system.caf"))
        let pcm = buffer(count: 480, value: -0.5)
        #expect(abs((try track.append(pcm, seconds: 0)) - 0.5) < 0.00001)
        let silence = buffer(count: 480, value: .nan)
        #expect(try track.append(silence, seconds: 0.01) == 0)
        try track.finish(duration: 0.02)
        let recorded = try read(track.url)
        #expect(sample(recorded, channel: 0, frame: 480) == 0)
    }

    @Test func testIntegerInterleavedPCMConvertsToFloatCAF() throws {
        let track = CapturePCMWriter(url: try directory().appendingPathComponent("system.caf"))
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000, channels: 2, interleaved: true)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        pcm.frameLength = 480
        let samples = pcm.mutableAudioBufferList.pointee.mBuffers.mData!.assumingMemoryBound(to: Int16.self)
        for index in 0..<960 { samples[index] = 16_384 }
        #expect(abs((try track.append(pcm, seconds: 0)) - 0.5) < 0.0001)
        try track.finish(duration: 0.01)
        let result = try read(track.url)
        #expect(abs((sample(result, channel: 1, frame: 479)) - 0.5) < 0.0001)
    }

    @Test func testFailureLeavesPreviouslyWrittenPCMReadable() throws {
        let track = CapturePCMWriter(url: try directory().appendingPathComponent("system.caf"))
        _ = try track.append(buffer(count: 480, value: 0.25), seconds: 0)
        #expect(throws: (any Error).self) { try track.append(buffer(rate: 44_100, count: 441, value: 0.5), seconds: 0.01) }
        track.close()
        let preserved = try read(track.url)
        #expect(preserved.frameLength == 480)
        #expect(sample(preserved, channel: 0, frame: 0) == 0.25)
    }

    @Test func testLongSilenceIsWrittenInChunks() throws {
        let track = CapturePCMWriter(url: try directory().appendingPathComponent("system.caf"))
        _ = try track.append(buffer(count: 480, value: 0.25), seconds: 0)
        try track.finish(duration: 3)
        let file = try AVAudioFile(forReading: track.url)
        #expect(file.length == 144_000)
        file.framePosition = 143_999
        let last = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1)!
        try file.read(into: last)
        #expect(sample(last, channel: 0, frame: 0) == 0)
    }

    @Test func testInvalidTimestampAndUnwritableDestinationThrow() throws {
        let folder = try directory()
        let track = CapturePCMWriter(url: folder.appendingPathComponent("system.caf"))
        #expect(throws: (any Error).self) { try track.append(buffer(count: 480, value: 0), seconds: .nan) }
        let invalid = CapturePCMWriter(url: folder.appendingPathComponent("missing/system.caf"))
        #expect(throws: (any Error).self) { try invalid.append(buffer(count: 480, value: 0), seconds: 0) }
    }

    @Test func testStopWithoutStartDoesNotRequestCapturePermission() async {
        let engine = CaptureEngine()
        do {
            _ = try await engine.stop()
            Issue.record("An idle engine must not produce a recording")
        } catch {
            guard case CaptureError.notRecording = error else { Issue.record("Unexpected error: \(error)"); return }
        }
    }
    @Test func testMicOnlyRecoveryPadsSilentSystemAndPreservesNativePCM() throws {
        let folder = try directory()
        let system = CapturePCMWriter(url: folder.appendingPathComponent("system.caf"))
        let mic = CapturePCMWriter(url: folder.appendingPathComponent("microphone.caf"))
        try system.open(format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
        _ = try mic.append(buffer(rate: 44_100, channels: 1, count: 441, value: 0.5), seconds: 0.02)
        let result = try #require(CapturePCMWriter.recover(system: system, microphone: mic))
        #expect(result.duration == 0.03)
        #expect(result.microphoneURL == mic.url)
        let silentSystem = try read(result.systemURL)
        #expect(silentSystem.frameLength == 1440)
        #expect(sample(silentSystem, channel: 1, frame: 1439) == 0)
        let recordedMicrophone = try read(mic.url)
        #expect(sample(recordedMicrophone, channel: 0, frame: 882) == 0.5)
    }

    @Test func testRecoveryReturnsCommittedSystemWhenPaddingCannotWrite() throws {
        let folder = try directory()
        let system = CapturePCMWriter(url: folder.appendingPathComponent("system.caf"))
        let mic = CapturePCMWriter(url: folder.appendingPathComponent("microphone.caf"))
        _ = try system.append(buffer(count: 480, value: 0.25), seconds: 0)
        system.close()
        _ = try mic.append(buffer(channels: 1, count: 960, value: 0.5), seconds: 0)
        let result = try #require(CapturePCMWriter.recover(system: system, microphone: mic))
        #expect(result.duration == 0.02)
        #expect(try AVAudioFile(forReading: result.systemURL).length == 480)
        #expect(try AVAudioFile(forReading: mic.url).length == 960)
    }

}
