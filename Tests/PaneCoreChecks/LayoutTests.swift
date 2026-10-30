import CoreGraphics

@testable import PaneCore

struct LayoutTests {
    let screen = CGRect(x: 0, y: 25, width: 1000, height: 800)

    func frames(_ kind: LayoutKind, _ n: Int, ratio: CGFloat = 0.5, gap: CGFloat = 0,
                shape: ScreenShape = .standard, in rect: CGRect? = nil) -> [CGRect] {
        LayoutEngine.frames(kind: kind, count: n, in: rect ?? screen, mainRatio: ratio, gap: gap, shape: shape)
    }

    func singleWindowFillsScreen() {
        for kind in LayoutKind.allCases {
            expect(frames(kind, 1) == [screen])
        }
    }

    func gridGrowsByHalvingNewestSpace() {
        expect(frames(.grid, 2) == [CGRect(x: 0, y: 25, width: 500, height: 800),
                                     CGRect(x: 500, y: 25, width: 500, height: 800)])
        expect(frames(.grid, 3) == [CGRect(x: 0, y: 25, width: 500, height: 800),
                                     CGRect(x: 500, y: 25, width: 500, height: 400),
                                     CGRect(x: 500, y: 425, width: 500, height: 400)])
        // The fourth window takes the bottom half of the primary's column.
        expect(frames(.grid, 4)[3] == CGRect(x: 0, y: 425, width: 500, height: 400))
        expect(frames(.grid, 4)[0] == CGRect(x: 0, y: 25, width: 500, height: 400))
    }

    func mainRatioSizesPrimary() {
        expect(frames(.columns, 3, ratio: 0.6).map(\.width) == [600, 200, 200])
        expect(frames(.rows, 2, ratio: 0.6).map(\.height) == [480, 320])
        expect(frames(.side, 3, ratio: 0.6)[0].width == 600)
    }

    func gapsSeparateTilesAndEdges() {
        let f = frames(.columns, 2, gap: 8)
        expect(f[0].minX == 8)
        expect(f[1].minX - f[0].maxX == 8)
        expect(f[1].maxX == 992)
        expect(f[0].minY == 33)
    }

    func ultrawideSideKeepsTwoLargeWindows() {
        let wide = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let f = frames(.side, 5, shape: .ultrawide, in: wide)
        expect(f.count == 5)
        expect(f[0].width == 1290 && f[1].width == 1290)
        expect(f[2].width == 860 && f[2].minX == 2580)
        expect(f[2...].map(\.height) == [480, 480, 480])
    }

    func verticalPutsMainOnTop() {
        let tall = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let grid = frames(.grid, 3, shape: .vertical, in: tall)
        expect(grid[0] == CGRect(x: 0, y: 0, width: 1080, height: 960))
        expect(grid[1] == CGRect(x: 0, y: 960, width: 540, height: 960))
        let rows = frames(.rows, 3, shape: .vertical, in: tall)
        expect(rows.allSatisfy { $0.width == 1080 })
        expect(frames(.columns, 2, shape: .vertical, in: tall) == frames(.rows, 2, shape: .vertical, in: tall))
    }

    func shapeDetection() {
        expect(ScreenShape.of(CGSize(width: 1512, height: 982)) == .standard)
        expect(ScreenShape.of(CGSize(width: 3440, height: 1440)) == .ultrawide)
        expect(ScreenShape.of(CGSize(width: 1080, height: 1920)) == .vertical)
    }

    func capacities() {
        let laptop = CGSize(width: 1512, height: 982)
        let monitor = CGSize(width: 2560, height: 1440)
        expect(LayoutEngine.maxCount(kind: .rows, shape: .standard, size: laptop) == 2)
        expect(LayoutEngine.maxCount(kind: .rows, shape: .standard, size: monitor) == 3)
        expect(LayoutEngine.maxCount(kind: .side, shape: .ultrawide, size: CGSize(width: 3440, height: 1440)) == 5)
        expect(LayoutEngine.maxCount(kind: .columns, shape: .standard, size: laptop) == 3)
    }

    func neighbors() {
        let f = frames(.grid, 4) // [lt, rt, rb, lb]
        expect(LayoutEngine.neighbor(of: 0, in: f, direction: .right) == 1)
        expect(LayoutEngine.neighbor(of: 0, in: f, direction: .down) == 3)
        expect(LayoutEngine.neighbor(of: 2, in: f, direction: .left) == 3)
        expect(LayoutEngine.neighbor(of: 2, in: f, direction: .up) == 1)
        expect(LayoutEngine.neighbor(of: 0, in: f, direction: .left) == nil)
    }

    // Docker Desktop's case: the bottom row needs more height than its share.
    func minimumTakesRoomFromNeighbours() {
        let f = LayoutEngine.fit(kind: .rows, count: 3, in: screen, mainRatio: 0.5, gap: 0, shape: .standard,
                                 minimums: [.zero, .zero, CGSize(width: 0, height: 400)])
        expect(f != nil)
        guard let f else { return }
        expect(f[2].height == 400)
        expect(f[0].height + f[1].height == 400)
        expect(f[0].height > f[1].height) // the primary keeps its larger share
        expect(f[2].maxY == screen.maxY)
    }

    func minimumsThatCannotFitReturnNil() {
        let tooTall = [CGSize.zero, .zero, CGSize(width: 0, height: 900)]
        expect(LayoutEngine.fit(kind: .rows, count: 3, in: screen, mainRatio: 0.5, gap: 0, shape: .standard,
                                minimums: tooTall) == nil)
        let tooWide = [CGSize(width: 700, height: 0), CGSize(width: 400, height: 0)]
        expect(LayoutEngine.fit(kind: .grid, count: 2, in: screen, mainRatio: 0.5, gap: 0, shape: .standard,
                                minimums: tooWide) == nil)
    }

    func minimumWidthInGridColumn() {
        // Tile 2 sits in the right column; its width minimum widens the whole column.
        let f = LayoutEngine.fit(kind: .grid, count: 3, in: screen, mainRatio: 0.5, gap: 8, shape: .standard,
                                 minimums: [.zero, .zero, CGSize(width: 700, height: 0)])
        expect(f?[2].width == 700)
        expect(f?[1].width == 700)
        expect(f?[0].maxX == 1000 - 8 - 700 - 8)
    }

    func resize(_ kind: LayoutKind, _ n: Int, tile: Int, to frame: CGRect, weights: SplitWeights = [:]) -> [CGRect] {
        let w = LayoutEngine.resize(tile: tile, to: frame, kind: kind, count: n, in: screen, mainRatio: 0.5, gap: 0,
                                    shape: .standard, minimums: [], weights: weights)
        return LayoutEngine.fit(kind: kind, count: n, in: screen, mainRatio: 0.5, gap: 0, shape: .standard,
                                minimums: [], weights: w) ?? []
    }

    func draggingAnEdgeMovesTheNeighbour() {
        var frame = frames(.columns, 2)[0]
        frame.size.width += 100
        let f = resize(.columns, 2, tile: 0, to: frame)
        expect(f[0].width == 600)
        expect(f[1].minX == 600 && f[1].width == 400)
    }

    func resizingOnlyAffectsTheSplitOnThatEdge() {
        // Grid of 4: tile 0's bottom edge belongs to the left column's split only.
        var frame = frames(.grid, 4)[0]
        frame.size.height += 100
        let f = resize(.grid, 4, tile: 0, to: frame)
        expect(f[0].height == 500)
        expect(f[3].minY == 525 && f[3].height == 300)
        expect(f[1] == frames(.grid, 4)[1]) // the right column is untouched
    }

    func dragFromTheLeftEdgeGrowsLeftward() {
        var frame = frames(.columns, 3)[1] // middle column, x 500..750
        frame.origin.x -= 100
        frame.size.width += 100
        let f = resize(.columns, 3, tile: 1, to: frame)
        expect(f[0].width == 400)
        expect(f[1].minX == 400 && f[1].width == 350)
        expect(f[2] == frames(.columns, 3)[2])
    }

    func outerEdgesNeverMoveAndNeighboursKeepAFloor() {
        var frame = frames(.columns, 2)[1]
        frame.size.width += 200 // the right screen edge: nothing to move
        expect(resize(.columns, 2, tile: 1, to: frame) == frames(.columns, 2))
        var grow = frames(.columns, 2)[0]
        grow.size.width = 990 // would crush the neighbour
        let f = resize(.columns, 2, tile: 0, to: grow)
        expect(f[1].width == LayoutEngine.minimumTileLength)
    }
}
