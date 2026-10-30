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

    static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
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
/// with each tile's app icon.
final class LayoutPreviewView: NSView {
    struct Tile {
        let rect: CGRect   // normalized to 0...1 within the screen
        let icon: NSImage?
        let isActive: Bool
        let isStacked: Bool
    }

    private let title: String
    private let tiles: [Tile]
    private let aspect: CGFloat

    init(title: String, tiles: [Tile], screenAspect: CGFloat) {
        self.title = title
        self.tiles = tiles
        self.aspect = min(max(screenAspect, 0.5), 3)
        let width: CGFloat = 260
        let previewHeight = min((width - 28) / self.aspect, 150)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: previewHeight + 40))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        (title as NSString).draw(at: CGPoint(x: 14, y: 6), withAttributes: titleAttributes)

        let available = CGRect(x: 14, y: 28, width: bounds.width - 28, height: bounds.height - 36)
        let width = min(available.width, available.height * aspect)
        let screen = CGRect(x: available.minX + (available.width - width) / 2, y: available.minY,
                            width: width, height: width / aspect)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6).fill()

        guard !tiles.isEmpty else {
            let empty = "No windows to tile" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let size = empty.size(withAttributes: attributes)
            empty.draw(at: CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2),
                       withAttributes: attributes)
            return
        }

        let accent = NSColor.controlAccentColor
        for tile in tiles {
            let rect = CGRect(x: screen.minX + tile.rect.minX * screen.width, y: screen.minY + tile.rect.minY * screen.height,
                              width: tile.rect.width * screen.width, height: tile.rect.height * screen.height)
                .insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            (tile.isActive ? accent.withAlphaComponent(0.35) : NSColor.windowBackgroundColor.withAlphaComponent(0.9)).setFill()
            path.fill()
            path.lineWidth = tile.isActive ? 2 : 1
            (tile.isActive ? accent : NSColor.separatorColor).setStroke()
            path.stroke()

            let side = min(28, rect.width - 6, rect.height - 6)
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
        }
    }
}
