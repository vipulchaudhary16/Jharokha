import AppKit

/// Tab View (⌃⌥⇥): every window, laid out screen by screen as it sits on the desktop.
/// Hold ⌃⌥ and press ⇥ / ⇧⇥ to move, arrows move spatially, release them (or press ↩, or click)
/// to switch, ⎋ to cancel. Window titles are read only while it is open, to label the tiles.
final class TabViewSwitcher {
    struct Item {
        let window: AXWindow
        let frame: CGRect          // AX coordinates
        let screenIndex: Int
        let icon: NSImage?
        let appName: String
        let title: String
        let isMinimized: Bool
    }

    private var panel: NSPanel?
    private var view: TabViewView?
    private var items: [Item] = []
    private var selected = 0
    private var monitors: [Any] = []
    private var previous: AXWindow?
    /// The modifiers held while the switcher is open (⌥ by default); releasing them switches.
    /// A shortcut without ⌃ ⌥ or ⌘ to hold keeps it open until ↩, a click or ⎋.
    private var hold: NSEvent.ModifierFlags = [.option]

    var isOpen: Bool { panel != nil }

    /// ⌃⌥⇥: opens with the previous window selected, or moves the selection while open.
    func advance(backward: Bool) {
        if isOpen {
            move(by: backward ? -1 : 1)
            return
        }
        items = Self.collect()
        guard !items.isEmpty else { return }
        previous = AX.focusedWindow()
        hold = (ShortcutStore.shared.shortcut(for: .tabView)?.cocoaModifiers ?? [.option])
            .intersection([.control, .option, .command])
        // Items are front to back, so the window used before this one comes second.
        selected = items.count > 1 ? (backward ? items.count - 1 : 1) : 0
        // A quick press already released: just switch back, like ⌘⇥.
        guard hold.isEmpty || NSEvent.modifierFlags.isSuperset(of: hold) else {
            choose()
            return
        }
        show()
    }

    private static func collect() -> [Item] {
        let order = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var zIndex: [CGWindowID: Int] = [:]
        for (index, entry) in order.enumerated() {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID { zIndex[id] = index }
        }
        let screens = NSScreen.screens
        let primaryTop = screens.first?.frame.maxY ?? 0
        func screenIndex(of frame: CGRect) -> Int {
            let center = CGPoint(x: frame.midX, y: primaryTop - frame.midY)
            return screens.firstIndex { $0.frame.contains(center) } ?? 0
        }
        var items: [Item] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            for window in AX.windows(of: app) {
                let element = window.element
                guard element.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole,
                      let frame = window.frame else { continue }
                let minimized = window.isMinimized
                // Windows on other Spaces are neither on screen nor minimized; leave them out.
                guard minimized || zIndex[window.id] != nil else { continue }
                items.append(Item(window: window, frame: frame, screenIndex: screenIndex(of: frame), icon: app.icon,
                                  appName: app.localizedName ?? "App", title: window.title, isMinimized: minimized))
            }
        }
        return items.sorted { (zIndex[$0.window.id] ?? .max) < (zIndex[$1.window.id] ?? .max) }
    }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let view = TabViewView(items: items)
        view.selected = selected
        view.onClick = { [weak self] index in
            self?.selected = index
            self?.choose()
        }
        let size = view.preferredSize(maxWidth: screen.visibleFrame.width * 0.85)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = view
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        self.view = view

        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged], handler: { [weak self] event in
            self?.handle(event) ?? event
        }) { monitors.append(local) }
        // If ⌥ is released while another app still has the keyboard, catch it too.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            _ = self?.handle(event)
        }) { monitors.append(global) }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            if !hold.isEmpty && !event.modifierFlags.isSuperset(of: hold) { choose() }
            return nil
        case .keyDown:
            switch event.keyCode {
            case 53: cancel()                                  // ⎋
            case 36, 76: choose()                              // ↩
            case 48: move(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            case 123: moveSpatially(dx: -1, dy: 0)
            case 124: moveSpatially(dx: 1, dy: 0)
            case 125: moveSpatially(dx: 0, dy: 1)
            case 126: moveSpatially(dx: 0, dy: -1)
            default: break
            }
            return nil
        default:
            return event
        }
    }

    private func move(by step: Int) {
        guard !items.isEmpty else { return }
        selected = ((selected + step) % items.count + items.count) % items.count
        view?.selected = selected
    }

    /// The nearest window in a direction, on any screen, by the tiles' positions in the switcher.
    private func moveSpatially(dx: CGFloat, dy: CGFloat) {
        guard let view, let current = view.tileRects[safe: selected] else { return }
        let candidates = view.tileRects.enumerated().filter { index, rect in
            guard index != selected else { return false }
            let vx = rect.midX - current.midX, vy = rect.midY - current.midY
            return dx != 0 ? vx * dx > 4 : vy * dy > 4
        }
        guard let best = candidates.min(by: { a, b in
            func cost(_ rect: CGRect) -> CGFloat {
                let vx = rect.midX - current.midX, vy = rect.midY - current.midY
                return dx != 0 ? abs(vx) + abs(vy) * 2 : abs(vy) + abs(vx) * 2
            }
            return cost(a.element) < cost(b.element)
        }) else { return }
        selected = best.offset
        view.selected = selected
    }

    private func choose() {
        guard items.indices.contains(selected) else { close(); return }
        let item = items[selected]
        close()
        if item.isMinimized { item.window.element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
        item.window.focus()
    }

    private func cancel() {
        let previous = self.previous
        close()
        previous?.focus()
    }

    private func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
        view = nil
    }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Each screen as a rounded box holding its windows at their real positions (scaled),
/// front windows drawn on top; minimized windows in a row below their screen.
final class TabViewView: NSView {
    var selected = 0 { didSet { needsDisplay = true } }
    var onClick: ((Int) -> Void)?
    private(set) var tileRects: [CGRect] = []

    private let items: [TabViewSwitcher.Item]
    private var screenBoxes: [(screen: NSScreen, box: CGRect, scale: CGFloat)] = []
    private let padding: CGFloat = 24, screenHeight: CGFloat = 300, minimizedHeight: CGFloat = 64

    init(items: [TabViewSwitcher.Item]) {
        self.items = items
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        var height = screenHeight
        var widths = screens.map { screenHeight * $0.frame.width / $0.frame.height }
        let total = widths.reduce(0, +) + padding * CGFloat(screens.count + 1)
        if total > maxWidth {
            let factor = (maxWidth - padding * CGFloat(screens.count + 1)) / (total - padding * CGFloat(screens.count + 1))
            widths = widths.map { $0 * factor }
            height *= factor
        }
        let hasMinimized = items.contains(where: \.isMinimized)
        var x = padding
        screenBoxes = zip(screens, widths).map { screen, width in
            defer { x += width + padding }
            return (screen, CGRect(x: x, y: padding + 22, width: width, height: height), width / screen.frame.width)
        }
        layoutTiles()
        return NSSize(width: x, height: padding + 22 + height + (hasMinimized ? minimizedHeight + 12 : 0) + padding + 18)
    }

    private func layoutTiles() {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var minimizedCount: [Int: Int] = [:]
        tileRects = items.map { item in
            let screen = NSScreen.screens[safe: item.screenIndex] ?? NSScreen.screens[0]
            guard let entry = screenBoxes.first(where: { $0.screen == screen }) else { return .zero }
            if item.isMinimized {
                let n = minimizedCount[item.screenIndex, default: 0]
                minimizedCount[item.screenIndex] = n + 1
                return CGRect(x: entry.box.minX + CGFloat(n) * 132, y: entry.box.maxY + 12, width: 124, height: minimizedHeight)
            }
            // AX frame → position within the screen box.
            let top = primaryTop - screen.frame.maxY
            let x = (item.frame.minX - screen.frame.minX) * entry.scale
            let y = (item.frame.minY - top) * entry.scale
            return CGRect(x: entry.box.minX + x, y: entry.box.minY + y,
                          width: item.frame.width * entry.scale, height: item.frame.height * entry.scale)
                .intersection(entry.box).insetBy(dx: 2, dy: 2)
        }
        // Windows stacked in one tile share a frame; fan them out a little so each can be seen.
        var seen: [CGRect: Int] = [:]
        for index in tileRects.indices where !items[index].isMinimized {
            let key = tileRects[index].integral
            let n = seen[key, default: 0]
            seen[key] = n + 1
            if n > 0 { tileRects[index] = tileRects[index].offsetBy(dx: CGFloat(n) * 10, dy: CGFloat(n) * 10) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Front windows are drawn last, so test them first.
        if let index = tileRects.indices.first(where: { tileRects[$0].contains(point) }) { onClick?(index) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        background.fill()

        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                     .foregroundColor: NSColor.secondaryLabelColor]
        for (index, entry) in screenBoxes.enumerated() {
            (entry.screen.localizedName as NSString).draw(at: CGPoint(x: entry.box.minX, y: entry.box.minY - 20), withAttributes: label)
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: entry.box, xRadius: 10, yRadius: 10).fill()
            _ = index
        }
        // Back to front, so the frontmost window is drawn on top; the selection always last,
        // so a window stacked behind another is still visible once picked.
        for index in items.indices.reversed() where index != selected {
            drawTile(index)
        }
        if items.indices.contains(selected) { drawTile(selected) }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let hint = NSAttributedString(string: "⇥ next   ←→↑↓ move   release to switch   ⎋ cancel", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor, .paragraphStyle: paragraph,
        ])
        hint.draw(in: CGRect(x: 0, y: bounds.maxY - padding - 4, width: bounds.width, height: 16))
    }

    private func drawTile(_ index: Int) {
        let item = items[index], rect = tileRects[index]
        guard rect.width > 4, rect.height > 4 else { return }
        let isSelected = index == selected
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        path.lineWidth = isSelected ? 3 : 1
        (isSelected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let side = min(40, rect.width * 0.4, rect.height * 0.4)
        let textHeight: CGFloat = rect.height > side + 40 ? 34 : 0
        let iconRect = CGRect(x: rect.midX - side / 2, y: rect.midY - (side + textHeight) / 2, width: side, height: side)
        item.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard textHeight > 0 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let name = NSAttributedString(string: item.appName, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        name.draw(in: CGRect(x: rect.minX + 6, y: iconRect.maxY + 4, width: rect.width - 12, height: 16))
        let title = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph,
        ])
        title.draw(in: CGRect(x: rect.minX + 6, y: iconRect.maxY + 19, width: rect.width - 12, height: 15))
    }
}
