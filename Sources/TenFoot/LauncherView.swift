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

                HintBar(state: state, controllers: controllers, unit: layout.unit)
                    .padding(layout.unit * Theme.hintMargin)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
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

    var body: some View {
        let unit = layout.unit
        ZStack {
            if state.games.isEmpty {
                EmptyLibrary(unit: unit)
                    .position(x: layout.size.width / 2, y: unit * Theme.rowCenterY)
            } else {
                TileRow(state: state, layout: layout)
                    .offset(x: layout.margin - layout.rim - CGFloat(state.scrollIndex) * layout.step,
                            y: unit * Theme.rowCenterY - layout.cell / 2)
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
            }

            SystemRow(state: state, unit: unit)
                .position(x: layout.size.width / 2, y: unit * Theme.systemRowCenterY)
        }
        .frame(width: layout.size.width, height: layout.size.height)
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
        let focusX = CGFloat(state.focusIndex) * layout.step
        let rowFocused = state.area == .games

        ZStack(alignment: .topLeading) {
            // The selector: one piece of glass that slides behind the tiles.
            Color.clear
                .frame(width: layout.cell, height: layout.cell)
                .glassEffect(.regular.tint(tint), in: selectorShape)
                .offset(x: focusX)
                .opacity(rowFocused ? 1 : 0)

            ForEach(Array(state.games.enumerated()), id: \.element.id) { index, game in
                TileView(game: game, tile: layout.tile, unit: unit)
                    .frame(width: layout.cell, height: layout.cell)
                    .offset(x: CGFloat(index) * layout.step)
            }

            // The title travels with the selector.
            Text(state.focusedGame?.title ?? "")
                .font(.system(size: unit * Theme.titleSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: unit * 0.008)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.identity) // swap the name instantly; a cross-fade leaves the old name behind
                .offset(x: focusX + rim, y: rim - unit * Theme.titleGap)
        }
        .frame(width: CGFloat(max(state.games.count - 1, 0)) * layout.step + layout.cell,
               height: layout.cell, alignment: .topLeading)
    }
}

private struct TileView: View {
    let game: Game
    let tile: CGFloat
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tile * Theme.tileCornerRadius, style: .continuous)

        ZStack {
            LinearGradient(colors: [game.primary, game.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(nsImage: game.icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: tile * Theme.iconScale, height: tile * Theme.iconScale)
                .shadow(color: .black.opacity(0.3), radius: tile * 0.03, y: tile * 0.015)
        }
        .frame(width: tile, height: tile)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: max(1, unit * 0.0015)))
    }
}

private struct EmptyLibrary: View {
    let unit: CGFloat

    var body: some View {
        VStack(spacing: unit * 0.018) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: unit * 0.06, weight: .light))
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
                    SettingsRow(item: item, focused: index == state.settingsIndex, unit: unit)
                }
            }
            .frame(width: unit * Theme.settingsListWidth)
        }
        .padding(.leading, layout.margin)
        .padding(.top, unit * Theme.screenTitleTop)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }
}

private struct SettingsRow: View {
    let item: LauncherState.SettingsItem
    let focused: Bool
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.03, style: .continuous)
        HStack(spacing: unit * 0.024) {
            Image(systemName: item.symbol)
                .font(.system(size: unit * 0.034, weight: .medium))
                .frame(width: unit * 0.05)
            VStack(alignment: .leading, spacing: unit * 0.004) {
                Text(item.title)
                    .font(.system(size: unit * Theme.settingsRowSize, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: unit * Theme.settingsDetailSize))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, unit * 0.03)
        .padding(.vertical, unit * 0.022)
        .glassEffect(focused ? Glass.regular.tint(.white.opacity(Theme.focusedGlassTint)) : .regular, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(focused ? 0.85 : 0), lineWidth: unit * 0.003))
    }
}

// MARK: - Shared

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

private struct HintBar: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var controllers: ControllerManager
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * 0.035) {
            ForEach(Array(state.hints.enumerated()), id: \.offset) { _, hint in
                item(symbol: symbol(for: hint.0), label: hint.1)
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
        }
    }

    private func item(symbol: String, label: String) -> some View {
        HStack(spacing: unit * 0.01) {
            Image(systemName: symbol)
            Text(label)
        }
    }
}
