import CoreGraphics
import Testing
@testable import TenFootCore

struct FullscreenTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func window(standard: Bool = true, minimized: Bool = false, fullScreen: Bool = false,
                        canFullScreen: Bool = true, frame: CGRect = CGRect(x: 200, y: 150, width: 1280, height: 720)) -> GameWindow {
        GameWindow(isStandard: standard, isMinimized: minimized, isFullScreen: fullScreen,
                   canFullScreen: canFullScreen, frame: frame, screen: screen)
    }

    @Test func windowedGameGoesNativeFullScreen() {
        #expect(Fullscreen.action(for: window()) == .nativeFullScreen)
    }

    @Test func windowWithoutFullScreenFillsTheScreen() {
        #expect(Fullscreen.action(for: window(canFullScreen: false)) == .fillScreen)
    }

    @Test func alreadyFullScreenIsLeftAlone() {
        #expect(Fullscreen.action(for: window(fullScreen: true)) == .leave)
        // Its own full screen mode: a window covering the screen (within a point or two).
        #expect(Fullscreen.action(for: window(frame: CGRect(x: 0, y: 1, width: 1920, height: 1079))) == .leave)
    }

    @Test func dialogsAndMinimisedWindowsAreLeftAlone() {
        #expect(Fullscreen.action(for: window(standard: false)) == .leave)
        #expect(Fullscreen.action(for: window(minimized: true)) == .leave)
    }

    @Test func screenOffsetIsRespected() {
        // A second screen to the right: covering that screen counts, not the first one.
        let second = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
        let covering = GameWindow(isStandard: true, isMinimized: false, isFullScreen: false, canFullScreen: true,
                                  frame: second, screen: second)
        #expect(Fullscreen.action(for: covering) == .leave)
    }
}
