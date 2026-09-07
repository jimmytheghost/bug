import AVFoundation
import Foundation
import Testing
@testable import Bug

private final class FakeCapture: AudioCapturing {
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?
    var starts = 0
    var stops = 0
    var failStart = false
    var failStop = false
    var result: CaptureResult?
    func start(directory: URL, includeMicrophone: Bool) async throws {
        starts += 1
        if failStart { throw CocoaError(.fileReadNoPermission) }
        let url = directory.appendingPathComponent("system.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        buffer.frameLength = 480
        for c in 0..<2 { for i in 0..<480 { buffer.floatChannelData![c][i] = 0 } }
        try file.write(from: buffer)
        result = CaptureResult(systemURL: url, microphoneURL: nil, duration: 0.01)
    }
    func stop() async throws -> CaptureResult {
        stops += 1
        if failStop { throw CocoaError(.fileWriteOutOfSpace) }
        return result!
    }
}

@MainActor
private final class FakeReminder: SilenceReminderPresenting {
    var shows = 0
    var visible = false
    var delay: SilenceReminderDelay?
    var keep: (() -> Void)?
    var stop: (() async -> Void)?
    func show(delay: SilenceReminderDelay, keepRecording: @escaping () -> Void, stopRecording: @escaping () async -> Void) {
        shows += 1
        visible = true
        self.delay = delay
        keep = keepRecording
        stop = stopRecording
    }
    func dismiss() { visible = false } // Retain callbacks to exercise stale actions.
}

private final class FakeClock { var now: TimeInterval = 100 }

@MainActor
private final class ReminderFixture {
    let library: RecordingLibrary
    let capture = FakeCapture()
    let reminder = FakeReminder()
    let clock = FakeClock()
    let preferences: UserDefaults
    let root: URL
    let suite = "BugReminderTests-\(UUID())"
    let store: RecorderStore
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BugReminderTests-\(UUID())")
        library = try RecordingLibrary(root: root)
        preferences = UserDefaults(suiteName: suite)!
        let clock = self.clock
        store = RecorderStore(library: library, preferences: preferences, startTimer: false,
                              engine: capture, reminderPresenter: reminder, monotonicTime: { clock.now })
    }
    func advance(to time: TimeInterval) { clock.now = time; store.processMeterTick() }
    func cleanup() {
        try? FileManager.default.removeItem(at: root)
        preferences.removePersistentDomain(forName: suite)
    }
}

@MainActor
struct SilenceReminderStoreTests {
    @Test func closedPopoverIsNotRequiredAndIgnoringDoesNotStopCapture() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        #expect(f.store.silenceReminderDelay == .thirtySeconds)
        await f.store.start() // No view, NSApp window, or actual capture.
        f.advance(to: 129.99)
        #expect(f.reminder.shows == 0)
        f.advance(to: 130)
        #expect(f.reminder.shows == 1)
        #expect(f.reminder.delay == .thirtySeconds)
        f.advance(to: 5_000)
        #expect(f.reminder.shows == 1)
        #expect(f.store.phase == .recording)
        #expect(f.capture.stops == 0)
        await f.store.stop()
    }

    @Test func keepRecordingResetsTimerAndStopUsesNormalSavePathExactlyOnce() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        await f.store.start()
        f.advance(to: 130)
        let keep = try #require(f.reminder.keep)
        let oldStop = try #require(f.reminder.stop)
        keep()
        #expect(!f.reminder.visible)
        #expect(f.store.phase == .recording)
        await oldStop()
        #expect(f.capture.stops == 0)
        f.advance(to: 159.99)
        #expect(f.reminder.shows == 1)
        f.advance(to: 160)
        #expect(f.reminder.shows == 2)
        let stop = try #require(f.reminder.stop)
        await stop()
        await stop()
        #expect(f.store.phase == .idle)
        #expect(f.capture.stops == 1)
        #expect(!f.reminder.visible)
        #expect(try f.library.load().count == 1)
        #expect(f.store.recordings.first?.duration == 0.01)
    }

    @Test func signalDismissesOpenReminderAndLaterSilencePromptsAgain() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        await f.store.start()
        f.advance(to: 130)
        let oldStop = try #require(f.reminder.stop)
        f.clock.now = 131
        // CaptureEngine's live level includes either source without phase cancellation.
        f.store.receiveCaptureLevel(0.01)
        #expect(!f.reminder.visible)
        await oldStop()
        #expect(f.store.phase == .recording)
        f.advance(to: 160)
        #expect(f.reminder.shows == 1)
        f.advance(to: 161)
        #expect(f.reminder.shows == 2)
        await f.store.stop()
    }

    @Test func offDismissesAndPersistsThenChangingDelayStartsFreshInterval() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        await f.store.start()
        f.advance(to: 130)
        f.store.silenceReminderDelay = .off
        #expect(!f.reminder.visible)
        #expect(f.preferences.integer(forKey: "silenceReminderDelay") == 0)
        let reopened = RecorderStore(library: f.library, preferences: f.preferences, startTimer: false,
                                     engine: FakeCapture(), reminderPresenter: FakeReminder())
        #expect(reopened.silenceReminderDelay == .off)
        f.advance(to: 200)
        #expect(f.reminder.shows == 1)
        f.store.silenceReminderDelay = .fifteenSeconds
        f.advance(to: 214.99)
        #expect(f.reminder.shows == 1)
        f.advance(to: 215)
        #expect(f.reminder.shows == 2)
        #expect(f.reminder.delay == .fifteenSeconds)
        await f.store.stop()
    }

    @Test func manualStopAndRestartFenceStalePromptActions() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        await f.store.start()
        f.advance(to: 130)
        let keep = try #require(f.reminder.keep)
        let stop = try #require(f.reminder.stop)
        await f.store.stop()
        #expect(!f.reminder.visible)
        await f.store.start()
        keep()
        await stop()
        #expect(f.store.phase == .recording)
        #expect(f.capture.stops == 1)
        f.advance(to: 160)
        #expect(f.reminder.shows == 2)
        await f.store.stop()
    }

    @Test func startAndStopErrorsNeverLeaveAnActionableReminder() async throws {
        let f = try ReminderFixture(); defer { f.cleanup() }
        f.capture.failStart = true
        await f.store.start()
        f.advance(to: 200)
        #expect(f.reminder.shows == 0)
        #expect(f.store.phase == .idle)
        f.capture.failStart = false
        await f.store.start()
        f.advance(to: 230)
        f.capture.failStop = true
        await f.reminder.stop?()
        #expect(f.store.phase == .idle)
        #expect(!f.reminder.visible)
        #expect(f.store.errorMessage != nil)
        f.advance(to: 500)
        #expect(f.reminder.shows == 1)
    }
}
