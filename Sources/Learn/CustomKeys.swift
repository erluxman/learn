import Foundation

/// Read-only view of App Shortcuts made in System Settings (NSUserKeyEquivalents), used to notice edits there.
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
