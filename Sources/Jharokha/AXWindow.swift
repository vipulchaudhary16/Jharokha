import AppKit
import ApplicationServices

// Private but long-stable API (also used by Rectangle, yabai, AeroSpace) mapping an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
    func value<T>(_ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func axValue(_ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}

/// A top-level window of another app, addressed through the Accessibility API.
/// Frames use AX coordinates: origin at the top-left of the primary screen, y down.
struct AXWindow {
    let element: AXUIElement
    let id: CGWindowID
    let pid: pid_t

    init?(_ element: AXUIElement, pid: pid_t) {
        guard let id = element.windowID else { return nil }
        self.element = element
        self.id = id
        self.pid = pid
    }

    var frame: CGRect? {
        var point = CGPoint.zero
        var size = CGSize.zero
        guard let p = element.axValue(kAXPositionAttribute), AXValueGetValue(p, .cgPoint, &point),
              let s = element.axValue(kAXSizeAttribute), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    var title: String { element.value(kAXTitleAttribute) ?? "" }
    var isMinimized: Bool { element.value(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { element.value("AXFullScreen") ?? false }

    /// Ordinary app windows: a standard window with a title bar that can be resized.
    /// Dialogs, sheets, panels and pop-ups have other roles or subroles and are never tiled.
    var isTileable: Bool {
        guard element.value(kAXRoleAttribute) as String? == kAXWindowRole,
              element.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole,
              !isMinimized, !isFullScreen else { return false }
        return element.isSettable(kAXSizeAttribute) && element.isSettable(kAXPositionAttribute)
    }

    /// Size, then position, then size again: macOS clamps sizes to the current display,
    /// so a window moving to a larger screen needs the second size write.
    func setFrame(_ frame: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        // Enhanced UI (enabled by some assistive tools) makes frame changes animate and stutter.
        let enhanced: Bool = app.value("AXEnhancedUserInterface") ?? false
        if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { app.set("AXEnhancedUserInterface", kCFBooleanTrue) } }

        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        element.set(kAXSizeAttribute, sizeValue)
        element.set(kAXPositionAttribute, originValue)
        element.set(kAXSizeAttribute, sizeValue)
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func focus() {
        raise()
        element.set(kAXMainAttribute, kCFBooleanTrue)
        // A background app can't reliably activate another one through NSRunningApplication;
        // AXFrontmost works whenever Jharokha has Accessibility access.
        AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
    }
}

enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// After a rebuild, System Settings can show Jharokha as allowed while macOS still rejects
    /// its calls. This asks the frontmost app for its windows to tell the two apart.
    static func probe() -> AXError {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .success }
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                             kAXWindowsAttribute as CFString, &value)
    }

    /// Trusted, and macOS actually accepts Jharokha's Accessibility calls.
    static var isUsable: Bool { isTrusted && probe() != .apiDisabled }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func windows(of app: NSRunningApplication) -> [AXWindow] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let windows: [AXUIElement] = element.value(kAXWindowsAttribute) ?? []
        return windows.compactMap { AXWindow($0, pid: app.processIdentifier) }
    }

    /// The window that has keyboard focus, system-wide.
    static func focusedWindow() -> AXWindow? {
        let system = AXUIElementCreateSystemWide()
        guard let app: AXUIElement = system.value(kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        guard let window: AXUIElement = app.value(kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(window, pid: pid)
    }
}
