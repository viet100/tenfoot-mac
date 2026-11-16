import SwiftUI

struct HomeView: View {
    @ObservedObject var state: HomeState

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.height
            let tile = unit * Theme.tileSize
            let rim = unit * Theme.focusGlassPadding
            let cell = tile + rim * 2
            let spacing = unit * Theme.tileSpacing
            let step = cell + spacing
            let margin = unit * Theme.sideMargin

            ZStack {
                Backdrop(game: state.focusedGame)

                GlassEffectContainer(spacing: spacing) {
                    HStack(spacing: spacing) {
                        ForEach(Array(state.games.enumerated()), id: \.element.id) { index, game in
                            TileView(
                                game: game,
                                tileSize: tile,
                                rim: rim,
                                unit: unit,
                                isFocused: index == state.row.index
                            )
                        }
                    }
                    .fixedSize()
                }
                .offset(x: margin - rim - CGFloat(state.row.firstVisible) * step,
                        y: unit * Theme.rowCenterY - cell / 2)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)

                HintBar(unit: unit)
                    .padding(unit * Theme.hintMargin)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
            }
            .onAppear { updateVisibleCount(width: geo.size.width, margin: margin, step: step, spacing: spacing) }
            .onChange(of: geo.size) { _, size in
                updateVisibleCount(width: size.width, margin: margin, step: step, spacing: spacing)
            }
        }
        .ignoresSafeArea()
    }

    private func updateVisibleCount(width: CGFloat, margin: CGFloat, step: CGFloat, spacing: CGFloat) {
        guard step > 0 else { return }
        let fits = Int((width - margin * 2 + spacing) / step)
        state.setVisibleCount(max(1, fits))
    }
}

private struct TileView: View {
    let game: SampleGame
    let tileSize: CGFloat
    let rim: CGFloat
    let unit: CGFloat
    let isFocused: Bool

    var body: some View {
        let radius = tileSize * Theme.tileCornerRadius
        let tileShape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let rimShape = RoundedRectangle(cornerRadius: radius + rim, style: .continuous)

        GameArt(game: game, size: tileSize)
            .clipShape(tileShape)
            .overlay(tileShape.strokeBorder(.white.opacity(isFocused ? 0.45 : 0.12), lineWidth: max(1, unit * 0.0015)))
            .shadow(color: .black.opacity(isFocused ? 0.45 : 0.25),
                    radius: isFocused ? unit * 0.03 : unit * 0.012,
                    y: isFocused ? unit * 0.015 : unit * 0.006)
            .padding(rim)
            // Glass sits behind the art (its content); unfocused tiles get no glass.
            .glassEffect(isFocused ? .regular.tint(game.primary.opacity(Theme.focusGlassTint)) : .identity,
                         in: rimShape)
            .scaleEffect(isFocused ? Theme.focusScale : 1)
            .overlay(alignment: .topLeading) {
                if isFocused {
                    Text(game.title)
                        .font(.system(size: unit * Theme.titleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: unit * 0.008)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, rim)
                        .offset(y: -unit * Theme.titleGap)
                        .transition(.opacity)
                }
            }
            .zIndex(isFocused ? 1 : 0)
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
        .font(.system(size: unit * Theme.hintSize, weight: .medium, design: .rounded))
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
