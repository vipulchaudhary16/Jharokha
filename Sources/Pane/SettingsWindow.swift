import AppKit
import ServiceManagement
import SwiftUI

/// Settings: General options and the keyboard shortcut editor.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    /// Layout settings changed (main size, spacing, all screens): re-lay out the windows.
    var onLayoutSettingsChanged: (() -> Void)?
    /// Smart placement was switched on: re-arrange now.
    var onRearrange: (() -> Void)?
    var onForgetSizes: (() -> Void)?
    /// Re-registers shortcuts after an edit; set by the app delegate.
    var onShortcutsChanged: (() -> Void)?
    var onSettingsChanged: (() -> Void)?

    func show(tab: SettingsView.Tab = .general) {
        let view = SettingsView(tab: tab, onShortcutsChanged: { [weak self] in self?.onShortcutsChanged?() },
                                onSettingsChanged: { [weak self] in self?.onSettingsChanged?() })
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Pane Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    enum Tab: Hashable { case general, keyboard }
    @State var tab: Tab
    let onShortcutsChanged: () -> Void
    let onSettingsChanged: () -> Void

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(onChange: onSettingsChanged)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            KeyboardSettings(onChange: onShortcutsChanged)
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(Tab.keyboard)
        }
        .frame(width: 560, height: 620)
    }
}

private struct GeneralSettings: View {
    let onChange: () -> Void
    private let settings = Settings.shared
    private var controller: SettingsWindowController { .shared }
    @State private var mainRatio = Settings.shared.mainRatio
    @State private var gap = Int(Settings.shared.gap)
    @State private var allScreens = Settings.shared.appliesToAllScreens
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var highlight = Settings.shared.highlightStyle
    @State private var color = Settings.shared.highlightColor
    @State private var quickActions = Settings.shared.showsQuickActions
    @State private var animate = Settings.shared.animatesWindows
    @State private var smart = Settings.shared.arrangesBySize
    @State private var overlap = Settings.shared.overlapsWhenCrowded
    @State private var veil = Settings.shared.veilsResizing
    @State private var hoverFocus = Settings.shared.hoverFocus
    @State private var dim = Settings.shared.noPeekDim
    @State private var blur = Settings.shared.noPeekBlur
    @State private var background = Settings.shared.cleanSpaceBackground
    @State private var cleanFills = Settings.shared.cleanSpaceFillsScreen

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Main window size", selection: $mainRatio) {
                    Text("Half").tag(0.5)
                    Text("60%").tag(0.6)
                    Text("Two-thirds").tag(2.0 / 3.0)
                }
                .onChange(of: mainRatio) { _, value in settings.mainRatio = value; controller.onLayoutSettingsChanged?() }
                Picker("Spacing", selection: $gap) {
                    ForEach([0, 4, 8, 12, 16], id: \.self) { Text($0 == 0 ? "None" : "\($0) pt").tag($0) }
                }
                .onChange(of: gap) { _, value in settings.gap = Double(value); controller.onLayoutSettingsChanged?() }
                Toggle("Same layout on every screen and desktop", isOn: $allScreens)
                    .onChange(of: allScreens) { _, value in settings.appliesToAllScreens = value; controller.onLayoutSettingsChanged?() }
                Text("Off: each desktop remembers its own layout, window count and sizes, even after a restart.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Smart placement: windows that need more room get the bigger tiles", isOn: $smart)
                    .onChange(of: smart) { _, value in settings.arrangesBySize = value; controller.onRearrange?() }
                Toggle("On small screens, overlap windows that can't shrink instead of stacking them", isOn: $overlap)
                    .onChange(of: overlap) { _, value in settings.overlapsWhenCrowded = value; controller.onRearrange?() }
                LabeledContent("Learned window sizes") {
                    Button("Forget") { controller.onForgetSizes?() }
                }
            }
            Section("Highlight") {
                Picker("Style", selection: $highlight) {
                    ForEach(Settings.HighlightStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: highlight) { _, value in settings.highlightStyle = value; onChange() }
                Picker("Color", selection: $color) {
                    ForEach(Settings.HighlightColor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: color) { _, value in settings.highlightColor = value; onChange() }
            }
            Section("Windows") {
                Toggle("Animate windows into place", isOn: $animate)
                    .onChange(of: animate) { _, value in settings.animatesWindows = value; onChange() }
                Toggle("Blur windows while they resize", isOn: $veil)
                    .onChange(of: veil) { _, value in settings.veilsResizing = value; onChange() }
                Toggle("Quick actions above the active window", isOn: $quickActions)
                    .onChange(of: quickActions) { _, value in settings.showsQuickActions = value; onChange() }
                Toggle("Activate windows on hover", isOn: $hoverFocus)
                    .onChange(of: hoverFocus) { _, value in settings.hoverFocus = value; onChange() }
            }
            Section("Startup") {
                Toggle("Open Pane at login", isOn: $login)
                    .onChange(of: login) { _, value in
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSAlert(error: error).runModal()
                        }
                        login = SMAppService.mainApp.status == .enabled
                    }
            }
            Section("No peek") {
                LabeledContent("Dim other windows") {
                    Slider(value: $dim, in: 0.1...0.9) { Text("\(Int(dim * 100))%") }
                        .onChange(of: dim) { _, value in settings.noPeekDim = value; onChange() }
                }
                Toggle("Blur other windows", isOn: $blur)
                    .onChange(of: blur) { _, value in settings.noPeekBlur = value; onChange() }
            }
            Section("Privacy Mode") {
                Picker("Background", selection: $background) {
                    ForEach(Settings.CleanSpaceBackground.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: background) { _, value in settings.cleanSpaceBackground = value; onChange() }
                Toggle("Fill the screen with the shared window", isOn: $cleanFills)
                    .onChange(of: cleanFills) { _, value in settings.cleanSpaceFillsScreen = value; onChange() }
                Text("Off: the shared window keeps its place, and the others show as cards with their app's icon and name — never their content.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeyboardSettings: View {
    let onChange: () -> Void
    private let store = ShortcutStore.shared
    @State private var enabled = ShortcutStore.shared.areEnabled
    @State private var version = 0

    var body: some View {
        Form {
            Section {
                Toggle("Keyboard shortcuts", isOn: $enabled)
                    .onChange(of: enabled) { _, value in store.areEnabled = value; onChange(); version += 1 }
                Text("Click a shortcut and press new keys. ⌫ turns it off, ⎋ cancels.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(ShortcutAction.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(ShortcutAction.allCases.filter { $0.group == group }, id: \.self) { action in
                        ShortcutRow(action: action, version: version) {
                            onChange()
                            version += 1
                        }
                    }
                }
            }
            Section {
                Button("Restore Defaults") {
                    ShortcutAction.allCases.forEach { store.set($0.defaultShortcut, for: $0) }
                    onChange()
                    version += 1
                }
            }
        }
        .formStyle(.grouped)
        .disabled(false)
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    let version: Int
    let onChange: () -> Void
    private let store = ShortcutStore.shared

    var body: some View {
        let shortcut = store.shortcut(for: action)
        let conflict = conflictMessage(shortcut)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let conflict {
                    Text(conflict.text).font(.caption).foregroundStyle(.orange)
                    if let suggestion = conflict.suggestion {
                        Button("Use \(suggestion.display)") {
                            store.set(suggestion, for: action)
                            onChange()
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }
            }
            Spacer()
            ShortcutRecorder(display: store.display(for: action)) { recorded in
                store.set(recorded, for: action)
                onChange()
            }
            .frame(width: 110, height: 24)
        }
        .id("\(action.rawValue)-\(version)")
    }

    private func conflictMessage(_ shortcut: Shortcut?) -> (text: String, suggestion: Shortcut?)? {
        guard let shortcut, store.areEnabled else { return nil }
        let taken = HotKeys.shared.taken
        let message: String
        if let other = store.action(using: shortcut, except: action) {
            message = "Also used for “\(other.title)”"
        } else if store.systemShortcuts().contains(shortcut) {
            message = "macOS uses this shortcut"
        } else if taken.contains(shortcut) {
            message = "Another app uses this shortcut"
        } else {
            return nil
        }
        return (message, store.suggestion(for: shortcut, action: action, taken: taken))
    }
}

/// A button that records the next key combination pressed. Pane's own shortcuts are
/// paused while recording, so pressing one doesn't trigger it.
private struct ShortcutRecorder: NSViewRepresentable {
    let display: String
    /// nil means the shortcut was turned off.
    let onRecord: (Shortcut?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = onRecord
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.idleTitle = display
        button.onRecord = onRecord
    }
}

final class RecorderButton: NSButton {
    /// Only one field records at a time.
    private static weak var active: RecorderButton?
    var onRecord: ((Shortcut?) -> Void)?
    var idleTitle = "" { didSet { if !isRecording { title = idleTitle } } }
    private var isRecording = false
    private var monitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        RecorderButton.active?.stop()
        RecorderButton.active = self
        isRecording = true
        title = "Press keys…"
        HotKeys.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: self.stop()                                   // ⎋ cancels
            case 51, 117: self.stop(); self.onRecord?(nil)         // ⌫ turns it off
            default:
                guard let shortcut = Shortcut(event: event) else { NSSound.beep(); return nil }
                self.stop()
                self.onRecord?(shortcut)
            }
            return nil
        }
    }

    /// Leaving the field any way at all (closing the window, switching tabs, the row being
    /// rebuilt) ends recording, so Pane's shortcuts are always registered again.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isRecording { stop() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification,
                                                   object: window)
        }
    }

    @objc private func windowResigned() { if isRecording { stop() } }

    private func stop() {
        guard isRecording || monitor != nil else { return }
        if RecorderButton.active === self { RecorderButton.active = nil }
        isRecording = false
        title = idleTitle
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Re-registers everything (including the unchanged shortcuts) through the app delegate.
        SettingsWindowController.shared.onShortcutsChanged?()
    }
}
