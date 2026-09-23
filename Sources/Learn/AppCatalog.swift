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
