import AppKit
import Carbon

/// A key combination in Carbon terms: a virtual key code plus Carbon modifier flags.
struct Shortcut: Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let prefix = UInt32(controlKey | optionKey)

    init(_ keyCode: Int, _ modifiers: UInt32 = prefix) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = modifiers
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let mods = Self.carbonModifiers(event.modifierFlags)
        // A shortcut needs ⌃, ⌥ or ⌘ so it can't swallow ordinary typing.
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let specialKeys: [UInt32: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 76: "⌤",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// The character this key types on the current keyboard layout.
    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Every action that can have a keyboard shortcut, with its default.
enum ShortcutAction: String, CaseIterable {
    case swapLeft, swapRight, swapUp, swapDown
    case makePrimary, nextWindow, previousWindow, nextInTile, previousInTile, stackDown, stackUp, tabView, tabViewBackward
    case grow, shrink, resetSizes
    case float, alwaysFloat, pinApp, focusMode, noPeek, cleanSpace, retile
    case tile1, tile2, tile3, tile4, tile5

    enum Group: String, CaseIterable { case move = "Move", activate = "Activate", size = "Size", more = "More" }

    var group: Group {
        switch self {
        case .swapLeft, .swapRight, .swapUp, .swapDown: return .move
        case .makePrimary, .nextWindow, .previousWindow, .nextInTile, .previousInTile, .stackDown, .stackUp, .tabView, .tabViewBackward:
            return .activate
        case .grow, .shrink, .resetSizes: return .size
        default: return .more
        }
    }

    var title: String {
        switch self {
        case .swapLeft: return "Swap with the window on the left"
        case .swapRight: return "Swap with the window on the right"
        case .swapUp: return "Swap with the window above"
        case .swapDown: return "Swap with the window below"
        case .makePrimary: return "Make the active window primary"
        case .nextWindow: return "Activate the next window"
        case .previousWindow: return "Activate the previous window"
        case .nextInTile: return "Show the next window in this tile"
        case .previousInTile: return "Show the previous window in this tile"
        case .stackDown: return "Scroll down through this tile's stack"
        case .stackUp: return "Scroll up through this tile's stack"
        case .tabView: return "Tab View: every window, by screen"
        case .tabViewBackward: return "Tab View, moving backwards"
        case .grow: return "Make the active window bigger"
        case .shrink: return "Make the active window smaller"
        case .resetSizes: return "Reset window sizes on this screen"
        case .float: return "Float the active window, or tile it again"
        case .alwaysFloat: return "Always float windows like the active one"
        case .pinApp: return "Pin the active app to every desktop"
        case .focusMode: return "Focus mode"
        case .noPeek: return "No peek: fade every other window"
        case .cleanSpace: return "Privacy Mode: share one window, the rest as app cards"
        case .retile: return "Re-apply tiling"
        case .tile1: return "Tile 1 window on this screen"
        case .tile2: return "Tile up to 2 windows"
        case .tile3: return "Tile up to 3 windows"
        case .tile4: return "Tile up to 4 windows"
        case .tile5: return "Tile up to 5 windows"
        }
    }

    var defaultShortcut: Shortcut {
        let p = Shortcut.prefix
        let shift = UInt32(shiftKey), cmd = UInt32(cmdKey)
        switch self {
        case .swapLeft: return Shortcut(123)
        case .swapRight: return Shortcut(124)
        case .swapUp: return Shortcut(126)
        case .swapDown: return Shortcut(125)
        case .makePrimary: return Shortcut(36)
        case .nextWindow: return Shortcut(30)
        case .previousWindow: return Shortcut(33)
        case .nextInTile: return Shortcut(50)
        case .previousInTile: return Shortcut(50, p | shift)
        case .stackDown: return Shortcut(125, p | cmd)
        case .stackUp: return Shortcut(126, p | cmd)
        case .tabView: return Shortcut(48, UInt32(optionKey))
        case .tabViewBackward: return Shortcut(48, UInt32(optionKey) | shift)
        case .grow: return Shortcut(24)
        case .shrink: return Shortcut(27)
        case .resetSizes: return Shortcut(29)
        case .float: return Shortcut(3)
        case .alwaysFloat: return Shortcut(3, p | shift)
        case .pinApp: return Shortcut(35, p | cmd)
        case .focusMode: return Shortcut(6)
        case .noPeek: return Shortcut(2)
        case .cleanSpace: return Shortcut(35)
        case .retile: return Shortcut(15)
        case .tile1: return Shortcut(18, p | cmd)
        case .tile2: return Shortcut(19, p | cmd)
        case .tile3: return Shortcut(20, p | cmd)
        case .tile4: return Shortcut(21, p | cmd)
        case .tile5: return Shortcut(23, p | cmd)
        }
    }
}

/// The user's shortcuts: defaults, overrides and "off", persisted in UserDefaults.
final class ShortcutStore {
    static let shared = ShortcutStore()
    private let defaults = UserDefaults.standard

    /// The shortcut for an action, or nil when the user turned it off.
    func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard let stored = defaults.array(forKey: "shortcut.\(action.rawValue)") as? [Int] else { return action.defaultShortcut }
        guard stored.count == 2 else { return nil }
        return Shortcut(keyCode: UInt32(stored[0]), modifiers: UInt32(stored[1]))
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut, shortcut == action.defaultShortcut {
            defaults.removeObject(forKey: "shortcut.\(action.rawValue)")
        } else if let shortcut {
            defaults.set([Int(shortcut.keyCode), Int(shortcut.modifiers)], forKey: "shortcut.\(action.rawValue)")
        } else {
            defaults.set([Int](), forKey: "shortcut.\(action.rawValue)") // empty = off
        }
    }

    var areEnabled: Bool {
        get { defaults.object(forKey: "shortcutsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shortcutsEnabled") }
    }

    func display(for action: ShortcutAction) -> String { shortcut(for: action)?.display ?? "Off" }

    /// " · ⌃⌥D to stop" for notices and subtitles, or nothing when the shortcut is off.
    func hint(_ action: ShortcutAction, _ text: String? = nil) -> String {
        guard areEnabled, let shortcut = shortcut(for: action) else { return "" }
        return " · \(shortcut.display)" + (text.map { " \($0)" } ?? "")
    }

    /// The other Pane action already using this combination, if any.
    func action(using shortcut: Shortcut, except: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != except && self.shortcut(for: $0) == shortcut }
    }

    /// Enabled macOS keyboard shortcuts (System Settings › Keyboard › Shortcuts) as Carbon combos.
    func systemShortcuts() -> Set<Shortcut> {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") as? [String: [String: Any]] else { return [] }
        var result = Set<Shortcut>()
        for entry in all.values {
            guard entry["enabled"] as? Bool ?? (entry["enabled"] as? Int == 1),
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count == 3,
                  parameters[1] != 65535 else { continue }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))
            result.insert(Shortcut(keyCode: UInt32(parameters[1]), modifiers: Shortcut.carbonModifiers(flags)))
        }
        return result
    }

    /// A combination for the same key that neither macOS nor another Pane action uses.
    func suggestion(for shortcut: Shortcut, action: ShortcutAction, taken: Set<Shortcut>) -> Shortcut? {
        let options: [UInt32] = [
            Shortcut.prefix, Shortcut.prefix | UInt32(shiftKey), Shortcut.prefix | UInt32(cmdKey),
            UInt32(controlKey | shiftKey | cmdKey), UInt32(optionKey | cmdKey),
        ]
        let system = systemShortcuts()
        return options.lazy
            .map { Shortcut(keyCode: shortcut.keyCode, modifiers: $0) }
            .first { $0 != shortcut && !system.contains($0) && !taken.contains($0) && self.action(using: $0, except: action) == nil }
    }
}
