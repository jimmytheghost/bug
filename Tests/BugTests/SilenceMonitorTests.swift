import Testing
@testable import Bug

struct SilenceMonitorTests {
    @Test func eachDelayFiresOnlyAtItsDeadlineWithoutAnyBuffers() {
        for delay in [SilenceReminderDelay.fifteenSeconds, .thirtySeconds, .oneMinute] {
            var monitor = SilenceMonitor()
            monitor.configure(delay, at: 100)
            monitor.start(at: 100)
            #expect(monitor.tick(at: 100 + Double(delay.rawValue) - 0.01) == nil)
            #expect(monitor.tick(at: 100 + Double(delay.rawValue)) != nil)
        }
    }

    @Test func offAndIdleNeverPrompt() {
        var monitor = SilenceMonitor()
        #expect(monitor.tick(at: 10_000) == nil)
        monitor.configure(.off, at: 0)
        monitor.start(at: 0)
        #expect(monitor.tick(at: 10_000) == nil)
        monitor.stop()
        monitor.configure(.fifteenSeconds, at: 10_000)
        #expect(monitor.tick(at: 20_000) == nil)
    }

    @Test func laterSilenceAndQuietButDetectableAudioResetTheClock() {
        var monitor = SilenceMonitor()
        monitor.start(at: 0)
        monitor.observe(level: 0.001, at: 29)
        #expect(monitor.tick(at: 30) == nil)
        #expect(monitor.tick(at: 58.99) == nil)
        #expect(monitor.tick(at: 59) != nil)
    }

    @Test func silenceNoiseBelowFloorAndInvalidLevelsDoNotResetTheClock() {
        var monitor = SilenceMonitor()
        monitor.start(at: 0)
        for level: Float in [0, 0.0001, .nan, .infinity, -1] {
            monitor.observe(level: level, at: 29)
        }
        #expect(monitor.tick(at: 30) != nil)
    }

    @Test func ignoredReminderDoesNotRepeatOrStopMonitoringSession() throws {
        var monitor = SilenceMonitor()
        monitor.start(at: 0)
        let firstValue = monitor.tick(at: 30)
        let first = try #require(firstValue)
        for time in [60.0, 90, 3600] { #expect(monitor.tick(at: time) == nil) }
        #expect(monitor.pendingReminder == first)
        #expect(monitor.keepRecording(reminder: first, at: 3600) == true)
        #expect(monitor.tick(at: 3629) == nil)
        #expect(monitor.tick(at: 3630) != nil)
    }

    @Test func resumedAudioDismissesReminderAndRearmsLaterSilence() throws {
        var monitor = SilenceMonitor()
        monitor.start(at: 0)
        let firstValue = monitor.tick(at: 30)
        let first = try #require(firstValue)
        monitor.observe(level: 0.2, at: 31)
        #expect(monitor.pendingReminder == nil)
        #expect(monitor.keepRecording(reminder: first, at: 59) == false)
        #expect(monitor.tick(at: 60.99) == nil)
        #expect(monitor.tick(at: 61) != nil)
    }

    @Test func changingSettingsAndNewSessionsInvalidateOldPrompts() throws {
        var monitor = SilenceMonitor()
        monitor.start(at: 0)
        let firstValue = monitor.tick(at: 30)
        let first = try #require(firstValue)
        monitor.configure(.fifteenSeconds, at: 40)
        #expect(monitor.pendingReminder == nil)
        #expect(monitor.keepRecording(reminder: first, at: 54) == false)
        #expect(monitor.tick(at: 54.99) == nil)
        let secondValue = monitor.tick(at: 55)
        let second = try #require(secondValue)
        monitor.stop()
        monitor.start(at: 100)
        #expect(monitor.keepRecording(reminder: second, at: 114) == false)
        #expect(monitor.tick(at: 115) != nil)
        monitor.configure(.off, at: 116)
        #expect(monitor.pendingReminder == nil)
        #expect(monitor.tick(at: 1_000) == nil)
    }
}
