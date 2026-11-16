import Foundation

/// An app or executable the user added to the launcher.
public struct LibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var path: String

    public init(id: UUID = UUID(), title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

/// The user's saved list of apps, in the order they were added.
public struct Library: Codable, Equatable, Sendable {
    public private(set) var entries: [LibraryEntry]

    public init(entries: [LibraryEntry] = []) {
        self.entries = entries
    }

    /// Adds an app, or returns the existing entry if that path is already in the library.
    @discardableResult
    public mutating func add(path: String, title: String) -> LibraryEntry {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = entries.first(where: { $0.path == path }) {
            return existing
        }
        let entry = LibraryEntry(title: title, path: path)
        entries.append(entry)
        return entry
    }

    /// Loads the library from `url`; a missing file is an empty library.
    public static func load(from url: URL) throws -> Library {
        guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
        return try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
