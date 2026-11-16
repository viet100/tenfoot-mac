import SwiftUI
import TenFootCore

@MainActor
final class HomeState: ObservableObject {
    let games: [SampleGame]
    @Published private(set) var row: RowFocus

    init(games: [SampleGame] = SampleGame.all) {
        self.games = games
        self.row = RowFocus(count: games.count)
    }

    var focusedGame: SampleGame? {
        games.indices.contains(row.index) ? games[row.index] : nil
    }

    // Animations are attached in HomeView, so the selector and the carousel
    // can each move with their own easing.
    func move(by delta: Int) {
        row.move(by: delta)
    }

    func select(_ index: Int) {
        row.select(index)
    }

    func setVisibleCount(_ count: Int) {
        guard count != row.visibleCount else { return }
        row.setVisibleCount(count)
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
