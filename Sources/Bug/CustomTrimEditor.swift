import SwiftUI

/// A bounded overview of the original recording. Tracks share the same 48 kHz
/// export timeline, so their peaks can be merged without retaining source PCM.
struct AudioWaveformAnalyzer: Sendable {
    func analyze(systemURL: URL, microphoneURL: URL?, duration: TimeInterval,
                 bucketCount: Int = 7_200) async throws -> [Float] {
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

enum CustomTrimEdge: Equatable { case start, end }

struct CustomTrimZoom {
    static let magnification = 10.0

    static func adjustedFraction(anchor: Double, translation: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return anchor }
        return anchor + Double(translation / width) / magnification
    }

    static func detailSamples(_ samples: [Float], boundary: Double, edge: CustomTrimEdge) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let count = max(2, Int(ceil(Double(samples.count) / magnification)))
        let boundaryIndex = Int((boundary.clamped(to: 0...1) * Double(samples.count)).rounded())
        let first = edge == .start ? boundaryIndex : boundaryIndex - count
        return (0..<count).map { offset in
            let index = first + offset
            return samples.indices.contains(index) ? samples[index] : 0
        }
    }

    static func overviewSamples(_ samples: [Float], maximumCount: Int = 720) -> [Float] {
        guard samples.count > maximumCount, maximumCount > 0 else { return samples }
        let groupSize = Int(ceil(Double(samples.count) / Double(maximumCount)))
        return stride(from: 0, to: samples.count, by: groupSize).map { start in
            samples[start..<min(samples.count, start + groupSize)].max() ?? 0
        }
    }
}

/// Compact waveform editor used in place of the live recorder card.
struct CustomTrimWaveformView: View {
    enum DragTarget: Equatable { case edge(CustomTrimEdge), playhead }
    let samples: [Float]
    let totalFrames: Int64
    let start: Double
    let end: Double
    let playhead: Double
    let setStart: (Double) -> Void
    let setEnd: (Double) -> Void
    let seek: (Double) -> Void
    let beginBoundaryEdit: () -> Void
    @State private var dragTarget: DragTarget?
    @State private var zoomEdge: CustomTrimEdge?
    @State private var holdToken: UUID?
    @State private var dragOriginX: CGFloat = 0
    @State private var latestPointerX: CGFloat = 0
    @State private var zoomAnchorFraction: Double = 0
    @State private var latestBoundaryFraction: Double?

    init(samples: [Float], totalFrames: Int64, start: Double, end: Double, playhead: Double,
         setStart: @escaping (Double) -> Void, setEnd: @escaping (Double) -> Void,
         seek: @escaping (Double) -> Void, beginBoundaryEdit: @escaping () -> Void = {},
         initialZoomEdge: CustomTrimEdge? = nil) {
        self.samples = samples
        self.totalFrames = totalFrames
        self.start = start
        self.end = end
        self.playhead = playhead
        self.setStart = setStart
        self.setEnd = setEnd
        self.seek = seek
        self.beginBoundaryEdit = beginBoundaryEdit
        _zoomEdge = State(initialValue: initialZoomEdge)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = width * start
            let endX = width * end
            let visibleSamples = zoomEdge.map {
                CustomTrimZoom.detailSamples(samples, boundary: $0 == .start ? start : end, edge: $0)
            } ?? CustomTrimZoom.overviewSamples(samples)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07))
                Canvas { context, size in
                    guard !visibleSamples.isEmpty else { return }
                    let step = size.width / CGFloat(visibleSamples.count)
                    for (index, sample) in visibleSamples.enumerated() {
                        let height = max(1, CGFloat(sqrt(max(0, sample))) * (size.height - 14))
                        let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2,
                                          width: max(1, step), height: height)
                        context.fill(Path(rect), with: .color(.primary.opacity(0.72)))
                    }
                }
                if let zoomEdge {
                    Rectangle().fill(Color.mint).frame(width: 6, height: 64)
                        .offset(x: zoomEdge == .start ? 0 : width - 6)
                    Text(zoomEdge == .start ? "10× HEAD" : "10× TAIL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.mint, in: Capsule())
                        .padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                } else {
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
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let fraction = (value.location.x / max(1, width)).clamped(to: 0...1)
                    latestPointerX = value.location.x
                    if dragTarget == nil {
                        let startDistance = abs(value.startLocation.x - startX)
                        let endDistance = abs(value.startLocation.x - endX)
                        let target: DragTarget = min(startDistance, endDistance) < 22
                            ? .edge(startDistance <= endDistance ? .start : .end) : .playhead
                        dragTarget = target
                        if case .edge(let edge) = target {
                            beginBoundaryEdit()
                            let token = UUID()
                            holdToken = token
                            dragOriginX = value.startLocation.x
                            zoomAnchorFraction = edge == .start ? start : end
                            latestBoundaryFraction = zoomAnchorFraction
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                guard holdToken == token, dragTarget == target else { return }
                                zoomEdge = edge
                                dragOriginX = latestPointerX
                                zoomAnchorFraction = edge == .start ? start : end
                                latestBoundaryFraction = zoomAnchorFraction
                            }
                        }
                    }
                    switch dragTarget {
                    case .edge(let edge):
                        if zoomEdge == edge {
                            let adjusted = boundedBoundary(CustomTrimZoom.adjustedFraction(
                                anchor: zoomAnchorFraction,
                                translation: value.location.x - dragOriginX,
                                width: width
                            ), edge: edge)
                            latestBoundaryFraction = adjusted
                            if edge == .start { setStart(adjusted) } else { setEnd(adjusted) }
                        } else if abs(value.translation.width) > 8 {
                            holdToken = nil
                            let adjusted = boundedBoundary(fraction, edge: edge)
                            latestBoundaryFraction = adjusted
                            if edge == .start { setStart(adjusted) } else { setEnd(adjusted) }
                        }
                    case .playhead: seek(fraction)
                    case nil: break
                    }
                }
                .onEnded { value in
                    holdToken = nil
                    if case .edge(let edge) = dragTarget {
                        if zoomEdge == nil, abs(value.translation.width) <= 8 {
                            let fraction = boundedBoundary(
                                (value.location.x / max(1, width)).clamped(to: 0...1), edge: edge)
                            latestBoundaryFraction = fraction
                            if edge == .start { setStart(fraction) } else { setEnd(fraction) }
                        }
                        if edge == .start { seek(latestBoundaryFraction ?? start) }
                    }
                    zoomEdge = nil
                    dragTarget = nil
                    latestBoundaryFraction = nil
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Custom trim waveform")
        .accessibilityValue("Keeping from \(time(start)) to \(time(end)). Hold a trim handle for 10 times magnification.")
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5).fill(Color.mint).frame(width: 16, height: 64)
            .overlay(Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 16))
    }

    private func time(_ fraction: Double) -> String {
        RecorderStore.durationLabel(Double(Int64((fraction * Double(totalFrames)).rounded())) / 48_000)
    }

    private func boundedBoundary(_ fraction: Double, edge: CustomTrimEdge) -> Double {
        let minimum = Double(CustomTrimSelection.minimumFrames) / Double(totalFrames)
        let fraction = fraction.clamped(to: 0...1)
        return edge == .start ? min(fraction, end - minimum) : max(fraction, start + minimum)
    }
}
