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
        arrangement = nil
        if let id = window?.id, Settings.shared.cleanSpaceFillsScreen { tiler.setFocusMode(true, window: id) }
        cleanSpace.start(on: screen, below: window?.id)
        update()
        Toast.show("Privacy Mode\(ShortcutStore.shared.hint(.cleanSpace, "to bring everything back"))")
        onChange?()
    }

    private func endCleanSpace(announce: Bool) {
        cleanSpace.stop()
        if let id = cleanWindow { tiler.setFocusMode(false, window: id) }
        cleanWindow = nil
        shown = []
        arrangement = nil
        if announce { Toast.show("Privacy Mode off") }
        onChange?()
    }

    /// Shows a hidden window (it comes forward with focus) or hides a shown one.
    private func toggleShown(_ id: CGWindowID) {
        if let index = shown.firstIndex(of: id) {
            shown.remove(at: index)
            arrangement = nil
            // Keystrokes must not keep going to a window that's now hidden.
            if AX.focusedWindow()?.id == id, let next = shown.last {
                tiler.activate(window: next)
            }
            update()
        } else {
            shown.append(id)
            arrangement = nil
            tiler.activate(window: id)
            update()
        }
    }

    /// Called after every layout pass and focus change.
    func update() {
        let focused = AX.focusedWindow()
        noPeek.update(below: focused?.id)
        guard cleanSpace.isOn, let screen = cleanSpace.screen else { return }

        let tiles = tiler.chromeTiles().filter { $0.screen == screen }
        let onScreen = Set(tiles.flatMap(\.windows))
        shown.removeAll { !onScreen.contains($0) && $0 != cleanWindow }
        // Bringing a hidden window forward (⌘-Tab, the Dock) shows it.
        if let id = focused?.id, onScreen.contains(id), !shown.contains(id) { shown.append(id) }

        // Shown windows above the backdrop, hidden ones below: raise the shown windows
        // (the active one last, so it stays in front), then slide the backdrop under them.
        let signature = shown.map(String.init).joined(separator: ",") + "|\(focused?.id ?? 0)"
        if signature != arrangement {
            arrangement = signature
            let order = shown.filter { $0 != focused?.id } + shown.filter { $0 == focused?.id }
            order.forEach { tiler.raise(window: $0) }
            cleanSpace.order(below: order.first)
        }

        let isShown: (TilingManager.ChromeTile) -> Bool = { tile in tile.windows.contains { self.shown.contains($0) } }
        cleanSpace.setCards(tiles.filter { !isShown($0) }.map { tile in
            CleanSpace.Card(window: tile.showing, rect: tile.rect, icon: tiler.appIcon(of: tile.showing),
                            name: tiler.appName(of: tile.showing)?.name ?? "Window", hiddenCount: tile.windows.count - 1)
        })
        cleanSpace.setEyes(tiles.map { tile in
            let window = tile.windows.first { shown.contains($0) } ?? tile.showing
            return (window, tile.rect, isShown(tile))
        })
    }

    /// Windows shown above the Privacy Mode backdrop, most recently shown last.
    private var shown: [CGWindowID] = []
    /// The last z-order arrangement applied, to avoid re-raising windows on every update.
    private var arrangement: String?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tiler = TilingManager()
    private lazy var chrome = WindowChrome(tiler: tiler)
    private lazy var modes = ModeController(tiler: tiler)
    private let tabView = TabViewSwitcher()
    private var menu: StatusMenu?
    private var trustTimer: Timer?

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
        case .tabView: tabView.advance(backward: false)
        case .tabViewBackward: tabView.advance(backward: true)
        case .grow: tiler.resizeActive(grow: true)
        case .shrink: tiler.resizeActive(grow: false)
        case .resetSizes: tiler.resetSizes()
        case .float: tiler.toggleFloat()
        case .alwaysFloat: tiler.alwaysFloatActiveApp()
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
