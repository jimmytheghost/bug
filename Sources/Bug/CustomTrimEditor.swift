import SwiftUI

/// A bounded overview of the original recording. Tracks share the same 48 kHz
/// export timeline, so their peaks can be merged without retaining source PCM.
struct AudioWaveformAnalyzer: Sendable {
    func analyze(systemURL: URL, microphoneURL: URL?, duration: TimeInterval,
                 bucketCount: Int = 720) async throws -> [Float] {
        guard duration.isFinite, duration > 0, bucketCount > 1 else {
            throw AudioExportError.invalidSource
        }
        let worker = Task.detached(priority: .utility) {
            let totalFrames = max(Int64(1), Int64((duration * 48_000).rounded()))
            var peaks = [Float](repeating: 0, count: bucketCount)
            for url in [systemURL] + (microphoneURL.map { [$0] } ?? []) {
                let track = try ExportTrack(url: url)
                var position: Int64 = 0
                while true {
                    try Task.checkCancellation()
                    let samples = try track.read()
                    if samples.isEmpty { break }
                    for frame in 0..<(samples.count / 2) {
                        let peak = max(abs(samples[frame * 2]), abs(samples[frame * 2 + 1]))
                        guard peak.isFinite else { throw AudioExportError.invalidSource }
                        let timelineFrame = position + Int64(frame)
                        let bucket = min(bucketCount - 1,
                                         Int(timelineFrame * Int64(bucketCount) / totalFrames))
                        peaks[bucket] = max(peaks[bucket], min(1, peak))
                    }
                    position += Int64(samples.count / 2)
                }
            }
            return peaks
        }
        return try await withTaskCancellationHandler(
            operation: { try await worker.value },
            onCancel: { worker.cancel() }
        )
    }
}

/// Frame-based selection keeps the editor, metadata, playback, and exports on
/// the same half-open 48 kHz timeline.
struct CustomTrimSelection: Equatable {
    static let minimumFrames: Int64 = 480 // 10 ms
    let totalFrames: Int64
    private(set) var startFrame: Int64
    private(set) var endFrame: Int64

    init(duration: TimeInterval, initialRange: AudioTrimRange?) {
        totalFrames = max(Self.minimumFrames, Int64((duration * 48_000).rounded()))
        if let initialRange, initialRange.isValid {
            startFrame = min(max(0, initialRange.startFrame), totalFrames - Self.minimumFrames)
            endFrame = min(max(startFrame + Self.minimumFrames, initialRange.endFrame), totalFrames)
        } else {
            startFrame = 0
            endFrame = totalFrames
        }
    }

    var range: AudioTrimRange { AudioTrimRange(startFrame: startFrame, endFrame: endFrame) }
    var startFraction: Double { Double(startFrame) / Double(totalFrames) }
    var endFraction: Double { Double(endFrame) / Double(totalFrames) }
    var duration: TimeInterval { Double(endFrame - startFrame) / 48_000 }

    mutating func setStart(fraction: Double) {
        let proposed = Int64((fraction.clamped(to: 0...1) * Double(totalFrames)).rounded())
        startFrame = min(proposed, endFrame - Self.minimumFrames)
    }

    mutating func setEnd(fraction: Double) {
        let proposed = Int64((fraction.clamped(to: 0...1) * Double(totalFrames)).rounded())
        endFrame = max(proposed, startFrame + Self.minimumFrames)
    }
}

struct CustomTrimEditorState {
    let recordingID: UUID
    let title: String
    let waveform: [Float]
    var selection: CustomTrimSelection
    var playheadFrame: Int64
    var isPlaying = false

    var playheadFraction: Double {
        Double(playheadFrame) / Double(selection.totalFrames)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

/// Compact waveform editor used in place of the live recorder card.
struct CustomTrimWaveformView: View {
    enum DragTarget { case start, end, playhead }
    let samples: [Float]
    let totalFrames: Int64
    let start: Double
    let end: Double
    let playhead: Double
    let setStart: (Double) -> Void
    let setEnd: (Double) -> Void
    let seek: (Double) -> Void
    @State private var dragTarget: DragTarget?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = width * start
            let endX = width * end
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07))
                Canvas { context, size in
                    guard !samples.isEmpty else { return }
                    let step = size.width / CGFloat(samples.count)
                    for (index, sample) in samples.enumerated() {
                        let height = max(1, CGFloat(sqrt(max(0, sample))) * (size.height - 14))
                        let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                          width: max(1, step), height: height)
                        context.fill(Path(rect), with: .color(.primary.opacity(0.72)))
                    }
                }
                Color.black.opacity(0.44).frame(width: max(0, startX))
                Color.black.opacity(0.44).frame(width: max(0, width - endX)).offset(x: endX)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.mint, lineWidth: 4)
                    .frame(width: max(1, endX - startX)).offset(x: startX)
                handle.offset(x: startX - 8)
                handle.offset(x: endX - 8)
                Rectangle().fill(Color.primary.opacity(0.85)).frame(width: 1, height: 52)
                    .offset(x: width * playhead).allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let fraction = (value.location.x / max(1, width)).clamped(to: 0...1)
                    if dragTarget == nil {
                        let startDistance = abs(value.startLocation.x - startX)
                        let endDistance = abs(value.startLocation.x - endX)
                        dragTarget = min(startDistance, endDistance) < 22
                            ? (startDistance <= endDistance ? .start : .end) : .playhead
                    }
                    switch dragTarget {
                    case .start: setStart(fraction)
                    case .end: setEnd(fraction)
                    case .playhead: seek(fraction)
                    case nil: break
                    }
                }
                .onEnded { _ in dragTarget = nil })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Custom trim waveform")
        .accessibilityValue("Keeping from \(time(start)) to \(time(end))")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5).fill(Color.mint).frame(width: 16, height: 64)
            .overlay(Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 16))
    }

    private func time(_ fraction: Double) -> String {
        RecorderStore.durationLabel(Double(Int64((fraction * Double(totalFrames)).rounded())) / 48_000)
    }
}
