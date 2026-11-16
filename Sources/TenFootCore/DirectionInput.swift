/// Turns a held direction into discrete moves: one move on press, then
/// repeats after `initialDelay`, every `interval`, until released or reversed.
///
/// Directions are `-1` (left), `0` (none) and `1` (right).
public struct RepeatFilter: Sendable {
    public var initialDelay: Double
    public var interval: Double

    private var held = 0
    private var nextRepeat = 0.0

    public init(initialDelay: Double = 0.4, interval: Double = 0.11) {
        self.initialDelay = initialDelay
        self.interval = interval
    }

    /// Feed the current direction at time `now` (seconds). Call it whenever input
    /// changes and regularly while a direction is held.
    /// Returns the move to make: `-1`, `0` or `1`.
    public mutating func update(direction: Int, at now: Double) -> Int {
        let direction = direction.signum()
        if direction != held {
            held = direction
            nextRepeat = now + initialDelay
            return direction
        }
        guard direction != 0, now >= nextRepeat else { return 0 }
        nextRepeat = max(nextRepeat + interval, now)
        return direction
    }
}

/// Reads an analog axis (-1...1) as a digital direction with hysteresis, so a
/// stick resting near the threshold doesn't flicker on and off.
public struct StickAxis: Sendable {
    public var pressThreshold: Float
    public var releaseThreshold: Float

    private var current = 0

    public init(pressThreshold: Float = 0.5, releaseThreshold: Float = 0.3) {
        self.pressThreshold = pressThreshold
        self.releaseThreshold = releaseThreshold
    }

    public mutating func direction(for value: Float) -> Int {
        if value >= pressThreshold {
            current = 1
        } else if value <= -pressThreshold {
            current = -1
        } else if abs(value) < releaseThreshold {
            current = 0
        }
        return current
    }
}
