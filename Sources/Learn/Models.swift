import AppKit

struct AppEntry: Identifiable, Hashable {
    let id: String      // bundle id
    let name: String
    let url: URL

    var isSystem: Bool { id == SystemShortcuts.bundleID }
    var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).first
    }
}

struct Mods: OptionSet, Codable, Hashable {
    let rawValue: Int
    static let cmd = Mods(rawValue: 1)
    static let shift = Mods(rawValue: 2)
    static let opt = Mods(rawValue: 4)
    static let ctrl = Mods(rawValue: 8)
    static let fn = Mods(rawValue: 16)

    /// AX menu modifier mask: 1 shift, 2 option, 4 control, 8 = NO command, 16 fn.
    init(ax m: Int) {
        var r: Mods = []
        if m & 8 == 0 { r.insert(.cmd) }
        if m & 1 != 0 { r.insert(.shift) }
        if m & 2 != 0 { r.insert(.opt) }
        if m & 4 != 0 { r.insert(.ctrl) }
        if m & 16 != 0 { r.insert(.fn) }
        self = r
    }

    /// NSEvent.ModifierFlags raw values (as stored in com.apple.symbolichotkeys).
    init(nsFlags f: Int) {
        var r: Mods = []
        if f & 0x100000 != 0 { r.insert(.cmd) }
        if f & 0x20000 != 0 { r.insert(.shift) }
        if f & 0x80000 != 0 { r.insert(.opt) }
        if f & 0x40000 != 0 { r.insert(.ctrl) }
        if f & 0x800000 != 0 { r.insert(.fn) }
        self = r
    }

    init(rawValue: Int) { self.rawValue = rawValue }

    var glyphs: String {
        (contains(.ctrl) ? "⌃" : "") + (contains(.opt) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.cmd) ? "⌘" : "")
    }

    var words: String {
        [(Mods.ctrl, "ctrl control"), (.opt, "opt option alt"), (.shift, "shift"), (.cmd, "cmd command"), (.fn, "fn")]
            .filter { contains($0.0) }.map(\.1).joined(separator: " ")
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.cmd) { f.insert(.maskCommand) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.opt) { f.insert(.maskAlternate) }
        if contains(.ctrl) { f.insert(.maskControl) }
        if contains(.fn) { f.insert(.maskSecondaryFn) }
        return f
    }
}

struct Shortcut: Codable, Hashable, Identifiable {
    let path: [String]      // ["File", "New Folder"]
    let key: String         // display key, e.g. "N", "←", "F11"
    let keyCode: Int?       // virtual key code if known
    let mods: Mods

    var id: String { path.joined(separator: "\u{1F}") + "|" + display }
    var title: String { path.last ?? "" }
    var location: String { path.dropLast().joined(separator: " ▸ ") }
    var hasKey: Bool { !key.isEmpty }
    var display: String {
        guard hasKey else { return "" }
        // fn is implicit on arrows/F-keys; only show it for character keys.
        let fn = mods.contains(.fn) && key.count == 1 && !Keys.special.contains(key) ? "fn " : ""
        return fn + mods.glyphs + key
    }
    var searchText: String {
        (path + [display, key, mods.words]).joined(separator: " ").lowercased()
    }
}

struct AppShortcuts: Codable {
    let bundleID: String
    var scannedAt: Date
    var shortcuts: [Shortcut]
    var customSig: String = ""   // NSUserKeyEquivalents fingerprint at scan time
    var stale = false
    var version: Int? = AppShortcuts.currentVersion   // bump → old DB entries get rescanned

    static let currentVersion = 2   // 2: includes menu commands without shortcuts
}

enum Keys {
    static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]
    static let special: Set<String> = ["↩", "⇥", "⌫", "⎋", "⌤", "⌦", "←", "→", "↓", "↑", "↖", "↘", "⇞", "⇟"]

    /// Carbon menu glyph codes → (display, key code).
    static let glyphs: [Int: (String, Int)] = {
        var g: [Int: (String, Int)] = [
            0x02: ("⇥", 48), 0x04: ("⌤", 76), 0x09: ("Space", 49), 0x0A: ("⌦", 117), 0x0B: ("↩", 36),
            0x0D: ("↩", 36), 0x17: ("⌫", 51), 0x1B: ("⎋", 53), 0x64: ("←", 123), 0x65: ("→", 124),
            0x68: ("↑", 126), 0x6A: ("↓", 125), 0x66: ("↖", 115), 0x69: ("↘", 119), 0x62: ("⇞", 116),
            0x6B: ("⇟", 121), 0x87: ("F13", 105), 0x88: ("F14", 107), 0x89: ("F15", 113),
        ]
        let fkeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fkeys.enumerated() { g[0x6F + i] = ("F\(i + 1)", code) }
        return g
    }()

    /// Shifted symbols as reported by menus ("?" for ⌘?), mapped to their base key.
    static let shifted: [Character: Int] = [
        "+": 24, "?": 44, "{": 33, "}": 30, "<": 43, ">": 47, "_": 27, ":": 41, "\"": 39, "|": 42,
        "~": 50, "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26, "*": 28, "(": 25, ")": 29,
    ]
    private static let byName: [String: Int] = Dictionary(names.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

    /// Key code + whether shift must be added to type `char`.
    static func code(for char: String) -> (Int, Bool)? {
        if let c = byName[char] ?? byName[char.uppercased()] { return (c, false) }
        if char.count == 1, let c = shifted[char.first!] { return (c, true) }
        return nil
    }
}
