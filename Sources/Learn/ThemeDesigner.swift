import SwiftUI

/// Arc-style theme designer: drag 1–3 color dots on a hue/saturation wheel, set intensity, darkness and grain,
/// or start from a preset. Dragging the first dot turns the others with it so the colors keep their harmony.
struct ThemeDesigner: View {
    @ObservedObject private var prefs = Prefs.shared

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
                        ForEach(ThemePreset.all) { p in
                            Button { apply(p) } label: { PresetSwatch(preset: p) }
                                .buttonStyle(RowPressStyle())
                                .help(p.name)
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
            Slider(value: value, in: 0...1)
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
            new = colors.enumerated().map { j, x in j == 0 ? target : HSB(h: (x.h + dh + 1).truncatingRemainder(dividingBy: 1), s: x.s) }
        } else {
            new[i] = target
        }
        onChange(new)
    }
}

private struct PresetSwatch: View {
    let preset: ThemePreset
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: preset.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().fill(.black.opacity(preset.darkness * 0.5)))
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
            .frame(width: 30, height: 30)
            .shadow(color: (preset.colors.first?.color ?? .clear).opacity(0.5), radius: 4, y: 2)
    }
}

// MARK: Model

/// Hue/saturation at full brightness (darkness is its own slider).
struct HSB: Equatable {
    var h: Double, s: Double
    init(h: Double, s: Double) { self.h = h; self.s = s }
    init(_ rgba: HUDStyle.RGBA) {
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        (rgba.ns.usingColorSpace(.sRGB) ?? .white).getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        h = hh; s = ss
    }
    var ns: NSColor { NSColor(hue: h, saturation: s, brightness: 1, alpha: 1) }
    var color: Color { Color(nsColor: ns) }
    var rgba: HUDStyle.RGBA { HUDStyle.RGBA(ns) }
}

struct ThemePreset: Identifiable {
    let name: String
    let colors: [HSB]
    var intensity = 0.4
    var darkness = 0.0
    var id: String { name }

    static let all: [ThemePreset] = [
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
    ]
}
