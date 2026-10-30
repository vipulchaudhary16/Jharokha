import CoreGraphics

public enum LayoutKind: String, CaseIterable, Codable, Sendable {
    case grid, columns, rows, side

    public var title: String {
        switch self {
        case .grid: return "Grid"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .side: return "Side"
        }
    }
}

public enum ScreenShape: Sendable, Equatable {
    case standard, ultrawide, vertical

    /// Ultrawide means at least twice as wide as tall (21:9 and wider).
    public static func of(_ size: CGSize) -> ScreenShape {
        if size.height > size.width { return .vertical }
        if size.width >= 2 * size.height { return .ultrawide }
        return .standard
    }
}

public enum Direction: Sendable, CaseIterable {
    case left, right, up, down
}

/// A layout is a tree of splits. Each split divides its rect along one axis between
/// weighted children; leaves are tile indices. Minimum sizes are solved on this tree,
/// so a window that needs more room takes it from its neighbours.
indirect enum LayoutNode {
    enum Axis { case x, y }

    case leaf(Int)
    case split(Axis, [(weight: CGFloat, node: LayoutNode)])

    var transposed: LayoutNode {
        switch self {
        case .leaf: return self
        case .split(let axis, let children):
            return .split(axis == .x ? .y : .x, children.map { ($0.weight, $0.node.transposed) })
        }
    }

    static func even(_ axis: Axis, _ range: Range<Int>) -> LayoutNode {
        .split(axis, range.map { (1, .leaf($0)) })
    }
}

public enum LayoutEngine {
    /// Screens at least this wide (in points) count as "bigger monitors" and hold more windows.
    public static let largeScreenWidth: CGFloat = 1800

    /// Columns makes no sense on a vertical monitor; it falls back to Rows.
    public static func effectiveKind(_ kind: LayoutKind, shape: ScreenShape) -> LayoutKind {
        if shape == .vertical && kind == .columns { return .rows }
        return kind
    }

    public static func defaultKind(for shape: ScreenShape) -> LayoutKind {
        shape == .vertical ? .rows : .grid
    }

    public static func maxCount(kind: LayoutKind, shape: ScreenShape, size: CGSize) -> Int {
        let large = shape != .standard || size.width >= largeScreenWidth
        switch effectiveKind(kind, shape: shape) {
        case .grid: return 4
        case .columns: return large ? 4 : 3
        case .rows: return large ? 3 : 2
        case .side: return shape == .standard ? (large ? 4 : 3) : 5
        }
    }

    /// Tile rects (top-left origin, y down, like the Accessibility API) for `count` windows,
    /// ignoring minimum sizes. Index 0 is the primary tile.
    public static func frames(kind: LayoutKind, count: Int, in rect: CGRect, mainRatio: CGFloat,
                              gap: CGFloat, shape: ScreenShape) -> [CGRect] {
        fit(kind: kind, count: count, in: rect, mainRatio: mainRatio, gap: gap, shape: shape, minimums: []) ?? []
    }

    /// Tile rects that respect each tile's minimum size, or nil when they cannot all fit.
    /// `minimums[i]` is the minimum for tile i; missing entries mean no minimum.
    public static func fit(kind: LayoutKind, count: Int, in rect: CGRect, mainRatio: CGFloat,
                           gap: CGFloat, shape: ScreenShape, minimums: [CGSize]) -> [CGRect]? {
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
        let ratio = min(max(mainRatio, 0.2), 0.8)
        let tree = layoutTree(kind: effectiveKind(kind, shape: shape), count: count, ratio: ratio, shape: shape)
        var rects = [CGRect](repeating: .null, count: count)
        let mins = (0..<count).map { $0 < minimums.count ? minimums[$0] : .zero }
        guard place(tree, in: rect.insetBy(dx: gap, dy: gap), gap: gap, minimums: mins, into: &rects) else { return nil }
        return rects
    }

    static func layoutTree(kind: LayoutKind, count n: Int, ratio: CGFloat, shape: ScreenShape) -> LayoutNode {
        if shape == .vertical {
            // A vertical monitor is the landscape layout transposed: "left" becomes "top".
            // Rows on a vertical screen are landscape columns transposed.
            let landscapeKind: LayoutKind = kind == .rows ? .columns : kind
            return landscapeTree(landscapeKind, n, ratio, ultrawide: false).transposed
        }
        return landscapeTree(kind, n, ratio, ultrawide: shape == .ultrawide)
    }

    private static func landscapeTree(_ kind: LayoutKind, _ n: Int, _ ratio: CGFloat, ultrawide: Bool) -> LayoutNode {
        if n == 1 { return .leaf(0) }
        let rest = 1 - ratio
        switch kind {
        case .grid:
            // Each new window takes half of the newest space; the fourth takes the
            // bottom half of the primary's column.
            switch n {
            case 2: return .split(.x, [(ratio, .leaf(0)), (rest, .leaf(1))])
            case 3: return .split(.x, [(ratio, .leaf(0)), (rest, .even(.y, 1..<3))])
            default:
                return .split(.x, [(ratio, .split(.y, [(1, .leaf(0)), (1, .leaf(3))])),
                                   (rest, .even(.y, 1..<3))])
            }
        case .columns:
            return .split(.x, [(ratio, .leaf(0))] + (1..<n).map { (rest / CGFloat(n - 1), .leaf($0)) })
        case .rows:
            return .split(.y, [(ratio, .leaf(0))] + (1..<n).map { (rest / CGFloat(n - 1), .leaf($0)) })
        case .side:
            if ultrawide && n >= 3 {
                // Two large windows on the left, the rest in a quarter-width column.
                return .split(.x, [(0.75 * ratio, .leaf(0)), (0.75 * rest, .leaf(1)), (0.25, .even(.y, 2..<n))])
            }
            return .split(.x, [(ratio, .leaf(0)), (rest, n == 2 ? .leaf(1) : .even(.y, 1..<n))])
        }
    }

    private static func minimumSize(of node: LayoutNode, _ minimums: [CGSize], gap: CGFloat) -> CGSize {
        switch node {
        case .leaf(let i): return minimums[i]
        case .split(let axis, let children):
            let sizes = children.map { minimumSize(of: $0.node, minimums, gap: gap) }
            let gaps = gap * CGFloat(children.count - 1)
            return axis == .x
                ? CGSize(width: sizes.map(\.width).reduce(0, +) + gaps, height: sizes.map(\.height).max() ?? 0)
                : CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +) + gaps)
        }
    }

    private static func place(_ node: LayoutNode, in rect: CGRect, gap: CGFloat, minimums: [CGSize],
                              into rects: inout [CGRect]) -> Bool {
        switch node {
        case .leaf(let i):
            let need = minimums[i]
            guard need.width <= rect.width + 0.5, need.height <= rect.height + 0.5 else { return false }
            rects[i] = rect
            return true
        case .split(let axis, let children):
            let length = axis == .x ? rect.width : rect.height
            let available = length - gap * CGFloat(children.count - 1)
            let mins = children.map { child -> CGFloat in
                let size = minimumSize(of: child.node, minimums, gap: gap)
                return axis == .x ? size.width : size.height
            }
            guard let sizes = allocate(available, weights: children.map(\.weight), minimums: mins) else { return false }
            // Round cumulative offsets, not sizes, so the children always end exactly at the far edge.
            var start: CGFloat = 0
            var cumulative: CGFloat = 0
            for (index, child) in children.enumerated() {
                cumulative += sizes[index]
                let end = index == children.count - 1 ? available : cumulative.rounded()
                let childRect = axis == .x
                    ? CGRect(x: rect.minX + start + gap * CGFloat(index), y: rect.minY, width: end - start, height: rect.height)
                    : CGRect(x: rect.minX, y: rect.minY + start + gap * CGFloat(index), width: rect.width, height: end - start)
                guard place(child.node, in: childRect, gap: gap, minimums: minimums, into: &rects) else { return false }
                start = end
            }
            return true
        }
    }

    /// Shares `total` by weight, but no child gets less than its minimum; the space
    /// a constrained child takes comes out of the others in proportion to their weights.
    static func allocate(_ total: CGFloat, weights: [CGFloat], minimums: [CGFloat]) -> [CGFloat]? {
        guard minimums.reduce(0, +) <= total + 0.5 else { return nil }
        var fixed = [Bool](repeating: false, count: weights.count)
        var sizes = [CGFloat](repeating: 0, count: weights.count)
        while true {
            let freeWeight = zip(weights, fixed).filter { !$0.1 }.map(\.0).reduce(0, +)
            let remaining = total - zip(minimums, fixed).filter(\.1).map(\.0).reduce(0, +)
            guard freeWeight > 0 else {
                // Every child is at its minimum; hand the leftover out by weight.
                let weightSum = weights.reduce(0, +)
                return zip(minimums, weights).map { $0 + (total - minimums.reduce(0, +)) * $1 / weightSum }
            }
            var changed = false
            for i in weights.indices where !fixed[i] {
                sizes[i] = remaining * weights[i] / freeWeight
                if sizes[i] < minimums[i] {
                    sizes[i] = minimums[i]
                    fixed[i] = true
                    changed = true
                }
            }
            if !changed { return sizes }
        }
    }

    /// The tile adjacent to `index` in `direction`, preferring the closest edge,
    /// then the best overlap on the perpendicular axis.
    public static func neighbor(of index: Int, in rects: [CGRect], direction: Direction) -> Int? {
        guard rects.indices.contains(index) else { return nil }
        let a = rects[index]
        let tolerance: CGFloat = 2
        var best: (index: Int, distance: CGFloat, offset: CGFloat)?
        for (i, b) in rects.enumerated() where i != index {
            let distance: CGFloat
            let overlaps: Bool
            let offset: CGFloat
            switch direction {
            case .left:
                distance = a.minX - b.maxX
                overlaps = b.maxX <= a.minX + tolerance && b.minY < a.maxY && b.maxY > a.minY
                offset = abs(b.midY - a.midY)
            case .right:
                distance = b.minX - a.maxX
                overlaps = b.minX >= a.maxX - tolerance && b.minY < a.maxY && b.maxY > a.minY
                offset = abs(b.midY - a.midY)
            case .up:
                distance = a.minY - b.maxY
                overlaps = b.maxY <= a.minY + tolerance && b.minX < a.maxX && b.maxX > a.minX
                offset = abs(b.midX - a.midX)
            case .down:
                distance = b.minY - a.maxY
                overlaps = b.minY >= a.maxY - tolerance && b.minX < a.maxX && b.maxX > a.minX
                offset = abs(b.midX - a.midX)
            }
            guard overlaps else { continue }
            if let current = best,
               (current.distance, current.offset) <= (distance, offset) { continue }
            best = (i, distance, offset)
        }
        return best?.index
    }

    /// Index of the rect containing `point`, if any.
    public static func tile(at point: CGPoint, in rects: [CGRect]) -> Int? {
        rects.firstIndex { $0.contains(point) }
    }
}
