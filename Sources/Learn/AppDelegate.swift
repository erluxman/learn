import AppKit
import Carbon
import ServiceManagement
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = SearchModel()
    private lazy var panel = Panel(model: model)
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var prefsSource: DispatchSourceFileSystemObject?
    private var syncWork: DispatchWorkItem?
    private var timer: Timer?
    private let store = ShortcutStore.shared
    private let keyTap = KeyTap()
    private let hints = HintMode()
    private let menuSearch = MenuSearch()
    private let pointer = PointerMode()
    private var bag = Set<AnyCancellable>()
    private var lastApp: NSRunningApplication?   // last app the user focused (not Learn)

    /// Read here: by applicationDidFinishLaunching the launch event is usually no longer current.
    private var launchedAtLogin = false
    func applicationWillFinishLaunching(_ note: Notification) {
        launchedAtLogin = Self.launchedAsLoginItem()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Sounds.installFeedback()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        // Chromium browsers show page contents to Learn only while their accessibility is on: keep it on, always.
        NSWorkspace.shared.runningApplications.forEach(ElementScanner.keepWebContentOn)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard self?.panel.isVisible == true else { return }
            Debug.log("activated \((n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? "?") space=\(Debug.space)")
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            Debug.log("space changed → \(Debug.space) front=\(Debug.front)")
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { ElementScanner.keepWebContentOn(app) }
            }
        }
        model.onClose = { [weak self] in
            self?.panel.dismiss(restoreFocus: $0)
            self?.model.clearScreen()
        }
        installLearnActions()
        model.openSettings = { [weak self] in self?.panel.dismiss(restoreFocus: false); SettingsWindow.shared.show() }
        panel.onDismiss = { [weak self] in self?.hints.highlight(nil) }
        registerPanelHotKey()
        for name in [Prefs.changed, Recorder.changed] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.registerPanelHotKey() }
        }
        SettingsWindow.shared.rescanRunning = { [weak self] in self?.scanRunningApps(onlyMissing: false) }
        SettingsWindow.shared.scanAll = { [weak self] in self?.menuScanAll() }
        installKeyMonitor()
        installStatusItem()
        watchPreferences()
        observeAppActivation()

        syncSystemShortcuts()
        if Prefs.shared.quickAnswers { Rates.shared.refreshIfStale() }   // so the first currency query has rates
        Debug.log("launch: AXTrusted=\(AXIsProcessTrusted()) postEvents=\(CGPreflightPostEventAccess()) listenEvents=\(CGPreflightListenEventAccess())")
        whenTrusted { [weak self] in
            self?.model.trusted = true
            NSLog("Learn key tap: %@", self?.keyTap.start() == true ? "started" : "FAILED")
            self?.scanRunningApps(onlyMissing: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.syncCustomKeys() }
        // Opening the app → Settings; the hotkey → search. Silent when started at login.
        if !launchedAtLogin { SettingsWindow.shared.show(AXIsProcessTrusted() ? .hotkeys : .permissions) }
    }

    /// ⌘C ⌘V ⌘X ⌘A ⌘Z ⇧⌘Z in the search field. Text fields get these from the app's Edit menu, which Learn (a menu
    /// bar app) doesn't have, so the panel sends them to the focused field itself.
    private static func editAction(_ e: NSEvent) -> Selector? {
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (Int(e.keyCode), flags) {
        case (kVK_ANSI_C, .command): return #selector(NSText.copy(_:))
        case (kVK_ANSI_V, .command): return #selector(NSText.paste(_:))
        case (kVK_ANSI_X, .command): return #selector(NSText.cut(_:))
        case (kVK_ANSI_A, .command): return #selector(NSText.selectAll(_:))
        case (kVK_ANSI_Z, .command): return Selector(("undo:"))
        case (kVK_ANSI_Z, [.command, .shift]): return Selector(("redo:"))
        default: return nil
        }
    }

    /// Whether `app` has a normal window on the screen the panel opens on (desktop icons, menus and panels don't count).
    /// A window on another display doesn't count: the screen you're looking at is empty.
    private static func hasOpenWindow(_ app: NSRunningApplication) -> Bool {
        guard let screen = NSScreen.main?.frame, let top = NSScreen.screens.first?.frame.maxY else { return false }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? [String: Double] else { return false }
            let x = b["X"] ?? 0, y = b["Y"] ?? 0, width = b["Width"] ?? 0, height = b["Height"] ?? 0
            let visible = NSRect(x: x, y: top - y - height, width: width, height: height).intersection(screen)   // CG is top-left origin
            return visible.width > 60 && visible.height > 60
        }
    }

    private static func launchedAsLoginItem() -> Bool {
        guard let e = NSAppleEventManager.shared().currentAppleEvent, e.eventID == kAEOpenApplication else { return false }
        return e.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Panel hotkey from Settings; paused while a recorder is capturing so the combo can be re-recorded.
    private func registerPanelHotKey() {
        hotKey = nil
        guard !Recorder.active else { return }
        let k = Prefs.shared.panelKey
        hotKey = HotKey(keyCode: k.keyCode, carbonMods: Prefs.carbonMods(k.mods)) { [weak self] in self?.toggle() }
        if Prefs.shared.panelKeyRegistered != hotKey!.registered { Prefs.shared.panelKeyRegistered = hotKey!.registered }
        statusItem?.menu?.items.first?.title = "Open Learn  (\(k.shortcut.display))"
    }

    // Opened again from Spotlight / Finder / Dock while running → Settings (the hotkey is for search).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.shared.show(AXIsProcessTrusted() ? nil : .permissions)
        return false
    }

    // MARK: Panel

    private func toggle() { panel.isVisible ? panel.dismiss() : show() }

    private func show() {
        pointer.stop()   // the panel needs plain keys
        if SettingsWindow.shared.isFront {   // searching Learn's own settings; Settings stays open underneath
            panel.returnTo = nil
            model.willShow(frontmost: nil, settings: true)
        } else {
            let me = Bundle.main.bundleIdentifier
            let candidates = [NSWorkspace.shared.frontmostApplication, NSWorkspace.shared.menuBarOwningApplication, lastApp]
            let target = QuickTerminal.ghosttyIfOnScreen()
                ?? candidates.compactMap { $0 }.first { $0.bundleIdentifier != me && !$0.isTerminated }
            panel.returnTo = target   // focus still goes back to it on close
            QuickTerminal.capture(target)   // before the panel takes the keyboard and Ghostty's drop-down hides
            Debug.log("show target=\(target?.bundleIdentifier ?? "nil") quickTerminal=\(QuickTerminal.window != nil) hasWindow=\(target.map(Self.hasOpenWindow) ?? false) space=\(Debug.space)")
            // Nothing open on this screen (e.g. Finder on a bare desktop): open on the app list, as if no app were selected.
            // (Ghostty's quick terminal floats above normal windows, so it's counted separately.)
            model.willShow(frontmost: target.flatMap { Self.hasOpenWindow($0) || QuickTerminal.window != nil ? $0 : nil })
        }
        panel.present(takeKey: QuickTerminal.window == nil)   // over the quick terminal: it keeps the keyboard, stays up
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            return self.panelKey(e)
        }
        // The panel open over Ghostty's quick terminal doesn't take the keyboard (the drop-down would hide): Learn's key tap
        // hands it every key instead, and they never reach the terminal. The panel hotkey passes (it closes the panel).
        keyTap.panelKeys = { [weak self] cg, type in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow, let e = NSEvent(cgEvent: cg) else { return false }
            if type == .keyDown, Prefs.shared.panelKey.matches(Int(e.keyCode), Recorder.mods(e.modifierFlags)) { return false }
            if let rest = self.panelKey(e, focused: false), rest.type == .keyDown { self.typeWithoutFocus(rest) }
            return true
        }
    }

    /// A key for the panel; returns it when the panel had no use for it (typing for the search field).
    /// `focused`: the panel has the keyboard, so editing keys go to its text field.
    private func panelKey(_ e: NSEvent, focused: Bool = true) -> NSEvent? {
        if e.type == .keyUp { return chordKeyUp(e) }
        if model.recording != nil { handleRecorderKey(e); return nil }
        let cmd = e.modifierFlags.contains(.command)
        let code = Int(e.keyCode), mods = Recorder.mods(e.modifierFlags)
        if focused, let action = Self.editAction(e) { NSApp.sendAction(action, to: nil, from: nil); return nil }
        if code == kVK_Tab, mods.isEmpty, model.enterScreenOnly() { return nil }   // ⇥ on an empty search: on-screen items only
        if code == kVK_Tab, mods == [.shift], model.toggleSuggestions() { return nil }   // ⇧⇥ on an empty search: frequent ↔ suggested
        if let handled = tabChord(e, code: code, mods: mods) { return handled }
        if model.selectedShortcut != nil, Prefs.shared.recordKey.matches(code, mods) {   // Settings ▸ General ▸ Inside Learn
            model.startRecording(); return nil
        }
        switch code {
        case kVK_DownArrow: model.move(1)
        case kVK_UpArrow: model.move(-1)
        case kVK_Return where cmd && model.selectedShortcut == nil: model.activate(alt: true)
        case kVK_Return, kVK_ANSI_KeypadEnter: model.activate()
        case kVK_Tab where mods == [.shift]: model.move(-1)
        case kVK_Escape: model.escape()
        case kVK_Delete where model.query.isEmpty && model.currentApp != nil: model.back()
        case kVK_ANSI_R where cmd: model.refresh()
        case kVK_ANSI_W where cmd: panel.dismiss()
        case kVK_ANSI_Comma where cmd: model.openSettings()
        default: return e
        }
        return nil
    }

    /// Typing into the search while the panel doesn't have the keyboard: characters, ⌫, ⌘⌫ (clear), ⌘V (paste).
    private func typeWithoutFocus(_ e: NSEvent) {
        let m = e.modifierFlags.intersection([.command, .control, .option])
        switch Int(e.keyCode) {
        case kVK_Delete where m.contains(.command) || m.contains(.option): model.query = ""
        case kVK_Delete: if !model.query.isEmpty { model.query.removeLast() }
        case kVK_ANSI_V where m == .command: model.query += NSPasteboard.general.string(forType: .string)?
            .components(separatedBy: .newlines).joined(separator: " ") ?? ""
        default:
            guard !m.contains(.command), !m.contains(.control), let s = e.characters, !s.isEmpty,
                  s.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) })
            else { return }   // arrows, F-keys and other function keys
            model.query += s
        }
    }

    // MARK: ⇥ and the ⇥ + Space chord

    /// ⇥ goes down the list (on an app row: into its shortcuts); ⇥ and Space together right-click the highlighted item.
    /// So ⇥ waits for its release (or a repeat) before moving: Space arriving first makes it the chord instead.
    private var tabDown = false, tabPending = false, spaceDown = false

    /// nil: not ⇥ / Space, carry on. Otherwise the event's fate (nil = swallowed).
    private func tabChord(_ e: NSEvent, code: Int, mods: Mods) -> NSEvent?? {
        switch code {
        case kVK_Tab where mods.isEmpty:
            if e.isARepeat {   // held: keep going down
                if tabPending { tabPending = false; tabStep() }
                tabStep()
                return .some(nil)
            }
            if spaceDown {   // Space went first: it typed a space — take it back
                if model.query.hasSuffix(" ") { model.query.removeLast() }
                model.contextMenu()
                return .some(nil)
            }
            tabDown = true; tabPending = true
            return .some(nil)
        case kVK_Space where mods.isEmpty:
            if tabDown {
                tabPending = false
                model.contextMenu()
                return .some(nil)
            }
            spaceDown = true
            return .some(e)   // types a space
        default:
            return nil
        }
    }

    private func chordKeyUp(_ e: NSEvent) -> NSEvent? {
        switch Int(e.keyCode) {
        case kVK_Tab:
            if tabPending { tabStep() }
            tabDown = false; tabPending = false
            return nil
        case kVK_Space:
            spaceDown = false
            return e
        default:
            return e
        }
    }

    private func tabStep() { if !model.drillIn() { model.move(1) } }   // ⇥ on an app: its shortcuts (↩ opens it)

    /// While recording: plain ↩ saves, plain ⌫ resets to default, plain ⎋ cancels; anything else is the new combo.
    private func handleRecorderKey(_ e: NSEvent) {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: Mods = []
        if f.contains(.command) { mods.insert(.cmd) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.option) { mods.insert(.opt) }
        if f.contains(.control) { mods.insert(.ctrl) }
        let plain = mods.isEmpty
        switch Int(e.keyCode) {
        case kVK_Escape where plain: model.cancelRecording()
        case kVK_Return where plain, kVK_ANSI_KeypadEnter where plain: model.saveRecording()
        case kVK_Delete where plain: model.saveRecording(reset: true)
        default: model.record(code: Int(e.keyCode), mods: mods)
        }
    }

    /// Learn's own commands (searchable in every app's list, bindable with ⌘↩) and label mode wiring.
    private func installLearnActions() {
        keyTap.suspended = { [weak self] in self?.model.recording != nil || Recorder.active }
        hints.onKeysCaptured = { [weak self] on in
            guard let self else { return }
            self.keyTap.interceptor = on ? { [weak self] code, mods, rep in rep || self?.hints.handle(keyCode: code, mods: mods) ?? false } : nil
        }
        menuSearch.onKeysCaptured = { [weak self] on in
            guard let self else { return }
            self.keyTap.interceptor = on ? { [weak self] code, mods, rep in rep || self?.menuSearch.handle(keyCode: code, mods: mods) ?? false } : nil
        }
        pointer.onKeysCaptured = { [weak self] on in
            guard let self else { return }
            self.keyTap.interceptor = on ? { [weak self] code, mods, rep in self?.pointer.handle(keyCode: code, mods: mods, isRepeat: rep) ?? false } : nil
            self.keyTap.releaser = on ? { [weak self] code in self?.pointer.release(code) } : nil
        }
        keyTap.onChord = {
            guard Prefs.shared.chordRightClick, let p = CGEvent(source: nil)?.location else { return }
            KeyHUD.shared.flash("⌃ + ⌃", caption: "Right-click")
            DispatchQueue.global(qos: .userInteractive).async { ElementScanner.click(at: p, right: true) }
        }
        keyTap.observer = { code, mods in
            let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            DispatchQueue.main.async {
                KeyHUD.shared.pressed(code: code, mods: mods, app: app)
                UsageStore.shared.recordKey(code: code, mods: mods, app: app)
            }
        }
        ElementScanner.onMenuOpened = { [weak self] pid, point in self?.menuSearch.start(pid: pid, near: point) }
        LearnActions.run = { [weak self] path in
            guard let self else { return }
            if path == LearnActions.settings { self.panel.dismiss(restoreFocus: false); SettingsWindow.shared.show(); return }
            if path == LearnActions.rightClick {
                let wait = self.panel.isVisible ? 0.25 : 0
                if self.panel.isVisible { self.panel.dismiss() }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                ElementScanner.axQueue(front).asyncAfter(deadline: .now() + wait) { ElementScanner.rightClickFocused() }
                return
            }
            if path == LearnActions.nextScreen { WindowMover.move(to: nil); return }
            if let last = path.last, last.hasPrefix(WindowMover.prefix) {   // "Move window to <display>"
                WindowMover.move(to: String(last.dropFirst(WindowMover.prefix.count)))
                return
            }
            if path == LearnActions.pointer {
                if self.pointer.active { self.pointer.stop(); return }
                if self.panel.isVisible { self.panel.dismiss() }
                self.hints.stop()   // one key interceptor at a time
                self.menuSearch.stop()
                self.pointer.start()
                return
            }
            guard path == LearnActions.labels else { return }
            self.pointer.stop()
            if self.panel.isVisible {   // panel open: close it, return focus to the app, then label that app
                self.panel.dismiss()
                self.model.clearScreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.hints.start() }
            } else {
                self.hints.toggle()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            if self?.hints.active == true { self?.hints.stop() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.hints.active == true { self?.hints.stop() }
        }
        model.$highlight.removeDuplicates().sink { [weak self] frame in
            guard let self else { return }
            self.hints.highlight(self.panel.isVisible ? frame : nil)
        }.store(in: &bag)
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Learn")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Learn  (\(Prefs.shared.panelKey.shortcut.display))", action: #selector(menuShow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Open Cleaner…", action: #selector(menuCleaner), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rescan Running Apps", action: #selector(menuScanRunning), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Scan All Installed Apps (launches each hidden)…", action: #selector(menuScanAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Rescan System Shortcuts", action: #selector(menuSyncSystem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Database in Finder", action: #selector(menuOpenDB), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isOn ? .on : .off
        menu.addItem(withTitle: "Quit Learn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    @objc private func menuShow() { show() }
    @objc private func menuCleaner() { CleanerWindow.shared.show() }
    @objc private func menuSettings() { SettingsWindow.shared.show() }
    @objc private func menuScanRunning() { scanRunningApps(onlyMissing: false) }
    @objc private func menuSyncSystem() { store.put(SystemShortcuts.load()) }
    @objc private func menuOpenDB() { NSWorkspace.shared.activateFileViewerSelecting([store.dir]) }

    @objc func menuScanAll() {
        let alert = NSAlert()
        alert.messageText = "Scan every installed app?"
        alert.informativeText = "Each app not already running is launched hidden, its menus are read, then it is quit. This can take several minutes."
        alert.addButton(withTitle: "Scan All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let apps = AppCatalog.load().filter { !$0.isSystem }
        Scanner.shared.scanAll(apps, launchIfNeeded: true) { [weak self] done, total in
            self?.statusItem?.button?.title = done == total ? "" : " \(done)/\(total)"
            self?.statusItem?.length = done == total ? NSStatusItem.squareLength : NSStatusItem.variableLength
        }
    }

    @objc private func menuToggleLogin(_ sender: NSMenuItem) {
        LoginItem.set(SMAppService.mainApp.status != .enabled)
        sender.state = LoginItem.isOn ? .on : .off
    }

    /// The menu can go stale when Settings flips the switch; refresh it every time it opens.
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.action == #selector(menuToggleLogin) }?.state = LoginItem.isOn ? .on : .off
    }

    // MARK: Sync

    /// Runs `body` once Accessibility is granted (polls, so no relaunch is needed after granting).
    private func whenTrusted(_ body: @escaping () -> Void) {
        if AXIsProcessTrusted() { return body() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            body()
        }
    }

    private func scanRunningApps(onlyMissing: Bool) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { r -> AppEntry? in
                guard let id = r.bundleIdentifier, let url = r.bundleURL else { return nil }
                if onlyMissing, let e = store.get(id), !e.stale { return nil }
                return AppEntry(id: id, name: r.localizedName ?? id, url: url)
            }
        Scanner.shared.scanAll(apps, launchIfNeeded: false) { _, _ in }
    }

    /// Rescan an app in the background whenever it's used and its entry is missing, stale or >10 min old.
    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] n in
            guard let self, let r = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = r.bundleIdentifier, id != Bundle.main.bundleIdentifier, let url = r.bundleURL else { return }
            self.lastApp = r
            if let e = self.store.get(id), !e.stale, e.scannedAt.timeIntervalSinceNow > -Double(Prefs.shared.rescanMinutes * 60) { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Scanner.shared.scan(AppEntry(id: id, name: r.localizedName ?? id, url: url), launchIfNeeded: false)
            }
        }
    }

    /// ~/Library/Preferences changes (System Settings edits land here) → debounce → re-sync.
    private func watchPreferences() {
        let path = NSHomeDirectory() + "/Library/Preferences"
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            self?.syncWork?.cancel()
            let work = DispatchWorkItem { self?.syncSystemShortcuts(); self?.syncCustomKeys() }
            self?.syncWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        prefsSource = src
    }

    private func syncSystemShortcuts() {
        if store.get(SystemShortcuts.bundleID)?.customSig != SystemShortcuts.signature() {
            store.put(SystemShortcuts.load())
        }
    }

    /// App Shortcuts edited in System Settings → mark app stale, rescan now if running.
    private func syncCustomKeys() {
        for e in store.all where e.bundleID != SystemShortcuts.bundleID {
            guard CustomKeys.signature(for: e.bundleID) != e.customSig else { continue }
            if let r = NSRunningApplication.runningApplications(withBundleIdentifier: e.bundleID).first, let url = r.bundleURL {
                Scanner.shared.scan(AppEntry(id: e.bundleID, name: r.localizedName ?? e.bundleID, url: url), launchIfNeeded: false)
            } else {
                store.markStale(e.bundleID)
            }
        }
    }
}

/// Launch at login through SMAppService. If macOS wants the user's OK (Login Items in System Settings), it's opened
/// for them rather than the switch silently flipping back.
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns an error message when it couldn't be changed.
    @discardableResult static func set(_ on: Bool) -> String? {
        let svc = SMAppService.mainApp
        do {
            if on { try svc.register() } else { try svc.unregister() }
        } catch {
            if on, svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems(); return nil }
            return error.localizedDescription
        }
        if on, svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        return nil
    }
}
