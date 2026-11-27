import Foundation

struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var title: String
    let duration: TimeInterval
    let systemFilename: String
    let microphoneFilename: String?
    var trimRange: AudioTrimRange? = nil
    var playbackDuration: TimeInterval { trimRange?.duration ?? duration }
}

/// A successful root scan may still contain unreadable individual entries.
struct RecordingLibraryLoad {
    struct Issue: Equatable {
        let directoryName: String
        let reason: String
    }
    let recordings: [Recording]
    let sessionIDs: [UUID]
    let issues: [Issue]

    var warning: String? {
        guard !issues.isEmpty else { return nil }
        let count = issues.count
        return "Could not load \(count) recording \(count == 1 ? "folder" : "folders"). Files are unchanged. Check the Library folder and refresh after repair."
    }
}

struct RecordingLibrary {
    let root: URL

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Bug/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func sessionIDs() throws -> [UUID] {
        try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)
            .compactMap { url in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      let id = UUID(uuidString: url.lastPathComponent),
                      id.uuidString == url.lastPathComponent else { return nil }
                return id
            }
    }

    func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func createSession(id: UUID) throws -> URL {
        let url = directory(for: id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func save(_ recording: Recording) throws {
        try JSONEncoder().encode(recording).write(to: directory(for: recording.id).appendingPathComponent("recording.json"), options: .atomic)
    }

    /// Root/listing failures throw; entry failures are returned without changing any files.
    func load() throws -> RecordingLibraryLoad {
        let directories = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)
        var recordings: [Recording] = []
        var sessionIDs: [UUID] = []
        var issues: [RecordingLibraryLoad.Issue] = []
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else {
                    // Never follow a session alias outside the library.
                    if UUID(uuidString: directory.lastPathComponent) != nil { throw CocoaError(.fileReadCorruptFile) }
                    continue
                }
                guard values.isDirectory == true else { continue }
                if let id = UUID(uuidString: directory.lastPathComponent), id.uuidString == directory.lastPathComponent {
                    sessionIDs.append(id)
                }
                // Listing distinguishes missing metadata (an unfinished session) from access failure.
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                guard names.contains("recording.json") else { continue }
                let metadata = directory.appendingPathComponent("recording.json")
                let metadataValues = try metadata.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard metadataValues.isRegularFile == true, metadataValues.isSymbolicLink != true else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let recording = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: metadata))
                guard directory.lastPathComponent == recording.id.uuidString,
                      Self.isSourceFilename(recording.systemFilename),
                      recording.microphoneFilename.map(Self.isSourceFilename) ?? true,
                      recording.trimRange?.isValid ?? true else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                recordings.append(recording)
            } catch {
                issues.append(.init(directoryName: directory.lastPathComponent, reason: error.localizedDescription))
            }
        }
        return RecordingLibraryLoad(recordings: recordings.sorted { $0.createdAt > $1.createdAt },
                                    sessionIDs: sessionIDs, issues: issues)
    }

    private static func isSourceFilename(_ filename: String) -> Bool {
        !filename.isEmpty && filename != "." && filename != ".."
            && filename == URL(fileURLWithPath: filename).lastPathComponent
    }

    func url(for recording: Recording, microphone: Bool = false) -> URL {
        directory(for: recording.id).appendingPathComponent(microphone ? (recording.microphoneFilename ?? recording.systemFilename) : recording.systemFilename)
    }

    /// Logical file bytes, including metadata and unfinished sessions; never follows symlinks.
    func storageBytes(at directory: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [],
            errorHandler: { _, error in traversalError = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        if let traversalError { throw traversalError }
        return total
    }

    @discardableResult
    func delete(_ recording: Recording) throws -> URL? {
        try deleteSession(recording.id)
    }

    @discardableResult
    func deleteSession(_ id: UUID) throws -> URL? {
        var destination: NSURL?
        try FileManager.default.trashItem(at: directory(for: id), resultingItemURL: &destination)
        return destination as URL?
    }
}
