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

    /// Tile rects (top-left origin, y down, like the Accessibility API) for `count` windows.
    /// Index 0 is the primary tile. `gap` is applied between tiles and at the outer edge.
    public static func frames(kind: LayoutKind, count: Int, in rect: CGRect, mainRatio: CGFloat,
                              gap: CGFloat, shape: ScreenShape) -> [CGRect] {
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
        let kind = effectiveKind(kind, shape: shape)
        let ratio = min(max(mainRatio, 0.2), 0.8)
        let area = rect.insetBy(dx: gap / 2, dy: gap / 2)

        let raw: [CGRect]
        if shape == .vertical {
            // A vertical monitor is the landscape layout transposed: "left" becomes "top".
            // Rows on a vertical screen are landscape columns transposed.
            let landscapeKind: LayoutKind = kind == .rows ? .columns : kind
            raw = landscape(landscapeKind, count, area.transposed, ratio, ultrawide: false).map(\.transposed)
        } else {
            raw = landscape(kind, count, area, ratio, ultrawide: shape == .ultrawide)
        }
        return raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).integral }
    }

    private static func landscape(_ kind: LayoutKind, _ n: Int, _ r: CGRect, _ ratio: CGFloat,
                                  ultrawide: Bool) -> [CGRect] {
        if n == 1 { return [r] }
        switch kind {
        case .grid:
            let (left, right) = r.splitX(ratio)
            switch n {
            case 2: return [left, right]
            case 3:
                let (rt, rb) = right.splitY(0.5)
                return [left, rt, rb]
            default:
                let (lt, lb) = left.splitY(0.5)
                let (rt, rb) = right.splitY(0.5)
                return [lt, rt, rb, lb]
            }
        case .columns:
            let (first, rest) = r.splitX(ratio)
            return [first] + rest.equalColumns(n - 1)
        case .rows:
            let (first, rest) = r.splitY(ratio)
            return [first] + rest.equalRows(n - 1)
        case .side:
            if ultrawide && n >= 3 {
                // Two large windows on the left, the rest in a quarter-width column.
                let (main, column) = r.splitX(0.75)
                let (a, b) = main.splitX(ratio)
                return [a, b] + column.equalRows(n - 2)
            }
            let (main, column) = r.splitX(ratio)
            return [main] + column.equalRows(n - 1)
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

extension CGRect {
    var transposed: CGRect { CGRect(x: minY, y: minX, width: height, height: width) }

    func splitX(_ ratio: CGFloat) -> (CGRect, CGRect) {
        let w = (width * ratio).rounded()
        return (CGRect(x: minX, y: minY, width: w, height: height),
                CGRect(x: minX + w, y: minY, width: width - w, height: height))
    }

    func splitY(_ ratio: CGFloat) -> (CGRect, CGRect) {
        let h = (height * ratio).rounded()
        return (CGRect(x: minX, y: minY, width: width, height: h),
                CGRect(x: minX, y: minY + h, width: width, height: height - h))
    }

    func equalColumns(_ n: Int) -> [CGRect] {
        (0..<n).map { i in
            let x0 = (minX + width * CGFloat(i) / CGFloat(n)).rounded()
            let x1 = (minX + width * CGFloat(i + 1) / CGFloat(n)).rounded()
            return CGRect(x: x0, y: minY, width: x1 - x0, height: height)
        }
    }

    func equalRows(_ n: Int) -> [CGRect] {
        (0..<n).map { i in
            let y0 = (minY + height * CGFloat(i) / CGFloat(n)).rounded()
            let y1 = (minY + height * CGFloat(i + 1) / CGFloat(n)).rounded()
            return CGRect(x: minX, y: y0, width: width, height: y1 - y0)
        }
    }
}
