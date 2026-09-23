import Foundation

/// User-defined app shortcuts (System Settings ▸ Keyboard ▸ App Shortcuts), stored per app in
/// NSUserKeyEquivalents as { "\u{1B}File\u{1B}New\u{1B}New Project…": "^~@n" }.
/// Goes through /usr/bin/defaults because it resolves sandboxed apps' container prefs; CFPreferences doesn't.
enum CustomKeys {
    private static let key = "NSUserKeyEquivalents"

    static func read(_ bundleID: String) -> [String: String] {
        let containerPrefs = NSHomeDirectory() + "/Library/Containers/\(bundleID)/Data/Library/Preferences"
        guard FileManager.default.fileExists(atPath: containerPrefs) else {
            CFPreferencesAppSynchronize(bundleID as CFString)
            return CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) as? [String: String] ?? [:]
        }
        let (ok, out) = defaults(["export", bundleID, "-"])
        guard ok, let plist = try? PropertyListSerialization.propertyList(from: out, format: nil) as? [String: Any] else { return [:] }
        return plist[key] as? [String: String] ?? [:]
    }

    static func signature(for bundleID: String) -> String {
        func flat(_ d: [String: String]) -> String { d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let global = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? [String: String] ?? [:]
        return flat(read(bundleID)) + "|" + flat(global)
    }

    static func menuKey(_ path: [String]) -> String { "\u{1B}" + path.joined(separator: "\u{1B}") }

    /// Sets (value != nil) or removes the custom shortcut for a menu item. Blocking; call off main.
    @discardableResult
    static func set(_ bundleID: String, path: [String], value: String?) -> Bool {
        let item = menuKey(path)
        let ok: Bool
        if let value {
            ok = defaults(["write", bundleID, key, "-dict-add", item, value]).0
        } else {
            var dict = read(bundleID)
            dict[item] = nil
            _ = defaults(["delete", bundleID, key])
            ok = dict.isEmpty || defaults(["write", bundleID, key, "-dict"] + dict.flatMap { [$0.key, $0.value] }).0
        }
        registerInSystemSettings(bundleID)
        return ok
    }

    /// Lists the app under System Settings ▸ App Shortcuts. Best effort: the domain may be protected.
    private static func registerInSystemSettings(_ bundleID: String) {
        let (_, out) = defaults(["read", "com.apple.universalaccess", "com.apple.custommenu.apps"])
        let listed = String(decoding: out, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\",()")) }
        if listed.contains(bundleID) { return }
        _ = defaults(["write", "com.apple.universalaccess", "com.apple.custommenu.apps", "-array-add", bundleID])
    }

    /// NSUserKeyEquivalents encoding: ^ ctrl, ~ option, $ shift, @ command, then the key character.
    static func encode(keyCode: Int, mods: Mods) -> String? {
        let special: [Int: String] = [
            123: "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}", 51: "\u{08}", 117: "\u{F728}",
            36: "\r", 76: "\u{03}", 48: "\t", 49: " ", 53: "\u{1B}", 115: "\u{F729}", 119: "\u{F72B}",
            116: "\u{F72C}", 121: "\u{F72D}",
        ]
        let fkeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        let char: String
        if let s = special[keyCode] { char = s }
        else if let i = fkeys.firstIndex(of: keyCode) { char = String(UnicodeScalar(0xF704 + i)!) }
        else if let n = Keys.names[keyCode], n.count == 1 { char = n.lowercased() }
        else { return nil }
        return (mods.contains(.ctrl) ? "^" : "") + (mods.contains(.opt) ? "~" : "")
            + (mods.contains(.shift) ? "$" : "") + (mods.contains(.cmd) ? "@" : "") + char
    }

    private static func defaults(_ args: [String]) -> (Bool, Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (false, Data()) }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0, out)
    }
}
