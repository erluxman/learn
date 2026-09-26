import SwiftUI

/// Arc-style theme designer: drag 1–3 color dots on a hue/saturation wheel, set intensity, darkness and grain,
/// or start from a preset. Dragging the first dot turns the others with it so the colors keep their harmony.
struct ThemeDesigner: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var showGallery = false

    private var colors: [HSB] { prefs.appearance.themeColors.map(HSB.init) }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ColorPad(colors: colors, onChange: set, onAdd: add)
                .frame(width: 210, height: 210)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Colors").font(.app(13, .semibold))
                    Spacer()
                    circleButton("minus", help: "Remove a color", disabled: colors.count <= 1) { set(Array(colors.dropLast())) }
                    circleButton("plus", help: "Add a color (or double-click the wheel)", disabled: colors.count >= 3) { add(nil) }
                    circleButton("dice.fill", help: "Shuffle a new harmony") { shuffle() }
                }
                slider("drop.fill", "Intensity", \.tintStrength)
                slider("moon.fill", "Darkness", \.darkness)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Presets").font(.app(13, .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
                        ForEach(ThemePreset.featured) { p in
                            Button { apply(p) } label: { PresetSwatch(preset: p, selected: isCurrent(p)) }
                                .buttonStyle(RowPressStyle())
                                .help(p.name)
                        }
                        Button { showGallery = true } label: {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.primary.opacity(0.06)))
                                .overlay(Circle().strokeBorder(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        }
                        .buttonStyle(RowPressStyle())
                        .help("More gradients")
                        .popover(isPresented: $showGallery, arrowEdge: .bottom) {
                            GradientGallery(isCurrent: isCurrent, apply: apply)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Edits

    private func set(_ new: [HSB]) {
        var look = prefs.appearance
        look.themeColorsChoice = new.map(\.rgba)
        if look.tintStrength == 0 { look.tintStrength = 0.35 }   // make the first change visible
        prefs.appearance = look
    }

    /// Adds a dot at `hsb`, or a harmonious one (120° from the first).
    private func add(_ hsb: HSB?) {
        guard colors.count < 3 else { return }
        let base = colors.first ?? HSB(h: 0.75, s: 0.6)
        set(colors + [hsb ?? HSB(h: (base.h + (colors.count == 1 ? 0.33 : 0.66)).truncatingRemainder(dividingBy: 1), s: base.s)])
    }

    private func shuffle() {
        let h = Double.random(in: 0..<1), s = Double.random(in: 0.45...0.85), spread = Double.random(in: 0.06...0.2)
        withAnimation(Theme.bouncy) {
            set((0..<max(colors.count, 2)).map { HSB(h: (h + Double($0) * spread).truncatingRemainder(dividingBy: 1), s: s) })
        }
    }

    private func isCurrent(_ p: ThemePreset) -> Bool {
        let now = prefs.appearance.themeColors
        return now.count == p.colors.count && zip(now, p.colors.map(\.rgba)).allSatisfy { a, b in
            abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.02
        }
    }

    private func apply(_ p: ThemePreset) {
        withAnimation(Theme.smooth) {
            var look = prefs.appearance
            look.themeColorsChoice = p.colors.map(\.rgba)
            look.tintStrength = p.intensity
            look.darkness = p.darkness
            prefs.appearance = look
        }
        Sounds.play(.click)
    }

    // MARK: Controls

    private func circleButton(_ symbol: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28)
        }
        .buttonStyle(LiquidButtonStyle(shape: Circle()))
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .help(help)
    }

    private func slider(_ symbol: String, _ title: String, _ key: WritableKeyPath<Appearance, Double>) -> some View {
        slider(symbol, title, $prefs.appearance[dynamicMember: key])
    }

    private func slider(_ symbol: String, _ title: String, _ value: SwiftUI.Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.app(13)).frame(width: 70, alignment: .leading)
            Slider(value: value, in: 0...1).sliderTicks(value.wrappedValue, in: 0...1)
            Text("\(Int((value.wrappedValue * 100).rounded()))%").font(.app(12)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: Wheel

/// Hue around, saturation outward. Dots drag; double-click adds one there.
private struct ColorPad: View {
    let colors: [HSB]
    let onChange: ([HSB]) -> Void
    let onAdd: (HSB?) -> Void
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2, c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            ZStack {
                Circle().fill(AngularGradient(colors: stride(from: 0.0, through: 1, by: 1 / 12).map { Color(hue: $0, saturation: 1, brightness: 1) },
                                              center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
                Circle().fill(.black.opacity(0.12))   // a touch softer than raw full-saturation hues
                ForEach([0.33, 0.66], id: \.self) { f in   // guide rings: how saturated
                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.75).frame(width: 2 * r * f, height: 2 * r * f)
                }
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: 1.2)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                // Harmony lines from the first dot to the others.
                Path { p in
                    guard let first = colors.first else { return }
                    for other in colors.dropFirst() { p.move(to: point(first, c, r)); p.addLine(to: point(other, c, r)) }
                }
                .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                ForEach(Array(colors.enumerated()), id: \.offset) { i, hsb in
                    Circle().fill(hsb.color)
                        .overlay(Circle().strokeBorder(.white, lineWidth: i == 0 ? 3.5 : 2.5))
                        .frame(width: i == 0 ? 30 : 22, height: i == 0 ? 30 : 22)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .scaleEffect(dragging == i ? 1.18 : 1)
                        .position(point(hsb, c, r))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("pad"))
                            .onChanged { v in
                                if dragging != i { withAnimation(Theme.bouncy) { dragging = i } }
                                drag(i, to: v.location, c, r)
                            }
                            .onEnded { _ in withAnimation(Theme.bouncy) { dragging = nil } })
                }
            }
            .coordinateSpace(name: "pad")
            .contentShape(Circle())
            .onTapGesture(count: 2, coordinateSpace: .named("pad")) { loc in onAdd(hsb(at: loc, c, r)) }
        }
    }

    private func point(_ hsb: HSB, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        let a = hsb.h * 2 * .pi, d = hsb.s * (r - 12)
        return CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d)
    }

    private func hsb(at p: CGPoint, _ c: CGPoint, _ r: CGFloat) -> HSB {
        let dx = p.x - c.x, dy = p.y - c.y
        var h = atan2(dy, dx) / (2 * .pi)
        if h < 0 { h += 1 }
        return HSB(h: h, s: min(hypot(dx, dy) / (r - 12), 1))
    }

    /// The first dot turns the others with it (same hue offsets); the others move on their own.
    private func drag(_ i: Int, to p: CGPoint, _ c: CGPoint, _ r: CGFloat) {
        var new = colors
        let target = hsb(at: p, c, r)
        if i == 0 {
            let dh = target.h - colors[0].h
            new = colors.enumerated().map { j, x in
                j == 0 ? HSB(h: target.h, s: target.s, b: x.b) : HSB(h: (x.h + dh + 1).truncatingRemainder(dividingBy: 1), s: x.s, b: x.b)
            }
        } else {
            new[i] = HSB(h: target.h, s: target.s, b: colors[i].b)
        }
        onChange(new)
    }
}

private struct PresetSwatch: View {
    let preset: ThemePreset
    var selected = false
    var size: CGFloat = 30
    var body: some View {
        GradientBlob(colors: preset.colors.map(\.color))
            .overlay(Circle().fill(.black.opacity(preset.darkness * 0.5)))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.95 : 0.4), lineWidth: selected ? 2.5 : 1))
            .frame(width: size, height: size)
            .shadow(color: (preset.colors.first?.color ?? .clear).opacity(0.5), radius: 4, y: 2)
    }
}

/// Soft, organic blend: a diagonal gradient with the last color glowing in from a corner, like light on a surface.
private struct GradientBlob: View {
    let colors: [Color]
    var body: some View {
        ZStack {
            LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if colors.count > 2 {
                RadialGradient(colors: [colors[2].opacity(0.85), colors[2].opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 40)
                    .blendMode(.normal)
            }
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: 30)
        }
    }
}

/// Every preset, grouped; clicking one applies it and leaves the gallery open to try another.
private struct GradientGallery: View {
    let isCurrent: (ThemePreset) -> Bool
    let apply: (ThemePreset) -> Void
    @State private var hovered: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(ThemePreset.groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name).font(.app(12, .semibold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 10), count: 6), alignment: .leading, spacing: 12) {
                            ForEach(group.presets) { p in
                                Button { apply(p) } label: {
                                    VStack(spacing: 5) {
                                        PresetSwatch(preset: p, selected: isCurrent(p), size: 44)
                                            .scaleEffect(hovered == p.id ? 1.1 : 1)
                                        Text(p.name).font(.app(10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .frame(width: 58)
                                }
                                .buttonStyle(RowPressStyle())
                                .onHover { h in withAnimation(Theme.bouncy) { hovered = h ? p.id : (hovered == p.id ? nil : hovered) } }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 440, height: 480)
    }
}

// MARK: Model

/// Hue and saturation (the wheel's two axes) plus brightness, which presets set and the wheel leaves alone.
struct HSB: Equatable {
    var h: Double, s: Double, b: Double
    init(h: Double, s: Double, b: Double = 1) { self.h = h; self.s = s; self.b = b }
    init(_ rgba: HUDStyle.RGBA) {
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        (rgba.ns.usingColorSpace(.sRGB) ?? .white).getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        h = hh; s = ss; b = bb
    }
    /// From a hex color like "5F8575".
    init(hex: String) {
        let v = Int(hex, radix: 16) ?? 0
        self.init(HUDStyle.RGBA(NSColor(srgbRed: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255,
                                        blue: Double(v & 255) / 255, alpha: 1)))
    }
    var ns: NSColor { NSColor(hue: h, saturation: s, brightness: b, alpha: 1) }
    var color: Color { Color(nsColor: ns) }
    var rgba: HUDStyle.RGBA { HUDStyle.RGBA(ns) }
}

struct ThemePreset: Identifiable {
    let name: String
    let colors: [HSB]
    var intensity = 0.4
    var darkness = 0.0
    var id: String { name }

    init(name: String, colors: [HSB], intensity: Double = 0.4, darkness: Double = 0) {
        (self.name, self.colors, self.intensity, self.darkness) = (name, colors, intensity, darkness)
    }
    /// Hex colors, e.g. `ThemePreset("Moss", "4A5D23", "8A9A5B")`.
    init(_ name: String, _ hex: String..., intensity: Double = 0.4, darkness: Double = 0) {
        self.init(name: name, colors: hex.map { HSB(hex: $0) }, intensity: intensity, darkness: darkness)
    }

    /// Palettes sampled from nature and photography: neighbouring hues, muted saturation, varied lightness —
    /// what makes a gradient feel organic rather than a rainbow sweep.
    static let groups: [(name: String, presets: [ThemePreset])] = [
        ("Nature", [
            ThemePreset("Moss", "4A5D23", "8A9A5B", "C9D6A3"),
            ThemePreset("Fern", "2E5E4E", "6B9E78"),
            ThemePreset("Sage Mist", "9CAF88", "D8E2DC", intensity: 0.35),
            ThemePreset("Eucalyptus", "5F8575", "A7C4B5", "E3EFE8"),
            ThemePreset("Lichen", "7C8363", "B5B682"),
            ThemePreset("Olive Grove", "708238", "B8A965"),
        ]),
        ("Sky", [
            ThemePreset("Dawn", "F6D1C1", "F4A7B9", "A7C7E7", intensity: 0.35),
            ThemePreset("Dusk", "2C3E6B", "7B5EA7", "F29E7A", intensity: 0.45),
            ThemePreset("Golden Hour", "F6BD60", "F28482", "F5CAC3"),
            ThemePreset("Overcast", "9AA5B1", "CBD2D9", intensity: 0.3),
            ThemePreset("Nordic Sky", "7FA7C9", "CFE1F2", "F2E8D5", intensity: 0.35),
            ThemePreset("Borealis", "1F4E47", "4FB08C", "8C7AE6", intensity: 0.45),
        ]),
        ("Water", [
            ThemePreset("Lagoon", "2A7F7A", "8FD3C8"),
            ThemePreset("Deep Sea", "0B2545", "13315C", "3E7CB1", intensity: 0.5),
            ThemePreset("Glacier", "457B9D", "A8DADC", "E0F2F1", intensity: 0.35),
            ThemePreset("Tide Pool", "2F6F73", "D9B99B"),
            ThemePreset("Rain", "6C8EA4", "B7C9D6", intensity: 0.35),
            ThemePreset("Kelp", "1E3D33", "4F7C5A", "A3B18A", intensity: 0.45),
        ]),
        ("Earth", [
            ThemePreset("Terracotta", "C8553D", "E7A977", "F2D0A4"),
            ThemePreset("Desert Sand", "D4A373", "FAEDCD", intensity: 0.35),
            ThemePreset("Clay", "A26769", "D5B9B2"),
            ThemePreset("Canyon", "8D4B2E", "D9895B", "F1C27D"),
            ThemePreset("Walnut", "5C4033", "A67B5B", intensity: 0.45),
            ThemePreset("Stone", "8B8C89", "C2B8A3", intensity: 0.3),
        ]),
        ("Flora", [
            ThemePreset("Peony", "E8A0BF", "F7D6E0", intensity: 0.35),
            ThemePreset("Lavender Field", "8E7DBE", "C3B1E1", "A0B3D9"),
            ThemePreset("Cherry Blossom", "E3A6B8", "F4C2C2", "FFE4E1", intensity: 0.35),
            ThemePreset("Marigold", "E09F3E", "F2C57C"),
            ThemePreset("Wildberry", "6D2E46", "A26769", "D5B9B2", intensity: 0.45),
            ThemePreset("Orchid", "B565A7", "E6C0E9"),
        ]),
        ("Moody", [
            ThemePreset("Ink", "1B2430", "51557E", intensity: 0.5, darkness: 0.2),
            ThemePreset("Smoke", "3A3A3C", "6E6E73", intensity: 0.45, darkness: 0.2),
            ThemePreset("Plum Night", "2D1E2F", "6B3E75", intensity: 0.5, darkness: 0.2),
            ThemePreset("Forest Night", "0B3D2E", "1F5F4A", intensity: 0.5, darkness: 0.2),
            ThemePreset("Espresso", "3C2A21", "7A5C45", intensity: 0.5, darkness: 0.2),
            ThemePreset("Storm", "37474F", "607D8B", "90A4AE", intensity: 0.45, darkness: 0.15),
        ]),
        ("Pastel", [
            ThemePreset("Cotton Candy", "F7C8E0", "C8E7FF", intensity: 0.35),
            ThemePreset("Peach Cream", "FFD6BA", "FFF1E6", intensity: 0.35),
            ThemePreset("Mint Cream", "CDEAC0", "F1FAEE", intensity: 0.35),
            ThemePreset("Lilac Haze", "D8C8F0", "F3E8FF", intensity: 0.35),
            ThemePreset("Butter", "FFE8A3", "FFF3B0", intensity: 0.3),
            ThemePreset("Seafoam", "B8E0D2", "D6EADF", intensity: 0.35),
        ]),
        ("Classic", [
            ThemePreset(name: "Aurora", colors: [HSB(h: 0.47, s: 0.7), HSB(h: 0.62, s: 0.75), HSB(h: 0.8, s: 0.6)]),
            ThemePreset(name: "Sunset", colors: [HSB(h: 0.04, s: 0.75), HSB(h: 0.93, s: 0.65), HSB(h: 0.12, s: 0.7)]),
            ThemePreset(name: "Ocean", colors: [HSB(h: 0.55, s: 0.8), HSB(h: 0.6, s: 0.7)], intensity: 0.45),
            ThemePreset(name: "Forest", colors: [HSB(h: 0.36, s: 0.6), HSB(h: 0.45, s: 0.55)], intensity: 0.4, darkness: 0.25),
            ThemePreset(name: "Lavender", colors: [HSB(h: 0.74, s: 0.45), HSB(h: 0.86, s: 0.4)], intensity: 0.4),
            ThemePreset(name: "Rose", colors: [HSB(h: 0.95, s: 0.55), HSB(h: 0.02, s: 0.45)], intensity: 0.4),
            ThemePreset(name: "Citrus", colors: [HSB(h: 0.13, s: 0.8), HSB(h: 0.2, s: 0.75)], intensity: 0.35),
            ThemePreset(name: "Midnight", colors: [HSB(h: 0.65, s: 0.7), HSB(h: 0.75, s: 0.6)], intensity: 0.45, darkness: 0.6),
            ThemePreset(name: "Ember", colors: [HSB(h: 0.02, s: 0.85), HSB(h: 0.08, s: 0.8)], intensity: 0.4, darkness: 0.45),
            ThemePreset(name: "Mint", colors: [HSB(h: 0.44, s: 0.45)], intensity: 0.35),
            ThemePreset(name: "Graphite", colors: [HSB(h: 0.6, s: 0.05)], intensity: 0.3, darkness: 0.5),
            ThemePreset(name: "Clear", colors: [HSB(h: 0.6, s: 0.0)], intensity: 0, darkness: 0),
        ]),
    ]

    static let all: [ThemePreset] = groups.flatMap(\.presets)

    /// The row under the wheel: a few organic picks; "+" opens the rest.
    static let featured: [ThemePreset] = ["Eucalyptus", "Dusk", "Terracotta", "Lavender Field", "Glacier", "Golden Hour",
                                          "Moss", "Peony", "Deep Sea", "Ink", "Clear"].compactMap { n in all.first { $0.name == n } }
}
