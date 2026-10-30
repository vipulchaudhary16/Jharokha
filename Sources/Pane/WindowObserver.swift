import AppKit
import ApplicationServices

/// Watches every regular app for window lifecycle events and reports them as a single
/// "something changed" signal; the tiler re-reads the world rather than trusting events.
final class WindowObserver {
    enum Change {
        /// A window appeared; its AX attributes may still be settling.
        case created
        case destroyed
        case focusChanged
        case movedOrResized
        case other
    }

    var onChange: ((Change) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    /// Windows already registered for kAXUIElementDestroyedNotification, per app.
    private var watchedWindows: [pid_t: Set<CGWindowID>] = [:]
    private var tokens: [NSObjectProtocol] = []

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    func start() {
        NSWorkspace.shared.runningApplications.forEach(observe)
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observe(app)
            self?.onChange?(.created)
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.forget(app.processIdentifier)
            self?.onChange?(.destroyed)
        })
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.onChange?(.focusChanged)
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.onChange?(.other)
        })
    }

    /// Not every app forwards window-level notifications to the app element, so each window
    /// is also watched directly. Called by the tiler for every window it sees.
    func watch(_ window: AXWindow) {
        guard let observer = observers[window.pid], !(watchedWindows[window.pid]?.contains(window.id) ?? false) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
        guard result == .success || result == .notificationAlreadyRegistered else { return }
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
        watchedWindows[window.pid, default: []].insert(window.id)
    }

    private static let windowNotifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }

        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            me.received(notification as String)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func forget(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        watchedWindows[pid] = nil
    }

    private func received(_ notification: String) {
        switch notification {
        case kAXWindowCreatedNotification, kAXWindowDeminiaturizedNotification, kAXApplicationShownNotification:
            onChange?(.created)
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXApplicationHiddenNotification:
            onChange?(.destroyed)
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            onChange?(.focusChanged)
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            onChange?(.movedOrResized)
        default:
            onChange?(.other)
        }
    }
}
