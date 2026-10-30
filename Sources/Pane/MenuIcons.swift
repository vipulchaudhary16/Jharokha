import AppKit
import PaneCore

/// Menu icons drawn from the layout engine itself, so each one shows exactly what the
/// option does: the real tile arrangement, in the shape of the screen it applies to.
enum MenuIcons {
    /// Laid out at this size, then scaled down, so rounding doesn't distort small icons.
    private static let virtualSize = CGSize(width: 200, height: 140)

    static func layout(_ kind: LayoutKind, count: Int, ratio: CGFloat, gap: CGFloat = 14,
                       shape: ScreenShape = .standard) -> NSImage {
        let size = iconSize(for: shape)
        let virtual = CGRect(origin: .zero, size: CGSize(width: virtualSize.height * size.width / size.height,
                                                         height: virtualSize.height))
        let frames = LayoutEngine.frames(kind: kind, count: max(count, 1), in: virtual, mainRatio: ratio,
                                         gap: gap, shape: shape)
        return draw(size: size, tiles: frames, in: virtual)
    }

    /// The window count at which a layout looks like itself (Grid and Side are identical at 3).
    static func characteristicCount(of kind: LayoutKind, shape: ScreenShape) -> Int {
        switch kind {
        case .grid, .side: return shape == .standard ? 4 : 3
        case .columns, .rows: return 3
        }
    }

    /// Two windows with the given spacing between them.
    static func spacing(_ gap: CGFloat) -> NSImage {
        let size = iconSize(for: .standard)
        let virtual = CGRect(origin: .zero, size: CGSize(width: 200, height: 140))
        let frames = LayoutEngine.frames(kind: .columns, count: 2, in: virtual, mainRatio: 0.5,
                                         gap: gap * 1.6, shape: .standard)
        return draw(size: size, tiles: frames, in: virtual)
    }

    /// An SF Symbol redrawn into a plain template image: this macOS drops symbol images
    /// from menu items, while drawn images (like the layout icons) show.
    /// The menu bar glyph: Jharokha's arched window with tiled panes, outlined when paused,
    /// with a dot while a mode (Focus, No Peek, Privacy) is on, so it isn't forgotten.
    static func statusGlyph(paused: Bool, modeOn: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: modeOn ? 20 : 16, height: 16), flipped: true) { bounds in
            NSColor.black.set()
            if modeOn {
                NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 4.5, y: 0.5, width: 4.5, height: 4.5)).fill()
            }
            // The arch: straight sides, a round top.
            let frame = CGRect(x: 1.5, y: 1, width: 13, height: 14.5)
            let radius = frame.width / 2
            let arch = NSBezierPath()
            arch.move(to: CGPoint(x: frame.minX, y: frame.maxY))
            arch.line(to: CGPoint(x: frame.minX, y: frame.minY + radius))
            arch.appendArc(withCenter: CGPoint(x: frame.midX, y: frame.minY + radius), radius: radius,
                           startAngle: 180, endAngle: 0, clockwise: false)
            arch.line(to: CGPoint(x: frame.maxX, y: frame.maxY))
            arch.close()
            let gap: CGFloat = 1.4
            let split = frame.minX + (frame.width - gap) * 0.55
            let rowSplit = frame.minY + frame.height * 0.55
            if paused {
                arch.lineWidth = 1.2
                arch.stroke()
                let bars = NSBezierPath()
                bars.move(to: CGPoint(x: split + gap / 2, y: frame.minY))
                bars.line(to: CGPoint(x: split + gap / 2, y: frame.maxY))
                bars.move(to: CGPoint(x: split + gap / 2, y: rowSplit))
                bars.line(to: CGPoint(x: frame.maxX, y: rowSplit))
                bars.lineWidth = 1.2
                bars.stroke()
            } else {
                NSGraphicsContext.saveGraphicsState()
                arch.addClip()
                CGRect(x: frame.minX, y: frame.minY, width: split - frame.minX, height: frame.height).fill()
                CGRect(x: split + gap, y: frame.minY, width: frame.maxX - split - gap, height: rowSplit - frame.minY - gap / 2).fill()
                CGRect(x: split + gap, y: rowSplit + gap / 2, width: frame.maxX - split - gap, height: frame.maxY - rowSplit - gap / 2).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func symbol(_ name: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) else { return nil }
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { bounds in
            let s = symbol.size
            let scale = min(1, bounds.width / s.width, bounds.height / s.height)
            let rect = CGRect(x: (bounds.width - s.width * scale) / 2, y: (bounds.height - s.height * scale) / 2,
                              width: s.width * scale, height: s.height * scale)
            symbol.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func iconSize(for shape: ScreenShape) -> NSSize {
        switch shape {
        case .standard: return NSSize(width: 20, height: 14)
        case .ultrawide: return NSSize(width: 24, height: 11)
        case .vertical: return NSSize(width: 12, height: 17)
        }
    }

    /// A screen outline with its tiles; the primary tile is solid, the others lighter.
    /// Template images, so they follow light and dark menus and the selection highlight.
    private static func draw(size: NSSize, tiles: [CGRect], in virtual: CGRect) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in
            let screen = bounds.insetBy(dx: 0.5, dy: 0.5)
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            NSColor.black.setStroke()
            outline.stroke()

            let area = screen.insetBy(dx: 1, dy: 1)
            let sx = area.width / virtual.width
            let sy = area.height / virtual.height
            for (index, tile) in tiles.enumerated() {
                let rect = CGRect(x: area.minX + tile.minX * sx, y: area.minY + tile.minY * sy,
                                  width: tile.width * sx, height: tile.height * sy)
                NSColor.black.withAlphaComponent(index == 0 ? 1 : 0.55).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The top of the menu: what Pane is doing and a live miniature of the current screen,
/// with each tile's app icon. Click a tile to select its window (the menu stays open, so
/// Focus Mode and the app switch act on it); double-click to switch to it.
final class LayoutPreviewView: NSView {
    struct Tile {
        let window: CGWindowID
        let rect: CGRect   // normalized to 0...1 within the screen
        let icon: NSImage?
        let isActive: Bool
        let isStacked: Bool
        let isZoomed: Bool
    }

    /// A tile was clicked once: it is now the selection.
    var onSelect: ((CGWindowID) -> Void)?
    /// A tile was double-clicked: switch to that window.
    var onActivate: ((CGWindowID) -> Void)?

    private let title: String
    private let tiles: [Tile]
    private let aspect: CGFloat
    private(set) var selected: Int?
    private var hovered: Int?

    init(title: String, tiles: [Tile], screenAspect: CGFloat) {
        self.title = title
        self.tiles = tiles
        self.aspect = min(max(screenAspect, 0.5), 3)
        selected = tiles.firstIndex(where: \.isActive)
        let width: CGFloat = 280
        let previewHeight = min((width - 28) / self.aspect, 160)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: previewHeight + (tiles.isEmpty ? 40 : 58)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(tile(at: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    override func mouseUp(with event: NSEvent) {
        guard let index = tile(at: event) else { return }
        if event.clickCount >= 2 {
            onActivate?(tiles[index].window)
            enclosingMenuItem?.menu?.cancelTracking()
            return
        }
        selected = index
        needsDisplay = true
        onSelect?(tiles[index].window)
    }

    private func setHovered(_ index: Int?) {
        guard index != hovered else { return }
        hovered = index
        needsDisplay = true
    }

    private func tile(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return tileRects().firstIndex { $0.contains(point) }
    }

    private var screenRect: CGRect {
        let hintSpace: CGFloat = tiles.isEmpty ? 0 : 18
        let available = CGRect(x: 14, y: 28, width: bounds.width - 28, height: bounds.height - 36 - hintSpace)
        let width = min(available.width, available.height * aspect)
        return CGRect(x: available.minX + (available.width - width) / 2, y: available.minY,
                      width: width, height: width / aspect)
    }

    private func tileRects() -> [CGRect] {
        let screen = screenRect
        return tiles.map { tile in
            CGRect(x: screen.minX + tile.rect.minX * screen.width, y: screen.minY + tile.rect.minY * screen.height,
                   width: tile.rect.width * screen.width, height: tile.rect.height * screen.height)
                .insetBy(dx: 1.5, dy: 1.5)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        (title as NSString).draw(at: CGPoint(x: 14, y: 6), withAttributes: titleAttributes)

        let screen = screenRect
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6).fill()

        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ]
        guard !tiles.isEmpty else {
            let empty = "No windows to tile" as NSString
            let size = empty.size(withAttributes: small)
            empty.draw(at: CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2), withAttributes: small)
            return
        }

        let accent = NSColor.controlAccentColor
        for (index, (tile, rect)) in zip(tiles, tileRects()).enumerated() {
            let isSelected = index == selected
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            let fill = isSelected ? accent.withAlphaComponent(0.35)
                : index == hovered ? accent.withAlphaComponent(0.15)
                : NSColor.windowBackgroundColor.withAlphaComponent(0.9)
            fill.setFill()
            path.fill()
            path.lineWidth = isSelected ? 2 : 1
            (isSelected ? accent : index == hovered ? accent.withAlphaComponent(0.6) : NSColor.separatorColor).setStroke()
            path.stroke()

            let side = min(30, rect.width - 6, rect.height - 6)
            if let icon = tile.icon, side > 8 {
                icon.draw(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            if tile.isStacked {
                // Two dots in the corner mark a tile with windows waiting behind it.
                accent.setFill()
                for i in 0..<2 {
                    NSBezierPath(ovalIn: CGRect(x: rect.maxX - 12 + CGFloat(i) * 5, y: rect.minY + 4, width: 3.5, height: 3.5)).fill()
                }
            }
            if tile.isZoomed {
                let badge: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: accent,
                ]
                ("FOCUS" as NSString).draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 3), withAttributes: badge)
            }
        }

        let hint = "Click to select · double-click to switch to it" as NSString
        let size = hint.size(withAttributes: small)
        hint.draw(at: CGPoint(x: screen.midX - size.width / 2, y: screen.maxY + 4), withAttributes: small)
    }
}
