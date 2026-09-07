import Foundation

enum SilenceReminderDelay: Int, CaseIterable, Identifiable {
    case off = 0, fifteenSeconds = 15, thirtySeconds = 30, oneMinute = 60
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .fifteenSeconds: return "15 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        }
    }
}

/// Driven by a monotonic clock, not by arrival of audio buffers. No-buffer silence
/// must trigger just as zero-valued PCM does. One outstanding reminder at a time.
struct SilenceMonitor {
    static let signalThreshold: Float = 0.001 // -60 dBFS RMS, matching the live meter's scale.
    private(set) var delay: SilenceReminderDelay = .thirtySeconds
    private(set) var pendingReminder: UUID?
    private var lastActivity: TimeInterval?

    mutating func start(at time: TimeInterval) {
        lastActivity = time
        pendingReminder = nil
    }

    mutating func stop() {
        lastActivity = nil
        pendingReminder = nil
    }

    /// A changed setting gets a fresh interval; Off also clears an open reminder.
    mutating func configure(_ delay: SilenceReminderDelay, at time: TimeInterval) {
        self.delay = delay
        pendingReminder = nil
        if lastActivity != nil { lastActivity = time }
    }

    mutating func observe(level: Float, at time: TimeInterval) {
        guard lastActivity != nil, level.isFinite, level >= Self.signalThreshold else { return }
        lastActivity = time
        pendingReminder = nil
    }

    mutating func tick(at time: TimeInterval) -> UUID? {
        guard delay != .off, let lastActivity, pendingReminder == nil,
              time - lastActivity >= Double(delay.rawValue) else { return nil }
        let id = UUID()
        pendingReminder = id
        return id
    }

    /// IDs fence callbacks from prompts that were dismissed or belong to old sessions.
    mutating func keepRecording(reminder id: UUID, at time: TimeInterval) -> Bool {
        guard pendingReminder == id, lastActivity != nil else { return false }
        pendingReminder = nil
        lastActivity = time
        return true
    }
}
