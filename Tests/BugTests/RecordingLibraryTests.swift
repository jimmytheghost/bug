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
        #expect(try library.load() == [later, earlier])
        later.title = "A renamed call"
        try library.save(later)
        #expect(try library.load().first?.title == later.title)
        #expect(library.url(for: later, microphone: true).lastPathComponent == "microphone.caf")
    }

    @Test func testIncompleteSessionDoesNotHideCompletedRecordings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        _ = try library.createSession(id: UUID())
        #expect(try library.load().isEmpty)
    }

    @Test func testRejectsMetadataPathTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try RecordingLibrary(root: root)
        let recording = Recording(id: UUID(), createdAt: Date(), title: "Bad path", duration: 1, systemFilename: "../outside.caf", microphoneFilename: nil)
        _ = try library.createSession(id: recording.id)
        try library.save(recording)
        #expect(throws: (any Error).self) { try library.load() }
    }
}
