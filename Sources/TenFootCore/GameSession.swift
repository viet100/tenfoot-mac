/// Decides which running processes belong to a launched game, and when the game
/// has finished so the launcher can come back.
///
/// A game isn't always one process. A CrossOver launcher starts Wine processes and
/// may quit straight away; a script may start the real app and exit. So the session
/// takes in:
/// - for a CrossOver game, any Wine app that starts while it's running, and
/// - the first other app that starts shortly after the game was launched, or
///   shortly after its last process quit (a hand-off). Only one app is taken per
///   hand-off, so apps you happen to open around the same time aren't counted as
///   the game (and aren't quit with it).
///
/// Once the game is being closed, nothing new is taken in.
///
/// It's over once none of those are running and nothing has taken over for a short
/// grace period. Times are in seconds.
public struct GameSession: Sendable {
    public struct Timing: Sendable {
        /// Other apps starting this soon after launch (or after a game process quits) count as the game.
        public var handoffWindow: Double = 10
        /// Wait this long after the last game process quits before returning.
        public var quitGrace: Double = 2
        /// A game that quits this soon after it started was handing over (a Steam
        /// shortcut asking Steam to start the game), so wait `handoffWindow` for it.
        public var handoffQuit: Double = 2
        /// How long to wait for anything to show up after launch.
        public var startGrace: Double = 10
        /// CrossOver games can take a while to start Wine; wait longer for it.
        public var wineStartGrace: Double = 30

        public init() {}
    }

    public private(set) var processes: Set<Int32> = []
    public let expectsWine: Bool
    /// The game is being closed: no more apps are taken in.
    public private(set) var isClosing = false
    public var timing: Timing

    private var sawWine = false
    private var trackedAnything = false
    private var firstTracked: Double?
    private var lastChange: Double
    /// Whether a hand-off may still take in an app (one per launch or quit).
    private var handoffOpen = true

    public init(expectsWine: Bool, at now: Double, timing: Timing = Timing()) {
        self.expectsWine = expectsWine
        self.timing = timing
        lastChange = now
    }

    /// The process TenFoot itself started (or the app it opened).
    ///
    /// Only real process IDs are kept. macOS reports -1 for an app that has no process
    /// (one that already quit, like a Steam shortcut), and signalling -1 or 0 would
    /// reach every app the user has open, not just the game.
    public mutating func track(_ pid: Int32, at now: Double) {
        guard Self.isRealProcess(pid) else { return }
        processes.insert(pid)
        trackedAnything = true
        if firstTracked == nil { firstTracked = now }
    }

    /// Another app started while the session is running. Returns true if it's
    /// counted as part of the game.
    @discardableResult
    public mutating func appLaunched(_ pid: Int32, isWine: Bool, at now: Double) -> Bool {
        guard Self.isRealProcess(pid) else { return false }
        if processes.contains(pid) { return true }
        guard !isClosing else { return false }
        if isWine && expectsWine {
            sawWine = true
        } else {
            guard handoffOpen, now - lastChange <= timing.handoffWindow else { return false }
            handoffOpen = false
        }
        track(pid, at: now)
        return true
    }

    /// A process quit (pids that aren't part of the game are ignored).
    public mutating func processQuit(_ pid: Int32, at now: Double) {
        guard processes.remove(pid) != nil else { return }
        lastChange = now
        // A hand-off is when the game is gone and something takes over, not when
        // one of several processes quits.
        if processes.isEmpty { handoffOpen = true }
    }

    /// The user asked to close the game.
    public mutating func closeRequested() {
        isClosing = true
    }

    /// A process ID that names one process (not -1 or 0, which mean "all" or "this group").
    public static func isRealProcess(_ pid: Int32) -> Bool {
        pid > 0
    }

    /// True once the game has finished and the launcher should come back.
    public func isOver(at now: Double) -> Bool {
        guard processes.isEmpty else { return false }
        let grace: Double
        if expectsWine && !sawWine {
            grace = timing.wineStartGrace
        } else if !trackedAnything {
            grace = timing.startGrace
        } else if !isClosing, let firstTracked, lastChange - firstTracked <= timing.handoffQuit {
            // Gone almost as soon as it started: a shortcut handing over to a store
            // (Steam) that may take a while to start the real game.
            grace = timing.handoffWindow
        } else {
            grace = timing.quitGrace
        }
        return now - lastChange >= grace
    }
}
