import AppKit
import PaneCore

/// A compact menu row of icon buttons: the four layouts, drawn from the layout engine.
/// Picking one acts at once and keeps the menu open.
final class LayoutPickerRow: NSView {
    var onPick: ((LayoutKind) -> Void)?
    private var selected: LayoutKind
    private let shape: ScreenShape
    private let ratio: CGFloat
    private var hovered: LayoutKind?
    private let caption = NSTextField(labelWithString: "")

    init(selected: LayoutKind, shape: ScreenShape, ratio: CGFloat) {
        self.selected = selected
        self.shape = shape
        self.ratio = ratio
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 78))
        autoresizingMask = [.width]
        caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center
        addSubview(caption)
        updateCaption()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func isAvailable(_ kind: LayoutKind) -> Bool { !(shape == .vertical && kind == .columns) }

    private func buttonRects() -> [(LayoutKind, NSRect)] {
        let kinds = LayoutKind.allCases
        let width: CGFloat = 62, spacing: CGFloat = 8
        let total = CGFloat(kinds.count) * width + CGFloat(kinds.count - 1) * spacing
        var x = (bounds.width - total) / 2
        return kinds.map { kind in
            defer { x += width + spacing }
            return (kind, NSRect(x: x, y: 6, width: width, height: 48))
        }
    }

    private func updateCaption() {
        let kind = hovered ?? selected
        caption.stringValue = isAvailable(kind) ? "\(kind.title) · \(Self.summary(kind))" : "Columns isn't available on a vertical monitor"
    }

    override func layout() {
        super.layout()
        caption.frame = NSRect(x: 12, y: 58, width: bounds.width - 24, height: 16)
    }

    static func summary(_ kind: LayoutKind) -> String {
        switch kind {
        case .grid: return "each window you open splits the last tile"
        case .columns: return "side by side, full height"
        case .rows: return "stacked, full width"
        case .side: return "one large window, the rest in a column"
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let kind = buttonRects().first { $0.1.contains(point) }?.0
        guard kind != hovered else { return }
        hovered = kind
        updateCaption()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        updateCaption()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let kind = buttonRects().first(where: { $0.1.contains(point) })?.0, isAvailable(kind) else { return }
        selected = kind
        updateCaption()
        needsDisplay = true
        onPick?(kind)
    }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        for (kind, rect) in buttonRects() {
            let isSelected = kind == selected
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            (isSelected ? accent.withAlphaComponent(0.25) : NSColor.labelColor.withAlphaComponent(kind == hovered ? 0.1 : 0.05)).setFill()
            path.fill()
            if isSelected {
                accent.setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
            let icon = MenuIcons.layout(kind, count: MenuIcons.characteristicCount(of: kind, shape: shape), ratio: ratio, shape: shape)
            let tinted = NSImage(size: icon.size, flipped: false) { r in
                icon.draw(in: r)
                (isSelected ? accent : NSColor.labelColor).withAlphaComponent(self.isAvailable(kind) ? 1 : 0.3).set()
                r.fill(using: .sourceAtop)
                return true
            }
            let iconSize = NSSize(width: icon.size.width * 1.4, height: icon.size.height * 1.4)
            tinted.draw(in: NSRect(x: rect.midX - iconSize.width / 2, y: rect.minY + 8, width: iconSize.width, height: iconSize.height))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? accent : NSColor.secondaryLabelColor,
            ]
            let title = kind.title as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - 4), withAttributes: attributes)
        }
    }
}

/// "Windows" with a segmented 1–5 choice; counts the layout can't hold here are dimmed.
final class CountPickerRow: NSView {
    var onPick: ((Int) -> Void)?
    private var selected: Int
    private let maximum: Int
    private var hovered: Int?

    init(selected: Int, maximum: Int) {
        self.selected = selected
        self.maximum = maximum
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 34))
        autoresizingMask = [.width]
        toolTip = "How many tiles this screen has; more windows than that stack up"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private func segmentRects() -> [(Int, NSRect)] {
        let width: CGFloat = 34, spacing: CGFloat = 4
        var x = bounds.width - 16 - (width * 5 + spacing * 4)
        return (1...5).map { n in
            defer { x += width + spacing }
            return (n, NSRect(x: x, y: 5, width: width, height: 24))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let n = segmentRects().first { $0.1.contains(point) }?.0
        if n != hovered { hovered = n; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let n = segmentRects().first(where: { $0.1.contains(point) })?.0, n <= maximum else { return }
        selected = n
        needsDisplay = true
        onPick?(n)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let icon = MenuIcons.symbol("square.grid.2x2") {
            let tinted = NSImage(size: icon.size, flipped: false) { r in icon.draw(in: r); NSColor.labelColor.set(); r.fill(using: .sourceAtop); return true }
            tinted.draw(in: NSRect(x: 26, y: bounds.midY - 8, width: 20, height: 16))
        }
        ("Windows" as NSString).draw(at: NSPoint(x: 54, y: bounds.midY - 8),
                                     withAttributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        let accent = NSColor.controlAccentColor
        for (n, rect) in segmentRects() {
            let isSelected = n == selected, available = n <= maximum
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            (isSelected ? accent : NSColor.labelColor.withAlphaComponent(n == hovered && available ? 0.12 : 0.06)).setFill()
            path.fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor.withAlphaComponent(available ? 0.85 : 0.25),
            ]
            let text = "\(n)" as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
