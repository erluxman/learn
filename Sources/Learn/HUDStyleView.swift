import SwiftUI

/// Settings ▸ General ▸ Shortcut display ▸ Customize…: its own window; every change previews the bubble live.
final class HUDStyleWindow {
    static let shared = HUDStyleWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Shortcut Display"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HUDStyleView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HUDStyleView: View {
    @ObservedObject private var prefs = Prefs.shared
    private static let families = NSFontManager.shared.availableFontFamilies

    private var style: SwiftUI.Binding<HUDStyle> { $prefs.hudStyle }

    var body: some View {
        Form {
            Section {
                Toggle("Show shortcuts as you press them", isOn: $prefs.showKeyHUD)
                Text("Pointer mode's hint uses this style too, and shows even when this is off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Position") {
                LabeledContent("Where on screen") { positionGrid }
                slider("Distance from edge", style.margin, 0...300, "%.0f pt")
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
                ColorPicker("Background", selection: color(\.background), supportsOpacity: true)
                Toggle("Frosted glass (blur behind)", isOn: style.frosted)
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
            }
            Section {
                HStack {
                    Button("Preview") { preview() }
                    Spacer()
                    Button("Reset to Defaults") { prefs.hudStyle = HUDStyle() }.disabled(prefs.hudStyle == HUDStyle())
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onChange(of: prefs.hudStyle) { preview() }
    }

    private func preview() { KeyHUD.shared.flash("⇧⌘T", caption: "Reopen Closed Tab", force: true) }

    /// 3×3 grid of screen spots, laid out like the screen.
    private var positionGrid: some View {
        let rows: [[HUDStyle.Position]] = [[.topLeft, .topCenter, .topRight], [.middleLeft, .center, .middleRight],
                                          [.bottomLeft, .bottomCenter, .bottomRight]]
        return VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { p in
                        let on = prefs.hudStyle.position == p
                        RoundedRectangle(cornerRadius: 4)
                            .fill(on ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 34, height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.4)))
                            .contentShape(Rectangle())
                            .onTapGesture { prefs.hudStyle.position = p }
                            .help(p.rawValue)
                    }
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5)))
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
