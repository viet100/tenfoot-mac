import Foundation
import Testing
@testable import TenFootCore

@Suite struct ReorderTests {
    /// The slots shown mid-drag must be exactly where the tiles end up after the drop.
    @Test func previewMatchesLibraryMove() {
        let titles = ["A", "B", "C", "D", "E"]
        for from in titles.indices {
            for target in titles.indices {
                var library = Library()
                for name in titles { library.add(path: "/Applications/\(name).app", title: name) }
                var shown = Array(repeating: "", count: titles.count)
                for index in titles.indices {
                    shown[Reorder.slot(of: index, movingFrom: from, to: target)] = titles[index]
                }
                library.move(from: from, to: target)
                #expect(shown == library.entries.map(\.title), "from \(from) to \(target)")
            }
        }
    }

    @Test func untouchedTilesStayPut() {
        #expect(Reorder.slot(of: 4, movingFrom: 0, to: 2) == 4)
        #expect(Reorder.slot(of: 0, movingFrom: 3, to: 1) == 0)
        #expect(Reorder.slot(of: 2, movingFrom: 2, to: 2) == 2)
    }
}
