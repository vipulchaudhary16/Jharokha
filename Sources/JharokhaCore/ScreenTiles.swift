public typealias WindowID = UInt32

/// One tile on a screen. Holds one window, or a stack of windows of which one is showing.
public struct Tile: Equatable, Sendable {
    /// Stable order, used for cycling and for the stack indicator.
    public private(set) var windows: [WindowID]
    public private(set) var showing: WindowID
    /// Most recently shown last; decides who comes forward when the showing window leaves.
    private var recent: [WindowID]

    public init(_ id: WindowID) {
        windows = [id]
        showing = id
        recent = [id]
    }

    public var isStacked: Bool { windows.count > 1 }

    /// Adds a window on top of the stack and shows it.
    mutating func push(_ id: WindowID) {
        windows.append(id)
        show(id)
    }

    mutating func show(_ id: WindowID) {
        guard windows.contains(id) else { return }
        showing = id
        recent.removeAll { $0 == id }
        recent.append(id)
    }

    /// Returns false when the tile is now empty.
    mutating func remove(_ id: WindowID) -> Bool {
        windows.removeAll { $0 == id }
        recent.removeAll { $0 == id }
        guard let next = recent.last ?? windows.last else { return false }
        if showing == id { show(next) }
        return true
    }

    /// Replaces the showing window with another one, leaving the rest of the stack in place.
    mutating func replaceShowing(with id: WindowID) {
        let old = showing
        if let i = windows.firstIndex(of: old) { windows[i] = id }
        recent.removeAll { $0 == old }
        showing = id
        recent.append(id)
    }

    /// A window waiting behind the showing one, least recently used first.
    func waiting(excluding excluded: Set<WindowID>) -> WindowID? {
        recent.first { $0 != showing && !excluded.contains($0) }
    }

    mutating func absorb(_ other: Tile) {
        for id in other.windows where !windows.contains(id) {
            windows.append(id)
            recent.insert(id, at: 0)
        }
    }

    mutating func cycle(by step: Int) -> WindowID {
        guard let i = windows.firstIndex(of: showing), windows.count > 1 else { return showing }
        let next = windows[((i + step) % windows.count + windows.count) % windows.count]
        show(next)
        return next
    }
}

/// The ordered tiles of one screen on one Space. Tile 0 is primary.
public struct ScreenTiles: Equatable, Sendable {
    public private(set) var tiles: [Tile] = []
    /// Windows the user stacked on purpose; they stay stacked even when there is room.
    public private(set) var pinned: Set<WindowID> = []

    public init() {}

    public var allWindows: [WindowID] { tiles.flatMap(\.windows) }
    public var showingWindows: [WindowID] { tiles.map(\.showing) }

    public func tileIndex(of id: WindowID) -> Int? {
        tiles.firstIndex { $0.windows.contains(id) }
    }

    public func contains(_ id: WindowID) -> Bool { tileIndex(of: id) != nil }

    /// A new window gets its own tile while there is room; on a full screen it stacks
    /// on top of the active tile (or the last tile if none is active).
    public mutating func insert(_ id: WindowID, capacity: Int, activeTile: Int?) {
        guard !contains(id) else { return }
        if tiles.count < max(capacity, 1) {
            tiles.append(Tile(id))
        } else {
            let target = activeTile.flatMap { tiles.indices.contains($0) ? $0 : nil } ?? tiles.count - 1
            tiles[target].push(id)
        }
    }

    public mutating func remove(_ id: WindowID, capacity: Int) {
        guard let i = tileIndex(of: id) else { return }
        pinned.remove(id)
        if !tiles[i].remove(id) { tiles.remove(at: i) }
        prunePins()
        normalize(capacity: capacity)
    }

    /// Removes windows that are gone and adds new ones in the order given.
    public mutating func reconcile(present: [WindowID], capacity: Int, activeTile: Int?) {
        let presentSet = Set(present)
        for id in allWindows where !presentSet.contains(id) {
            remove(id, capacity: capacity)
        }
        normalize(capacity: capacity)
        for id in present where !contains(id) {
            insert(id, capacity: capacity, activeTile: activeTile)
        }
    }

    /// Lowering the count merges the last tiles into the previous one; raising it
    /// gives waiting stacked windows their own tile, except those stacked on purpose.
    public mutating func normalize(capacity: Int) {
        let capacity = max(capacity, 1)
        while tiles.count > capacity {
            let last = tiles.removeLast()
            tiles[tiles.count - 1].absorb(last)
        }
        while tiles.count < capacity {
            // A stack made on purpose that got merged with other windows moves out together.
            if let source = tiles.firstIndex(where: { tile in
                let group = tile.windows.filter(pinned.contains)
                return !group.isEmpty && group.count < tile.windows.count
            }) {
                let group = tiles[source].windows.filter(pinned.contains)
                group.forEach { _ = tiles[source].remove($0) }
                var stack = Tile(group[0])
                group.dropFirst().forEach { stack.push($0) }
                tiles.append(stack)
                continue
            }
            guard let source = tiles.lastIndex(where: { $0.waiting(excluding: pinned) != nil }),
                  let id = tiles[source].waiting(excluding: pinned) else { break }
            _ = tiles[source].remove(id)
            tiles.append(Tile(id))
        }
    }

    /// Swaps the showing windows of two tiles; each stack stays with its tile.
    public mutating func swapShowing(_ a: Int, _ b: Int) {
        guard a != b, tiles.indices.contains(a), tiles.indices.contains(b) else { return }
        let idA = tiles[a].showing
        let idB = tiles[b].showing
        tiles[a].replaceShowing(with: idB)
        tiles[b].replaceShowing(with: idA)
        // Both left the stack they were pinned in.
        pinned.remove(idA)
        pinned.remove(idB)
        prunePins()
    }

    /// A window is only pinned while it shares a tile with others.
    private mutating func prunePins() {
        pinned = pinned.filter { id in tileIndex(of: id).map { tiles[$0].isStacked } ?? false }
    }

    /// Marks a window as the showing one in its tile (e.g. after ⌘-Tab brought it forward).
    @discardableResult
    public mutating func show(_ id: WindowID) -> Bool {
        guard let i = tileIndex(of: id), tiles[i].showing != id else { return false }
        tiles[i].show(id)
        return true
    }

    /// Moves a window onto another tile's stack, on top. Its old tile closes up if it empties.
    public mutating func move(_ id: WindowID, toTile target: Int, capacity: Int) {
        guard let from = tileIndex(of: id), tiles.indices.contains(target), from != target else { return }
        // Indices shift if the old tile empties; remember the target by its showing window.
        let anchor = tiles[target].showing
        pinned.remove(id)
        if !tiles[from].remove(id) { tiles.remove(at: from) }
        guard let destination = tileIndex(of: anchor) else { return }
        tiles[destination].push(id)
        // The whole stack was made on purpose, so none of it splits off when there's room.
        pinned.formUnion(tiles[destination].windows)
        prunePins()
        normalize(capacity: capacity)
    }

    /// Stacks tile `b` onto tile `a` (when windows can't all fit side by side).
    public mutating func merge(_ a: Int, _ b: Int) {
        guard a != b, tiles.indices.contains(a), tiles.indices.contains(b) else { return }
        let other = tiles[b]
        tiles[a].absorb(other)
        tiles.remove(at: b)
    }

    /// Reorders the tiles: position i gets the tile that was at `order[i]`. Stacks move whole.
    public mutating func arrange(_ order: [Int]) {
        guard order.count == tiles.count, Set(order) == Set(tiles.indices) else { return }
        tiles = order.map { tiles[$0] }
    }

    /// Shows the next (or previous) window of a stacked tile and returns it.
    public mutating func cycle(tile index: Int, by step: Int) -> WindowID? {
        guard tiles.indices.contains(index), tiles[index].isStacked else { return nil }
        return tiles[index].cycle(by: step)
    }
}
