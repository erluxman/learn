import Foundation

/// Which result you picked for what you typed, like Spotlight: pick an app after typing "scree" and next time
/// "s", "sc"… "scree" lead with that app, ahead of the closer name match (macOS's Screenshot).
/// Keyed by every prefix of the query, so the shorter queries you type on the way there learn it too.
/// Picks fade with a two-week half-life, so a new habit takes over from an old one. Main-thread; saved to `picks.json`.
final class PickStore {
    static let shared = PickStore()

    struct Entry: Codable { var count: Double; var last: Date }

    private var byQuery: [String: [String: Entry]] = [:]   // query prefix → result key → picks
    private let file = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("picks.json")
    private var saveWork: DispatchWorkItem?

    private static let halfLife: TimeInterval = 14 * 86_400
    private static let maxQueryLength = 40
    private static let maxPerQuery = 8
    private static let maxQueries = 4_000

    private init() {
        byQuery = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: [String: Entry]].self, from: $0) } ?? [:]
    }

    /// Lowercased, spaces trimmed and collapsed: "  Scree " and "scree" are the same search.
    static func norm(_ q: String) -> String {
        q.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func score(_ e: Entry, at now: Date = Date()) -> Double {
        e.count * pow(0.5, now.timeIntervalSince(e.last) / halfLife)
    }

    /// `key` (a result) was picked after typing `query`.
    func record(query: String, key: String) {
        let q = Self.norm(query)
        guard !q.isEmpty, !key.isEmpty else { return }
        let now = Date()
        for n in 1...min(q.count, Self.maxQueryLength) {
            let prefix = String(q.prefix(n))
            guard prefix.last != " " else { continue }   // "vs " is "vs"
            var picks = byQuery[prefix, default: [:]]
            let old = picks[key].map { Self.score($0, at: now) } ?? 0
            picks[key] = Entry(count: old + 1, last: now)
            if picks.count > Self.maxPerQuery {   // forget the faintest
                let keep = picks.sorted { Self.score($0.value, at: now) > Self.score($1.value, at: now) }.prefix(Self.maxPerQuery)
                picks = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            }
            byQuery[prefix] = picks
        }
        if byQuery.count > Self.maxQueries {   // drop the queries untouched the longest
            let stale = byQuery.map { ($0.key, $0.value.values.map(\.last).max() ?? .distantPast) }
                .sorted { $0.1 < $1.1 }.prefix(byQuery.count - Self.maxQueries).map(\.0)
            for k in stale { byQuery[k] = nil }
        }
        scheduleSave()
    }

    /// Result keys picked for exactly this query, most picked (recent picks count more) first.
    func picks(for query: String) -> [String] {
        let q = Self.norm(query)
        guard let picks = byQuery[q] else { return [] }
        let now = Date()
        return picks.map { ($0.key, Self.score($0.value, at: now), $0.value.last) }
            .filter { $0.1 >= 0.25 }   // one pick fades out after about four weeks
            .sorted { ($0.1, $0.2) > ($1.1, $1.2) }
            .map(\.0)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = byQuery, file = file
        let w = DispatchWorkItem { DispatchQueue.global(qos: .utility).async { try? JSONEncoder().encode(snapshot).write(to: file, options: .atomic) } }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }
}
