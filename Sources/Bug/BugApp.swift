import AppKit
import SwiftUI

@main
struct BugApp: App {
    @NSApplicationDelegateAdaptor(BugAppDelegate.self) private var delegate
    @StateObject private var store = RecorderStore()

    var body: some Scene {
        MenuBarExtra {
            BugMenuView(store: store)
                .onAppear { delegate.store = store }
        } label: {
            Image(systemName: store.phase == .recording ? "record.circle.fill" : "ladybug")
                .accessibilityLabel(store.phase == .recording ? "Bug is recording" : "Bug")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class BugAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: RecorderStore?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard store.canQuit else {
            store.errorMessage = "Stop recording and wait for export to finish before quitting Bug."
            return .terminateCancel
        }
        store.stopPlayback()
        return .terminateNow
    }
}
