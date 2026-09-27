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
        case colorful, theme, glass
        var id: Self { self }
        var title: String {
            switch self { case .colorful: "Colorful gradient"; case .theme: "Theme gradient"; case .glass: "Glass" }
        }
    }

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
    var iconStyle: IconStyle { iconStyleChoice ?? .slab }   // icons in pages, and the selected sidebar item
    var idleIconStyleChoice: IconStyle? = nil
    var idleIconStyle: IconStyle { idleIconStyleChoice ?? .frosted }   // sidebar items that aren't selected, as in the Cleaner
    var surfaceChoice: Surface? = nil
    var surface: Surface { surfaceChoice ?? .colorful }

    var clickSoundChoice: SoundEffect? = nil
    var shortcutSoundChoice: SoundEffect? = nil
    var soundVolumeChoice: Double? = nil
    var clickSound: SoundEffect { clickSoundChoice ?? .tick }
    var shortcutSound: SoundEffect { shortcutSoundChoice ?? .pop }
    var soundVolume: Double { soundVolumeChoice ?? 0.5 }

    static let defaultFont = ""   // SF Pro, as Spotlight
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

    var tintColor: Color { Color(nsColor: themeColors[0].ns) }

    /// The one tint the glass is drawn with: the chosen color, pulled toward black by `darkness`; nil = untinted.
    var themeColorsChoice: [HUDStyle.RGBA]? = nil   // 1–3 colors from the theme designer; nil = the single `tint`
    var grainChoice: Double? = nil
    var themeColors: [HUDStyle.RGBA] { themeColorsChoice.flatMap { $0.isEmpty ? nil : $0 } ?? [tint] }
    var grain: Double { grainChoice ?? 0 }
    var grainStyleChoice: GrainStyle? = nil
    var grainScaleChoice: Double? = nil
    var grainStyle: GrainStyle { grainStyleChoice ?? (grain > 0 ? .film : .none) }
    var grainScale: Double { grainScaleChoice ?? 1 }
    var grainColor: HUDStyle.RGBA? = nil      // nil: grey grain blended into the glass; a color: grain in that color

    var blurStyleChoice: BlurStyle? = nil     // nil: from `material` (before blur styles existed)
    var blurAmountChoice: Double? = nil
    var blur: BlurStyle { blurStyleChoice ?? (material == .clear ? .liquidClear : .liquidRegular) }
    var blurAmount: Double { blurAmountChoice ?? 1 }
    var blurRadiusChoice: Double? = nil       // tunable blurs only; nil = the style's preset
    var blurSaturationChoice: Double? = nil
    var blurRadius: Double { min(blurRadiusChoice ?? blur.preset.radius, BlurStyle.maxRadius) }
    var blurSaturation: Double { blurSaturationChoice ?? blur.preset.saturation }

    /// The theme's colors averaged: what the glass itself is tinted with.
    private var themeBlend: NSColor {
        let cs = themeColors.map { $0.ns.usingColorSpace(.sRGB) ?? .white }
        let n = CGFloat(cs.count)
        return NSColor(srgbRed: cs.map(\.redComponent).reduce(0, +) / n, green: cs.map(\.greenComponent).reduce(0, +) / n,
                       blue: cs.map(\.blueComponent).reduce(0, +) / n, alpha: 1)
    }

    /// With 2–3 theme colors: the gradient glass can't hold (its tint is one color), laid lightly on top of it.
    var sheen: [Color]? {
        themeColors.count > 1 && tintStrength > 0 ? themeColors.map { Color(nsColor: $0.ns).opacity(tintStrength * 0.4) } : nil
    }

    var glassTint: Color? {
        guard tintStrength > 0 || darkness > 0 else { return nil }
        let base = tintStrength > 0 ? themeBlend : .black
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
