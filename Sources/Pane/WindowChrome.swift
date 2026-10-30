import AppKit

/// Everything Pane draws around tiled windows: the highlight (border or glow), the grip
/// above the active window with its stack chips or quick actions, the dots above other
/// stacked tiles, and hover-to-focus. Rebuilt after every layout pass and focus change.
final class WindowChrome {
    private let tiler: TilingManager
    private let settings = Settings.shared

    private var borders: [CGWindowID: NSPanel] = [:]
    private var grip: (panel: NSPanel, view: GripView)?
    private var bar: (panel: NSPanel, view: ChipBarView)?
    private var dots: [CGWindowID: (panel: NSPanel, view: StackDotsView)] = [:]
    private var hideBarWork: DispatchWorkItem?
    private var hidden = false
    private var mouseMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?

    init(tiler: TilingManager) {
        self.tiler = tiler
    }

    // MARK: - Updates

    func update() {
        guard !hidden else { return }
        let tiles = tiler.chromeTiles()
        updateBorders(tiles)
        updateGrip(tiles)
        updateDots(tiles)
        updateHoverMonitor()
    }

    /// While a window is dragged or resized the chrome would lag behind it; hide it.
    func setHidden(_ hide: Bool) {
        hidden = hide
        if hide {
            borders.values.forEach { $0.orderOut(nil) }
            grip?.panel.orderOut(nil)
            hideBar()
            dots.values.forEach { $0.panel.orderOut(nil) }
        } else {
            update()
        }
    }

    // MARK: - Borders and glow

    private func updateBorders(_ tiles: [TilingManager.ChromeTile]) {
        let style = settings.highlightStyle
        let wanted = tiles.filter { style == .allBorders || ((style == .activeBorder || style == .glow) && $0.isActive) }
        let ids = Set(wanted.map(\.showing))
        for (id, panel) in borders where !ids.contains(id) {
            panel.orderOut(nil)
            borders[id] = nil
        }
        let color = settings.highlightColor.color
        for tile in wanted {
            let glow = style == .glow
            let pad: CGFloat = glow ? 22 : 4
            let panel = borders[tile.showing] ?? Self.overlayPanel(clickThrough: true)
            borders[tile.showing] = panel
            let view = (panel.contentView as? BorderView) ?? BorderView()
            view.color = color
            view.glow = glow
            view.isActive = tile.isActive
            view.inset = pad
            panel.contentView = view
            panel.setFrame(Self.nsRect(tile.rect).insetBy(dx: -pad, dy: -pad), display: true)
            // Just above its own window, so other windows that cover it also cover the border.
            panel.order(.above, relativeTo: Int(tile.showing))
        }
    }

    // MARK: - Grip and chip bar

    private func updateGrip(_ tiles: [TilingManager.ChromeTile]) {
        guard settings.showsQuickActions, let active = tiles.first(where: \.isActive) else {
            grip?.panel.orderOut(nil)
            hideBar()
            return
        }
        let entry = grip ?? makeGrip()
        grip = entry
        entry.view.segments = active.windows.count
        entry.view.showingIndex = active.windows.firstIndex(of: active.showing) ?? 0
        entry.view.tile = active
        let size = entry.view.intrinsicSize
        let rect = Self.nsRect(active.rect)
        // Centered on the window's top edge, in the gap above it.
        let frame = NSRect(x: rect.midX - size.width / 2, y: rect.maxY + max(settings.gap / 2, 3) - size.height / 2,
                           width: size.width, height: size.height)
        entry.panel.setFrame(frame, display: true)
        entry.panel.order(.above, relativeTo: Int(active.showing))
        if let bar, bar.panel.isVisible { showBar(for: active) }
    }

    private func makeGrip() -> (panel: NSPanel, view: GripView) {
        let panel = Self.overlayPanel(clickThrough: false)
        let view = GripView()
        view.onHover = { [weak self] inside in
            guard let self else { return }
            if inside, let tile = self.grip?.view.tile { self.showBar(for: tile) } else { self.scheduleHideBar() }
        }
        view.onSelectSegment = { [weak self] index in
            guard let self, let tile = self.grip?.view.tile, tile.windows.indices.contains(index) else { return }
            self.tiler.activate(window: tile.windows[index])
        }
        panel.contentView = view
        return (panel, view)
    }

    private func showBar(for tile: TilingManager.ChromeTile) {
        hideBarWork?.cancel()
        let entry = bar ?? makeBar()
        bar = entry
        if tile.windows.count > 1 {
            entry.view.mode = .stack(tile.windows.map { id in
                .init(id: id, icon: tiler.appIcon(of: id), title: Self.chipTitle(tiler, id), isShowing: id == tile.showing)
            })
        } else {
            entry.view.mode = .actions(tile.showing)
        }
        let size = entry.view.fittingSize
        let rect = Self.nsRect(tile.rect)
        let width = min(size.width, rect.width - 16)
        let frame = NSRect(x: rect.midX - width / 2, y: rect.maxY - size.height - 10, width: width, height: size.height)
        entry.panel.setFrame(frame, display: true)
        entry.panel.order(.above, relativeTo: Int(tile.showing))
    }

    private static func chipTitle(_ tiler: TilingManager, _ id: CGWindowID) -> String {
        let title = tiler.title(of: id)
        return title.isEmpty ? (tiler.appName(of: id)?.name ?? "Window") : title
    }

    private func makeBar() -> (panel: NSPanel, view: ChipBarView) {
        let panel = Self.overlayPanel(clickThrough: false)
        let view = ChipBarView()
        view.onHover = { [weak self] inside in
            if inside { self?.hideBarWork?.cancel() } else { self?.scheduleHideBar() }
        }
        view.onShow = { [weak self] id in self?.tiler.activate(window: id) }
        view.onClose = { [weak self] id in self?.tiler.close(window: id) }
        view.onCycle = { [weak self] step in self?.tiler.cycleStack(step: step) }
        view.onDropChip = { [weak self] id, point in
            self?.hideBar()
            self?.tiler.moveWindow(id, toTileAt: point)
        }
        view.onAction = { [weak self] action, id in
            guard let self else { return }
            self.hideBar()
            switch action {
            case .primary: self.tiler.activate(window: id); self.tiler.makePrimary()
            case .focus: self.tiler.toggleFocusMode(window: id)
            case .float: self.tiler.activate(window: id); self.tiler.toggleFloat()
            case .minimize: self.tiler.minimize(window: id)
            case .close: self.tiler.close(window: id)
            }
        }
        panel.contentView = view
        return (panel, view)
    }

    private func scheduleHideBar() {
        hideBarWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideBar() }
        hideBarWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func hideBar() {
        hideBarWork?.cancel()
        bar?.panel.orderOut(nil)
    }

    // MARK: - Stack dots on inactive tiles

    private func updateDots(_ tiles: [TilingManager.ChromeTile]) {
        let stacked = tiles.filter { $0.windows.count > 1 && !($0.isActive && settings.showsQuickActions) }
        let ids = Set(stacked.map(\.showing))
        for (id, entry) in dots where !ids.contains(id) {
            entry.panel.orderOut(nil)
            dots[id] = nil
        }
        for tile in stacked {
            let entry = dots[tile.showing] ?? {
                let panel = Self.overlayPanel(clickThrough: false)
                let view = StackDotsView()
                view.onSelect = { [weak self] id in self?.tiler.activate(window: id) }
                panel.contentView = view
                return (panel, view)
            }()
            dots[tile.showing] = entry
            entry.view.windows = tile.windows
            entry.view.showing = tile.showing
            let size = entry.view.intrinsicSize
            let rect = Self.nsRect(tile.rect)
            entry.panel.setFrame(NSRect(x: rect.midX - size.width / 2, y: rect.maxY + max(settings.gap / 2, 3) - size.height / 2,
                                        width: size.width, height: size.height), display: true)
            entry.panel.order(.above, relativeTo: Int(tile.showing))
        }
    }

    // MARK: - Hover focus

    private func updateHoverMonitor() {
        if settings.hoverFocus, mouseMonitors.isEmpty {
            let handler: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { mouseMonitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { handler($0); return $0 }) {
                mouseMonitors.append(local)
            }
        } else if !settings.hoverFocus, !mouseMonitors.isEmpty {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors.removeAll()
        }
    }

    /// Focus follows the pointer once it rests on a tiled window for a moment.
    private func pointerMoved() {
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, NSEvent.pressedMouseButtons == 0,
                  NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let id = self.tiler.tiledWindow(at: NSEvent.axMouseLocation),
                  id != self.tiler.focusedTiledWindow else { return }
            self.tiler.activate(window: id)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: - Helpers

    static func overlayPanel(clickThrough: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = clickThrough
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        return panel
    }

    /// AX rect (top-left origin, y down) to AppKit screen coordinates.
    static func nsRect(_ rect: CGRect) -> NSRect {
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: - Views

final class BorderView: NSView {
    var color: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
    var glow = false { didSet { needsDisplay = true } }
    var isActive = true { didSet { needsDisplay = true } }
    var inset: CGFloat = 4 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        // macOS windows have rounded corners; follow them just outside the window.
        let rect = bounds.insetBy(dx: inset - 2, dy: inset - 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        if glow {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = color.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 16
            shadow.set()
            color.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 3
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        } else {
            (isActive ? color : color.withAlphaComponent(0.35)).setStroke()
            path.lineWidth = isActive ? 2.5 : 1.5
            path.stroke()
        }
    }
}

/// The grip above the active window: one segment per window in its tile, the showing one
/// longer and solid. Resting on it opens the chip bar or quick actions.
final class GripView: NSView {
    var segments = 1 { didSet { needsDisplay = true } }
    var showingIndex = 0 { didSet { needsDisplay = true } }
    var tile: TilingManager.ChromeTile?
    var onHover: ((Bool) -> Void)?
    var onSelectSegment: ((Int) -> Void)?

    private let segmentWidth: CGFloat = 14, showingWidth: CGFloat = 26, spacing: CGFloat = 4, barHeight: CGFloat = 5

    var intrinsicSize: NSSize {
        let count = CGFloat(max(segments, 1))
        let width = segments > 1 ? (count - 1) * (segmentWidth + spacing) + showingWidth : 40
        return NSSize(width: width + 24, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    private func segmentRects() -> [NSRect] {
        guard segments > 1 else {
            return [NSRect(x: bounds.midX - 20, y: bounds.midY - barHeight / 2, width: 40, height: barHeight)]
        }
        var x: CGFloat = 12
        return (0..<segments).map { index in
            let width = index == showingIndex ? showingWidth : segmentWidth
            defer { x += width + spacing }
            return NSRect(x: x, y: bounds.midY - barHeight / 2, width: width, height: barHeight)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = segmentRects().firstIndex(where: { $0.insetBy(dx: -2, dy: -6).contains(point) }) {
            onSelectSegment?(index)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let stackColor = NSColor.systemOrange
        for (index, rect) in segmentRects().enumerated() {
            let path = NSBezierPath(roundedRect: rect, xRadius: barHeight / 2, yRadius: barHeight / 2)
            if segments == 1 {
                NSColor.white.withAlphaComponent(0.55).setFill()
            } else {
                (index == showingIndex ? stackColor : stackColor.withAlphaComponent(0.4)).setFill()
            }
            path.fill()
        }
    }
}

/// The row that opens from the grip: chips for a stack, or quick actions for a single window.
final class ChipBarView: NSView {
    struct Chip {
        let id: CGWindowID
        let icon: NSImage?
        let title: String
        let isShowing: Bool
    }

    enum QuickAction: CaseIterable {
        case primary, focus, float, minimize, close
        var symbol: String {
            switch self {
            case .primary: return "star"
            case .focus: return "arrow.up.left.and.arrow.down.right"
            case .float: return "macwindow.on.rectangle"
            case .minimize: return "minus"
            case .close: return "xmark"
            }
        }
        var help: String {
            switch self {
            case .primary: return "Make primary"
            case .focus: return "Focus mode"
            case .float: return "Float"
            case .minimize: return "Minimize"
            case .close: return "Close"
            }
        }
    }

    enum Mode {
        case stack([Chip])
        case actions(CGWindowID)
    }

    var mode: Mode = .actions(0) { didSet { rebuild() } }
    var onHover: ((Bool) -> Void)?
    var onShow: ((CGWindowID) -> Void)?
    var onClose: ((CGWindowID) -> Void)?
    var onCycle: ((Int) -> Void)?
    var onDropChip: ((CGWindowID, CGPoint) -> Void)?
    var onAction: ((QuickAction, CGWindowID) -> Void)?

    private let stack = NSStackView()
    private let background = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 6, bottom: 5, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func scrollWheel(with event: NSEvent) {
        guard case .stack = mode, abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 3 else { return }
        onCycle?((event.scrollingDeltaY + event.scrollingDeltaX) > 0 ? -1 : 1)
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch mode {
        case .stack(let chips):
            stack.addArrangedSubview(button(symbol: "chevron.left", help: "Previous window") { [weak self] in self?.onCycle?(-1) })
            for chip in chips {
                let view = ChipView(chip: chip)
                view.onShow = { [weak self] in self?.onShow?(chip.id) }
                view.onClose = { [weak self] in self?.onClose?(chip.id) }
                view.onDrop = { [weak self] point in self?.onDropChip?(chip.id, point) }
                stack.addArrangedSubview(view)
            }
            stack.addArrangedSubview(button(symbol: "chevron.right", help: "Next window") { [weak self] in self?.onCycle?(1) })
        case .actions(let id):
            for action in QuickAction.allCases {
                stack.addArrangedSubview(button(symbol: action.symbol, help: action.help) { [weak self] in self?.onAction?(action, id) })
            }
        }
        layoutSubtreeIfNeeded()
    }

    private func button(symbol: String, help: String, _ action: @escaping () -> Void) -> NSView {
        let button = ClosureButton(action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = .labelColor
        button.toolTip = help
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }
}

final class ClosureButton: NSButton {
    private let handler: () -> Void
    init(action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { handler() }
}

/// One window of a stack: icon and title; click shows it, × or middle-click closes it,
/// dragging it onto another tile moves it there.
final class ChipView: NSView {
    var onShow: (() -> Void)?
    var onClose: (() -> Void)?
    var onDrop: ((CGPoint) -> Void)?

    private let chip: ChipBarView.Chip
    private var hovered = false { didSet { needsDisplay = true } }
    private var dragStart: NSPoint?
    private var dragged = false

    init(chip: ChipBarView.Chip) {
        self.chip = chip
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        toolTip = chip.title
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private var closeRect: NSRect { NSRect(x: bounds.maxX - 22, y: bounds.midY - 8, width: 16, height: 16) }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        if hypot(now.x - start.x, now.y - start.y) > 6 { dragged = true }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if dragged {
            onDrop?(NSEvent.axMouseLocation)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if hovered && closeRect.contains(point) { onClose?() } else { onShow?() }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        if chip.isShowing {
            NSColor.systemOrange.withAlphaComponent(0.3).setFill()
            background.fill()
        } else if hovered {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            background.fill()
        }
        chip.icon?.draw(in: NSRect(x: 6, y: bounds.midY - 9, width: 18, height: 18))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: chip.isShowing ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let titleWidth = bounds.width - 30 - (hovered ? 24 : 6)
        let title = NSAttributedString(string: chip.title, attributes: attributes)
        title.draw(with: NSRect(x: 28, y: bounds.midY - 8, width: titleWidth, height: 16),
                   options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
        if hovered, let close = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close") {
            close.draw(in: closeRect)
        }
    }
}

/// Dots in the gap above a stacked tile that isn't active: one per window.
final class StackDotsView: NSView {
    var windows: [CGWindowID] = [] { didSet { needsDisplay = true } }
    var showing: CGWindowID = 0 { didSet { needsDisplay = true } }
    var onSelect: ((CGWindowID) -> Void)?

    private let dot: CGFloat = 7, spacing: CGFloat = 6

    var intrinsicSize: NSSize {
        NSSize(width: CGFloat(windows.count) * (dot + spacing) - spacing + 16, height: 16)
    }

    private func dotRect(_ index: Int) -> NSRect {
        NSRect(x: 8 + CGFloat(index) * (dot + spacing), y: bounds.midY - dot / 2, width: dot, height: dot)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = windows.indices.first(where: { dotRect($0).insetBy(dx: -3, dy: -4).contains(point) }) {
            onSelect?(windows[index])
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, id) in windows.enumerated() {
            (id == showing ? NSColor.systemOrange : NSColor.systemOrange.withAlphaComponent(0.4)).setFill()
            NSBezierPath(ovalIn: dotRect(index)).fill()
        }
    }
}
