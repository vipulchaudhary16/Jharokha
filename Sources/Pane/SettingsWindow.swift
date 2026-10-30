import AppKit
import SwiftUI

/// Settings: General options and the keyboard shortcut editor.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
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
    @State private var highlight = Settings.shared.highlightStyle
    @State private var color = Settings.shared.highlightColor
    @State private var quickActions = Settings.shared.showsQuickActions
    @State private var hoverFocus = Settings.shared.hoverFocus
    @State private var dim = Settings.shared.noPeekDim
    @State private var blur = Settings.shared.noPeekBlur
    @State private var background = Settings.shared.cleanSpaceBackground

    var body: some View {
        Form {
            Section("Highlight") {
                Picker("Style", selection: $highlight) {
                    ForEach(Settings.HighlightStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: highlight) { settings.highlightStyle = $0; onChange() }
                Picker("Color", selection: $color) {
                    ForEach(Settings.HighlightColor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: color) { settings.highlightColor = $0; onChange() }
            }
            Section("Windows") {
                Toggle("Quick actions above the active window", isOn: $quickActions)
                    .onChange(of: quickActions) { settings.showsQuickActions = $0; onChange() }
                Toggle("Activate windows on hover", isOn: $hoverFocus)
                    .onChange(of: hoverFocus) { settings.hoverFocus = $0; onChange() }
            }
            Section("No peek") {
                LabeledContent("Dim other windows") {
                    Slider(value: $dim, in: 0.1...0.9) { Text("\(Int(dim * 100))%") }
                        .onChange(of: dim) { settings.noPeekDim = $0; onChange() }
                }
                Toggle("Blur other windows", isOn: $blur)
                    .onChange(of: blur) { settings.noPeekBlur = $0; onChange() }
            }
            Section("Clean Space") {
                Picker("Background", selection: $background) {
                    ForEach(Settings.CleanSpaceBackground.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .onChange(of: background) { settings.cleanSpaceBackground = $0; onChange() }
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
                    .onChange(of: enabled) { store.areEnabled = $0; onChange(); version += 1 }
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

    private func stop() {
        isRecording = false
        title = idleTitle
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Re-registers everything (including the unchanged shortcuts) through the app delegate.
        SettingsWindowController.shared.onShortcutsChanged?()
    }
}
