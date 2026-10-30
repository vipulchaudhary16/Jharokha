import Carbon

/// Global keyboard shortcuts through Carbon's RegisterEventHotKey, which needs no extra
/// permission and only ever sees Jharokha's own key combinations.
final class HotKeys {
    static let shared = HotKeys()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false
    /// Combinations another app already holds, found when registering.
    private(set) var taken: Set<Shortcut> = []

    /// Registers every enabled shortcut from the store, replacing the previous set.
    func apply(_ store: ShortcutStore, perform: @escaping (ShortcutAction) -> Void) {
        unregisterAll()
        taken = []
        guard store.areEnabled else { return }
        for action in ShortcutAction.allCases {
            guard let shortcut = store.shortcut(for: action) else { continue }
            if !register(shortcut, { perform(action) }) { taken.insert(shortcut) }
        }
    }

    /// Unregisters everything, e.g. while the shortcut editor records a new combination.
    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
    }

    @discardableResult
    private func register(_ shortcut: Shortcut, _ handler: @escaping () -> Void) -> Bool {
        installIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5041_4E45), id: nextID) // 'PANE'
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else {
            log.error("Shortcut \(shortcut.display, privacy: .public) is already taken by another app")
            return false
        }
        refs.append(ref)
        handlers[nextID] = handler
        nextID += 1
        return true
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
