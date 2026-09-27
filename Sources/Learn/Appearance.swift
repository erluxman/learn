import SwiftUI

/// How Learn's glass looks and moves. Edited in Settings ▸ Appearance; every glass surface reads it live.
struct Appearance: Codable, Equatable {
    enum Material: String, Codable, CaseIterable { case clear, regular }
    enum IconStyle: String, Codable, CaseIterable, Identifiable {
        case slab, frosted, tinted, mono, color, glass, outline, gradient, soft, plain
        var id: Self { self }
        var title: String {
            switch self {
            case .slab: "3D glass"
            case .frosted: "Frosted glass"
            default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }
    }
    /// What Learn's windows are made of: a living gradient in each page's color (the Cleaner look), one in the
    /// theme's colors, or glass (the blur and tint settings below).
    enum Surface: String, Codable, CaseIterable, Identifiable {
        case colorful, glass
        var id: Self { self }
        var title: String {
            switch self { case .colorful: "Colorful gradient"; case .glass: "Liquid glass" }
        }
        /// Surfaces that no longer exist (the old "theme" gradient) come back as Colorful instead of failing to load.
        init(from decoder: Decoder) throws {
            self = Surface(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .colorful
        }
    }

    var material = Material.regular           // Liquid Glass comes in two blur levels: clear and regular
    var tint = HUDStyle.RGBA(NSColor.systemPurple)
    var tintStrength = 0.0                    // Liquid glass only: 0 no color … 1 strongly colored glass
    var wobble = 1.0                          // jelly wobble when a window is dragged; 0 off

    // Settled looks, no longer settings (older saved values for them are ignored):
    var cornerRadius: Double { 40 }
    var shadow: Double { 1 }
    var hoverMotion: Bool { true }            // swell, lean and tilt under the pointer
    var iconStyle: IconStyle { .gradient }    // icons in pages, and the selected sidebar item
    var idleIconStyle: IconStyle { .plain }   // sidebar items that aren't selected
    var surfaceChoice: Surface? = nil
    var surface: Surface { surfaceChoice ?? .colorful }

    var soundVolumeChoice: Double? = nil
    var clickSound: SoundEffect { .tick }       // settled sounds; only the volume is a setting
    var shortcutSound: SoundEffect { .coin }    // game-style coin: the shortcut ran
    var soundVolume: Double { soundVolumeChoice ?? 0.5 }

    static let defaultFont = ""   // SF Pro, as Spotlight
    var font: String { Self.defaultFont }
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


    // No grain, and Liquid Glass at its regular blur: fixed, no longer settings.
    var grain: Double { 0 }
    var grainStyle: GrainStyle { .none }
    var grainScale: Double { 1 }
    var grainColor: HUDStyle.RGBA? { nil }
    var blur: BlurStyle { .liquidRegular }
    var blurAmount: Double { 1 }
    var blurRadius: Double { min(blur.preset.radius, BlurStyle.maxRadius) }
    var blurSaturation: Double { blur.preset.saturation }

    /// Gradients draw their own color; only Liquid glass takes a tint.
    var sheen: [Color]? { nil }

    /// Liquid glass tinted with the chosen color at the chosen intensity; nil = untinted (and on gradient surfaces).
    var glassTint: Color? {
        guard surface == .glass, tintStrength > 0 else { return nil }
        return Color(nsColor: tint.ns.withAlphaComponent(tintStrength))
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
        // `.custom(family).weight(_)` silently falls back to SF when the family lacks that exact weight,
        // so pick the family's closest upright face ourselves.
        guard let face = FontFaces.closest(family: look.font, weight: weight), let ns = NSFont(name: face, size: size) else {
            return .custom(look.font, size: size)
        }
        return Font(ns as CTFont)
    }
}

private enum FontFaces {
    private static var cache: [String: String] = [:]

    /// PostScript name of the family's non-italic member nearest `weight` (ties go to the heavier face).
    static func closest(family: String, weight: Font.Weight) -> String? {
        let target = nsWeight(weight), key = "\(family)|\(target)"
        if let hit = cache[key] { return hit }
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        let upright = members.compactMap { m -> (name: String, weight: Int)? in
            guard m.count >= 4, let name = m[0] as? String, let w = m[2] as? Int, let traits = m[3] as? UInt,
                  traits & NSFontTraitMask.italicFontMask.rawValue == 0 else { return nil }
            return (name, w)
        }
        let best = upright.min { a, b in
            let da = abs(a.weight - target), db = abs(b.weight - target)
            return da != db ? da < db : a.weight > b.weight
        }?.name
        cache[key] = best
        return best
    }

    /// SwiftUI weight → NSFontManager's 0–15 weight scale (5 regular, 9 bold).
    private static func nsWeight(_ w: Font.Weight) -> Int {
        switch w {
        case .ultraLight: 2
        case .thin: 3
        case .light: 4
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 10
        case .black: 11
        default: 5
        }
    }
}
