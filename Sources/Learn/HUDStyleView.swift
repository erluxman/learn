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
            SettingRow(title: "Animation", detail: "How the bubble appears and leaves.", symbol: "wand.and.stars", color: .orange) {
                Picker("", selection: style.motion) {
                    Text("Jelly").tag(HUDStyle.Motion.jelly)
                    Text("Fade").tag(HUDStyle.Motion.fade)
                    Text("Slide").tag(HUDStyle.Motion.slide)
                    Text("Pop").tag(HUDStyle.Motion.pop)
                    Text("None").tag(HUDStyle.Motion.none)
                }
                .labelsHidden().frame(width: 210)
            }
            SettingRow(title: "Font", symbol: "textformat", color: .blue) {
                Picker("", selection: style.font) {
                    Text("System").tag("")
                    Text("System Rounded").tag(".rounded")
                    Text("System Monospaced").tag(".mono")
                    Divider()
                    ForEach(Self.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 210)
            }
        } header: {
            Text("Shortcut bubble")
        } footer: {
            Text("Click a spot on the preview to move the bubble there. Pointer mode's hint uses this style too.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
        // Background: Liquid glass, like Spotlight, in a color of your choice.
        Section("Background") {
            SettingRow(title: "Glass color", symbol: "paintpalette.fill", color: .purple) {
                ColorPicker("", selection: SwiftUI.Binding(get: { Color(nsColor: prefs.hudStyle.tint.ns) },
                                                           set: { prefs.hudStyle.tint = HUDStyle.RGBA(NSColor($0)) }),
                            supportsOpacity: false)
                    .labelsHidden()
            }
            row("Color intensity", "How strongly the glass takes the color. 0 keeps it Spotlight's plain dark glass.", "drop.fill", .blue,
                style.tintStrength, 0...1, "\(Int((prefs.hudStyle.tintStrength * 100).rounded()))%")
            SettingRow(title: "Gradient", detail: "A lighter shade of the color sliding into a deeper one, instead of one flat color.",
                       symbol: "circle.lefthalf.filled", color: .pink) {
                Toggle("", isOn: style.gradient).labelsHidden().toggleStyle(.switch)
            }
            .disabled(prefs.hudStyle.tintStrength == 0)
            row("Corner roundness", "How rounded the bubble is.", "square.on.square", .indigo,
                SwiftUI.Binding(get: { prefs.hudStyle.corner }, set: { prefs.hudStyle.cornerRadius = $0.rounded() }),
                0...prefs.hudStyle.maxCorner.rounded(.down), String(format: "%.0f pt", prefs.hudStyle.corner))
        }
        Section {
            HStack {
                Button("Show on Screen") { KeyHUD.shared.flash("⇧⌘T".spacedKeys, caption: "Reopen Closed Tab", force: true) }
                    .glassButton()
                Spacer()
                Button("Reset to Spotlight Look") { withAnimation(Theme.smooth) { prefs.hudStyle = HUDStyle() } }
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
        let shape = RoundedRectangle(cornerRadius: st.corner, style: .continuous)
        return VStack(spacing: 2) {
            Text("⇧⌘T".spacedKeys).font(Font(st.keyFont() as CTFont))
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

    /// A slider row laid out like Settings ▸ Appearance's.
    private func row(_ title: String, _ detail: String?, _ symbol: String, _ color: Color, _ value: SwiftUI.Binding<Double>,
                     _ range: ClosedRange<Double>, _ label: String) -> some View {
        SettingRow(title: title, detail: detail, symbol: symbol, color: color) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).sliderTicks(value.wrappedValue, in: range).frame(width: 210)
                Text(label).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            }
        }
    }

}

/// The box as the real bubble draws it, from the current backdrop's own look.
private struct BubbleBox<S: InsettableShape>: ViewModifier {
    let st: HUDStyle
    let shape: S
    func body(content: Content) -> some View {
        let look = st.current, color = Color(nsColor: look.color.ns)
        let boxed = Group {
            if let tint = st.glassTint {
                let wash = LinearGradient(colors: st.washColors.map { Color(nsColor: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                if #available(macOS 26, *) {
                    content.background(wash.opacity(st.tintStrength * 0.7), in: shape)
                        .glassEffect(Glass.regular.tint(Color(nsColor: tint)), in: shape)
                } else { content.background(wash.opacity(st.tintStrength), in: shape).background(.regularMaterial, in: shape) }
            } else {
            switch st.box {
            case .solid:
                content.background(color.opacity(look.opacity), in: shape)
            case .spotlight:
                if #available(macOS 26, *) {
                    content.glassEffect(Glass.regular.tint(look.darken > 0 ? .black.opacity(look.darken) : nil), in: shape)
                        .environment(\.colorScheme, st.textColor.ns.brightnessComponentSafe > 0.5 ? .dark : .light)
                } else { content.background(.regularMaterial, in: shape) }
            case .glass:
                if #available(macOS 26, *) {
                    content.glassEffect(Glass.clear.tint(look.darken > 0 ? .black.opacity(look.darken) : nil), in: shape)
                } else { content.background(.ultraThinMaterial, in: shape) }
            case .tinted:
                if #available(macOS 26, *) {
                    content.background(color.opacity(look.opacity * 0.7), in: shape)
                        .glassEffect(Glass.regular.tint(color.opacity(look.opacity)), in: shape)
                } else { content.background(color.opacity(look.opacity), in: shape).background(.regularMaterial, in: shape) }
            case .frosted:
                content.background(color.opacity(look.opacity), in: shape)
                    .background {
                        GeometryReader { g in
                            if look.material.isTunable {
                                BackdropBlur(params: look.backdropParams(corner: min(st.corner, g.size.height / 2)))
                            } else {
                                BehindWindowBlur(material: look.material.appKitMaterial ?? .hudWindow, radius: min(st.corner, g.size.height / 2))
                                    .opacity(look.blur)
                            }
                        }
                    }
            }
            }
        }
        boxed.overlay(shape.strokeBorder(.white.opacity(look.shine * 0.7), lineWidth: look.shine > 0 ? 1 : 0))
    }
}
