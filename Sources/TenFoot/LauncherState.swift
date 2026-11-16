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

    enum HintKind { case move, confirm, back, close, options }

    /// A game's options menu (Y, or right-click on its tile).
    struct OptionsMenu {
        let game: Game
    }

    enum OptionsItem: CaseIterable, Identifiable {
        case remove
        case cancel
        var id: Self { self }
        var title: String {
            switch self {
            case .remove: "Remove from TenFoot"
            case .cancel: "Cancel"
            }
        }
        var symbol: String {
            switch self {
            case .remove: "minus.circle"
            case .cancel: "xmark"
            }
        }
    }

    /// "Close <game>?" — shown before closing a running game. `next` is the game to
    /// start once it has closed, when the user picked a different game.
    struct ClosePrompt {
        let running: Game
        let next: Game?
    }

    /// The two buttons of the close prompt; left/right moves between them.
    enum PromptButton { case cancel, close }

    /// A game being dragged with the mouse: it started at `from` and is held over `target`.
    struct Drag: Equatable {
        let id: UUID
        let from: Int
        var target: Int
    }

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
    /// Called to go back to the running game.
    var onResume: (() -> Void)?
    /// Called to close the running game; the game passed in starts once it has closed.
    var onClose: ((Game?) -> Void)?
    /// CI only: notes on mouse handling, printed to the log.
    var trace: ((String) -> Void)?

    /// The game that is running (in the background while TenFoot is shown).
    @Published private(set) var runningGameID: UUID?
    @Published private(set) var closePrompt: ClosePrompt?
    @Published private(set) var promptFocus: PromptButton = .close
    @Published private(set) var drag: Drag?
    @Published private(set) var optionsMenu: OptionsMenu?
    @Published private(set) var optionsIndex = 0

    /// The game that is starting: its tile shows a spinner until the game is in front.
    @Published private(set) var launchingGameID: UUID?
    private var launchTimeout: Task<Void, Never>?
    /// How many times each game has been pressed; each press plays its tile's bounce.
    @Published private(set) var presses: [UUID: Int] = [:]
    private var dragScroll: Task<Void, Never>?
    private var dragScrollDirection = 0

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
        if let drag { return games.first { $0.id == drag.id } }
        return games.indices.contains(focusIndex) ? games[focusIndex] : nil
    }

    /// The focused game, only while focus is on the game row (or the game being dragged).
    var focusedGame: Game? {
        area == .games || drag != nil ? backdropGame : nil
    }

    /// Where the selector sits: the focused game, or the slot a dragged game is held over.
    var selectorIndex: Int {
        drag?.target ?? focusIndex
    }

    /// The slot a game shows in; only differs from `index` while another game is dragged.
    func slot(of index: Int) -> Int {
        guard let drag else { return index }
        return Reorder.slot(of: index, movingFrom: drag.from, to: drag.target)
    }

    var runningGame: Game? {
        games.first { $0.id == runningGameID }
    }

    var hints: [(HintKind, String)] {
        if closePrompt != nil {
            return [(.move, "Move"), (.confirm, "Select"), (.back, "Cancel")]
        }
        if optionsMenu != nil {
            return [(.move, "Move"), (.confirm, "Select"), (.back, "Back")]
        }
        switch (screen, area) {
        case (.home, .games) where focusedGame != nil && focusedGame?.id == runningGameID:
            return [(.move, "Move"), (.confirm, "Resume"), (.close, "Close"), (.options, "Options")]
        case (.home, .games): return [(.move, "Move"), (.confirm, "Start"), (.options, "Options")]
        case (.home, .system): return [(.move, "Move"), (.confirm, "Open")]
        case (.settings, _): return [(.move, "Move"), (.confirm, "Select"), (.back, "Back")]
        }
    }

    // MARK: - Input

    func handle(_ action: InputAction) {
        guard drag == nil else { return } // the mouse is moving a game
        if closePrompt != nil {
            handlePrompt(action)
            return
        }
        if optionsMenu != nil {
            handleOptions(action)
            return
        }
        if action == .home {
            // Already in TenFoot: Home goes back to the home screen.
            if screen != .home { withAnimation(Theme.screenAnimation) { screen = .home } }
            return
        }
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
            if let game = focusedGame { start(game) }
        case (.games, .close):
            if let game = focusedGame, game.id == runningGameID {
                askToClose(game, then: nil)
            }
        case (.games, .options):
            openOptions(game: focusIndex)
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
        case .left, .right, .close, .home, .options:
            break
        }
    }

    private func handlePrompt(_ action: InputAction) {
        switch action {
        case .left:
            withAnimation(Theme.selectorAnimation) { promptFocus = .cancel }
        case .right:
            withAnimation(Theme.selectorAnimation) { promptFocus = .close }
        case .confirm:
            choose(promptFocus)
        case .back, .home:
            choose(.cancel)
        case .up, .down, .close, .options:
            break
        }
    }

    /// Picks a button of the close prompt (A on the focused one, or a click).
    func choose(_ button: PromptButton) {
        guard let prompt = closePrompt else { return }
        withAnimation(Theme.popupAnimation) { closePrompt = nil }
        if button == .close { onClose?(prompt.next) }
    }

    private func askToClose(_ running: Game, then next: Game?) {
        promptFocus = .close
        withAnimation(Theme.popupAnimation) { closePrompt = ClosePrompt(running: running, next: next) }
    }

    /// A on a game: resume it if it's the one running, offer to close the running
    /// one if it's different, otherwise start it.
    private func start(_ game: Game) {
        presses[game.id, default: 0] += 1
        if game.id == runningGameID {
            onResume?()
        } else if let running = runningGame {
            askToClose(running, then: game)
        } else {
            onLaunch?(game)
        }
    }

    // MARK: - Running game

    /// Shows (or, with nil, clears) the spinner on a starting game's tile.
    func setLaunching(_ id: UUID?) {
        guard id != launchingGameID else { return }
        launchTimeout?.cancel()
        withAnimation(Theme.screenAnimation) { launchingGameID = id }
        guard id != nil else { return }
        launchTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.launchFeedbackTimeout))
            guard !Task.isCancelled else { return }
            self?.setLaunching(nil)
        }
    }

    func setRunningGame(_ id: UUID?) {
        runningGameID = id
        if id == nil { closePrompt = nil }
    }

    /// Back from a game with Home: the home screen with the running game focused.
    func showRunningGame() {
        setLaunching(nil)
        closePrompt = nil
        optionsMenu = nil
        messageClear?.cancel()
        message = nil
        screen = .home
        if let index = games.firstIndex(where: { $0.id == runningGameID }) {
            select(index)
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
        trace?("click on game \(index)")
        guard screen == .home, games.indices.contains(index) else { return }
        guard closePrompt == nil, optionsMenu == nil, drag == nil else { return }
        if area == .games && index == focusIndex {
            start(games[index])
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
        guard closePrompt == nil, optionsMenu == nil, screen == .home,
              SystemButton.allCases.indices.contains(index) else { return }
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
        case .close: handle(.close)
        case .options: handle(.options)
        case .move: break
        }
    }

    /// Scroll wheel or trackpad swipe: along the game row on the home screen,
    /// up and down the list in Settings. Positive is right/down.
    func scroll(by steps: Int) {
        guard steps != 0, closePrompt == nil, optionsMenu == nil, drag == nil else { return }
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

    // MARK: - Game options

    /// Opens a game's options menu (Y on the focused game, or right-click on a tile).
    func openOptions(game index: Int) {
        guard screen == .home, closePrompt == nil, optionsMenu == nil, drag == nil,
              games.indices.contains(index) else { return }
        if area != .games || index != focusIndex {
            withAnimation(Theme.selectorAnimation) { area = .games }
            var next = row
            next.select(index)
            apply(next)
        }
        let game = games[index]
        // A running game can't be removed, so start on Cancel.
        optionsIndex = game.id == runningGameID ? OptionsItem.allCases.firstIndex(of: .cancel)! : 0
        withAnimation(Theme.popupAnimation) { optionsMenu = OptionsMenu(game: game) }
    }

    /// Whether an item can be picked right now (Remove is off for the running game).
    func isAvailable(_ item: OptionsItem) -> Bool {
        item != .remove || optionsMenu?.game.id != runningGameID
    }

    /// Picks an item of the options menu (A on the focused one, or a click).
    func pick(_ item: OptionsItem) {
        guard let menu = optionsMenu, isAvailable(item) else { return }
        withAnimation(Theme.popupAnimation) { optionsMenu = nil }
        switch item {
        case .remove: remove(gameID: menu.game.id)
        case .cancel: break
        }
    }

    private func handleOptions(_ action: InputAction) {
        let last = OptionsItem.allCases.count - 1
        switch action {
        case .up:
            withAnimation(Theme.selectorAnimation) { optionsIndex = max(0, optionsIndex - 1) }
        case .down:
            withAnimation(Theme.selectorAnimation) { optionsIndex = min(last, optionsIndex + 1) }
        case .confirm:
            pick(OptionsItem.allCases[optionsIndex])
        case .back, .home, .options:
            pick(.cancel)
        case .left, .right, .close:
            break
        }
    }

    /// Takes a game off the home screen and saves the library; the app itself stays on
    /// the Mac. Focus stays in the same place, so the next game slides into it.
    private func remove(gameID id: UUID) {
        guard id != runningGameID, let index = games.firstIndex(where: { $0.id == id }) else { return }
        library.remove(id: id)
        if saves {
            do {
                try library.save(to: StorageLocation.library)
            } catch {
                print("Couldn't save library: \(error)")
            }
        }
        var remaining = games
        remaining.remove(at: index)
        var next = RowFocus(count: remaining.count, visibleCount: row.visibleCount)
        next.select(min(focusIndex, remaining.count - 1))
        next.scroll(to: scrollIndex)
        withAnimation(Theme.reorderAnimation) {
            games = remaining
            row = next
            scrollIndex = next.firstVisible
            focusIndex = next.index
            if remaining.isEmpty { area = .system }
        }
    }

    // MARK: - Drag to reorder

    /// Picks up the game at `index`. Returns false if it can't be moved right now.
    func beginDrag(_ index: Int) -> Bool {
        guard drag == nil, screen == .home, closePrompt == nil, optionsMenu == nil, games.indices.contains(index) else {
            trace?("couldn't pick up game \(index): dragging \(drag != nil), prompt \(closePrompt != nil)")
            return false
        }
        trace?("picked up game \(index)")
        withAnimation(Theme.selectorAnimation) {
            drag = Drag(id: games[index].id, from: index, target: index)
            area = .games
        }
        return true
    }

    /// Holds the dragged game over `slot`. Only on-screen slots count; dragging
    /// to the edge of the screen scrolls the row instead (`setDragEdge`).
    func moveDrag(to slot: Int) {
        guard var next = drag else { return }
        let lastVisible = min(scrollIndex + row.visibleCount, games.count) - 1
        next.target = min(max(slot, scrollIndex), lastVisible)
        guard next != drag else { return }
        withAnimation(Theme.reorderAnimation) { drag = next }
    }

    /// While the pointer is at the left (-1) or right (1) edge of the screen, the row
    /// keeps scrolling that way with the dragged game; 0 stops it.
    func setDragEdge(_ direction: Int) {
        guard direction != dragScrollDirection else { return }
        dragScrollDirection = direction
        dragScroll?.cancel()
        dragScroll = nil
        guard direction != 0, drag != nil else { return }
        dragScroll = Task { [weak self] in
            while !Task.isCancelled {
                self?.scrollDrag()
                try? await Task.sleep(for: .seconds(Theme.dragScrollInterval * Theme.motionScale))
            }
        }
    }

    private func scrollDrag() {
        guard var next = drag else { return }
        let lastFirst = max(0, games.count - row.visibleCount)
        let first = min(max(scrollIndex + dragScrollDirection, 0), lastFirst)
        guard first != scrollIndex else { return }
        withAnimation(Theme.dragScrollAnimation) { scrollIndex = first }
        next.target = dragScrollDirection > 0 ? min(first + row.visibleCount, games.count) - 1 : first
        withAnimation(Theme.reorderAnimation) { drag = next }
    }

    /// Drops the dragged game where it's held, saves the new order and focuses it.
    /// The tiles are already showing the new order, so nothing moves.
    func endDrag() {
        setDragEdge(0)
        guard let drag else { return }
        trace?("dropped game \(drag.from) on slot \(drag.target)")
        library.move(from: drag.from, to: drag.target)
        if saves {
            do {
                try library.save(to: StorageLocation.library)
            } catch {
                print("Couldn't save library: \(error)")
            }
        }
        var reordered = games
        reordered.insert(reordered.remove(at: drag.from), at: drag.target)

        var next = RowFocus(count: reordered.count, visibleCount: row.visibleCount)
        next.select(drag.target)
        next.scroll(to: scrollIndex)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            games = reordered
            self.drag = nil
            row = next
            scrollIndex = next.firstVisible
            focusIndex = next.index
        }
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

    /// Reads every game's icon again, e.g. after one was changed in Finder.
    func reloadIcons() {
        guard drag == nil else { return }
        games = library.entries.map { Game(entry: $0, iconStyle: preferences.iconStyle) }
    }

    /// Switches to the next icon style, reloads every icon and saves the choice.
    private func nextIconStyle() {
        let styles = IconStyle.allCases
        let index = styles.firstIndex(of: preferences.iconStyle) ?? 0
        preferences.iconStyle = styles[(index + 1) % styles.count]
        reloadIcons()
        if saves {
            do {
                try preferences.save(to: StorageLocation.preferences)
            } catch {
                print("Couldn't save preferences: \(error)")
            }
        }
    }
}
