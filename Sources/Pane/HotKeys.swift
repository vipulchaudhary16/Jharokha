import Carbon

/// Global keyboard shortcuts through Carbon's RegisterEventHotKey, which needs no extra
/// permission and only ever sees Pane's own key combinations.
final class HotKeys {
    static let shared = HotKeys()

    /// ⌃⌥, the default prefix.
    static let prefix = UInt32(controlKey | optionKey)

    enum Key: UInt32 {
        case left = 123, right = 124, down = 125, up = 126
        case returnKey = 36, rightBracket = 30, leftBracket = 33, grave = 50
        case f = 3, z = 6, r = 15
        case one = 18, two = 19, three = 20, four = 21, five = 23
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false

    func register(_ key: Key, modifiers: UInt32 = prefix, _ handler: @escaping () -> Void) {
        installIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5041_4E45), id: nextID) // 'PANE'
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(key.rawValue, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else {
            NSLog("Pane: shortcut for key \(key) is already taken by another app")
            return
        }
        refs.append(ref)
        handlers[nextID] = handler
        nextID += 1
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            HotKeys.shared.handlers[hotKey.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
