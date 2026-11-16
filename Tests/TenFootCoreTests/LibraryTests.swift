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

    @Test func removesAnEntry() {
        var library = Library()
        for name in ["A", "B", "C"] { library.add(path: "/Applications/\(name).app", title: name) }
        let b = library.entries[1]
        #expect(library.remove(id: b.id))
        #expect(library.entries.map(\.title) == ["A", "C"])
        #expect(library.remove(id: b.id) == false) // already gone
        #expect(library.entries.map(\.title) == ["A", "C"])
    }

    @Test func movesEntriesBothWays() {
        var library = Library()
        for name in ["A", "B", "C", "D"] { library.add(path: "/Applications/\(name).app", title: name) }
        library.move(from: 0, to: 2)
        #expect(library.entries.map(\.title) == ["B", "C", "A", "D"])
        library.move(from: 3, to: 0)
        #expect(library.entries.map(\.title) == ["D", "B", "C", "A"])
        library.move(from: 1, to: 9) // out of range: no change
        #expect(library.entries.map(\.title) == ["D", "B", "C", "A"])
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
