import AppKit
import ServiceManagement
import SwiftUI

struct BugMenuView: View {
    @ObservedObject var store: RecorderStore
    @State private var showingSettings = false
    @State private var renaming: Recording?
    @State private var newTitle = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    init(store: RecorderStore, showingSettings: Bool = false) {
        _store = ObservedObject(wrappedValue: store)
        _showingSettings = State(initialValue: showingSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showingSettings { settings } else {
                VStack(spacing: 14) {
                    recorder
                    messages
                    library
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.mint)
        .task {
            while !Task.isCancelled {
                store.refreshLibrary()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshLibrary()
        }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let renaming { store.rename(renaming, to: newTitle) }; renaming = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.mint)
                .frame(width: 30, height: 30)
                .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Bug").font(.headline)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { showingSettings.toggle() } label: {
                Image(systemName: showingSettings ? "xmark" : "gearshape")
                    .foregroundStyle(showingSettings ? Color.mint : Color.secondary)
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showingSettings ? "Back to recorder" : "Settings")
            .accessibilityLabel(showingSettings ? "Back to recorder" : "Settings")
        }
        .padding(14)
    }

    private var status: String {
        if let customTrim = store.customTrimState { return "Custom Trim · \(customTrim.title)" }
        if store.preparingCustomTrimID != nil { return "Preparing Custom Trim…" }
        switch store.phase {
        case .idle: return store.trimmingID == nil ? "Catch a little audio." : "Trimming recording…"
        case .starting: return "Starting audio capture…"
        case .recording: return "Recording \(store.includeMicrophone ? "system + microphone" : "system audio")"
        case .stopping: return "Finishing recording…"
        }
    }

    @ViewBuilder private var recorder: some View {
        if let state = store.customTrimState { customTrimEditor(state) }
        else if let id = store.preparingCustomTrimID,
                let recording = store.recordings.first(where: { $0.id == id }) {
            customTrimLoading(recording)
        }
        else { liveRecorder }
    }

    private func customTrimLoading(_ recording: Recording) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Preparing Custom Trim…").font(.callout.weight(.medium))
            Text(recording.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("Building the full-recording waveform and preview.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var liveRecorder: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 5) {
                    Circle().fill(store.phase == .recording ? Color.red : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    Text(store.phase == .recording ? "RECORDING" : "SYSTEM AUDIO")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(RecorderStore.durationLabel(store.elapsed)).font(.system(.title3, design: .monospaced).weight(.medium))
            }
            WaveformView(levels: store.levels, active: store.phase == .recording)
                .frame(height: 70)
                .accessibilityLabel(store.phase == .recording ? "Live audio waveform" : "Audio waveform")
            HStack(spacing: 8) {
                Image(systemName: store.includeMicrophone ? "mic.fill" : "mic.slash")
                    .foregroundStyle(store.includeMicrophone ? Color.mint : Color.secondary)
                    .frame(width: 14)
                Toggle("Include microphone", isOn: $store.includeMicrophone)
                    .font(.caption).toggleStyle(.switch).controlSize(.mini)
                    .disabled(store.isBusy)
            }
            Button {
                Task { if store.phase == .recording { await store.stop() } else { await store.start() } }
            } label: {
                HStack(spacing: 8) {
                    if store.phase == .starting || store.phase == .stopping {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: store.phase == .recording ? "stop.fill" : "record.circle")
                    }
                    Text(recordButtonTitle).font(.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(store.phase == .recording ? Color.red.opacity(0.13) : Color.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(store.phase == .recording ? Color.red : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(store.phase == .starting || store.phase == .stopping || store.trimmingID != nil)
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private func customTrimEditor(_ state: CustomTrimEditorState) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CUSTOM TRIM").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(state.title).font(.caption).lineLimit(1)
                }
                Spacer()
                Text("Keep \(RecorderStore.durationLabel(state.selection.duration))")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Cancel") { store.cancelCustomTrim() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { store.skipCustomTrim(seconds: -5) } label: { Image(systemName: "gobackward.5") }
                    .buttonStyle(.plain)
                Button { store.toggleCustomTrimPlayback() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).frame(width: 28)
                }
                .buttonStyle(.plain)
                Button { store.skipCustomTrim(seconds: 5) } label: { Image(systemName: "goforward.5") }
                    .buttonStyle(.plain)
                Spacer()
                Button("Save") { store.saveCustomTrim() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            CustomTrimWaveformView(
                samples: state.waveform,
                totalFrames: state.selection.totalFrames,
                start: state.selection.startFraction,
                end: state.selection.endFraction,
                playhead: state.playheadFraction,
                setStart: store.setCustomTrimStart,
                setEnd: store.setCustomTrimEnd,
                seek: store.seekCustomTrim
            )
            .frame(height: 64)
            HStack {
                Text(RecorderStore.durationLabel(Double(state.selection.startFrame) / 48_000))
                Spacer()
                Text(RecorderStore.durationLabel(Double(state.playheadFrame) / 48_000))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(RecorderStore.durationLabel(Double(state.selection.endFrame) / 48_000))
            }
            .font(.system(.caption2, design: .monospaced)).monospacedDigit()
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var recordButtonTitle: String {
        switch store.phase {
        case .idle: return "Record"
        case .recording: return "Stop recording"
        case .starting: return "Starting…"
        case .stopping: return "Saving…"
        }
    }

    @ViewBuilder private var messages: some View {
        if let error = store.errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }
                Button("Audio recording permissions…") { store.openPermissions() }.font(.caption)
            }
        } else if let notice = store.notice {
            HStack {
                Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button { store.notice = nil } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss notice")
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECORDINGS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.recordings.count) · \(RecorderStore.sizeLabel(store.libraryBytes))").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    .help("Total file sizes in the Library folder, including unfinished sessions. Trim keeps the original files.")
            }
            if store.recordings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("Ready when you are.").font(.callout.weight(.medium))
                    Text("Record audio from your Mac.\nYour recordings will appear here.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.recordings) { recording in
                            recordingRow(recording)
                            if recording.id != store.recordings.last?.id { Divider().padding(.vertical, 7) }
                        }
                    }
                }
                .frame(height: min(CGFloat(store.recordings.count) * 64, 220))
                .id(store.recordings.first?.id)
            }
        }
    }

    private func recordingRow(_ recording: Recording) -> some View {
        HStack(spacing: 9) {
            Button { store.togglePlayback(recording) } label: {
                Group {
                    if store.preparingPlaybackID == recording.id { ProgressView().controlSize(.small) }
                    else { Image(systemName: store.playingID == recording.id ? "stop.fill" : "play.fill").font(.caption) }
                }
                .frame(width: 28, height: 32)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain).disabled(store.isBusy)
            .accessibilityLabel(store.playingID == recording.id ? "Stop playback" : "Play \(recording.title)")
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title).font(.callout.weight(.medium)).lineLimit(1).help("\(recording.title) · \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))")
                Text("\(RecorderStore.durationLabel(recording.playbackDuration)) · \(store.sizeLabel(for: recording))\(recording.trimRange != nil ? " · Trimmed" : "")\(recording.microphoneFilename != nil ? " · Mic" : "")")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if store.exportingID == recording.id { ProgressView().controlSize(.small) }
            if store.trimmingID == recording.id {
                ProgressView().controlSize(.small).accessibilityLabel("Trimming recording")
            } else {
                Button(recording.trimRange == nil ? "Trim" : "Undo") {
                    if recording.trimRange != nil { store.undoTrim(recording) }
                    else { Task { await store.trim(recording) } }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!store.canTrim)
                .help(recording.trimRange == nil ? "Trim silence at the beginning and end" : "Undo Trim and restore the full recording")
                .accessibilityLabel(recording.trimRange == nil ? "Trim \(recording.title)" : "Undo Trim for \(recording.title)")
            }
            Button { Task { await store.customTrim(recording) } } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 20, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(!store.canTrim)
            .help("Custom Trim")
            .accessibilityLabel("Custom Trim \(recording.title)")
            Button { store.requestDelete(recording) } label: {
                Image(systemName: "trash").frame(width: 22, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(store.exportingID == recording.id || store.trimmingID == recording.id)
            .help("Move to Trash")
            .accessibilityLabel("Move \(recording.title) to Trash")
            Menu {
                Button("Export WAV · 24-bit") { Task { await store.export(recording, format: .wav) } }
                    .disabled(store.exportingID != nil || store.trimmingID != nil)
                Button("Export MP3 · 320 kbps") { Task { await store.export(recording, format: .mp3) } }
                    .disabled(store.exportingID != nil || store.trimmingID != nil)
                Divider()
                Button(recording.trimRange == nil ? "Trim" : "Undo Trim") {
                    if recording.trimRange != nil { store.undoTrim(recording) }
                    else { Task { await store.trim(recording) } }
                }
                .disabled(!store.canTrim)
                Button("Custom Trim…") { Task { await store.customTrim(recording) } }
                    .disabled(!store.canTrim)
                Button("Rename…") { newTitle = recording.title; renaming = recording }
                    .disabled(store.trimmingID == recording.id)
                Button("Move to Trash…", role: .destructive) { store.requestDelete(recording) }
                    .disabled(store.exportingID == recording.id || store.trimmingID == recording.id)
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 28) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Actions for \(recording.title)")
        }
        .padding(.vertical, 4)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SETTINGS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Toggle("Start on computer startup", isOn: Binding(get: { loginEnabled }, set: updateLoginItem))
                .font(.callout).toggleStyle(.switch).controlSize(.small)
                .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Picker("Silence reminder", selection: $store.silenceReminderDelay) {
                    ForEach(SilenceReminderDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .font(.callout)
                Text("Ask whether to keep recording when no audio is detected. Either system audio or your included microphone resets the timer. Ignoring the reminder keeps recording.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Picker("Trim padding", selection: $store.trimPadding) {
                    Text("None").tag(0.0)
                    Text("0.25 seconds").tag(0.25)
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                }
                .font(.callout).disabled(store.trimmingID != nil)
                Text("Keeps up to this much silence at each end. Pauses inside the recording stay intact. Undo restores the original. Trim does not reduce library storage.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("Made to stay local.").font(.callout.weight(.medium))
                Text("Audio stays on this Mac. WAV exports use 48 kHz, 24-bit stereo; MP3 uses 320 kbps.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Use headphones when including your microphone to avoid recording speaker audio twice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Audio recording permissions…") { store.openPermissions() }
            Button("Open recording library") { store.revealLibrary() }
            Button("Delete All", role: .destructive) {
                Task { @MainActor in
                    await Task.yield()
                    store.requestDeleteAll()
                }
            }
            .disabled(!store.canDeleteAll)
            .help("Move all saved recordings to Trash")

            messages
            Text("Bug 0.5.1 · A companion to Worklog").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Button { store.revealLibrary() } label: { Label("Library folder", systemImage: "folder") }
            Spacer()
            Button("Quit Bug") { NSApp.terminate(nil) }
                .disabled(!store.canQuit)
                .keyboardShortcut("q", modifiers: [.command])
        }
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
        .frame(minHeight: 20)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            store.errorMessage = "Could not update startup setting: \(error.localizedDescription)"
        }
    }
}

struct WaveformView: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let step = size.width / CGFloat(max(1, levels.count))
                for (index, level) in levels.enumerated() {
                    let height = max(2, CGFloat(sqrt(max(0, level))) * (size.height - 4))
                    let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: max(1, step - 2), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(active ? .mint.opacity(0.35 + Double(index) / Double(max(1, levels.count)) * 0.65) : .secondary.opacity(0.25)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
