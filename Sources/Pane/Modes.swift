import AppKit

/// No peek: every screen is dimmed (and blurred) except the active window, its sheets and
/// menus, the menu bar and the Dock. A full-screen layer is kept ordered just below the
/// active window, so it covers everything behind it.
final class NoPeek {
    private let settings = Settings.shared
    private var panels: [NSScreen: (panel: NSPanel, dim: NSView, blur: NSVisualEffectView)] = [:]
    private(set) var isOn = false

    func setOn(_ on: Bool, below window: CGWindowID?) {
        isOn = on
        if on { update(below: window) } else { panels.values.forEach { $0.panel.orderOut(nil) }; panels.removeAll() }
    }

    /// Re-applies the dim amount and blur, and re-orders below the newly active window.
    func update(below window: CGWindowID?) {
        guard isOn else { return }
        let screens = Set(NSScreen.screens)
        for (screen, entry) in panels where !screens.contains(screen) {
            entry.panel.orderOut(nil)
            panels[screen] = nil
        }
        for screen in NSScreen.screens {
            let entry = panels[screen] ?? makePanel()
            panels[screen] = entry
            entry.panel.setFrame(screen.frame, display: false)
            entry.blur.isHidden = !settings.noPeekBlur
            entry.dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(settings.noPeekDim).cgColor
            if let window {
                entry.panel.order(.below, relativeTo: Int(window))
            } else {
                entry.panel.orderFront(nil)
            }
        }
    }

    private func makePanel() -> (panel: NSPanel, dim: NSView, blur: NSVisualEffectView) {
        let panel = WindowChrome.overlayPanel(clickThrough: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let content = NSView()
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let dim = NSView()
        dim.wantsLayer = true
        for view in [blur, dim] {
            view.autoresizingMask = [.width, .height]
            content.addSubview(view)
        }
        panel.contentView = content
        blur.frame = content.bounds
        dim.frame = content.bounds
        return (panel, dim, blur)
    }
}

/// Privacy Mode (internally Clean Space): share some windows, cover the rest. A plain
/// background replaces the desktop picture, below every window. Each hidden window gets its
/// own opaque card laid exactly over it (app icon and name, never content), above normal
/// windows; shown windows simply have no card. Nothing depends on how other apps' windows
/// are stacked, which Pane can't reliably control.
final class CleanSpace {
    private let settings = Settings.shared
    private var backdrop: NSPanel?
    private(set) var screen: NSScreen?
    private var cards: [CGWindowID: (panel: NSPanel, view: PrivacyCardView)] = [:]
    private var pills: [CGWindowID: (panel: NSPanel, view: EyeButton)] = [:]
    private var tokens: [NSObjectProtocol] = []
    var onAutomaticEnd: (() -> Void)?
    /// A card's Show button (or the card itself), or a shown window's Hide pill, was clicked.
    var onToggle: ((CGWindowID) -> Void)?

    var isOn: Bool { backdrop != nil }

    struct Card {
        let window: CGWindowID
        let rect: CGRect          // AX coordinates
        let icon: NSImage?
        let name: String
        let hiddenCount: Int      // other windows stacked behind it
    }

    init() {
        // Ends by itself when the Mac sleeps or locks, or the screen is disconnected.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.endAutomatically() })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            guard let self, let screen = self.screen, !NSScreen.screens.contains(screen) else { return }
            self.endAutomatically()
        })
        tokens.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
                                                                           object: nil, queue: .main) { [weak self] _ in
            self?.endAutomatically()
        })
    }

    func start(on screen: NSScreen) {
        let panel = backdrop ?? WindowChrome.overlayPanel(clickThrough: true)
        // Just above the desktop picture and icons, below every window.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.isOpaque = true
        panel.backgroundColor = settings.cleanSpaceBackground.color
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        backdrop = panel
        self.screen = screen
    }

    /// Covers each hidden window with its card.
    func setCards(_ wanted: [Card]) {
        backdrop?.backgroundColor = settings.cleanSpaceBackground.color
        let ids = Set(wanted.map(\.window))
        for (id, entry) in cards where !ids.contains(id) {
            entry.panel.orderOut(nil)
            cards[id] = nil
        }
        for card in wanted {
            let entry = cards[card.window] ?? {
                let panel = WindowChrome.overlayPanel(clickThrough: false)
                // Above normal windows, so it covers its window however apps are stacked.
                panel.level = .floating
                let view = PrivacyCardView()
                view.onShow = { [weak self] in self?.onToggle?(card.window) }
                panel.contentView = view
                return (panel, view)
            }()
            cards[card.window] = entry
            entry.view.update(card: card, background: settings.cleanSpaceBackground)
            entry.panel.setFrame(WindowChrome.nsRect(card.rect), display: true)
            entry.panel.orderFrontRegardless()
        }
    }

    /// A Hide pill on each shown window's top edge.
    func setPills(_ shown: [(window: CGWindowID, rect: CGRect)]) {
        let ids = Set(shown.map(\.window))
        for (id, entry) in pills where !ids.contains(id) {
            entry.panel.orderOut(nil)
            pills[id] = nil
        }
        for item in shown {
            let entry = pills[item.window] ?? {
                let panel = WindowChrome.overlayPanel(clickThrough: false)
                panel.level = .floating
                let view = EyeButton()
                view.isShown = true
                view.onClick = { [weak self] in self?.onToggle?(item.window) }
                panel.contentView = view
                return (panel, view)
            }()
            pills[item.window] = entry
            let rect = WindowChrome.nsRect(item.rect)
            let size = entry.view.intrinsicSize
            // Straddling the window's top edge, near its right corner.
            entry.panel.setFrame(NSRect(x: rect.maxX - size.width - 24, y: rect.maxY - size.height / 2,
                                        width: size.width, height: size.height), display: true)
            entry.panel.orderFrontRegardless()
        }
    }

    func stop() {
        cards.values.forEach { $0.panel.orderOut(nil) }
        cards.removeAll()
        pills.values.forEach { $0.panel.orderOut(nil) }
        pills.removeAll()
        backdrop?.orderOut(nil)
        backdrop = nil
        screen = nil
    }

    private func endAutomatically() {
        guard isOn else { return }
        stop()
        onAutomaticEnd?()
    }
}

/// The opaque card over a hidden window: the background colour, a soft dashed outline, the
/// app's icon and name, and a Show button. Clicking anywhere on it shows the window.
final class PrivacyCardView: NSView {
    var onShow: (() -> Void)?
    private var card: CleanSpace.Card?
    private var background: Settings.CleanSpaceBackground = .graphite
    private var hovered = false { didSet { needsDisplay = true } }

    func update(card: CleanSpace.Card, background: Settings.CleanSpaceBackground) {
        self.card = card
        self.background = background
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseUp(with event: NSEvent) { onShow?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let card else { return }
        background.color.setFill()
        bounds.fill()
        let ink: NSColor = background == .mist ? .black : .white
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        ink.withAlphaComponent(hovered ? 0.09 : 0.05).setFill()
        path.fill()
        ink.withAlphaComponent(hovered ? 0.4 : 0.22).setStroke()
        path.lineWidth = 1.5
        path.setLineDash([8, 6], count: 2, phase: 0)
        path.stroke()

        let side = min(72, rect.width * 0.3, rect.height * 0.3)
        let roomy = rect.height > side + 80
        let iconRect = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2 + (roomy ? 22 : 0), width: side, height: side)
        card.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.85)
        guard roomy else { return }
        var name = card.name
        if card.hiddenCount > 0 { name += "  +\(card.hiddenCount)" }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.7),
        ]
        let size = (name as NSString).size(withAttributes: attributes)
        let nameY = iconRect.minY - size.height - 10
        (name as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: nameY), withAttributes: attributes)

        // The Show button under the name.
        let label = "Show" as NSString
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let labelSize = label.size(withAttributes: [.font: font])
        let button = NSRect(x: rect.midX - (labelSize.width + 44) / 2, y: nameY - 36, width: labelSize.width + 44, height: 26)
        NSColor.controlAccentColor.withAlphaComponent(hovered ? 1 : 0.85).setFill()
        NSBezierPath(roundedRect: button, xRadius: 13, yRadius: 13).fill()
        if let eye = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
            let white = NSImage(size: eye.size, flipped: false) { r in eye.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true }
            white.draw(in: NSRect(x: button.minX + 12, y: button.midY - 7, width: 16, height: 14))
        }
        label.draw(at: NSPoint(x: button.minX + 32, y: button.midY - labelSize.height / 2),
                   withAttributes: [.font: font, .foregroundColor: NSColor.white])
    }
}

/// The eye on a tile in Privacy Mode: "Show" on a hidden window, "Hide" on a shown one.
final class EyeButton: NSView {
    var isShown = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }

    var intrinsicSize: NSSize {
        let text = (isShown ? "Hide" : "Show") as NSString
        return NSSize(width: text.size(withAttributes: [.font: Self.font]).width + 44, height: 24)
    }

    private static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (isShown ? NSColor.black.withAlphaComponent(hovered ? 0.8 : 0.62) : NSColor.controlAccentColor.withAlphaComponent(hovered ? 1 : 0.88)).setFill()
        pill.fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        pill.stroke()
        let symbol = NSImage(systemSymbolName: isShown ? "eye.slash" : "eye", accessibilityDescription: isShown ? "Hide" : "Show")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        let tinted = symbol.map { image -> NSImage in
            NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }
        tinted?.draw(in: NSRect(x: 10, y: bounds.midY - 7, width: 16, height: 14))
        ((isShown ? "Hide" : "Show") as NSString).draw(at: NSPoint(x: 30, y: bounds.midY - 7),
                                                       withAttributes: [.font: Self.font, .foregroundColor: NSColor.white])
    }
}
