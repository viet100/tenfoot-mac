import Testing
@testable import TenFootCore

@Suite struct RowFocusTests {
    @Test func startsAtFirstTile() {
        let focus = RowFocus(count: 5, visibleCount: 3)
        #expect(focus.index == 0)
        #expect(focus.firstVisible == 0)
    }

    @Test func clampsAtBothEnds() {
        var focus = RowFocus(count: 3, visibleCount: 3)
        #expect(focus.move(by: -1) == false)
        #expect(focus.index == 0)
        #expect(focus.move(by: 1))
        #expect(focus.move(by: 1))
        #expect(focus.move(by: 1) == false)
        #expect(focus.index == 2)
    }

    @Test func scrollsOnlyWhenFocusLeavesVisibleTiles() {
        var focus = RowFocus(count: 10, visibleCount: 4)
        focus.select(3)
        #expect(focus.firstVisible == 0)
        focus.move(by: 1)
        #expect(focus.index == 4)
        #expect(focus.firstVisible == 1)
        focus.select(2)
        #expect(focus.firstVisible == 1)
        focus.select(0)
        #expect(focus.firstVisible == 0)
    }

    @Test func neverScrollsPastTheEnd() {
        var focus = RowFocus(count: 6, visibleCount: 4)
        focus.select(5)
        #expect(focus.firstVisible == 2)
        focus.setVisibleCount(10)
        #expect(focus.firstVisible == 0)
    }

    @Test func emptyRowIgnoresMoves() {
        var focus = RowFocus(count: 0)
        #expect(focus.move(by: 1) == false)
        #expect(focus.index == 0)
    }
}
