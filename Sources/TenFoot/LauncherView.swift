import Observation
import SwiftUI

/// Sizes derived from the window, shared by every screen.
struct Layout {
    let size: CGSize
    var unit: CGFloat { size.height }
    var tile: CGFloat { unit * Theme.tileSize }
    var rim: CGFloat { unit * Theme.selectorRim }
    var cell: CGFloat { tile + rim * 2 }               // a tile plus the selector rim around it
    var spacing: CGFloat { unit * Theme.tileSpacing }  // gap between tiles
    var step: CGFloat { cell + spacing }               // distance from one tile to the next
    var margin: CGFloat { unit * Theme.sideMargin }
    var visibleCount: Int { max(1, Int((size.width - margin * 2 - tile) / step) + 1) }
}

/// The whole launcher: backdrop, the current screen, status bar and hints.
struct LauncherView: View {
    @ObservedObject var state: LauncherState
    let status: StatusModel
    let controllers: ControllerManager

    var body: some View {
        GeometryReader { geo in
            let layout = Layout(size: geo.size)

            ZStack {
                Backdrop(game: state.backdropGame)

                switch state.screen {
                case .home:
                    HomeScreen(state: state, layout: layout)
                        .transition(.opacity)
                case .settings:
                    SettingsScreen(state: state, layout: layout)
                        .transition(.opacity)
                }

                StatusBar(model: status, unit: layout.unit)
                    .padding(layout.unit * Theme.statusMargin)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)

                // The dim and the panel fade separately; the panel also eases in from a
                // little smaller and shrinks a little as it goes. The fixed layer order keeps
                // them in front while they fade out (otherwise they drop behind the backdrop
                // and vanish at once).
                if let prompt = state.closePrompt {
                    Color.black.opacity(Theme.popupDim)
                        .ignoresSafeArea()
                        .onTapGesture { state.choose(.cancel) }
                        .transition(.opacity)
                        .zIndex(10)
                    ClosePromptView(state: state, prompt: prompt, unit: layout.unit)
                        .transition(.scale(scale: Theme.popupScale).combined(with: .opacity))
                        .zIndex(11)
                }

                // A game's options menu, shown the same way as the close prompt.
                if let menu = state.optionsMenu {
                    Color.black.opacity(Theme.popupDim)
                        .ignoresSafeArea()
                        .onTapGesture { state.pick(.cancel) }
                        .transition(.opacity)
                        .zIndex(10)
                    OptionsMenuView(state: state, menu: menu, unit: layout.unit)
                        .transition(.scale(scale: Theme.popupScale).combined(with: .opacity))
                        .zIndex(11)
                }

                // The power menu (hold Home), then "Restart your Mac?" and the like.
                // One dim stays up while the menu hands over to the question.
                if state.powerMenuOpen || state.powerConfirm != nil {
                    Color.black.opacity(Theme.popupDim)
                        .ignoresSafeArea()
                        .onTapGesture {
                            if state.powerConfirm != nil { state.confirmPower(false) } else { state.pickPower(.cancel) }
                        }
                        .transition(.opacity)
                        .zIndex(10)
                }
                if state.powerMenuOpen {
                    PowerMenuView(state: state, unit: layout.unit)
                        .transition(.scale(scale: Theme.popupScale).combined(with: .opacity))
                        .zIndex(11)
                }
                if let item = state.powerConfirm {
                    PowerConfirmView(state: state, item: item, unit: layout.unit)
                        .transition(.scale(scale: Theme.popupScale).combined(with: .opacity))
                        .zIndex(11)
                }

                // The message ("Starting…", or an error) sits on its own line above the hints.
                VStack(alignment: .trailing, spacing: layout.unit * Theme.messageGap) {
                    if let message = state.message {
                        MessageBanner(text: message, unit: layout.unit)
                            .transition(.opacity)
                    }
                    HintBar(state: state, controllers: controllers, unit: layout.unit)
                }
                .padding(layout.unit * Theme.hintMargin)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
                .zIndex(12) // above the close prompt's dim, as the hints belong to the prompt too
            }
            .onAppear { state.setVisibleCount(layout.visibleCount) }
            .onChange(of: geo.size) { _, size in state.setVisibleCount(Layout(size: size).visibleCount) }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Home

private struct HomeScreen: View {
    @ObservedObject var state: LauncherState
    let layout: Layout
    @State private var dragging = DragTracker()

    static let space = "home"

    var body: some View {
        let unit = layout.unit
        ZStack {
            if state.games.isEmpty {
                EmptyLibrary(unit: unit)
                    .position(x: layout.size.width / 2, y: unit * Theme.rowCenterY)
            } else {
                TileRow(state: state, layout: layout)
                    .offset(x: layout.rowOrigin(scrollIndex: state.scrollIndex),
                            y: unit * Theme.rowCenterY - layout.cell / 2)
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            }

            // Presses on the row: an invisible strip across the screen that never moves, so
            // where you press is always where the tiles are drawn. One gesture handles both
            // clicking and dragging: let go without moving and it's a click; move a few points
            // and the game under the pointer is picked up.
            if !state.games.isEmpty {
                Color.clear
                    .frame(width: layout.size.width, height: layout.cell)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { pointerMoved($0) }
                            .onEnded { pointerReleased($0) }
                    )
                    .position(x: layout.size.width / 2, y: unit * Theme.rowCenterY)
            }

            SystemRow(state: state, unit: unit)
                .position(x: layout.size.width / 2, y: unit * Theme.systemRowCenterY)

            DragGhost(state: state, dragging: dragging, layout: layout)
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .coordinateSpace(.named(Self.space))
    }

    /// The game whose tile is under `point` (home-screen coordinates), if any.
    private func game(at point: CGPoint) -> Int? {
        layout.game(atX: point.x, scrollIndex: state.scrollIndex, count: state.games.count)
    }

    private func pointerMoved(_ value: DragGesture.Value) {
        if state.drag == nil {
            let distance = hypot(value.translation.width, value.translation.height)
            guard distance >= Theme.dragThreshold, let index = game(at: value.startLocation) else { return }
            dragChanged(index, value)
        } else {
            dragChanged(state.drag?.from ?? 0, value)
        }
    }

    private func pointerReleased(_ value: DragGesture.Value) {
        if state.drag != nil {
            drop()
        } else if hypot(value.translation.width, value.translation.height) < Theme.dragThreshold,
                  let index = game(at: value.startLocation) {
            state.click(game: index)
        }
    }

    /// The pointer moved while holding a game: pick it up the first time, then keep the
    /// copy under the pointer and the other games making room for it.
    private func dragChanged(_ index: Int, _ value: DragGesture.Value) {
        if state.drag == nil {
            if dragging.landing { state.trace?("drag on game \(index) ignored: still landing") }
            guard !dragging.landing, state.beginDrag(index) else { return }
            let center = layout.tileCenter(slot: index, scrollIndex: state.scrollIndex)
            dragging.grabOffset = CGSize(width: center.x - value.startLocation.x,
                                         height: center.y - value.startLocation.y)
            dragging.lifted = false
            dragging.location = center
            withAnimation(Theme.liftAnimation) { dragging.lifted = true }
        }
        guard !dragging.landing else { return }

        let ghost = CGPoint(x: value.location.x + dragging.grabOffset.width,
                            y: value.location.y + dragging.grabOffset.height)
        dragging.location = ghost

        let edge = layout.unit * Theme.dragEdgeZone
        if value.location.x < edge {
            state.setDragEdge(-1)
        } else if value.location.x > layout.size.width - edge {
            state.setDragEdge(1)
        } else {
            state.setDragEdge(0)
            state.moveDrag(to: layout.slot(atX: ghost.x, scrollIndex: state.scrollIndex))
        }
    }

    /// Let go: the copy glides into its slot, then the new order is saved.
    private func drop() {
        guard let drag = state.drag, !dragging.landing else { return }
        state.setDragEdge(0)
        dragging.landing = true
        let target = layout.tileCenter(slot: drag.target, scrollIndex: state.scrollIndex)
        withAnimation(Theme.dropAnimation) {
            dragging.location = target
            dragging.lifted = false
        } completion: {
            state.endDrag()
            dragging.location = nil
            dragging.landing = false
        }
    }
}

extension Layout {
    /// Left edge of the row's first cell, with the row scrolled to `scrollIndex`.
    func rowOrigin(scrollIndex: Int) -> CGFloat {
        margin - rim - CGFloat(scrollIndex) * step
    }

    /// Centre of the tile in `slot`, in home-screen coordinates.
    func tileCenter(slot: Int, scrollIndex: Int) -> CGPoint {
        CGPoint(x: rowOrigin(scrollIndex: scrollIndex) + CGFloat(slot) * step + cell / 2,
                y: unit * Theme.rowCenterY)
    }

    /// The game whose tile covers `x` across the screen, if any (not the gaps between tiles).
    func game(atX x: CGFloat, scrollIndex: Int, count: Int) -> Int? {
        let intoRow = x - rowOrigin(scrollIndex: scrollIndex)
        let slot = Int((intoRow / step).rounded(.down))
        let intoCell = intoRow - CGFloat(slot) * step
        guard (0..<count).contains(slot), intoCell >= rim, intoCell <= rim + tile else { return nil }
        return slot
    }

    /// The slot nearest to a point `x` across the screen.
    func slot(atX x: CGFloat, scrollIndex: Int) -> Int {
        Int(((x - rowOrigin(scrollIndex: scrollIndex) - cell / 2) / step).rounded())
    }
}

/// Where the see-through copy of a dragged game is. Kept out of `LauncherState`
/// so following the pointer only redraws the copy, not the whole screen.
@MainActor @Observable
final class DragTracker {
    var location: CGPoint?   // centre of the copy; nil when nothing is dragged
    var grabOffset = CGSize.zero
    var lifted = false
    var landing = false      // let go: gliding into its slot
}

/// The see-through copy of the dragged game that follows the pointer.
private struct DragGhost: View {
    @ObservedObject var state: LauncherState
    let dragging: DragTracker
    let layout: Layout

    var body: some View {
        if let location = dragging.location,
           let drag = state.drag,
           let game = state.games.first(where: { $0.id == drag.id }) {
            TileView(game: game, tile: layout.tile, unit: layout.unit, running: game.id == state.runningGameID)
                .scaleEffect(dragging.lifted ? Theme.dragLiftScale : 1)
                .opacity(dragging.lifted ? Theme.dragGhostOpacity : 1)
                .shadow(color: .black.opacity(dragging.lifted ? 0.45 : 0),
                        radius: layout.unit * 0.03, y: layout.unit * 0.015)
                .position(location)
                .allowsHitTesting(false)
        }
    }
}

/// The tiles, the glass selector and the title, laid out in one coordinate space.
///
/// Every tile and the selector are placed with the same formula
/// (cell `i` starts at `i × step`), so the selector is always exactly centred
/// on the focused tile, and it moves with the row when the carousel scrolls.
private struct TileRow: View {
    @ObservedObject var state: LauncherState
    let layout: Layout

    var body: some View {
        let unit = layout.unit
        let rim = layout.rim
        let radius = layout.tile * Theme.tileCornerRadius
        let selectorShape = RoundedRectangle(cornerRadius: radius + rim, style: .continuous)
        let tint = (state.backdropGame?.primary ?? .white).opacity(Theme.selectorTint)
        let focusX = CGFloat(state.selectorIndex) * layout.step
        let rowFocused = state.area == .games || state.drag != nil

        ZStack(alignment: .topLeading) {
            ForEach(Array(state.games.enumerated()), id: \.element.id) { index, game in
                let launching = state.launchingGameID == game.id
                // The game under the selector is magnified a little, as if seen through a lens.
                let magnified = rowFocused && state.slot(of: index) == state.selectorIndex && state.drag?.id != game.id
                TileView(game: game, tile: layout.tile, unit: unit, running: game.id == state.runningGameID,
                         launching: launching)
                    // A quick squeeze and spring back when the game is pressed.
                    .keyframeAnimator(initialValue: CGFloat(1),
                                      trigger: state.presses[game.id] ?? 0) { view, scale in
                        view.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack(\.self) {
                            CubicKeyframe(Theme.pressScale, duration: Theme.pressDownDuration)
                            SpringKeyframe(1, duration: Theme.pressReleaseDuration,
                                           spring: .bouncy(duration: Theme.pressReleaseDuration))
                        }
                    }
                    .scaleEffect(magnified ? Theme.selectorMagnify : 1)
                    // While a game starts, the others step back.
                    .opacity(state.launchingGameID != nil && !launching ? Theme.launchOthersOpacity : 1)
                    // The dragged game's own tile waits, invisible, in the slot it will drop into.
                    .opacity(state.drag?.id == game.id ? 0 : 1)
                    .frame(width: layout.cell, height: layout.cell)
                    .contentShape(selectorShape.inset(by: rim)) // the tile is what you can click, not the rim
                    .offset(x: CGFloat(state.slot(of: index)) * layout.step)
            }

            // The selector: one piece of lightly frosted glass that slides over the tiles,
            // like a magnifying lens over the focused game.
            Color.clear
                .frame(width: layout.cell, height: layout.cell)
                .glassEffect(Glass.clear.tint(tint), in: selectorShape)
                .offset(x: focusX)
                .opacity(rowFocused ? 1 : 0)
                .allowsHitTesting(false)

            // The title travels with the selector.
            BlurText(state.focusedGame?.title ?? "")
                .font(.system(size: unit * Theme.titleSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: unit * 0.008)
                .lineLimit(1)
                .fixedSize()
                .offset(x: focusX + rim, y: rim - unit * Theme.titleGap)
                .allowsHitTesting(false)
        }
        .frame(width: CGFloat(max(state.games.count - 1, 0)) * layout.step + layout.cell,
               height: layout.cell, alignment: .topLeading)
    }
}

private struct TileView: View {
    let game: Game
    let tile: CGFloat
    let unit: CGFloat
    let running: Bool
    var launching = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tile * Theme.tileCornerRadius, style: .continuous)
        // macOS icons leave a transparent margin around their artwork; enlarge the
        // image so the artwork itself fills the tile.
        let imageSize = tile / Theme.iconArtFraction

        Image(nsImage: game.icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: imageSize, height: imageSize)
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                if launching {
                    ZStack {
                        shape.fill(.black.opacity(Theme.launchDarken))
                        LaunchSpinner(unit: unit)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if running && !launching { RunningBadge(unit: unit).padding(tile * 0.06) }
            }
    }
}

/// A turning ring on glass, over a game that is starting.
private struct LaunchSpinner: View {
    let unit: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Theme.spinnerPeriod) / Theme.spinnerPeriod
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(.white, style: StrokeStyle(lineWidth: unit * 0.007, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
        }
        .frame(width: unit * 0.055, height: unit * 0.055)
        .padding(unit * 0.024)
        .glassEffect(.clear, in: Circle())
        .allowsHitTesting(false)
    }
}

/// Marks the game that is running in the background.
private struct RunningBadge: View {
    let unit: CGFloat

    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: unit * 0.022, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: unit * 0.05, height: unit * 0.05)
            .glassEffect(.regular.tint(.black.opacity(0.3)), in: Circle())
            .allowsHitTesting(false)
    }
}

private struct EmptyLibrary: View {
    let unit: CGFloat

    var body: some View {
        VStack(spacing: unit * 0.018) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: unit * 0.06, weight: .semibold))
            Text("No apps yet")
                .font(.system(size: unit * 0.04, weight: .semibold))
            Text("Open Settings below and choose Add App to put your games here.")
                .font(.system(size: unit * 0.024))
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
    }
}

/// Round glass buttons under the game row (Settings, and more later).
private struct SystemRow: View {
    @ObservedObject var state: LauncherState
    let unit: CGFloat

    var body: some View {
        let size = unit * Theme.systemButtonSize
        HStack(spacing: unit * 0.04) {
            ForEach(Array(LauncherState.SystemButton.allCases.enumerated()), id: \.element) { index, button in
                let focused = state.area == .system && state.systemIndex == index
                VStack(spacing: unit * 0.016) {
                    Image(systemName: button.symbol)
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                        .glassEffect(focused ? Glass.regular.tint(.white.opacity(Theme.focusedGlassTint)) : .regular,
                                     in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(focused ? 0.9 : 0), lineWidth: unit * 0.003))
                    Text(button.title)
                        .font(.system(size: unit * Theme.systemLabelSize, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(focused ? 1 : 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { state.click(systemButton: index) }
            }
        }
    }
}

// MARK: - Settings

private struct SettingsScreen: View {
    @ObservedObject var state: LauncherState
    let layout: Layout

    var body: some View {
        let unit = layout.unit
        VStack(alignment: .leading, spacing: unit * 0.04) {
            Text("Settings")
                .font(.system(size: unit * Theme.screenTitleSize, weight: .bold))
                .foregroundStyle(.white)

            VStack(spacing: unit * 0.014) {
                ForEach(Array(LauncherState.SettingsItem.allCases.enumerated()), id: \.element) { index, item in
                    SettingsRow(item: item, value: value(of: item), focused: index == state.settingsIndex,
                                pressed: item == .addApp && state.addingApps, unit: unit)
                        .contentShape(Rectangle())
                        .onTapGesture { state.click(settingsItem: index) }
                }
            }
            .frame(width: unit * Theme.settingsListWidth)
        }
        .padding(.leading, layout.margin)
        .padding(.top, unit * Theme.screenTitleTop)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

private extension SettingsScreen {
    /// The current choice, shown at the right of a row (nil for actions like Add App).
    func value(of item: LauncherState.SettingsItem) -> String? {
        switch item {
        case .addApp: nil
        case .iconStyle:
            switch state.preferences.iconStyle {
            case .matchMacOS: "Match macOS"
            case .fullColour: "Full Colour"
            }
        }
    }
}

private struct SettingsRow: View {
    let item: LauncherState.SettingsItem
    let value: String?
    let focused: Bool
    let pressed: Bool // held down while its file picker is open
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.03, style: .continuous)
        HStack(spacing: unit * 0.024) {
            Image(systemName: item.symbol)
                .font(.system(size: unit * 0.034, weight: .semibold)) // same weight as the row's title
                .frame(width: unit * 0.05)
            VStack(alignment: .leading, spacing: unit * 0.004) {
                Text(item.title)
                    .font(.system(size: unit * Theme.settingsRowSize, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: unit * Theme.settingsDetailSize))
                    .opacity(0.7)
            }
            Spacer(minLength: unit * 0.02)
            if let value {
                BlurText(value)
                    .font(.system(size: unit * Theme.settingsRowSize, weight: .medium))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, unit * 0.03)
        .padding(.vertical, unit * 0.022)
        .glassEffect(focused ? Glass.regular.tint(.white.opacity(Theme.focusedGlassTint)) : .regular, in: shape)
        .overlay(shape.fill(.black.opacity(pressed ? Theme.rowPressDarken : 0)))
        .overlay(shape.strokeBorder(.white.opacity(focused ? 0.85 : 0), lineWidth: unit * 0.003))
        .scaleEffect(pressed ? Theme.rowPressScale : 1)
    }
}

// MARK: - Shared

/// Text that eases from one string to the next: the old text blurs and fades out while
/// the new text blurs in, in the same place.
struct BlurText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        ZStack {
            Text(text)
                .id(text)
                .transition(.blurReplace)
        }
        .animation(Theme.textAnimation, value: text)
    }
}

/// A drifting colour field taken from the focused game, for the glass to refract.
private struct Backdrop: View {
    let game: Game?

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
    ]

    var body: some View {
        let a = game?.primary ?? Color(red: 0.2, green: 0.3, blue: 0.5)
        let b = game?.secondary ?? Color(red: 0.25, green: 0.15, blue: 0.4)
        let colors: [Color] = [
            a, a.mix(with: b, by: 0.5), b,
            a.mix(with: .black, by: 0.45), b.mix(with: .black, by: 0.5), a.mix(with: .black, by: 0.65),
            .black, b.mix(with: .black, by: 0.75), .black,
        ]
        MeshGradient(width: 3, height: 3, points: Self.points, colors: colors)
            .overlay(Color.black.opacity(Theme.backdropDim))
            .animation(Theme.backdropAnimation, value: game?.id)
            .ignoresSafeArea()
    }
}

/// "Close <game>?" over a dimmed screen. Left/right picks a button, A presses it, B cancels.
private struct ClosePromptView: View {
    @ObservedObject var state: LauncherState
    let prompt: LauncherState.ClosePrompt
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.04, style: .continuous)
        VStack(spacing: unit * 0.035) {
            VStack(spacing: unit * 0.014) {
                Text("Close \(prompt.running.title)?")
                    .font(.system(size: unit * Theme.screenTitleSize * 0.8, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.system(size: unit * Theme.settingsDetailSize * 1.2))
                    .multilineTextAlignment(.center)
                    .opacity(0.8)
            }
            HStack(spacing: unit * 0.02) {
                button("Cancel", focused: state.promptFocus == .cancel) { state.choose(.cancel) }
                button("Close", focused: state.promptFocus == .close) { state.choose(.close) }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(Theme.popupTextShadow), radius: unit * 0.006)
        .padding(unit * 0.05)
        .frame(width: unit * 0.9)
        .glassEffect(Theme.popupGlass, in: shape)
    }

    private var detail: String {
        if let next = prompt.next {
            "\(next.title) will start once it has closed. Unsaved progress will be lost."
        } else {
            "Unsaved progress will be lost."
        }
    }

    private func button(_ title: String, focused: Bool, action: @escaping () -> Void) -> some View {
        let shape = Capsule()
        return Text(title)
            .font(.system(size: unit * Theme.settingsRowSize, weight: .semibold))
            .frame(width: unit * 0.3)
            .padding(.vertical, unit * 0.018)
            .glassEffect(focused ? Glass.clear.tint(.white.opacity(Theme.focusedGlassTint))
                                 : Glass.clear.tint(.black.opacity(Theme.popupTint)), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(focused ? 0.85 : 0), lineWidth: unit * 0.003))
            .contentShape(shape)
            .onTapGesture(perform: action)
    }
}

/// A game's options: its name, then Remove from TenFoot and Cancel.
private struct OptionsMenuView: View {
    @ObservedObject var state: LauncherState
    let menu: LauncherState.OptionsMenu
    let unit: CGFloat

    var body: some View {
        MenuPanel(title: menu.game.title, unit: unit, rows: LauncherState.OptionsItem.allCases.enumerated().map { index, item in
            MenuPanel.Row(id: index, title: item.title, symbol: item.symbol,
                          note: state.isAvailable(item) ? nil : "Close it first",
                          focused: state.optionsIndex == index) { state.pick(item) }
        })
    }
}

/// The power menu (hold Home): Quit TenFoot, Sleep, Restart, Shut Down, Cancel.
private struct PowerMenuView: View {
    @ObservedObject var state: LauncherState
    let unit: CGFloat

    var body: some View {
        MenuPanel(title: "TenFoot", unit: unit, rows: LauncherState.PowerItem.allCases.enumerated().map { index, item in
            MenuPanel.Row(id: index, title: item.title, symbol: item.symbol, note: nil,
                          focused: state.powerIndex == index) { state.pickPower(item) }
        })
    }
}

/// "Restart your Mac?": the action, then Cancel (focused first).
private struct PowerConfirmView: View {
    @ObservedObject var state: LauncherState
    let item: LauncherState.PowerItem
    let unit: CGFloat

    var body: some View {
        MenuPanel(title: item.question, unit: unit, rows: [
            MenuPanel.Row(id: 0, title: item.title, symbol: item.symbol, note: nil,
                          focused: state.powerConfirmIndex == 0) { state.confirmPower(true) },
            MenuPanel.Row(id: 1, title: "Cancel", symbol: "xmark", note: nil,
                          focused: state.powerConfirmIndex == 1) { state.confirmPower(false) },
        ])
    }
}

/// A pop-up list: a title, then one row per action. Up/down moves, A picks, B closes.
/// A row with a `note` can't be picked right now and is dimmed, with the note saying why.
private struct MenuPanel: View {
    struct Row: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        let note: String?
        let focused: Bool
        let pick: () -> Void
    }

    let title: String
    let unit: CGFloat
    let rows: [Row]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.04, style: .continuous)
        VStack(alignment: .leading, spacing: unit * 0.03) {
            Text(title)
                .font(.system(size: unit * Theme.screenTitleSize * 0.8, weight: .bold))
                .lineLimit(1)
            VStack(spacing: unit * 0.014) {
                ForEach(rows) { row($0) }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(Theme.popupTextShadow), radius: unit * 0.006)
        .padding(unit * 0.05)
        .frame(width: unit * 0.9)
        .glassEffect(Theme.popupGlass, in: shape)
    }

    private func row(_ row: Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.025, style: .continuous)
        return HStack(spacing: unit * 0.02) {
            Image(systemName: row.symbol)
                .font(.system(size: unit * 0.03, weight: .semibold)) // same weight as the row's title
                .frame(width: unit * 0.045)
            Text(row.title)
                .font(.system(size: unit * Theme.settingsRowSize, weight: .semibold))
            Spacer(minLength: unit * 0.02)
            if let note = row.note {
                Text(note)
                    .font(.system(size: unit * Theme.settingsDetailSize))
            }
        }
        .opacity(row.note == nil ? 1 : 0.5)
        .padding(.horizontal, unit * 0.025)
        .padding(.vertical, unit * 0.018)
        .glassEffect(row.focused ? Glass.clear.tint(.white.opacity(Theme.focusedGlassTint))
                                 : Glass.clear.tint(.black.opacity(Theme.popupTint)), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(row.focused ? 0.85 : 0), lineWidth: unit * 0.003))
        .contentShape(shape)
        .onTapGesture(perform: row.pick)
    }
}

/// "Starting…" or an error, on its own line above the hint bar.
private struct MessageBanner: View {
    let text: String
    let unit: CGFloat

    var body: some View {
        BlurText(text)
            .font(.system(size: unit * Theme.hintSize, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(2)
            .frame(maxWidth: unit * 0.9, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false) // as wide as the text (up to the maximum), not the full width
            .shadow(color: .black.opacity(Theme.popupTextShadow), radius: unit * 0.006)
            .padding(.horizontal, unit * 0.03)
            .padding(.vertical, unit * 0.016)
            .glassEffect(Theme.popupGlass, in: Capsule())
            .allowsHitTesting(false)
    }
}

private struct HintBar: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var controllers: ControllerManager
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * 0.035) {
            ForEach(Array(state.hints.enumerated()), id: \.offset) { _, hint in
                item(symbol: symbol(for: hint.0), label: hint.1)
                    .contentShape(Rectangle())
                    .onTapGesture { state.click(hint: hint.0) }
            }
            item(symbol: "command", label: "Q  Exit")
        }
        .font(.system(size: unit * Theme.hintSize, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, unit * 0.03)
        .padding(.vertical, unit * 0.016)
        .glassEffect(.regular, in: Capsule())
    }

    private func symbol(for kind: LauncherState.HintKind) -> String {
        switch kind {
        case .move: controllers.moveSymbol
        case .confirm: controllers.confirmSymbol
        case .back: controllers.backSymbol
        case .close: controllers.closeSymbol
        case .options: controllers.optionsSymbol
        }
    }

    private func item(symbol: String, label: String) -> some View {
        HStack(spacing: unit * 0.01) {
            Image(systemName: symbol)
            BlurText(label)
        }
    }
}
