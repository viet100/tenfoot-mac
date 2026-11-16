import Testing
@testable import TenFootCore

@Suite struct RepeatFilterTests {
    @Test func movesOnceOnPress() {
        var filter = RepeatFilter(initialDelay: 0.4, interval: 0.1)
        let press = filter.update(direction: 1, at: 0)
        let stillHeld = filter.update(direction: 1, at: 0.2)
        #expect(press == 1)
        #expect(stillHeld == 0)
    }

    @Test func repeatsAfterDelayThenAtInterval() {
        var filter = RepeatFilter(initialDelay: 0.4, interval: 0.1)
        _ = filter.update(direction: -1, at: 0)
        let first = filter.update(direction: -1, at: 0.4)
        let tooSoon = filter.update(direction: -1, at: 0.45)
        let second = filter.update(direction: -1, at: 0.5)
        #expect(first == -1)
        #expect(tooSoon == 0)
        #expect(second == -1)
    }

    @Test func releaseStopsRepeating() {
        var filter = RepeatFilter(initialDelay: 0.4, interval: 0.1)
        _ = filter.update(direction: 1, at: 0)
        let release = filter.update(direction: 0, at: 0.2)
        let later = filter.update(direction: 0, at: 1.0)
        #expect(release == 0)
        #expect(later == 0)
    }

    @Test func reversingMovesImmediatelyAndRestartsDelay() {
        var filter = RepeatFilter(initialDelay: 0.4, interval: 0.1)
        _ = filter.update(direction: 1, at: 0)
        let reverse = filter.update(direction: -1, at: 0.1)
        let beforeDelay = filter.update(direction: -1, at: 0.4)
        let afterDelay = filter.update(direction: -1, at: 0.5)
        #expect(reverse == -1)
        #expect(beforeDelay == 0)
        #expect(afterDelay == -1)
    }

    @Test func pressingAgainAfterReleaseMovesAgain() {
        var filter = RepeatFilter()
        _ = filter.update(direction: 1, at: 0)
        _ = filter.update(direction: 0, at: 0.05)
        let again = filter.update(direction: 1, at: 0.1)
        #expect(again == 1)
    }
}

@Suite struct StickAxisTests {
    @Test func needsPressThresholdToEngage() {
        var axis = StickAxis(pressThreshold: 0.5, releaseThreshold: 0.3)
        let small = axis.direction(for: 0.4)
        let full = axis.direction(for: 0.6)
        #expect(small == 0)
        #expect(full == 1)
    }

    @Test func staysEngagedUntilBelowReleaseThreshold() {
        var axis = StickAxis(pressThreshold: 0.5, releaseThreshold: 0.3)
        _ = axis.direction(for: -0.8)
        let between = axis.direction(for: -0.4)
        let released = axis.direction(for: -0.2)
        #expect(between == -1)
        #expect(released == 0)
    }

    @Test func flipsStraightAcrossCentre() {
        var axis = StickAxis()
        _ = axis.direction(for: 0.9)
        let flipped = axis.direction(for: -0.9)
        #expect(flipped == -1)
    }
}
