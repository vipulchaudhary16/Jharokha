// A minimal test runner: Command Line Tools can build swift-testing but cannot run it,
// so the core checks run as a plain executable (`swift run PaneCoreChecks`).
import Foundation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var current = ""

func expect(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    if !condition() {
        failures += 1
        print("  ✘ \(current) failed at \(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)")
    }
}

func run(_ name: String, _ body: () -> Void) {
    current = name
    let before = failures
    body()
    if failures == before { print("  ✔ \(name)") }
}

let layout = LayoutTests()
run("singleWindowFillsScreen", layout.singleWindowFillsScreen)
run("gridGrowsByHalvingNewestSpace", layout.gridGrowsByHalvingNewestSpace)
run("mainRatioSizesPrimary", layout.mainRatioSizesPrimary)
run("gapsSeparateTilesAndEdges", layout.gapsSeparateTilesAndEdges)
run("ultrawideSideKeepsTwoLargeWindows", layout.ultrawideSideKeepsTwoLargeWindows)
run("verticalPutsMainOnTop", layout.verticalPutsMainOnTop)
run("shapeDetection", layout.shapeDetection)
run("capacities", layout.capacities)
run("neighbors", layout.neighbors)

let tiles = ScreenTilesTests()
run("newWindowsGetTilesUntilFullThenStack", tiles.newWindowsGetTilesUntilFullThenStack)
run("closingReflowsAndNextBecomesPrimary", tiles.closingReflowsAndNextBecomesPrimary)
run("closingShowingStackedWindowBringsMostRecentForward", tiles.closingShowingStackedWindowBringsMostRecentForward)
run("waitingWindowGetsOwnTileWhenRoomAppears", tiles.waitingWindowGetsOwnTileWhenRoomAppears)
run("loweringCountMergesIntoPreviousTile", tiles.loweringCountMergesIntoPreviousTile)
run("swapMovesOnlyShowingWindows", tiles.swapMovesOnlyShowingWindows)
run("cycleWrapsAround", tiles.cycleWrapsAround)

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
