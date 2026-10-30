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
        let paused = !settings.isTilingEnabled || tiler.isPausedForStageManager || !AX.isTrusted || !tiler.accessUsable
        let image = NSImage(systemSymbolName: paused ? "rectangle.split.2x2" : "rectangle.split.2x2.fill",
                            accessibilityDescription: "Pane")
        image?.isTemplate = true
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        frontApp = NSWorkspace.shared.frontmostApplication
        display = tiler.targetDisplay()
        menu.removeAllItems()

        let preview = NSMenuItem()
        preview.view = LayoutPreviewView(title: statusText, tiles: display.map(tiler.preview) ?? [],
                                         screenAspect: display.map { $0.rect.width / $0.rect.height } ?? 1.6)
        menu.addItem(preview)
        if !AX.isUsable {
            menu.addItem(action("Grant Accessibility Access…", #selector(grantAccess),
                                icon: "lock.shield", subtitle: "Pane needs it to move and resize windows"))
        }
        menu.addItem(.separator())
        menu.addItem(toggle("Automatic Tiling", on: settings.isTilingEnabled, #selector(toggleTiling),
                            icon: "rectangle.split.2x2", subtitle: "Place windows as they open"))
        menu.addItem(action("Re-apply Tiling", #selector(retile), key: "r", modifiers: [.control, .option],
                            icon: "arrow.triangle.2.circlepath", subtitle: "Put every window back in its place"))
        menu.addItem(.separator())

        let ratio = CGFloat(settings.mainRatio)
        if let display {
            let current = settings.layout(for: display)
            let shared = settings.appliesToAllScreens
            let capacity = settings.capacity(for: display)
            menu.addItem(header(shared ? "Layout" : "Layout on This Screen"))
            for kind in LayoutKind.allCases {
                let unavailable = display.shape == .vertical && kind == .columns
                let entry = toggle(kind.title, on: current == kind, #selector(chooseLayout(_:)))
                entry.image = MenuIcons.layout(kind, count: MenuIcons.characteristicCount(of: kind, shape: display.shape),
                                               ratio: ratio, shape: display.shape)
                entry.subtitle = unavailable ? "Not available on a vertical monitor" : Self.summary(of: kind)
                entry.representedObject = kind.rawValue
                entry.isEnabled = !unavailable
                menu.addItem(entry)
            }
            menu.addItem(.separator())

            let counts = NSMenu()
            // A shared count is offered up to what the roomiest screen holds.
            let max = shared ? Display.current().map(settings.maxCount).max() ?? settings.maxCount(for: display)
                             : settings.maxCount(for: display)
            for n in 1...5 {
                let entry = toggle(n == 1 ? "1 Window" : "\(n) Windows", on: n == capacity, #selector(chooseCount(_:)))
                entry.image = MenuIcons.layout(current, count: min(n, LayoutEngine.maxCount(kind: current, shape: display.shape, size: display.rect.size)),
                                               ratio: ratio, shape: display.shape)
                entry.tag = n
                entry.keyEquivalent = "\(n)"
                entry.keyEquivalentModifierMask = [.control, .option, .command]
                entry.isEnabled = n <= max
                if n > max { entry.subtitle = "\(current.title) holds up to \(max) here" }
                counts.addItem(entry)
            }
            let countItem = submenu(shared ? "Windows per Screen: \(capacity)" : "Windows on This Screen: \(capacity)", counts)
            countItem.image = MenuIcons.layout(current, count: capacity, ratio: ratio, shape: display.shape)
            countItem.subtitle = "More windows than this stack in the active tile"
            menu.addItem(countItem)

            let sizes = NSMenu()
            for (title, value) in [("Half", 0.5), ("60%", 0.6), ("Two-thirds", 2.0 / 3.0)] {
                let entry = toggle(title, on: abs(settings.mainRatio - value) < 0.01, #selector(chooseMainRatio(_:)))
                entry.image = MenuIcons.layout(current == .rows ? .rows : .columns, count: 2, ratio: value, shape: display.shape)
                entry.representedObject = value
                sizes.addItem(entry)
            }
            let sizeItem = submenu("Main Window Size", sizes)
            sizeItem.image = MenuIcons.layout(current == .rows ? .rows : .columns, count: 2, ratio: ratio, shape: display.shape)
            sizeItem.subtitle = "How much room the first window gets"
            menu.addItem(sizeItem)
        }

        let gaps = NSMenu()
        for gap in [0, 4, 8, 12, 16] {
            let entry = toggle(gap == 0 ? "None" : "\(gap) pt", on: Int(settings.gap) == gap, #selector(chooseGap(_:)))
            entry.image = MenuIcons.spacing(CGFloat(gap))
            entry.tag = gap
            gaps.addItem(entry)
        }
        let gapItem = submenu("Spacing: \(Int(settings.gap)) pt", gaps)
        gapItem.image = MenuIcons.spacing(CGFloat(settings.gap))
        gapItem.subtitle = "Gap between windows and screen edges"
        menu.addItem(gapItem)
        menu.addItem(toggle("Apply Changes to All Screens", on: settings.appliesToAllScreens, #selector(toggleAllScreens),
                            icon: "display.2", subtitle: settings.appliesToAllScreens
                                ? "Layout and count are shared by every screen"
                                : "Each screen keeps its own layout and count"))
        menu.addItem(.separator())

        if let app = frontApp, let bundleID = app.bundleIdentifier, app.processIdentifier != getpid() {
            let name = app.localizedName ?? bundleID
            let tiled = !settings.excludedBundleIDs.contains(bundleID)
            let entry = toggle("Tile \(name)", on: tiled, #selector(toggleFrontApp))
            entry.image = app.icon.map { icon in
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                return small
            }
            entry.subtitle = tiled ? "Its windows join the layout" : "Its windows stay where you put them"
            menu.addItem(entry)
        }
        menu.addItem(action("Focus Mode", #selector(focusMode), key: "z", modifiers: [.control, .option],
                            icon: "arrow.up.left.and.arrow.down.right", subtitle: "Fill the screen with the active window"))
        menu.addItem(action("Forget Learned Window Sizes", #selector(forgetSizes),
                            icon: "arrow.counterclockwise", subtitle: "Re-learn how small each app can get"))
        menu.addItem(.separator())

        menu.addItem(toggle("Open at Login", on: SMAppService.mainApp.status == .enabled, #selector(toggleLogin),
                            icon: "power"))
        menu.addItem(action("Keyboard Shortcuts…", #selector(showShortcuts), icon: "keyboard"))
        menu.addItem(action("Quit Pane", #selector(quit), key: "q", modifiers: [.command], icon: "xmark.circle"))
    }

    private static func summary(of kind: LayoutKind) -> String {
        switch kind {
        case .grid: return "Each new window takes half the newest space"
        case .columns: return "Side by side, full height"
        case .rows: return "Stacked top to bottom, full width"
        case .side: return "One large window, the rest in a column"
        }
    }

    private var statusText: String {
        if !AX.isTrusted { return "Pane needs Accessibility access" }
        if !tiler.accessUsable { return "Accessibility access isn't working: turn Pane off and on in System Settings" }
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

    @objc private func toggleAllScreens() {
        settings.appliesToAllScreens.toggle()
        tiler.relayout()
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
        ⌃⌥ R           Re-apply tiling (puts every window back, re-attaches to all apps)
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
                        modifiers: NSEvent.ModifierFlags = [], icon: String? = nil, subtitle: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.keyEquivalentModifierMask = modifiers
        entry.target = self
        entry.image = icon.flatMap(MenuIcons.symbol)
        entry.subtitle = subtitle
        return entry
    }

    private func toggle(_ title: String, on: Bool, _ selector: Selector,
                        icon: String? = nil, subtitle: String? = nil) -> NSMenuItem {
        let entry = action(title, selector, icon: icon, subtitle: subtitle)
        entry.state = on ? .on : .off
        return entry
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }
}
