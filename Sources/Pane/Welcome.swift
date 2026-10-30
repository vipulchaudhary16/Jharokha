import AppKit
import SwiftUI

/// The first-run welcome: what Pane does, why it needs Accessibility access, the shortcuts
/// worth knowing, and a choice to tidy windows now or later. Nothing moves until it's done.
final class WelcomeController {
    static let shared = WelcomeController()
    private var window: NSWindow?

    /// `onFinish(tidy)` runs once, when the last step is chosen or the window is closed.
    func show(onFinish: @escaping (_ tidy: Bool) -> Void) {
        var finished = false
        let finish: (Bool) -> Void = { [weak self] tidy in
            guard !finished else { return }
            finished = true
            Settings.shared.hasOnboarded = true
            self?.window?.close()
            self?.window = nil
            onFinish(tidy)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(onFinish: finish)))
        window.title = "Welcome to Pane"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        // Closing it is "not now": tiling stays off until switched on from the menu.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            finish(false)
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let onFinish: (Bool) -> Void
    @State private var step = 0
    @State private var trusted = AX.isUsable
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: intro
                case 1: access
                case 2: shortcuts
                default: tidy
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                .accessibilityLabel("Step \(step + 1) of \(steps)")
                Spacer()
                if step > 0 && step < steps - 1 {
                    Button("Back") { go(step - 1) }.buttonStyle(.borderless)
                }
                footerButton
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 540, height: 470)
        .onReceive(poll) { _ in trusted = AX.isUsable }
    }

    @ViewBuilder private var footerButton: some View {
        switch step {
        case 0: Button("Get Started") { go(1) }.keyboardShortcut(.defaultAction).controlSize(.large)
        case 1: Button("Continue") { go(2) }.keyboardShortcut(.defaultAction).controlSize(.large).disabled(!trusted)
        case 2: Button("Continue") { go(3) }.keyboardShortcut(.defaultAction).controlSize(.large)
        default: EmptyView()
        }
    }

    private func go(_ next: Int) {
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(duration: 0.35)) { step = next }
    }

    // MARK: Steps

    private var intro: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Welcome to Pane").font(.system(size: 28, weight: .bold))
            Text("Pane arranges your windows into tiles the moment you open them. No dragging, no snapping.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
            VStack(alignment: .leading, spacing: 12) {
                feature("rectangle.split.2x2", "Four layouts, remembered for each desktop")
                feature("square.stack", "Windows stack neatly when a screen is full")
                feature("eye.slash", "Focus, No Peek and Privacy Mode for screen sharing")
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
    }

    private var access: some View {
        VStack(spacing: 16) {
            Image(systemName: trusted ? "checkmark.shield.fill" : "lock.shield")
                .font(.system(size: 54)).foregroundStyle(trusted ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
            Text("Let Pane move your windows").font(.system(size: 24, weight: .bold))
            Text("macOS lets window managers move windows only with Accessibility access. Pane uses it just to see where windows are and put them in place. It never records your screen and doesn't use the network.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            if trusted {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
            } else {
                Button("Open Accessibility Settings") {
                    AX.requestTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .controlSize(.large)
                Text("Turn on Pane in the list, then come back here.").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 40)
    }

    private var shortcuts: some View {
        VStack(spacing: 16) {
            Text("A few keys worth knowing").font(.system(size: 24, weight: .bold))
            Text("Pane lives in the menu bar. These work from any app:").foregroundStyle(.secondary)
            VStack(spacing: 8) {
                shortcut(.swapRight, "Swap with the window beside it", fallback: "⌃⌥ arrows")
                shortcut(.makePrimary, "Make the active window the main one")
                shortcut(.stackDown, "Scroll through a stack")
                shortcut(.focusMode, "Focus Mode: one window fills the screen")
                shortcut(.cleanSpace, "Privacy Mode for screen sharing")
                shortcut(.retile, "Put every window back in place")
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            Text("Change any of them in Settings › Keyboard.").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 40)
    }

    private var tidy: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 54)).foregroundStyle(Color.accentColor)
            Text("Ready for your first tidy?").font(.system(size: 24, weight: .bold))
            Text("Pane will arrange the windows on your screens now. Re-apply puts them back any time, and you can switch Automatic Tiling off from the menu bar.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 12) {
                Button("Not Now") { onFinish(false) }.controlSize(.large)
                Button("Tidy My Windows") { onFinish(true) }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
                    .disabled(!trusted)
            }
            .padding(.top, 8)
            if !trusted {
                Text("Pane needs Accessibility access first.").font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: Pieces

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24)
        }
        .font(.body)
    }

    private func shortcut(_ action: ShortcutAction, _ text: String, fallback: String? = nil) -> some View {
        HStack {
            Text(text)
            Spacer()
            Text(fallback ?? ShortcutStore.shared.shortcut(for: action)?.display ?? "—")
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
        .frame(width: 400)
    }
}
