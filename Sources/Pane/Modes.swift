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

/// Clean Space: one window on a plain background, for sharing or presenting. The screen is
/// covered by an opaque backdrop ordered just below the window; nothing is moved or closed,
/// and windows brought to that screen appear above the backdrop.
final class CleanSpace {
    private let settings = Settings.shared
    private var backdrop: NSPanel?
    private(set) var screen: NSScreen?
    private var tokens: [NSObjectProtocol] = []
    var onAutomaticEnd: (() -> Void)?

    var isOn: Bool { backdrop != nil }

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
        // macOS posts the lock as a distributed notification.
        tokens.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
                                                                           object: nil, queue: .main) { [weak self] _ in
            self?.endAutomatically()
        })
    }

    /// A window behind the backdrop, shown as a placeholder: where it is and which app,
    /// never its content or title, so sharing the screen reveals nothing.
    struct Card {
        let rect: CGRect          // AX coordinates
        let icon: NSImage?
        let name: String
        let hiddenCount: Int      // other windows stacked behind it
    }

    func start(on screen: NSScreen, below window: CGWindowID?) {
        let panel = backdrop ?? WindowChrome.overlayPanel(clickThrough: true)
        panel.isOpaque = true
        panel.backgroundColor = settings.cleanSpaceBackground.color
        if !(panel.contentView is CleanSpaceView) { panel.contentView = CleanSpaceView() }
        panel.setFrame(screen.frame, display: true)
        backdrop = panel
        self.screen = screen
        if let window { panel.order(.below, relativeTo: Int(window)) } else { panel.orderFront(nil) }
    }

    /// Keeps the backdrop just below whichever window is active on that screen.
    func update(below window: CGWindowID?) {
        guard let backdrop, let window else { return }
        backdrop.backgroundColor = settings.cleanSpaceBackground.color
        backdrop.order(.below, relativeTo: Int(window))
    }

    /// The placeholder cards drawn on the backdrop. Clicks pass through to the real window
    /// underneath, which then comes forward as the presented one.
    func setCards(_ cards: [Card]) {
        guard let backdrop, let view = backdrop.contentView as? CleanSpaceView, let screen else { return }
        view.background = settings.cleanSpaceBackground
        view.cards = cards.map { card in
            let ns = WindowChrome.nsRect(card.rect)
            return .init(rect: ns.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), icon: card.icon,
                         name: card.name, hiddenCount: card.hiddenCount)
        }
    }

    func stop() {
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

/// The Clean Space background with a placeholder card for each window behind it.
final class CleanSpaceView: NSView {
    var background: Settings.CleanSpaceBackground = .graphite { didSet { needsDisplay = true } }
    var cards: [CleanSpace.Card] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        background.color.setFill()
        bounds.fill()
        // Light backgrounds get dark marks, dark ones light marks.
        let ink: NSColor = background == .mist ? .black : .white
        for card in cards {
            let rect = card.rect.insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
            ink.withAlphaComponent(0.05).setFill()
            path.fill()
            ink.withAlphaComponent(0.22).setStroke()
            path.lineWidth = 1.5
            path.setLineDash([8, 6], count: 2, phase: 0)
            path.stroke()

            let side = min(72, rect.width * 0.3, rect.height * 0.3)
            let showsName = rect.height > side + 50
            let iconRect = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2 + (showsName ? 12 : 0), width: side, height: side)
            card.icon?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.85)
            guard showsName else { continue }
            var name = card.name
            if card.hiddenCount > 0 { name += "  +\(card.hiddenCount)" }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: ink.withAlphaComponent(0.7),
            ]
            let size = (name as NSString).size(withAttributes: attributes)
            (name as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: iconRect.minY - size.height - 10), withAttributes: attributes)
        }
    }
}
