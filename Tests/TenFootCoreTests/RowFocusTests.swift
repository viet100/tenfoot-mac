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
        let leftAtStart = focus.move(by: -1)
        #expect(leftAtStart == false)
        #expect(focus.index == 0)
        let first = focus.move(by: 1)
        let second = focus.move(by: 1)
        let pastEnd = focus.move(by: 1)
        #expect(first && second)
        #expect(pastEnd == false)
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
        let moved = focus.move(by: 1)
        #expect(moved == false)
        #expect(focus.index == 0)
    }

    @Test func scrollsToAGivenFirstTileButKeepsFocusVisible() {
        var focus = RowFocus(count: 10, visibleCount: 4)
        focus.select(5)
        focus.scroll(to: 3)
        #expect(focus.firstVisible == 3)
        focus.scroll(to: 0) // would hide the focused tile 5
        #expect(focus.firstVisible == 2)
        focus.scroll(to: 9) // past the end of the row
        #expect(focus.firstVisible == 5)
    }
}
