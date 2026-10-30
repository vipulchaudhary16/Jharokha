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
}
