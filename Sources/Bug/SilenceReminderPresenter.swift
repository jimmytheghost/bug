import AppKit
import SwiftUI

@MainActor
protocol SilenceReminderPresenting: AnyObject {
    func show(delay: SilenceReminderDelay, keepRecording: @escaping () -> Void, stopRecording: @escaping () async -> Void)
    func dismiss()
}

/// Independent of MenuBarExtra: it can appear with the popover closed. This is
/// nonmodal, so ignoring it cannot block the meter, recording writes, or Stop.
@MainActor
final class SilenceReminderPresenter: NSObject, SilenceReminderPresenting, NSWindowDelegate {
    private var panel: NSPanel?

    func show(delay: SilenceReminderDelay, keepRecording: @escaping () -> Void, stopRecording: @escaping () async -> Void) {
        guard panel == nil else { return }
        let content = SilenceReminderView(delay: delay, keepRecording: keepRecording,
                                           stopRecording: { Task { await stopRecording() } })
        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.titled, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Bug · Silence reminder"
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
}

struct SilenceReminderView: View {
    let delay: SilenceReminderDelay
    let keepRecording: () -> Void
    let stopRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.title2).foregroundStyle(.mint)
                    .frame(width: 38, height: 38)
                    .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Still waiting for audio?").font(.headline)
                    Text("No audio detected for \(delay.title).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Need more time to play your source? Recording continues until you choose Stop Recording.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Stop Recording", action: stopRecording)
                    .help("Stop and save what has been recorded")
                Spacer()
                Button("Keep Recording", action: keepRecording)
                    .keyboardShortcut(.defaultAction)
                    .help("Continue recording and restart the silence timer")
            }
        }
        .padding(20).frame(width: 380).tint(.mint)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
