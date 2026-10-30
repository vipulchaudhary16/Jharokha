import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tiler = TilingManager()
    private var menu: StatusMenu?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = StatusMenu(tiler: tiler)
        tiler.onStateChange = { [weak self] in self?.menu?.updateIcon() }
        registerShortcuts()

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

    private func registerShortcuts() {
        let hotKeys = HotKeys.shared
        hotKeys.register(.left) { [tiler] in tiler.swap(.left) }
        hotKeys.register(.right) { [tiler] in tiler.swap(.right) }
        hotKeys.register(.up) { [tiler] in tiler.swap(.up) }
        hotKeys.register(.down) { [tiler] in tiler.swap(.down) }
        hotKeys.register(.returnKey) { [tiler] in tiler.makePrimary() }
        hotKeys.register(.rightBracket) { [tiler] in tiler.activate(step: 1) }
        hotKeys.register(.leftBracket) { [tiler] in tiler.activate(step: -1) }
        hotKeys.register(.grave) { [tiler] in tiler.cycleStack(step: 1) }
        hotKeys.register(.grave, modifiers: HotKeys.prefix | UInt32(shiftKey)) { [tiler] in tiler.cycleStack(step: -1) }
        hotKeys.register(.f) { [tiler] in tiler.toggleFloat() }
        hotKeys.register(.z) { [tiler] in tiler.toggleFocusMode() }
        hotKeys.register(.r) { [tiler] in tiler.retile() }
        let counts: [(HotKeys.Key, Int)] = [(.one, 1), (.two, 2), (.three, 3), (.four, 4), (.five, 5)]
        for (key, count) in counts {
            hotKeys.register(key, modifiers: HotKeys.prefix | UInt32(cmdKey)) { [tiler] in tiler.setCapacity(count) }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
