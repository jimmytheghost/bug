import AVFoundation
import CoreMedia

/// Incremental Float32 PCM CAF track. All methods are confined to the capture writer queue.
/// Tracks retain their source sample rate/channel count; frame zero is the session host epoch.
/// AVAudioFile consumers must read processingFormat (microphones need not be 48 kHz/stereo).
final class CapturePCMWriter {
    let url: URL
    private(set) var format: AVAudioFormat?
    private var file: AVAudioFile?
    private(set) var frames: AVAudioFramePosition = 0
    private let chunk: AVAudioFrameCount = 4096

    init(url: URL) { self.url = url }

    func open(format: AVAudioFormat) throws {
        guard self.format == nil else { return }
        guard let pcm = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate,
                                     channels: format.channelCount) else { throw CaptureError.invalidAudio }
        file = try AVAudioFile(forWriting: url, settings: pcm.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
        self.format = pcm
    }

    func append(_ buffer: AVAudioPCMBuffer, seconds: Double) throws -> Float {
        guard seconds.isFinite, abs(seconds) < Double(Int64.max) / buffer.format.sampleRate else {
            throw CaptureError.invalidTimestamp
        }
        try open(format: buffer.format)
        guard let format, let file, format.sampleRate == buffer.format.sampleRate,
              format.channelCount == buffer.format.channelCount else { throw CaptureError.formatChanged }
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else {
            throw CaptureError.invalidAudio
        }
        if buffer.format == format {
            converted.frameLength = buffer.frameLength
            let destination = UnsafeMutableAudioBufferListPointer(converted.mutableAudioBufferList)
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            for index in source.indices {
                guard let src = source[index].mData, let dst = destination[index].mData else { throw CaptureError.invalidAudio }
                memcpy(dst, src, Int(source[index].mDataByteSize))
            }
        } else {
            guard let converter = AVAudioConverter(from: buffer.format, to: format) else { throw CaptureError.invalidAudio }
            try converter.convert(to: converted, from: buffer)
        }
        let target = AVAudioFramePosition((seconds * format.sampleRate).rounded())
        try pad(to: max(0, target))
        // Trim pre-epoch samples and timestamp overlaps; never shift a delayed source earlier.
        let skip = min(Int64(converted.frameLength), max(0, frames - target))
        let count = Int(converted.frameLength) - Int(skip)
        guard count > 0, let channels = converted.floatChannelData else { return 0 }
        var energy = 0.0
        for channel in 0..<Int(format.channelCount) {
            let samples = channels[channel]
            for index in Int(skip)..<Int(converted.frameLength) {
                let sample = samples[index].isFinite ? samples[index] : 0
                samples[index] = sample
                energy += Double(sample) * Double(sample)
            }
            if skip > 0 { memmove(samples, samples.advanced(by: Int(skip)), count * MemoryLayout<Float>.size) }
        }
        converted.frameLength = AVAudioFrameCount(count)
        try file.write(from: converted)
        frames += Int64(count)
        return min(1, Float(sqrt(energy / Double(count * Int(format.channelCount)))))
    }

    func pad(to target: AVAudioFramePosition) throws {
        guard let format, let file, target > frames else { return }
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw CaptureError.invalidAudio }
        for buffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
            if let data = buffer.mData { memset(data, 0, Int(chunk) * MemoryLayout<Float>.size) }
        }
        while frames < target {
            silence.frameLength = AVAudioFrameCount(min(Int64(chunk), target - frames))
            try file.write(from: silence)
            frames += Int64(silence.frameLength)
        }
    }

    func finish(duration: Double) throws {
        defer { file = nil }
        if format == nil { try open(format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!) }
        try pad(to: Int64((duration * format!.sampleRate).rounded()))
    }

    func close() { file = nil }

    /// Salvages committed PCM after an interruption; no live capture or source deletion.
    /// Storage failure may prevent tail padding, in which case the exporter pads the short track.
    static func recover(system: CapturePCMWriter, microphone: CapturePCMWriter?) -> CaptureResult? {
        let duration = max(Double(system.frames) / (system.format?.sampleRate ?? 48_000),
                           Double(microphone?.frames ?? 0) / (microphone?.format?.sampleRate ?? 48_000))
        guard duration > 0 else { system.close(); microphone?.close(); return nil }
        try? system.finish(duration: duration)
        try? microphone?.finish(duration: duration)
        system.close()
        microphone?.close()
        guard system.frames > 0, (try? AVAudioFile(forReading: system.url).length) ?? 0 > 0 else { return nil }
        let micURL: URL?
        if let microphone, (try? AVAudioFile(forReading: microphone.url).length) ?? 0 > 0 { micURL = microphone.url }
        else { micURL = nil }
        let result = CaptureResult(systemURL: system.url, microphoneURL: micURL, duration: duration)
        return result
    }

}
