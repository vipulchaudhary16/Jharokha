
@testable import PaneCore

struct ScreenTilesTests {
    func newWindowsGetTilesUntilFullThenStack() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3], capacity: 3, activeTile: nil)
        expect(s.showingWindows == [1, 2, 3])
        s.reconcile(present: [1, 2, 3, 4], capacity: 3, activeTile: 1)
        expect(s.tiles.count == 3)
        expect(s.tiles[1].windows == [2, 4])
        expect(s.tiles[1].showing == 4)
    }

    func closingReflowsAndNextBecomesPrimary() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3], capacity: 3, activeTile: nil)
        s.reconcile(present: [2, 3], capacity: 3, activeTile: nil)
        expect(s.showingWindows == [2, 3])
    }

    func closingShowingStackedWindowBringsMostRecentForward() {
        var s = ScreenTiles()
        s.reconcile(present: [1], capacity: 1, activeTile: nil)
        s.insert(2, capacity: 1, activeTile: 0)
        s.insert(3, capacity: 1, activeTile: 0)
        s.show(2)
        s.show(3)
        s.remove(3, capacity: 1)
        expect(s.tiles[0].showing == 2)
    }

    func waitingWindowGetsOwnTileWhenRoomAppears() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2], capacity: 2, activeTile: nil)
        s.insert(3, capacity: 2, activeTile: 0)
        expect(s.tiles.count == 2)
        s.remove(2, capacity: 2)
        expect(s.tiles.count == 2)
        expect(Set(s.allWindows) == [1, 3])
        expect(s.tiles.allSatisfy { !$0.isStacked })
    }

    func loweringCountMergesIntoPreviousTile() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3], capacity: 3, activeTile: nil)
        s.normalize(capacity: 2)
        expect(s.tiles.count == 2)
        expect(s.tiles[1].windows == [2, 3])
        expect(s.tiles[1].showing == 2)
        s.normalize(capacity: 3)
        expect(s.tiles.count == 3)
    }

    func swapMovesOnlyShowingWindows() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2], capacity: 2, activeTile: nil)
        s.insert(3, capacity: 2, activeTile: 1) // tile 1 = [2, 3], showing 3
        s.swapShowing(0, 1)
        expect(s.tiles[0].windows == [3])
        expect(s.tiles[1].windows == [2, 1])
        expect(s.tiles[1].showing == 1)
    }

    func cycleWrapsAround() {
        var s = ScreenTiles()
        s.reconcile(present: [1], capacity: 1, activeTile: nil)
        s.insert(2, capacity: 1, activeTile: 0)
        s.insert(3, capacity: 1, activeTile: 0)
        expect(s.cycle(tile: 0, by: 1) == 1)
        expect(s.cycle(tile: 0, by: -1) == 3)
        expect(s.cycle(tile: 5, by: 1) == nil)
    }

    func movingAWindowOntoAnotherTileStacksIt() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3], capacity: 3, activeTile: nil)
        s.move(3, toTile: 0, capacity: 3)
        expect(s.tiles.count == 2)
        expect(s.tiles[0].windows == [1, 3])
        expect(s.tiles[0].showing == 3)
        s.move(1, toTile: 1, capacity: 2)
        expect(s.tiles[1].windows == [2, 1])
        expect(s.tiles[0].showing == 3)
    }

    func pinsFollowTheStackNotTheWindow() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3, 4], capacity: 4, activeTile: nil)
        s.move(2, toTile: 0, capacity: 4)        // [1,2] [3] [4]
        s.move(2, toTile: 2, capacity: 4)        // 2 joins 4; 1 is alone again
        expect(!s.pinned.contains(1))
        s.normalize(capacity: 1)
        s.normalize(capacity: 3)
        // 2 and 4 were stacked on purpose; 1 and 3 get their own tiles back.
        expect(s.tiles.count == 3)
        expect(s.tiles.contains { Set($0.windows) == [2, 4] })
    }

    func mergeStacksTwoChosenTiles() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3, 4], capacity: 4, activeTile: nil)
        s.merge(0, 2)                            // [1,3] [2] [4]
        expect(s.tiles.count == 3)
        expect(Set(s.tiles[0].windows) == [1, 3])
        expect(s.tiles[1].windows == [2] && s.tiles[2].windows == [4])
    }

    func arrangeMovesStacksWhole() {
        var s = ScreenTiles()
        s.reconcile(present: [1, 2, 3], capacity: 3, activeTile: nil)
        s.merge(0, 1)                            // [1,2] [3]
        s.arrange([1, 0])
        expect(s.tiles[0].windows == [3])
        expect(Set(s.tiles[1].windows) == [1, 2])
        s.arrange([0, 0])                        // not a permutation: ignored
        expect(s.tiles[0].windows == [3])
    }
}
