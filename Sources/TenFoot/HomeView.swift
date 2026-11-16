import SwiftUI

struct HomeView: View {
    @ObservedObject var state: HomeState
    let status: StatusModel

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.height
            let tile = unit * Theme.tileSize
            let rim = unit * Theme.selectorRim
            let cell = tile + rim * 2               // a tile plus the selector rim around it
            let spacing = unit * Theme.tileSpacing  // gap between tiles
            let step = cell + spacing               // distance from one tile to the next
            let margin = unit * Theme.sideMargin

            ZStack {
                Backdrop(game: state.focusedGame)

                TileRow(state: state, unit: unit, tile: tile, rim: rim, cell: cell, step: step)
                    .offset(x: margin - rim - CGFloat(state.scrollIndex) * step,
                            y: unit * Theme.rowCenterY - cell / 2)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)

                StatusBar(model: status, unit: unit)
                    .padding(unit * Theme.statusMargin)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)

                HintBar(unit: unit)
                    .padding(unit * Theme.hintMargin)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
            }
            .onAppear { updateVisibleCount(width: geo.size.width, margin: margin, tile: tile, step: step) }
            .onChange(of: geo.size) { _, size in
                updateVisibleCount(width: size.width, margin: margin, tile: tile, step: step)
            }
        }
        .ignoresSafeArea()
    }

    private func updateVisibleCount(width: CGFloat, margin: CGFloat, tile: CGFloat, step: CGFloat) {
        guard step > 0 else { return }
        let fits = Int((width - margin * 2 - tile) / step) + 1
        state.setVisibleCount(max(1, fits))
    }
}

/// The tiles, the glass selector and the title, laid out in one coordinate space.
///
/// Every tile and the selector are placed with the same formula
/// (cell `i` starts at `i × step`), so the selector is always exactly centred
/// on the focused tile, and it moves with the row when the carousel scrolls.
private struct TileRow: View {
    @ObservedObject var state: HomeState
    let unit: CGFloat
    let tile: CGFloat
    let rim: CGFloat
    let cell: CGFloat
    let step: CGFloat

    var body: some View {
        let radius = tile * Theme.tileCornerRadius
        let selectorShape = RoundedRectangle(cornerRadius: radius + rim, style: .continuous)
        let tint = (state.focusedGame?.primary ?? .white).opacity(Theme.selectorTint)
        let focusX = CGFloat(state.focusIndex) * step

        ZStack(alignment: .topLeading) {
            // The selector: one piece of glass that slides behind the tiles.
            Color.clear
                .frame(width: cell, height: cell)
                .glassEffect(.regular.tint(tint), in: selectorShape)
                .offset(x: focusX)

            ForEach(Array(state.games.enumerated()), id: \.element.id) { index, game in
                TileView(game: game, tile: tile, unit: unit)
                    .frame(width: cell, height: cell)
                    .offset(x: CGFloat(index) * step)
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
        .frame(width: CGFloat(max(state.games.count - 1, 0)) * step + cell, height: cell, alignment: .topLeading)
    }
}

private struct TileView: View {
    let game: SampleGame
    let tile: CGFloat
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tile * Theme.tileCornerRadius, style: .continuous)

        GameArt(game: game, size: tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: max(1, unit * 0.0015)))
    }
}

/// Placeholder art until real app icons / custom images arrive.
private struct GameArt: View {
    let game: SampleGame
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [game.primary, game.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: game.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.01)
        }
        .frame(width: size, height: size)
    }
}

/// A drifting colour field taken from the focused game, for the glass to refract.
private struct Backdrop: View {
    let game: SampleGame?

    private static let points: [SIMD2<Float>] = [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.55, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
    ]

    var body: some View {
        let a = game?.primary ?? .gray
        let b = game?.secondary ?? .black
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
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * 0.035) {
            hint(symbol: "arrow.left.arrow.right", label: "Move")
            hint(symbol: "command", label: "Q  Exit")
        }
        .font(.system(size: unit * Theme.hintSize, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, unit * 0.03)
        .padding(.vertical, unit * 0.016)
        .glassEffect(.regular, in: Capsule())
    }

    private func hint(symbol: String, label: String) -> some View {
        HStack(spacing: unit * 0.01) {
            Image(systemName: symbol)
            Text(label)
        }
    }
}
