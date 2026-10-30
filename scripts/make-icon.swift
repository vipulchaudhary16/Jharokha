// Draws Pane's app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift   (from the repository root; needs iconutil)
import AppKit

let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    // macOS icon grid: an 824 pt rounded square centred on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let corner: CGFloat = 186

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background: deep indigo to violet.
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.95, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.17, green: 0.12, blue: 0.52, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // A gentle glow from the top-left.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(calibratedRed: 0.75, green: 0.6, blue: 1, alpha: 0.55).cgColor,
        NSColor(calibratedRed: 0.75, green: 0.6, blue: 1, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.minX + 180, y: body.maxY - 160), startRadius: 0,
                           endCenter: CGPoint(x: body.minX + 180, y: body.maxY - 160), endRadius: 620, options: [])

    // Three panes in the Side layout: one large, two stacked.
    let inset: CGFloat = 132, gap: CGFloat = 40
    let area = body.insetBy(dx: inset, dy: inset)
    let mainWidth = (area.width - gap) * 0.56
    let main = CGRect(x: area.minX, y: area.minY, width: mainWidth, height: area.height)
    let sideX = main.maxX + gap, sideWidth = area.maxX - sideX
    let half = (area.height - gap) / 2
    let top = CGRect(x: sideX, y: area.minY + half + gap, width: sideWidth, height: half)
    let bottom = CGRect(x: sideX, y: area.minY, width: sideWidth, height: half)

    func pane(_ rect: CGRect, strength: CGFloat, active: Bool = false) {
        let radius: CGFloat = 52
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if active {
            // The active window's glow, as Pane's highlight draws it.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 46, color: NSColor(calibratedRed: 0.45, green: 0.9, blue: 1, alpha: 0.9).cgColor)
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor(calibratedRed: 0.55, green: 0.93, blue: 1, alpha: 1).cgColor)
            ctx.setLineWidth(10)
            ctx.strokePath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.14 * strength).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        // Frosted glass: lighter at the top.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let frost = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor.white.withAlphaComponent(0.95 * strength).cgColor,
            NSColor.white.withAlphaComponent(0.62 * strength).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(frost, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        // A title bar with the three window controls.
        ctx.setFillColor(NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.95, alpha: 0.14).cgColor)
        ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 60, width: rect.width, height: 60))
        let colors: [NSColor] = active
            ? [NSColor(calibratedRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(calibratedRed: 1, green: 0.74, blue: 0.18, alpha: 1),
               NSColor(calibratedRed: 0.16, green: 0.79, blue: 0.27, alpha: 1)]
            : Array(repeating: NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.95, alpha: 0.35), count: 3)
        for (i, color) in colors.enumerated() {
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: rect.minX + 30 + CGFloat(i) * 30, y: rect.maxY - 41, width: 21, height: 21))
        }
        ctx.restoreGState()
        // Fine edge highlight.
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()
    }
    pane(bottom, strength: 0.8)
    pane(top, strength: 0.88)
    pane(main, strength: 1, active: true)

    // Glassy sheen across the top of the tile.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor.white.withAlphaComponent(0.18).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.midY + 60), options: [])
    ctx.restoreGState()

    // Hairline rim.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
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
