import AppKit
import JharokhaCore

/// What the window chrome (borders, grips, stack dots) and the modes need from the tiler.
extension TilingManager {
    struct ChromeTile {
        let screen: NSScreen
        /// AX coordinates.
        let rect: CGRect
        let windows: [CGWindowID]
        let showing: CGWindowID
        let isActive: Bool
        /// The focused window floats; its quick actions offer to tile it.
        var isFloating = false
    }

    /// The focused window as a chrome tile when it floats (by hand, or because its app is set to
    /// float) but could be tiled. Dialogs and pinned apps never qualify.
    func focusedFloatingTile() -> ChromeTile? {
        untiledFocus = nil
        guard canTile, let window = AX.focusedWindow(), window.pid != getpid(),
              floating.contains(window.id) || floatsByApp(window) || isLeftAlone(window.id), window.isTileable,
              let frame = window.frame,
              let display = Display.current().containing(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
        untiledFocus = window
        return ChromeTile(screen: display.screen, rect: frame, windows: [window.id], showing: window.id,
                          isActive: true, isFloating: true)
    }

    /// A window Jharokha tiles, or the focused floating one.
    func anyWindow(_ id: CGWindowID) -> AXWindow? {
        windows[id] ?? (untiledFocus?.id == id ? untiledFocus : nil)
    }

    /// Whether the app of a window is set to float.
    func appFloats(_ id: CGWindowID) -> Bool {
        guard let bundleID = appName(of: id)?.bundleID else { return false }
        return settings.excludedBundleIDs.contains(bundleID)
    }

    /// Tiles the floating window `id` (quick action).
    func tile(window id: CGWindowID) {
        guard let window = anyWindow(id) else { return }
        tile(window: window)
    }

    /// Sets a window's app to float or to tile; its windows follow the setting from now on.
    func setAppFloats(_ floats: Bool, of id: CGWindowID) {
        guard let bundleID = appName(of: id)?.bundleID else { return }
        setAppFloats(floats, bundleID: bundleID)
    }

    func setAppFloats(_ floats: Bool, bundleID: String) {
        setTiling(!floats, forBundleID: bundleID, announce: false)
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
        Toast.show(floats ? "\(name) floats now · its windows stay where you put them"
                          : "\(name) is tiled again")
    }

    /// Every tile on screen now, with the active one marked. Empty while tiling is paused.
    func chromeTiles() -> [ChromeTile] {
        guard canTile else { return [] }
        // Resolved like keyboard commands: an app focusing a helper window Jharokha doesn't tile
        // (Electron apps do) still has an active tile, so its grip doesn't vanish.
        let focused = context()?.window ?? AX.focusedWindow()?.id
        var result: [ChromeTile] = []
        for display in Display.current() {
            guard let state = states[display.key] else { continue }
            let zoomed = focusMode[display.key]
            // A lone window left where it opened has no tile to outline; it gets a floating grip.
            if leftAlone.contains(display.key) && zoomed == nil { continue }
            let rects = rects(for: display)
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

    func title(of id: CGWindowID) -> String { anyWindow(id)?.title ?? "" }

    /// Closes a window as its close button would; the app may ask to save first.
    func close(window id: CGWindowID) {
        guard let element = anyWindow(id)?.element, let button: AXUIElement = element.value(kAXCloseButtonAttribute) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Brings a window to the front without giving it focus.
    func raise(window id: CGWindowID) { windows[id]?.raise() }

    func minimize(window id: CGWindowID) {
        anyWindow(id)?.element.set(kAXMinimizedAttribute, kCFBooleanTrue)
    }

    /// Moves a window onto the tile under a point (AX coordinates), adding it to that tile's stack.
    func moveWindow(_ id: CGWindowID, toTileAt point: CGPoint) {
        let displays = Display.current()
        guard let destination = displays.containing(point),
              let target = LayoutEngine.tile(at: point, in: lookupRects(for: destination)) else { return }
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
    }

    /// ⌃⌥⇧F: never tile the active window's app again (it floats where you put it).
    func alwaysFloatActiveApp() {
        guard let pid = AX.focusedWindow()?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return }
        setAppFloats(true, bundleID: bundleID)
    }

    /// The tiled window under a point, if it is the frontmost window there.
    func tiledWindow(at point: CGPoint) -> CGWindowID? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Jharokha's own borders and No peek / Clean Space layers sit at the normal level too; skip them.
        for entry in info where entry[kCGWindowLayer as String] as? Int == 0
            && entry[kCGWindowOwnerPID as String] as? pid_t != getpid() {
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
        // While tiling is off or paused, the recorded tiles are stale; leave windows alone.
        guard canTile else { return }
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
