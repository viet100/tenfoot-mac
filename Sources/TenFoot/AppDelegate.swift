import AppKit
import CoreServices
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
    private let launcher = GameLauncher()
    /// A game to start once the running one has closed.
    private var pendingLaunch: Game?
    private var isTerminating = false
    private var window: LauncherWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var rightClickMonitor: Any?
    private var scrollAmount: CGFloat = 0
    private var mouseViaSystem = false // CI drag check: post system-wide mouse events

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
            // Let the row show its press before the picker takes over the screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.pickerDelay) { self?.presentAddAppPanel() }
        }

        state.onPower = { [weak self] item in self?.power(item) }

        // Starting or resuming waits until A is let go; otherwise the game comes to the
        // front with A still held and takes it as a press of its own.
        state.onLaunch = { [weak self] game in
            self?.afterButtonsReleased { self?.launch(game) }
        }
        state.onResume = { [weak self] in
            self?.afterButtonsReleased { self?.launcher.resume() }
        }
        state.onClose = { [weak self] next in
            self?.pendingLaunch = next
            self?.launcher.close()
        }

        let controllers = ControllerManager { [weak self] action in self?.handleControllerAction(action) }
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
        installRightClick()

        // Back in front: pick up any icon changed in Finder (Get Info) meanwhile.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.reloadIcons() }
        }

        // Once the game is in front (TenFoot steps back), its tile stops showing the spinner.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.setLaunching(nil) }
        }

        if let snapshotDir {
            Task { await renderSnapshots(of: window, to: snapshotDir) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        NSApp.presentationOptions = []
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Games

    /// Opens the game; when it has quit, TenFoot comes back to the front.
    private func launch(_ game: Game) {
        state.show(message: "Starting \(game.title)…", for: 6)
        state.setLaunching(game.id)
        state.setRunningGame(game.id)
        controllers?.watchInBackground = true
        launcher.launch(game, onFailure: { [weak self] message in
            self?.gameEnded()
            self?.state.show(message: message, for: 6)
        }, onFinished: { [weak self] in
            guard let self else { return }
            self.gameEnded()
            self.returnToLauncher()
            if let next = self.pendingLaunch {
                self.pendingLaunch = nil
                self.launch(next)
            }
        })
    }

    private func afterButtonsReleased(_ action: @escaping () -> Void) {
        if let controllers {
            controllers.afterButtonsReleased(action)
        } else {
            action()
        }
    }

        private func gameEnded() {
        state.setLaunching(nil)
        state.setRunningGame(nil)
        controllers?.watchInBackground = false
    }

    /// Home from inside a game brings TenFoot back with the game focused; the game
    /// keeps running behind it. Everything else goes to the launcher as usual.
    private func handleControllerAction(_ action: InputAction) {
        if action == .home && !NSApp.isActive && launcher.current != nil {
            state.showRunningGame()
            returnToLauncher()
        } else if action == .power && !NSApp.isActive {
            // Home held during a game: TenFoot comes forward with the power menu open.
            returnToLauncher()
            state.handle(.power)
        } else {
            // Using the controller hides the pointer until the mouse moves again.
            if NSApp.isActive { NSCursor.setHiddenUntilMouseMoves(true) }
            state.handle(action)
        }
    }

    /// Brings TenFoot back to the front. Since macOS 14 an app in the background
    /// can't always activate itself, so it also asks Launch Services to open TenFoot,
    /// which brings the running copy forward like clicking it in the Dock.
    private func returnToLauncher() {
        NSApp.unhide(nil)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)

        // Only if that didn't work (and TenFoot isn't on its way out, which would
        // make Launch Services start a fresh copy).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard !NSApp.isActive, !self.isTerminating else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                if let error { print("Couldn't bring TenFoot forward: \(error)") }
            }
        }
    }

    // MARK: - Power menu

    /// Carries out a power menu choice. Restart and Shut Down go through macOS the same
    /// way the Apple menu does, so apps (and games) get the chance to save and quit.
    private func power(_ item: LauncherState.PowerItem) {
        switch item {
        case .quit:
            NSApp.terminate(nil)
        case .sleep:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            do {
                try process.run()
            } catch {
                state.show(message: "Couldn't put the Mac to sleep")
            }
        case .restart:
            askLoginWindow(AEEventID(kAERestart), failure: "Couldn't restart")
        case .shutDown:
            askLoginWindow(AEEventID(kAEShutDown), failure: "Couldn't shut down")
        case .cancel:
            break
        }
    }

    /// Sends a restart or shut down request to macOS (the loginwindow process).
    private func askLoginWindow(_ eventID: AEEventID, failure: String) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: eventID,
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        do {
            _ = try event.sendEvent(options: [.noReply], timeout: 10)
        } catch {
            print("\(failure): \(error)")
            state.show(message: "\(failure). Allow TenFoot in System Settings → Privacy & Security → Automation.")
        }
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
        state.finishAddingApps()
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
                case 7: action = .close        // X
                case 16: action = .options     // Y
                default: return event
                }
                self.state.handle(action)
                return nil
            }
        }
    }

    /// Right-clicking a game's tile opens its options menu.
    private func installRightClick() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                guard event.window === self.window, let view = self.window?.contentView else { return event }
                let layout = Layout(size: view.bounds.size)
                // Window coordinates count up from the bottom; SwiftUI's count down from the top.
                let x = event.locationInWindow.x
                let y = view.bounds.height - event.locationInWindow.y
                let rowY = layout.unit * Theme.rowCenterY
                guard abs(y - rowY) <= layout.tile / 2,
                      let index = layout.game(atX: x, scrollIndex: self.state.scrollIndex,
                                              count: self.state.games.count)
                else { return event }
                self.state.openOptions(game: index)
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

        // Settings → Add App, held pressed as if the file picker were open (the real
        // picker would stop the run).
        state.handle(.confirm)
        let addApp = state.onAddApp
        state.onAddApp = nil
        state.handle(.confirm)
        await capture("settings-add-app-pressed")
        print("ADD APP CHECK: row held pressed while the picker is open: \(state.addingApps), on \(state.screen)")
        state.finishAddingApps()
        state.onAddApp = addApp

        // Settings → Icon Style, switched to Full Colour.
        state.handle(.down)
        state.handle(.confirm)
        await capture("settings-icon-style")
        state.handle(.back)
        state.handle(.up)

        await recordSlide(of: window, to: directory.appendingPathComponent("slide", isDirectory: true))
        await checkDragToReorder(window: window, directory: directory)
        await checkLaunchAndReturn(window: window, directory: directory)
        await checkRemove(window: window, directory: directory)
        await checkPowerMenu(window: window, directory: directory)
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
        await record(window, to: directory, slowdown: slowdown) {
            for _ in 0..<7 {
                self.state.handle(.right)
                try? await Task.sleep(for: .seconds(moveInterval * slowdown))
            }
        }
    }

    /// Captures the window as fast as it can while `actions` run with every animation
    /// slowed down `slowdown` times, then writes the manifest `make-gif.py` reads.
    private func record(_ window: NSWindow, to directory: URL, slowdown: Double,
                        actions: () async -> Void) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        await actions()
        try? await Task.sleep(for: .seconds(3.5))

        recorder.cancel()
        let lines = await recorder.value
        let manifest = "slowdown\t\(slowdown)\n" + lines.joined(separator: "\n") + "\n"
        try? manifest.write(to: directory.appendingPathComponent("frames.tsv"), atomically: true, encoding: .utf8)
        Theme.motionScale = 1
    }

    /// Drags games along the row with real mouse events sent to the window: stills of a
    /// game mid-drag and after the drop, then a GIF of two drags (the second one held at
    /// the right edge so the row scrolls). Logged as "DRAG CHECK: …".
    private func checkDragToReorder(window: NSWindow, directory: URL) async {
        guard let size = window.contentView?.bounds.size else { return }
        let layout = Layout(size: size)
        func titles() -> String { state.games.map(\.title).joined(separator: ", ") }
        func center(_ slot: Int) -> CGPoint { layout.tileCenter(slot: slot, scrollIndex: state.scrollIndex) }

        // Real mouse events, posted system-wide like a mouse would (events handed straight
        // to the app don't reach SwiftUI's gestures). Every press and release TenFoot
        // receives is logged, with how many drag events came in between.
        mouseViaSystem = true
        state.trace = { print("DRAG TRACE: \($0)") }
        final class Count { var dragged = 0 }
        let count = Count()
        let mouseLog = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { event in
            if event.type == .leftMouseDragged {
                count.dragged += 1
            } else {
                let point = event.locationInWindow
                print("DRAG TRACE: mouse \(event.type == .leftMouseDown ? "down" : "up") at \(Int(point.x)),\(Int(point.y)), "
                      + "click count \(event.clickCount), \(count.dragged) drag events before it, "
                      + "TenFoot active: \(MainActor.assumeIsolated { NSApp.isActive })")
                count.dragged = 0
            }
            return event
        }
        defer { if let mouseLog { NSEvent.removeMonitor(mouseLog) } }

        // Click an empty spot first, the way you'd click TenFoot to bring it to the front.
        state.select(0)
        for _ in 0..<4 where !NSApp.isActive {
            sendMouse(.leftMouseDown, at: CGPoint(x: size.width / 2, y: layout.unit * 0.15), in: window)
            try? await Task.sleep(for: .seconds(0.05))
            sendMouse(.leftMouseUp, at: CGPoint(x: size.width / 2, y: layout.unit * 0.15), in: window)
            try? await Task.sleep(for: .seconds(1))
        }
        print("DRAG CHECK: before: \(titles()); TenFoot active: \(NSApp.isActive), key window: \(window.isKeyWindow)")

        // A plain click on the third game should focus it.
        sendMouse(.leftMouseDown, at: center(2), in: window)
        try? await Task.sleep(for: .seconds(0.05))
        sendMouse(.leftMouseUp, at: center(2), in: window)
        try? await Task.sleep(for: .seconds(0.8))
        print("DRAG CHECK: clicking the third game focused it: \(state.focusIndex == 2)")
        state.select(0)
        try? await Task.sleep(for: .seconds(0.8))

        // Stills: the second game picked up and held over the fourth slot.
        let moved = state.games[1].title
        let hold = center(3).moved(30, -25)
        sendMouse(.leftMouseDown, at: center(1), in: window)
        await dragMouse(from: center(1), to: hold, seconds: 0.5, in: window)
        try? await Task.sleep(for: .seconds(1))
        print("DRAG CHECK: mid-drag: picked up: \(state.drag != nil), "
              + "held over slot: \(state.drag.map { String($0.target) } ?? "-")")
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("home-drag.png"))
        sendMouse(.leftMouseUp, at: hold, in: window)
        try? await Task.sleep(for: .seconds(1))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("home-dropped.png"))
        let landed = state.games.firstIndex { $0.title == moved }
        print("DRAG CHECK: after dropping \(moved) on slot 3: \(titles()); "
              + (landed == 3 && state.drag == nil ? "PASSED" : "FAILED, it's at \(landed.map(String.init) ?? "nowhere")"))

        // Straight after a drop, the same game dragged back again.
        sendMouse(.leftMouseDown, at: center(3), in: window)
        await dragMouse(from: center(3), to: center(1), seconds: 0.5, in: window)
        try? await Task.sleep(for: .seconds(0.3))
        sendMouse(.leftMouseUp, at: center(1), in: window)
        try? await Task.sleep(for: .seconds(1))
        let back = state.games.firstIndex { $0.title == moved }
        print("DRAG CHECK: dragged \(moved) straight back to slot 1: \(titles()); "
              + (back == 1 ? "PASSED" : "FAILED, it's at \(back.map(String.init) ?? "nowhere")"))

        // GIF: drag the first game two places right; then take the third one to the right
        // edge and hold it there while the row scrolls.
        let slowdown = 6.0
        await record(window, to: directory.appendingPathComponent("drag", isDirectory: true), slowdown: slowdown) {
            let start = center(0), end = center(2).moved(-20, -20)
            self.sendMouse(.leftMouseDown, at: start, in: window)
            await self.dragMouse(from: start, to: end, seconds: 0.7 * slowdown, in: window)
            try? await Task.sleep(for: .seconds(0.4 * slowdown))
            self.sendMouse(.leftMouseUp, at: end, in: window)
            try? await Task.sleep(for: .seconds(0.8 * slowdown))

            let grab = center(2), edge = CGPoint(x: size.width - 30, y: grab.y - 20)
            self.sendMouse(.leftMouseDown, at: grab, in: window)
            await self.dragMouse(from: grab, to: edge, seconds: 0.6 * slowdown, in: window)
            try? await Task.sleep(for: .seconds(1.2 * slowdown))
            let back = edge.moved(-layout.step * 1.2, 0)
            await self.dragMouse(from: edge, to: back, seconds: 0.3 * slowdown, in: window)
            try? await Task.sleep(for: .seconds(0.3 * slowdown))
            self.sendMouse(.leftMouseUp, at: back, in: window)
        }
        print("DRAG CHECK: after the GIF drags: \(titles()); first visible: \(state.scrollIndex); "
              + "dragging: \(state.drag != nil)")
    }

    /// Sends a mouse event to the window at `point` (top-left origin, like SwiftUI).
    private func sendMouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) {
        let height = window.contentView?.bounds.height ?? 0
        if mouseViaSystem {
            // Window point → AppKit screen point (bottom-left origin) → CG global point (top-left origin).
            let screenY = window.frame.maxY - point.y
            let primaryHeight = NSScreen.screens.first?.frame.height ?? height
            let global = CGPoint(x: window.frame.minX + point.x, y: primaryHeight - screenY)
            let cgType: CGEventType = switch type {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            default: .leftMouseDragged
            }
            CGEvent(mouseEventSource: nil, mouseType: cgType, mouseCursorPosition: global, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            return
        }
        guard let event = NSEvent.mouseEvent(
            with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
        ) else { return }
        // Through the app, the way real mouse events arrive.
        NSApp.sendEvent(event)
    }

    /// Moves a held mouse button from `start` to `end` over `seconds`, easing in and out.
    private func dragMouse(from start: CGPoint, to end: CGPoint, seconds: Double, in window: NSWindow) async {
        let steps = max(1, Int(seconds * 60))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            let point = CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
            sendMouse(.leftMouseDragged, at: point, in: window)
            try? await Task.sleep(for: .seconds(seconds / Double(steps)))
        }
    }

    /// Opens Calculator from the row, quits it, and checks TenFoot comes back to the
    /// front. The result is printed to the CI log as "LAUNCH CHECK: …".
    private func checkLaunchAndReturn(window: NSWindow, directory: URL) async {
        let bundleID = "com.apple.calculator"
        guard let index = state.games.firstIndex(where: { $0.title == "Calculator" }) else {
            print("LAUNCH CHECK: Calculator isn't in the sample row")
            return
        }
        state.select(index)
        try? await Task.sleep(for: .seconds(1))
        state.handle(.confirm)
        // The press bounce has settled; the tile shows the spinner until Calculator is in front.
        try? await Task.sleep(for: .seconds(0.6))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("launch-pressed.png"))
        print("LAUNCH CHECK: spinner on Calculator right after pressing: \(state.launchingGameID == state.games[index].id)")

        var calculator: NSRunningApplication?
        for _ in 0..<40 where calculator == nil {
            try? await Task.sleep(for: .seconds(0.25))
            calculator = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        guard let calculator else {
            print("LAUNCH CHECK: FAILED, Calculator didn't open")
            return
        }
        try? await Task.sleep(for: .seconds(2))
        let tenFootWasInFront = NSApp.isActive
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("launch-starting.png"))

        func describe(_ pids: Set<Int32>) -> String {
            pids.map { pid in "\(pid):\(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?")" }
                .sorted().joined(separator: ", ")
        }
        print("LAUNCH CHECK: Calculator is pid \(calculator.processIdentifier); tracking [\(describe(launcher.trackedProcesses))]")

        calculator.terminate()
        let quitAt = Date()
        var returned = false
        for step in 0..<60 where !returned {
            try? await Task.sleep(for: .seconds(0.25))
            returned = NSApp.isActive && launcher.current == nil
            if step % 4 == 3 {
                let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "none"
                print("LAUNCH CHECK: +\((step + 1) / 4)s game finished: \(launcher.current == nil), "
                      + "TenFoot active: \(NSApp.isActive), frontmost: \(front), tracking [\(describe(launcher.trackedProcesses))]")
            }
        }
        let seconds = String(format: "%.1f", Date().timeIntervalSince(quitAt))
        print("LAUNCH CHECK: opened Calculator (TenFoot in front while it ran: \(tenFootWasInFront)); "
              + (returned ? "PASSED, TenFoot came back \(seconds)s after Calculator quit" : "FAILED, TenFoot didn't come back"))

        await checkHomeAndClose(window: window, directory: directory, bundleID: bundleID)
    }

    /// Opens Calculator again, presses Home (as a controller would, from the
    /// background), then closes it from TenFoot. Logged as "CLOSE CHECK: …".
    private func checkHomeAndClose(window: NSWindow, directory: URL, bundleID: String) async {
        try? await Task.sleep(for: .seconds(1))
        state.handle(.confirm)
        var calculator: NSRunningApplication?
        for _ in 0..<40 where calculator == nil || NSApp.isActive {
            try? await Task.sleep(for: .seconds(0.25))
            calculator = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        guard calculator != nil else {
            print("CLOSE CHECK: FAILED, Calculator didn't open")
            return
        }
        try? await Task.sleep(for: .seconds(1))

        handleControllerAction(.home)
        var back = false
        for _ in 0..<20 where !back {
            try? await Task.sleep(for: .seconds(0.25))
            back = NSApp.isActive
        }
        print("CLOSE CHECK: Home brought TenFoot back: \(back); Calculator still running: \(launcher.current != nil)")
        try? await Task.sleep(for: .seconds(1))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("home-running-game.png"))

        // The close prompt fading in, then out again on B.
        let slowdown = 6.0
        await record(window, to: directory.appendingPathComponent("prompt", isDirectory: true), slowdown: slowdown) {
            self.state.handle(.close)
            try? await Task.sleep(for: .seconds(1 * slowdown))
            self.state.handle(.back)
            try? await Task.sleep(for: .seconds(0.3 * slowdown))
        }

        state.handle(.close)
        try? await Task.sleep(for: .seconds(1.2))
        state.handle(.left)
        try? await Task.sleep(for: .seconds(0.8))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("close-prompt-cancel.png"))
        state.handle(.right)
        try? await Task.sleep(for: .seconds(0.8))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("close-prompt.png"))

        state.handle(.confirm)
        var closed = false
        for _ in 0..<60 where !closed {
            try? await Task.sleep(for: .seconds(0.25))
            closed = launcher.current == nil
                && NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        }
        print("CLOSE CHECK: " + (closed && NSApp.isActive ? "PASSED, Calculator closed and TenFoot is in front"
                                                          : "FAILED, closed: \(closed), TenFoot active: \(NSApp.isActive)"))
    }

    /// Opens the options menu on the focused game (a still of it), then removes that game.
    /// Logged as "REMOVE CHECK: …".
    private func checkRemove(window: NSWindow, directory: URL) async {
        guard state.screen == .home, !state.games.isEmpty else {
            print("REMOVE CHECK: FAILED, no games on the home screen")
            return
        }
        if state.area != .games { state.handle(.up) }
        try? await Task.sleep(for: .seconds(0.5))
        let before = state.games.map(\.title)
        let target = state.games[state.focusIndex].title
        state.handle(.options)
        try? await Task.sleep(for: .seconds(1.2))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("options-menu.png"))
        state.handle(.confirm)
        try? await Task.sleep(for: .seconds(1.2))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("options-removed.png"))
        let after = state.games.map(\.title)
        let removed = after.count == before.count - 1 && !after.contains(target) && state.optionsMenu == nil
        print("REMOVE CHECK: " + (removed ? "PASSED, removed \(target) (\(before.count) → \(after.count) games)"
                                          : "FAILED, before: \(before), after: \(after)"))
    }

    /// Opens the power menu, then asks to restart and says no. Nothing is carried out:
    /// choices are only logged. Logged as "POWER CHECK: …".
    private func checkPowerMenu(window: NSWindow, directory: URL) async {
        var chosen: [LauncherState.PowerItem] = []
        state.onPower = { chosen.append($0) }
        state.handle(.power)
        try? await Task.sleep(for: .seconds(1.2))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("power-menu.png"))
        let opened = state.powerMenuOpen
        state.handle(.down) // Sleep
        state.handle(.down) // Restart
        state.handle(.confirm)
        try? await Task.sleep(for: .seconds(1.2))
        Self.captureWindow(window.windowNumber, to: directory.appendingPathComponent("power-confirm.png"))
        let asked = state.powerConfirm == .restart && state.powerConfirmIndex == 1
        state.handle(.confirm) // Cancel is focused
        try? await Task.sleep(for: .seconds(0.8))
        let ok = opened && asked && chosen.isEmpty && !state.popupOpen
        print("POWER CHECK: " + (ok ? "PASSED, menu opened, Restart asked first, Cancel did nothing"
                                    : "FAILED, opened: \(opened), asked: \(asked), chosen: \(chosen), still open: \(state.popupOpen)"))
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

private extension CGPoint {
    func moved(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}
