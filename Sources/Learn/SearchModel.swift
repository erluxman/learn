import AppKit
import Combine

final class SearchModel: ObservableObject {
    enum Mode: Equatable { case apps, shortcuts(AppEntry) }

    @Published var mode: Mode = .apps
    @Published var query = "" { didSet { if query != oldValue { notice = nil; recompute() } } }
    @Published var selection = 0 { didSet { updateHighlight() } }
    @Published private(set) var highlight: CGRect?   // on-screen element under the list selection
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var shortcuts: [Shortcut] = []
    @Published private(set) var scanning = false
    @Published private(set) var info = ""
    @Published private(set) var notice: String?   // one-off message; wins over `info` until the next navigation
    @Published var trusted = AXIsProcessTrusted()
    @Published var focusTick = 0

    // Shortcut recorder (⌘↩ on a row)
    @Published private(set) var recording: Shortcut?
    @Published private(set) var recorded: (code: Int, mods: Mods)?

    var onClose: (_ restoreFocus: Bool) -> Void = { _ in }
    private var allApps: [AppEntry] = AppCatalog.load()
    private var preferred: String?   // app that was frontmost before the panel opened
    private var bag: AnyCancellable?
    private var screen: (appID: String, elements: [String: ScreenElement]) = ("", [:])   // by row id
    private var screenRows: [Shortcut] = []

    init() {
        bag = NotificationCenter.default.publisher(for: ShortcutStore.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in
                if case .shortcuts(let a) = self?.mode, a.id == n.object as? String { self?.recompute(keepSelection: true) }
            }
    }

    var currentApp: AppEntry? { if case .shortcuts(let a) = mode { a } else { nil } }
    var count: Int { currentApp == nil ? apps.count : shortcuts.count }
    var selectedID: String? {
        guard selection < count else { return nil }
        return currentApp == nil ? apps[selection].id : shortcuts[selection].id
    }

    /// Opens straight into the focused app's shortcuts; falls back to the app list.
    func willShow(frontmost: NSRunningApplication?) {
        preferred = frontmost?.bundleIdentifier
        notice = nil
        trusted = AXIsProcessTrusted()
        query = ""
        screen = ("", [:]); screenRows = []
        if let f = frontmost, let id = f.bundleIdentifier, let url = f.bundleURL {
            scanScreen(appID: id, pid: f.processIdentifier)
            open(allApps.first { $0.id == id } ?? AppEntry(id: id, name: f.localizedName ?? id, url: url))
        } else {
            mode = .apps
            recompute()
        }
        focusTick += 1
        DispatchQueue.global(qos: .utility).async {
            let fresh = AppCatalog.load()
            DispatchQueue.main.async { self.allApps = fresh; if self.currentApp == nil { self.recompute(keepSelection: true) } }
        }
    }

    func recompute(keepSelection: Bool = false) {
        if let app = currentApp {
            let entry = ShortcutStore.shared.get(app.id)
            let learn = LearnActions.all.map { Shortcut(path: $0, key: "", keyCode: nil, mods: []) }
            let onScreen = screen.appID == app.id ? screenRows : []
            let list = Self.withBindings(learn + onScreen + (entry?.shortcuts ?? []), app: app.id)
            shortcuts = query.isEmpty ? list
                : list.compactMap { s in Fuzzy.rank(query, title: s.title, context: s.searchText, keys: s.display).map { (s, $0) } }
                    .sorted { ($0.1, -$0.0.title.count, -$0.0.path.count) > ($1.1, -$1.0.title.count, -$1.0.path.count) }
                    .map(\.0)
            scanning = Scanner.shared.busy.contains(app.id)
            if scanning { info = "Scanning \(app.name)…" }
            else if let entry {
                let ago = RelativeDateTimeFormatter().localizedString(for: entry.scannedAt, relativeTo: Date())
                let keyed = list.filter(\.hasKey).count
                info = "\(keyed) shortcuts · \(list.count - keyed) commands · \(onScreen.count) on screen · scanned \(ago)\(entry.stale ? " · outdated" : "")"
            } else { info = "No shortcuts found — press ⌘R to scan" }
        } else {
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            func rank(_ a: AppEntry) -> Int { a.id == preferred ? 2 : running.contains(a.id) ? 1 : 0 }
            if query.isEmpty {
                apps = allApps.sorted { (rank($0), $1.name.lowercased()) > (rank($1), $0.name.lowercased()) }
            } else {
                apps = allApps.compactMap { a in Fuzzy.rank(query, title: a.name).map { (a, $0 * 10 + rank(a)) } }
                    .sorted { ($0.1, -$0.0.name.count) > ($1.1, -$1.0.name.count) }.map(\.0)
            }
            info = "\(apps.count) apps · ↩ show shortcuts"
        }
        if !keepSelection || selection >= count { selection = 0 }
        updateHighlight()
    }

    // MARK: On-screen elements

    private func scanScreen(appID: String, pid: pid_t) {
        DispatchQueue.global(qos: .userInitiated).async {
            let els = ElementScanner.scan(pid: pid)
            DispatchQueue.main.async {
                var byID: [String: ScreenElement] = [:], rows: [Shortcut] = []
                for e in els where !e.text.isEmpty {   // unlabeled icons: reachable via label mode only
                    let s = e.shortcut
                    if byID[s.id] == nil { byID[s.id] = e; rows.append(s) }
                }
                self.screen = (appID, byID)
                self.screenRows = rows
                if self.currentApp?.id == appID { self.recompute(keepSelection: true) }
            }
        }
    }

    private func updateHighlight() {
        let h = currentApp != nil && selection < shortcuts.count ? screen.elements[shortcuts[selection].id]?.frame : nil
        if h != highlight { highlight = h }
    }

    func clearScreen() { screen = ("", [:]); screenRows = []; highlight = nil }

    func move(_ d: Int) {
        guard count > 0 else { return }
        selection = (selection + d + count) % count
    }

    func activate(_ index: Int? = nil) {
        if let index { selection = index }
        guard selection < count else { return }
        if let app = currentApp {
            let s = shortcuts[selection]
            switch s.path.first {
            case LearnActions.group, ElementScanner.marker:
                let el = screen.elements[s.id]
                let pid = app.runningApp?.processIdentifier
                onClose(true)   // focus back to the app, then act in it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    if s.path.first == LearnActions.group { LearnActions.run(s.path) }
                    else if let el { ElementScanner.perform(el) }
                    else if let pid { DispatchQueue.global().async { _ = ElementScanner.pressMatching(path: s.path, pid: pid) } }
                }
            default:
                onClose(false)   // Executor activates the target app itself
                Executor.run(s, in: app)
            }
        } else {
            open(apps[selection])
        }
    }

    func open(_ app: AppEntry) {
        mode = .shortcuts(app)
        query = ""
        let cached = ShortcutStore.shared.get(app.id)
        recompute()
        if cached == nil || cached!.stale || app.isSystem { refresh() }
    }

    /// Re-reads the app's menus now (launches it hidden if not running).
    func refresh() {
        guard let app = currentApp else { return }
        Scanner.shared.scan(app, launchIfNeeded: true, deep: true) { [weak self] r in
            guard let self, self.currentApp == app else { return }
            self.recompute(keepSelection: true)
            if r == nil { self.info = self.trusted ? "Couldn't read menus of \(app.name)" : "Grant Accessibility access first" }
        }
        recompute(keepSelection: true)
    }

    // MARK: Custom shortcuts

    func startRecording() {
        guard let app = currentApp, selection < shortcuts.count else { return }
        guard !app.isSystem else { notice = "System shortcuts are changed in System Settings ▸ Keyboard"; return }
        recording = shortcuts[selection]
        recorded = nil
    }

    func cancelRecording() { recording = nil; recorded = nil }

    /// Needs ⌘/⌃/⌥ (or an F-key) so plain typing can't become a shortcut.
    func record(code: Int, mods: Mods) {
        let fkey = Keys.names[code]?.hasPrefix("F") == true && Keys.names[code]!.count > 1
        guard Keys.names[code] != nil, fkey || !mods.intersection([.cmd, .ctrl, .opt]).isEmpty else { NSSound.beep(); return }
        recorded = (code, mods)
    }

    var recordedShortcut: Shortcut? {
        guard let r = recording, let k = recorded, let name = Keys.names[k.code] else { return nil }
        return Shortcut(path: r.path, key: name, keyCode: k.code, mods: k.mods)
    }

    /// Other items in this app already using the recorded combo.
    var conflicts: [Shortcut] {
        guard let new = recordedShortcut, let app = currentApp else { return [] }
        return Self.withBindings(ShortcutStore.shared.get(app.id)?.shortcuts ?? [], app: app.id)
            .filter { $0.hasKey && $0.display == new.display && $0.path != new.path }
    }

    /// Saves the recorded combo as a Learn binding (works immediately); reset removes it.
    func saveRecording(reset: Bool = false) {
        guard let app = currentApp, let item = recording else { return }
        let scope = item.path.first == LearnActions.group ? Bindings.global : app.id
        if reset {
            Bindings.shared.remove(scope, path: item.path)
            notice = "Removed custom shortcut for \(item.title)"
        } else {
            guard let k = recorded else { NSSound.beep(); return }
            let b = Binding(path: item.path, keyCode: k.code, mods: k.mods)
            Bindings.shared.set(scope, b)
            notice = "\(b.shortcut.display) now runs \(item.title)\(scope == Bindings.global ? " everywhere" : " in \(app.name)")"
        }
        cancelRecording()
        recompute(keepSelection: true)
    }

    /// Menu items with Learn bindings applied on top (bindings for vanished items are kept visible).
    static func withBindings(_ list: [Shortcut], app: String) -> [Shortcut] {
        let binds = Bindings.shared.all(app)
        let userGlobal = Bindings.shared.all(Bindings.global)
        func custom(_ b: Binding, _ orig: Shortcut?) -> Shortcut {
            var s = b.shortcut
            s.original = orig.map { $0.hasKey ? $0.display : "" } ?? ""
            return s
        }
        var out = list.map { s -> Shortcut in
            if s.path.first == LearnActions.group {   // Learn command: user binding, else built-in default
                if let b = userGlobal.first(where: { $0.path == s.path }) { return custom(b, s) }
                return LearnActions.defaults.first { $0.path == s.path }?.shortcut ?? s
            }
            return Bindings.shared.get(app, path: s.path).map { custom($0, s) } ?? s
        }
        let paths = Set(list.map(\.path))
        out += binds.filter { !paths.contains($0.path) }.map { custom($0, nil) }
        return out
    }

    func back() { notice = nil; mode = .apps; query = ""; recompute(); focusTick += 1 }

    /// Esc is the only way back: shortcuts → apps; in apps it clears the query, then closes.
    func escape() {
        if currentApp != nil { back() }
        else if !query.isEmpty { query = "" }
        else { onClose(true) }
    }
}
