import Foundation
import NaturalLanguage

/// How worth knowing each of an app's shortcuts is — a deterministic, on-device score, recomputed after every scan.
///
/// Signals, each 0…1:
/// - prior: closeness to a sample of commands that matter in nearly every app (`canon`), via Apple's on-device
///   sentence embedding (NaturalLanguage) plus exact title matches — "Reopen Closed Window" lands near "Reopen Closed Tab";
/// - prevalence: how many of your other apps have the same command — standard commands are important ones;
/// - elsewhere: how much you use that command in other apps;
/// - key: apps give short keys to their most used commands (⌘T beats ⌃⌥⇧T; no key at all scores low);
/// - depth: top-level menu items beat ones buried in submenus;
/// - signature: a short key on a command few other apps have — what makes this app this app (Slack's ⌘K).
/// Basics everyone already knows (copy, paste, undo…) are tips nobody needs, so they sink; housekeeping items (About, Hide Others, Services, window lists, recent files…) are pushed down.
final class RelevanceStore {
    static let shared = RelevanceStore()
    static let changed = Notification.Name("LearnRelevanceChanged")   // object: app id

    private var cache: [String: (scannedAt: Date, scores: [String: Double])] = [:]   // main-thread
    private var pending = Set<String>()
    private let queue = DispatchQueue(label: "learn.relevance", qos: .utility)
    private var embedding: NLEmbedding?   // queue-only
    private var canonVectors: [(vector: [Double], weight: Double)] = []   // queue-only

    private init() {
        NotificationCenter.default.addObserver(forName: ShortcutStore.changed, object: nil, queue: .main) { [weak self] n in
            if let id = n.object as? String { self?.prepare(id) }   // every scan, quiet ones included
        }
    }

    /// Cached static scores by shortcut id; nil until computed (then `changed` is posted).
    func scores(for app: String) -> [String: Double]? {
        guard let entry = ShortcutStore.shared.get(app) else { return nil }
        if let c = cache[app], c.scannedAt == entry.scannedAt { return c.scores }
        prepare(app)
        return nil
    }

    /// Best `limit` of `candidates` for `app`: static relevance plus your own use of them here.
    func suggestions(_ candidates: [Shortcut], app: String, limit: Int) -> [Shortcut] {
        guard let scores = scores(for: app) else { return [] }
        return candidates.map { s -> (Shortcut, Double) in
            let personal = min(UsageStore.shared.score(app: app, path: s.path) / 5, 1)
            return (s, (scores[s.id] ?? 0) + personal * 0.5)
        }
        .filter { $0.1 > 0.2 }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
        .reduce(into: [Shortcut]()) { kept, s in   // one row per command (History › Back and Go › History › Back)
            if !kept.contains(where: { $0.title == s.title && $0.display == s.display }) { kept.append(s) }
        }
        .prefix(limit).map { $0 }
    }

    private func prepare(_ app: String) {
        guard !pending.contains(app), let entry = ShortcutStore.shared.get(app) else { return }
        pending.insert(app)
        // Gather on main (the store is main-thread); score off main.
        let items = entry.shortcuts
        var appsHaving: [String: Int] = [:]
        let others = ShortcutStore.shared.all.filter { $0.bundleID != app }
        for other in others {
            for t in Set(other.shortcuts.filter(\.hasKey).map { Self.norm($0.title) }) { appsHaving[t, default: 0] += 1 }
        }
        let usedElsewhere = UsageStore.shared.useByTitle(excluding: app)
        let scannedAt = entry.scannedAt
        queue.async {
            let scores = self.compute(items, appsHaving: appsHaving, appCount: max(others.count, 1), usedElsewhere: usedElsewhere)
            DispatchQueue.main.async {
                self.pending.remove(app)
                self.cache[app] = (scannedAt, scores)
                NotificationCenter.default.post(name: Self.changed, object: app)
            }
        }
    }

    // MARK: Scoring (queue)

    private func compute(_ items: [Shortcut], appsHaving: [String: Int], appCount: Int, usedElsewhere: [String: Double]) -> [String: Double] {
        loadModel()
        var out: [String: Double] = [:]
        for s in items {
            let title = Self.norm(s.title)
            guard !title.isEmpty else { continue }
            let prior = self.prior(title)
            let prevalence = min(Double(appsHaving[title] ?? 0) / Double(min(appCount, 8)), 1)
            let elsewhere = min((usedElsewhere[title] ?? 0) / 5, 1)
            let key: Double = {
                guard s.hasKey else { return 0.05 }
                let n = [Mods.cmd, .shift, .opt, .ctrl].filter { s.mods.contains($0) }.count
                return n <= 1 ? 1 : n == 2 ? 0.6 : 0.3
            }()
            let depth = s.path.count <= 2 ? 1 : s.path.count == 3 ? 0.55 : 0.25
            let signature = key * (1 - prevalence)
            var score = 0.3 * prior + 0.1 * prevalence + 0.15 * elsewhere + 0.15 * key + 0.1 * depth + 0.2 * signature
            if Self.isNoise(s) { score *= 0.2 }
            if Self.basics.contains(title) { score *= 0.35 }
            out[s.id] = score
        }
        return out
    }

    /// 0…1: how close `title` is to an always-useful command, scaled by that command's weight.
    private func prior(_ title: String) -> Double {
        if let w = Self.canonExact[title] { return w / 3 }
        guard let embedding, let v = embedding.vector(for: title) else { return 0 }
        var best = 0.0
        for c in canonVectors {
            let sim = Self.cosine(v, c.vector)
            best = max(best, max(0, (sim - 0.55) / 0.45) * c.weight / 3)   // below ~0.55 is unrelated
        }
        return best
    }

    private func loadModel() {
        guard embedding == nil, let e = NLEmbedding.sentenceEmbedding(for: .english) else { return }
        embedding = e
        canonVectors = Self.canon.compactMap { t, w in e.vector(for: t.lowercased()).map { ($0, w) } }
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    static func norm(_ t: String) -> String {
        t.lowercased().replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Everyone knows these already; as suggestions they're filler.
    private static let basics: Set<String> = ["undo", "redo", "cut", "copy", "paste", "select all", "close window", "quit",
                                              "minimize", "save", "open", "new window", "print", "delete"]

    private static let noise = ["about ", "hide ", "hide others", "show all", "quit", "quit ", "services", "bring all to front",
                                "minimize all", "emoji & symbols", "start dictation", "autofill", "clear menu",
                                "check for updates", "send feedback", "release notes", "acknowledgements", "license"]

    private static func isNoise(_ s: Shortcut) -> Bool {
        let t = norm(s.title)
        if noise.contains(where: { t == $0.trimmingCharacters(in: .whitespaces) || ($0.hasSuffix(" ") && t.hasPrefix($0)) }) { return true }
        if s.path.first == "Help" { return true }
        // Documents listed by name: recent files and open windows (no key, under those menus).
        if !s.hasKey, s.path.contains(where: { ["Open Recent", "Recent Items", "Recently Closed"].contains($0) }) { return true }
        if !s.hasKey, s.path.first == "Window", s.path.count == 2 { return true }
        return false
    }

    // MARK: Sample of commands that matter in nearly every app (3 = used constantly, 1 = useful to know)

    static let canon: [(String, Double)] = [
        ("New", 3), ("New Window", 3), ("New Tab", 3), ("New Document", 2.5), ("New Folder", 2.5), ("New Private Window", 2),
        ("New Message", 2.5), ("New Note", 2.5), ("Open", 3), ("Open Location", 2), ("Quick Open", 2.5), ("Go to File", 2.5),
        ("Save", 3), ("Save As", 2), ("Duplicate", 2), ("Export", 1.5), ("Print", 1.5), ("Share", 1.5),
        ("Close Window", 3), ("Close Tab", 3), ("Reopen Closed Tab", 2.5), ("Undo", 3), ("Redo", 2.5), ("Cut", 3), ("Copy", 3),
        ("Paste", 3), ("Paste and Match Style", 2), ("Select All", 2.5), ("Delete", 2), ("Find", 3), ("Find Next", 2),
        ("Find Previous", 1.5), ("Find and Replace", 2), ("Search", 2.5), ("Settings", 2), ("Preferences", 2),
        ("Show Sidebar", 2), ("Toggle Sidebar", 2), ("Show Inspector", 1.5), ("Zoom In", 2), ("Zoom Out", 2), ("Actual Size", 1.5),
        ("Enter Full Screen", 2), ("Reload Page", 2.5), ("Refresh", 2), ("Show Downloads", 1.5), ("Show History", 1.5),
        ("Bookmark This Page", 1.5), ("Show Bookmarks", 1.5), ("Back", 2.5), ("Forward", 2), ("Show Next Tab", 2.5),
        ("Show Previous Tab", 2.5), ("Developer Tools", 1.5), ("Command Palette", 3), ("Go to Line", 2), ("Toggle Comment", 2),
        ("Format Document", 1.5), ("Run", 2), ("Build", 2), ("Toggle Terminal", 2), ("Split Editor", 1.5), ("Bold", 2),
        ("Italic", 2), ("Underline", 1.5), ("Insert Link", 1.5), ("Move to Trash", 2.5), ("Get Info", 2), ("Quick Look", 2),
        ("Go to Folder", 2), ("Rename", 2), ("Compress", 1), ("Show Hidden Files", 1.5), ("Reply", 2.5), ("Reply All", 2),
        ("Forward Message", 2), ("Send", 2.5), ("Mark as Read", 1.5), ("Archive", 2), ("Mute", 1.5), ("Play", 2), ("Pause", 2),
        ("Next Track", 1.5), ("Previous Track", 1.5), ("Rotate", 1), ("Crop", 1), ("Adjust Size", 1), ("Show Tab Overview", 1.5),
        ("Minimize", 1.5), ("Switch Workspace", 1.5), ("Jump to Conversation", 2), ("Next Unread", 2), ("Mentions", 1.5),
    ]
    private static let canonExact = Dictionary(canon.map { (norm($0.0), $0.1) }, uniquingKeysWith: max)
}
