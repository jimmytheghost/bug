import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecorderStore: ObservableObject {
    enum Phase { case idle, starting, recording, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published var includeMicrophone = UserDefaults.standard.bool(forKey: "includeMicrophone") {
        didSet { UserDefaults.standard.set(includeMicrophone, forKey: "includeMicrophone") }
    }
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 64)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var exportingID: UUID?
    @Published private(set) var playingID: UUID?
    @Published private(set) var preparingPlaybackID: UUID?

    private var library: RecordingLibrary?
    private let engine = CaptureEngine()
    private let exporter = AudioExporter()
    private var sessionID: UUID?
    private var startedAt: Date?
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var playbackURL: URL?
    private var playbackTask: Task<Void, Never>?
    private var latestLevel: Float = 0
    private var latestLevelAt = Date.distantPast
    private var failedWhileStarting = false

    var isBusy: Bool { phase != .idle }
    var canQuit: Bool { !isBusy && exportingID == nil }

    init() {
        do {
            let library = try RecordingLibrary()
            self.library = library
            recordings = try library.load()
        } catch { errorMessage = "Could not open the recording library: \(error.localizedDescription)" }
        engine.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .recording else { return }
                self.latestLevel = min(1, max(0, level))
                self.latestLevelAt = Date()
            }
        }
        engine.onFailure = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.errorMessage = "Recording interrupted: \(error.localizedDescription)"
                if self.phase == .starting { self.failedWhileStarting = true }
                if self.phase == .recording { await self.stop() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.phase == .recording, let startedAt = self.startedAt {
                    self.elapsed = Date().timeIntervalSince(startedAt)
                    self.levels.removeFirst()
                    self.levels.append(Date().timeIntervalSince(self.latestLevelAt) < 0.2 ? self.latestLevel : 0)
                }
                if self.playingID != nil, self.player?.isPlaying != true { self.stopPlayback() }
            }
        }
    }

    func start() async {
        guard phase == .idle, let library else { return }
        stopPlayback()
        phase = .starting
        failedWhileStarting = false
        errorMessage = nil
        notice = nil
        elapsed = 0
        levels = Array(repeating: 0, count: 64)
        let id = UUID()
        sessionID = id
        do {
            let directory = try library.createSession(id: id)
            try await engine.start(directory: directory, includeMicrophone: includeMicrophone)
            startedAt = Date()
            phase = .recording
            if failedWhileStarting { await stop() }
        } catch {
            phase = .idle
            sessionID = nil
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard phase == .recording, let id = sessionID, let library else { return }
        phase = .stopping
        defer { phase = .idle; sessionID = nil; startedAt = nil }
        do {
            let result = try await engine.stop()
            let date = startedAt ?? Date()
            let recording = Recording(id: id, createdAt: date,
                title: "Recording \(date.formatted(date: .abbreviated, time: .shortened))",
                duration: result.duration, systemFilename: result.systemURL.lastPathComponent,
                microphoneFilename: result.microphoneURL?.lastPathComponent)
            try library.save(recording)
            recordings = try library.load()
            elapsed = result.duration
            notice = "Saved to your library."
        } catch {
            errorMessage = "Could not finalize recording: \(error.localizedDescription) Audio files remain in the library folder."
        }
    }

    func export(_ recording: Recording, format: AudioExportFormat) async {
        guard exportingID == nil, let library else { return }
        exportingID = recording.id
        defer { exportingID = nil }
        let panel = NSSavePanel()
        panel.title = "Export recording"
        panel.nameFieldStringValue = recording.title.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: "-") + "." + format.rawValue
        panel.allowedContentTypes = [format == .wav ? .wav : .mp3]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let destination = panel.url else { return }
        errorMessage = nil
        do {
            try await exporter.export(systemURL: library.url(for: recording),
                microphoneURL: recording.microphoneFilename == nil ? nil : library.url(for: recording, microphone: true),
                to: destination, format: format)
            notice = "Exported \(destination.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch { errorMessage = "Export failed: \(error.localizedDescription) Your original recording is safe." }
    }

    func togglePlayback(_ recording: Recording) {
        if playingID == recording.id || preparingPlaybackID == recording.id { stopPlayback(); return }
        guard !isBusy, let library else { return }
        stopPlayback()
        preparingPlaybackID = recording.id
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Bug-preview-\(UUID().uuidString).wav")
        playbackTask = Task {
            do {
                try await exporter.export(systemURL: library.url(for: recording),
                    microphoneURL: recording.microphoneFilename == nil ? nil : library.url(for: recording, microphone: true),
                    to: url, format: .wav)
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: url); return }
                let player = try AVAudioPlayer(contentsOf: url)
                guard player.play() else { throw CocoaError(.fileReadUnknown) }
                self.player = player
                playbackURL = url
                playingID = recording.id
                preparingPlaybackID = nil
            } catch {
                try? FileManager.default.removeItem(at: url)
                guard !Task.isCancelled else { return }
                preparingPlaybackID = nil
                errorMessage = "Could not play recording: \(error.localizedDescription)"
            }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        player?.stop()
        player = nil
        playingID = nil
        preparingPlaybackID = nil
        if let playbackURL { try? FileManager.default.removeItem(at: playbackURL) }
        playbackURL = nil
    }

    func rename(_ recording: Recording, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let library else { return }
        var updated = recording
        updated.title = title
        do { try library.save(updated); recordings = try library.load() }
        catch { errorMessage = "Could not rename recording: \(error.localizedDescription)" }
    }

    func delete(_ recording: Recording) {
        guard exportingID != recording.id, let library else { return }
        if playingID == recording.id || preparingPlaybackID == recording.id { stopPlayback() }
        do { try library.delete(recording); recordings = try library.load() }
        catch { errorMessage = "Could not move recording to Trash: \(error.localizedDescription)" }
    }

    func revealLibrary() { if let library { NSWorkspace.shared.open(library.root) } }
    func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.isFinite ? duration : 0))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
