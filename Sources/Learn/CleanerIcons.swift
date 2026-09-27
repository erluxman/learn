import SwiftUI

/// The Cleaner's 3D glass icons, drawn in code: a thick translucent body (a darker extrusion under a lit face,
/// a rim catching light from the top, an inner shadow at the bottom) with a frosted-white glyph sitting on it.
/// `mono` is the sidebar version: the same body in frosted white that picks up the background's color.
struct ModuleIcon: View {
    let module: CleanerModule
    var size: CGFloat = 220
    var mono = false

    var body: some View {
        let p = mono ? Palette.mono : module.palette
        Group {
            switch module {
            case .smartCare: SmartCareIcon(size: size * 1.12, mono: mono)
            case .cleanup: CleanupIcon(size: size, p: p)
            case .protection: GlassBody(shape: RoundedPolygon(sides: 8, corner: 0.16, rotation: .pi / 8), size: size, p: p, depth: 0.07) {
                Image(systemName: "hand.raised.fill").resizable().scaledToFit().frame(width: size * 0.42)
                    .foregroundStyle(p.glyph).offset(x: size * 0.02)
            }
            case .performance: GlassBody(shape: Chevron(), size: size, p: p, depth: 0.08) {
                Image(systemName: "bolt.fill").resizable().scaledToFit().frame(width: size * 0.3)
                    .foregroundStyle(p.glyph).rotationEffect(.degrees(12)).offset(y: -size * 0.05)
            }
            case .applications: GlassBody(shape: RoundedPolygon(sides: 6, corner: 0.2, rotation: .pi / 6), size: size, p: p, depth: 0.07) {
                AppsGlyph(size: size, p: p)
            }
            case .clutter: GlassBody(shape: Blob(), size: size, p: p, depth: 0.07) {
                FolderGlyph(size: size * 0.46, p: p).offset(y: -size * 0.02)
            }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Any SF Symbol on a Cleaner-style glass slab in `color` — Learn's default icon look.
/// `frosted`: the Cleaner's unselected look — frosted white glass that takes on the background, grey symbol.
struct GlassSlab: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28
    var frosted = false
    var body: some View {
        let p = frosted ? Palette.mono : Palette.glass(color)
        GlassBody(shape: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous), size: size / 0.84, p: p, depth: 0.08) {
            Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(p.glyph)
        }
        .frame(width: size, height: size)
    }
}

// MARK: Palette

struct Palette {
    var light: Color, base: Color, dark: Color, rim: Color
    var glyph: LinearGradient
    var glyphShade: Color
    var clear: Double = 0.78   // face opacity: glass lets a little of the background through

    static let mono = Palette(light: .white.opacity(0.7), base: .white.opacity(0.3), dark: .white.opacity(0.1), rim: .white,
                              glyph: LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                              glyphShade: .black.opacity(0.45), clear: 0.6)

    /// Glass in any color: lighter at the top, deep at the bottom.
    static func glass(_ c: Color) -> Palette {
        Palette(light: c.mix(.white, 0.45), base: c, dark: c.mix(.black, 0.55), rim: c.mix(.white, 0.7),
                glyph: LinearGradient(colors: [.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom),
                glyphShade: c.mix(.black, 0.6).opacity(0.6))
    }

    static func glass(_ light: UInt32, _ base: UInt32, _ dark: UInt32, rim: UInt32) -> Palette {
        Palette(light: Color(hex: light), base: Color(hex: base), dark: Color(hex: dark), rim: Color(hex: rim),
                glyph: LinearGradient(colors: [.white.opacity(0.95), Color(white: 0.86).opacity(0.9)], startPoint: .top, endPoint: .bottom),
                glyphShade: Color(hex: dark).opacity(0.6))
    }
}

extension CleanerModule {
    var palette: Palette {
        switch self {
        case .smartCare: .glass(0xFF8AD8, 0xE23AA8, 0x8E1470, rim: 0xFFC2EC)
        case .cleanup: .glass(0x7CF07C, 0x22A83A, 0x0B5A1C, rim: 0xB8FFB0)
        case .protection: .glass(0xFF7FC4, 0xD62A8A, 0x7A0C4C, rim: 0xFFC0E2)
        case .performance: .glass(0xFFB070, 0xD9661E, 0x6E2A0A, rim: 0xFFD2A8)
        case .applications: .glass(0x7FD8FF, 0x2566E0, 0x0B2A8A, rim: 0x9FF0FF)
        case .clutter: .glass(0x9FF5E4, 0x2FB8A2, 0x0D5E58, rim: 0xC8FFF4)
        }
    }
}

// MARK: Body

/// Thick glass slab in `shape`, with `glyph` on its face.
private struct GlassBody<S: Shape, Glyph: View>: View {
    let shape: S
    let size: CGFloat
    let p: Palette
    var depth: CGFloat = 0.07
    @ViewBuilder let glyph: Glyph

    var body: some View {
        let d = size * depth
        ZStack {
            // Extrusion: the slab's side, darker, peeking out below the face.
            // Solid side wall: the shape stacked down to its full depth, so the edge reads as one thick slab.
            ForEach(0..<8, id: \.self) { i in
                shape.fill(LinearGradient(colors: [p.base.mix(p.dark, 0.35), p.dark], startPoint: .top, endPoint: .bottom))
                    .offset(y: d * CGFloat(i + 1) / 8)
            }
            shape.stroke(p.rim.opacity(0.3), lineWidth: size * 0.005).offset(y: d).mask(shape.offset(y: d))
            // Face: lit from the top left, deeper toward the bottom right.
            shape.fill(LinearGradient(stops: [.init(color: p.light, location: 0), .init(color: p.base, location: 0.55),
                                               .init(color: p.dark.opacity(0.9), location: 1)],
                                      startPoint: UnitPoint(x: 0.3, y: 0), endPoint: UnitPoint(x: 0.7, y: 1)))
                .opacity(p.clear)
            // Soft light pooled in the upper part of the glass.
            shape.fill(RadialGradient(colors: [.white.opacity(0.45), .white.opacity(0)], center: UnitPoint(x: 0.4, y: 0.18),
                                      startRadius: 0, endRadius: size * 0.55))
            // Inner shadow along the bottom edge: gives the face its thickness.
            shape.stroke(p.dark.opacity(0.75), lineWidth: size * 0.07)
                .blur(radius: size * 0.035)
                .offset(y: -size * 0.02)
                .mask(shape)
            // Rim light: bright on top, fading down the sides.
            shape.stroke(LinearGradient(colors: [p.rim.opacity(0.95), p.rim.opacity(0.15), p.rim.opacity(0.5)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: size * 0.012)
            glyph
                .shadow(color: p.glyphShade, radius: size * 0.02, y: size * 0.02)
            // Specular streak across the top of the glass.
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.42, height: size * 0.09)
                .blur(radius: size * 0.012)
                .offset(x: -size * 0.1, y: -size * 0.33)
                .mask(shape)
        }
        .frame(width: size * 0.84, height: size * 0.84)
        .offset(y: -d / 2)
        .compositingGroup()
        .shadow(color: p.dark.opacity(0.55), radius: size * 0.08, y: size * 0.07)
    }
}

// MARK: Cleanup: glass disc with a white token

private struct CleanupIcon: View {
    let size: CGFloat
    let p: Palette
    var body: some View {
        let w = size * 0.9, h = size * 0.74, d = size * 0.06
        ZStack {
            // The disc, tilted toward the viewer: see-through green glass with a thick lit rim.
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    Ellipse().fill(LinearGradient(colors: [p.base.mix(p.dark, 0.3), p.dark], startPoint: .top, endPoint: .bottom))
                        .frame(width: w, height: h).offset(y: d * CGFloat(i + 1) / 8)
                }
                Ellipse().fill(RadialGradient(colors: [p.light.opacity(0.55), p.base.opacity(0.7), p.dark.opacity(0.85)],
                                              center: UnitPoint(x: 0.42, y: 0.35), startRadius: 0, endRadius: w * 0.62))
                    .frame(width: w, height: h)
                Ellipse().stroke(p.dark.opacity(0.7), lineWidth: size * 0.06).blur(radius: size * 0.03)
                    .frame(width: w, height: h).offset(y: -size * 0.015).mask(Ellipse().frame(width: w, height: h))
                Ellipse().stroke(LinearGradient(colors: [p.rim, p.rim.opacity(0.15), p.rim.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                                 lineWidth: size * 0.016)
                    .frame(width: w, height: h)
                Ellipse().stroke(.white.opacity(0.18), lineWidth: size * 0.005).frame(width: w * 0.86, height: h * 0.84)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * 0.6, height: h * 0.2).blur(radius: size * 0.015).offset(x: -w * 0.06, y: -h * 0.34)
            }
            .rotationEffect(.degrees(-16))
            // The token: a thick soft-white puck with a round hole and a slot, standing on the glass.
            ZStack {
                Ellipse().fill(p.dark.opacity(0.55)).frame(width: size * 0.4, height: size * 0.36).offset(x: size * 0.02, y: size * 0.05)
                    .blur(radius: size * 0.03)
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.38, height: size * 0.34).offset(y: size * 0.03)
                Ellipse().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size * 0.38, height: size * 0.34)
                Ellipse().stroke(.white, lineWidth: size * 0.006).frame(width: size * 0.38, height: size * 0.34).blur(radius: 0.5)
                hole(Ellipse(), w: 0.095, h: 0.075).offset(x: size * 0.005, y: -size * 0.075)
                hole(Capsule(), w: 0.08, h: 0.04).offset(x: -size * 0.005, y: size * 0.085)
            }
            .offset(x: -size * 0.01, y: -size * 0.02)
        }
        .compositingGroup()
        .shadow(color: p.dark.opacity(0.55), radius: size * 0.08, y: size * 0.07)
    }

    /// A hole through the token: the green glass seen inside, darker at its top lip.
    private func hole<S: Shape>(_ s: S, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            s.fill(LinearGradient(colors: [p.dark, p.base, p.light], startPoint: .top, endPoint: .bottom))
            s.stroke(Color(white: 0.55), lineWidth: size * 0.006)
        }
        .frame(width: size * w, height: size * h)
    }
}

// MARK: Applications glyph: an X over a spray of bubbles

private struct AppsGlyph: View {
    let size: CGFloat
    let p: Palette
    var body: some View {
        ZStack {
            ForEach([-28.0, 28.0], id: \.self) { a in
                Capsule().fill(p.glyph).frame(width: size * 0.075, height: size * 0.3).rotationEffect(.degrees(a))
            }
            .offset(y: -size * 0.12)
            // Bubbles fanning out below, bigger in the middle row.
            ForEach(Array(Self.dots.enumerated()), id: \.offset) { _, d in
                Circle().fill(RadialGradient(colors: [.white.opacity(0.95), p.light.opacity(0.7)], center: UnitPoint(x: 0.35, y: 0.3),
                                             startRadius: 0, endRadius: size * d.r))
                    .frame(width: size * d.r * 2, height: size * d.r * 2)
                    .offset(x: size * d.x, y: size * d.y)
            }
        }
    }
    private static let dots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (-0.2, 0.03, 0.026), (-0.13, 0.02, 0.035), (0, 0.0, 0.035), (0.13, 0.02, 0.035), (0.2, 0.03, 0.026),
        (-0.17, 0.1, 0.028), (-0.07, 0.08, 0.018), (0.06, 0.08, 0.018), (0.17, 0.1, 0.028),
        (-0.1, 0.15, 0.012), (0, 0.13, 0.017), (0.1, 0.15, 0.012), (0, 0.2, 0.01),
    ]
}

// MARK: Folder glyph

private struct FolderGlyph: View {
    let size: CGFloat
    let p: Palette
    var body: some View {
        ZStack {
            FolderShape().fill(LinearGradient(colors: [Color(hex: 0xDFFBFF), Color(hex: 0x9FDDEB)], startPoint: .top, endPoint: .bottom))
            FolderShape().stroke(.white.opacity(0.8), lineWidth: size * 0.015)
            Capsule().fill(Color(hex: 0x6FB8C8)).frame(width: size * 0.18, height: size * 0.04).offset(x: size * 0.22, y: size * 0.16)
        }
        .frame(width: size, height: size * 0.78)
    }
}

private struct FolderShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, c = w * 0.08
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + w * 0.36, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + w * 0.46, y: r.minY + h * 0.14), control: CGPoint(x: r.minX + w * 0.42, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY + h * 0.14))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.14 + c), control: CGPoint(x: r.maxX, y: r.minY + h * 0.14))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        return p
    }
}

// MARK: Smart Care: a pink glass iMac with a squeegee

private struct SmartCareIcon: View {
    let size: CGFloat
    var mono = false
    var body: some View {
        let pink = LinearGradient(colors: [Color(hex: 0xFF9BDD), Color(hex: 0xF04FB8), Color(hex: 0xC0288E)], startPoint: .top, endPoint: .bottom)
        let silver = LinearGradient(colors: [Color(white: 0.95), Color(white: 0.7)], startPoint: .top, endPoint: .bottom)
        ZStack {
            // Stand and foot.
            Trapezoid().fill(silver).frame(width: size * 0.16, height: size * 0.14).offset(y: size * 0.26)
            Capsule().fill(silver).frame(width: size * 0.32, height: size * 0.05).offset(y: size * 0.33)
            // Screen: thick pink glass, lighter at the top.
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous).fill(Color(hex: 0x9E1C74))
                .frame(width: size * 0.8, height: size * 0.5).offset(y: -size * 0.02 + size * 0.03)
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous).fill(pink)
                .frame(width: size * 0.8, height: size * 0.5).offset(y: -size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: UnitPoint(x: 0.35, y: 0.1), startRadius: 0, endRadius: size * 0.45))
                .frame(width: size * 0.8, height: size * 0.5).offset(y: -size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: size * 0.012)
                .frame(width: size * 0.8, height: size * 0.5).offset(y: -size * 0.02)
            // Chin.
            RoundedRectangle(cornerRadius: size * 0.03, style: .continuous).fill(Color(hex: 0xFFC6EC).opacity(0.9))
                .frame(width: size * 0.74, height: size * 0.07).offset(y: size * 0.17)
            // Squeegee sweeping the screen.
            Capsule().fill(silver).frame(width: size * 0.05, height: size * 0.46)
                .rotationEffect(.degrees(-38)).offset(x: size * 0.12, y: -size * 0.12)
                .shadow(color: .black.opacity(0.3), radius: size * 0.02, x: size * 0.01, y: size * 0.02)
        }
        .saturation(mono ? 0.9 : 1)
        .compositingGroup()
        .shadow(color: Color(hex: 0x8E1470).opacity(0.5), radius: size * 0.08, y: size * 0.07)
    }
}

// MARK: Shapes

/// Regular polygon with rounded corners (`corner` as a fraction of the radius).
struct RoundedPolygon: Shape {
    var sides: Int
    var corner: CGFloat = 0.15
    var rotation: Double = 0
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height) / 2
        let pts = (0..<sides).map { i -> CGPoint in
            let a = rotation + Double(i) / Double(sides) * 2 * .pi - .pi / 2
            return CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
        }
        var p = Path()
        let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        p.move(to: mid(pts[sides - 1], pts[0]))
        for i in 0..<sides {
            p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % sides], radius: rad * corner)
        }
        p.closeSubpath()
        return p
    }
}

/// Performance's badge: a rounded shield that dips to a point at the bottom.
struct Chevron: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let pts = [CGPoint(x: r.minX + w * 0.08, y: r.minY + h * 0.14), CGPoint(x: r.maxX - w * 0.08, y: r.minY + h * 0.14),
                   CGPoint(x: r.maxX - w * 0.02, y: r.minY + h * 0.62), CGPoint(x: r.midX, y: r.maxY - h * 0.04),
                   CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.62)]
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: pts[0].y))
        for i in 1...pts.count { p.addArc(tangent1End: pts[i % pts.count], tangent2End: pts[(i + 1) % pts.count], radius: w * 0.12) }
        p.closeSubpath()
        return p
    }
}

/// My Clutter's soft four-lobed blob.
struct Blob: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height) / 2
        var p = Path()
        let n = 120
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let k = 0.86 + 0.08 * cos(4 * a + 0.4) + 0.03 * cos(2 * a)
            let pt = CGPoint(x: c.x + cos(a) * rad * k, y: c.y + sin(a) * rad * k * 0.92)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

private struct Trapezoid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

extension Color {
    func mix(_ other: Color, _ t: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .white, b = NSColor(other).usingColorSpace(.sRGB) ?? .white
        return Color(.sRGB, red: a.redComponent + (b.redComponent - a.redComponent) * t,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                     opacity: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }

    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255, opacity: opacity)
    }
}
