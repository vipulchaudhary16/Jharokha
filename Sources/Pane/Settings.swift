import Foundation
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

    func layout(for display: Display) -> LayoutKind {
        defaults.string(forKey: "layout.\(display.uuid)").flatMap(LayoutKind.init(rawValue:))
            ?? LayoutEngine.defaultKind(for: display.shape)
    }

    func setLayout(_ kind: LayoutKind, for display: Display) {
        defaults.set(kind.rawValue, forKey: "layout.\(display.uuid)")
    }

    /// How many windows get their own tile on this display (default 3), clamped to what the layout allows.
    func capacity(for display: Display) -> Int {
        let requested = defaults.object(forKey: "count.\(display.uuid)") as? Int ?? 3
        return min(max(requested, 1), maxCount(for: display))
    }

    func setCapacity(_ count: Int, for display: Display) {
        defaults.set(count, forKey: "count.\(display.uuid)")
    }

    func maxCount(for display: Display) -> Int {
        LayoutEngine.maxCount(kind: layout(for: display), shape: display.shape, size: display.rect.size)
    }
}
