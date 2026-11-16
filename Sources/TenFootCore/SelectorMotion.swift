/// How fast something is moving, measured from its position on each frame.
///
/// The speed is smoothed over a few frames so uneven frame timing doesn't make it
/// flicker, and drops to zero after a pause so the first frame of a new move isn't
/// read as one huge jump.
public struct VelocityTracker: Sendable {
    /// Weight of the newest frame in the smoothed speed (0...1).
    public var smoothing: Double
    /// A longer gap between frames than this means the motion had stopped.
    public var maxGap: Double

    public private(set) var speed: Double = 0
    private var last: (x: Double, time: Double)?

    public init(smoothing: Double = 0.5, maxGap: Double = 0.1) {
        self.smoothing = smoothing
        self.maxGap = maxGap
    }

    /// Records where it is at `time` (seconds) and returns its speed in units per second.
    public mutating func sample(x: Double, at time: Double) -> Double {
        guard let previous = last else {
            last = (x, time)
            return speed
        }
        let gap = time - previous.time
        guard gap > 0 else { return speed } // the same frame drawn again
        last = (x, time)
        guard gap <= maxGap else {
            speed = 0
            return speed
        }
        let instant = abs(x - previous.x) / gap
        speed = smoothing * instant + (1 - smoothing) * speed
        return speed
    }

    /// It has stopped: the next move starts from zero.
    public mutating func reset() {
        speed = 0
        last = nil
    }
}

/// How much the selector stretches while it moves: longer across, a little shorter
/// top to bottom, more the faster it goes.
public enum SelectorStretch {
    /// Width and height as multiples of the selector's size at rest. `squash` is how much
    /// of the extra width is taken off the height (0.4 takes off 40% as much).
    public static func scale(tilesPerSecond: Double, perTilePerSecond: Double,
                             maxStretch: Double, squash: Double) -> (width: Double, height: Double) {
        let grow = min(maxStretch, max(0, tilesPerSecond) * perTilePerSecond)
        return (1 + grow, 1 - grow * squash)
    }
}
