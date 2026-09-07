import Foundation

/// Half-open bounds in the common 48 kHz export timeline. Source files remain untouched.
struct AudioTrimRange: Codable, Equatable, Sendable {
    let startFrame: Int64
    let endFrame: Int64
    var isValid: Bool { startFrame >= 0 && endFrame > startFrame }
    var duration: TimeInterval { Double(endFrame - startFrame) / 48_000 }
}

enum AudioTrimError: LocalizedError {
    case invalidRange, invalidPadding
    var errorDescription: String? {
        switch self {
        case .invalidRange: return "The saved trim does not fit this recording. Undo Trim to restore the original."
        case .invalidPadding: return "Trim padding must be between 0 and 2 seconds."
        }
    }
}

struct AudioTrimmer: Sendable {
    /// A conservative sample-peak floor of -60 dBFS. Inspect sources separately so
    /// stereo phase cancellation or a quiet microphone cannot erase meaningful audio.
    static let silenceThreshold: Float = 0.001

    func analyze(systemURL: URL, microphoneURL: URL?, padding: TimeInterval = 0.5) async throws -> AudioTrimRange? {
        guard padding.isFinite, (0...2).contains(padding) else { throw AudioTrimError.invalidPadding }
        let worker = Task.detached(priority: .utility) {
            var first: Int64?
            var last: Int64 = 0
            var total: Int64 = 0
            for url in [systemURL] + (microphoneURL.map { [$0] } ?? []) {
                let track = try ExportTrack(url: url)
                var position: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let samples = try track.read()
                    if samples.isEmpty { break }
                    guard samples.allSatisfy(\.isFinite) else { throw AudioExportError.invalidSource }
                    for frame in 0..<(samples.count / 2) {
                        if max(abs(samples[frame * 2]), abs(samples[frame * 2 + 1])) >= Self.silenceThreshold {
                            let index = position + Int64(frame)
                            first = min(first ?? index, index)
                            last = max(last, index + 1)
                        }
                    }
                    position += Int64(samples.count / 2)
                }
                total = max(total, position)
            }
            try Task.checkCancellation()
            // Entirely silent and empty recordings are left alone, never reduced to zero.
            guard let first else { return nil as AudioTrimRange? }
            let margin = Int64((padding * 48_000).rounded())
            let start = max(0, first - margin)
            let end = min(total, last + margin)
            guard start > 0 || end < total else { return nil }
            return AudioTrimRange(startFrame: start, endFrame: end)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
