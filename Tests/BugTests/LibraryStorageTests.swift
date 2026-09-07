import Foundation
import Testing
@testable import Bug

struct LibraryStorageTests {
    private func fixture(_ library: RecordingLibrary) throws -> Recording {
        let recording = Recording(id: UUID(), createdAt: Date(), title: "Storage test",
                                  duration: 10, systemFilename: "system.caf", microphoneFilename: "mic.caf")
        _ = try library.createSession(id: recording.id)
        try Data(repeating: 1, count: 512).write(to: library.url(for: recording))
        try Data(repeating: 2, count: 256).write(to: library.url(for: recording, microphone: true))
        try library.save(recording)
        return recording
    }

    @Test func sizesIncludeBothSourcesMetadataAndUnfinishedSessionsButNotSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let recording = try fixture(library)
        let metadata = try Data(contentsOf: library.directory(for: recording.id).appendingPathComponent("recording.json"))
        let expected = Int64(768 + metadata.count)
        #expect(try library.storageBytes(at: library.directory(for: recording.id)) == expected)
        let unfinished = try library.createSession(id: UUID())
        try Data(repeating: 0, count: 4096).write(to: unfinished.appendingPathComponent("system.caf"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".alias"), withDestinationURL: library.directory(for: recording.id))
        #expect(try library.storageBytes(at: root) == expected + 4096)
        #expect(try library.load() == [recording])
    }

    @MainActor @Test func refreshTracksFinderRemovalRestorationAndSizeChanges() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try RecordingLibrary(root: parent.appendingPathComponent("library"))
        let recording = try fixture(library)
        let suite = "BugStorageTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
        let originalBytes = try #require(store.libraryBytes)
        #expect(store.recordings == [recording])
        let moved = parent.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: library.directory(for: recording.id), to: moved)
        store.refreshLibrary()
        #expect(store.recordings.isEmpty)
        #expect(store.libraryBytes == 0)
        try FileManager.default.moveItem(at: moved, to: library.directory(for: recording.id))
        try Data(repeating: 0, count: 1024).write(to: library.url(for: recording))
        store.refreshLibrary()
        #expect(store.recordings == [recording])
        #expect(store.libraryBytes == originalBytes + 512)
        #expect(store.recordingBytes[recording.id] == originalBytes + 512)
    }

    @Test func trashPreservesRecoverableSourcesAndExportedCopy() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try RecordingLibrary(root: parent.appendingPathComponent("library"))
        let recording = try fixture(library)
        let exported = parent.appendingPathComponent("export.wav")
        let content = Data(repeating: 3, count: 100)
        try content.write(to: exported)
        let trashed = try #require(try library.delete(recording))
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(try library.load().isEmpty)
        #expect(try Data(contentsOf: exported) == content)
        #expect(try Data(contentsOf: trashed.appendingPathComponent("system.caf")).count == 512)
        try FileManager.default.moveItem(at: trashed, to: library.directory(for: recording.id))
        #expect(try library.load() == [recording])
    }
    @MainActor @Test(arguments: [false, true])
    func bulkDeletionUsesConfirmedSnapshotAndPreservesFailures(failOne: Bool) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try RecordingLibrary(root: parent.appendingPathComponent("library"))
        let first = try fixture(library)
        let second = try fixture(library)
        let unfinished = try library.createSession(id: UUID())
        let suite = "BugBulkTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var trashed: [URL] = []
        defer { for url in trashed { try? FileManager.default.removeItem(at: url) } }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false,
                                  trashRecording: { id in
            if failOne && id == first.id { throw CocoaError(.fileWriteNoPermission) }
            if let url = try library.deleteSession(id) { trashed.append(url) }
        })
        let confirmed = store.recordings
        #expect(confirmed.count == 2)
        #expect(try library.load().count == 2) // Preparing confirmation does not delete.
        let addedLater = try fixture(library)
        store.deleteAll(confirmed)
        #expect(store.recordings.contains(where: { $0.id == addedLater.id }))
        #expect(!store.recordings.contains(where: { $0.id == second.id }))
        #expect(store.recordings.contains(where: { $0.id == first.id }) == failOne)
        #expect((store.errorMessage != nil) == failOne)
        #expect(FileManager.default.fileExists(atPath: unfinished.path))
        #expect(store.libraryBytes == (try library.storageBytes(at: library.root)))
        #expect(trashed.count == (failOne ? 1 : 2))
    }

    @MainActor @Test func bulkCleanupIncludesEmptySessionsWithoutInventingRecordings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let emptyID = UUID()
        _ = try library.createSession(id: emptyID)
        let suite = "BugEmptyTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var trashed: URL?
        defer { if let trashed { try? FileManager.default.removeItem(at: trashed) } }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false,
                                  trashRecording: { id in trashed = try library.deleteSession(id) })
        #expect(store.recordings.isEmpty)
        #expect(store.canDeleteAll)
        #expect(store.librarySessionIDs == [emptyID])
        store.deleteSessions(store.librarySessionIDs)
        #expect(store.librarySessionIDs.isEmpty)
        #expect(!store.canDeleteAll)
        #expect(trashed != nil)
    }

    @MainActor @Test(arguments: [false, true])
    func independentConfirmationRoutesCancelAndDelete(approved: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        _ = try library.createSession(id: UUID())
        let suite = "BugConfirmationTests-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        var trashed: URL?
        defer { if let trashed { try? FileManager.default.removeItem(at: trashed) } }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false,
                                  trashRecording: { id in trashed = try library.deleteSession(id) })
        var confirmationCount = 0
        store.requestDeleteAll { count in
            confirmationCount += 1
            #expect(count == 1)
            store.requestDeleteAll { _ in
                Issue.record("Duplicate confirmation must be suppressed")
                return true
            }
            return approved
        }
        #expect(confirmationCount == 1)
        #expect(store.librarySessionIDs.isEmpty == approved)
        #expect((trashed != nil) == approved)
    }

}
