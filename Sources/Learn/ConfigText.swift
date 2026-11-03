import AppKit

/// Reads values out of what the user says: sentences and clauses, numbers, colors, option names, questions.
/// It doesn't decide what the user means (SemanticModel does); it fills in the "30%", the "purple", the "Instagram".
enum ConfigText {
    static func normalize(_ raw: String) -> String {
        var t = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        t = t.replacingOccurrences(of: #"[^a-z0-9#%'&\-\.\?,;\s]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\.(?!\d)"#, with: " ", options: .regularExpression)   // keep 0.5, drop full stops
        return t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func sentences(_ raw: String) -> [String] {
        raw.replacingOccurrences(of: #"([.!?])\s+"#, with: "$1\n", options: .regularExpression)
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// "the background is nice, but the sound is too loud" → two clauses.
    static func clauses(_ sentence: String) -> [String] {
        sentence.split(separator: #/\s*(?:,|;|\band then\b|\bthen\b|\balso\b|\bbut\b|\band\b)\s*/#)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.split(separator: " ").count >= 2 }
    }

    static func isQuestion(_ text: String) -> Bool {
        let t = normalize(text)
        return text.hasSuffix("?") && t.range(of: #"^(what|what's|whats|how|is|are|which|does|do)\b"#, options: .regularExpression) != nil
    }

    static func has(_ phrase: String, _ text: String) -> Bool {
        (" " + normalize(text).replacingOccurrences(of: #"[?,;]"#, with: " ", options: .regularExpression) + " ").contains(" \(phrase) ")
    }

    /// "30%", "20 pt", "0.5", "half", "max". Percent settings take 30 as 30%.
    static func number(_ raw: String, for s: ConfigSetting) -> Double? {
        guard case .number(let range, _, let unit) = s.kind else { return nil }
        let text = normalize(raw)
        if text.range(of: #"\b(max|maximum|highest)\b"#, options: .regularExpression) != nil { return range.upperBound }
        if text.range(of: #"\b(min|minimum|lowest|zero)\b"#, options: .regularExpression) != nil { return range.lowerBound }
        guard let m = text.firstMatch(of: #/(\d+(?:\.\d+)?)\s*(%|percent)?/#), let n = Double(m.1) else { return nil }
        let v = unit == .percent && (m.2 != nil || n > range.upperBound) ? n / 100 : n
        return min(max(v, range.lowerBound), range.upperBound)
    }

    /// An option of a choice setting named in the text ("instagram" for the background).
    static func option(_ raw: String, for s: ConfigSetting) -> String? {
        guard case .choice(let options) = s.kind else { return nil }
        return options.filter { !$0.id.isEmpty }.flatMap { o in o.aliases.filter { has($0, raw) }.map { (o.id, $0.count) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// A value given as words by Apple Intelligence ("on", "30%", "purple", "Liquid glass", "more") for `s`.
    static func op(for s: ConfigSetting, value raw: String) -> ConfigOp? {
        let v = normalize(raw)
        if ["reset", "default"].contains(v) { return .reset }
        switch s.kind {
        case .toggle:
            if ["on", "true", "yes", "enable", "enabled", "show"].contains(v) { return .set(.bool(true)) }
            if ["off", "false", "no", "disable", "disabled", "hide"].contains(v) { return .set(.bool(false)) }
            return v == "toggle" ? .toggle : nil
        case .number:
            if ["more", "increase", "up", "higher"].contains(v) { return .step(1) }
            if ["less", "decrease", "down", "lower"].contains(v) { return .step(-1) }
            if ["off", "none"].contains(v) { return .set(.bool(false)) }
            return number(raw, for: s).map { .set(.number($0)) }
        case .color:
            return ColorNames.find(in: v).map { .set(.color($0)) }
        case .choice(let options):
            if let id = option(raw, for: s) ?? options.first(where: { normalize($0.title) == v })?.id { return .set(.choice(id)) }
            if s.id == "background", let c = ColorNames.find(in: v) { return .set(.choice(gradient(near: c, away: false, from: s.get()))) }
            return nil
        }
    }

    /// The gradient whose middle color is nearest `color`, or (`away`) a vivid one far from it; never the current one.
    static func gradient(near color: HUDStyle.RGBA, away: Bool, from now: ConfigValue) -> String {
        let h = ColorNames.hue(color).hue
        let scored = GradientPreset.all.compactMap { p -> (String, Double)? in
            guard p.hex.count > 1, .choice(p.name) != now else { return nil }
            let mid = p.hex[1]
            let c = HUDStyle.RGBA(NSColor(srgbRed: Double(mid >> 16 & 255) / 255, green: Double(mid >> 8 & 255) / 255, blue: Double(mid & 255) / 255, alpha: 1))
            let (hue, sat) = ColorNames.hue(c)
            return sat > 0.3 ? (p.name, ColorNames.hueDistance(hue, h)) : nil
        }
        if away { return scored.filter { $0.1 >= 0.3 }.randomElement()?.0 ?? "" }
        return scored.min { $0.1 < $1.1 }?.0 ?? ""
    }

    /// Any other option of a choice setting, for "change the background" / "new key colors".
    static func another(_ s: ConfigSetting) -> String? {
        guard case .choice(let options) = s.kind else { return nil }
        let now = s.get()
        if s.id == "background" || s.id == "keyGradient" {
            return GradientPreset.all.filter { .choice($0.name) != now && $0.group == .vivid }.randomElement()?.name
        }
        return options.first { .choice($0.id) != now }?.id
    }
}
