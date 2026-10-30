import AppKit
import PaneCore

/// Smart placement: the windows that need the most room get the tiles that fit them.
extension TilingManager {
    /// Apps that work best in a big window, before Pane has learned anything about them.
    private static let roomyApps: [(prefix: String, width: CGFloat)] = [
        ("com.apple.Safari", 1000), ("com.google.Chrome", 1000), ("company.thebrowser", 1000), ("org.mozilla.firefox", 1000),
        ("com.microsoft.edgemac", 1000), ("com.brave.Browser", 1000), ("com.microsoft.VSCode", 1000),
        ("com.todesktop.230313mzl4w4u92", 1000), ("dev.zed.Zed", 1000), ("com.apple.dt.Xcode", 1100), ("com.jetbrains", 1000),
        ("com.figma.Desktop", 1100), ("com.microsoft.Excel", 1000), ("com.apple.iWork.Numbers", 1000),
    ]

    /// How much room a window needs: what its app has refused to go below, or a known preference.
    func need(of id: CGWindowID) -> CGSize {
        let learned = minimumSize(id)
        let preferred = bundleIDs[id].flatMap { bundle in Self.roomyApps.first { bundle.hasPrefix($0.prefix) }?.width } ?? 0
        // Roomy apps want a big window both ways; learned minimums stay hard limits (checked by fit).
        return CGSize(width: max(learned.width, preferred), height: max(learned.height, preferred > 0 ? 700 : 0))
    }

    /// Reorders a screen's tiles by need. Runs when windows come or go (or on Re-apply), so a
    /// swap you make stays put until the set of windows changes.
    func arrangeBySize(_ display: Display, _ state: inout ScreenTiles) {
        guard settings.arrangesBySize, state.tiles.count > 1 else { return }
        let rects = frames(for: display, count: state.tiles.count)
        let needs = state.tiles.map { tile in
            tile.windows.map(need).reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        }
        let minimums = state.tiles.map { tile in
            tile.windows.map(minimumSize).reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        }
        // Arrangements where every window fits come first, so smart placement never forces
        // Pane to tile fewer windows than it otherwise could.
        let order = LayoutEngine.assignBySize(tiles: rects, needs: needs) { order in
            LayoutEngine.fit(kind: settings.layout(for: display), count: order.count, in: display.rect,
                             mainRatio: settings.mainRatio, gap: settings.gap, shape: display.shape,
                             minimums: order.map { minimums[$0] }) != nil
        }
        if order != Array(state.tiles.indices) { state.arrange(order) }
    }
}
