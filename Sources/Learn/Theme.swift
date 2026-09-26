import SwiftUI

/// Shared look and feel: radii, motion, Liquid Glass (macOS 26) with a material fallback, and the pieces that make
/// glass respond to the pointer — light that follows it, buttons that swell, lean and squash, a selection that stretches.
enum Theme {
    static let rowRadius: CGFloat = 12
    static let cardRadius: CGFloat = 18

    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let bouncy = Animation.spring(response: 0.36, dampingFraction: 0.7)
    /// Press goes in fast and firm; release wobbles back like a liquid.
    static let press = Animation.spring(response: 0.16, dampingFraction: 0.78)
    static let release = Animation.spring(response: 0.46, dampingFraction: 0.52)

    static let highlight = Color.primary.opacity(0.1)
    static let hairline = Color.primary.opacity(0.08)
}

extension View {
    /// Liquid Glass (macOS 26; frosted material before) styled by Settings ▸ Appearance: clear or regular blur,
    /// and the app-wide tint / darkness applied to the glass itself. An explicit `tint` (e.g. a recorder listening) wins over the app tint.
    func liquidGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, interactive: interactive))
    }

    /// Morphs between glass shapes sharing a namespace (macOS 26); no-op before.
    @ViewBuilder
    func glassID(_ id: String?, in ns: Namespace.ID?) -> some View {
        if #available(macOS 26, *), let id, let ns { glassEffectID(id, in: ns) } else { self }
    }

    /// `.glass` button on macOS 26, bordered before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Glass surface lights up where the pointer is: a soft glow inside and a brighter rim near the cursor.
    func pointerLight<S: InsettableShape>(_ shape: S, strength: Double = 1, radius: CGFloat = 140) -> some View {
        modifier(PointerLight(shape: shape, strength: strength, radius: radius))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @Environment(\.appearance) private var look

    /// Nothing is layered under the glass: its color and darkness are the glass's own tint.
    func body(content: Content) -> some View {
        let tint = tint ?? look.glassTint
        if #available(macOS 26, *) {
            content.glassEffect((look.material == .clear ? Glass.clear : Glass.regular).tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(look.material == .clear ? Material.ultraThin : Material.regular, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

/// Groups sibling glass shapes so they blend and morph together (macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}

// MARK: Pointer light

/// The specular part of glass: glow + rim highlight centred on `point` (view coordinates).
private struct Specular<S: InsettableShape>: View {
    let shape: S
    let point: CGPoint
    let strength: Double
    let radius: CGFloat
    @Environment(\.appearance) private var look
    var body: some View {
        let strength = strength * look.light
        GeometryReader { g in
            let c = UnitPoint(x: point.x / max(g.size.width, 1), y: point.y / max(g.size.height, 1))
            ZStack {
                RadialGradient(colors: [.white.opacity(0.14 * strength), .white.opacity(0)], center: c, startRadius: 0, endRadius: radius)
                shape.strokeBorder(RadialGradient(colors: [.white.opacity(0.75 * strength), .white.opacity(0)],
                                                  center: c, startRadius: 0, endRadius: radius * 1.2), lineWidth: 1.1)
            }
            .blendMode(.plusLighter)
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

private struct PointerLight<S: InsettableShape>: ViewModifier {
    let shape: S
    let strength: Double
    let radius: CGFloat
    @State private var point = CGPoint.zero
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .overlay { Specular(shape: shape, point: point, strength: strength, radius: radius).opacity(lit ? 1 : 0) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if !lit { point = p; withAnimation(.easeOut(duration: 0.25)) { lit = true } }
                    else { withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.9)) { point = p } }
                case .ended:
                    withAnimation(.easeOut(duration: 0.4)) { lit = false }
                }
            }
    }
}

// MARK: Liquid button

/// Glass button that behaves like liquid: swells on hover, its content leans toward the pointer,
/// squashes on press and wobbles back on release; the rim catches the light where the pointer is.
struct LiquidButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var tint: Color? = nil
    var glassID: String? = nil
    var namespace: Namespace.ID? = nil
    func makeBody(configuration: Configuration) -> some View {
        LiquidButton(label: configuration.label, pressed: configuration.isPressed, shape: shape, tint: tint,
                     glassID: glassID, namespace: namespace)
    }
}

private struct LiquidButton<Label: View, S: InsettableShape>: View {
    let label: Label
    let pressed: Bool
    let shape: S
    let tint: Color?
    let glassID: String?
    let namespace: Namespace.ID?
    @State private var point: CGPoint?
    @State private var size = CGSize.zero
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearance) private var look

    /// Content drifts up to 3 pt toward the pointer.
    private var lean: CGSize {
        guard let p = point, !reduceMotion, look.hoverMotion, size.width > 0 else { return .zero }
        let dx = (p.x - size.width / 2) / (size.width / 2), dy = (p.y - size.height / 2) / (size.height / 2)
        return CGSize(width: dx * 3, height: dy * 3)
    }
    private var hovering: Bool { point != nil && enabled }

    var body: some View {
        label
            .offset(lean)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: lean)
            .contentShape(shape)
            .liquidGlass(in: shape, tint: tint, interactive: true)
            .glassID(glassID, in: namespace)
            .overlay { if let point { Specular(shape: shape, point: point, strength: pressed ? 1.6 : 1, radius: max(size.width, 40)) } }
            .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
            .scaleEffect(x: pressed ? 0.93 : hovering && look.hoverMotion ? 1.05 : 1, y: pressed ? 0.9 : hovering && look.hoverMotion ? 1.05 : 1)
            .brightness(pressed ? 0.05 : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(pressed ? Theme.press : Theme.release, value: pressed)
            .animation(Theme.bouncy, value: hovering)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): point = p
                case .ended: point = nil
                }
            }
    }
}

/// List rows: a small, quick press-in.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(configuration.isPressed ? Theme.press : Theme.release, value: configuration.isPressed)
    }
}

// MARK: Liquid selection

/// Selection highlight that flows between rows: the leading edge races ahead and the trailing edge catches up,
/// so it stretches while moving and settles back into a pill.
struct LiquidBlob: View {
    let target: CGRect
    var tint: Color? = nil
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 0
    @State private var placed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: tint.map { [$0.opacity(0.42), $0.opacity(0.26)] } ?? [Color.primary.opacity(0.13), Color.primary.opacity(0.07)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                                        lineWidth: 0.8))
            .shadow(color: (tint ?? .black).opacity(tint == nil ? 0.12 : 0.35), radius: 8, y: 3)
            .animation(Theme.smooth, value: tint)
            .frame(width: target.width, height: max(bottom - top, 0))
            .position(x: target.midX, y: (top + bottom) / 2)
            .opacity(placed ? 1 : 0)
            .onAppear { top = target.minY; bottom = target.maxY; withAnimation(.easeOut(duration: 0.2)) { placed = true } }
            .onChange(of: target) { old, new in
                guard !reduceMotion, abs(new.midY - old.midY) < 420, new.height > 0 else { top = new.minY; bottom = new.maxY; return }
                let lead = Animation.spring(response: 0.2, dampingFraction: 0.82)
                let trail = Animation.spring(response: 0.36, dampingFraction: 0.74)
                let down = new.midY > old.midY
                withAnimation(down ? lead : trail) { bottom = new.maxY }
                withAnimation(down ? trail : lead) { top = new.minY }
            }
    }
}

struct SelectionAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

// MARK: Keys and icons

/// A shortcut drawn as physical keys: "⌥⇧⌘N" → ⌥ ⇧ ⌘ N.
struct Keycaps: View {
    let display: String
    var size: CGFloat = 12
    var dim = false

    static func split(_ s: String) -> [String] {
        var rest = Substring(s), caps: [String] = []
        if rest.hasPrefix("fn ") { caps.append("fn"); rest = rest.dropFirst(3) }
        while let c = rest.first, "⌃⌥⇧⌘".contains(c), rest.count > 1 { caps.append(String(c)); rest = rest.dropFirst() }
        if !rest.isEmpty { caps.append(String(rest)) }
        return caps
    }

    var body: some View {
        HStack(spacing: size * 0.28) {
            ForEach(Array(Self.split(display).enumerated()), id: \.offset) { _, k in Keycap(label: k, size: size, dim: dim) }
        }
        .fixedSize()
    }
}

struct Keycap: View {
    let label: String
    var size: CGFloat = 12
    var dim = false

    /// SF Symbols drawn for keyboard keys; anything else (letters, F-keys) is text.
    static let symbols: [String: String] = [
        "⌘": "command", "⇧": "shift", "⌥": "option", "⌃": "control", "fn": "globe",
        "↩": "return", "⌤": "return", "⎋": "escape", "⌫": "delete.left", "⌦": "delete.right", "⇥": "arrow.right.to.line",
        "←": "arrow.left", "→": "arrow.right", "↑": "arrow.up", "↓": "arrow.down", "Space": "space",
    ]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
        Group {
            if let symbol = Self.symbols[label] {
                Image(systemName: symbol).font(.system(size: size * 0.92, weight: .semibold))
            } else {
                Text(label).font(.system(size: size, weight: .semibold, design: .rounded)).lineLimit(1)
            }
        }
            .fixedSize()
            .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .padding(.horizontal, size * 0.42)
            .frame(minWidth: size * 1.9, minHeight: size * 1.85)
            .background(
                shape.fill(LinearGradient(colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .primary.opacity(0.12)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 1)
            )
    }
}

/// SF Symbol on a squircle, in the style chosen in Settings ▸ Appearance:
/// tinted (quiet tile, colored symbol), mono (neutral), or color (glossy, lit from above, glowing).
struct IconTile: View {
    let symbol: String
    var color: Color = .accentColor
    var size: CGFloat = 28
    @Environment(\.appearance) private var look

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        switch look.iconStyle {
        case .tinted:
            shape.fill(color.opacity(0.16))
                .overlay(shape.strokeBorder(color.opacity(0.32), lineWidth: 0.75))
                .frame(width: size, height: size)
                .overlay(Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(color))
        case .mono:
            shape.fill(Color.primary.opacity(0.07))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.75))
                .frame(width: size, height: size)
                .overlay(Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                    .font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(.primary))
        case .color:
            glossy(shape)
        }
    }

    private func glossy(_ shape: RoundedRectangle) -> some View {
        shape.fill(color)
            .overlay(shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0),
                                                       .init(color: .white.opacity(0.04), location: 0.5),
                                                       .init(color: .black.opacity(0.2), location: 1)],
                                               startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(0.5, size / 60)))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5))
            .shadow(color: color.opacity(0.4), radius: size * 0.14, y: size * 0.06)
    }
}

/// Big pane icon: floats on a breathing glow of its color and tilts toward the pointer in 3D.
struct HeroIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 56
    @State private var tilt = CGSize.zero
    @State private var shown = false
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearance) private var look

    var body: some View {
        let box = size * 1.6
        ZStack {
            Circle().fill(color).frame(width: size * 1.3, height: size * 1.3)
                .blur(radius: size * 0.45)
                .opacity(breathe ? 0.55 : 0.3)
            IconTile(symbol: symbol, color: color, size: size)
                .rotation3DEffect(.degrees(tilt.width), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-tilt.height), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
        }
        .frame(width: box, height: box)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard !reduceMotion, look.hoverMotion else { return }
            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.7)) {
                switch phase {
                case .active(let p): tilt = CGSize(width: (p.x / box - 0.5) * 30, height: (p.y / box - 0.5) * 30)
                case .ended: tilt = .zero
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.05)) { shown = true }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}

/// Footer hint: keycap + what it does.
struct KeyHint: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 5) {
            Keycaps(display: keys, size: 10, dim: true)
            Text(label).font(.app(11, .medium)).foregroundStyle(.secondary)
        }
    }
}

/// An app's signature color, from its icon: the average of its saturated pixels, lifted so it reads on glass.
enum IconColor {
    private static var cache: [String: Color] = [:]

    static func of(_ app: AppEntry) -> Color {
        if let c = cache[app.id] { return c }
        let c = compute(AppCatalog.icon(app)).map { Color(nsColor: $0) } ?? .accentColor
        cache[app.id] = c
        return c
    }

    private static func compute(_ image: NSImage) -> NSColor? {
        let n = 16
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        let px = data.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        for i in 0..<(n * n) {
            let a = Double(px[i * 4 + 3]) / 255
            guard a > 0.5 else { continue }
            let pr = Double(px[i * 4]) / 255 / a, pg = Double(px[i * 4 + 1]) / 255 / a, pb = Double(px[i * 4 + 2]) / 255 / a
            let sat = max(pr, pg, pb) - min(pr, pg, pb)   // grey pixels say little about the icon's color
            let w = sat * sat * a
            r += pr * w; g += pg * w; b += pb * w; weight += w
        }
        guard weight > 0.5 else { return nil }   // a grey icon: fall back to the accent
        let avg = NSColor(srgbRed: r / weight, green: g / weight, blue: b / weight, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, al: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
        return NSColor(hue: h, saturation: max(s, 0.5), brightness: max(v, 0.75), alpha: 1)
    }
}
