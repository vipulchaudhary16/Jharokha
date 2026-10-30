import AppKit

/// While a tiled window is being dragged: outlines every tile on every screen and previews
/// the result of dropping, i.e. which window ends up where.
final class DragOverlay {
    struct Tile: Equatable {
        enum Role { case normal, source, target }
        /// AX coordinates (top-left origin of the primary screen, y down).
        let rect: CGRect
        let role: Role
        let icon: NSImage?
        let caption: String?

        static func == (a: Tile, b: Tile) -> Bool {
            a.rect == b.rect && a.role == b.role && a.icon === b.icon && a.caption == b.caption
        }
    }

    struct Scene: Equatable {
        let screen: NSScreen
        let tiles: [Tile]
    }

    private var panels: [NSScreen: (panel: NSPanel, view: DragOverlayView)] = [:]
    private var shown: [Scene] = []

    func show(_ scenes: [Scene]) {
        guard scenes != shown else { return }
        shown = scenes
        let screens = Set(scenes.map(\.screen))
        for (screen, entry) in panels where !screens.contains(screen) {
            entry.panel.orderOut(nil)
            panels[screen] = nil
        }
        for scene in scenes {
            let entry = panels[scene.screen] ?? makePanel(for: scene.screen)
            panels[scene.screen] = entry
            entry.panel.setFrame(scene.screen.frame, display: false)
            entry.view.screen = scene.screen
            entry.view.tiles = scene.tiles
            entry.panel.orderFrontRegardless()
        }
    }

    func hide() {
        panels.values.forEach { $0.panel.orderOut(nil) }
        panels.removeAll()
        shown = []
    }

    private func makePanel(for screen: NSScreen) -> (panel: NSPanel, view: DragOverlayView) {
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Above ordinary windows, including the one being dragged, but never takes clicks.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = DragOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
        return (panel, view)
    }
}

final class DragOverlayView: NSView {
    var screen: NSScreen?
    var tiles: [DragOverlay.Tile] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    /// AX rect (global, y down from the primary screen's top) to this view's coordinates.
    private func local(_ rect: CGRect) -> CGRect {
        guard let screen, let primary = NSScreen.screens.first else { return rect }
        let top = primary.frame.maxY - screen.frame.maxY
        return CGRect(x: rect.minX - screen.frame.minX, y: rect.minY - top, width: rect.width, height: rect.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A faint dim tells you Jharokha is showing where windows can go.
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        let accent = NSColor.controlAccentColor
        for tile in tiles {
            let rect = local(tile.rect).insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            switch tile.role {
            case .normal:
                NSColor.black.withAlphaComponent(0.18).setFill()
                path.fill()
                NSColor.white.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 2
            case .source:
                NSColor.black.withAlphaComponent(0.3).setFill()
                path.fill()
                accent.setStroke()
                path.lineWidth = 2
                path.setLineDash([10, 6], count: 2, phase: 0)
            case .target:
                accent.withAlphaComponent(0.3).setFill()
                path.fill()
                accent.setStroke()
                path.lineWidth = 4
            }
            path.stroke()
            drawContent(of: tile, in: rect)
        }
    }

    private func drawContent(of tile: DragOverlay.Tile, in rect: CGRect) {
        let side = min(72, rect.width * 0.4, rect.height * 0.4)
        let captionHeight: CGFloat = tile.caption == nil ? 0 : 34
        let iconRect = CGRect(x: rect.midX - side / 2, y: rect.midY - (side + captionHeight) / 2, width: side, height: side)
        if let icon = tile.icon, side > 16 {
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver,
                      fraction: tile.role == .normal ? 0.6 : 1, respectFlipped: true, hints: nil)
        }
        guard let caption = tile.caption else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = caption as NSString
        let size = text.size(withAttributes: attributes)
        let pill = CGRect(x: rect.midX - size.width / 2 - 14, y: iconRect.maxY + 10,
                          width: size.width + 28, height: size.height + 10)
        (tile.role == .target ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.65)).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 5), withAttributes: attributes)
    }
}
