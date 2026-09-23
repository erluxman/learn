import AppKit

/// Shortcut DB: one JSON file per bundle id in ~/Library/Application Support/Learn/db. Main-thread only.
final class ShortcutStore {
    static let shared = ShortcutStore()
    static let changed = Notification.Name("LearnStoreChanged")

    let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Learn/db", isDirectory: true)
    private var cache: [String: AppShortcuts] = [:]

    private init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), var s = try? JSONDecoder().decode(AppShortcuts.self, from: d) {
                if s.version != AppShortcuts.currentVersion { s.stale = true }
                cache[s.bundleID] = s
            }
        }
    }

    var all: [AppShortcuts] { Array(cache.values) }
    func get(_ id: String) -> AppShortcuts? { cache[id] }

    func put(_ s: AppShortcuts) {
        cache[s.bundleID] = s
        if let d = try? JSONEncoder().encode(s) {
            try? d.write(to: dir.appendingPathComponent(s.bundleID + ".json"), options: .atomic)
        }
        NotificationCenter.default.post(name: Self.changed, object: s.bundleID)
    }

    /// Swaps one item after the user changed its shortcut, without waiting for a rescan.
    func replace(_ id: String, old: Shortcut, with new: Shortcut, customSig: String, stale: Bool) {
        guard var s = cache[id] else { return }
        if let i = s.shortcuts.firstIndex(where: { $0.path == old.path }) { s.shortcuts[i] = new } else { s.shortcuts.append(new) }
        s.customSig = customSig
        s.stale = s.stale || stale
        put(s)
    }

    func markStale(_ id: String) {
        guard var s = cache[id], !s.stale else { return }
        s.stale = true
        put(s)
    }
}

/// Runs scans serially off the main thread. Launches (hidden) and quits apps that aren't running.
final class Scanner {
    static let shared = Scanner()
    private let queue = DispatchQueue(label: "learn.scan", qos: .userInitiated)
    private(set) var busy = Set<String>()   // main-thread
    static var holdingFocus = 0              // main-thread; >0 while a scan may steal focus (hidden launch, menu expansion)

    /// `deep`: also open lazily-filled submenus (menus flash briefly). Only for user-initiated scans.
    func scan(_ app: AppEntry, launchIfNeeded: Bool, deep: Bool = false, completion: ((AppShortcuts?) -> Void)? = nil) {
        guard !busy.contains(app.id) else { return }
        busy.insert(app.id)
        queue.async {
            let result = Self.scanSync(app, launchIfNeeded: launchIfNeeded, deep: deep)
            DispatchQueue.main.async {
                self.busy.remove(app.id)
                if let result { ShortcutStore.shared.put(result) }
                completion?(result)
            }
        }
    }

    /// Scans a list one by one; `progress(done, total)` on main.
    func scanAll(_ apps: [AppEntry], launchIfNeeded: Bool, progress: @escaping (Int, Int) -> Void) {
        queue.async {
            for (i, app) in apps.enumerated() {
                if let r = Self.scanSync(app, launchIfNeeded: launchIfNeeded, deep: false) {
                    DispatchQueue.main.async { ShortcutStore.shared.put(r) }
                }
                DispatchQueue.main.async { progress(i + 1, apps.count) }
            }
        }
    }

    private static func scanSync(_ app: AppEntry, launchIfNeeded: Bool, deep: Bool) -> AppShortcuts? {
        if app.isSystem { return SystemShortcuts.load() }
        if let running = app.runningApp { return read(app, pid: running.processIdentifier, deep: deep) }
        guard launchIfNeeded else { return nil }
        DispatchQueue.main.sync { holdingFocus += 1 }
        defer { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { holdingFocus -= 1 } }
        guard let launched = launchHidden(app.url) else { return nil }
        defer { launched.terminate() }
        _ = waitForMenus(pid: launched.processIdentifier)
        return read(app, pid: launched.processIdentifier, deep: true)
    }

    private static func read(_ app: AppEntry, pid: pid_t, deep: Bool) -> AppShortcuts? {
        if deep {
            DispatchQueue.main.sync { holdingFocus += 1 }
            MenuScanner.expandLazySubmenus(pid: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { holdingFocus -= 1 }
        }
        var (items, empty) = MenuScanner.scanWithGaps(pid: pid)
        guard !items.isEmpty else { return nil }
        // Submenus the app emptied again (lazy apps refill only on open): keep what we saw there before.
        if !empty.isEmpty, let old = DispatchQueue.main.sync(execute: { ShortcutStore.shared.get(app.id) }) {
            let have = Set(items.map(\.id))
            items += old.shortcuts.filter { s in
                !have.contains(s.id) && empty.contains { s.path.count > $0.count && Array(s.path.prefix($0.count)) == $0 }
            }
        }
        return AppShortcuts(bundleID: app.id, scannedAt: Date(), shortcuts: items, customSig: CustomKeys.signature(for: app.id))
    }

    static func launchHidden(_ url: URL) -> NSRunningApplication? {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.hides = true
        cfg.addsToRecentItems = false
        let sem = DispatchSemaphore(value: 0)
        var app: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { a, _ in app = a; sem.signal() }
        _ = sem.wait(timeout: .now() + 15)
        return app
    }

    /// Menus appear some time after launch; poll until the item count stops changing.
    static func waitForMenus(pid: pid_t, timeout: TimeInterval = 12) -> [Shortcut] {
        let end = Date().addingTimeInterval(timeout)
        var last: [Shortcut] = []
        while Date() < end {
            Thread.sleep(forTimeInterval: 1)
            let now = MenuScanner.scan(pid: pid)
            if !now.isEmpty && now.count == last.count { return now }
            last = now
        }
        return last
    }
}
