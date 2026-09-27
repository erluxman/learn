import AppKit

/// How often each shortcut is used, per app — whether run from Learn or pressed directly in the app —
/// so the panel can lead with the ones you actually use. Main-thread; saved to `usage.json` beside the DB.
final class UsageStore {
    static let shared = UsageStore()

    struct Entry: Codable { var count: Double; var last: Date }

    private var byApp: [String: [String: Entry]] = [:]   // app id → path key → use
    private let file = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("usage.json")
    private var saveWork: DispatchWorkItem?

    private init() {
        byApp = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [String: Entry]].self, from: $0) } ?? [:]
    }

    static func key(_ path: [String]) -> String { path.joined(separator: "\u{1F}") }

    func record(app: String, path: [String]) {
        guard !path.isEmpty else { return }
        var e = byApp[app, default: [:]][Self.key(path)] ?? Entry(count: 0, last: .distantPast)
        e.count += 1
        e.last = Date()
        byApp[app, default: [:]][Self.key(path)] = e
        scheduleSave()
    }

    /// A combo pressed in `app`: count the command it runs — a Learn binding, else the app's own menu shortcut.
    func recordKey(code: Int, mods: Mods, app: String?) {
        guard let app, app != Bundle.main.bundleIdentifier else { return }   // typing in Learn's own panel
        let fkey = Keys.names[code].map { $0.hasPrefix("F") && $0.count > 1 } ?? false
        guard fkey || !mods.isDisjoint(with: [.cmd, .ctrl, .opt]) else { return }
        if let b = Bindings.shared.match(app, keyCode: code, mods: mods) { return record(app: app, path: b.path) }
        if let s = ShortcutStore.shared.get(app)?.shortcuts.first(where: { $0.matches(code: code, mods: mods) }) {
            record(app: app, path: s.path)
        }
    }

    /// Use count, fading with a two-week half-life so today's habits outrank last year's.
    func score(app: String, path: [String]) -> Double {
        guard let e = byApp[app]?[Self.key(path)] else { return 0 }
        return e.count * pow(0.5, -e.last.timeIntervalSinceNow / (14 * 86_400))
    }

    /// The app's most used items among `candidates`, best first.
    func top(_ candidates: [Shortcut], app: String, limit: Int) -> [Shortcut] {
        guard let used = byApp[app], !used.isEmpty else { return [] }
        return candidates.compactMap { s in used[Self.key(s.path)] != nil ? (s, score(app: app, path: s.path)) : nil }
            .filter { $0.1 >= 0.5 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit).map(\.0)
    }

    /// Use by command title in every app but `app` ("new tab" used in Chrome counts for Brave).
    func useByTitle(excluding app: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for (other, items) in byApp where other != app {
            for k in items.keys {
                let path = k.components(separatedBy: "\u{1F}")
                guard let title = path.last else { continue }
                out[RelevanceStore.norm(title), default: 0] += score(app: other, path: path)
            }
        }
        return out
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = byApp, file = file
        let w = DispatchWorkItem { DispatchQueue.global(qos: .utility).async { try? JSONEncoder().encode(snapshot).write(to: file, options: .atomic) } }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }
}

extension Shortcut {
    /// Whether pressing key `code` with `mods` triggers this item.
    func matches(code: Int, mods: Mods) -> Bool {
        guard hasKey else { return false }
        var m = self.mods.subtracting(.fn), c = keyCode
        if c == nil, let (k, shift) = Keys.code(for: key) { c = k; if shift { m.insert(.shift) } }
        return c == code && m == mods
    }
}
