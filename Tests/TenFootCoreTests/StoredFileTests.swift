import Foundation
import Testing
@testable import TenFootCore

@Suite struct StoredFileTests {
    @Test func movesAnUnreadableFileAside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        try Data("{ not json".utf8).write(to: file)

        let aside = try #require(StoredFile.setAside(file))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(aside.lastPathComponent.hasPrefix("library.json.unreadable-"))
        #expect(try Data(contentsOf: aside) == Data("{ not json".utf8))
    }

    @Test func nothingToMove() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        #expect(StoredFile.setAside(file) == nil)
    }
}
