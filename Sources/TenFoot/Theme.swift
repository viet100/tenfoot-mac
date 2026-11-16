import SwiftUI

/// Every tunable value for the look and feel lives here.
///
/// Sizes are fractions of the window height, so the UI scales the same on a
/// laptop screen and on a TV across the room.
enum Theme {
    // Tile row
    static let tileSize: CGFloat = 0.30          // tile edge, × height
    static let tileSpacing: CGFloat = 0.03       // gap between tiles, × height
    static let tileCornerRadius: CGFloat = 0.225 // × tile edge; matches the rounded shape of macOS app icons
    static let rowCenterY: CGFloat = 0.50        // vertical centre of the row, × height
    static let sideMargin: CGFloat = 0.10        // left edge of the first tile, × height

    static let iconArtFraction: CGFloat = 0.805  // macOS icons draw their artwork in the middle 80.5% of the image

    // Selector (the glass that slides behind the focused tile)
    static let selectorRim: CGFloat = 0.016      // glass visible around the tile, × height
    static let selectorTint: Double = 0.25       // how much of the game's colour tints the glass

    static let focusedGlassTint: Double = 0.22   // white tint on focused buttons and menu rows

    // Title of the focused game
    static let titleSize: CGFloat = 0.040        // × height
    static let titleGap: CGFloat = 0.075         // from tile top to title, × height

    // System buttons under the game row (Settings)
    static let systemButtonSize: CGFloat = 0.085 // × height
    static let systemRowCenterY: CGFloat = 0.82  // × height
    static let systemLabelSize: CGFloat = 0.020  // × height

    // Settings screen
    static let screenTitleSize: CGFloat = 0.050  // × height
    static let screenTitleTop: CGFloat = 0.12    // × height
    static let settingsListWidth: CGFloat = 0.90 // × height
    static let settingsRowSize: CGFloat = 0.030  // × height
    static let settingsDetailSize: CGFloat = 0.020 // × height

    // Hint bar
    static let hintSize: CGFloat = 0.022         // × height
    static let hintMargin: CGFloat = 0.05        // from the screen corner, × height

    // Status bar (battery, Wi‑Fi, time), top right
    static let statusSize: CGFloat = 0.022        // × height
    static let statusItemSpacing: CGFloat = 0.03  // between items, × height
    static let statusMargin: CGFloat = 0.05       // from the screen corner, × height
    static let statusRefreshInterval: TimeInterval = 10 // seconds between battery/Wi‑Fi readings

    // Controller input
    static let repeatDelay: Double = 0.40   // seconds a direction is held before it repeats
    static let repeatInterval: Double = 0.11 // seconds between repeats while held
    static let stickPress: Float = 0.5      // stick deflection that counts as a press
    static let stickRelease: Float = 0.3    // stick must return below this to release
    static let trackpadStep: CGFloat = 50   // points of trackpad swipe per move

    // Backdrop
    static let backdropDim: Double = 0.35        // black overlay on the colour mesh

    // Motion. `motionScale` slows everything down (used to record the CI animation GIF).
    static var motionScale: Double = 1
    static var selectorAnimation: Animation { .smooth(duration: 0.30 * motionScale) }
    static var carouselAnimation: Animation { .smooth(duration: 0.18 * motionScale) }
    static var screenAnimation: Animation { .smooth(duration: 0.35 * motionScale) }
    static var backdropAnimation: Animation { .easeInOut(duration: 0.60 * motionScale) }
}
