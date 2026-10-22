// Renders the Snag app icon into an .iconset (all required sizes). Run via scripts/build.sh.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225

    // Squircle body: deep indigo -> violet.
    let bg = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.16, blue: 0.52, alpha: 1),
                        NSColor(red: 0.47, green: 0.27, blue: 0.93, alpha: 1)])!.draw(in: bg, angle: 90)

    // The shelf: a rounded bar near the bottom.
    let shelf = NSRect(x: body.minX + body.width * 0.16, y: body.minY + body.height * 0.17,
                       width: body.width * 0.68, height: body.height * 0.08)
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: shelf, xRadius: shelf.height / 2, yRadius: shelf.height / 2).fill()

    // Three "files" resting on it, slightly fanned.
    let w = body.width * 0.22, h = body.height * 0.3
    let colors = [NSColor(red: 1, green: 0.78, blue: 0.3, alpha: 1),
                  NSColor(red: 0.35, green: 0.85, blue: 0.75, alpha: 1),
                  NSColor(red: 1, green: 0.45, blue: 0.55, alpha: 1)]
    let angles: [CGFloat] = [12, 0, -12]
    let xs: [CGFloat] = [-0.17, 0, 0.17]
    for i in [0, 2, 1] { // center card on top
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        let cx = body.midX + body.width * xs[i]
        let lift = abs(sin(angles[i] * .pi / 180)) * w / 2
        let base = shelf.maxY + h / 2 + lift - body.height * 0.01
        ctx.translateBy(x: cx, y: base)
        ctx.rotate(by: angles[i] * .pi / 180)
        let card = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let sh = NSShadow()
        sh.shadowBlurRadius = s * 0.02
        sh.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
        sh.set()
        colors[i].setFill()
        NSBezierPath(roundedRect: card, xRadius: w * 0.14, yRadius: w * 0.14).fill()
        ctx.restoreGState()
    }

    // Down arrow above: "snag it".
    let arrow = NSBezierPath()
    let ax = body.midX, top = body.maxY - body.height * 0.14, tip = body.minY + body.height * 0.7
    arrow.lineWidth = body.width * 0.06
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: ax, y: top)); arrow.line(to: NSPoint(x: ax, y: tip))
    arrow.move(to: NSPoint(x: ax - body.width * 0.1, y: tip + body.width * 0.1))
    arrow.line(to: NSPoint(x: ax, y: tip))
    arrow.line(to: NSPoint(x: ax + body.width * 0.1, y: tip + body.width * 0.1))
    NSColor.white.setStroke()
    arrow.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("icon -> \(out)")
