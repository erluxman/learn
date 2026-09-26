import AppKit
import Carbon

/// Learn's own settings (UserDefaults). Main-thread only.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    static let changed = Notification.Name("LearnPrefsChanged")
    static let defaultPanelKey = Binding(path: [LearnActions.group, "Open Learn"], keyCode: kVK_Space, mods: [.opt])
    // Keys inside Learn's panel
    static let defaultRecordKey = Binding(path: ["Panel", "Record shortcut"], keyCode: kVK_Return, mods: [.cmd])
    static let defaultContextKey = Binding(path: ["Panel", "Right-click"], keyCode: kVK_Tab, mods: [])

    private let d = UserDefaults.standard

    @Published var panelKey: Binding { didSet { save(panelKey, "panelKey"); notify() } }
    @Published var recordKey: Binding { didSet { save(recordKey, "recordKey") } }
    @Published var contextKey: Binding { didSet { save(contextKey, "contextKey") } }
    @Published var rescanMinutes: Int { didSet { d.set(rescanMinutes, forKey: "rescanMinutes") } }
    @Published var showScreenItems: Bool { didSet { d.set(showScreenItems, forKey: "showScreenItems") } }
    @Published var showMenuCommands: Bool { didSet { d.set(showMenuCommands, forKey: "showMenuCommands") } }
    @Published var debugLog: Bool { didSet { d.set(debugLog, forKey: "debugLog") } }
    @Published var showKeyHUD: Bool { didSet { d.set(showKeyHUD, forKey: "showKeyHUD") } }
    @Published var hudStyle: HUDStyle { didSet { d.set(try? JSONEncoder().encode(hudStyle), forKey: "hudStyle") } }
    @Published var appearance: Appearance { didSet { d.set(try? JSONEncoder().encode(appearance), forKey: "appearance") } }
    @Published var searchFiles: Bool { didSet { d.set(searchFiles, forKey: "searchFiles") } }
    @Published var quickAnswers: Bool { didSet { d.set(quickAnswers, forKey: "quickAnswers") } }
    @Published var chordRightClick: Bool { didSet { d.set(chordRightClick, forKey: "chordRightClick") } }
    /// Set by AppDelegate: false when macOS refused the panel hotkey (another app owns it).
    @Published var panelKeyRegistered = true

    private init() {
        d.register(defaults: ["rescanMinutes": 10, "showScreenItems": true, "showMenuCommands": true, "debugLog": false, "showKeyHUD": true, "searchFiles": true, "quickAnswers": true, "chordRightClick": true])
        panelKey = Self.load("panelKey", Self.defaultPanelKey)
        recordKey = Self.load("recordKey", Self.defaultRecordKey)
        contextKey = Self.load("contextKey", Self.defaultContextKey)
        rescanMinutes = d.integer(forKey: "rescanMinutes")
        showScreenItems = d.bool(forKey: "showScreenItems")
        showMenuCommands = d.bool(forKey: "showMenuCommands")
        debugLog = d.bool(forKey: "debugLog")
        showKeyHUD = d.bool(forKey: "showKeyHUD")
        hudStyle = d.data(forKey: "hudStyle").flatMap { try? JSONDecoder().decode(HUDStyle.self, from: $0) } ?? HUDStyle()
        appearance = d.data(forKey: "appearance").flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) } ?? Appearance()
        searchFiles = d.bool(forKey: "searchFiles")
        quickAnswers = d.bool(forKey: "quickAnswers")
        chordRightClick = d.bool(forKey: "chordRightClick")
    }

    private static func load(_ k: String, _ def: Binding) -> Binding {
        UserDefaults.standard.data(forKey: k).flatMap { try? JSONDecoder().decode(Binding.self, from: $0) } ?? def
    }
    private func save(_ b: Binding, _ k: String) { d.set(try? JSONEncoder().encode(b), forKey: k) }
    private func notify() { NotificationCenter.default.post(name: Self.changed, object: nil) }

    static func carbonMods(_ m: Mods) -> Int {
        (m.contains(.cmd) ? cmdKey : 0) | (m.contains(.shift) ? shiftKey : 0)
            | (m.contains(.opt) ? optionKey : 0) | (m.contains(.ctrl) ? controlKey : 0)
    }
}

/// While any recorder is capturing keys, Learn's global hotkey and key tap must stay out of the way.
enum Recorder {
    static let changed = Notification.Name("LearnRecorderChanged")
    static var active = false { didSet { NotificationCenter.default.post(name: changed, object: nil) } }

    /// Needs ⌘/⌃/⌥, or an F-key. `panelKey`: keys used inside Learn's panel may also be plain ⇥.
    static func acceptable(code: Int, mods: Mods, panelKey: Bool = false) -> Bool {
        guard let name = Keys.names[code] else { return false }
        let fkey = name.hasPrefix("F") && name.count > 1
        return fkey || !mods.intersection([.cmd, .ctrl, .opt]).isEmpty || (panelKey && name == "⇥")
    }

    static func mods(_ f: NSEvent.ModifierFlags) -> Mods {
        var m: Mods = []
        if f.contains(.command) { m.insert(.cmd) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.option) { m.insert(.opt) }
        if f.contains(.control) { m.insert(.ctrl) }
        return m
    }
}
