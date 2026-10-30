import AppKit

/// A soft blur with the app's icon laid over windows while they change size, so apps that
/// redraw slowly mid-resize (Electron apps especially) look smooth. Veils follow the tiles
/// and fade away once windows settle.
final class ResizeVeil {
    private var panels: [CGWindowID: NSPanel] = [:]
    private var hideWork: DispatchWorkItem?
    /// While veils glide, an early "settled" from another animation must not pull them away.
    private var glideEnds = Date.distantPast
    private static let fade: TimeInterval = 0.16

    var isShowing: Bool { !panels.isEmpty }

    /// Covers (or moves the veil of) each window, at frames in AX coordinates.
    func show(_ frames: [CGWindowID: CGRect], icons: (CGWindowID) -> NSImage?, instantly: Bool = false) {
        hideWork?.cancel()
        for (id, frame) in frames {
            let panel = panels[id] ?? makePanel(icon: icons(id))
            let isNew = panels[id] == nil
            panels[id] = panel
            panel.setFrame(WindowChrome.nsRect(frame), display: true)
            if isNew && instantly {
                // Must already cover the window before it jumps underneath.
                panel.alphaValue = 1
                panel.orderFrontRegardless()
                panel.display()
            } else if isNew {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.fade * 0.75
                    panel.animator().alphaValue = 1
                }
            }
        }
    }

    /// Moves existing veils only (e.g. on each animation frame).
    func follow(_ frames: [CGWindowID: CGRect]) {
        for (id, frame) in frames {
            panels[id]?.setFrame(WindowChrome.nsRect(frame), display: true)
        }
    }

    /// Glides veils to new frames (AX coordinates) — smooth whatever the app underneath does.
    func glide(_ frames: [CGWindowID: CGRect], duration: TimeInterval = 0.26, completion: @escaping () -> Void) {
        glideEnds = Date().addingTimeInterval(duration)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            for (id, frame) in frames {
                panels[id]?.animator().setFrame(WindowChrome.nsRect(frame), display: true)
            }
        }, completionHandler: completion)
    }

    /// Fades every veil out after a short pause, letting the last redraw land underneath.
    func hide(after delay: TimeInterval = 0.12) {
        hideWork?.cancel()
        let delay = max(delay, glideEnds.timeIntervalSinceNow + 0.1)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let panels = self.panels
            self.panels.removeAll()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Self.fade
                panels.values.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: {
                panels.values.forEach { $0.orderOut(nil) }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel(icon: NSImage?) -> NSPanel {
        let panel = WindowChrome.overlayPanel(clickThrough: true)
        // Above the windows it covers for the moment it is shown; it never takes clicks,
        // so an edge being dragged underneath keeps working.
        panel.level = .floating
        panel.contentView = VeilView(icon: icon)
        return panel
    }
}

private final class VeilView: NSView {
    private let blur = NSVisualEffectView()
    private let iconView = NSImageView()
    private let tint = NSView()

    init(icon: NSImage?) {
        super.init(frame: .zero)
        wantsLayer = true
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        // macOS windows have rounded corners; the veil follows them.
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55).cgColor
        tint.layer?.cornerRadius = 16
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.alphaValue = 0.9
        addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        let side = min(64, bounds.width * 0.3, bounds.height * 0.3)
        iconView.frame = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
}
