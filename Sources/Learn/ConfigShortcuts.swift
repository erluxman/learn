import AppKit

/// A key combination read out of a sentence: "⌘⇧K", "cmd+shift+k", "command shift K", "control option S", "F5".
struct KeyCombo: Equatable {
    let code: Int
    let mods: Mods
    var display: String { mods.glyphs + (Keys.names[code] ?? "?") }
    func matches(_ b: Binding) -> Bool { b.keyCode == code && b.mods == mods }
}

/// Shortcut requests: "when I press ⌃⌥S open Safari", "⌘⇧R in Chrome should reopen the closed tab",
/// "I accidentally made that shortcut, remove it", "what shortcuts do I have". Learn stores and runs them (Bindings).
enum ShortcutIntent {
    case create(KeyCombo?, target: String)     // either may be missing: AI Config asks for it
    case remove(Removal)
    case list

    enum Removal { case combo(KeyCombo), named(String), latest, all }
}

/// Opens an app or a link from a shortcut (Bindings path ["Open", name-or-URL], scope everywhere).
enum OpenTarget {
    static let group = "Open"
    static func open(_ target: String) {
        if let url = URL(string: target), url.scheme?.hasPrefix("http") == true { NSWorkspace.shared.open(url); return }
        guard let app = ConfigShortcuts.app(named: target) else { NSSound.beep(); return }
        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum ConfigShortcuts {
    struct Outcome { var text: String; var changes: [AppliedChange] = []; var suggestions: [String] = [] }

    // MARK: Values

    /// The details of a shortcut request once the semantic model knows it is one: the keys, what they should do,
    /// which one to remove.
    static func intent(_ command: String, _ text: String) -> ShortcutIntent {
        let combo = Self.combo(in: text)
        switch command {
        case "shortcut.list": return .list
        case "shortcut.remove":
            if let combo { return .remove(.combo(combo.0)) }
            if text.range(of: #"\b(all|every|everything)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return .remove(.all) }
            // A shortcut named in the sentence ("my Safari shortcut"); otherwise "that one" is the newest.
            let named = Bindings.shared.scopes.flatMap { Bindings.shared.all($0) }.first { b in
                let name = ConfigText.normalize(b.path.last ?? "")
                return name.count > 2 && ConfigText.normalize(text).contains(name)
            }
            return .remove(named.map { .named(ConfigText.normalize($0.path.last ?? "")) } ?? .latest)
        default:
            return .create(combo?.0, target: target(text, removing: combo?.1, extra: []))
        }
    }

    /// The combo in `text`, and which of its `tokens` it took up.
    static func combo(in raw: String) -> (KeyCombo, Range<Int>)? {
        let tokens = tokens(raw)
        var mods: Mods = [], start = 0
        var i = 0
        while i < tokens.count {
            let w = tokens[i]
            if let m = modWords[w] { if mods.isEmpty { start = i }; mods.formUnion(m); i += 1; continue }
            let next = i + 1 < tokens.count ? tokens[i + 1] : ""
            if let (code, width) = key(w, next), !mods.isEmpty || (Keys.names[code]?.hasPrefix("F") == true && Keys.names[code]!.count > 1) {
                return (KeyCombo(code: code, mods: mods), (mods.isEmpty ? i : start)..<i + width)
            }
            mods = []
            i += 1
        }
        return nil
    }

    /// Words, with key symbols spelled out and "cmd+shift+k" / "command-shift-k" split up; "github.com" stays whole.
    private static func tokens(_ raw: String) -> [String] {
        var t = raw.lowercased().replacingOccurrences(of: "’", with: "'")
        for (glyph, word) in [("⌘", " cmd "), ("⇧", " shift "), ("⌥", " opt "), ("⌃", " ctrl "), ("+", " ")] { t = t.replacingOccurrences(of: glyph, with: word) }
        t = t.replacingOccurrences(of: #"\b(cmd|command|shift|opt|option|alt|ctrl|control|fn)-"#, with: "$1 ", options: .regularExpression)
        return t.split(whereSeparator: \.isWhitespace).compactMap { tok -> String? in
            let s = String(tok)
            let w = s.count > 1 ? s.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?:;\"()“”")) : s
            return w.isEmpty ? nil : w
        }
    }

    private static let modWords: [String: Mods] = [
        "cmd": .cmd, "command": .cmd, "commands": .cmd, "shift": .shift, "opt": .opt, "option": .opt, "alt": .opt,
        "ctrl": .ctrl, "control": .ctrl, "ctl": .ctrl, "fn": .fn, "hyper": [.cmd, .opt, .ctrl, .shift],
    ]

    /// A key name (and how many words it took: "left arrow" is two).
    private static func key(_ w: String, _ next: String) -> (Int, Int)? {
        let wide = next == "arrow" || next == "key" || next == "bracket" ? 2 : 1
        if w == "arrow", let (code, _) = Keys.code(for: ["left": "←", "right": "→", "up": "↑", "down": "↓"][next] ?? "") { return (code, 2) }
        let named: [String: String] = [
            "space": "Space", "spacebar": "Space", "return": "↩", "enter": "↩", "tab": "⇥", "escape": "⎋", "esc": "⎋",
            "delete": "⌫", "backspace": "⌫", "left": "←", "right": "→", "up": "↑", "down": "↓", "home": "↖", "end": "↘",
            "comma": ",", "period": ".", "dot": ".", "slash": "/", "backslash": "\\", "semicolon": ";", "quote": "'",
            "minus": "-", "dash": "-", "hyphen": "-", "equals": "=", "equal": "=", "plus": "=", "backtick": "`", "grave": "`",
        ]
        if w == "left", next == "bracket" { return (33, 2) }
        if w == "right", next == "bracket" { return (30, 2) }
        if let n = named[w], let (code, _) = Keys.code(for: n) { return (code, wide) }
        if w.count == 1 || w.range(of: #"^f([1-9]|1[0-9]|20)$"#, options: .regularExpression) != nil,
           let (code, shift) = Keys.code(for: w.uppercased()), !shift { return (code, 1) }
        return nil
    }

    /// A sentence without its filler words: what a shortcut should do.
    static func words(_ text: String) -> String { target(text, removing: combo(in: text)?.1, extra: []) }

    /// What's left of the sentence once the combo and the filler around it are gone: "open safari", "reopen closed tab in chrome".
    private static func target(_ text: String, removing combo: Range<Int>?, extra: Set<String>) -> String {
        var words = tokens(text)
        if let combo { words.removeSubrange(combo) }
        words = words.filter { $0.range(of: #"[a-z0-9]"#, options: .regularExpression) != nil }
        let filler: Set<String> = ["when", "whenever", "if", "i", "press", "pressing", "hit", "hitting", "type", "it", "should", "will", "would",
                                   "make", "makes", "bind", "map", "assign", "set", "setup", "add", "create", "a", "an", "the", "shortcut",
                                   "shortcuts", "hotkey", "hotkeys", "keyboard", "key", "keys", "combo", "to", "for", "with", "so", "that", "then",
                                   "please", "can", "you", "want", "i'd", "like", "as", "be", "my", "me", "do", "does", "together", "this",
                                   "up", "let's", "lets", "using", "use", "is", "binding", "combination", "by", "and", "same", "time"]
        return words.filter { !filler.contains($0) && !extra.contains($0) }.joined(separator: " ")
    }

    // MARK: Targets

    enum Target {
        case learn([String], String)             // Learn command path, its name
        case open(String, String)                // app name or URL, what to call it
        case menu(AppEntry, Shortcut)

        var scope: String {
            if case .menu(let app, _) = self { return app.id }
            return Bindings.global
        }
        var path: [String] {
            switch self {
            case .learn(let p, _): p
            case .open(let t, _): [OpenTarget.group, t]
            case .menu(_, let s): s.path
            }
        }
        var name: String {
            switch self {
            case .learn(_, let n), .open(_, let n): n
            case .menu(let app, let s): "\(s.title) in \(app.name)"
            }
        }
        /// "opens Safari", "presses “Reopen Closed Tab” in Google Chrome".
        var does: String {
            switch self {
            case .open(_, let n): "o" + n.dropFirst() .replacingOccurrences(of: "pen ", with: "pens ", options: .anchored)
            case .learn(_, let n): "does “\(n)”"
            case .menu(let app, let s): "presses “\(s.title)” in \(app.name)"
            }
        }
    }

    private static var apps: [AppEntry] = []
    static func app(named name: String) -> AppEntry? {
        if apps.isEmpty { apps = AppCatalog.load().filter { !$0.isSystem } }
        let n = name.lowercased()
        return apps.first { $0.name.lowercased() == n }
            ?? apps.filter { $0.name.lowercased().hasPrefix(n) || $0.name.lowercased().contains(" " + n) }.min { $0.name.count < $1.name.count }
            ?? (n.count > 3 ? apps.filter { n.contains($0.name.lowercased()) }.max { $0.name.count < $1.name.count } : nil)
    }

    private static let learnCommands: [([String], [String])] = [
        (LearnActions.labels, ["label", "labels", "hints", "clickable", "letters"]),
        (LearnActions.rightClick, ["right click", "right-click", "context menu"]),
        (LearnActions.pointer, ["pointer mode", "keyboard pointer", "control the pointer", "mouse with the keyboard", "move the mouse", "move the pointer"]),
        (LearnActions.nextScreen, ["next screen", "other screen", "next display", "other display", "move window", "move the window", "other monitor"]),
        (LearnActions.mouse, ["mouse on", "mouse off", "toggle mouse", "turn off the mouse", "turn on the mouse", "trackpad"]),
        (LearnActions.settings, ["learn settings", "settings", "preferences"]),
    ]

    /// What the words should do: open an app or a link, one of Learn's commands, or a menu item ("… in <app>").
    static func resolve(_ words: String) -> (Target?, [String]) {
        var what = words, scope: AppEntry?
        if let m = words.firstMatch(of: #/^(.*?)\s+\b(?:in|inside|within|on)\s+(.+)$/#), let app = app(named: String(m.2)) {
            what = String(m.1); scope = app
        }
        let verb = #/^(?:opens?|opening|launch(?:es)?|starts?|runs?|bring up|brings up|switch to|switches to|go to|goes to|focus|show|shows|visit)\s+(.+)$/#
        if scope == nil, let m = what.firstMatch(of: verb) {
            let thing = String(m.1)
            if let app = app(named: thing) { return (.open(app.name, "Open \(app.name)"), []) }
            if thing.range(of: #"^[a-z0-9\-]+(\.[a-z0-9\-]+)+(/\S*)?$"#, options: .regularExpression) != nil {
                return (.open("https://" + thing, "Open \(thing)"), [])
            }
        }
        if scope == nil, let app = app(named: what), app.name.lowercased() == what { return (.open(app.name, "Open \(app.name)"), []) }
        if scope == nil, let hit = learnCommands.first(where: { $0.1.contains { ConfigText.has($0, what) } }) {
            return (.learn(hit.0, hit.0.last ?? ""), [])
        }
        return menuItem(what, in: scope)
    }

    /// The menu item best matching `words`, in `app` or in every app Learn has read; suggestions when it's unclear.
    private static func menuItem(_ words: String, in app: AppEntry?) -> (Target?, [String]) {
        let want = Set(words.split(separator: " ").map(String.init)).subtracting(["open", "the", "a", "in", "of"])
        guard !want.isEmpty else { return (nil, []) }
        if apps.isEmpty { apps = AppCatalog.load().filter { !$0.isSystem } }
        var hits: [(AppEntry, Shortcut, Double)] = []
        for a in app.map({ [$0] }) ?? apps {
            for s in ShortcutStore.shared.get(a.id)?.shortcuts ?? [] {
                let title = Set(ConfigText.normalize(s.title).split(separator: " ").map(String.init))
                let score = Double(want.intersection(title).count) / Double(max(want.count, title.count))
                if score >= 0.5 { hits.append((a, s, score)) }
            }
        }
        hits.sort { $0.2 > $1.2 }
        guard let best = hits.first else { return (nil, []) }
        let tied = hits.filter { $0.2 == best.2 }
        if tied.count > 1, Set(tied.map(\.0.id)).count > 1 {
            return (nil, tied.prefix(3).map { "\(words) in \($0.0.name)" })
        }
        return (.menu(best.0, best.1), [])
    }

    // MARK: Doing

    static func create(_ combo: KeyCombo, _ target: Target) -> Outcome {
        guard Recorder.acceptable(code: combo.code, mods: combo.mods) else {
            return Outcome(text: "\(combo.display) would get in the way of typing. Shortcuts need ⌘, ⌃ or ⌥ (or an F-key), like ⌃⌥\(Keys.names[combo.code] ?? "K").")
        }
        if Prefs.shared.panelKey.matches(combo.code, combo.mods) {
            return Outcome(text: "\(combo.display) is the key that opens Learn. Pick another, like ⌃⌥\(Keys.names[combo.code] ?? "K").")
        }
        let reserved: Set<String> = ["⌘C", "⌘V", "⌘X", "⌘Z", "⌘A", "⌘S", "⌘Q", "⌘W", "⌘⇥", "⌘Space", "⌘H", "⌘M", "⌘N", "⌘O", "⌘P", "⌘T", "⌘F"]
        if target.scope == Bindings.global, reserved.contains(combo.display) {
            return Outcome(text: "\(combo.display) is used by nearly every app, so taking it everywhere would break things. Try ⌃⌥\(Keys.names[combo.code] ?? "K") instead.")
        }

        var notes: [String] = []
        if let old = Bindings.shared.all(target.scope).first(where: combo.matches), old.path != target.path {
            notes.append("It replaces your \(combo.display) for \(old.path.last ?? "").")
        } else if let old = Bindings.shared.globals.first(where: combo.matches), old.path != target.path {
            notes.append("\(combo.display) was Learn's key for \(old.path.last ?? ""); in \(target.scope == Bindings.global ? "every app" : "this app") it now does this instead.")
        }
        if target.scope == Bindings.global {
            let users = apps.filter { a in ShortcutStore.shared.get(a.id)?.shortcuts.contains { $0.keyCode == combo.code && $0.mods == combo.mods } == true }
            if !users.isEmpty {
                notes.append("\(users.prefix(3).map(\.name).joined(separator: ", "))\(users.count > 3 ? " and \(users.count - 3) more" : "") also \(users.count == 1 ? "uses" : "use") \(combo.display); Learn's shortcut wins there.")
            }
        }

        let before = Bindings.shared.all(target.scope)
        Bindings.shared.set(target.scope, Binding(path: target.path, keyCode: combo.code, mods: combo.mods))
        let scope = target.scope
        let change = AppliedChange(label: "\(combo.display) → \(target.name)\(scope == Bindings.global ? ", in every app" : "")",
                                   spoken: "\(combo.display) now \(target.does)",
                                   undoLabel: "\(combo.display) shortcut removed", tab: .shortcuts,
                                   undo: { Bindings.shared.restore(scope, before) })
        return Outcome(text: (["Done: \(combo.display) now \(target.does)."] + notes).joined(separator: " "),
                       changes: [change])
    }

    static func remove(_ what: ShortcutIntent.Removal) -> Outcome {
        let mine = Bindings.shared.scopes.flatMap { scope in Bindings.shared.all(scope).map { (scope, $0) } }
        guard !mine.isEmpty else { return Outcome(text: "You haven't made any shortcuts in Learn, so there's nothing to remove.") }

        var pick: [(String, Binding)]
        switch what {
        case .all: pick = mine
        case .combo(let c):
            pick = mine.filter { c.matches($0.1) }
            if pick.isEmpty, LearnActions.defaults.contains(where: c.matches) {
                return Outcome(text: "\(c.display) is one of Learn's built-in keys, not one you made. You can change it in Hotkeys.")
            }
        case .named(let words):
            let want = Set(words.split(separator: " ").map(String.init))
            pick = mine.filter { !want.isDisjoint(with: Set(ConfigText.normalize($0.1.path.joined(separator: " ")).split(separator: " ").map(String.init))) }
            if pick.count > 1, let exact = pick.first(where: { ConfigText.normalize($0.1.path.last ?? "") == words }) { pick = [exact] }
        case .latest:
            let dated = mine.compactMap { m in Bindings.shared.made(m.0, m.1.path).map { (m, $0) } }
            if let newest = dated.max(by: { $0.1 < $1.1 }) { pick = [newest.0] }
            else if mine.count == 1 { pick = mine }
            else { pick = [] }
        }
        guard !pick.isEmpty else {
            return Outcome(text: "Which one? These are the shortcuts you made:",
                           suggestions: mine.prefix(6).map { "Remove \($0.1.shortcut.display) (\(describe($0.1)))" })
        }

        var changes: [AppliedChange] = []
        for scope in Set(pick.map(\.0)) {
            let before = Bindings.shared.all(scope)
            let gone = pick.filter { $0.0 == scope }.map(\.1)
            for b in gone { Bindings.shared.remove(scope, path: b.path) }
            changes.append(AppliedChange(label: gone.map { "\($0.shortcut.display) \(describe($0)) removed" }.joined(separator: ", "),
                                         spoken: gone.map { "\($0.shortcut.display) removed" }.joined(separator: ", "),
                                         undoLabel: gone.map { "\($0.shortcut.display) is back" }.joined(separator: ", "), tab: .shortcuts,
                                         undo: { Bindings.shared.restore(scope, before) }))
        }
        return Outcome(text: "Removed.", changes: changes)
    }

    static func list() -> Outcome {
        let mine = Bindings.shared.scopes.flatMap { scope in Bindings.shared.all(scope).map { (scope, $0) } }
        guard !mine.isEmpty else { return Outcome(text: "You haven't made any shortcuts yet. Try “when I press ⌃⌥S, open Safari”.") }
        return Outcome(text: "Your shortcuts: " + mine.map { "\($0.1.shortcut.display) \(describe($0.1))" }.joined(separator: "; ") + ".",
                       suggestions: ["Remove the last shortcut"])
    }

    private static func describe(_ b: Binding) -> String {
        if b.path.first == OpenTarget.group { return "opens \(b.path.last ?? "")" }
        return b.path.last ?? ""
    }
}
