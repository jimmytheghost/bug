import AVFoundation
import Darwin
import Foundation

enum AudioExportFormat: String, CaseIterable, Sendable { case wav, mp3 }

enum AudioExportError: LocalizedError {
    case invalidSource, sourceDestinationConflict, conversion(String), encoder(String), tooLarge
    var errorDescription: String? {
        switch self {
        case .invalidSource: return "The recording is empty or contains unsupported or non-finite audio."
        case .sourceDestinationConflict: return "Choose a destination different from the source recordings."
        case .conversion(let message): return "Audio conversion failed: \(message)"
        case .encoder(let message): return "MP3 encoder: \(message)"
        case .tooLarge: return "This recording exceeds the 4 GB WAV limit. Export a shorter recording or use MP3."
        }
    }
}

struct AudioExporter: Sendable {
    /// Explicit override is useful for development/tests; packaged builds load only their bundled encoder.
    var encoderURL: URL? = nil

    func export(systemURL: URL, microphoneURL: URL?, to destination: URL, format: AudioExportFormat) async throws {
        let worker = Task.detached(priority: .utility) {
            try Self.run(systemURL: systemURL, microphoneURL: microphoneURL, destination: destination,
                         format: format, encoderURL: encoderURL)
        }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private static func run(systemURL: URL, microphoneURL: URL?, destination: URL,
                            format: AudioExportFormat, encoderURL: URL?) throws {
        try Task.checkCancellation()
        let sources = [systemURL] + (microphoneURL.map { [$0] } ?? [])
        func protectSources() throws {
            for source in sources {
                var a = stat(), b = stat()
                if source.standardizedFileURL.resolvingSymlinksInPath() == destination.standardizedFileURL.resolvingSymlinksInPath()
                    || (stat(source.path, &a) == 0 && stat(destination.path, &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
                    throw AudioExportError.sourceDestinationConflict
                }
            }
        }
        try protectSources()
        // Contract: capture has already padded each track to a common epoch. Mix frame zero with
        // frame zero and zero-fill a shorter track; never shift a microphone to its first nonzero sample.
        // Two bounded-memory passes measure the summed sample peak, then apply one constant gain:
        // min(1, 0.95 / peak). This retains relative dynamics, never boosts, and leaves ~0.45 dB headroom.
        // MP3 reconstruction can overshoot; this is sample-peak protection, not a true-peak limiter.
        var peak: Float = 0
        var frames: UInt64 = 0
        try mix(sources) { samples in
            for sample in samples { peak = max(peak, abs(sample)) }
            frames += UInt64(samples.count / 2)
        }
        guard frames > 0 else { throw AudioExportError.invalidSource }
        if format == .wav && frames > (UInt64(UInt32.max) - 36) / 6 { throw AudioExportError.tooLarge }
        let gain: Float = peak > 0.95 ? 0.95 / peak : 1
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".bug-export-\(UUID().uuidString)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temp) }
        let encoder = format == .mp3 ? try ExportMP3Encoder(url: encoderURL) : nil
        if format == .wav { try output.write(contentsOf: wavHeader(frames: frames)) }
        var written: UInt64 = 0
        try mix(sources) { samples in
            let scaled = samples.map { max(-0.95, min(0.95, $0 * gain)) }
            if let encoder {
                try output.write(contentsOf: encoder.encode(scaled))
            } else {
                var data = Data(capacity: scaled.count * 3)
                for sample in scaled {
                    let bits = UInt32(bitPattern: Int32((Double(sample) * 8_388_607).rounded()))
                    data.append(UInt8(truncatingIfNeeded: bits))
                    data.append(UInt8(truncatingIfNeeded: bits >> 8))
                    data.append(UInt8(truncatingIfNeeded: bits >> 16))
                }
                try output.write(contentsOf: data)
            }
            written += UInt64(samples.count / 2)
        }
        guard written == frames else { throw AudioExportError.conversion("Source changed during export.") }
        if let encoder { try output.write(contentsOf: encoder.finish()) }
        try output.synchronize()
        try output.close()
        try Task.checkCancellation()
        try protectSources()
        // Same-directory POSIX rename atomically replaces an existing destination, without deleting it first.
        guard rename(temp.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private static func mix(_ urls: [URL], consume: ([Float]) throws -> Void) throws {
        let tracks = try urls.map { try ExportTrack(url: $0) }
        while true {
            try Task.checkCancellation()
            let blocks = try tracks.map { try $0.read() }
            let count = blocks.map(\.count).max() ?? 0
            if count == 0 { return }
            var mixed = [Float](repeating: 0, count: count)
            for block in blocks {
                for index in block.indices { mixed[index] += block[index] }
            }
            guard mixed.allSatisfy(\.isFinite) else { throw AudioExportError.invalidSource }
            try consume(mixed)
        }
    }

    private static func wavHeader(frames: UInt64) -> Data {
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(frames * 6 + 36))
        data.append(contentsOf: "WAVEfmt ".utf8); word(UInt32(16)); word(UInt16(1)); word(UInt16(2))
        word(UInt32(48_000)); word(UInt32(288_000)); word(UInt16(6)); word(UInt16(24))
        data.append(contentsOf: "data".utf8); word(UInt32(frames * 6))
        return data
    }
}

/// Streaming sample-rate conversion; at most 4096 frames per input/output buffer.
private final class ExportTrack {
    let file: AVAudioFile
    let converter: AVAudioConverter
    let input: AVAudioPCMBuffer
    let output: AVAudioPCMBuffer
    var ended = false

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.channelCount == 1 || format.channelCount == 2,
              format.sampleRate >= 8_000, format.sampleRate <= 192_000,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                         channels: format.channelCount, interleaved: false),
              let conversion = AVAudioConverter(from: format, to: target),
              let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096),
              let targetBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else {
            throw AudioExportError.invalidSource
        }
        converter = conversion
        converter.primeMethod = .normal
        input = sourceBuffer
        output = targetBuffer
    }

    func read() throws -> [Float] {
        if ended { return [] }
        // Fill the whole logical block even if the converter returns partial output.
        var result: [Float] = []
        result.reserveCapacity(8192)
        while result.count < 8192 && !ended {
            let output = result.isEmpty ? self.output : AVAudioPCMBuffer(
                pcmFormat: self.output.format, frameCapacity: AVAudioFrameCount((8192 - result.count) / 2))!
            output.frameLength = 0
            var conversionError: NSError?
            var readError: Error?
            let status = converter.convert(to: output, error: &conversionError) { requested, status in
                do {
                    guard self.file.framePosition < self.file.length else {
                        status.pointee = .endOfStream
                        return nil
                    }
                    try self.file.read(into: self.input, frameCount: min(requested, self.input.frameCapacity))
                    status.pointee = self.input.frameLength == 0 ? .endOfStream : .haveData
                    return self.input.frameLength == 0 ? nil : self.input
                } catch {
                    readError = error
                    status.pointee = .endOfStream
                    return nil
                }
            }
            if let readError { throw readError }
            if let conversionError { throw conversionError }
            if status == .error { throw AudioExportError.conversion("Sample-rate conversion failed.") }
            if status == .endOfStream { ended = true }
            let length = Int(output.frameLength)
            guard length > 0 else {
                if ended { break }
                throw AudioExportError.conversion("Sample-rate converter made no progress.")
            }
            guard let channels = output.floatChannelData else { throw AudioExportError.invalidSource }
            for i in 0..<length {
                result.append(channels[0][i])
                result.append(channels[output.format.channelCount == 1 ? 0 : 1][i])
            }
            // AVAudioConverter normally fills output; partial blocks only occur at EOF.
            if !ended && result.count < 8192 { output.frameLength = 0 }
        }
        return result
    }
}
