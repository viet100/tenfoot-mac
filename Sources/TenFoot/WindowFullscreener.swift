import AppKit
import ApplicationServices
import TenFootCore

/// Makes a game's windows fill the screen as they open: macOS full screen where the
/// window supports it (like the green button), otherwise resized to cover the screen.
/// Windows that already cover it are left alone, and each window is only handled
/// once, so a game you take out of full screen yourself stays that way.
///
/// Uses macOS Accessibility, which the user allows once in System Settings →
/// Privacy & Security → Accessibility.
@MainActor
final class WindowFullscreener {
    /// Called once if Accessibility isn't allowed yet (macOS also shows its own prompt).
    var onNeedsPermission: (() -> Void)?

    private struct Seen {
        let window: AXUIElement
        let since: Double
        var attempts = 0
        var done = false
    }
    private var seen: [Seen] = []

    init() {
        // A busy game can take seconds to answer; don't let that freeze TenFoot (and Home).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Theme.accessibilityTimeout)
    }
    private var askedForPermission = false

    /// A new game: forget the last one's windows.
    func reset() {
        seen = []
    }

    /// Looks at the game's windows; called every half second while it runs.
    func check(processes: Set<Int32>, now: Double) {
        guard !processes.isEmpty else { return }
        guard AXIsProcessTrusted() else {
            if !askedForPermission {
                askedForPermission = true
                let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // kAXTrustedCheckOptionPrompt
                _ = AXIsProcessTrustedWithOptions(prompt)
                onNeedsPermission?()
            }
            return
        }
        for pid in processes {
            for window in Self.windows(of: pid) {
                guard let index = seen.firstIndex(where: { CFEqual($0.window, window) }) else {
                    // Give a new window a moment to finish opening before touching it.
                    seen.append(Seen(window: window, since: now))
                    continue
                }
                guard !seen[index].done, now - seen[index].since >= Theme.fullscreenDelay,
                      let info = Self.info(of: window) else { continue }
                switch Fullscreen.action(for: info) {
                case .leave:
                    seen[index].done = true
                case .nativeFullScreen where seen[index].attempts < Theme.fullscreenAttempts:
                    // Going full screen takes a moment; ask again until it reports full screen.
                    let result = AXUIElementSetAttributeValue(window, Self.fullScreen, kCFBooleanTrue)
                    seen[index].attempts += 1
                    if result != .success {
                        Self.fill(window, screen: info.screen)
                        seen[index].done = true
                    }
                case .nativeFullScreen, .fillScreen:
                    Self.fill(window, screen: info.screen)
                    seen[index].done = true
                }
            }
        }
    }

    // MARK: - Accessibility

    private static let fullScreen = "AXFullScreen" as CFString

    private static func windows(of pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// The window's state, in Accessibility's coordinates (top-left of the main screen, y down).
    private static func info(of window: AXUIElement) -> GameWindow? {
        guard let position: CGPoint = value(of: window, kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = value(of: window, kAXSizeAttribute, type: .cgSize) else { return nil }
        let frame = CGRect(origin: position, size: size)
        var settable = DarwinBoolean(false)
        let canFullScreen = AXUIElementIsAttributeSettable(window, fullScreen, &settable) == .success && settable.boolValue
        return GameWindow(
            isStandard: string(of: window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
            isMinimized: bool(of: window, kAXMinimizedAttribute as CFString),
            isFullScreen: bool(of: window, fullScreen),
            canFullScreen: canFullScreen,
            frame: frame,
            screen: screen(containing: frame))
    }

    /// Moves and resizes the window to cover the screen. Position goes first and again
    /// last, as some apps won't grow past the screen edge from where they are.
    private static func fill(_ window: AXUIElement, screen: CGRect) {
        var origin = screen.origin, size = screen.size
        if let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, extent)
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    /// The whole screen (not just the area beside the menu bar and Dock) that holds
    /// most of the window, in Accessibility's coordinates.
    private static func screen(containing frame: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screens = NSScreen.screens.map { screen -> CGRect in
            let f = screen.frame
            return CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.first { $0.contains(center) } ?? screens.first ?? frame
    }

    private static func value<T>(of element: AXUIElement, _ attribute: String, type: AXValueType) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AXValueGetValue(raw as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }

    private static func bool(of element: AXUIElement, _ attribute: CFString) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &raw) == .success else { return false }
        return (raw as? Bool) ?? false
    }
}
