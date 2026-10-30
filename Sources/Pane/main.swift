import AppKit
import Carbon

/// No peek and Clean Space, kept in step with the active window.
final class ModeController {
    let noPeek = NoPeek()
    let cleanSpace = CleanSpace()
    private let tiler: TilingManager
    /// The window Clean Space put on its plain screen (zoomed, if it is tiled).
    private var cleanWindow: CGWindowID?
    var onChange: (() -> Void)?

    init(tiler: TilingManager) {
        self.tiler = tiler
        cleanSpace.onAutomaticEnd = { [weak self] in self?.endCleanSpace(announce: false) }
        cleanSpace.onToggle = { [weak self] id in self?.toggleShown(id) }
    }

    func toggleNoPeek() {
        noPeek.setOn(!noPeek.isOn, below: AX.focusedWindow()?.id)
        Toast.show(noPeek.isOn ? "No peek\(ShortcutStore.shared.hint(.noPeek, "to stop"))" : "No peek off")
        onChange?()
    }

    func toggleCleanSpace() {
        if cleanSpace.isOn {
            endCleanSpace(announce: true)
            return
        }
        let window = AX.focusedWindow()
        let screen: NSScreen?
        if let frame = window?.frame {
            let height = NSScreen.screens.first?.frame.maxY ?? 0
            let center = NSPoint(x: frame.midX, y: height - frame.midY)
            screen = NSScreen.screens.first { $0.frame.contains(center) }
        } else {
            // No active window: the screen under the pointer becomes plain.
            screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        }
        guard let screen = screen ?? NSScreen.main else { return }
        cleanWindow = window?.id
        // At first only the window you're in is shown; each other tile gets an eye to show it too.
        shown = window.map { [$0.id] } ?? []
        if let id = window?.id, Settings.shared.cleanSpaceFillsScreen { tiler.setFocusMode(true, window: id) }
        cleanSpace.start(on: screen)
        update()
        Toast.show("Privacy Mode\(ShortcutStore.shared.hint(.cleanSpace, "to bring everything back"))")
        onChange?()
    }

    private func endCleanSpace(announce: Bool) {
        cleanSpace.stop()
        if let id = cleanWindow { tiler.setFocusMode(false, window: id) }
        cleanWindow = nil
        shown = []
        if announce { Toast.show("Privacy Mode off") }
        onChange?()
    }

    /// Shows a hidden window (it comes forward with focus) or hides a shown one. Showing
    /// one never hides another; only Hide does.
    private func toggleShown(_ id: CGWindowID) {
        if let index = shown.firstIndex(of: id) {
            shown.remove(at: index)
            // Keystrokes must not keep going to a window that's now covered.
            if AX.focusedWindow()?.id == id, let next = shown.last { tiler.activate(window: next) }
        } else {
            shown.append(id)
            tiler.activate(window: id)
        }
        update()
    }

    /// Called after every layout pass and focus change.
    func update() {
        let focused = AX.focusedWindow()
        noPeek.update(below: focused?.id)
        guard cleanSpace.isOn, let screen = cleanSpace.screen else { return }

        let tiles = tiler.chromeTiles().filter { $0.screen == screen }
        let tiled = Set(tiles.flatMap(\.windows))
        let others = Self.untiledWindows(on: screen, excluding: tiled)
        let present = tiled.union(others.map(\.id))
        shown.removeAll { !present.contains($0) }

        // Every tile without a shown window is covered by a card; so is any window Pane
        // doesn't tile, so nothing on that screen slips through.
        var cards: [CleanSpace.Card] = tiles.filter { tile in !tile.windows.contains { shown.contains($0) } }.map { tile in
            CleanSpace.Card(window: tile.showing, rect: tile.rect, icon: tiler.appIcon(of: tile.showing),
                            name: tiler.appName(of: tile.showing)?.name ?? "Window", hiddenCount: tile.windows.count - 1)
        }
        cards += others.filter { !shown.contains($0.id) }.map { window in
            CleanSpace.Card(window: window.id, rect: window.frame, icon: window.icon, name: window.name, hiddenCount: 0)
        }
        cleanSpace.setCards(cards)

        let shownTiles = tiles.compactMap { tile in tile.windows.first { shown.contains($0) }.map { ($0, tile.rect) } }
        let shownOthers = others.filter { shown.contains($0.id) }.map { ($0.id, $0.frame) }
        cleanSpace.setPills(shownTiles + shownOthers)
    }

    /// On-screen windows of other apps on a screen that Pane doesn't tile (floating,
    /// excluded apps, dialogs), with their frames in AX coordinates.
    private static func untiledWindows(on screen: NSScreen, excluding tiled: Set<CGWindowID>)
        -> [(id: CGWindowID, frame: CGRect, icon: NSImage?, name: String)] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY
        let axScreen = CGRect(x: screen.frame.minX, y: top, width: screen.frame.width, height: screen.frame.height)
        return info.compactMap { entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let id = entry[kCGWindowNumber as String] as? CGWindowID, !tiled.contains(id),
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let frame = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            guard frame.width > 40, frame.height > 40, axScreen.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return (id, frame, app?.icon, app?.localizedName ?? "Window")
        }
    }

    /// Windows shown in Privacy Mode, most recently shown last.
    private var shown: [CGWindowID] = []
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tiler = TilingManager()
    private lazy var chrome = WindowChrome(tiler: tiler)
    private lazy var modes = ModeController(tiler: tiler)
    private let tabView = TabViewSwitcher()
    private var menu: StatusMenu?
    private var trustTimer: Timer?
    private var lastPinPress = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(tiler: tiler, modes: modes, chrome: chrome)
        tiler.onStateChange = { [weak self] in self?.menu?.updateIcon() }
        tiler.onLayoutChange = { [weak self] in
            self?.chrome.update()
            self?.modes.update()
        }
        tiler.onDragChange = { [weak self] dragging in self?.chrome.setHidden(dragging) }
        modes.onChange = { [weak self] in self?.menu?.updateIcon() }
        SettingsWindowController.shared.onShortcutsChanged = { [weak self] in self?.registerShortcuts() }
        SettingsWindowController.shared.onLayoutSettingsChanged = { [weak self] in self?.tiler.relayout() }
        SettingsWindowController.shared.onRearrange = { [weak self] in self?.tiler.retile() }
        SettingsWindowController.shared.onForgetSizes = { [weak self] in self?.tiler.forgetLearnedSizes() }
        SettingsWindowController.shared.onSettingsChanged = { [weak self] in
            self?.chrome.update()
            self?.modes.update()
        }
        registerShortcuts()
        log.info("Launch: trusted \(AX.isTrusted), probe \(AX.probe().rawValue), frontmost \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public)")

        if AX.isUsable {
            tiler.start()
        } else {
            AX.requestTrust()
            // Start as soon as the user grants access in System Settings.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard let self, AX.isUsable else { return }
                timer.invalidate()
                self.trustTimer = nil
                self.tiler.start()
                self.menu?.updateIcon()
            }
        }
    }

    func registerShortcuts() {
        HotKeys.shared.apply(ShortcutStore.shared) { [weak self] action in self?.perform(action) }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .swapLeft: tiler.swap(.left)
        case .swapRight: tiler.swap(.right)
        case .swapUp: tiler.swap(.up)
        case .swapDown: tiler.swap(.down)
        case .makePrimary: tiler.makePrimary()
        case .nextWindow: tiler.activate(step: 1)
        case .previousWindow: tiler.activate(step: -1)
        case .nextInTile: tiler.cycleStack(step: 1)
        case .previousInTile: tiler.cycleStack(step: -1)
        case .stackDown: tiler.cycleStack(step: 1)
        case .stackUp: tiler.cycleStack(step: -1)
        case .tabView: tabView.advance(backward: false)
        case .tabViewBackward: tabView.advance(backward: true)
        case .grow: tiler.resizeActive(grow: true)
        case .shrink: tiler.resizeActive(grow: false)
        case .resetSizes: tiler.resetSizes()
        case .float: tiler.toggleFloat()
        case .alwaysFloat: tiler.alwaysFloatActiveApp()
        case .pinApp:
            // One press, one change: a bounce would unpin straight away (and restart the Dock twice).
            guard Date().timeIntervalSince(lastPinPress) > 1 else { return }
            lastPinPress = Date()
            tiler.togglePin()
        case .focusMode: tiler.toggleFocusMode()
        case .noPeek: modes.toggleNoPeek()
        case .cleanSpace: modes.toggleCleanSpace()
        case .retile: tiler.retile()
        case .tile1: tiler.setCapacity(1)
        case .tile2: tiler.setCapacity(2)
        case .tile3: tiler.setCapacity(3)
        case .tile4: tiler.setCapacity(4)
        case .tile5: tiler.setCapacity(5)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
