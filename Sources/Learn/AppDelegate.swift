import AppKit
import Carbon
import ServiceManagement
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    private var bag = Set<AnyCancellable>()
    private var lastApp: NSRunningApplication?   // last app the user focused (not Learn)

    func applicationDidFinishLaunching(_ note: Notification) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        model.onClose = { [weak self] in
            self?.panel.dismiss(restoreFocus: $0)
            self?.model.clearScreen()
        }
        installLearnActions()
        panel.onDismiss = { [weak self] in self?.hints.highlight(nil) }
        hotKey = HotKey(keyCode: kVK_Space, carbonMods: optionKey) { [weak self] in self?.toggle() }
        installKeyMonitor()
        installStatusItem()
        watchPreferences()
        observeAppActivation()

        syncSystemShortcuts()
        whenTrusted { [weak self] in
            self?.model.trusted = true
            NSLog("Learn key tap: %@", self?.keyTap.start() == true ? "started" : "FAILED")
            self?.scanRunningApps(onlyMissing: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.syncCustomKeys() }
        show()
    }

    // Launched again from Spotlight / Finder while running → show panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        show()
        return false
    }

    // MARK: Panel

    private func toggle() { panel.isVisible ? panel.dismiss() : show() }

    private func show() {
        let me = Bundle.main.bundleIdentifier
        let candidates = [NSWorkspace.shared.frontmostApplication, NSWorkspace.shared.menuBarOwningApplication, lastApp]
        let target = candidates.compactMap { $0 }.first { $0.bundleIdentifier != me && !$0.isTerminated }
        model.willShow(frontmost: target)
        panel.present()
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            if self.model.recording != nil { self.handleRecorderKey(e); return nil }
            let cmd = e.modifierFlags.contains(.command)
            switch Int(e.keyCode) {
            case kVK_Return where cmd && self.model.currentApp != nil: self.model.startRecording()
            case kVK_DownArrow: self.model.move(1)
            case kVK_UpArrow: self.model.move(-1)
            case kVK_Return, kVK_ANSI_KeypadEnter: self.model.activate()
            case kVK_Tab where self.model.currentApp == nil: self.model.activate()
            case kVK_Escape: self.model.escape()
            case kVK_Delete where self.model.query.isEmpty && self.model.currentApp != nil: self.model.back()
            case kVK_ANSI_R where cmd: self.model.refresh()
            case kVK_ANSI_W where cmd: self.panel.dismiss()
            default: return e
            }
            return nil
        }
    }

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
        keyTap.suspended = { [weak self] in self?.model.recording != nil }
        hints.onKeysCaptured = { [weak self] on in
            guard let self else { return }
            self.keyTap.interceptor = on ? { [weak self] code, mods in self?.hints.handle(keyCode: code, mods: mods) ?? false } : nil
        }
        LearnActions.run = { [weak self] path in
            guard let self, path == LearnActions.labels else { return }
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
        menu.addItem(withTitle: "Open Learn  (⌥Space)", action: #selector(menuShow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Rescan Running Apps", action: #selector(menuScanRunning), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Scan All Installed Apps (launches each hidden)…", action: #selector(menuScanAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Rescan System Shortcuts", action: #selector(menuSyncSystem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Database in Finder", action: #selector(menuOpenDB), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Quit Learn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func menuShow() { show() }
    @objc private func menuScanRunning() { scanRunningApps(onlyMissing: false) }
    @objc private func menuSyncSystem() { store.put(SystemShortcuts.load()) }
    @objc private func menuOpenDB() { NSWorkspace.shared.activateFileViewerSelecting([store.dir]) }

    @objc private func menuScanAll() {
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
        let svc = SMAppService.mainApp
        try? svc.status == .enabled ? svc.unregister() : svc.register()
        sender.state = svc.status == .enabled ? .on : .off
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
            if let e = self.store.get(id), !e.stale, e.scannedAt.timeIntervalSinceNow > -600 { return }
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
