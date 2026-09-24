import SwiftUI
import ServiceManagement

/// Learn ▸ Settings: Permissions · General · Shortcuts.
final class SettingsWindow {
    static let shared = SettingsWindow()
    static let title = "Learn Settings"
    var isFront: Bool { window?.isKeyWindow == true && NSApp.isActive }
    enum Tab: Hashable { case permissions, general, shortcuts }

    /// Hooks into AppDelegate for actions that live there.
    var rescanRunning: () -> Void = {}
    var scanAll: () -> Void = {}

    private var window: NSWindow?
    private let selection = TabSelection()

    func show(_ tab: Tab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = Self.title
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(selection: selection))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class TabSelection: ObservableObject { @Published var tab: SettingsWindow.Tab = .permissions }

struct SettingsView: View {
    @ObservedObject var selection: TabSelection
    var body: some View {
        TabView(selection: $selection.tab) {
            PermissionsTab().tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(SettingsWindow.Tab.permissions)
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsWindow.Tab.general)
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(SettingsWindow.Tab.shortcuts)
        }
        .padding(16)
        .frame(width: 640, height: 540)
    }
}

// MARK: Permissions

private struct PermissionsTab: View {
    @State private var ax = AXIsProcessTrusted()
    @State private var post = CGPreflightPostEventAccess()
    @State private var listen = CGPreflightListenEventAccess()
    @State private var login = SMAppService.mainApp.status == .enabled
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var missing: Int { [ax, post, listen].filter { !$0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: missing == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 26)).foregroundStyle(missing == 0 ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(missing == 0 ? "All set" : "\(missing) permission\(missing == 1 ? "" : "s") missing").font(.title3.bold())
                    Text("Changes are picked up automatically — no restart needed.").font(.caption).foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(spacing: 0) {
                    PermissionRow(title: "Accessibility", granted: ax,
                                  detail: "Read menus and on-screen items, click, focus fields, run shortcuts.",
                                  button: "Grant…") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(opts)
                        openPane("Privacy_Accessibility")
                    }
                    Divider()
                    PermissionRow(title: "Send keystrokes & clicks", granted: post,
                                  detail: "Real clicks for web apps, right-click menus, key fallbacks.",
                                  button: "Grant…") { _ = CGRequestPostEventAccess(); openPane("Privacy_Accessibility") }
                    Divider()
                    PermissionRow(title: "Input Monitoring", granted: listen,
                                  detail: "Catch your custom shortcuts and label keys in every app.",
                                  button: "Grant…") { _ = CGRequestListenEventAccess(); openPane("Privacy_ListenEvent") }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at login").font(.body.weight(.medium))
                            Text("Start Learn automatically so \(Prefs.shared.panelKey.shortcut.display) always works.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: SwiftUI.Binding(get: { login }, set: { on in
                            let svc = SMAppService.mainApp
                            try? on ? svc.register() : svc.unregister()
                            login = svc.status == .enabled
                        })).toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 6)
            }
            Text("If a permission stays red after granting, remove Learn from that list in System Settings and add it again.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .onReceive(tick) { _ in
            ax = AXIsProcessTrusted(); post = CGPreflightPostEventAccess(); listen = CGPreflightListenEventAccess()
            login = SMAppService.mainApp.status == .enabled
        }
    }

    private func openPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

private struct PermissionRow: View {
    let title: String, granted: Bool, detail: String, button: String
    let action: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted { Text("Granted").font(.caption).foregroundStyle(.secondary) }
            else { Button(button, action: action) }
        }
        .padding(.vertical, 10)
    }
}

// MARK: General

private struct GeneralTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @State private var learnKeys = GeneralTab.currentLearnKeys()
    @State private var spotlight = SpotlightKey.current

    static func currentLearnKeys() -> [[String]: Learn.Binding] {
        Dictionary(Bindings.shared.globals.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Form {
            Section("Hotkeys") {
                LabeledContent("Open Learn") {
                    HStack {
                        KeyRecorder(display: prefs.panelKey.shortcut.display) { code, mods in
                            prefs.panelKey = Learn.Binding(path: Prefs.defaultPanelKey.path, keyCode: code, mods: mods)
                        }
                        Button("Reset") { prefs.panelKey = Prefs.defaultPanelKey }
                            .disabled(prefs.panelKey == Prefs.defaultPanelKey)
                    }
                }
                Picker("⌘Space opens", selection: SwiftUI.Binding(get: { spotlight }, set: { spotlight = $0; SpotlightKey.apply($0) })) {
                    Text("Spotlight (macOS default)").tag(SpotlightKey.Mode.keep)
                    Text("Learn — Spotlight off").tag(SpotlightKey.Mode.replace)
                    Text("Learn — Spotlight moves to ⌥Space").tag(SpotlightKey.Mode.swap)
                }
                if spotlight != .keep {
                    Text("Learn must be running for ⌘Space to work — keep Launch at login on. Switch back here any time.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !prefs.panelKeyRegistered {
                    Text("⚠︎ \(prefs.panelKey.shortcut.display) is taken by another app or macOS — pick another combo.")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(LearnActions.all, id: \.self) { path in
                    LabeledContent(path.last ?? "") {
                        HStack {
                            KeyRecorder(display: learnKeys[path]?.shortcut.display ?? "") { code, mods in
                                Bindings.shared.set(Bindings.global, Learn.Binding(path: path, keyCode: code, mods: mods))
                                learnKeys = GeneralTab.currentLearnKeys()
                            }
                            Button("Reset") {
                                Bindings.shared.remove(Bindings.global, path: path)
                                learnKeys = GeneralTab.currentLearnKeys()
                            }
                        }
                    }
                }
                Text("Any other command or menu item: select it in Learn and press \(prefs.recordKey.shortcut.display).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Inside Learn's panel") {
                LabeledContent("Record a shortcut for the selected item") {
                    HStack {
                        KeyRecorder(display: prefs.recordKey.shortcut.display, panelKey: true) { code, mods in
                            prefs.recordKey = Learn.Binding(path: Prefs.defaultRecordKey.path, keyCode: code, mods: mods)
                        }
                        Button("Reset") { prefs.recordKey = Prefs.defaultRecordKey }.disabled(prefs.recordKey == Prefs.defaultRecordKey)
                    }
                }
                LabeledContent("Right-click the selected on-screen item") {
                    HStack {
                        KeyRecorder(display: prefs.contextKey.shortcut.display, panelKey: true) { code, mods in
                            prefs.contextKey = Learn.Binding(path: Prefs.defaultContextKey.path, keyCode: code, mods: mods)
                        }
                        Button("Reset") { prefs.contextKey = Prefs.defaultContextKey }.disabled(prefs.contextKey == Prefs.defaultContextKey)
                    }
                }
                ForEach([("↩", "Run the selected item / open the selected app"), ("↑ ↓", "Move the selection"),
                         ("⎋  or  ⌫ on empty search", "Back to the app list, then close"), ("⌘R", "Re-read this app's shortcuts"),
                         ("⌘,", "Open these settings"), ("⌘W", "Close Learn")], id: \.0) { key, what in
                    LabeledContent(what) { Text(key).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(.secondary) }
                }
            }
            Section("On screen") {
                Toggle("Show shortcuts as you press them (bottom centre)", isOn: $prefs.showKeyHUD)
                Toggle("Both ⌃ keys together (left + right) = right-click at the pointer", isOn: $prefs.chordRightClick)
                Text("Pointer mode (\(learnKeys[LearnActions.pointer]?.shortcut.display ?? "")): HJKL or arrows move, ⇧ slow, ⌥ scroll, Space click, D double-click, R right-click, V drag, the same hotkey again jumps to your next screen, ⎋ exit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Search") {
                Toggle("Show on-screen items (buttons, fields, links)", isOn: $prefs.showScreenItems)
                Toggle("Show menu commands without a shortcut", isOn: $prefs.showMenuCommands)
                Toggle("Search files in your home folder (Spotlight index)", isOn: $prefs.searchFiles)
                Toggle("Quick answers: calculator, unit conversions (5 km to mi), definitions", isOn: $prefs.quickAnswers)
            }
            Section("Shortcut database") {
                Stepper("Rescan an app when used, if older than \(prefs.rescanMinutes) min",
                        value: $prefs.rescanMinutes, in: 1...240)
                HStack {
                    Button("Rescan Running Apps") { SettingsWindow.shared.rescanRunning() }
                    Button("Scan All Installed Apps…") { SettingsWindow.shared.scanAll() }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ShortcutStore.shared.dir]) }
                }
            }
            Section("Troubleshooting") {
                Toggle("Write debug log", isOn: $prefs.debugLog)
                if prefs.debugLog {
                    Button("Show Log") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("debug.log")])
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Shortcuts

private struct ShortcutsTab: View {
    @State private var groups: [(scope: String, name: String, items: [Learn.Binding])] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcuts you recorded in Learn").font(.title3.bold())
            Text("Created with \(Prefs.shared.recordKey.shortcut.display) on a selected item. Learn catches the keys and runs the item itself, so they work instantly without touching the app's own settings. The apps' built-in shortcuts aren't listed here — search them in Learn.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if groups.isEmpty {
                Spacer()
                Text("No custom shortcuts yet.\nOpen Learn, select any item, press ⌘↩.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(groups, id: \.scope) { g in
                        Section(g.name) {
                            ForEach(g.items, id: \.self) { b in
                                HStack {
                                    Text(b.path.first == ElementScanner.marker ? "On screen ▸ " + b.path.dropFirst().joined(separator: " ▸ ")
                                                                              : b.path.joined(separator: " ▸ "))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    if let orig = appShortcut(g.scope, b.path) {
                                        Text("replaces app's \(orig)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(b.shortcut.display).font(.system(.body, design: .rounded).weight(.medium))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                                    Button { Bindings.shared.remove(g.scope, path: b.path); reload() } label: {
                                        Image(systemName: "trash")
                                    }.buttonStyle(.borderless).help("Remove")
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.changed)) { _ in reload() }
    }

    /// The app's own key for this item, if it has one (from Learn's menu database).
    private func appShortcut(_ scope: String, _ path: [String]) -> String? {
        if scope == Bindings.global { return LearnActions.defaults.first { $0.path == path }.map { "default \($0.shortcut.display)" } }
        return ShortcutStore.shared.get(scope)?.shortcuts.first { $0.path == path && $0.hasKey }?.display
    }

    private func reload() {
        groups = Bindings.shared.scopes.compactMap { scope in
            let items = Bindings.shared.all(scope)
            guard !items.isEmpty else { return nil }
            let name = scope == Bindings.global ? "Everywhere (Learn commands)"
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: scope)
                    .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? scope
            return (scope, name, items)
        }.sorted { $0.name < $1.name }
    }
}

// MARK: Key recorder

/// Click, press a combo (needs ⌘/⌃/⌥ or an F-key); ⎋ cancels.
struct KeyRecorder: View {
    let display: String
    var panelKey = false   // keys used inside Learn's panel may be plain ⇥
    let onRecord: (Int, Mods) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…  (⎋ cancel)" : (display.isEmpty ? "Record Shortcut" : display)) {
            recording ? stop() : start()
        }
        .font(.system(.body, design: .rounded).weight(.medium))
        .frame(minWidth: 140)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        Recorder.active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = Recorder.mods(e.modifierFlags)
            if e.keyCode == 53, mods.isEmpty { stop(); return nil }
            if Recorder.acceptable(code: Int(e.keyCode), mods: mods, panelKey: panelKey) {
                onRecord(Int(e.keyCode), mods); stop()
                KeyHUD.shared.flash(Shortcut(path: [], key: Keys.names[Int(e.keyCode)] ?? "", keyCode: Int(e.keyCode), mods: mods).display, caption: "Recorded")
            }
            else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; Recorder.active = false }
    }
}
