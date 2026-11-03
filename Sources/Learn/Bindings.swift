import AppKit

/// User-recorded shortcuts, owned by Learn (not written into the apps).
/// Learn's key tap catches the combo in the frontmost app and presses the menu item itself.
struct Binding: Codable, Hashable {
    let path: [String]
    let keyCode: Int
    let mods: Mods

    var shortcut: Shortcut { Shortcut(path: path, key: Keys.names[keyCode] ?? "?", keyCode: keyCode, mods: mods) }
    func matches(_ code: Int, _ m: Mods) -> Bool { keyCode == code && mods == m }
}

/// Learn's own commands. Listed in every app's shortcut list, bound globally (scope "*").
enum LearnActions {
    static let group = "Learn"
    static let labels = [group, "Label clickable items on screen"]
    static let settings = [group, "Open Learn Settings"]
    static let configure = [group, "Configure Learn (AI Config)"]
    static let rightClick = [group, "Right-click the focused item"]
    static let pointer = [group, "Control the pointer with the keyboard"]
    static let nextScreen = [group, "Move window to next screen"]
    static let mouse = [group, "Turn mouse & trackpad on or off"]
    static let all: [[String]] = [labels, rightClick, pointer, nextScreen, mouse, configure, settings]
    /// Built-in combos until the user rebinds them (⌘↩ on the item; ⌫ there restores these).
    static let defaults: [Binding] = [
        Binding(path: labels, keyCode: 49, mods: [.cmd, .shift]),   // ⌘⇧Space
        Binding(path: rightClick, keyCode: 109, mods: [.shift]),   // ⇧F10, the Windows context-menu key
        Binding(path: pointer, keyCode: 49, mods: [.opt, .shift]),   // ⌥⇧Space
        Binding(path: nextScreen, keyCode: 49, mods: [.cmd, .opt, .shift]),   // ⌘⌥⇧Space
        Binding(path: mouse, keyCode: 46, mods: [.cmd, .opt, .ctrl]),   // ⌃⌥⌘M
    ]
    static var run: ([String]) -> Void = { _ in }
}

/// Main-thread only. Stored in ~/Library/Application Support/Learn/bindings.json.
/// Keys are bundle ids; "*" holds global bindings (Learn's own commands).
final class Bindings {
    static let global = "*"
    static let shared = Bindings()

    private let file = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("bindings.json")
    private var byApp: [String: [Binding]] = [:]

    private init() {
        if let d = try? Data(contentsOf: file), let b = try? JSONDecoder().decode([String: [Binding]].self, from: d) { byApp = b }
    }

    func all(_ app: String) -> [Binding] { byApp[app] ?? [] }
    var scopes: [String] { Array(byApp.keys) }
    func get(_ app: String, path: [String]) -> Binding? { byApp[app]?.first { $0.path == path } }

    func match(_ app: String, keyCode: Int, mods: Mods) -> Binding? {
        func hit(_ list: [Binding]) -> Binding? { list.first { $0.keyCode == keyCode && $0.mods == mods } }
        return hit(all(app)) ?? hit(globals)
    }

    /// Global bindings, with Learn's defaults filling in for commands the user hasn't rebound.
    var globals: [Binding] {
        let user = all(Self.global)
        return user + LearnActions.defaults.filter { d in !user.contains { $0.path == d.path } }
    }

    /// One binding per menu item and per combo within an app.
    func set(_ app: String, _ b: Binding) {
        var list = all(app).filter { $0.path != b.path && !($0.keyCode == b.keyCode && $0.mods == b.mods) }
        list.append(b)
        byApp[app] = list
        madeAt[Self.key(app, b.path)] = Date().timeIntervalSince1970
        UserDefaults.standard.set(madeAt, forKey: "bindingTimes")
        save(app)
    }

    /// Puts an app's list back as it was (AI Config's undo).
    func restore(_ app: String, _ list: [Binding]) {
        byApp[app] = list.isEmpty ? nil : list
        save(app)
    }

    /// When each binding was made (seconds since 1970), so "remove the shortcut I just made" finds the newest.
    /// Bindings from before this was kept have no time.
    private var madeAt = UserDefaults.standard.dictionary(forKey: "bindingTimes") as? [String: Double] ?? [:]
    func made(_ app: String, _ path: [String]) -> Date? { madeAt[Self.key(app, path)].map(Date.init(timeIntervalSince1970:)) }
    private static func key(_ app: String, _ path: [String]) -> String { ([app] + path).joined(separator: "\u{1F}") }

    func remove(_ app: String, path: [String]) {
        byApp[app] = all(app).filter { $0.path != path }
        save(app)
    }

    private func save(_ app: String) {
        if let d = try? JSONEncoder().encode(byApp) { try? d.write(to: file, options: .atomic) }
        NotificationCenter.default.post(name: ShortcutStore.changed, object: app)
    }
}

/// Global keyDown tap: bound combo in the frontmost app → swallow it and press the menu item.
final class KeyTap {
    private var tap: CFMachPort?
    /// When set (label / pointer mode), every keyDown (code, mods, isRepeat) goes here first; true = swallowed.
    var interceptor: ((Int, Mods, Bool) -> Bool)?
    /// Key releases while intercepting: pointer mode tracks held keys.
    var releaser: ((Int) -> Void)?
    /// Every fresh key press, even while intercepted or recording: feeds the on-screen shortcut display.
    var observer: (Int, Mods) -> Void = { _, _ in }
    /// Left ⌃ + right ⌃ held together, then released with no other key in between.
    var onChord: () -> Void = {}
    private var chordArmed = false
    private var ctrlDown: Set<Int> = []   // 59 left ⌃, 62 right ⌃
    /// While the panel is open without the keyboard (over Ghostty's quick terminal): every key press / release goes here
    /// first; true = it was for the panel (swallowed).
    var panelKeys: ((CGEvent, CGEventType) -> Bool)?
    /// ⌘↑ / ⌘↓ (code, mods, press / release) for the wheel scroller, ahead of every mode; true = swallowed.
    var wheel: ((Int, Mods, Bool) -> Bool)?
    /// True while Learn's recorder is open: keys must reach the recorder untouched.
    var suspended: () -> Bool = { false }
    private let queue = DispatchQueue(label: "learn.press", qos: .userInteractive)

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue | 1 << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, ctx in
            Unmanaged<KeyTap>.fromOpaque(ctx!).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// `eventSourceUserData` on keys Learn posts itself (adjust mode's arrow keys): never handled here.
    static let ownKey: Int64 = 0x4C45_4152

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if e.getIntegerValueField(.eventSourceUserData) == Self.ownKey { return pass }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if type == .flagsChanged {
            // Track each ⌃ by key code (left/right device bits aren't reported by every keyboard).
            let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
            if !e.flags.contains(.maskControl) { ctrlDown = [] }
            else if code == 59 || code == 62 { if ctrlDown.remove(code) == nil { ctrlDown.insert(code) } }
            if ctrlDown.count == 2 { chordArmed = e.flags.isDisjoint(with: [.maskShift, .maskAlternate, .maskCommand]) }
            else if chordArmed { chordArmed = false; DispatchQueue.main.async { self.onChord() } }
            return pass
        }
        if type == .keyDown || type == .keyUp, let panelKeys, panelKeys(e, type) { return nil }
        if type == .keyUp {
            if let wheel, wheel(Int(e.getIntegerValueField(.keyboardEventKeycode)), [], false) { return nil }
            releaser?(Int(e.getIntegerValueField(.keyboardEventKeycode)))
            return pass
        }
        guard type == .keyDown else { return pass }
        chordArmed = false   // ⌃ + a key is a shortcut, not a right-click
        let f = e.flags
        var mods: Mods = []
        if f.contains(.maskCommand) { mods.insert(.cmd) }
        if f.contains(.maskShift) { mods.insert(.shift) }
        if f.contains(.maskAlternate) { mods.insert(.opt) }
        if f.contains(.maskControl) { mods.insert(.ctrl) }
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = e.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat { observer(code, mods) }
        guard !suspended() else { return pass }
        if let wheel, wheel(code, mods, true) { return nil }
        if let interceptor { return interceptor(code, mods, isRepeat) ? nil : pass }
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return pass }
        let mine = id == Bundle.main.bundleIdentifier   // Learn's panel: only global commands apply
        guard let b = Bindings.shared.match(mine ? "" : id, keyCode: code, mods: mods) else { return pass }
        if !isRepeat {
            DispatchQueue.main.async { Sounds.play(.shortcut) }
            let pid = app.processIdentifier
            switch b.path.first {
            case LearnActions.group: DispatchQueue.main.async { LearnActions.run(b.path) }
            case OpenTarget.group where b.path.count == 2: DispatchQueue.main.async { OpenTarget.open(b.path[1]) }
            case ElementScanner.marker:
                queue.async { if !ElementScanner.pressMatching(path: b.path, pid: pid) { DispatchQueue.main.async { NSSound.beep() } } }
            default:
                queue.async { if !MenuScanner.press(path: b.path, pid: pid) { DispatchQueue.main.async { NSSound.beep() } } }
            }
        }
        return nil
    }
}
