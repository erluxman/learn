import AppKit
import Combine

/// A search row: an app's shortcut / command / on-screen item, or — in any list — instant answer, app, file,
/// or another scanned app's shortcut (`global`, runs without opening that app first).
enum Hit: Identifiable, Hashable {
    case shortcut(Shortcut), answer(Answer), app(AppEntry), file(FileHit), global(Shortcut, AppEntry)
    var id: String {
        switch self {
        case .shortcut(let s): s.id
        case .global(let s, let a): "global:" + a.id + "|" + s.id
        case .answer(let a): "answer:" + a.title
        case .app(let a): "app:" + a.id
        case .file(let f): "file:" + f.url.path
        }
    }
}

final class SearchModel: ObservableObject {
    enum Mode: Equatable { case apps, shortcuts(AppEntry) }

    /// ⌥Space while Learn Settings is in front searches Learn's own settings.
    static let settingsEntry = AppEntry(id: Bundle.main.bundleIdentifier ?? "com.erluxman.learn", name: SettingsWindow.title,
                                        url: Bundle.main.bundleURL)
    static let settingsGroup = SettingsWindow.title
    private static let settingsIndex: [(String, SettingsWindow.Tab)] = [
        ("Permissions", .permissions), ("Accessibility permission", .permissions), ("Send keystrokes & clicks permission", .permissions),
        ("Input Monitoring permission", .permissions), ("Launch at login", .permissions),
        ("Appearance", .appearance), ("Blur: liquid glass, gaussian radius, vibrant, frosted, progressive, materials", .appearance), ("Grain / noise texture: fine, blue noise, film, fractal, paper, halftone", .appearance), ("Theme: colors, gradient, presets, grain", .appearance), ("Tint color of the glass", .appearance),
        ("Corner roundness", .appearance), ("Window shadow", .appearance), ("Pointer light", .appearance),
        ("Jelly wobble when dragging windows", .appearance), ("Hover motion", .appearance), ("App font, typeface", .appearance), ("Icon style", .appearance),
        ("Sounds", .sounds), ("Click sound", .sounds), ("Shortcut sound", .sounds), ("Sound volume", .sounds),
        ("Hotkeys", .hotkeys), ("Open Learn hotkey", .hotkeys), ("Replace Spotlight (⌘Space opens Learn)", .hotkeys), ("Label clickable items hotkey", .hotkeys),
        ("Right-click the focused item hotkey", .hotkeys), ("Open Learn Settings hotkey", .hotkeys),
        ("Pointer mode hotkey (control the pointer with the keyboard)", .hotkeys), ("Move window to next screen hotkey", .hotkeys),
        ("Learn Panel", .panel), ("Record-shortcut key (inside Learn)", .panel), ("Right-click key (inside Learn)", .panel),
        ("On Screen", .display), ("Shortcut display: customize look, position, font, color, animation", .display),
        ("Right-click with both control keys", .display), ("Pointer mode", .display),
        ("Search", .search), ("Show on-screen items", .search), ("Search files (Spotlight index)", .search),
        ("Quick answers: calculator, unit conversions, definitions", .search), ("Show menu commands without a shortcut", .search),
        ("Advanced", .advanced), ("Rescan interval", .advanced), ("Rescan running apps", .advanced), ("Scan all installed apps", .advanced),
        ("Show database in Finder", .advanced), ("Debug log", .advanced),
        ("My Shortcuts", .shortcuts), ("Shortcuts you recorded in Learn", .shortcuts), ("Remove a recorded shortcut", .shortcuts),
    ]
    private static let settingsRows = settingsIndex.map {
        Shortcut(path: [settingsGroup, $0.1.title, $0.0], key: "", keyCode: nil, mods: [])
    }
    private static let settingsTabs = Dictionary(settingsIndex.map { ([settingsGroup, $0.1.title, $0.0], $0.1) }, uniquingKeysWith: { a, _ in a })

    @Published var mode: Mode = .apps
    /// ⇥ with nothing typed inside an app: the most relevant shortcuts instead of the most used.
    @Published private(set) var suggesting = false

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            suggesting = false
            notice = nil
            files = []
            fileSearch.search(Prefs.shared.searchFiles && currentApp != Self.settingsEntry ? query : "")
            searchGlobal()
            recompute()
        }
    }
    @Published var selection = 0 { didSet { updateHighlight() } }
    @Published private(set) var highlight: CGRect?   // on-screen element under the list selection
    @Published private(set) var results: [Hit] = []
    @Published private(set) var scanning = false
    @Published private(set) var info = ""
    @Published private(set) var notice: String?   // one-off message; wins over `info` until the next navigation
    @Published var trusted = AXIsProcessTrusted()
    @Published var focusTick = 0
    @Published var presentTick = 0   // panel shown: replays the entrance animation
    /// Pointer position of the last hover-select; rows that slide under a still pointer (scroll, new results) don't grab the selection.
    var lastMouse = NSPoint.zero
    /// The last selection change came from the pointer: the row is already on screen, so the list shouldn't scroll.
    var selectedByHover = false

    /// Hovering a row selects it, but only when the pointer really moved.
    func hover(_ i: Int) {
        let m = NSEvent.mouseLocation
        guard m != lastMouse, i != selection, i < results.count else { return }
        lastMouse = m
        selectedByHover = true
        selection = i
    }

    // Shortcut recorder (⌘↩ on a row)
    @Published private(set) var recording: Shortcut?
    @Published private(set) var recorded: (code: Int, mods: Mods)?

    var onClose: (_ restoreFocus: Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}
    private var allApps: [AppEntry] = AppCatalog.load()
    private var preferred: String?   // app that was frontmost before the panel opened
    private var bag: AnyCancellable?
    private var screen: (appID: String, elements: [String: ScreenElement]) = ("", [:])   // by row id
    private var screenRows: [Shortcut] = []
    private var files: [FileHit] = []
    private let fileSearch = FileSearch()

    init() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.rebuildGlobalIndex() }   // warm the cache before first open
        NotificationCenter.default.addObserver(forName: Rates.changed, object: nil, queue: .main) { [weak self] _ in
            if self?.query.isEmpty == false { self?.recompute(keepSelection: true) }   // first rates arrived mid-query
        }
        fileSearch.onResults = { [weak self] hits in
            guard let self else { return }
            self.files = hits
            self.recompute(keepSelection: true)
        }
        bag = NotificationCenter.default.publisher(for: ShortcutStore.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] n in
                self?.globalDirty = true   // rescan or binding change: rebuild the from-anywhere index on next open
                if case .shortcuts(let a) = self?.mode, a.id == n.object as? String { self?.recompute(keepSelection: true) }
            }
        NotificationCenter.default.addObserver(forName: RelevanceStore.changed, object: nil, queue: .main) { [weak self] n in
            guard let self, self.suggesting, case .shortcuts(let a) = self.mode, a.id == n.object as? String else { return }
            self.recompute(keepSelection: true)
        }
    }

    var currentApp: AppEntry? { if case .shortcuts(let a) = mode { a } else { nil } }
    var count: Int { results.count }
    var selectedID: String? { selection < count ? results[selection].id : nil }
    var selectedShortcut: Shortcut? {
        guard selection < count, case .shortcut(let s) = results[selection] else { return nil }
        return s
    }

    /// Opens straight into the focused app's shortcuts (or Learn's settings); falls back to the app list.
    func willShow(frontmost: NSRunningApplication?, settings: Bool = false) {
        preferred = frontmost?.bundleIdentifier
        Synonyms.refreshScreens()   // displays come and go (Sidecar, docks)
        notice = nil
        trusted = AXIsProcessTrusted()
        query = ""
        rebuildGlobalIndex()
        screen = ("", [:]); screenRows = []
        if settings {
            scanScreen(appID: Self.settingsEntry.id, pid: getpid(), windowTitle: SettingsWindow.title)
            open(Self.settingsEntry)
        } else if let f = frontmost, let id = f.bundleIdentifier, let url = f.bundleURL {
            if Prefs.shared.showScreenItems { scanScreen(appID: id, pid: f.processIdentifier) }
            open(allApps.first { $0.id == id } ?? AppEntry(id: id, name: f.localizedName ?? id, url: url))
        } else {
            mode = .apps
            recompute()
        }
        focusTick += 1
        presentTick += 1
        lastMouse = NSEvent.mouseLocation
        DispatchQueue.global(qos: .utility).async {
            let fresh = AppCatalog.load()
            DispatchQueue.main.async {
                if fresh.map(\.id) != self.allApps.map(\.id) { self.globalDirty = true }   // apps installed / removed
                self.allApps = fresh
                if self.currentApp == nil { self.recompute(keepSelection: true) }
            }
        }
    }

    func recompute(keepSelection: Bool = false) {
        if let app = currentApp {
            let entry = ShortcutStore.shared.get(app.id)
            // Learn's own commands only appear when searched for — the list itself is just this app.
            let learn = query.isEmpty ? [] : (LearnActions.all + WindowMover.paths).map { Shortcut(path: $0, key: "", keyCode: nil, mods: []) }
            let onScreen = screen.appID == app.id ? screenRows : []
            let menus = (entry?.shortcuts ?? []).filter { Prefs.shared.showMenuCommands || $0.hasKey }
            let list = app == Self.settingsEntry ? Self.settingsRows + onScreen
                                                  : Self.withBindings(learn + onScreen + menus, app: app.id)
            let shortcuts = query.isEmpty ? list
                : list.compactMap { s in Fuzzy.rank(query, title: s.title, context: s.searchText, keys: s.display).map { (s, $0) } }
                    .sorted { ($0.1, -$0.0.title.count, -$0.0.path.count) > ($1.1, -$1.0.title.count, -$1.0.path.count) }
                    .map(\.0)
            // Anywhere, not just the top level: answer on top; definition, apps and files after this app's items.
            let (top, rest) = app == Self.settingsEntry ? ([], []) : extras(apps: rankedApps().filter { Fuzzy.rank(query, title: $0.name) ?? 0 >= 6_000 }.prefix(5), files: 12)
            let elsewhere = app == Self.settingsEntry ? [] : globalHits(excluding: app.id, limit: 8)
            // Nothing typed: only the shortcuts you use most here (⇥: the most relevant ones); typing searches all of them.
            let browsing = query.isEmpty && app != Self.settingsEntry
            let picked = !browsing ? [] : suggesting ? RelevanceStore.shared.suggestions(menus, app: app.id, limit: 12)
                                                     : UsageStore.shared.top(shortcuts, app: app.id, limit: 8)
            frequentIDs = suggesting ? [] : Set(picked.map { Hit.shortcut($0).id })
            results = top + (browsing ? picked : shortcuts).map(Hit.shortcut) + elsewhere + rest
            scanning = Scanner.shared.busy.contains(app.id) && !quietScans.contains(app.id)
            if scanning { info = "Scanning \(app.name)…" }
            else if app == Self.settingsEntry { info = "Search Learn's settings · ↩ go there" }
            else if let entry {
                let ago = RelativeDateTimeFormatter().localizedString(for: entry.scannedAt, relativeTo: Date())
                let keyed = list.filter(\.hasKey).count
                info = "\(keyed) shortcuts · \(list.count - keyed) commands · \(onScreen.count) on screen · scanned \(ago)\(entry.stale ? " · outdated" : "")"
            } else { info = "No shortcuts found — press ⌘R to scan" }
        } else {
            let apps = rankedApps()
            let (top, rest) = extras(apps: [], files: 40)
            let global = globalHits(excluding: nil, limit: 25)
            // Apps named like the query first, then every app's matching shortcuts, then looser app matches.
            let strong = query.isEmpty ? apps : apps.filter { Fuzzy.rank(query, title: $0.name) ?? 0 >= 6_000 }
            let weak = query.isEmpty ? [] : apps.filter { Fuzzy.rank(query, title: $0.name) ?? 0 < 6_000 }
            let frequent = query.isEmpty ? frequentEverywhere() : []
            frequentIDs = Set(frequent.map(\.id))
            results = top + frequent + strong.map(Hit.app) + global + weak.map(Hit.app) + rest
            info = "\(apps.count) apps\(global.isEmpty ? "" : " · \(global.count) shortcuts")\(files.isEmpty ? "" : " · \(files.count) files")"
        }
        if !keepSelection || selection >= count { selection = 0 }
        updateHighlight()
    }

    /// ⇥ with nothing typed in an app: switch between frequently used and suggested. Returns false when it doesn't apply.
    func toggleSuggestions() -> Bool {
        guard query.isEmpty, let app = currentApp, app != Self.settingsEntry else { return false }
        suggesting.toggle()
        recompute()
        return true
    }

    /// Rows shown under "Frequently used" (ids of `results`).
    private(set) var frequentIDs = Set<String>()

    /// Your most used shortcuts across apps, for the top level with nothing typed.
    private func frequentEverywhere() -> [Hit] {
        let apps = Dictionary(allApps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return UsageStore.shared.topEverywhere(limit: 12).compactMap { use in
            guard let app = apps[use.app],
                  let s = ShortcutStore.shared.get(use.app)?.shortcuts.first(where: { $0.path == use.path }) else { return nil }
            return Hit.global(s, app)
        }.prefix(6).map { $0 }
    }

    private func rankedApps() -> [AppEntry] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        func rank(_ a: AppEntry) -> Int { a.id == preferred ? 2 : running.contains(a.id) ? 1 : 0 }
        if query.isEmpty { return allApps.sorted { (rank($0), $1.name.lowercased()) > (rank($1), $0.name.lowercased()) } }
        return allApps.compactMap { a in Fuzzy.rank(query, title: a.name).map { (a, $0 * 10 + rank(a)) } }
            .sorted { ($0.1, -$0.0.name.count) > ($1.1, -$1.0.name.count) }.map(\.0)
    }

    // MARK: Shortcuts from anywhere

    /// Every scanned app's shortcuts, so "brave profile" or "record screen" run without opening the app first.
    /// Built on main when the panel opens (search text cached across opens); ranked off main per keystroke.
    private struct GlobalItem { let app: AppEntry; let shortcut: Shortcut; let context: String }
    private var globalIndex: [GlobalItem] = []
    private var globalDirty = true
    private var contextCache: [String: String] = [:]   // app id | shortcut id → search text (synonym expansion is slow)
    private var globalFound: [(hit: Hit, app: String)] = []
    private var globalGeneration = 0
    private let globalQueue = DispatchQueue(label: "learn.global-search", qos: .userInitiated)

    private func rebuildGlobalIndex() {
        guard globalDirty else { return }
        globalDirty = false
        let apps = Dictionary(allApps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var index: [GlobalItem] = []
        for entry in ShortcutStore.shared.all {
            guard let app = apps[entry.bundleID] else { continue }   // uninstalled apps and helper processes
            let name = app.name.lowercased()
            for s in Self.withBindings(entry.shortcuts, app: app.id)
            where s.path.first != ElementScanner.marker && s.path.first != LearnActions.group {
                let key = app.id + "|" + s.id
                let context = contextCache[key] ?? { let c = s.searchText + " " + name; contextCache[key] = c; return c }()
                index.append(GlobalItem(app: app, shortcut: s, context: context))
            }
        }
        globalIndex = index
    }

    /// Ranks the index for the current query off main; stale answers (older keystrokes) are dropped.
    private func searchGlobal() {
        globalGeneration += 1
        let generation = globalGeneration, q = query
        guard q.count >= 3 else { globalFound = []; return }
        let index = globalIndex, keyless = Prefs.shared.showMenuCommands
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        globalQueue.async { [weak self] in
            var scored: [(GlobalItem, Int)] = []
            for item in index where keyless || item.shortcut.hasKey {
                // Only fairly strong matches: every word hits the title, menu path or app name.
                guard let r = Fuzzy.rank(q, title: item.shortcut.title, context: item.context, keys: item.shortcut.display), r >= 4_000
                else { continue }
                scored.append((item, r * 2 + (running.contains(item.app.id) ? 1 : 0)))
            }
            var seen = Set<String>()   // the same standard item in many apps (Emoji & Symbols…): list it once
            let found = scored.sorted { $0.1 > $1.1 }
                .filter { seen.insert($0.0.shortcut.title.lowercased() + "|" + $0.0.shortcut.display).inserted }
                .prefix(40).map { (hit: Hit.global($0.0.shortcut, $0.0.app), app: $0.0.app.id) }
            DispatchQueue.main.async {
                guard let self, generation == self.globalGeneration else { return }
                self.globalFound = found
                self.recompute(keepSelection: true)
            }
        }
    }

    private func globalHits(excluding: String?, limit: Int) -> [Hit] {
        guard query.count >= 3 else { return [] }
        return globalFound.filter { $0.app != excluding }.prefix(limit).map(\.hit)
    }

    /// Spotlight-style rows around the main list: calculator / conversion on top; then apps, a definition, files.
    private func extras(apps: some Collection<AppEntry>, files limit: Int) -> (top: [Hit], rest: [Hit]) {
        guard !query.isEmpty else { return ([], []) }
        let answers = Prefs.shared.quickAnswers
        let top = answers ? Answers.instant(query).map { [Hit.answer($0)] } ?? [] : []
        let def = answers ? Answers.define(query).map { [Hit.answer($0)] } ?? [] : []
        return (top, apps.map(Hit.app) + def + files.prefix(limit).map(Hit.file))
    }

    // MARK: On-screen elements

    /// Tab on a highlighted on-screen element: open its right-click menu in the app.
    func contextMenu() {
        guard let app = currentApp, app != Self.settingsEntry, let s = selectedShortcut else { return }
        guard let el = screen.elements[s.id] else {
            notice = s.path.first == ElementScanner.marker ? "\(s.title) isn't on screen right now"
                                                           : "Right-click works on on-screen items (tagged “screen”)"
            return
        }
        handFocus(to: app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ElementScanner.showMenu(el) }
    }

    private func scanScreen(appID: String, pid: pid_t, windowTitle: String? = nil) {
        ElementScanner.axQueue(pid).async {   // own windows: main thread (in-process AX); other apps: background
            let els = ElementScanner.scan(pid: pid, windowTitle: windowTitle)
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

    /// Close the panel and give activation straight to `app` (Learn is still active, so macOS allows it).
    private func handFocus(to app: AppEntry) {
        if let running = app.runningApp {
            NSApp.yieldActivation(to: running)
            running.activate()
            onClose(false)
        } else {
            onClose(true)
        }
    }

    private func updateHighlight() {
        let h = selectedShortcut.flatMap { screen.elements[$0.id]?.frame }
        if h != highlight { highlight = h }
    }

    func clearScreen() { screen = ("", [:]); screenRows = []; highlight = nil }

    func move(_ d: Int) {
        guard count > 0 else { return }
        selection = (selection + d + count) % count
    }

    /// `alt` (⌘↩ on an app or file row): launch the app instead of listing its shortcuts, show a file in Finder.
    func activate(_ index: Int? = nil, alt: Bool = false) {
        if let index { selection = index }
        guard selection < count else { return }
        if let app = currentApp, let s = selectedShortcut {
            if app != Self.settingsEntry { UsageStore.shared.record(app: app.id, path: s.path) }
            if app == Self.settingsEntry {   // Learn's own settings: go there; press visible controls off main
                let el = screen.elements[s.id]
                onClose(false)
                SettingsWindow.shared.show(Self.settingsTabs[s.path])
                if let el { DispatchQueue.main.async { ElementScanner.perform(el) } }   // own window: main thread
                return
            }
            switch s.path.first {
            case LearnActions.group, ElementScanner.marker:
                let el = screen.elements[s.id]
                let pid = app.runningApp?.processIdentifier
                Debug.log("activate row '\(s.title)' path=\(s.path) el=\(el.map { "\($0.roleName) web=\($0.web) frame=\($0.frame)" } ?? "nil") screenApp=\(screen.appID) app=\(app.id)")
                handFocus(to: app)
                Sounds.play(.shortcut)
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
            switch results[selection] {
            case .shortcut: break   // only listed inside an app, handled above
            case .global(let s, let app):   // another app's shortcut: Executor activates or launches it, then presses the item
                UsageStore.shared.record(app: app.id, path: s.path)
                onClose(false)
                Executor.run(s, in: app)
            case .app(let a) where alt:
                onClose(false)
                NSWorkspace.shared.openApplication(at: a.url, configuration: NSWorkspace.OpenConfiguration())
            case .app(let a): open(a)
            case .file(let f):
                onClose(false)
                if alt { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } else { NSWorkspace.shared.open(f.url) }
            case .answer(let a) where a.kind == .define:
                onClose(false)
                if let w = a.value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let url = URL(string: "dict://" + w) {
                    NSWorkspace.shared.open(url)
                }
            case .answer(let a):   // calculator / conversion: copy, back to the previous app to paste
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(a.value, forType: .string)
                Sounds.play(.shortcut)
                onClose(true)
                KeyHUD.shared.flash(a.value, caption: "Copied")
            }
        }
    }

    func open(_ app: AppEntry) {
        fileSearch.cancel(); files = []
        mode = .shortcuts(app)
        query = ""
        let cached = ShortcutStore.shared.get(app.id)
        recompute()
        guard app != Self.settingsEntry else { return }   // Learn has no menus to scan
        if cached == nil || cached!.stale || app.isSystem { refresh() }
        else { refreshQuietly(app, since: cached!.scannedAt) }
    }

    /// Every time an app is opened in the panel: re-read its menus in the background — no launch, no menus
    /// flashing open, no spinner — so its list stays current a little at a time. At most every 30 s per app.
    private func refreshQuietly(_ app: AppEntry, since scannedAt: Date) {
        guard app.runningApp != nil, Date().timeIntervalSince(scannedAt) > 30 else { return }
        quietScans.insert(app.id)
        Scanner.shared.scan(app, launchIfNeeded: false) { [weak self] _ in
            guard let self else { return }
            self.quietScans.remove(app.id)
            if self.currentApp == app, self.recording == nil { self.globalDirty = true; self.recompute(keepSelection: true) }
        }
    }
    private var quietScans = Set<String>()

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

    func startRecording() {   // Settings ▸ General ▸ Inside Learn ▸ Record shortcut (default ⌘↩)
        guard let app = currentApp, app != Self.settingsEntry, let item = selectedShortcut else { return }
        guard !app.isSystem else { notice = "System shortcuts are changed in System Settings ▸ Keyboard"; return }
        recording = item
        recorded = nil
    }

    func cancelRecording() { recording = nil; recorded = nil }

    /// Needs ⌘/⌃/⌥ (or an F-key) so plain typing can't become a shortcut.
    func record(code: Int, mods: Mods) {
        let fkey = Keys.names[code]?.hasPrefix("F") == true && Keys.names[code]!.count > 1
        guard Keys.names[code] != nil, fkey || !mods.intersection([.cmd, .ctrl, .opt]).isEmpty else { NSSound.beep(); return }
        recorded = (code, mods)
        if let s = recordedShortcut { KeyHUD.shared.flash(s.display, caption: "New shortcut for \(s.title)") }
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
