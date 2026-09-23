import AppKit

/// User-recorded shortcuts, owned by Learn (not written into the apps).
/// Learn's key tap catches the combo in the frontmost app and presses the menu item itself.
struct Binding: Codable, Hashable {
    let path: [String]
    let keyCode: Int
    let mods: Mods

    var shortcut: Shortcut { Shortcut(path: path, key: Keys.names[keyCode] ?? "?", keyCode: keyCode, mods: mods) }
}

/// Main-thread only. Stored in ~/Library/Application Support/Learn/bindings.json.
final class Bindings {
    static let shared = Bindings()

    private let file = ShortcutStore.shared.dir.deletingLastPathComponent().appendingPathComponent("bindings.json")
    private var byApp: [String: [Binding]] = [:]

    private init() {
        if let d = try? Data(contentsOf: file), let b = try? JSONDecoder().decode([String: [Binding]].self, from: d) { byApp = b }
    }

    func all(_ app: String) -> [Binding] { byApp[app] ?? [] }
    func get(_ app: String, path: [String]) -> Binding? { byApp[app]?.first { $0.path == path } }

    func match(_ app: String, keyCode: Int, mods: Mods) -> Binding? {
        byApp[app]?.first { $0.keyCode == keyCode && $0.mods == mods }
    }

    /// One binding per menu item and per combo within an app.
    func set(_ app: String, _ b: Binding) {
        var list = all(app).filter { $0.path != b.path && !($0.keyCode == b.keyCode && $0.mods == b.mods) }
        list.append(b)
        byApp[app] = list
        save(app)
    }

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
    private let queue = DispatchQueue(label: "learn.press", qos: .userInteractive)

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, ctx in
            Unmanaged<KeyTap>.fromOpaque(ctx!).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(e)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == .keyDown, let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return pass }
        let f = e.flags
        var mods: Mods = []
        if f.contains(.maskCommand) { mods.insert(.cmd) }
        if f.contains(.maskShift) { mods.insert(.shift) }
        if f.contains(.maskAlternate) { mods.insert(.opt) }
        if f.contains(.maskControl) { mods.insert(.ctrl) }
        let code = Int(e.getIntegerValueField(.keyboardEventKeycode))
        guard let b = Bindings.shared.match(id, keyCode: code, mods: mods) else { return pass }
        if e.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            let pid = app.processIdentifier
            queue.async { if !MenuScanner.press(path: b.path, pid: pid) { DispatchQueue.main.async { NSSound.beep() } } }
        }
        return nil
    }
}
