// Draws Learn's app icon (1024px master) and writes an .iconset for iconutil.
// Usage: swift scripts/make_icon.swift <out.iconset>
import AppKit

func draw(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size / 1024
    // macOS icon grid: 824px rounded square centered in 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 20 * s; shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.55, alpha: 1),
                        NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.70, alpha: 1)])!.draw(in: path, angle: -60)
    NSGraphicsContext.current?.restoreGraphicsState()
    // Keycap
    let cap = NSRect(x: 262 * s, y: 300 * s, width: 500 * s, height: 460 * s)
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(roundedRect: cap.offsetBy(dx: 0, dy: -22 * s), xRadius: 90 * s, yRadius: 90 * s).fill()
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: cap, xRadius: 90 * s, yRadius: 90 * s).fill()
    // ⌘ glyph on the keycap
    let glyph = NSAttributedString(string: "⌘", attributes: [
        .font: NSFont.systemFont(ofSize: 330 * s, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.21, blue: 0.62, alpha: 1)])
    let g = glyph.size()
    glyph.draw(at: NSPoint(x: cap.midX - g.width / 2, y: cap.midY - g.height / 2 + 6 * s))
    // Search lens badge
    let lens = NSRect(x: 600 * s, y: 170 * s, width: 250 * s, height: 250 * s)
    NSColor(calibratedRed: 1, green: 0.80, blue: 0.20, alpha: 1).setFill()
    NSBezierPath(ovalIn: lens).fill()
    let ring = NSBezierPath(ovalIn: lens.insetBy(dx: 62 * s, dy: 62 * s).offsetBy(dx: 12 * s, dy: 14 * s))
    ring.lineWidth = 24 * s; NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.50, alpha: 1).setStroke(); ring.stroke()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: lens.midX - 22 * s, y: lens.midY - 20 * s))
    handle.line(to: NSPoint(x: lens.minX + 62 * s, y: lens.minY + 58 * s))
    handle.lineWidth = 28 * s; handle.lineCapStyle = .round; handle.stroke()
    img.unlockFocus()
    return img
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                   (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
