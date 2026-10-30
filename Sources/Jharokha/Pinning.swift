import AppKit
import JharokhaCore

/// Pinned apps: on every desktop, floating (never tiled), and following you between screens.
///
/// "Every desktop" uses the same setting as the Dock's Options › All Desktops, which macOS
/// applies only when the Dock restarts. Keeping another app's window above all others isn't
/// possible without disabling System Integrity Protection, so a pinned window floats like any
/// untiled window and moves to whichever screen you're working on.
extension TilingManager {
    var pinnedBundleIDs: Set<String> { settings.pinnedBundleIDs }

    func isPinned(_ bundleID: String) -> Bool { settings.pinnedBundleIDs.contains(bundleID) }

    /// Pins or unpins the front app (the keyboard shortcut).
    func togglePin() {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        setPinned(!isPinned(bundleID), bundleID: bundleID)
    }

    /// Pins or unpins an app. Setting a state rather than flipping it means a repeated click
    /// or key bounce can't undo the change (each one also restarts the Dock).
    func setPinned(_ pin: Bool, bundleID: String) {
        guard bundleID != Bundle.main.bundleIdentifier, pin != isPinned(bundleID) else { return }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
        guard Self.confirmDockRestart(pinning: pin) else { return }

        var pinned = settings.pinnedBundleIDs
        if pin { pinned.insert(bundleID) } else { pinned.remove(bundleID) }
        settings.pinnedBundleIDs = pinned
        setAllDesktops(pin, for: bundleID)

        if pin {
            // Out of the layout, then into a picture-in-picture corner of the screen you're on.
            refresh()
            for window in pinnedWindows(of: bundleID) { placeAsPinned(window) }
            Toast.show("\(name) is pinned to every desktop and follows you between screens")
        } else {
            refresh()
            Toast.show("\(name) is no longer pinned")
        }
        onStateChange?()
    }

    /// Standard, visible windows of a pinned app (pinned apps aren't part of `windows`).
    func pinnedWindows(of bundleID: String? = nil) -> [AXWindow] {
        let ids = bundleID.map { [$0] } ?? Array(settings.pinnedBundleIDs)
        return ids.flatMap { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { !$0.isHidden }
                .flatMap { AX.windows(of: $0) }
                .filter { $0.isTileable }
        }
    }

    /// A small window in the bottom-right corner of the screen you're working on.
    private func placeAsPinned(_ window: AXWindow) {
        guard let display = targetDisplay() else { return }
        let area = display.rect.insetBy(dx: 20, dy: 20)
        let current = window.frame?.size ?? CGSize(width: 480, height: 300)
        let size = CGSize(width: min(current.width, max(360, area.width * 0.3)),
                          height: min(current.height, max(240, area.height * 0.3)))
        window.setFrame(CGRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height).integral)
    }

    /// Pinned windows move to the screen you're working on, keeping their place on it.
    func followWithPinnedWindows() {
        guard !settings.pinnedBundleIDs.isEmpty, let active = targetDisplay() else { return }
        let displays = Display.current()
        for window in pinnedWindows() {
            guard let frame = window.frame,
                  let from = displays.containing(CGPoint(x: frame.midX, y: frame.midY)),
                  from.uuid != active.uuid else { continue }
            // Same relative position on the new screen, clamped to fit.
            let rx = (frame.minX - from.rect.minX) / max(from.rect.width - frame.width, 1)
            let ry = (frame.minY - from.rect.minY) / max(from.rect.height - frame.height, 1)
            let size = CGSize(width: min(frame.width, active.rect.width), height: min(frame.height, active.rect.height))
            let origin = CGPoint(x: active.rect.minX + max(0, min(1, rx)) * (active.rect.width - size.width),
                                 y: active.rect.minY + max(0, min(1, ry)) * (active.rect.height - size.height))
            window.setFrame(CGRect(origin: origin, size: size).integral)
        }
    }

    // MARK: - The Dock's All Desktops setting

    /// Writes the Dock's "All Desktops" assignment for an app and restarts the Dock to apply it.
    /// Unpinning restores the app's own Dock assignment (This Desktop, Desktop 2…), if it had one.
    private func setAllDesktops(_ on: Bool, for bundleID: String) {
        let domain = "com.apple.spaces" as CFString
        let key = "app-bindings" as CFString
        let id = bundleID.lowercased()
        var bindings = CFPreferencesCopyAppValue(key, domain) as? [String: String] ?? [:]
        var previous = settings.previousSpaceBindings
        if on {
            if let old = bindings[id], old != "AllSpaces" { previous[id] = old }
            bindings[id] = "AllSpaces"
        } else {
            bindings[id] = previous.removeValue(forKey: id)
        }
        settings.previousSpaceBindings = previous
        CFPreferencesSetAppValue(key, bindings as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        // The Dock reads the assignments at launch; macOS starts it again straight away.
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Dock"]
        try? restart.run()
    }

    /// Asks once before the first pin, since it briefly restarts the Dock.
    private static func confirmDockRestart(pinning: Bool) -> Bool {
        let key = "pinRestartConfirmed"
        if UserDefaults.standard.bool(forKey: key) { return true }
        let alert = NSAlert()
        alert.messageText = pinning ? "Pin to every desktop?" : "Unpin from every desktop?"
        alert.informativeText = """
        Jharokha uses the same setting as the Dock's Options › All Desktops. macOS only applies it \
        when the Dock restarts, so the Dock will disappear for a second. Your windows aren't affected.
        """
        alert.addButton(withTitle: pinning ? "Pin" : "Unpin")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        if confirmed && alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: key) }
        return confirmed
    }
}
