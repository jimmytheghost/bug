import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class RecorderStore: ObservableObject {
    enum Phase { case idle, starting, recording, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published var includeMicrophone: Bool {
        didSet { preferences.set(includeMicrophone, forKey: "includeMicrophone") }
    }
    @Published var trimPadding: Double {
        didSet { preferences.set(trimPadding, forKey: "trimPadding") }
    }
    @Published var silenceReminderDelay: SilenceReminderDelay {
        didSet {
            preferences.set(silenceReminderDelay.rawValue, forKey: "silenceReminderDelay")
            silenceMonitor.configure(silenceReminderDelay, at: monotonicTime())
            reminderPresenter.dismiss()
        }
    }
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var recordingBytes: [UUID: Int64] = [:]
    @Published private(set) var librarySessionIDs: [UUID] = []
    @Published private(set) var libraryBytes: Int64?

    @Published private(set) var levels: [Float] = Array(repeating: 0, count: 64)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var exportingID: UUID?
    @Published private(set) var playingID: UUID?
    @Published private(set) var preparingPlaybackID: UUID?
    @Published private(set) var trimmingID: UUID?
    @Published private(set) var preparingCustomTrimID: UUID?
    @Published private(set) var customTrimState: CustomTrimEditorState?
    @Published private(set) var pendingRecordingDeletion: Recording?

    private var confirmingDeletion = false
    private var confirmingRecordingDeletion = false
    private var library: RecordingLibrary?
    private let trashRecording: ((UUID) throws -> Void)?
    private let engine: any AudioCapturing
    private let exporter = AudioExporter()
    private var sessionID: UUID?
    private var startedAt: Date?
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var playbackURL: URL?
    private var playbackTask: Task<Void, Never>?
    private var customTrimPlayer: AVAudioPlayer?
    private var customTrimPreviewURL: URL?
    private var latestLevel: Float = 0
    private var latestLevelAt = Date.distantPast
    private var failedWhileStarting = false
    private let preferences: UserDefaults
    private let reminderPresenter: any SilenceReminderPresenting
    private let monotonicTime: () -> TimeInterval
    private var silenceMonitor = SilenceMonitor()

    var isBusy: Bool { phase != .idle || trimmingID != nil }
    var canDeleteAll: Bool { !isBusy && exportingID == nil && !librarySessionIDs.isEmpty }
    var canQuit: Bool { !isBusy && exportingID == nil }
    var canTrim: Bool { !isBusy && exportingID == nil }

    init(library: RecordingLibrary? = nil, preferences: UserDefaults = .standard, startTimer: Bool = true,
         engine: any AudioCapturing = CaptureEngine(), reminderPresenter: (any SilenceReminderPresenting)? = nil,
         trashRecording: ((UUID) throws -> Void)? = nil,
         monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.trashRecording = trashRecording
        self.preferences = preferences
        self.engine = engine
        self.reminderPresenter = reminderPresenter ?? SilenceReminderPresenter()
        self.monotonicTime = monotonicTime
        includeMicrophone = preferences.bool(forKey: "includeMicrophone")
        let padding = preferences.object(forKey: "trimPadding") as? Double ?? 0.5
        trimPadding = padding.isFinite && (0...2).contains(padding) ? padding : 0.5
        silenceReminderDelay = SilenceReminderDelay(rawValue: preferences.object(forKey: "silenceReminderDelay") as? Int ?? 30) ?? .thirtySeconds
        silenceMonitor.configure(silenceReminderDelay, at: monotonicTime())
        do {
            let library = try library ?? RecordingLibrary()
            self.library = library
            try reloadLibrary()
        } catch { errorMessage = "Could not open the recording library: \(error.localizedDescription)" }
        engine.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.receiveCaptureLevel(level)
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
        if startTimer {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.processMeterTick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    deinit { timer?.invalidate() }

    func start() async {
        guard !isBusy, let library else { return }
        stopPlayback()
        phase = .starting
        silenceMonitor.stop()
        reminderPresenter.dismiss()
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
            silenceMonitor.start(at: monotonicTime())
            if failedWhileStarting { await stop() }
        } catch {
            phase = .idle
            silenceMonitor.stop()
            reminderPresenter.dismiss()
            sessionID = nil
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stop() async {
        guard phase == .recording, let id = sessionID, let library else { return }
        phase = .stopping
        silenceMonitor.stop()
        reminderPresenter.dismiss()
        defer { phase = .idle; sessionID = nil; startedAt = nil }
        do {
            let result = try await engine.stop()
            let date = startedAt ?? Date()
            let recording = Recording(id: id, createdAt: date,
                title: "Recording \(date.formatted(date: .abbreviated, time: .shortened))",
                duration: result.duration, systemFilename: result.systemURL.lastPathComponent,
                microphoneFilename: result.microphoneURL?.lastPathComponent)
            try library.save(recording)
            try reloadLibrary()
            elapsed = result.duration
            notice = "Saved to your library."
        } catch {
            errorMessage = "Could not finalize recording: \(error.localizedDescription) Audio files remain in the library folder."
        }
    }

    /// Also called by deterministic tests; no dependency on the popover being open.
    func processMeterTick() {
        if phase == .recording, let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
            levels.removeFirst()
            levels.append(Date().timeIntervalSince(latestLevelAt) < 0.2 ? latestLevel : 0)
            if let id = silenceMonitor.tick(at: monotonicTime()) {
                reminderPresenter.show(delay: silenceReminderDelay, keepRecording: { [weak self] in
                    guard let self, self.phase == .recording,
                          self.silenceMonitor.keepRecording(reminder: id, at: self.monotonicTime()) else { return }
                    self.reminderPresenter.dismiss()
                }, stopRecording: { [weak self] in
                    guard let self, self.phase == .recording, self.silenceMonitor.pendingReminder == id else { return }
                    await self.stop()
                })
            }
        }
        if playingID != nil, player?.isPlaying != true { stopPlayback() }
        updateCustomTrimPlayback()
    }

    func receiveCaptureLevel(_ level: Float) {
        guard phase == .recording else { return }
        latestLevel = level.isFinite ? min(1, max(0, level)) : 0
        latestLevelAt = Date()
        let hadReminder = silenceMonitor.pendingReminder != nil
        silenceMonitor.observe(level: level, at: monotonicTime())
        if hadReminder && silenceMonitor.pendingReminder == nil { reminderPresenter.dismiss() }
    }

    func export(_ recording: Recording, format: AudioExportFormat) async {
        guard exportingID == nil, trimmingID == nil, let library else { return }
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
                to: destination, format: format, trimRange: recording.trimRange)
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
                    to: url, format: .wav, trimRange: recording.trimRange)
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
        guard !title.isEmpty, trimmingID != recording.id, let library,
              var updated = recordings.first(where: { $0.id == recording.id }) else { return }
        updated.title = title
        do { try library.save(updated); try reloadLibrary() }
        catch { errorMessage = "Could not rename recording: \(error.localizedDescription)" }
    }

    func delete(_ recording: Recording) {
        guard exportingID != recording.id, trimmingID != recording.id, let library else { return }
        if playingID == recording.id || preparingPlaybackID == recording.id { stopPlayback() }
        do {
            if let trashRecording { try trashRecording(recording.id) }
            else { try library.delete(recording) }
            try reloadLibrary()
            notice = "Moved to Trash. Exported copies are unchanged."
        }
        catch { errorMessage = "Could not move recording to Trash: \(error.localizedDescription)" }
    }

    /// UI requests remain inside the MenuBarExtra panel so confirmation does not
    /// dismiss it. Tests can inject a synchronous confirmation decision.
    func requestDelete(_ recording: Recording, confirm: ((Recording) -> Bool)? = nil) {
        guard pendingRecordingDeletion == nil, !confirmingRecordingDeletion else { return }
        refreshLibrary()
        guard exportingID != recording.id, trimmingID != recording.id,
              let current = recordings.first(where: { $0.id == recording.id }) else { return }
        if let confirm {
            confirmingRecordingDeletion = true
            defer { confirmingRecordingDeletion = false }
            if confirm(current) { delete(current) }
        } else {
            pendingRecordingDeletion = current
        }
    }

    func cancelRecordingDeletion() {
        pendingRecordingDeletion = nil
    }

    func confirmRecordingDeletion() {
        guard let recording = pendingRecordingDeletion else { return }
        pendingRecordingDeletion = nil
        delete(recording)
    }

    /// The application-modal dialog owns its lifetime independently of MenuBarExtra.
    func requestDeleteAll(confirm: ((Int) -> Bool)? = nil) {
        guard !confirmingDeletion else { return }
        refreshLibrary()
        guard canDeleteAll else { return }
        let snapshot = librarySessionIDs
        confirmingDeletion = true
        defer { confirmingDeletion = false }
        let approved: Bool
        if let confirm {
            approved = confirm(snapshot.count)
        } else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Delete all recordings?"
            alert.informativeText = "Move all \(snapshot.count) session folders to macOS Trash, including saved recordings and empty or unfinished sessions? Exported copies elsewhere are kept. You can recover recordings from Trash; empty it to free disk space."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Delete All")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = ""
            alert.window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            approved = alert.runModal() == .alertSecondButtonReturn
        }
        if approved { deleteSessions(snapshot) }
    }

    /// Only deletes the snapshot the user confirmed, never newly added recordings.
    func deleteAll(_ confirmed: [Recording]) {
        deleteSessions(confirmed.map(\.id))
    }

    func deleteSessions(_ confirmed: [UUID]) {
        guard canDeleteAll, let library else { return }
        stopPlayback()
        errorMessage = nil
        notice = nil
        var moved = 0
        var failures = 0
        for id in Set(confirmed) {
            guard librarySessionIDs.contains(id) else { continue }
            guard FileManager.default.fileExists(atPath: library.directory(for: id).path) else { continue }
            do {
                if let trashRecording { try trashRecording(id) }
                else { try library.deleteSession(id) }
                moved += 1
            } catch { failures += 1 }
        }
        do { try reloadLibrary() }
        catch { errorMessage = "Could not refresh the library after deletion: \(error.localizedDescription)" }
        if failures > 0 {
            errorMessage = "Moved \(moved) session folders to Trash. Could not move \(failures); they remain in the Library folder."
        } else {
            notice = "Moved \(moved) session folders to Trash. Exported copies are unchanged."
        }
    }

    func trim(_ recording: Recording) async {
        guard canTrim, let library,
              let current = recordings.first(where: { $0.id == recording.id }), current.trimRange == nil else { return }
        stopPlayback()
        trimmingID = current.id
        errorMessage = nil
        notice = nil
        defer { trimmingID = nil }
        do {
            let range = try await AudioTrimmer().analyze(systemURL: library.url(for: current),
                microphoneURL: current.microphoneFilename == nil ? nil : library.url(for: current, microphone: true),
                padding: trimPadding)
            try Task.checkCancellation()
            guard let range else {
                notice = "No silence to trim, or no clear audio found. Recording unchanged."
                return
            }
            var updated = current
            updated.trimRange = range
            try library.save(updated)
            if let index = recordings.firstIndex(where: { $0.id == updated.id }) { recordings[index] = updated }
            notice = "Trimmed. Undo restores the original recording."
        } catch is CancellationError {
            notice = "Trim cancelled. Recording unchanged."
        } catch { errorMessage = "Trim failed: \(error.localizedDescription) Your original recording is safe." }
    }

    func customTrim(_ recording: Recording) async {
        guard canTrim, let library,
              let current = recordings.first(where: { $0.id == recording.id }) else { return }
        stopPlayback()
        trimmingID = current.id
        preparingCustomTrimID = current.id
        errorMessage = nil
        notice = nil
        let previewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bug-custom-trim-\(UUID().uuidString).wav")
        do {
            async let waveform = AudioWaveformAnalyzer().analyze(
                systemURL: library.url(for: current),
                microphoneURL: current.microphoneFilename == nil ? nil : library.url(for: current, microphone: true),
                duration: current.duration
            )
            async let preview: Void = exporter.export(
                systemURL: library.url(for: current),
                microphoneURL: current.microphoneFilename == nil ? nil : library.url(for: current, microphone: true),
                to: previewURL, format: .wav, trimRange: nil
            )
            let peaks = try await waveform
            try await preview
            try Task.checkCancellation()
            guard trimmingID == current.id else {
                try? FileManager.default.removeItem(at: previewURL)
                return
            }
            let player = try AVAudioPlayer(contentsOf: previewURL)
            player.prepareToPlay()
            let selection = CustomTrimSelection(duration: current.duration, initialRange: current.trimRange)
            customTrimPlayer = player
            customTrimPreviewURL = previewURL
            preparingCustomTrimID = nil
            customTrimState = CustomTrimEditorState(recordingID: current.id, title: current.title,
                                                     waveform: peaks, selection: selection,
                                                     playheadFrame: selection.startFrame)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: previewURL)
            if trimmingID == current.id { trimmingID = nil }
            if preparingCustomTrimID == current.id { preparingCustomTrimID = nil }
            notice = "Custom Trim cancelled. Recording unchanged."
        } catch {
            try? FileManager.default.removeItem(at: previewURL)
            if trimmingID == current.id { trimmingID = nil }
            if preparingCustomTrimID == current.id { preparingCustomTrimID = nil }
            errorMessage = "Could not open Custom Trim: \(error.localizedDescription) Your original recording is safe."
        }
    }

    func setCustomTrimStart(_ fraction: Double) {
        guard var state = customTrimState else { return }
        state.selection.setStart(fraction: fraction)
        if state.playheadFrame < state.selection.startFrame {
            state.playheadFrame = state.selection.startFrame
            customTrimPlayer?.currentTime = Double(state.playheadFrame) / 48_000
        }
        customTrimState = state
    }

    func setCustomTrimEnd(_ fraction: Double) {
        guard var state = customTrimState else { return }
        state.selection.setEnd(fraction: fraction)
        if state.playheadFrame > state.selection.endFrame {
            state.playheadFrame = state.selection.endFrame
            customTrimPlayer?.currentTime = Double(state.playheadFrame) / 48_000
        }
        customTrimState = state
    }

    func seekCustomTrim(_ fraction: Double) {
        guard var state = customTrimState else { return }
        let bounded = fraction.clamped(to: state.selection.startFraction...state.selection.endFraction)
        state.playheadFrame = Int64((bounded * Double(state.selection.totalFrames)).rounded())
        customTrimPlayer?.currentTime = Double(state.playheadFrame) / 48_000
        customTrimState = state
    }

    func skipCustomTrim(seconds: TimeInterval) {
        guard let state = customTrimState else { return }
        let frame = state.playheadFrame + Int64((seconds * 48_000).rounded())
        seekCustomTrim(Double(frame) / Double(state.selection.totalFrames))
    }

    func toggleCustomTrimPlayback() {
        guard var state = customTrimState, let customTrimPlayer else { return }
        if state.isPlaying {
            customTrimPlayer.pause()
            state.isPlaying = false
        } else {
            if state.playheadFrame >= state.selection.endFrame {
                state.playheadFrame = state.selection.startFrame
            }
            customTrimPlayer.currentTime = Double(state.playheadFrame) / 48_000
            state.isPlaying = customTrimPlayer.play()
        }
        customTrimState = state
    }

    func saveCustomTrim() {
        guard let state = customTrimState, trimmingID == state.recordingID, let library,
              var current = recordings.first(where: { $0.id == state.recordingID }) else { return }
        customTrimPlayer?.pause()
        let range = state.selection.range
        let totalFrames = max(CustomTrimSelection.minimumFrames, Int64((current.duration * 48_000).rounded()))
        guard range.isValid, range.startFrame >= 0, range.endFrame <= totalFrames else {
            errorMessage = "Custom Trim selection is invalid. Recording unchanged."
            return
        }
        let savedRange: AudioTrimRange? = range.startFrame == 0 && range.endFrame == totalFrames ? nil : range
        current.trimRange = savedRange
        do {
            try library.save(current)
            if let index = recordings.firstIndex(where: { $0.id == current.id }) { recordings[index] = current }
            closeCustomTrim()
            errorMessage = nil
            notice = savedRange == nil
                ? "Custom Trim restored the full recording."
                : "Custom Trim saved. Undo restores the original recording."
        } catch {
            errorMessage = "Could not save Custom Trim: \(error.localizedDescription) Your original recording is safe."
        }
    }

    func cancelCustomTrim() {
        guard customTrimState != nil else { return }
        closeCustomTrim()
        notice = "Custom Trim cancelled. Recording unchanged."
    }

    private func closeCustomTrim() {
        customTrimPlayer?.stop()
        customTrimPlayer = nil
        if let customTrimPreviewURL { try? FileManager.default.removeItem(at: customTrimPreviewURL) }
        customTrimPreviewURL = nil
        preparingCustomTrimID = nil
        customTrimState = nil
        trimmingID = nil
    }

    private func updateCustomTrimPlayback() {
        guard var state = customTrimState, state.isPlaying, let customTrimPlayer else { return }
        state.playheadFrame = min(state.selection.endFrame,
                                  Int64((customTrimPlayer.currentTime * 48_000).rounded()))
        if !customTrimPlayer.isPlaying || state.playheadFrame >= state.selection.endFrame {
            customTrimPlayer.pause()
            state.isPlaying = false
            state.playheadFrame = state.selection.endFrame
            customTrimPlayer.currentTime = Double(state.playheadFrame) / 48_000
        }
        customTrimState = state
    }

    func undoTrim(_ recording: Recording) {
        guard canTrim, let library,
              var current = recordings.first(where: { $0.id == recording.id }), current.trimRange != nil else { return }
        stopPlayback()
        current.trimRange = nil
        do {
            try library.save(current)
            if let index = recordings.firstIndex(where: { $0.id == current.id }) { recordings[index] = current }
            errorMessage = nil
            notice = "Trim undone. Original recording restored."
        } catch { errorMessage = "Could not undo Trim: \(error.localizedDescription)" }
    }

    /// Reads metadata and file sizes only; never reads audio samples.
    private func reloadLibrary() throws {
        guard let library else { return }
        librarySessionIDs = try library.sessionIDs()
        let current = try library.load()
        if let id = pendingRecordingDeletion?.id, !current.contains(where: { $0.id == id }) {
            pendingRecordingDeletion = nil
        }
        if let id = customTrimState?.recordingID, !current.contains(where: { $0.id == id }) {
            closeCustomTrim()
        }
        if let id = playingID ?? preparingPlaybackID, !current.contains(where: { $0.id == id }) {
            stopPlayback()
        }
        recordings = current
        recordingBytes = Dictionary(uniqueKeysWithValues: current.compactMap { recording in
            guard let bytes = try? library.storageBytes(at: library.directory(for: recording.id)) else { return nil }
            return (recording.id, bytes)
        })
        libraryBytes = try? library.storageBytes(at: library.root)
    }

    func refreshLibrary() {
        do { try reloadLibrary() }
        catch { errorMessage = "Could not refresh the recording library: \(error.localizedDescription)" }
    }

    func sizeLabel(for recording: Recording) -> String {
        Self.sizeLabel(recordingBytes[recording.id])
    }

    static func sizeLabel(_ bytes: Int64?) -> String {
        guard let bytes else { return "Size unavailable" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
