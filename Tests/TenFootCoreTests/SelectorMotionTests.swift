import Testing
@testable import TenFootCore

struct SelectorMotionTests {
    private func stretch(_ tilesPerSecond: Double) -> (width: Double, height: Double) {
        SelectorStretch.scale(tilesPerSecond: tilesPerSecond, perTilePerSecond: 0.02, maxStretch: 0.3, squash: 0.4)
    }

    @Test func restingSelectorIsItsNormalSize() {
        let size = stretch(0)
        #expect(size.width == 1 && size.height == 1)
    }

    @Test func fasterStretchesMoreUpToTheCap() {
        let slow = stretch(3), fast = stretch(9), flatOut = stretch(1000)
        #expect(slow.width > 1 && fast.width > slow.width)
        #expect(fast.height < slow.height && slow.height < 1)
        #expect(abs(flatOut.width - 1.3) < 1e-9)
        #expect(stretch(-5).width == 1) // speed is never negative, but stay safe
    }

    @Test func heightShrinksLessThanWidthGrows() {
        let size = stretch(10)
        #expect(1 - size.height < size.width - 1)
    }

    @Test func tracksASteadySpeed() {
        var tracker = VelocityTracker()
        var speed = 0.0
        for frame in 0...60 { // 10 points a frame at 60 frames a second: 600 per second
            speed = tracker.sample(x: Double(frame) * 10, at: Double(frame) / 60)
        }
        #expect(abs(speed - 600) < 1)
    }

    @Test func pauseOrSameFrameDoesNotInventSpeed() {
        var tracker = VelocityTracker()
        _ = tracker.sample(x: 0, at: 0)
        _ = tracker.sample(x: 10, at: 1.0 / 60)
        let again = tracker.sample(x: 10, at: 1.0 / 60) // drawn twice in one frame
        #expect(again > 0)
        #expect(tracker.sample(x: 500, at: 2) == 0)     // a long gap: it had stopped
        tracker.reset()
        #expect(tracker.speed == 0)
    }
}
