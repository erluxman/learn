import Foundation

/// Ranks a result by how well the query matches its *name*, favoring names the query covers most.
/// Tiers (high → low): exact name · name prefix · word-start inside name · initials · substring ·
/// all words match name · match via menu path / keys · fuzzy. Within a tier, higher coverage
/// (query length ÷ name length) wins, so the shortest name containing what you typed comes first.
enum Fuzzy {
    /// `keys`: the item's shortcut display (e.g. "⇧⌘N") so "cmd shift n" / "⇧⌘n" hit it exactly.
    static func rank(_ query: String, title: String, context: String = "", keys: String = "") -> Int? {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }
        if !keys.isEmpty, let combo = keyCombo(query), combo == keys.lowercased() { return 15_000 }
        let t = normalize(title)
        let cov = min(1, Double(q.count) / Double(max(t.count, 1)))
        func tier(_ base: Int, _ c: Double = cov) -> Int { base + Int(c * 999) }

        if t == q { return 20_000 }
        if t.hasPrefix(q) { return tier(9_000) }
        if t.contains(" " + q) { return tier(8_000) }
        let tw = t.split(separator: " ").map(String.init)
        let compact = q.replacingOccurrences(of: " ", with: "")
        let initials = String(tw.compactMap(\.first))
        if q.count > 1, !q.contains(" "), initials.hasPrefix(q) {
            return tier(7_500, Double(q.count) / Double(max(tw.count, 1)))
        }
        if t.contains(q) { return tier(7_000) }
        let qw = q.split(separator: " ").map(String.init)
        if qw.allSatisfy({ tok in tw.contains { $0.hasPrefix(tok) } }) { return tier(6_000) }

        let ctx = normalize(context)
        let all = ctx.split(separator: " ").map(String.init) + tw
        if qw.allSatisfy({ tok in all.contains { $0.hasPrefix(tok) } }) {
            return tier(4_000, Double(q.count) / Double(max(ctx.count + t.count, 1)))
        }
        if ctx.contains(q) { return 3_500 }
        if let s = subsequence(compact, t) { return 1_000 + s }
        if let s = subsequence(compact, ctx + " " + t) { return s / 2 }
        return nil
    }

    /// "cmd shift n" / "shift+cmd+n" / "⇧⌘n" → "⇧⌘n" (display order ⌃⌥⇧⌘ + key); nil if not a combo.
    static func keyCombo(_ query: String) -> String? {
        let words: [String: Mods] = ["cmd": .cmd, "command": .cmd, "⌘": .cmd, "shift": .shift, "⇧": .shift,
                                     "opt": .opt, "option": .opt, "alt": .opt, "⌥": .opt, "ctrl": .ctrl, "control": .ctrl, "⌃": .ctrl]
        var spaced = query.lowercased().replacingOccurrences(of: "+", with: " ")
        for g in ["⌘", "⇧", "⌥", "⌃"] { spaced = spaced.replacingOccurrences(of: g, with: " \(g) ") }
        var mods: Mods = [], key: String?
        for tok in spaced.split(separator: " ").map(String.init) {
            if let m = words[tok] { mods.insert(m) } else if key == nil { key = tok } else { return nil }
        }
        guard let key, !mods.isEmpty else { return nil }
        return mods.glyphs + key
    }

    /// Lowercase, drop ellipses and punctuation, collapse spaces ("New Project…" → "new project").
    static func normalize(_ s: String) -> String {
        var out = s.lowercased().replacingOccurrences(of: "…", with: " ").replacingOccurrences(of: "...", with: " ")
        let punct = CharacterSet(charactersIn: ".,:;'\"()[]{}<>/\\|-_–—+*&!?·▸")
        out = String(out.unicodeScalars.map { punct.contains($0) ? " " : Character($0) })
        return out.split(separator: " ").joined(separator: " ")
    }

    /// Characters of q in order inside text; 1…999, fewer gaps = higher.
    private static func subsequence(_ q: String, _ text: String) -> Int? {
        var idx = text.startIndex, gaps = 0
        for c in q {
            guard let f = text[idx...].firstIndex(of: c) else { return nil }
            gaps += text.distance(from: idx, to: f)
            idx = text.index(after: f)
        }
        return gaps < 90 ? 999 - gaps * 10 : nil   // too scattered = noise
    }
}
