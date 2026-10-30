import AppKit
import PaneCore
import ServiceManagement

/// The menu bar item. The menu is rebuilt each time it opens so it always shows the
/// layout of the screen you are working on and the app in front.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let tiler: TilingManager
    private let settings = Settings.shared
    /// The app in front when the menu opened; the menu bar does not activate Pane, so this is the user's app.
    private var frontApp: NSRunningApplication?
    private var display: Display?

    init(tiler: TilingManager) {
        self.tiler = tiler
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon()
    }

    func updateIcon() {
        let paused = !settings.isTilingEnabled || tiler.isPausedForStageManager || !AX.isTrusted
        let image = NSImage(systemSymbolName: paused ? "rectangle.split.2x2" : "rectangle.split.2x2.fill",
                            accessibilityDescription: "Pane")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        frontApp = NSWorkspace.shared.frontmostApplication
        display = tiler.targetDisplay()
        menu.removeAllItems()

        menu.addItem(header(statusText))
        if !AX.isTrusted {
            menu.addItem(action("Grant Accessibility Access…", #selector(grantAccess)))
        }
        menu.addItem(toggle("Automatic Tiling", on: settings.isTilingEnabled, #selector(toggleTiling)))
        menu.addItem(.separator())

        if let display {
            let current = settings.layout(for: display)
            menu.addItem(header("Layout on This Screen"))
            for kind in LayoutKind.allCases {
                let unavailable = display.shape == .vertical && kind == .columns
                let entry = toggle(kind.title, on: current == kind, #selector(chooseLayout(_:)))
                entry.representedObject = kind.rawValue
                entry.isEnabled = !unavailable
                if unavailable { entry.toolTip = "Columns isn't available on a vertical monitor" }
                entry.indentationLevel = 1
                menu.addItem(entry)
            }

            let counts = NSMenu()
            let capacity = settings.capacity(for: display)
            let max = settings.maxCount(for: display)
            for n in 1...5 {
                let entry = toggle(n == 1 ? "1 Window" : "\(n) Windows", on: n == capacity, #selector(chooseCount(_:)))
                entry.tag = n
                entry.keyEquivalent = "\(n)"
                entry.keyEquivalentModifierMask = [.control, .option, .command]
                entry.isEnabled = n <= max
                if n > max { entry.toolTip = "\(current.title) holds up to \(max) windows on this screen" }
                counts.addItem(entry)
            }
            menu.addItem(submenu("Windows on This Screen: \(capacity)", counts))
        }

        let sizes = NSMenu()
        for (title, ratio) in [("Half", 0.5), ("60%", 0.6), ("Two-thirds", 2.0 / 3.0)] {
            let entry = toggle(title, on: abs(settings.mainRatio - ratio) < 0.01, #selector(chooseMainRatio(_:)))
            entry.representedObject = ratio
            sizes.addItem(entry)
        }
        menu.addItem(submenu("Main Window Size", sizes))

        let gaps = NSMenu()
        for gap in [0, 4, 8, 12, 16] {
            let entry = toggle("\(gap) pt", on: Int(settings.gap) == gap, #selector(chooseGap(_:)))
            entry.tag = gap
            gaps.addItem(entry)
        }
        menu.addItem(submenu("Spacing", gaps))
        menu.addItem(.separator())

        if let app = frontApp, let bundleID = app.bundleIdentifier, app.processIdentifier != getpid() {
            let name = app.localizedName ?? bundleID
            menu.addItem(toggle("Tile \(name)", on: !settings.excludedBundleIDs.contains(bundleID), #selector(toggleFrontApp)))
        }
        menu.addItem(action("Focus Mode", #selector(focusMode), key: "z", modifiers: [.control, .option]))
        menu.addItem(action("Retile", #selector(retile), key: "r", modifiers: [.control, .option]))
        menu.addItem(action("Forget Learned Window Sizes", #selector(forgetSizes)))
        menu.addItem(.separator())

        menu.addItem(toggle("Open at Login", on: SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(action("Keyboard Shortcuts…", #selector(showShortcuts)))
        menu.addItem(action("Quit Pane", #selector(quit), key: "q", modifiers: [.command]))
    }

    private var statusText: String {
        if !AX.isTrusted { return "Pane needs Accessibility access" }
        if !settings.isTilingEnabled { return "Automatic tiling is off" }
        if tiler.isPausedForStageManager { return "Paused while Stage Manager is on" }
        let count = tiler.tiledWindowCount
        let windows = "\(count) window\(count == 1 ? "" : "s")"
        if let display, tiler.isFocusMode(on: display) { return "Focus mode · \(windows)" }
        return "Tiling \(windows)"
    }

    // MARK: - Actions

    @objc private func grantAccess() {
        AX.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleTiling() { tiler.setTilingEnabled(!settings.isTilingEnabled); updateIcon() }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = LayoutKind(rawValue: raw) else { return }
        tiler.setLayout(kind, on: display)
    }

    @objc private func chooseCount(_ sender: NSMenuItem) { tiler.setCapacity(sender.tag, on: display) }

    @objc private func chooseMainRatio(_ sender: NSMenuItem) {
        guard let ratio = sender.representedObject as? Double else { return }
        settings.mainRatio = ratio
        tiler.relayout()
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        settings.gap = Double(sender.tag)
        tiler.relayout()
    }

    @objc private func toggleFrontApp() {
        guard let bundleID = frontApp?.bundleIdentifier else { return }
        tiler.setTiling(settings.excludedBundleIDs.contains(bundleID), forBundleID: bundleID)
    }

    @objc private func focusMode() { tiler.toggleFocusMode() }
    @objc private func retile() { tiler.retile() }
    @objc private func forgetSizes() { tiler.forgetLearnedSizes() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = """
        ⌃⌥ ← → ↑ ↓   Swap with the window in that direction (past the edge: next display)
        ⌃⌥ ↩          Make the active window primary
        ⌃⌥ ] / [       Activate the next / previous window
        ⌃⌥ ` / ⇧`     Show the next / previous window in this tile
        ⌃⌥ F           Float the active window, or tile it again
        ⌃⌥ Z           Focus mode
        ⌃⌥ R           Retile
        ⌃⌥⌘ 1–5       Tile up to N windows on this screen
        Drag a window onto another tile to swap them, or onto another screen to move it.
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Builders

    private func header(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, _ selector: Selector, key: String = "",
                        modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        return entry
    }

    private func toggle(_ title: String, on: Bool, _ selector: Selector) -> NSMenuItem {
        let entry = action(title, selector)
        entry.state = on ? .on : .off
        return entry
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }
}
