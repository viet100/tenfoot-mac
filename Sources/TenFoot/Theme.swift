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
    static let selectorMagnify: CGFloat = 1.05   // the focused game grows this much under the selector's lens
    static let selectorStretchPerTile: Double = 0.02 // extra width per tile/second of speed (≈12% at the peak of one move)
    static let selectorMaxStretch: Double = 0.30     // never more than 30% longer
    static let selectorSquash: Double = 0.4          // height shrinks 40% as much as the width grows
    static let lensSheen: Double = 0.22          // white frost at the lens's top-left corner

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

    // Pop-ups (the close prompt and the "Starting…" message)
    static let popupDim: Double = 0.35           // black over the screen behind the close prompt
    static let popupTint: Double = 0.30          // black tint in the pop-up glass, so white text reads clearly
    /// Frosted glass for pop-up panels: regular glass blurs what's behind it, and the dark
    /// tint keeps it from looking milky so white text stays easy to read.
    static var popupGlass: Glass { Glass.regular.tint(.black.opacity(popupTint)) }
    static let popupTextShadow: Double = 0.35    // keeps text readable on the glass
    static let popupScale: CGFloat = 0.92        // the close prompt grows from this size as it fades in

    // Hint bar
    static let hintSize: CGFloat = 0.022         // × height
    static let hintMargin: CGFloat = 0.05        // from the screen corner, × height
    static let messageGap: CGFloat = 0.015       // between the "Starting…" message and the hints, × height

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
    static let trackpadStep: CGFloat = 120  // points of trackpad swipe per move
    static let homeHoldTime: Double = 0.8   // seconds Home is held to open the power menu
    static let releaseWait: Double = 3      // longest wait for buttons to be let go before resuming or starting a game

    // Dragging a game to a new place with the mouse
    static let dragThreshold: CGFloat = 6          // points the pointer moves before a press becomes a drag
    static let dragLiftScale: CGFloat = 1.06       // the copy under the pointer is a little bigger…
    static let dragGhostOpacity: Double = 0.75     // …and a little see-through
    static let dragEdgeZone: CGFloat = 0.10        // pointer this close to the screen edge scrolls the row, × height
    static let dragScrollInterval: Double = 0.35   // seconds per tile while scrolling at the edge

    // Starting a game
    static let pressScale: CGFloat = 0.90          // a tile shrinks to this when pressed, then springs back
    static let rowPressInset: CGFloat = 0.008      // a Settings row draws in this much while its picker is open, × height
    static let rowPressDarken: Double = 0.25       // black over a pressed Settings row
    static let pickerDelay: Double = 0.15          // seconds the press shows before the file picker opens
    static let launchOthersOpacity: Double = 0.35  // the other tiles fade back while a game starts
    static let launchDarken: Double = 0.30         // black over the starting game's tile, behind the spinner
    static let spinnerPeriod: Double = 0.9         // seconds per turn of the spinner
    static let launchFeedbackTimeout: Double = 60  // the spinner gives up after this many seconds

    // Games
    static let closeTimeout: Double = 10    // seconds a game gets to quit before it's stopped outright
    static let fullscreenDelay: Double = 0.5 // seconds a new game window gets to finish opening before it's made full screen
    static let fullscreenAttempts = 4       // times to ask for macOS full screen before resizing the window instead
    static let accessibilityTimeout: Float = 0.25 // seconds to wait for a game to answer before trying again later

    // Backdrop
    static let backdropDim: Double = 0.30        // black overlay on the colour mesh
    static let backdropBottomDarken: Double = 0.40 // the bottom of the mesh is this much darker (not black)

    // Motion. Everything moves on the same smooth curve at one of three speeds, and
    // presses spring back with the same bounce. `motionScale` slows everything down
    // (used to record the CI animation GIF).
    static var motionScale: Double = 1
    static var quick: Double { 0.18 * motionScale }     // small, direct moves: scrolling, picking up
    static var standard: Double { 0.30 * motionScale }  // focus, pop-ups, screens, text, tiles settling
    static var slow: Double { 0.60 * motionScale }      // the backdrop's colours

    static var selectorAnimation: Animation { .smooth(duration: standard) }
    static var carouselAnimation: Animation { .smooth(duration: quick) }
    static var popupAnimation: Animation { .smooth(duration: standard) }
    static var screenAnimation: Animation { .smooth(duration: standard) }
    static var textAnimation: Animation { .smooth(duration: standard) }   // old text blurs out, new text blurs in
    static var backdropAnimation: Animation { .smooth(duration: slow) }
    static var reorderAnimation: Animation { .smooth(duration: standard) } // tiles making room
    static var liftAnimation: Animation { .smooth(duration: quick) }       // picking a game up
    static var dropAnimation: Animation { .smooth(duration: standard) }    // settling into its slot
    static var dragScrollAnimation: Animation { .linear(duration: dragScrollInterval * motionScale) }

    // Pressing something: it dips quickly, then springs back.
    static var pressDownDuration: Double { 0.08 * motionScale }
    static var pressReleaseDuration: Double { 0.45 * motionScale }
    static var pressAnimation: Animation { .smooth(duration: pressDownDuration) }
    static var releaseAnimation: Animation { .bouncy(duration: pressReleaseDuration) }
}
