import AppKit
import PaneCore
import ServiceManagement

/// The menu bar item. The menu is rebuilt each time it opens so it always shows the
/// layout of the screen you are working on and the app in front.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let tiler: TilingManager
    private let modes: ModeController
    private let chrome: WindowChrome
    private let settings = Settings.shared
    /// The app in front when the menu opened; the menu bar does not activate Pane, so this is the user's app.
    private var frontApp: NSRunningApplication?
    /// A window picked by clicking its tile in the preview; Focus Mode and the app switch
    /// act on it, and it becomes active when the menu closes.
    private var selectedWindow: CGWindowID?
    private var selectionChanged = false
    /// Set by actions that already activate the selected window themselves.
    private var selectionHandled = false
    private weak var appRow: SwitchRowView?
    private weak var focusRow: SwitchRowView?
    private var appItemBundleID: String?
    private var display: Display?

    init(tiler: TilingManager, modes: ModeController, chrome: WindowChrome) {
        self.tiler = tiler
        self.modes = modes
        self.chrome = chrome
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon()
    }

    func updateIcon() {
        let paused = !settings.isTilingEnabled || tiler.isPausedForStageManager || !AX.isTrusted || !tiler.accessUsable
        item.button?.image = MenuIcons.statusGlyph(paused: paused)
        item.button?.setAccessibilityLabel(paused ? "Pane, paused" : "Pane")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        frontApp = NSWorkspace.shared.frontmostApplication
        display = tiler.targetDisplay()
        menu.removeAllItems()

        selectedWindow = nil
        selectionChanged = false
        selectionHandled = false
        let preview = NSMenuItem()
        let previewView = LayoutPreviewView(title: statusText, tiles: display.map(tiler.preview) ?? [],
                                            screenAspect: display.map { $0.rect.width / $0.rect.height } ?? 1.6)
        previewView.onSelect = { [weak self] window in
            guard let self else { return }
            self.selectedWindow = window
            self.selectionChanged = true
            self.updateSelectionItems()
        }
        previewView.onActivate = { [weak self] window in
            self?.selectionHandled = true
            self?.tiler.activate(window: window)
        }
        preview.view = previewView
        menu.addItem(preview)
        if !AX.isUsable {
            menu.addItem(action("Grant Accessibility Access…", #selector(grantAccess),
                                icon: "lock.shield", subtitle: "Pane needs it to move and resize windows"))
        }
        menu.addItem(.separator())
        menu.addItem(switchItem("Automatic Tiling", subtitle: Self.tilingSubtitle(settings.isTilingEnabled),
                                icon: MenuIcons.symbol("rectangle.split.2x2"), isOn: settings.isTilingEnabled) { [weak self] on in
            self?.tiler.setTilingEnabled(on)
            self?.updateIcon()
            return Self.tilingSubtitle(on)
        }.item)
        menu.addItem(action("Re-apply Tiling", #selector(retile), key: "r", modifiers: [.control, .option],
                            icon: "arrow.triangle.2.circlepath", subtitle: "Put every window back in its place"))
        menu.addItem(.separator())

        if let display {
            let shared = settings.appliesToAllScreens
            let picker = LayoutPickerRow(selected: settings.layout(for: display), shape: display.shape,
                                         ratio: CGFloat(settings.mainRatio))
            picker.onPick = { [weak self] kind in self?.tiler.setLayout(kind, on: self?.display) }
            let pickerItem = NSMenuItem()
            pickerItem.view = picker
            menu.addItem(header(shared ? "Layout" : "Layout on This Screen"))
            menu.addItem(pickerItem)

            // A shared count is offered up to what the roomiest screen holds.
            let max = shared ? Display.current().map(settings.maxCount).max() ?? settings.maxCount(for: display)
                             : settings.maxCount(for: display)
            let counts = CountPickerRow(selected: settings.capacity(for: display), maximum: max)
            counts.onPick = { [weak self] n in self?.tiler.setCapacity(n, on: self?.display) }
            let countItem = NSMenuItem()
            countItem.view = counts
            menu.addItem(countItem)
            menu.addItem(.separator())
        }

        if let app = frontApp, let bundleID = app.bundleIdentifier, app.processIdentifier != getpid() {
            let (item, row) = switchItem("", subtitle: "", icon: nil, isOn: false) { [weak self] on in
                guard let self, let bundleID = self.appItemBundleID else { return nil }
                self.tiler.setTiling(on, forBundleID: bundleID)
                return Self.appSubtitle(on)
            }
            configureAppRow(row, name: app.localizedName ?? bundleID, bundleID: bundleID, icon: app.icon)
            appRow = row
            menu.addItem(item)
        }
        let focusOn = display.map(tiler.isFocusMode) ?? false
        let (focusItem, row) = switchItem("Focus Mode", subtitle: Self.focusSubtitle(focusOn, app: nil),
                                          icon: MenuIcons.symbol("arrow.up.left.and.arrow.down.right"), isOn: focusOn) { [weak self] _ in
            guard let self else { return nil }
            self.selectionHandled = true
            if let window = self.selectedWindow {
                self.tiler.toggleFocusMode(window: window)
            } else {
                self.tiler.toggleFocusMode()
            }
            // Show the real outcome: a window may not be tiled, or the zoom may have moved.
            let on = self.display.map(self.tiler.isFocusMode) ?? false
            self.focusRow?.isOn = on
            return Self.focusSubtitle(on, app: nil)
        }
        focusRow = row
        menu.addItem(focusItem)

        let noPeekOn = modes.noPeek.isOn
        let dimRow = SliderRowView(title: "Dim", value: settings.noPeekDim, range: 0.1...0.9) { "\(Int(($0 * 100).rounded()))%" }
        dimRow.onChange = { [weak self] value in
            self?.settings.noPeekDim = value
            self?.modes.update()
        }
        let dimItem = NSMenuItem()
        dimItem.view = dimRow
        dimItem.isHidden = !noPeekOn
        menu.addItem(switchItem("No Peek", subtitle: Self.noPeekSubtitle(noPeekOn),
                                icon: MenuIcons.symbol("circle.lefthalf.filled"), isOn: noPeekOn) { [weak self, weak dimItem] _ in
            guard let self else { return nil }
            self.modes.toggleNoPeek()
            dimItem?.isHidden = !self.modes.noPeek.isOn
            return Self.noPeekSubtitle(self.modes.noPeek.isOn)
        }.item)
        menu.addItem(dimItem)

        let cleanOn = modes.cleanSpace.isOn
        menu.addItem(switchItem("Privacy Mode", subtitle: Self.cleanSpaceSubtitle(cleanOn),
                                icon: MenuIcons.symbol("eye.slash"), isOn: cleanOn) { [weak self] _ in
            guard let self else { return nil }
            // Act after the menu closes, so the window to present is the user's, not the menu.
            menu.cancelTracking()
            DispatchQueue.main.async { self.modes.toggleCleanSpace() }
            return Self.cleanSpaceSubtitle(!cleanOn)
        }.item)
        menu.addItem(.separator())

        if let display, tiler.hasCustomSizes(on: display) {
            menu.addItem(action("Reset Window Sizes", #selector(resetSizes), key: "0", modifiers: [.control, .option],
                                icon: "arrow.up.left.and.down.right.magnifyingglass", subtitle: "Back to equal shares and your main size"))
            menu.addItem(.separator())
        }

        menu.addItem(action("Settings…", #selector(showSettings), key: ",", modifiers: [.command], icon: "gearshape",
                            subtitle: "Sizes, spacing, highlight, shortcuts and more"))
        menu.addItem(action("Quit Pane", #selector(quit), key: "q", modifiers: [.command], icon: "xmark.circle"))
    }

    private static func tilingSubtitle(_ on: Bool) -> String {
        on ? "Place windows as they open" : "Off: windows stay where you put them"
    }

    private static func appSubtitle(_ on: Bool) -> String {
        on ? "Its windows are part of the layout" : "Its windows are left where you put them"
    }

    private static func focusSubtitle(_ on: Bool, app: String?) -> String {
        if on { return "On: switch off to put every window back\(ShortcutStore.shared.hint(.focusMode))" }
        return "Fill the screen with \(app ?? "the active window")\(ShortcutStore.shared.hint(.focusMode))"
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

    /// Closing the menu after picking a tile makes that window active. Actions run after
    /// the menu closes, so wait a moment to let one that handles the selection itself claim it.
    func menuDidClose(_ menu: NSMenu) {
        guard selectionChanged, let window = selectedWindow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, !self.selectionHandled, self.selectedWindow == window else { return }
            self.tiler.activate(window: window)
        }
    }

    private func updateSelectionItems() {
        guard let window = selectedWindow, let app = tiler.appName(of: window) else { return }
        if let appRow, let bundleID = app.bundleID {
            configureAppRow(appRow, name: app.name, bundleID: bundleID, icon: tiler.appIcon(of: window))
        }
        if let focusRow, !focusRow.isOn {
            focusRow.update(title: "Focus Mode", subtitle: Self.focusSubtitle(false, app: app.name),
                            icon: MenuIcons.symbol("arrow.up.left.and.arrow.down.right"), isOn: false)
        }
    }

    private func configureAppRow(_ row: SwitchRowView, name: String, bundleID: String, icon: NSImage?) {
        let tiled = !settings.excludedBundleIDs.contains(bundleID)
        appItemBundleID = bundleID
        let small = icon.map { icon -> NSImage in
            let small = icon.copy() as! NSImage
            small.size = NSSize(width: 16, height: 16)
            return small
        }
        row.update(title: "Include \(name) in Tiling", subtitle: Self.appSubtitle(tiled), icon: small, isOn: tiled)
    }
    @objc private func retile() { tiler.retile() }
    @objc private func showSettings() { SettingsWindowController.shared.show(tab: .general) }
    @objc private func resetSizes() { tiler.resetSizes(on: display) }

    private static func noPeekSubtitle(_ on: Bool) -> String {
        on ? "On: other windows are faded\(ShortcutStore.shared.hint(.noPeek))" : "Fade every window except the active one\(ShortcutStore.shared.hint(.noPeek))"
    }

    private static func cleanSpaceSubtitle(_ on: Bool) -> String {
        on ? "On: switch off to bring everything back\(ShortcutStore.shared.hint(.cleanSpace))" : "Share one window; the rest show as app cards\(ShortcutStore.shared.hint(.cleanSpace))"
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

    /// An on/off setting shown as a switch; it acts immediately and keeps the menu open.
    private func switchItem(_ title: String, subtitle: String?, icon: NSImage?, isOn: Bool,
                            _ onChange: @escaping (Bool) -> String?) -> (item: NSMenuItem, row: SwitchRowView) {
        let row = SwitchRowView(title: title, subtitle: subtitle, icon: icon, isOn: isOn)
        row.onChange = onChange
        let item = NSMenuItem()
        item.view = row
        return (item, row)
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }
}
