import SwiftUI
import TenFootCore

@MainActor
final class HomeState: ObservableObject {
    let games: [SampleGame]
    private var row: RowFocus

    /// Drives the selector and the title.
    @Published private(set) var focusIndex = 0
    /// Index of the first visible tile; drives the carousel offset.
    @Published private(set) var scrollIndex = 0

    init(games: [SampleGame] = SampleGame.all) {
        self.games = games
        self.row = RowFocus(count: games.count)
    }

    var focusedGame: SampleGame? {
        games.indices.contains(focusIndex) ? games[focusIndex] : nil
    }

    func move(by delta: Int) {
        var next = row
        guard next.move(by: delta) else { return }
        apply(next)
    }

    func select(_ index: Int) {
        var next = row
        guard next.select(index) else { return }
        apply(next)
    }

    func setVisibleCount(_ count: Int) {
        guard count != row.visibleCount else { return }
        row.setVisibleCount(count)
        scrollIndex = row.firstVisible
    }

    /// The carousel and the selector each animate in their own transaction,
    /// so each gets its own easing.
    private func apply(_ next: RowFocus) {
        row = next
        if next.firstVisible != scrollIndex {
            withAnimation(Theme.carouselAnimation) { scrollIndex = next.firstVisible }
        }
        withAnimation(Theme.selectorAnimation) { focusIndex = next.index }
    }
}

/// Placeholder library for Step 1; real games are discovered in a later step.
struct SampleGame: Identifiable, Equatable {
    let id: Int
    let title: String
    let symbol: String
    let primary: Color
    let secondary: Color

    static let all: [SampleGame] = [
        SampleGame(id: 0, title: "Skyward Drift", symbol: "airplane", primary: .cyan, secondary: .indigo),
        SampleGame(id: 1, title: "Ember Hollow", symbol: "flame.fill", primary: .orange, secondary: .red),
        SampleGame(id: 2, title: "Tidebreaker", symbol: "water.waves", primary: .teal, secondary: .blue),
        SampleGame(id: 3, title: "Pixel Rally", symbol: "car.fill", primary: .yellow, secondary: .orange),
        SampleGame(id: 4, title: "Moonlit Grove", symbol: "moon.stars.fill", primary: .purple, secondary: .indigo),
        SampleGame(id: 5, title: "Iron Circuit", symbol: "bolt.fill", primary: .gray, secondary: .blue),
        SampleGame(id: 6, title: "Starlane Racers", symbol: "sparkles", primary: .pink, secondary: .purple),
        SampleGame(id: 7, title: "Frostpeak", symbol: "snowflake", primary: .mint, secondary: .cyan),
    ]
}
