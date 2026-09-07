import Foundation

struct Recording: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var title: String
    let duration: TimeInterval
    let systemFilename: String
    let microphoneFilename: String?
}

struct RecordingLibrary {
    let root: URL

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Bug/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
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
                  recording.microphoneFilename.map({ $0 == URL(fileURLWithPath: $0).lastPathComponent }) ?? true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return recording
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func url(for recording: Recording, microphone: Bool = false) -> URL {
        directory(for: recording.id).appendingPathComponent(microphone ? (recording.microphoneFilename ?? recording.systemFilename) : recording.systemFilename)
    }

    func delete(_ recording: Recording) throws {
        try FileManager.default.trashItem(at: directory(for: recording.id), resultingItemURL: nil)
    }
}
