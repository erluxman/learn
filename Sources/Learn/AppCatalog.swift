import AppKit

enum AppCatalog {
    private static let roots = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications", "/System/Library/CoreServices/Finder.app",
    ]
    private static var icons: [String: NSImage] = [:]

    /// All installed + running regular apps, deduped by bundle id.
    static func load() -> [AppEntry] {
        let fm = FileManager.default
        var urls: [URL] = []
        for root in roots {
            let u = URL(fileURLWithPath: root)
            if u.pathExtension == "app" { urls.append(u); continue }
            for item in (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" { urls.append(item) }
                else if item.hasDirectoryPath, root != "/System/Applications" {   // one level of folders (e.g. Adobe X/)
                    let inner = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                    urls += inner.filter { $0.pathExtension == "app" }
                }
            }
        }
        urls += NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)

        var seen: Set<String> = [SystemShortcuts.bundleID, Bundle.main.bundleIdentifier ?? ""]
        var out = [SystemShortcuts.entry]
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { continue }
            out.append(AppEntry(id: id, name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url: url))
        }
        return out
    }

    static func icon(_ app: AppEntry) -> NSImage {
        if let i = icons[app.id] { return i }
        let i = NSWorkspace.shared.icon(forFile: app.url.path)
        icons[app.id] = i
        return i
    }
}

enum Fuzzy {
    /// Higher is better; nil = no match. Every whitespace-separated token must match.
    static func score(_ query: String, _ text: String) -> Int? {
        var total = 0
        for token in query.lowercased().split(separator: " ") {
            guard let s = tokenScore(String(token), text) else { return nil }
            total += s
        }
        return total
    }

    private static func tokenScore(_ q: String, _ text: String) -> Int? {
        if text.hasPrefix(q) { return 1000 }
        if let r = text.range(of: " " + q) { return 800 - text.distance(from: text.startIndex, to: r.lowerBound) }
        if q.count > 1, String(text.split(separator: " ").compactMap(\.first)).hasPrefix(q) { return 700 }   // initials
        if let r = text.range(of: q) { return 500 - text.distance(from: text.startIndex, to: r.lowerBound) }
        // subsequence
        var idx = text.startIndex, gaps = 0
        for c in q {
            guard let f = text[idx...].firstIndex(of: c) else { return nil }
            gaps += text.distance(from: idx, to: f)
            idx = text.index(after: f)
        }
        return max(1, 200 - gaps)
    }
}
