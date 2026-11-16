/// Focus state for a horizontal row of tiles.
///
/// Tracks which tile is focused and which tile is the first one visible on
/// screen. The row only scrolls when focus would otherwise leave the visible
/// area, so moving within the visible tiles keeps the row still.
public struct RowFocus: Equatable, Sendable {
    public private(set) var count: Int
    public private(set) var index: Int = 0
    public private(set) var firstVisible: Int = 0
    public private(set) var visibleCount: Int

    public init(count: Int, visibleCount: Int = 1) {
        self.count = max(0, count)
        self.visibleCount = max(1, visibleCount)
    }

    /// Moves focus by `delta`, stopping at either end of the row.
    /// Returns `true` if the focused tile changed.
    @discardableResult
    public mutating func move(by delta: Int) -> Bool {
        select(index + delta)
    }

    /// Focuses the tile at `newIndex`, clamped to the row.
    /// Returns `true` if the focused tile changed.
    @discardableResult
    public mutating func select(_ newIndex: Int) -> Bool {
        guard count > 0 else { return false }
        let clamped = min(max(newIndex, 0), count - 1)
        guard clamped != index else { return false }
        index = clamped
        scrollIntoView()
        return true
    }

    /// Updates how many tiles fit on screen (e.g. when the window resizes).
    public mutating func setVisibleCount(_ newValue: Int) {
        visibleCount = max(1, newValue)
        scrollIntoView()
    }

    /// Scrolls so `first` is the first visible tile, as far as the row allows,
    /// while keeping the focused tile on screen.
    public mutating func scroll(to first: Int) {
        firstVisible = first
        scrollIntoView()
    }

    private mutating func scrollIntoView() {
        if index < firstVisible {
            firstVisible = index
        } else if index >= firstVisible + visibleCount {
            firstVisible = index - visibleCount + 1
        }
        firstVisible = min(max(firstVisible, 0), max(0, count - visibleCount))
    }
}
