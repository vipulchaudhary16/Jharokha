import AppKit
import IOKit.pwr_mgt
import Security

/// Black Out: every screen goes black so the Mac looks locked, while it stays awake and
/// apps keep running. Esc three times (or the password, if one is set) brings it back;
/// the lock key or ⌃⌘Q locks the Mac for real and lifts the black screen.
final class BlackOut {
    static let shared = BlackOut()

    private(set) var isOn = false
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sleepAssertion: IOPMAssertionID = 0
    private var escapes: [Date] = []
    private var typed = ""
    private var savedOptions: NSApplication.PresentationOptions = []

    func start() {
        guard !isOn else { return }
        isOn = true
        escapes = []
        typed = ""

        NSApp.activate(ignoringOtherApps: true)
        savedOptions = NSApp.presentationOptions
        // No Dock, menu bar or ⌘Tab: nothing on screen gives away that the Mac is unlocked.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        coverScreens()
        NSCursor.hide()

        // Keep the display (and so the Mac) awake: a sleeping display can make macOS lock.
        IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Jharokha Black Out" as CFString, &sleepAssertion)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        // The lock key, Touch ID button or the Apple menu locked the Mac: get out of the way.
        observe(distributed, "com.apple.screenIsLocked")
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue)
        observe(workspace, NSWorkspace.willSleepNotification.rawValue)
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.coverScreens()
            }))
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach { center, token in center.removeObserver(token) }
        observers = []
        if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion) }
        sleepAssertion = 0
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.unhide()
        NSApp.presentationOptions = savedOptions
        typed = ""
    }

    private func observe(_ center: NotificationCenter, _ name: String) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
        observers.append((center, token))
    }

    /// One black window per screen, above everything, on every desktop.
    private func coverScreens() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = BlackWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        windows.first?.makeKey()
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // ⌃⌘Q: lock for real.
        if event.keyCode == 12, mods.contains(.control), mods.contains(.command) {
            lockScreen()
            return
        }
        let password = BlackOutPassword.current
        if event.keyCode == 53 {                           // ⎋
            typed = ""
            guard password == nil else { return }
            let now = Date()
            escapes = escapes.filter { now.timeIntervalSince($0) < 1.5 } + [now]
            if escapes.count >= 3 { stop() }
            return
        }
        guard let password else { return }
        switch event.keyCode {
        case 36, 76:                                       // Return
            if typed == password { stop() }
            typed = ""
        case 51:                                           // ⌫
            if !typed.isEmpty { typed.removeLast() }
        default:
            typed += event.characters ?? ""
            if typed.count > 256 { typed = "" }
        }
    }

    /// Locks the Mac like the lock key, then lifts the black screen behind the lock screen.
    func lockScreen() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias Lock = @convention(c) () -> Int32
            _ = unsafeBitCast(symbol, to: Lock.self)()
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["displaysleepnow"]
            try? task.run()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.stop() }
    }
}

/// Borderless windows can't take key status by default; Black Out needs the keys.
private final class BlackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The optional Black Out password, kept in the login keychain.
enum BlackOutPassword {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Jharokha Black Out",
        kSecAttrAccount as String: "unlock",
    ]

    static var current: String? {
        var query = query
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// Nil or empty removes it, so Esc three times works again.
    static func set(_ password: String?) {
        SecItemDelete(query as CFDictionary)
        guard let password, !password.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
