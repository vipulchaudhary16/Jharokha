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

    /// Windows glide into their tiles instead of jumping.
    var animatesWindows: Bool {
        get { defaults.object(forKey: "animatesWindows") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "animatesWindows") }
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
        defaults.set(all, forKey: "learnedMinimums")
    }

    func forgetLearnedMinimums() {
        defaults.removeObject(forKey: "learnedMinimums")
    }

    private var learnedMinimums: [String: [Double]] {
        defaults.dictionary(forKey: "learnedMinimums") as? [String: [Double]] ?? [:]
    }

    /// Layout and window-count changes go to every screen (the default), or only to the
    /// screen they were made on. Either way they apply to every Space of that screen.
    var appliesToAllScreens: Bool {
        get { defaults.object(forKey: "appliesToAllScreens") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "appliesToAllScreens") }
    }

    /// The defaults key for a per-screen setting: shared by all screens, or one screen's own,
    /// falling back to the shared value until that screen is changed.
    private func key(_ name: String, for display: Display, writing: Bool = false) -> String {
        let own = "\(name).\(display.uuid)"
        if appliesToAllScreens { return "\(name).all" }
        return writing || defaults.object(forKey: own) != nil ? own : "\(name).all"
    }

    func layout(for display: Display) -> LayoutKind {
        defaults.string(forKey: key("layout", for: display)).flatMap(LayoutKind.init(rawValue:))
            ?? LayoutEngine.defaultKind(for: display.shape)
    }

    func setLayout(_ kind: LayoutKind, for display: Display) {
        defaults.set(kind.rawValue, forKey: key("layout", for: display, writing: true))
    }

    /// How many windows get their own tile on this display (default 3), clamped to what the
    /// layout allows there, so one shared count suits a laptop and a big monitor alike.
    func capacity(for display: Display) -> Int {
        let requested = defaults.object(forKey: key("count", for: display)) as? Int ?? 3
        return min(max(requested, 1), maxCount(for: display))
    }

    func setCapacity(_ count: Int, for display: Display) {
        defaults.set(count, forKey: key("count", for: display, writing: true))
    }

    func maxCount(for display: Display) -> Int {
        LayoutEngine.maxCount(kind: layout(for: display), shape: display.shape, size: display.rect.size)
    }
}
