import SwiftUI

/// Every tunable value for the look and feel lives here.
///
/// Sizes are fractions of the window height, so the UI scales the same on a
/// laptop screen and on a TV across the room.
enum Theme {
    // Tile row
    static let tileSize: CGFloat = 0.30          // tile edge, × height
    static let tileSpacing: CGFloat = 0.03       // gap between tiles, × height
    static let tileCornerRadius: CGFloat = 0.14  // × tile edge
    static let rowCenterY: CGFloat = 0.50        // vertical centre of the row, × height
    static let sideMargin: CGFloat = 0.10        // left edge of the first tile, × height

    // Focus
    static let focusScale: CGFloat = 1.08
    static let focusGlassPadding: CGFloat = 0.016 // glass rim around the focused tile, × height
    static let focusGlassTint: Double = 0.25      // how much of the game's colour tints the glass rim

    // Title of the focused game
    static let titleSize: CGFloat = 0.040         // × height
    static let titleGap: CGFloat = 0.075          // from tile top to title baseline area, × height

    // Hint bar
    static let hintSize: CGFloat = 0.022          // × height
    static let hintMargin: CGFloat = 0.05         // from the screen corner, × height

    // Backdrop
    static let backdropDim: Double = 0.35         // black overlay on the colour mesh

    // Motion
    static let focusSpring = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let backdropAnimation = Animation.easeInOut(duration: 0.6)
}
