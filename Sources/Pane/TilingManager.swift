import AppKit
import OSLog
import PaneCore

/// `log stream --predicate 'subsystem == "dev.pane.Pane"'` follows what the tiler does.
let log = Logger(subsystem: "dev.pane.Pane", category: "tiling")

/// Keeps every tileable window in its place. On any window event it re-reads the windows
/// on screen, reconciles them into per-display, per-Space tile state, and writes the frames
/// that differ. Commands mutate that state and apply it directly.
final class TilingManager {
    private let observer = WindowObserver()
    private let settings = Settings.shared

    private var states: [String: ScreenTiles] = [:]
    private var windows: [CGWindowID: AXWindow] = [:]
    /// Opening order; the earliest window on a screen is its primary.
    private var firstSeen: [CGWindowID: Int] = [:]
    private var seenCounter = 0
    private var floating: Set<CGWindowID> = []
    /// Focus mode: per display key, the window that fills the screen.
    private var focusMode: [String: CGWindowID] = [:]
    /// The frame Pane last asked each window to take.
    private var targets: [CGWindowID: CGRect] = [:]
    /// The last tiled window that had focus; new windows stack into its tile on a full screen.
    private var lastFocused: CGWindowID?
    private var bundleIDs: [CGWindowID: String] = [:]
    /// The tile rects last applied per display key, after minimum sizes were solved.
    private var appliedRects: [String: [CGRect]] = [:]
    /// Repeated writes of the same frame to one window; see `place`.
    private var writes: [CGWindowID: (target: CGRect, attempts: Int)] = [:]
    private var minimumsChanged = false
    /// Per display key, the app whose size made Pane tile fewer windows (to notify once).
    private var limitedBy: [String: String] = [:]

    private var pendingRefresh: DispatchWorkItem?
    private var dragTimer: Timer?
    private var healthTimer: Timer?
    /// Whether macOS currently accepts Pane's Accessibility calls.
    private(set) var accessUsable = true
    private(set) var isPausedForStageManager = false
    private(set) var isRunning = false

    /// Called after state changes the menu bar may want to reflect.
    var onStateChange: (() -> Void)?

    var tiledWindowCount: Int {
        Display.current().reduce(0) { $0 + (states[$1.key]?.allWindows.count ?? 0) }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        log.info("Tiling started")
        // An unresponsive app must not stall the tiler for the default 6 seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        observer.onChange = { [weak self] change in self?.handle(change) }
        observer.start()
        isPausedForStageManager = Self.isStageManagerOn
        accessUsable = AX.isUsable
        if !accessUsable { log.error("Accessibility access is granted but not usable yet") }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkStageManager()
            self?.checkAccess()
        }
        refresh()
    }

    // MARK: - Events

    private func handle(_ change: WindowObserver.Change) {
        switch change {
        case .created, .spaceChanged:
            scheduleRefresh(after: 0.05)
            // New windows often settle their role, size and position a moment after creation.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
        case .movedOrResized:
            if Self.isMouseDown { beginDragWatch() } else { scheduleRefresh(after: 0.08) }
        case .destroyed, .focusChanged, .other:
            scheduleRefresh(after: 0.03)
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static var isMouseDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }

    /// While the user holds the mouse (dragging or resizing a window), wait; act on release.
    private func beginDragWatch() {
        guard dragTimer == nil else { return }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self, !Self.isMouseDown else { return }
            timer.invalidate()
            self.dragTimer = nil
            self.handleDrop()
            self.refresh()
        }
    }

    private static var isStageManagerOn: Bool {
        let domain = "com.apple.WindowManager" as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue("GloballyEnabled" as CFString, domain) as? Bool ?? false
    }

    private func checkStageManager() {
        let on = Self.isStageManagerOn
        guard on != isPausedForStageManager else { return }
        isPausedForStageManager = on
        if !on { refresh() }
        onStateChange?()
    }

    /// When access starts working again (e.g. re-granted after a rebuild), observers created
    /// while it was broken never fire, so re-attach and tile everything.
    private func checkAccess() {
        let usable = AX.isUsable
        guard usable != accessUsable else { return }
        accessUsable = usable
        log.info("Accessibility access is \(usable ? "usable again" : "no longer usable", privacy: .public)")
        if usable {
            observer.reattach()
            writes.removeAll()
            refresh()
        }
        onStateChange?()
    }

    private var canTile: Bool {
        isRunning && settings.isTilingEnabled && AX.isTrusted && !isPausedForStageManager
    }

    // MARK: - Reconcile

    func refresh() {
        pendingRefresh?.cancel()
        guard canTile else { return }
        guard !Self.isMouseDown else { beginDragWatch(); return }

        let displays = Display.current()
        let (found, frontToBack) = enumerateWindows()
        windows = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Windows discovered together (e.g. at launch) are ordered front to back, so the
        // frontmost window becomes primary.
        let newWindows = found.map(\.id).filter { firstSeen[$0] == nil }
            .sorted { frontToBack[$0, default: .max] < frontToBack[$1, default: .max] }
        for id in newWindows {
            seenCounter += 1
            firstSeen[id] = seenCounter
        }
        floating.formIntersection(windows.keys)
        let focused = AX.focusedWindow()?.id

        var groups: [String: [CGWindowID]] = [:]
        for window in found where !floating.contains(window.id) {
            guard let frame = window.frame,
                  let display = displays.containing(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            groups[display.key, default: []].append(window.id)
        }

        for display in displays {
            var state = states[display.key] ?? ScreenTiles()
            let present = (groups[display.key] ?? []).sorted { firstSeen[$0, default: 0] < firstSeen[$1, default: 0] }
            let active = lastFocused.flatMap { state.tileIndex(of: $0) }
            state.reconcile(present: present, capacity: settings.capacity(for: display), activeTile: active)
            // ⌘-Tab, the Dock or a click can bring a stacked window forward; it becomes the showing one.
            if let focused { state.show(focused) }
            states[display.key] = state
            if let zoomed = focusMode[display.key], !state.contains(zoomed) { focusMode[display.key] = nil }
        }
        if let focused, windows[focused] != nil, !floating.contains(focused) { lastFocused = focused }

        apply(displays)
        onStateChange?()
    }

    /// Tileable windows, plus each on-screen window's z-order (0 = frontmost).
    private func enumerateWindows() -> ([AXWindow], [CGWindowID: Int]) {
        let excluded = settings.excludedBundleIDs
        // AX can report windows from other Spaces for some apps; keep only those on screen now.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var onScreen: [CGWindowID: Int] = [:]
        for (index, entry) in info.enumerated() {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID { onScreen[id] = index }
        }

        var result: [AXWindow] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            if let bundleID = app.bundleIdentifier, excluded.contains(bundleID) { continue }
            for window in AX.windows(of: app) where onScreen[window.id] != nil && window.isTileable {
                observer.watch(window)
                bundleIDs[window.id] = app.bundleIdentifier
                result.append(window)
            }
        }
        return (result, onScreen)
    }

    // MARK: - Apply

    private func frames(for display: Display, count: Int) -> [CGRect] {
        LayoutEngine.frames(kind: settings.layout(for: display), count: count, in: display.rect,
                            mainRatio: settings.mainRatio, gap: settings.gap, shape: display.shape)
    }

    /// The tile rects in use on a display (minimum sizes already solved).
    private func rects(for display: Display) -> [CGRect] {
        appliedRects[display.key] ?? frames(for: display, count: states[display.key]?.tiles.count ?? 0)
    }

    /// Writes the layout of each display; windows already in place are left alone,
    /// so the move/resize events caused by these writes settle after one pass.
    /// A pass that learns a new minimum size is followed by another, which makes room for it.
    private func apply(_ displays: [Display]) {
        for _ in 0..<3 {
            minimumsChanged = false
            displays.forEach(applyOnce)
            if !minimumsChanged { return }
        }
    }

    private func applyOnce(_ display: Display) {
        guard var state = states[display.key] else { return }
        let rects = solve(display, &state)
        states[display.key] = state
        appliedRects[display.key] = rects
        let zoomed = focusMode[display.key]
        let full = display.rect.insetBy(dx: settings.gap, dy: settings.gap)
        for (index, tile) in state.tiles.enumerated() where rects.indices.contains(index) {
            // Stacked windows sit behind the showing one at the same size; place them first.
            for id in tile.windows where id != tile.showing {
                place(id, id == zoomed ? full : rects[index])
            }
            place(tile.showing, tile.showing == zoomed ? full : rects[index])
        }
    }

    /// Lays out the display around each app's minimum size. When the windows cannot all
    /// fit, tiles fewer of them; the rest stack, so nothing extends off screen.
    private func solve(_ display: Display, _ state: inout ScreenTiles) -> [CGRect] {
        let reducedFrom = state.tiles.count
        while true {
            let minimums = state.tiles.map { tile in
                tile.windows.map(minimumSize).reduce(CGSize.zero) {
                    CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
                }
            }
            if let rects = LayoutEngine.fit(kind: settings.layout(for: display), count: state.tiles.count,
                                            in: display.rect, mainRatio: settings.mainRatio, gap: settings.gap,
                                            shape: display.shape, minimums: minimums) {
                if state.tiles.count < reducedFrom { notifyLimit(on: display, state: state) } else { limitedBy[display.key] = nil }
                return rects
            }
            // A single window larger than the screen: let the app clamp it.
            guard state.tiles.count > 1 else { return frames(for: display, count: 1) }
            state.normalize(capacity: state.tiles.count - 1)
        }
    }

    private func minimumSize(_ id: CGWindowID) -> CGSize {
        bundleIDs[id].map(settings.learnedMinimum) ?? .zero
    }

    private func notifyLimit(on display: Display, state: ScreenTiles) {
        // Name the app with the largest minimum on this screen.
        guard let culprit = state.allWindows.max(by: {
            let a = minimumSize($0), b = minimumSize($1)
            return a.width * a.height < b.width * b.height
        }), let window = windows[culprit],
              let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName,
              limitedBy[display.key] != name else { return }
        limitedBy[display.key] = name
        Toast.show("Tiling \(state.tiles.count) here: \(name) needs more room")
    }

    private func place(_ id: CGWindowID, _ rect: CGRect) {
        guard let window = windows[id] else { return }
        targets[id] = rect
        guard let frame = window.frame, !frame.isClose(to: rect) else {
            writes[id] = nil
            return
        }
        var write = writes[id] ?? (rect, 0)
        if !write.target.isClose(to: rect) { write = (rect, 0) }
        write.attempts += 1
        writes[id] = write
        // An app that keeps refusing the same frame (some apply their minimum a moment later)
        // would otherwise bounce forever: learn the size it insists on and stop writing.
        guard write.attempts <= 3 else {
            learnMinimum(id, accepted: frame, requested: rect)
            return
        }
        window.setFrame(rect)
        // Only a size that moved toward the request but stopped short is a minimum. A size that
        // hasn't changed yet may just be an app that resizes a moment later (Notes, Electron apps);
        // those are caught by the repeated-refusal check above once they settle.
        if let accepted = window.frame, !accepted.size.isClose(to: frame.size) {
            learnMinimum(id, accepted: accepted, requested: rect)
        }
    }

    /// An app that ends up larger than asked has a minimum size; remember it per app.
    private func learnMinimum(_ id: CGWindowID, accepted: CGRect, requested: CGRect) {
        guard let bundleID = bundleIDs[id] else { return }
        // A "minimum" larger than any screen is a misreading (e.g. a window mid-animation), not a limit.
        let roomiest = Display.current().map(\.rect.size)
        guard roomiest.contains(where: { accepted.width <= $0.width && accepted.height <= $0.height }) else { return }
        var learned = settings.learnedMinimum(for: bundleID)
        var grew = false
        if accepted.width > requested.width + 1, accepted.width > learned.width {
            learned.width = accepted.width.rounded(.up)
            grew = true
        }
        if accepted.height > requested.height + 1, accepted.height > learned.height {
            learned.height = accepted.height.rounded(.up)
            grew = true
        }
        guard grew else { return }
        settings.setLearnedMinimum(learned, for: bundleID)
        minimumsChanged = true
    }

    func forgetLearnedSizes() {
        settings.forgetLearnedMinimums()
        writes.removeAll()
        limitedBy.removeAll()
        refresh()
    }

    /// After the mouse is released: a window dropped on another tile swaps with it, a window
    /// dropped on another display moves there, anything else goes back to its place.
    private func handleDrop() {
        let mouse = NSEvent.axMouseLocation
        let displays = Display.current()
        for display in displays {
            guard var state = states[display.key] else { continue }
            for id in state.showingWindows {
                guard let frame = windows[id]?.frame, let target = targets[id],
                      frame.size.isClose(to: target.size), !frame.origin.isClose(to: target.origin) else { continue }
                if let destination = displays.containing(mouse), destination.key != display.key {
                    state.remove(id, capacity: settings.capacity(for: display))
                    states[display.key] = state
                    var other = states[destination.key] ?? ScreenTiles()
                    let rects = rects(for: destination)
                    other.insert(id, capacity: settings.capacity(for: destination),
                                 activeTile: LayoutEngine.tile(at: mouse, in: rects))
                    states[destination.key] = other
                } else if let from = state.tileIndex(of: id),
                          let to = LayoutEngine.tile(at: mouse, in: rects(for: display)),
                          from != to {
                    state.swapShowing(from, to)
                    states[display.key] = state
                }
                apply(displays)
                return
            }
        }
        apply(displays)
    }

    // MARK: - Commands

    private struct Context {
        let displays: [Display]
        let display: Display
        let tile: Int
        let window: CGWindowID
    }

    private func context() -> Context? {
        guard canTile, let id = AX.focusedWindow()?.id else { return nil }
        let displays = Display.current()
        for display in displays {
            if let tile = states[display.key]?.tileIndex(of: id) {
                return Context(displays: displays, display: display, tile: tile, window: id)
            }
        }
        return nil
    }

    /// The display a command without a focused tiled window acts on.
    func targetDisplay() -> Display? {
        let displays = Display.current()
        if let frame = AX.focusedWindow()?.frame,
           let display = displays.containing(CGPoint(x: frame.midX, y: frame.midY)) { return display }
        return displays.containing(NSEvent.axMouseLocation)
    }

    /// Swaps with the neighbour in a direction; past the screen edge, moves to the next display.
    func swap(_ direction: Direction) {
        guard let c = context(), var state = states[c.display.key] else { return }
        let rects = rects(for: c.display)
        if let neighbor = LayoutEngine.neighbor(of: c.tile, in: rects, direction: direction) {
            state.swapShowing(c.tile, neighbor)
            states[c.display.key] = state
            apply(c.displays)
        } else if let other = c.displays.neighbor(of: c.display, direction: direction) {
            state.remove(c.window, capacity: settings.capacity(for: c.display))
            states[c.display.key] = state
            var destination = states[other.key] ?? ScreenTiles()
            destination.insert(c.window, capacity: settings.capacity(for: other), activeTile: nil)
            states[other.key] = destination
            apply(c.displays)
        }
        windows[c.window]?.focus()
    }

    func makePrimary() {
        guard let c = context(), c.tile != 0 else { return }
        states[c.display.key]?.swapShowing(c.tile, 0)
        apply(c.displays)
        windows[c.window]?.focus()
    }

    /// Activates the next or previous tile's window on this screen.
    func activate(step: Int) {
        guard let c = context(), let showing = states[c.display.key]?.showingWindows, showing.count > 1 else { return }
        let next = showing[((c.tile + step) % showing.count + showing.count) % showing.count]
        windows[next]?.focus()
    }

    /// Shows the next or previous window in the active tile's stack.
    func cycleStack(step: Int) {
        guard let c = context(), let next = states[c.display.key]?.cycle(tile: c.tile, by: step) else { return }
        apply(c.displays)
        windows[next]?.focus()
    }

    func toggleFloat() {
        guard let id = AX.focusedWindow()?.id else { return }
        if floating.remove(id) != nil {
            Toast.show("Tiled")
            refresh()
            return
        }
        guard let c = context(), let window = windows[id] else { return }
        floating.insert(id)
        states[c.display.key]?.remove(id, capacity: settings.capacity(for: c.display))
        let area = c.display.rect
        let size = CGSize(width: min(window.frame?.width ?? area.width, area.width * 0.7),
                          height: min(window.frame?.height ?? area.height, area.height * 0.7))
        window.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                               width: size.width, height: size.height).integral)
        targets[id] = nil
        apply(c.displays)
        window.focus()
        Toast.show("Floating")
    }

    /// Fills the screen with the active window; pressed again — from any window on that
    /// screen — puts every window back.
    func toggleFocusMode() {
        guard canTile, let display = targetDisplay() else { return }
        let displays = Display.current()
        if let zoomed = focusMode.removeValue(forKey: display.key) {
            apply(displays)
            windows[zoomed]?.focus()
            Toast.show("Focus mode off")
        } else {
            guard let c = context() else { return }
            enterFocusMode(c.window, on: c.display, displays)
        }
        onStateChange?()
    }

    /// Focus mode for a chosen window (e.g. a tile picked in the menu preview): zooms it,
    /// switches the zoom to it if another window was zoomed, or turns focus mode off if it
    /// already was the zoomed one.
    func toggleFocusMode(window id: CGWindowID) {
        guard canTile else { return }
        let displays = Display.current()
        guard let display = displays.first(where: { states[$0.key]?.contains(id) ?? false }) else { return }
        if focusMode[display.key] == id {
            focusMode[display.key] = nil
            apply(displays)
            windows[id]?.focus()
            Toast.show("Focus mode off")
        } else {
            enterFocusMode(id, on: display, displays)
        }
        onStateChange?()
    }

    private func enterFocusMode(_ id: CGWindowID, on display: Display, _ displays: [Display]) {
        states[display.key]?.show(id)
        focusMode[display.key] = id
        apply(displays)
        windows[id]?.focus()
        Toast.show("Focus mode · ⌃⌥Z to put windows back")
    }

    /// Makes a tiled window the active one, bringing it forward in its stack.
    func activate(window id: CGWindowID) {
        guard let window = windows[id] else { return }
        let displays = Display.current()
        if let display = displays.first(where: { states[$0.key]?.contains(id) ?? false }),
           states[display.key]?.show(id) == true {
            apply(displays)
        }
        window.focus()
    }

    func appIcon(of id: CGWindowID) -> NSImage? {
        windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
    }

    func appName(of id: CGWindowID) -> (name: String, bundleID: String?)? {
        guard let window = windows[id], let app = NSRunningApplication(processIdentifier: window.pid) else { return nil }
        return (app.localizedName ?? app.bundleIdentifier ?? "App", app.bundleIdentifier)
    }

    func isFocusMode(on display: Display) -> Bool { focusMode[display.key] != nil }

    /// The tiles of a display as last applied, normalized to its usable area, for the menu preview.
    func preview(of display: Display) -> [LayoutPreviewView.Tile] {
        guard let state = states[display.key] else { return [] }
        let rects = rects(for: display)
        let focused = AX.focusedWindow()?.id ?? lastFocused
        let area = display.rect
        return state.tiles.enumerated().compactMap { index, tile in
            guard rects.indices.contains(index) else { return nil }
            let r = rects[index]
            let normalized = CGRect(x: (r.minX - area.minX) / area.width, y: (r.minY - area.minY) / area.height,
                                    width: r.width / area.width, height: r.height / area.height)
            let icon = windows[tile.showing].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.icon }
            return .init(window: tile.showing, rect: normalized, icon: icon,
                         isActive: tile.windows.contains { $0 == focused }, isStacked: tile.isStacked,
                         isZoomed: focusMode[display.key] == tile.showing)
        }
    }

    /// Puts every window back in its place and says whether anything had moved.
    /// Also re-attaches to every app and forgets refused writes, so it recovers tiling that
    /// stalled, e.g. after Accessibility access was re-granted while Pane was running.
    func retile() {
        guard AX.isUsable else {
            log.error("Retile: Accessibility access is not usable (\(String(describing: AX.probe()), privacy: .public))")
            AX.requestTrust()
            Toast.show("Turn Pane off and on in Settings › Privacy & Security › Accessibility")
            onStateChange?()
            return
        }
        if !settings.isTilingEnabled { settings.isTilingEnabled = true }
        if isRunning { observer.reattach() } else { start() }
        guard !isPausedForStageManager else {
            Toast.show("Paused while Stage Manager is on")
            return
        }
        let moved = targets.filter { id, target in
            guard let frame = windows[id]?.frame else { return false }
            return !frame.isClose(to: target)
        }.count
        // "Every window back in its place" includes leaving focus mode.
        focusMode.removeAll()
        writes.removeAll()
        limitedBy.removeAll()
        refresh()
        let tiled = tiledWindowCount
        log.info("Retile: \(tiled) windows tiled, \(moved) had moved")
        var message = tiled == 0 ? "No windows to tile on this Space"
            : moved == 0 ? "Tiling \(tiled) window\(tiled == 1 ? "" : "s")"
            : "Put \(moved) window\(moved == 1 ? "" : "s") back"
        // Say which visible apps are left out, so an excluded app isn't mistaken for a bug.
        let skipped = excludedAppsWithWindows()
        if !skipped.isEmpty {
            message += " · \(skipped.joined(separator: ", ")) \(skipped.count == 1 ? "is" : "are") excluded"
        }
        Toast.show(message)
    }

    /// Names of excluded apps that have a window on screen right now.
    private func excludedAppsWithWindows() -> [String] {
        let excluded = settings.excludedBundleIDs
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let owners = Set(info.compactMap { entry -> pid_t? in
            guard entry[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return entry[kCGWindowOwnerPID as String] as? pid_t
        })
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, excluded.contains(bundleID),
                  owners.contains(app.processIdentifier) else { return nil }
            return app.localizedName
        }.sorted()
    }

    func setCapacity(_ count: Int, on display: Display? = nil) {
        guard let display = display ?? targetDisplay() else { return }
        let max = settings.maxCount(for: display)
        // Stored unclamped: with a shared count, each screen takes as many as its layout allows.
        settings.setCapacity(count, for: display)
        if count > max { Toast.show("This screen holds up to \(max) windows in \(settings.layout(for: display).title)") }
        relayout(scope(display))
    }

    func setLayout(_ kind: LayoutKind, on display: Display? = nil) {
        guard let display = display ?? targetDisplay() else { return }
        settings.setLayout(kind, for: display)
        relayout(scope(display))
    }

    /// The screens a layout or count change made on `display` applies to (nil = all).
    /// Other Spaces pick the change up as soon as you switch to them.
    private func scope(_ display: Display) -> Display? {
        settings.appliesToAllScreens ? nil : display
    }

    /// Re-applies layout after a setting changed (layout, count, main size, spacing).
    func relayout(_ display: Display? = nil) {
        let displays = Display.current()
        for d in displays where display == nil || d.uuid == display?.uuid {
            states[d.key]?.normalize(capacity: settings.capacity(for: d))
        }
        if canTile { apply(displays) }
        onStateChange?()
    }

    func setTilingEnabled(_ enabled: Bool) {
        settings.isTilingEnabled = enabled
        if enabled { refresh() }
        onStateChange?()
    }

    func setTiling(_ enabled: Bool, forBundleID bundleID: String) {
        var excluded = settings.excludedBundleIDs
        if enabled { excluded.remove(bundleID) } else { excluded.insert(bundleID) }
        settings.excludedBundleIDs = excluded
        refresh()
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? bundleID
        Toast.show(enabled ? "\(name) is tiled again" : "\(name) won't be tiled · choose again to include it")
    }
}

private extension CGFloat {
    func isClose(to other: CGFloat) -> Bool { abs(self - other) <= 1.5 }
}

extension CGPoint {
    func isClose(to other: CGPoint) -> Bool { x.isClose(to: other.x) && y.isClose(to: other.y) }
}

extension CGSize {
    func isClose(to other: CGSize) -> Bool { width.isClose(to: other.width) && height.isClose(to: other.height) }
}

extension CGRect {
    func isClose(to other: CGRect) -> Bool { origin.isClose(to: other.origin) && size.isClose(to: other.size) }
}
