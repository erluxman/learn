import SwiftUI

/// How Learn's glass looks and moves. Edited in Settings ▸ Appearance; every glass surface reads it live.
struct Appearance: Codable, Equatable {
    enum Material: String, Codable, CaseIterable { case clear, regular }
    enum IconStyle: String, Codable, CaseIterable { case tinted, mono, color }

    var material = Material.regular           // Liquid Glass comes in two blur levels: clear and regular
    var tint = HUDStyle.RGBA(NSColor.systemPurple)
    var tintStrength = 0.0                    // 0 no color … 1 strongly colored glass
    var darkness = 0.0                        // 0 as macOS draws it … 1 smoked glass
    var cornerRadius = 26.0
    var shadow = 0.5
    var light = 1.0                           // how strongly glass catches the pointer
    var wobble = 1.0                          // jelly wobble when a window is dragged; 0 off
    var hoverMotion = true                    // swell, lean and tilt under the pointer
    var fontChoice: String? = nil             // "" SF Pro · ".rounded" · ".serif" · ".mono" · a font family; nil = default

    var iconStyleChoice: IconStyle? = nil     // nil = default
    var iconStyle: IconStyle { iconStyleChoice ?? .tinted }

    static let defaultFont = ".rounded"
    var font: String { fontChoice ?? Self.defaultFont }
    /// System designs go through SwiftUI's font design; a family name is used as a custom font.
    var fontDesign: Font.Design? {
        switch font {
        case "": .default
        case ".rounded": .rounded
        case ".serif": .serif
        case ".mono": .monospaced
        default: nil
        }
    }

    var tintColor: Color { Color(nsColor: tint.ns) }

    /// The one tint the glass is drawn with: the chosen color, pulled toward black by `darkness`; nil = untinted.
    var glassTint: Color? {
        guard tintStrength > 0 || darkness > 0 else { return nil }
        let base = tintStrength > 0 ? tint.ns : .black
        let color = base.blended(withFraction: tintStrength > 0 ? darkness : 0, of: .black) ?? base
        return Color(nsColor: color.withAlphaComponent(max(tintStrength, darkness)))
    }
    var radius: CGFloat { cornerRadius }
}

private struct AppearanceKey: EnvironmentKey { static let defaultValue = Appearance() }

extension EnvironmentValues {
    var appearance: Appearance {
        get { self[AppearanceKey.self] }
        set { self[AppearanceKey.self] = newValue }
    }
}

/// Hands the current appearance to everything below, and re-renders when it changes.
struct AppearanceRoot<Content: View>: View {
    @ObservedObject private var prefs = Prefs.shared
    @ViewBuilder let content: Content
    var body: some View {
        content
            .environment(\.appearance, prefs.appearance)
            .fontDesign(prefs.appearance.fontDesign ?? .default)
            .font(.app(13))                  // for text that doesn't set its own size
            .id(prefs.appearance.font)       // a new font: rebuild so every Text picks it up
    }
}

extension Font {
    /// Learn's text font at `size`: the family chosen in Settings ▸ Appearance, or SF in the chosen design.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let look = Prefs.shared.appearance
        guard look.fontDesign == nil else { return .system(size: size, weight: weight) }   // design comes from the environment
        return .custom(look.font, size: size).weight(weight)
    }
}
