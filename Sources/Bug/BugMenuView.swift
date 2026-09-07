import AppKit
import ServiceManagement
import SwiftUI

struct BugMenuView: View {
    @ObservedObject var store: RecorderStore
    @State private var showingSettings = false
    @State private var renaming: Recording?
    @State private var newTitle = ""
    @State private var deleting: Recording?
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
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.mint)
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let renaming { store.rename(renaming, to: newTitle) }; renaming = nil }
        }
        .alert("Move recording to Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Move to Trash", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
        } message: { Text("You can recover the original audio from the Trash. Exported copies stay where you saved them.") }
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
                Text(status).font(.caption).foregroundStyle(.secondary)
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
        switch store.phase {
        case .idle: return store.trimmingID == nil ? "Catch a little audio." : "Trimming recording…"
        case .starting: return "Starting audio capture…"
        case .recording: return "Recording \(store.includeMicrophone ? "system + microphone" : "system audio")"
        case .stopping: return "Finishing recording…"
        }
    }

    private var recorder: some View {
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
                Text("\(store.recordings.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            if store.recordings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("Ready when you are.").font(.callout.weight(.medium))
                    Text("Record audio from your Mac.\nYour recordings will appear here.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                Text(recording.title).font(.callout.weight(.medium)).lineLimit(1).help(recording.title)
                Text("\(RecorderStore.durationLabel(recording.playbackDuration))\(recording.trimRange != nil ? " · Trimmed" : "")\(recording.microphoneFilename != nil ? " · Mic" : "") · \(recording.createdAt.formatted(date: .abbreviated, time: .omitted))")
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
                Button("Rename…") { newTitle = recording.title; renaming = recording }
                    .disabled(store.trimmingID == recording.id)
                Button("Move to Trash…", role: .destructive) { deleting = recording }
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
                Picker("Trim padding", selection: $store.trimPadding) {
                    Text("None").tag(0.0)
                    Text("0.25 seconds").tag(0.25)
                    Text("0.5 seconds").tag(0.5)
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                }
                .font(.callout).disabled(store.trimmingID != nil)
                Text("Keeps up to this much silence at each end. Pauses inside the recording stay intact. Undo restores the original.")
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
            messages
            Text("Bug 0.2.0 · A companion to Worklog").font(.caption2).foregroundStyle(.tertiary)
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
        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(14)
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
