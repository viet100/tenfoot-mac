import AppKit
import SwiftUI
import TenFootCore
import UniformTypeIdentifiers

/// A borderless window still needs to accept keyboard focus.
final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: LauncherState!
    private var controllers: ControllerManager?
    private var window: LauncherWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAmount: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let snapshotDir = Self.snapshotDirectory()
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        // Snapshot mode renders at a fixed TV-sized frame regardless of the CI display.
        let frame = snapshotDir == nil ? screenFrame : NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let window = LauncherWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(frame, display: true)
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        let status = snapshotDir == nil ? StatusModel() : StatusModel(sample: ())

        // CI snapshots start from an empty library and never touch the saved one.
        if snapshotDir == nil {
            let library: Library
            do {
                library = try Library.load(from: StorageLocation.library)
            } catch {
                print("Couldn't read library: \(error)")
                library = Library()
            }
            let preferences: Preferences
            do {
                preferences = try Preferences.load(from: StorageLocation.preferences)
            } catch {
                print("Couldn't read preferences: \(error)")
                preferences = Preferences()
            }
            state = LauncherState(library: library, preferences: preferences, saves: true)
        } else {
            state = LauncherState(library: Library(), preferences: Preferences(), saves: false)
        }
        state.onAddApp = { [weak self] in
            // Let the current input event finish before the picker takes over.
            DispatchQueue.main.async { self?.presentAddAppPanel() }
        }

        let controllers = ControllerManager { [weak self] action in self?.state.handle(action) }
        self.controllers = controllers
        let hosting = NSHostingView(rootView: LauncherView(state: state, status: status, controllers: controllers))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Console-style: no Dock, no menu bar while the launcher is up.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSApp.activate()
        NSCursor.setHiddenUntilMouseMoves(true)

        installKeyboardInput()
        installScrollInput()

        if let snapshotDir {
            Task { await renderSnapshots(of: window, to: snapshotDir) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Add App

    /// The standard Mac file picker, for choosing apps or programs to add.
    private func presentAddAppPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add App"
        panel.message = "Choose apps or programs to put on the TenFoot home screen."
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application, .unixExecutable, .executable, .shellScript]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        NSCursor.unhide()
        let response = panel.runModal()
        if response == .OK {
            state.addApps(panel.urls)
        }
        window?.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    // MARK: - Input

    /// Arrow keys move, Return selects, Esc goes back. Keys typed into the file
    /// picker are left alone.
    private func installKeyboardInput() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !event.modifierFlags.contains(.command) else { return event }
            return MainActor.assumeIsolated {
                guard event.window === self.window else { return event }
                let action: InputAction
                switch event.keyCode {
                case 123: action = .left
                case 124: action = .right
                case 125: action = .down
                case 126: action = .up
                case 36, 76: action = .confirm // Return, keypad Enter
                case 53: action = .back        // Esc
                default: return event
                }
                self.state.handle(action)
                return nil
            }
        }
    }

    /// Scroll wheel and trackpad swipes move along the game row (or the Settings list).
    /// A trackpad moves one step per `Theme.trackpadStep` points; a mouse wheel one step
    /// per notch. Momentum after lifting the fingers is ignored so the row stops where you do.
    private func installScrollInput() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                guard event.window === self.window else { return event }
                guard event.momentumPhase.isEmpty else { return nil }
                if event.phase == .began { self.scrollAmount = 0 }

                let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
                // Content follows the fingers: swiping left (negative delta) reveals games to the right.
                let delta = -(abs(dx) > abs(dy) ? dx : dy)
                if event.hasPreciseScrollingDeltas {
                    self.scrollAmount += delta
                    let steps = Int(self.scrollAmount / Theme.trackpadStep)
                    self.scrollAmount -= CGFloat(steps) * Theme.trackpadStep
                    self.state.scroll(by: steps)
                } else if delta != 0 {
                    self.state.scroll(by: delta > 0 ? 1 : -1)
                }
                return nil
            }
        }
    }

    /// The menu bar is hidden, but its key equivalents (⌘Q) still work.
    private func installMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit TenFoot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Snapshots (used by CI to review the UI)

    private static func snapshotDirectory() -> URL? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-snapshots"), flag + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[flag + 1], isDirectory: true)
    }

    private func renderSnapshots(of window: NSWindow, to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))

        func capture(_ name: String) async {
            try? await Task.sleep(for: .seconds(1.2))
            Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("\(name).png"))
            captureViewCache(window.contentView, to: directory.appendingPathComponent("\(name)-viewcache.png"))
        }

        // First launch: nothing added yet, focus on the Settings button.
        await capture("home-empty")
        state.handle(.confirm)
        await capture("settings")

        // Add some built-in apps the same way the file picker does.
        state.addApps(Self.sampleApps)
        await capture("home-added")

        // The selector resting on a tile.
        let shots: [(name: String, focus: Int)] = [
            ("home-first-tile", 0),
            ("home-third-tile", 2),
        ]
        for shot in shots {
            state.select(shot.focus)
            await capture(shot.name)
        }
        state.handle(.down)
        await capture("home-settings-button")

        // Settings → Icon Style, switched to Full Colour.
        state.handle(.confirm)
        state.handle(.down)
        state.handle(.confirm)
        await capture("settings-icon-style")
        state.handle(.back)
        state.handle(.up)

        await recordSlide(of: window, to: directory.appendingPathComponent("slide", isDirectory: true))
        NSApp.terminate(nil)
    }

    /// Records the selector sliding right across the row (and the row scrolling) as numbered
    /// frames plus a manifest of capture times. Motion is slowed down so the window can be
    /// captured often enough; CI turns the frames back into a real-speed GIF.
    private func recordSlide(of window: NSWindow, to directory: URL) async {
        let slowdown = 10.0
        let moveInterval = 0.15 // seconds between moves at real speed, like holding a direction
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        state.select(0)
        try? await Task.sleep(for: .seconds(1.5))
        Theme.motionScale = slowdown

        let windowNumber = window.windowNumber
        let recorder = Task.detached(priority: .userInitiated) { () -> [String] in
            var lines: [String] = []
            var frame = 0
            let start = Date()
            while !Task.isCancelled {
                let name = String(format: "frame-%04d.png", frame)
                let time = Date().timeIntervalSince(start)
                Self.captureWindow(windowNumber, to: directory.appendingPathComponent(name))
                lines.append("\(name)\t\(time)")
                frame += 1
            }
            return lines
        }

        try? await Task.sleep(for: .seconds(1))
        for _ in 0..<7 {
            state.handle(.right)
            try? await Task.sleep(for: .seconds(moveInterval * slowdown))
        }
        try? await Task.sleep(for: .seconds(3.5))

        recorder.cancel()
        let lines = await recorder.value
        let manifest = "slowdown\t\(slowdown)\n" + lines.joined(separator: "\n") + "\n"
        try? manifest.write(to: directory.appendingPathComponent("frames.tsv"), atomically: true, encoding: .utf8)
        Theme.motionScale = 1
    }

    /// Apps every Mac has, standing in for the user's games in CI snapshots.
    private static let sampleApps: [URL] = [
        "Chess", "Calculator", "Maps", "Music", "Photos", "Notes", "Weather", "Freeform", "TV", "Podcasts",
    ].map { URL(fileURLWithPath: "/System/Applications/\($0).app") }

    /// Window-server capture: the only way to get Liquid Glass composited as it appears on screen.
    nonisolated private static func captureWindow(_ windowNumber: Int, to url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(windowNumber), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("screencapture failed: \(error)")
        }
    }

    /// Fallback capture from the view hierarchy (glass may not render here).
    private func captureViewCache(_ view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
