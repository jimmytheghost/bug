import Foundation
import Testing
@testable import Bug

struct RecordingLibraryTests {
    @Test func testRoundTripAndNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let earlier = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: 10), title: "First", duration: 2.5, systemFilename: "system.caf", microphoneFilename: nil)
        var later = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: 20), title: "Second", duration: 7, systemFilename: "system.caf", microphoneFilename: "microphone.caf")
        _ = try library.createSession(id: earlier.id)
        _ = try library.createSession(id: later.id)
        try library.save(earlier)
        try library.save(later)
        #expect(try library.load().recordings == [later, earlier])
        later.title = "A renamed call"
        try library.save(later)
        #expect(try library.load().recordings.first?.title == later.title)
        #expect(library.url(for: later, microphone: true).lastPathComponent == "microphone.caf")
    }

    @Test func testIncompleteSessionDoesNotHideCompletedRecordings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        _ = try library.createSession(id: UUID())
        #expect(try library.load().recordings.isEmpty)
    }

    @Test func testRejectsMetadataPathTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let recording = Recording(id: UUID(), createdAt: Date(), title: "Bad path", duration: 1, systemFilename: "../outside.caf", microphoneFilename: nil)
        _ = try library.createSession(id: recording.id)
        try library.save(recording)
        #expect(try library.load().recordings.isEmpty)
        #expect(try library.load().issues.count == 1)
    }
}

extension RecordingLibraryTests {
    private func saved(_ library: RecordingLibrary, time: TimeInterval = 10) throws -> Recording {
        let recording = Recording(id: UUID(), createdAt: Date(timeIntervalSince1970: time),
                                  title: "Synthetic fixture", duration: 2, systemFilename: "system.caf", microphoneFilename: nil)
        _ = try library.createSession(id: recording.id)
        try library.save(recording)
        try Data([1, 2, 3]).write(to: library.url(for: recording))
        return recording
    }

    @Test func mixedMalformedLibraryPreservesFilesAndOrderingAcrossLoads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let earlier = try saved(library)
        let later = try saved(library, time: 20)
        let broken = try library.createSession(id: UUID())
        let metadata = broken.appendingPathComponent("recording.json")
        let malformed = Data("{broken JSON".utf8)
        try malformed.write(to: metadata)
        let source = broken.appendingPathComponent("system.caf")
        try Data([4, 5, 6]).write(to: source)
        let unfinished = try library.createSession(id: UUID())
        try Data([7, 8]).write(to: unfinished.appendingPathComponent("system.caf"))
        let originalBytes = try library.storageBytes(at: root)
        let originalNames = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        for _ in 0..<3 {
            let result = try library.load()
            #expect(result.recordings == [later, earlier])
            #expect(result.issues.map(\.directoryName) == [broken.lastPathComponent])
            #expect(result.issues.first?.reason.isEmpty == false)
            #expect(result.sessionIDs.count == 4)
            #expect(result.warning?.contains("1 recording folder") == true)
            #expect(try Data(contentsOf: metadata) == malformed)
            #expect(try Data(contentsOf: source) == Data([4, 5, 6]))
            #expect(try Data(contentsOf: library.url(for: earlier)) == Data([1, 2, 3]))
            #expect(try Data(contentsOf: library.url(for: later)) == Data([1, 2, 3]))
            #expect(try library.storageBytes(at: root) == originalBytes)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == originalNames)
        }
    }

    @Test(arguments: ["identity", "system-path", "mic-path", "empty-path", "dot-path", "negative-trim", "empty-trim", "reversed-trim"])
    func invalidEntriesAreReportedWithoutHidingValidEntries(kind: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let good = try saved(library)
        let id = UUID()
        let directory = try library.createSession(id: id)
        var bad = Recording(id: kind == "identity" ? UUID() : id, createdAt: Date(), title: "Invalid",
                            duration: 2, systemFilename: kind == "system-path" ? "../outside.caf" : kind == "empty-path" ? "" : kind == "dot-path" ? ".." : "system.caf",
                            microphoneFilename: kind == "mic-path" ? "/outside.caf" : nil)
        if kind == "negative-trim" { bad.trimRange = AudioTrimRange(startFrame: -1, endFrame: 48_000) }
        if kind == "empty-trim" { bad.trimRange = AudioTrimRange(startFrame: 0, endFrame: 0) }
        if kind == "reversed-trim" { bad.trimRange = AudioTrimRange(startFrame: 48_000, endFrame: 1) }
        let data = try JSONEncoder().encode(bad)
        let metadata = directory.appendingPathComponent("recording.json")
        try data.write(to: metadata)
        let result = try library.load()
        #expect(result.recordings == [good])
        #expect(result.issues.map(\.directoryName) == [id.uuidString])
        #expect(try Data(contentsOf: metadata) == data)
    }

    @Test func unreadableMetadataAndSessionAliasesAreReported() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try RecordingLibrary(root: parent.appendingPathComponent("library"))
        let good = try saved(library)
        let bad = try library.createSession(id: UUID())
        // Deterministic read failure, even for a privileged runner: metadata is a directory.
        try FileManager.default.createDirectory(at: bad.appendingPathComponent("recording.json"), withIntermediateDirectories: false)
        let external = parent.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        let alias = library.directory(for: UUID())
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: external)
        let result = try library.load()
        #expect(result.recordings == [good])
        #expect(result.issues.count == 2)
        #expect(result.warning?.contains("2 recording folders") == true)
        #expect(result.sessionIDs.count == 2)
        #expect(try alias.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
    }

    @MainActor @Test func storeWarningRecoversAfterRepairAndDoesNotReplaceOperationErrors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let good = try saved(library)
        let bad = try saved(library, time: 20)
        let metadata = library.directory(for: bad.id).appendingPathComponent("recording.json")
        try Data("invalid".utf8).write(to: metadata)
        let suite = "BugLibraryResilience-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
        #expect(store.recordings == [good])
        #expect(store.libraryWarning != nil)
        #expect(store.errorMessage == nil)
        store.errorMessage = "Unrelated operation failed"
        store.refreshLibrary()
        #expect(store.recordings == [good])
        #expect(store.libraryWarning != nil)
        #expect(store.errorMessage == "Unrelated operation failed")
        try library.save(bad)
        store.refreshLibrary()
        #expect(store.recordings == [bad, good])
        #expect(store.libraryWarning == nil)
        #expect(store.errorMessage == "Unrelated operation failed")
    }

    @MainActor @Test func rootListingFailureThrowsAndStoreRetainsLastGoodSnapshot() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let library = try RecordingLibrary(root: parent.appendingPathComponent("library"))
        let good = try saved(library)
        let suite = "BugLibraryRootFailure-\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = RecorderStore(library: library, preferences: preferences, startTimer: false)
        try FileManager.default.moveItem(at: library.root, to: parent.appendingPathComponent("preserved"))
        #expect(throws: (any Error).self) { try library.load() }
        // An inaccessible root cannot masquerade as an empty successful scan.
        try Data([0]).write(to: library.root)
        #expect(throws: (any Error).self) { try library.load() }
        store.refreshLibrary()
        #expect(store.recordings == [good])
        #expect(store.libraryWarning == nil)
        #expect(store.errorMessage?.contains("Could not refresh the recording library") == true)
        let newStore = RecorderStore(library: library, preferences: preferences, startTimer: false)
        #expect(newStore.errorMessage?.contains("Could not open the recording library") == true)
    }
}


extension RecordingLibraryTests {
    @Test func accessDeniedIsIsolatedAtEntryButFatalAtRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let good = try saved(library)
        let bad = try saved(library)
        let directory = library.directory(for: bad.id)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)
        let result = try library.load()
        #expect(result.recordings == [good])
        #expect(result.issues.map(\.directoryName) == [bad.id.uuidString])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(try library.load().issues.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)
        #expect(throws: (any Error).self) { try library.load() }
    }
}
