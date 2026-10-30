import AppKit
import PaneCore

/// Resizing: dragging the edge between two windows (the neighbours make room live) and
/// ⌃⌥= / ⌃⌥- / ⌃⌥0. Sizes belong to positions, so they survive swaps, and are kept per
/// display, Space, layout and window count until reset.
extension TilingManager {
    func weightsKey(_ display: Display, count: Int) -> String {
        "\(display.key)|\(settings.layout(for: display).rawValue)\(count)"
    }

    private func resizeWeights(display: Display, tile: Int, to frame: CGRect) -> SplitWeights {
        let count = states[display.key]?.tiles.count ?? 0
        let minimums = states[display.key]?.tiles.map { tile in
            tile.windows.map(minimumSize).reduce(CGSize.zero) {
                CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
            }
        } ?? []
        return LayoutEngine.resize(tile: tile, to: frame, kind: settings.layout(for: display), count: count,
                                   in: display.rect, mainRatio: settings.mainRatio, gap: settings.gap,
                                   shape: display.shape, minimums: minimums,
                                   weights: splitWeights[weightsKey(display, count: count)] ?? [:])
    }

    /// A showing window whose size left its tile while the mouse is down, with the pointer on
    /// its edge, is being resized by that edge. (A window that refuses its tile size also
    /// differs from its target; the pointer check keeps it from being mistaken for a resize.)
    func beginResizeIfNeeded(_ displays: [Display]) {
        let mouse = NSEvent.axMouseLocation
        for display in displays {
            guard let state = states[display.key], focusMode[display.key] == nil else { continue }
            for id in state.showingWindows {
                // Against the size before the press, so a refusing window dragged by its title bar
                // (its size never matched the tile) isn't taken for a resize.
                guard animator.target(of: id) == nil, let frame = windows[id]?.frame, let target = targets[id],
                      let size = baselineSize(of: id), !frame.size.isClose(to: size),
                      frame.insetBy(dx: -16, dy: -16).contains(mouse), !frame.insetBy(dx: 16, dy: 16).contains(mouse) else { continue }
                resizing = (id, display.key, target)
                return
            }
        }
    }

    /// While an edge is dragged, the neighbours follow; the window under the pointer is left to the user.
    func updateLiveResize(_ displays: [Display]) {
        guard let current = resizing, let display = displays.first(where: { $0.key == current.displayKey }),
              let tile = states[display.key]?.tileIndex(of: current.id),
              let frame = windows[current.id]?.frame, !frame.isClose(to: current.frame) else { return }
        resizing?.frame = frame
        let base = splitWeights
        splitWeights[weightsKey(display, count: states[display.key]?.tiles.count ?? 0)] =
            resizeWeights(display: display, tile: tile, to: frame)
        apply([display], excluding: [current.id], animated: false)
        // Live passes don't keep the provisional weights; the drop computes the final ones.
        splitWeights = base
    }

    func finishResize(_ displays: [Display]) {
        guard let current = resizing, let display = displays.first(where: { $0.key == current.displayKey }) else { return }
        if let tile = states[display.key]?.tileIndex(of: current.id), let frame = windows[current.id]?.frame {
            splitWeights[weightsKey(display, count: states[display.key]?.tiles.count ?? 0)] =
                resizeWeights(display: display, tile: tile, to: frame)
        }
        apply(displays)
    }

    /// ⌃⌥= and ⌃⌥-: move the active window's shared edges outward or inward by a small step.
    func resizeActive(grow: Bool) {
        guard let c = context(), focusMode[c.display.key] == nil else { return }
        let rects = rects(for: c.display)
        guard rects.indices.contains(c.tile) else { return }
        let old = rects[c.tile]
        let area = c.display.rect.insetBy(dx: settings.gap, dy: settings.gap)
        let step = max(32, min(area.width, area.height) * 0.05) * (grow ? 1 : -1)
        var frame = old
        // Only shared edges move; edges on the screen's border stay put.
        if abs(old.minX - area.minX) > 2 { frame.origin.x -= step; frame.size.width += step }
        if abs(old.maxX - area.maxX) > 2 { frame.size.width += step }
        if abs(old.minY - area.minY) > 2 { frame.origin.y -= step; frame.size.height += step }
        if abs(old.maxY - area.maxY) > 2 { frame.size.height += step }

        let key = weightsKey(c.display, count: states[c.display.key]?.tiles.count ?? 0)
        let before = splitWeights[key]
        splitWeights[key] = resizeWeights(display: c.display, tile: c.tile, to: frame)
        apply(c.displays)
        if let new = appliedRects[c.display.key], new.indices.contains(c.tile), new[c.tile].isClose(to: old) {
            splitWeights[key] = before
            NSSound.beep()
            Toast.show(grow ? "Maximum size reached" : "Minimum size reached")
        }
        onStateChange?()
    }

    /// ⌃⌥0: every window on this screen back to its starting size.
    func resetSizes(on display: Display? = nil) {
        guard let display = display ?? targetDisplay() else { return }
        let hadCustom = hasCustomSizes(on: display)
        splitWeights = splitWeights.filter { !$0.key.hasPrefix(display.key + "|") }
        guard canTile else { return }
        apply(Display.current())
        Toast.show(hadCustom ? "Window sizes reset" : "Windows are at their starting sizes")
        onStateChange?()
    }

    func hasCustomSizes(on display: Display) -> Bool {
        splitWeights.keys.contains { $0.hasPrefix(display.key + "|") }
    }
}
