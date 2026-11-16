import AppKit
import SwiftUI

/// A borderless window still needs to accept keyboard focus.
final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = HomeState()
    private var window: LauncherWindow?
    private var keyMonitor: Any?

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
        let hosting = NSHostingView(rootView: HomeView(state: state))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // Console-style: no Dock, no menu bar while the launcher is up.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        NSApp.activate()
        NSCursor.setHiddenUntilMouseMoves(true)

        installKeyboardInput()

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

    // MARK: - Input

    /// Temporary keyboard navigation; controller input comes in a later step.
    private func installKeyboardInput() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !event.modifierFlags.contains(.command) else { return event }
            return MainActor.assumeIsolated {
                switch event.keyCode {
                case 123: // left arrow
                    self.state.move(by: -1)
                    return nil
                case 124: // right arrow
                    self.state.move(by: 1)
                    return nil
                default:
                    return event
                }
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

        // Stills: the selector resting on a tile.
        let shots: [(name: String, focus: Int)] = [
            ("home-first-tile", 0),
            ("home-third-tile", 2),
            ("home-scrolled", state.games.count - 1),
        ]
        for shot in shots {
            state.select(shot.focus)
            try? await Task.sleep(for: .seconds(1.2))
            Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("\(shot.name).png"))
            captureViewCache(window.contentView, to: directory.appendingPathComponent("\(shot.name)-viewcache.png"))
        }

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
            state.move(by: 1)
            try? await Task.sleep(for: .seconds(moveInterval * slowdown))
        }
        try? await Task.sleep(for: .seconds(3.5))

        recorder.cancel()
        let lines = await recorder.value
        let manifest = "slowdown\t\(slowdown)\n" + lines.joined(separator: "\n") + "\n"
        try? manifest.write(to: directory.appendingPathComponent("frames.tsv"), atomically: true, encoding: .utf8)
        Theme.motionScale = 1
    }

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
