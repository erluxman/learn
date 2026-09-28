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
        ("General", .permissions), ("Permissions", .permissions), ("Cleaner: clean up, protect, speed up your Mac", .permissions), ("Accessibility permission", .permissions), ("Send keystrokes & clicks permission", .permissions),
        ("Input Monitoring permission", .permissions), ("Launch at login", .permissions),
        ("Appearance", .appearance), ("Surface: colorful gradient or liquid glass", .appearance),
        ("Glass color and intensity", .appearance), ("Jelly wobble when dragging windows", .appearance), ("Corner roundness of windows", .appearance),
        ("Sounds", .permissions), ("Sound volume", .permissions),
        ("Hotkeys", .hotkeys), ("Open Learn hotkey", .hotkeys), ("Replace Spotlight (⌘Space opens Learn)", .hotkeys), ("Label clickable items hotkey", .hotkeys),
        ("Right-click the focused item hotkey", .hotkeys), ("Open Learn Settings hotkey", .hotkeys),
        ("Pointer mode hotkey (control the pointer with the keyboard)", .hotkeys), ("Move window to next screen hotkey", .hotkeys),
        ("Learn Panel keys", .hotkeys), ("Record-shortcut key (inside Learn)", .hotkeys), ("Right-click key (inside Learn)", .hotkeys),
        ("On Screen", .display), ("Shortcut bubble: position, size, animation", .display),
        ("Right-click with both control keys", .display), ("Pointer mode", .display),
        ("Search", .search), ("Show on-screen items", .search), ("Search files (Spotlight index)", .search),
        ("Quick answers: calculator, unit conversions, definitions", .search), ("Show menu commands without a shortcut", .search),
        ("Advanced", .advanced), ("Rescan interval", .advanced), ("Rescan running apps", .advanced), ("Scan all installed apps", .advanced),
        ("Show database in Finder", .advanced), ("Debug log", .advanced),
        ("My Shortcuts", .shortcuts), ("Shortcuts you recorded in Learn", .shortcuts), ("Remove a recorded shortcut", .shortcuts),
    ].filter { Debug.build || !$0.0.hasPrefix("Cleaner") }   // the Cleaner is debug-only
    private static let settingsRows = settingsIndex.map {
        Shortcut(path: [settingsGroup, $0.1.title, $0.0], key: "", keyCode: nil, mods: [])
    }
    private static let settingsTabs = Dictionary(settingsIndex.map { ([settingsGroup, $0.1.title, $0.0], $0.1) }, uniquingKeysWith: { a, _ in a })

    @Published var mode: Mode = .apps { didSet { screenOnly = false } }
    /// ⇧⇥ with nothing typed inside an app: the most relevant shortcuts instead of the most used.
    @Published private(set) var suggesting = false
    /// ⇥ + Space with nothing typed inside an app: search only what's on screen (buttons, links, text) — no shortcuts, no other apps.
    @Published private(set) var screenOnly = false

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            suggesting = false
            notice = nil
            files = []
            fileSearch.cancel()   // started by recompute only when almost nothing else matched
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
            if Prefs.shared.showScreenItems { scanScreen(appID: id, pid: f.processIdentifier, window: QuickTerminal.window) }
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
        if screenOnly, let app = currentApp {
            let onScreen = screen.appID == app.id ? screenRows : []
            let ranked = query.isEmpty ? onScreen
                : onScreen.compactMap { s in Fuzzy.rank(query, title: s.title, context: s.searchText).map { (s, $0) } }
                    .sorted { ($0.1, -$0.0.title.count) > ($1.1, -$1.0.title.count) }.map(\.0)
            results = ranked.map(Hit.shortcut)
            info = "\(onScreen.count) on screen"
        } else if let app = currentApp {
            let entry = ShortcutStore.shared.get(app.id)
            // Learn's own commands only appear when searched for — the list itself is just this app.
            let learn = query.isEmpty ? [] : (LearnActions.all + WindowMover.paths).map { Shortcut(path: $0, key: "", keyCode: nil, mods: []) }
            let onScreen = screen.appID == app.id ? screenRows : []
            let menus = (entry?.shortcuts ?? []).filter { Prefs.shared.showMenuCommands || $0.hasKey || Self.documentKind($0) != nil }
            let list = app == Self.settingsEntry ? Self.settingsRows + onScreen
                                                  : Self.withBindings(learn + onScreen + menus, app: app.id)
            let scored = query.isEmpty ? list.map { ($0, 0) }
                : list.compactMap { s in Fuzzy.rank(query, title: s.title, context: s.searchText, keys: s.display)
                        .map { (s, $0 + (s.path.first == ElementScanner.marker ? Self.onScreenBoost : 0)) } }
                    .sorted { ($0.1, -$0.0.title.count, -$0.0.path.count) > ($1.1, -$1.0.title.count, -$1.0.path.count) }
            let shortcuts = scored.map(\.0)
            let outside = app == Self.settingsEntry
            // Nothing typed: only the shortcuts you use most here (⇥: the most relevant ones); typing searches all of them.
            if query.isEmpty && !outside {
                let picked = suggesting ? RelevanceStore.shared.suggestions(menus, app: app.id, limit: 12)
                                        : UsageStore.shared.top(shortcuts.filter { Self.documentKind($0) == nil }, app: app.id, limit: 8)
                results = picked.map(Hit.shortcut)
            } else if outside && query.isEmpty {
                results = shortcuts.map(Hit.shortcut)   // Learn's settings, listed
            } else {
                // Searching from Learn's Settings works like any app: its settings first, then apps, answers and the rest.
                let kinds = scored.map { ($0.0, $0.1, Self.documentKind($0.0)) }
                // 2nd: this app's commands, apps named like the query ("vs code" → VS Code), system shortcuts.
                let own = kinds.filter { $0.2 == nil }.map { (Hit.shortcut($0.0), $0.1) }
                let apps = rankedApps().filter { $0 != app }.compactMap { a in Fuzzy.rank(query, title: a.name).map { (Hit.app(a), $0) } }
                    .filter { $0.1 >= 6_000 }.prefix(5)
                let system = globalFound.filter(\.system).map { ($0.hit, $0.rank) }
                let second = (own + apps + system).enumerated()
                    .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }.map(\.element)   // ties: this app first
                // 3rd: other apps' shortcuts and bookmarks (this app's bookmarks too), held below the top rows.
                let foreign = (globalFound.filter { !$0.system && $0.app != app.id && ($0.kind == nil || $0.kind == .bookmark) }
                                   .prefix(10).map { ($0.hit, $0.rank) }
                               + kinds.filter { $0.2 == .bookmark }.map { (Hit.shortcut($0.0), $0.1) })
                    .sorted { $0.1 > $1.1 }
                let (top, def) = answers()
                // Then this app's tabs and windows; then history, recent files and other apps' windows; files last.
                let mine = kinds.filter { $0.2 == .tab || $0.2 == .window }.map { Hit.shortcut($0.0) }
                let low = kinds.filter { $0.2 == .history || $0.2 == .recent }.map { Hit.shortcut($0.0) }
                    + globalFound.filter { $0.app != app.id && [.window, .history, .recent].contains($0.kind) }.prefix(8).map(\.hit)
                results = top + Self.merge(second, filler: def + mine, foreign: foreign, start: top.count) + low
            }
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
            let (top, def) = answers()
            let named = apps.compactMap { a in Fuzzy.rank(query, title: a.name).map { (a, $0) } }
            // Like Spotlight: nothing typed, nothing listed — the panel is just the search field.
            // "settings", "prefs", "learn set…": Learn's own settings come first, ahead of System Settings and the rest.
            let own = !query.isEmpty && [SettingsWindow.title, "Settings", "Preferences", "Learn Preferences"]
                .contains { Fuzzy.rank(query, title: $0) ?? 0 >= 6_000 }
            let mine: [(Hit, Int)] = own ? [(Hit.app(Self.settingsEntry), Int.max)] : []
            // 2nd: apps named like the query and system shortcuts; 3rd: every app's shortcuts and bookmarks, held
            // below the top rows; then looser app matches and a definition; history, recent files and windows low.
            let second = mine + (named.filter { $0.1 >= 6_000 && $0.0 != Self.settingsEntry }.map { (Hit.app($0.0), $0.1) }
                                 + globalFound.filter(\.system).map { ($0.hit, $0.rank) }).sorted { $0.1 > $1.1 }
            let foreign = globalFound.filter { !$0.system && ($0.kind == nil || $0.kind == .bookmark) }.prefix(25).map { ($0.hit, $0.rank) }
            let weak = named.filter { $0.1 < 6_000 }.map { Hit.app($0.0) }
            let low = globalFound.filter { [.window, .history, .recent].contains($0.kind) }.prefix(8).map(\.hit)
            results = query.isEmpty ? [] : top + Self.merge(second, filler: weak + def, foreign: foreign, start: top.count) + low
            let global = globalFound
            info = "\(apps.count) apps\(global.isEmpty ? "" : " · \(global.count) shortcuts")\(files.isEmpty ? "" : " · \(files.count) files")"
        }
        // Files on disk only when almost nothing else matched (a Spotlight query is the costliest part of a search).
        if Prefs.shared.searchFiles, !screenOnly, !query.isEmpty, globalSettled, results.count < 2 {
            fileSearch.search(query)
            results += files.prefix(40).map(Hit.file)
        }
        if !keepSelection || selection >= count { selection = 0 }
        updateHighlight()
    }

    /// `own` rows in score order with `foreign` ones (other apps' shortcuts) merged in by score — but never in the
    /// first two rows, and only from the 3rd row with a strong match (the query starts the name or one of its
    /// words), otherwise not above the 8th. `filler` (lower sections) fills rows until foreign ones may go there.
    private static func merge(_ own: [(Hit, Int)], filler: [Hit], foreign: [(Hit, Int)], start: Int) -> [Hit] {
        let ownRows = own + filler.map { ($0, Int.min) }
        var out: [Hit] = [], i = 0, j = 0
        while i < ownRows.count || j < foreign.count {
            if j < foreign.count {
                let (hit, rank) = foreign[j]
                let floor = rank >= 8_000 ? 2 : 7
                if i >= ownRows.count || (start + out.count >= floor && rank > ownRows[i].1) {
                    out.append(hit); j += 1; continue
                }
            }
            out.append(ownRows[i].0); i += 1
        }
        return out
    }

    /// Nothing typed in an app: search only its on-screen items (⎋ / ⌫ go back). False when it doesn't apply.
    func enterScreenOnly() -> Bool {
        guard query.isEmpty, !screenOnly, let app = currentApp else { return false }
        if screen.appID != app.id, let running = app.runningApp {   // not scanned yet (setting off, or drilled in)
            scanScreen(appID: app.id, pid: running.processIdentifier)
        }
        screenOnly = true
        suggesting = false
        recompute()
        return true
    }

    /// ⇧⇥ with nothing typed in an app: switch between frequently used and suggested. Returns false when it doesn't apply.
    func toggleSuggestions() -> Bool {
        guard query.isEmpty, !screenOnly, let app = currentApp, app != Self.settingsEntry else { return false }
        suggesting.toggle()
        recompute()
        return true
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
    private struct GlobalItem { let app: AppEntry; let shortcut: Shortcut; let context: String; let used: Double; let kind: DocKind? }
    private var globalIndex: [GlobalItem] = []
    private var globalDirty = true
    private var contextCache: [String: String] = [:]   // app id | shortcut id → search text (synonym expansion is slow)
    /// Matches from every app: `rank` is the plain match strength (comparable with this app's rows), `system` marks
    /// macOS's own shortcuts (window management, screenshots…), `kind` a document (tab, window, bookmark…).
    private var globalFound: [(hit: Hit, app: String, rank: Int, system: Bool, kind: DocKind?)] = []
    private var globalSettled = true   // the everywhere-search has answered for the current query
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
                index.append(GlobalItem(app: app, shortcut: s, context: context,
                                        used: UsageStore.shared.score(app: app.id, path: s.path), kind: Self.documentKind(s)))
            }
        }
        globalIndex = index
    }

    /// Ranks the index for the current query off main; stale answers (older keystrokes) are dropped.
    private func searchGlobal() {
        globalGeneration += 1
        let generation = globalGeneration, q = query
        guard q.count >= 3 else { globalFound = []; globalSettled = true; return }
        globalSettled = false
        let index = globalIndex, keyless = Prefs.shared.showMenuCommands
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        globalQueue.async { [weak self] in
            var scored: [(GlobalItem, Int, Int)] = []   // item, match strength, order (strength + use + running)
            for item in index where keyless || item.shortcut.hasKey || item.kind != nil {
                // Only fairly strong matches: every word hits the title, menu path or app name.
                guard let r = Fuzzy.rank(q, title: item.shortcut.title, context: item.context, keys: item.shortcut.display), r >= 4_000
                else { continue }
                // Match quality first; how much you use it (recent use counts more) lifts it within its match tier.
                scored.append((item, r, r * 2 + Int(min(item.used, 10) * 150) + (running.contains(item.app.id) ? 1 : 0)))
            }
            var seen = Set<String>()   // the same standard item in many apps (Emoji & Symbols…): list it once
            let found = scored.sorted { $0.2 > $1.2 }
                .filter { seen.insert($0.0.shortcut.title.lowercased() + "|" + $0.0.shortcut.display).inserted }
                .prefix(60).map { (hit: Hit.global($0.0.shortcut, $0.0.app), app: $0.0.app.id,
                                   rank: $0.1 + Int(min($0.0.used, 10) * 150), system: $0.0.app.id == SystemShortcuts.bundleID, kind: $0.0.kind) }
            DispatchQueue.main.async {
                guard let self, generation == self.globalGeneration else { return }
                self.globalFound = found
                self.globalSettled = true
                self.recompute(keepSelection: true)
            }
        }
    }

    /// Quick answers: a calculation or conversion always on top. A definition goes on top too when asked for
    /// ("define gold", "gold meaning", "synonyms of happy"); otherwise it waits lower down.
    private func answers() -> (top: [Hit], definition: [Hit]) {
        guard !query.isEmpty, Prefs.shared.quickAnswers else { return ([], []) }
        let instant = Answers.instant(query).map { [Hit.answer($0)] } ?? []
        if let word = Self.dictionaryWord(query) { return (instant + (Answers.define(word).map { [Hit.answer($0)] } ?? []), []) }
        return (instant, Answers.define(query).map { [Hit.answer($0)] } ?? [])
    }

    private static let dictionaryAsks: Set<String> = ["define", "definition", "definitions", "meaning", "meanings", "mean",
                                                      "synonym", "synonyms", "antonym", "antonyms"]
    /// The word in a dictionary request, or nil when the query isn't one.
    static func dictionaryWord(_ q: String) -> String? {
        let words = q.lowercased().split(whereSeparator: { $0 == " " || $0 == "?" }).map(String.init)
        guard words.contains(where: dictionaryAsks.contains) else { return nil }
        let rest = words.filter { !dictionaryAsks.contains($0) && !["of", "the", "what", "is", "does", "for", "a", "word"].contains($0) }
        return rest.count == 1 ? rest[0] : nil
    }

    /// Menu items that name a document rather than a command. Tabs show only in their own browser; bookmarks rank like
    /// other apps' shortcuts; windows of this app come after its commands; history, recent files and other apps'
    /// windows go low (a Brave tab titled "How to find gold" never tops a search in VS Code).
    enum DocKind { case tab, window, bookmark, history, recent }

    static func documentKind(_ s: Shortcut) -> DocKind? {
        guard !s.hasKey, s.path.first != ElementScanner.marker else { return nil }
        let menus = s.path.dropLast()
        if menus.contains(where: ["Bookmarks", "Favorites", "Reading List"].contains) { return .bookmark }
        if menus.contains(where: ["History", "Recently Visited", "Recently Closed"].contains) { return .history }
        if menus.contains(where: ["Open Recent", "Recent Items"].contains) { return .recent }
        guard ["Window", "Tab"].contains(s.path.first), s.path.count == 2 else { return nil }   // Brave/Chrome list tabs under Tab
        let t = s.title.lowercased()
        guard !windowCommands.contains(where: { t.hasPrefix($0) }) else { return nil }
        return s.path.first == "Tab" ? .tab : .window
    }
    /// Window- and Tab-menu commands (everything else listed there is an open window or tab).
    private static let windowCommands = ["minimize", "zoom", "fill", "center", "move", "tile", "bring all", "arrange", "remove window",
                                         "show", "merge", "name window", "enter full", "exit full", "pin", "unpin", "duplicate",
                                         "close", "select", "go to", "new", "reopen", "float", "cycle", "full screen", "resize",
                                         "return to", "restore", "developer", "downloads", "extensions", "task manager", "search tabs",
                                         "mute", "unmute", "group", "ungroup", "reload", "add ", "remove ", "bookmark", "split",
                                         "open ", "sleep", "discard", "copy", "send ", "share", "rename", "clear", "reset", "toggle"]

    // MARK: On-screen elements

    /// ⇥ + Space. Nothing typed inside an app: search only what's on screen (plain ⇥ always moves down the list).
    /// Otherwise right-click (`contextMenu`).
    func onScreenChord() { if !enterScreenOnly() { contextMenu() } }

    /// ⇥ + Space: right-clicks the highlighted on-screen item. With none highlighted (no app selected, or a menu
    /// command / app row), right-clicks wherever the mouse is, like ⌃ + ⌃.
    func contextMenu() {
        if let app = currentApp, app != Self.settingsEntry, let s = selectedShortcut, let el = screen.elements[s.id] {
            handFocus(to: app)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ElementScanner.showMenu(el) }
            return
        }
        guard let p = CGEvent(source: nil)?.location else { return }
        onClose(true)   // focus back to the app under the panel first
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.25) { ElementScanner.click(at: p, right: true) }
    }

    /// `window`: Ghostty's open quick terminal — scanned right away, alone, before the panel takes the keyboard and it hides.
    private func scanScreen(appID: String, pid: pid_t, windowTitle: String? = nil, window: AXUIElement? = nil, retries: Int = 4) {
        if let window {
            apply(ElementScanner.scan(pid: pid, only: window), appID: appID)
            return
        }
        ElementScanner.axQueue(pid).async {   // own windows: main thread (in-process AX); other apps: background
            let els = ElementScanner.scan(pid: pid, windowTitle: windowTitle)
            // A browser that just had its page accessibility turned on takes ~2 s to build the page's tree: look again.
            if retries > 0, ElementScanner.isChromiumBrowser(pid), !els.contains(where: \.web) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, self.screen.appID == appID || self.screen.appID.isEmpty else { return }
                    self.scanScreen(appID: appID, pid: pid, windowTitle: windowTitle, retries: retries - 1)
                }
            }
            DispatchQueue.main.async { self.apply(els, appID: appID) }
        }
    }

    private func apply(_ els: [ScreenElement], appID: String) {
        var byID: [String: ScreenElement] = [:], rows: [Shortcut] = []
        for e in els where !e.text.isEmpty {   // unlabeled icons: reachable via label mode only
            let s = e.shortcut
            if byID[s.id] == nil { byID[s.id] = e; rows.append(s) }
        }
        screen = (appID, byID)
        screenRows = rows
        if currentApp?.id == appID { recompute(keepSelection: true) }
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
                Sounds.play(.shortcut)
                let quickTerminal = QuickTerminal.take(for: app.id)   // Ghostty's drop-down hid when the panel opened
                handFocus(to: app)   // closes the panel first, so the drop-down can have the keyboard back
                let run = {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if s.path.first == LearnActions.group { LearnActions.run(s.path) }
                        else if let el { ElementScanner.perform(el) }
                        else if let pid { DispatchQueue.global().async { _ = ElementScanner.pressMatching(path: s.path, pid: pid) } }
                    }
                }
                if quickTerminal { QuickTerminal.bringBack(then: run) } else { run() }
            default:
                let quickTerminal = QuickTerminal.take(for: app.id)
                onClose(false)   // Executor activates the target app itself
                if quickTerminal { QuickTerminal.bringBack { Executor.run(s, in: app) } } else { Executor.run(s, in: app) }
            }
        } else {
            switch results[selection] {
            case .shortcut: break   // only listed inside an app, handled above
            case .global(let s, let app):   // another app's shortcut: Executor activates or launches it, then presses the item
                UsageStore.shared.record(app: app.id, path: s.path)
                onClose(false)
                Executor.run(s, in: app)
            case .app(let a) where a == Self.settingsEntry:   // Learn's own settings
                onClose(false)
                SettingsWindow.shared.show()
            case .app(let a):   // ↩ opens the app (⇥ shows its shortcuts instead: see drillIn)
                onClose(false)
                NSWorkspace.shared.openApplication(at: a.url, configuration: NSWorkspace.OpenConfiguration())
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

    /// ⇥ on an app row: show that app's shortcuts instead of opening it. False when the row isn't an app.
    func drillIn() -> Bool {
        guard selection < count, case .app(let a) = results[selection] else { return false }
        open(a)
        return true
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

    func back() {
        notice = nil
        if screenOnly { screenOnly = false; query = "" } else { mode = .apps; query = "" }   // on-screen search → the app first
        recompute(); focusTick += 1
    }

    /// Esc is the only way back: shortcuts → apps; in apps it clears the query, then closes.
    /// One press closes, like Spotlight (and brings Ghostty's quick terminal back). ⌫ on an empty search goes back instead.
    func escape() { onClose(true) }

    /// What's on screen beats a shortcut matching equally well: one Fuzzy tier up (an exact shortcut name still wins).
    static let onScreenBoost = 1_000
}
