import AVFoundation
import CoreMedia
import ScreenCaptureKit

protocol AudioCapturing: AnyObject {
    var onLevel: ((Float) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
    func start(directory: URL, includeMicrophone: Bool) async throws
    func stop() async throws -> CaptureResult
}

/// Recoverable sources are system.caf and (if requested) microphone.caf inside directory.
/// Float32 linear PCM CAF, system 48 kHz stereo; microphone native rate/channel count.
/// Both tracks start at a common host-clock epoch, including leading/intermediate/trailing silence.
struct CaptureResult: Sendable {
    let systemURL: URL
    let microphoneURL: URL?
    let duration: TimeInterval
}

enum CaptureError: LocalizedError {
    case alreadyRecording, notRecording, microphonePermission, microphoneUnavailable
    case screenPermission, noDisplay, invalidAudio, invalidTimestamp, formatChanged, overloaded, existingFiles
    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "A recording is already starting, running, or stopping."
        case .notRecording: return "There is no active recording."
        case .microphonePermission: return "Allow Bug to use the microphone in System Settings → Privacy & Security → Microphone."
        case .microphoneUnavailable: return "No microphone is available. Connect a microphone or record system audio only."
        case .screenPermission: return "Allow Bug in System Settings → Privacy & Security → Screen & System Audio Recording, then try again. You may need to reopen Bug."
        case .noDisplay: return "ScreenCaptureKit could not find an available display for system audio capture."
        case .invalidAudio: return "The capture stream supplied unsupported or invalid PCM audio."
        case .invalidTimestamp: return "The capture stream supplied an invalid audio timestamp."
        case .formatChanged: return "The audio device format changed during recording. The existing recording has been preserved."
        case .overloaded: return "Audio writing could not keep up. Recording stopped and the existing audio has been preserved."
        case .existingFiles: return "This capture directory already contains source audio. Choose a new session directory."
        }
    }
}

/// Callback properties are safe to replace while capturing; callbacks execute off-main.
final class CaptureEngine: AudioCapturing, @unchecked Sendable {
    private let callbacks = CaptureCallbacks()
    private let lifecycle = CaptureLifecycle()
    var onLevel: ((Float) -> Void)? {
        get { callbacks.lock.withLock { callbacks.level } }
        set { callbacks.lock.withLock { callbacks.level = newValue } }
    }
    var onFailure: ((Error) -> Void)? {
        get { callbacks.lock.withLock { callbacks.failure } }
        set { callbacks.lock.withLock { callbacks.failure = newValue } }
    }
    func start(directory: URL, includeMicrophone: Bool) async throws {
        try Task.checkCancellation()
        try await lifecycle.start(directory: directory, microphone: includeMicrophone, callbacks: callbacks)
        if Task.isCancelled {
            _ = try? await lifecycle.stop()
            throw CancellationError()
        }
    }
    func stop() async throws -> CaptureResult { try await lifecycle.stop() }
}

private final class CaptureCallbacks: @unchecked Sendable {
    let lock = NSLock()
    var level: ((Float) -> Void)?
    var failure: ((Error) -> Void)?
    func emitLevel(_ value: Float) { lock.withLock { level }?(value) }
    func emitFailure(_ error: Error) { lock.withLock { failure }?(error) }
}

/// Coalesces concurrent stops, and lets stop wait for an in-flight permission/start operation.
private actor CaptureLifecycle {
    private var starting: Task<CaptureSession, Error>?
    private var stopping: Task<CaptureResult, Error>?
    private var session: CaptureSession?
    private var generation = UUID()

    func start(directory: URL, microphone: Bool, callbacks: CaptureCallbacks) async throws {
        guard starting == nil, stopping == nil, session == nil else { throw CaptureError.alreadyRecording }
        let id = UUID()
        generation = id
        let task = Task { try await CaptureSession.start(directory: directory, microphone: microphone, callbacks: callbacks) }
        starting = task
        do {
            let created = try await task.value
            if generation == id, starting != nil { session = created; starting = nil }
        } catch {
            if generation == id { starting = nil }
            throw error
        }
    }

    func stop() async throws -> CaptureResult {
        if let stopping { return try await stopping.value }
        if let starting {
            let created = try await starting.value
            if let stopping { return try await stopping.value }
            // A different waiter may already have completed the stop.
            guard self.starting != nil || session != nil else { throw CaptureError.notRecording }
            session = created
            self.starting = nil
        }
        guard let current = session else { throw CaptureError.notRecording }
        let task = Task { try await current.stop() }
        stopping = task
        session = nil
        defer { stopping = nil }
        return try await task.value
    }
}

private final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let ingress = DispatchQueue(label: "Bug.capture.ingress", qos: .userInitiated)
    private let writer = DispatchQueue(label: "Bug.capture.writer", qos: .userInitiated)
    private let slots = DispatchSemaphore(value: 16)
    private let gate = NSLock()
    private var accepting = true
    private var overloadReported = false
    private let callbacks: CaptureCallbacks
    private let system: CapturePCMWriter
    private let microphone: CapturePCMWriter?
    private var stream: SCStream?
    // Everything below is confined to writer, except epoch (set before capture starts).
    private var epoch = CMTime.zero
    private var failure: Error?
    private var recovered: CaptureResult?
    private var lastLevelTime = -Double.infinity
    private var systemLevel: (Double, Float) = (0, 0)
    private var microphoneLevel: (Double, Float) = (0, 0)

    private init(directory: URL, microphone: Bool, callbacks: CaptureCallbacks) {
        self.callbacks = callbacks
        system = CapturePCMWriter(url: directory.appendingPathComponent("system.caf"))
        self.microphone = microphone ? CapturePCMWriter(url: directory.appendingPathComponent("microphone.caf")) : nil
    }

    static func start(directory: URL, microphone: Bool, callbacks: CaptureCallbacks) async throws -> CaptureSession {
        if microphone {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            var allowed = status == .authorized
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
            guard allowed else { throw CaptureError.microphonePermission }
            guard AVCaptureDevice.default(for: .audio) != nil else { throw CaptureError.microphoneUnavailable }
        }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { throw map(error) }
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = CaptureSession(directory: directory, microphone: microphone, callbacks: callbacks)
        for path in [session.system.url, session.microphone?.url].compactMap({ $0 }) {
            guard !FileManager.default.fileExists(atPath: path.path) else { throw CaptureError.existingFiles }
        }
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = false
        configuration.captureMicrophone = microphone
        // SCK needs a display filter, but no video is persisted or inspected.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 600)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: session)
        session.stream = stream
        do {
            try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.ingress)
            try stream.addStreamOutput(session, type: .audio, sampleHandlerQueue: session.ingress)
            if microphone { try stream.addStreamOutput(session, type: .microphone, sampleHandlerQueue: session.ingress) }
            try session.system.open(format: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!)
            session.epoch = CMClockGetTime(CMClockGetHostTimeClock())
            try await stream.startCapture()
            try await session.checkFailure()
            return session
        } catch {
            _ = try? await session.stop()
            throw map(error)
        }
    }

    private static func map(_ error: Error) -> Error {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == -3801 ? CaptureError.screenPermission : error
    }

    private func checkFailure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async { if let error = self.failure { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio || type == .microphone else { return }
        // Bound retained sample count AND individual size before taking ownership.
        gate.lock()
        guard accepting else { gate.unlock(); return }
        guard CMSampleBufferGetNumSamples(sampleBuffer) <= 16_384,
              CMSampleBufferGetTotalSampleSize(sampleBuffer) <= 1024 * 1024,
              slots.wait(timeout: .now()) == .success else {
            accepting = false
            let report = !overloadReported
            overloadReported = true
            gate.unlock()
            if report { writer.async { self.fail(CaptureError.overloaded) } }
            return
        }
        writer.async {
            defer { self.slots.signal() }
            guard self.failure == nil else { return }
            do { try self.consume(sampleBuffer, microphone: type == .microphone) }
            catch { self.fail(error) }
        }
        gate.unlock()
    }

    private func consume(_ sample: CMSampleBuffer, microphone isMicrophone: Bool) throws {
        guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { throw CaptureError.invalidAudio }
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let seconds = CMTimeGetSeconds(CMTimeSubtract(pts, epoch))
        let now = CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), epoch))
        guard seconds.isFinite, seconds >= -5, seconds <= now + 5 else { throw CaptureError.invalidTimestamp }
        guard let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaSubType(description) == kAudioFormatLinearPCM else { throw CaptureError.invalidAudio }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.sampleRate >= 8_000, format.sampleRate <= 192_000,
              format.channelCount > 0, format.channelCount <= 2,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw CaptureError.invalidAudio
        }
        pcm.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList) == noErr else {
            throw CaptureError.invalidAudio
        }
        let track = isMicrophone ? microphone : system
        let level = try track?.append(pcm, seconds: seconds) ?? 0
        if isMicrophone { microphoneLevel = (now, level) } else { systemLevel = (now, level) }
        if now - lastLevelTime >= 0.05 {
            lastLevelTime = now
            let a = now - systemLevel.0 < 0.2 ? systemLevel.1 : 0
            let b = now - microphoneLevel.0 < 0.2 ? microphoneLevel.1 : 0
            callbacks.emitLevel(min(1, sqrt(a * a + b * b)))
        }
    }

    private func fail(_ error: Error) {
        guard failure == nil else { return }
        failure = error
        gate.withLock { accepting = false }
        recovered = recover()
        callbacks.emitFailure(Self.map(error))
        if let stream { Task { try? await stream.stopCapture() } }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        writer.async { self.fail(error) }
    }

    func stop() async throws -> CaptureResult {
        // Fence ingress before finalizing, so no callback can enqueue after the writer barrier.
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        var stopError: Error?
        if let stream { do { try await stream.stopCapture() } catch { stopError = error } }
        gate.withLock { accepting = false }
        let capturedError = stopError
        return try await withCheckedThrowingContinuation { continuation in
            writer.async {
                defer { self.system.close(); self.microphone?.close(); self.stream = nil }
                do {
                    if let error = self.failure ?? capturedError {
                        if let result = self.recovered ?? self.recover() {
                            if self.failure == nil { self.callbacks.emitFailure(Self.map(error)) }
                            continuation.resume(returning: result)
                            return
                        }
                        throw Self.map(error)
                    }
                    if let mic = self.microphone, mic.format == nil { throw CaptureError.microphoneUnavailable }
                    let elapsed = max(0, CMTimeGetSeconds(CMTimeSubtract(end, self.epoch)))
                    let systemDuration = Double(self.system.frames) / (self.system.format?.sampleRate ?? 48_000)
                    let micDuration = Double(self.microphone?.frames ?? 0) / (self.microphone?.format?.sampleRate ?? 48_000)
                    let duration = max(elapsed, systemDuration, micDuration)
                    try self.system.finish(duration: duration)
                    try self.microphone?.finish(duration: duration)
                    self.callbacks.emitLevel(0)
                    continuation.resume(returning: CaptureResult(systemURL: self.system.url,
                                                                 microphoneURL: self.microphone?.url, duration: duration))
                } catch {
                    if let result = self.recover() {
                        self.callbacks.emitFailure(error)
                        continuation.resume(returning: result)
                    } else { continuation.resume(throwing: error) }
                }
            }
        }
    }

    /// Best effort alignment on failure. If storage is exhausted, preserve readable shorter
    /// tracks as-is; the exporter should treat a shorter track's tail as silence.
    private func recover() -> CaptureResult? {
        if let recovered { return recovered }
        let result = CapturePCMWriter.recover(system: system, microphone: microphone)
        recovered = result
        return result
    }
}
