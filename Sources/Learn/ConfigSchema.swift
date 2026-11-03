import AppKit

/// Every setting AI Config may change, typed: what it's called, its range, and how to read and write it. Whatever
/// understands the user (the semantic model, Apple Intelligence) only picks a setting and a value from here; the
/// schema checks, clamps and applies it, and knows how to undo it.
enum ConfigValue: Equatable {
    case bool(Bool)
    case number(Double)
    case choice(String)          // an Option id
    case color(HUDStyle.RGBA)
}

enum ConfigOp: Equatable {
    case set(ConfigValue)
    case toggle
    case step(Int)               // +1 more, -1 less
    case reset
}

struct ConfigSetting: Identifiable {
    enum Unit { case percent, points, minutes }
    struct Option { let id: String; let title: String; var aliases: [String] = [] }
    enum Kind {
        case toggle
        case number(ClosedRange<Double>, step: Double, unit: Unit)
        case choice([Option])
        case color
    }

    let id: String
    let title: String
    let detail: String                 // plain sentence: shown in the Models page, fed to embeddings and the model
    let aliases: [String]              // names for it: speech-recognition hints, option names read from a sentence
    let kind: Kind
    let tab: SettingsWindow.Tab
    let defaultValue: ConfigValue
    let get: () -> ConfigValue
    let set: (ConfigValue) -> Void

    func format(_ v: ConfigValue) -> String {
        switch (v, kind) {
        case (.bool(let b), _): return b ? "on" : "off"
        case (.number(let n), .number(_, _, let unit)):
            switch unit {
            case .percent: return "\(Int((n * 100).rounded()))%"
            case .points: return "\(Int(n.rounded())) pt"
            case .minutes: return "\(Int(n.rounded())) min"
            }
        case (.choice(let id), .choice(let options)): return options.first { $0.id == id }?.title ?? (id == "mixed" ? "a gradient per page" : id)
        case (.color(let c), _): return ColorNames.name(of: c)
        default: return "?"
        }
    }

    /// What `op` would make of the current value, clamped to the setting's range; nil when it can't apply.
    func resolve(_ op: ConfigOp) -> ConfigValue? {
        let now = get()
        switch (op, kind) {
        case (.reset, _): return defaultValue
        case (.toggle, .toggle): if case .bool(let b) = now { return .bool(!b) }; return nil
        case (.set(.bool(let on)), .number(let r, _, _)):   // "sounds off" on a volume: bottom; "on": back to default
            if !on { return .number(r.lowerBound) }
            if case .number(let n) = now, n > r.lowerBound { return nil }
            return defaultValue
        case (.set(.number(let n)), .number(let r, _, _)): return .number(min(max(n, r.lowerBound), r.upperBound))
        case (.step(let dir), .number(let r, let step, _)):
            guard case .number(let n) = now else { return nil }
            return .number(min(max(n + Double(dir) * step, r.lowerBound), r.upperBound))
        case (.set(.bool), .toggle), (.set(.choice), .choice), (.set(.color), .color): return op.value
        default: return nil
        }
    }
}

private extension ConfigOp {
    var value: ConfigValue? { if case .set(let v) = self { v } else { nil } }
}

/// One applied change — a setting, or a shortcut made or removed — with its way back.
struct AppliedChange: Identifiable {
    let id = UUID()
    let label: String          // "Sound volume: 50% → 30%"
    let spoken: String         // "Sound volume 30%"
    let undoLabel: String      // "Sound volume back to 50%"
    let tab: SettingsWindow.Tab
    var warning: String? = nil
    let undo: () -> Void
}

enum ConfigSchema {
    static func setting(_ id: String) -> ConfigSetting? { all.first { $0.id == id } }

    /// Applies `op`. Glass color also switches the surface to glass and gives the tint some strength, as separate
    /// changes so each can be undone and is listed.
    static func apply(_ setting: ConfigSetting, _ op: ConfigOp) -> [AppliedChange] {
        guard let to = setting.resolve(op) else { return [] }
        var out: [AppliedChange] = []
        if setting.id == "glassColor" {
            if let s = Self.setting("surface"), s.get() != .choice("glass") { out += apply(s, .set(.choice("glass"))) }
            if let s = Self.setting("glassIntensity"), case .number(let n) = s.get(), n < 0.3 { out += apply(s, .set(.number(0.45))) }
        }
        let from = setting.get()
        guard from != to else { return out }
        let gradients = prefs.pageGradients   // the background sets every page; undo puts back each page's own pick
        setting.set(to)
        var change = AppliedChange(label: "\(setting.title): \(setting.format(from)) → \(setting.format(to))",
                                   spoken: "\(setting.title) \(setting.format(to))",
                                   undoLabel: "\(setting.title) back to \(setting.format(from))", tab: setting.tab,
                                   undo: setting.id == "background" ? { prefs.pageGradients = gradients } : { setting.set(from) })
        if setting.id == "mouse", to == .bool(false) { change.warning = "The mouse and trackpad are off: press ⌃⌥⌘M to turn them back on." }
        return out + [change]
    }

    private static var prefs: Prefs { Prefs.shared }

    private static func toggle(_ id: String, _ title: String, _ detail: String, _ aliases: [String], tab: SettingsWindow.Tab,
                               default d: Bool, _ key: ReferenceWritableKeyPath<Prefs, Bool>, inverted: Bool = false) -> ConfigSetting {
        ConfigSetting(id: id, title: title, detail: detail, aliases: aliases, kind: .toggle, tab: tab, defaultValue: .bool(d),
                      get: { .bool(prefs[keyPath: key] != inverted) },
                      set: { if case .bool(let b) = $0 { prefs[keyPath: key] = b != inverted } })
    }

    static let all: [ConfigSetting] = [
        ConfigSetting(id: "volume", title: "Sound volume", detail: "How loud Learn's clicks and shortcut sounds are. 0 is silent.",
                      aliases: ["volume", "sound", "sounds", "click sound", "clicks", "clicking", "audio", "noise", "noises", "beep", "beeps", "tick", "ticks", "mute", "silent", "silence", "hear"],
                      kind: .number(0...1, step: 0.15, unit: .percent), tab: .permissions, defaultValue: .number(0.5),
                      get: { .number(prefs.appearance.soundVolume) },
                      set: { if case .number(let n) = $0 { prefs.appearance.soundVolumeChoice = n } }),
        ConfigSetting(id: "cornerRadius", title: "Corner roundness", detail: "How rounded the corners of the Settings and Cleaner windows are.",
                      aliases: ["corner roundness", "corner radius", "corners", "corner", "roundness", "rounded", "radius", "edges", "round"],
                      kind: .number(0...160, step: 20, unit: .points), tab: .appearance, defaultValue: .number(40),
                      get: { .number(prefs.appearance.cornerRadius) },
                      set: { if case .number(let n) = $0 { prefs.appearance.cornerRadiusChoice = n.rounded() } }),
        ConfigSetting(id: "wobble", title: "Jelly wobble", detail: "How much windows wobble like jelly when you drag them. 0 turns it off.",
                      aliases: ["jelly wobble", "wobble", "wobbly", "wobbling", "jelly", "jiggle", "jiggles", "wiggle", "shaking", "shake", "shakes", "bounce", "bouncy", "springy", "elastic"],
                      kind: .number(0...2, step: 0.3, unit: .percent), tab: .appearance, defaultValue: .number(1),
                      get: { .number(prefs.appearance.wobble) },
                      set: { if case .number(let n) = $0 { prefs.appearance.wobble = n } }),
        ConfigSetting(id: "surface", title: "Window surface", detail: "What Learn's windows are made of: a colorful living gradient, or liquid glass that lets the screen show through.",
                      aliases: ["surface", "window surface", "material"],
                      kind: .choice([
                          .init(id: "colorful", title: "Colorful gradient", aliases: ["colorful", "colourful", "vivid", "solid", "opaque", "not see-through", "less see-through", "less transparent"]),
                          .init(id: "glass", title: "Liquid glass", aliases: ["liquid glass", "glass", "glassy", "transparent", "see-through", "see through", "translucent", "frosted"]),
                      ]), tab: .appearance, defaultValue: .choice("colorful"),
                      get: { .choice(prefs.appearance.surface.rawValue) },
                      set: { if case .choice(let id) = $0 { prefs.appearance.surfaceChoice = Appearance.Surface(rawValue: id) } }),
        ConfigSetting(id: "background", title: "Background gradient", detail: "The living gradient behind the Settings pages when the surface is Colorful. Each page has its own color unless one gradient is picked for all.",
                      aliases: ["background gradient", "background", "backgrounds", "backdrop", "gradient", "window color", "window colour", "page color", "page colour", "wallpaper"],
                      kind: .choice([.init(id: "", title: "Each page's own color", aliases: ["default", "original", "page colors", "each page"])]
                                    + GradientPreset.all.map { .init(id: $0.name, title: $0.name, aliases: [$0.name.lowercased()]) }),
                      tab: .appearance, defaultValue: .choice(""),
                      get: {
                          let picks = Set(SettingsWindow.Tab.allCases.map { prefs.pageGradients["settings.\($0.rawValue)"] ?? "" })
                          return .choice(picks.count == 1 ? picks.first! : "mixed")
                      },
                      set: {
                          guard case .choice(let id) = $0, id != "mixed" else { return }
                          var g = prefs.pageGradients
                          for t in SettingsWindow.Tab.allCases { g["settings.\(t.rawValue)"] = id.isEmpty ? nil : id }
                          prefs.pageGradients = g
                      }),
        ConfigSetting(id: "glassColor", title: "Glass color", detail: "The color the liquid glass is tinted with.",
                      aliases: ["glass color", "glass colour", "tint color", "tint", "color", "colour", "hue", "theme color"],
                      kind: .color, tab: .appearance, defaultValue: .color(HUDStyle.RGBA(.systemPurple)),
                      get: { .color(prefs.appearance.tint) },
                      set: { if case .color(let c) = $0 { prefs.appearance.tint = c } }),
        ConfigSetting(id: "glassIntensity", title: "Glass color intensity", detail: "How strongly the liquid glass takes its color. 0 keeps it clear.",
                      aliases: ["color intensity", "colour intensity", "tint strength", "tint intensity", "intensity", "saturation", "tinted", "colored", "coloured"],
                      kind: .number(0...1, step: 0.2, unit: .percent), tab: .appearance, defaultValue: .number(0),
                      get: { .number(prefs.appearance.tintStrength) },
                      set: { if case .number(let n) = $0 { prefs.appearance.tintStrength = n } }),
        toggle("keyHUD", "Shortcut bubble", "A bubble on screen with the keys you press and the command they run.",
               ["shortcut bubble", "key bubble", "keys bubble", "bubble", "key hud", "hud", "keystrokes", "keystroke", "key presses", "keys i press", "keys i type", "what keys", "keycast", "screencast"],
               tab: .display, default: true, \.showKeyHUD),
        toggle("chordRightClick", "Both ⌃ keys = right-click", "Pressing left and right Control together right-clicks at the pointer.",
               ["both control", "control chord", "ctrl chord", "control keys", "right-click chord", "chord"], tab: .display, default: true, \.chordRightClick),
        toggle("screenItems", "On-screen items in search", "Buttons, fields and links in the front window show up in search.",
               ["on-screen items", "on screen items", "screen items", "buttons", "links", "clickable", "page items"], tab: .search, default: true, \.showScreenItems),
        toggle("menuCommands", "Menu commands without a shortcut", "Every menu item shows up in search, not only the ones with keys.",
               ["menu commands", "menu items", "all menus", "menus", "menu"], tab: .search, default: true, \.showMenuCommands),
        toggle("searchFiles", "Files in search", "Files in your home folder show up in search, from the Spotlight index.",
               ["files", "file", "documents", "document", "docs", "file search", "folders", "pdfs"], tab: .search, default: true, \.searchFiles),
        toggle("quickAnswers", "Quick answers", "Calculator, unit and currency conversions, and definitions in search.",
               ["quick answers", "answers", "calculator", "calculations", "math", "maths", "conversions", "convert", "units", "definitions", "dictionary", "currency"],
               tab: .search, default: true, \.quickAnswers),
        toggle("mouse", "Mouse & trackpad", "Turns the mouse and trackpad off to practice keyboard shortcuts. ⌃⌥⌘M turns them back on.",
               ["mouse and trackpad", "mouse & trackpad", "mouse", "trackpad", "touchpad", "cursor", "pointer"], tab: .display, default: true, \.blockPointer, inverted: true),
        ConfigSetting(id: "rescan", title: "Rescan interval", detail: "How old an app's shortcuts can get before Learn rescans its menus when you use it.",
                      aliases: ["rescan interval", "rescan", "rescanning", "scan interval", "refresh interval", "rescans"],
                      kind: .number(1...240, step: 10, unit: .minutes), tab: .advanced, defaultValue: .number(10),
                      get: { .number(Double(prefs.rescanMinutes)) },
                      set: { if case .number(let n) = $0 { prefs.rescanMinutes = Int(n.rounded()) } }),
        ConfigSetting(id: "keyGradient", title: "Shortcut key gradient", detail: "The gradient the shortcut keycaps are drawn in.",
                      aliases: ["key gradient", "keycap gradient", "keycaps", "keycap", "key colors", "key colours", "shortcut keys"],
                      kind: .choice([.init(id: "", title: "Default", aliases: ["default", "pink", "original"])]
                                    + GradientPreset.all.map { .init(id: $0.name, title: $0.name, aliases: [$0.name.lowercased()]) }),
                      tab: .permissions, defaultValue: .choice(""),
                      get: { .choice(prefs.keyGradient ?? "") },
                      set: { if case .choice(let id) = $0 { prefs.keyGradient = id.isEmpty ? nil : id } }),
        toggle("debugLog", "Debug log", "Writes a diagnostics log, for bug reports.",
               ["debug log", "debug", "logging", "diagnostics", "logs"], tab: .advanced, default: false, \.debugLog),
    ]
}

/// Color words → colors, and the nearest name for a color.
enum ColorNames {
    static let table: [(String, NSColor)] = [
        ("red", .systemRed), ("orange", .systemOrange), ("yellow", .systemYellow), ("green", .systemGreen), ("mint", .systemMint),
        ("teal", .systemTeal), ("cyan", .systemCyan), ("blue", .systemBlue), ("indigo", .systemIndigo), ("purple", .systemPurple),
        ("violet", .systemPurple), ("pink", .systemPink), ("magenta", NSColor(srgbRed: 1, green: 0.2, blue: 0.8, alpha: 1)),
        ("brown", .systemBrown), ("gray", .systemGray), ("grey", .systemGray), ("black", .black), ("white", .white),
        ("gold", NSColor(srgbRed: 1, green: 0.78, blue: 0.2, alpha: 1)), ("lavender", NSColor(srgbRed: 0.72, green: 0.6, blue: 1, alpha: 1)),
        ("navy", NSColor(srgbRed: 0.1, green: 0.15, blue: 0.45, alpha: 1)), ("lime", NSColor(srgbRed: 0.6, green: 0.95, blue: 0.2, alpha: 1)),
        ("coral", NSColor(srgbRed: 1, green: 0.5, blue: 0.4, alpha: 1)), ("turquoise", NSColor(srgbRed: 0.2, green: 0.85, blue: 0.8, alpha: 1)),
    ]

    /// A color named in `text`: a word from the table or #rrggbb.
    static func find(in text: String) -> HUDStyle.RGBA? {
        if let r = text.range(of: #"#[0-9a-f]{6}\b"#, options: .regularExpression), let v = UInt32(text[r].dropFirst(), radix: 16) {
            return HUDStyle.RGBA(NSColor(srgbRed: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1))
        }
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        return table.first { words.contains($0.0) }.map { HUDStyle.RGBA($0.1) }
    }

    static func hue(_ c: HUDStyle.RGBA) -> (hue: Double, saturation: Double) {
        let n = c.ns.usingColorSpace(.sRGB) ?? c.ns
        return (n.hueComponent, n.saturationComponent)
    }

    /// 0 same hue … 0.5 opposite.
    static func hueDistance(_ a: Double, _ b: Double) -> Double { let d = abs(a - b); return min(d, 1 - d) }

    /// A pleasant color far from `c`, for "I don't like the green".
    static func contrasting(_ c: HUDStyle.RGBA) -> HUDStyle.RGBA {
        let h = hue(c).hue
        let pick = ["blue", "purple", "pink", "orange", "teal", "indigo"].compactMap { n in table.first { $0.0 == n } }
            .first { hueDistance(hue(HUDStyle.RGBA($0.1)).hue, h) >= 0.25 }
        return HUDStyle.RGBA(pick?.1 ?? .systemBlue)
    }

    static func name(of c: HUDStyle.RGBA) -> String {
        func dist(_ n: NSColor) -> Double { let o = HUDStyle.RGBA(n); return pow(o.r - c.r, 2) + pow(o.g - c.g, 2) + pow(o.b - c.b, 2) }
        guard let best = table.min(by: { dist($0.1) < dist($1.1) }) else { return "custom" }
        return dist(best.1) < 0.02 ? best.0 : "custom (\(String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))))"
    }
}
