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

    func load() throws -> [Recording] {
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return try directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("recording.json")
            guard FileManager.default.fileExists(atPath: metadata.path) else { return nil }
            let recording = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: metadata))
            guard directory.lastPathComponent == recording.id.uuidString,
                  recording.systemFilename == URL(fileURLWithPath: recording.systemFilename).lastPathComponent,
                  recording.microphoneFilename.map({ $0 == URL(fileURLWithPath: $0).lastPathComponent }) ?? true,
                  recording.trimRange?.isValid ?? true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return recording
        }.sorted { $0.createdAt > $1.createdAt }
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
