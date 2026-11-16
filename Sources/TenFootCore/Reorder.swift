/// Where tiles sit while one of them is being dragged to a new place.
public enum Reorder {
    /// The slot the tile at `index` shows in while the tile at `from` is held over
    /// slot `target`: the held tile takes `target` and the tiles in between shift
    /// one place towards the gap it left. Matches `Library.move(from:to:)`.
    public static func slot(of index: Int, movingFrom from: Int, to target: Int) -> Int {
        if index == from { return target }
        if from < target, index > from, index <= target { return index - 1 }
        if from > target, index >= target, index < from { return index + 1 }
        return index
    }
}
