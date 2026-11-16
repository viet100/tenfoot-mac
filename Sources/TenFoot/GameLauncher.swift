import AppKit
import TenFootCore

/// Opens a game and calls back once it has finished, so the launcher can return.
///
/// `.app` bundles are opened through Launch Services, like double-clicking them.
/// Anything else (an emulator binary, a shell script) is run directly. While the
/// game runs, newly started apps are offered to a `GameSession`, which decides
/// whether they belong to the game (CrossOver/Wine processes, launcher hand-offs).
@MainActor
final class GameLauncher {
    /// The game being played, if any.
    private(set) var current: Game?

    /// Makes the game's windows full screen as they open.
    let fullscreener = WindowFullscreener()

    /// Processes currently counted as the game (for diagnostics).
    var trackedProcesses: Set<Int32> { session?.processes ?? [] }

    private var session: GameSession?
    private var onFinished: (() -> Void)?
    private var knownApps: Set<Int32> = []
    private var appsObservation: NSKeyValueObservation?
    private var timer: Timer?

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Starts `game`. `onFailure` gets a message to show if it couldn't be opened;
    /// `onFinished` is called once every process of the game has quit.
    func launch(_ game: Game, onFailure: @escaping (String) -> Void, onFinished: @escaping () -> Void) {
        // Pressing A again while a game is starting or running brings it forward
        // instead of starting a second copy.
        if current?.id == game.id, session != nil {
            resume()
            return
        }
        stopTracking()
        fullscreener.reset()

        current = game
        self.onFinished = onFinished
        session = GameSession(expectsWine: Self.isCrossOverLauncher(game.url), at: now)
        knownApps = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.runningAppsChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }

        if Self.isAppBundle(game.url) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: game.url, configuration: configuration) { app, error in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.current?.id == game.id else { return }
                    if let app {
                        self.session?.track(app.processIdentifier, at: self.now)
                    } else {
                        self.stopTracking()
                        onFailure("Couldn't open \(game.title): \(error?.localizedDescription ?? "unknown error")")
                    }
                }
            }
        } else {
            do {
                let process = try Self.run(executable: game.url)
                session?.track(process.processIdentifier, at: now)
            } catch {
                stopTracking()
                onFailure("Couldn't start \(game.title): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tracking

    private func runningAppsChanged() {
        guard session != nil else { return }
        let apps = NSWorkspace.shared.runningApplications
        for app in apps where !knownApps.contains(app.processIdentifier) {
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            // The game's own app is always the game, without using up a hand-off.
            if let game = current, Self.isAppBundle(game.url),
               app.bundleURL?.standardizedFileURL == game.url.standardizedFileURL {
                session?.track(app.processIdentifier, at: now)
                continue
            }
            // A store like Steam can start when one of its games is opened, but it isn't
            // the game: it shouldn't be waited for, or quit when the game is closed.
            if let id = app.bundleIdentifier, Self.storeLaunchers.contains(id) { continue }
            let isWine = Self.isWine(app)
            // Background helpers and menu bar items only count if they're Wine.
            if isWine || app.activationPolicy == .regular {
                session?.appLaunched(app.processIdentifier, isWine: isWine, at: now)
            }
        }
        knownApps = Set(apps.map(\.processIdentifier))
    }

    /// Notices processes that have exited, and finishes when the session is over.
    private func check() {
        guard var session else { return }
        for pid in session.processes where !Self.isAlive(pid) {
            session.processQuit(pid, at: now)
        }
        self.session = session
        fullscreener.check(processes: session.processes, now: now)
        if session.isOver(at: now) {
            let finished = onFinished
            stopTracking()
            finished?()
        }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        appsObservation = nil
        session = nil
        current = nil
        onFinished = nil
    }

    /// Asks every process of the game to quit, like ⌘Q. Anything still running
    /// after `Theme.closeTimeout` is stopped outright. `onFinished` follows as usual.
    func close() {
        guard let session else { return }
        for pid in session.processes {
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.terminate()
            } else {
                kill(pid, SIGTERM)
            }
        }
        let gameID = current?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.closeTimeout) { [weak self] in
            guard let self, self.current?.id == gameID, let session = self.session else { return }
            for pid in session.processes where Self.isAlive(pid) {
                if let app = NSRunningApplication(processIdentifier: pid) {
                    app.forceTerminate()
                } else {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    /// Brings the running game back to the front.
    func resume() {
        guard let session else { return }
        for pid in session.processes {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                app.activate()
                return
            }
        }
    }

    // MARK: - Helpers

    /// Game stores that open alongside their games (Steam, Epic Games, GOG Galaxy).
    private static let storeLaunchers: Set<String> = [
        "com.valvesoftware.steam",
        "com.epicgames.EpicGamesLauncher",
        "com.gog.galaxy",
    ]

    private static func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
    }

    /// Runs an executable or script directly, from its own folder.
    private static func run(executable url: URL) throws -> Process {
        let process = Process()
        if FileManager.default.isExecutableFile(atPath: url.path) {
            process.executableURL = url
        } else {
            // A script without the executable bit set.
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [url.path]
        }
        process.currentDirectoryURL = url.deletingLastPathComponent()
        try process.run()
        return process
    }

    private static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// A Windows program running under CrossOver/Wine.
    private static func isWine(_ app: NSRunningApplication) -> Bool {
        let paths = [app.executableURL?.path, app.bundleURL?.path].compactMap { $0?.lowercased() }
        return paths.contains { $0.contains("wine") || $0.contains("crossover") }
    }

    /// CrossOver's launchers live in ~/Applications/CrossOver and are small scripts
    /// that call CrossOver; either one is enough to expect Wine to start.
    private static func isCrossOverLauncher(_ url: URL) -> Bool {
        if url.path.lowercased().contains("crossover") { return true }
        guard let executable = Bundle(url: url)?.executableURL,
              let handle = try? FileHandle(forReadingFrom: executable) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        guard head.starts(with: Data("#!".utf8)) else { return false }
        let text = String(decoding: head, as: UTF8.self).lowercased()
        return text.contains("crossover") || text.contains("wine")
    }
}
