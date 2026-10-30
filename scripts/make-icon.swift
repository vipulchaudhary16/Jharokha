// Draws Jharokha's app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift   (from the repository root; needs iconutil)
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    NSColor(calibratedRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha).cgColor
}

/// A round-topped arch: straight sides from `bottom`, a half circle on top.
func archPath(minX: CGFloat, maxX: CGFloat, bottom: CGFloat, springLine: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let radius = (maxX - minX) / 2
    path.move(to: CGPoint(x: minX, y: bottom))
    path.addLine(to: CGPoint(x: minX, y: springLine))
    path.addArc(center: CGPoint(x: minX + radius, y: springLine), radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
    path.addLine(to: CGPoint(x: maxX, y: bottom))
    path.closeSubpath()
    return path
}

/// Jharokha's icon: a carved sandstone palace window on terracotta, its panes the tiles,
/// the main one lit like a window with the sun behind it.
func drawIcon(in ctx: CGContext) {
    // macOS icon grid: an 824 pt rounded square centred on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let corner: CGFloat = 186
    let space = CGColorSpaceCreateDeviceRGB()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Terracotta, like the walls of a Rajasthani haveli.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    let wall = CGGradient(colorsSpace: space, colors: [color(0xE55A33), color(0x9C2E18)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(wall, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // A faint jaali of small rings across the wall.
    ctx.setStrokeColor(color(0xFFE2C4, 0.06))
    ctx.setLineWidth(5)
    var y = body.minY + 20
    var row = 0
    while y < body.maxY {
        var x = body.minX + (row % 2 == 0 ? 20 : 56)
        while x < body.maxX {
            ctx.strokeEllipse(in: CGRect(x: x - 22, y: y - 22, width: 44, height: 44))
            x += 72
        }
        y += 62
        row += 1
    }
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFB27A, 0.45), color(0xFFB27A, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 470, options: [])

    let sandstone = CGGradient(colorsSpace: space, colors: [color(0xFFF1DC), color(0xEBCFA8)] as CFArray, locations: [0, 1])!
    func fillSandstone(_ path: CGPath, shadow: Bool = true) {
        if shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: color(0x4A1208, 0.45))
            ctx.addPath(path)
            ctx.setFillColor(color(0xF3DEC0))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let box = path.boundingBox
        ctx.drawLinearGradient(sandstone, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])
        ctx.restoreGState()
    }

    // The balcony ledge, then the arched frame standing on it.
    let ledge = CGPath(roundedRect: CGRect(x: 236, y: 206, width: 552, height: 58), cornerWidth: 22, cornerHeight: 22, transform: nil)
    fillSandstone(ledge)
    let frame = archPath(minX: 276, maxX: 748, bottom: 256, springLine: 540)
    fillSandstone(frame)
    // The finial on top of the arch.
    fillSandstone(CGPath(ellipseIn: CGRect(x: 488, y: 758, width: 48, height: 48), transform: nil))

    // The opening, divided into panes like the layout: one large, two stacked.
    let opening = archPath(minX: 316, maxX: 708, bottom: 292, springLine: 540)
    ctx.saveGState()
    ctx.addPath(opening)
    ctx.clip()
    ctx.setFillColor(color(0x7A2412))
    ctx.fill(opening.boundingBox)
    let gap: CGFloat = 26
    let split = 316 + (392 - gap) * 0.56
    let main = CGRect(x: 316, y: 292, width: split - 316, height: 470)
    let side = CGRect(x: split + gap, y: 292, width: 708 - split - gap, height: 470)
    let lower = CGRect(x: side.minX, y: side.minY, width: side.width, height: 210)
    let upper = CGRect(x: side.minX, y: lower.maxY + gap, width: side.width, height: side.maxY - lower.maxY - gap)
    // The main pane glows with sunlight; the others are softer.
    let sun = CGGradient(colorsSpace: space, colors: [color(0xFFE7A8), color(0xFFB04F)] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.clip(to: main)
    ctx.drawLinearGradient(sun, start: CGPoint(x: main.midX, y: main.maxY), end: CGPoint(x: main.midX, y: main.minY), options: [])
    ctx.restoreGState()
    for (rect, alpha) in [(upper, 0.92), (lower, 0.78)] {
        ctx.setFillColor(color(0xFFE9CF, alpha))
        ctx.fill(rect)
    }
    ctx.restoreGState()
    // A fine carved edge around the opening.
    ctx.addPath(opening)
    ctx.setStrokeColor(color(0xC9A27A))
    ctx.setLineWidth(6)
    ctx.strokePath()

    // Soft light across the top of the tile.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY + 80), options: [])
    ctx.restoreGState()

    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.2).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: root.appendingPathComponent("build/AppIcon-preview.png"))

let resources = root.appendingPathComponent("Resources")
try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
