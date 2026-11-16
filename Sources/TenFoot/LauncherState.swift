import SwiftUI
import TenFootCore

/// Everything the launcher shows and where focus is, driven by `InputAction`s.
@MainActor
final class LauncherState: ObservableObject {
    enum Screen { case home, settings }

    /// Which row of the home screen has focus.
    enum HomeArea { case games, system }

    /// Round buttons under the game row.
    enum SystemButton: CaseIterable, Identifiable {
        case settings
        var id: Self { self }
        var title: String { "Settings" }
        var symbol: String { "gearshape.fill" }
    }

    /// Items on the Settings screen. New menus get added here over time.
    enum SettingsItem: CaseIterable, Identifiable {
        case addApp
        case iconStyle
        var id: Self { self }
        var title: String {
            switch self {
            case .addApp: "Add App"
            case .iconStyle: "Icon Style"
            }
        }
        var detail: String {
            switch self {
            case .addApp: "Choose an app or program to put on the home screen"
            case .iconStyle: "Match the macOS icon style, or always show icons in full colour"
            }
        }
        var symbol: String {
            switch self {
            case .addApp: "plus.app"
            case .iconStyle: "paintpalette"
            }
        }
    }

    enum HintKind { case move, confirm, back }

    @Published private(set) var games: [Game]
    @Published private(set) var screen: Screen = .home
    @Published private(set) var area: HomeArea
    /// Focused game; drives the selector and the title.
    @Published private(set) var focusIndex = 0
    /// First visible game; drives the carousel offset.
    @Published private(set) var scrollIndex = 0
    @Published private(set) var systemIndex = 0
    @Published private(set) var settingsIndex = 0
    @Published private(set) var preferences: Preferences

    /// Called when the user picks Add App; the app delegate shows the file picker.
    var onAddApp: (() -> Void)?
    /// Called when the user starts a game.
    var onLaunch: ((Game) -> Void)?

    /// A short message at the bottom of the screen ("Starting…", or an error).
    @Published private(set) var message: String?
    private var messageClear: Task<Void, Never>?

    private var library: Library
    private let saves: Bool // false: don't save anything (CI snapshots)
    private var row: RowFocus

    init(library: Library, preferences: Preferences, saves: Bool) {
        self.library = library
        self.preferences = preferences
        self.saves = saves
        let games = library.entries.map { Game(entry: $0, iconStyle: preferences.iconStyle) }
        self.games = games
        self.row = RowFocus(count: games.count)
        self.area = games.isEmpty ? .system : .games
    }

    /// The game whose colours fill the backdrop (the last focused one, even while
    /// focus is on the buttons below).
    var backdropGame: Game? {
        games.indices.contains(focusIndex) ? games[focusIndex] : nil
    }

    /// The focused game, only while focus is on the game row.
    var focusedGame: Game? {
        area == .games ? backdropGame : nil
    }

    var hints: [(HintKind, String)] {
        switch (screen, area) {
        case (.home, .games): [(.move, "Move"), (.confirm, "Start")]
        case (.home, .system): [(.move, "Move"), (.confirm, "Open")]
        case (.settings, _): [(.move, "Move"), (.confirm, "Select"), (.back, "Back")]
        }
    }

    // MARK: - Input

    func handle(_ action: InputAction) {
        switch screen {
        case .home: handleHome(action)
        case .settings: handleSettings(action)
        }
    }

    private func handleHome(_ action: InputAction) {
        switch (area, action) {
        case (.games, .left): moveGames(by: -1)
        case (.games, .right): moveGames(by: 1)
        case (.games, .confirm):
            if let game = focusedGame { onLaunch?(game) }
        case (.games, .down):
            withAnimation(Theme.selectorAnimation) { area = .system }
        case (.system, .up) where !games.isEmpty:
            withAnimation(Theme.selectorAnimation) { area = .games }
        case (.system, .left):
            withAnimation(Theme.selectorAnimation) { systemIndex = max(0, systemIndex - 1) }
        case (.system, .right):
            withAnimation(Theme.selectorAnimation) { systemIndex = min(SystemButton.allCases.count - 1, systemIndex + 1) }
        case (.system, .confirm):
            open(SystemButton.allCases[systemIndex])
        default:
            break
        }
    }

    private func handleSettings(_ action: InputAction) {
        switch action {
        case .up:
            withAnimation(Theme.selectorAnimation) { settingsIndex = max(0, settingsIndex - 1) }
        case .down:
            withAnimation(Theme.selectorAnimation) { settingsIndex = min(SettingsItem.allCases.count - 1, settingsIndex + 1) }
        case .confirm:
            switch SettingsItem.allCases[settingsIndex] {
            case .addApp: onAddApp?()
            case .iconStyle: nextIconStyle()
            }
        case .back:
            withAnimation(Theme.screenAnimation) { screen = .home }
        case .left, .right:
            break
        }
    }

    private func open(_ button: SystemButton) {
        switch button {
        case .settings:
            settingsIndex = 0
            withAnimation(Theme.screenAnimation) { screen = .settings }
        }
    }

    // MARK: - Mouse and trackpad

    /// Clicking a game focuses it; clicking the focused game starts it.
    func click(game index: Int) {
        guard screen == .home, games.indices.contains(index) else { return }
        if area == .games && index == focusIndex {
            onLaunch?(games[index])
            return
        }
        if area != .games {
            withAnimation(Theme.selectorAnimation) { area = .games }
        }
        var next = row
        guard next.select(index) else { return }
        apply(next)
    }

    /// Clicking a round button opens it.
    func click(systemButton index: Int) {
        guard screen == .home, SystemButton.allCases.indices.contains(index) else { return }
        withAnimation(Theme.selectorAnimation) {
            area = .system
            systemIndex = index
        }
        open(SystemButton.allCases[index])
    }

    /// Clicking a Settings item selects it.
    func click(settingsItem index: Int) {
        guard screen == .settings, SettingsItem.allCases.indices.contains(index) else { return }
        settingsIndex = index
        handleSettings(.confirm)
    }

    /// Clicking Open/Select or Back in the hint bar does the same as the button.
    func click(hint: HintKind) {
        switch hint {
        case .confirm: handle(.confirm)
        case .back: handle(.back)
        case .move: break
        }
    }

    /// Scroll wheel or trackpad swipe: along the game row on the home screen,
    /// up and down the list in Settings. Positive is right/down.
    func scroll(by steps: Int) {
        guard steps != 0 else { return }
        switch screen {
        case .home:
            guard !games.isEmpty else { return }
            if area != .games {
                withAnimation(Theme.selectorAnimation) { area = .games }
            }
            moveGames(by: steps)
        case .settings:
            let last = SettingsItem.allCases.count - 1
            withAnimation(Theme.selectorAnimation) { settingsIndex = min(max(settingsIndex + steps, 0), last) }
        }
    }

    // MARK: - Game row

    /// Focuses a game directly (used for CI snapshots).
    func select(_ index: Int) {
        var next = row
        next.select(index)
        area = .games
        apply(next)
    }

    func setVisibleCount(_ count: Int) {
        guard count != row.visibleCount else { return }
        row.setVisibleCount(count)
        scrollIndex = row.firstVisible
    }

    private func moveGames(by delta: Int) {
        var next = row
        guard next.move(by: delta) else { return }
        apply(next)
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

    // MARK: - Library

    /// Adds the chosen apps, saves the library, and returns to the home screen
    /// with the last added app focused.
    func addApps(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var lastAdded: LibraryEntry?
        for url in urls {
            lastAdded = library.add(path: url.path, title: Game.title(for: url))
        }
        if saves {
            do {
                try library.save(to: StorageLocation.library)
            } catch {
                print("Couldn't save library: \(error)")
            }
        }

        let existing = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
        games = library.entries.map { existing[$0.id] ?? Game(entry: $0, iconStyle: preferences.iconStyle) }

        var next = RowFocus(count: games.count, visibleCount: row.visibleCount)
        if let id = lastAdded?.id, let index = games.firstIndex(where: { $0.id == id }) {
            next.select(index)
        }
        row = next
        scrollIndex = next.firstVisible
        focusIndex = next.index
        withAnimation(Theme.screenAnimation) {
            screen = .home
            area = .games
        }
    }

    // MARK: - Messages

    /// Shows `text` at the bottom of the screen for a few seconds.
    func show(message text: String, for seconds: Double = 4) {
        messageClear?.cancel()
        withAnimation(Theme.screenAnimation) { message = text }
        messageClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.screenAnimation) { self?.message = nil }
        }
    }

    // MARK: - Preferences

    /// Switches to the next icon style, reloads every icon and saves the choice.
    private func nextIconStyle() {
        let styles = IconStyle.allCases
        let index = styles.firstIndex(of: preferences.iconStyle) ?? 0
        preferences.iconStyle = styles[(index + 1) % styles.count]
        games = library.entries.map { Game(entry: $0, iconStyle: preferences.iconStyle) }
        if saves {
            do {
                try preferences.save(to: StorageLocation.preferences)
            } catch {
                print("Couldn't save preferences: \(error)")
            }
        }
    }
}
