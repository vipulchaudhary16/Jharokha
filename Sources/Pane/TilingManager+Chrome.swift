import AppKit
import PaneCore

/// What the window chrome (borders, grips, stack dots) and the modes need from the tiler.
extension TilingManager {
    struct ChromeTile {
        let screen: NSScreen
        /// AX coordinates.
        let rect: CGRect
        let windows: [CGWindowID]
        let showing: CGWindowID
        let isActive: Bool
    }

    /// Every tile on screen now, with the active one marked. Empty while tiling is paused.
    func chromeTiles() -> [ChromeTile] {
        guard canTile else { return [] }
        let focused = AX.focusedWindow()?.id
        var result: [ChromeTile] = []
        for display in Display.current() {
            guard let state = states[display.key] else { continue }
            let rects = rects(for: display)
            let zoomed = focusMode[display.key]
            for (index, tile) in state.tiles.enumerated() where rects.indices.contains(index) {
                // In focus mode only the zoomed window is visible, at full size.
                if let zoomed, tile.showing != zoomed { continue }
                let rect = zoomed == nil ? rects[index] : display.rect.insetBy(dx: settings.gap, dy: settings.gap)
                result.append(ChromeTile(screen: display.screen, rect: rect, windows: tile.windows, showing: tile.showing,
                                         isActive: tile.windows.contains { $0 == focused }))
            }
        }
        return result
    }

    var focusedTiledWindow: CGWindowID? {
        guard let id = AX.focusedWindow()?.id, windows[id] != nil, !floating.contains(id) else { return nil }
        return id
    }

    func title(of id: CGWindowID) -> String { windows[id]?.title ?? "" }

    /// Closes a window as its close button would; the app may ask to save first.
    func close(window id: CGWindowID) {
        guard let element = windows[id]?.element, let button: AXUIElement = element.value(kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    func minimize(window id: CGWindowID) {
        windows[id]?.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
    }

    /// Moves a window onto the tile under a point (AX coordinates), adding it to that tile's stack.
    func moveWindow(_ id: CGWindowID, toTileAt point: CGPoint) {
        let displays = Display.current()
        guard let destination = displays.containing(point),
              let target = LayoutEngine.tile(at: point, in: rects(for: destination)) else { return }
        if var state = states[destination.key], state.contains(id) {
            state.move(id, toTile: target, capacity: settings.capacity(for: destination))
            states[destination.key] = state
        } else {
            for display in displays where states[display.key]?.contains(id) ?? false {
                states[display.key]?.remove(id, capacity: settings.capacity(for: display))
            }
            var state = states[destination.key] ?? ScreenTiles()
            state.insert(id, capacity: settings.capacity(for: destination), activeTile: target)
            states[destination.key] = state
        }
        apply(displays)
        activate(window: id)
        Toast.show("Moved here")
    }

    /// ⌃⌥⇧F: never tile the active window's app again (it floats where you put it).
    func alwaysFloatActiveApp() {
        guard let id = AX.focusedWindow()?.id, let app = appName(of: id), let bundleID = app.bundleID else { return }
        setTiling(false, forBundleID: bundleID)
        Toast.show("\(app.name) windows will always float · turn it back on from the menu")
    }

    /// The tiled window under a point, if it is the frontmost window there.
    func tiledWindow(at point: CGPoint) -> CGWindowID? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in info where entry[kCGWindowLayer as String] as? Int == 0 {
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
                    .contains(point) else { continue }
            let id = entry[kCGWindowNumber as String] as? CGWindowID ?? 0
            return windows[id] != nil && !floating.contains(id) ? id : nil
        }
        return nil
    }
}

extension TilingManager {
    /// Turns focus mode on or off for a specific window (used by Clean Space).
    func setFocusMode(_ on: Bool, window id: CGWindowID) {
        let displays = Display.current()
        guard let display = displays.first(where: { states[$0.key]?.contains(id) ?? false }) else { return }
        if on {
            guard focusMode[display.key] != id else { return }
            focusMode[display.key] = id
            states[display.key]?.show(id)
        } else {
            guard focusMode[display.key] == id else { return }
            focusMode[display.key] = nil
        }
        apply(displays)
        onStateChange?()
    }
}
