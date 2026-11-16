import CoreGraphics

/// What to do with a game's window so it fills the screen.
public enum FullscreenAction: Equatable, Sendable {
    case leave        // already full screen, or not a window to touch (dialogs, minimised windows)
    case nativeFullScreen // macOS full screen, like the green button
    case fillScreen   // resize it to cover the screen, for windows that can't go full screen
}

/// A game window as macOS's Accessibility reports it.
public struct GameWindow: Equatable, Sendable {
    public var isStandard: Bool      // an ordinary document/app window, not a dialog or panel
    public var isMinimized: Bool
    public var isFullScreen: Bool
    public var canFullScreen: Bool   // it accepts macOS full screen
    public var frame: CGRect
    public var screen: CGRect        // the whole screen it's on, in the same coordinates

    public init(isStandard: Bool, isMinimized: Bool, isFullScreen: Bool, canFullScreen: Bool,
                frame: CGRect, screen: CGRect) {
        self.isStandard = isStandard
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.canFullScreen = canFullScreen
        self.frame = frame
        self.screen = screen
    }
}

public enum Fullscreen {
    /// How close to the screen's edges a window must be to count as covering it.
    static let tolerance: CGFloat = 2

    /// Native full screen where the window supports it, otherwise fill the screen.
    /// Windows that already cover the screen (games with their own full screen mode) are left alone.
    public static func action(for window: GameWindow) -> FullscreenAction {
        guard window.isStandard, !window.isMinimized, !window.isFullScreen, !covers(window) else { return .leave }
        return window.canFullScreen ? .nativeFullScreen : .fillScreen
    }

    static func covers(_ window: GameWindow) -> Bool {
        window.frame.minX <= window.screen.minX + tolerance && window.frame.minY <= window.screen.minY + tolerance
            && window.frame.maxX >= window.screen.maxX - tolerance && window.frame.maxY >= window.screen.maxY - tolerance
    }
}
