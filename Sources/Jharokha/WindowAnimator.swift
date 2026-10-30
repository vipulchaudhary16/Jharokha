import AppKit
import QuartzCore

/// Glides windows into their tiles, driven by the display's refresh. Progress follows elapsed
/// time rather than frame count, so an app that answers Accessibility writes slowly skips
/// frames instead of falling behind. Retargeting mid-flight continues from the current frame.
final class WindowAnimator: NSObject {
    static let duration: CFTimeInterval = 0.22

    private struct Animation {
        let window: AXWindow
        let from: CGRect
        let to: CGRect
        let start: CFTimeInterval
        let completion: () -> Void
    }

    private var animations: [CGWindowID: Animation] = [:]
    private var link: CADisplayLink?
    /// Apps whose enhanced UI was switched off for the animation, restored when it ends.
    private var enhancedApps: Set<pid_t> = []

    /// Each frame, the current frame of every animating window (AX coordinates).
    var onTick: (([CGWindowID: CGRect]) -> Void)?
    /// All animations finished.
    var onIdle: (() -> Void)?
    /// An animation started, with its start and end frames.
    var onStart: ((CGWindowID, CGRect, CGRect) -> Void)?

    var isRunning: Bool { !animations.isEmpty }

    func target(of id: CGWindowID) -> CGRect? { animations[id]?.to }

    /// Where an animating window is right now (AX coordinates).
    func currentFrame(of id: CGWindowID) -> CGRect? {
        animations[id].map { frame(of: $0, at: CACurrentMediaTime()) }
    }

    func animate(_ window: AXWindow, to target: CGRect, completion: @escaping () -> Void) {
        let now = CACurrentMediaTime()
        let from = animations[window.id].map { frame(of: $0, at: now) } ?? window.frame ?? target
        disableEnhancedUI(window.pid)
        animations[window.id] = Animation(window: window, from: from, to: target, start: now, completion: completion)
        onStart?(window.id, from, target)
        startLink()
    }

    /// Stops a window's animation where it is (e.g. the user grabbed it).
    func cancel(_ id: CGWindowID) {
        // Only a real cancellation can end the animation run; otherwise every instant write
        // would report "idle" and trigger a refresh.
        guard animations.removeValue(forKey: id) != nil else { return }
        if animations.isEmpty { finishAll() }
    }

    // MARK: - Frames

    /// Cubic deceleration: quick to start, settling without a long near-still tail.
    private static func ease(_ t: Double) -> CGFloat {
        let t = min(1, max(0, t))
        return CGFloat(t * (3 + t * (t - 3)))
    }

    private func frame(of animation: Animation, at time: CFTimeInterval) -> CGRect {
        let e = Self.ease((time - animation.start) / Self.duration)
        let a = animation.from, b = animation.to
        return CGRect(x: a.minX + (b.minX - a.minX) * e, y: a.minY + (b.minY - a.minY) * e,
                      width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e).integral
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var frames: [CGWindowID: CGRect] = [:]
        var finished: [Animation] = []
        for (id, animation) in animations {
            if now - animation.start >= Self.duration {
                // The last write is exact: size, position, size, as for an instant move.
                animation.window.setFrame(animation.to)
                frames[id] = animation.to
                finished.append(animation)
                animations[id] = nil
            } else {
                let frame = frame(of: animation, at: now)
                animation.window.setFrameQuickly(frame)
                frames[id] = frame
            }
        }
        onTick?(frames)
        finished.forEach { $0.completion() }
        if animations.isEmpty { finishAll() }
    }

    private func startLink() {
        guard link == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func finishAll() {
        link?.invalidate()
        link = nil
        for pid in enhancedApps { AXUIElementCreateApplication(pid).set("AXEnhancedUserInterface", kCFBooleanTrue) }
        enhancedApps.removeAll()
        onIdle?()
    }

    /// Enhanced UI (turned on by some assistive tools) animates every frame change itself and
    /// stutters; switch it off once for the whole animation instead of on every write.
    private func disableEnhancedUI(_ pid: pid_t) {
        guard !enhancedApps.contains(pid) else { return }
        let app = AXUIElementCreateApplication(pid)
        if app.value("AXEnhancedUserInterface") as Bool? == true {
            app.set("AXEnhancedUserInterface", kCFBooleanFalse)
            enhancedApps.insert(pid)
        }
    }
}

extension AXWindow {
    /// One intermediate animation frame: position and size, no extra checks.
    func setFrameQuickly(_ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let originValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        element.set(kAXPositionAttribute, originValue)
        element.set(kAXSizeAttribute, sizeValue)
    }
}
