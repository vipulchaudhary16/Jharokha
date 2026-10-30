import AppKit
import JharokhaCore

// Private SkyLight calls, the only way to know which Space a display is showing.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ connection: Int32, _ display: CFString) -> UInt64
@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: Int32) -> UInt64
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> Unmanaged<CFArray>?

/// A screen as the tiler sees it: its usable rect in AX coordinates and the Space it shows.
struct Display {
    let screen: NSScreen
    let uuid: String
    let space: UInt64
    /// The Space's own UUID, which macOS keeps across restarts (its numeric ID may not).
    let spaceUUID: String
    /// "Desktop 2" is 2: the Space's position among this screen's desktops.
    let desktopNumber: Int
    /// The visible frame (below the menu bar, beside the Dock) in AX coordinates (top-left origin).
    let rect: CGRect

    var shape: ScreenShape { ScreenShape.of(rect.size) }
    /// Tiling state is kept per display and per Space.
    var key: String { "\(uuid)#\(space)" }
    /// Like `key`, but stable across restarts: what saved layouts are stored under.
    var persistentKey: String { "\(uuid)#\(spaceUUID)" }
    var desktopName: String { "Desktop \(desktopNumber)" }

    /// Managed Space ID → (UUID, desktop number), from the window server's Space list.
    private static var cachedSpaces: (at: Date, info: [UInt64: (uuid: String, number: Int)])?

    private static func spaceInfo(_ connection: Int32) -> [UInt64: (uuid: String, number: Int)] {
        if let cached = cachedSpaces, Date().timeIntervalSince(cached.at) < 0.5 { return cached.info }
        let info = readSpaceInfo(connection)
        cachedSpaces = (Date(), info)
        return info
    }

    private static func readSpaceInfo(_ connection: Int32) -> [UInt64: (uuid: String, number: Int)] {
        guard let displays = CGSCopyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else { return [:] }
        var info: [UInt64: (String, Int)] = [:]
        for display in displays {
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            var desktop = 0
            for space in spaces {
                // Type 0 is an ordinary desktop; full-screen apps have their own Spaces.
                if (space["type"] as? Int ?? 0) == 0 { desktop += 1 }
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? (space["id64"] as? NSNumber)?.uint64Value
                else { continue }
                info[id] = (space["uuid"] as? String ?? "\(id)", max(desktop, 1))
            }
        }
        return info
    }

    static func current() -> [Display] {
        guard let primary = NSScreen.screens.first else { return [] }
        let connection = CGSMainConnectionID()
        let spaces = spaceInfo(connection)
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let cfUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
                  let uuid = CFUUIDCreateString(nil, cfUUID) as String? else { return nil }
            var space = CGSManagedDisplayGetCurrentSpace(connection, uuid as CFString)
            // With "Displays have separate Spaces" off there is a single active Space.
            if space == 0 { space = CGSGetActiveSpace(connection) }
            let visible = screen.visibleFrame
            let rect = CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY,
                              width: visible.width, height: visible.height)
            let info = spaces[space]
            return Display(screen: screen, uuid: uuid, space: space, spaceUUID: info?.uuid ?? "\(space)",
                           desktopNumber: info?.number ?? 1, rect: rect)
        }
    }
}

extension Array where Element == Display {
    /// The display containing a point (AX coordinates), falling back to the closest one.
    func containing(_ point: CGPoint) -> Display? {
        // Use full screen frames so points in the menu bar or Dock area still match their screen.
        guard let primary = NSScreen.screens.first else { return first }
        func axFrame(_ d: Display) -> CGRect {
            let f = d.screen.frame
            return CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        }
        if let hit = first(where: { axFrame($0).contains(point) }) { return hit }
        return self.min { a, b in
            hypot(axFrame(a).midX - point.x, axFrame(a).midY - point.y)
                < hypot(axFrame(b).midX - point.x, axFrame(b).midY - point.y)
        }
    }

    /// The nearest display in a direction from another one.
    func neighbor(of display: Display, direction: Direction) -> Display? {
        let rects = map(\.rect)
        guard let index = firstIndex(where: { $0.uuid == display.uuid }) else { return nil }
        return LayoutEngine.neighbor(of: index, in: rects, direction: direction).map { self[$0] }
    }
}

extension NSEvent {
    /// The mouse location in AX coordinates.
    static var axMouseLocation: CGPoint {
        let p = mouseLocation
        let height = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: p.x, y: height - p.y)
    }
}
