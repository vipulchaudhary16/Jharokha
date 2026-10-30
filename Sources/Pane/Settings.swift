import AppKit
import PaneCore

/// User preferences, persisted in UserDefaults. Layout and window count are per display.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    /// Apps that are never tiled unless the user turns tiling on for them.
    static let defaultExcluded: Set<String> = [
        "com.apple.calculator",
        "com.apple.Stickies",
        "com.apple.systempreferences",
        "com.apple.ScreenContinuity", // iPhone Mirroring
        "com.apple.PhotoBooth",
    ]

    var isTilingEnabled: Bool {
        get { defaults.object(forKey: "tilingEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "tilingEnabled") }
    }

    /// Share of the screen the main window starts with: 0.5, 0.6 or 2/3.
    var mainRatio: Double {
        get { defaults.object(forKey: "mainRatio") as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "mainRatio") }
    }

    var gap: Double {
        get { defaults.object(forKey: "gap") as? Double ?? 8 }
        set { defaults.set(newValue, forKey: "gap") }
    }

    /// Apps pinned to every desktop: never tiled, and following you between screens.
    var pinnedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "pinnedBundleIDs") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "pinnedBundleIDs") }
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? Array(Self.defaultExcluded)) }
        set { defaults.set(Array(newValue).sorted(), forKey: "excludedBundleIDs") }
    }

    enum HighlightStyle: String, CaseIterable {
        case none, activeBorder, allBorders, glow
        var title: String {
            switch self {
            case .none: return "None"
            case .activeBorder: return "Active Border"
            case .allBorders: return "All Borders"
            case .glow: return "Glow"
            }
        }
    }

    enum HighlightColor: String, CaseIterable {
        case accent, blue, purple, pink, orange, green, graphite
        var title: String { rawValue == "accent" ? "Accent Color" : rawValue.capitalized }
        var color: NSColor {
            switch self {
            case .accent: return .controlAccentColor
            case .blue: return .systemBlue
            case .purple: return .systemPurple
            case .pink: return .systemPink
            case .orange: return .systemOrange
            case .green: return .systemGreen
            case .graphite: return .systemGray
            }
        }
    }

    enum CleanSpaceBackground: String, CaseIterable {
        case graphite, mist, stone
        var title: String { rawValue.capitalized }
        var color: NSColor {
            switch self {
            case .graphite: return NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
            case .mist: return NSColor(calibratedRed: 0.86, green: 0.87, blue: 0.89, alpha: 1)
            case .stone: return NSColor(calibratedRed: 0.62, green: 0.58, blue: 0.53, alpha: 1)
            }
        }
    }

    var highlightStyle: HighlightStyle {
        get { defaults.string(forKey: "highlightStyle").flatMap(HighlightStyle.init(rawValue:)) ?? .activeBorder }
        set { defaults.set(newValue.rawValue, forKey: "highlightStyle") }
    }

    var highlightColor: HighlightColor {
        get { defaults.string(forKey: "highlightColor").flatMap(HighlightColor.init(rawValue:)) ?? .accent }
        set { defaults.set(newValue.rawValue, forKey: "highlightColor") }
    }

    /// The grip above the active window, with stack chips or quick actions on hover.
    var showsQuickActions: Bool {
        get { defaults.object(forKey: "showsQuickActions") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showsQuickActions") }
    }

    /// When apps' minimum sizes don't fit a screen, overlap them slightly instead of stacking.
    var overlapsWhenCrowded: Bool {
        get { defaults.object(forKey: "overlapsWhenCrowded") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "overlapsWhenCrowded") }
    }

    /// Give the biggest tiles to the windows that need the most room.
    var arrangesBySize: Bool {
        get { defaults.object(forKey: "arrangesBySize") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "arrangesBySize") }
    }

    /// Windows glide into their tiles instead of jumping.
    var animatesWindows: Bool {
        get { defaults.object(forKey: "animatesWindows") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "animatesWindows") }
    }

    /// A soft blur with the app's icon over windows while they change size.
    var veilsResizing: Bool {
        get { defaults.object(forKey: "veilsResizing") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "veilsResizing") }
    }

    /// Activate a tiled window when the pointer rests on it.
    var hoverFocus: Bool {
        get { defaults.object(forKey: "hoverFocus") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hoverFocus") }
    }

    /// How dark No peek makes other windows, 0.1...0.9.
    var noPeekDim: Double {
        get { defaults.object(forKey: "noPeekDim") as? Double ?? 0.5 }
        set { defaults.set(min(max(newValue, 0.1), 0.9), forKey: "noPeekDim") }
    }

    var noPeekBlur: Bool {
        get { defaults.object(forKey: "noPeekBlur") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "noPeekBlur") }
    }

    /// Clean Space zooms the shared window to fill the screen, instead of keeping its tile
    /// with the other windows shown as placeholder cards.
    var cleanSpaceFillsScreen: Bool {
        get { defaults.object(forKey: "cleanSpaceFillsScreen") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "cleanSpaceFillsScreen") }
    }

    var cleanSpaceBackground: CleanSpaceBackground {
        get { defaults.string(forKey: "cleanSpaceBackground").flatMap(CleanSpaceBackground.init(rawValue:)) ?? .graphite }
        set { defaults.set(newValue.rawValue, forKey: "cleanSpaceBackground") }
    }

    /// The smallest size each app has been seen to accept, learned from frames it refused.
    /// Kept on this Mac only.
    func learnedMinimum(for bundleID: String) -> CGSize {
        guard let pair = learnedMinimums[bundleID], pair.count == 2 else { return .zero }
        return CGSize(width: pair[0], height: pair[1])
    }

    func setLearnedMinimum(_ size: CGSize, for bundleID: String) {
        var all = learnedMinimums
        all[bundleID] = [Double(size.width), Double(size.height)]
        learnedMinimums = all
    }

    func forgetLearnedMinimum(for bundleID: String) {
        var all = learnedMinimums
        guard all.removeValue(forKey: bundleID) != nil else { return }
        learnedMinimums = all
    }

    func forgetLearnedMinimums() { learnedMinimums = [:] }

    /// Dock desktop assignments apps had before Pane pinned them, by lowercased bundle ID.
    var previousSpaceBindings: [String: String] {
        get { defaults.dictionary(forKey: "previousSpaceBindings") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "previousSpaceBindings") }
    }

    /// Read on every layout pass (many times over while placing by size), so kept in memory.
    private var cachedMinimums: [String: [Double]]?
    private var learnedMinimums: [String: [Double]] {
        get {
            if let cachedMinimums { return cachedMinimums }
            let stored = defaults.dictionary(forKey: "learnedMinimums") as? [String: [Double]] ?? [:]
            cachedMinimums = stored
            return stored
        }
        set {
            cachedMinimums = newValue
            defaults.set(newValue, forKey: "learnedMinimums")
        }
    }

    /// One layout and count for every screen and desktop, instead of each desktop
    /// remembering its own (the default).
    var appliesToAllScreens: Bool {
        get { defaults.object(forKey: "sameLayoutEverywhere") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "sameLayoutEverywhere") }
    }

    /// The defaults key for a per-desktop setting: shared everywhere, or this desktop's own,
    /// falling back to the last choice made anywhere until this desktop gets one.
    private func key(_ name: String, for display: Display, writing: Bool = false) -> String {
        let own = "\(name).\(display.persistentKey)"
        if appliesToAllScreens { return "\(name).all" }
        return writing || defaults.object(forKey: own) != nil ? own : "\(name).all"
    }

    func layout(for display: Display) -> LayoutKind {
        defaults.string(forKey: key("layout", for: display)).flatMap(LayoutKind.init(rawValue:))
            ?? LayoutEngine.defaultKind(for: display.shape)
    }

    func setLayout(_ kind: LayoutKind, for display: Display) {
        defaults.set(kind.rawValue, forKey: key("layout", for: display, writing: true))
        defaults.set(kind.rawValue, forKey: "layout.all")   // new desktops start from the latest choice
    }

    /// How many windows get their own tile on this display (default 3), clamped to what the
    /// layout allows there, so one shared count suits a laptop and a big monitor alike.
    func capacity(for display: Display) -> Int {
        let requested = defaults.object(forKey: key("count", for: display)) as? Int ?? 3
        return min(max(requested, 1), maxCount(for: display))
    }

    func setCapacity(_ count: Int, for display: Display) {
        defaults.set(count, forKey: key("count", for: display, writing: true))
        defaults.set(count, forKey: "count.all")
    }

    /// Custom split sizes per desktop, layout and count (see `TilingManager.weightsKey`).
    var splitWeights: [String: SplitWeights] {
        get { defaults.dictionary(forKey: "splitWeights") as? [String: SplitWeights] ?? [:] }
        set { defaults.set(newValue, forKey: "splitWeights") }
    }

    /// A desktop's saved arrangement: for each tile, the bundle IDs of its windows.
    func savedArrangement(for display: Display) -> [[String]]? {
        defaults.dictionary(forKey: "savedArrangements")?[display.persistentKey] as? [[String]]
    }

    func setSavedArrangement(_ arrangement: [[String]]?, for display: Display) {
        var all = defaults.dictionary(forKey: "savedArrangements") ?? [:]
        all[display.persistentKey] = arrangement
        defaults.set(all, forKey: "savedArrangements")
    }

    func maxCount(for display: Display) -> Int {
        LayoutEngine.maxCount(kind: layout(for: display), shape: display.shape, size: display.rect.size)
    }
}
