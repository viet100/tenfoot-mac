import Foundation
import Testing
@testable import TenFootCore

@Suite struct LibraryTests {
    @Test func addsInOrder() {
        var library = Library()
        library.add(path: "/Applications/One.app", title: "One")
        library.add(path: "/Applications/Two.app", title: "Two")
        #expect(library.entries.map(\.title) == ["One", "Two"])
    }

    @Test func addingSamePathTwiceKeepsOneEntry() {
        var library = Library()
        let first = library.add(path: "/Applications/Game.app", title: "Game")
        let again = library.add(path: "/Applications/../Applications/Game.app", title: "Game")
        #expect(library.entries.count == 1)
        #expect(again.id == first.id)
    }

    @Test func savesAndLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")

        var library = Library()
        library.add(path: "/Applications/Game.app", title: "Game")
        library.add(path: "/usr/local/bin/emulator", title: "emulator")
        try library.save(to: file)

        let loaded = try Library.load(from: file)
        #expect(loaded == library)
    }

    @Test func missingFileIsEmptyLibrary() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        let loaded = try Library.load(from: file)
        #expect(loaded.entries.isEmpty)
    }
}
