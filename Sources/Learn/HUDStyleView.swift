import SwiftUI

/// Settings ▸ On Screen: the shortcut bubble's look. A mini screen previews it live; tap a spot to move it there.
struct HUDStyleSections: View {
    @ObservedObject private var prefs = Prefs.shared
    private static let families = NSFontManager.shared.availableFontFamilies

    private var style: SwiftUI.Binding<HUDStyle> { $prefs.hudStyle }

    var body: some View {
        Section {
            preview
                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            slider("Distance from edge", style.margin, 0...300, "%.0f pt")
        } header: {
            Text("Shortcut bubble")
        } footer: {
            Text("Click a spot on the preview to move the bubble there. Pointer mode's hint uses this style too.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        Section("Text") {
            Picker("Font", selection: style.font) {
                Text("System").tag("")
                Text("System Rounded").tag(".rounded")
                Text("System Monospaced").tag(".mono")
                Divider()
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Bold keys", isOn: style.bold)
            slider("Key size", style.keySize, 12...96, "%.0f pt")
            Toggle("Show command name", isOn: style.showCaption)
            slider("Command name size", style.captionSize, 8...40, "%.0f pt").disabled(!prefs.hudStyle.showCaption)
            ColorPicker("Text color", selection: color(\.textColor), supportsOpacity: true)
        }
        Section("Box") {
            Picker("Background", selection: style.box) {
                Text("Solid").tag(HUDStyle.Backdrop.solid)
                Text("Clear glass").tag(HUDStyle.Backdrop.glass)
                Text("Colored glass").tag(HUDStyle.Backdrop.tinted)
                Text("Blurred").tag(HUDStyle.Backdrop.frosted)
            }
            .pickerStyle(.segmented)
            ColorPicker(prefs.hudStyle.box == .tinted ? "Glass color" : "Color", selection: color(\.background), supportsOpacity: true)
                .disabled(prefs.hudStyle.box == .glass)
            slider("Rounded corners", style.cornerRadius, 0...40, "%.0f pt")
            slider("Padding left/right", style.paddingH, 0...80, "%.0f pt")
            slider("Padding top/bottom", style.paddingV, 0...60, "%.0f pt")
            Toggle("Shadow", isOn: style.shadow)
        }
        Section("Timing & animation") {
            slider("Stays on screen", style.duration, 0.3...6, "%.1f s")
            Picker("Appear / disappear", selection: style.motion) {
                Text("Fade").tag(HUDStyle.Motion.fade)
                Text("Slide").tag(HUDStyle.Motion.slide)
                Text("Pop").tag(HUDStyle.Motion.pop)
                Text("None").tag(HUDStyle.Motion.none)
            }
            slider("Animation speed", style.animationSpeed, 0.05...1, "%.2f s").disabled(prefs.hudStyle.motion == .none)
            HStack {
                Button("Show on Screen") { KeyHUD.shared.flash("⇧⌘T", caption: "Reopen Closed Tab", force: true) }
                    .glassButton()
                Spacer()
                Button("Reset to Defaults") { withAnimation(Theme.smooth) { prefs.hudStyle = HUDStyle() } }
                    .disabled(prefs.hudStyle == HUDStyle())
            }
        }
    }

    // MARK: Preview

    private static let grid: [[HUDStyle.Position]] = [[.topLeft, .topCenter, .topRight], [.middleLeft, .center, .middleRight],
                                                     [.bottomLeft, .bottomCenter, .bottomRight]]

    /// A little desktop with the bubble where it will appear, at ~half size.
    private var preview: some View {
        let st = prefs.hudStyle, scale = 0.5
        return ZStack(alignment: Self.alignment(st.position)) {
            LinearGradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.95), Color(red: 0.85, green: 0.45, blue: 0.75),
                                    Color(red: 1, green: 0.7, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            bubble(st)
                .scaleEffect(scale, anchor: Self.anchor(st.position))
                .padding(8 + st.margin * 0.12)
            VStack(spacing: 0) {
                ForEach(Self.grid, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { p in
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { withAnimation(Theme.bouncy) { prefs.hudStyle.position = p } }
                                .help(p.rawValue)
                        }
                    }
                }
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .animation(Theme.smooth, value: st)
    }

    private func bubble(_ st: HUDStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: st.cornerRadius, style: .continuous)
        return VStack(spacing: 2) {
            Text("⇧⌘T").font(Font(st.keyFont() as CTFont))
            if st.showCaption {
                Text("Reopen Closed Tab").font(Font(st.captionFont() as CTFont)).opacity(0.75)
            }
        }
        .foregroundStyle(Color(nsColor: st.textColor.ns))
        .padding(.horizontal, st.paddingH).padding(.vertical, st.paddingV)
        .modifier(BubbleBox(st: st, shape: shape))
        .shadow(color: .black.opacity(st.shadow ? 0.3 : 0), radius: 12, y: 4)
        .fixedSize()
    }

    private static func alignment(_ p: HUDStyle.Position) -> Alignment {
        switch p {
        case .topLeft: .topLeading
        case .topCenter: .top
        case .topRight: .topTrailing
        case .middleLeft: .leading
        case .center: .center
        case .middleRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    private static func anchor(_ p: HUDStyle.Position) -> UnitPoint {
        let a = alignment(p)
        return UnitPoint(x: a.horizontal == .leading ? 0 : a.horizontal == .trailing ? 1 : 0.5,
                         y: a.vertical == .top ? 0 : a.vertical == .bottom ? 1 : 0.5)
    }

    private func slider(_ title: String, _ value: SwiftUI.Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: fmt, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            }
        }
    }

    private func color(_ key: WritableKeyPath<HUDStyle, HUDStyle.RGBA>) -> SwiftUI.Binding<Color> {
        SwiftUI.Binding(get: { Color(nsColor: prefs.hudStyle[keyPath: key].ns) },
                        set: { prefs.hudStyle[keyPath: key] = HUDStyle.RGBA(NSColor($0)) })
    }
}

/// The box as the real bubble draws it: solid, clear glass, colored glass or blur.
private struct BubbleBox<S: Shape>: ViewModifier {
    let st: HUDStyle
    let shape: S
    func body(content: Content) -> some View {
        let color = Color(nsColor: st.background.ns)
        switch st.box {
        case .solid: content.background(color, in: shape)
        case .glass: content.liquidGlass(in: shape)
        case .tinted: content.liquidGlass(in: shape, tint: color)
        case .frosted: content.background(color, in: shape).background(.ultraThinMaterial, in: shape)
        }
    }
}
